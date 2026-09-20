"""Atomic YAML/JSON writes with security defenses for the flow plugin.

Shared by:
  - journal-record.sh           (manifest append)
  - flow-record-activity.sh     (FlowActivity standalone YAML writes)
  - flow-record-evidence.sh     (FlowEvidence sidecar + raw output writes)
  - flow-goal-record.sh         (FlowGoal contract + lifecycle writes)
  - flow-record-verdict.sh      (FlowRun last-verdict.json writes)

Surface:
  - record_artifact()   — journal manifest append (frontmatter + body)
  - append_body()       — journal BODY append, under the same flock
  - replace_section()   — journal BODY section replace-or-append, under the same flock
  - write_yaml_file()   — standalone YAML write (no frontmatter; replace)
  - write_json_file()   — standalone JSON write (sort_keys=True; replace)
  - append_jsonl()      — JSONL event-ledger append (under flock)
  - acquire_lock()      — primitive used by all of the above

Callers must set PYTHONSAFEPATH=1 in their environment before invoking
Python (Python 3.11+ honors it; this module also runs a defensive
sys.path filter as a fallback for older Pythons or hostile sys.path
mutations after import).

Security defenses (preserved verbatim from journal-record.sh):
  - os.open(O_NOFOLLOW) on lockfile, journal, target, and events files —
    rejects pre-staged symlinks atomically (ELOOP/EMLINK). Without this,
    a hostile fork's `.decisions/issue-N.md → ~/.ssh/id_rsa` symlink
    would read sensitive content into the journal body on the next write.
  - fcntl.flock(LOCK_EX) on the lockfile FD — serializes concurrent
    same-target writers so the read-modify-write of artifacts[] cannot
    lose entries.
  - tempfile.mkstemp + os.rename in the same directory — POSIX-atomic
    publish. Partial writes never replace the journal.
  - os.fsync on the file FD before rename, then on the directory FD
    after rename — durable across power loss.

Exit-code contract for callers:
  - JournalAtomicError.exit_code == 1: user input was invalid (bad metadata,
    bad arg) — surface message and exit 1.
  - JournalAtomicError.exit_code == 2: infrastructure error or refusal
    (symlink, malformed frontmatter, write failure) — surface message,
    append the 'refusing to overwrite — fix manually' line if `refuse=True`
    on the exception, and exit 2.
"""

import errno
import fcntl
import json
import os
import sys
import tempfile

try:
    import yaml  # PyYAML
except ImportError:  # pragma: no cover - environment-dependent
    raise SystemExit(
        "flow: PyYAML is required by flow journal and run-state writes but is not installed.\n"
        "  python3 -m pip install --user --break-system-packages pyyaml\n"
        "Callers normally preflight this; reaching here means the module was\n"
        "imported directly. No manifest declares the dependency (see issue #175)."
    )


class JournalAtomicError(RuntimeError):
    """Raised on any atomicity / symlink / parse error.

    Attributes:
      exit_code: 1 for user-input errors, 2 for infrastructure / refusal.
      refuse: when True, the caller should append the canonical
              "refusing to overwrite — fix manually" line to stderr.
              Matches the original journal-record.sh:217-232 behavior.
    """

    def __init__(self, message, exit_code=2, refuse=False):
        super().__init__(message)
        self.exit_code = exit_code
        self.refuse = refuse


# ---------------------------------------------------------------------------
# sys.path hardening (defense-in-depth for Python <3.11 where PYTHONSAFEPATH
# is ignored). Removes "" (CWD) and "." entries so a hostile fork's
# `./yaml.py` cannot shadow the real PyYAML during `import yaml` above.
# Idempotent — safe to call multiple times.

def _harden_sys_path():
    sys.path[:] = [p for p in sys.path if p not in ("", ".")]


_harden_sys_path()


# ---------------------------------------------------------------------------
# Lockfile + atomicity primitives.

def acquire_lock(lockfile_path):
    """Open lockfile_path with O_NOFOLLOW + LOCK_EX. Returns the open fd.

    Caller MUST close the returned fd. Raises JournalAtomicError(exit_code=2)
    on symlink or open failure.
    """
    try:
        fd = os.open(lockfile_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.EMLINK):
            raise JournalAtomicError(
                f"refusing — lockfile {lockfile_path} is a symlink",
                exit_code=2,
            )
        raise JournalAtomicError(
            f"cannot open lockfile {lockfile_path}: {e}",
            exit_code=2,
        )
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
    except OSError as e:
        os.close(fd)
        raise JournalAtomicError(
            f"cannot acquire flock on {lockfile_path}: {e}",
            exit_code=2,
        )
    return fd


