#!/usr/bin/env bash
# [flow] PreToolUse hook (matcher: Bash): apply the tier settings (`tiers.*`)
# to the Bash command about to run.
#
# Flow sorts the actions that leave the machine into tiers
# (references/three-tier-safety.md). Each has a setting, resolved through
# bin/cascade-resolve.sh:
#
#   tiers.push         git push                                  default journal
#   tiers.prCreate     gh pr create                              default journal
#   tiers.issueAssign  gh issue edit --add-assignee              default journal
#   tiers.issueCreate  gh issue create                           default journal
#   tiers.merge        gh pr merge                               always confirm
#   tiers.release      gh release create, edit, delete, upload   always confirm
#                      and delete-asset, and a tag push
#
# gh release edit publishes a draft (--draft=false) or moves a release's tag,
# and delete removes a release (and its tag, with --cleanup-tag). upload and
# delete-asset are the release tier too: on a published release they change
# the files people download at once, and --clobber replaces one.
#
# `new` is gh's alias for `create` (`gh pr new`, `gh issue new`, `gh release
# new`) and counts the same. `gh api` counts as follows. A leading `/`, a full
# https:// URL, a query string, `{owner}/{repo}` placeholders and
# percent-encoded characters (`git/refs/tags%2Fv1`) are allowed;
# the method is -X/--method, or POST when a -f/-F/--field/--raw-field/--input
# parameter is given (gh's own rule), or GET. gh's options are read as its
# parser reads them: `-X POST`, `-XPOST`, `-X=POST`, a bundle (`-iX=POST`),
# `--method POST`, `--method=POST`, and the same forms of -f and -F. A method
# that is a variable, or that is not GET, HEAD, POST, PUT, PATCH or DELETE,
# is read as any write: on an endpoint where one of them would be a merge or
# a release it asks. A ref given as `-F ref=@file` (read from a file or
# stdin) cannot be read, so it asks; with -f the `@` is text. Under xargs an
# endpoint missing from the command may come from its input, so a write asks.
#   POST/PUT .../pulls/{n}/merge, .../merges              merge
#   POST .../releases; PATCH .../releases/{id}; DELETE
#     .../releases/{id} or .../releases/assets/{id};
#     POST .../releases/{id}/assets                       release
#   POST .../git/refs with a refs/tags/ ref               release
#   DELETE or PATCH .../git/refs/tags/{tag}               release
#   POST .../pulls                                        prCreate
#   POST .../issues                                       issueCreate
#   POST .../issues/{n}/assignees; PATCH or PUT
#     .../issues/{n} with an assignee or assignees field  issueAssign
#   graphql with mergePullRequest or
#     enablePullRequestAutoMerge                          merge
#     (disablePullRequestAutoMerge is not one)
#   graphql with createRelease or updateRelease           release
#   graphql with createPullRequest                        prCreate
#   graphql with createIssue                              issueCreate
#   graphql with addAssigneesToAssignable                 issueAssign
#   graphql mutation with any other field whose name
#     holds Merge (any case), or enqueuePullRequest       merge
#   graphql mutation with any other field whose name
#     holds Release or Ref (any case): createRef,
#     updateRef, deleteRef, updateRefs, deleteRelease     release
# The GraphQL query is read from -f/-F query=..., query=@file and --input
# file (relative to the command's directory). A field is a name followed by
# its arguments, and only a document with a mutation in it is read for the
# Merge/Release/Ref names: a query that reads refs or mergeable changes
# nothing. String values ("...", """...""") and # comments are not read, so
# `body:"refactor(gate)"` names no field. A query typed on the command line
# is read as bash hands it to gh: inside single quotes every backslash stays,
# inside double quotes only the one before $, `, " or \ goes, so an escaped
# quote (`title:"Say \"hi"`) ends no string. A double-quoted query in which
# bash expands something (`"mutation { $FIELD(...) }"`, a backquote) cannot
# be read, so it asks; `\$id` or '$id' is a GraphQL variable. A query typed
# on the command line has lost its line ends, so from its first comment on it
# is read as written; a --input body is JSON and is read as written.
#
# Pushing a tag is the release tier, not push: `git push` with --tags,
# --follow-tags, --mirror, `-c push.followTags=true`, or push.followTags true
# in the repository's git configuration (a -c on the command line overrides
# it); `git push <remote> tag <name>`; a refspec with refs/tags/ on either
# side (`HEAD:refs/tags/v1`); a refspec whose source or destination is a tag
# in this repository (`git push origin v1.2.0` when v1.2.0 is a tag; a branch
# named v1-fix is not); or a `tags/<name>` source. Deleting a tag is release
# too: `:<tag>`, `:refs/tags/<tag>`, or --delete/-d with a tag's name; a
# deleted name that is neither a tag nor a known branch (local, or
# remote-tracking on that remote) may be a tag on the remote, so it asks. Any
# other source that is not a local branch (HEAD, @ and refs/heads/ count as
# branches) may be a tag, so it asks too: a name that does not exist yet (`git
# tag v7 && git push origin v7`), a glob (`refs/*:refs/*`), a commit, a
# remote-tracking branch. A forced push (-f, --force, --force-with-lease, a
# `+` refspec) to a destination not under refs/ that is neither a local branch
# nor a remote-tracking branch of that remote asks too: git looks the name up
# on the remote, and moves a tag there that this repository does not have
# (`git push -f origin HEAD:v5`); without force git refuses to. A command that
# pushes a branch and a tag is release.
#
# git push's options are read as git reads them: any unambiguous prefix of a
# long option counts (`--tag`, `--mirr`, `--follow-tag`, `--del`,
# `--no-fol`, `--force-w`), and a bundle of short options is read letter by
# letter (`-qd` deletes, `-fu` forces; `-o` takes the rest of the bundle, or
# the next word, as its value). push.followTags is read as git reads a
# boolean: false, no, off, 0 and the empty value are false, a bare `-c
# push.followTags` is true, and any other value is true (git reads a
# non-zero number as true and stops on a word it does not know).
#
# The remote's configuration counts as well: remote.<name>.mirror makes every
# push to that remote a tag push, and its remote.<name>.push refspecs are read
# as if written when the command names no refspec. The remote is the first
# word after the options, else --repo's value (`--repo=mir`, `--repo mir`);
# a push that names neither goes where git sends it
# (branch.<branch>.pushRemote, remote.pushDefault, branch.<branch>.remote,
# then origin); a remote given as a variable may be any of them, and may be
# an option too (`git push $OPTS`, `git push $'--tags'`), so it asks, as an
# option whose name is a variable does (`--$X`, `-$F`). Setting
# configuration for one command that can make a push send tags asks: `-c
# remote.<name>.mirror`, `-c remote.<name>.push=...`, `-c include.path=...`
# or `-c includeIf.<condition>.path=...` (a file of settings), the same
# through --config-env (`--config-env=<key>=<var>` or `--config-env
# <key>=<var>`), and GIT_CONFIG, GIT_CONFIG_COUNT, GIT_CONFIG_KEY_<n>,
# GIT_CONFIG_VALUE_<n>, GIT_CONFIG_PARAMETERS, GIT_CONFIG_GLOBAL,
# GIT_CONFIG_SYSTEM, GIT_COMMON_DIR, HOME or XDG_CONFIG_HOME set before git
# or set earlier in the same command, exported or not (an assignment, also
# NAME+=value and NAME[i]=value; a name after export, declare, typeset, local
# or readonly; a name read into by read, mapfile, readarray or getopts; the
# name of printf -v; or an unset of one set in this hook's environment; `echo
# HOME` sets nothing). A plain assignment counts because `set -a` or an
# earlier export makes it reach git. Setting the keys that pick the remote
# (remote.pushDefault, branch.<name>.pushRemote, branch.<name>.remote) the
# same ways asks when the push names no remote. Earlier in the same command,
# each of these makes every later push in it ask: a `git config` that writes
# a key under push., remote., branch., include. or includeIf. (any form: -C,
# --global, --file, `set`, --add, --unset, a key given as a variable, or -e),
# or renames or removes one of those sections, with or without a subsection
# (`--rename-section x push`, `rename-section`); a `git remote add`,
# `set-url` or `rename` (`--mirror=push`); an upstream or tracking change
# (`git branch -u`, `--set-upstream-to`, `--unset-upstream`, `-t`/`--track`,
# a moved or copied branch, `git checkout -b <name> <start>`, `-t`/`--track`
# on checkout or switch, `git push -u`); under xargs, which appends words
# this hook cannot see, a git config that is not a read, a git remote that
# is not show or get-url, a git branch, a git push, or a git with no
# subcommand; a git whose subcommand is a variable; and a write to a file
# under .git, to a .gitconfig or to ~/.config/git (a redirection target such
# as `>> .git/config`, or an argument of a program that does not only print
# or search it: `cp ../other/.git/config .git/config`, `tee -a .git/config`,
# `ln -s ../other/.git .git`). A git checkout or switch that may change the
# branch (not `git checkout -- <paths>`), or a git symbolic-ref of HEAD,
# makes a later push that names no remote ask: the new branch's
# configuration picks it. Each of these counts the same in a quoted argument
# or here-string handed to a shell anywhere in the command (`bash -c 'git
# config ...' && git push`), or to a program this hook does not know (`watch
# 'git config ...'`); reading configuration (--get, --list, `get`), other
# keys (user.name) and reading a file under .git (cat, grep) do not. Under
# xargs, words appended from its input may be refspecs, so the push asks.
#
# Some commands change the shell itself in a way this hook does not follow,
# so that the directory, the variables or the program a later name runs can
# no longer be read from the command: eval, source and `.` (they run text in
# this shell; the words of eval and a here-string to source are read as
# commands too, but an evaluated variable or a sourced file is not), exec
# with a command, alias, `hash -p`, enable with arguments, a DEBUG, RETURN
# or ERR trap, a nameref (declare, typeset or local -n), and a command word
# that is a variable or a substitution (`CD=cd; $CD ../other`). One anywhere
# in the command, before a push or after it (a loop or a function can run
# the push again), makes the directory, the environment and git's
# configuration unreadable from the start of the command: every push in it
# asks as a possible tag push, and a gh release create --verify-tag asks.
# `bash -c '...'` differs: its shell is a child, so only what it changes in
# the repository (a git config) outlives it, and only that is counted.
#
# `git -C <dir>`, `--git-dir`, `--work-tree`, and GIT_DIR= or GIT_WORK_TREE=
# before git name the repository a push acts on: tags, push.followTags, the
# remotes' configuration and the breadcrumb's trail are taken from that
# repository, not the payload's. A relative --git-dir, --work-tree, GIT_DIR
# or GIT_WORK_TREE is found from the directory the last -C names, as git
# finds it. When the repository cannot be found (a missing directory, a
# variable), the push asks: none of that can be read. A cd, pushd or popd
# earlier in the command is followed: a cd to a directory of the payload's
# repository changes nothing, while a cd into another repository, or one
# whose target cannot be read (a variable, `cd -`, popd, pushd +N, a name
# an exported CDPATH may resolve, a substitution, a home directory: `cd`
# alone, `cd ~`, `cd ~/src`), makes a later push ask as
# a possible tag push. Two more are followed: a cd into another worktree of
# the payload's repository (the same common directory), which shares its tags,
# branches and configuration, so a push there is judged there, and asks only
# when it names no remote (the branch checked out picks it) or the repository
# gives worktrees configuration of their own (extensions.worktreeConfig); and
# `cd "$(git rev-parse --show-toplevel)"`, the top of the repository the
# command is in. A cd inside a subshell or a substitution is read the same
# way, since the parser does not keep the subshell's bounds.
#
# `gh release create <tag> --verify-tag` creates a release for a tag that
# must already be on GitHub, and that tag's push was already confirmed. So it
# is journaled instead of asked when gh creates the release in origin's
# repository and `git ls-remote --tags origin` finds the tag there within
# TG_REMOTE_TIMEOUT seconds (default 5). The repository gh uses is -R/--repo,
# else GH_REPO before gh or in this hook's environment, else gh's default:
# the remote `gh repo set-default` chose (remote.<name>.gh-resolved), or the
# only remote. It has to be origin's: the same host/owner/name as
# remote.origin.url, in any case, for a named repository; origin itself for
# the default. Without --verify-tag, with a tag absent from origin, when the
# check fails, when the repository cannot be confirmed to be origin's, with
# GH_HOST set, with GH_REPO+= or GH_REPO[i]= before gh, after a cd or a
# GH_REPO/GH_HOST setting earlier in the same command (in any of the forms
# above), with an eval, source or other change to the shell the hook does not
# follow anywhere in it, or behind a program this hook does not know, it
# asks.
#
# Values: confirm asks (permissionDecision "ask", with a reason naming the
# action, the setting and the command); journal writes one breadcrumb to the
# git-ignored auto-log trail and allows; autonomous allows. merge and release
# have a floor of confirm: they always ask, and a lower value is ignored with
# one stderr line naming the setting. An "ask" is a prompt in an interactive
# session, bypassPermissions mode included, and a refusal in `claude -p`,
# which has no one to ask.
#
# Decision table:
#   command names no tiered action                    -> exit 0, no output
#   every action it names resolves to autonomous      -> exit 0, no output
#   any action resolves to confirm (merge and release -> exit 0, stdout JSON permissionDecision "ask"
#     always do)                                         naming each such action; no breadcrumb is
#                                                        written, since the person may refuse
#   merge or release set below confirm                -> as above, plus one stderr line naming the setting
#   gh release create --verify-tag, in origin's       -> journaled, as below
#     repository, tag on origin
#   gh release create --verify-tag, tag not found,    -> "ask"
#     the check failed or timed out, or the
#     repository is not confirmed to be origin's
#   otherwise, journal-tier actions                   -> one breadcrumb per distinct action (the same
#                                                        command text read twice is one) in the auto-log
#                                                        trail (<journal dir>/auto-log/issue-{N}.{YYYY-MM}.md
#                                                        on a branch naming issue N, otherwise
#                                                        auto-log/session-{YYYY-MM-DD}.md), exit 0, no
#                                                        output; the tracked journal is not touched
#     the journal directory does not exist            -> nothing written, exit 0, no output (the
#                                                        repository does not keep a flow journal)
#     the trail is refused (a symlink) or the write   -> exit 0, one stderr line
#     fails
#   push, prCreate, issueAssign or issueCreate whose  -> that action is allowed, one stderr line
#     value is not autonomous|journal|confirm, or
#     whose setting cannot be read (cascade fails)
#   gh api PATCH/PUT on .../issues/{n} whose body is  -> allowed, one stderr line (it may change
#     a file (--input)                                   assignees; not a confirm-floor action)
#   a gh api write whose whole endpoint is a variable -> "ask": it may be a merge or a release
#     or a substitution (or left to xargs), a GraphQL
#     query that cannot be read (a variable, stdin, a
#     missing file, a double-quoted query in which
#     bash expands something), a method that is a variable or
#     not a verb on a merge or release endpoint, a
#     gh pr or gh release whose subcommand is a
#     variable (`gh pr $A 7`, `gh $SUB merge 7`), an
#     eval of a variable or a substitution, a source
#     or . of stdin or of no file (`. <(...)`), a
#     command word that is a variable with nothing
#     after it (`$CMD`), a quoted command nested more
#     than four deep, or more quoted commands after
#     one program than flow reads
#   a shell that reads its script from its input      -> "ask": it may merge or release
#     (`echo '...' | bash`, `| sh -s`, `| sudo bash`,
#     xargs bash): no -c, no script file, and no
#     here-string, heredoc or < on it
#   a push whose refspec, remote or option is a       -> "ask": it may push or delete a tag
#     variable or a substitution (or left to xargs),
#     whose source is not a local branch, a forced
#     push to a destination that is not a known
#     branch, a deleted name that is neither tag nor
#     branch, a push into a -C/--git-dir repository
#     that cannot be found or after a cd into another
#     repository, a command-line setting of a
#     remote's mirror or push, of include.path, or of
#     the remote when the push names none; after a
#     git config, git remote, upstream or tracking
#     change, or write under .git earlier in the
#     command that may change what it sends; anywhere
#     in a command with an eval, source, exec, alias
#     or other change to the shell this hook does not
#     follow; a push naming no remote after a cd into
#     another worktree or a branch change; or a gh
#     api git/refs request whose ref cannot be read
#   cannot decide: jq missing, a payload jq cannot    -> text that mentions merge or release with gh:
#     parse, the command parser missing or failed        "ask"; other text that mentions push or gh:
#                                                        exit 0, one stderr line; anything else:
#                                                        exit 0, no output
#
# In practice block-unchecked-merge.sh refuses every Bash call when jq is
# missing, so the jq row decides only when that hook is not installed.
#
# Reading the command. The command is parsed, not matched: the same parser
# block-unchecked-merge.sh and block-destructive.sh use
# (lib/command-parse.sh). `#` comments and heredoc bodies fed to cat, tee,
# echo, printf or gh are removed; the text is split into simple commands at
# `;`, `|` (not the one of `>|`), `&` (not the `&` of `2>&1`, `<&3` or `&>`),
# `(`, `)`, newlines and
# command substitutions (`$(...)` and backquotes, inside double quotes too),
# outside quotes; each simple command is split into the words bash hands the
# program: quotes removed, a backslash removed outside quotes (`g\h pr
# mer\ge 1` is gh pr merge 1, `gh\ pr` one word) and inside double quotes
# only before $, `, " and \, and kept inside single quotes; `$"merge"` is a
# double-quoted string (bash drops the $), while `$'...'` keeps its $ and
# reads as a variable. An unquoted < or
# > starts a redirection wherever it stands, also inside a word
# (`--tags>/dev/null` is --tags and a redirection), and the redirection and
# its target (`2>&1`, `>/dev/null`, `> "push log.txt"`) are set aside, so
# neither is a refspec or the program, while a quoted or escaped one (`-q
# '1>0'`, `\>x`) stays an argument. A quoted argument handed to something
# that runs it (`bash -c '...'`, `eval`, `ssh`, also inside a substitution:
# `x=$(bash -c '...')`) is read as a command too, and so is a here-string on
# a line that names such a program (`bash <<<'...'`, `cat <<<'...' | bash`),
# since that program reads it as its script, and so is a quoted argument of
# the simple command before a shell that reads its script from its input
# (`echo 'gh pr merge 1' | bash`).
#
# Every action counts when its program is the command word: first in its
# simple command, after any VAR=value assignments; after a shell keyword or
# group opener (if, then, elif, else, while, until, do, !, {), `function
# NAME`, or coproc (and its NAME before a body); and after any of these,
# which run the rest of the line as a command: command, builtin, exec, env,
# nohup, time, nice, timeout, sudo, doas, xargs. Their options are read as
# getopt reads them: a bundle of short options letter by letter, the first
# that takes a value taking the rest of the word or the next one (`sudo -Eu
# root`, `timeout -vk 5 10`), and a long option under any prefix of three or
# more characters (`sudo --us root`). `env -S STRING` (also -S'...', a bundle
# such as -iS'...', and --split-string=...) runs the words of STRING, which
# are read in its place. `gh` and `git` may carry a path. So `make && git
# push`, `x=$(gh pr create ...)` and `timeout 60 git push` count.
#
# A Tier 3 action counts anywhere after a command word that is none of
# those, because a program this hook does not know may run the rest of its
# line (caffeinate, stdbuf, setsid, watch, `find -exec`, parallel, `script -q
# /dev/null`): the words after it are read for gh and git, and a merge, a
# release, a tag push or a possible one, or an unreadable gh api call there
# asks. Each word after it with a space in it (a quoted argument) that names
# push, merge, release or api is read as a whole command for the same
# actions, since such a program may hand it to a shell: `watch 'gh release
# create v9'`, `script -c '...'`, `flock f -c '...'`, `tmux new '...'`, `trap
# '...' EXIT`, `awk 'BEGIN { system("...") }'`; so is a here-string, which is
# its input (`script -q /dev/null <<<'...'`). A program such as ssh, watch or
# `sudo -s` joins its arguments into one shell command, so when a word from
# the program on holds a space or a character the shell reads specially, the
# words from the program on are also read joined with spaces as one command:
# `ssh host gh\ pr merge 1`, `watch "gh pr" merge 1`, `watch 'x;gh' release
# create v9`; not after a shell or a language's interpreter (`bash -c '...'
# a b` runs only its script, which is read already). At most 16 such readings are made per simple command, and one
# more asks as an unreadable gh call. A shell among the words that reads its
# script from its input asks. A command word that is a variable or a
# substitution (`$GH pr merge 7`) is read as possibly gh or git for the same
# Tier 3 actions, and with nothing after it (`$CMD`) asks. Programs that
# only print, search or compare their arguments are exempt: echo, printf,
# grep, egrep, fgrep, zgrep, rg, jq, cat, tee, test, `[`, `[[` and `:`. So
# `echo gh pr merge 1`, `grep "gh pr merge" log`, `git commit -m "then gh pr
# merge 1"` and `npm run git push` ask nothing.
#
# Not covered, by design. A Tier 2 action (push, prCreate, issueAssign,
# issueCreate) behind a program this hook does not know, or under a command
# word that is a variable: `caffeinate git push` is neither asked about nor
# journaled, since a prompt for every script that
# mentions git would cost more than the setting saves. And what text cannot
# show: a whole command held in a variable with arguments after it (`$CMD
# --repo o/r`, read only as possibly gh or git), a gh or git alias, a gh
# extension, a script file (`bash release.sh`; one run with `source` or `.`
# makes the pushes in the command ask, but its own actions are not read) or
# a make target, another program that talks to GitHub (curl, git
# send-pack), GIT_DIR, GIT_WORK_TREE, GIT_CONFIG_*, HOME or XDG_CONFIG_HOME
# exported in an earlier Bash call, GH_REPO or GH_HOST exported in an earlier
# Bash call, a CDPATH set in the shell but not exported to this hook (`cd
# name` is then read as a directory under the current one), a GraphQL
# mutation whose field names hold none of Merge, Release or Ref
# (createCommitOnBranch), and gh api DELETE or PATCH requests other than
# those above (deleting a branch ref). Branch protection,
# rulesets and tag protection are the mechanism against those; this hook
# reads the commands an agent writes. `--help` is not exempted: it costs a
# prompt, while exempting a value that happens to read `--help` would cost a
# missed confirmation. For the same reason the parser reads every quoted
# argument with a space in it, after env, sudo, timeout, xargs, nohup and the
# other words it treats as running a script, as a command too: so `timeout 60
# gh pr create --body "git push later"` also counts as a push; a quoted
# argument after a program this hook does not know is read as a command even
# when it only prints it (`caffeinate echo "gh pr merge 1"` asks); a cd to a
# variable or to any substitution but `$(git rev-parse --show-toplevel)` makes
# a later push ask (`cd $REPO_ROOT && git push`), since the repository it
# lands in cannot be read; a git config of a push., remote., branch.,
# include. or includeIf. key makes a later push ask even when the value
# changes nothing; any path under .git that a program other than a reader
# (cat, grep, ls, ...) is given makes a later push ask (`stat .git/config`);
# a git checkout of a branch makes a push that names no remote ask; an eval,
# source, `.`, exec with a command, or a command word that is a variable
# makes every push in the command ask (`. venv/bin/activate && git push`,
# `exec git push origin br`); the joined reading of a program's words is
# made for every program but a shell or a language's interpreter, so
# `"gh release" create v9`, which runs nothing, asks; and a shell that reads
# its script from its input after `;` rather than `|` asks too. Each of
# these costs an extra prompt or journal line, never a missed one.
#
# ask-issue-create.sh is a separate hook and both apply to `gh issue create`:
# Claude Code takes the most restrictive answer, so an ask from either wins.
#
# Hook input (stdin JSON): tool_input.command, and cwd when present (the
# directory the command runs in; the settings, the branch and the journal are
# read there).

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines. Its value is kept: a `cd name` in the
# command may be resolved through it (_tg_cd).
TG_CDPATH="${CDPATH:-}"
unset CDPATH
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"
# cascade-resolve.sh locates the plugin-default settings.json through
# CLAUDE_PLUGIN_ROOT, so publish the resolved root to it.
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

