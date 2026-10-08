---
description: "Analyze the decision journal and session transcripts for learnable patterns and generate skill or enforcement proposals from repeated user corrections and common patterns. Use when reviewing session activity to extract reusable knowledge."
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Learn from Decisions

Analyze the decision journal and the session transcripts for recurring patterns and generate skill proposals.

The journal and run ledgers only contain what flow wrote about itself. The corrections a user actually made ("that's not what I asked", "I opened it and it is empty", "why didn't you run the tests?") live in the Claude Code session transcripts, so Phase 1 mines those too.

## Required Skills

_None — retrospective pattern analysis over the decision journal and transcripts. No skill invocations._

## Phase 1: Gather Journal Entries

```!
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

printf '%s\n' "### Resolved Paths"
# JOURNAL_DIR resolves through bin/journal-dir.sh, as every journal writer
# resolves it; PROPOSAL_DIR via the standard settings cascade.
# settings.json may store paths with a leading `~` (literal — JSON has no
# tilde-expansion semantics). The cascade helper returns the value verbatim
# without expansion, so downstream tools that do not auto-expand tildes
# (Read/Write/Edit, Python os.path) would fail. Manually expand `~` to
# the home of the user so the agent always receives an absolute path. The home is
# the one cascade-resolve.sh --user-home gives: a HOME the repository sets
# does not choose where proposals go.
HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
USER_HOME=""
# The home comes from a resolver outside the repository (the lookup skips any
# copy inside it): a copy the repository ships must not say where it is.
# USER_FILES_BEGIN
USER_HELPER="$(__t=$(git rev-parse --show-toplevel 2>/dev/null);__x=0;[ -z "$__t" ]||{ __t=$(cd "$__t" 2>/dev/null&&pwd -P);[ -n "$__t" ]||__x=1; };[ "$__x" = 1 ]||{ printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-}";ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do __p=${__p%/};[ -n "$__p" ]&&[ -x "$__p/bin/cascade-resolve.sh" ]||continue;__r=$(cd "$__p" 2>/dev/null&&pwd -P)||continue;[ -n "$__r" ]||continue;[ -z "$__t" ]||{ __d=$__r;__in=0;while :;do [ "$__d" -ef "$__t" ]&&{ __in=1;break; };[ "$__d" = / ]&&break;__d=$(dirname "$__d");done;[ "$__in" = 1 ]&&continue; };printf '%s\n' "$__r";break;done)/bin/cascade-resolve.sh"
# USER_FILES_END
[ -x "$USER_HELPER" ] && USER_HOME=$("$USER_HELPER" --user-home 2>/dev/null)
case "$USER_HOME" in /*) ;; *) USER_HOME=/nonexistent ;; esac
PROPOSAL_DIR="$USER_HOME/.claude/flow-proposals"
if [ -x "$HELPER" ]; then
  # Both values are printed below as `KEY=value` lines, and
  # .claude/settings.flow.json is a tracked file, so a fork pull request chooses
  # them. cascade-resolve.sh refuses a value carrying a newline by default —
  # without that, one in journal.dir closed the JOURNAL_DIR= line and opened a
  # forged `### Dismissal Artifacts` section above the real one.
  JOURNAL_DIR=$("${HELPER%/cascade-resolve.sh}/journal-dir.sh")
  [ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
  # Proposals are written where this names, so only the user settings file
  # and the plugin default may name it: a repository setting could aim them
  # at any directory the user can write. USER_HELPER, defined above, skips
  # any copy of the resolver inside the repository, as the review command
  # finds its own: a copy the repository ships must not answer this.
  if [ -x "$USER_HELPER" ] && __pd=$("$USER_HELPER" --no-repo-settings --default "$USER_HOME/.claude/flow-proposals" '.learning.proposalDir // empty'); then
    PROPOSAL_DIR=$__pd
  else
    printf '%s\n' "WARN=learning.proposalDir could not be read from the user settings (no installed flow outside this repository answered); using the default"
  fi
  printf '%s\n' "STATE=ok"
else
  # Helper missing or non-executable — using compile-time defaults. Surface
  # so the agent knows resolution was best-effort and config might be ignored.
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "ERROR=cascade-resolve.sh missing or non-executable; using built-in defaults"
fi
# Expand leading `~` to the home of the user so downstream Read/Write/Edit tools
# (which do not tilde-expand) receive absolute paths.
JOURNAL_DIR="${JOURNAL_DIR/#\~/$USER_HOME}"
PROPOSAL_DIR="${PROPOSAL_DIR/#\~/$USER_HOME}"
# A relative value would resolve inside the working directory, the repository.
case "$PROPOSAL_DIR" in
  /*) ;;
  *) printf '%s\n' "WARN=learning.proposalDir is not an absolute path or one under ~; using the default"
     PROPOSAL_DIR="$USER_HOME/.claude/flow-proposals" ;;
esac
printf '%s\n' "JOURNAL_DIR=$JOURNAL_DIR"
printf '%s\n' "PROPOSAL_DIR=$PROPOSAL_DIR"

printf '%s\n' ""
printf '%s\n' "### Journal Files"
JOURNAL_FILES=0
[ -d "$JOURNAL_DIR" ] && JOURNAL_FILES=$(ls "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
printf '%s\n' "JOURNAL_FILE_COUNT=$JOURNAL_FILES"
if [ "$JOURNAL_FILES" = "0" ]; then
  printf '%s\n' "STATE=empty"
else
  ls "$JOURNAL_DIR"/*.md 2>/dev/null | sed 's/^/JOURNAL_FILE=/'
fi

printf '%s\n' ""
printf '%s\n' "### Proposal Files"
PROPOSAL_FILES=0
[ -d "$PROPOSAL_DIR" ] && PROPOSAL_FILES=$(ls "$PROPOSAL_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
printf '%s\n' "PROPOSAL_FILE_COUNT=$PROPOSAL_FILES"
if [ "$PROPOSAL_FILES" = "0" ]; then
  printf '%s\n' "STATE=empty"
else
  ls "$PROPOSAL_DIR"/*.md 2>/dev/null | sed 's/^/PROPOSAL_FILE=/'
fi

# Section: FlowRun Events + FlowGoals (v3)
# Gated behind flow.goals.enabled — when v3 is enabled, surface the goal
# YAMLs + run-event ledgers so the Phase 2 Goal Failure Patterns can detect
# recurring failed ACs, stuck-detection hits, and not_executed warnings.
printf '%s\n' ""
printf '%s\n' "### FlowRun Events"
GOALS_ENABLED="false"
[ -x "$HELPER" ] && GOALS_ENABLED=$("$HELPER" --default "true" '.flow.goals.enabled' 2>/dev/null)
if [ "$GOALS_ENABLED" != "true" ]; then
  printf '%s\n' "STATE=disabled"
else
  # No goal is read through a symlink. A repository can commit .flow or
  # .flow/goals, or a goal file, as a symlink to something outside the
  # checkout, and a goal read there belongs to the target of the link.
  # flow-mkdir.sh --check is the rule every flow writer applies below the
  # repository; a refusal is said on stderr and no goal file is listed. A
  # check that cannot run (exit 3: python3 missing) is not a refusal and not
  # an empty directory: the section is then unavailable.
  GOAL_FILES=0
  GOAL_LIST=""
  LEARN_UNCHECKED=""
  GOAL_DIR_RC=0
  GOAL_DIR_ERR=$("${HELPER%/cascade-resolve.sh}/flow-mkdir.sh" --check -- .flow/goals 2>&1) || GOAL_DIR_RC=$?
  GOAL_DIR_ERR=${GOAL_DIR_ERR#flow-mkdir.sh: }
  # A Windows python3 ends the line in \r\n, which $(...) keeps the \r of.
  GOAL_DIR_ERR=${GOAL_DIR_ERR%$'\r'}
  if [ "$GOAL_DIR_RC" -eq 0 ]; then
    if [ -d ".flow/goals" ]; then
      GOAL_LIST=$(find .flow/goals -maxdepth 1 -name '*.goal.yaml' ! -type l 2>/dev/null | LC_ALL=C sort)
      find .flow/goals -maxdepth 1 -name '*.goal.yaml' -type l 2>/dev/null | LC_ALL=C sort |
        while IFS= read -r GOAL_LINK; do
          printf 'refusing — %s is a symlink; goals are not read through it\n' "$GOAL_LINK" >&2
        done
    fi
  elif [ "$GOAL_DIR_RC" -eq 2 ]; then
    printf '%s; goals are not read through it\n' "${GOAL_DIR_ERR%"; nothing is written under it"}" >&2
  else
    LEARN_UNCHECKED=$(printf '%s' "$GOAL_DIR_ERR" | head -1 | LC_ALL=C tr -d '\n' | LC_ALL=C tr '\000-\037\177' ' ')
  fi
  [ -n "$GOAL_LIST" ] && GOAL_FILES=$(printf '%s\n' "$GOAL_LIST" | wc -l | tr -d ' ')
  # No run is read through a symlink either: .flow, .flow/runs or a run
  # directory committed as one belongs to the target of the link. A refused
  # run is left out, with a note on stderr.
  RUN_FILES=0
  RUN_LIST=""
  VERDICT_LIST=""
  RUN_DIR_RC=0
  RUN_DIR_ERR=$("${HELPER%/cascade-resolve.sh}/flow-mkdir.sh" --check -- .flow/runs 2>&1) || RUN_DIR_RC=$?
  RUN_DIR_ERR=${RUN_DIR_ERR#flow-mkdir.sh: }
  RUN_DIR_ERR=${RUN_DIR_ERR%$'\r'}
  if [ "$RUN_DIR_RC" -eq 0 ]; then
    if [ -d ".flow/runs" ]; then
      find .flow/runs -mindepth 1 -maxdepth 1 -type l 2>/dev/null | LC_ALL=C sort |
        while IFS= read -r RUN_LINK; do
          printf 'refusing — %s is a symlink; runs are not read through it\n' "$RUN_LINK" >&2
        done
      RUN_LIST=$(find .flow/runs -name "events.jsonl" ! -type l 2>/dev/null | LC_ALL=C sort)
      # The last verdict of each run, for the stuck-detection pattern, listed the same
      # way: never one that is a symlink.
      VERDICT_LIST=$(find .flow/runs -name "last-verdict.json" ! -type l 2>/dev/null | LC_ALL=C sort)
    fi
  elif [ "$RUN_DIR_RC" -eq 2 ]; then
    printf '%s; runs are not read through it\n' "${RUN_DIR_ERR%"; nothing is written under it"}" >&2
  elif [ -z "$LEARN_UNCHECKED" ]; then
    LEARN_UNCHECKED=$(printf '%s' "$RUN_DIR_ERR" | head -1 | LC_ALL=C tr -d '\n' | LC_ALL=C tr '\000-\037\177' ' ')
  fi
  [ -n "$RUN_LIST" ] && RUN_FILES=$(printf '%s\n' "$RUN_LIST" | wc -l | tr -d ' ')
  if [ -n "$LEARN_UNCHECKED" ]; then
    printf '%s\n' "STATE=unavailable"
    printf '%s\n' "REASON=$LEARN_UNCHECKED, so which goal files and run events can be read is unknown"
  else
    printf '%s\n' "GOAL_FILE_COUNT=$GOAL_FILES"
    printf '%s\n' "RUN_EVENT_FILE_COUNT=$RUN_FILES"
    if [ "$GOAL_FILES" = "0" ] && [ "$RUN_FILES" = "0" ]; then
      printf '%s\n' "STATE=empty"
    else
      printf '%s\n' "STATE=ok"
      [ -n "$GOAL_LIST" ] && printf '%s\n' "$GOAL_LIST" | sed 's/^/GOAL_FILE=/'
      [ -n "$RUN_LIST" ] && printf '%s\n' "$RUN_LIST" | sed 's/^/RUN_EVENTS=/'
      [ -n "$VERDICT_LIST" ] && printf '%s\n' "$VERDICT_LIST" | sed 's/^/RUN_VERDICT=/'
    fi
  fi
fi

# Section: Transcript Corrections
# TRANSCRIPT_CORRECTIONS_BLOCK_BEGIN
# learning.sources (JSON array, default ["journal","transcripts"]) selects the
# evidence sources this command reads. Session transcripts are the Claude Code
# own logs under <config>/projects/<slug>/, <config> being $CLAUDE_CONFIG_DIR when you set it, or
# ~/.claude (override: learning.transcriptDir,
# empty = auto) — read-only, user-scoped, never written here. The miner keeps
# recall-oriented candidates; Phase 2 does the judging.
printf '%s\n' ""
printf '%s\n' "### Transcript Corrections"
LEARN_SOURCES='["journal","transcripts"]'
[ -x "$HELPER" ] && LEARN_SOURCES=$("$HELPER" --compact --default '["journal","transcripts"]' '.learning.sources // empty' 2>/dev/null)
printf '%s\n' "TRANSCRIPT_SOURCES=$LEARN_SOURCES"
TRANSCRIPTS_ON="false"
if command -v jq >/dev/null 2>&1; then
  TRANSCRIPTS_ON=$(printf '%s' "$LEARN_SOURCES" | jq -r 'type == "array" and any(.[]; . == "transcripts")' 2>/dev/null)
else
  case "$LEARN_SOURCES" in *transcripts*) TRANSCRIPTS_ON="true" ;; esac
fi
MINER="$(dirname "$HELPER")/flow-mine-corrections.sh"
TRANSCRIPT_DIR_SETTING=""
# Only the user settings file and the plugin default may name the transcript
# directory: a repository setting could point the miner at transcripts it
# ships. A value that is not absolute after ~ is expanded is not used.
# USER_FILES_BEGIN
USER_HELPER="$(__t=$(git rev-parse --show-toplevel 2>/dev/null);__x=0;[ -z "$__t" ]||{ __t=$(cd "$__t" 2>/dev/null&&pwd -P);[ -n "$__t" ]||__x=1; };[ "$__x" = 1 ]||{ printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-}";ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do __p=${__p%/};[ -n "$__p" ]&&[ -x "$__p/bin/cascade-resolve.sh" ]||continue;__r=$(cd "$__p" 2>/dev/null&&pwd -P)||continue;[ -n "$__r" ]||continue;[ -z "$__t" ]||{ __d=$__r;__in=0;while :;do [ "$__d" -ef "$__t" ]&&{ __in=1;break; };[ "$__d" = / ]&&break;__d=$(dirname "$__d");done;[ "$__in" = 1 ]&&continue; };printf '%s\n' "$__r";break;done)/bin/cascade-resolve.sh"
# USER_FILES_END
if [ -x "$USER_HELPER" ]; then
  TRANSCRIPT_DIR_SETTING=$("$USER_HELPER" --no-repo-settings --default "" '.learning.transcriptDir // empty') ||
    { TRANSCRIPT_DIR_SETTING=""; printf '%s\n' "WARN=learning.transcriptDir could not be read from the user settings; using the default roots"; }
else
  printf '%s\n' "WARN=learning.transcriptDir could not be read from the user settings (no installed flow outside this repository answered); using the default roots"
fi
USER_HOME=""
[ -x "$USER_HELPER" ] && USER_HOME=$("$USER_HELPER" --user-home 2>/dev/null)
case "$USER_HOME" in /*) ;; *) USER_HOME=/nonexistent ;; esac
TRANSCRIPT_DIR_SETTING="${TRANSCRIPT_DIR_SETTING/#\~/$USER_HOME}"
case "$TRANSCRIPT_DIR_SETTING" in
  /*|'') ;;
  *) printf '%s\n' "WARN=learning.transcriptDir is not an absolute path or one under ~; using the default roots"
     TRANSCRIPT_DIR_SETTING="" ;;
esac
if [ "$TRANSCRIPTS_ON" != "true" ]; then
  printf '%s\n' "TRANSCRIPT_STATE=disabled"
  printf '%s\n' "CANDIDATE_COUNT=0"
elif [ ! -x "$MINER" ]; then
  printf '%s\n' "TRANSCRIPT_STATE=missing"
  printf '%s\n' "ERROR=flow-mine-corrections.sh missing or non-executable next to cascade-resolve.sh"
  printf '%s\n' "CANDIDATE_COUNT=0"
else
  if [ -n "$TRANSCRIPT_DIR_SETTING" ]; then
    MINER_OUT=$("$MINER" --format markdown --max-sessions 50 --transcript-dir "$TRANSCRIPT_DIR_SETTING" 2>/dev/null)
  else
    MINER_OUT=$("$MINER" --format markdown --max-sessions 50 2>/dev/null)
  fi
  # System One screening (site learn.correction, references/system-one.md).
  # The state sent for each candidate is the user turn as typed (up to 600
  # characters) and the first 300 characters of the last assistant message
  # before it. Nothing in that text is removed or replaced first: a key or
  # password typed into the turn is sent with it. With provider typesafe it
  # goes to the TypeSafe hosted API, with custom (or imajev at an address off
  # this machine) to the server at baseUrl, and with imajev at its default
  # local address it stays on this machine. The mode comes from
  # flow-s1-mode.sh, the one place that applies the mode rule: a repository
  # can lower the mode set in the user settings or the plugin default, but
  # never start the sending, and with no provider configured the site is off.
  # The screening runs the miner again with --format jsonl and asks about each
  # candidate; the miner itself sends nothing. That miner, flow-s1-mode.sh,
  # flow-s1.sh and the screener all come from the installed copy of the plugin
  # outside the repository, so code the repository ships never chooses the
  # text that is sent. Only when at least one candidate was answered, which
  # happens in on mode alone, does it print the section again with the rows
  # reordered (rated corrections first, then unanswered, then rated
  # non-corrections) and four S1_ lines. Otherwise, in shadow mode or when no
  # call answered, the section below prints what the miner printed; a fault in
  # the screener adds one WARN= line. The screener runs in the background and
  # this shell waits for it, so a TERM, INT or HUP stops it (and the call it
  # has in progress) and removes the temporary files, which hold transcript
  # text, before the shell exits.
  LEARN_S1_MODE=off
  LEARN_S1_BIN="$(dirname "$USER_HELPER")"
  if [ -n "$MINER_OUT" ] && [ -x "$USER_HELPER" ] && [ -x "$LEARN_S1_BIN/flow-s1-mode.sh" ] && [ -x "$LEARN_S1_BIN/flow-s1.sh" ] && [ -x "$LEARN_S1_BIN/flow-mine-corrections.sh" ] && [ -f "$LEARN_S1_BIN/_flow_learn_s1.py" ] && command -v python3 >/dev/null 2>&1; then
    LEARN_S1_MODE=$("$LEARN_S1_BIN/flow-s1-mode.sh" learn.correction 2>/dev/null) || LEARN_S1_MODE=off
  fi
  case "$LEARN_S1_MODE" in
    shadow|on)
      LEARN_S1_TMP=""
      LEARN_S1_PID=""
      _learn_s1_clean() {
        if [ -n "$LEARN_S1_PID" ]; then
          kill -TERM "$LEARN_S1_PID" 2>/dev/null
          wait "$LEARN_S1_PID" 2>/dev/null
          LEARN_S1_PID=""
        fi
        [ -n "$LEARN_S1_TMP" ] && { rm "$LEARN_S1_TMP/table.md" "$LEARN_S1_TMP/out" "$LEARN_S1_TMP/err" 2>/dev/null; rmdir "$LEARN_S1_TMP" 2>/dev/null; }
      }
      trap '_learn_s1_clean; exit 129' HUP
      trap '_learn_s1_clean; exit 130' INT
      trap '_learn_s1_clean; exit 143' TERM
      # A template, so TMPDIR is used on macOS too: mktemp -d alone ignores it
      # there.
      LEARN_S1_TMP=$(mktemp -d "${TMPDIR:-/tmp}/flow-learn-s1.XXXXXX" 2>/dev/null) || LEARN_S1_TMP=""
      if [ -n "$LEARN_S1_TMP" ] && printf '%s' "$MINER_OUT" > "$LEARN_S1_TMP/table.md" 2>/dev/null; then
        PYTHONSAFEPATH=1 python3 "$LEARN_S1_BIN/_flow_learn_s1.py" screen --table "$LEARN_S1_TMP/table.md" --miner "$LEARN_S1_BIN/flow-mine-corrections.sh" --flow-s1 "$LEARN_S1_BIN/flow-s1.sh" --transcript-dir "$TRANSCRIPT_DIR_SETTING" > "$LEARN_S1_TMP/out" 2> "$LEARN_S1_TMP/err" &
        LEARN_S1_PID=$!
        wait "$LEARN_S1_PID"
        LEARN_S1_RC=$?
        LEARN_S1_PID=""
        # Only the exception type the screener names is printed, never other
        # text from its stderr.
        LEARN_S1_FAIL=$(sed -n 's/^flow-learn-s1: WARN: screening failed: \([A-Za-z0-9_]\{1,64\}\)$/\1/p' "$LEARN_S1_TMP/err" 2>/dev/null | head -n 1)
        [ -n "$LEARN_S1_FAIL" ] || [ "$LEARN_S1_RC" -eq 0 ] || LEARN_S1_FAIL="exit $LEARN_S1_RC"
        # The screener's output replaces the miner's only when it exited 0 and
        # named no fault: a run that failed part way through its write leaves
        # a table with rows missing.
        if [ -z "$LEARN_S1_FAIL" ]; then
          LEARN_S1_OUT=$(cat "$LEARN_S1_TMP/out" 2>/dev/null) || LEARN_S1_OUT=""
          [ -n "$LEARN_S1_OUT" ] && MINER_OUT=$LEARN_S1_OUT
        else
          printf '%s\n' "WARN=System One screening failed ($LEARN_S1_FAIL); the candidates are in the miner's order"
        fi
      fi
      _learn_s1_clean
      trap - HUP INT TERM
      ;;
  esac
  case "$MINER_OUT" in
    *TRANSCRIPT_DIR_STATE=ok*) printf '%s\n' "TRANSCRIPT_STATE=ok" ;;
    *) printf '%s\n' "TRANSCRIPT_STATE=missing" ;;
  esac
  if [ -n "$MINER_OUT" ]; then
    printf '%s\n' "$MINER_OUT"
  else
    printf '%s\n' "ERROR=flow-mine-corrections.sh produced no output"
    printf '%s\n' "CANDIDATE_COUNT=0"
  fi
fi
# TRANSCRIPT_CORRECTIONS_BLOCK_END

# Section: Dismissal Artifacts
printf '%s\n' ""
printf '%s\n' "### Dismissal Artifacts"
# DISMISSAL_ARTIFACTS_BLOCK_BEGIN
# Findings the team rejected. `review.md` has written `dropped-finding`
# artifacts since it was added, with a comment saying it does so "so /flow:learn
# can detect repeated drop reasons across cycles" — and nothing here read them.
# This is the first category that reads the journal manifest rather than the
# freeform body.
#
# The two types are different records and both matter: `dropped-finding` says a
# finding did not survive the review machinery, `finding-dismissed` says a human
# rejected it on stated grounds. Only the second is evidence for an exception,
# so they are counted apart.
DISMISSAL_JOURNAL_DIR="${JOURNAL_DIR:-.decisions}"
# The reader is bin/_journal_manifest.py, shared with the DISPUTED_ARRAY_BLOCK
# in address.md and taking its fence predicate from bin/_journal_atomic.py.
# Resolved the same way every other helper in this command is.
# No apostrophes in these comments: this is an inline-! block, and an unpaired
# one kills the whole block on the Windows executor.
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")"
# Probed for the same reason PyYAML is below: the import sits above the first
# print, so on an install where the reader is missing this block would die
# before emitting any STATE line — and a missing STATE line reads exactly like
# a project that has dismissed nothing.
if [ ! -f "$FLOW_ROOT/bin/_journal_manifest.py" ]; then
  printf '%s\n' "DISMISSED_COUNT=0"
  printf '%s\n' "DROPPED_COUNT=0"
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=the shared journal reader could not be located, so whether this project has recorded dismissals is unknown"
else
# Probe before the heredoc. `import yaml` sits above the try below, so a machine
# without PyYAML dies before the first print and the section is a bare heading —
# no STATE line at all, which Phase 2 reads as "this project has dismissed
# nothing". Every sibling block in start.md and status.md probes first.
if ! command -v python3 >/dev/null 2>&1 || \
     ! PYTHONSAFEPATH=1 python3 -c 'import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; import yaml' >/dev/null 2>&1; then
  printf '%s\n' "DISMISSED_COUNT=0"
  printf '%s\n' "DROPPED_COUNT=0"
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=python3 with PyYAML is required to read the journal manifests, so whether this project has recorded dismissals is unknown"
else
DISMISSAL_OUT=$(PYTHONSAFEPATH=1 python3 - "$FLOW_ROOT/bin" "$DISMISSAL_JOURNAL_DIR" <<'DISMISSAL_PY'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import sys

# The reader lives in the bin/ directory of the plugin, and takes its fence
# predicate from bin/_journal_atomic.py — the module every journal write goes
# through. This block used to carry its own copy. The copies drifted every
# review round: this one never gained the O_NONBLOCK that stops a FIFO in the
# journal directory hanging the read forever, and the comment here claimed the
# sibling reader "opens the same way" while the two had already diverged.
sys.path.insert(0, sys.argv[1])

import errno
import os

from _journal_manifest import ManifestError, one_line, read_artifacts

journal_dir = sys.argv[2]

if not os.path.isdir(journal_dir):
    # A directory that is not there is not a project with no dismissals. The
    # journal dir comes from the settings cascade and falls back to a RELATIVE
    # .decisions, so running from a subdirectory reproduces this.
    print("DISMISSED_COUNT=0")
    print("DROPPED_COUNT=0")
    print("STATE=unavailable")
    # Through one_line: journal.dir is read from .claude/settings.flow.json, a
    # tracked file, so a fork pull request chooses this string.
    print("REASON=the journal directory %s does not exist, so whether this project has "
          "recorded dismissals is unknown" % one_line(journal_dir))
    sys.exit(0)

dismissed = []
dropped = []
unreadable = []

# os.listdir, not glob. Two reasons, both the same defect class this issue
# exists to remove — an unreadable input answering like a legitimately absent
# one:
#
#   1. glob SWALLOWS the OSError from a directory it cannot read, returning an
#      empty list. A directory holding recorded dismissals that the process may
#      not list therefore reported DISMISSED_COUNT=0 / STATE=empty, byte for
#      byte what a project with nothing recorded reports.
#   2. glob reads [ ? and * inside the pattern as syntax. The revision right
#      before this one passed the directory through glob.escape, so that was
#      handled there — but the escaping only existed because glob was the wrong
#      tool, and the revision before THAT reported a project with no dismissals
#      for a directory that genuinely held journals.
#
# listdir raises for the first and needs no escaping for the second. The
# leading-dot skip preserves the behaviour glob had: `*` does not match a
# leading dot, so a `.hidden.md` in the journal directory was and remains
# ignored.
try:
    _entries = sorted(os.listdir(journal_dir))
except OSError as exc:
    print("DISMISSED_COUNT=0")
    print("DROPPED_COUNT=0")
    print("STATE=unavailable")
    print("REASON=the journal directory %s could not be listed (%s), so whether this "
          "project has recorded dismissals is unknown" % (one_line(journal_dir), errno.errorcode.get(exc.errno, "OSError")))
    sys.exit(0)

for _name in _entries:
    if _name.startswith(".") or not _name.endswith(".md"):
        continue
    path = os.path.join(journal_dir, _name)
    try:
        for a in read_artifacts(path):
            if not isinstance(a, dict):
                # One silently dropped entry can decide whether a cluster
                # reaches the two-instance threshold.
                unreadable.append((path, "an artifacts entry is %s, not a mapping" % type(a).__name__))
                continue
            t = a.get("type")
            if t == "finding-dismissed":
                dismissed.append((path, a))
            elif t == "dropped-finding":
                dropped.append((path, a))
    except ManifestError as exc:
        # A manifest nobody could read is not a project with no dismissals.
        # Counting it as zero would hide the evidence this category exists to
        # find, which is the whole failure mode being fixed here. A journal with
        # no frontmatter at all is NOT this case — read_artifacts returns [] for
        # it, because the writer prepends a manifest on the first write and a
        # file without one has had nothing recorded in it.
        unreadable.append((path, exc))
    except Exception as exc:
        # Not ours, so only the class goes out: the text of a parse error quotes
        # the file, and the file may not be a manifest at all.
        unreadable.append((path, "the manifest could not be read (%s); its text is not "
                                 "echoed here" % type(exc).__name__))

for path, exc in unreadable:
    print("JOURNAL_UNREADABLE=%s — %s" % (one_line(path), one_line(exc)))
print("DISMISSED_COUNT=%d" % len(dismissed))
print("DROPPED_COUNT=%d" % len(dropped))
if unreadable:
    print("STATE=degraded")
    print("REASON=%d journal file(s) could not be read, so the counts above are a floor, not a total" % len(unreadable))
elif not dismissed and not dropped:
    print("STATE=empty")
else:
    print("STATE=ok")
for path, a in dismissed:
    print("DISMISSED=journal=%s pr=%s cycle=%s finding_id=%s category=%s reason=%s by=%s" % (
        one_line(path), one_line(a.get("pr")), one_line(a.get("cycle")),
        one_line(a.get("finding_id")), one_line(a.get("category")),
        one_line(a.get("reason")), one_line(a.get("by"))))
for path, a in dropped:
    print("DROPPED=journal=%s pr=%s cycle=%s finding_id=%s facet=%s reason=%s" % (
        one_line(path), one_line(a.get("pr")), one_line(a.get("cycle")),
        one_line(a.get("finding_id")), one_line(a.get("facet")),
        one_line(a.get("reason"))))
DISMISSAL_PY
); DISMISSAL_RC=$?
  # A reader that died mutely leaves no STATE line, which reads as a project
  # with nothing to report.
  if [ "$DISMISSAL_RC" -ne 0 ] || [ "$(printf '%s\n' "$DISMISSAL_OUT" | grep -c '^STATE=')" != "1" ]; then
    printf '%s\n' "DISMISSED_COUNT=0"
    printf '%s\n' "DROPPED_COUNT=0"
    printf '%s\n' "STATE=unavailable"
    printf '%s\n' "REASON=the dismissal reader did not complete (exit $DISMISSAL_RC), so whether this project has recorded dismissals is unknown"
  else
    printf '%s\n' "$DISMISSAL_OUT"
  fi
fi
fi
# DISMISSAL_ARTIFACTS_BLOCK_END

true
```

Read all journal files from the current session (today's entries). The `### Transcript Corrections` table is already in context — do not re-run the miner; re-read individual cited lines only (Phase 2).

## Phase 2: Pattern Analysis

Analyze journal entries for:

### Repeated Corrections
- Same type of fix applied multiple times (e.g., "added missing error handling" appears 3x)
- Same convention violation corrected repeatedly
- Same file structure pattern created repeatedly

### Decision Patterns
- Consistent architectural choices (always choosing X over Y)
- Recurring trade-off resolutions
- Common risk assessments

### Gate Patterns
- Gates that always get approved → candidate for tier demotion
- Gates that frequently trigger → valuable safety check

### Goal Failure Patterns (v3, when `flow.goals.enabled: true`)

Parse the `GOAL_FILE=`, `RUN_EVENTS=` and `RUN_VERDICT=` files the block lists (`.flow/goals/*.goal.yaml`, `.flow/runs/*/events.jsonl`, `.flow/runs/*/last-verdict.json`, none read through a symlink) to detect goal-level patterns the journal alone can't see:

- **Recurring failed ACs**: same `verification_command` failing across 3+ goals → the command may be wrong, flaky, or testing the wrong thing. Pattern qualifies when the same command string appears in `objective.acceptance_criteria[].verification_command` of ≥3 goals AND the corresponding AC `last_result` shows non-zero exit on each.
- **Stuck-detection hits**: count of `delta == "unchanged"` runs across recent verdicts. A goal that hit `failAfterStuckTurns` is parseable from the `RUN_VERDICT=` files the block lists (never a `last-verdict.json` that is a symlink) + a final `lifecycle.status: failed` with `last_evaluation.reason: stuck_no_progress`. Pattern: 2+ goals failing this way → either ACs are too coarse, or the executor needs different scaffolding.
- **`not_executed` ACs**: across goals, count ACs whose `last_result.reason` includes `not_executed`. If the user has `executeVerificationCommands: false` but goals consistently fail to capture deterministic evidence, suggest flipping the flag.
- **Path-boundary violations**: `events.jsonl` entries with `type: path-boundary-violation` indicate goals whose `allowed_paths` was too narrow OR the executor strayed from scope. Recurring violations of the same path glob → either the glob is too tight, or the workflow's natural scope exceeds the goal's contract.

Pattern qualifies for proposal generation under the same rules as decision patterns: ≥2 occurrences + evidence citations (goal id + AC id + run id + event timestamp).

### Correction Patterns (transcript source)

Source: the `### Transcript Corrections` table from Phase 1, when `TRANSCRIPT_STATE=ok`. Skip this category when the state is `disabled` or `missing`, or when `CANDIDATE_COUNT=0`. Every row is a *candidate* selected by the recall-oriented keyword filter in `bin/flow-mine-corrections.sh` (`REACTION_PHRASES`); most rows are noise, and this phase is where the judging happens.

1. **Verify before counting.** For each row you intend to cite, re-read the cited transcript line (`sed -n '<line_no>p' <transcript_path>`, or `Read` with an offset; a `Line` cell whose path ends in `…` was cut at 200 characters, so find the file that starts with the part shown first) and confirm the user is correcting the assistant's previous turn — not giving a new task, asking about the codebase, or thanking. Drop rows that do not survive. Quote only the user's turn and the truncated assistant context; never paste whole assistant turns or tool results into the analysis.
   Then record what you decided for that row: `kept` when it survives, `dropped` when it does not. Run the block below once per re-read row, with `LINE` set to the full path of the transcript you re-read and the line number (`<transcript_path>:<line_no>`) and `VERDICT` to `kept` or `dropped`. It writes only when Phase 1 asked System One about that row (site `learn.correction` in `shadow` or `on`), so with the site off it writes nothing. The record holds the row's reference, the digest of what was sent, and your verdict, never the transcript text; it is what System One's answers are compared against before the site is switched on by default ([`references/system-one.md`](../references/system-one.md)). When Phase 1 printed `S1_STATE=`, the rows rated as corrections come first; that order is a reading order only, and every row you cite is still re-read.

   ```bash
   LINE="<transcript_path>:<line_no>"; VERDICT="kept"
   # LEARN_VERDICT_BLOCK_BEGIN
   # USER_FILES_BEGIN
   USER_HELPER="$(__t=$(git rev-parse --show-toplevel 2>/dev/null);__x=0;[ -z "$__t" ]||{ __t=$(cd "$__t" 2>/dev/null&&pwd -P);[ -n "$__t" ]||__x=1; };[ "$__x" = 1 ]||{ printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-}";ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do __p=${__p%/};[ -n "$__p" ]&&[ -x "$__p/bin/cascade-resolve.sh" ]||continue;__r=$(cd "$__p" 2>/dev/null&&pwd -P)||continue;[ -n "$__r" ]||continue;[ -z "$__t" ]||{ __d=$__r;__in=0;while :;do [ "$__d" -ef "$__t" ]&&{ __in=1;break; };[ "$__d" = / ]&&break;__d=$(dirname "$__d");done;[ "$__in" = 1 ]&&continue; };printf '%s\n' "$__r";break;done)/bin/cascade-resolve.sh"
   # USER_FILES_END
   if [ -x "$(dirname "$USER_HELPER")/flow-learn-verdict.sh" ]; then
     "$(dirname "$USER_HELPER")/flow-learn-verdict.sh" --line "$LINE" --verdict "$VERDICT"
   fi
   # LEARN_VERDICT_BLOCK_END
   ```
2. **Cluster by what the user asked for**, not by wording. "I opened it and it is empty", "the file has nothing in it", and "why is the output blank?" are one cluster: *verify the output exists before reporting done*. Name every cluster as the behaviour the user wanted.
3. **Threshold.** A cluster qualifies only with ≥3 verified instances across ≥2 distinct sessions (`Session` column). Repeats inside one session show one bad session, not a habit.
4. **Cross-reference existing skills.** For each qualifying cluster, search for the rule with 2–3 phrasings: `grep -ril '<key phrase>' plugins/flow/skills` (use the plugin root from Phase 1 when not running inside this repo). Label the cluster `rule exists in <skill>` when a skill already states the behaviour, otherwise `no rule`.
5. Record per cluster: name, verified instance count, session count, cited lines (`transcript_path:line_no`), and the label. These feed Phase 3 and the Phase 5 table.

### Dismissal patterns

Read the `### Dismissal Artifacts` section from Phase 1. Cluster the `DISMISSED=` rows by
`category` and `reason`; a cluster is a finding the team keeps rejecting for the same stated reason.

`DROPPED=` rows are counted and shown but are **not** evidence for an exception. A dropped finding
did not survive the review machinery — both variants disagreed, or consolidation lost it. A
dismissed finding is one a human rejected on stated grounds. Only the second says anything about
what this team wants, and conflating them would turn a reviewer disagreement into a standing rule.

A cluster that recurs in one project becomes an `exception` proposal (below). A cluster that recurs
across projects is knowledge rather than a local preference, and becomes a skill proposal as today.

When Phase 1 reported `STATE=degraded`, say so alongside the counts: journals that could not be read
mean the counts are a floor, and a cluster that just missed the threshold may only have missed it
because a file was unreadable.

## Phase 3: Quality Filters

A pattern qualifies for a skill proposal when:

1. **Minimum occurrences**: Pattern appears ≥2 times in journal entries
2. **Evidence citations**: Can cite specific journal entries as evidence
3. **Actionable knowledge**: The pattern can be expressed as a reusable instruction
4. **Not already covered**: No existing skill captures this knowledge

### Transcript-sourced Patterns

Correction patterns from Phase 2 use their own threshold (≥3 verified instances across ≥2 sessions) in place of filter 1, and transcript line citations satisfy filter 2. Filter 4 changes what gets proposed rather than whether:

- `no rule` → a standard skill proposal, with transcript citations as evidence.
- `rule exists in <skill>` → **not** a new skill. The words were already in a skill and were still broken, so the proposal is of type `enforcement`: name the skill holding the rule, the mechanical check point (which hook — `PreToolUse`, `PostToolUse`, `Stop`, `TaskCompleted`, `SessionEnd` — or which command gate/phase), what the check reads, and what it blocks or warns on. Fill in the template's `## Enforcement point` section and cite transcript lines under `## Evidence`. Skip the proposal only when an existing hook or gate already enforces the rule mechanically — cite the script.

### Dismissal Patterns

Replaces filter 1 for the Dismissal patterns category. A cluster qualifies at
**two or more dismissals across two or more pull requests**.
Two dismissals on one pull request is one argument
had twice, not a pattern — the same reviewer and the same author in the same conversation. Requiring
two pull requests is what makes it a property of the project rather than of one exchange.

Filter 2 is already satisfied: every `finding-dismissed` artifact carries its `evidence` field,
which `references/decision-journal-schema.md` requires per reason.

### Fatigue Circuit Breaker

When a session yields more proposals than you can evidence well, propose the patterns
with the strongest transcript evidence and say in the output which patterns were seen
but not written up, so the next run can pick them up.

## Phase 4: Generate Proposals

For each qualifying pattern, create a skill proposal:

```bash
mkdir -p "$PROPOSAL_DIR"
```

Write each proposal to `$PROPOSAL_DIR/YYYY-MM-DD-{topic}.md` using the skill-proposal template. Enforcement proposals (Phase 3) keep the same template and required sections, add the `## Enforcement point` section, and use the `-enforcement` topic suffix (e.g. `YYYY-MM-DD-verify-output-enforcement.md`) so reviewers can tell them from new-skill proposals at a glance.

Set `type:` in the frontmatter — `skill`, `enforcement` or `exception`. It is what
`bin/promote-proposal.sh` branches on, and the filename suffix alone is a convention the promoter
cannot read.

**Exception proposals** (from the Dismissal patterns category) use the `-exception` suffix and carry
only `## Pattern Detected`, `## Evidence` and `## Exception row`. The other sections are skill-shaped
and say nothing about a rule. The body of `## Exception row` is one table row for
`.flow/review-exceptions.md`:

```
| {the rule, as a reviewer needs to read it} | {path glob it is scoped to} | {why the team rejected the finding} | {the pull requests it was dismissed on} |
```

The glob comes from where the dismissals actually happened — the `location` field of the clustered
artifacts, narrowed to the directory they share. A rule scoped wider than the evidence supports is a
rule that will suppress findings nobody dismissed. Promotion appends the row; it never writes a
skill, and `/flow:learn` never writes `.flow/review-exceptions.md` itself.

## Phase 5: Display Summary

```markdown
## Learning Analysis

### Patterns Detected
| # | Pattern | Source | Occurrences | Evidence |
|---|---------|--------|-------------|----------|
| 1 | {pattern description} | journal | {N} | issue-{X}.md, issue-{Y}.md |
| 2 | {behaviour the user asked for} | transcripts ({sessions} sessions) — {rule exists in <skill> \| no rule} | {N verified} | {transcript_path}:{line_no}, … |

### Proposals Generated
| # | Proposal | Type | Path |
|---|----------|------|------|
| 1 | {skill name} | skill \| enforcement \| exception | {proposal file path} |

### Promotion Workflow

To promote a proposal to an active skill, use the canonical helper. `{PROPOSAL_DIR}` is the directory Phase 1 printed as `PROPOSAL_DIR=`:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/promote-proposal.sh" \
  --proposal {PROPOSAL_DIR}/YYYY-MM-DD-{topic}.md
```

The script:
1. Validates the proposal frontmatter (required fields, status: proposal, kebab-case name)
2. Validates the body (must contain `## Contract`, `## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist` sections per `templates/skill-proposal.md`)
3. Refuses to overwrite an existing learned skill at the target name
4. Writes `plugins/flow/skills/learned/{name}/SKILL.md`, rewriting `status: proposal` -> `status: promoted` with today's date and removing `## Pattern Detected`, `## Evidence`, `## Enforcement point`, `## Promotion Checklist` and the `source-sessions` / `evidence-count` / `proposed` frontmatter — those argue for promotion or name the project the pattern was mined in, while the installed file is read by an agent about to act. All of it is published in the pull request body, where it can still be edited before merge. It then refuses the promotion unless the result is skill-shaped: `## Contract` first, at most 120 contract words and 600 body words.
5. Creates a feature branch `feature/learn-promote-{name}`, commits, pushes, and opens a **draft** PR for human review

The PR is **always draft** — `bin/promote-proposal.sh` is Tier 2 (journal-and-proceed) and never marks the PR ready or merges it. A human reviewer must mark the PR ready and merge it explicitly. This prevents `/flow:learn` from autonomously reshaping Claude's behavior without explicit consent.

Use `--dry-run` to validate a proposal without filesystem effects:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/promote-proposal.sh" \
  --proposal {PROPOSAL_DIR}/YYYY-MM-DD-{topic}.md \
  --dry-run
```

The dry-run reports validation results and the planned filesystem/git actions without executing them. It also runs the real transform against a throwaway copy, so it catches a proposal that would not promote to a well-formed skill, and prints the material the pull request would publish — the last point at which you can decide something mined from another project should not go public.
```

## Phase 6: Clear Pending

```bash
# USER_FILES_BEGIN
USER_HOME=$("$(__t=$(git rev-parse --show-toplevel 2>/dev/null);__x=0;[ -z "$__t" ]||{ __t=$(cd "$__t" 2>/dev/null&&pwd -P);[ -n "$__t" ]||__x=1; };[ "$__x" = 1 ]||{ printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-}";ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do __p=${__p%/};[ -n "$__p" ]&&[ -x "$__p/bin/cascade-resolve.sh" ]||continue;__r=$(cd "$__p" 2>/dev/null&&pwd -P)||continue;[ -n "$__r" ]||continue;[ -z "$__t" ]||{ __d=$__r;__in=0;while :;do [ "$__d" -ef "$__t" ]&&{ __in=1;break; };[ "$__d" = / ]&&break;__d=$(dirname "$__d");done;[ "$__in" = 1 ]&&continue; };printf '%s\n' "$__r";break;done)/bin/cascade-resolve.sh" --user-home 2>/dev/null) || USER_HOME=""
# USER_FILES_END
case "$USER_HOME" in
  /*) rm -f "$USER_HOME/.claude/flow-learn-pending" ;;
  *) printf '%s\n' "WARN=no flow install outside this repository answered, so the learn-pending flag in your home was not cleared" ;;
esac
```

## No Entries Case

If no journal entries found:
- "No decision journal entries found. Journal entries are created automatically during `/flow:start`, `/flow:commit`, and `/flow:address` workflows."
- Suggest running a workflow first.

State the transcript half plainly, because it is the half that carries the behavioural signal and the half that fails silently.

- `TRANSCRIPT_STATE=ok` and `CANDIDATE_COUNT=0`: "No correction candidates in the last `SESSION_COUNT` transcripts." The source was read and held nothing.
- `TRANSCRIPT_STATE=missing`: say the transcript half produced nothing **and why** — name every root from `TRANSCRIPT_ROOTS_TRIED`, not just the one path, and say that `learning.transcriptDir` (in the user settings file) or `CLAUDE_TRANSCRIPT_DIR` points at it. Do not let this read as "no corrections found": the corrections a user actually made live in the transcripts, so a run without them has seen only what flow wrote about itself.
- `disabled`: say transcripts are off via `learning.sources`.

The two states are different findings. One says the evidence was read and was empty; the other says the evidence was never reached.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read decision journal | 1 | Autonomous, read-only |
| Read `.flow/goals/*.goal.yaml` + `.flow/runs/*/events.jsonl` (v3) | 1 | Autonomous, read-only |
| Read session transcripts under `<config>/projects/<slug>/` (`$CLAUDE_CONFIG_DIR` or `~/.claude`) via `bin/flow-mine-corrections.sh` | 1 | Autonomous, read-only, user-scoped files (outside repo); gated by `learning.sources` |
| Pattern detection across journal entries + goal/run events + transcript corrections | 1 | Autonomous |
| Ask System One about each transcript correction candidate (site `learn.correction`), and record the Phase 2 verdict on each one asked | 1 | Off by default; only your user settings can set it to `shadow` or `on`. With provider `typesafe` the user turn as typed (up to 600 characters) and the first 300 characters of the assistant's last message before it go to TypeSafe's hosted API, with nothing removed, so a key typed into the turn goes with it; with `custom`, or `imajev` at an address that is not on your machine, they go to the server at `baseUrl`; with `imajev` at its default local address nothing leaves the machine. Records and verdicts go to the per-user state directory |
| Write skill proposals to `learning.proposalDir` (default `~/.claude/flow-proposals/`) | 1 | Autonomous, user-scoped files (outside repo) |
| Clear `~/.claude/flow-learn-pending` flag | 1 | Autonomous |

Promotion of a proposal to an active skill (`plugins/flow/skills/learned/`) is **separate** and is owned by `bin/promote-proposal.sh`, which opens a draft PR (Tier 2 — never auto-merges). Learning analysis itself is Tier 1; promotion is Tier 2.