def _read_with_no_follow(path):
    """Read path with O_NOFOLLOW. Returns content string or '' if missing.

    Raises JournalAtomicError(exit_code=2) on symlink or read failure.
    """
    if not os.path.lexists(path):
        return ""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.EMLINK):
            raise JournalAtomicError(
                f"refusing — {path} is a symlink",
                exit_code=2,
            )
        raise JournalAtomicError(
            f"cannot read {path}: {e}",
            exit_code=2,
        )
    with os.fdopen(fd, "r", encoding="utf-8") as f:
        return f.read()


def _atomic_write(target_path, content):
    """Write content to target_path atomically.

    tempfile.mkstemp in the same dir → write+flush+fsync → os.rename → fsync dir.
    On any write failure the tempfile is cleaned up and the original target
    (if any) is untouched.
    """
    target_dir = os.path.dirname(target_path) or "."
    fd, tmp = tempfile.mkstemp(
        dir=target_dir,
        prefix=os.path.basename(target_path) + ".",
        suffix=".tmp",
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        # Carry the target's mode across the rename. mkstemp creates 0600, so
        # without this every rewrite silently tightens the permissions of a
        # journal someone created by hand — and git tracks only the exec bit,
        # so nothing in a diff or a report would show it. A missing target (a
        # new file) keeps mkstemp's mode, which is the safe default.
        try:
            os.chmod(tmp, os.stat(target_path).st_mode & 0o7777)
        except OSError:
            pass
        os.rename(tmp, target_path)
        # Durably persist the rename. Best-effort: some filesystems disallow
        # fsync on a directory fd and raise EINVAL — that's benign here.
        try:
            dir_fd = os.open(target_dir, os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            pass
    except JournalAtomicError:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass
        raise
    except Exception as e:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass
        raise JournalAtomicError(f"write failed: {e}", exit_code=2)


# ---------------------------------------------------------------------------
# Metadata coercion + frontmatter parsing.

def coerce_metadata(metadata_pairs):
    """Parse 'key=value' strings into a dict with type coercion.

    Coercion rules (preserve journal-record.sh:178-187 behavior verbatim):
      - value containing ',' → list of stripped non-empty segments
      - value matching int → int
      - value matching 'true'/'false' (case-insensitive) → bool
      - otherwise → string

    Raises JournalAtomicError(exit_code=1) on malformed pairs (no '=' or
    empty key).
    """
    result = {}
    for pair in metadata_pairs:
        if not pair:
            continue
        if "=" not in pair:
            raise JournalAtomicError(
                f"invalid metadata '{pair}' — must be key=value",
                exit_code=1,
            )
        key, raw = pair.split("=", 1)
        key = key.strip()
        if not key:
            raise JournalAtomicError(
                f"metadata key cannot be empty (in '{pair}')",
                exit_code=1,
            )
        if "," in raw:
            value = [v.strip() for v in raw.split(",") if v.strip()]
        elif raw.isdigit():
            value = int(raw)
        elif raw.lower() in ("true", "false"):
            value = raw.lower() == "true"
        else:
            value = raw
        result[key] = value
    return result


def parse_frontmatter(content, loader=None):
    """Parse YAML frontmatter from journal content.

    Returns (manifest_dict_or_None, body_str). manifest_dict is None when
    content has no opening '---' fence (treat as new manifest).

    Raises JournalAtomicError(exit_code=2, refuse=True) on:
      - opening '---' with no closing fence
      - YAML parse failure inside the frontmatter
      - non-mapping (list, scalar) frontmatter

    The refuse=True flag tells callers to append the
    "refusing to overwrite — fix manually" line, matching the original
    journal-record.sh:217-232 behavior.

    `loader` defaults to yaml.SafeLoader, which is what every write path has
    always used. bin/_journal_manifest.py passes a stricter subclass: a reader
    prints what it parses, so it refuses aliases, and a read that refuses more
    than a write accepts is safe in a way the reverse is not. It is a
    parameter rather than a second fence test in the reader because the fence
    predicate drifting between the two was the defect — a journal opening
    `--- ` has no manifest here and had a complete one over there.
    """
    if loader is None:
        loader = yaml.SafeLoader
    if not content.startswith("---\n"):
        return None, content
    end_marker = content.find("\n---\n", 4)
    if end_marker == -1:
        # Opening `---` with no closing fence. A fresh-render fallback would
        # prepend new frontmatter to a body that itself starts with `---`,
        # producing a doubly-fenced file that parses but silently ships the
        # old malformed content into the new body.
        raise JournalAtomicError(
            "existing journal has unclosed frontmatter "
            "(opening `---` with no closing fence)",
            exit_code=2,
            refuse=True,
        )
    try:
        manifest = yaml.load(content[4:end_marker], Loader=loader)
    except yaml.YAMLError as e:
        raise JournalAtomicError(
            f"existing frontmatter is invalid YAML: {e}",
            exit_code=2,
            refuse=True,
        )
    body = content[end_marker + 5:]
    if not isinstance(manifest, dict):
        raise JournalAtomicError(
            "existing frontmatter is not a YAML mapping",
            exit_code=2,
            refuse=True,
        )
    return manifest, body


# ---------------------------------------------------------------------------
# Public API: three write shapes.

def record_artifact(journal_path, lockfile_path, issue, artifact_type,
                    metadata_pairs, now_iso):
    """Append an artifact to the journal manifest.

    Preserves journal-record.sh semantics verbatim:
      - If journal does not exist: create with {issue, created, artifacts:[]}
      - If journal exists with frontmatter: parse, append to artifacts[]
      - If journal exists without frontmatter: prepend a manifest, preserve body
      - Atomicity via lockfile + temp+rename + fsync

    Raises JournalAtomicError on any failure (exit_code/refuse set per error).
    """
    _harden_sys_path()
    lock_fd = acquire_lock(lockfile_path)
    try:
        meta_dict = coerce_metadata(metadata_pairs)

        content = _read_with_no_follow(journal_path)
        if content:
            manifest, body = parse_frontmatter(content)
            if manifest is None:
                # File exists but has no frontmatter — legacy entry. Seed a
                # manifest and preserve the body verbatim.
                manifest = {"issue": issue, "created": now_iso, "artifacts": []}
        else:
            manifest, body = {"issue": issue, "created": now_iso, "artifacts": []}, ""

        manifest.setdefault("issue", issue)
        manifest.setdefault("created", now_iso)
        manifest.setdefault("artifacts", [])

        artifact = {"type": artifact_type, "captured_at": now_iso}
        artifact.update(meta_dict)
        manifest["artifacts"].append(artifact)

        front = yaml.safe_dump(
            manifest, sort_keys=False, default_flow_style=False, allow_unicode=True,
        )
        new_content = f"---\n{front}---\n{body}"
        _atomic_write(journal_path, new_content)
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass


def append_body(target_path, lockfile_path, text, *, leading_blank=True):
    """Append `text` to target_path under flock, via O_APPEND.

    Two invariants, both load-bearing:

    ORDERING — acquire the lock BEFORE opening the target. An fd opened before
    the lock points at the pre-rename inode, so a concurrent record_artifact()
    that wins the lock and renames over the file would leave this writer's bytes
    in an unlinked inode: an append that succeeds and disappears with no error.

    O_APPEND rather than read-modify-write. flock cannot see a non-cooperating
    writer — an editor, a session still running an older plugin version, a bare
    `>>` from an un-migrated consumer — so a whole-file temp+rename here would
    publish a stale copy over whatever that writer added. It is also O(1) in
    file size where a rewrite is O(size), and this runs on every Edit/Write.

    The residual, stated rather than hidden: record_artifact() can still revert
    an *unlocked* append that lands inside its own read→rename window. That
    window is not removable while the manifest must live in the frontmatter at
    the top of the file, and this function does not widen it.

    The entry is handed to a single os.write on the open fd, so a concurrent
    reader never observes a torn entry — the same one-write(2) property
    bin/flow-quality-ledger.sh relies on at its append. A short write (only
    reachable for a payload larger than the kernel will take in one call) is
    completed by a loop, which is why the guarantee is per-call and not
    per-entry for arbitrarily large input.
    """
    _harden_sys_path()
    lock_fd = acquire_lock(lockfile_path)
    try:
        try:
            fd = os.open(
                target_path,
                os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW,
                0o644,
            )
        except OSError as e:
            if e.errno in (errno.ELOOP, errno.EMLINK):
                raise JournalAtomicError(
                    f"refusing — {target_path} is a symlink",
                    exit_code=2,
                )
            raise JournalAtomicError(
                f"cannot open {target_path}: {e}",
                exit_code=2,
            )
        try:
            payload = "\n" + text if leading_blank else text
            if not payload.endswith("\n"):
                payload += "\n"
            data = payload.encode("utf-8")
            written = 0
            while written < len(data):
                n = os.write(fd, data[written:])
                if n <= 0:
                    raise JournalAtomicError(
                        f"short write to {target_path}", exit_code=2
                    )
                written += n
            os.fsync(fd)
        except JournalAtomicError:
            raise
        except OSError as e:
            raise JournalAtomicError(
                f"append to {target_path} failed: {e}", exit_code=2
            )
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass


def _fence_delim(line):
    """Return the fence character a line opens/closes with, or ''.

    Only the first non-space run counts. A journal that quotes a section heading
    inside a fenced example is real — the schema reference documents the
    specification shape that way — and treating that quoted heading as the
    section would corrupt both the example and the real section, and leave the
    fence unbalanced. Same rule as bin/flow-strip-auto-log.sh's tracker.
    """
    s = line.lstrip()
    if s.startswith("```"):
        return "`"
    if s.startswith("~~~"):
        return "~"
    return ""


def _splice_section(body, heading, text):
    """Return `body` with `heading`'s section replaced by `text`, or appended.

    A section runs from its heading line to the next `## ` heading. Headings
    inside a fenced code block are not headings, and neither are `## ` lines
    inside a fence that sits within the section being skipped.

    Split out from replace_section() so the splice rule is testable without a
    filesystem.
    """
    lines = body.split("\n")
    out = []
    found = False
    i = 0
    in_fence = False
    fence_char = ""
    while i < len(lines):
        line = lines[i]
        delim = _fence_delim(line)
        if delim and (not in_fence or delim == fence_char):
            in_fence = not in_fence
            fence_char = delim if in_fence else ""
            out.append(line)
            i += 1
            continue
        if in_fence:
            out.append(line)
            i += 1
            continue
        # Only the FIRST match is the section. A journal can carry the heading
        # twice — a hand-edit, an append by a writer that predates this one, or
        # a capture that appended because an unclosed fence hid the original —
        # and replacing every one of them duplicates the new text and destroys
        # the second copy's body.
        if line == heading and not found:
            found = True
            out.append(heading)
            out.append("")
            # Normalize: one blank line after the section, whatever trailing
            # newlines the caller's text carries, so the section that follows
            # stays visually separated from this one.
            text_lines = text.split("\n")
            while text_lines and text_lines[-1] == "":
                text_lines.pop()
            out.extend(text_lines)
            out.append("")
            i += 1
            # Skip the old section, fence-aware so a `## ` line inside a
            # fenced block within the section cannot end the skip early.
            while i < len(lines):
                inner = lines[i]
                inner_delim = _fence_delim(inner)
                if inner_delim and (not in_fence or inner_delim == fence_char):
                    in_fence = not in_fence
                    fence_char = inner_delim if in_fence else ""
                    i += 1
                    continue
                if not in_fence and inner.startswith("## "):
                    break
                i += 1
            continue
        out.append(line)
        i += 1
    if not found:
        if out and out[-1] != "":
            out.append("")
        out.append(heading)
        out.append("")
        text_lines = text.split("\n")
        while text_lines and text_lines[-1] == "":
            text_lines.pop()
        out.extend(text_lines)
        # Terminate the file. Without this the append branch wrote no final
        # newline, so every first capture for an issue produced a tracked file
        # that git reports as "\ No newline at end of file" — and the replace
        # branch, which keeps the surrounding lines, did not.
        out.append("")
    return "\n".join(out)


def replace_section(journal_path, lockfile_path, heading, text):
    """Replace `heading`'s section in the journal body, or append it.

    Read-modify-write under flock (tempfile + rename), because a mid-file
    replacement cannot be done with O_APPEND — which is exactly why this is a
    separate entry point from append_body() rather than a flag on it.

    The frontmatter is preserved byte-for-byte: parse_frontmatter() is called
    for its refusals (unclosed fence, invalid YAML, non-mapping) and the prefix
    is then recovered by length, so a rewritten journal never re-serializes a
    manifest it was only supposed to leave alone.

    A target that does not exist is created with just the section; the manifest
    is added later by record_artifact(), which is the only writer that knows the
    issue number.
    """
    _harden_sys_path()
    lock_fd = acquire_lock(lockfile_path)
    try:
        content = _read_with_no_follow(journal_path)
        if content:
            _manifest, body = parse_frontmatter(content)
            prefix = content[: len(content) - len(body)]
        else:
            prefix, body = "", ""
        new_content = prefix + _splice_section(body, heading, text)
        if new_content != content:
            _atomic_write(journal_path, new_content)
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass


def write_yaml_file(target_path, lockfile_path, data):
    """Atomically write `data` (dict) as a standalone YAML file.

    Used for FlowActivity, FlowEvidence sidecar, FlowGoal contract — anywhere
    the payload is a single YAML document with no markdown body. Does NOT
    use frontmatter wrapping.

    target_path is checked for symlink via O_NOFOLLOW probe before the
    temp+rename, since a pre-staged symlink would let an attacker redirect
    writes to user-readable files outside the intended directory.
    """
    _harden_sys_path()
    lock_fd = acquire_lock(lockfile_path)
    try:
        if os.path.lexists(target_path):
            try:
                check_fd = os.open(target_path, os.O_RDONLY | os.O_NOFOLLOW)
                os.close(check_fd)
            except OSError as e:
                if e.errno in (errno.ELOOP, errno.EMLINK):
                    raise JournalAtomicError(
                        f"refusing — target {target_path} is a symlink",
                        exit_code=2,
                    )
                # Other read errors are non-fatal here (e.g., transient
                # filesystem hiccup) — let _atomic_write surface them.

        content = yaml.safe_dump(
            data, sort_keys=False, default_flow_style=False, allow_unicode=True,
        )
        _atomic_write(target_path, content)
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass


def write_json_file(target_path, lockfile_path, data):
    """Atomically write `data` (dict) as a standalone JSON file.

    Used for FlowRun last-verdict.json and any other JSON state file under
    .flow/runs/. Replace semantics (NOT merge) — verdicts are immutable per
    turn but mutable across turns; the new verdict supersedes the old.

    Same security defenses as write_yaml_file:
      - O_NOFOLLOW probe rejects symlinked target atomically
      - flock(lockfile_path) serializes concurrent writers
      - tempfile.mkstemp + os.rename + dual fsync for durability
      - Hostile-fork sys.path filter inherited via _harden_sys_path

    JSON is serialized with sort_keys=True so re-writing the same data
    produces byte-identical output (useful for diff-based comparison and
    avoids spurious mtime churn).
    """
    _harden_sys_path()
    lock_fd = acquire_lock(lockfile_path)
    try:
        if os.path.lexists(target_path):
            try:
                check_fd = os.open(target_path, os.O_RDONLY | os.O_NOFOLLOW)
                os.close(check_fd)
            except OSError as e:
                if e.errno in (errno.ELOOP, errno.EMLINK):
                    raise JournalAtomicError(
                        f"refusing — target {target_path} is a symlink",
                        exit_code=2,
                    )

        import json as _json
        # sort_keys=True is intentionally asymmetric vs write_yaml_file
        # (which uses sort_keys=False). Rationale: JSON state files
        # (last-verdict.json) prioritize byte-identical re-writes so two
        # callers writing the same data don't churn mtime/sha. YAML
        # contracts (goals, evidence sidecars) are human-edited and
        # preserve author key order. Don't unify the two without a
        # corresponding test that proves byte-identity isn't load-bearing.
        content = _json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
        _atomic_write(target_path, content)
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass


def append_jsonl(events_path, event):
    """Append `event` (dict) as a JSON line to `events_path`.

    Uses flock(events_path + '.lock') for concurrent-safe appends. JSONL is
    tolerant of partial reads — readers MUST skip un-parseable trailing
    lines (which can happen if a writer is killed mid-line).

    Defends the events file itself with O_NOFOLLOW so a pre-staged symlink
    cannot redirect appends.
    """
    _harden_sys_path()
    lockfile_path = events_path + ".lock"
    lock_fd = acquire_lock(lockfile_path)
    try:
        try:
            fd = os.open(
                events_path,
                os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW,
                0o644,
            )
        except OSError as e:
            if e.errno in (errno.ELOOP, errno.EMLINK):
                raise JournalAtomicError(
                    f"refusing — events file {events_path} is a symlink",
                    exit_code=2,
                )
            raise JournalAtomicError(
                f"cannot open events file {events_path}: {e}",
                exit_code=2,
            )
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
            f.flush()
            os.fsync(f.fileno())
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass
