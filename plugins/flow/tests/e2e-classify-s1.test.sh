# shellcheck shell=bash
# End-to-end: the System One decision point classify.serves-issue. For each
# file change classification puts in the uncertain band, /flow:commit Phase 3
# and /flow:start CODE step 8 run S1_CLASSIFY_BLOCK before asking the user,
# and S1_RECORD_BLOCK after the user chooses include, include as cleanup, or
# exclude. Both blocks
# call bin/flow-classify-s1.sh, which asks bin/flow-s1.sh one yes/no question:
# does this change serve the issue?
#
# Each scenario runs the shipped blocks and helper in a scratch repository
# with its own HOME, against stub servers (tests/lib/s1_stub.py) that log
# every request, and the shipped system-one/questions.yaml. The harness runs
# a block under every shell in E2E_FENCE_SHELLS (zsh, then bash), so request
# and record counts for a block are per file times the number of shells.
# One artifact per scenario is written to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   C1  the classify block asks the provider in shadow mode, so each file is
#       asked twice per prompt and a record with current=uncertain mixes
#       with the user's real choices; or the record block asks in on mode
#   C2  shadow mode prints an estimate the model then shows in the prompt
#   C3  a red-flag file (.env.local) is sent to the provider, or gets an
#       estimate that reads like permission to commit it
#   C4  the estimate shown is the confidence |2p-1|, so a confident "does not
#       serve" (p=0.05) shows as 0.90
#   C5  a stub reply the client reads as malformed makes "no note" pass for
#       the wrong reason: every no-answer case asserts its exact reason
#   C6  a repository's settings switch the site on, start shadow when the
#       user's mode is off, or choose the server the diffs go to
#   C7  with no issue, or gh failing, a state with no objective is sent
#   C8  off, shadow or no provider still fetches the issue or sends a request
#   C9  more than 8 files are asked in one prompt
#   C10 /flow:start step 8 never sends uncertain files to the user, or its
#       records do not go to the run it passes
#   C11 the state for one file is not the same bytes twice, so the ask and
#       the record cannot be joined, or two files share one digest
#   C12 a path the --ref grammar does not take (a space) makes the client exit
#       2, so the file is never asked and no record is written
#   C13 an unchanged file, an untracked file, a binary file or a long diff is
#       sent as something other than the change
#   C14 the plugin inside the repository: the refusal to read the user's
#       mode is taken as off, which gives not-on instead of settings-refused
#   C15 --file names a directory, so the diffs of every changed file under it
#       (a tracked .env among them) are sent
#   C16 a path with a byte that is not valid UTF-8 is cut short before the
#       red-flag match, so a red-flag file under it is read and sent
#   C17 the issue is fetched once per file, so a slow gh is waited on up to
#       eight times per prompt
#   C18 a repository's settings set the site to shadow: the helper reads the
#       mode in another directory than bin/flow-s1.sh does (the session works
#       in a subdirectory), so the classify block asks and records
#       current=uncertain, or the record block writes nothing
#   C19 the resolver's warning about a settings file it cannot parse reaches
#       the prompt twice per file: once from the mode read and once from the
#       client
#   C20 a path or a signal reaches a shell line: a file named a'$(touch X)'.md
#       or a signal with an apostrophe runs code or breaks the block when the
#       session fills the block's template
#   C21 the block reads a file the session did not make with mktemp (outside
#       TMPDIR, a symlink, a hard link), or input that is not one object of
#       files, and sends something
#   C22 the shadow record path skips the red-flag refusal, so .env.local is
#       sent when the session lists it by mistake
#   C23 a rename or copy of a red-flag file (git mv .env notes.md, a staged
#       cp .env notes.md, or mv .env notes.md without git) is sent under its
#       new, harmless name
#   C24 a shadow record that is not written (a decision in another spelling,
#       no issue, a red flag) leaves no trace
#   C25 after a call times out, every other file of the prompt waits out the
#       same timeout; nothing bounds the prompt as a whole
#   C26 a gh issue view that never returns holds the block before any
#       provider timeout applies
#   C27 a block stopped by a signal leaves its copy of the issue in TMPDIR
#   C28 a file included as cleanup is recorded as include, which the
#       question (cleanup does not serve the issue) counts as a disagreement
#   C29 a guard that only one directory shape reaches: a tracked file
#       replaced by a directory of staged files, or a directory holding one
#       changed red-flag file
#   C30 with the site off, the record block prints a warning (jq missing, a
#       decision in another spelling, input it refuses) for records it would
#       never write; or in shadow mode a file past the 8th is dropped with no
#       warning

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

C_HELPER="bin/flow-classify-s1.sh"
C_RECORDS=".claude/flow-state/system-one.jsonl"
C_TITLE="Uncertain change-classification prompts show whether the change serves the issue"
# The number of shells each block runs under.
# shellcheck disable=SC2086
C_SH=$(set -- $E2E_FENCE_SHELLS; printf '%s' "$#")

# A reply in the client's noul shape: the probability is the noul field.
_reply() { printf '{"body":{"model":"jev-1.13.0","answers":{"serves_issue":{"type":"noul","noul":%s}}}}' "$1"; }

# _git <args>: git in the scratch repository, with the scenario's HOME.
_git() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git "$@"
  )
}

# _c_setup <name> <purpose> [branch]: scratch repository on a branch that
# names issue 270, the issue fixture, and one uncommitted change to a
# committed file, docs/notes.md.
_c_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo "${3:-feature/issue-270-classify}"
  e2e_gh_fixture issue-270 "$(jq -nc --arg t "$C_TITLE" '{number:270,title:$t,body:"Show the model estimate next to the signals for uncertain files."}')"
  mkdir -p "$E2E_REPO/docs"
  printf 'Notes\n' > "$E2E_REPO/docs/notes.md"
  _git add docs/notes.md
  _git commit -q -m notes
  printf 'Notes\nThe estimate is shown beside the signals.\n' > "$E2E_REPO/docs/notes.md"
}

# _settings <mode> [stub] [extra jq]: user settings with a custom provider at
# the stub and the site in <mode>; mode "-" leaves the site out.
_settings() {
  local mode="$1" stub="${2:-a}"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$stub")" --arg m "$mode" \
    '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-1.13.0",timeoutMs:3000,uses:(if $m == "-" then {} else {"classify.serves-issue":$m} end)}}')"
}

# _c_input <path> [NAME=value ...] — write the input file the session writes
# with the Write tool: {"files": [{"path", "signals", "decision"}]}, one entry
# per line of FILES, with SIGNALS_<n> and DECISION_<n> when given.
_c_input() {
  python3 -I -c '
import json, sys
kv = dict(a.split("=", 1) for a in sys.argv[2:])
out = []
for n, f in enumerate([f for f in kv.get("FILES", "").split("\n") if f], 1):
    e = {"path": f}
    for key, name in (("signals", "SIGNALS_%d"), ("decision", "DECISION_%d")):
        if name % n in kv:
            e[key] = kv[name % n]
    out.append(e)
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({"files": out}, f)
' "$@"
}

# _c_block <command file> <block> [NAME=value ...] — run a block the way the
# session does: FILES, SIGNALS_<n> and DECISION_<n> go into a file from
# mktemp in the scenario's TMPDIR (TMPDIR=... when given, else $E2E_DIR/tmp),
# named by S1_INPUT; every other NAME=value is set for the block. The block
# removes that file, so it runs under one shell at a time with the file
# written again before each; stdout is compared between the shells, and
# E2E_OUT, E2E_ERR and E2E_RC are those of the first shell.
_c_block() {
  local md="$1" blk="$2" a sh tmpd="$E2E_DIR/tmp" first="" first_out="" first_err="" first_rc=""
  local all_shells="$E2E_FENCE_SHELLS" ins=() envs=()
  shift 2
  for a in "$@"; do
    case "$a" in
      FILES=*|SIGNALS_*=*|DECISION_*=*) ins+=("$a") ;;
      TMPDIR=*) tmpd="${a#TMPDIR=}" ;;
      *) envs+=("$a") ;;
    esac
  done
  mkdir -p "$tmpd"
  for sh in $all_shells; do
    C_INPUT=$(TMPDIR="$tmpd" mktemp "$tmpd/tmp.XXXXXX")
    _c_input "$C_INPUT" ${ins[@]+"${ins[@]}"}
    E2E_FENCE_SHELLS="$sh" e2e_run_block TMPDIR="$tmpd" S1_INPUT="$C_INPUT" ${envs[@]+"${envs[@]}"} "$md" "$blk"
    if [ -e "$C_INPUT" ]; then _e2e_result fail "the input file is removed under $sh"
    else _e2e_result pass "the input file is removed under $sh"; fi
    if [ -z "$first" ]; then
      first="$sh"; first_out="$E2E_OUT"; first_err="$E2E_ERR"; first_rc="$E2E_RC"
    elif [ "$E2E_OUT" = "$first_out" ]; then
      _e2e_result pass "stdout under $sh matches $first"
    else
      _e2e_result fail "stdout under $sh matches $first"
    fi
  done
  E2E_FENCE_SHELLS="$all_shells"
  E2E_OUT="$first_out"; E2E_ERR="$first_err"; E2E_RC="$first_rc"
}