_tg_note() { printf 'flow: tier-gate — %s\n' "$1" >&2; }

# The ask for a command this hook could not read. Constant text, so it needs
# no jq to be valid JSON.
_tg_ask_unread() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Flow could not read this command, and it may merge a pull request or create a release, which flow always asks about (tiers.merge, tiers.release; Tier 3). Approve only if that is intended."}}'
}

# Cannot decide: judge the bare text instead. $1 = the text, $2 = why.
_tg_undecidable() {
  local bare
  bare=$(printf '%s' "$1" | LC_ALL=C tr -d "'\"\\\\" | LC_ALL=C tr 'A-Z' 'a-z' 2>/dev/null) || bare="merge gh"
  case "$bare" in
    *gh*merge*|*gh*release*|*merge*gh*|*release*gh*|*/merge*|*/releases*)
      _tg_ask_unread; exit 0 ;;
    *push*|*gh*)
      _tg_note "could not read the command ($2); allowing it without a tier check"
      exit 0 ;;
  esac
  exit 0
}

INPUT=$(cat 2>/dev/null) || INPUT=""

if ! command -v jq >/dev/null 2>&1; then
  # Without jq the payload cannot be parsed, so the text from the command key
  # on is judged: the rest of the payload (the transcript path, the working
  # directory) says nothing about the command.
  case "$INPUT" in
    *'"command"'*) _tg_undecidable "${INPUT#*\"command\"}" "jq is not installed" ;;
  esac
  exit 0
fi
# A payload jq cannot parse is judged like one read without jq: from the
# command key on. A payload that parses and holds no command is no command.
if ! COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  case "$INPUT" in
    *'"command"'*) _tg_undecidable "${INPUT#*\"command\"}" "the hook payload could not be parsed" ;;
  esac
  exit 0
fi
[ -z "$COMMAND" ] && exit 0

# Cheap reject before any parsing: this hook runs before every Bash call, and
# every action it knows needs `gh` or `push` in the text, or `merge` or
# `release` when the program is a variable (`$X pr merge 7`). Quotes and
# backslashes are removed first, so `p""ush` still reaches the parser.
_TG_BARE=$(printf '%s' "$COMMAND" | LC_ALL=C tr -d "'\"\\\\") || _TG_BARE=gh
case "$_TG_BARE" in
  *[Gg][Hh]*|*[Pp][Uu][Ss][Hh]*|*[Mm][Ee][Rr][Gg][Ee]*|*[Rr][Ee][Ll][Ee][Aa][Ss][Ee]*) ;;
  *) exit 0 ;;
esac

_TG_LIB="$SCRIPT_DIR/lib/command-parse.sh"
[ -r "$_TG_LIB" ] || _tg_undecidable "$COMMAND" "the command parser $(basename "$_TG_LIB") is missing"
# shellcheck source=lib/command-parse.sh
. "$_TG_LIB" 2>/dev/null
for _tg_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _bd_words _bd_is_opt _bd_is_interpreter; do
  type "$_tg_fn" >/dev/null 2>&1 || _tg_undecidable "$COMMAND" "the command parser did not load"
done
[ -n "${_BD_SEG_AWK:-}" ] || _tg_undecidable "$COMMAND" "the command parser did not load"

# --- reading one simple command ---------------------------------------------

# An assignment word, as bash reads one: NAME=value, NAME+=value (appended to
# what NAME holds, which this hook cannot see) or NAME[index]=value. Sets
# TG_AN to NAME.
_tg_is_assignment() {
  local l
  TG_AN=""
  case "$1" in [A-Za-z_]*=*) ;; *) return 1 ;; esac
  l="${1%%=*}"
  l="${l%+}"
  case "$l" in *\[*\]) l="${l%%\[*}" ;; esac
  case "$l" in ''|*[!A-Za-z0-9_]*) return 1 ;; esac
  TG_AN="$l"
  return 0
}

# A word this hook cannot read without running a shell.
_tg_unreadable() {
  case "$1" in *'$'*|*'`'*|*__BD_SUBST__*) return 0 ;; esac
  return 1
}

# The program a word names: its last path component, a leading backslash
# removed, in lower case (a case-insensitive filesystem runs `GH`).
_tg_prog() {
  local b="${1##*/}"
  b="${b#\\}"
  printf '%s' "$b" | LC_ALL=C tr 'A-Z' 'a-z'
}

# A wrapper's options that take a value: TG_WS, the short ones (one letter
# each), and TG_WL, the long ones.
_tg_wrapper_opts() {   # $1 = wrapper
  TG_WS=""; TG_WL=""
  case "$1" in
    exec) TG_WS=a ;;
    env) TG_WS=uCS; TG_WL="--unset --chdir --split-string" ;;
    nice) TG_WS=n; TG_WL="--adjustment" ;;
    timeout) TG_WS=sk; TG_WL="--signal --kill-after" ;;
    sudo) TG_WS=acCDghpRrTtUu
          TG_WL="--user --group --host --prompt --close-from --chdir --chroot --command-timeout --other-user --role --type --auth-type --login-class" ;;
    doas) TG_WS=aCu ;;
    xargs) TG_WS=adEIJLnPRsS
           TG_WL="--arg-file --delimiter --max-lines --max-args --max-procs --max-chars --process-slot-var" ;;
    time) TG_WS=fo; TG_WL="--format --output" ;;
  esac
}

# A bundle of short options, read letter by letter as getopt and pflag read
# it: the first letter that takes a value (one of $2) takes the rest of the
# word (`-Eu root` takes nothing more, `-XPOST`, `-iS'...'`) or, when nothing
# is left, the next word (`-u root`, `-X POST`). With $4 = 1 (pflag, gh's
# parser) a rest that starts with `=` is the value without it (`-X=POST`).
# Sets TG_PO to that letter (empty when none takes a value), TG_PV to its
# value and TG_PN to the words used (1 or 2).
_tg_short_bundle() {   # $1 = the word, $2 = the letters that take a value, $3 = the next word, $4 = 1 for pflag
  local rest="${1#-}" c
  TG_PO=""; TG_PV=""; TG_PN=1
  while [ -n "$rest" ]; do
    c="${rest:0:1}"; rest="${rest:1}"
    case "$2" in
      *"$c"*)
        TG_PO="$c"
        case "$4:$rest" in
          *:) TG_PV="$3"; TG_PN=2 ;;
          1:=?*) TG_PV="${rest#=}" ;;
          *) TG_PV="$rest" ;;
        esac
        return 0 ;;
    esac
  done
  return 0
}

# One option word of a wrapper, read as getopt reads it: a bundle of short
# options letter by letter, the first letter that takes a value taking the
# rest of the word or, when nothing is left, the next word (`-Eu root`,
# `-iS'...'`, `-vk 5`); a long option taking `=value` or the next word, under
# any prefix of three or more characters (`--us root`, `--sp=...`). Sets
# TG_WO to the option that took a value (a letter or a long name, empty for
# none), TG_WV to its value and TG_WN to the words used (1 or 2).
_tg_wrapper_opt() {   # $1 = wrapper, $2 = the word, $3 = the next word
  local t="$2" o
  TG_WO=""; TG_WV=""; TG_WN=1
  _tg_wrapper_opts "$1"
  case "$t" in
    --?*)
      for o in $TG_WL; do
        if _bd_is_opt "$t" "$o" "${o:0:3}"; then
          TG_WO="$o"
          case "$t" in *=*) TG_WV="${t#*=}" ;; *) TG_WV="$3"; TG_WN=2 ;; esac
          return 0
        fi
      done ;;
    -?*)
      _tg_short_bundle "$t" "$TG_WS" "$3" 0
      TG_WO="$TG_PO"; TG_WV="$TG_PV"; TG_WN="$TG_PN" ;;
  esac
  return 0
}

