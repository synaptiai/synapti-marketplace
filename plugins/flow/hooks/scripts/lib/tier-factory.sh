# shellcheck shell=bash
# [flow] lib/tier-factory.sh — the flow factory's own rules for Bash commands,
# sourced by hooks/scripts/tier-gate.sh.
#
# tier-gate.sh sources this file only in a factory (a FLOW_FACTORY_JOB,
# _DIRECTIVE, _IO or _MAIN variable in its environment, or the directory
# <main checkout>/<runtime dir>/factory for the command's repository), and
# only for a payload that names flow-factory, _flow_factory or /factory. It
# does so before it needs jq, before it reads the command, and before any
# ask, breadcrumb or approval record is written.
#
# The contract with tier-gate.sh:
#   _tg_factory_rules is called with no arguments. INPUT holds the raw hook
#   payload (it may not be valid JSON, and jq may be missing); SCRIPT_DIR is
#   hooks/scripts and PLUGIN_ROOT the plugin's root.
#   To leave the decision to the rest of tier-gate.sh it returns.
#   To decide, it prints one PreToolUse decision and exits 0. `_tg_deny
#   <reason>` prints a deny without jq and exits; a deny is the answer for
#   the whole command, whatever else the command does.
#
# The rules, in the order they are checked (every deny comes before any ask):
#
#   1. A worker session (FLOW_FACTORY_JOB or FLOW_FACTORY_DIRECTIVE set in
#      this hook's own environment): a command whose text names flow-factory.sh
#      or _flow_factory.py is allowed only when the whole text, blanks at
#      either end aside, is `[<plain path>/]flow-factory.sh context --mode` or
#      `[<plain path>/]flow-factory.sh await <qid> [--max-seconds <digits>]`.
#      Anything else naming either file is denied: a chain, a substitution, a
#      redirection or a line end fails the match.
#   2. Any session: a command naming the absolute factory directory is denied.
#      The directory is <FLOW_FACTORY_MAIN>/<runtime dir>/factory when that
#      variable is set, else <main checkout of the payload's cwd>/<runtime
#      dir>/factory; it counts only when it exists. Both its spelling and its
#      physical path are matched, and the name must end there (a folder named
#      factory2 is another folder). An absolute path in the command that is
#      in that folder by identity (device and inode: a link, a `..`, another
#      case on a volume that ignores case) counts too.
#   3. Any session, with flow.factory.enabled true (user and plugin settings
#      only): `gh issue comment`, `gh pr comment` and `gh api` to a comments or
#      reviews endpoint, in a command that names /flow-factory, are denied, so
#      a session cannot post a person command as the person.
#   4. Other sessions: a call of a person subcommand (the Person group of
#      `flow-factory.sh usage`; answer only with --text or --text=) is found
#      by program words, after env, nohup, timeout and the other wrappers,
#      inside bash -c and sh -c, as `python3 <path>/_flow_factory.py`, and
#      through a variable naming the script, in every command of a chain;
#      an interpreter's options are read as it reads them (bash -o pipefail,
#      python3 -W ignore, python3 -m _flow_factory). A person call that is
#      not the whole command (in a chain, beside another command, in a
#      substitution, or after an assignment or a wrapper's -C, -D or --chdir)
#      is denied with the terminal text below in every mode: what an ask
#      would show could differ from what runs.
#      Otherwise, with permission_mode "default" it asks, showing the whole command:
#      for confirm, the stored literal from the read-only `status --intent`
#      of this plugin's own bin/flow-factory.sh (never the path the command
#      names); for approve-spec, the spec hash, the head and the spec file;
#      for answer, the text. In any other mode, or with no mode, it denies
#      with `run it in a terminal outside Claude Code: <command>`; so does a
#      confirm whose lookup fails, and a subcommand word that is a variable.
#   Without jq, or with a payload jq cannot parse, the command is judged by
#   its text: in a worker as in rule 1; elsewhere a text naming either file
#   is denied with the terminal text unless the whole text is
#   `[<plain path>/]flow-factory.sh` and an untiered subcommand (status,
#   next, wait, question, probe, answer with no word starting --t) followed
#   by plain words, with no quote, backslash or $ anywhere. Rule 3 then
#   counts the factory as enabled, since the setting cannot be read either.