_classify() { _c_block commands/commit.md S1_CLASSIFY_BLOCK "$@"; }

# _path_without_jq: a PATH holding every command of this one but jq, as links
# in a directory of the scenario's own, with the scenario's bin first.
_path_without_jq() {
  local d dir="$E2E_DIR/nojq" f n IFS=:
  mkdir -p "$dir"
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n="${f##*/}"
      [ "$n" != jq ] && [ -x "$f" ] && [ ! -e "$dir/$n" ] && ln -s "$f" "$dir/$n"
    done
  done
  printf '%s:%s' "$E2E_BIN" "$dir"
}
_record() { _c_block commands/commit.md S1_RECORD_BLOCK "$@"; }

_expect_requests() { e2e_expect_equal "$2" "$(e2e_stub_requests "$1")" "requests to stub $1"; }

# _records [file]: the records the scenario wrote, one JSON object per line.
_records() { cat "${1:-$E2E_HOME/$C_RECORDS}" 2>/dev/null; }
_record_count() { local n; n=$(_records "${1:-}" | wc -l); printf '%s' "${n// /}"; }

# stdout without its S1_REASON lines, for comparing the prompt input across
# scenarios whose reasons differ.
_no_reason() { grep -v '^S1_REASON=' <<<"$1"; }

# What off prints for docs/notes.md. The off scenario checks the blocks print
# it; the scenarios compared with off use it whether or not off ran.
OFF_OUT=$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=not-on')

if _want off; then
  _flow_test_begin "off"
  _c_setup off "the site left out of the settings (off, the default) with a provider configured: neither block sends anything, the classify block says not-on for each file, and the record block prints nothing, on stdout or stderr, also for a decision in another spelling and with jq missing (C8, C30)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings -
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout"
  _record FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=include
  e2e_expect_equal 0 "$E2E_RC" "record block exit status"
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  e2e_expect_equal "" "$E2E_ERR" "record block stderr"
  _record FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=Include
  e2e_expect_equal "" "$E2E_ERR" "record block stderr for decision Include"
  _record PATH="$(_path_without_jq)" FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=include
  e2e_expect_equal 0 "$E2E_RC" "record block exit status with jq missing"
  e2e_expect_equal "" "$E2E_ERR" "record block stderr with jq missing"
  _expect_requests a 0
  e2e_expect_equal 0 "$(_record_count)" "records"
  # The same PATH hides jq from the classify block, which checks for jq
  # before anything else: the record block was silent with jq missing, not
  # with jq still found.
  _classify PATH="$(_path_without_jq)" FILES="docs/notes.md" ISSUE_NUM=270
  e2e_expect_equal "$(printf 'S1_INPUT=refused\nS1_REASON=jq-missing')" "$E2E_OUT" "classify block stdout with jq missing"
  # Off makes no gh call: a gh that fails would not change the reason.
  e2e_gh_fail issue-270
  _classify FILES="$(printf 'docs/notes.md\ndocs/other.md')" ISSUE_NUM=270
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=not-on\nS1_FILE=docs/other.md\nS1_ESTIMATE=none\nS1_REASON=not-on')" "$E2E_OUT" "stdout for two files"
  _expect_requests a 0
  e2e_expect_clean_edges
fi

if _want on-shows-estimate; then
  _flow_test_begin "on-shows-estimate"
  _c_setup on-shows-estimate "site on, stub p=0.93: the classify block prints p (0.93) and the model, sends the issue, the file and its diff once per shell, and records current=uncertain with the ref; the ref is not sent (C5)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only; first-touch"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=0.93\nS1_MODEL=jev-1.13.0\nS1_TRUNCATED=false')" "$E2E_OUT" "stdout"
  _expect_requests a "$C_SH"
  log=$(e2e_stub_log a)
  e2e_expect_equal "$C_TITLE" "$(head -1 "$log" | jq -r '.body.state.issue.title')" "issue title sent"
  e2e_expect_equal 270 "$(head -1 "$log" | jq -r '.body.state.issue.number')" "issue number sent"
  e2e_expect_equal "docs/notes.md M" "$(head -1 "$log" | jq -r '.body.state.file.path + " " + .body.state.file.status')" "file path and status sent"
  e2e_expect_equal 1 "$(head -1 "$log" | jq -r '.body.state.file.diff' | grep -c '^+The estimate is shown beside the signals.$')" "added line in the diff sent"
  e2e_expect_equal '["sibling only","first-touch"]' "$(head -1 "$log" | jq -c '.body.state.signals')" "signals sent"
  e2e_expect_equal '["serves_issue"]' "$(head -1 "$log" | jq -c '.body.questions | keys')" "question sent"
  e2e_expect_equal 0 "$(grep -c 'classify:issue-270' "$log")" "requests carrying the ref"
  e2e_expect_equal "$C_SH" "$(_record_count)" "records"
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.site == "classify.serves-issue" and .question == "serves_issue" and .mode == "on" and .current == "uncertain" and .result == "answered" and .answer.p == 0.93 and .ref == "classify:issue-270/docs/notes.md")' | wc -l | tr -d ' ')" "records: on, uncertain, answered, with the ref"
  # In on mode the record block does nothing: the file was asked once, by
  # the classify block (C1).
  _record FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only; first-touch" DECISION_1=include
  e2e_expect_equal 0 "$E2E_RC" "record block exit status"
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_record_count)" "records after the record block"
  e2e_expect_equal 0 "$(_records | jq -c 'select(.current == "include")' | wc -l | tr -d ' ')" "records with current=include"
  e2e_expect_clean_edges
fi

if _want on-low-p-shown-as-is; then
  _flow_test_begin "on-low-p-shown-as-is"
  _c_setup on-low-p-shown-as-is "site on, stub p=0.05: confidence |2*0.05-1| = 0.90 clears 0.6, and the estimate shown is p, 0.05, a confident 'does not serve', not 0.90 (C4)"
  e2e_stub_start a "$(_reply 0.05)"
  _settings on
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_ESTIMATE=0.05"
  e2e_expect_no_line "S1_ESTIMATE=0.90"
  _expect_requests a "$C_SH"
  e2e_expect_clean_edges
fi

if _want on-below-threshold; then
  _flow_test_begin "on-below-threshold"
  _c_setup on-below-threshold "site on, stub p=0.6: confidence 0.2 is below 0.6, so no estimate and S1_REASON=below-threshold; the prompt input matches off except for the reason, and the record keeps the answer (C5)"
  e2e_stub_start a "$(_reply 0.6)"
  _settings on
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_REASON=below-threshold"
  e2e_expect_line "S1_ESTIMATE=none"
  e2e_expect_equal "$(_no_reason "$OFF_OUT")" "$(_no_reason "$E2E_OUT")" "stdout without its reason, against off"
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.result == "below-threshold" and .answer.p == 0.6 and .current == "uncertain")' | wc -l | tr -d ' ')" "records keeping the below-threshold answer"
  e2e_expect_clean_edges
fi

if _want on-unparsable-repo-settings-warns-once; then
  _flow_test_begin "on-unparsable-repo-settings-warns-once"
  _c_setup on-unparsable-repo-settings-warns-once "site on, the repository's settings file is not valid JSON: the classify block still shows the estimate for each of two files, and shows the resolver's warning about that file once per file, not once from the mode read and again from the client (C19)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne": \n' > "$E2E_REPO/.claude/settings.flow.json"
  printf 'Other\n' > "$E2E_REPO/docs/other.md"
  _classify FILES="$(printf 'docs/notes.md\ndocs/other.md')" ISSUE_NUM=270
  e2e_expect_equal 2 "$(grep -c '^S1_ESTIMATE=0.93$' <<<"$E2E_OUT")" "estimates shown"
  e2e_expect_equal 2 "$(grep -c '^cascade-resolve: WARN: failed to parse .*settings.flow.json' <<<"$E2E_ERR")" "resolver warnings about the settings file"
  e2e_expect_clean_edges
fi