# The words of `env -S STRING`, into TG_SPLITW, and their expansion flags
# into TG_SPLITE. env splits STRING much as the shell does, but not exactly
# (inside its single quotes `\\` and `\'` are escapes): when STRING holds a
# backslash, every word of it is flagged as one this hook cannot read exactly.
_tg_split_words() {   # $1 = the text
  local -a TOK=() TOKE=() BD_HSTR=()
  _bd_words "$1"
  TG_SPLITW=(${TOK[@]+"${TOK[@]}"})
  TG_SPLITE=(${TOKE[@]+"${TOKE[@]}"})
  case "$1" in *\\*) TG_SPLITE=(${TG_SPLITE[@]+"${TG_SPLITE[@]/*/1}"}) ;; esac
}

# Sets TG_I to the index of the command word in TOK (n words), past
# assignments and wrappers, or to n when there is none. `env -S STRING` (and
# -S'...', --split-string=...) runs the words of STRING followed by the rest
# of the line, and reads options and assignments in them as its own: the
# words are put in place of the option in TOK, and the reading goes on.
# TG_XARGS=1 when xargs is among the wrappers: it appends words read from its
# input, which this hook cannot see, to the command. TG_EXECW=1 when exec is
# among them.
_tg_command_word() {
  local i=0 w t splits=0
  TG_XARGS=0; TG_EXECW=0
  # A reserved word or a group opener in command position starts a compound
  # command, and the command it runs is the next word: `if gh release create
  # v1; then`, `do gh pr merge 1`, `! git push`, `{ git push --tags; }`.
  # `function NAME` is followed by the body (`function f { git push; }`), and
  # coproc by the command it runs, or by a NAME and a body (`coproc N { ...;
  # }`). The parser splits at `(` and `)`, so `f() { ...; }`, a subshell and a
  # case pattern already start their own simple command.
  while [ "$i" -lt "$n" ]; do
    case "${TOK[i]}" in
      if|then|elif|else|while|until|do|'!'|'{') i=$((i + 1)) ;;
      function) i=$((i + 2)) ;;
      coproc)
        i=$((i + 1))
        [ "${TOK[i+1]:-}" = '{' ] && i=$((i + 1)) ;;
      *) _tg_is_assignment "${TOK[i]}" && i=$((i + 1)) || break ;;
    esac
  done
  while [ "$i" -lt "$n" ]; do
    [ "${#TOK[i]}" -le 4096 ] || break
    w=$(_tg_prog "${TOK[i]}")
    case "$w" in
      command|builtin|exec|env|nohup|time|nice|timeout|sudo|doas|xargs) ;;
      *) break ;;
    esac
    [ "$w" = xargs ] && TG_XARGS=1
    [ "$w" = exec ] && TG_EXECW=1
    i=$((i + 1))
    while [ "$i" -lt "$n" ]; do
      t="${TOK[i]}"
      if [ "$t" = "--" ]; then i=$((i + 1)); break; fi
      if [ "$w" = env ] && { _tg_is_assignment "$t" || [ "$t" = - ]; }; then i=$((i + 1)); continue; fi
      case "$t" in
        -?*)
          _tg_wrapper_opt "$w" "$t" "${TOK[i+1]:-}"
          if [ "$w" = env ] && { [ "$TG_WO" = S ] || [ "$TG_WO" = --split-string ]; } && [ "$splits" -lt 8 ]; then
            splits=$((splits + 1))
            _tg_split_words "$TG_WV"
            # TOKE, the words' expansion flags, moves with TOK.
            TOK=("${TOK[@]:0:i}" ${TG_SPLITW[@]+"${TG_SPLITW[@]}"} "${TOK[@]:i+TG_WN}")
            TOKE=("${TOKE[@]:0:i}" ${TG_SPLITE[@]+"${TG_SPLITE[@]}"} "${TOKE[@]:i+TG_WN}")
            n=${#TOK[@]}
            continue
          fi
          i=$((i + TG_WN)); continue ;;
      esac
      break
    done
    # timeout's first operand is the duration, not the command.
    [ "$w" = timeout ] && [ "$i" -lt "$n" ] && i=$((i + 1))
  done
  TG_I=$i
  return 0
}

# Emit one action line: key, a tab, the command summary, a tab, and the
# top of the repository a `git -C <dir>` push names (TG_ADIR, empty for the
# payload's own).
TG_ADIR=""
_tg_emit() {   # $1 = key, $2 = index of the command word
  # The words from the command word on; a word with a space in it is shown
  # in double quotes, so `--title "Add x"` does not read as two words.
  local s="" w k
  for ((k = $2; k < n; k++)); do
    w="${TOK[k]}"
    case "$w" in *[[:space:]]*|'') w="\"$w\"" ;; esac
    s="$s${s:+ }$w"
  done
  s="${s// __BD_SUBST__ /\$(...)}"
  s="${s//__BD_SUBST__/\$(...)}"
  s=$(printf '%s' "$s" | LC_ALL=C tr '\000-\037\177' ' ' | tr -s ' ')
  if [ "${#s}" -gt 160 ]; then s="${s:0:160}..."; fi
  printf '%s\t%s\t%s\n' "$1" "$s" "$TG_ADIR"
}

# The environment variables that choose where git reads its configuration or
# its repository from. One set before git, or exported earlier in the same
# command, can make a push send tags; GIT_CONFIG_NOSYSTEM can only drop a
# file, so it is not among them.
_tg_git_env_name() {   # $1 = a variable name
  case "$1" in
    GIT_CONFIG|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|GIT_CONFIG_PARAMETERS|\
    GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|HOME|XDG_CONFIG_HOME)
      return 0 ;;
  esac
  return 1
}