# The person subcommands, in the order `flow-factory.sh usage` prints its
# Person group. answer is asked about only with --text.
_TF_PERSON="answer approve-spec confirm feedback rework retry reject cancel rebuild"

# The deny text for a person subcommand outside default mode (design
# person_channels L31).
_tf_terminal() { printf 'run it in a terminal outside Claude Code: %s' "$1"; }

# _tf_names_file <text> — the text names flow-factory.sh or _flow_factory.py,
# or runs the engine as a module (python3 -m _flow_factory, -m_flow_factory,
# -Bm _flow_factory).
_tf_names_file() {
  case "$1" in *flow-factory.sh*|*_flow_factory.py*) return 0 ;; esac
  local re='(^|[^A-Za-z0-9_-])-[A-Za-z]*m[[:space:]]*_flow_factory([^A-Za-z0-9_.]|$)'
  [[ $1 =~ $re ]]
}

# _tf_read — the command (TF_CMD), the permission mode (TF_MODE, empty when
# the payload has none), the cwd (TF_CWD) and TF_JQ=1 when jq read the
# payload. Otherwise TF_RAW holds the payload text from the command key on.
_tf_read() {
  TF_JQ=0; TF_CMD=""; TF_MODE=""; TF_CWD=""; TF_RAW=""
  local ev
  if command -v jq >/dev/null 2>&1 \
     && ev=$(printf '%s' "$INPUT" | jq -r '@sh "TF_CMD=\(.tool_input.command // "") TF_MODE=\(.permission_mode // "" | strings) TF_CWD=\(.cwd // "" | strings)"' 2>/dev/null) \
     && [ -n "$ev" ]; then
    eval "$ev" && TF_JQ=1 && return 0
    TF_CMD=""; TF_MODE=""; TF_CWD=""
  fi
  case "$INPUT" in *'"command"'*) TF_RAW="${INPUT#*\"command\"}" ;; esac
}

# _tf_raw_value — without jq, TF_VAL is the command's JSON string when it holds
# no backslash (so it reads as written) and the payload has one command key.
_tf_raw_value() {
  local v="$TF_RAW" rest
  rest="${INPUT#*\"command\"}"
  case "$rest" in *'"command"'*) return 1 ;; esac
  v="${v#"${v%%[![:space:]]*}"}"
  case "$v" in :*) v="${v#:}" ;; *) return 1 ;; esac
  v="${v#"${v%%[![:space:]]*}"}"
  case "$v" in \"*) v="${v#\"}" ;; *) return 1 ;; esac
  case "$v" in *\"*) ;; *) return 1 ;; esac
  TF_VAL="${v%%\"*}"
  case "$TF_VAL" in *\\*) return 1 ;; esac
  return 0
}

# _tf_worker_form <text> — the whole text is one of the two worker forms.
_tf_worker_form() {
  local nl=$'\n' tab=$'\t'
  local path="[^][ ${tab}${nl};&|\$'\"\`<>()\\\\]*/"
  local re="^[ ${tab}]*(${path})?flow-factory\\.sh[ ${tab}]+(context[ ${tab}]+--mode|await[ ${tab}]+[A-Za-z0-9._-]+([ ${tab}]+--max-seconds[ ${tab}]+[0-9]+)?)[ ${tab}]*\$"
  [[ $1 =~ $re ]]
}

# _tf_untiered_form <text> — the jq-free allow form outside a worker: the
# whole text is `[<plain path>/]flow-factory.sh <status|next|wait|question|
# probe|answer>` and plain words, with no quote, backslash or $ anywhere, and
# for answer no word starting --t (--text, or a prefix of it).
_tf_untiered_form() {
  local nl=$'\n' tab=$'\t' cr=$'\r'
  local bad="][ ${tab}${nl}${cr};&|\$'\"\`<>(){}\\\\*?#~!"
  local re="^[ ${tab}]*([^${bad}]*/)?flow-factory\\.sh[ ${tab}]+(status|next|wait|question|probe|answer)(([ ${tab}]+[^${bad}]+)*)[ ${tab}]*\$"
  [[ $1 =~ $re ]] || return 1
  if [ "${BASH_REMATCH[2]}" = answer ]; then
    local args=" ${BASH_REMATCH[3]//$tab/ }"
    case "$args" in *" --t"*) return 1 ;; esac
  fi
  return 0
}

