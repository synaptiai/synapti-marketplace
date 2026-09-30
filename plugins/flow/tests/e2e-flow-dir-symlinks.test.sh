# shellcheck shell=bash
# End-to-end: flow never creates or writes a file through a symlinked
# directory under .flow/ or the decision journal, never reads a goal through
# one, and never writes the journal outside the repository because the
# repository's own settings say so.
#
# A repository can commit .flow, .flow/runs, .flow/goals or .decisions as a
# symlink to a directory outside the checkout. Each writer refused a symlink at
# the file it writes, but followed one at a directory above it, so the run
# state, goals, evidence and journal entries landed in the link's target; the
# readers of .flow/goals followed it too, so the Stop hook and the gates acted
# on a goal that belongs elsewhere. Each scenario plants such a link to
# $E2E_DIR/outside in a scratch repository, runs the writer or reader the way
# flow reaches it (the shipped command block or hook when one runs as
# committed; otherwise the helper, with the arguments the command or skill
# passes it), and checks that the target is left exactly as it was, that the
# refusal is on stderr, and the exit status the code's header gives for it.
#
# journal.dir is the other way out of the repository: .claude/settings.flow.json
# is committed, so a repository chooses where its journal is written. A value
# from the repository's settings must resolve inside the repository and falls
# back to .decisions with a warning otherwise; a value from the user's own
# settings may point anywhere. The artifact for each scenario is written to
# $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   L1 flow-record-verdict.sh (/flow:goal evaluate) creates the run directory
#      and writes last-verdict.json and its lock in the target of a symlinked
#      .flow or .flow/runs: it refused only a run directory that is itself a
#      symlink
#   L2 flow-record-activity.sh (run-state-management, at every phase boundary)
#      creates activities/ and evidence/, the activity, its lock and
#      events.jsonl there
#   L3 flow-record-evidence.sh (goal-evidence-ledger) creates evidence/ and the
#      sidecar there
#   L4 flow-goal-record.sh --create (goal-contract-capture) creates .flow/goals
#      and the goal in the target of a symlinked .flow or .flow/goals
#   L5 flow-goal-record.sh --update-lifecycle, which the Stop hook runs on
#      every turn it blocks, rewrites a goal reached through a symlinked .flow
#      and leaves its lock in the link's target
#   L5b the same update run by /flow:goal's lifecycle block exits 1 with a
#      traceback instead of the 2 its header gives for a refused symlink
#   L6 journal-record.sh (the /flow:start Stranger Test block) writes the
#      journal manifest and its lock through a symlinked .decisions, or
#      creates a configured journal.dir under a symlinked parent directory
#   L7 journal-append.sh (the /flow:brainstorm decision block) does the same
#   L8 the SessionEnd hook appends a session_end event, and creates its lock,
#      in every active run it finds through a symlinked .flow, .flow/runs or
#      run directory, and says nothing about it
#   L9 the /flow:setup strip block rewrites journals under a configured
#      journal.dir whose parent directory is a symlink: it refused only a
#      journal directory that is itself one
#   L10 the /flow:trigger and /flow:watch pre-flights create .flow/triggers in
#      the target of a symlinked .flow, where the trigger is then written
#   L11 the /flow:goal pre-flight creates .flow/goals in the target of a
#      symlinked .flow
#   L12 the /flow:start journal block accepts a symlinked .decisions, and the
#      journal header is then written into its target
#   L13 run-state-management creates a run's directory through a symlinked
#      .flow or .flow/runs before it writes run.yaml there
#   L14 a path whose name climbs out of a symlinked directory with `..` is
#      accepted because its components, read without the link, are real
#   L15 the check refuses what it should not: a writer in an ordinary
#      repository, reached through macOS's /var -> /private/var, stops
#      writing
#
# Reads of .flow/goals:
#   L16 the Stop hook reads the active goal through a symlinked .flow or
#      .flow/goals, or reads a goal file that is itself a symlink, and blocks
#      or approves the stop on a goal that belongs elsewhere: its own scan
#      refused none of them
#   L17 flow-active-goal.sh, which the /flow:merge, /flow:pr and /flow:status
#      gates ask, answers with a goal read through a symlinked .flow: it
#      refused only a symlinked .flow/goals
#   L18 the /flow:goal status scan names an active goal read through a
#      symlinked .flow
#   L19 /flow:learn lists the goal files it finds through a symlinked .flow
#   L20 /flow:start resumes a goal it read through a symlinked .flow
#   L21 a refused read is silent, or the Stop hook blocks on it instead of
#      treating the goal as absent
#   L22 the read check refuses what it should not: an ordinary repository's
#      goal is no longer read
#
# journal.dir set in the repository's own settings:
#   L23 a journal.dir in .claude/settings.flow.json that leaves the repository
#      (`..`, or a directory under a symlink) is written by journal-record.sh
#      or journal-append.sh
#   L24 the same value in .claude/settings.flow.local.json, which a pull
#      request can commit as well, is not checked
#   L25 inside is decided on the string: an absolute path that only shares
#      the repository's path as a prefix (<repo>-outside) passes, or a
#      component that is a symlink passes because its name is under the
#      repository
#   L26 the refusal is silent, does not name the value and the file it came
#      from, or stops the writer instead of falling back to .decisions
#   L27 the writers and readers disagree: the /flow:setup strip refuses a
#      value journal-record.sh and journal-append.sh write to, or /flow:learn
#      or /flow:explain reads a directory the writers no longer use
#   L28 a journal.dir in the user's own settings that points outside the
#      repository is refused, warned about, or not stripped: the strip refused
#      `..` and absolute paths outside the repository, and journal-record.sh
#      warned on `..`, whichever file the value came from
#   L29 a journal.dir in the repository's settings inside the repository
#      (docs/decisions) is refused
#   L30 a file other than bin/journal-dir.sh resolves journal.dir itself, so a
#      writer or reader added later skips the rule
#   L31 a repository journal.dir that is refused falls back to .decisions even
#      when the user's own settings set a journal.dir, so the user's journal
#      is split across two directories
#   L32 the /flow:start journal block and the /flow:pr journal section use
#      .decisions whatever journal.dir says: /flow:start creates a directory no
#      writer uses, and /flow:pr reads a journal nobody wrote
#   L33 /flow:resume counts a change to the configured journal as unlinked
#      human work
#
# Reads of .flow/runs:
#   L34 a reader of .flow/runs — the /flow:learn listing, the /flow:resume
#      pre-flight, scan and run read, the /flow:status recent runs, the
#      judge's evidence bundle — reads a run through a symlinked .flow,
#      .flow/runs or run directory
#   L35 a refused run is silent, or is reported as unreadable instead of as
#      absent
#   L36 the run-read check refuses what it should not: an ordinary
#      repository's runs are no longer read
#
# Refusals the gates report:
#   L37 the /flow:merge and /flow:pr goal gates, /flow:status and the
#      gh issue create hook show a refused goal read only as
#      "flow-active-goal.sh exited 2", without the path that was refused
#
# A check that cannot run:
#   L38 when the directory check cannot run (python3 missing or failing), a
#      reader reports what a refusal or an empty directory reports:
#      /flow:status and /flow:learn show no runs or goal files, /flow:resume
#      says no runs exist or blames a symlink, /flow:start treats the goal as
#      absent, and the /flow:start journal block, the /flow:trigger and
#      /flow:watch pre-flights, run creation and the /flow:setup strip say
#      "refusing"; journal-dir.sh calls a repository journal.dir it could not
#      check refused
#
# Operands that look like options:
#   L39 a journal.dir that starts with '-' is read by flow-mkdir.sh as an
#      option: `--check` makes the /flow:start journal block fail with a usage
#      message, and `-h` prints the help and exits 0 without checking, so a
#      repository that commits `-h` as a symlink is written through
#
# Paths spelled through a symlink above the repository:
#   L40 an absolute path to the repository spelled through a symlink above it
#      (macOS /var for /private/var) counts as outside the rule, so a
#      directory the repository committed as a symlink is written through
#
# Writers run from a subdirectory:
#   L41 a writer run from a subdirectory of the repository checks only below
#      its working directory, so a path that climbs back to the repository
#      top (journal-append.sh --file ../.decisions/..., or journal-record.sh
#      with an absolute journal.dir) is written through a symlinked
#      .decisions; a Flow block can run there, since the Bash tool keeps its
#      working directory between calls
#   L42 the check from a subdirectory refuses what it should not: an ordinary
#      .decisions at the repository top is no longer written
#   L43 the check takes the wrong top: in a repository nested inside another
#      the outer one's top, or in a git worktree (whose .git is a file) no
#      top at all
#
# Per-user state:
#   L44 a home directory kept in git with ~/.claude a symlink to elsewhere (as
#      GNU stow makes it) is the repository top for a folder inside it that
#      is not a repository, so a per-user write under ~/.claude (the goal
#      trust ledger) is refused as if the repository had committed the link
#   L45 the exemption for per-user state leaks: a repository's own symlink
#      inside that home, or inside a real project repository in it, is no
#      longer refused; a repository kept inside ~/.claude loses the rule; a
#      repository symlink that points into ~/.claude, or a path that climbs
#      back into it with `..` through a repository symlink, is taken for
#      per-user state and written through
#   L46 a relative path, which only repository content uses, is taken for
#      per-user state: a folder inside ~/.claude that is not a repository, or
#      a FLOW_STATE_DIR set to a directory in the repository, lets a
#      committed .flow symlink be written through
#   L47 CLAUDE_CONFIG_DIR counts as a per-user root, though Flow keeps its
#      own files under ~/.claude whatever it says: set to a directory in the
#      repository, it exempts that directory's symlinks
#
# A journal.dir the user chose:
#   L48 an absolute journal.dir from the user's own settings runs through a
#      symlink the user made under a home kept in git (~/Dropbox), and every
#      writer refuses it as if the repository had committed the link; or the
#      exemption reaches a relative user value, or a repository value
#   L49 an absolute repository journal.dir that passes the check (it is inside
#      the repository) counts as the user's own, so a symlink the repository
#      commits below it, such as its auto-log directory, is written through
#   L50 an absolute user journal.dir that climbs back out of a repository
#      symlink with `..` counts as the user's own: the /flow:start journal
#      block creates it through the link, and the /flow:setup strip reads the
#      journals there; or only a `..` followed by another component is seen,
#      so one that ends in `..` counts as the user's own
#   L51 in a home kept in git, run with the working directory at HOME, the
#      user's own ~/.claude/settings.flow.json is read as the repository's
#      settings file: its journal.dir is refused as a repository value, the
#      user's value is skipped with it, and the journal goes to ~/.decisions
#   L52 the auto-log hooks hold an absolute user journal.dir to the
#      repository by its physical path, so a trail under a symlink the user
#      made (~/Dropbox) is never written, though the journal is; or the
#      exception reaches a journal directory the repository chose, and a
#      committed .decisions symlink gets the trail written through it; or,
#      as in L51, the hooks take the user's own settings file at HOME for
#      the repository's and write the trail to ~/.decisions
#   L53 the auto-log hooks resolve the journal dir, or ask journal-dir.sh
#      --user-owned, in their own working directory instead of at the
#      repository top: run from a subdirectory whose answer differs from the
#      top's, the hook creates the trail directory and its .gitignore through
#      a committed .decisions symlink, or writes the trail to a journal dir
#      that no writer at the top uses; or they run the symlink check in their
#      own working directory, so run from another repository while the
#      payload names this one, the check judges the wrong repository and the
#      trail is written through a committed .decisions symlink
#   L54 the auto-log hooks decide whether the journal dir is in the
#      repository by comparing its text with the repository's physical path,
#      so a user journal.dir that names the repository through a symlink
#      above it (<D>/up/repo/sub/../j) skips their containment, and the trail
#      directory and its .gitignore are created through a symlink the
#      repository commits; or one that leaves the repository with `..` gets a
#      trail in one spelling (<D>/up/repo/../j) and not in the other; or the
#      fix takes a directory whose `..` never reaches the repository
#      (<D>/x/../j) for one that leaves it and drops its trail; or a check
#      that cannot run lets the hook create the trail directory anyway
#   L55 log-commits.sh's Guard 2 decides whether a commit touched only the
#      journal by comparing the journal path's text with the repository's
#      path, so a user journal.dir that names the repository through a
#      symlink above it never matches what git reports, and a commit of the
#      journal alone gets a breadcrumb
#
# A path resolved one component at a time:
#   L56 the rule splits a path by its text into the repository and a tail,
#      while the kernel resolves it one component at a time: a doubled `/`
#      after the repository (<R>//sub/../j, <UP>/repo//sub/../j) drops the
#      repository from the tail, and a component below the top followed by
#      enough `..` to climb out (sub/../../j, absolute or relative) reads as
#      outside the repository, so a symlink the repository commits is passed
#      without being checked; or `..` after a link outside the repository
#      goes back along the name instead of to the physical parent, or a
#      writer crashes on it
#   L57 the auto-log hooks check for a symlinked trail directory only when
#      the rule refused the directory, so a user journal.dir outside the
#      repository whose auto-log is a symlink gets the trail written through
#      it; the user-owned arm writes through a committed .decisions/auto-log
#      symlink, or creates no self-ignoring .gitignore
#   L58 Guard 2 misses a journal-only commit when the journal dir is the
#      repository top (journal.dir `.`), or when git quotes the journal's
#      name (a non-ASCII journal.dir)
#   L59 the judge's evidence bundle keeps an evidence sidecar's output_ref
#      inside the evidence directory by its text, so a symlink the
#      repository commits there reads a file outside the repository into the
#      judge's prompt; or it lists and reads the sidecars through a symlinked
#      evidence directory; or it calls a refused name a symlink when it is not
#      a directory; or /flow:status reads a run's verdict or events through a
#      symlinked file
#   L60 the walk has no end: a link loop outside the repository hangs the
#      writer, a chain longer than the limit is followed and a directory
#      created at its end, or a directory under a regular file is reported
#      created
#   L61 Guard 2 reads a name that ends in a newline as the journal's path
#   L62 on Windows, where the system cleans `..` by its text before it
#      follows links, the walk follows `..` physically and judges a path
#      through a repository symlink to be outside, or reads a link target
#      rooted without a drive as relative; or it walks a name that ends in a
#      period or a space, which Win32 may open under another name (sub. as
#      sub), or cleans a path under the \\?\ prefix, which Windows passes
#      through as written
#   L63 the evidence schema, its fixture and the evidence skill give
#      output_ref as a repository path, which the bundle, reading it from the
#      sidecar's directory, never finds
#   L64 an author spells output_ref, and a name no writer creates (the
#      sidecar's id is lower-cased for the copy) is never read; or a refused
#      verdict or events file reads as none recorded; or on Windows a device
#      path (//?/, \\.\, \??\) is walked as a drive path, or as written;
#      or /flow:learn lists a run's last-verdict.json through a symlink; or a
#      refusal is cut at a "; " inside a name the repository chose; or a
#      check of the evidence directory that cannot run ends the bundle in a
#      traceback
#   L65 the recorder saves the sidecar before it copies the raw output, so a
#      copy it refuses leaves a sidecar naming a missing file, and a second
#      record of an id replaces the sidecar while the first copy stays; or
#      it names output_ref from the id before lower-casing it; or a "; " in
#      a name is cut at another reader; or, where Python writes \r\n to a
#      pipe (Windows), a shell reader keeps the \r and no longer finds the
#      refusal's fixed ending
#   L66 the recorder takes a short write for a full copy, keeps a copy when
#      the sidecar write fails for any reason other than the ones it names,
#      refuses a copy left by an interrupted record as "already exists",
#      or lets two overlapping records of one id both write; or
#      journal-dir.sh keeps a \r in the reason it names
#   L67 the recorder's clean-up removes the copy after its sidecar was
#      published (a SIGINT, or a failing step, after the publish), or a copy
#      it did not make; or it calls anything at the copy's name a copy; or a
#      data error while the sidecar is written ends in a traceback; or an
#      interrupt while the sidecar is written leaves its temporary file
#   L68 the recorder ends in a traceback on evidence it cannot read (nested
#      too deep, not UTF-8, unreadable) or whose metadata is not a mapping,
#      or gives evidence nested too deep a different exit status at the read
#      and at the write; or its clean-up removes another record's copy made
#      at its copy's name, where the file system gives the new file the
#      removed one's inode number (Linux); or it keeps its copy when another
#      record's sidecar is written first
#   L69 the recorder ends in a traceback on evidence PyYAML parses but cannot
#      build, or prints a value from the evidence file or an argument with
#      its line ends and escape sequences, or refuses evidence it cannot
#      write with the infrastructure status, or waits on a FIFO put in place
#      of an input after the shell checked it, or names a directory as
#      missing, or needs O_NOFOLLOW (absent on Windows), or cannot remove its
#      copy where an open file cannot be removed, or expands aliases into a
#      schema refusal that prints the whole value, or gives an unreadable raw
#      output the infrastructure status; or the evidence bundle ends in a
#      traceback on a sidecar PyYAML cannot build; or the overlap scenario
#      counts the records after they ended, not when the lock was let go
#   L70 the recorder has an exit path or a message its header and the
#      decision journal's table do not list, prints a value with a control
#      character or with its spaces folded, cuts the line and column off a
#      YAML error, prints an id or a run id of any length, makes the run
#      directory before refusing an unreadable raw output, checks that the
#      evidence can be written one call shallower than it writes it, or
#      opens a file in text mode on Windows

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

# FLOW_E2E_SCENARIOS=a,b runs only the scenarios whose artifacts are named a
# and b.
_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

RID="2026-05-20T143000Z-issue-42"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures"
STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
SESSION_END_HOOK="hooks/scripts/session-end-state.sh"

# _plant <path under the repository> — replace <path> with a symlink to
# $E2E_DIR/outside. What the path held moves there first, so a writer that
# follows the link finds what it would have found in the repository. BEFORE is
# what the target holds once the link is in place.
_plant() {
  local p="$E2E_REPO/$1"
  if [ -e "$p" ]; then
    mv "$p" "$E2E_DIR/outside"
  else
    mkdir -p "$E2E_DIR/outside" "$(dirname "$p")"
  fi || { _flow_assert_fail "$E2E_NAME: could not move $1 outside the repository"; return 0; }
  ln -s "$E2E_DIR/outside" "$p" || _flow_assert_fail "$E2E_NAME: could not plant the $1 symlink"
  printf 'planted: %s -> <scratch>/%s/outside\n' "$1" "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
}

# _outside_state — every entry under the link's target: a directory by name,
# a file by name and sha256. Equal before and after means nothing was created,
# removed or changed there.
_outside_state() {
  (
    cd "$E2E_DIR/outside" 2>/dev/null || exit 0
    find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r p; do
      if [ -d "$p" ] && [ ! -L "$p" ]; then printf '%s/\n' "$p"
      else printf '%s %s\n' "$p" "$(_e2e_sha256 "$p")"; fi
    done
  )
}

# _expect_untouched — the link's target holds what it held before the run.
_expect_untouched() {
  e2e_expect_equal "$BEFORE" "$(_outside_state)" "what the symlink's target holds"
}

# _expect_refused <exit status> <text> — the writer refused: its exit status,
# the refusal on stderr, and nothing written through the link.
_expect_refused() {
  e2e_expect_equal "$1" "$E2E_RC" "the exit status"
  e2e_expect_err "$2"
  _expect_untouched
}

# _expect_err_lacks <text> — stderr does not contain text.
_expect_err_lacks() {
  case "$E2E_ERR" in
    *"$1"*) _e2e_result fail "stderr lacks: $1" ;;
    *) _e2e_result pass "stderr lacks: $1" ;;
  esac
}

# _run_bin <file under the plugin> [arguments] — run a helper in the scratch
# repository as a command block or skill runs it. Sets E2E_OUT, E2E_ERR,
# E2E_RC. Arguments are paths inside the repository, so the artifact names no
# scratch directory.
_run_bin() {
  local rel="$1"; shift
  {
    printf 'code: %s\n' "$rel"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$rel")"
    printf 'arguments: %s\n' "$*"
  } >> "$E2E_ARTIFACT"
  _e2e_exec "$E2E_ACTIVE_PLUGIN/$rel" "$@"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

# _run_in <directory> <file under the plugin> [arguments] — run a helper with
# the working directory in <directory> (relative to the repository, or
# absolute). The artifact names the scratch root by its token.
_run_in() {
  local dir="$1" rel="$2"; shift 2
  local p_private="/private$E2E_ROOT" p_root="$E2E_ROOT"
  local shown="${*//"$p_private"/<scratch>}" where="${dir//"$p_private"/<scratch>}"
  shown="${shown//"$p_root"/<scratch>}"; where="${where//"$p_root"/<scratch>}"
  {
    printf 'code: %s\n' "$rel"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$rel")"
    printf 'working directory: %s\n' "$where"
    printf 'arguments: %s\n' "$shown"
  } >> "$E2E_ARTIFACT"
  _e2e_exec bash -c 'cd "$1" && shift && exec "$@"' _ "$dir" "$E2E_ACTIVE_PLUGIN/$rel" "$@"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

# _run_with_env <NAME=value ...> -- <e2e_run_fence arguments> — run a fence
# with the variables an earlier step of the command set. They are exported
# for the fence's shell only, and named in the artifact.
_run_with_env() {
  local assignments=() a
  while [ "$1" != "--" ]; do assignments+=("$1"); shift; done
  shift
  printf 'environment: %s\n' "${assignments[*]}" >> "$E2E_ARTIFACT"
  for a in "${assignments[@]}"; do export "${a?}"; done
  e2e_run_fence "$@"
  for a in "${assignments[@]}"; do unset "${a%%=*}"; done
}

# _run_yaml — a FlowRun with state.status active, at .flow/runs/$RID.
_run_yaml() {
  mkdir -p "$E2E_REPO/.flow/runs/$RID"
  cp "$FIXTURES/run/valid.yaml" "$E2E_REPO/.flow/runs/$RID/run.yaml"
}

# _verdict_file / _activity_file / _evidence_file — the inputs the command or
# skill composes, written into the repository and passed by relative path.
_verdict_file() {
  printf '%s\n' '{"verdict":"not_achieved","confidence":0.4,"delta":"unchanged","reason":"AC1 still fails","source":"command"}' \
    > "$E2E_REPO/verdict.json"
}
_activity_file() { cp "$FIXTURES/activity/valid.yaml" "$E2E_REPO/activity.yaml"; }
_evidence_file() { cp "$FIXTURES/evidence/valid.yaml" "$E2E_REPO/evidence.yaml"; }

# _goal_source <id> <branch> — a goal whose must_pass criterion always fails.
_goal_source() {
  python3 - "$FIXTURES/goal/valid.yaml" "$E2E_REPO/goal-source.yaml" "$1" "$2" <<'PY' ||
import sys, yaml
src, dst, gid, branch = sys.argv[1:5]
with open(src, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = gid
g["scope"]["branch"] = branch
g["objective"]["acceptance_criteria"][0]["verification_command"] = "false"
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  _flow_assert_fail "$E2E_NAME: could not write the goal source"
}

# _create_goal <id> <branch> — the goal, recorded in the repository through
# the shipped create path, so its trust record is real.
_create_goal() {
  _goal_source "$1" "$2"
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file goal-source.yaml >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create failed: $(cat "$E2E_DIR/create.err")"
  fi
}

# _settings <json> — the repository's .claude/settings.flow.json.
_settings() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
}

# _local_settings <json> — the repository's .claude/settings.flow.local.json.
# The artifact does not print it, so a value naming a scratch path goes here.
_local_settings() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.local.json"
}

# _user_settings <json> — the user's settings file, ~/.claude/settings.flow.json
# under the scenario's HOME, which the harness runs every step with.
_user_settings() {
  mkdir -p "$E2E_HOME/.claude"
  printf '%s\n' "$1" > "$E2E_HOME/.claude/settings.flow.json"
}

# _outside_empty — an empty $E2E_DIR/outside, and BEFORE its state.
_outside_empty() {
  mkdir -p "$E2E_DIR/outside"
  BEFORE=$(_outside_state)
}

# _physical <path> — the path as the kernel resolves it (macOS reaches the
# scratch root through /var -> /private/var).
_physical() { (cd "$1" 2>/dev/null && pwd -P); }

# --- flow-record-verdict.sh (L1) --------------------------------------------
# The Stop hook never reaches this helper with a symlinked run directory: it
# refuses the run directory itself first. /flow:goal evaluate is the caller
# that reaches it; its block carries the verdict as placeholders the model
# fills, so the helper runs here with the arguments that block passes.

if _want verdict-flow-link; then
  _flow_test_begin "flow-record-verdict.sh: a symlinked .flow gets no run directory or verdict (L1)"
  e2e_new verdict-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the verdict is recorded as /flow:goal evaluate records it"
  e2e_repo feature/issue-42-e2e
  _verdict_file
  _plant .flow
  _run_bin bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want verdict-runs-link; then
  _flow_test_begin "flow-record-verdict.sh: a symlinked .flow/runs gets no run directory or verdict (L1)"
  e2e_new verdict-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _verdict_file
  _plant .flow/runs
  _run_bin bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

if _want verdict-real; then
  _flow_test_begin "flow-record-verdict.sh: an ordinary repository still gets its verdict (L15)"
  e2e_new verdict-real
  e2e_describe "no symlink under the repository; the scratch repository is reached through its logical path, which on macOS is itself under a symlink (/var)"
  e2e_repo feature/issue-42-e2e
  _verdict_file
  _run_bin bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".flow/runs/$RID/last-verdict.json" '"verdict": "not_achieved"'
fi

# --- flow-record-activity.sh (L2) -------------------------------------------

if _want activity-flow-link; then
  _flow_test_begin "flow-record-activity.sh: a symlinked .flow gets no activity (L2)"
  e2e_new activity-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the activity is recorded as run-state-management records one"
  e2e_repo feature/issue-42-e2e
  _activity_file
  _plant .flow
  _run_bin bin/flow-record-activity.sh --run-id "$RID" --activity-file activity.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want activity-runs-link; then
  _flow_test_begin "flow-record-activity.sh: a symlinked .flow/runs gets no activity (L2)"
  e2e_new activity-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _activity_file
  _plant .flow/runs
  _run_bin bin/flow-record-activity.sh --run-id "$RID" --activity-file activity.yaml
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

# --- flow-record-evidence.sh (L3) -------------------------------------------

if _want evidence-flow-link; then
  _flow_test_begin "flow-record-evidence.sh: a symlinked .flow gets no evidence (L3)"
  e2e_new evidence-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the evidence is recorded as goal-evidence-ledger records it"
  e2e_repo feature/issue-42-e2e
  _evidence_file
  _plant .flow
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want evidence-runs-link; then
  _flow_test_begin "flow-record-evidence.sh: a symlinked .flow/runs gets no evidence (L3)"
  e2e_new evidence-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _evidence_file
  _plant .flow/runs
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

# --- flow-goal-record.sh (L4, L5) -------------------------------------------

if _want goal-create-flow-link; then
  _flow_test_begin "flow-goal-record.sh --create: a symlinked .flow gets no goal (L4)"
  e2e_new goal-create-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the goal is created as goal-contract-capture creates it"
  e2e_repo feature/issue-42-e2e
  _goal_source g-link feature/issue-42-e2e
  _plant .flow
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want goal-create-goals-link; then
  _flow_test_begin "flow-goal-record.sh --create: a symlinked .flow/goals gets no goal (L4)"
  e2e_new goal-create-goals-link
  e2e_describe ".flow/goals is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _goal_source g-link feature/issue-42-e2e
  _plant .flow/goals
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  _expect_refused 2 "refusing — .flow/goals is a symlink"
fi

if _want goal-lifecycle-flow-link; then
  _flow_test_begin "Stop hook: a goal reached through a symlinked .flow is not rewritten there (L5, L16)"
  e2e_new goal-lifecycle-flow-link
  e2e_describe "evaluator-loop; an active goal whose check fails is created, then .flow is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"goals":{"stopHookEnforcement":"evaluator-loop"}}}'
  _create_goal g-link feature/issue-42-e2e
  _plant .flow
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  # The hook used to read the goal through the link, block on its failing
  # check, and have its lifecycle update refused. It no longer reads a goal
  # through a symlinked .flow (L16), so the stop is approved as if no goal were
  # active. What L5 is about holds either way: nothing is written in the
  # link's target.
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow is a symlink; goals are not read through it"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want goal-update-flow-link; then
  _flow_test_begin "flow-goal-record.sh --update-lifecycle: a goal reached through a symlinked .flow is refused with exit 2 (L5, L5b)"
  e2e_new goal-update-flow-link
  e2e_describe "an active goal is created, then .flow is moved outside the repository and replaced by a symlink to it; the lifecycle is updated with the arguments /flow:goal's lifecycle block passes"
  e2e_repo feature/issue-42-e2e
  _create_goal g-link feature/issue-42-e2e
  printf '%s\n' '{"lifecycle":{"status":"waiting_for_user"}}' > "$E2E_REPO/lifecycle.yaml"
  _plant .flow
  _run_bin bin/flow-goal-record.sh --update-lifecycle --goal-id g-link --lifecycle-file lifecycle.yaml --from-status active
  _expect_refused 2 "refusing — .flow is a symlink"
  _expect_err_lacks "Traceback"
fi

# --- journal-record.sh and journal-append.sh (L6, L7) -----------------------

if _want journal-record-decisions-link; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a symlinked .decisions is not written (L6)"
  e2e_new journal-record-decisions-link
  e2e_describe ".decisions is a symlink to a directory outside the repository that holds another checkout's issue-42.md; the block runs with the gate result the command computed"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Another checkout'\''s journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" 'STRANGER_TEST_EMIT_BLOCK_BEGIN'
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want journal-record-parent-link; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a journal.dir under a symlinked parent is not created there (L6)"
  e2e_new journal-record-parent-link
  e2e_describe "journal.dir is docs/decisions, set in the user's settings; docs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  # Set in the user's settings, which may point anywhere, so the value reaches
  # the writer and its own check is what refuses. The same value in the
  # repository's settings is refused before any writer sees it (L23), and the
  # journal then goes to .decisions: journal-append-repo-parent-link.
  _user_settings '{"journal":{"dir":"docs/decisions"}}'
  _plant docs
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" 'STRANGER_TEST_EMIT_BLOCK_BEGIN'
  _expect_refused 2 "refusing — docs is a symlink"
fi

if _want journal-append-decisions-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a symlinked .decisions is not appended to (L7)"
  e2e_new journal-append-decisions-link
  e2e_describe ".decisions is a symlink to a directory outside the repository that holds another checkout's issue-42.md; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Another checkout'\''s journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want journal-append-parent-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a journal.dir under a symlinked parent is not created there (L7)"
  e2e_new journal-append-parent-link
  e2e_describe "journal.dir is docs/decisions, set in the user's settings; docs is a symlink to an empty directory outside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  # The user's settings, as in journal-record-parent-link: a repository's own
  # value under a symlink never reaches the writer.
  _user_settings '{"journal":{"dir":"docs/decisions"}}'
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — docs is a symlink"
fi

if _want journal-append-real; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): an ordinary repository still gets its entry (L15)"
  e2e_new journal-append-real
  e2e_describe "no symlink under the repository; branch feature/issue-42-e2e, no journal yet"
  e2e_repo feature/issue-42-e2e
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".decisions/issue-42.md" "## Brainstorm Decision: {topic}"
fi