# git: the subcommand past git's own options. -C, --git-dir and --work-tree
# say which repository the push acts on; tags, push.followTags and the
# journal target are judged there (TG_GDIR and TG_GARGS, the arguments every
# lookup runs git with). A relative --git-dir or --work-tree is found from the
# directory the last -C names, as git finds it. When they name a repository
# that cannot be found, or are given as a variable, the payload's repository
# is used and the push asks if it could be a tag push (TG_UNRES=1). GIT_DIR=
# and GIT_WORK_TREE= before git count as --git-dir and --work-tree. A cd
# earlier in the command (TG_CDBASE, TG_CDOTHER) is where git starts.
#
# Configuration set for this one command can make a push send tags:
# `-c remote.<name>.mirror`, `-c remote.<name>.push=<refspec>`, a config file
# pulled in with include.path or includeIf.<condition>.path, the same keys
# through --config-env (`--config-env=<key>=<var>` or `--config-env
# <key>=<var>`), GIT_CONFIG_* (and HOME, XDG_CONFIG_HOME, GIT_DIR, ...) before
# git or exported earlier in the command (TG_GITENV). Each asks as a possible
# tag push (cfg=1). Setting the remote a push goes to (remote.pushDefault,
# branch.<name>.pushRemote, branch.<name>.remote) asks when the push names no
# remote (rcfg=1). push.followTags is read as git reads a boolean: false, no,
# off, 0 and the empty value are false, a bare key is true, and anything else
# is true or makes git stop; through --config-env it is unknown.
_tg_git() {   # $1 = index of git
  local j=$(($1 + 1)) follow="" c v o key t base="${TG_CDBASE:-$CWD}" gd="" wt="" explicit=0 cfg=0 rcfg=0 k ce
  [ "${TG_CDOTHER:-0}" = 1 ] && cfg=1
  [ "${TG_GITENV:-0}" = 1 ] && cfg=1
  [ "$base" = "$CWD" ] || explicit=1
  for ((k = 0; k < $1; k++)); do
    t="${TOK[k]}"
    _tg_is_assignment "$t" || continue
    # GIT_DIR+=... or GIT_DIR[0]=... appends to, or is, a value this hook
    # cannot see: not a directory it can find.
    case "$t" in
      GIT_DIR=*) gd="${t#GIT_DIR=}"; explicit=1 ;;
      GIT_WORK_TREE=*) wt="${t#GIT_WORK_TREE=}"; explicit=1 ;;
      *) _tg_git_env_name "$TG_AN" && cfg=1 ;;
    esac
  done
  while [ "$j" -lt "$n" ]; do
    c=""; ce=0; t="${TOK[j]}"
    case "$t" in
      -c) c="${TOK[j+1]:-}"; j=$((j + 2)) ;;
      -c?*) c="${t#-c}"; j=$((j + 1)) ;;
      # --config-env <key>=<variable>, in either spelling: the value is in
      # the environment.
      --config-env=*) c="${t#--config-env=}"; ce=1; j=$((j + 1)) ;;
      --config-env) c="${TOK[j+1]:-}"; ce=1; j=$((j + 2)) ;;
      -C)
        v="${TOK[j+1]:-}"; j=$((j + 2)); explicit=1
        case "$v" in /*) base="$v" ;; *) base="$base/$v" ;; esac
        continue ;;
      --git-dir|--git-dir=*|--work-tree|--work-tree=*)
        o="${t%%=*}"
        case "$t" in
          *=*) v="${t#*=}"; j=$((j + 1)) ;;
          *) v="${TOK[j+1]:-}"; j=$((j + 2)) ;;
        esac
        explicit=1
        if [ "$o" = --git-dir ]; then gd="$v"; else wt="$v"; fi
        continue ;;
      --namespace|--super-prefix|--list-cmds|--attr-source) j=$((j + 2)); continue ;;
      -*) j=$((j + 1)); continue ;;
      *) break ;;
    esac
    key=$(printf '%s' "${c%%=*}" | LC_ALL=C tr 'A-Z' 'a-z')
    case "$key" in
      push.followtags)
        if [ "$ce" = 1 ]; then follow=unknown
        else
          case "$c" in
            *=*) v=$(printf '%s' "${c#*=}" | LC_ALL=C tr 'A-Z' 'a-z')
                 case "$v" in ''|false|no|off|0) follow=0 ;; *) follow=1 ;; esac ;;
            *) follow=1 ;;
          esac
        fi ;;
      remote.*.mirror|remote.*.push|include.path|includeif.*.path) cfg=1 ;;
      remote.pushdefault|branch.*.pushremote|branch.*.remote) rcfg=1 ;;
    esac
  done
  [ "$j" -lt "$n" ] || return 0
  [ "${TOK[j]}" = push ] || return 0

  # git finds a relative --git-dir, --work-tree, GIT_DIR or GIT_WORK_TREE
  # from the directory it is in after every -C.
  [ -n "$gd" ] && case "$gd" in /*) ;; *) gd="$base/$gd" ;; esac
  [ -n "$wt" ] && case "$wt" in /*) ;; *) wt="$base/$wt" ;; esac
  TG_GDIR="$base"; TG_GARGS=(); TG_UNRES=0; TG_ADIR=""
  [ -n "$gd" ] && TG_GARGS+=("--git-dir=$gd")
  [ -n "$wt" ] && TG_GARGS+=("--work-tree=$wt")
  if [ "$explicit" = 1 ]; then
    # A directory given as a variable or a substitution names a path that
    # does not exist, so it is not found here either.
    if [ -d "$base" ] \
       && git -C "$base" ${TG_GARGS[@]+"${TG_GARGS[@]}"} rev-parse --git-dir >/dev/null 2>&1; then
      TG_ADIR=$(git -C "$base" ${TG_GARGS[@]+"${TG_GARGS[@]}"} rev-parse --show-toplevel 2>/dev/null) || TG_ADIR=""
    else
      TG_GDIR="$CWD"; TG_GARGS=(); TG_UNRES=1
    fi
  fi
  # push.followTags from git's configuration, unless a -c set it. Unknown when
  # the repository could not be found.
  if [ -z "$follow" ]; then
    if [ "$TG_UNRES" = 1 ]; then follow=unknown
    elif [ "$(_tg_git_in config --type=bool --get push.followTags 2>/dev/null)" = true ]; then follow=1
    else follow=0
    fi
  fi
  _tg_git_push "$1" $((j + 1)) "$follow" "$cfg" "$rcfg"
  TG_ADIR=""
  return 0
}

# git, run in the repository the push acts on.
_tg_git_in() { git -C "$TG_GDIR" ${TG_GARGS[@]+"${TG_GARGS[@]}"} "$@"; }

# What a name is in the repository the push acts on: tag, branch (a local
# branch, or a remote-tracking one on the remote being pushed to), or
# unknown. Unknown too when that repository could not be found.
_tg_ref_kind() {   # $1 = name, $2 = remote
  case "$1" in ''|*'*'*) printf unknown; return 0 ;; esac
  [ "${TG_UNRES:-0}" = 1 ] && { printf unknown; return 0; }
  if _tg_git_in rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then printf tag
  elif _tg_git_in rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1 \
       || { [ -n "$2" ] && _tg_git_in rev-parse -q --verify "refs/remotes/$2/$1" >/dev/null 2>&1; }; then printf branch
  else printf unknown
  fi
}

# Is this name a local branch of the repository the push acts on? A
# revision suffix (`main~1`, `HEAD^`) names a commit on that branch.
_tg_is_local_branch() {   # $1 = name
  local b="${1%%[~^]*}"
  case "$b" in HEAD|@) return 0 ;; ''|*'*'*) return 1 ;; esac
  [ "${TG_UNRES:-0}" = 1 ] && return 1
  case "$b" in refs/heads/?*) b="${b#refs/heads/}" ;; esac
  _tg_git_in rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1
}

# The remote a push that names none goes to, found as git finds it:
# branch.<branch>.pushRemote, remote.pushDefault, branch.<branch>.remote,
# then origin.
_tg_push_remote() {
  local b r=""
  b=$(_tg_git_in symbolic-ref -q --short HEAD 2>/dev/null) || b=""
  [ -n "$b" ] && r=$(_tg_git_in config --get "branch.$b.pushRemote" 2>/dev/null)
  [ -n "$r" ] || r=$(_tg_git_in config --get remote.pushDefault 2>/dev/null)
  [ -n "$b" ] && [ -z "$r" ] && r=$(_tg_git_in config --get "branch.$b.remote" 2>/dev/null)
  printf '%s' "${r:-origin}"
}

# Does a remote's configuration push tags? Prints mirror when
# remote.<name>.mirror is true, and otherwise its remote.<name>.push
# refspecs, one per line. An empty name (the remote is a variable) stands for
# every remote: mirror when any of them mirrors, and every configured push
# refspec.
_tg_remote_config() {   # $1 = remote name, or empty for any
  local line
  if [ -n "$1" ]; then
    [ "$(_tg_git_in config --type=bool --get "remote.$1.mirror" 2>/dev/null)" = true ] && { printf 'mirror\n'; return 0; }
    _tg_git_in config --get-all "remote.$1.push" 2>/dev/null
    return 0
  fi
  while IFS= read -r line; do
    case "$line" in
      *.mirror\ *) [ "$(_tg_git_in config --type=bool --get "${line%% *}" 2>/dev/null)" = true ] && { printf 'mirror\n'; return 0; } ;;
    esac
  done <<TG_RC_EOF
$(_tg_git_in config --get-regexp '^remote\..*\.mirror$' 2>/dev/null)
TG_RC_EOF
  _tg_git_in config --get-regexp '^remote\..*\.push$' 2>/dev/null | sed 's/^[^ ]* //'
  return 0
}

# git push's long options, read the way git reads them: any unambiguous
# prefix counts (`--tag`, `--mirr`, `--follow-tag`, `--del`, `--force-w`).
# `--force` is a prefix of --force-with-lease and --force-if-includes, so only
# its full spelling is --force. Prints the option's full name, or nothing for
# one this hook does not need.
_tg_push_long() {   # $1 = the word, without any =value
  local o
  for o in --tags:--ta --mirror:--m --follow-tags:--fol --delete:--de \
           --repo:--rep --receive-pack:--rece --exec:--e --push-option:--pu \
           --recurse-submodules:--recu --force:--force --force-with-lease:--force-w; do
    if _bd_is_opt "$1" "${o%%:*}" "${o#*:}"; then printf '%s' "${o%%:*}"; return 0; fi
  done
  case "$1" in
    --no-?*) _bd_is_opt "--${1#--no-}" --follow-tags --fol && printf '%s' --no-follow-tags ;;
  esac
  return 0
}

# git push: a tag push is the release tier, a branch push the push tier.
# A tag is pushed by --tags, --follow-tags, --mirror, push.followTags,
# `tag <name>`, a refspec naming refs/tags/ on either side, a source or a
# destination that is the name of a tag in the repository (a branch named
# v1-fix is not a tag), or a `tags/<name>` source. A tag is deleted by
# `:<tag>` or --delete/-d <tag>; a name deleted that is neither a tag nor a
# known branch may be a tag on the remote. Any other source that is not a
# local branch (a name that does not exist yet, a commit, a glob such as
# refs/*:refs/*, a remote-tracking branch) may be a tag, and a refspec this
# hook cannot read may be one: both ask. A forced push (-f, --force,
# --force-with-lease, a `+` refspec) to a destination not under refs/ that is
# neither a local branch nor a branch known on that remote may move a tag
# that exists only on the remote (git finds the destination there), so it
# asks; without force git refuses to move a tag.
#
# The remote is the first word, else --repo's value, else the one git picks
# (_tg_push_remote). Its configuration counts too: remote.<name>.mirror makes
# every push to it a tag push, and its remote.<name>.push refspecs are read as
# if written when the command names none. Command-line settings of those keys
# ask ($4), and so do settings of the keys that pick the remote when the
# command names none ($5).
_tg_git_push() {   # $1 = index of git, $2 = first word after push, $3 = followTags (1, 0, unknown), $4 = 1 when the command sets configuration that may push tags, $5 = 1 when it sets the keys that pick the remote
  local j k t o c f rest tag=0 unread=0 del=0 nofollow=0 force=0 words=() specs=() r src dst w name kind remote="" repo="" line
  for ((k = $2; k < n; k++)); do
    t="${TOK[k]}"
    # An option whose name this hook cannot read (`--$X`, `-$F`) may be
    # --tags, --mirror, --follow-tags or -d. A value is not its name: the
    # text after `=`, or after the o of a short bundle (`-o$MSG`).
    case "$t" in
      --?*) _tg_unreadable "${t%%=*}" && { unread=1; continue; } ;;
      -?*) _tg_unreadable "${t%%o*}" && { unread=1; continue; } ;;
    esac
    case "$t" in
      --) for ((j = k + 1; j < n; j++)); do words+=("${TOK[j]}"); done; k=$n ;;
      --*)
        o=$(_tg_push_long "${t%%=*}")
        case "$o" in
          --tags|--follow-tags|--mirror) tag=1 ;;
          --no-follow-tags) nofollow=1 ;;
          --delete) del=1 ;;
          --force|--force-with-lease) force=1 ;;
          --repo)
            case "$t" in *=*) repo="${t#*=}" ;; *) repo="${TOK[k+1]:-}"; k=$((k + 1)) ;; esac ;;
          --receive-pack|--exec|--push-option|--recurse-submodules)
            case "$t" in *=*) ;; *) k=$((k + 1)) ;; esac ;;
        esac ;;
      -?*)
        # A bundle of short options (`-qd`, `-fdu`): d is --delete, f is
        # --force; o takes the rest of the word as its value, or the next word.
        rest="${t#-}"
        while [ -n "$rest" ]; do
          c="${rest:0:1}"; rest="${rest:1}"
          case "$c" in
            d) del=1 ;;
            f) force=1 ;;
            o) [ -z "$rest" ] && k=$((k + 1)); break ;;
          esac
        done ;;
      -) ;;
      *) words+=("$t") ;;
    esac
  done
  if [ "$nofollow" = 0 ]; then
    case "$3" in 1) tag=1 ;; unknown) unread=1 ;; esac
  fi
  [ "${4:-0}" = 1 ] && unread=1
  # Words xargs appends from its input may be refspecs, or the remote.
  [ "${TG_XARGS:-0}" = 1 ] && unread=1
  # words[0] is the remote; the rest are refspecs. A remote this hook cannot
  # read (`git push $OPTS`, `git push $'--tags'`) may be an option as well:
  # --tags, --mirror or --follow-tags.
  [ -n "${words[0]:-}" ] && _tg_unreadable "${words[0]}" && unread=1
  for ((w = 1; w < ${#words[@]}; w++)); do specs+=("${words[w]}"); done
  if [ "${TG_UNRES:-0}" = 1 ]; then
    # The repository is unknown, so its remotes' configuration is too.
    unread=1
  else
    remote="${words[0]:-}"
    [ -z "$remote" ] && remote="$repo"
    if [ -z "$remote" ]; then
      # The command names no remote: a setting of the keys that pick one,
      # for this command, may pick a mirror.
      [ "${5:-0}" = 1 ] && unread=1
      # After a cd into another worktree of this repository the branch, and
      # so the remote it picks, depends on whether that cd applied (_tg_cd).
      [ "${TG_CDWT:-0}" = 1 ] && unread=1
      remote=$(_tg_push_remote)
    fi
    # A remote given as a variable may be any of them: a mirror among them,
    # or a push refspec that is not plainly a branch's, may push a tag.
    _tg_unreadable "$remote" && remote=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ -z "$remote" ]; then
        case "$line" in
          mirror) unread=1 ;;
          *) [ "${#words[@]}" -le 1 ] && case "${line#+}" in *refs/tags/*) unread=1 ;; *:refs/heads/*|refs/heads/*) ;; *) unread=1 ;; esac ;;
        esac
      elif [ "$line" = mirror ]; then tag=1
      elif [ "${#words[@]}" -le 1 ]; then specs+=("$line")
      fi
    done <<TG_PUSH_EOF
$(_tg_remote_config "$remote")
TG_PUSH_EOF
  fi
  for ((w = 0; w < ${#specs[@]}; w++)); do
    r="${specs[w]}"
    if [ "$r" = tag ] && [ $((w + 1)) -lt ${#specs[@]} ]; then tag=1; w=$((w + 1)); continue; fi
    if _tg_unreadable "$r"; then unread=1; continue; fi
    f="$force"
    case "$r" in +*) f=1; r="${r#+}" ;; esac
    src="${r%%:*}"
    case "$r" in *:*) dst="${r#*:}" ;; *) dst="" ;; esac
    case "$src $dst" in *refs/tags/*) tag=1; continue ;; esac
    case "$dst" in refs/heads/*) continue ;; esac
    if [ "$del" = 1 ] || [ -z "$src" ]; then
      # A deletion names the remote ref: a tag, a branch, or unknown.
      name="${dst:-$src}"
      case "$name" in refs/heads/*) continue ;; esac
      kind=$(_tg_ref_kind "$name" "$remote")
      case "$kind" in tag) tag=1 ;; unknown) unread=1 ;; esac
      continue
    fi
    # A destination that is a tag here is that tag on the remote. Forced, a
    # destination that is not a branch known here may be a tag there.
    case "$dst" in
      ''|refs/*) ;;
      *)
        kind=$(_tg_ref_kind "$dst" "$remote")
        [ "$kind" = tag ] && { tag=1; continue; }
        [ "$f" = 1 ] && [ "$kind" != branch ] && unread=1 ;;
    esac
    case "$src" in tags/?*) tag=1; continue ;; refs/heads/*) continue ;; esac
    if [ "$(_tg_ref_kind "$src" "")" = tag ]; then tag=1
    elif ! _tg_is_local_branch "$src"; then unread=1
    fi
  done
  if [ "$tag" = 1 ]; then _tg_emit release "$1"
  elif [ "$unread" = 1 ]; then _tg_emit tagUnread "$1"
  else _tg_emit push "$1"
  fi
}

# The text of a GraphQL query given as a field value or a file: prints it, or
# returns 1 when it cannot be read (a variable, a substitution, stdin, a file
# that is not there). A `$` inside the query is a GraphQL variable, so only a
# value that is wholly a variable counts as unreadable. A relative file is
# found where the command runs, after any cd earlier in it.
_tg_query_text() {   # $1 = the value after query=, or @file
  local v="$1" f
  case "$v" in
    '$'*|__BD_SUBST__*|'`'*) return 1 ;;
    @*)
      f="${v#@}"
      case "$f" in ''|-|*'$'*|*__BD_SUBST__*) return 1 ;; esac
      case "$f" in /*) ;; *) f="${TG_CDBASE:-$CWD}/$f" ;; esac
      [ -f "$f" ] && [ -r "$f" ] || return 1
      head -c 200000 "$f" 2>/dev/null || return 1 ;;
    *) printf '%s' "$v" ;;
  esac
}

# A GraphQL document without its string values ("...", with \" escapes, and
# """...""" blocks) and its # comments, so a name inside a string or a
# comment (`body:"merge(x)"`) is not read as a field. One left-to-right pass,
# so a quote inside a comment opens no string. A query typed on the command
# line has lost its line ends (the parser joins the lines of a quoted
# argument), so there a comment's end cannot be seen: from the first comment
# on, the rest is kept as written ($2 = 0). From a file the line ends are
# real ($2 = 1). A string that does not end is kept as written from its
# opening quote on.
_tg_gql_strip() {   # $1 = the text, $2 = 1 when its line ends are real
  printf '%s\n' "$1" | LC_ALL=C awk -v real="$2" '
    BEGIN { st = ""; raw = 0; braw = "" }
    {
      line = $0; out = ""
      if (raw) { print line; next }
      while (line != "") {
        if (st == "B") {
          p = index(line, "\"\"\"")
          if (p == 0) { braw = braw line "\n"; line = ""; break }
          if (p > 1 && substr(line, p - 1, 1) == "\\") { braw = braw substr(line, 1, p + 2); line = substr(line, p + 3); continue }
          st = ""; braw = ""; out = out " "; line = substr(line, p + 3); continue
        }
        if (st == "S") {
          p = match(line, /[\\"]/)
          if (p == 0) { out = out sraw line; line = ""; st = ""; raw = 1; break }
          if (substr(line, p, 1) == "\\") { sraw = sraw substr(line, 1, p + 1); line = substr(line, p + 2); continue }
          st = ""; sraw = ""; out = out " "; line = substr(line, p + 1); continue
        }
        p = match(line, /["#]/)
        if (p == 0) { out = out line; line = ""; break }
        out = out substr(line, 1, p - 1)
        if (substr(line, p, 1) == "#") {
          if (!real) { out = out substr(line, p); raw = 1 }
          line = ""; break
        }
        if (substr(line, p, 3) == "\"\"\"") { st = "B"; braw = "\"\"\""; line = substr(line, p + 3); continue }
        st = "S"; sraw = "\""; line = substr(line, p + 1)
      }
      if (st == "S") { out = out sraw; st = ""; raw = 1 }
      print out
    }
    END { if (st == "B") printf "%s", braw }
  '
}

# pflag (gh's option parser) reads a bundle of short options as getopt
# does (_tg_short_bundle), and also takes `=value` (`-X=POST`).
_tg_pflag_short() {   # $1 = the word, $2 = the letters that take a value, $3 = the next word
  _tg_short_bundle "$1" "$2" "$3" 1
}

# What a gh api request with this method does, one key per line: merge,
# release, tagUnread, prCreate, issueCreate, issueAssign, assignUnread. Reads
# ep, fields and input of _tg_api. A field is `f:name=value` (-f, a raw
# string) or `F:name=value` (-F, where a value `@file` or `@-` is read from
# that file or stdin).
_tg_api_keys() {   # $1 = method (POST, PUT, PATCH or DELETE)
  local m="$1" fv ft name refs="" have=0 unr=0
  # A tag ref deleted or moved (DELETE or PATCH on .../git/refs/tags/<tag>)
  # is a tag push. A ref whose last part cannot be read may be a tag.
  if [ "$m" = DELETE ] || [ "$m" = PATCH ]; then
    case "$ep" in
      */git/refs/tags/*) printf 'release\n'; return 0 ;;
      */git/refs/*)
        case "${ep##*/git/refs/}" in heads/*) ;; *) _tg_unreadable "$ep" && { printf 'tagUnread\n'; return 0; } ;; esac ;;
      # Deleting a release or one of its files.
      */releases/*) [ "$m" = DELETE ] && { printf 'release\n'; return 0; } ;;
    esac
    [ "$m" = DELETE ] && return 0
  fi
  # PATCH: editing or publishing a release, and changing an issue's
  # assignees. (PUT on an issue is matched the same way.)
  if [ "$m" = PATCH ] || [ "$m" = PUT ]; then
    case "$ep" in
      */releases/*/*) ;;
      */releases/*) [ "$m" = PATCH ] && { printf 'release\n'; return 0; } ;;
      */issues/*/*) ;;
      */issues/*)
        for fv in "${fields[@]+"${fields[@]}"}"; do
          name="${fv#?:}"; name="${name%%=*}"
          case "$name" in
            assignee|assignees|'assignees[]') printf 'issueAssign\n'; return 0 ;;
          esac
          _tg_unreadable "$name" && unr=1
        done
        # A body from a file, or a field whose name cannot be read, may
        # change the assignees; that is not a confirm-floor action, so it is
        # allowed with a note.
        { [ -n "$input" ] || [ "$unr" = 1 ]; } && printf 'assignUnread\n'
        return 0 ;;
    esac
    [ "$m" = PATCH ] && return 0
  fi
  case "$ep" in
    */git/refs)
      # Creating a tag ref is a tag push. A ref that cannot be read (a
      # variable, a -F value read from a file or stdin, a field whose name
      # cannot be read, or --input) may be a tag.
      for fv in "${fields[@]+"${fields[@]}"}"; do
        ft="${fv%%:*}"; fv="${fv#?:}"; name="${fv%%=*}"
        if _tg_unreadable "$name"; then unr=1; continue; fi
        [ "$name" = ref ] || continue
        have=1; fv="${fv#ref=}"
        case "$ft:$fv" in F:@*) unr=1 ;; esac
        refs="$refs $fv"
      done
      case "$refs" in
        *refs/tags/*) printf 'release\n' ;;
        *'$'*|*__BD_SUBST__*) printf 'tagUnread\n' ;;
        *) { [ "$have" = 0 ] || [ -n "$input" ] || [ "$unr" = 1 ]; } && printf 'tagUnread\n' ;;
      esac ;;
    */pulls/*/merge|*/merges) printf 'merge\n' ;;
    */releases|*/releases/*/assets) printf 'release\n' ;;
    */pulls) printf 'prCreate\n' ;;
    */issues) printf 'issueCreate\n' ;;
    */issues/*/assignees) printf 'issueAssign\n' ;;
  esac
  return 0
}

# gh api: the effective method, the endpoint and the fields, read as gh's
# option parser reads them: -X VALUE, -XVALUE, -X=VALUE, a bundle (-iX=POST),
# --method VALUE and --method=VALUE; -f/-F/--raw-field/--field the same way.
_tg_api() {   # $1 = index of gh, $2 = index of the word api
  local k=$(($2 + 1)) t o v adv method="" mset=0 any=0 ep="" after=0 input="" fv keys key m qi
  # fexp: for each field, 1 when the shell expands something in the word that
  # holds its value (TOKE), so the text gh receives cannot be read here.
  local -a fields=() fexp=()
  while [ "$k" -lt "$n" ]; do
    t="${TOK[k]}"
    if [ "$after" = 1 ]; then [ -z "$ep" ] && ep="$t"; k=$((k + 1)); continue; fi
    o=""; v=""; adv=1
    case "$t" in
      --) after=1 ;;
      --*=*) o="${t%%=*}"; v="${t#*=}" ;;
      --method|--raw-field|--field|--input|--header|--jq|--template|--hostname|--preview|--cache)
        o="$t"; adv=2
        if [ $((k + 1)) -lt "$n" ]; then v="${TOK[k+1]}"; elif [ "$t" = --input ]; then v=-; fi ;;
      --*|-) ;;
      -?*)
        _tg_pflag_short "$t" XfFHpqt "${TOK[k+1]:-}"
        [ -n "$TG_PO" ] && { o="-$TG_PO"; v="$TG_PV"; adv=$TG_PN; } ;;
      *) [ -z "$ep" ] && ep="$t" ;;
    esac
    case "$o" in
      -X|--method) method="$v"; mset=1 ;;
      -f|--raw-field|-F|--field)
        case "$o" in -f|--raw-field) fields+=("f:$v") ;; *) fields+=("F:$v") ;; esac
        fexp+=("${TOKE[k + adv - 1]:-1}") ;;
      --input) input="${v:--}" ;;
    esac
    k=$((k + adv))
  done
  # Under xargs the endpoint may be a word it appends from its input.
  if [ -z "$ep" ]; then
    [ "${TG_XARGS:-0}" = 1 ] || return 0
    # A literal `$`: an endpoint read as a variable, which cannot be read.
    # shellcheck disable=SC2016
    ep='$XARGS'
  fi

  # GraphQL: the mutation names decide, read from -f/-F query=..., a
  # query=@file, or the --input body (JSON, read as written).
  case "$ep" in
    graphql|/graphql|*/graphql)
      local text="" unread=0 found=0 qs
      for ((qi = 0; qi < ${#fields[@]}; qi++)); do
        fv="${fields[qi]#?:}"
        case "$fv" in
          query=*) found=1
            v="${fv#query=}"
            # The query as bash hands it to gh: the words keep a backslash
            # where bash keeps one (inside single quotes, and inside double
            # quotes before any character but $ ` " \), so the string
            # boundaries below are gh's. A query in which bash expands
            # something (`"... $FIELD(...)"`) cannot be read; one written
            # `\$id` or '$id' holds a GraphQL variable, and can.
            if [ "${fexp[qi]:-1}" = 1 ] && case "$v" in @*) false ;; *) true ;; esac; then
              unread=1
            elif t=$(_tg_query_text "$v"); then
              case "$v" in @*) qs=1 ;; *) qs=0 ;; esac
              t=$(_tg_gql_strip "$t" "$qs") || true
              text="$text $t"
            else unread=1; fi ;;
        esac
      done
      if [ -n "$input" ]; then
        found=1
        if t=$(_tg_query_text "@$input"); then text="$text $t"; else unread=1; fi
      fi
      [ "$found" = 1 ] || return 0
      for m in $(printf '%s' "$text" | grep -owE 'mergePullRequest|enablePullRequestAutoMerge|createRelease|updateRelease|createPullRequest|createIssue|addAssigneesToAssignable' | LC_ALL=C sort -u); do
        case "$m" in
          mergePullRequest|enablePullRequestAutoMerge) _tg_emit merge "$1" ;;
          createRelease|updateRelease) _tg_emit release "$1" ;;
          createPullRequest) _tg_emit prCreate "$1" ;;
          createIssue) _tg_emit issueCreate "$1" ;;
          addAssigneesToAssignable) _tg_emit issueAssign "$1" ;;
        esac
      done
      # Any other mutation field whose name holds Merge, Release or Ref, in
      # any case (mergeBranch, enqueuePullRequest, deleteRelease, createRef,
      # updateRef, deleteRef, updateRefs): a field is a name followed by its
      # arguments. Only in a document that has a mutation; a query that
      # reads refs or mergeable changes nothing. disablePullRequestAutoMerge
      # turns a merge off.
      case "$text" in
        *mutation*)
          local fm=0 fr=0
          for m in $(printf '%s' "$text" | grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' | LC_ALL=C tr -d '(\t ' | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sort -u); do
            case "$m" in
              mutation|mergepullrequest|enablepullrequestautomerge|createrelease|updaterelease|disablepullrequestautomerge) ;;
              *merge*|enqueuepullrequest) fm=1 ;;
              *release*|*ref*) fr=1 ;;
            esac
          done
          [ "$fm" = 1 ] && _tg_emit merge "$1"
          [ "$fr" = 1 ] && _tg_emit release "$1" ;;
      esac
      [ "$unread" = 1 ] && _tg_emit unknown "$1"
      return 0 ;;
  esac

  # The method: given, else POST when a field or a body is given (gh's own
  # rule), else GET. GET and HEAD change nothing. A method that is a variable,
  # or that is not one of the verbs, cannot be read: any write may be meant.
  if [ "$mset" = 0 ]; then
    if [ "${#fields[@]}" -gt 0 ] || [ -n "$input" ]; then method=POST; else method=GET; fi
  fi
  if _tg_unreadable "$method"; then any=2
  else
    method=$(printf '%s' "$method" | LC_ALL=C tr 'a-z' 'A-Z')
    case "$method" in GET|HEAD) return 0 ;; POST|PUT|PATCH|DELETE) ;; *) any=1 ;; esac
  fi
  # A whole endpoint this hook cannot read may be a merge or a release. A
  # partly unreadable one is read by its literal parts: `/merge` would have
  # to be written.
  case "$ep" in
    */*) ;;
    *) if _tg_unreadable "$ep"; then _tg_emit unknown "$1"; return 0; fi ;;
  esac
  # Matched by the end of the path, so a leading `/`, a full URL and
  # `{owner}/{repo}` all read the same; a query string and trailing slashes
  # are not part of the path. A percent-encoded character is read decoded, as
  # the server reads it (`git/refs/tags%2Fv1`, `%72eleases`).
  ep="${ep%%\?*}"
  case "$ep" in *%[0-9A-Fa-f][0-9A-Fa-f]*) ep=$(printf '%b' "${ep//%/\\x}") ;; esac
  while :; do case "$ep" in */) ep="${ep%/}" ;; *) break ;; esac; done

  if [ "$any" = 0 ]; then
    keys=$(_tg_api_keys "$method")
  else
    # Any write: a Tier 3 result under any of them asks as unreadable. A
    # variable method (any=2) may be POST, so its Tier 2 results count too;
    # a verb that is not one (OPTIONS) writes nothing those would.
    keys=$(for m in POST PUT PATCH DELETE; do _tg_api_keys "$m"; done | LC_ALL=C sort -u)
    case "$keys" in
      *merge*|*release*|*tagUnread*) _tg_emit unknown "$1"; return 0 ;;
    esac
    [ "$any" = 2 ] || return 0
  fi
  while IFS= read -r key; do
    [ -n "$key" ] && _tg_emit "$key" "$1"
  done <<TG_KEYS_EOF
