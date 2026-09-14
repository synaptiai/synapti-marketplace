#!/bin/bash
# [flow] PreToolUse hook: refuse a merge while its checks are unfinished.
#
# `/flow:merge` reads statusCheckRollup and will not proceed on a red or
# unfinished pull request. That gate only covers merges that go through the
# command. A `gh pr merge` typed straight into Bash consults nothing, and that
# is how a pull request came to be merged with twelve jobs still queued
# (issue #170).
#
# Two things are refused:
#
#   1. Any `gh pr merge` while a check is queued, running, or failed. The
#      checks are named, so the message says what to wait for.
#
#   2. `--auto` on a base branch with no required status checks. GitHub's
#      auto-merge waits for REQUIRED checks; where none are required it merges
#      at once. Reaching for `--auto` means "wait for CI", and on such a
#      repository it does the opposite of what the person asking for it wants.
#      Requiring branch protection is not this hook's business — issue #170
#      says so explicitly — but neither is letting its absence read as a
#      passing gate.
#
# What is NOT refused: a merge of a fully green pull request, by any route.
# `/flow:merge` on a green PR passes through untouched.
#
# The command is parsed, not matched. `echo "gh pr merge 3"` runs no merge, and
# a hook that reads text rather than commands refuses the bug report that
# describes it — the lesson of issues #167 and #142, whose parser this shares.
#
# Reading text has a cost: a shell variable cannot be expanded. A merge whose
# pull request or repository is `$PR_NUM`, `${REPO}` or `$(...)` is refused, and
# the refusal names that value, so write merge commands with literal values.
# The same goes for anything that changes which pull request gh means without
# changing the merge's words — a `cd` or an exported GH_REPO earlier in the
# command — and for a merge gh is told to run some other way: through
# `bash -c` or `eval`, under a variable command name, or by `gh api` on the
# merge endpoint (#195).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq not available — cannot verify merge readiness. Install jq to proceed." >&2
  exit 2
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "BLOCKED: awk not available — cannot verify merge readiness. Install awk to proceed." >&2
  exit 2
fi

_BD_LIB="$HOOK_DIR/lib/command-parse.sh"
if [ ! -r "$_BD_LIB" ]; then
  echo "BLOCKED: cannot read $_BD_LIB — the command parser is missing, so merge readiness cannot be verified." >&2
  exit 2
fi
# shellcheck source=lib/command-parse.sh
. "$_BD_LIB"

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Cheap reject before any parsing: this hook runs before every Bash call.
# Any case: the GraphQL auto-merge mutation is spelled enablePullRequestAutoMerge.
case "$COMMAND" in *[Mm][Ee][Rr][Gg][Ee]*) ;; *) exit 0 ;; esac

_bd_strip_noncode "$COMMAND"

# --- find every `gh pr merge`, in command position ----------------------------
#
# Three things this has to get right, each of which it got wrong first:
#
#   - gh has its own value-taking options, at the root (`-R`, `--repo`) and on
#     the subcommand (`-t`, `-b`, `-F`, `--match-head-commit`, ...). Skipping a
#     `-x` without also skipping its value made the value look like the pull
#     request selector: `gh --repo owner/repo pr merge 3` was read as merging
#     "owner/repo", so the subcommand never matched and the hook allowed it.
#   - The selector is whatever the merge command says: a number, a branch, or a
#     URL. Dropping the non-numeric ones made the probe resolve the current
#     branch instead, so the hook reported on one pull request while the human
#     merged another.
#   - A command can hold more than one merge. Stopping at the first left the
#     rest unchecked.
#
# The repository is the command's own `--repo` when it carries one, because
# forcing the session's repository onto the probe checks the wrong place.

# Options that consume the following token, at either level — the root, `pr
# merge`, and `api`, whose merge endpoint is checked too.
_bum_takes_value() {
  case "$1" in
    -R|--repo|-t|--subject|-b|--body|-F|--body-file|-A|--author-email|--match-head-commit)
      return 0 ;;
    -X|--method|-f|--raw-field|--field|-H|--header|--input|-q|--jq|--template|--hostname|-p|--preview|--cache)
      return 0 ;;
  esac
  return 1
}