# --- session-end-state.sh (L8) ----------------------------------------------

SESSION_END='{"session_id":"e2e-session"}'

if _want session-end-flow-link; then
  _flow_test_begin "SessionEnd hook: an active run under a symlinked .flow gets no event (L8)"
  e2e_new session-end-flow-link
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  _expect_refused 0 "refusing — .flow is a symlink"
fi

if _want session-end-runs-link; then
  _flow_test_begin "SessionEnd hook: an active run under a symlinked .flow/runs gets no event (L8)"
  e2e_new session-end-runs-link
  e2e_describe "an active run is created, then .flow/runs is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow/runs
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  _expect_refused 0 "refusing — .flow/runs is a symlink"
fi

if _want session-end-run-dir-link; then
  _flow_test_begin "SessionEnd hook: an active run whose directory is a symlink gets no event (L8)"
  e2e_new session-end-run-dir-link
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  _expect_refused 0 "refusing — .flow/runs/$RID is a symlink"
fi

if _want session-end-real; then
  _flow_test_begin "SessionEnd hook: an active run in an ordinary repository still gets its event (L15)"
  e2e_new session-end-real
  e2e_describe "an active run, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".flow/runs/$RID/events.jsonl" '"type": "session_end"'
fi

# --- flow-strip-auto-log.sh (L9) --------------------------------------------

if _want strip-parent-link; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a journal dir under a symlinked parent is not rewritten (L9)"
  e2e_new strip-parent-link
  e2e_describe "journal.dir is docs/decisions, set in the user's settings; docs is moved outside the repository and replaced by a symlink to it; its journal carries one breadcrumb"
  e2e_repo feature/issue-42-e2e
  # The user's settings, as in journal-record-parent-link: a repository's own
  # value under a symlink never reaches the strip.
  _user_settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/docs/decisions"
  printf '# Journal\n\nA decision.\n\n<!-- auto-log: 2026-05-20 10:00 Edit src/search.ts -->\n' \
    > "$E2E_REPO/docs/decisions/issue-42.md"
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" '/bin/flow-strip-auto-log.sh" --apply'
  _expect_refused 2 "refusing — journal dir docs/decisions"
fi

# --- command pre-flights and the run's creation (L10-L13) -------------------

if _want trigger-preflight-flow-link; then
  _flow_test_begin "/flow:trigger pre-flight: a symlinked .flow gets no triggers directory (L10)"
  e2e_new trigger-preflight-flow-link
  e2e_describe "flow.triggers.enabled is true; .flow is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/trigger.md" '.flow/triggers'
  _expect_refused 1 "refusing — .flow is a symlink"
fi

if _want watch-preflight-flow-link; then
  _flow_test_begin "/flow:watch pre-flight: a symlinked .flow gets no triggers directory (L10)"
  e2e_new watch-preflight-flow-link
  e2e_describe "flow.triggers.enabled is true; .flow is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/watch.md" '.flow/triggers'
  _expect_refused 1 "refusing — .flow is a symlink"
fi

if _want goal-preflight-flow-link; then
  _flow_test_begin "/flow:goal pre-flight: a symlinked .flow gets no goals directory (L11)"
  e2e_new goal-preflight-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" 'Resolve stopHookEnforcement'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want start-journal-link; then
  _flow_test_begin "/flow:start journal block: a symlinked .decisions is refused (L12)"
  e2e_new start-journal-link
  e2e_describe ".decisions is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _plant .decisions
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'JOURNAL_INIT_BLOCK_BEGIN'
  _expect_refused 1 "refusing — .decisions is a symlink"
fi

RUN_SKILL="skills/run-state-management/SKILL.md"

if _want run-create-flow-link; then
  _flow_test_begin "run-state-management: a symlinked .flow gets no run directory (L13)"
  e2e_new run-create-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the block runs with the run id the command chose"
  e2e_repo feature/issue-42-e2e
  _plant .flow
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  _expect_refused 1 "refusing — .flow is a symlink"
  e2e_expect_no_line "RUN_DIR=.flow/runs/$RID"
fi

if _want run-create-runs-link; then
  _flow_test_begin "run-state-management: a symlinked .flow/runs gets no run directory (L13)"
  e2e_new run-create-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _plant .flow/runs
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  _expect_refused 1 "refusing — .flow/runs is a symlink"
fi

if _want run-create-real; then
  _flow_test_begin "run-state-management: an ordinary repository gets its run directory (L15)"
  e2e_new run-create-real
  e2e_describe "no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "RUN_DIR=.flow/runs/$RID"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/.flow/runs/$RID" ] && [ ! -L "$E2E_REPO/.flow/runs/$RID" ] && echo yes || echo no)" "a real run directory exists"
fi

if _want journal-dotdot-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a journal.dir that climbs out of a symlinked directory with .. is refused (L14)"
  e2e_new journal-dotdot-link
  e2e_describe "journal.dir is shared/../escaped, set in the user's settings; shared is a symlink to outside/inner, so the name reaches outside/escaped, while read without the link it names escaped in the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  # The user's settings, as in journal-record-parent-link: a repository's own
  # value that climbs out of a symlink never reaches the writer.
  _user_settings '{"journal":{"dir":"shared/../escaped"}}'
  mkdir -p "$E2E_DIR/outside/inner" "$E2E_DIR/outside/escaped"
  ln -s "$E2E_DIR/outside/inner" "$E2E_REPO/shared"
  printf 'planted: shared -> <scratch>/%s/outside/inner\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — shared is a symlink"
fi

# --- reads of .flow/goals (L16-L22) -----------------------------------------
# A goal read through a symlinked .flow belongs to whatever directory the link
# names. Goal trust is keyed on the repository where the check runs, so no
# verification command runs from it, but the Stop hook blocked or approved on
# it and the gates answered with it. Every reader now refuses a symlink below
# the repository's top on the way to a goal, says so on stderr, and treats the
# goal as absent: the Stop hook approves, a command block reports no goal, and
# flow-active-goal.sh exits 2, the status its header gives for a refused
# symlink, which the gates read as blocked.

READ_NOTE="goals are not read through it"
GOAL_SCAN_MARK='GOAL_SCAN_BLOCK_BEGIN'
MERGE_GOAL_FENCE='### FlowGoal Gate'
BLOCK='{"flow":{"goals":{"stopHookEnforcement":"block"}}}'

if _want stop-block-flow-link; then
  _flow_test_begin "Stop hook (block): a goal under a symlinked .flow is not read, and the stop is approved (L16, L21)"
  e2e_new stop-block-flow-link
  e2e_describe "stopHookEnforcement block; a trusted goal owning this branch whose check fails is created, then .flow is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  _plant .flow
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want stop-block-goals-link; then
  _flow_test_begin "Stop hook (block): a goal under a symlinked .flow/goals is not read, and the stop is approved (L16, L21)"
  e2e_new stop-block-goals-link
  e2e_describe "stopHookEnforcement block; a trusted goal whose check fails is created, then .flow/goals is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  _plant .flow/goals
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_no_out 'Active goal: g-link'
  e2e_expect_err "refusing — .flow/goals is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want stop-block-goal-file-link; then
  _flow_test_begin "Stop hook (block): a goal file that is a symlink is not read, and the stop is approved (L16, L21)"
  e2e_new stop-block-goal-file-link
  e2e_describe "stopHookEnforcement block; a trusted goal whose check fails is created, then its file is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  mv "$E2E_REPO/.flow/goals/g-link.goal.yaml" "$E2E_DIR/outside/g-link.goal.yaml" &&
    ln -s "$E2E_DIR/outside/g-link.goal.yaml" "$E2E_REPO/.flow/goals/g-link.goal.yaml" ||
    _flow_assert_fail "$E2E_NAME: could not plant the goal file symlink"
  printf 'planted: .flow/goals/g-link.goal.yaml -> <scratch>/%s/outside/g-link.goal.yaml\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_no_out 'Active goal: g-link'
  e2e_expect_err "refusing — .flow/goals/g-link.goal.yaml is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want stop-block-real; then
  _flow_test_begin "Stop hook (block): an ordinary repository's goal is still read and blocks the stop (L22)"
  e2e_new stop-block-real
  e2e_describe "stopHookEnforcement block; a trusted goal owning this branch whose check fails; no symlink under the repository; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"block"'
  e2e_expect_out 'Active goal: g-link'
  _expect_err_lacks "$READ_NOTE"
  e2e_expect_clean_edges
fi

if _want merge-gate-flow-link; then
  _flow_test_begin "flow-active-goal.sh (/flow:merge goal gate): an achieved goal under a symlinked .flow does not pass the gate, and the gate names the path (L17, L37)"
  e2e_new merge-gate-flow-link
  e2e_describe "an achieved goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e achieved true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/merge.md" "$MERGE_GOAL_FENCE"
  e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
  # The gate says which path was refused, not only the exit status (L37).
  e2e_expect_line "FLOW_GOAL_BLOCK_REASON=flow-active-goal.sh exited 2: refusing — .flow is a symlink; $READ_NOTE"
  e2e_expect_no_line "FLOW_GOAL_ID=g-link"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want active-goal-flow-link; then
  _flow_test_begin "flow-active-goal.sh: a goal under a symlinked .flow is refused with exit 2 and a note (L17, L21)"
  e2e_new active-goal-flow-link
  e2e_describe "an active goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it; the helper is asked as /flow:status asks it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  _run_bin bin/flow-active-goal.sh --status
  _expect_refused 2 "refusing — .flow is a symlink; $READ_NOTE"
fi

if _want goal-status-flow-link; then
  _flow_test_begin "/flow:goal status scan: an active goal under a symlinked .flow is not named (L18, L21)"
  e2e_new goal-status-flow-link
  e2e_describe "an active goal is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" "$GOAL_SCAN_MARK"
  e2e_expect_line "STATE=none"
  e2e_expect_no_line "ACTIVE_GOAL=.flow/goals/g-link.goal.yaml"
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want goal-status-real; then
  _flow_test_begin "/flow:goal status scan: an ordinary repository's active goal is named (L22)"
  e2e_new goal-status-real
  e2e_describe "an active goal, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" "$GOAL_SCAN_MARK"
  e2e_expect_line "STATE=ok"
  e2e_expect_line "ACTIVE_GOAL=.flow/goals/g-link.goal.yaml"
  e2e_expect_clean_edges
fi

if _want learn-goals-flow-link; then
  _flow_test_begin "/flow:learn: goal files under a symlinked .flow are not listed (L19, L21)"
  e2e_new learn-goals-flow-link
  e2e_describe "a goal is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "GOAL_FILE_COUNT=0"
  e2e_expect_no_line "GOAL_FILE=.flow/goals/g-link.goal.yaml"
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want learn-goals-real; then
  _flow_test_begin "/flow:learn: an ordinary repository's goal files are listed (L22)"
  e2e_new learn-goals-real
  e2e_describe "a goal, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "GOAL_FILE_COUNT=1"
  e2e_expect_line "GOAL_FILE=.flow/goals/g-link.goal.yaml"
  e2e_expect_clean_edges
fi

if _want start-goal-flow-link; then
  _flow_test_begin "/flow:start goal block: a goal under a symlinked .flow is not resumed (L20, L21)"
  e2e_new start-goal-flow-link
  e2e_describe "an active goal issue-42 is written, then .flow is moved outside the repository and replaced by a symlink to it; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_line "FLOW_GOAL_STATE=create"
  e2e_expect_no_line "FLOW_GOAL_STATE=exists"
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want start-goal-real; then
  _flow_test_begin "/flow:start goal block: an ordinary repository's goal is resumed (L22)"
  e2e_new start-goal-real
  e2e_describe "an active goal issue-42, no symlink under the repository; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_line "FLOW_GOAL_STATE=exists"
  e2e_expect_line "GOAL_STATUS=active"
  e2e_expect_clean_edges
fi

# --- journal.dir from the repository's settings (L23-L30) --------------------
# A journal.dir in .claude/settings.flow.json or .claude/settings.flow.local.json
# must resolve inside the repository, by ensure_repo_dir()'s rule: it ends under
# the repository's physical path, and no component of it that exists is a
# symlink. Otherwise the writers warn, naming the value and the file, and use
# .decisions. A journal.dir in the user's own settings is used as configured.

REPO_REFUSED="refusing journal.dir"
STRANGER='STRANGER_TEST_EMIT_BLOCK_BEGIN'
BRAINSTORM='## Brainstorm Decision: {topic}'
STRIP='/bin/flow-strip-auto-log.sh" --apply'
CRUMB='<!-- auto-log: 2026-05-20 10:00 Edit src/search.ts -->'

if _want journal-record-repo-dotdot; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a repository journal.dir that climbs out with .. is refused, and the journal goes to .decisions (L23, L26)"
  e2e_new journal-record-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside is an empty directory beside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  _outside_empty
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_file_has ".decisions/issue-42.md" "type: stranger-test"
  _expect_untouched
fi

if _want journal-append-repo-parent-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a repository journal.dir under a symlinked directory is refused, and the entry goes to .decisions (L23, L25, L26)"
  e2e_new journal-append-repo-parent-link
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; docs is a symlink to an empty directory outside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED 'docs/decisions' from .claude/settings.flow.json: docs is a symlink"
  e2e_expect_file_has ".decisions/issue-42.md" "$BRAINSTORM"
  _expect_untouched
fi

if _want journal-append-local-absolute; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): an absolute journal.dir outside the repository in the local settings file is refused (L24, L26)"
  e2e_new journal-append-local-absolute
  e2e_describe "journal.dir in .claude/settings.flow.local.json is the physical path of an empty directory beside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _outside_empty
  _local_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/outside")\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "from .claude/settings.flow.local.json: "
  e2e_expect_err "$REPO_REFUSED"
  e2e_expect_file_has ".decisions/issue-42.md" "$BRAINSTORM"
  _expect_untouched
fi

if _want journal-record-local-prefix; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): an absolute journal.dir that only shares the repository's path as a prefix is refused (L25)"
  e2e_new journal-record-local-prefix
  e2e_describe "journal.dir in .claude/settings.flow.local.json is <physical repository path>-outside, a directory that does not exist beside the repository"
  e2e_repo feature/issue-42-e2e
  _local_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")-outside\"}}"
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED"
  e2e_expect_file_has ".decisions/issue-42.md" "type: stranger-test"
  e2e_expect_equal no "$([ -e "$E2E_DIR/repo-outside" ] && echo yes || echo no)" "a directory was created beside the repository"
fi

if _want strip-repo-dotdot; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a repository journal.dir that climbs out with .. is refused, and .decisions is stripped instead (L23, L27)"
  e2e_new strip-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside, beside the repository, holds a journal carrying one breadcrumb"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  mkdir -p "$E2E_DIR/outside"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_DIR/outside/issue-42.md"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_line "STRIP_AUTO_LOG=none"
  _expect_untouched
fi

if _want strip-user-absolute; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a journal.dir outside the repository set in the user's settings is stripped where it points (L27, L28)"
  e2e_new strip-user-absolute
  e2e_describe "journal.dir in the user's settings is the physical path of a directory beside the repository holding a journal with one breadcrumb"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_DIR/outside/issue-42.md"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/outside")\"}}"
  # One shell only: the block rewrites the journal, so a second run finds
  # nothing left to strip and prints a different report.
  E2E_FENCE_SHELLS="${E2E_FENCE_SHELLS%% *}" e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "STRIP_AUTO_LOG_APPLIED=1 files=1 removed=1 warned=0"
  e2e_expect_equal "$(printf '# Journal\n\nA decision.')" "$(cat "$E2E_DIR/outside/issue-42.md")" "the journal the user's journal.dir names, stripped"
  _expect_err_lacks "refusing"
fi

if _want journal-append-user-absolute; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a journal.dir outside the repository set in the user's settings is written as configured (L28)"
  e2e_new journal-append-user-absolute
  e2e_describe "journal.dir in the user's settings is the physical path of an empty directory beside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/outside")\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -qF "$BRAINSTORM" "$E2E_DIR/outside/issue-42.md" 2>/dev/null && echo yes || echo no)" "the entry is in the journal the user's journal.dir names"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
  _expect_err_lacks "refusing"
fi

if _want journal-record-user-dotdot; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a journal.dir that climbs out with .. set in the user's settings is written without a warning (L28)"
  e2e_new journal-record-user-dotdot
  e2e_describe "journal.dir is ../outside in the user's settings; outside is an empty directory beside the repository"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  _user_settings '{"journal":{"dir":"../outside"}}'
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -qF 'type: stranger-test' "$E2E_DIR/outside/issue-42.md" 2>/dev/null && echo yes || echo no)" "the manifest is in the journal the user's journal.dir names"
  _expect_err_lacks "WARN"
  _expect_err_lacks "refusing"
fi

if _want journal-append-repo-inside; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a repository journal.dir inside the repository is used (L29)"
  e2e_new journal-append-repo-inside
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; no symlink under the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "docs/decisions/issue-42.md" "$BRAINSTORM"
  _expect_err_lacks "refusing"
fi

if _want learn-journal-repo-dotdot; then
  _flow_test_begin "/flow:learn: a repository journal.dir that climbs out with .. is not read; .decisions is (L27)"
  e2e_new learn-journal-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside, beside the repository, holds a journal"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  mkdir -p "$E2E_DIR/outside"
  printf '# Another journal\n' > "$E2E_DIR/outside/issue-7.md"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_no_line "JOURNAL_FILE=../outside/issue-7.md"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want explain-journal-repo-dotdot; then
  _flow_test_begin "/flow:explain: a repository journal.dir that climbs out with .. is not read; .decisions is (L27)"
  e2e_new explain-journal-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside, beside the repository, holds issue-42.md; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  mkdir -p "$E2E_DIR/outside"
  printf '# The journal outside the repository\n' > "$E2E_DIR/outside/issue-42.md"
  BEFORE=$(_outside_state)
  e2e_gh_fixture issue-42 '{"title":"Search","body":"Find things."}'
  e2e_gh_fixture repo '{"defaultBranchRef":{"name":"main"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/explain.md" '### Decision Journal'
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_no_line "# The journal outside the repository"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want journal-dir-one-place; then
  _flow_test_begin "journal.dir is resolved in one place: no other shipped file reads it from the settings (L30)"
  # A writer or reader that asks cascade-resolve.sh for journal.dir itself skips
  # the rule for the repository's settings, which is how the three writers came
  # to disagree. Every expression that selects the key names it as
  # '.journal.dir; the only file allowed to is the resolver. cascade-resolve.sh
  # is the generic settings reader the resolver calls, and names the key only in
  # a comment's example.
  JOURNAL_DIR_READERS=$(cd "$E2E_PLUGIN_DIR" && grep -rlF "'.journal.dir" bin hooks commands skills agents 2>/dev/null | grep -vxF bin/cascade-resolve.sh | LC_ALL=C sort | tr '\n' ' ')
  assert_equal "bin/journal-dir.sh " "$JOURNAL_DIR_READERS" "the files that resolve journal.dir from the settings"
fi

# --- the user's journal.dir behind a refused one (L31) -----------------------

if _want journal-append-repo-refused-user-set; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a refused repository journal.dir leaves the user's journal.dir in effect (L31)"
  e2e_new journal-append-repo-refused-user-set
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json and the physical path of a directory beside the repository in the user's settings; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  _outside_empty
  mkdir -p "$E2E_DIR/userjournal"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/userjournal")\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_err "userjournal"
  e2e_expect_equal yes "$(grep -qF "$BRAINSTORM" "$E2E_DIR/userjournal/issue-42.md" 2>/dev/null && echo yes || echo no)" "the entry is in the journal the user's journal.dir names"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
  _expect_untouched
fi

# --- journal readers and writers that named .decisions themselves (L32, L33) --

# _section <heading> — the lines of stdout under "### <heading>", up to the
# next "### " heading.
_section() {
  printf '%s\n' "$E2E_OUT" | awk -v h="### $1" '$0 == h { f = 1; next } /^### / { f = 0 } f'
}

# _commit_all — commit everything in the scratch repository, so only what a
# scenario changes afterwards shows in git status.
_commit_all() {
  (_e2e_git_env; cd "$E2E_REPO" && git add -A && git commit -q -m setup) ||
    _flow_assert_fail "$E2E_NAME: could not commit the setup"
}

JOURNAL_INIT='JOURNAL_INIT_BLOCK_BEGIN'
PR_CONTEXT='### Decision Journal'

if _want start-journal-configured; then
  _flow_test_begin "/flow:start journal block: the configured journal.dir is created, not .decisions (L32)"
  e2e_new start-journal-configured
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; no journal directory exists yet"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=docs/decisions"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/docs/decisions" ] && [ ! -L "$E2E_REPO/docs/decisions" ] && echo yes || echo no)" "docs/decisions is a real directory"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
fi

if _want start-journal-repo-dotdot; then
  _flow_test_begin "/flow:start journal block: a refused repository journal.dir falls back to .decisions and the command goes on (L32)"
  e2e_new start-journal-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside is an empty directory beside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  _outside_empty
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions exists"
  _expect_untouched
fi

if _want pr-journal-configured; then
  _flow_test_begin "/flow:pr context block: the journal is read from the configured journal.dir (L32)"
  e2e_new pr-journal-configured
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json, holding issue-42.md; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/docs/decisions"
  printf '# The configured journal\n' > "$E2E_REPO/docs/decisions/issue-42.md"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/pr.md" "$PR_CONTEXT"
  e2e_expect_equal "yes" "$(_section 'Decision Journal' | grep -qxF 'JOURNAL_FILE=docs/decisions/issue-42.md' && echo yes || echo no)" "the Decision Journal section names docs/decisions/issue-42.md"
  e2e_expect_equal "yes" "$(_section 'Decision Journal' | grep -qxF '# The configured journal' && echo yes || echo no)" "the Decision Journal section carries its contents"
fi

if _want resume-unlinked-journal-dir; then
  _flow_test_begin "/flow:resume unlinked-change check: a change to the configured journal is flow's own (L33)"
  e2e_new resume-unlinked-journal-dir
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; its issue-42.md is committed, then changed"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/docs/decisions"
  printf '# Journal\n' > "$E2E_REPO/docs/decisions/issue-42.md"
  _commit_all
  printf 'A decision.\n' >> "$E2E_REPO/docs/decisions/issue-42.md"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'FLOW_RESUME_UNLINKED=unknown'
  e2e_expect_line "FLOW_RESUME_UNLINKED=0"
  e2e_expect_no_line "  docs/decisions/issue-42.md"
fi

if _want resume-unlinked-real; then
  _flow_test_begin "/flow:resume unlinked-change check: a change outside flow's directories is still unlinked (L33)"
  e2e_new resume-unlinked-real
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; src/search.ts is committed, then changed"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/src"
  printf 'x\n' > "$E2E_REPO/src/search.ts"
  _commit_all
  printf 'y\n' >> "$E2E_REPO/src/search.ts"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'FLOW_RESUME_UNLINKED=unknown'
  e2e_expect_line "FLOW_RESUME_UNLINKED=1"
  e2e_expect_line "  src/search.ts"
fi

# --- reads of .flow/runs (L34-L36) -------------------------------------------
# A run read through a symlinked .flow, .flow/runs or run directory belongs to
# the link's target. Every reader refuses it by the writers' rule, says so on
# stderr, and treats the run as absent.

RUNS_NOTE="runs are not read through it"

# _run_with_events — the active run at .flow/runs/$RID, with one event.
_run_with_events() {
  _run_yaml
  printf '%s\n' '{"type":"phase","phase":"code"}' > "$E2E_REPO/.flow/runs/$RID/events.jsonl"
}

if _want learn-runs-flow-link; then
  _flow_test_begin "/flow:learn: run events under a symlinked .flow are not listed (L34, L35)"
  e2e_new learn-runs-flow-link
  e2e_describe "an active run with one event is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_EVENT_FILE_COUNT=0"
  e2e_expect_no_line "RUN_EVENTS=.flow/runs/$RID/events.jsonl"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want learn-runs-run-dir-link; then
  _flow_test_begin "/flow:learn: a run directory that is a symlink is not listed, and is named (L34, L35)"
  e2e_new learn-runs-run-dir-link
  e2e_describe "an active run with one event is created, then its directory is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant ".flow/runs/$RID"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_EVENT_FILE_COUNT=0"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want learn-runs-real; then
  _flow_test_begin "/flow:learn: an ordinary repository's run events are listed (L36)"
  e2e_new learn-runs-real
  e2e_describe "an active run with one event, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_EVENT_FILE_COUNT=1"
  e2e_expect_line "RUN_EVENTS=.flow/runs/$RID/events.jsonl"
fi

if _want resume-preflight-flow-link; then
  _flow_test_begin "/flow:resume pre-flight: runs under a symlinked .flow are treated as absent (L34, L35)"
  e2e_new resume-preflight-flow-link
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'No FlowRuns exist'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "No FlowRuns exist"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-flow-link; then
  _flow_test_begin "/flow:resume scan: an active run under a symlinked .flow is not found (L34, L35)"
  e2e_new resume-scan-flow-link
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=none"
  e2e_expect_no_line "RUN_ID=$RID"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-run-dir-link; then
  _flow_test_begin "/flow:resume scan: an active run whose directory is a symlink is not found, and is named (L34, L35)"
  e2e_new resume-scan-run-dir-link
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=none"
  e2e_expect_no_line "RUN_ID=$RID"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-real; then
  _flow_test_begin "/flow:resume scan: an ordinary repository's active run is found (L36)"
  e2e_new resume-scan-real
  e2e_describe "an active run, no symlink under the repository; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=ok"
  e2e_expect_line "RUN_ID=$RID"
fi

if _want resume-read-run-dir-link; then
  _flow_test_begin "/flow:resume run read: a run whose directory is a symlink is not read (L34, L35)"
  e2e_new resume-read-run-dir-link
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it; the block runs with the run id step 1 chose"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-read-real; then
  _flow_test_begin "/flow:resume run read: an ordinary repository's run is read (L36)"
  e2e_new resume-read-real
  e2e_describe "an active run, no symlink under the repository; the block runs with the run id step 1 chose"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_err_lacks "$RUNS_NOTE"
fi

STATUS_MD_MARK='# RECENT_RUNS_BLOCK_BEGIN'