if _want shadow-output-unchanged-and-records-decision; then
  _flow_test_begin "shadow-output-unchanged-and-records-decision"
  _c_setup shadow-output-unchanged-and-records-decision "site shadow: the classify block sends nothing and prints what off prints; the record block sends once per file per shell with the user's choice as current, prints nothing, and the same inputs give the same state digest while another file gives another (C1, C2, C11)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings shadow
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against off"
  e2e_expect_no_out "S1_ESTIMATE=0"
  _expect_requests a 0
  _record FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=exclude
  e2e_expect_equal 0 "$E2E_RC" "record block exit status"
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_record_count)" "records"
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.mode == "shadow" and .current == "exclude" and .result == "answered" and .answer.p == 0.93 and .ref == "classify:issue-270/docs/notes.md")' | wc -l | tr -d ' ')" "records: shadow, exclude, answered"
  e2e_expect_equal 0 "$(_records | jq -c 'select(.current == "uncertain")' | wc -l | tr -d ' ')" "records with current=uncertain"
  e2e_expect_equal 1 "$(_records | jq -r '.state_sha256' | sort -u | wc -l | tr -d ' ')" "distinct state digests for one file across shells"
  e2e_expect_equal 1 "$(jq -c '.body.state' "$(e2e_stub_log a)" | sort -u | wc -l | tr -d ' ')" "distinct states sent for one file"
  printf 'Other\n' > "$E2E_REPO/docs/other.md"
  e2e_run_bin "$C_HELPER" record --file docs/other.md --issue 270 --signals "sibling only" --decision include
  e2e_expect_equal "0" "$E2E_RC" "helper exit status for a second file"
  e2e_expect_equal 2 "$(_records | jq -r '.state_sha256' | sort -u | wc -l | tr -d ' ')" "distinct state digests for two files"
  e2e_expect_clean_edges
fi

if _want provider-none-sends-nothing; then
  _flow_test_begin "provider-none-sends-nothing"
  _c_setup provider-none-sends-nothing "the site on in the user's settings with no provider: S1_REASON=provider-none, no request, and no gh call (gh fails here, which would give no-issue if the issue were fetched first) (C8)"
  e2e_stub_start a "$(_reply 0.93)"
  e2e_user_settings '{"systemOne":{"uses":{"classify.serves-issue":"on"}}}'
  e2e_gh_fail issue-270
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=provider-none')" "$E2E_OUT" "stdout"
  _expect_requests a 0
  e2e_expect_equal 0 "$(_record_count)" "records"
  e2e_expect_clean_edges
fi

if _want repo-cannot-switch-on; then
  _flow_test_begin "repo-cannot-switch-on"
  _c_setup repo-cannot-switch-on "the repository's settings set the site on and the user's do not set it: the user's mode (off) is used with one warning, nothing is sent and the output is off's (C6)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings -
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"classify.serves-issue":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against off"
  e2e_expect_err "can only lower your own mode; using off"
  e2e_expect_equal 1 "$(grep -c 'can only lower your own mode' <<<"$E2E_ERR")" "warnings"
  _expect_requests a 0
  e2e_expect_clean_edges
fi

if _want repo-cannot-redirect; then
  _flow_test_begin "repo-cannot-redirect"
  _c_setup repo-cannot-redirect "the user's settings put the site on at stub a; the repository's settings name stub b as the provider: only stub a is asked (C6)"
  e2e_stub_start a "$(_reply 0.93)"
  e2e_stub_start b "$(_reply 0.05)"
  _settings on a
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u}}' > "$E2E_REPO/.claude/settings.flow.json"
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_ESTIMATE=0.93"
  _expect_requests a "$C_SH"
  _expect_requests b 0
  e2e_expect_clean_edges
fi

if _want repo-cannot-start-shadow; then
  _flow_test_begin "repo-cannot-start-shadow"
  _c_setup repo-cannot-start-shadow "the repository's settings set the site to shadow and the user's settings name a provider and do not set the site: the user's mode (off) is used, with one warning from the classify block, so it prints what off prints, the record block prints nothing, and neither sends anything or writes a record (C1, C6)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings -
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"classify.serves-issue":"shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against off"
  e2e_expect_equal 1 "$(grep -c 'is shadow in this repository.s settings, which can only lower your own mode; using off' <<<"$E2E_ERR")" "warnings from the classify block"
  _record FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=include
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  _expect_requests a 0
  e2e_expect_equal 0 "$(_record_count)" "records"
  e2e_expect_clean_edges
fi

if _want repo-shadow-from-subdirectory; then
  _flow_test_begin "repo-shadow-from-subdirectory"
  _c_setup repo-shadow-from-subdirectory "the user's settings set the site on, the repository's settings at its top lower it to shadow, and both blocks run in docs/: the mode is shadow in both, with no warning, so the classify block sends nothing and writes no record with current=uncertain, and the record block sends once per file per shell and records the user's choice (C1, C18)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"classify.serves-issue":"shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  c_top="$E2E_REPO"
  # The harness runs code in E2E_REPO; here that is the subdirectory.
  E2E_REPO="$c_top/docs"
  printf 'working directory: <repo>/docs\n' | _e2e_art
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against off"
  e2e_expect_err_lacks "can only lower your own mode"
  _expect_requests a 0
  e2e_expect_equal 0 "$(_records | jq -c 'select(.current == "uncertain")' | wc -l | tr -d ' ')" "records with current=uncertain"
  _record FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=exclude
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.mode == "shadow" and .current == "exclude" and .result == "answered")' | wc -l | tr -d ' ')" "records: shadow, exclude, answered"
  E2E_REPO="$c_top"
  e2e_expect_clean_edges
fi

if _want no-answer-timeout; then
  _flow_test_begin "no-answer-timeout"
  _c_setup no-answer-timeout "site on, the stub answers after 1500 ms with timeoutMs 300: S1_REASON=timeout, the prompt input matches off except for the reason, and the record says timeout (C5)"
  e2e_stub_start a "{\"delay_ms\":1500,$(_reply 0.93 | sed 's/^{//')"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:300,uses:{"classify.serves-issue":"on"}}}')"
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_REASON=timeout"
  e2e_expect_equal "$(_no_reason "$OFF_OUT")" "$(_no_reason "$E2E_OUT")" "stdout without its reason, against off"
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.result == "timeout")' | wc -l | tr -d ' ')" "records with result timeout"
  e2e_expect_clean_edges
fi

if _want no-answer-http-and-malformed; then
  _flow_test_begin "no-answer-http-and-malformed"
  _c_setup no-answer-http-and-malformed "site on: a stub answering 500 gives S1_REASON=http-500, one answering with a reply in another shape ({p: 0.93}) gives malformed; neither shows an estimate (C5)"
  e2e_stub_start a '{"status":500,"body":{"detail":"boom"}}'
  _settings on a
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_REASON=http-500"
  e2e_expect_line "S1_ESTIMATE=none"
  _expect_requests a "$C_SH"
  e2e_stub_start b '{"body":{"model":"jev-1.13.0","answers":{"serves_issue":{"p":0.93}}}}'
  _settings on b
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_REASON=malformed"
  e2e_expect_line "S1_ESTIMATE=none"
  _expect_requests b "$C_SH"
  e2e_expect_clean_edges
fi

