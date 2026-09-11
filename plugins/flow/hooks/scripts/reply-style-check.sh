#!/usr/bin/env bash
# [flow] Stop hook: check the reply that was just written against the project's
# reply-style rule.
#
# Projects state a house writing style in their instruction file, loaded once at
# session start. Nothing then checks it at the moment a reply is produced. In
# one project the user stopped the work three times across two sessions to say
# they could not understand the reply; the third time they noted they had asked
# before. The rule was already written down twice in that project's own
# instructions and in the active output style. Writing it a fourth time is not
# the fix — the rule is in context at session start and the violations happen
# deep into long sessions, after many tool results have pushed it out of the
# window (issue #172).
#
# So this is not a style engine. It matches a short, literal list of
# constructions, names where each appeared, and warns.
#
# It never blocks, and it must never be the reason a session keeps going: the
# finding goes out as `systemMessage` on stdout with exit 0, and carries no
# `decision` field. stderr from an exit-0 Stop hook goes to the debug log and is
# shown to nobody — an earlier version of this relied on stderr alone, so the
# check ran, found things, and told no one.
#
# Off unless the project opts in:
#
#   .claude/settings.flow.json  {"replyStyle": {"enabled": true}}
#
# Configure the list per project:
#
#   {"replyStyle": {"enabled": true,
#                   "constructions": ["issue-references", "not-x-but-y"],
#                   "extraPatterns": [{"name": "our-own-tic", "pattern": "\\bsynergy\\b"}]}}
#
# `constructions` selects from the built-in set; omit it for all of them, or give
# [] to run only your own `extraPatterns`.
#
# What it deliberately does NOT do:
#   - judge clarity. It matches constructions; it does not score prose.
#   - rewrite anything.
#   - look at what was committed. Code and commit messages are a different
#     check with different rules.

set -uo pipefail
export PYTHONSAFEPATH=1

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

# Graceful degradation: a missing tool must not break the stop.
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0
# A symlinked transcript path is not followed: this hook reads whatever it is
# pointed at, and the path arrives from outside.
[ -L "$TRANSCRIPT" ] && exit 0

RESOLVE="$PLUGIN_ROOT/bin/cascade-resolve.sh"
[ -x "$RESOLVE" ] || exit 0

ENABLED=$("$RESOLVE" --default "false" '.replyStyle.enabled' 2>/dev/null)
[ "$ENABLED" = "true" ] || exit 0

SELECTED=$("$RESOLVE" --compact --default "null" '.replyStyle.constructions' 2>/dev/null)
EXTRA=$("$RESOLVE" --compact --default "null" '.replyStyle.extraPatterns' 2>/dev/null)

# A project-supplied regex can backtrack catastrophically, and this runs at every
# stop: `(x+x+)+y` against a long non-matching string does not come back. Python
# cannot interrupt its own regex engine — signal.alarm never fires, because the
# matcher does not return to the interpreter loop — so the bound has to come from
# outside the process. `timeout` is absent on a stock macOS, hence the watchdog.
_rsc_run_with_limit() {
  local limit=5 out rc pid watchdog
  out=$(mktemp -t flow-replystyle.XXXXXX 2>/dev/null) || return 1
  python3 "$@" >"$out" 2>/dev/null &
  pid=$!
  ( sleep "$limit"; kill -9 "$pid" >/dev/null 2>&1 ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" >/dev/null 2>&1
  rc=$?
  kill "$watchdog" >/dev/null 2>&1
  wait "$watchdog" >/dev/null 2>&1 || true
  if [ "$rc" -ne 0 ]; then
    rm -f "$out"
    return 1
  fi
  cat "$out"
  rm -f "$out"
  return 0
}

SCRIPT=$(mktemp -t flow-replystyle-py.XXXXXX 2>/dev/null) || exit 0
cat > "$SCRIPT" <<'PYTHON'
import json
import re
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]

transcript, selected_raw, extra_raw = sys.argv[1], sys.argv[2], sys.argv[3]