# _tf_factory_dir — TF_FDIRS: the factory directory's spellings, one per
# line; 1 when it cannot be resolved or does not exist.
_tf_factory_dir() {
  local main cwd common rt d p
  TF_FDIRS=""; TF_FDIR=""
  if [ -n "${FLOW_FACTORY_MAIN:-}" ]; then
    main="$FLOW_FACTORY_MAIN"
  else
    cwd="$TF_CWD"
    [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
    common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    main=$(dirname -- "$common") || return 1
  fi
  case "$main" in /*) ;; *) return 1 ;; esac
  while [ "$main" != / ] && [ "${main%/}" != "$main" ]; do main="${main%/}"; done
  [ -d "$main" ] || return 1
  rt=$(cd "$main" 2>/dev/null && env -u PYTHONPATH "$PLUGIN_ROOT/bin/flow-runtime-dir.sh" 2>/dev/null) || return 1
  [ -n "$rt" ] || return 1
  d="$main/$rt/factory"
  [ -d "$d" ] || return 1
  p=$(cd -P "$d" 2>/dev/null && pwd -P) || p="$d"
  TF_FDIR="$d"
  TF_FDIRS="$d
$p"
  # macOS reaches /var, /tmp and /etc both as themselves and under /private.
  case "$p" in /private/*) TF_FDIRS="$TF_FDIRS
${p#/private}" ;; esac
  case "$d" in /var/*|/tmp/*|/etc/*) TF_FDIRS="$TF_FDIRS
/private$d" ;; esac
  return 0
}

# _tf_norm <path> — the absolute path with `.`, `..` and repeated slashes
# applied to the text (as factory-state-guard.sh's norm does).
_tf_norm() {
  local IFS=/ part out=() r="" parts f=0
  case "$-" in *f*) f=1 ;; esac
  set -f
  parts=($1)
  [ "$f" = 1 ] || set +f
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      ''|.) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  for part in ${out[@]+"${out[@]}"}; do r="$r/$part"; done
  TF_NORMED="${r:-/}"
}

# _tf_is_fdir <path> — the path, or a folder above it, is the factory
# directory itself: the same device and inode (bash's -ef), so another
# spelling (a link, a `..`, another case on a volume that ignores case)
# counts.
_tf_is_fdir() {
  local p="$1"
  while [ -n "$p" ] && [ "$p" != / ]; do
    if [ -e "$p" ] && [ "$p" -ef "$TF_FDIR" ]; then return 0; fi
    p="${p%/*}"
  done
  return 1
}

# _tf_names_dir <text> — the text names a spelling of the factory directory
# whose name ends there, or an absolute path (a word of the text, split at
# blanks, quotes, `=`, `:` and the shell's operators) that is in the factory
# directory by identity.
_tf_names_dir() {
  local s t after w TF_SETF=0
  case "$-" in *f*) TF_SETF=1 ;; esac
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    t="$1"
    while :; do
      case "$t" in *"$s"*) ;; *) break ;; esac
      after="${t#*"$s"}"
      case "${after:0:1}" in
        [A-Za-z0-9._-]) t="$after" ;;
        *) TF_DIR_HIT="$s"; return 0 ;;
      esac
    done
  done <<TF_DIRS_EOF
$TF_FDIRS
TF_DIRS_EOF
  [ -n "$TF_FDIR" ] || return 1
  local IFS=$' \t\n\r;&|<>()`\'"=:{},' words
  # The words without pathname expansion.
  set -f
  words=($1)
  case "$TF_SETF" in 1) ;; *) set +f ;; esac
  for w in ${words[@]+"${words[@]}"}; do
    case "$w" in /*) ;; *) continue ;; esac
    # Longer than PATH_MAX, it cannot be opened.
    [ "${#w}" -le 4096 ] || continue
    _tf_norm "$w"
    if _tf_is_fdir "$w" || _tf_is_fdir "$TF_NORMED"; then
      TF_DIR_HIT="$TF_FDIR"
      return 0
    fi
  done
  return 1
}

# _tf_text_person <text> — the reading of a command the parser could not
# split: a person subcommand word, and for answer also --text.
_tf_text_person() {
  local w re words=""
  for w in $_TF_PERSON; do [ "$w" = answer ] || words="$words${words:+|}$w"; done
  re="(^|[^A-Za-z0-9_-])($words)([^A-Za-z0-9_-]|\$)"
  [[ $1 =~ $re ]] && return 0
  re='(^|[^A-Za-z0-9_-])answer([^A-Za-z0-9_-]|$)'
  if [[ $1 =~ $re ]]; then
    case "$1" in *--text*) return 0 ;; esac
  fi
  return 1
}

# _tf_text_post <text> — the jq-free reading of a comment post.
_tf_text_post() {
  local re='(^|[^A-Za-z0-9_-])gh[^A-Za-z0-9_-].*((issue|pr)[[:space:]]+comment|/(comments|reviews)([^A-Za-z0-9_-]|$))'
  [[ $1 =~ $re ]]
}

# _tf_factory_enabled — flow.factory.enabled from the user and plugin settings
# (the project's own files could come with a pull request). Without jq the
# setting cannot be read (cascade-resolve.sh then prints the default), and a
# value that cannot be read counts as enabled.
_tf_factory_enabled() {
  local cwd="$TF_CWD" v
  command -v jq >/dev/null 2>&1 || return 0
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
  v=$(cd "$cwd" 2>/dev/null && "$PLUGIN_ROOT/bin/cascade-resolve.sh" --no-repo-settings --default false '.flow.factory.enabled' 2>/dev/null) || return 0
  [ "$v" = true ]
}

_tf_load_parser() {
  local f
  [ -r "$SCRIPT_DIR/lib/command-parse.sh" ] || return 1
  # shellcheck source=command-parse.sh
  . "$SCRIPT_DIR/lib/command-parse.sh" 2>/dev/null
  for f in _bd_strip_noncode _bd_expand_interpreter_args _bd_segments _bd_words _bd_command_word _bd_is_language _bd_is_shell; do
    declare -F "$f" >/dev/null || return 1
  done
}

# _tf_is_python <name> — python followed by a version (python3.12), which
# command-parse.sh's list of languages does not name.
_tf_is_python() {
  [[ $1 =~ ^python[0-9][0-9.]*$ ]]
}

# The words _bd_command_word may stop at after a wrapper (env, nohup,
# timeout, ...): the factory's scripts, gh, an interpreter, a variable.
_tf_target() {
  local b="${1##*/}"
  case "$b" in flow-factory.sh|_flow_factory.py|gh) return 0 ;; esac
  case "$1" in *'$'*) return 0 ;; esac
  _bd_is_language "$b" && return 0
  _bd_is_shell "$b" && return 0
  _tf_is_python "$b" && return 0
  return 1
}