if _want red-flag-never-sent; then
  _flow_test_begin "red-flag-never-sent"
  _c_setup red-flag-never-sent "site on, FILES holds .env.local and docs/notes.md, both changed: only docs/notes.md is sent, .env.local gets S1_REASON=red-flag; other red-flag paths given to the helper are refused with no request (C3)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  printf 'TOKEN=abc\n' > "$E2E_REPO/.env.local"
  _classify FILES="$(printf '.env.local\ndocs/notes.md')" ISSUE_NUM=270 SIGNALS_1="config in root" SIGNALS_2="sibling only"
  e2e_expect_equal "$(printf 'S1_FILE=.env.local\nS1_ESTIMATE=none\nS1_REASON=red-flag\nS1_FILE=docs/notes.md\nS1_ESTIMATE=0.93\nS1_MODEL=jev-1.13.0\nS1_TRUNCATED=false')" "$E2E_OUT" "stdout"
  _expect_requests a "$C_SH"
  e2e_expect_equal 0 "$(grep -c 'env.local\|TOKEN=abc' "$(e2e_stub_log a)")" "requests naming .env.local or holding its content"
  # Each path matches one pattern of the list, so a pattern dropped from the
  # helper fails here.
  for p in config/credentials.yml secrets/db.md config/db_password.txt .env \
      .ssh/id_rsa .ssh/id_dsa .ssh/id_ecdsa .ssh/id_ed25519 keys/deploy.pub \
      certs/server.PEM tls/server.key certs/a.p12 certs/a.pfx keys/app.jks \
      android/release.keystore keys/putty.ppk keys/private.asc backup/db.gpg \
      .netrc .npmrc .pgpass web/.htpasswd .envrc config/prod.env .pypirc \
      .dockercfg .docker/config.json home/.docker/config.json infra/prod.tfvars \
      infra/terraform.tfstate infra/terraform.tfstate.backup ops/kubeconfig.yaml \
      .kube/config home/.kube/config vpn/office.ovpn gcp/service-account-prod.json; do
    mkdir -p "$E2E_REPO/$(dirname "$p")"
    printf 'x\n' > "$E2E_REPO/$p"
    e2e_run_bin "$C_HELPER" ask --file "$p" --issue 270 --signals ""
    e2e_expect_equal "$(printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=red-flag' "$p")" "$E2E_OUT" "stdout for $p"
  done
  # A byte that is not valid UTF-8 before the red-flag part of the path, under
  # a UTF-8 locale (C16). The file need not exist: the path is refused first.
  # The first path pins the match on the last component, the second the
  # match on the whole path. With no UTF-8 locale the case is skipped, and
  # says so, rather than passing under the C locale.
  u=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1)
  cm=""
  [ -z "$u" ] || cm=$(LC_ALL='' LANG="$u" locale charmap 2>/dev/null)
  case "$cm" in
    UTF-8|utf-8|UTF8|utf8)
      for p in "$(printf 'cfg/\377x/.ENV')" "$(printf 'cfg/\377/secrets/app.yml')"; do
        e2e_run_bin LC_ALL= LANG="$u" "$C_HELPER" ask --file "$p" --issue 270 --signals ""
        e2e_expect_line "S1_REASON=red-flag"
      done ;;
    *)
      printf 'SKIP C16: no UTF-8 locale is installed (locale -a gave "%s", charmap "%s")\n' "$u" "$cm" | _e2e_art
      _flow_assert_pass "$E2E_NAME: SKIP: C16 needs a UTF-8 locale, and none is installed" ;;
  esac
  _expect_requests a "$C_SH"
  # Shadow mode, the mode users switch on to collect records: the record path
  # refuses the same file (C22), and says so.
  _settings shadow
  _record FILES="$(printf '.env.local\ndocs/notes.md')" ISSUE_NUM=270 SIGNALS_1="config in root" SIGNALS_2="sibling only" DECISION_1=exclude DECISION_2=include
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  e2e_expect_equal "flow: WARN: no System One record for .env.local: red-flag" "$E2E_ERR" "record block warning"
  _expect_requests a $((2 * C_SH))
  e2e_run_bin "$C_HELPER" record --file .env.local --issue 270 --signals "" --decision include
  e2e_expect_equal 3 "$E2E_RC" "helper exit status for a red-flag record"
  e2e_expect_equal "S1_REASON=red-flag" "$E2E_OUT" "helper stdout for a red-flag record"
  _expect_requests a $((2 * C_SH))
  e2e_expect_equal 0 "$(grep -c 'env.local\|TOKEN=abc' "$(e2e_stub_log a)")" "requests naming .env.local or holding its content, after the record block"
  e2e_expect_equal 0 "$(_records | jq -c 'select((.ref // "") | test("env\\.local"))' | wc -l | tr -d ' ')" "records for .env.local"
  e2e_expect_clean_edges
fi

if _want no-issue; then
  _flow_test_begin "no-issue"
  _c_setup no-issue "site on, on a branch with no issue number: ISSUE_NUM empty or (none) gives S1_REASON=no-issue with no request; with ISSUE_NUM 270 and gh failing, also no-issue and no request (C7)" feature/no-number
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  _classify FILES="docs/notes.md" ISSUE_NUM="" SIGNALS_1="sibling only"
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=no-issue')" "$E2E_OUT" "stdout with no issue"
  _classify FILES="docs/notes.md" ISSUE_NUM='"(none)"' SIGNALS_1="sibling only"
  e2e_expect_line "S1_REASON=no-issue"
  e2e_gh_fail issue-270
  _classify FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_REASON=no-issue"
  _expect_requests a 0
  e2e_expect_clean_edges
fi

if _want cap-at-eight; then
  _flow_test_begin "cap-at-eight"
  _c_setup cap-at-eight "site on, ten uncertain files: exactly 8 are asked per shell, files 9 and 10 get S1_REASON=not-asked-limit; in shadow the record block also stops at 8, with one not-asked-limit warning each for files 9 and 10 (C9, C30)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  files=""
  for i in 1 2 3 4 5 6 7 8 9 10; do
    printf 'f%s\n' "$i" > "$E2E_REPO/docs/f$i.md"
    files="$files${files:+
}docs/f$i.md"
  done
  _classify FILES="$files" ISSUE_NUM=270
  _expect_requests a $((8 * C_SH))
  e2e_expect_equal 8 "$(grep -c '^S1_ESTIMATE=0.93$' <<<"$E2E_OUT")" "files with an estimate"
  e2e_expect_equal "$(printf 'S1_FILE=docs/f9.md\nS1_ESTIMATE=none\nS1_REASON=not-asked-limit\nS1_FILE=docs/f10.md\nS1_ESTIMATE=none\nS1_REASON=not-asked-limit')" "$(tail -6 <<<"$E2E_OUT")" "the last two files"
  e2e_stub_start b "$(_reply 0.93)"
  _settings shadow b
  _record FILES="$files" ISSUE_NUM=270 DECISION_1=include DECISION_2=include DECISION_3=include DECISION_4=include \
    DECISION_5=exclude DECISION_6=exclude DECISION_7=exclude DECISION_8=exclude DECISION_9=include DECISION_10=include
  _expect_requests b $((8 * C_SH))
  e2e_expect_equal 0 "$(grep -c 'docs/f9.md\|docs/f10.md' "$(e2e_stub_log b)")" "record requests for files 9 and 10"
  e2e_expect_equal "$(printf 'flow: WARN: no System One record for docs/f9.md: not-asked-limit\nflow: WARN: no System One record for docs/f10.md: not-asked-limit')" "$E2E_ERR" "record block warnings for files 9 and 10"
  e2e_expect_clean_edges
fi

if _want file-shapes; then
  _flow_test_begin "file-shapes"
  _c_setup file-shapes "site on: an unchanged file gets S1_REASON=no-diff and no request; an untracked file is sent whole with status ??; a binary file is sent as (binary); a diff over 400 lines is cut to 400 and one line over 64 KiB is cut to 64 KiB, each with S1_TRUNCATED=true, and of that 9000000-byte line at most 512 KiB is copied; a path with a space is asked and recorded under a ref naming its digest (C12, C13)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  e2e_run_bin "$C_HELPER" ask --file README.md --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=README.md\nS1_ESTIMATE=none\nS1_REASON=no-diff')" "$E2E_OUT" "stdout for an unchanged file"
  _expect_requests a 0
  printf 'new line one\nnew line two\n' > "$E2E_REPO/docs/new.md"
  e2e_run_bin "$C_HELPER" ask --file docs/new.md --issue 270 --signals ""
  e2e_expect_line "S1_ESTIMATE=0.93"
  _expect_requests a 1
  e2e_expect_equal "?? 1" "$(tail -1 "$(e2e_stub_log a)" | jq -r '.body.state.file.status + " " + (.body.state.file.diff | [splits("\n")] | map(select(. == "+new line two")) | length | tostring)')" "untracked status and content sent"
  printf '\000\001\002binary' > "$E2E_REPO/docs/blob.bin"
  e2e_run_bin "$C_HELPER" ask --file docs/blob.bin --issue 270 --signals ""
  _expect_requests a 2
  e2e_expect_equal "(binary)" "$(tail -1 "$(e2e_stub_log a)" | jq -r '.body.state.file.diff')" "binary diff sent"
  seq 1 600 > "$E2E_REPO/docs/long.md"
  e2e_run_bin "$C_HELPER" ask --file docs/long.md --issue 270 --signals ""
  e2e_expect_line "S1_TRUNCATED=true"
  _expect_requests a 3
  e2e_expect_equal 400 "$(tail -1 "$(e2e_stub_log a)" | jq -r '.body.state.file.diff | rtrimstr("\n") | split("\n") | length')" "diff lines sent"
  printf 'spaced\n' > "$E2E_REPO/docs/my notes.md"
  e2e_run_bin "$C_HELPER" ask --file "docs/my notes.md" --issue 270 --signals ""
  e2e_expect_equal 0 "$E2E_RC" "exit status for a path with a space"
  e2e_expect_line "S1_ESTIMATE=0.93"
  _expect_requests a 4
  e2e_expect_equal 1 "$(_records | jq -r '.ref' | grep -c '^classify:issue-270/sha256:[0-9a-f]\{16\}$')" "records for the spaced path under a digest ref"
  # One line of 9000000 bytes is under the line cap. Passed whole, the state
  # would be over the client's 8 MiB limit and get no answer
  # (state-too-large); cut to 64 KiB it is asked.
  # The issue is fetched after the diff is written, so a gh that measures
  # the helper's copy of the diff sees how much of the file was copied. It
  # must be at most 512 KiB, eight times the 64 KiB sent, not 9000000 bytes.
  head -c 9000000 /dev/zero | tr '\0' a > "$E2E_REPO/docs/wide.txt"
  tmpd="$E2E_DIR/tmp"
  mkdir -p "$tmpd"
  mv "$E2E_BIN/gh" "$E2E_BIN/gh.real"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' 'for f in "$TMPDIR"/flow-classify-s1.*/diff.full; do [ -f "$f" ] && wc -c < "$f" | tr -d " " >> "$E2E_DIR/diff-size.log"; done' 'exec "$E2E_DIR/bin/gh.real" "$@"' > "$E2E_BIN/gh"
  chmod +x "$E2E_BIN/gh"
  e2e_run_bin TMPDIR="$tmpd" "$C_HELPER" ask --file docs/wide.txt --issue 270 --signals ""
  e2e_expect_line "S1_ESTIMATE=0.93"
  e2e_expect_line "S1_TRUNCATED=true"
  _expect_requests a 5
  e2e_expect_equal 524288 "$(cat "$E2E_DIR/diff-size.log" 2>/dev/null)" "bytes of the diff copied for a 9000000-byte file"
  mv "$E2E_BIN/gh.real" "$E2E_BIN/gh"
  rm "$E2E_REPO/docs/wide.txt"
  e2e_expect_clean_edges
