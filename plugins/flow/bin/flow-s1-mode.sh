#!/usr/bin/env bash
# [flow] The mode of a System One decision point, decided in one place: the
# client (bin/flow-s1.sh) and every call site that needs to know the mode
# before asking take it from here, so the rule cannot differ between them.
#
# Usage:
#   flow-s1-mode.sh <site>         print `shadow` or `on` when a provider is
#                                  configured and the site is in one of those
#                                  modes; print nothing otherwise. For a call
#                                  site deciding whether to run its System One
#                                  step at all: with the site off, the command's
#                                  output and its work stay as they were.
#   flow-s1-mode.sh --all <site>   print the mode the client uses, whatever it
#                                  is: off, shadow, on, or a value that is not
#                                  a mode (cut to 200 characters; the client
#                                  then reports it and treats the site as off).
#                                  The warning below goes to stderr.
#
# The rule: systemOne.uses.<site> is read from every settings tier, and from
# the user's settings and the plugin default alone; the lower of the two is
# used (on > shadow > off). A repository can lower the user's mode but never
# raise it, so it can neither switch a site on nor start shadow, which would
# send the state from the user's checkout to the user's provider. A repository
# value above the user's gets the user's mode, with one warning (--all only).
# A user value that is not a mode counts as off. The provider is read from the
# user's settings and the plugin default only.
#
# Exit 0, or 2 when the arguments are wrong. Sends nothing and writes nothing.
# Any failure (no resolver; the plugin inside the repository, so the resolver
# refuses to read the user's settings) means off: without --all nothing is
# printed, with --all `off` and, for the refused read, a warning saying so.
# The self-directory lookup below has siblings in bin/flow-s1.sh and
# bin/flow-clone-scan.sh; a fix to one belongs in all three.

set -uo pipefail
unset CDPATH

ALL=0
if [ "${1:-}" = --all ]; then ALL=1; shift; fi
SITE="${1:-}"
_site_ok() {
  local LC_ALL=C
  [[ "$1" =~ ^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$ ]]
}
if [ $# -ne 1 ] || ! _site_ok "$SITE"; then
  printf 'usage: flow-s1-mode.sh [--all] <site>   (site: lowercase words joined by dots)\n' >&2
  exit 2
fi

# This script's own directory, through symlinks, by parameter expansion where
# possible: the resolver is its sibling.
_self="$0"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *) case "$_self" in */*) _self="${_self%/*}/$_link" ;; *) _self="$_link" ;; esac ;;
  esac
  _hops=$((_hops + 1))
done
case "$_self" in */*) _dir="${_self%/*}" ;; *) _dir=. ;; esac
SELF_DIR="$(cd "$_dir" 2>/dev/null && pwd -P)" || { [ "$ALL" -eq 1 ] && printf 'off\n'; exit 0; }
CR="$SELF_DIR/cascade-resolve.sh"
if [ ! -x "$CR" ]; then
  [ "$ALL" -eq 1 ] && printf 'off\n'
  exit 0
fi

if [ "$ALL" -eq 0 ]; then
  PROVIDER=$("$CR" --no-repo-settings --default none ".systemOne.provider" 2>/dev/null) || exit 0
  case "$PROVIDER" in typesafe|imajev|custom) ;; *) exit 0 ;; esac
fi

# The site id was checked above, so it is safe inside the quoted key.
# With --all the full read keeps its stderr: the resolver's warning about a
# settings file it could not parse is the client's to show.
if [ "$ALL" -eq 1 ]; then
  MODE=$("$CR" --default off ".systemOne.uses[\"$SITE\"]") || MODE=off
else
  MODE=$("$CR" --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null) || MODE=off
fi
# The user-only read is refused when this script sits inside the repository
# (the plugin loaded from the checkout): the user's own mode is then unknown,
# and the site is off. The client stops earlier in that case, with
# settings-refused; --all says so instead of blaming the repository.
if ! USER_MODE=$("$CR" --no-repo-settings --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null); then
  [ "$ALL" -eq 1 ] && { printf 'flow-s1: WARN: your own settings for systemOne.uses["%s"] could not be read; using off\n' "$SITE" >&2; printf 'off\n'; }
  exit 0
fi
case "$USER_MODE" in off|shadow|on) ;; *) USER_MODE=off ;; esac
_rank() { case "$1" in off) printf 0 ;; shadow) printf 1 ;; on) printf 2 ;; esac; }
_r=$(_rank "$MODE")
if [ -n "$_r" ] && [ "$_r" -gt "$(_rank "$USER_MODE")" ]; then
  [ "$ALL" -eq 1 ] && printf 'flow-s1: WARN: systemOne.uses["%s"] is %s in this repository'"'"'s settings, which can only lower your own mode; using %s\n' "$SITE" "$MODE" "$USER_MODE" >&2
  MODE=$USER_MODE
fi

if [ "$ALL" -eq 1 ]; then
  # The mode may come from the repository, so a value that is not a mode is
  # cut before it reaches a command line.
  case "$MODE" in off|shadow|on) ;; *) MODE="${MODE:0:200}" ;; esac
  printf '%s\n' "$MODE"
else
  case "$MODE" in shadow|on) printf '%s\n' "$MODE" ;; esac
fi
exit 0