# _tf_opt <index> <name> — TF_OPT: the value of --<name> v or --<name>=v
# among TOK[index..]; 1 when absent.
_tf_opt() {
  local k
  for ((k = $1; k < ${#TOK[@]}; k++)); do
    case "${TOK[k]}" in
      "--$2") TF_OPT="${TOK[k+1]:-}"; return 0 ;;
      "--$2="*) TF_OPT="${TOK[k]#--"$2"=}"; return 0 ;;
    esac
  done
  return 1
}

# _tf_call <index> — TOK[index] is the subcommand word of a factory call;
# a person call is added to TF_CALLS as "<subcommand>\t<detail>". A person
# call in a segment that changes the directory or the environment first
# (TF_SEGPRE) sets TF_SHIFTED.
_tf_call() {
  local before=${#TF_CALLS[@]}
  _tf_call_add "$1"
  if [ "${#TF_CALLS[@]}" -gt "$before" ] && [ "$TF_SEGPRE" = 1 ]; then TF_SHIFTED=1; fi
  return 0
}

_tf_call_add() {
  local j="$1" s="${TOK[$1]:-}" first
  [ -n "$s" ] || return 0
  if [ "${TOKE[j]:-0}" = 1 ] || [[ "$s" == *'$'* ]]; then
    TF_CALLS+=("unread	"); return 0
  fi
  first="${TOK[j+1]:-}"
  case "$s" in
    answer)
      _tf_opt "$((j + 1))" text || return 0
      TF_CALLS+=("answer	answer $first, text: $TF_OPT") ;;
    confirm)
      TF_CALLS+=("confirm	$first") ;;
    approve-spec)
      local h="none" hd="none"
      _tf_opt "$((j + 1))" spec-hash && h="$TF_OPT"
      _tf_opt "$((j + 1))" head && hd="$TF_OPT"
      TF_CALLS+=("approve-spec	approve-spec $first: spec_hash: $h; head: $hd; spec file: none recorded") ;;
    *)
      case " $_TF_PERSON " in *" $s "*) TF_CALLS+=("$s	") ;; esac ;;
  esac
}