fi

if _want directory-never-sent; then
  _flow_test_begin "directory-never-sent"
  _c_setup directory-never-sent "site on, a tracked directory config/ holding a changed config/app.md and a changed config/.env: --file config, --file . and --file config/ (with config/ then deleted) each give S1_REASON=no-diff, with no request and nothing of config/.env sent (C15)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  mkdir -p "$E2E_REPO/config"
  printf 'app\n' > "$E2E_REPO/config/app.md"
  printf 'TOKEN=old\n' > "$E2E_REPO/config/.env"
  _git add config/app.md config/.env
  _git commit -q -m config
  printf 'app\nmore\n' > "$E2E_REPO/config/app.md"
  printf 'TOKEN=abc\n' > "$E2E_REPO/config/.env"
  for p in config . config/; do
    e2e_run_bin "$C_HELPER" ask --file "$p" --issue 270 --signals ""
    e2e_expect_equal "$(printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=no-diff' "$p")" "$E2E_OUT" "stdout for --file $p"
  done
  rm "$E2E_REPO/config/app.md" "$E2E_REPO/config/.env"
  rmdir "$E2E_REPO/config"
  e2e_run_bin "$C_HELPER" ask --file config --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=config\nS1_ESTIMATE=none\nS1_REASON=no-diff')" "$E2E_OUT" "stdout for a deleted directory"
  _expect_requests a 0
  # A directory with exactly one changed file, config/.env: one diff, so only
  # the check that git's first entry is the path itself refuses it (C29).
  _git checkout -q -- config
  printf 'TOKEN=abc\n' > "$E2E_REPO/config/.env"
  e2e_run_bin "$C_HELPER" ask --file config --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=config\nS1_ESTIMATE=none\nS1_REASON=no-diff')" "$E2E_OUT" "stdout for a directory holding one changed .env"
  _expect_requests a 0
  _git checkout -q -- config
  # A tracked file replaced by a directory holding a staged cfg/.env: git's
  # first entry is the deleted file cfg itself, so only the one-diff check
  # refuses it (C29).
  printf 'plain settings line for the tool\n' > "$E2E_REPO/cfg"
  _git add cfg
  _git commit -q -m cfg
  _git rm -q --cached cfg
  rm "$E2E_REPO/cfg"
  mkdir "$E2E_REPO/cfg"
  printf 'TOKEN=abc\n' > "$E2E_REPO/cfg/.env"
  _git add -f cfg/.env
  e2e_run_bin "$C_HELPER" ask --file cfg --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=cfg\nS1_ESTIMATE=none\nS1_REASON=no-diff')" "$E2E_OUT" "stdout for a file replaced by a directory"
  _expect_requests a 0
  # The single file in the directory is still asked about.
  printf 'app\nmore\n' > "$E2E_REPO/docs/app.md"
  _git add docs/app.md
  e2e_run_bin "$C_HELPER" ask --file docs/app.md --issue 270 --signals ""
  e2e_expect_line "S1_ESTIMATE=0.93"
  _expect_requests a 1
  e2e_expect_equal 0 "$(grep -c 'TOKEN=' "$(e2e_stub_log a)")" "requests holding config/.env content"
  e2e_expect_clean_edges
fi

if _want plugin-in-repository; then
  _flow_test_begin "plugin-in-repository"
  _c_setup plugin-in-repository "the plugin sits inside the repository, as in synapti-marketplace, and the user's settings set the site on: the user's mode cannot be read there, so S1_REASON=settings-refused, with no warning and no request, whether the site is on or left out (C14)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  mkdir -p "$E2E_REPO/plugins"
  cp -R "$E2E_PLUGIN_DIR" "$E2E_REPO/plugins/flow"
  # e2e_run_bin runs the helper from E2E_ACTIVE_PLUGIN.
  # shellcheck disable=SC2034
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugins/flow"
  e2e_run_bin "$C_HELPER" ask --file docs/notes.md --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=settings-refused')" "$E2E_OUT" "stdout"
  e2e_expect_err_lacks "WARN"
  _expect_requests a 0
  # With the site left out the user's mode is just as unknown, and the
  # repository's shadow does not count without it.
  _settings -
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"classify.serves-issue":"shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  e2e_run_bin "$C_HELPER" ask --file docs/notes.md --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=settings-refused')" "$E2E_OUT" "stdout with the site left out"
  e2e_run_bin "$C_HELPER" record --file docs/notes.md --issue 270 --signals "" --decision include
  e2e_expect_equal "" "$E2E_OUT" "record stdout with the repository at shadow"
  _expect_requests a 0
  e2e_expect_clean_edges
fi

if _want issue-fetched-once; then
  _flow_test_begin "issue-fetched-once"
  _c_setup issue-fetched-once "site on, three uncertain files: the classify block fetches the issue once per run, not once per file, and leaves no directory behind; when that fetch fails, every file gets S1_REASON=no-issue after one call; the shadow record block also fetches once (C17)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  mv "$E2E_BIN/gh" "$E2E_BIN/gh.real"
  # A gh that logs each call, then answers as the harness stub does.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$E2E_DIR/gh-calls.log"' 'exec "$E2E_DIR/bin/gh.real" "$@"' > "$E2E_BIN/gh"
  chmod +x "$E2E_BIN/gh"
  printf 'one\n' > "$E2E_REPO/docs/one.md"
  printf 'two\n' > "$E2E_REPO/docs/two.md"
  three=$(printf 'docs/notes.md\ndocs/one.md\ndocs/two.md')
  tmpd="$E2E_DIR/tmp"
  mkdir -p "$tmpd"
  _classify TMPDIR="$tmpd" FILES="$three" ISSUE_NUM=270
  e2e_expect_equal 3 "$(grep -c '^S1_ESTIMATE=0.93$' <<<"$E2E_OUT")" "files with an estimate"
  _expect_requests a $((3 * C_SH))
  e2e_expect_equal "$C_SH" "$(grep -c '^issue view 270' "$E2E_DIR/gh-calls.log")" "gh issue view calls"
  e2e_expect_equal "" "$(find "$tmpd" -maxdepth 1 -name 'flow-classify-issue.*')" "issue directories left behind"
  : > "$E2E_DIR/gh-calls.log"
  e2e_gh_fail issue-270
  _classify TMPDIR="$tmpd" FILES="$three" ISSUE_NUM=270
  e2e_expect_equal 3 "$(grep -c '^S1_REASON=no-issue$' <<<"$E2E_OUT")" "files with no-issue"
  e2e_expect_equal "$C_SH" "$(grep -c '^issue view 270' "$E2E_DIR/gh-calls.log")" "gh issue view calls when the fetch fails"
  _expect_requests a $((3 * C_SH))
  rm "$E2E_GH/issue-270.fail"
  : > "$E2E_DIR/gh-calls.log"
  _settings shadow
  _record TMPDIR="$tmpd" FILES="$three" ISSUE_NUM=270 DECISION_1=include DECISION_2=exclude DECISION_3=include
  _expect_requests a $((6 * C_SH))
  e2e_expect_equal "$C_SH" "$(grep -c '^issue view 270' "$E2E_DIR/gh-calls.log")" "gh issue view calls from the record block"
  e2e_expect_equal "" "$(find "$tmpd" -maxdepth 1 -name 'flow-classify-issue.*')" "issue directories left behind by the record block"
  e2e_expect_clean_edges
fi