if _want status-runs-flow-link; then
  _flow_test_begin "/flow:status recent runs: runs under a symlinked .flow are not listed (L34, L35)"
  e2e_new status-runs-flow-link
  e2e_describe "an active run with one event is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=empty" "$(_section 'Recent Runs')" "the Recent Runs section"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want status-runs-run-dir-link; then
  _flow_test_begin "/flow:status recent runs: a run directory that is a symlink is not listed, and is named (L34, L35)"
  e2e_new status-runs-run-dir-link
  e2e_describe "an active run with one event is created, then its directory is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant ".flow/runs/$RID"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=empty" "$(_section 'Recent Runs')" "the Recent Runs section"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want status-runs-real; then
  _flow_test_begin "/flow:status recent runs: an ordinary repository's runs are listed (L36)"
  e2e_new status-runs-real
  e2e_describe "an active run with one event, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "$(printf 'STATE=ok\nRUN=id=%s verdict=- activities=1' "$RID")" "$(_section 'Recent Runs')" "the Recent Runs section"
fi

# _run_bundle — the judge's evidence bundle for goal g-link and run $RID,
# assembled as the evaluator loop assembles it.
_run_bundle() {
  local code="bin/_flow_evidence_bundle.py"
  {
    printf 'code: %s\n' "$code"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$code")"
    printf 'arguments: .flow/goals/g-link.goal.yaml {} .flow/runs/%s\n' "$RID"
  } >> "$E2E_ARTIFACT"
  _e2e_exec env PYTHONSAFEPATH=1 python3 "$E2E_ACTIVE_PLUGIN/$code" \
    .flow/goals/g-link.goal.yaml '{}' ".flow/runs/$RID"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

# _run_with_evidence — the run at .flow/runs/$RID with one evidence sidecar
# and a previous verdict.
_run_with_evidence() {
  _run_yaml
  mkdir -p "$E2E_REPO/.flow/runs/$RID/evidence"
  cp "$FIXTURES/evidence/valid.yaml" "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  printf '%s\n' '{"verdict":"not_achieved","confidence":0.4,"delta":"unchanged","reason":"PREVIOUS-VERDICT-MARK"}' \
    > "$E2E_REPO/.flow/runs/$RID/last-verdict.json"
}

if _want bundle-runs-link; then
  _flow_test_begin "evidence bundle (evaluator loop): a run under a symlinked .flow/runs is not read into the judge's prompt (L34, L35)"
  e2e_new bundle-runs-link
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; .flow/runs is then moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  _plant .flow/runs
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "(no run directory; evidence ledger unavailable)"
  e2e_expect_no_out "evidence-ac1-test"
  e2e_expect_no_out "PREVIOUS-VERDICT-MARK"
  e2e_expect_err "refusing — .flow/runs is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want bundle-real; then
  _flow_test_begin "evidence bundle (evaluator loop): an ordinary repository's run is read into the judge's prompt (L36)"
  e2e_new bundle-real
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "evidence-ac1-test"
  e2e_expect_out "PREVIOUS-VERDICT-MARK"
  _expect_err_lacks "$RUNS_NOTE"
fi

# --- refusals the gates report (L37) -----------------------------------------

if _want pr-gate-flow-link; then
  _flow_test_begin "/flow:pr goal gate: a goal under a symlinked .flow blocks, and the gate names the path (L17, L37)"
  e2e_new pr-gate-flow-link
  e2e_describe "an achieved goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e achieved true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/pr.md" "$PR_CONTEXT"
  e2e_expect_equal "$(printf 'STATE=unavailable\nGATE=block\nREASON=flow-active-goal.sh exited 2: refusing — .flow is a symlink; %s' "$READ_NOTE")" "$(_section 'FlowGoal State')" "the FlowGoal State section"
  _expect_untouched
fi

if _want status-goal-flow-link; then
  _flow_test_begin "/flow:status goal section: a goal under a symlinked .flow is reported with the path refused (L37)"
  e2e_new status-goal-flow-link
  e2e_describe "an active goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "$(printf 'STATE=unavailable\nREASON=flow-active-goal.sh exited 2: refusing — .flow is a symlink; %s' "$READ_NOTE")" "$(_section 'FlowGoal State')" "the FlowGoal State section"
  _expect_untouched
fi

if _want issue-hook-flow-link; then
  _flow_test_begin "gh issue create hook: a goal under a symlinked .flow is reported with the path refused (L37)"
  e2e_new issue-hook-flow-link
  e2e_describe "an active goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it; the agent runs gh issue create"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_hook hooks/scripts/ask-issue-create.sh '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title later"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "flow-active-goal.sh exit 2: refusing — .flow is a symlink; $READ_NOTE"
  e2e_expect_no_out "permissionDecision"
  _expect_untouched
fi

# --- a check that cannot run (L38) -------------------------------------------
# python3 is replaced by a stub that exits 1, for the code the scenario runs
# only: the harness's own python3 calls do not look in $E2E_BIN.

# _python_dead — every python3 the code under test runs exits 1.
_python_dead() {
  printf '#!/bin/sh\nexit 1\n' > "$E2E_BIN/python3"
  chmod +x "$E2E_BIN/python3"
  printf 'python3: a stub that exits 1\n' >> "$E2E_ARTIFACT"
}

UNCHECKED="cannot check"

if _want status-runs-unchecked; then
  _flow_test_begin "/flow:status recent runs: a check that cannot run is reported as unavailable, not as no runs (L38)"
  e2e_new status-runs-unchecked
  e2e_describe "an active run with one event, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=unavailable" "$(_section 'Recent Runs' | head -1)" "the first line of the Recent Runs section"
  e2e_expect_equal yes "$(_section 'Recent Runs' | grep -q '^REASON=.*cannot check' && echo yes || echo no)" "the Recent Runs section says the check could not run"
  _expect_err_lacks "runs are not read through it"
fi

if _want learn-unchecked; then
  _flow_test_begin "/flow:learn: a check that cannot run is reported as unavailable, not as no goal files or runs (L38)"
  e2e_new learn-unchecked
  e2e_describe "a goal and an active run with one event, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_events
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_equal yes "$(_section 'FlowRun Events' | grep -qx 'STATE=unavailable' && echo yes || echo no)" "the FlowRun Events section is unavailable"
  e2e_expect_equal no "$(_section 'FlowRun Events' | grep -qx 'GOAL_FILE_COUNT=0' && echo yes || echo no)" "the section counts no goal files"
  e2e_expect_equal no "$(_section 'FlowRun Events' | grep -qx 'RUN_EVENT_FILE_COUNT=0' && echo yes || echo no)" "the section counts no run events"
  _expect_err_lacks "not read through it"
fi

if _want learn-journal-dir-unchecked; then
  _flow_test_begin "journal-dir.sh (/flow:learn): a repository journal.dir it cannot check is withheld and said so, not called refused (L38)"
  e2e_new learn-journal-dir-unchecked
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_err "$UNCHECKED journal.dir 'docs/decisions' from .claude/settings.flow.json"
  _expect_err_lacks "$REPO_REFUSED"
fi

if _want resume-preflight-unchecked; then
  _flow_test_begin "/flow:resume pre-flight: a check that cannot run is not reported as no runs (L38)"
  e2e_new resume-preflight-unchecked
  e2e_describe "an active run, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'No FlowRuns exist'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "Cannot tell whether FlowRuns exist"
  e2e_expect_no_out "No FlowRuns exist"
  _expect_err_lacks "not read through"
fi

if _want resume-read-unchecked; then
  _flow_test_begin "/flow:resume run read: a check that cannot run is not reported as a symlink (L38)"
  e2e_new resume-read-unchecked
  e2e_describe "an active run, no symlink; python3 exits 1; the block runs with the run id step 1 chose"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _python_dead
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
fi

if _want start-goal-unchecked; then
  _flow_test_begin "/flow:start goal block: a check that cannot run blocks, and the goal is not treated as absent (L38)"
  e2e_new start-goal-unchecked
  e2e_describe "an active goal issue-42, no symlink; python3 exits 1; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_line "FLOW_GOAL_STATE=blocked"
  e2e_expect_out "FLOW_GOAL_ERROR=$UNCHECKED"
  e2e_expect_no_line "FLOW_GOAL_STATE=create"
fi

if _want start-journal-unchecked; then
  _flow_test_begin "/flow:start journal block: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new start-journal-unchecked
  e2e_describe "no journal directory, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
fi

if _want trigger-preflight-unchecked; then
  _flow_test_begin "/flow:trigger pre-flight: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new trigger-preflight-unchecked
  e2e_describe "flow.triggers.enabled is true; no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/trigger.md" '.flow/triggers'
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.flow/triggers" ] && echo yes || echo no)" ".flow/triggers was created"
fi

if _want watch-preflight-unchecked; then
  _flow_test_begin "/flow:watch pre-flight: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new watch-preflight-unchecked
  e2e_describe "flow.triggers.enabled is true; no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/watch.md" '.flow/triggers'
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
fi

if _want run-create-unchecked; then
  _flow_test_begin "run-state-management: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new run-create-unchecked
  e2e_describe "no symlink; python3 exits 1; the block runs with the run id the command chose"
  e2e_repo feature/issue-42-e2e
  _python_dead
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_no_line "RUN_DIR=.flow/runs/$RID"
fi

if _want strip-unchecked; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a check that cannot run is not reported as a refused symlink (L38)"
  e2e_new strip-unchecked
  e2e_describe ".decisions holds a journal with one breadcrumb; no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_REPO/.decisions/issue-42.md"
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_file_has ".decisions/issue-42.md" "$CRUMB"
fi

# .flow with no permissions: a component below it cannot be inspected, which
# is a check that could not be done, not a refusal. Skipped as root, which
# chmod does not stop.
_flow_is_root() { [ "$(id -u)" = 0 ]; }

if _want stop-block-goals-uninspectable; then
  _flow_test_begin "Stop hook (block): a .flow/goals that cannot be inspected leaves the goal unknown, not absent (L38)"
  if _flow_is_root; then
    _flow_assert_pass "SKIP: running as root, which permissions do not stop"
  else
    e2e_new stop-block-goals-uninspectable
    e2e_describe "stopHookEnforcement block; a trusted goal whose check fails; .flow is then made unreadable (mode 000); one stop"
    e2e_repo feature/issue-42-e2e
    _settings "$BLOCK"
    _create_goal g-link feature/issue-42-e2e
    chmod 000 "$E2E_REPO/.flow"
    e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
    chmod 755 "$E2E_REPO/.flow"
    e2e_expect_equal 0 "$E2E_RC" "the exit status"
    e2e_expect_out '"decision":"approve"'
    e2e_expect_out 'FLOW_GOAL_UNCHECKED'
    e2e_expect_no_out 'no active flow goal'
  fi
fi

if _want goal-status-uninspectable; then
  _flow_test_begin "/flow:goal status scan: a .flow/goals that cannot be inspected is unavailable, not none (L38)"
  if _flow_is_root; then
    _flow_assert_pass "SKIP: running as root, which permissions do not stop"
  else
    e2e_new goal-status-uninspectable
    e2e_describe "an active goal; .flow is then made unreadable (mode 000)"
    e2e_repo feature/issue-42-e2e
    e2e_goal g-link feature/issue-42-e2e active true
    chmod 000 "$E2E_REPO/.flow"
    e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" "$GOAL_SCAN_MARK"
    chmod 755 "$E2E_REPO/.flow"
    e2e_expect_line "STATE=unavailable"
    e2e_expect_no_line "STATE=none"
  fi
fi

# --- operands that look like options (L39) ----------------------------------

FLOW_MKDIR_HELP="Create a directory in the repository"

if _want start-journal-dir-check-named; then
  _flow_test_begin "/flow:start journal block: a journal.dir named --check is a directory, not an option (L39)"
  e2e_new start-journal-dir-check-named
  e2e_describe "journal.dir is --check in .claude/settings.flow.json"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"--check"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=./--check"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/--check" ] && [ ! -L "$E2E_REPO/--check" ] && echo yes || echo no)" "--check is a real directory"
  _expect_err_lacks "usage"
fi

if _want start-journal-dir-h-named; then
  _flow_test_begin "/flow:start journal block: a journal.dir named -h is a directory, not a request for help (L39)"
  e2e_new start-journal-dir-h-named
  e2e_describe "journal.dir is -h in .claude/settings.flow.json"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"-h"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=./-h"
  e2e_expect_no_out "$FLOW_MKDIR_HELP"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/-h" ] && [ ! -L "$E2E_REPO/-h" ] && echo yes || echo no)" "-h is a real directory"
fi

if _want start-journal-user-h-link; then
  _flow_test_begin "/flow:start journal block: a journal.dir named -h that the repository commits as a symlink is refused (L39)"
  e2e_new start-journal-user-h-link
  e2e_describe "journal.dir is -h in the user's settings; -h is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _user_settings '{"journal":{"dir":"-h"}}'
  _plant -h
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  _expect_refused 1 "refusing — -h is a symlink"
  e2e_expect_no_out "$FLOW_MKDIR_HELP"
fi

if _want strip-user-h-link; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a journal.dir named -h that the repository commits as a symlink is not rewritten (L39)"
  e2e_new strip-user-h-link
  e2e_describe "journal.dir is -h in the user's settings; -h is moved outside the repository and replaced by a symlink to it; its journal carries one breadcrumb"
  e2e_repo feature/issue-42-e2e
  _user_settings '{"journal":{"dir":"-h"}}'
  mkdir -p "$E2E_REPO/-h"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_REPO/-h/issue-42.md"
  _plant -h
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  _expect_refused 2 "-h is a symlink"
fi

# --- paths spelled through a symlink above the repository (L40) --------------
# The repository is named through $E2E_DIR/repo-link, a symlink beside it to
# the repository, so no string comparison with the working directory can
# match on any system; on macOS the path also runs through /var, a symlink to
# /private/var, as mktemp spells it.

# _repo_link — $E2E_DIR/repo-link, a symlink to the repository.
_repo_link() {
  ln -s "$E2E_REPO" "$E2E_DIR/repo-link" || _flow_assert_fail "$E2E_NAME: could not link the repository"
  printf 'the repository is also reached as <scratch>/%s/repo-link\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
}

if _want journal-append-user-logical-link; then
  _flow_test_begin "journal-append.sh --file: a path naming the repository through a symlink above it is still checked (L40)"
  e2e_new journal-append-user-logical-link
  e2e_describe "docs is a symlink to an empty directory outside the repository; journal-append.sh runs with --file <scratch>/repo-link/docs/j/issue-42.md, repo-link a symlink to the repository"
  e2e_repo feature/issue-42-e2e
  _repo_link
  _plant docs
  # An explicit --file: an absolute journal.dir from the user's settings is
  # written as configured without the walk (L48), so the walk through a path
  # spelled via repo-link is pinned with a path the rule still covers.
  _run_in . bin/journal-append.sh --file "$E2E_DIR/repo-link/docs/j/issue-42.md" --text entry
  _expect_refused 2 "refusing — docs is a symlink"
fi

if _want journal-append-file-logical-link; then
  _flow_test_begin "journal-append.sh --file: a journal named through a symlink above the repository is not written through a symlinked .decisions (L40)"
  e2e_new journal-append-file-logical-link
  e2e_describe ".decisions is a symlink to an empty directory outside the repository; journal-append.sh runs from the repository top with --file <scratch>/repo-link/.decisions/issue-42.md, repo-link a symlink to the repository"
  e2e_repo feature/issue-42-e2e
  _repo_link
  _plant .decisions
  {
    printf 'code: bin/journal-append.sh\n'
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/bin/journal-append.sh")"
    printf 'arguments: --file <scratch>/%s/repo-link/.decisions/issue-42.md --text entry\n' "$E2E_NAME"
  } >> "$E2E_ARTIFACT"
  _e2e_exec "$E2E_ACTIVE_PLUGIN/bin/journal-append.sh" --file "$E2E_DIR/repo-link/.decisions/issue-42.md" --text entry
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want journal-append-local-logical-inside; then
  _flow_test_begin "journal-dir.sh (/flow:brainstorm decision block): a repository journal.dir naming the repository through a symlink above it is inside (L40)"
  e2e_new journal-append-local-logical-inside
  e2e_describe "journal.dir in .claude/settings.flow.local.json is <scratch>/repo-link/docs/decisions, repo-link a symlink to the repository; no symlink under the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _repo_link
  _local_settings "{\"journal\":{\"dir\":\"$E2E_DIR/repo-link/docs/decisions\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "docs/decisions/issue-42.md" "$BRAINSTORM"
  _expect_err_lacks "$REPO_REFUSED"
fi

if _want flow-mkdir-dashdash; then
  _flow_test_begin "flow-mkdir.sh: -- ends the options, so a directory named -h is checked, not taken for help (L39)"
  e2e_new flow-mkdir-dashdash
  e2e_describe "-h is a symlink to an empty directory outside the repository; the helper is asked with --check -- -h"
  e2e_repo feature/issue-42-e2e
  _plant -h
  _run_bin bin/flow-mkdir.sh --check -- -h
  _expect_refused 2 "refusing — -h is a symlink"
  e2e_expect_no_out "$FLOW_MKDIR_HELP"
fi

if _want journal-append-user-logical-self-link; then
  _flow_test_begin "journal-append.sh --file: a symlink below the repository that points back at its top is still a component to walk (L40)"
  e2e_new journal-append-user-logical-self-link
  e2e_describe "self is a symlink the repository commits to its own top; journal-append.sh runs with --file <scratch>/repo-link/self/j/issue-42.md, repo-link a symlink to the repository"
  e2e_repo feature/issue-42-e2e
  _repo_link
  ln -s . "$E2E_REPO/self" || _flow_assert_fail "$E2E_NAME: could not plant self"
  printf 'planted: self -> .\n' >> "$E2E_ARTIFACT"
  # An explicit --file, for the reason journal-append-user-logical-link gives.
  _run_in . bin/journal-append.sh --file "$E2E_DIR/repo-link/self/j/issue-42.md" --text entry
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — self is a symlink"
  e2e_expect_equal no "$([ -e "$E2E_REPO/j" ] && echo yes || echo no)" "j was created at the repository top through self"
fi

# --- writers run from a subdirectory (L41-L43) -------------------------------
# The check starts at the repository top: the nearest directory at or above
# the working directory with a .git entry (a file in a worktree).


if _want append-subdir-decisions-link; then
  _flow_test_begin "journal-append.sh --file from a subdirectory: a symlinked .decisions at the repository top is refused (L41)"
  e2e_new append-subdir-decisions-link
  e2e_describe ".decisions is a symlink to an empty directory outside the repository; journal-append.sh runs in src/ with --file ../.decisions/issue-42.md"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/src"
  _plant .decisions
  _run_in src bin/journal-append.sh --file ../.decisions/issue-42.md --text entry
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want record-subdir-decisions-link; then
  _flow_test_begin "journal-record.sh from a subdirectory: a symlinked .decisions at the repository top is refused (L41)"
  e2e_new record-subdir-decisions-link
  e2e_describe ".decisions is a symlink to an empty directory outside the repository; journal.dir in the user's settings is ../.decisions; journal-record.sh runs in src/"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/src"
  # Relative: an absolute journal.dir from the user's settings is written as
  # configured without the walk (L48); a relative one keeps the rule, walked
  # from the repository top.
  _user_settings '{"journal":{"dir":"../.decisions"}}'
  _plant .decisions
  _run_in src bin/journal-record.sh --issue 42 --type stranger-test --metadata result=PASS
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want append-subdir-real; then
  _flow_test_begin "journal-append.sh --file from a subdirectory: an ordinary .decisions at the repository top is written (L42)"
  e2e_new append-subdir-real
  e2e_describe "no symlink under the repository; journal-append.sh runs in src/ with --file ../.decisions/issue-42.md"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/src"
  _run_in src bin/journal-append.sh --file ../.decisions/issue-42.md --text entry
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".decisions/issue-42.md" "entry"
fi

if _want record-subdir-real; then
  _flow_test_begin "journal-record.sh from a subdirectory: an ordinary .decisions at the repository top is written (L42)"
  e2e_new record-subdir-real
  e2e_describe "no symlink under the repository; journal.dir in the user's settings is ../.decisions; journal-record.sh runs in src/"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/src"
  _user_settings '{"journal":{"dir":"../.decisions"}}'
  _run_in src bin/journal-record.sh --issue 42 --type stranger-test --metadata result=PASS
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".decisions/issue-42.md" "type: stranger-test"
fi

if _want append-nested-repo-link; then
  _flow_test_begin "journal-append.sh --file in a nested repository: its own top applies (L43)"
  e2e_new append-nested-repo-link
  e2e_describe "inner/ is a git repository inside the scratch repository; inner/.decisions is a symlink to an empty directory outside both; journal-append.sh runs in inner/src with --file ../.decisions/issue-42.md"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/inner/src"
  (_e2e_git_env; cd "$E2E_REPO/inner" && git init -q) || _flow_assert_fail "$E2E_NAME: could not create the nested repository"
  _plant inner/.decisions
  _run_in inner/src bin/journal-append.sh --file ../.decisions/issue-42.md --text entry
  # Named from the nested repository's top, not the outer one's.
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want append-worktree-link; then
  _flow_test_begin "journal-append.sh --file in a git worktree: the worktree's top applies (L43)"
  e2e_new append-worktree-link
  e2e_describe "wt is a git worktree of the scratch repository (its .git is a file); wt/.decisions is a symlink to an empty directory outside the repository; journal-append.sh runs in wt/src with --file ../.decisions/issue-42.md"
  e2e_repo feature/issue-42-e2e
  (_e2e_git_env; cd "$E2E_REPO" && git worktree add -q -b e2e-wt "$E2E_DIR/wt") ||
    _flow_assert_fail "$E2E_NAME: could not add the worktree"
  mkdir -p "$E2E_DIR/wt/src" "$E2E_DIR/outside"
  ln -s "$E2E_DIR/outside" "$E2E_DIR/wt/.decisions" || _flow_assert_fail "$E2E_NAME: could not plant wt/.decisions"
  printf 'planted: wt/.decisions -> <scratch>/%s/outside\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  _run_in "$E2E_DIR/wt/src" bin/journal-append.sh --file ../.decisions/issue-42.md --text entry
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

# --- per-user state under a home kept in git (L44, L45) ----------------------

# _git_home — the scenario's HOME is a git repository on branch
# feature/issue-42-e2e. ~/.claude is made a directory unless it is already
# there (_stow_home plants it as a symlink first).
_git_home() {
  mkdir -p "$E2E_HOME/.claude" &&
    (
      _e2e_git_env
      cd "$E2E_HOME" &&
        git init -q &&
        git config user.email e2e@example.invalid &&
        git config user.name e2e &&
        git config commit.gpgsign false &&
        git commit -q --allow-empty -m init &&
        git checkout -q -b feature/issue-42-e2e
    ) || _flow_assert_fail "$E2E_NAME: could not make HOME a repository"
  printf 'HOME is a git repository\n' >> "$E2E_ARTIFACT"
}

# _stow_home — _git_home, with $HOME/.claude a symlink to
# $E2E_DIR/dotfiles/claude, as GNU stow makes it. E2E_REPO becomes $HOME/proj,
# a folder inside it that is not a repository of its own.
_stow_home() {
  mkdir -p "$E2E_DIR/dotfiles/claude" "$E2E_HOME/proj" &&
    ln -s "$E2E_DIR/dotfiles/claude" "$E2E_HOME/.claude" ||
    _flow_assert_fail "$E2E_NAME: could not stow HOME/.claude"
  _git_home
  # Named through $E2E_DIR, as the harness expects, whichever way HOME is spelled.
  E2E_REPO="$E2E_DIR/home/proj"
  printf 'HOME/.claude -> <scratch>/%s/dotfiles/claude; the working directory is HOME/proj, not a repository of its own\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
}

if _want per-user-ledger-stow-home; then
  _flow_test_begin "flow-goal-record.sh --create: the trust ledger under a stowed ~/.claude is written, whatever the repository top (L44)"
  e2e_new per-user-ledger-stow-home
  e2e_describe "HOME is a git repository and ~/.claude a symlink to a directory elsewhere; a goal is created from HOME/proj as goal-contract-capture creates it"
  _stow_home
  _goal_source g-home feature/issue-42-e2e
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_err_lacks "trust ledger record failed"
  e2e_expect_equal yes "$(grep -q '"goal_id": "g-home"' "$E2E_DIR/dotfiles/claude/flow-state/goal-trust.jsonl" 2>/dev/null && echo yes || echo no)" "the trust ledger in the stowed directory records the goal"
  e2e_expect_file_has ".flow/goals/g-home.goal.yaml" "id: g-home"
fi

if _want repo-link-stow-home; then
  _flow_test_begin "flow-goal-record.sh --create: a symlinked .flow in a folder of that home is still refused (L45)"
  e2e_new repo-link-stow-home
  e2e_describe "HOME is a git repository and ~/.claude a symlink to a directory elsewhere; HOME/proj/.flow is a symlink to an empty directory outside"
  _stow_home
  _goal_source g-home feature/issue-42-e2e
  _plant .flow
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  _expect_refused 2 "refusing — proj/.flow is a symlink"
fi

if _want project-link-stow-home; then
  _flow_test_begin "flow-goal-record.sh --create: a symlinked .flow in a project repository inside that home is still refused (L45)"
  e2e_new project-link-stow-home
  e2e_describe "HOME is a git repository and ~/.claude a symlink to a directory elsewhere; HOME/project is a git repository whose .flow is a symlink to an empty directory outside"
  _stow_home
  mkdir -p "$E2E_HOME/project"
  (_e2e_git_env; cd "$E2E_HOME/project" && git init -q) || _flow_assert_fail "$E2E_NAME: could not make the project repository"
  E2E_REPO="$E2E_HOME/project"
  _goal_source g-home feature/issue-42-e2e
  _plant .flow
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

# _physical_home — HOME exported by its physical path ($E2E_HOME; the
# scenario still names directories through $E2E_DIR, as the harness expects). The paths these
# scenarios write are taken from the physical working directory, and on
# macOS mktemp spells HOME through /var: with the two spellings apart, a path
# under ~/.claude would never be taken for per-user state, and the limits of
# that exemption would pass untested.
_physical_home() { E2E_HOME=$(cd "$E2E_HOME" && pwd -P); }

if _want config-dir-repo-link; then
  _flow_test_begin "flow-mkdir.sh: a repository kept inside ~/.claude keeps the rule for its own paths (L45)"
  e2e_new config-dir-repo-link
  e2e_describe "HOME/.claude/plugins/clone is a git repository (as a plugin marketplace clone is) whose .flow is a symlink to an empty directory outside"
  _physical_home
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_HOME/.claude/plugins/clone"
  (_e2e_git_env; cd "$E2E_HOME/.claude/plugins/clone" && git init -q) || _flow_assert_fail "$E2E_NAME: could not make the repository"
  E2E_REPO="$E2E_DIR/home/.claude/plugins/clone"
  _plant .flow
  # Absolute, the only kind of path that can be per-user state.
  _run_in . bin/flow-mkdir.sh -- "$E2E_HOME/.claude/plugins/clone/.flow/runs/r"
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want repo-link-into-config; then
  _flow_test_begin "journal-append.sh --file: a repository symlink that points into ~/.claude is still refused (L45)"
  e2e_new repo-link-into-config
  e2e_describe ".decisions is a symlink the repository commits to HOME/.claude/stolen; journal-append.sh runs with --file .decisions/issue-42.md"
  _physical_home
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_HOME/.claude/stolen"
  ln -s "$E2E_HOME/.claude/stolen" "$E2E_REPO/.decisions" || _flow_assert_fail "$E2E_NAME: could not plant .decisions"
  printf 'planted: .decisions -> <scratch>/%s/home/.claude/stolen\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  # Absolute, the only kind of path that can be per-user state.
  _run_in . bin/journal-append.sh --file "$(_physical "$E2E_REPO")/.decisions/issue-42.md" --text entry
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .decisions is a symlink"
  e2e_expect_equal no "$([ -e "$E2E_HOME/.claude/stolen/issue-42.md" ] && echo yes || echo no)" "a journal was written into the user's config directory"
fi

if _want dotdot-into-config-stow-home; then
  _flow_test_begin "journal-append.sh --file: a path that climbs back into ~/.claude through a repository symlink is refused (L45)"
  e2e_new dotdot-into-config-stow-home
  e2e_describe "HOME is a git repository and ~/.claude a symlink to a directory elsewhere; HOME/proj/.decisions is a symlink to outside/a/b; journal-append.sh runs in HOME/proj with --file .decisions/../../.claude/issue-42.md, which reads as ~/.claude/issue-42.md but the kernel resolves through .decisions"
  _physical_home
  _stow_home
  mkdir -p "$E2E_DIR/outside/a/b"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/.decisions" || _flow_assert_fail "$E2E_NAME: could not plant .decisions"
  printf 'planted: proj/.decisions -> <scratch>/%s/outside/a/b\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  _run_bin bin/journal-append.sh --file .decisions/../../.claude/issue-42.md --text entry
  _expect_refused 2 "refusing — proj/.decisions is a symlink"