# A value this hook cannot know without running a shell: a variable, or a
# substitution (the segmenter leaves `__BD_SUBST__` where `$(...)` or a backtick
# pair stood). Quoting is gone by this point, so `'$X'` counts too. A pull
# request number and a repository name cannot contain `$`; a branch name can,
# and is refused anyway, because from the text it is indistinguishable from a
# variable. The refusal says to merge such a branch by number.
_bum_unreadable() {
  case "$1" in
    *'$'*|*'`'*|*__BD_SUBST__*) return 0 ;;
  esac
  return 1
}

# A `{…}` left in the value: a documented command template run before its
# placeholders were filled in.
_bum_placeholder() {
  case "$1" in
    *'{'*'}'*) return 0 ;;
  esac
  return 1
}

# The value as the refusal should show it: substitutions spelled as the reader
# wrote them, no control characters (the stderr goes back into a transcript),
# and not so long that the instruction after it is lost.
_bum_show() {
  local v="$1"
  v="${v// __BD_SUBST__ /\$(...)}"
  v="${v//__BD_SUBST__/\$(...)}"
  v="${v//[[:cntrl:]]/?}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  if [ "${#v}" -gt 200 ]; then v="${v:0:200}..."; fi
  printf '%s' "$v"
}

_bum_refuse_unreadable() {   # $1 = what, $2 = value
  echo "BLOCKED: gh pr merge, but the $1 is given as \"$(_bum_show "$2")\", which this hook reads as text and cannot expand." >&2
  echo "Write it literally (e.g. gh pr merge 123 --repo owner/name) so its checks can be verified. A branch whose name contains \$ or a backtick cannot be told from a variable here; merge it by number." >&2
  exit 2
}

_bum_refuse_placeholder() {  # $1 = what, $2 = value
  echo "BLOCKED: gh pr merge, but the $1 is \"$(_bum_show "$2")\", a placeholder that was not filled in." >&2
  echo "Replace it with the real value before running the merge." >&2
  exit 2
}

# Is this token an assignment (NAME=value) rather than a word?
_bum_is_assignment() {
  case "$1" in
    [A-Za-z_]*=*)
      local name="${1%%=*}"
      case "$name" in *[!A-Za-z0-9_]*) return 1 ;; esac
      return 0 ;;
  esac
  return 1
}

MERGE_FOUND=0
MERGE_N=0
MERGE_SEL=()
MERGE_REPO=()
MERGE_HOST=()
MERGE_AUTO=()

# State that one simple command leaves for the ones after it. gh reads GH_REPO
# and GH_HOST from the environment when no --repo is given, and resolves the
# repository from the working directory when neither is — so an `export`, or a
# `cd`, earlier in the same command changes which pull request a later merge
# means, even though the merge's own words are unchanged.
#
# Whether such an assignment reaches the merge is not something text can
# settle: `(export GH_REPO=x); gh pr merge 7` sets it in a subshell that is gone
# by the time gh runs. So an earlier assignment is not used for the probe. It
# only means a merge that does not name its own repository is refused.
CARRY_REPO_SET=0
CARRY_HOST_SET=0
CHDIR=0

# `bash -c 'gh pr merge 9'` and `eval '...'` hide the merge inside one quoted
# word. Expand those first, so the merge is a command like any other.
_bd_expand_interpreter_args

