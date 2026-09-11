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
# constructions, names where each appeared, and warns. It never blocks: a false
# positive that stops a reply is worse than the prose it was guarding against.
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
# `constructions` selects from the built-in set; omit it for the conservative
# default. `extraPatterns` adds project-specific ones. Setting `constructions`
# to [] with no extraPatterns disables every check while leaving the hook on,
# which is a legitimate way to say "only my own patterns matter".
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

# Everything user-controlled travels via argv or stdin, never interpolated.
FINDINGS=$(python3 - "$TRANSCRIPT" "$SELECTED" "$EXTRA" <<'PYTHON'
import json
import re
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]

transcript, selected_raw, extra_raw = sys.argv[1], sys.argv[2], sys.argv[3]

# --- the built-in list -------------------------------------------------------
# Each entry is (name, regex, what to say). The wording matters more than the
# match: a warning that only says "you did the thing" teaches nothing.
BUILTIN = [
    (
        "issue-references",
        r"(?<![\w/#])#\d+\b",
        "an issue or PR number. The reader did not file it and cannot see it; "
        "say what it was about.",
    ),
    (
        "repo-paths",
        r"(?<![\w/`])(?:[\w.-]+/){1,}[\w.-]+\.(?:py|js|ts|tsx|sh|md|json|ya?ml|toml|rs|go|rb|java|c|h|cpp)\b",
        "a repository-relative file path. Unless the reader is being asked to "
        "open it, it is a fact about how the work was done.",
    ),
    (
        "not-x-but-y",
        r"\b(?:is|was|are|were|it\s+is|that\s+is)\s+not\s+(?:just\s+|merely\s+|only\s+)?[^,.;]{1,40},?\s+but\s+",
        "the not-X-but-Y contrast. Say Y.",
    ),
    (
        "staged-emphasis",
        r"\bthe\s+(?:key|real|deeper|crucial|central|underlying|fundamental)\s+\w+\s+(?:is|was|here)\b",
        "staged emphasis. If it is the important one, it can be stated first "
        "without the drum roll.",
    ),
    (
        "gated-compounds",
        r"\b[\w-]+-gated\b|\bload-bearing\b",
        "a coined compound. Say what it does.",
    ),
    (
        "surface-as-noun",
        r"\b(?:the|a|every|each|this|that)\s+(?:\w+\s+)?surface\b(?!\s+(?:of|area))",
        "\"surface\" used as a noun for a component.",
    ),
]

try:
    selected = json.loads(selected_raw) if selected_raw not in ("", "null") else None
except (ValueError, TypeError):
    selected = None
if not isinstance(selected, list):
    selected = None

patterns = []
for name, rx, advice in BUILTIN:
    if selected is None or name in selected:
        patterns.append((name, rx, advice))

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
    sys.exit(0)

# --- the final assistant text ------------------------------------------------
# Only the last assistant message, and only its text: tool calls and their
# output are not prose the user reads. A transcript is JSONL, one record per
# line, and the last assistant record is the reply that was just written.
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
            if rec.get("type") != "assistant":
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

# Fenced code and inline code are not prose. A path inside backticks is usually
# the reader being shown a thing to run or open, which the issue says explicitly
# must not be flagged.
prose = re.sub(r"```.*?```", " ", last_text, flags=re.S)
prose = re.sub(r"`[^`\n]*`", " ", prose)

# A path the reader is being asked to open is not process noise. Suppress the
# path check for a line that tells them to do something with it.
# Instructional verbs only. An earlier version also listed "in" and "at", which
# are prepositions that appear in almost any sentence — "the bug lived in
# plugins/flow/x.sh" was suppressed, which is precisely the sentence this check
# exists for.
OPEN_HINT = re.compile(
    r"\b(?:open|read|see|edit|run|execute|inspect|review|visit|copy|paste)\b"
    r"|\blook\s+at\b|\bhave\s+a\s+look\b", re.I)

hits = []
for name, rx, advice in patterns:
    # Case-insensitive throughout. A sentence-initial "The key insight is"
    # is the same construction as a mid-sentence one, and a case-sensitive
    # pattern missed exactly that.
    try:
        matcher = re.compile(rx, re.I)
    except re.error:
        continue
    for m in matcher.finditer(prose):
        line_no = prose.count("\n", 0, m.start()) + 1
        line_start = prose.rfind("\n", 0, m.start()) + 1
        line_end = prose.find("\n", m.end())
        line = prose[line_start: line_end if line_end != -1 else len(prose)].strip()
        if name == "repo-paths" and OPEN_HINT.search(line):
            continue
        hits.append((name, line_no, m.group(0).strip()[:60], advice, line[:100]))
        if len(hits) >= 12:
            break
    if len(hits) >= 12:
        break

if not hits:
    sys.exit(0)

print("flow: reply-style check — %d construction%s in the reply just written:"
      % (len(hits), "" if len(hits) == 1 else "s"))
seen_advice = set()
for name, line_no, frag, advice, line in hits:
    print("  line %d: %s — \"%s\"" % (line_no, name, frag))
    if name not in seen_advice:
        print("      %s" % advice)
        seen_advice.add(name)
print("  (warning only; nothing was blocked. Configure under replyStyle in .claude/settings.flow.json.)")
PYTHON
) || exit 0

# Warn, never block. The Stop hook contract treats a non-zero exit as a failure
# and "decision":"block" as a reason to keep working; this emits neither.
if [ -n "$FINDINGS" ]; then
  printf '%s\n' "$FINDINGS" >&2
fi
exit 0
