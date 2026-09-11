#!/usr/bin/env bash
# [flow] Mine Claude Code session transcripts for user corrections.
#
# /flow:learn and the SessionEnd hook historically read only what flow wrote
# itself (.decisions/*.md, .flow/runs/*/events.jsonl). Every user correction
# ("that's not what I asked", "it is still empty", "why didn't you run the
# tests?") lives in the session transcript, which nothing opened. This script
# streams those transcripts and emits the user turns that look like reactions
# to the assistant's previous turn, so /flow:learn Phase 2 can cluster them.
#
# Usage:
#   flow-mine-corrections.sh [--project-dir <cwd>] [--transcript-dir <dir>]
#                            [--file <transcript.jsonl>] [--since <ISO date>]
#                            [--max-sessions <n>] [--format jsonl|markdown]
#                            [--min-chars <n>]
#
# Flags:
#   --project-dir <cwd>    project whose transcripts to scan (default: $PWD)
#   --transcript-dir <dir> directory holding <session>.jsonl files. Default:
#                          CLAUDE_TRANSCRIPT_DIR/<slug> when that is set,
#                          otherwise the first of $HOME/.claude/projects/<slug>
#                          and $HOME/.claude-work/projects/<slug> that actually
#                          holds transcripts
#                          where <slug> is --project-dir with every
#                          non-alphanumeric character replaced by `-`
#   --file <path>          scan exactly this one transcript (ignores the dir)
#   --since <ISO date>     keep records at or after this timestamp
#                          (YYYY-MM-DD or full ISO 8601; naive = UTC)
#   --max-sessions <n>     newest N transcripts by mtime (default 50)
#   --format jsonl         one JSON object per candidate (default)
#   --format markdown      KEY=value counts + a markdown table
#   --min-chars <n>        drop candidate texts shorter than n (default 1)
#
# Output (jsonl): {session_id, timestamp, project, text, preceded_by,
#                  transcript_path, line_no} per candidate.
# Output (markdown): TRANSCRIPT_DIR=<path>, TRANSCRIPT_DIR_STATE=ok|missing,
#                  CANDIDATE_COUNT=N, SESSION_COUNT=N,
#                  SESSIONS_WITH_CANDIDATES=N, then a table.
#
# Exit:
#   0 — scan completed (also when the transcript dir/file is missing:
#       stderr note + CANDIDATE_COUNT=0)
#   1 — bad argument
#   2 — python3 missing
#
# Read-only. No network. Never prints a full assistant turn (the assistant
# context is truncated to 300 chars). The transcript format is internal and
# unstable: every line is parsed defensively and unparsable lines are skipped.

set -uo pipefail

# PYTHONSAFEPATH keeps the CWD off sys.path so a hostile checkout cannot
# shadow stdlib modules (json, re, datetime) during the heredoc run.
export PYTHONSAFEPATH=1

PROJECT_DIR=""
TRANSCRIPT_DIR=""
ONE_FILE=""
SINCE=""
MAX_SESSIONS="50"
FORMAT="jsonl"
MIN_CHARS="1"

_need_value() {
  [ $# -ge 2 ] || { echo "flow-mine-corrections.sh: $1 requires a value" >&2; exit 1; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)    _need_value "$@"; PROJECT_DIR="$2"; shift 2 ;;
    --transcript-dir) _need_value "$@"; TRANSCRIPT_DIR="$2"; shift 2 ;;
    --file)           _need_value "$@"; ONE_FILE="$2"; shift 2 ;;
    --since)          _need_value "$@"; SINCE="$2"; shift 2 ;;
    --max-sessions)   _need_value "$@"; MAX_SESSIONS="$2"; shift 2 ;;
    --format)         _need_value "$@"; FORMAT="$2"; shift 2 ;;
    --min-chars)      _need_value "$@"; MIN_CHARS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,45p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "flow-mine-corrections.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$FORMAT" in
  jsonl|markdown) ;;
  *) echo "flow-mine-corrections.sh: --format must be jsonl or markdown (got: $FORMAT)" >&2; exit 1 ;;