$keys
TG_KEYS_EOF
  return 0
}

# gh release create: with --verify-tag and a literal tag, emit
# releaseVerified:<tag>:<repo> so the caller can check that gh creates the
# release in origin's repository and that the tag is already on origin;
# otherwise release. The repository is -R/--repo (in any form gh's option
# parser reads: -R o/r, -Ro/r, -R=o/r, a bundle such as -dR o/r), else a
# GH_REPO= before gh, else GH_REPO in this hook's environment, else gh's
# default. GH_HOST, GH_REPO+= or GH_REPO[i]= before gh, or a cd or a
# GH_REPO/GH_HOST setting earlier in the command (TG_GHMOVED), makes it a
# plain release. A tag name cannot hold a `:`.
_tg_release() {   # $1 = index of gh, $2 = index of the word create
  local k t tag="" verify=0 repo="" envrepo="" moved="${TG_GHMOVED:-0}"
  for ((k = $2 + 1; k < n; k++)); do
    t="${TOK[k]}"
    case "$t" in
      --verify-tag) verify=1 ;;
      --repo) repo="${TOK[k+1]:-}"; k=$((k + 1)) ;;
      --repo=*) repo="${t#--repo=}" ;;
      --title|--notes|--notes-file|--target|--discussion-category|--notes-start-tag|--assets) k=$((k + 1)) ;;
      --*|-) ;;
      -?*)
        _tg_pflag_short "$t" RtnFA "${TOK[k+1]:-}"
        [ "$TG_PO" = R ] && repo="$TG_PV"
        k=$((k + TG_PN - 1)) ;;
      *) [ -z "$tag" ] && tag="$t" ;;
    esac
  done
  # -R before `release` belongs to gh too.
  for ((k = $1 + 1; k < $2; k++)); do
    t="${TOK[k]}"
    case "$t" in
      --repo) repo="${TOK[k+1]:-}"; k=$((k + 1)) ;;
      --repo=*) repo="${t#--repo=}" ;;
      --*|-) ;;
      -?*)
        _tg_pflag_short "$t" R "${TOK[k+1]:-}"
        [ "$TG_PO" = R ] && repo="$TG_PV"
        k=$((k + TG_PN - 1)) ;;
    esac
  done
  for ((k = 0; k < $1; k++)); do
    t="${TOK[k]}"
    case "$t" in
      GH_REPO=*) envrepo="${t#GH_REPO=}" ;;
      GH_HOST=*) moved=1 ;;
      # GH_REPO+=... or GH_REPO[0]=...: a value this hook cannot see.
      *) _tg_is_assignment "$t" && case "$TG_AN" in GH_REPO|GH_HOST) moved=1 ;; esac ;;
    esac
  done
  [ -n "${GH_HOST:-}" ] && moved=1
  [ -n "$repo" ] || repo="$envrepo"
  [ -n "$repo" ] || repo="${GH_REPO:-}"
  # A repository given as a variable cannot be compared with origin. A tag
  # given as one is looked up as written, and is not found.
  if [ "$verify" = 1 ] && [ -n "$tag" ] && [ "$moved" = 0 ] && ! _tg_unreadable "$repo"; then
    case "$tag$repo" in *:*|*[[:space:]]*) _tg_emit release "$1"; return 0 ;; esac
    _tg_emit "releaseVerified:$tag:$repo" "$1"
  else
    _tg_emit release "$1"
  fi
}

# gh: the two subcommand words past options.
_tg_gh() {   # $1 = index of gh
  local j=$(($1 + 1)) w1="" w2="" i2=-1 t k
  while [ "$j" -lt "$n" ]; do
    t="${TOK[j]}"
    case "$t" in
      --repo|--hostname) j=$((j + 2)); continue ;;
      --*|-) j=$((j + 1)); continue ;;
      -?*) _tg_pflag_short "$t" R "${TOK[j+1]:-}"; j=$((j + TG_PN)); continue ;;
    esac
    if [ -z "$w1" ]; then
      w1="$t"
      [ "$w1" = api ] && { _tg_api "$1" "$j"; return 0; }
    else
      w2="$t"; i2=$j; break
    fi
    j=$((j + 1))
  done
  # A subcommand word this hook cannot read (`gh $SUB merge 7`, `gh pr $A 7`,
  # `gh pr $'m\x65rge' 7`) may be merge or a release subcommand. Not when the
  # program itself is a variable read as possibly gh (`$EDITOR "$f"`): that is
  # a whole command this hook cannot read, which it does not guess at.
  if ! _tg_unreadable "${TOK[$1]}"; then
    if _tg_unreadable "$w1"; then _tg_emit unknown "$1"; return 0; fi
    case "$w1" in
      pr|release) _tg_unreadable "$w2" && { _tg_emit unknown "$1"; return 0; } ;;
    esac
  fi
  case "$w1 $w2" in
    "pr create"|"pr new") _tg_emit prCreate "$1" ;;
    "pr merge") _tg_emit merge "$1" ;;
    "issue create"|"issue new") _tg_emit issueCreate "$1" ;;
    "release create"|"release new") _tg_release "$1" "$i2" ;;
    # edit publishes a draft (--draft=false) or moves its tag; delete removes
    # a release (and its tag, with --cleanup-tag); upload and delete-asset
    # change the files people download from it.
    "release edit"|"release delete"|"release upload"|"release delete-asset") _tg_emit release "$1" ;;
    "issue edit")
      for ((k = i2 + 1; k < n; k++)); do
        case "${TOK[k]}" in
          --add-assignee|--add-assignee=*) _tg_emit issueAssign "$1"; break ;;
        esac
      done ;;
  esac
  return 0
}