if _want arguments; then
  _flow_test_begin "arguments"
  _c_setup arguments "wrong arguments exit 2: no subcommand, an unknown one, ask without --file, record without --decision or with another value, --decision given to ask, and mode given any argument; mode prints the site's mode"
  e2e_run_bin "$C_HELPER"
  e2e_expect_equal 2 "$E2E_RC" "exit status with no subcommand"
  e2e_run_bin "$C_HELPER" tell --file docs/notes.md --issue 270 --signals ""
  e2e_expect_equal 2 "$E2E_RC" "exit status for an unknown subcommand"
  e2e_run_bin "$C_HELPER" ask --issue 270 --signals ""
  e2e_expect_equal 2 "$E2E_RC" "exit status for ask without --file"
  e2e_run_bin "$C_HELPER" record --file docs/notes.md --issue 270 --signals ""
  e2e_expect_equal 2 "$E2E_RC" "exit status for record without --decision"
  e2e_run_bin "$C_HELPER" record --file docs/notes.md --issue 270 --signals "" --decision maybe
  e2e_expect_equal 2 "$E2E_RC" "exit status for record with --decision maybe"
  e2e_run_bin "$C_HELPER" ask --file docs/notes.md --issue 270 --signals "" --decision include
  e2e_expect_equal 2 "$E2E_RC" "exit status for ask with --decision"
  e2e_run_bin "$C_HELPER" record --file docs/notes.md --issue 270 --signals "" --decision include-cleanup
  e2e_expect_equal 0 "$E2E_RC" "exit status for record with --decision include-cleanup (site off)"
  e2e_run_bin "$C_HELPER" mode --file docs/notes.md
  e2e_expect_equal 2 "$E2E_RC" "exit status for mode with --file"
  e2e_run_bin "$C_HELPER" mode
  e2e_expect_equal 0 "$E2E_RC" "exit status for mode"
  e2e_expect_equal off "$E2E_OUT" "mode with no settings"
  e2e_stub_start a "$(_reply 0.93)"
  _settings shadow
  e2e_run_bin "$C_HELPER" mode
  e2e_expect_equal shadow "$E2E_OUT" "mode with the site in shadow"
  e2e_expect_clean_edges
fi

if _want start-run-records; then
  _flow_test_begin "start-run-records"
  _c_setup start-run-records "/flow:start step 8 runs the same blocks with RUN_ID: in shadow the record block writes into .flow/runs/<RUN_ID>/system-one.jsonl and not the per-user file; in on the classify block does the same; step 8 sends uncertain files to the user and names both blocks (C10)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings shadow
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  _c_block commands/start.md S1_RECORD_BLOCK RUN_ID=r1 FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only" DECISION_1=include
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_records "$E2E_REPO/.flow/runs/r1/system-one.jsonl" | jq -c 'select(.mode == "shadow" and .current == "include")' | wc -l | tr -d ' ')" "shadow records in the run"
  e2e_expect_equal 0 "$(_record_count)" "per-user records"
  _settings on
  _c_block commands/start.md S1_CLASSIFY_BLOCK RUN_ID=r1 FILES="docs/notes.md" ISSUE_NUM=270 SIGNALS_1="sibling only"
  e2e_expect_line "S1_ESTIMATE=0.93"
  e2e_expect_equal "$C_SH" "$(_records "$E2E_REPO/.flow/runs/r1/system-one.jsonl" | jq -c 'select(.mode == "on" and .current == "uncertain")' | wc -l | tr -d ' ')" "on records in the run"
  e2e_expect_equal 0 "$(_record_count)" "per-user records after the classify block"
  step8=$(awk '/^  8\. Per-task change classification:/{on=1} on&&/^  8b\./{exit} on' "$E2E_PLUGIN_DIR/commands/start.md")
  case "$step8" in *uncertain*) _e2e_result pass "step 8 names uncertain files" ;; *) _e2e_result fail "step 8 names uncertain files" ;; esac
  case "$step8" in *S1_CLASSIFY_BLOCK*S1_RECORD_BLOCK*) _e2e_result pass "step 8 names both blocks" ;; *) _e2e_result fail "step 8 names both blocks" ;; esac
  e2e_expect_clean_edges
fi

if _want blocks-match; then
  _flow_test_begin "blocks-match"
  _c_setup blocks-match "commit.md and start.md carry the same two blocks, so a fix to one reaches the other, and Flow's destructive-command hook lets each run"
  for b in S1_CLASSIFY_BLOCK S1_RECORD_BLOCK; do
    c=$( (cd "$E2E_PLUGIN_DIR" && flow_block commands/commit.md "$b") 2>&1)
    s=$( (cd "$E2E_PLUGIN_DIR" && flow_block commands/start.md "$b") 2>&1)
    if [ -n "$c" ] && [ "$c" = "$s" ]; then _e2e_result pass "$b is the same in commit.md and start.md"
    else _e2e_result fail "$b is the same in commit.md and start.md"; fi
    # A session runs the block through the Bash tool, where Flow's own
    # destructive-command hook refuses a recursive forced remove.
    e2e_run_hook hooks/scripts/block-destructive.sh "$(jq -nc --arg c "$c" '{tool_name: "Bash", tool_input: {command: $c}}')"
    e2e_expect_equal 0 "$E2E_RC" "block-destructive.sh lets $b run"
  done
  # The estimate is a note: both commands say it never changes the
  # classification, the Recommendation or the options.
  for md in commit.md start.md; do
    if grep -q 'The estimate never changes the classification, the Recommendation.* the options' "$E2E_PLUGIN_DIR/commands/$md"
    then _e2e_result pass "$md says the estimate never changes the classification, the Recommendation or the options"
    else _e2e_result fail "$md says the estimate never changes the classification, the Recommendation or the options"; fi
  done
  # Step 10 of /flow:start does not complete a task while a file step 8 sent
  # to the user is unresolved.
  if grep -q '^      - No unresolved uncertain or out-of-context files from this task$' "$E2E_PLUGIN_DIR/commands/start.md"
  then _e2e_result pass "step 10 waits for uncertain and out-of-context files"
  else _e2e_result fail "step 10 waits for uncertain and out-of-context files"; fi
fi

# _c_fill <command file> <block> [NAME=value ...] — the whole fence holding
# the block, with each template line NAME='{...}' filled the way the session
# fills it: its value put between the quotes the template shows. Names the
# template has and the arguments do not get an empty value. The result is
# $E2E_DIR/fence.sh.raw, ready for _e2e_run_code.
_c_fill() {
  local md="$1" blk="$2"
  shift 2
  e2e_fence "$E2E_ACTIVE_PLUGIN/$md" "# ${blk}_BEGIN" | python3 -I -c '
import re, sys
kv = dict(a.split("=", 1) for a in sys.argv[1:])
for line in sys.stdin:
    m = re.match(r"^([A-Z][A-Z0-9_]*)=\x27\{.*\}\x27$", line.rstrip("\n"))
    if m:
        line = "%s=\x27%s\x27\n" % (m.group(1), kv.get(m.group(1), ""))
    sys.stdout.write(line)
' "$@" > "$E2E_DIR/fence.sh.raw"
}

if _want hostile-input-stays-data; then
  _flow_test_begin "hostile-input-stays-data"
  _c_setup hostile-input-stays-data "the session fills each block's template for a file named docs/a'\$(touch PWNED)'.md with a signal holding an apostrophe: nothing is run, no PWNED file appears, the file is asked about in on mode and recorded in shadow mode, and the signal is sent as written (C20)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  hp="docs/a'\$(touch PWNED)'.md"
  printf 'hostile\n' > "$E2E_REPO/$hp"
  sig="the issue's own words"
  tmpd="$E2E_DIR/tmp"
  mkdir -p "$tmpd"
  for sh in $E2E_FENCE_SHELLS; do
    C_INPUT=$(TMPDIR="$tmpd" mktemp "$tmpd/tmp.XXXXXX")
    _c_input "$C_INPUT" FILES="$hp" SIGNALS_1="$sig"
    _c_fill commands/commit.md S1_CLASSIFY_BLOCK S1_INPUT="$C_INPUT" FILES="$hp" SIGNALS_1="$sig" ISSUE_NUM=270
    E2E_FENCE_SHELLS="$sh" _e2e_run_code "commands/commit.md (filled S1_CLASSIFY_BLOCK fence)" "" TMPDIR="$tmpd"
    e2e_expect_line "S1_FILE=$hp"
    e2e_expect_line "S1_ESTIMATE=0.93"
  done
  _expect_requests a "$C_SH"
  e2e_expect_equal '["the issue'"'"'s own words"]' "$(head -1 "$(e2e_stub_log a)" | jq -c '.body.state.signals')" "signals sent"
  _settings shadow
  for sh in $E2E_FENCE_SHELLS; do
    C_INPUT=$(TMPDIR="$tmpd" mktemp "$tmpd/tmp.XXXXXX")
    _c_input "$C_INPUT" FILES="$hp" SIGNALS_1="$sig" DECISION_1=include
    _c_fill commands/start.md S1_RECORD_BLOCK S1_INPUT="$C_INPUT" FILES="$hp" SIGNALS_1="$sig" DECISION_1=include ISSUE_NUM=270
    E2E_FENCE_SHELLS="$sh" _e2e_run_code "commands/start.md (filled S1_RECORD_BLOCK fence)" "" TMPDIR="$tmpd"
    e2e_expect_equal "" "$E2E_OUT" "record block stdout under $sh"
  done
  _expect_requests a $((2 * C_SH))
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.mode == "shadow" and .current == "include")' | wc -l | tr -d ' ')" "shadow records"
  e2e_expect_equal "" "$(find "$E2E_DIR" -name PWNED)" "PWNED files created"
  e2e_expect_clean_edges