fi

if _want dotdot-abs-into-config-stow-home; then
  _flow_test_begin "journal-append.sh --file: an absolute path that climbs back into ~/.claude through a repository symlink is refused (L45)"
  e2e_new dotdot-abs-into-config-stow-home
  e2e_describe "HOME is a git repository and ~/.claude a symlink to a directory elsewhere; HOME/proj/.decisions is a symlink to outside/a/b; journal-append.sh runs in HOME/proj with --file <HOME>/proj/.decisions/../../.claude/issue-42.md, which reads as ~/.claude/issue-42.md but the kernel resolves through .decisions"
  _physical_home
  _stow_home
  mkdir -p "$E2E_DIR/outside/a/b"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/.decisions" || _flow_assert_fail "$E2E_NAME: could not plant .decisions"
  printf 'planted: proj/.decisions -> <scratch>/%s/outside/a/b\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  _run_in . bin/journal-append.sh --file "$E2E_HOME/proj/.decisions/../../.claude/issue-42.md" --text entry
  _expect_refused 2 "refusing — proj/.decisions is a symlink"
fi

# --- relative paths and the per-user roots (L46, L47) ------------------------

# _run_env <NAME=value> <file under the plugin> [arguments] — run a helper in
# the repository with one more environment variable, which the harness would
# otherwise clear. The artifact names the scratch root by its token.
_run_env() {
  local assign="$1" rel="$2"; shift 2
  local p_private="/private$E2E_ROOT" p_root="$E2E_ROOT" shown
  shown="${assign//"$p_private"/<scratch>} $*"
  shown="${shown//"$p_private"/<scratch>}"; shown="${shown//"$p_root"/<scratch>}"
  {
    printf 'code: %s\n' "$rel"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$rel")"
    printf 'environment and arguments: %s\n' "$shown"
  } >> "$E2E_ARTIFACT"
  _e2e_exec env "$assign" "$E2E_ACTIVE_PLUGIN/$rel" "$@"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

if _want relative-in-config-folder-link; then
  _flow_test_begin "flow-mkdir.sh: a relative .flow in a folder inside ~/.claude is repository content, and its symlink is refused (L46)"
  e2e_new relative-in-config-folder-link
  e2e_describe "HOME is a git repository; the working directory is HOME/.claude/plugins/cache/p, not a repository of its own; its .flow is a symlink to an empty directory outside; flow-mkdir.sh -- .flow/runs/r"
  _physical_home
  _git_home
  mkdir -p "$E2E_HOME/.claude/plugins/cache/p"
  E2E_REPO="$E2E_DIR/home/.claude/plugins/cache/p"
  _plant .flow
  _run_bin bin/flow-mkdir.sh -- .flow/runs/r
  _expect_refused 2 "p/.flow is a symlink"
fi

if _want relative-state-dir-in-repo-link; then
  _flow_test_begin "flow-mkdir.sh: FLOW_STATE_DIR set inside the repository does not exempt a relative path (L46)"
  e2e_new relative-state-dir-in-repo-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository; FLOW_STATE_DIR is the repository's .flow; flow-mkdir.sh -- .flow/runs/r"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.flow"
  _plant .flow/runs
  _run_env "FLOW_STATE_DIR=$(_physical "$E2E_REPO")/.flow" bin/flow-mkdir.sh -- .flow/runs/r
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

if _want config-dir-env-not-root; then
  _flow_test_begin "flow-mkdir.sh: CLAUDE_CONFIG_DIR is not a per-user root (L47)"
  e2e_new config-dir-env-not-root
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository; CLAUDE_CONFIG_DIR is the repository's .flow; flow-mkdir.sh -- <repository>/.flow/runs/r"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.flow"
  _plant .flow/runs
  _run_env "CLAUDE_CONFIG_DIR=$(_physical "$E2E_REPO")/.flow" bin/flow-mkdir.sh -- "$(_physical "$E2E_REPO")/.flow/runs/r"
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

# --- an absolute journal.dir from the user's settings (L48) ------------------

# _dropbox_home — HOME is a git repository; ~/Dropbox is a symlink the user
# made to $E2E_DIR/cloud/Dropbox; the working directory is HOME/notes, not a
# repository of its own.
_dropbox_home() {
  _git_home
  mkdir -p "$E2E_DIR/cloud/Dropbox" "$E2E_HOME/notes" &&
    ln -s "$E2E_DIR/cloud/Dropbox" "$E2E_HOME/Dropbox" ||
    _flow_assert_fail "$E2E_NAME: could not make ~/Dropbox"
  E2E_REPO="$E2E_DIR/home/notes"
  printf 'HOME/Dropbox -> <scratch>/%s/cloud/Dropbox; the working directory is HOME/notes\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
}
DROPBOX_J="cloud/Dropbox/decisions/issue-42.md"

if _want dropbox-user-record; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): an absolute user journal.dir through ~/Dropbox is written as configured (L48)"
  e2e_new dropbox-user-record
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions"
  _dropbox_home
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -q 'type: stranger-test' "$E2E_DIR/$DROPBOX_J" 2>/dev/null && echo yes || echo no)" "the manifest is in the Dropbox journal"
  _expect_err_lacks "refusing"
fi

if _want dropbox-user-append; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): an absolute user journal.dir through ~/Dropbox is written as configured (L48)"
  e2e_new dropbox-user-append
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions; branch feature/issue-42-e2e"
  _dropbox_home
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -qF "$BRAINSTORM" "$E2E_DIR/$DROPBOX_J" 2>/dev/null && echo yes || echo no)" "the entry is in the Dropbox journal"
  _expect_err_lacks "refusing"
fi

if _want dropbox-user-append-file; then
  _flow_test_begin "journal-append.sh --file: a file under an absolute user journal.dir through ~/Dropbox is written, as the auto-log hooks write it (L48)"
  e2e_new dropbox-user-append-file
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions; journal-append.sh --file <HOME>/Dropbox/decisions/auto-log/issue-42.md"
  _dropbox_home
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  _run_in . bin/journal-append.sh --file "$E2E_HOME/Dropbox/decisions/auto-log/issue-42.md" --text entry
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -q entry "$E2E_DIR/cloud/Dropbox/decisions/auto-log/issue-42.md" 2>/dev/null && echo yes || echo no)" "the trail entry is in the Dropbox journal"
fi

if _want dropbox-user-strip; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): an absolute user journal.dir through ~/Dropbox is stripped where it points (L48)"
  e2e_new dropbox-user-strip
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions, whose journal carries one breadcrumb"
  _dropbox_home
  mkdir -p "$E2E_DIR/cloud/Dropbox/decisions"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_DIR/$DROPBOX_J"
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  E2E_FENCE_SHELLS="${E2E_FENCE_SHELLS%% *}" e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "STRIP_AUTO_LOG_APPLIED=1 files=1 removed=1 warned=0"
  _expect_err_lacks "refusing"
fi

if _want dropbox-user-start; then
  _flow_test_begin "/flow:start journal block: an absolute user journal.dir through ~/Dropbox is created as configured (L48)"
  e2e_new dropbox-user-start
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions, not there yet"
  _dropbox_home
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$([ -d "$E2E_DIR/cloud/Dropbox/decisions" ] && echo yes || echo no)" "the Dropbox journal directory exists"
  _expect_err_lacks "refusing"
fi

if _want dropbox-repo-value; then
  _flow_test_begin "journal-dir.sh (/flow:brainstorm decision block): the same path as a repository journal.dir is refused (L48)"
  e2e_new dropbox-repo-value
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in HOME/notes/.claude/settings.flow.local.json is <HOME>/Dropbox/decisions; branch feature/issue-42-e2e"
  _dropbox_home
  _local_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED"
  e2e_expect_file_has ".decisions/issue-42.md" "$BRAINSTORM"
  e2e_expect_equal no "$([ -e "$E2E_DIR/$DROPBOX_J" ] && echo yes || echo no)" "a journal was written in Dropbox"
fi

if _want dropbox-user-relative; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a relative user journal.dir through ~/Dropbox keeps the rule (L48)"
  e2e_new dropbox-user-relative
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is ../Dropbox/decisions; branch feature/issue-42-e2e"
  _dropbox_home
  _user_settings '{"journal":{"dir":"../Dropbox/decisions"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — Dropbox is a symlink"
  e2e_expect_equal no "$([ -e "$E2E_DIR/$DROPBOX_J" ] && echo yes || echo no)" "a journal was written in Dropbox"
fi

if _want dropbox-user-relative-start; then
  _flow_test_begin "/flow:start journal block: a relative user journal.dir through ~/Dropbox keeps the rule (L48)"
  e2e_new dropbox-user-relative-start
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is ../Dropbox/decisions, not there yet"
  _dropbox_home
  _user_settings '{"journal":{"dir":"../Dropbox/decisions"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "Dropbox is a symlink"
  e2e_expect_equal no "$([ -e "$E2E_DIR/cloud/Dropbox/decisions" ] && echo yes || echo no)" "the Dropbox journal directory was created"
fi

# --- which journal.dir is the user's own (L49-L52) ---------------------------

if _want journal-append-repo-absolute-inside-link; then
  _flow_test_begin "journal-append.sh --file: an absolute repository journal.dir inside the repository is not the user's own, and a symlink below it is refused (L49)"
  e2e_new journal-append-repo-absolute-inside-link
  e2e_describe "journal.dir in .claude/settings.flow.local.json is <repository>/docs/j, real directories; docs/j/auto-log is a symlink to an empty directory outside the repository; journal-append.sh --file <repository>/docs/j/auto-log/issue-42.md, as the auto-log hooks pass one"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/docs/j"
  _local_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")/docs/j\"}}"
  _plant docs/j/auto-log
  _run_in . bin/journal-append.sh --file "$(_physical "$E2E_REPO")/docs/j/auto-log/issue-42.md" --text entry
  _expect_refused 2 "refusing — docs/j/auto-log is a symlink"
  _run_in . bin/journal-dir.sh --user-owned
  e2e_expect_equal 1 "$E2E_RC" "journal-dir.sh --user-owned exit status"
  e2e_expect_equal "" "$E2E_OUT" "what journal-dir.sh --user-owned prints"
fi

# _sub_dotdot_link [tail] — sub is a symlink the repository commits to
# outside/a/b, and journal.dir in the user's settings is <repository>/sub/
# followed by <tail>, ../j when none is given: read without the link
# <repository>/sub/../j is <repository>/j, but the kernel resolves sub first,
# so it names outside/a/j. A tail of .. names outside/a: the `..` is the last
# component.
_sub_dotdot_link() {
  local tail="${1:-../j}"
  mkdir -p "$E2E_DIR/outside/a/b"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/sub" || _flow_assert_fail "$E2E_NAME: could not plant sub"
  printf 'planted: sub -> <scratch>/%s/outside/a/b\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")/sub/$tail\"}}"
}

if _want start-journal-user-dotdot-link; then
  _flow_test_begin "/flow:start journal block: an absolute user journal.dir that climbs out of a repository symlink with .. keeps the rule (L50)"
  e2e_new start-journal-user-dotdot-link
  e2e_describe "sub is a symlink the repository commits to outside/a/b; journal.dir in the user's settings is <repository>/sub/../j, which the kernel resolves to outside/a/j"
  e2e_repo feature/issue-42-e2e
  _sub_dotdot_link
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  _expect_refused 1 "refusing — sub is a symlink"
fi

if _want start-journal-user-dotdot-last-link; then
  _flow_test_begin "/flow:start journal block: an absolute user journal.dir that ends in a .. after a repository symlink keeps the rule (L50)"
  e2e_new start-journal-user-dotdot-last-link
  e2e_describe "sub is a symlink the repository commits to outside/a/b; journal.dir in the user's settings is <repository>/sub/.., which the kernel resolves to outside/a"
  e2e_repo feature/issue-42-e2e
  _sub_dotdot_link ..
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  _expect_refused 1 "refusing — sub is a symlink"
fi

if _want strip-user-dotdot-link; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip dry run): an absolute user journal.dir that climbs out of a repository symlink with .. is not read (L50)"
  e2e_new strip-user-dotdot-link
  e2e_describe "sub is a symlink the repository commits to outside/a/b; journal.dir in the user's settings is <repository>/sub/../j; outside/a/j holds a journal carrying one breadcrumb"
  e2e_repo feature/issue-42-e2e
  _sub_dotdot_link
  mkdir -p "$E2E_DIR/outside/a/j"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_DIR/outside/a/j/issue-42.md"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" 'dry-run — emits STRIP_AUTO_LOG'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — journal dir"
  e2e_expect_err "sub is a symlink"
  e2e_expect_no_out "STRIP_AUTO_LOG_FILE="
  _expect_untouched
fi

if _want dropbox-user-record-at-home; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): run at HOME, the user's own settings file is not taken for the repository's (L51)"
  e2e_new dropbox-user-record-at-home
  e2e_describe "HOME is a git repository and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions; the working directory is HOME, whose .claude/settings.flow.json is that same file"
  _dropbox_home
  E2E_REPO="$E2E_DIR/home"
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -q 'type: stranger-test' "$E2E_DIR/$DROPBOX_J" 2>/dev/null && echo yes || echo no)" "the manifest is in the Dropbox journal"
  e2e_expect_equal no "$([ -e "$E2E_HOME/.decisions/issue-42.md" ] && echo yes || echo no)" "a journal was written in ~/.decisions"
  _expect_err_lacks "refusing"
  _run_in . bin/journal-dir.sh --user-owned
  e2e_expect_equal 0 "$E2E_RC" "journal-dir.sh --user-owned exit status"
  e2e_expect_equal yes "$([ "$E2E_OUT" = "$E2E_HOME/Dropbox/decisions" ] && echo yes || echo no)" "journal-dir.sh --user-owned prints <HOME>/Dropbox/decisions"
fi

# _dropbox_trail_has <text> — the auto-log trail of issue 42 in the Dropbox
# journal holds <text>. The trail is named by month, so it is found by a glob.
_dropbox_trail_has() {
  local f found=no
  for f in "$E2E_DIR"/cloud/Dropbox/decisions/auto-log/issue-42.*.md; do
    [ -f "$f" ] && grep -qF -- "$1" "$f" && found=yes
  done
  e2e_expect_equal yes "$found" "the Dropbox trail holds: $1"
}

# _home_decisions_journal — ~/.decisions holds issue-42.md, so a hook that took
# ~/.decisions for the journal dir would write its trail there: the hook logs
# only beside a journal that exists.
_home_decisions_journal() {
  mkdir -p "$E2E_HOME/.decisions" && printf '# Journal\n' > "$E2E_HOME/.decisions/issue-42.md" ||
    _flow_assert_fail "$E2E_NAME: could not write ~/.decisions/issue-42.md"
}

if _want dropbox-user-hook-edit; then
  _flow_test_begin "PostToolUse log-file-changes.sh: an edit is logged to the trail under an absolute user journal.dir through ~/Dropbox (L52)"
  e2e_new dropbox-user-hook-edit
  e2e_describe "HOME, spelled physically, is a git repository on feature/issue-42-e2e and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions, which holds issue-42.md, and ~/.decisions holds issue-42.md too; an Edit of HOME/notes/note.md, with the hook's working directory in HOME/notes"
  _physical_home
  _dropbox_home
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  mkdir -p "$E2E_DIR/cloud/Dropbox/decisions"
  printf '# Journal\n' > "$E2E_DIR/$DROPBOX_J"
  _home_decisions_journal
  e2e_run_hook hooks/scripts/log-file-changes.sh '{"tool_name":"Edit","tool_input":{"file_path":"note.md"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _dropbox_trail_has "Edit notes/note.md -->"
  e2e_expect_equal yes "$([ -f "$E2E_DIR/cloud/Dropbox/decisions/auto-log/.gitignore" ] && echo yes || echo no)" "the Dropbox trail directory ignores itself"
  e2e_expect_equal no "$([ -e "$E2E_HOME/.decisions/auto-log" ] && echo yes || echo no)" "~/.decisions/auto-log exists"
fi

if _want dropbox-user-hook-commit; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit is logged to the trail under an absolute user journal.dir through ~/Dropbox (L52)"
  e2e_new dropbox-user-hook-commit
  e2e_describe "HOME, spelled physically, is a git repository on feature/issue-42-e2e whose last commit is init, and ~/Dropbox a symlink the user made; journal.dir in the user's settings is <HOME>/Dropbox/decisions, which holds issue-42.md, and ~/.decisions holds issue-42.md too; a git commit run in HOME/notes"
  _physical_home
  _dropbox_home
  _user_settings "{\"journal\":{\"dir\":\"$E2E_HOME/Dropbox/decisions\"}}"
  mkdir -p "$E2E_DIR/cloud/Dropbox/decisions"
  printf '# Journal\n' > "$E2E_DIR/$DROPBOX_J"
  _home_decisions_journal
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m init"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _dropbox_trail_has 'commit "init" -->'
  e2e_expect_equal yes "$([ -f "$E2E_DIR/cloud/Dropbox/decisions/auto-log/.gitignore" ] && echo yes || echo no)" "the Dropbox trail directory ignores itself"
  e2e_expect_equal no "$([ -e "$E2E_HOME/.decisions/auto-log" ] && echo yes || echo no)" "~/.decisions/auto-log exists"
fi

# _decisions_link_journal — the repository's .decisions, holding issue-42.md,
# is moved outside the repository and replaced by a symlink to it; the user
# sets no journal.dir.
_decisions_link_journal() {
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions
}

if _want hook-edit-decisions-link; then
  _flow_test_begin "PostToolUse log-file-changes.sh: a symlinked .decisions the repository commits gets no trail (L52)"
  e2e_new hook-edit-decisions-link
  e2e_describe ".decisions, holding issue-42.md, is a symlink to a directory outside the repository; no journal.dir is set; an Edit of note.md on feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _decisions_link_journal
  e2e_run_hook hooks/scripts/log-file-changes.sh '{"tool_name":"Edit","tool_input":{"file_path":"note.md"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want hook-commit-decisions-link; then
  _flow_test_begin "PostToolUse log-commits.sh: a symlinked .decisions the repository commits gets no trail (L52)"
  e2e_new hook-commit-decisions-link
  e2e_describe ".decisions, holding issue-42.md, is a symlink to a directory outside the repository; no journal.dir is set; a git commit on feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _decisions_link_journal
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m init"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

# _hook_top_differs — the repository's .decisions, holding issue-42.md, is a
# symlink to a directory outside the repository; its
# .claude/settings.flow.local.json sets a journal.dir carrying a control
# character, which the settings cascade refuses, printing the default
# .decisions; the user's settings set an absolute journal.dir, userj, which
# holds issue-42.md too. Asked at the repository top, journal-dir.sh prints
# .decisions and --user-owned prints nothing; asked in sub, where no
# repository settings file is, both print userj. The hook then runs with its
# working directory in sub: the payload's cwd would not move it.
_hook_top_differs() {
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/sub" "$E2E_DIR/userj"
  _local_settings '{"journal":{"dir":"a\u0001b"}}'
  _decisions_link_journal
  printf '# Journal\n' > "$E2E_DIR/userj/issue-42.md"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/userj")\"}}"
  E2E_REPO="$E2E_DIR/repo/sub"
  printf 'the hook runs in <repository>/sub\n' >> "$E2E_ARTIFACT"
}

if _want hook-edit-user-owned-top; then
  _flow_test_begin "PostToolUse log-file-changes.sh: whether the journal dir is the user's own is asked at the repository top, where the journal dir was resolved (L53)"
  e2e_new hook-edit-user-owned-top
  e2e_describe ".decisions, holding issue-42.md, is a symlink to a directory outside the repository; .claude/settings.flow.local.json sets journal.dir to a value with a control character, which the cascade refuses; the user's settings set an absolute journal.dir outside the repository that holds issue-42.md; an Edit of note.md on feature/issue-42-e2e, with the hook's working directory in <repository>/sub"
  _hook_top_differs
  e2e_run_hook hooks/scripts/log-file-changes.sh '{"tool_name":"Edit","tool_input":{"file_path":"note.md"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
  e2e_expect_equal no "$([ -e "$E2E_DIR/userj/auto-log" ] && echo yes || echo no)" "the user's journal.dir has an auto-log directory"
fi

if _want hook-commit-user-owned-top; then
  _flow_test_begin "PostToolUse log-commits.sh: whether the journal dir is the user's own is asked at the repository top, where the journal dir was resolved (L53)"
  e2e_new hook-commit-user-owned-top
  e2e_describe ".decisions, holding issue-42.md, is a symlink to a directory outside the repository; .claude/settings.flow.local.json sets journal.dir to a value with a control character, which the cascade refuses; the user's settings set an absolute journal.dir outside the repository that holds issue-42.md; a git commit on feature/issue-42-e2e, with the hook's working directory in <repository>/sub"
  _hook_top_differs
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m init"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
  e2e_expect_equal no "$([ -e "$E2E_DIR/userj/auto-log" ] && echo yes || echo no)" "the user's journal.dir has an auto-log directory"
fi

# --- the auto-log hooks and a repository spelled through a symlink (L54) -----

# _link_above <tail> — up, beside the repository, is a symlink the scenario
# makes to the directory above the repository, so <D>/up/repo names the
# repository through a symlink above it; <D> is that directory's physical
# path, so no other link (macOS's /var) is on the way. sub is a symlink the
# repository commits to outside/a/b, and outside/a/j holds issue-42.md, as
# does <D>/j; <D>/x is a real directory. journal.dir in the user's settings is
# <D>/<tail>.
_link_above() {
  local d
  e2e_repo feature/issue-42-e2e
  d=$(_physical "$E2E_DIR")
  mkdir -p "$E2E_DIR/outside/a/b" "$E2E_DIR/outside/a/j" "$E2E_DIR/x" "$E2E_DIR/j"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/sub" || _flow_assert_fail "$E2E_NAME: could not plant sub"
  ln -s "$d" "$E2E_DIR/up" || _flow_assert_fail "$E2E_NAME: could not make up"
  printf 'planted: sub -> <scratch>/%s/outside/a/b\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  printf 'up -> <scratch>/%s, the directory above the repository\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  printf '# Journal\n' > "$E2E_DIR/outside/a/j/issue-42.md"
  printf '# Journal\n' > "$E2E_DIR/j/issue-42.md"
  _user_settings "{\"journal\":{\"dir\":\"$d/$1\"}}"
  BEFORE=$(_outside_state)
}

# _j_trail_has <text> — the auto-log trail of issue 42 in <D>/j holds <text>.
_j_trail_has() {
  local f found=no
  for f in "$E2E_DIR"/j/auto-log/issue-42.*.md; do
    [ -f "$f" ] && grep -qF -- "$1" "$f" && found=yes
  done
  e2e_expect_equal yes "$found" "the trail in <D>/j holds: $1"
}

EDIT_PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"note.md"}}'
COMMIT_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m init"}}'

if _want hook-edit-link-above-sub-dotdot; then
  _flow_test_begin "PostToolUse log-file-changes.sh: a user journal.dir naming the repository through a symlink above it gets nothing created through a repository symlink (L54)"
  e2e_new hook-edit-link-above-sub-dotdot
  e2e_describe "journal.dir in the user's settings is <D>/up/repo/sub/../j, with up a symlink to <D>, the directory above the repository, and sub a symlink the repository commits to outside/a/b, whose outside/a/j holds issue-42.md; an Edit of note.md on feature/issue-42-e2e"
  _link_above up/repo/sub/../j
  e2e_run_hook hooks/scripts/log-file-changes.sh "$EDIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want hook-commit-link-above-sub-dotdot; then
  _flow_test_begin "PostToolUse log-commits.sh: a user journal.dir naming the repository through a symlink above it gets nothing created through a repository symlink (L54)"
  e2e_new hook-commit-link-above-sub-dotdot
  e2e_describe "journal.dir in the user's settings is <D>/up/repo/sub/../j, with up a symlink to <D>, the directory above the repository, and sub a symlink the repository commits to outside/a/b, whose outside/a/j holds issue-42.md; a git commit on feature/issue-42-e2e"
  _link_above up/repo/sub/../j
  e2e_run_hook hooks/scripts/log-commits.sh "$COMMIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want hook-edit-link-above-leaves; then
  _flow_test_begin "PostToolUse log-file-changes.sh: a user journal.dir that leaves the repository with .. gets no trail, however the repository is spelled (L54)"
  e2e_new hook-edit-link-above-leaves
  e2e_describe "journal.dir in the user's settings is <D>/up/repo/../j, with up a symlink to <D>, the directory above the repository; <D>/j holds issue-42.md; an Edit of note.md on feature/issue-42-e2e"
  _link_above up/repo/../j
  e2e_run_hook hooks/scripts/log-file-changes.sh "$EDIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal no "$([ -e "$E2E_DIR/j/auto-log" ] && echo yes || echo no)" "<D>/j has an auto-log directory"
fi

if _want hook-commit-link-above-leaves; then
  _flow_test_begin "PostToolUse log-commits.sh: a user journal.dir that leaves the repository with .. gets no trail, however the repository is spelled (L54)"
  e2e_new hook-commit-link-above-leaves
  e2e_describe "journal.dir in the user's settings is <D>/up/repo/../j, with up a symlink to <D>, the directory above the repository; <D>/j holds issue-42.md; a git commit on feature/issue-42-e2e"
  _link_above up/repo/../j
  e2e_run_hook hooks/scripts/log-commits.sh "$COMMIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal no "$([ -e "$E2E_DIR/j/auto-log" ] && echo yes || echo no)" "<D>/j has an auto-log directory"
fi

if _want hook-edit-outside-dotdot; then
  _flow_test_begin "PostToolUse log-file-changes.sh: a user journal.dir whose .. never reaches the repository keeps its trail (L54)"
  e2e_new hook-edit-outside-dotdot
  e2e_describe "journal.dir in the user's settings is <D>/x/../j, with <D> the directory above the repository and x a real directory; <D>/j holds issue-42.md; an Edit of note.md on feature/issue-42-e2e"
  _link_above x/../j
  e2e_run_hook hooks/scripts/log-file-changes.sh "$EDIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _j_trail_has "Edit note.md -->"
fi

if _want hook-commit-outside-dotdot; then
  _flow_test_begin "PostToolUse log-commits.sh: a user journal.dir whose .. never reaches the repository keeps its trail (L54)"
  e2e_new hook-commit-outside-dotdot
  e2e_describe "journal.dir in the user's settings is <D>/x/../j, with <D> the directory above the repository and x a real directory; <D>/j holds issue-42.md; a git commit on feature/issue-42-e2e whose last commit is init"
  _link_above x/../j
  e2e_run_hook hooks/scripts/log-commits.sh "$COMMIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _j_trail_has 'commit "init" -->'
fi

if _want hook-edit-unchecked; then
  _flow_test_begin "PostToolUse log-file-changes.sh: when the symlink check cannot run, no trail directory is created (L54)"
  e2e_new hook-edit-unchecked
  e2e_describe ".decisions, a real directory, holds issue-42.md; no journal.dir is set; python3 exits 1; an Edit of note.md on feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _python_dead
  e2e_run_hook hooks/scripts/log-file-changes.sh "$EDIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions/auto-log" ] && echo yes || echo no)" ".decisions/auto-log exists"
fi

if _want hook-commit-unchecked; then
  _flow_test_begin "PostToolUse log-commits.sh: when the symlink check cannot run, no trail directory is created (L54)"
  e2e_new hook-commit-unchecked
  e2e_describe ".decisions, a real directory, holds issue-42.md; no journal.dir is set; python3 exits 1; a git commit on feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _python_dead
  e2e_run_hook hooks/scripts/log-commits.sh "$COMMIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions/auto-log" ] && echo yes || echo no)" ".decisions/auto-log exists"
fi

# _hook_in_other_repo — the repository's .decisions, holding issue-42.md, is
# a symlink to a directory outside it; the hook process runs in project,
# another repository beside it, as a hook runs in the session's project while
# the Bash tool's working directory, which the payload's cwd names, is in
# this one.
_hook_in_other_repo() {
  e2e_repo feature/issue-42-e2e
  _decisions_link_journal
  mkdir -p "$E2E_DIR/project"
  (_e2e_git_env; cd "$E2E_DIR/project" && git init -q) || _flow_assert_fail "$E2E_NAME: could not make project"
  HOOK_CWD=$(_physical "$E2E_REPO")
  E2E_REPO="$E2E_DIR/project"
  printf 'the hook runs in <scratch>/%s/project, another repository\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
}