# --- the built-in list -------------------------------------------------------
# Each entry is (name, regex, what to say). The wording matters more than the
# match: a warning that only says "you did the thing" teaches nothing.
#
# Every pattern here was narrowed against ordinary technical prose. A check that
# fires on ordinary sentences teaches the reader to ignore it, which is worse
# than the prose it guards against — so where a pattern could not be made
# precise, it was made narrow.
BUILTIN = [
    (
        "issue-references",
        # Two or more digits, and not the six-digit shape of a hex colour.
        # `#1` is as likely to be "priority #1" as an issue reference.
        r"(?<![\w/#])#(?!\d{6}\b)\d{2,}\b",
        "an issue or PR number. The reader did not file it and cannot see it; "
        "say what it was about.",
    ),
    (
        "repo-paths",
        r"(?<![\w/`@])(?:[\w.-]+/){1,}[\w.-]+\.(?:py|js|ts|tsx|sh|md|json|ya?ml|toml|rs|go|rb|java|c|h|cpp)\b",
        "a repository-relative file path. Unless the reader is being asked to "
        "open it, it is a fact about how the work was done.",
    ),
    (
        "not-x-but-y",
        # No comma before `but`. With one this matched every contrastive clause
        # in English — "it is not clear, but we can check" — which is a comma
        # splice, not the construction.
        r"\b(?:is|was|are|were|it\s+is|that\s+is)\s+not\s+(?:just\s+|merely\s+|only\s+)?[^,.;]{1,40}\s+but\s+",
        "the not-X-but-Y contrast. Say Y.",
    ),
    (
        "staged-emphasis",
        # Abstract nouns only. A bare \w+ matched "the key file is missing" and
        # "the real problem is solved", which are ordinary sentences.
        r"\bthe\s+(?:key|real|deeper|crucial|central|underlying|fundamental)\s+"
        # problem and issue are deliberately absent: "the real problem is solved"
        # is a statement of fact, and no pattern can tell it from the tic.
        r"(?:insight|point|thing|question|difference|takeaway|reason|lesson)\s+"
        r"(?:is|was|here)\b",
        "staged emphasis. If it is the important one, it can be stated first "
        "without the drum roll.",
    ),
    (
        "gated-compounds",
        # flag-gated, rate-gated and time-gated are established vocabulary, and
        # a load-bearing wall is a wall.
        r"\b(?!flag-|rate-|feature-|time-|token-)[\w]+-gated\b"
        r"|(?<!wall is )(?<!walls are )(?<!beam is )(?<!column is )\bload-bearing\b(?!\s+(?:wall|walls|beam|column|structure))",
        "a coined compound. Say what it does.",
    ),
    (
        "surface-as-noun",
        # A positive list. "attack surface", "API surface" and "drawing surface"
        # are terms of art, and an exclusion list is always one legitimate
        # compound behind.
        r"\bthe\s+(?:review|blast|decision|ownership|failure|execution|config(?:uration)?)\s+surface\b",
        "\"surface\" used as a noun for a component.",
    ),
]
BUILTIN_NAMES = {name for name, _, _ in BUILTIN}

notes = []

try:
    selected = json.loads(selected_raw) if selected_raw not in ("", "null") else None
except (ValueError, TypeError):
    selected = None

if selected is not None and not isinstance(selected, list):
    # Falling back to "all patterns" would widen a check whose author was trying
    # to narrow it — the wrong direction for something this cautious.
    print(json.dumps({"note": "replyStyle.constructions must be an array; the check was skipped."}))
    sys.exit(0)

patterns = []
for name, rx, advice in BUILTIN:
    if selected is None or name in selected:
        patterns.append((name, rx, advice))

if isinstance(selected, list):
    unknown = [str(n) for n in selected if n not in BUILTIN_NAMES]
    if unknown:
        notes.append("replyStyle.constructions names nothing known: " + ", ".join(unknown[:5]))

# Project-specific additions. A bad regex is the project's to fix, but it must
# not take the hook down with it.
try:
    extra = json.loads(extra_raw) if extra_raw not in ("", "null") else []
except (ValueError, TypeError):
    extra = []
if isinstance(extra, list):
    for item in extra[:20]:
        if not isinstance(item, dict):
            continue
        rx = item.get("pattern")
        if not isinstance(rx, str) or not rx or len(rx) > 200:
            continue
        try:
            re.compile(rx)
        except re.error:
            continue
        patterns.append((str(item.get("name") or "custom")[:40], rx,
                         str(item.get("advice") or "a construction this project asked to avoid.")[:200]))