fi

if _want input-refused; then
  _flow_test_begin "input-refused"
  _c_setup input-refused "S1_INPUT names a file outside TMPDIR, a symlink in TMPDIR to it, a hard link in TMPDIR to it, a relative path, or a file in TMPDIR holding two JSON values or a path with a newline: S1_INPUT=refused with the reason, nothing sent, the file outside TMPDIR left as it was; the record block says no records were written in shadow mode and prints nothing with the site on (C21, C30)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  tmpd="$E2E_DIR/tmp"
  mkdir -p "$tmpd" "$E2E_DIR/elsewhere"
  outside="$E2E_DIR/elsewhere/input.json"
  _c_input "$outside" FILES=docs/notes.md
  ln -s "$outside" "$tmpd/tmp.link"
  ln "$outside" "$tmpd/tmp.hard"
  for in_file in "$outside" "$tmpd/tmp.link" "$tmpd/tmp.hard" "../tmp/tmp.hard"; do
    e2e_run_block TMPDIR="$tmpd" S1_INPUT="$in_file" ISSUE_NUM=270 commands/commit.md S1_CLASSIFY_BLOCK
    e2e_expect_equal "$(printf 'S1_INPUT=refused\nS1_REASON=input-not-from-mktemp')" "$E2E_OUT" "stdout for S1_INPUT=${in_file#"$E2E_DIR"/}"
  done
  e2e_expect_equal '{"files": [{"path": "docs/notes.md"}]}' "$(cat "$outside")" "the file outside TMPDIR, unchanged"
  for raw in '{"files":[]} {"files":[]}' '{"files":[{"path":"docs/notes.md\nx"}]}' '[]' '{"files":[{"path":""}]}'; do
    C_INPUT=$(TMPDIR="$tmpd" mktemp "$tmpd/tmp.XXXXXX")
    printf '%s' "$raw" > "$C_INPUT"
    E2E_FENCE_SHELLS=bash e2e_run_block TMPDIR="$tmpd" S1_INPUT="$C_INPUT" ISSUE_NUM=270 commands/commit.md S1_CLASSIFY_BLOCK
    e2e_expect_equal "$(printf 'S1_INPUT=refused\nS1_REASON=input-invalid')" "$E2E_OUT" "stdout for input $raw"
  done
  e2e_run_block TMPDIR="$tmpd" S1_INPUT="$outside" ISSUE_NUM=270 commands/commit.md S1_RECORD_BLOCK
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  e2e_expect_equal "" "$E2E_ERR" "record block stderr with the site on"
  _settings shadow
  e2e_run_block TMPDIR="$tmpd" S1_INPUT="$outside" ISSUE_NUM=270 commands/commit.md S1_RECORD_BLOCK
  e2e_expect_equal "" "$E2E_OUT" "record block stdout in shadow mode"
  e2e_expect_equal "flow: WARN: no System One records were written: input-not-from-mktemp" "$E2E_ERR" "record block warning in shadow mode"
  _expect_requests a 0
  e2e_expect_clean_edges
fi

if _want renamed-red-flag-never-sent; then
  _flow_test_begin "renamed-red-flag-never-sent"
  _c_setup renamed-red-flag-never-sent "a committed .env renamed with git mv to docs/moved.md, copied with cp and staged as docs/copy.md, or moved with mv (no git) to docs/untracked.md: asking or recording any of the new names gives red-flag, and no request holds the file's content; an unrelated rename is still asked (C23)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  printf 'SECRET_TOKEN=zzz\nOTHER=1\n' > "$E2E_REPO/.env"
  _git add -f .env
  _git commit -q -m env
  _git mv .env docs/moved.md
  e2e_run_bin "$C_HELPER" ask --file docs/moved.md --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=docs/moved.md\nS1_ESTIMATE=none\nS1_REASON=red-flag')" "$E2E_OUT" "stdout for a renamed .env"
  _settings shadow
  e2e_run_bin "$C_HELPER" record --file docs/moved.md --issue 270 --signals "" --decision include
  e2e_expect_equal "S1_REASON=red-flag" "$E2E_OUT" "record stdout for a renamed .env"
  _expect_requests a 0
  _settings on
  _git mv docs/moved.md .env
  # A staged copy of the committed, unchanged .env: git reports it as added.
  cp "$E2E_REPO/.env" "$E2E_REPO/docs/copy.md"
  _git add docs/copy.md
  e2e_expect_equal "A  docs/copy.md" "$(_git status --porcelain -- docs/copy.md)" "git status of the staged copy"
  e2e_run_bin "$C_HELPER" ask --file docs/copy.md --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=docs/copy.md\nS1_ESTIMATE=none\nS1_REASON=red-flag')" "$E2E_OUT" "stdout for a staged copy of .env"
  _settings shadow
  e2e_run_bin "$C_HELPER" record --file docs/copy.md --issue 270 --signals "" --decision include
  e2e_expect_equal "S1_REASON=red-flag" "$E2E_OUT" "record stdout for a staged copy of .env"
  _settings on
  _git rm -q --cached docs/copy.md
  rm -f "$E2E_REPO/docs/copy.md"
  # mv without git: .env shows as deleted and docs/untracked.md as untracked.
  mv "$E2E_REPO/.env" "$E2E_REPO/docs/untracked.md"
  e2e_expect_equal "?? docs/untracked.md" "$(_git status --porcelain --untracked-files=all -- docs/untracked.md)" "git status of the moved file"
  e2e_run_bin "$C_HELPER" ask --file docs/untracked.md --issue 270 --signals ""
  e2e_expect_equal "$(printf 'S1_FILE=docs/untracked.md\nS1_ESTIMATE=none\nS1_REASON=red-flag')" "$E2E_OUT" "stdout for .env moved without git"
  mv "$E2E_REPO/docs/untracked.md" "$E2E_REPO/.env"
  _expect_requests a 0
  # An unrelated rename is still asked about.
  _git mv docs/notes.md docs/renamed.md
  e2e_run_bin "$C_HELPER" ask --file docs/renamed.md --issue 270 --signals ""
  e2e_expect_line "S1_ESTIMATE=0.93"
  _expect_requests a 1
  e2e_expect_equal 0 "$(grep -c 'SECRET_TOKEN' "$(e2e_stub_log a)")" "requests holding the .env content"
  e2e_expect_clean_edges
fi

if _want record-failure-warns; then
  _flow_test_begin "record-failure-warns"
  _c_setup record-failure-warns "site shadow: of three files, one with decision include is recorded, one with Include and one with no decision get one warning line each and no request; with no issue, each file's warning says no-issue, and a RUN_ID the helper refuses says arguments-refused; include-cleanup is recorded as it is (C24, C28)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings shadow
  printf 'Other\n' > "$E2E_REPO/docs/other.md"
  printf 'Third\n' > "$E2E_REPO/docs/third.md"
  _record FILES="$(printf 'docs/notes.md\ndocs/other.md\ndocs/third.md')" ISSUE_NUM=270 DECISION_1=include DECISION_2=Include
  e2e_expect_equal 0 "$E2E_RC" "record block exit status"
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  e2e_expect_equal "$(printf 'flow: WARN: no System One record for docs/other.md: decision-invalid (include, include-cleanup or exclude)\nflow: WARN: no System One record for docs/third.md: decision-invalid (include, include-cleanup or exclude)')" "$E2E_ERR" "record block warnings"
  _expect_requests a "$C_SH"
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.current == "include")' | wc -l | tr -d ' ')" "records with current=include"
  _record FILES="$(printf 'docs/notes.md\ndocs/other.md')" ISSUE_NUM="" DECISION_1=include DECISION_2=exclude
  e2e_expect_equal "$(printf 'flow: WARN: no System One record for docs/notes.md: no-issue\nflow: WARN: no System One record for docs/other.md: no-issue')" "$E2E_ERR" "record block warnings with no issue"
  _expect_requests a "$C_SH"
  _record FILES="docs/other.md" ISSUE_NUM=270 RUN_ID="../x" DECISION_1=include
  e2e_expect_equal "flow: WARN: no System One record for docs/other.md: arguments-refused" "$E2E_ERR" "record block warning for a RUN_ID the helper refuses"
  _expect_requests a "$C_SH"
  _record FILES="docs/other.md" ISSUE_NUM=270 DECISION_1=include-cleanup
  e2e_expect_equal "" "$E2E_ERR" "record block stderr for include-cleanup"
  _expect_requests a $((2 * C_SH))
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.current == "include-cleanup" and .ref == "classify:issue-270/docs/other.md")' | wc -l | tr -d ' ')" "records with current=include-cleanup"
  e2e_expect_clean_edges