if _want hook-edit-other-repo-cwd; then
  _flow_test_begin "PostToolUse log-file-changes.sh: run from another repository, the hook checks the payload's repository for symlinks (L53)"
  e2e_new hook-edit-other-repo-cwd
  e2e_describe ".decisions, holding issue-42.md, is a symlink to a directory outside the repository; no journal.dir is set; an Edit of note.md on feature/issue-42-e2e, the payload's cwd the repository, with the hook's working directory in another repository"
  _hook_in_other_repo
  e2e_run_hook hooks/scripts/log-file-changes.sh "{\"cwd\":\"$HOOK_CWD\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"note.md\"}}"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want hook-commit-other-repo-cwd; then
  _flow_test_begin "PostToolUse log-commits.sh: run from another repository, the hook checks the payload's repository for symlinks (L53)"
  e2e_new hook-commit-other-repo-cwd
  e2e_describe ".decisions, holding issue-42.md, is a symlink to a directory outside the repository; no journal.dir is set; a git commit on feature/issue-42-e2e, the payload's cwd the repository, with the hook's working directory in another repository"
  _hook_in_other_repo
  e2e_run_hook hooks/scripts/log-commits.sh "{\"cwd\":\"$HOOK_CWD\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m init\"}}"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

# --- Guard 2 and a repository spelled through a symlink (L55) ----------------

# _journal_commit_link_above <message> <file...> — up, beside the repository,
# is a symlink the scenario makes to the directory above it, and journal.dir
# in the user's settings is <D>/up/repo/.decisions, <D> that directory's
# physical path: the repository's own .decisions, named through a symlink
# above the repository. The last commit, <message>, adds
# .decisions/issue-42.md and each <file>.
_journal_commit_link_above() {
  local d msg="$1"; shift
  e2e_repo feature/issue-42-e2e
  d=$(_physical "$E2E_DIR")
  ln -s "$d" "$E2E_DIR/up" || _flow_assert_fail "$E2E_NAME: could not make up"
  printf 'up -> <scratch>/%s, the directory above the repository\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  _user_settings "{\"journal\":{\"dir\":\"$d/up/repo/.decisions\"}}"
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  local f
  for f in "$@"; do printf 'x\n' > "$E2E_REPO/$f"; done
  (_e2e_git_env; cd "$E2E_REPO" && git add .decisions/issue-42.md "$@" && git commit -q -m "$msg") ||
    _flow_assert_fail "$E2E_NAME: could not commit the journal"
}

# _repo_trail_commits — how many commit breadcrumbs the trail of issue 42 in
# the repository's .decisions holds.
_repo_trail_commits() {
  local f n=0 c
  for f in "$E2E_REPO"/.decisions/auto-log/issue-42.*.md; do
    [ -f "$f" ] || continue
    c=$(grep -c ' commit "' "$f") || c=0
    n=$((n + c))
  done
  printf '%s' "$n"
}

if _want hook-commit-journal-only-link-above; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit of the journal alone gets no breadcrumb when the user's journal.dir names the repository through a symlink above it (L55)"
  e2e_new hook-commit-journal-only-link-above
  e2e_describe "journal.dir in the user's settings is <D>/up/repo/.decisions, with up a symlink to <D>, the directory above the repository; the last commit on feature/issue-42-e2e adds .decisions/issue-42.md and nothing else"
  _journal_commit_link_above "docs: the journal"
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m journal"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 0 "$(_repo_trail_commits)" "commit breadcrumbs in the trail"
fi

if _want hook-commit-journal-and-file-link-above; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit of the journal and another file gets its breadcrumb when the user's journal.dir names the repository through a symlink above it (L55)"
  e2e_new hook-commit-journal-and-file-link-above
  e2e_describe "journal.dir in the user's settings is <D>/up/repo/.decisions, with up a symlink to <D>, the directory above the repository; the last commit on feature/issue-42-e2e adds .decisions/issue-42.md and note.md"
  _journal_commit_link_above "feat: a note" note.md
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m note"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 1 "$(_repo_trail_commits)" "commit breadcrumbs in the trail"
fi

# --- a path resolved one component at a time (L56) ---------------------------

# _walk_link <value> — sub is a symlink the repository commits to
# outside/a/b, and up, beside the repository, a symlink the scenario makes to
# the directory above it. journal.dir in the user's settings is <value>, with
# @R@ the repository's physical path and @UP@ <D>/up/repo, the repository
# named through up.
_walk_link() {
  local d r v
  d=$(_physical "$E2E_DIR")
  r=$(_physical "$E2E_REPO")
  mkdir -p "$E2E_DIR/outside/a/b"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/sub" || _flow_assert_fail "$E2E_NAME: could not plant sub"
  ln -s "$d" "$E2E_DIR/up" || _flow_assert_fail "$E2E_NAME: could not make up"
  printf 'planted: sub -> <scratch>/%s/outside/a/b\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  printf 'up -> <scratch>/%s, the directory above the repository\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  v=${1//@R@/$r}; v=${v//@UP@/$d/up/repo}
  _user_settings "{\"journal\":{\"dir\":\"$v\"}}"
  BEFORE=$(_outside_state)
}

# _walk_case <name> <value> <spelled> — two scenarios for one journal.dir: the
# /flow:start journal block and journal-append.sh --issue 42 (the
# /flow:brainstorm decision block's helper), each refusing sub.
_walk_case() {
  local name="$1" value="$2" spelled="$3"
  if _want "start-journal-walk-$name"; then
    _flow_test_begin "/flow:start journal block: a user journal.dir of $spelled is refused at the repository's sub symlink (L56)"
    e2e_new "start-journal-walk-$name"
    e2e_describe "sub is a symlink the repository commits to outside/a/b; journal.dir in the user's settings is $spelled"
    e2e_repo feature/issue-42-e2e
    _walk_link "$value"
    e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
    _expect_refused 1 "refusing — sub is a symlink"
  fi
  if _want "journal-append-walk-$name"; then
    _flow_test_begin "journal-append.sh --issue: a user journal.dir of $spelled is refused at the repository's sub symlink (L56)"
    e2e_new "journal-append-walk-$name"
    e2e_describe "sub is a symlink the repository commits to outside/a/b; journal.dir in the user's settings is $spelled; journal-append.sh --issue 42"
    e2e_repo feature/issue-42-e2e
    _walk_link "$value"
    _run_bin bin/journal-append.sh --issue 42 --text entry
    _expect_refused 2 "refusing — sub is a symlink"
  fi
}

_walk_case double-slash '@R@//sub/../j' '<repository>//sub/../j'
_walk_case up-double-slash '@UP@//sub/../j' '<D>/up/repo//sub/../j, up a symlink to the directory above the repository'
_walk_case climb-out '@R@/sub/../../j' '<repository>/sub/../../j'
_walk_case climb-out-relative 'sub/../../j' 'sub/../../j'

if _want journal-append-walk-double-slash-parent; then
  _flow_test_begin "journal-append.sh --issue: a .. after a doubled / goes to the parent of the directory before it (L56)"
  e2e_new journal-append-walk-double-slash-parent
  e2e_describe "docs is a real directory in the repository; journal.dir in the user's settings is <repository>/docs//../j, which is <repository>/j; journal-append.sh --issue 42"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/docs"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")/docs//../j\"}}"
  _run_bin bin/journal-append.sh --issue 42 --text entry
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "j/issue-42.md" "entry"
  e2e_expect_equal no "$([ -e "$E2E_REPO/docs/j" ] && echo yes || echo no)" "docs/j exists"
fi

if _want journal-append-walk-link-to-repo-link; then
  _flow_test_begin "journal-append.sh --issue: a link the user made to a symlink the repository commits does not carry a write past it (L56)"
  e2e_new journal-append-walk-link-to-repo-link
  e2e_describe "sub is a symlink the repository commits to outside/a/b, and lnk, beside the repository, a symlink the user made to <repository>/sub; journal.dir in the user's settings is <D>/lnk/x/..; journal-append.sh --issue 42"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside/a/b"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/sub" || _flow_assert_fail "$E2E_NAME: could not plant sub"
  ln -s "$(_physical "$E2E_REPO")/sub" "$E2E_DIR/lnk" || _flow_assert_fail "$E2E_NAME: could not make lnk"
  printf 'planted: sub -> <scratch>/%s/outside/a/b\nlnk -> <scratch>/%s/repo/sub\n' "$E2E_NAME" "$E2E_NAME" >> "$E2E_ARTIFACT"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR")/lnk/x/..\"}}"
  BEFORE=$(_outside_state)
  _run_bin bin/journal-append.sh --issue 42 --text entry
  _expect_refused 2 "refusing — sub is a symlink"
fi

if _want journal-append-walk-missing-parent; then
  _flow_test_begin "journal-append.sh --issue: a missing directory followed by .. is made, as the system needs it (L56)"
  e2e_new journal-append-walk-missing-parent
  e2e_describe "j is a real directory in the repository and j/new is not there yet; journal.dir in the user's settings is <repository>/j/new/.., which the system reaches only once j/new exists; journal-append.sh --issue 42"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/j"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")/j/new/..\"}}"
  _run_bin bin/journal-append.sh --issue 42 --text entry
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "j/issue-42.md" "entry"
fi

# The repository named by another spelling of the same directory: on a file
# system that ignores case, the directory above it spelled in lower case. Where
# case matters there is no other spelling, and the scenario does not run.
_lower_d=$(printf '%s' "$E2E_ROOT" | tr 'A-Z' 'a-z')
if [ "$_lower_d" != "$E2E_ROOT" ] && [ "$_lower_d" -ef "$E2E_ROOT" ] && _want journal-append-walk-case-spelling; then
  _flow_test_begin "journal-append.sh --issue: the repository reached by another spelling of its path is still the repository (L56)"
  e2e_new journal-append-walk-case-spelling
  e2e_describe "the file system ignores case; sub is a symlink the repository commits to outside/a/b, and up2, beside the repository, a symlink to the directory above it spelled in lower case; journal.dir in the user's settings is <D>/up2/repo/sub/../j; journal-append.sh --issue 42"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside/a/b"
  ln -s "$E2E_DIR/outside/a/b" "$E2E_REPO/sub" || _flow_assert_fail "$E2E_NAME: could not plant sub"
  ln -s "$(_physical "$E2E_DIR" | tr 'A-Z' 'a-z')" "$E2E_DIR/up2" || _flow_assert_fail "$E2E_NAME: could not make up2"
  printf 'planted: sub -> <scratch>/%s/outside/a/b\nup2 -> <scratch>/%s in lower case\n' "$E2E_NAME" "$E2E_NAME" >> "$E2E_ARTIFACT"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR")/up2/repo/sub/../j\"}}"
  BEFORE=$(_outside_state)
  _run_bin bin/journal-append.sh --issue 42 --text entry
  _expect_refused 2 "refusing — sub is a symlink"
fi

# _lnk_into_docs — docs is a real directory in the repository, and lnk, beside
# the repository, a symlink the user made to it; journal.dir in the user's
# settings is <D>/lnk/../j: lnk reaches <repository>/docs, and its `..` the
# repository, so the journal is <repository>/j.
_lnk_into_docs() {
  local d
  d=$(_physical "$E2E_DIR")
  mkdir -p "$E2E_REPO/docs"
  ln -s "$(_physical "$E2E_REPO")/docs" "$E2E_DIR/lnk" || _flow_assert_fail "$E2E_NAME: could not make lnk"
  printf 'lnk -> <scratch>/%s/repo/docs\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  _user_settings "{\"journal\":{\"dir\":\"$d/lnk/../j\"}}"
}

if _want journal-append-walk-link-parent; then
  _flow_test_begin "journal-append.sh --issue: a .. after a link outside the repository goes to the link target's parent (L56)"
  e2e_new journal-append-walk-link-parent
  e2e_describe "docs is a real directory in the repository, and lnk, beside it, a symlink the user made to <repository>/docs; journal.dir in the user's settings is <D>/lnk/../j; journal-append.sh --issue 42"
  e2e_repo feature/issue-42-e2e
  _lnk_into_docs
  _run_bin bin/journal-append.sh --issue 42 --text entry
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "j/issue-42.md" "entry"
  e2e_expect_equal no "$([ -e "$E2E_DIR/j" ] && echo yes || echo no)" "<D>/j exists"
fi

if _want journal-record-walk-link-parent; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a .. after a link outside the repository goes to the link target's parent (L56)"
  e2e_new journal-record-walk-link-parent
  e2e_describe "docs is a real directory in the repository, and lnk, beside it, a symlink the user made to <repository>/docs; journal.dir in the user's settings is <D>/lnk/../j"
  e2e_repo feature/issue-42-e2e
  _lnk_into_docs
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "j/issue-42.md" "type: stranger-test"
  _expect_err_lacks "Traceback"
fi

# --- the auto-log hooks' symlinked trail directory (L57) ---------------------

# _user_outside_trail_link — journal.dir in the user's settings is <D>/j,
# outside the repository, which holds issue-42.md; <D>/j/auto-log is a
# symlink to <D>/elsewhere, an empty directory.
_user_outside_trail_link() {
  local d
  e2e_repo feature/issue-42-e2e
  d=$(_physical "$E2E_DIR")
  mkdir -p "$E2E_DIR/j" "$E2E_DIR/elsewhere"
  printf '# Journal\n' > "$E2E_DIR/j/issue-42.md"
  ln -s "$E2E_DIR/elsewhere" "$E2E_DIR/j/auto-log" || _flow_assert_fail "$E2E_NAME: could not make the auto-log link"
  printf 'j/auto-log -> <scratch>/%s/elsewhere\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  _user_settings "{\"journal\":{\"dir\":\"$d/j\"}}"
}

# _elsewhere_empty — <D>/elsewhere holds nothing.
_elsewhere_empty() {
  e2e_expect_equal "" "$(cd "$E2E_DIR/elsewhere" && find . -mindepth 1)" "what <D>/elsewhere holds"
}

if _want hook-edit-user-outside-trail-link; then
  _flow_test_begin "PostToolUse log-file-changes.sh: a symlinked auto-log under the user's own journal.dir outside the repository gets nothing written through it (L57)"
  e2e_new hook-edit-user-outside-trail-link
  e2e_describe "journal.dir in the user's settings is <D>/j, outside the repository, holding issue-42.md; <D>/j/auto-log is a symlink to <D>/elsewhere; an Edit of note.md on feature/issue-42-e2e"
  _user_outside_trail_link
  e2e_run_hook hooks/scripts/log-file-changes.sh "$EDIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _elsewhere_empty
fi

if _want hook-commit-user-outside-trail-link; then
  _flow_test_begin "PostToolUse log-commits.sh: a symlinked auto-log under the user's own journal.dir outside the repository gets nothing written through it (L57)"
  e2e_new hook-commit-user-outside-trail-link
  e2e_describe "journal.dir in the user's settings is <D>/j, outside the repository, holding issue-42.md; <D>/j/auto-log is a symlink to <D>/elsewhere; a git commit on feature/issue-42-e2e"
  _user_outside_trail_link
  e2e_run_hook hooks/scripts/log-commits.sh "$COMMIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _elsewhere_empty
fi

# _user_repo_trail_link — .decisions, a real directory, holds issue-42.md, and
# the repository commits .decisions/auto-log as a symlink to an empty
# directory outside it; journal.dir in the user's settings is
# <repository>/.decisions, which journal-dir.sh --user-owned prints.
_user_repo_trail_link() {
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions/auto-log
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")/.decisions\"}}"
}

if _want hook-edit-user-repo-trail-link; then
  _flow_test_begin "PostToolUse log-file-changes.sh: the user's own journal.dir in the repository gets nothing written through a committed auto-log symlink (L57)"
  e2e_new hook-edit-user-repo-trail-link
  e2e_describe ".decisions holds issue-42.md and .decisions/auto-log is a symlink the repository commits to a directory outside it; journal.dir in the user's settings is <repository>/.decisions; an Edit of note.md on feature/issue-42-e2e"
  _user_repo_trail_link
  e2e_run_hook hooks/scripts/log-file-changes.sh "$EDIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want hook-commit-user-repo-trail-link; then
  _flow_test_begin "PostToolUse log-commits.sh: the user's own journal.dir in the repository gets nothing written through a committed auto-log symlink (L57)"
  e2e_new hook-commit-user-repo-trail-link
  e2e_describe ".decisions holds issue-42.md and .decisions/auto-log is a symlink the repository commits to a directory outside it; journal.dir in the user's settings is <repository>/.decisions; a git commit on feature/issue-42-e2e"
  _user_repo_trail_link
  e2e_run_hook hooks/scripts/log-commits.sh "$COMMIT_PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

# --- Guard 2: the repository top and a quoted name (L58) ---------------------

# _journal_commit <journal dir> <message> <file...> — journal.dir in the
# repository's settings is <journal dir>, relative; the last commit, <message>,
# adds <journal dir>/issue-42.md and each <file>.
_journal_commit() {
  local jd="$1" msg="$2" f j
  shift 2
  e2e_repo feature/issue-42-e2e
  _settings "{\"journal\":{\"dir\":\"$jd\"}}"
  mkdir -p "$E2E_REPO/$jd"
  printf '# Journal\n' > "$E2E_REPO/$jd/issue-42.md"
  j="$jd/issue-42.md"
  [ "$jd" = . ] && j=issue-42.md
  for f in "$@"; do printf 'x\n' > "$E2E_REPO/$f"; done
  (_e2e_git_env; cd "$E2E_REPO" && git add "$j" "$@" && git commit -q -m "$msg") ||
    _flow_assert_fail "$E2E_NAME: could not commit the journal"
}

# _trail_commits <journal dir> — how many commit breadcrumbs the trail of
# issue 42 under <journal dir> holds.
_trail_commits() {
  local f n=0 c
  for f in "$E2E_REPO/$1"/auto-log/issue-42.*.md; do
    [ -f "$f" ] || continue
    c=$(grep -c ' commit "' "$f") || c=0
    n=$((n + c))
  done
  printf '%s' "$n"
}

if _want hook-commit-journal-only-top; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit of the journal alone gets no breadcrumb when journal.dir is the repository top (L58)"
  e2e_new hook-commit-journal-only-top
  e2e_describe "journal.dir in .claude/settings.flow.json is .; the last commit on feature/issue-42-e2e adds issue-42.md and nothing else"
  _journal_commit . "docs: the journal"
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m journal"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 0 "$(_trail_commits .)" "commit breadcrumbs in the trail"
fi

if _want hook-commit-journal-and-file-top; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit of the journal and another file gets its breadcrumb when journal.dir is the repository top (L58)"
  e2e_new hook-commit-journal-and-file-top
  e2e_describe "journal.dir in .claude/settings.flow.json is .; the last commit on feature/issue-42-e2e adds issue-42.md and note.md"
  _journal_commit . "feat: a note" note.md
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m note"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 1 "$(_trail_commits .)" "commit breadcrumbs in the trail"
fi

if _want hook-commit-journal-only-non-ascii; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit of the journal alone gets no breadcrumb when the journal's name is not ASCII (L58)"
  e2e_new hook-commit-journal-only-non-ascii
  e2e_describe "journal.dir in .claude/settings.flow.json is décisions; the last commit on feature/issue-42-e2e adds décisions/issue-42.md and nothing else"
  _journal_commit décisions "docs: the journal"
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m journal"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 0 "$(_trail_commits décisions)" "commit breadcrumbs in the trail"
fi

# --- the evidence bundle's raw output (L59) ----------------------------------

if _want bundle-output-ref-link; then
  _flow_test_begin "evidence bundle (evaluator loop): an output_ref through a symlink in the evidence directory is not read into the judge's prompt (L59)"
  e2e_new bundle-output-ref-link
  e2e_describe "a goal, and a run with one evidence sidecar whose output_ref is out/secret.txt; evidence/out is a symlink the repository commits to a directory outside it holding secret.txt"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  sed -i.bak "s#output_ref: .*#output_ref: 'out/secret.txt'#" "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  mv "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml.bak" "$E2E_DIR/sidecar.bak"
  mkdir -p "$E2E_DIR/outside"
  printf 'SECRET-MARK\n' > "$E2E_DIR/outside/secret.txt"
  _plant ".flow/runs/$RID/evidence/out"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "evidence-ac1-test"
  e2e_expect_no_out "SECRET-MARK"
  e2e_expect_out "(refused: output_ref: .flow/runs/$RID/evidence/out is a symlink)"
  _expect_untouched
fi

if _want bundle-output-ref-real; then
  _flow_test_begin "evidence bundle (evaluator loop): an output_ref in a real directory under the evidence directory is read into the judge's prompt (L59)"
  e2e_new bundle-output-ref-real
  e2e_describe "a goal, and a run with one evidence sidecar whose output_ref is out/raw.txt; evidence/out is a real directory holding raw.txt"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  sed -i.bak "s#output_ref: .*#output_ref: 'out/raw.txt'#" "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  mv "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml.bak" "$E2E_DIR/sidecar.bak"
  mkdir -p "$E2E_REPO/.flow/runs/$RID/evidence/out"
  printf 'RAW-OUTPUT-MARK\n' > "$E2E_REPO/.flow/runs/$RID/evidence/out/raw.txt"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "RAW-OUTPUT-MARK"
fi

# --- the evidence directory, a refused name, /flow:status's run files (L59) --

if _want bundle-evidence-link; then
  _flow_test_begin "evidence bundle (evaluator loop): sidecars under a symlinked evidence directory are not read into the judge's prompt (L59)"
  e2e_new bundle-evidence-link
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; the run's evidence directory is then moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  _plant ".flow/runs/$RID/evidence"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_no_out "evidence-ac1-test"
  e2e_expect_out "(evidence directory not read; evidence ledger unavailable)"
  e2e_expect_no_out "(no evidence sidecars in this run)"
  e2e_expect_out "PREVIOUS-VERDICT-MARK"
  e2e_expect_err "refusing — .flow/runs/$RID/evidence is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want bundle-output-ref-not-dir; then
  _flow_test_begin "evidence bundle (evaluator loop): an output_ref under a regular file is refused as not a directory (L59)"
  e2e_new bundle-output-ref-not-dir
  e2e_describe "a goal, and a run with one evidence sidecar whose output_ref is x.txt/y; evidence/x.txt is a regular file"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  sed -i.bak "s#output_ref: .*#output_ref: 'x.txt/y'#" "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  mv "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml.bak" "$E2E_DIR/sidecar.bak"
  printf 'x\n' > "$E2E_REPO/.flow/runs/$RID/evidence/x.txt"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "(refused: output_ref: .flow/runs/$RID/evidence/x.txt is not a directory)"
fi

if _want status-runs-verdict-link; then
  _flow_test_begin "/flow:status recent runs: a run's verdict and events are not read through symlinked files (L59)"
  e2e_new status-runs-verdict-link
  e2e_describe "an active run with one event; its last-verdict.json is a symlink to a file outside the repository whose verdict is achieved, and its events.jsonl a symlink to a file outside it with two lines"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  mkdir -p "$E2E_DIR/outside"
  printf '%s\n' '{"verdict":"achieved"}' > "$E2E_DIR/outside/verdict.json"
  printf 'one\ntwo\n' > "$E2E_DIR/outside/events.jsonl"
  mv "$E2E_REPO/.flow/runs/$RID/events.jsonl" "$E2E_DIR/events.orig"
  ln -s "$E2E_DIR/outside/verdict.json" "$E2E_REPO/.flow/runs/$RID/last-verdict.json" &&
    ln -s "$E2E_DIR/outside/events.jsonl" "$E2E_REPO/.flow/runs/$RID/events.jsonl" ||
    _flow_assert_fail "$E2E_NAME: could not plant the run files"
  printf 'planted: .flow/runs/%s/last-verdict.json and events.jsonl -> files in <scratch>/%s/outside\n' "$RID" "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "$(printf 'STATE=ok\nRUN=id=%s verdict=not-read activities=not-read' "$RID")" "$(_section 'Recent Runs')" "the Recent Runs section"
  e2e_expect_err "refusing — .flow/runs/$RID/last-verdict.json is a symlink; $RUNS_NOTE"
  e2e_expect_err "refusing — .flow/runs/$RID/events.jsonl is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

# --- the walk's limits (L60) -------------------------------------------------

# _watchdog <seconds> <command...> — run the command in its own process group
# and kill the group when it runs longer: a walk with no end would otherwise
# hang the suite. Exits 124 when it killed it.
WATCHDOG_PY='
import os, signal, subprocess, sys
limit = int(sys.argv[1])
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(p.wait(timeout=limit))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    p.wait()
    print("watchdog: killed after %ds" % limit, file=sys.stderr)
    sys.exit(124)
'