esac
case "$MAX_SESSIONS" in
  ''|*[!0-9]*) echo "flow-mine-corrections.sh: --max-sessions must be a non-negative integer (got: $MAX_SESSIONS)" >&2; exit 1 ;;
esac
case "$MIN_CHARS" in
  ''|*[!0-9]*) echo "flow-mine-corrections.sh: --min-chars must be a non-negative integer (got: $MIN_CHARS)" >&2; exit 1 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-mine-corrections.sh: python3 required but not installed" >&2
  exit 2
fi

# Resolve the project dir to an absolute path (Claude Code derives the
# transcript slug from the cwd it was launched in).
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$PWD"
elif [ -d "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
fi

# Defined before the root resolution below, which calls it: the HOME guard
# there was dead code while this sat 23 lines further down, so an unset HOME
# produced 'command not found' and then died on $HOME under set -u — with
# none of the keys a caller parses, breaking the exit-0 contract the `!`
# blocks and the SessionEnd hook rely on.
# Missing inputs are a normal state (fresh machine, transcripts pruned,
# non-standard install). Report zero candidates and exit 0 so callers in `!`
# blocks and SessionEnd hooks never fail because of it.
_report_missing() {
  echo "flow-mine-corrections.sh: $1" >&2
  if [ "$FORMAT" = "markdown" ]; then
    echo "TRANSCRIPT_DIR=${ONE_FILE:-$TRANSCRIPT_DIR}"
    echo "TRANSCRIPT_DIR_STATE=missing"
    # Name every root that was probed. "Not found" and "found and empty" are
    # different facts, and reporting one path made them look identical.
      # The roots are named whether or not one matched — see the success-path
    # emit below for why.
    [ -z "$ONE_FILE" ] && [ -n "${TRANSCRIPT_ROOTS_TRIED:-}" ] && echo "TRANSCRIPT_ROOTS_TRIED=$TRANSCRIPT_ROOTS_TRIED"
    echo "CANDIDATE_COUNT=0"
    echo "SESSION_COUNT=0"
    echo "SESSIONS_WITH_CANDIDATES=0"
  fi
  exit 0
}
# Default transcript dir: <root>/<slug>. The slug replaces every character
# that is not [A-Za-z0-9] with `-` (so /home/user/repo -> -home-user-repo).
#
# The root is a LIST, not one path. Claude Code stores transcripts under
# ~/.claude/projects on some machines and ~/.claude-work/projects on others, and
# probing only the first meant that on a machine using the second layout the
# miner reported TRANSCRIPT_STATE=missing and /flow:learn ran its whole
# correction phase against zero rows. Nothing looked wrong: the run completed,
# proposals were produced, and the half carrying the behavioural signal was one
# line in a status table. On the machine where this was measured the default
# path held nothing and the real directory held 8 sessions and 46 candidate
# rows (issue #168).
#
# CLAUDE_TRANSCRIPT_DIR and --transcript-dir still override the list outright.
# TRANSCRIPT_ROOTS_TRIED records every root probed so a genuinely empty result
# is distinguishable from a directory that was never found.
TRANSCRIPT_ROOTS_TRIED=""
TRANSCRIPT_ROOTS_SEARCHED=0
if [ -z "$TRANSCRIPT_DIR" ]; then
  SLUG=$(printf '%s' "$PROJECT_DIR" | sed 's/[^A-Za-z0-9]/-/g')
  if [ -n "${CLAUDE_TRANSCRIPT_DIR:-}" ]; then
    TRANSCRIPT_DIR="$CLAUDE_TRANSCRIPT_DIR/$SLUG"
  else
    TRANSCRIPT_ROOTS_SEARCHED=1
    # Probe for CONTENT, not for the directory. On the machine that reported
    # this issue, ~/.claude/projects/<slug> exists and holds only a memory/
    # subdirectory -- zero transcripts -- while ~/.claude-work/projects/<slug>
    # holds them. A directory-existence probe picks the first, reports
    # TRANSCRIPT_STATE=ok with SESSION_COUNT=0, and the whole evidence source
    # stays invisible behind a result that reads like "found and empty". That is
    # the exact confusion issue #168 is about, so the probe has to ask the
    # question the issue asks: which root actually has the transcripts.
    _first_existing=""
    if [ -z "${HOME:-}" ]; then
      _report_missing "HOME is unset, so the transcript roots cannot be located; pass --transcript-dir or set CLAUDE_TRANSCRIPT_DIR"
    fi
    for _root in "$HOME/.claude/projects" "$HOME/.claude-work/projects"; do
      TRANSCRIPT_ROOTS_TRIED="${TRANSCRIPT_ROOTS_TRIED:+$TRANSCRIPT_ROOTS_TRIED, }$_root"
      if ls "$_root/$SLUG"/*.jsonl >/dev/null 2>&1; then
        TRANSCRIPT_DIR="$_root/$SLUG"
        break
      fi
      # Remember the first root whose directory exists, so a genuinely empty
      # project still reports a path someone can go and look at.
      [ -z "$_first_existing" ] && [ -d "$_root/$SLUG" ] && _first_existing="$_root/$SLUG"
    done
    if [ -z "$TRANSCRIPT_DIR" ]; then
      TRANSCRIPT_DIR="${_first_existing:-$HOME/.claude/projects/$SLUG}"
    fi
    unset _first_existing
    unset _root
  fi
fi

if [ -n "$ONE_FILE" ]; then
  [ -L "$ONE_FILE" ] && _report_missing "--file is a symlink; refusing to follow it: $ONE_FILE"
  [ -f "$ONE_FILE" ] || _report_missing "transcript file not found: $ONE_FILE"
else
  if [ ! -d "$TRANSCRIPT_DIR" ]; then
    # Two different facts, two different sentences. When the caller named the
    # directory, say that directory is not there. When the roots were searched,
    # name every one of them — "not found" and "found and empty" look identical
    # otherwise, which is how a whole evidence source stayed invisible.
    if [ "$TRANSCRIPT_ROOTS_SEARCHED" = "1" ]; then
      _report_missing "no transcript dir for this project under any known root (tried: $TRANSCRIPT_ROOTS_TRIED); set --transcript-dir or CLAUDE_TRANSCRIPT_DIR to point at it"
    else
      _report_missing "transcript dir not found: $TRANSCRIPT_DIR (set --transcript-dir or CLAUDE_TRANSCRIPT_DIR)"
    fi
  fi
fi

# Everything user-controlled travels via argv, never via source interpolation.
python3 - "$PROJECT_DIR" "$TRANSCRIPT_DIR" "$ONE_FILE" "$SINCE" "$MAX_SESSIONS" "$FORMAT" "$MIN_CHARS" "${TRANSCRIPT_ROOTS_TRIED:-}" <<'PYTHON'
import datetime
import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Reaction filter — the list that decides which user turns are *candidate*
# corrections. It is deliberately recall-oriented: it keeps anything that
# sounds like a reaction to the assistant's previous turn and accepts false
# positives. Precision is applied later, by /flow:learn Phase 2, which reads
# each cited transcript line before counting it toward a pattern.
#
# To extend: append a phrase. Phrases are matched case-insensitively as whole
# words anywhere in the text (a leading match counts too). An apostrophe in a
# phrase also matches its absence and the typographic form (don't / dont /
# don’t). Multi-word phrases match across any whitespace.
REACTION_PHRASES = [
    "no",
    "not",
    "don't",
    "do not",
    "stop",
    "why did",
    "why didn't",
    "what do you mean",
    "i asked",
    "i said",
    "again",
    "wrong",
    "incorrect",
    "that's not",
    "this is not",
    "instead",
    "you should have",
    "you didn't",
    "still",
    "empty",
    "broken",
    "doesn't work",
    "speak",
    "plain",
]
# A sentence that addresses the assistant ("you") and ends with "?" is a
# question about its behaviour ("haven't you run deploy?"). Kept as a regex
# because it is a shape, not a phrase.
YOU_QUESTION_RE = re.compile(r"\byou\b[^.!?]*\?", re.IGNORECASE)
# Keyword matching only applies to short turns; long turns are task briefs,
# not reactions. Slash-command repeats are exempt from the cap.
MAX_REACTION_CHARS = 600
# Assistant context is truncated so a full assistant turn is never emitted.
PRECEDED_BY_MAX = 300
# Candidate text is bounded too (slash-command repeats can carry long args).
TEXT_MAX = 600
# ---------------------------------------------------------------------------


def _phrase_regex(phrase):
    parts = []
    for tok in phrase.split():
        esc = re.escape(tok).replace(re.escape("'"), "['’]?")
        parts.append(esc)
    return re.compile(r"\b" + r"\s+".join(parts) + r"\b", re.IGNORECASE)


REACTION_RES = [_phrase_regex(p) for p in REACTION_PHRASES]

# Tags Claude Code injects into user turns that are not the user's words.
INJECTED_BLOCK_RE = re.compile(
    r"<(system-reminder|local-command-caveat|local-command-stdout|local-command-stderr|"
    r"command-message|task-notification|ide_opened_file|ide_selection)>.*?</\1>",
    re.IGNORECASE | re.DOTALL,
)
COMMAND_NAME_RE = re.compile(r"<command-name>(.*?)</command-name>", re.DOTALL)
COMMAND_ARGS_RE = re.compile(r"<command-args>(.*?)</command-args>", re.DOTALL)

project_dir, transcript_dir, one_file, since_raw, max_sessions, fmt, min_chars = sys.argv[1:8]
max_sessions = int(max_sessions)
min_chars = int(min_chars)


def parse_ts(value):
    """ISO 8601 -> aware UTC datetime, or None when unparsable."""
    if not isinstance(value, str) or not value:
        return None
    v = value.strip()
    if v.endswith("Z") or v.endswith("z"):
        v = v[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(v)
    except ValueError:
        try:
            dt = datetime.datetime.combine(datetime.date.fromisoformat(v), datetime.time())
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


since = None
if since_raw:
    since = parse_ts(since_raw)
    if since is None:
        print(f"flow-mine-corrections.sh: --since is not an ISO date: {since_raw}", file=sys.stderr)
        sys.exit(1)


def user_text(content):
    """Return (text, is_slash, slash_text) for a user record's message.content.

    tool_result blocks are ignored; a list without a text block yields "".
    """
    if isinstance(content, str):
        raw = content
    elif isinstance(content, list):
        pieces = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                t = block.get("text")
                if isinstance(t, str):
                    pieces.append(t)
        raw = "\n".join(pieces)
    else:
        return "", False, ""
    m = COMMAND_NAME_RE.search(raw)
    if m:
        name = m.group(1).strip()
        a = COMMAND_ARGS_RE.search(raw)
        args = a.group(1).strip() if a else ""
        slash = (name + " " + args).strip() if args else name
        return slash, True, slash
    cleaned = INJECTED_BLOCK_RE.sub("", raw).strip()
    return cleaned, False, ""


def assistant_last_text(content):
    """Last text block of an assistant record, or None when it has none."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    last = None
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text" and isinstance(block.get("text"), str):
            last = block["text"]
    return last


def is_reaction(text):
    if len(text) > MAX_REACTION_CHARS:
        return False
    for rx in REACTION_RES:
        if rx.search(text):
            return True
    return bool(YOU_QUESTION_RE.search(text))


def truncate(s, n):
    s = s.replace("\r", "")
    if len(s) <= n:
        return s
    return s[: n - 1] + "…"


def scan_file(path):
    """Yield candidate dicts from one transcript, in file order."""
    session_fallback = os.path.splitext(os.path.basename(path))[0]
    assistant_since_human = False   # an assistant record was seen after the last human turn
    last_assistant_text = ""
    last_slash = None                # previous human turn's slash command, if any
    try:
        fh = open(path, "r", encoding="utf-8", errors="replace")
    except OSError as e:
        print(f"flow-mine-corrections.sh: cannot read {path}: {e}", file=sys.stderr)
        return
    with fh:
        for line_no, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            rtype = rec.get("type")
            msg = rec.get("message")
            content = msg.get("content") if isinstance(msg, dict) else None

            if rtype == "assistant":
                if rec.get("isSidechain") is True:
                    continue
                t = assistant_last_text(content)
                if t is not None:
                    last_assistant_text = t
                assistant_since_human = True
                continue

            if rtype != "user":
                continue
            if rec.get("isMeta") is True or rec.get("isSidechain") is True:
                continue
            origin = rec.get("origin")
            if isinstance(origin, dict) and "kind" in origin and origin.get("kind") != "human":
                continue
            text, is_slash, slash_text = user_text(content)
            if not text:
                continue

            # From here on this is a human turn: decide, then reset the
            # "follows an assistant record" state for the next turn.
            follows_assistant = assistant_since_human
            preceded_by = last_assistant_text
            prev_slash = last_slash
            assistant_since_human = False
            last_assistant_text = ""
            last_slash = slash_text if is_slash else None

            if not follows_assistant:
                continue
            if len(text) < min_chars:
                continue
            ts = parse_ts(rec.get("timestamp"))
            if since is not None and (ts is None or ts < since):
                continue

            keep = False
            if is_slash:
                keep = prev_slash is not None and prev_slash == slash_text
            if not keep:
                keep = is_reaction(text)
            if not keep:
                continue

            yield {
                "session_id": rec.get("sessionId") or session_fallback,
                "timestamp": rec.get("timestamp") if isinstance(rec.get("timestamp"), str) else "",
                "project": rec.get("cwd") if isinstance(rec.get("cwd"), str) else project_dir,
                "text": truncate(text, TEXT_MAX),
                "preceded_by": truncate(preceded_by, PRECEDED_BY_MAX),
                "transcript_path": path,
                "line_no": line_no,
            }


# Pick transcripts: one explicit file, or the newest N regular *.jsonl files.
if one_file:
    files = [one_file]
else:
    entries = []
    for name in os.listdir(transcript_dir):
        if not name.endswith(".jsonl"):
            continue
        full = os.path.join(transcript_dir, name)
        if os.path.islink(full) or not os.path.isfile(full):
            continue
        try:
            mtime = os.stat(full).st_mtime
        except OSError:
            continue
        entries.append((mtime, full))
    entries.sort(reverse=True)
    if since is not None:
        # A file's mtime is never older than its last record, so files
        # untouched since --since cannot contain matching records.
        cutoff = since.timestamp()
        entries = [e for e in entries if e[0] >= cutoff]
    entries = entries[:max_sessions]
    entries.sort()  # oldest first for a chronological report
    files = [e[1] for e in entries]

candidates = []
for f in files:
    candidates.extend(scan_file(f))

sessions_with = len({c["transcript_path"] for c in candidates})

if fmt == "jsonl":
    out = sys.stdout
    for c in candidates:
        out.write(json.dumps(c, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"flow-mine-corrections.sh: CANDIDATE_COUNT={len(candidates)} SESSION_COUNT={len(files)}", file=sys.stderr)
    sys.exit(0)


def cell(s, n):
    s = " ".join(str(s).split())
    s = s.replace("|", "\\|")
    return truncate(s, n)


print(f"TRANSCRIPT_DIR={one_file or transcript_dir}")
print("TRANSCRIPT_DIR_STATE=ok")
# Which roots were searched, on the success path as well as the failure one.
# "Searched both and found nothing" and "found it, and it is empty" are
# different findings, and naming the roots only when nothing matched left them
# reading the same here — the confusion issue #168 is about, one level down.
_roots = sys.argv[8] if len(sys.argv) > 8 else ""
if _roots and not one_file:
    print(f"TRANSCRIPT_ROOTS_TRIED={_roots}")
print(f"CANDIDATE_COUNT={len(candidates)}")
print(f"SESSION_COUNT={len(files)}")
print(f"SESSIONS_WITH_CANDIDATES={sessions_with}")
if candidates:
    print("")
    print("| # | Session | Timestamp | Line | User said | Preceded by (assistant, truncated) |")
    print("|---|---------|-----------|------|-----------|-----------------------------------|")
    for i, c in enumerate(candidates, 1):
        print(
            f"| {i} | {cell(c['session_id'], 40)} | {cell(c['timestamp'], 24)} | "
            f"{cell(c['transcript_path'], 200)}:{c['line_no']} | {cell(c['text'], 240)} | "
            f"{cell(c['preceded_by'], 120)} |"
        )
PYTHON