fi

if _want provider-unavailable-stops-asking; then
  _flow_test_begin "provider-unavailable-stops-asking"
  _c_setup provider-unavailable-stops-asking "a stub that answers after 1500 ms with timeoutMs 300, three files: in on mode the first file times out and the other two get S1_REASON=provider-unavailable with no request; in shadow mode the first is recorded as a timeout and the other two each get one warning line; a stub answering 503 stops asking the same way (C25)"
  e2e_stub_start a "{\"delay_ms\":1500,$(_reply 0.93 | sed 's/^{//')"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:300,uses:{"classify.serves-issue":"on"}}}')"
  printf 'one\n' > "$E2E_REPO/docs/one.md"
  printf 'two\n' > "$E2E_REPO/docs/two.md"
  three=$(printf 'docs/notes.md\ndocs/one.md\ndocs/two.md')
  _classify FILES="$three" ISSUE_NUM=270
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=none\nS1_REASON=timeout\nS1_FILE=docs/one.md\nS1_ESTIMATE=none\nS1_REASON=provider-unavailable\nS1_FILE=docs/two.md\nS1_ESTIMATE=none\nS1_REASON=provider-unavailable')" "$E2E_OUT" "stdout"
  _expect_requests a "$C_SH"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:300,uses:{"classify.serves-issue":"shadow"}}}')"
  _record FILES="$three" ISSUE_NUM=270 DECISION_1=include DECISION_2=exclude DECISION_3=include
  e2e_expect_equal "" "$E2E_OUT" "record block stdout"
  e2e_expect_equal "$(printf 'flow: WARN: no System One record for docs/one.md: provider-unavailable\nflow: WARN: no System One record for docs/two.md: provider-unavailable')" "$E2E_ERR" "record block warnings"
  _expect_requests a $((2 * C_SH))
  e2e_expect_equal "$C_SH" "$(_records | jq -c 'select(.mode == "shadow" and .result == "timeout" and .current == "include")' | wc -l | tr -d ' ')" "shadow records of the timeout"
  e2e_stub_start b '{"status":503,"body":{"detail":"busy"}}'
  _settings on b
  _classify FILES="$three" ISSUE_NUM=270
  e2e_expect_equal "$(printf 'S1_REASON=http-503\nS1_REASON=provider-unavailable\nS1_REASON=provider-unavailable')" "$(grep '^S1_REASON=' <<<"$E2E_OUT")" "reasons with a 503"
  _expect_requests b "$C_SH"
  e2e_expect_clean_edges
fi

if _want time-budget; then
  _flow_test_begin "time-budget"
  _c_setup time-budget "site on, a stub that answers after 1500 ms, three files, and a budget of 1 second: the first file is answered, the other two get S1_REASON=not-asked-time with no request; the record block in shadow mode records the first and warns for the other two (C25)"
  e2e_stub_start a "{\"delay_ms\":1500,$(_reply 0.93 | sed 's/^{//')"
  _settings on
  printf 'one\n' > "$E2E_REPO/docs/one.md"
  printf 'two\n' > "$E2E_REPO/docs/two.md"
  three=$(printf 'docs/notes.md\ndocs/one.md\ndocs/two.md')
  _classify FLOW_S1_CLASSIFY_BUDGET_S=1 FILES="$three" ISSUE_NUM=270
  e2e_expect_equal "$(printf 'S1_FILE=docs/notes.md\nS1_ESTIMATE=0.93\nS1_MODEL=jev-1.13.0\nS1_TRUNCATED=false\nS1_FILE=docs/one.md\nS1_ESTIMATE=none\nS1_REASON=not-asked-time\nS1_FILE=docs/two.md\nS1_ESTIMATE=none\nS1_REASON=not-asked-time')" "$E2E_OUT" "stdout"
  _expect_requests a "$C_SH"
  _settings shadow
  _record FLOW_S1_CLASSIFY_BUDGET_S=1 FILES="$three" ISSUE_NUM=270 DECISION_1=include DECISION_2=exclude DECISION_3=include
  e2e_expect_equal "$(printf 'flow: WARN: no System One record for docs/one.md: not-asked-time\nflow: WARN: no System One record for docs/two.md: not-asked-time')" "$E2E_ERR" "record block warnings"
  _expect_requests a $((2 * C_SH))
  e2e_expect_clean_edges
fi

if _want gh-stall-bounded; then
  _flow_test_begin "gh-stall-bounded"
  _c_setup gh-stall-bounded "site on, a gh issue view that sleeps 60 seconds: the first file gets S1_REASON=no-issue within 25 seconds and marks the fetch failed, the second file gets no-issue at once, and nothing is sent (C26)"
  e2e_stub_start a "$(_reply 0.93)"
  _settings on
  mv "$E2E_BIN/gh" "$E2E_BIN/gh.real"
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 60' > "$E2E_BIN/gh"
  chmod +x "$E2E_BIN/gh"
  printf 'one\n' > "$E2E_REPO/docs/one.md"
  cache="$E2E_DIR/issue-cache"
  mkdir -p "$cache"
  t0=$(date +%s)
  e2e_run_bin "$C_HELPER" ask --file docs/notes.md --issue 270 --signals "" --issue-cache "$cache"
  took=$(( $(date +%s) - t0 ))
  e2e_expect_line "S1_REASON=no-issue"
  if [ "$took" -lt 25 ]; then _e2e_result pass "the stalled fetch ended within 25 seconds (took $took)"
  else _e2e_result fail "the stalled fetch ended within 25 seconds (took $took)"; fi
  e2e_expect_equal yes "$([ -e "$cache/issue.failed" ] && echo yes || echo no)" "the failed fetch is marked"
  t0=$(date +%s)
  e2e_run_bin "$C_HELPER" ask --file docs/one.md --issue 270 --signals "" --issue-cache "$cache"
  took=$(( $(date +%s) - t0 ))
  e2e_expect_line "S1_REASON=no-issue"
  if [ "$took" -lt 5 ]; then _e2e_result pass "the second file did not wait (took $took)"
  else _e2e_result fail "the second file did not wait (took $took)"; fi
  _expect_requests a 0
  mv "$E2E_BIN/gh.real" "$E2E_BIN/gh"
  e2e_expect_clean_edges
fi

if _want stopped-block-leaves-nothing; then
  _flow_test_begin "stopped-block-leaves-nothing"
  _c_setup stopped-block-leaves-nothing "site on, a stub that answers after 1500 ms: the classify block, stopped with TERM while it waits on the provider, leaves no issue directory in TMPDIR, under each shell (C27)"
  e2e_stub_start a "{\"delay_ms\":1500,$(_reply 0.93 | sed 's/^{//')"
  _settings on
  tmpd="$E2E_DIR/tmp"
  mkdir -p "$tmpd"
  (cd "$E2E_ACTIVE_PLUGIN" && flow_block commands/commit.md S1_CLASSIFY_BLOCK) > "$E2E_DIR/classify-block.sh"
  # shellcheck disable=SC2016
  printf '%s\n' 'sh="$1"; blk="$2"; log="$3"; n="$4"' \
    '"$sh" "$blk" > /dev/null 2>&1 &' 'pid=$!' 'i=0' \
    'while [ "$i" -lt 100 ]; do [ "$(wc -l < "$log" 2>/dev/null | tr -d " ")" -gt "$n" ] && break; sleep 0.1; i=$((i + 1)); done' \
    'kill -TERM "$pid"' 'wait "$pid"' 'printf "stopped=%s\n" "$?"' > "$E2E_DIR/stop.sh"
  for sh in $E2E_FENCE_SHELLS; do
    C_INPUT=$(TMPDIR="$tmpd" mktemp "$tmpd/tmp.XXXXXX")
    _c_input "$C_INPUT" FILES=docs/notes.md
    before=$(e2e_stub_requests a)
    _e2e_exec env TMPDIR="$tmpd" S1_INPUT="$C_INPUT" ISSUE_NUM=270 bash "$E2E_DIR/stop.sh" "$sh" "$E2E_DIR/classify-block.sh" "$(e2e_stub_log a)" "$before"
    e2e_expect_equal $((before + 1)) "$(e2e_stub_requests a)" "requests under $sh before the stop"
    e2e_expect_equal "stopped=143" "$E2E_OUT" "exit status of the stopped block under $sh"
    e2e_expect_equal "" "$(find "$tmpd" -maxdepth 1 -name 'flow-classify-issue.*')" "issue directories left behind under $sh"
  done
  e2e_expect_clean_edges
fi