# _run_bin_watchdog <seconds> <file under the plugin> [arguments] — _run_bin
# under the watchdog.
_run_bin_watchdog() {
  local limit="$1" rel="$2"; shift 2
  {
    printf 'code: %s\n' "$rel"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$rel")"
    printf 'arguments: %s\n' "$*"
    printf 'watchdog: %ss\n' "$limit"
  } >> "$E2E_ARTIFACT"
  _e2e_exec python3 -c "$WATCHDOG_PY" "$limit" "$E2E_ACTIVE_PLUGIN/$rel" "$@"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

# _dir_listing <dir> — every entry under <dir>, by name.
_dir_listing() { (cd "$1" 2>/dev/null && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' '); }

if _want journal-append-walk-link-loop; then
  _flow_test_begin "journal-append.sh --issue: a user journal.dir through a link loop outside the repository fails, and does not hang (L60)"
  e2e_new journal-append-walk-link-loop
  e2e_describe "loopa and loopb, beside the repository, are symlinks to each other; journal.dir in the user's settings is ../loopa/j; journal-append.sh --issue 42, killed after 30 seconds"
  e2e_repo feature/issue-42-e2e
  ln -s loopb "$E2E_DIR/loopa" && ln -s loopa "$E2E_DIR/loopb" || _flow_assert_fail "$E2E_NAME: could not make the loop"
  printf 'loopa -> loopb, loopb -> loopa\n' >> "$E2E_ARTIFACT"
  _user_settings '{"journal":{"dir":"../loopa/j"}}'
  _run_bin_watchdog 30 bin/journal-append.sh --issue 42 --text entry
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "too many levels of symbolic links"
  e2e_expect_equal "" "$(cd "$E2E_DIR" && find . -name j)" "directories named j"
fi

if _want journal-append-walk-link-chain; then
  _flow_test_begin "journal-append.sh --issue: a user journal.dir through a chain of 41 links outside the repository fails and creates nothing at its end (L60)"
  e2e_new journal-append-walk-link-chain
  e2e_describe "c0 to c40, beside the repository, are 41 symlinks, each to the next and c40 to real, an empty directory; journal.dir in the user's settings is ../c0/j; journal-append.sh --issue 42, killed after 30 seconds"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/real"
  _i=0
  while [ "$_i" -lt 40 ]; do
    ln -s "c$((_i + 1))" "$E2E_DIR/c$_i" || _flow_assert_fail "$E2E_NAME: could not make c$_i"
    _i=$((_i + 1))
  done
  ln -s real "$E2E_DIR/c40" || _flow_assert_fail "$E2E_NAME: could not make c40"
  printf 'c0 -> c1 -> ... -> c40 -> real\n' >> "$E2E_ARTIFACT"
  _user_settings '{"journal":{"dir":"../c0/j"}}'
  _run_bin_watchdog 30 bin/journal-append.sh --issue 42 --text entry
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "too many levels of symbolic links"
  e2e_expect_equal "" "$(_dir_listing "$E2E_DIR/real")" "what real holds"
fi

if _want start-journal-walk-under-file; then
  _flow_test_begin "/flow:start journal block: a user journal.dir under a regular file outside the repository fails (L60)"
  e2e_new start-journal-walk-under-file
  e2e_describe "afile, beside the repository, is a regular file; journal.dir in the user's settings is ../afile/j"
  e2e_repo feature/issue-42-e2e
  printf 'x\n' > "$E2E_DIR/afile"
  _user_settings '{"journal":{"dir":"../afile/j"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "is not a directory"
  e2e_expect_equal yes "$([ -f "$E2E_DIR/afile" ] && echo yes || echo no)" "afile is still a regular file"
fi

# --- Guard 2 and a name ending in a newline (L61) ----------------------------

if _want hook-commit-journal-newline-name; then
  _flow_test_begin "PostToolUse log-commits.sh: a commit of a file whose name is the journal's followed by a newline gets its breadcrumb (L61)"
  e2e_new hook-commit-journal-newline-name
  e2e_describe ".decisions/issue-42.md is committed; the last commit on feature/issue-42-e2e adds only a file named .decisions/issue-42.md followed by a newline"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _nl_name=$(printf '.decisions/issue-42.md\nx'); _nl_name=${_nl_name%x}
  (_e2e_git_env; cd "$E2E_REPO" && git add .decisions/issue-42.md && git commit -q -m "docs: the journal" &&
    printf 'x\n' > "$_nl_name" && git add -- "$_nl_name" && git commit -q -m "feat: a file") ||
    _flow_assert_fail "$E2E_NAME: could not commit"
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m file"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 1 "$(_trail_commits .decisions)" "commit breadcrumbs in the trail"
fi

# --- the walk on Windows, run with ntpath (L62) -------------------------------
# The walk's platform steps are pure functions of a path module; here they run
# with ntpath, as they would on Windows: cleaning the spelled path by its text
# (`.` and `..`), refusing a name that ends in a period or a space, which Win32
# may open under another name, and leaving a path with the \\?\ prefix as
# written; refusing every other device spelling (//?/, \\.\, \??\) before
# the slashes are made backslashes, as _walk does; and joining a link target
# to the link's directory, cleaned the same way. What does not run here: lstat, readlink and mkdir as Windows does them,
# so neither the walk over real Windows directories nor the form readlink
# returns a target in (such as one with the \\?\ prefix); the windows-hooks CI
# job is where those run.

WIN_WALK_PY='
import ntpath, sys
sys.path.insert(0, sys.argv[1])
from _repo_dir import JournalAtomicError, _begin, _link_names

def begin(raw, cwd, pathmod):
    # The first step of _walk itself: the spelling checked and made the
    # platform one, then where the walk starts. The top is not reached here.
    return _begin(raw, cwd, "/no-top", pathmod)

def show(label, step, *args):
    try:
        root, names = step(*args, ntpath)
    except JournalAtomicError as e:
        print(label, "REFUSED:", e.reason)
        return
    print(label, root, "/".join(names))

show("START", begin, r"C:\D\ulink\..\repo\sub\j", r"C:\cwd")
show("RELATIVE", begin, r"..\x\.\y", r"C:\cwd\in")
show("ROOTED", _link_names, r"C:\D\links\lnk", r"\a\b", ["j"])
show("TARGET", _link_names, r"C:\D\links\lnk", r"..\c", ["j"])
show("DRIVE", _link_names, r"C:\D\links\lnk", r"E:\e", ["j"])
show("PARENT", begin, r"C:\D\repo\sub.\..\j", r"C:\cwd")
show("MIDDLE-SPACE", begin, "C:\\D\\repo\\sub \\j", r"C:\cwd")
show("MIDDLE-DOT", begin, r"C:\D\repo\sub.\j", r"C:\cwd")
show("END-DOT", begin, r"C:\D\repo\j.", r"C:\cwd")
show("DOTS", begin, r"C:\D\repo\...\j", r"C:\cwd")
show("VERBATIM", begin, r"\\?\C:\D\repo\sub.\..\j", r"C:\cwd")
show("LINK-DOT", _link_names, r"C:\D\links\lnk", r"..\repo\sub.", ["j"])
show("LINK-VERBATIM", _link_names, r"C:\D\links\lnk", r"\\?\C:\D\repo\sub.", ["j"])
show("DEVICE-SLASH", begin, "//?/C:/D/ulink/../repo/sub/j", r"C:\cwd")
show("DEVICE-DOT", begin, r"\\.\C:\D\repo\j", r"C:\cwd")
show("DEVICE-DOT-PARENT", begin, r"\\.\C:\..\D\repo\j", r"C:\cwd")
show("DEVICE-NT", begin, r"\??\C:\D\repo\j", r"C:\cwd")
show("UNC", begin, r"\\server\share\repo\j", r"C:\cwd")
show("LINK-DEVICE", _link_names, r"C:\D\links\lnk", r"\\.\C:\x", ["j"])
show("UNC-SLASH", begin, "//server/share/j", r"C:\cwd")
show("UNC-SLASH-IP", begin, "//192.168.1.5/share/j", r"C:\cwd")
'

if _want walk-windows-paths; then
  _flow_test_begin "_repo_dir.py with ntpath: a path is cleaned by its text before the walk, a name ending in a period or a space is refused except under \\\\?\\, and a link target rooted without a drive takes the link's drive (L62)"
  e2e_new walk-windows-paths
  e2e_describe "the walk's start and link steps run with ntpath on this system, not on Windows (lstat, readlink and mkdir do not run as Windows does them): C:\\D\\ulink\\..\\repo\\sub\\j from C:\\cwd; ..\\x\\.\\y from C:\\cwd\\in; the link C:\\D\\links\\lnk with the targets \\a\\b, ..\\c and E:\\e; C:\\D\\repo\\sub.\\..\\j; sub followed by a space in the middle, as a committed link named so beside a real sub would be; sub. in the middle; j. at the end; ... as a name; \\\\?\\C:\\D\\repo\\sub.\\..\\j, walked as written; the targets ..\\repo\\sub. and \\\\?\\C:\\D\\repo\\sub.; through _walk's own first step, //?/C:/D/ulink/../repo/sub/j, \\\\.\\C:\\D\\repo\\j, \\\\.\\C:\\..\\D\\repo\\j and \\??\\C:\\D\\repo\\j, refused as device paths, and \\\\server\\share\\repo\\j, //server/share/j and //192.168.1.5/share/j, walked as UNC paths; the target \\\\.\\C:\\x"
  e2e_repo feature/issue-42-e2e
  {
    printf 'code: bin/_repo_dir.py\n'
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/bin/_repo_dir.py")"
  } >> "$E2E_ARTIFACT"
  _e2e_exec python3 -c "$WIN_WALK_PY" "$E2E_ACTIVE_PLUGIN/bin"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line 'START C:\ D/repo/sub/j'
  e2e_expect_line 'RELATIVE C:\ cwd/x/y'
  e2e_expect_line 'ROOTED C:\ a/b/j'
  e2e_expect_line 'TARGET C:\ D/c/j'
  e2e_expect_line 'DRIVE E:\ e/j'
  e2e_expect_line 'PARENT C:\ D/repo/j'
  e2e_expect_line "MIDDLE-SPACE REFUSED: 'sub ' ends in a period or a space, and Windows may open a different name"
  e2e_expect_line "MIDDLE-DOT REFUSED: 'sub.' ends in a period or a space, and Windows may open a different name"
  e2e_expect_line "END-DOT REFUSED: 'j.' ends in a period or a space, and Windows may open a different name"
  e2e_expect_line "DOTS REFUSED: '...' ends in a period or a space, and Windows may open a different name"
  e2e_expect_line 'VERBATIM \\?\C:\ D/repo/sub./../j'
  e2e_expect_line "LINK-DOT REFUSED: 'sub.' ends in a period or a space, and Windows may open a different name"
  e2e_expect_line 'LINK-VERBATIM \\?\C:\ D/repo/sub./j'
  e2e_expect_line "DEVICE-SLASH REFUSED: '//?/C:/D/ulink/../repo/sub/j' is a Windows device path; use a drive path, or \\\\?\\ to name a path as written"
  e2e_expect_line "DEVICE-DOT REFUSED: '\\\\.\\C:\\D\\repo\\j' is a Windows device path; use a drive path, or \\\\?\\ to name a path as written"
  e2e_expect_line "DEVICE-DOT-PARENT REFUSED: '\\\\.\\C:\\..\\D\\repo\\j' is a Windows device path; use a drive path, or \\\\?\\ to name a path as written"
  e2e_expect_line "DEVICE-NT REFUSED: '\\??\\C:\\D\\repo\\j' is a Windows device path; use a drive path, or \\\\?\\ to name a path as written"
  e2e_expect_line 'UNC \\server\share\ repo/j'
  e2e_expect_line "LINK-DEVICE REFUSED: '\\\\.\\C:\\x' is a Windows device path; use a drive path, or \\\\?\\ to name a path as written"
  e2e_expect_line 'UNC-SLASH \\server\share\ j'
  e2e_expect_line 'UNC-SLASH-IP \\192.168.1.5\share\ j'
fi

# --- output_ref as the evidence skill writes it (L63) ------------------------

if _want bundle-output-ref-as-recorded; then
  _flow_test_begin "evidence bundle (evaluator loop): the raw output flow-record-evidence.sh copies is read through the fixture's output_ref (L63)"
  e2e_new bundle-output-ref-as-recorded
  e2e_describe "a goal, and the fixture sidecar recorded by flow-record-evidence.sh with --raw-output, as the evidence skill runs it; its output_ref names the copy"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_yaml
  _evidence_file
  printf 'RECORDED-RAW-MARK\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 0 "$E2E_RC" "flow-record-evidence.sh exit status"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "RECORDED-RAW-MARK"
fi

# --- output_ref written by the recorder, not the author (L64) ----------------

# _sidecar_without_ref — the fixture sidecar with no output_ref, in the
# repository as evidence.yaml.
_sidecar_without_ref() {
  grep -v 'output_ref:' "$FIXTURES/evidence/valid.yaml" > "$E2E_REPO/evidence.yaml"
}

if _want record-evidence-writes-output-ref; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: the sidecar gets the output_ref of the copy it writes, and the bundle reads it (L64)"
  e2e_new record-evidence-writes-output-ref
  e2e_describe "a goal, and the fixture sidecar (id evidence-ac1-test) with no output_ref, recorded by flow-record-evidence.sh with --raw-output raw.txt; then the judge's bundle"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_yaml
  _sidecar_without_ref
  printf 'WRITTEN-REF-MARK\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 0 "$E2E_RC" "flow-record-evidence.sh exit status"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" "output_ref: evidence-ac1-test.txt"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "WRITTEN-REF-MARK"
fi

if _want record-evidence-output-ref-mismatch; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a sidecar whose output_ref names another file is refused (L64)"
  e2e_new record-evidence-output-ref-mismatch
  e2e_describe "the fixture sidecar (id evidence-ac1-test) with output_ref AC1-test.txt, recorded by flow-record-evidence.sh with --raw-output raw.txt, which copies to evidence-ac1-test.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  awk '{ print } /^  exit_code: / { print "  output_ref: '"'"'AC1-test.txt'"'"'" }' "$FIXTURES/evidence/valid.yaml" |
    grep -v "output_ref: 'evidence-ac1-test.txt'" > "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "output_ref is AC1-test.txt, but --raw-output is copied to evidence-ac1-test.txt"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" ] && echo yes || echo no)" "the sidecar was written"
fi

# --- a "; " inside a refused name (L64) --------------------------------------

if _want bundle-output-ref-semicolon-link; then
  _flow_test_begin "evidence bundle (evaluator loop): a refused name holding '; ' is named whole (L64)"
  e2e_new bundle-output-ref-semicolon-link
  e2e_describe "a goal, and a run with one evidence sidecar whose output_ref is 'x; y/secret.txt'; evidence/x; y is a symlink the repository commits to a directory outside it holding secret.txt"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  sed -i.bak "s#output_ref: .*#output_ref: 'x; y/secret.txt'#" "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  mv "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml.bak" "$E2E_DIR/sidecar.bak"
  mkdir -p "$E2E_DIR/outside"
  printf 'SECRET-MARK\n' > "$E2E_DIR/outside/secret.txt"
  _plant ".flow/runs/$RID/evidence/x; y"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_no_out "SECRET-MARK"
  e2e_expect_out "(refused: output_ref: .flow/runs/$RID/evidence/x; y is a symlink)"
fi

if _want resume-read-semicolon-link; then
  _flow_test_begin "/flow:resume run read: a refused run directory whose name holds '; ' is named whole (L64)"
  e2e_new resume-read-semicolon-link
  e2e_describe "a run directory named 'x; y' is a symlink to a directory outside the repository; the block runs with that run id"
  e2e_repo feature/issue-42-e2e
  _plant ".flow/runs/x; y"
  _run_with_env "RUN_ID=x; y" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow/runs/x; y is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

# --- the evidence directory check that cannot run (L64) ----------------------

if [ "$(id -u)" != 0 ] && _want bundle-run-dir-unreadable; then
  _flow_test_begin "evidence bundle (evaluator loop): an evidence directory that cannot be inspected leaves the ledger unavailable, without a traceback (L64)"
  e2e_new bundle-run-dir-unreadable
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; the run directory's mode is 000, so nothing in it can be inspected"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  chmod 000 "$E2E_REPO/.flow/runs/$RID"
  _run_bundle
  chmod 755 "$E2E_REPO/.flow/runs/$RID"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "(evidence directory not read; evidence ledger unavailable)"
  e2e_expect_err "cannot inspect"
  _expect_err_lacks "Traceback"
fi

# --- /flow:learn and a run's verdict file (L64) ------------------------------

if _want learn-runs-verdict-files; then
  _flow_test_begin "/flow:learn: a run's last-verdict.json is listed, and not through a symlink (L64)"
  e2e_new learn-runs-verdict-files
  e2e_describe "the run r-real holds last-verdict.json; the run r-link holds a last-verdict.json that is a symlink to a file outside the repository; both hold events.jsonl"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.flow/runs/r-real" "$E2E_REPO/.flow/runs/r-link" "$E2E_DIR/outside"
  for r in r-real r-link; do printf '%s\n' '{"type":"phase"}' > "$E2E_REPO/.flow/runs/$r/events.jsonl"; done
  printf '%s\n' '{"verdict":"not_achieved"}' > "$E2E_REPO/.flow/runs/r-real/last-verdict.json"
  printf '%s\n' '{"verdict":"achieved"}' > "$E2E_DIR/outside/verdict.json"
  ln -s "$E2E_DIR/outside/verdict.json" "$E2E_REPO/.flow/runs/r-link/last-verdict.json" ||
    _flow_assert_fail "$E2E_NAME: could not plant the verdict link"
  printf 'planted: .flow/runs/r-link/last-verdict.json -> <scratch>/%s/outside/verdict.json\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_VERDICT=.flow/runs/r-real/last-verdict.json"
  e2e_expect_no_line "RUN_VERDICT=.flow/runs/r-link/last-verdict.json"
fi

# --- the recorder writes nothing it cannot finish (L65) ----------------------

if _want record-evidence-raw-link; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a raw output that is a symlink leaves no sidecar and no copy (L65)"
  e2e_new record-evidence-raw-link
  e2e_describe "the fixture sidecar with no output_ref, recorded by flow-record-evidence.sh with --raw-output raw.txt, where raw.txt is a symlink to a file outside the repository"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  mkdir -p "$E2E_DIR/outside"
  printf 'LINKED-RAW\n' > "$E2E_DIR/outside/raw.txt"
  ln -s "$E2E_DIR/outside/raw.txt" "$E2E_REPO/raw.txt" || _flow_assert_fail "$E2E_NAME: could not plant raw.txt"
  printf 'planted: raw.txt -> <scratch>/%s/outside/raw.txt\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "raw-output source raw.txt is a symlink"
  e2e_expect_equal "" "$(cd "$E2E_REPO/.flow/runs/$RID/evidence" 2>/dev/null && find . -mindepth 1)" "what the evidence directory holds"
fi

if _want record-evidence-twice; then
  _flow_test_begin "flow-record-evidence.sh: a second record of an id leaves the first sidecar and copy as they were (L65)"
  e2e_new record-evidence-twice
  e2e_describe "the fixture sidecar with no output_ref and exit_code 1 is recorded with --raw-output holding FAIL-OUTPUT; then the same id with exit_code 0 and --raw-output holding PASS-OUTPUT"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  sed -i.bak 's/^  exit_code: 0$/  exit_code: 1/' "$E2E_REPO/evidence.yaml"
  mv "$E2E_REPO/evidence.yaml.bak" "$E2E_DIR/evidence.bak"
  printf 'FAIL-OUTPUT\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 0 "$E2E_RC" "the first record's exit status"
  _sidecar_without_ref
  printf 'PASS-OUTPUT\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the second record's exit status"
  e2e_expect_err "evidence-ac1-test is already recorded"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" "exit_code: 1"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.txt" "FAIL-OUTPUT"
fi

# _hide_jsonschema — a jsonschema package on PYTHONPATH that raises
# ImportError, so a helper takes its path for a system without jsonschema.
_hide_jsonschema() {
  mkdir -p "$E2E_DIR/nojs/jsonschema"
  printf 'raise ImportError("jsonschema is hidden for this scenario")\n' > "$E2E_DIR/nojs/jsonschema/__init__.py"
  printf 'jsonschema: hidden\n' >> "$E2E_ARTIFACT"
}

if _want record-evidence-uppercase-id; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: output_ref is the copy's name, the id lower-cased (L65)"
  e2e_new record-evidence-uppercase-id
  e2e_describe "jsonschema is hidden; a goal, and the fixture sidecar with id evidence-AC1-test and no output_ref, recorded with --raw-output raw.txt; then the judge's bundle"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_yaml
  _sidecar_without_ref
  sed -i.bak 's/^  id: evidence-ac1-test$/  id: evidence-AC1-test/' "$E2E_REPO/evidence.yaml"
  mv "$E2E_REPO/evidence.yaml.bak" "$E2E_DIR/evidence.bak"
  printf 'UPPER-ID-MARK\n' > "$E2E_REPO/raw.txt"
  _hide_jsonschema
  _saved_pythonpath="${PYTHONPATH:-}"
  export PYTHONPATH="$E2E_DIR/nojs${_saved_pythonpath:+:$_saved_pythonpath}"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  export PYTHONPATH="$_saved_pythonpath"
  e2e_expect_equal 0 "$E2E_RC" "flow-record-evidence.sh exit status"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" "output_ref: evidence-ac1-test.txt"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "UPPER-ID-MARK"
fi

# --- "; " in a name, at every reader (L65) ------------------------------------