# _tf_gh_post <index> — TOK[index] is gh; 0 when it posts a comment or a review.
_tf_gh_post() {
  local k=$(($1 + 1)) n=${#TOK[@]}
  while [ "$k" -lt "$n" ]; do
    case "${TOK[k]}" in
      -R|--repo) k=$((k + 2)) ;;
      -*) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  case "${TOK[k]:-} ${TOK[k+1]:-}" in "issue comment"|"pr comment") return 0 ;; esac
  [ "${TOK[k]:-}" = api ] || return 1
  for ((k = k + 1; k < n; k++)); do
    [[ "${TOK[k]}" =~ (^|/)(comments|reviews)(/|\?|$) ]] && return 0
  done
  return 1
}

# _tf_interp <index> — TOK[index] is a shell or a language. Its options are
# read as it reads them, so that an option's value is not taken for the
# script: for a shell as _bd_shell_reads_stdin does (-o, -O, +o, +O, also at
# the end of a bundle, --rcfile and --init-file take the next word); for
# python as block-secrets.sh's _inline_scripts does (-W, -X and -Q take the
# next word unless the value is attached, --check-hash-based-pycs takes the
# next word, -m ends the options with the module). TF_IK is then carrier
# (a -c script, read as segments of its own), call (TF_IJ is the index of
# the subcommand word: a script named flow-factory.sh or _flow_factory.py,
# or the module _flow_factory), or none.
_tf_interp() {
  local k=$(($1 + 1)) n=${#TOK[@]} w rest c py=0
  TF_IK=none; TF_IJ=0
  case "$2" in python|python[0-9]*) py=1 ;; esac
  while [ "$k" -lt "$n" ]; do
    w="${TOK[k]}"
    case "$w" in
      --) k=$((k + 1)); break ;;
      -|''|[!-+]*) break ;;
    esac
    if [ "$py" = 1 ]; then
      case "$w" in
        +*) break ;;
        --check-hash-based-pycs) k=$((k + 2)); continue ;;
        --*) k=$((k + 1)); continue ;;
      esac
      rest="${w#-}"
      while [ -n "$rest" ]; do
        c="${rest:0:1}"; rest="${rest:1}"
        case "$c" in
          c) TF_IK=carrier; return 0 ;;
          m)
            if [ -z "$rest" ]; then k=$((k + 1)); rest="${TOK[k]:-}"; fi
            if [ "$rest" = _flow_factory ]; then TF_IK=call; TF_IJ=$((k + 1)); fi
            return 0 ;;
          [WXQ]) [ -n "$rest" ] || k=$((k + 1)); rest="" ;;
        esac
      done
      k=$((k + 1))
      continue
    fi
    case "$w" in
      --rcfile|--init-file) k=$((k + 2)) ;;
      --*) k=$((k + 1)) ;;
      [-+]*c*) TF_IK=carrier; return 0 ;;
      [-+]*[oO]*) k=$((k + 2)) ;;
      *) k=$((k + 1)) ;;
    esac
  done
  [ "$k" -lt "$n" ] || return 0
  case "${TOK[k]##*/}" in flow-factory.sh|_flow_factory.py) TF_IK=call; TF_IJ=$((k + 1)) ;; esac
  return 0
}