while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  TOK=()
  _rm_tokenise "$SEG"
  n=${#TOK[@]}
  [ "$n" -gt 0 ] || continue

  # Leading assignments, and the first word that is not one: `GH_REPO=x gh ...`
  # sets it for that gh alone; `export GH_REPO=x` or a bare `GH_REPO=x` sets it
  # for what follows.
  first=""
  declared=0
  seg_env_repo=""; seg_env_repo_set=0; seg_env_host=""; seg_env_host_set=0
  for ((i = 0; i < n; i++)); do
    tok="${TOK[i]}"
    if _bum_is_assignment "$tok"; then
      case "$tok" in
        GH_REPO=*) seg_env_repo="${tok#GH_REPO=}"; seg_env_repo_set=1 ;;
        GH_HOST=*) seg_env_host="${tok#GH_HOST=}"; seg_env_host_set=1 ;;
      esac
      continue
    fi
    case "$tok" in
      env) continue ;;
      export|declare|typeset|readonly) declared=1; continue ;;
      -*) [ "$declared" = "1" ] && continue ;;
    esac
    first="$tok"
    break
  done
  case "${first##*/}" in
    cd|pushd|popd) CHDIR=1; continue ;;
  esac
  if [ -z "$first" ]; then
    [ "$seg_env_repo_set" = "1" ] && CARRY_REPO_SET=1
    [ "$seg_env_host_set" = "1" ] && CARRY_HOST_SET=1
    continue
  fi

  # Command position, after tokenising rather than before: `g""h` is one token
  # spelled gh, and the basename compare is case-insensitive because a
  # case-insensitive filesystem will happily run `GH`. A word this hook cannot
  # read (`$GH`, `$(which gh)`) is a candidate too: whatever it expands to, if
  # the words after it are `pr merge`, it is a merge nobody can check.
  matched=0
  for ((c = 0; c < n; c++)); do
    [ "${#TOK[c]}" -le 4096 ] || continue
    base="${TOK[c]##*/}"
    base="${base#\\}"
    base=$(printf '%s' "$base" | tr 'A-Z' 'a-z')
    cmd_var=0
    if [ "$base" != "gh" ]; then
      _bum_is_assignment "${TOK[c]}" && continue
      _bum_unreadable "${TOK[c]}" || continue
      cmd_var=1
    fi

    # Walk the arguments once: positional words, the repository and host if the
    # command names them, whether auto-merge was asked for, and the method an
    # api call uses.
    seg_repo=""; seg_repo_set=0
    seg_host=""
    seg_auto=0
    seg_method=""
    words=()
    i=$((c + 1))
    while [ $i -lt $n ]; do
      tok="${TOK[i]}"
      nxt="${TOK[i+1]:-}"
      case "$tok" in
        --auto|--auto=true|--auto=1|--auto=yes) seg_auto=1; i=$((i + 1)); continue ;;
        --auto=*) i=$((i + 1)); continue ;;          # --auto=false and friends
        --repo=*|-R=*)
          seg_repo="${tok#*=}"; seg_repo_set=1
          # An unquoted `$(...)` joined to the value is split off by the
          # segmenter; the repository is the two together, and the split-off
          # half is consumed here rather than read again as a selector.
          i=$((i + 1))
          [ "$nxt" = "__BD_SUBST__" ] && { seg_repo="$seg_repo$nxt"; i=$((i + 1)); }
          continue ;;
        --method=*) seg_method="${tok#*=}"; i=$((i + 1)); continue ;;
        --hostname=*) seg_host="${tok#*=}"; i=$((i + 1)); continue ;;
        --) i=$((i + 1)); continue ;;
      esac
      if _bum_takes_value "$tok"; then
        case "$tok" in
          -R|--repo)
            seg_repo="$nxt"; seg_repo_set=1
            [ "${TOK[i+2]:-}" = "__BD_SUBST__" ] && { seg_repo="$seg_repo${TOK[i+2]}"; i=$((i + 1)); } ;;
          -X|--method) seg_method="$nxt" ;;
          --hostname) seg_host="$nxt" ;;
        esac
        i=$((i + 2)); continue
      fi
      case "$tok" in
        # gh also takes a short option's value attached: -Rowner/name, -XPUT.
        -R?*) seg_repo="${tok#-R}"; seg_repo_set=1
              i=$((i + 1))
              [ "$nxt" = "__BD_SUBST__" ] && { seg_repo="$seg_repo$nxt"; i=$((i + 1)); }
              continue ;;
        -X?*) seg_method="${tok#-X}"; i=$((i + 1)); continue ;;
        -*) i=$((i + 1)); continue ;;
      esac
      if ! _bd_is_redirection "$tok"; then
        words+=("$tok")
      fi
      i=$((i + 1))
    done

    # `gh pr merge [selector]`, or `gh api` on the merge endpoint.
    kind=""
    sel=""
    api_repo=""
    if [ "${words[0]:-}" = "pr" ] && [ "${words[1]:-}" = "merge" ]; then
      kind=merge
      sel="${words[2]:-}"
      # gh takes one selector. A second word, if it cannot be read, may expand
      # into anything at all — `--repo other/x`, `--auto` — so it is the
      # selector's problem too.
      for ((w = 3; w < ${#words[@]}; w++)); do
        if _bum_unreadable "${words[w]}"; then sel="${words[*]:2}"; break; fi
      done
    elif [ "${words[0]:-}" = "api" ]; then
      ep="${words[1]:-}"
      if [ "$ep" = "graphql" ]; then
        # A merge through GraphQL names the pull request by node id, which the
        # checks lookup cannot take. Refuse it rather than guess.
        for ((t = c + 1; t < n; t++)); do
          case "${TOK[t]}" in
            *mergePullRequest*|*enablePullRequestAutoMerge*)
              echo "BLOCKED: a pull request merge through gh api graphql. Its checks cannot be verified from here." >&2
              echo "Use gh pr merge <number> --repo owner/name instead." >&2
              exit 2 ;;
          esac
        done
        continue
      fi
      case "$ep" in *merge*) ;; *) continue ;; esac
      if _bum_unreadable "$ep"; then _bum_refuse_unreadable "api endpoint" "$ep"; fi
      if _bum_unreadable "$seg_method"; then _bum_refuse_unreadable "api method" "$seg_method"; fi
      [ "$(printf '%s' "$seg_method" | tr 'a-z' 'A-Z')" = "PUT" ] || continue
      ep="${ep#/}"; ep="${ep%%\?*}"; ep="${ep%/}"
      case "$ep" in
        repos/*/*/pulls/*/merge) ;;
        *) continue ;;
      esac
      rest="${ep#repos/}"
      api_owner="${rest%%/*}"; rest="${rest#*/}"
      api_name="${rest%%/*}"; rest="${rest#*/pulls/}"
      sel="${rest%/merge}"
      case "$sel" in ''|*[!0-9]*) continue ;; esac
      # gh fills {owner} and {repo} from the environment or the directory, the
      # same way it resolves a merge without --repo.
      if [ "$api_owner" != "{owner}" ] && [ "$api_name" != "{repo}" ]; then
        api_repo="$api_owner/$api_name"
      fi
      kind=api
    else
      continue
    fi
    matched=1
    break
  done
  [ "$matched" = "1" ] || continue

  if [ "$cmd_var" = "1" ]; then
    _bum_refuse_unreadable "gh command" "${TOK[c]}"
  fi

  # Which repository gh will use: --repo, then an api endpoint's own, then
  # GH_REPO on this very command.
  if [ "$kind" = "api" ] && [ -n "$api_repo" ]; then
    seg_repo="$api_repo"; seg_repo_set=1
  fi
  if [ "$seg_repo_set" = "0" ] && [ "$seg_env_repo_set" = "1" ]; then
    seg_repo="$seg_env_repo"; seg_repo_set=1
  fi
  [ -z "$seg_host" ] && seg_host="$seg_env_host"

  # A value this hook cannot read is named, before anything else is said about
  # the merge and before any probe: `"$REPO"` reaches a lookup as the literal
  # string `$REPO`, the lookup fails, and the refusal used to blame the checks.
  _bum_unreadable "$sel" && _bum_refuse_unreadable "pull request" "$sel"
  _bum_unreadable "$seg_repo" && _bum_refuse_unreadable "repository" "$seg_repo"
  _bum_unreadable "$seg_host" && _bum_refuse_unreadable "GitHub host" "$seg_host"
  _bum_placeholder "$sel" && _bum_refuse_placeholder "pull request" "$sel"
  _bum_placeholder "$seg_repo" && _bum_refuse_placeholder "repository" "$seg_repo"

  # A selector supplied from somewhere this hook cannot read — xargs, or a
  # substitution the segmenter replaced with a placeholder — is not "no
  # selector, so the current branch". It is "unknown", and a gate that cannot
  # tell which pull request is being merged must not open.
  case "$SEG" in
    *xargs*|*__BD_SUBST__*)
      if [ -z "$sel" ]; then
        echo "BLOCKED: a gh pr merge whose pull request comes from somewhere this hook cannot read (xargs, or a command substitution)." >&2
        echo "Name the pull request explicitly so its checks can be verified." >&2
        exit 2
      fi
      ;;
  esac

  # After a `cd`, gh resolves the repository — and, with no selector, the
  # branch — from a directory this hook is not in. Unless the merge names its
  # repository, the probe would check a pull request other than the one merged.
  case "$sel" in http://*|https://*) sel_is_url=1 ;; *) sel_is_url=0 ;; esac
  if [ "$CHDIR" = "1" ] && [ "$seg_repo_set" = "0" ] && [ "$sel_is_url" = "0" ]; then
    echo "BLOCKED: gh pr merge after a cd in the same command. gh will resolve the repository from that directory, which this hook cannot see." >&2
    echo "Name it: gh pr merge <number> --repo owner/name." >&2
    exit 2
  fi
  if [ "$CARRY_REPO_SET" = "1" ] && [ "$seg_repo_set" = "0" ] && [ "$sel_is_url" = "0" ]; then
    echo "BLOCKED: gh pr merge after GH_REPO was set earlier in the same command. Whether it reaches the merge cannot be read from the text." >&2
    echo "Name the repository on the merge itself: gh pr merge <number> --repo owner/name." >&2
    exit 2
  fi
  if [ "$CARRY_HOST_SET" = "1" ] && [ -z "$seg_host" ]; then
    echo "BLOCKED: gh pr merge after GH_HOST was set earlier in the same command. Whether it reaches the merge cannot be read from the text." >&2
    echo "Set it on the merge itself (GH_HOST=host gh pr merge ...) or run the two separately." >&2
    exit 2
  fi

  MERGE_FOUND=1
  MERGE_SEL[$MERGE_N]="$sel"
  MERGE_REPO[$MERGE_N]="$seg_repo"
  MERGE_HOST[$MERGE_N]="$seg_host"
  MERGE_AUTO[$MERGE_N]="$seg_auto"
  MERGE_N=$((MERGE_N + 1))