# A program this hook does not know may run the rest of its line as a
# command: caffeinate, stdbuf, setsid, watch, `find -exec`, parallel,
# `script -q /dev/null`, and any other. So the words after it are read for gh
# or git, and what each would do is kept when it is a Tier 3 action (a merge,
# a release, a tag push or a possible one, a gh api call that cannot be read)
# and dropped otherwise: `npm run git push` names no action, and a Tier 2
# action there would cost a prompt for every script that merely mentions
# git. A command word that is a variable or a substitution (`$GH pr merge 7`)
# may be gh or git itself; one with nothing after it (`$CMD`) is a whole
# command this hook cannot read, and asks. A word with a space in it (a quoted
# argument, as in `watch 'gh release create v9'`, `script -c '...'`, `trap
# '...' EXIT`, `awk 'BEGIN { system("...") }'`) may be a whole command, and is
# read as one, for the same Tier 3 actions, unless the parser already read it
# as a command of its own (it does for every such word after bash, env, ssh
# and the other words lib/command-parse.sh treats as running a script) or it
# could not hold one (_tg_may_run). A git config, a branch change or a write
# to .git in such a word changes the repository for every later push, as it
# does on its own (_tg_config_prescan). Some programs join their arguments
# into one shell command (`ssh host gh\ pr merge 1`, `watch "gh pr" merge 1`,
# `sudo -s`), so when a word after the program holds a space or a character
# the shell reads specially, the words from the program on are also read
# joined with spaces, as one command. A shell among the words that reads its
# script from its input asks (_bd_shell_reads_stdin). The --verify-tag
# exemption does not apply here. At most TG_SCAN_MAX (16) quoted words,
# here-strings and joined readings are read per simple command; one more that
# could hold a Tier 3 action is read as an unreadable gh call, which asks.
TG_SCAN_MAX=16
_tg_scan() {   # $1 = index of the command word
  local k t p out line start=$(($1 + 1)) interp=0 reads=0 over=0 joined="" join=0 texts=()
  if _tg_unreadable "${TOK[$1]}"; then
    start=$1
    [ "$(($1 + 1))" -ge "$n" ] && { _tg_emit unknown "$1"; return 0; }
  fi
  # interp=1 once a word the parser treats as running a script has been
  # passed: every quoted word after it is already a command of its own.
  for ((k = 0; k <= $1; k++)); do
    p="${TOK[k]}"
    [ "${#p}" -le 4096 ] && _bd_is_interpreter "$p" && interp=1
  done
  for ((k = $1; k < n; k++)); do
    t="${TOK[k]}"
    out=""
    if [ "$k" -gt "$1" ]; then
      p="${TOK[k-1]}"
      [ "${#p}" -le 4096 ] && _bd_is_interpreter "$p" && interp=1
    fi
    # The command word counts too: after `sudo -s` it is the first word of
    # the joined command (`sudo -s gh\ release create v9`).
    case "$t" in *[[:space:]\;\|\&\<\>\(\)\`]*) join=1 ;; esac
    case "$t" in
      *[[:space:]]*)
        [ "$interp" = 0 ] || continue
        [ "${#texts[@]}" -lt "$TG_SCAN_MAX" ] && _tg_persist_hint "$t" && texts+=("$t")
        if _tg_may_run "$t"; then
          if [ "$reads" -ge "$TG_SCAN_MAX" ]; then over=1; continue; fi
          reads=$((reads + 1))
          out=$(_tg_read_text "$t" $((TG_DEPTH + 1)))
        fi ;;
      *)
        [ "$k" -ge "$start" ] || continue
        [ "${#t}" -le 4096 ] || continue
        case "${t##*/}" in
          [Gg][Hh]) out=$(_tg_gh "$k") ;;
          [Gg][Ii][Tt]) out=$(_tg_git "$k") ;;
          *)
            if [ "$k" -gt "$1" ] && [ "$TG_RIN" = 0 ] && _bd_shell_reads_stdin "$k"; then
              _tg_emit shell "$k"; continue
            fi
            [ "$k" = "$1" ] || continue
            out=$(_tg_gh "$k"; _tg_git "$k") ;;
        esac ;;
    esac
    [ -n "$out" ] || continue
    _tg_tier3 "$out"
  done
  # The words joined, as ssh, watch or `sudo -s` hand them to a shell. Not
  # after a shell or a language's own interpreter: `bash -c '...' a b` runs
  # its one script, already read as a command, with a and b as arguments.
  [ "${#TOK[$1]}" -le 4096 ] && case "${TOK[$1]##*/}" in
    sh|bash|zsh|ksh|dash|ash|mksh|busybox|python|python[23]|perl|ruby|node|deno|bun) join=0 ;;
  esac
  if [ "$join" = 1 ]; then
    for ((k = $1; k < n; k++)); do joined="$joined${joined:+ }${TOK[k]}"; done
    if _tg_may_run "$joined"; then
      if [ "$reads" -ge "$TG_SCAN_MAX" ]; then over=1
      else
        reads=$((reads + 1))
        out=$(_tg_read_text "$joined" $((TG_DEPTH + 1)))
        [ -n "$out" ] && _tg_tier3 "$out"
      fi
    fi
  fi
  # A here-string is the program's input, which a program this hook does not
  # know may run (`script -q /dev/null <<<'...'`): each is read for the same
  # Tier 3 actions. After an interpreter the parser has read it already.
  if [ "$interp" = 0 ]; then
    for t in ${TG_HSTR[@]+"${TG_HSTR[@]}"}; do
      [ "${#texts[@]}" -lt "$TG_SCAN_MAX" ] && _tg_persist_hint "$t" && texts+=("$t")
      _tg_may_run "$t" || continue
      if [ "$reads" -ge "$TG_SCAN_MAX" ]; then over=1; continue; fi
      reads=$((reads + 1))
      out=$(_tg_read_text "$t" $((TG_DEPTH + 1)))
      [ -n "$out" ] && _tg_tier3 "$out"
    done
  fi
  [ "$over" = 1 ] && _tg_emit unknown "$1"
  # What the quoted words and here-strings change for good: the repository's
  # configuration, its branch, its .git (`watch 'git config ...'`, `watch
  # 'git checkout main'`), whether or not they name a Tier 3 action. At most
  # TG_SCAN_MAX of them are parsed.
  for t in ${texts[@]+"${texts[@]}"}; do
    _tg_config_prescan "$t"
  done
  return 0
}

# The Tier 3 lines of what a text read as a command names: merge, release,
# tagUnread, unknown and shell; a verified release is a plain one here.
_tg_tier3() {   # $1 = the lines
  local line
  while IFS= read -r line; do
    case "${line%%$'\t'*}" in
      merge|release|tagUnread|unknown|shell) printf '%s\n' "$line" ;;
      releaseVerified:*) printf 'release\t%s\n' "${line#*$'\t'}" ;;
    esac
  done <<TG_T3_EOF
$1
TG_T3_EOF
}

# Could a text change git's configuration, the branch checked out, or what
# is under .git? A cheap look before _tg_config_prescan parses it.
_tg_persist_hint() {   # $1 = the text
  case "$1" in
    *[Cc][Oo][Nn][Ff][Ii][Gg]*|*[Rr][Ee][Mm][Oo][Tt][Ee]*|*[Bb][Rr][Aa][Nn][Cc][Hh]*|\
    *[Cc][Hh][Ee][Cc][Kk][Oo][Uu][Tt]*|*[Ss][Ww][Ii][Tt][Cc][Hh]*|*[Pp][Uu][Ss][Hh]*|\
    *[Ss][Yy][Mm][Bb][Oo][Ll][Ii][Cc]*|*.[Gg][Ii][Tt]*|*[Gg][Ii][Tt]/*|*[Xx][Aa][Rr][Gg][Ss]*|\
    *'$'*|*'`'*) return 0 ;;
  esac
  return 1
}

# Could this quoted word run a Tier 3 action? Only if, with its quotes and
# backslashes removed, it names one, in any case: push, merge, release or api
# (a gh api call may be unreadable, or a GraphQL mutation); and it holds gh
# or git as a word of its own (at the start, or after a character that is not
# a letter, a digit or `_`, or after the S of `env -S`), or something this
# hook cannot read (`$`, a backquote, a substitution): `$GH pr merge 1`. So
# `'gh pr view 12'` is not read. A word longer than 4096 characters is passed
# on to _tg_read_text, which judges its text the same way as the whole
# command. Kept in the shell: this runs for every quoted word after a
# program this hook does not know.
_tg_may_run() {   # $1 = the word
  local b
  [ "${#1}" -le 4096 ] || return 0
  b="${1//[\"\'\\]/}"
  case "$b" in
    *[Pp][Uu][Ss][Hh]*|*[Mm][Ee][Rr][Gg][Ee]*|*[Rr][Ee][Ll][Ee][Aa][Ss][Ee]*|*[Aa][Pp][Ii]*) ;;
    *) return 1 ;;
  esac
  case "$1" in *'$'*|*'`'*|*__BD_SUBST__*) return 0 ;; esac
  case "$b" in
    [Gg][Hh]|[Gg][Ii][Tt]|[Gg][Hh][!A-Za-z0-9_-]*|[Gg][Ii][Tt][!A-Za-z0-9_-]*|\
    *[!A-Za-z0-9_][Gg][Hh]|*[!A-Za-z0-9_][Gg][Ii][Tt]|*[Ss][Gg][Hh]|*[Ss][Gg][Ii][Tt]|\
    *[!A-Za-z0-9_][Gg][Hh][!A-Za-z0-9_-]*|*[!A-Za-z0-9_][Gg][Ii][Tt][!A-Za-z0-9_-]*|\
    *[Ss][Gg][Hh][!A-Za-z0-9_-]*|*[Ss][Gg][Ii][Tt][!A-Za-z0-9_-]*) return 0 ;;
  esac
  return 1
}

# The names of the variables this simple command sets, into TG_SETN: an
# assignment before the command word (`GIT_DIR=x git push`, also after env;
# NAME+=value and NAME[i]=value too), a name or an assignment after export,
# declare, typeset, local or readonly, a name read into by read, mapfile,
# readarray or getopts, the name of printf -v, and a name after unset that is
# set in this hook's environment (unsetting one that is not changes nothing
# git or gh would read). A word that only looks like one (`echo HOME`, `echo
# GIT_DIR=x`) sets nothing. A plain assignment counts whether or not it is
# exported (`set -a`, `set -o allexport`, or a name exported before this
# command all make it one).
_tg_set_names() {
  local k t w=""
  TG_SETN=()
  for ((k = 0; k < TG_I && k < n; k++)); do
    t="${TOK[k]}"
    _tg_is_assignment "$t" && TG_SETN+=("$TG_AN")
  done
  [ "$TG_I" -lt "$n" ] && w="${TOK[TG_I]}"
  case "$w" in
    export|declare|typeset|local|readonly)
      for ((k = TG_I + 1; k < n; k++)); do
        t="${TOK[k]}"
        case "$t" in -*) continue ;; esac
        if _tg_is_assignment "$t"; then TG_SETN+=("$TG_AN")
        else _tg_is_assignment "$t=" && TG_SETN+=("$TG_AN")
        fi
      done ;;
    read|mapfile|readarray|getopts)
      for ((k = TG_I + 1; k < n; k++)); do
        t="${TOK[k]}"
        case "$t" in -*) continue ;; esac
        _tg_is_assignment "$t=" && TG_SETN+=("$TG_AN")
      done ;;
    printf)
      for ((k = TG_I + 1; k < n; k++)); do
        t="${TOK[k]}"
        case "$t" in
          -v) _tg_is_assignment "${TOK[k+1]:-}=" && TG_SETN+=("$TG_AN"); break ;;
          -v?*) _tg_is_assignment "${t#-v}=" && TG_SETN+=("$TG_AN"); break ;;
          --) break ;;
          -*) continue ;;
        esac
        break
      done ;;
    unset)
      for ((k = TG_I + 1; k < n; k++)); do
        t="${TOK[k]}"
        case "$t" in -*) continue ;; esac
        _tg_is_assignment "$t=" && [ -n "${!t+x}" ] && TG_SETN+=("$t")
      done ;;
  esac
  return 0
}

# Does the git at $1 change configuration that decides what a later push
# sends or where it goes? `git config` (any form: -C, --global, --file, the
# `set` subcommand, --add, --unset, --replace-all, -e) naming a key under
# push., remote., branch., include. or includeIf., a key this hook cannot
# read, or the editor; --rename-section and --remove-section (or the
# subcommands) naming one of those sections, with or without a subsection
# (`git config --rename-section x push`); `git remote add`, `set-url` or
# `rename`, which create or move a remote (`--mirror=push`); an upstream or
# tracking change: `git branch -u`, `--set-upstream-to`, `--unset-upstream`,
# `-t`/`--track`, a moved or copied branch (-m, -M, -c, -C), `git checkout -b
# <name> <start>` (a remote-tracking start sets the upstream), `-t`/`--track`
# on checkout or switch, `git push -u` (not counted with $2 = 1: it changes
# only the pushes after it); and, under xargs, which appends words this hook
# cannot see, any git config but a read, any git remote but show or get-url,
# a git branch, or a git with no subcommand. A subcommand this hook cannot
# read (`git $SUB ...`) may be any of them. Reading configuration (--get,
# --get-all, --get-regexp, --list, -l, `get`, `list`) changes nothing, and
# neither does a key such as user.name.
#
# Also sets TG_PB=1 when the git at $1 may change the branch checked out
# (checkout or switch without `--`, symbolic-ref with a target): a push that
# names no remote is then sent where that branch's configuration says.
_tg_config_write() {   # $1 = index of git, $2 = 1 to leave out git push -u
  local j=$(($1 + 1)) t first="" ro=0 hit=0 sect=0 path=0 words=0 c rest sub
  while [ "$j" -lt "$n" ]; do
    case "${TOK[j]}" in
      -C|-c|--config-env|--git-dir|--work-tree|--namespace|--super-prefix|--list-cmds|--attr-source) j=$((j + 2)) ;;
      -*) j=$((j + 1)) ;;
      *) break ;;
    esac
  done
  if [ "$j" -ge "$n" ]; then
    [ "${TG_XARGS:-0}" = 1 ]
    return
  fi
  _tg_unreadable "${TOK[j]}" && return 0
  sub="${TOK[j]}"
  # Section and key names are compared in any case, as git compares them.
  shopt -s nocasematch
  case "$sub" in
    config)
      for ((j = j + 1; j < n; j++)); do
        t="${TOK[j]}"
        _tg_unreadable "$t" && hit=1
        case "$t" in
          --get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|--list|-l) ro=1; continue ;;
          -e|--edit) hit=1; continue ;;
          --rename-section|--remove-section) sect=1; continue ;;
          -*) continue ;;
        esac
        if [ -z "$first" ]; then
          first="$t"
          case "$t" in get|list) ro=1 ;; edit) hit=1 ;; rename-section|remove-section) sect=1 ;; esac
        fi
        case "$t" in push.*|remote.*|branch.*|include.*|includeif.*) hit=1 ;; esac
        [ "$sect" = 1 ] && case "$t" in push|remote|branch|include|includeif) hit=1 ;; esac
      done
      [ "${TG_XARGS:-0}" = 1 ] && hit=1 ;;
    remote)
      for ((j = j + 1; j < n; j++)); do
        t="${TOK[j]}"
        case "$t" in -*) continue ;; esac
        first="$t"
        case "$t" in add|set-url|rename) hit=1 ;; esac
        _tg_unreadable "$t" && hit=1
        break
      done
      [ "${TG_XARGS:-0}" = 1 ] && case "$first" in show|get-url) ;; *) hit=1 ;; esac ;;
    branch)
      [ "${TG_XARGS:-0}" = 1 ] && hit=1
      for ((j = j + 1; j < n; j++)); do
        t="${TOK[j]}"
        case "$t" in
          --) break ;;
          --*)
            for c in --set-upstream-to:--set-u --unset-upstream:--uns --track:--tr --no-track:--no-t --move:--mov --copy:--cop; do
              _bd_is_opt "$t" "${c%%:*}" "${c#*:}" && hit=1
            done ;;
          -?*) case "${t#-}" in *[utmMcC]*) hit=1 ;; esac ;;
        esac
      done ;;
    checkout|switch)
      TG_PB=1
      for ((j = j + 1; j < n; j++)); do
        t="${TOK[j]}"
        case "$t" in
          --) path=1; break ;;
          --track|--track=*|-t) hit=1 ;;
          --orphan|--create|--force-create) words=-1; j=$((j + 1)) ;;
          --*) ;;
          -?*)
            rest="${t#-}"
            case "$rest" in *t*) hit=1 ;; esac
            # -b, -B, -c, -C: the new branch's name follows; a word after
            # it is the start point.
            case "$rest" in *[bBcC]*) words=-1; [ "${rest##*[bBcC]}" = "" ] && j=$((j + 1)) ;; esac ;;
          *) [ "$words" = -1 ] && hit=1; words=$((words + 1)) ;;
        esac
      done
      # `git checkout -- <paths>` restores files and stays on the branch.
      [ "$path" = 1 ] && [ "$sub" = checkout ] && TG_PB=0 ;;
    symbolic-ref)
      for ((j = j + 1; j < n; j++)); do
        case "${TOK[j]}" in -*) ;; *) words=$((words + 1)) ;; esac
      done
      [ "$words" -ge 2 ] && TG_PB=1 ;;
    push)
      if [ "${2:-0}" != 1 ]; then
        [ "${TG_XARGS:-0}" = 1 ] && hit=1
        for ((j = j + 1; j < n; j++)); do
          t="${TOK[j]}"
          case "$t" in
            --) break ;;
            --*) _bd_is_opt "${t%%=*}" --set-upstream --set-u && hit=1 ;;
            -?*) rest="${t#-}"; rest="${rest%%o*}"; case "$rest" in *u*) hit=1 ;; esac ;;
          esac
        done
      fi ;;
  esac
  shopt -u nocasematch
  [ "$hit" = 1 ] && [ "$ro" = 0 ]
}

# Does this simple command write under a .git directory, to a .gitconfig, or
# to git's configuration under ~/.config/git? A redirection target always
# counts (`printf ... >> .git/config`); an argument counts unless the program
# only reads or prints it (echo, printf, grep, cat, test, ...; not tee, which
# writes), or is git itself, whose own options are read where they apply:
# `cp ../other/.git/config .git/config`, `ln -s ../other/.git .git`, `sed -i
# ... .git/config`. Such a write can make a later push send tags or go to
# another remote, and this hook cannot read what was written.
_tg_gitpath_write() {
  local k t w=""
  for t in ${TG_RDIR[@]+"${TG_RDIR[@]}"}; do _tg_gitpath "$t" && return 0; done
  [ "$TG_I" -lt "$n" ] || return 1
  [ "${#TOK[TG_I]}" -le 4096 ] && w="${TOK[TG_I]##*/}"
  case "$w" in
    [Gg][Ii][Tt]|echo|printf|grep|egrep|fgrep|zgrep|rg|jq|cat|test|'['|'[['|:|cd|pushd|ls) return 1 ;;
  esac
  for ((k = TG_I + 1; k < n; k++)); do
    _tg_gitpath "${TOK[k]}" && return 0
  done
  return 1
}

