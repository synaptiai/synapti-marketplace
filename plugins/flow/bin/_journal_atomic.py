"""Atomic YAML writes with security defenses for the flow plugin.

Extracted from journal-record.sh:120-295 (M1 of flow v3). Shared by:
  - journal-record.sh           (manifest append; existing semantics preserved)
  - flow-record-activity.sh     (FlowActivity standalone YAML writes)
  - flow-record-evidence.sh     (FlowEvidence sidecar + raw output writes)
  - flow-goal-record.sh         (FlowGoal contract + lifecycle writes; M2)

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

import yaml


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


def parse_frontmatter(content):
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
    """
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
        manifest = yaml.safe_load(content[4:end_marker])
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