# _tf_scan — read TF_CMD by program words: TF_CALLS (person calls), TF_POST=1
# for a comment post, TF_SCAN_FAIL=1 when a part could not be read, TF_NSEG
# the number of commands (a shell's -c that only carries its script is not
# counted; its script's commands are), and TF_SHIFTED=1 when a person call
# has an assignment, or a wrapper's -C, -D or --chdir, before it.
_tf_scan() {
  TF_CALLS=(); TF_POST=0; TF_SCAN_FAIL=0; TF_NSEG=0; TF_SHIFTED=0; TF_SEGPRE=0
  local BD_LANG_DATA=0 BD_BLANK_BODIES=0 BD_SEG_ALT=0 BD_SEG_MARK=0 BD_SPLIT_EXP=0
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=() BD_WRAPI=()
  local BD_RIN=0 BD_CMDI=0 BD_CODE="" BD_KEPT_BODY=0 BD_UNBALANCED=0
  local seg segs n i j k w b
  _bd_strip_noncode "$TF_CMD" || { TF_SCAN_FAIL=1; return 0; }
  _bd_expand_interpreter_args
  segs=$(_bd_segments "$BD_CODE") || TF_SCAN_FAIL=1
  while IFS= read -r seg; do
    case "$seg" in
      '') continue ;;
      __BD_UNBALANCED__|__BD_SEG_FAIL__) TF_SCAN_FAIL=1; continue ;;
    esac
    case "$seg" in __BD_ALT__*) seg="${seg:10}" ;; esac
    case "$seg" in __BD_PIPE__*) seg="${seg:11}" ;; esac
    TF_NSEG=$((TF_NSEG + 1))
    _bd_words "$seg" || { TF_SCAN_FAIL=1; continue; }
    n=${#TOK[@]}
    _bd_command_word _tf_target 0
    i=$BD_CMDI
    TF_SEGPRE=0
    for ((k = 0; k < i && k < n; k++)); do
      case "${TOK[k]}" in
        [A-Za-z_]*=*|--chdir|--chdir=*) TF_SEGPRE=1 ;;
        --*) ;;
        -*[CD]*) TF_SEGPRE=1 ;;
      esac
      # A wrapper's option that carries the script (env --split-string=...)
      # is a call this reading cannot split.
      case "${TOK[k]}" in -*) _tf_names_file "${TOK[k]}" && TF_CALLS+=("unread	") ;; esac
    done
    [ "$i" -lt "$n" ] || continue
    w="${TOK[i]}"; b="${w##*/}"
    case "$b" in
      flow-factory.sh) _tf_call "$((i + 1))"; continue ;;
      gh) _tf_gh_post "$i" && TF_POST=1; continue ;;
    esac
    if [ "${TOKE[i]:-0}" = 1 ] || [[ "$w" == *'$'* ]]; then
      # A program named by a variable, in a command that names the script.
      _tf_names_file "$TF_CMD" || continue
      case "${TOK[i+1]:-}" in */_flow_factory.py|_flow_factory.py|*/flow-factory.sh|flow-factory.sh) j=$((i + 2)) ;; *) j=$((i + 1)) ;; esac
      _tf_call "$j"
      continue
    fi
    if _bd_is_language "$b" || _bd_is_shell "$b" || _tf_is_python "$b"; then
      # python3 <path>/_flow_factory.py <sub>, python3 -m _flow_factory
      # <sub>, or a shell given the script.
      _tf_interp "$i" "$b"
      case "$TF_IK" in
        # A -c that carries the script's call is not a command of its own;
        # one that does not name the script (bash -c "$X") is.
        carrier) _tf_names_file "$seg" && TF_NSEG=$((TF_NSEG - 1)) ;;
        call) _tf_call "$TF_IJ" ;;
      esac
    fi
  done <<TF_SEGS_EOF
$segs
TF_SEGS_EOF
  return 0
}

# _tf_ask_reason — the ask's text for TF_CALLS, or 1 when a confirm's stored
# literal cannot be shown (then the call is denied).
_tf_ask_reason() {
  local c sub detail out cwd first
  cwd="$TF_CWD"
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
  TF_REASON="Flow factory: this is a person command. In a session it runs only when you approve it here; approve only if you, not the model, mean it. Command: $TF_CMD"
  for c in "${TF_CALLS[@]}"; do
    sub="${c%%	*}"; detail="${c#*	}"
    case "$sub" in
      unread) return 1 ;;
      confirm)
        [ -n "$detail" ] || return 1
        out=$(cd "$cwd" 2>/dev/null && "$PLUGIN_ROOT/bin/flow-factory.sh" status --intent "$detail" < /dev/null 2>/dev/null) || return 1
        first="${out%%$'\n'*}"
        case "$first" in "INTENT id=$detail "*) ;; *) return 1 ;; esac
        TF_REASON="$TF_REASON