_tg_gitpath() {   # $1 = a word
  [ "${#1}" -le 4096 ] || return 1
  case "$1" in
    .[Gg][Ii][Tt]|.[Gg][Ii][Tt]/*|*/.[Gg][Ii][Tt]|*/.[Gg][Ii][Tt]/*|\
    *[!A-Za-z0-9_.-].[Gg][Ii][Tt]|*[!A-Za-z0-9_.-].[Gg][Ii][Tt]/*|\
    *.[Gg][Ii][Tt][Cc][Oo][Nn][Ff][Ii][Gg]*|*[Gg][Ii][Tt]/[Cc][Oo][Nn][Ff][Ii][Gg]*|\
    *[Cc][Oo][Nn][Ff][Ii][Gg].[Ww][Oo][Rr][Kk][Tt][Rr][Ee][Ee]*) return 0 ;;
  esac
  return 1
}

# Does this simple command change the shell itself in a way this hook does
# not follow, so that the directory a later git or gh runs in, the variables
# it sees, or the program a name runs can no longer be read from the
# command? eval, source and `.` run text in this shell (their words are read
# as commands too, but what a sourced file or an evaluated variable does is
# not); exec with a command; alias, which can turn any later name into
# anything; hash -p, which points a name at another program; enable with
# arguments; a DEBUG, RETURN or ERR trap, which runs its text in this shell
# before or after other commands; a nameref (declare, typeset or local -n),
# through which a later assignment sets another variable; and a command word
# that is a variable or a substitution (`$CD ../other`), which may be any of
# them, or cd.
_tg_unmodeled() {
  local k t w
  [ "$TG_I" -lt "$n" ] || return 1
  [ "${TG_EXECW:-0}" = 1 ] && return 0
  w="${TOK[TG_I]}"
  _tg_unreadable "$w" && return 0
  case "$w" in
    eval|source|.|alias) return 0 ;;
    enable) [ $((TG_I + 1)) -lt "$n" ] && return 0 ;;
    hash)
      for ((k = TG_I + 1; k < n; k++)); do
        case "${TOK[k]}" in -*p*) return 0 ;; esac
      done ;;
    trap)
      shopt -s nocasematch
      for ((k = TG_I + 1; k < n; k++)); do
        case "${TOK[k]}" in DEBUG|RETURN|ERR) shopt -u nocasematch; return 0 ;; esac
      done
      shopt -u nocasematch ;;
    declare|typeset|local)
      for ((k = TG_I + 1; k < n; k++)); do
        case "${TOK[k]}" in --) break ;; -*n*) return 0 ;; esac
      done ;;
  esac
  return 1
}

# Is any simple command in these segments one _tg_unmodeled names? Then from
# the start of the command the directory, the environment and git's
# configuration are unreadable (TG_CDOTHER, TG_GITENV, TG_GHMOVED): a push or
# a gh release anywhere in it asks, before the change as well as after,
# since a loop or a function can run it again afterwards. Only a segment that
# could hold one is parsed.
_tg_state_prescan() {   # $1 = the segments
  local seg
  while IFS= read -r seg; do
    case "$seg" in ''|__BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
    case "$seg" in
      *eval*|*source*|*exec*|*alias*|*hash*|*enable*|*trap*|*declare*|*typeset*|*local*|\
      *'$'*|*'`'*|*__BD_SUBST__*|*[\'\"\\]*|.|.[[:space:]]*|*[[:space:]].|*[[:space:]].[[:space:]]*) ;;
      *) continue ;;
    esac
    _bd_words "$seg"
    n=${#TOK[@]}
    [ "$n" -gt 0 ] || continue
    _tg_command_word
    if _tg_unmodeled; then
      TG_CDOTHER=1; TG_GITENV=1; TG_GHMOVED=1
      return 0
    fi
  done <<TG_STATE_EOF
$1
TG_STATE_EOF
  return 0
}

# cd, pushd or popd: where the rest of the command runs. TG_CDBASE becomes
# the directory when it can be read; TG_CDOTHER=1 when it cannot (a variable,
# `cd -`, popd, pushd +N, a name CDPATH may resolve, a directory that is not
# there, a substitution other than `$(git rev-parse --show-toplevel)`, a home
# directory: `cd` alone or `~`) or
# when it is in another repository than the payload's. A git push after
# TG_CDOTHER=1 asks as a possible tag push: that repository's tags and
# remotes are not the ones this hook would read, and a cd inside a subshell
# or a substitution cannot be told from one that applies to what follows.
#
# Another worktree of the payload's repository (the same common directory)
# shares its tags, branches and configuration, so a push there is read there
# (TG_CDWT=1), unless the repository gives worktrees configuration of their
# own (extensions.worktreeConfig), which counts as another repository. What
# still differs is the branch checked out, so a push there that names no
# remote, whose remote the branch's configuration picks, asks.
#
# `cd "$(git rev-parse --show-toplevel)"` goes to the top of the repository
# the command is in at that point: the parser has just read the substitution
# as the simple command before this one (TG_LASTW).
_tg_cd() {   # $1 = index of cd, pushd or popd
  local w="${TOK[$1]}" k=$(($1 + 1)) t d top cd1 wtc
  [ "$w" = popd ] && { TG_CDOTHER=1; return 0; }
  while [ "$k" -lt "$n" ]; do
    t="${TOK[k]}"
    case "$t" in
      --) k=$((k + 1)); break ;;
      -[0-9]*|+*) TG_CDOTHER=1; return 0 ;;
      -?*) k=$((k + 1)); continue ;;
    esac
    break
  done
  # cd alone goes home and pushd alone swaps the top two directories. The
  # home directory is the shell's, which only cascade-resolve.sh may read
  # (and a repository's settings can move), so it is not read here.
  [ "$k" -lt "$n" ] || { TG_CDOTHER=1; return 0; }
  d="${TOK[k]}"
  case "$d" in '') return 0 ;; -) TG_CDOTHER=1; return 0 ;; esac
  case "$d" in
    __BD_SUBST__|' __BD_SUBST__ ')
      if [ "${TG_LASTW:-}" = "git rev-parse --show-toplevel" ] \
         && d=$(git -C "${TG_CDBASE:-$CWD}" rev-parse --show-toplevel 2>/dev/null) && [ -n "$d" ]; then :
      else TG_CDOTHER=1; return 0
      fi ;;
  esac
  _tg_unreadable "$d" && { TG_CDOTHER=1; return 0; }
  # The word is as the shell received it, so a leading ~ is still a ~: a
  # home directory, which is not read here either.
  case "$d" in '~'*) TG_CDOTHER=1; return 0 ;; esac
  case "$d" in
    /*) ;;
    .|..|./*|../*) d="${TG_CDBASE:-$CWD}/$d" ;;
    *) [ -n "${TG_CDPATH:-}" ] && { TG_CDOTHER=1; return 0; }
       d="${TG_CDBASE:-$CWD}/$d" ;;
  esac
  [ -d "$d" ] || { TG_CDOTHER=1; return 0; }
  TG_CDBASE="$d"
  [ -n "${TG_TOP0+x}" ] || TG_TOP0=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || TG_TOP0=""
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || top=""
  [ "$top" = "$TG_TOP0" ] && return 0
  [ -n "${TG_COMMON0+x}" ] || TG_COMMON0=$(_tg_common_dir "$CWD")
  cd1=$(_tg_common_dir "$d")
  wtc=$(git -C "$d" config --type=bool --get extensions.worktreeConfig 2>/dev/null) || wtc=""
  if [ -n "$top" ] && [ -n "$cd1" ] && [ "$cd1" = "$TG_COMMON0" ] && [ "$wtc" != true ]; then
    TG_CDWT=1
  else
    TG_CDOTHER=1
  fi
  return 0
}

# The common directory of the repository a directory is in (the .git
# directory every worktree of it shares), as a physical path; empty when the
# directory is in none.
_tg_common_dir() {   # $1 = a directory
  local c
  c=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 0
  [ -n "$c" ] || return 0
  case "$c" in /*) ;; *) c="$1/$c" ;; esac
  (cd -P "$c" 2>/dev/null && pwd -P)
  return 0
}

# Does a text handed to a shell, or to a program that may run it, hold a
# change to the repository that lasts beyond it: a git config, git remote,
# upstream or tracking change (_tg_config_write), or a write under .git
# (_tg_gitpath_write)? Then TG_GITENV=1: every push in the command asks. A
# branch change there (TG_PB) makes a push that names no remote ask
# (TG_CDWT). The words of the command being read are kept: this runs in the
# middle of reading one (_tg_scan). With $2 = 1 a `git push -u` is left out:
# the text handed to a shell is also read in order as commands, and its own
# push must not ask because of the upstream it sets.
_tg_config_prescan() {   # $1 = the text, $2 = 1 to leave out git push -u
  local segs seg k n TG_I TG_XARGS TG_EXECW TG_PB=0 TG_RIN TG_AN
  local -a TOK=() TOKE=() BD_HSTR=() BD_RDIR=() TG_RDIR=()
  local BD_RIN=0
  segs=$(_bd_segments "$1")
  while IFS= read -r seg; do
    case "$seg" in ''|__BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
    _bd_words "$seg"
    n=${#TOK[@]}
    TG_RDIR=(${BD_RDIR[@]+"${BD_RDIR[@]}"})
    [ "$n" -gt 0 ] || continue
    _tg_command_word
    _tg_gitpath_write && { TG_GITENV=1; return 0; }
    for ((k = TG_I; k < n; k++)); do
      [ "${#TOK[k]}" -le 4096 ] || continue
      case "${TOK[k]##*/}" in
        [Gg][Ii][Tt]) _tg_config_write "$k" "${2:-0}" && { TG_GITENV=1; return 0; } ;;
      esac
    done
    [ "$TG_PB" = 1 ] && TG_CDWT=1
  done <<TG_PRESCAN_EOF
$segs
TG_PRESCAN_EOF
  return 0
}