if not patterns:
    if notes:
        print(json.dumps({"note": " ".join(notes)}))
    sys.exit(0)

# --- the final assistant text ------------------------------------------------
# Only the last assistant message, and only its text: tool calls and their
# output are not prose the user reads. A sidechain record belongs to a subagent,
# whose text the user never sees either.
last_text = None
try:
    with open(transcript, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or not line.startswith("{"):
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") != "assistant" or rec.get("isSidechain"):
                continue
            msg = rec.get("message") or {}
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            parts = []
            if isinstance(content, str):
                parts.append(content)
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        t = block.get("text")
                        if isinstance(t, str):
                            parts.append(t)
            text = "\n".join(p for p in parts if p.strip())
            if text.strip():
                last_text = text
except OSError:
    sys.exit(0)

if not last_text:
    sys.exit(0)


def _blank(m):
    # Replaced by the newlines it consumed, so the line numbers reported below
    # still point at the right line. Collapsing a fence to a single space made
    # every number after the first code block wrong.
    return "\n" * m.group(0).count("\n")


prose = re.sub(r"```.*?```", _blank, last_text, flags=re.S)
# An unterminated fence is still code. Leaving it as prose scans a code block,
# which is dense in exactly the things this checks for.
prose = re.sub(r"```.*\Z", _blank, prose, flags=re.S)
prose = re.sub(r"`[^`\n]*`", " ", prose)
# A URL is being shown to the reader, not described to them.
prose = re.sub(r"https?://\S+", " ", prose)

# A path the reader is being told to open is an instruction, not process noise.
# The verb has to sit just before the path: searched across the whole line, a
# "see" or "run" anywhere in a markdown paragraph silenced every path in it.
OPEN_HINT = re.compile(
    r"\b(?:open|read|see|edit|run|execute|inspect|review|check|visit|copy|paste)\w*\s+"
    r"(?:the\s+|a\s+|at\s+|in\s+)?$", re.I)

hits = []
for name, rx, advice in patterns:
    try:
        matcher = re.compile(rx, re.I)
    except re.error:
        continue
    for m in matcher.finditer(prose):
        line_no = prose.count("\n", 0, m.start()) + 1
        line_start = prose.rfind("\n", 0, m.start()) + 1
        line_end = prose.find("\n", m.end())
        line = prose[line_start: line_end if line_end != -1 else len(prose)].strip()
        if name == "repo-paths":
            before = prose[line_start:m.start()][-40:]
            if OPEN_HINT.search(before):
                continue
        hits.append((name, line_no, m.group(0).strip()[:60], advice, line[:100]))
        if len(hits) >= 12:
            break
    if len(hits) >= 12:
        break

if not hits:
    if notes:
        print(json.dumps({"note": " ".join(notes)}))
    sys.exit(0)

lines = ["flow: reply-style check — %d construction%s in the reply just written:"
         % (len(hits), "" if len(hits) == 1 else "s")]
seen_advice = set()
for name, line_no, frag, advice, line in hits:
    lines.append("  line %d: %s — \"%s\"" % (line_no, name, frag))
    if name not in seen_advice:
        lines.append("      %s" % advice)
        seen_advice.add(name)
lines.extend("  " + n for n in notes)
lines.append("  (warning only; nothing was blocked. Configure under replyStyle in .claude/settings.flow.json.)")
print(json.dumps({"findings": "\n".join(lines)}))
PYTHON

RESULT=$(_rsc_run_with_limit "$SCRIPT" "$TRANSCRIPT" "$SELECTED" "$EXTRA") || RESULT=""
rm -f "$SCRIPT"
[ -n "$RESULT" ] || exit 0

# `systemMessage` is the field a Stop hook has for saying something. No
# `decision`: a second Stop hook answering "approve" could override the FlowGoal
# hook's "block", and a style note has no business doing that.
MESSAGE=$(printf '%s' "$RESULT" | jq -r '.findings // .note // empty' 2>/dev/null)
[ -n "$MESSAGE" ] || exit 0

printf '%s' "$MESSAGE" | jq -Rs '{systemMessage: .}' 2>/dev/null || true
# Also on stderr, where it appears in the debug log beside the hook that made it.
printf '%s\n' "$MESSAGE" >&2
exit 0