The write that confirm $detail releases, as the engine recorded it:
$out" ;;
      *) [ -n "$detail" ] && TF_REASON="$TF_REASON
$detail" ;;
    esac
  done
  return 0
}

_tg_factory_rules() {
  local text worker=""
  _tf_read
  if [ "$TF_JQ" = 1 ]; then text="$TF_CMD"; else text="$TF_RAW"; fi
  [ -n "${FLOW_FACTORY_JOB:-}${FLOW_FACTORY_DIRECTIVE:-}" ] && worker=1

  # 1. A worker session.
  if [ -n "$worker" ] && _tf_names_file "$text"; then
    local exact=""
    if [ "$TF_JQ" = 1 ]; then exact="$TF_CMD"
    elif _tf_raw_value; then exact="$TF_VAL"
    fi
    if [ -z "$exact" ] || ! _tf_worker_form "$exact"; then
      _tg_deny "Flow factory: a worker session may run only \`flow-factory.sh context --mode\` and \`flow-factory.sh await <qid> [--max-seconds <n>]\`, each as the whole command; this command names the factory's engine (flow-factory.sh or _flow_factory.py) otherwise and was not run."
    fi
  fi

  # 2. The factory directory.
  if _tf_factory_dir && _tf_names_dir "$text"; then
    _tg_deny "Flow factory: this command names the factory directory $TF_DIR_HIT, which only the factory's engine reads and writes. Use flow-factory.sh status (or run the command in a terminal outside Claude Code)."
  fi

  # Program words, when jq read the command and it names the factory.
  local parsed=0
  TF_CALLS=(); TF_POST=0; TF_SCAN_FAIL=0
  if [ "$TF_JQ" = 1 ]; then
    if _tf_names_file "$text" || case "$text" in */flow-factory*) true ;; *) false ;; esac; then
      _tf_load_parser || _tg_deny "Flow factory: the command parser (hooks/scripts/lib/command-parse.sh) could not be loaded, so this command, which names the factory, was not run. Reinstall the flow plugin."
      _tf_scan
      parsed=1
    fi
  fi

  # 3. A comment post naming /flow-factory.
  case "$text" in
    */flow-factory*)
      local post=0
      if [ "$parsed" = 1 ] && [ "$TF_SCAN_FAIL" = 0 ]; then post="$TF_POST"
      elif _tf_text_post "$text"; then post=1
      fi
      if [ "$post" = 1 ] && _tf_factory_enabled; then
        _tg_deny "Flow factory: this command posts an issue or pull request comment that names /flow-factory. With the factory enabled, a person command is posted by the person on GitHub, never from a session."
      fi ;;
  esac

  # 4. Person subcommands, outside a worker.
  [ -z "$worker" ] || return 0
  _tf_names_file "$text" || return 0
  if [ "$parsed" = 0 ]; then
    # Without jq the text cannot be read by program words: only an untiered
    # subcommand as the whole command, in plain words, runs.
    if _tf_raw_value; then
      _tf_untiered_form "$TF_VAL" && return 0
      _tg_deny "$(_tf_terminal "$TF_VAL")"
    fi
    _tg_deny "$(_tf_terminal "$text")"
  fi
  if [ "$TF_SCAN_FAIL" = 1 ] && _tf_text_person "$TF_CMD"; then
    _tg_deny "$(_tf_terminal "$TF_CMD")"
  fi
  [ "${#TF_CALLS[@]}" -gt 0 ] || return 0
  # Asked about only as the whole command: in a chain, beside another
  # command, or after a change of directory or environment, what the ask
  # shows could differ from what runs.
  if [ "$TF_NSEG" -ne 1 ] || [ "$TF_SHIFTED" = 1 ]; then _tg_deny "$(_tf_terminal "$TF_CMD")"; fi
  [ "$TF_MODE" = default ] || _tg_deny "$(_tf_terminal "$TF_CMD")"
  _tf_ask_reason || _tg_deny "$(_tf_terminal "$TF_CMD")"
  jq -cn --arg r "$TF_REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