# Every action a command text names, one `key<TAB>summary<TAB>dir` line each.
# $2 is how deep this text sits inside quoted arguments read as commands
# (_tg_scan): past four levels, a text that mentions gh, push, merge or
# release is read as an unreadable gh call. Run in a subshell: the parser
# exits 2 when awk fails, and that must reach the caller as "cannot decide",
# not end this hook with a refusal.
_tg_read_text() {   # $1 = the text, $2 = depth
  local segs seg pend=0 gpend=0 bpend=0 k t bare code0 added sc
  TG_DEPTH=$2
  bare=$(printf '%s' "$1" | LC_ALL=C tr -d "'\"\\\\") || bare=gh
  case "$bare" in
    *[Gg][Hh]*|*[Pp][Uu][Ss][Hh]*|*[Mm][Ee][Rr][Gg][Ee]*|*[Rr][Ee][Ll][Ee][Aa][Ss][Ee]*) ;;
    *) return 0 ;;
  esac
  if [ "$2" -gt 4 ]; then
    printf 'unknown\t%s\t\n' "$(printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-160)"
    return 0
  fi
  _bd_strip_noncode "$1"
  code0="$BD_CODE"
  _bd_expand_interpreter_args
  # The arguments and here-strings handed to a shell are appended to the end
  # of the text, so they are read after every command in it. A git config
  # among them (`bash -c 'git config push.followTags true' && git push`)
  # changes the repository's configuration for good, so it counts from the
  # start (_tg_config_prescan).
  added="${BD_CODE:${#code0}}"
  [ -n "$added" ] && _tg_persist_hint "$added" && _tg_config_prescan "$added" 1
  segs=$(_bd_segments "$BD_CODE")
  case "$segs" in
    *__BD_SEG_FAIL__*)
      [ "$2" = 0 ] && exit 3
      printf 'unknown\t%s\t\n' "$(printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-160)"
      return 0 ;;
  esac
  # eval, source, exec and the rest anywhere in the text: from its start,
  # the directory, the environment and git's configuration are unreadable.
  _tg_state_prescan "$segs"
  while IFS= read -r seg; do
    # pend: an earlier simple command changed directory or set GH_REPO or
    # GH_HOST, so a later gh may act on another repository (TG_GHMOVED).
    # gpend: it set or exported a variable that chooses git's configuration
    # or repository, or changed git's configuration with git config or git
    # remote (TG_GITENV).
    # bpend: it may have changed the branch checked out (TG_CDWT).
    [ "$pend" = 1 ] && TG_GHMOVED=1
    [ "$gpend" = 1 ] && TG_GITENV=1
    [ "$bpend" = 1 ] && TG_CDWT=1
    [ -z "$seg" ] && continue
    case "$seg" in __BD_UNBALANCED__) continue ;; esac
    # Every comparison below is on the words as bash passes them to the
    # program (_bd_words): quotes removed, a backslash removed where bash
    # removes it, and redirections (`2>&1`, `--tags>/dev/null`, `> "a b"`)
    # set aside with their targets. A here-string's text is kept apart
    # (TG_HSTR): it is the program's input, not an argument.
    _bd_words "$seg"
    n=${#TOK[@]}
    TG_HSTR=(${BD_HSTR[@]+"${BD_HSTR[@]}"})
    TG_RDIR=(${BD_RDIR[@]+"${BD_RDIR[@]}"})
    TG_RIN="$BD_RIN"
    # The words of the simple command before this one (a substitution comes
    # just before the command that holds it): _tg_cd.
    TG_LASTW="${TG_CURW:-}"; TG_CURW="${TOK[*]:-}"
    [ "$n" -gt 0 ] || continue
    _tg_command_word
    # A variable this simple command sets (_tg_set_names) that chooses gh's
    # repository, or git's configuration or repository.
    _tg_set_names
    for t in ${TG_SETN[@]+"${TG_SETN[@]}"}; do
      case "$t" in GH_REPO|GH_HOST) pend=1 ;; esac
      _tg_git_env_name "$t" && gpend=1
    done
    # A write under .git or to a .gitconfig (_tg_gitpath_write), also by a
    # redirection of a simple command with no program: from the next simple
    # command on, a push asks.
    _tg_gitpath_write && gpend=1
    [ "$TG_I" -lt "$n" ] || continue
    # git config, git remote, an upstream or tracking change, or a branch
    # change, changing what a later push sends or where it goes
    # (_tg_config_write), as the command word or behind a program this hook
    # does not know: from the next simple command on, a push asks (a branch
    # change: a push that names no remote).
    sc=$(_tg_prog "${TOK[TG_I]}")
    case "$sc" in
      echo|printf|grep|egrep|fgrep|zgrep|rg|jq|cat|tee|test|'['|'[['|:) ;;
      *)
        TG_PB=0
        for ((k = TG_I; k < n; k++)); do
          [ "${#TOK[k]}" -le 4096 ] || continue
          case "${TOK[k]##*/}" in
            [Gg][Ii][Tt]) _tg_config_write "$k" && gpend=1 ;;
          esac
        done
        [ "$TG_PB" = 1 ] && bpend=1 ;;
    esac
    # A shell that reads its script from a pipe (`echo '...' | bash`) runs
    # text this hook cannot read; with the input redirected it reads a
    # here-string or a heredoc, which is read as commands, or a file.
    if [ "$TG_RIN" = 0 ] && _bd_shell_reads_stdin "$TG_I"; then _tg_emit shell "$TG_I"; continue; fi
    # eval of text this hook cannot read (`eval "$CMD"`, `eval "$(...)"`), and
    # source or . of no file, of stdin with no here-string, or of a file named
    # by a variable (`. <(...)`, `cmd | source /dev/stdin`), run commands it
    # cannot see.
    case "${TOK[TG_I]}" in
      eval)
        for ((k = TG_I + 1; k < n; k++)); do
          _tg_unreadable "${TOK[k]}" && { _tg_emit unknown "$TG_I"; break; }
        done ;;
      source|.)
        t="${TOK[TG_I + 1]:-}"
        if [ -z "$t" ] || _tg_unreadable "$t" \
           || { case "$t" in /dev/stdin|/dev/fd/*|-) true ;; *) false ;; esac \
                && [ "${#TG_HSTR[@]}" -eq 0 ] && [ "$TG_RIN" = 0 ]; }; then
          _tg_emit unknown "$TG_I"
        fi ;;
    esac
    case "${TOK[TG_I]}" in cd|pushd|popd) pend=1; _tg_cd "$TG_I" ;; esac
    case "$sc" in
      git) _tg_git "$TG_I" ;;
      gh) _tg_gh "$TG_I" ;;
      # They print, search or compare their arguments, and run none of them:
      # `echo gh pr merge 1`, `grep "gh pr merge" log`.
      echo|printf|grep|egrep|fgrep|zgrep|rg|jq|cat|tee|test|'['|'[['|:) ;;
      *) _tg_scan "$TG_I" ;;
    esac
  done <<< "$segs"
}

# Every action the command names.
_tg_actions() {
  TG_GHMOVED=0; TG_GITENV=0; TG_CDOTHER=0; TG_CDWT=0; TG_CDBASE="$CWD"; TG_CURW=""
  _tg_read_text "$COMMAND" 0
}

# --- the settings, the branch and the journal live where the command runs ---
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# The parser's own refusal text ("BLOCKED: ...") is not this hook's answer,
# so its stderr is dropped; the line below says what happened.
if ! ACTIONS=$(_tg_actions 2>/dev/null); then
  _tg_undecidable "$COMMAND" "the command parser failed"
fi
[ -n "$ACTIONS" ] || exit 0
# The same action read twice (a quoted argument read both as an interpreter's
# script and as a command handed to a program, `env -S '...'`) counts once.
ACTIONS=$(printf '%s\n' "$ACTIONS" | awk '!seen[$0]++')

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
RUN_DIR="${REPO_ROOT:-$CWD}"

_tg_phrase() {
  case "$1" in
    push) printf 'Pushing to a remote' ;;
    prCreate) printf 'Creating a pull request' ;;
    issueAssign) printf 'Assigning an issue' ;;
    issueCreate) printf 'Creating an issue' ;;
    merge) printf 'Merging a pull request' ;;
    release) printf 'Creating a release or pushing a tag' ;;
  esac
}

# host/owner/name of a git remote URL or a gh repository argument, in lower
# case: https://host/o/n(.git), ssh://user@host:port/o/n, user@host:o/n,
# host/o/n, or o/n (on github.com). Returns 1 for anything else.
_tg_repo_id() {   # $1 = URL or repository argument
  local u="$1" host path
  case "$u" in
    *://*)
      u="${u#*://}"; host="${u%%/*}"; path="${u#*/}"
      [ "$path" != "$u" ] || return 1
      host="${host##*@}"; host="${host%%:*}" ;;
    *@*:*) u="${u#*@}"; host="${u%%:*}"; path="${u#*:}" ;;
    */*/*) host="${u%%/*}"; path="${u#*/}" ;;
    */*) host=github.com; path="$u" ;;
    *) return 1 ;;
  esac
  path="${path#/}"; path="${path%/}"; path="${path%.git}"
  case "$path" in */*/*|/*|*/|'') return 1 ;; */*) ;; *) return 1 ;; esac
  [ -n "$host" ] || return 1
  printf '%s/%s' "$host" "$path" | LC_ALL=C tr 'A-Z' 'a-z'
}

# Does gh create the release in origin's repository? With a repository
# named (-R or GH_REPO), when it is origin's. With none, gh's default: the
# remote `gh repo set-default` chose (remote.<name>.gh-resolved), or the only
# remote; it must be origin.
_tg_gh_repo_is_origin() {   # $1 = the repository named, or empty
  local url want have resolved remotes
  # The URL as configured: `remote get-url` applies url.<base>.insteadOf,
  # which can turn a GitHub URL into a path that names no repository.
  url=$(git -C "$RUN_DIR" config --get remote.origin.url 2>/dev/null) || return 1
  if [ -n "$1" ]; then
    want=$(_tg_repo_id "$1") || return 1
    have=$(_tg_repo_id "$url") || return 1
    [ "$want" = "$have" ]
    return
  fi
  resolved=$(git -C "$RUN_DIR" config --name-only --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null)
  if [ -n "$resolved" ]; then
    [ "$resolved" = remote.origin.gh-resolved ]
    return
  fi
  remotes=$(git -C "$RUN_DIR" remote 2>/dev/null)
  [ "$remotes" = origin ]
}

# Is this tag already on origin? `git ls-remote --tags origin`, stopped after
# TG_REMOTE_TIMEOUT seconds (default 5). Any failure to check is "no".
_tg_tag_on_remote() {   # $1 = tag
  local tmp pid w rc=1
  TG_REMOTE=origin
  tmp=$(mktemp -t flow-tier-gate.XXXXXX 2>/dev/null) || return 1
  # Output goes to a file, not a pipe: a killed git can leave a helper (ssh,
  # a credential helper) holding a pipe open, and the read would then wait
  # for it.
  GIT_TERMINAL_PROMPT=0 git -C "$RUN_DIR" ls-remote --tags "$TG_REMOTE" "refs/tags/$1" >"$tmp" 2>/dev/null &
  pid=$!
  ( sleep "${TG_REMOTE_TIMEOUT:-5}"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  w=$!
  # The shell reports a killed job on stderr when it reaps it; that report
  # is not this hook's to print.
  { wait "$pid"; } 2>/dev/null; rc=$?
  { kill "$w"; wait "$w"; } 2>/dev/null
  if [ "$rc" -eq 0 ] && awk -v r="refs/tags/$1" '$2 == r { f = 1 } END { exit !f }' "$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"
  return 1
}

REASONS=()
# Each entry: the setting's label, a tab, the command summary.
JOURNAL_LINES=()
while IFS=$'\t' read -r KEY SUMMARY ADIR; do
  case "$KEY" in
    tagUnread)
      REASONS+=("A push whose refs, repository or configuration cannot be read or resolved from the command (or that the command changes first) may push or delete a tag, which is a Tier 3 action (tiers.release): flow asks before every one. Command: $SUMMARY")
      continue ;;
    unknown)
      REASONS+=("A gh api call whose method, endpoint or GraphQL query cannot be read from the command (a variable, a substitution, stdin, a missing file, a query in which the shell expands something, a method that is not GET, HEAD, POST, PUT, PATCH or DELETE, a quoted command nested too deep, or more quoted commands after one program than flow reads) may merge a pull request or create a release, which flow always asks about (tiers.merge, tiers.release; Tier 3). Command: $SUMMARY")
      continue ;;
    shell)
      REASONS+=("A shell that reads its script from its input (a pipe, or words xargs appends) runs commands flow cannot read, which may merge a pull request or create a release (tiers.merge, tiers.release; Tier 3): flow asks. Command: $SUMMARY")
      continue ;;
    assignUnread)
      _tg_note "could not read whether $SUMMARY changes an issue's assignees (its body is a file); allowing it without a tier check"
      continue ;;
    releaseVerified:*)
      # gh release create --verify-tag on a tag already on the remote creates
      # a release for a tag whose push was already confirmed: journaled. A tag
      # that is not there, or a check that fails, asks as any release does.
      # The tag is looked for on origin, so gh must be creating the release
      # in origin's repository too.
      VREST="${KEY#releaseVerified:}"
      VTAG="${VREST%%:*}"
      VREPO="${VREST#*:}"
      if git -C "$RUN_DIR" remote get-url origin >/dev/null 2>&1 && ! _tg_gh_repo_is_origin "$VREPO"; then
        REASONS+=("Creating a release is a Tier 3 action (tiers.release). flow asks unless --verify-tag names a tag that is already on origin and gh creates the release in origin's repository, and the repository gh would use${VREPO:+ ($VREPO)} could not be confirmed to be origin's. Command: $SUMMARY")
      elif _tg_tag_on_remote "$VTAG"; then
        JOURNAL_LINES+=("tiers.release (--verify-tag, $VTAG already on the remote)"$'\t'"$SUMMARY"$'\t'"$ADIR")
      else
        REASONS+=("Creating a release is a Tier 3 action (tiers.release). flow asks unless --verify-tag names a tag that is already on the remote, and $VTAG could not be found on $TG_REMOTE. Command: $SUMMARY")
      fi
      continue ;;
  esac
  case "$KEY" in merge|release) DEFAULT=confirm ;; *) DEFAULT=journal ;; esac
  VALUE=$(cd "$RUN_DIR" 2>/dev/null && "$PLUGIN_ROOT/bin/cascade-resolve.sh" --default "$DEFAULT" ".tiers.$KEY" 2>/dev/null)
  RC=$?
  VALUE=$(printf '%s' "$VALUE" | LC_ALL=C tr -d '\r\n')
  case "$KEY" in
    merge|release)
      # The floor: whatever the setting says, ask. A lower value is named so
      # the person can see their setting is not what decides.
      if [ "$RC" -eq 0 ] && [ "$VALUE" != confirm ]; then
        _tg_note "tiers.$KEY is \"$(printf '%s' "$VALUE" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-40)\", below the confirm floor for $KEY; ignoring it and asking"
      fi
      REASONS+=("$(_tg_phrase "$KEY") is a Tier 3 action (tiers.$KEY): flow asks before every one. Command: $SUMMARY")
      ;;
    *)
      if [ "$RC" -ne 0 ]; then
        _tg_note "could not read tiers.$KEY (cascade-resolve.sh exit $RC); allowing $SUMMARY without a tier check"
        continue
      fi
      case "$VALUE" in
        confirm) REASONS+=("$(_tg_phrase "$KEY") is a Tier 2 action set to confirm (tiers.$KEY), so it needs your approval. Command: $SUMMARY") ;;
        journal) JOURNAL_LINES+=("tiers.$KEY (journal)"$'\t'"$SUMMARY"$'\t'"$ADIR") ;;
        autonomous) ;;
        *) _tg_note "tiers.$KEY is \"$(printf '%s' "$VALUE" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-40)\", not autonomous, journal or confirm; allowing $SUMMARY without a tier check" ;;
      esac
      ;;
  esac
done <<< "$ACTIONS"

if [ "${#REASONS[@]}" -gt 0 ]; then
  REASON="Flow tier gate. ${REASONS[0]}"
  for ((r = 1; r < ${#REASONS[@]}; r++)); do REASON="$REASON Also: ${REASONS[r]}"; done
  jq -nc --arg r "$REASON" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

[ "${#JOURNAL_LINES[@]}" -gt 0 ] || exit 0

# --- the journal line goes to the auto-log trail ------------------------------
# Not the tracked journal: `<journal dir>/auto-log/`, the git-ignored trail
# log-commits.sh and log-file-changes.sh write, named the same way:
# issue-{N}.{YYYY-MM}.md on a branch naming issue N (rotated monthly),
# otherwise session-{YYYY-MM-DD}.md. The path checks below are theirs (see
# log-file-changes.sh, _flow_autolog). Written only where the repository keeps
# a flow journal directory: a push in a repository that never ran /flow:setup
# must not create .decisions/ in it. A `git -C <dir> push` is recorded in
# <dir>'s repository, on <dir>'s branch.

# One HTML-comment breadcrumb per action, as the other trail entries are,
# with the comment terminators and control characters neutralized: the trail
# is fed back to Claude by /flow:explain.
_tg_crumb_safe() {
  local v="${1//-->/-- >}"
  v="${v//<!--/< !--}"
  printf '%s' "$v" | LC_ALL=C tr '\000-\037\177' ' '
}

_tg_trail_refused() { _tg_note "could not write to the auto-log trail ($1); allowing"; }

_tg_write_trail() {   # $1 = repository top, $2 = breadcrumbs
  local top="$1" jdir base branch issue autolog adir user err rc
  [ -n "$top" ] || return 0
  jdir=$(cd "$top" && "$PLUGIN_ROOT/bin/journal-dir.sh" 2>/dev/null) || jdir=""
  [ -n "$jdir" ] || jdir=".decisions"
  case "$jdir" in /*) base="$jdir" ;; *) base="$top/$jdir" ;; esac
  [ -d "$base" ] || return 0
  branch=$(git -C "$top" branch --show-current 2>/dev/null) || branch=""
  issue=$(printf '%s' "$branch" | grep -oE 'issue-[0-9]+' | head -n 1 | grep -oE '[0-9]+') || issue=""
  if [ -n "$issue" ]; then
    autolog="$base/auto-log/issue-$issue.$(date +%Y-%m).md"
  else
    autolog="$base/auto-log/session-$(date +%Y-%m-%d).md"
  fi
  adir=$(dirname "$autolog")
  # A symlinked trail file or directory is refused: after `gh pr checkout` of
  # a hostile fork it could point anywhere. The directory is created by
  # bin/flow-mkdir.sh --contained at the repository top (nothing below the
  # top through a symlink); an absolute journal.dir from the user's own
  # settings is created as configured.
  [ -L "$autolog" ] && { _tg_trail_refused "the trail file is a symlink"; return 0; }
  [ -L "$adir" ] && { _tg_trail_refused "the trail directory is a symlink"; return 0; }
  if ! (cd "$top" && "$PLUGIN_ROOT/bin/flow-mkdir.sh" --contained -- "$adir") >/dev/null 2>&1; then
    user=$(cd "$top" && "$PLUGIN_ROOT/bin/journal-dir.sh" --user-owned 2>/dev/null) || user=""
    [ -n "$user" ] || { _tg_trail_refused "its directory could not be created inside the repository"; return 0; }
    mkdir -p "$adir" 2>/dev/null || { _tg_trail_refused "its directory could not be created"; return 0; }
  fi
  # The trail directory ignores itself, so it never dirties the tree.
  [ -L "$adir/.gitignore" ] && { _tg_trail_refused "its .gitignore is a symlink"; return 0; }
  { [ -f "$adir/.gitignore" ] || printf '*\n' > "$adir/.gitignore" 2>/dev/null; } || true
  err=$(printf '%s' "$2" | (cd "$top" && "$PLUGIN_ROOT/bin/journal-append.sh" --file "$autolog" -) 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    err=$(printf '%s' "$err" | head -n 1 | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-200)
    _tg_trail_refused "journal-append.sh exit $rc${err:+: $err}"
  fi
  return 0
}

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null) || AGENT_TYPE=""
AGENT_SAFE=""
[ -n "$AGENT_TYPE" ] && AGENT_SAFE=" agent=$(_tg_crumb_safe "$AGENT_TYPE")"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Group the breadcrumbs by repository, in the order the actions came.
TOPS=()
for J in "${JOURNAL_LINES[@]}"; do
  T="${J##*$'\t'}"; [ -n "$T" ] || T="$REPO_ROOT"
  SEEN=0
  for U in ${TOPS[@]+"${TOPS[@]}"}; do [ "$U" = "$T" ] && SEEN=1; done
  [ "$SEEN" = 1 ] || TOPS+=("$T")
done
for T in ${TOPS[@]+"${TOPS[@]}"}; do
  TEXT=""
  for J in "${JOURNAL_LINES[@]}"; do
    JT="${J##*$'\t'}"; [ -n "$JT" ] || JT="$REPO_ROOT"
    [ "$JT" = "$T" ] || continue
    J="${J%$'\t'*}"
    TEXT="$TEXT<!-- auto-log: $NOW $(_tg_crumb_safe "${J%%$'\t'*}") \"$(_tg_crumb_safe "${J#*$'\t'}")\"$AGENT_SAFE -->"$'\n'
  done
  _tg_write_trail "$T" "$TEXT"
done
exit 0