# _run_bundle_id <run id> — _run_bundle for another run id.
_run_bundle_id() {
  local code="bin/_flow_evidence_bundle.py"
  {
    printf 'code: %s\n' "$code"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$code")"
    printf 'arguments: .flow/goals/g-link.goal.yaml {} .flow/runs/%s\n' "$1"
  } >> "$E2E_ARTIFACT"
  _e2e_exec env PYTHONSAFEPATH=1 python3 "$E2E_ACTIVE_PLUGIN/$code" \
    .flow/goals/g-link.goal.yaml '{}' ".flow/runs/$1"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

if _want bundle-run-dir-semicolon-link; then
  _flow_test_begin "evidence bundle (evaluator loop): a refused run directory whose name holds '; ' is named whole (L65)"
  e2e_new bundle-run-dir-semicolon-link
  e2e_describe "a goal, and a run directory named 'x; y' that is a symlink to a directory outside the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  mkdir -p "$E2E_REPO/.flow/runs"
  _plant ".flow/runs/x; y"
  _run_bundle_id "x; y"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow/runs/x; y is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want bundle-evidence-semicolon-link; then
  _flow_test_begin "evidence bundle (evaluator loop): a refused evidence directory under a run named 'x; y' is named whole (L65)"
  e2e_new bundle-evidence-semicolon-link
  e2e_describe "a goal, and a run directory named 'x; y' whose evidence directory is a symlink to a directory outside the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  mkdir -p "$E2E_REPO/.flow/runs/x; y"
  _plant ".flow/runs/x; y/evidence"
  _run_bundle_id "x; y"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow/runs/x; y/evidence is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-semicolon-link; then
  _flow_test_begin "/flow:resume scan: a run directory whose name holds '; ' is named whole (L65)"
  e2e_new resume-scan-semicolon-link
  e2e_describe "an active run in a directory named 'x; y', which is then moved outside the repository and replaced by a symlink to it; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.flow/runs/x; y"
  cp "$FIXTURES/run/valid.yaml" "$E2E_REPO/.flow/runs/x; y/run.yaml"
  _plant ".flow/runs/x; y"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=none"
  e2e_expect_err "refusing — .flow/runs/x; y is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want journal-dir-semicolon-link; then
  _flow_test_begin "journal-dir.sh (/flow:brainstorm decision block): a refused repository journal.dir whose name holds '; ' is named whole (L65)"
  e2e_new journal-dir-semicolon-link
  e2e_describe "journal.dir in .claude/settings.flow.json is 'a; b', a symlink the repository commits to a directory outside it; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"a; b"}}'
  _plant "a; b"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing journal.dir 'a; b' from .claude/settings.flow.json: a; b is a symlink; using .decisions"
  _expect_untouched
fi

# --- a refusal read from a pipe that ends lines in \r\n (L65) ----------------

# _python_crlf — python3 in the scenario's bin is the real one with its stderr
# lines ending in \r\n, as Python writes them to a pipe on Windows.
_python_crlf() {
  local real cr
  real=$(command -v python3)
  cr=$(printf '\r')
  cat > "$E2E_BIN/python3" <<SHIM
#!/bin/bash
{ "$real" "\$@" 2>&1 1>&3 3>&- | sed 's/\$/$cr/' >&2; exit "\${PIPESTATUS[0]}"; } 3>&1
SHIM
  chmod +x "$E2E_BIN/python3"
  printf 'python3: the real one, its stderr lines ending in CR LF\n' >> "$E2E_ARTIFACT"
}

if _want status-runs-flow-link-crlf; then
  _flow_test_begin "/flow:status recent runs: a refusal whose line ends in \\r is still named without its ending (L65)"
  e2e_new status-runs-flow-link-crlf
  e2e_describe "an active run with one event is created, then .flow is moved outside the repository and replaced by a symlink to it; python3 ends its stderr lines in CR LF"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant .flow
  _python_crlf
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=empty" "$(_section 'Recent Runs')" "the Recent Runs section"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
fi

if _want learn-flow-link-crlf; then
  _flow_test_begin "/flow:learn: refusals whose lines end in \\r are still named without their ending (L65)"
  e2e_new learn-flow-link-crlf
  e2e_describe "a goal and an active run are written, then .flow is moved outside the repository and replaced by a symlink to it; python3 ends its stderr lines in CR LF"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_events
  _plant .flow
  _python_crlf
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
fi

if _want resume-preflight-flow-link-crlf; then
  _flow_test_begin "/flow:resume pre-flight: a refusal whose line ends in \\r is still named without its ending (L65)"
  e2e_new resume-preflight-flow-link-crlf
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it; python3 ends its stderr lines in CR LF"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  _python_crlf
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'No FlowRuns exist'
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
fi

if _want resume-read-run-dir-link-crlf; then
  _flow_test_begin "/flow:resume run read: a refusal whose line ends in \\r is still named without its ending (L65)"
  e2e_new resume-read-run-dir-link-crlf
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it; python3 ends its stderr lines in CR LF"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  _python_crlf
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
fi

if _want start-goal-flow-link-crlf; then
  _flow_test_begin "/flow:start goal block: a refusal whose line ends in \\r is still named without its ending (L65)"
  e2e_new start-goal-flow-link-crlf
  e2e_describe "an active goal issue-42 is written, then .flow is moved outside the repository and replaced by a symlink to it; python3 ends its stderr lines in CR LF; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  _plant .flow
  _python_crlf
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
fi

if _want hook-commit-journal-only-crlf; then
  _flow_test_begin "PostToolUse log-commits.sh: a journal-only commit is recognised when python3 ends its stdout lines in \\r\\n (L65)"
  e2e_new hook-commit-journal-only-crlf
  e2e_describe "journal.dir is .decisions; the last commit on feature/issue-42-e2e adds .decisions/issue-42.md and nothing else; python3 ends its stdout lines in CR LF, as on Windows"
  _journal_commit .decisions "docs: the journal"
  _real_python3=$(command -v python3)
  _cr=$(printf '\r')
  cat > "$E2E_BIN/python3" <<SHIM
#!/bin/bash
"$_real_python3" "\$@" | sed 's/\$/$_cr/'; exit "\${PIPESTATUS[0]}"
SHIM
  chmod +x "$E2E_BIN/python3"
  printf 'python3: the real one, its stdout lines ending in CR LF\n' >> "$E2E_ARTIFACT"
  e2e_run_hook hooks/scripts/log-commits.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m journal"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal 0 "$(_trail_commits .decisions)" "commit breadcrumbs in the trail"
fi

# --- the recorder under failures (L66) ---------------------------------------

# _evidence_listing — every entry in the run's evidence directory.
_evidence_listing() { (cd "$E2E_REPO/.flow/runs/$RID/evidence" 2>/dev/null && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' '); }

# _run_bin_ulimit <1024-byte blocks> <file under the plugin> [arguments] —
# _run_bin with the files the helper writes held to that size.
_run_bin_ulimit() {
  local blocks="$1" rel="$2"; shift 2
  {
    printf 'code: %s\n' "$rel"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$rel")"
    printf 'arguments: %s\n' "$*"
    printf 'ulimit -f: %s\n' "$blocks"
  } >> "$E2E_ARTIFACT"
  _e2e_exec bash -c 'ulimit -f "$1" && shift && exec "$@"' _ "$blocks" "$E2E_ACTIVE_PLUGIN/$rel" "$@"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

if _want record-evidence-short-copy; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a copy cut short by a file size limit is not recorded, and leaves nothing (L66)"
  e2e_new record-evidence-short-copy
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt, 70000 bytes ending in Z, under ulimit -f 64 (65536 bytes, in bash's 1024-byte blocks)"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  python3 -c 'import sys; open(sys.argv[1], "w").write("A" * 69999 + "Z")' "$E2E_REPO/raw.txt"
  _run_bin_ulimit 64 bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "raw-output copy failed"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-short-write; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a copy written short in its one write is not recorded (L66)"
  e2e_new record-evidence-short-write
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt, 50000 bytes ending in Z, read in one piece, under ulimit -f 40 (40960 bytes, in bash's 1024-byte blocks): the one write is short"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  python3 -c 'import sys; open(sys.argv[1], "w").write("A" * 49999 + "Z")' "$E2E_REPO/raw.txt"
  _run_bin_ulimit 40 bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "raw-output copy failed"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-lock-link; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a sidecar that cannot be written takes its copy away again (L66)"
  e2e_new record-evidence-lock-link
  e2e_describe "the run's .lock is a symlink to a file outside the repository, so the sidecar cannot be written; the fixture sidecar with no output_ref, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  mkdir -p "$E2E_DIR/outside"
  printf 'lock\n' > "$E2E_DIR/outside/lock"
  ln -s "$E2E_DIR/outside/lock" "$E2E_REPO/.flow/runs/$RID/.lock" || _flow_assert_fail "$E2E_NAME: could not plant .lock"
  printf 'planted: .flow/runs/%s/.lock -> <scratch>/%s/outside/lock\n' "$RID" "$E2E_NAME" >> "$E2E_ARTIFACT"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "is a symlink"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-twice-no-raw; then
  _flow_test_begin "flow-record-evidence.sh: a second record of an id without --raw-output is refused, and the first sidecar stays (L66)"
  e2e_new record-evidence-twice-no-raw
  e2e_describe "the fixture sidecar with no output_ref and exit_code 1 is recorded; then the same id with exit_code 0; neither with --raw-output"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  sed -i.bak 's/^  exit_code: 0$/  exit_code: 1/' "$E2E_REPO/evidence.yaml"
  mv "$E2E_REPO/evidence.yaml.bak" "$E2E_DIR/evidence.bak"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  e2e_expect_equal 0 "$E2E_RC" "the first record's exit status"
  _sidecar_without_ref
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  e2e_expect_equal 2 "$E2E_RC" "the second record's exit status"
  e2e_expect_err "evidence-ac1-test is already recorded"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" "exit_code: 1"
fi

# _py_site <name> <python> — a sitecustomize.py in $E2E_DIR/site-<name> that
# runs <python> and then the sitecustomize it hides, if any; put on
# PYTHONPATH, it changes a helper's python3 at start-up, to inject a failure
# or watch a call.
_py_site() {
  mkdir -p "$E2E_DIR/site-$1"
  {
    printf '%s\n' "$2"
    cat <<'CHAIN'
import os as _os, sys as _sys
def _flow_e2e_chain():
    here = _os.path.dirname(_os.path.abspath(__file__))
    for d in _sys.path:
        p = _os.path.join(_os.path.abspath(d or "."), "sitecustomize.py")
        if _os.path.dirname(p) != here and _os.path.isfile(p):
            exec(compile(open(p).read(), p, "exec"), {"__name__": "sitecustomize", "__file__": p})
            return
_flow_e2e_chain()
CHAIN
  } > "$E2E_DIR/site-$1/sitecustomize.py"
  printf 'python3 start-up: %s\n' "$1" >> "$E2E_ARTIFACT"
}

# _run_bin_site <name> <file under the plugin> [arguments] — _run_bin with
# $E2E_DIR/site-<name> first on PYTHONPATH.
_run_bin_site() {
  local name="$1" saved="${PYTHONPATH:-}"; shift
  export PYTHONPATH="$E2E_DIR/site-$name${saved:+:$saved}"
  _run_bin "$@"
  export PYTHONPATH="$saved"
}

# A record touches waiting.<pid> in its working directory just before it
# waits for a lock.
FLOCK_MARKER_PY='
import fcntl as _fcntl, os as _os0
_real_flock = _fcntl.flock
def _marking_flock(fd, op):
    if op & _fcntl.LOCK_EX:
        open("waiting.%d" % _os0.getpid(), "w").close()
    return _real_flock(fd, op)
_fcntl.flock = _marking_flock
'

# The two overlapping records: the run's lock is held until both records have
# reached it (each touches a marker, through the flock shim, just before it
# waits for the lock), so both are past every check made before the lock
# when it is released, and the refusal is the one made under the lock. The
# holder lets go after 10 seconds whatever it has seen, so a record that
# never reaches the lock fails the count instead of hanging the suite; the
# count is the number of records waiting as the holder lets go, written by
# the holder itself.
OVERLAP_SH='
plugin=$1; rid=$2; shim=$3
python3 -c "import fcntl, glob, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], \"w\").close()
deadline = time.time() + 10
while len(glob.glob(\"waiting.*\")) < 2 and time.time() < deadline:
    time.sleep(0.05)
open(sys.argv[3], \"w\").write(str(len(glob.glob(\"waiting.*\"))))" ".flow/runs/$rid/.lock" held waiting-at-release &
holder=$!
n=0
while [ ! -e held ] && [ "$n" -lt 200 ]; do sleep 0.05; n=$((n + 1)); done
PYTHONPATH="$shim${PYTHONPATH:+:$PYTHONPATH}" "$plugin/bin/flow-record-evidence.sh" --run-id "$rid" --evidence-file first.yaml 2>first.err & a=$!
PYTHONPATH="$shim${PYTHONPATH:+:$PYTHONPATH}" "$plugin/bin/flow-record-evidence.sh" --run-id "$rid" --evidence-file second.yaml 2>second.err & b=$!
wait $a; ra=$?; wait $b; rb=$?; wait $holder
printf "records waiting on the lock at once: %s\n" "$(cat waiting-at-release 2>/dev/null)"
printf "exit statuses: %s\n" "$(printf "%s\n" "$ra" "$rb" | sort | tr "\n" " ")"
grep -h "recorded by another record" first.err second.err | head -1
'

if _want record-evidence-overlap; then
  _flow_test_begin "flow-record-evidence.sh: of two overlapping records of one id, one is refused (L66)"
  e2e_new record-evidence-overlap
  e2e_describe "the run's lock is held until two records of evidence-ac1-test, one with exit_code 1 and one with exit_code 0, neither with --raw-output, are both waiting for it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  sed 's/^  exit_code: 0$/  exit_code: 1/' "$E2E_REPO/evidence.yaml" > "$E2E_REPO/first.yaml"
  cp "$E2E_REPO/evidence.yaml" "$E2E_REPO/second.yaml"
  _py_site flock-marker "$FLOCK_MARKER_PY"
  printf 'code: bin/flow-record-evidence.sh, twice at once\ncode sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh")" >> "$E2E_ARTIFACT"
  _e2e_exec bash -c "$OVERLAP_SH" _ "$E2E_ACTIVE_PLUGIN" "$RID" "$E2E_DIR/site-flock-marker"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
  e2e_expect_line "records waiting on the lock at once: 2"
  e2e_expect_line "exit statuses: 0 2 "
  e2e_expect_out "evidence-ac1-test was recorded by another record while this one ran"
fi

if _want record-evidence-long-id; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: an id too long for the names written for it is refused before the copy, and no traceback (L66, L70)"
  e2e_new record-evidence-long-id
  e2e_describe "the fixture sidecar with an id of 235 characters and no output_ref, recorded with --raw-output raw.txt: the copy's name would fit, the temporary file beside the sidecar would not"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  _long_id=$(python3 -c 'print("e" * 235)')
  sed -i.bak "s/^  id: evidence-ac1-test\$/  id: $_long_id/" "$E2E_REPO/evidence.yaml"
  mv "$E2E_REPO/evidence.yaml.bak" "$E2E_DIR/evidence.bak"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence.metadata.id is too long: 235 characters"
  _expect_err_lacks "Traceback"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-orphan-copy; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a copy an interrupted record left is named as such (L66)"
  e2e_new record-evidence-orphan-copy
  e2e_describe "the run's evidence directory holds evidence-ac1-test.txt and no sidecar, as a record killed between its copy and its sidecar leaves it; the fixture sidecar with no output_ref, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  mkdir -p "$E2E_REPO/.flow/runs/$RID/evidence"
  printf 'ORPHAN\n' > "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.txt"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "a copy .flow/runs/$RID/evidence/evidence-ac1-test.txt exists with no sidecar: a record of this id is running, or one was stopped"
  e2e_expect_equal "./evidence-ac1-test.txt " "$(_evidence_listing)" "what the evidence directory holds"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.txt" "ORPHAN"
fi

# --- a \r in journal-dir.sh's reason, and in the strip (L66) ------------------

# _python_crlf_out — python3 in the scenario's bin is the real one with its
# stdout lines ending in \r\n, as Python writes them to a pipe on Windows.
_python_crlf_out() {
  local real cr
  real=$(command -v python3)
  cr=$(printf '\r')
  cat > "$E2E_BIN/python3" <<SHIM
#!/bin/bash
"$real" "\$@" | sed 's/\$/$cr/'; exit "\${PIPESTATUS[0]}"
SHIM
  chmod +x "$E2E_BIN/python3"
  printf 'python3: the real one, its stdout lines ending in CR LF\n' >> "$E2E_ARTIFACT"
}

if _want journal-dir-semicolon-link-crlf; then
  _flow_test_begin "journal-dir.sh (/flow:brainstorm decision block): a reason whose line ends in \\r is named without it (L66)"
  e2e_new journal-dir-semicolon-link-crlf
  e2e_describe "journal.dir in .claude/settings.flow.json is 'a; b', a symlink the repository commits to a directory outside it; python3 ends its stdout lines in CR LF; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"a; b"}}'
  _plant "a; b"
  _python_crlf_out
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_err "refusing journal.dir 'a; b' from .claude/settings.flow.json: a; b is a symlink; using .decisions"
  _expect_untouched
fi

if _want strip-decisions-link-crlf; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip dry run): a refusal whose line ends in \\r is printed without it (L66)"
  e2e_new strip-decisions-link-crlf
  e2e_describe ".decisions, holding a journal, is a symlink the repository commits to a directory outside it; python3 ends its stderr lines in CR LF"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions
  _python_crlf
  E2E_FENCE_SHELLS="${E2E_FENCE_SHELLS%% *}" e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" 'dry-run — emits STRIP_AUTO_LOG'
  e2e_expect_err "refusing — journal dir .decisions: .decisions is a symlink; nothing is written under it"
  e2e_expect_equal no "$(printf '%s' "$E2E_ERR" | grep -q "$(printf '\r')" && echo yes || echo no)" "stderr holds a carriage return"
  _expect_untouched
fi

# --- the recorder's clean-up and the sidecar that was published (L67) --------

# A SIGINT once the sidecar is published: after a directory is synced and
# the sidecar is there.
SIGINT_AFTER_PY='
import os as _o, signal as _sig, stat as _st
_real_fsync = _o.fsync
def _fsync(fd):
    r = _real_fsync(fd)
    side = _o.environ.get("SPY_SIDECAR", "")
    try:
        if side and _st.S_ISDIR(_o.fstat(fd).st_mode) and _o.path.lexists(side):
            _o.kill(_o.getpid(), _sig.SIGINT)
    except OSError:
        pass
    return r
_o.fsync = _fsync
'

# A SIGINT once the copy is synced, before the sidecar is written.
SIGINT_BEFORE_PY='
import os as _o, signal as _sig, stat as _st
_real_fsync = _o.fsync
_done = []
def _fsync(fd):
    r = _real_fsync(fd)
    try:
        if not _done and _st.S_ISREG(_o.fstat(fd).st_mode):
            _done.append(1)
            _o.kill(_o.getpid(), _sig.SIGINT)
    except OSError:
        pass
    return r
_o.fsync = _fsync
'

# A SIGINT once the sidecar's temporary file is synced, before it is published:
# after the second regular file synced (the copy, then the temporary file).
SIGINT_SIDECAR_PY='
import os as _o, signal as _sig, stat as _st
_real_fsync = _o.fsync
_seen = []
def _fsync(fd):
    r = _real_fsync(fd)
    try:
        if _st.S_ISREG(_o.fstat(fd).st_mode):
            _seen.append(1)
            if len(_seen) == 2:
                _o.kill(_o.getpid(), _sig.SIGINT)
    except OSError:
        pass
    return r
_o.fsync = _fsync
'

# os.unlink of the sidecar's temporary file fails, as after an I/O error.
UNLINK_TMP_EIO_PY='
import errno as _e, os as _o
_real_unlink = _o.unlink
def _unlink(p, *a, **k):
    if str(p).endswith(".tmp") and ".evidence.yaml." in str(p):
        raise OSError(_e.EIO, _o.strerror(_e.EIO), p)
    return _real_unlink(p, *a, **k)
_o.unlink = _unlink
'

# Every fsync is logged by the inode of what it synced, to $SPY_LOG.
FSYNC_SPY_PY='
import os as _o
_real_fsync = _o.fsync
def _fsync(fd):
    try:
        with open(_o.environ["SPY_LOG"], "a") as f:
            f.write("%d\n" % _o.fstat(fd).st_ino)
    except (OSError, KeyError):
        pass
    return _real_fsync(fd)
_o.fsync = _fsync
'

# Creating the sidecar's temporary file fails, and the copy is replaced by
# another file first, as if something else wrote to that name meanwhile.
COPY_REPLACED_PY='
import errno as _e, os as _o, tempfile as _t
_real_mkstemp = _t.mkstemp
def _mkstemp(*a, **k):
    _o.rename(_o.environ["SPY_REPLACEMENT"], _o.environ["SPY_COPY"])
    raise OSError(_e.ENOSPC, _o.strerror(_e.ENOSPC))
_t.mkstemp = _mkstemp
'

if _want record-evidence-sigint-after-publish; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a SIGINT after the sidecar is published leaves the sidecar and its copy (L67)"
  e2e_new record-evidence-sigint-after-publish
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; python3 sends itself SIGINT once a directory is synced and the sidecar is there"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site sigint-after "$SIGINT_AFTER_PY"
  export SPY_SIDECAR="$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  _run_bin_site sigint-after bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_SIDECAR
  e2e_expect_equal 130 "$E2E_RC" "the exit status"
  e2e_expect_equal "./evidence-ac1-test.evidence.yaml ./evidence-ac1-test.txt " "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-sigint-before-publish; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a SIGINT after the copy and before the sidecar leaves nothing (L67)"
  e2e_new record-evidence-sigint-before-publish
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; python3 sends itself SIGINT once the copy is synced"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site sigint-before "$SIGINT_BEFORE_PY"
  _run_bin_site sigint-before bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 130 "$E2E_RC" "the exit status"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-sigint-during-sidecar; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a SIGINT while the sidecar is written, before it is published, leaves nothing, no temporary file either (L67)"
  e2e_new record-evidence-sigint-during-sidecar
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; python3 sends itself SIGINT once the sidecar's temporary file is synced"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site sigint-sidecar "$SIGINT_SIDECAR_PY"
  _run_bin_site sigint-sidecar bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 130 "$E2E_RC" "the exit status"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-unlink-tmp-fails; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a step that fails after the sidecar is published does not undo the record (L67)"
  e2e_new record-evidence-unlink-tmp-fails
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; python3's os.unlink of the sidecar's temporary file fails with EIO once the sidecar is linked into place"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site unlink-eio "$UNLINK_TMP_EIO_PY"
  _run_bin_site unlink-eio bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" "output_ref: evidence-ac1-test.txt"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.txt" "raw"
fi

if _want record-evidence-copy-replaced; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: the clean-up removes only the copy it made (L67)"
  e2e_new record-evidence-copy-replaced
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; creating the sidecar's temporary file fails, after the copy has been replaced by another file holding REPLACEMENT"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  printf 'REPLACEMENT\n' > "$E2E_REPO/replacement.txt"
  _py_site copy-replaced "$COPY_REPLACED_PY"
  export SPY_REPLACEMENT="$E2E_REPO/replacement.txt" SPY_COPY="$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.txt"
  _run_bin_site copy-replaced bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_REPLACEMENT SPY_COPY
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.txt" "REPLACEMENT"
fi

if _want record-evidence-copy-synced; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: the copy is synced before the sidecar names it (L67)"
  e2e_new record-evidence-copy-synced
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; python3 logs the inode of everything it syncs"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site fsync-spy "$FSYNC_SPY_PY"
  export SPY_LOG="$E2E_DIR/fsync.log"
  _run_bin_site fsync-spy bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_LOG
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _copy_ino=$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.txt" 2>/dev/null)
  e2e_expect_equal yes "$([ -n "$_copy_ino" ] && grep -qx "$_copy_ino" "$E2E_DIR/fsync.log" 2>/dev/null && echo yes || echo no)" "the copy was synced"
fi

if _want record-evidence-deep-evidence; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: evidence nested too deep to write is refused in one line, as at the read, and leaves nothing (L67, L68)"
  e2e_new record-evidence-deep-evidence
  e2e_describe "the fixture sidecar with no output_ref and a list nested 400 deep under evidence.notes, recorded with --raw-output raw.txt: PyYAML reads it and cannot write it (it writes to about 350 levels, and reads to about 490, on Python 3.14)"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  python3 -c 'import sys; open(sys.argv[1], "a").write("  notes: " + "[" * 400 + "x" + "]" * 400 + "\n")' "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence evidence-ac1-test is nested too deep to write"
  _expect_err_lacks "Traceback"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-copy-name-dir; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a directory at the copy's name is not called a copy (L67)"
  e2e_new record-evidence-copy-name-dir
  e2e_describe "the run's evidence directory holds a directory named evidence-ac1-test.txt and no sidecar; the fixture sidecar with no output_ref, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  mkdir -p "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.txt"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err ".flow/runs/$RID/evidence/evidence-ac1-test.txt is in the way, and not a regular file"
  _expect_err_lacks "exists with no sidecar"
fi

# --- the recorder's reads, and a race for its copy's name (L68) --------------

# _expect_one_line_err — stderr is one line, and not an empty one.
_expect_one_line_err() {
  local n=0
  [ -z "$E2E_ERR" ] || n=$(printf '%s\n' "$E2E_ERR" | wc -l | tr -d ' ')
  e2e_expect_equal 1 "$n" "the number of lines on stderr"
}

if _want record-evidence-deep-read; then
  _flow_test_begin "flow-record-evidence.sh: evidence nested too deep to read is refused in one line, and nothing is written (L68)"
  e2e_new record-evidence-deep-read
  e2e_describe "the fixture sidecar with no output_ref and a list nested 1000 deep under evidence.notes, recorded with --raw-output raw.txt: PyYAML cannot read it (it reads to about 490 levels on Python 3.14; 1000 leaves room for other versions)"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  python3 -c 'import sys; open(sys.argv[1], "a").write("  notes: " + "[" * 1000 + "x" + "]" * 1000 + "\n")' "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--evidence-file is nested too deep to read"
  _expect_err_lacks "Traceback"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-metadata-list; then
  _flow_test_begin "flow-record-evidence.sh: a metadata that is not a mapping is refused in one line (L68)"
  e2e_new record-evidence-metadata-list
  e2e_describe "an evidence file whose metadata is the list [a], recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowEvidence\nmetadata: [a]\n' > "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence.metadata must be a mapping"
  _expect_err_lacks "Traceback"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-not-utf8; then
  _flow_test_begin "flow-record-evidence.sh: an evidence file that is not UTF-8 is refused in one line (L68)"
  e2e_new record-evidence-not-utf8
  e2e_describe "the fixture sidecar with no output_ref and a comment line holding the byte 0xff, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf '# \377\n' >> "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--evidence-file is not UTF-8"
  _expect_err_lacks "Traceback"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-bad-yaml; then
  _flow_test_begin "flow-record-evidence.sh: an evidence file that is not valid YAML is refused in one line (L68)"
  e2e_new record-evidence-bad-yaml
  e2e_describe "an evidence file whose metadata is a flow mapping that is never closed, recorded with --raw-output raw.txt: PyYAML's error names two places, on four lines"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowEvidence\nmetadata: {id: evidence-ac1-test\n' > "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--evidence-file is not valid YAML: while parsing a flow mapping"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if [ "$(id -u)" != 0 ] && _want record-evidence-unreadable; then
  _flow_test_begin "flow-record-evidence.sh: an evidence file that cannot be read is refused in one line (L68)"
  e2e_new record-evidence-unreadable
  e2e_describe "the fixture sidecar with no output_ref, mode 000, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  chmod 000 "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  chmod 644 "$E2E_REPO/evidence.yaml"
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "cannot read --evidence-file evidence.yaml: Permission denied"
  _expect_err_lacks "Traceback"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

# Creating the sidecar's temporary file raises an error that is not flow's own
# and not an OSError: a failure of the write after the evidence's text was
# made and found writable.
WRITE_FAILS_PY='
import tempfile as _t
def _mkstemp(*a, **k):
    raise ValueError("injected by the test")
_t.mkstemp = _mkstemp
'

if _want record-evidence-write-fails; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a write that fails after the evidence was found writable is refused in one line, exit 2, and leaves nothing (L68, L69, L70)"
  e2e_new record-evidence-write-fails
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; python3's tempfile.mkstemp raises ValueError when the sidecar is written"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site write-fails "$WRITE_FAILS_PY"
  _run_bin_site write-fails bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "cannot record evidence-ac1-test: ValueError: injected by the test"
  _expect_err_lacks "Traceback"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

# Just before the record first waits for a lock (the run's lock, which the
# sidecar is written under), $SPY_BEFORE_LOCK runs in bash, with this start-up
# shim left off PYTHONPATH; its exit status goes to before-lock.log in the
# working directory.
BEFORE_LOCK_PY='
import fcntl as _fcntl1, os as _os1, subprocess as _sp1
_real_flock1 = _fcntl1.flock
_ran1 = []
_here1 = _os1.path.dirname(_os1.path.abspath(__file__))
def _before_lock_flock(fd, op):
    if op & _fcntl1.LOCK_EX and not _ran1 and _os1.environ.get("SPY_BEFORE_LOCK"):
        _ran1.append(1)
        env = dict(_os1.environ)
        cmd = env.pop("SPY_BEFORE_LOCK")
        kept = [p for p in env.get("PYTHONPATH", "").split(_os1.pathsep) if p and _os1.path.abspath(p) != _here1]
        if kept:
            env["PYTHONPATH"] = _os1.pathsep.join(kept)
        else:
            env.pop("PYTHONPATH", None)
        r = _sp1.run(["bash", "-c", cmd], env=env)
        with open("before-lock.log", "a") as f:
            f.write("before the lock: exit %d\n" % r.returncode)
    return _real_flock1(fd, op)
_fcntl1.flock = _before_lock_flock
'

if _want record-evidence-lost-race; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a record whose sidecar another record wrote first takes its copy away (L68)"
  e2e_new record-evidence-lost-race
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; just before it waits for the run's lock, a second record of the id without --raw-output completes"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  cp "$E2E_REPO/evidence.yaml" "$E2E_REPO/second.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site before-lock "$BEFORE_LOCK_PY"
  export SPY_BEFORE_LOCK="\"$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh\" --run-id $RID --evidence-file second.yaml 2>/dev/null"
  _run_bin_site before-lock bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_BEFORE_LOCK
  e2e_expect_file_has "before-lock.log" "before the lock: exit 0"
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence-ac1-test was recorded by another record while this one ran"
  e2e_expect_equal "./evidence-ac1-test.evidence.yaml " "$(_evidence_listing)" "what the evidence directory holds"
  e2e_expect_file_lacks ".flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml" "output_ref"
fi

if _want record-evidence-copy-recycled; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: another record's copy made at this one's copy name is not taken away by this one's clean-up (L68)"
  e2e_new record-evidence-copy-recycled
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt (A-RAW); just before it waits for the run's lock, its copy is removed, as the refusal of a copy with no sidecar advises, and a second record of the id with --raw-output raw2.txt (B-RAW) completes. On Linux (ext4) the second copy can be given the removed copy's inode number, which the clean-up took for its own copy; macOS (APFS) does not reuse an inode number, so there this passes either way"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  cp "$E2E_REPO/evidence.yaml" "$E2E_REPO/second.yaml"
  printf 'A-RAW\n' > "$E2E_REPO/raw.txt"
  printf 'B-RAW\n' > "$E2E_REPO/raw2.txt"
  _py_site before-lock "$BEFORE_LOCK_PY"
  export SPY_BEFORE_LOCK="python3 -c 'import os, sys; os.unlink(sys.argv[1])' .flow/runs/$RID/evidence/evidence-ac1-test.txt && \"$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh\" --run-id $RID --evidence-file second.yaml --raw-output raw2.txt 2>/dev/null"
  _run_bin_site before-lock bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_BEFORE_LOCK
  e2e_expect_file_has "before-lock.log" "before the lock: exit 0"
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence-ac1-test was recorded by another record while this one ran"
  e2e_expect_equal "./evidence-ac1-test.evidence.yaml ./evidence-ac1-test.txt " "$(_evidence_listing)" "what the evidence directory holds"
  e2e_expect_file_has ".flow/runs/$RID/evidence/evidence-ac1-test.txt" "B-RAW"
fi

# --- the recorder's inputs and messages (L69) --------------------------------

if _want record-evidence-bad-date; then
  _flow_test_begin "flow-record-evidence.sh: evidence PyYAML parses but cannot build is refused in one line (L69)"
  e2e_new record-evidence-bad-date
  e2e_describe "the fixture sidecar with no output_ref and ran_on: 2024-13-01 under evidence, recorded with --raw-output raw.txt: a date with a thirteenth month"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf '  ran_on: 2024-13-01\n' >> "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--evidence-file is not valid YAML: ValueError: month must be in 1..12"
  _expect_err_lacks "Traceback"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-bad-scalars; then
  _flow_test_begin "flow-record-evidence.sh: scalars PyYAML cannot build, whatever it raises, are refused in one line (L69)"
  e2e_new record-evidence-bad-scalars
  e2e_describe "the fixture sidecar with no output_ref recorded three times, with one line added under evidence each time: ran_on: !!timestamp not-a-date (AttributeError), size: !!int abc (ValueError), and size: a decimal integer of 5001 digits (ValueError, over Python's limit)"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  for _scalar in 'ran_on: !!timestamp not-a-date' 'size: !!int abc' "size: $(python3 -c 'print("9" * 5001)')"; do
    _sidecar_without_ref
    printf '  %s\n' "$_scalar" >> "$E2E_REPO/evidence.yaml"
    _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
    e2e_expect_equal 1 "$E2E_RC" "the exit status"
    e2e_expect_err "--evidence-file is not valid YAML: "
    _expect_err_lacks "Traceback"
    _expect_one_line_err
  done
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-hex-int; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: evidence PyYAML reads but cannot write is refused before the copy, with exit 1 (L69)"
  e2e_new record-evidence-hex-int
  e2e_describe "the fixture sidecar with no output_ref and size: 0x followed by 4000 f digits under evidence, recorded with --raw-output raw.txt: read in base 16, which has no digit limit, and written in decimal, which has one (4300 digits)"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  python3 -c 'import sys; open(sys.argv[1], "a").write("  size: 0x" + "f" * 4000 + "\n")' "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence evidence-ac1-test cannot be written as YAML: ValueError"
  _expect_err_lacks "Traceback"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

# In the recorder's main python3 (the one reading its program from stdin), the
# first os.open of the file $SPY_SWAP names first replaces it, after the
# recorder checked it by name, with a FIFO nothing writes to, a Unix socket,
# or a symlink to $SPY_SWAP_TARGET ($SPY_SWAP_KIND: fifo, socket, symlink);
# and the process is ended by SIGALRM after 10 seconds, so a read that waits
# on the FIFO fails the scenario instead of hanging the suite.
SWAP_PY='
import os as _o8, signal as _s8, socket as _k8, sys as _y8
if _y8.argv[:1] == ["-"]:
    _s8.alarm(10)
    _real_open8 = _o8.open
    _done8 = []
    _keep8 = []
    def _open8(path, flags, *a, **k):
        _p8 = _o8.environ.get("SPY_SWAP", "")
        if _p8 and path == _p8 and not _done8:
            _done8.append(1)
            _o8.unlink(_p8)
            _kind8 = _o8.environ.get("SPY_SWAP_KIND", "fifo")
            if _kind8 == "fifo":
                _o8.mkfifo(_p8)
            elif _kind8 == "socket":
                _sock8 = _k8.socket(_k8.AF_UNIX)
                _sock8.bind(_p8)
                _keep8.append(_sock8)
            else:
                _o8.symlink(_o8.environ["SPY_SWAP_TARGET"], _p8)
        return _real_open8(path, flags, *a, **k)
    _o8.open = _open8
'

if _want record-evidence-fifo-swap; then
  _flow_test_begin "flow-record-evidence.sh: an evidence file replaced by a FIFO after the recorder checked it is refused, not waited on (L69)"
  e2e_new record-evidence-fifo-swap
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; evidence.yaml is replaced by a FIFO when the recorder opens it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site swap "$SWAP_PY"
  export SPY_SWAP=evidence.yaml SPY_SWAP_KIND=fifo
  _run_bin_site swap bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_SWAP SPY_SWAP_KIND
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--evidence-file evidence.yaml is not a regular file"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-raw-fifo-swap; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a raw output replaced by a FIFO after the recorder checked it is refused, not waited on (L69)"
  e2e_new record-evidence-raw-fifo-swap
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; raw.txt is replaced by a FIFO when the recorder opens it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site swap "$SWAP_PY"
  export SPY_SWAP=raw.txt SPY_SWAP_KIND=fifo
  _run_bin_site swap bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_SWAP SPY_SWAP_KIND
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--raw-output raw.txt is not a regular file"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-raw-socket-swap; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a raw output replaced by a Unix socket after the recorder checked it is the caller's fault, exit 1 (L70)"
  e2e_new record-evidence-raw-socket-swap
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt; raw.txt is replaced by a Unix socket when the recorder opens it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _py_site swap "$SWAP_PY"
  export SPY_SWAP=raw.txt SPY_SWAP_KIND=socket
  _run_bin_site swap bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  unset SPY_SWAP SPY_SWAP_KIND
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "cannot read --raw-output raw.txt: "
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-symlink-swap; then
  _flow_test_begin "flow-record-evidence.sh: an evidence file replaced by a symlink after the recorder checked it is refused as a symlink (L70)"
  e2e_new record-evidence-symlink-swap
  e2e_describe "the fixture sidecar with no output_ref; evidence.yaml is replaced, when the recorder opens it, by a symlink to a copy of itself outside the repository"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  mkdir -p "$E2E_DIR/outside"
  cp "$E2E_REPO/evidence.yaml" "$E2E_DIR/outside/evidence.yaml"
  _py_site swap "$SWAP_PY"
  export SPY_SWAP=evidence.yaml SPY_SWAP_KIND=symlink SPY_SWAP_TARGET="$E2E_DIR/outside/evidence.yaml"
  _run_bin_site swap bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  unset SPY_SWAP SPY_SWAP_KIND SPY_SWAP_TARGET
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — --evidence-file evidence.yaml is a symlink"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if [ "$(id -u)" != 0 ] && _want record-evidence-raw-unreadable; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a raw output that cannot be read is the caller's fault, exit 1, in one line (L69)"
  e2e_new record-evidence-raw-unreadable
  e2e_describe "the fixture sidecar with no output_ref, recorded with --raw-output raw.txt, where raw.txt has mode 000"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  chmod 000 "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  chmod 644 "$E2E_REPO/raw.txt"
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "cannot read --raw-output raw.txt: Permission denied"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

# The os module without O_NOFOLLOW and O_NONBLOCK, as on a native Windows
# python3.
NO_NOFOLLOW_PY='
import os as _o12
for _n12 in ("O_NOFOLLOW", "O_NONBLOCK"):
    if hasattr(_o12, _n12):
        delattr(_o12, _n12)
'

if _want record-evidence-no-nofollow; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: a python3 with no O_NOFOLLOW (native Windows) records, and still refuses a symlinked raw output (L69)"
  e2e_new record-evidence-no-nofollow
  e2e_describe "python3's os module has no O_NOFOLLOW and no O_NONBLOCK; the fixture sidecar with no output_ref is recorded with --raw-output raw.txt; then, in a second run, a raw output that is a symlink to a file outside the repository"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  cp "$E2E_REPO/evidence.yaml" "$E2E_REPO/second.yaml"
  sed -i.bak 's/^  id: evidence-ac1-test$/  id: evidence-ac1-link/' "$E2E_REPO/second.yaml"
  mv "$E2E_REPO/second.yaml.bak" "$E2E_DIR/second.bak"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  mkdir -p "$E2E_DIR/outside"
  printf 'LINKED-RAW\n' > "$E2E_DIR/outside/raw.txt"
  ln -s "$E2E_DIR/outside/raw.txt" "$E2E_REPO/raw-link.txt" || _flow_assert_fail "$E2E_NAME: could not plant raw-link.txt"
  printf 'planted: raw-link.txt -> <scratch>/%s/outside/raw.txt\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  _py_site no-nofollow "$NO_NOFOLLOW_PY"
  _run_bin_site no-nofollow bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 0 "$E2E_RC" "the exit status of the record"
  _run_bin_site no-nofollow bin/flow-record-evidence.sh --run-id "$RID" --evidence-file second.yaml --raw-output raw-link.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status of the record with a symlinked raw output"
  e2e_expect_err "raw-output source raw-link.txt is a symlink"
  e2e_expect_equal "./evidence-ac1-test.evidence.yaml ./evidence-ac1-test.txt " "$(_evidence_listing)" "what the evidence directory holds"
fi

# os.unlink refuses a file that a descriptor from os.dup still holds open, as
# Windows refuses to delete a file that is open.
WINDOWS_UNLINK_PY='
import errno as _e13, os as _o13
_held13 = {}
_real_dup13, _real_close13, _real_unlink13 = _o13.dup, _o13.close, _o13.unlink
def _dup13(fd):
    n = _real_dup13(fd)
    st = _o13.fstat(n)
    _held13[n] = (st.st_dev, st.st_ino)
    return n
def _close13(fd):
    _held13.pop(fd, None)
    return _real_close13(fd)
def _unlink13(p, *a, **k):
    try:
        st = _o13.lstat(p)
    except OSError:
        st = None
    if st is not None and (st.st_dev, st.st_ino) in _held13.values():
        raise PermissionError(_e13.EACCES, "the file is open", p)
    return _real_unlink13(p, *a, **k)
_o13.dup, _o13.close, _o13.unlink = _dup13, _close13, _unlink13
'

if _want record-evidence-windows-unlink; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: the clean-up removes its copy where an open file cannot be removed (Windows) (L69)"
  e2e_new record-evidence-windows-unlink
  e2e_describe "the run's .lock is a symlink, so the sidecar cannot be written after the copy; python3's os.unlink refuses a file a descriptor from os.dup still holds, as Windows does; the fixture sidecar with no output_ref, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  mkdir -p "$E2E_DIR/outside"
  printf 'lock\n' > "$E2E_DIR/outside/lock"
  ln -s "$E2E_DIR/outside/lock" "$E2E_REPO/.flow/runs/$RID/.lock" || _flow_assert_fail "$E2E_NAME: could not plant .lock"
  printf 'planted: .flow/runs/%s/.lock -> <scratch>/%s/outside/lock\n' "$RID" "$E2E_NAME" >> "$E2E_ARTIFACT"
  _py_site windows-unlink "$WINDOWS_UNLINK_PY"
  _run_bin_site windows-unlink bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "is a symlink"
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if _want record-evidence-alias; then
  _flow_test_begin "flow-record-evidence.sh: evidence that uses a YAML alias is refused in one line (L69)"
  e2e_new record-evidence-alias
  e2e_describe "the fixture sidecar with no output_ref, its proves list anchored as &p and repeated as notes: *p, recorded with --raw-output raw.txt"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  sed -i.bak 's/^  proves:$/  proves: \&p/' "$E2E_REPO/evidence.yaml"
  mv "$E2E_REPO/evidence.yaml.bak" "$E2E_DIR/evidence.bak"
  printf '  notes: *p\n' >> "$E2E_REPO/evidence.yaml"
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "--evidence-file uses a YAML alias"
  _expect_one_line_err
  e2e_expect_equal "" "$(_evidence_listing)" "what the evidence directory holds"
fi

if python3 -c 'import jsonschema' 2>/dev/null && _want record-evidence-schema-message; then
  _flow_test_begin "flow-record-evidence.sh: a schema refusal names where and which rule, not the value (L69)"
  e2e_new record-evidence-schema-message
  e2e_describe "the fixture sidecar with no output_ref whose proves is a string of 20000 A characters, not a list, recorded with jsonschema installed"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _sidecar_without_ref
  python3 - "$E2E_REPO/evidence.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "  proves:\n    - AC1\n"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "  proves: " + "A" * 20000 + "\n"))
PY
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "evidence does not match schema at \$.evidence.proves (type: \"array\")"
  _expect_one_line_err
  e2e_expect_equal yes "$([ "${#E2E_ERR}" -lt 400 ] && echo yes || echo no)" "stderr is under 400 characters"
fi

if _want bundle-sidecar-bad-date; then
  _flow_test_begin "evidence bundle (evaluator loop): a sidecar PyYAML parses but cannot build is reported unreadable, without a traceback (L69)"
  e2e_new bundle-sidecar-bad-date
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; the sidecar also holds ran_on: 2024-13-01 under evidence"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  printf '  ran_on: 2024-13-01\n' >> "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "(unreadable: evidence-ac1-test.evidence.yaml): YAML parse error: ValueError"
  _expect_err_lacks "Traceback"
fi

# --- every exit and message of the recorder, from the decision journal (L70) --

# _stderr_problems [<text>] — what is wrong with stderr, as bytes: empty, more
# or less than one line, a control character (category Cc, which holds C0,
# DEL and C1), a byte that is not UTF-8, U+2028 or U+2029, or not holding
# <text>; "ok" when nothing is. Read from the file the command wrote, since
# $E2E_ERR has lost its last line end, and decoded as UTF-8, not byte by byte.
_stderr_problems() {
  python3 - "$E2E_DIR/err" "${1-}" <<'PY'
import sys, unicodedata
text = open(sys.argv[1], "rb").read().decode("utf-8", "surrogateescape")
problems = []
if not text:
    problems.append("stderr is empty")
elif text.count("\n") != 1 or not text.endswith("\n"):
    problems.append("stderr has %d line ends, not one at its end" % text.count("\n"))
bad = sorted({"U+%04X" % ord(c) for c in text.rstrip("\n")
              if unicodedata.category(c) in ("Cc", "Cs") or c in "\u2028\u2029"})
if bad:
    problems.append("stderr holds " + " ".join(bad))
if sys.argv[2] and sys.argv[2] not in text:
    problems.append("stderr does not hold " + ascii(sys.argv[2]))
print("; ".join(problems) or "ok")
PY
}

# _flow_tree — every entry under .flow, one per line.
_flow_tree() { (cd "$E2E_REPO" && find .flow 2>/dev/null | LC_ALL=C sort); }

# _refusal <row> <exit> <text> <made> -- <arguments>: one row of the decision
# journal's table. The recorder is run with <arguments>, and with PATH set to
# $REFUSAL_PATH when that is set; its exit status is <exit>, its stderr one
# line of text holding <text>, and, where <made> is "none", nothing under
# .flow was made or removed by it.
_refusal() {
  local row="$1" want="$2" text="$3" made="$4" before
  shift 5
  printf 'row: %s\n' "$row" >> "$E2E_ARTIFACT"
  before=$(_flow_tree)
  if [ -n "${REFUSAL_PATH:-}" ]; then
    printf 'code: bin/flow-record-evidence.sh\ncode sha256: %s\narguments: %s\nPATH: %s\n' \
      "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh")" "$*" "${REFUSAL_PATH#"$E2E_DIR/"}" >> "$E2E_ARTIFACT"
    _e2e_exec env PATH="$REFUSAL_PATH" "$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh" "$@"
    printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
  else
    _run_bin bin/flow-record-evidence.sh "$@"
  fi
  e2e_expect_equal "$want" "$E2E_RC" "$row: the exit status"
  e2e_expect_equal ok "$(_stderr_problems "$text")" "$row: stderr is one line of text that names what was refused"
  if [ "$made" = none ]; then
    e2e_expect_equal "$before" "$(_flow_tree)" "$row: what is under .flow"
  fi
}

if python3 -c 'import jsonschema' 2>/dev/null && _want record-evidence-refusals; then
  _flow_test_begin "flow-record-evidence.sh: every refusal in the decision journal's table exits as the header says, on one line of text that names what was refused (L70)"
  e2e_new record-evidence-refusals
  e2e_describe "one run of the recorder per row of the decision journal's table of its exits and messages, each under its own run id: the arguments, the inputs, the evidence, and what is in the way once the run directory is made. Values carry a line end, an escape sequence, U+009B, U+2028 and a byte that is not UTF-8, and must come out escaped. Each row up to the symlinked inputs must leave .flow as it found it. Run with jsonschema installed, as CI runs it; without it a warning line comes first once a day"
  e2e_repo feature/issue-42-e2e
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  mkdir -p "$E2E_DIR/outside"
  printf 'outside\n' > "$E2E_DIR/outside/file"
  _forged=$(printf 'x\nflow-record-evidence.sh: recorded evidence-ac1-test \033[31mFORGED\302\2331m\342\200\250end')
  _forged_byte=$(printf 'x\nflow-record-evidence.sh: recorded evidence-ac1-test \033[31mFORGED\302\2331m\342\200\250\233end')
  _escaped='x\nflow-record-evidence.sh: recorded evidence-ac1-test \x1b[31mFORGED\x9b1m\u2028end'
  _escaped_byte='x\nflow-record-evidence.sh: recorded evidence-ac1-test \x1b[31mFORGED\x9b1m\u2028\x9bend'
  _evidence_with() { # <file> <line added under evidence>
    grep -v 'output_ref:' "$FIXTURES/evidence/valid.yaml" > "$E2E_REPO/$1"
    printf '%s\n' "$2" >> "$E2E_REPO/$1"
  }

  # A PATH with bash and dirname and no python3; then one whose python3
  # cannot import yaml.
  mkdir -p "$E2E_DIR/path-no-python" "$E2E_DIR/path-no-yaml"
  ln -s "$(command -v bash)" "$E2E_DIR/path-no-python/bash"
  ln -s "$(command -v dirname)" "$E2E_DIR/path-no-python/dirname"
  ln -s "$(command -v bash)" "$E2E_DIR/path-no-yaml/bash"
  ln -s "$(command -v dirname)" "$E2E_DIR/path-no-yaml/dirname"
  printf '#!/bin/sh\nexit 1\n' > "$E2E_DIR/path-no-yaml/python3"
  chmod +x "$E2E_DIR/path-no-yaml/python3"
  REFUSAL_PATH="$E2E_DIR/path-no-python"
  _refusal no-python3 2 "python3 required but not installed" none -- --run-id R-no-python3 --evidence-file evidence.yaml
  REFUSAL_PATH="$E2E_DIR/path-no-yaml"
  _refusal no-pyyaml 2 "PyYAML required" none -- --run-id R-no-pyyaml --evidence-file evidence.yaml
  REFUSAL_PATH=""
  _refusal unknown-argument 1 "unknown argument: --bogus$_escaped_byte" none -- "--bogus$_forged_byte"
  _refusal option-without-value 1 "--raw-output needs a value" none -- --run-id R-option --evidence-file evidence.yaml --raw-output
  _refusal no-run-id 1 "--run-id is required" none -- --evidence-file evidence.yaml
  _refusal no-evidence-file 1 "--evidence-file is required" none -- --run-id R-no-evidence-file
  _refusal run-id-dots 1 "--run-id contains '..' or '/' — refusing for safety (got: R..$_escaped_byte)" none -- --run-id "R..$_forged_byte" --evidence-file evidence.yaml
  _refusal run-id-long 1 "--run-id is 300 bytes" none -- --run-id "$(python3 -c 'print("r" * 300)')" --evidence-file evidence.yaml
  _refusal evidence-absent 1 "--evidence-file absent$_escaped does not exist" none -- --run-id R-evidence-absent --evidence-file "absent$_forged"
  _long_name=$(python3 -c 'print("n" * 300)')
  _refusal evidence-name-too-long 1 "cannot read --evidence-file $_long_name: File name too long" none -- --run-id R-name-too-long --evidence-file "$_long_name"
  mkdir "$E2E_REPO/ev-dir"
  _refusal evidence-dir 1 "--evidence-file ev-dir is not a regular file" none -- --run-id R-evidence-dir --evidence-file ev-dir
  mkfifo "$E2E_REPO/ev-fifo"
  _refusal evidence-fifo 1 "--evidence-file ev-fifo is not a regular file" none -- --run-id R-evidence-fifo --evidence-file ev-fifo
  if [ "$(id -u)" != 0 ]; then
    cp "$E2E_REPO/evidence.yaml" "$E2E_REPO/ev  two spaces.yaml"
    chmod 000 "$E2E_REPO/ev  two spaces.yaml"
    _refusal evidence-unreadable 1 "cannot read --evidence-file ev  two spaces.yaml: Permission denied" none -- --run-id R-evidence-unreadable --evidence-file "ev  two spaces.yaml"
    chmod 644 "$E2E_REPO/ev  two spaces.yaml"
  fi
  _long_dir="$(python3 -c 'print("d" * 140)')/$(python3 -c 'print("e" * 140)')"
  mkdir -p "$E2E_REPO/$_long_dir"
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowEvidence\nmetadata: {id: evidence-ac1-test\n' > "$E2E_REPO/$_long_dir/bad.yaml"
  _refusal evidence-bad-yaml-long-path 1 "--evidence-file is not valid YAML: while parsing a flow mapping, expected ',' or '}', but got '<stream end>' (line 4, column 1)" none -- --run-id R-bad-yaml --evidence-file "$_long_dir/bad.yaml"
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowEvidence\nmetadata:\n  id: a\0b\n' > "$E2E_REPO/ev-nul.yaml"
  _refusal evidence-nul 1 "--evidence-file is not valid YAML: unacceptable character #x0000: special characters are not allowed (position 67)" none -- --run-id R-nul --evidence-file ev-nul.yaml
  _evidence_with ev-not-utf8.yaml "$(printf '# \377')"
  _refusal evidence-not-utf8 1 "--evidence-file is not UTF-8" none -- --run-id R-not-utf8 --evidence-file ev-not-utf8.yaml
  _evidence_with ev-alias.yaml '  notes: *p'
  sed -i.bak 's/^  proves:$/  proves: \&p/' "$E2E_REPO/ev-alias.yaml"
  mv "$E2E_REPO/ev-alias.yaml.bak" "$E2E_DIR/ev-alias.bak"
  _refusal evidence-alias 1 "--evidence-file uses a YAML alias" none -- --run-id R-alias --evidence-file ev-alias.yaml
  _evidence_with ev-deep.yaml "  notes: $(python3 -c 'print("[" * 1000 + "x" + "]" * 1000)')"
  _refusal evidence-deep 1 "--evidence-file is nested too deep to read" none -- --run-id R-deep --evidence-file ev-deep.yaml
  _evidence_with ev-date.yaml '  ran_on: 2024-13-01'
  _refusal evidence-bad-date 1 "--evidence-file is not valid YAML: ValueError: month must be in 1..12" none -- --run-id R-bad-date --evidence-file ev-date.yaml
  printf -- '- a\n' > "$E2E_REPO/ev-list.yaml"
  _refusal evidence-list 1 "evidence YAML must be a top-level mapping" none -- --run-id R-list --evidence-file ev-list.yaml
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowEvidence\nmetadata: [a]\n' > "$E2E_REPO/ev-metadata-list.yaml"
  _refusal metadata-list 1 "evidence.metadata must be a mapping" none -- --run-id R-metadata-list --evidence-file ev-metadata-list.yaml
  grep -v '^  id: ' "$E2E_REPO/evidence.yaml" > "$E2E_REPO/ev-no-id.yaml"
  _refusal no-id 1 "evidence.metadata.id is required and must be a string" none -- --run-id R-no-id --evidence-file ev-no-id.yaml
  sed "s/^  id: evidence-ac1-test\$/  id: $(python3 -c 'print("a" * 20000)')/" "$E2E_REPO/evidence.yaml" > "$E2E_REPO/ev-long-id.yaml"
  _refusal id-long 1 "evidence.metadata.id is too long: 20000 characters" none -- --run-id R-id-long --evidence-file ev-long-id.yaml
  _evidence_with ev-output-ref.yaml '  output_ref: "x\nflow-record-evidence.sh: recorded evidence-ac1-test \e[31mFORGED\x9b1m\u2028end"'
  _refusal output-ref 1 "output_ref is $_escaped, but --raw-output is copied to evidence-ac1-test.txt" none -- --run-id R-output-ref --evidence-file ev-output-ref.yaml --raw-output raw.txt
  sed 's/^    - AC1$/    - [AC1]/' "$E2E_REPO/evidence.yaml" > "$E2E_REPO/ev-schema.yaml"
  _refusal schema 1 "evidence does not match schema at \$.evidence.proves[0] (type: \"string\")" none -- --run-id R-schema --evidence-file ev-schema.yaml
  _evidence_with ev-hex.yaml "  size: 0x$(python3 -c 'print("f" * 4000)')"
  _refusal cannot-write 1 "evidence evidence-ac1-test cannot be written as YAML: ValueError" none -- --run-id R-cannot-write --evidence-file ev-hex.yaml
  _refusal raw-absent 1 "--raw-output absent-raw.txt does not exist" none -- --run-id R-raw-absent --evidence-file evidence.yaml --raw-output absent-raw.txt
  mkdir "$E2E_REPO/raw-dir"
  _refusal raw-dir 1 "--raw-output raw-dir is not a regular file" none -- --run-id R-raw-dir --evidence-file evidence.yaml --raw-output raw-dir
  if [ "$(id -u)" != 0 ]; then
    printf 'raw\n' > "$E2E_REPO/raw-000.txt"
    chmod 000 "$E2E_REPO/raw-000.txt"
    _refusal raw-unreadable 1 "cannot read --raw-output raw-000.txt: Permission denied" none -- --run-id R-raw-unreadable --evidence-file evidence.yaml --raw-output raw-000.txt
    chmod 644 "$E2E_REPO/raw-000.txt"
  fi
  ln -s evidence.yaml "$E2E_REPO/ev-link.yaml"
  _refusal evidence-symlink 2 "refusing — --evidence-file ev-link.yaml is a symlink" none -- --run-id R-evidence-symlink --evidence-file ev-link.yaml
  ln -s "$E2E_DIR/outside/file" "$E2E_REPO/raw-link.txt"
  _refusal raw-symlink 2 "refusing — raw-output source raw-link.txt is a symlink" none -- --run-id R-raw-symlink --evidence-file evidence.yaml --raw-output raw-link.txt

  # From here the run directory is made first.
  mkdir -p "$E2E_REPO/.flow/runs"
  ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow/runs/R-run-dir-symlink"
  _refusal run-dir-symlink 2 ".flow/runs/R-run-dir-symlink is a symlink" made -- --run-id R-run-dir-symlink --evidence-file evidence.yaml
  _run_bin bin/flow-record-evidence.sh --run-id R-already-recorded --evidence-file evidence.yaml
  e2e_expect_equal 0 "$E2E_RC" "already-recorded: the first record's exit status"
  _refusal already-recorded 2 "refusing — evidence evidence-ac1-test is already recorded in .flow/runs/R-already-recorded/evidence/evidence-ac1-test.evidence.yaml" made -- --run-id R-already-recorded --evidence-file evidence.yaml
  mkdir -p "$E2E_REPO/.flow/runs/R-copy-orphan/evidence"
  printf 'orphan\n' > "$E2E_REPO/.flow/runs/R-copy-orphan/evidence/evidence-ac1-test.txt"
  _refusal copy-orphan 2 "refusing — a copy .flow/runs/R-copy-orphan/evidence/evidence-ac1-test.txt exists with no sidecar" made -- --run-id R-copy-orphan --evidence-file evidence.yaml --raw-output raw.txt
  mkdir -p "$E2E_REPO/.flow/runs/R-copy-name-dir/evidence/evidence-ac1-test.txt"
  _refusal copy-name-dir 2 "refusing — .flow/runs/R-copy-name-dir/evidence/evidence-ac1-test.txt is in the way, and not a regular file" made -- --run-id R-copy-name-dir --evidence-file evidence.yaml --raw-output raw.txt
  mkdir -p "$E2E_REPO/.flow/runs/R-copy-name-symlink/evidence"
  ln -s "$E2E_DIR/outside/file" "$E2E_REPO/.flow/runs/R-copy-name-symlink/evidence/evidence-ac1-test.txt"
  _refusal copy-name-symlink 2 "refusing — raw-output target .flow/runs/R-copy-name-symlink/evidence/evidence-ac1-test.txt is a symlink" made -- --run-id R-copy-name-symlink --evidence-file evidence.yaml --raw-output raw.txt
  mkdir -p "$E2E_REPO/.flow/runs/R-lock-symlink"
  ln -s "$E2E_DIR/outside/file" "$E2E_REPO/.flow/runs/R-lock-symlink/.lock"
  _refusal lock-symlink 2 "refusing — lockfile .flow/runs/R-lock-symlink/.lock is a symlink" made -- --run-id R-lock-symlink --evidence-file evidence.yaml --raw-output raw.txt
fi

# The files a python3 opens: os gets an O_BINARY flag (a bit no other O_ flag
# of this platform uses), and os.open logs "binary <name>" or "TEXT <name>"
# to $SPY_LOG for each call on a path that is not a directory, by whether it
# asked for it, then opens without the bit. Native Windows opens a file in text mode unless O_BINARY is asked
# for: a copy of "ok\n\x1aFAIL" would be read as "ok" and written as "ok\r\n".
BINARY_SPY_PY='
import os as _o14
_used14 = 0
for _k14, _v14 in list(vars(_o14).items()):
    if _k14.startswith("O_") and isinstance(_v14, int):
        _used14 |= _v14
_bit14 = next(1 << _i14 for _i14 in range(30, 8, -1) if not _used14 & (1 << _i14))
_o14.O_BINARY = _bit14
_real_open14 = _o14.open
def _open14(path, flags, *a, **k):
    try:
        if not _o14.path.isdir(path):
            with open(_o14.environ["SPY_LOG"], "a") as _f14:
                _f14.write("%s %s\n" % ("binary" if flags & _bit14 else "TEXT", _o14.path.basename(str(path))))
    except (OSError, KeyError, TypeError, ValueError):
        pass
    return _real_open14(path, flags & ~_bit14, *a, **k)
_o14.open = _open14
'

if _want binary-opens; then
  _flow_test_begin "every file flow's python3 opens with os.open is opened in binary mode, as native Windows needs (L70)"
  e2e_new binary-opens
  e2e_describe "python3's os module is given an O_BINARY flag and an os.open that logs whether each call asked for it; under it: the recorder with --raw-output, an activity record, a journal append, a verdict record, the judge's evidence bundle, flow-strip-auto-log.sh --apply, and _journal_manifest.read_text"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_yaml
  _sidecar_without_ref
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  cp "$FIXTURES/activity/valid.yaml" "$E2E_REPO/activity.yaml"
  printf '%s\n' '{"verdict":"not_achieved","confidence":0.4,"delta":"unchanged","reason":"x"}' > "$E2E_REPO/verdict.json"
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n\nA decision.\n\n<!-- auto-log: 2026-05-20 10:00 Edit src/search.ts -->\n' > "$E2E_REPO/.decisions/issue-42.md"
  _py_site binary-spy "$BINARY_SPY_PY"
  export SPY_LOG="$E2E_DIR/opens.log"
  _run_bin_site binary-spy bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml --raw-output raw.txt
  e2e_expect_equal 0 "$E2E_RC" "the recorder's exit status"
  _run_bin_site binary-spy bin/flow-record-activity.sh --run-id "$RID" --activity-file activity.yaml
  e2e_expect_equal 0 "$E2E_RC" "the activity writer's exit status"
  _run_bin_site binary-spy bin/journal-append.sh --issue 42 --text entry
  e2e_expect_equal 0 "$E2E_RC" "journal-append.sh's exit status"
  _run_bin_site binary-spy bin/flow-strip-auto-log.sh --apply .decisions
  e2e_expect_equal 0 "$E2E_RC" "flow-strip-auto-log.sh's exit status"
  _saved_pp="${PYTHONPATH:-}"
  export PYTHONPATH="$E2E_DIR/site-binary-spy${_saved_pp:+:$_saved_pp}"
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the bundle's exit status"
  printf 'code: bin/_journal_manifest.py read_text\n' >> "$E2E_ARTIFACT"
  _e2e_exec python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _journal_manifest; _journal_manifest.read_text(sys.argv[2])' "$E2E_ACTIVE_PLUGIN/bin" .decisions/issue-42.md
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
  e2e_expect_equal 0 "$E2E_RC" "_journal_manifest.read_text's exit status"
  export PYTHONPATH="$_saved_pp"
  # After the bundle, which prints the run's last verdict with the time it
  # was recorded.
  _run_bin_site binary-spy bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  e2e_expect_equal 0 "$E2E_RC" "the verdict writer's exit status"
  unset SPY_LOG
  e2e_expect_equal "" "$(grep '^TEXT' "$E2E_DIR/opens.log" | sort -u | tr '\n' ' ')" "the opens that did not ask for binary mode"
  for _name in evidence.yaml raw.txt evidence-ac1-test.txt .lock events.jsonl issue-42.md verdict.json evidence-ac1-test.evidence.yaml; do
    e2e_expect_equal yes "$(grep -qx "binary $_name" "$E2E_DIR/opens.log" && echo yes || echo no)" "$_name was opened in binary mode"
  done
fi

if _want record-evidence-depth-limit; then
  _flow_test_begin "flow-record-evidence.sh --raw-output: evidence nested one level too deep to write is refused with exit 1 before anything is made, under each python3 here (L70)"
  e2e_new record-evidence-depth-limit
  e2e_describe "under each python3 here that has PyYAML, the recorder is run on the fixture sidecar with a list nested N deep under evidence.notes, recorded with --raw-output raw.txt, each time under a new run id; N is searched by halving between 50 and 2000 until the deepest it records and the shallowest it refuses are one apart. The search runs the recorder itself, so it finds the limit wherever the recorder's own calls put it. The deepest is recorded with exit 0; the shallowest is refused with exit 1 as nested too deep, and nothing is made for its run"
  e2e_repo feature/issue-42-e2e
  printf 'raw\n' > "$E2E_REPO/raw.txt"
  mkdir -p "$E2E_DIR/tmp"
  # _depth_record <python3 directory> <label> <depth> <run id>
  _depth_record() {
    grep -v 'output_ref:' "$FIXTURES/evidence/valid.yaml" > "$E2E_REPO/evidence.yaml"
    python3 -c 'import sys; n = int(sys.argv[2]); open(sys.argv[1], "a").write("  notes: " + "[" * n + "x" + "]" * n + "\n")' "$E2E_REPO/evidence.yaml" "$3"
    printf 'python3 %s, a list nested %s deep, run %s\n' "$2" "$3" "$4" >> "$E2E_ARTIFACT"
    _e2e_exec env PATH="$1:$PATH" TMPDIR="$E2E_DIR/tmp" "$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh" --run-id "$4" --evidence-file evidence.yaml --raw-output raw.txt
  }
  _pythons=0; _seen=""
  for _py in "$(command -v python3)" /usr/bin/python3 $(command -v python3.9 python3.10 python3.11 python3.12 python3.13 python3.14 2>/dev/null); do
    [ -x "$_py" ] || continue
    _v=$("$_py" -c 'import platform; print(platform.python_version())' 2>/dev/null) || continue
    case " $_seen " in *" $_v "*) continue ;; esac
    _seen="$_seen $_v"
    HOME="$E2E_HOME" "$_py" -c 'import yaml' 2>/dev/null || continue
    _pythons=$((_pythons + 1))
    mkdir -p "$E2E_DIR/py-$_v"
    ln -sf "$_py" "$E2E_DIR/py-$_v/python3"
    _lo=50; _hi=2000
    _depth_record "$E2E_DIR/py-$_v" "$_v" "$_lo" "R-$_v-$_lo"
    e2e_expect_equal 0 "$E2E_RC" "python3 $_v: the exit status at $_lo deep"
    _depth_record "$E2E_DIR/py-$_v" "$_v" "$_hi" "R-$_v-$_hi"
    e2e_expect_equal 1 "$E2E_RC" "python3 $_v: the exit status at $_hi deep"
    while [ $((_hi - _lo)) -gt 1 ]; do
      _mid=$(((_lo + _hi) / 2))
      _depth_record "$E2E_DIR/py-$_v" "$_v" "$_mid" "R-$_v-$_mid"
      if [ "$E2E_RC" = 0 ]; then _lo=$_mid; else _hi=$_mid; fi
    done
    printf 'python3 %s: the deepest recorded is %d, the shallowest refused %d\n' "$_v" "$_lo" "$_hi" >> "$E2E_ARTIFACT"
    _depth_record "$E2E_DIR/py-$_v" "$_v" "$_lo" "R-$_v-$_lo-again"
    e2e_expect_equal 0 "$E2E_RC" "python3 $_v: the exit status one level short of the limit"
    _depth_record "$E2E_DIR/py-$_v" "$_v" "$_hi" "R-$_v-$_hi-again"
    e2e_expect_equal 1 "$E2E_RC" "python3 $_v: the exit status at the limit"
    e2e_expect_err "is nested too deep"
    e2e_expect_equal absent "$([ -e "$E2E_REPO/.flow/runs/R-$_v-$_hi-again" ] && echo present || echo absent)" "python3 $_v: nothing made for the run refused at the limit"
  done
  e2e_expect_equal yes "$([ "$_pythons" -ge 1 ] && echo yes || echo no)" "at least one python3 with PyYAML ran the search"
fi