done < <(_bd_segments "$BD_CODE")

[ "$MERGE_FOUND" = "1" ] || exit 0

# The probe asks the host the merge will go to. RHOST is set per merge below.
_bum_gh() {
  if [ -n "${RHOST:-}" ]; then
    GH_HOST="$RHOST" gh "$@"
  else
    gh "$@"
  fi
}

if ! command -v gh >/dev/null 2>&1; then
  echo "BLOCKED: gh pr merge, but the gh CLI is not on PATH — merge readiness cannot be checked." >&2
  exit 2
fi

# Only consulted when the command names no repository of its own.
SESSION_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)

for ((M = 0; M < MERGE_N; M++)); do
  SEL="${MERGE_SEL[M]}"
  RREPO="${MERGE_REPO[M]}"
  RHOST="${MERGE_HOST[M]}"
  AUTO="${MERGE_AUTO[M]}"

  # Build the same view the merge itself will resolve. With no selector and no
  # --repo, gh resolves the current branch — so the probe must do that too,
  # which means passing neither. `gh pr view --repo X` with no selector is an
  # error, so the two travel together.
  VIEW=(pr view)
  [ -n "$SEL" ] && VIEW+=("$SEL")
  # A URL names its own repository; pairing it with --repo is redundant at best
  # and a conflict at worst.
  case "$SEL" in
    http://*|https://*) SEL_IS_URL=1 ;;
    *) SEL_IS_URL=0 ;;
  esac
  if [ "$SEL_IS_URL" = "1" ]; then
    :
  elif [ -n "$RREPO" ]; then
    VIEW+=(--repo "$RREPO")
  elif [ -n "$SEL" ] && [ -n "$SESSION_REPO" ]; then
    VIEW+=(--repo "$SESSION_REPO")
  fi
  VIEW+=(--json "number,baseRefName,statusCheckRollup")

  ROLLUP=$(_bum_gh "${VIEW[@]}" 2>/dev/null); GH_RC=$?
  if [ "$GH_RC" -ne 0 ] || [ -z "$ROLLUP" ]; then
    echo "BLOCKED: gh pr merge${SEL:+ $SEL}, but its checks could not be read (gh exit $GH_RC). A gate that cannot see must not open." >&2
    exit 2
  fi
  # gh can exit 0 having printed something that is not the object expected —
  # an error body, a truncated stream. Emptiness is not the only way to fail.
  # Entries must be objects too. A rollup of `["ci"]` satisfies "is an array"
          # and then kills the classifiers below with a type error, leaving both
          # empty — which reads as "nothing wrong".
  if ! printf '%s' "$ROLLUP" | jq -e 'type == "object" and has("number") and (.statusCheckRollup | type == "array") and (all(.statusCheckRollup[]; type == "object"))' >/dev/null 2>&1; then
    echo "BLOCKED: gh pr merge${SEL:+ $SEL}, but the check rollup did not parse as expected. Refusing rather than guessing." >&2
    exit 2
  fi

  PR_NUMBER=$(printf '%s' "$ROLLUP" | jq -r '.number')
  BASE=$(printf '%s' "$ROLLUP" | jq -r '.baseRefName // empty')
  if [ -z "$BASE" ]; then
    echo "BLOCKED: the base branch of PR #$PR_NUMBER could not be read, so its required checks cannot be established." >&2
    exit 2
  fi

  # An allow-list, not a deny-list. A conclusion this does not recognise —
  # ACTION_REQUIRED and STALE were the two that got through, and GitHub can add
  # more — must land in "not passing", never in "fine". Same for an entry whose
  # __typename is missing.
  # Each classifier's exit status is checked. An empty result must mean "jq
  # looked and found none", never "jq fell over". That distinction is the whole
  # difference between a gate and a formality.
  UNFINISHED=$(printf '%s' "$ROLLUP" | jq -r '
    [ .statusCheckRollup[]
      | if .__typename == "CheckRun"
        then select(.status != "COMPLETED") | "\(.name // "check") [\(.status // "unknown" | ascii_downcase)]"
        elif .__typename == "StatusContext"
        then select(.state == "PENDING" or .state == "EXPECTED") | "\(.context // "status") [pending]"
        else "\(.name // .context // "unrecognised check") [unknown shape]"
        end ]
    | join(", ")') || {
    echo "BLOCKED: the check rollup for PR #$PR_NUMBER could not be classified. Refusing rather than guessing." >&2
    exit 2
  }

  NOT_PASSING=$(printf '%s' "$ROLLUP" | jq -r '
    [ .statusCheckRollup[]
      | if .__typename == "CheckRun"
        then select(.status == "COMPLETED")
             | select((.conclusion // "") | IN("SUCCESS","SKIPPED","NEUTRAL") | not)
             | "\(.name // "check") [\(.conclusion // "no conclusion" | ascii_downcase)]"
        elif .__typename == "StatusContext"
        then select(.state != "PENDING" and .state != "EXPECTED" and .state != "SUCCESS")
             | "\(.context // "status") [\(.state // "unknown" | ascii_downcase)]"
        else empty
        end ]
    | join(", ")') || {
    echo "BLOCKED: the check rollup for PR #$PR_NUMBER could not be classified. Refusing rather than guessing." >&2
    exit 2
  }

  TOTAL=$(printf '%s' "$ROLLUP" | jq -r '.statusCheckRollup | length') || TOTAL=""
  case "$TOTAL" in
    ''|*[!0-9]*)
      echo "BLOCKED: could not count the checks on PR #$PR_NUMBER." >&2
      exit 2 ;;
  esac

  if [ -n "$UNFINISHED" ]; then
    echo "BLOCKED: PR #$PR_NUMBER has checks that have not finished: $UNFINISHED" >&2
    echo "Wait for them (gh pr checks $PR_NUMBER --watch) and merge after they report." >&2
    exit 2
  fi
  if [ -n "$NOT_PASSING" ]; then
    echo "BLOCKED: PR #$PR_NUMBER has checks that did not pass: $NOT_PASSING" >&2
    exit 2
  fi

  # What does this base branch require? Both branch protection and rulesets,
  # because asking only the first reports "none required" on a repository that
  # requires plenty. The endpoints are also consulted for the empty-rollup case
  # below, so the probe runs whether or not --auto was asked for.
  # `gh api` exits 1 for a 404 and for a 403 alike, and the difference matters:
  # a 404 means this branch genuinely requires nothing, a 403 means we are not
  # allowed to know. Reading the status line separates them. Anything else —
  # a network failure, a rate limit — is also "cannot tell".
  _bum_required() {   # $1 = endpoint, $2 = jq filter. Sets REQ_OUT, REQ_STATE.
    local body errf rc
    errf=$(mktemp -t flow-bum-err.XXXXXX 2>/dev/null) || { REQ_STATE=unknown; REQ_OUT=""; return; }
    body=$(_bum_gh api "$1" 2>"$errf"); rc=$?
    if [ "$rc" -eq 0 ]; then
      REQ_STATE="read"
      REQ_OUT=$(printf '%s' "$body" | jq -r "$2" 2>/dev/null || true)
    elif grep -q '(HTTP 404)' "$errf" 2>/dev/null; then
      REQ_STATE=absent          # definitively nothing configured here
      REQ_OUT=""
    else
      REQ_STATE=unknown
      REQ_OUT=""
    fi
    rm -f "$errf"
  }

  PROBE_REPO="${RREPO:-$SESSION_REPO}"
  REQUIRED=""
  REQ_READABLE=0
  if [ -n "$PROBE_REPO" ]; then
    _bum_required "repos/$PROBE_REPO/branches/$BASE/protection/required_status_checks" \
      '[(.contexts[]?), (.checks[]?.context)] | unique | join(", ")'
    [ "$REQ_STATE" != "unknown" ] && REQ_READABLE=1
    REQUIRED="$REQ_OUT"
    if [ -z "$REQUIRED" ]; then
      _bum_required "repos/$PROBE_REPO/rules/branches/$BASE" \
        '[ .[]? | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context ] | join(", ")'
      [ "$REQ_STATE" != "unknown" ] && REQ_READABLE=1
      REQUIRED="$REQ_OUT"
    fi
  fi

  # An empty rollup is "no checks" on a repository with no CI, and "not
  # reported yet" in the seconds after a push. Where the base requires checks,
  # the second reading is the one that matters.
  if [ "$TOTAL" = "0" ]; then
    if [ -n "$REQUIRED" ]; then
      echo "BLOCKED: PR #$PR_NUMBER reports no checks yet, but '$BASE' requires: $REQUIRED" >&2
      echo "They have not been created on this commit. Wait for them to appear." >&2
      exit 2
    fi
    # An empty rollup means "no CI here" on a repository with none, and "not
    # reported yet" in the seconds after a push — which is the window this hook
    # was written for. Telling them apart depends on knowing what the base
    # requires, so when that could not be read, neither reading is available.
    if [ "$REQ_READABLE" = "0" ]; then
      echo "BLOCKED: PR #$PR_NUMBER reports no checks, and whether '$BASE' requires any could not be read." >&2
      echo "No checks yet and no checks at all look identical from here. Re-run once the requirements are readable, or merge deliberately." >&2
      exit 2
    fi
  fi

  if [ "$AUTO" = "1" ] && [ -z "$REQUIRED" ]; then
    if [ "$REQ_READABLE" = "0" ]; then
      echo "BLOCKED: --auto on PR #$PR_NUMBER, but whether '$BASE' requires any checks could not be read (no access, or the request failed)." >&2
      echo "Auto-merge waits only for required checks, so this cannot be established as a wait. Merge without --auto once you are satisfied." >&2
    else
      echo "BLOCKED: --auto on PR #$PR_NUMBER, but '$BASE' requires no status checks." >&2
      echo "Auto-merge waits for REQUIRED checks. With none required it merges immediately, which is the opposite of what --auto is usually reached for." >&2
      if [ "$TOTAL" = "0" ]; then
        echo "This pull request has no checks at all, so there is nothing to wait for." >&2
      else
        echo "Every check on this PR has already passed ($TOTAL of $TOTAL), so merge without --auto if that is what you want." >&2
      fi
    fi
    exit 2
  fi
done

