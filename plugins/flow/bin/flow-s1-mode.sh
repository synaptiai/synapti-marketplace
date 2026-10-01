#!/usr/bin/env bash
# [flow] Say whether a System One decision point is active, without asking
# anything: print the site's mode, `shadow` or `on`, when a provider is
# configured and the site is in one of those modes, and print nothing
# otherwise. A command runs this in a `!` fence to decide whether to run its
# System One step at all, so that with the site off the command's text and its
# work are what they were before the site existed.
#
# Usage: flow-s1-mode.sh <site>
#
# Prints nothing when: the provider is none, empty or not one of typesafe,
# imajev and custom; cascade-resolve.sh refuses to read the user's settings
# (the plugin is inside the repository); the site is off or its mode is not a
# mode. The settings are read the way bin/flow-s1.sh reads them: the provider
# from the user's settings and the plugin default only, the mode from every
# tier, where a repository's `on` counts only when the user's settings or the
# plugin default also say `on`. flow-s1.sh applies the same rule again when it
# is asked, so a probe that says `on` where the client says `shadow` costs a
# request whose answer is not used, never an answer used against the user's
# settings.
#
# Exit 0, or 2 when the site id is not lowercase words joined by dots. Sends
# nothing and writes nothing.

set -uo pipefail
unset CDPATH

SITE="${1:-}"
_site_ok() {
  local LC_ALL=C
  [[ "$1" =~ ^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$ ]]
}
if [ $# -ne 1 ] || ! _site_ok "$SITE"; then
  printf 'usage: flow-s1-mode.sh <site>   (site: lowercase words joined by dots)\n' >&2
  exit 2
fi

_self="$0"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$(dirname "$_self")/$_link" ;;
  esac
  _hops=$((_hops + 1))
done
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || exit 0
CR="$SELF_DIR/cascade-resolve.sh"
[ -x "$CR" ] || exit 0

PROVIDER=$("$CR" --no-repo-settings --default none ".systemOne.provider" 2>/dev/null) || exit 0
case "$PROVIDER" in typesafe|imajev|custom) ;; *) exit 0 ;; esac

MODE=$("$CR" --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null) || MODE=off
USER_MODE=$("$CR" --no-repo-settings --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null) || USER_MODE=off
if [ "$MODE" = on ] && [ "$USER_MODE" != on ]; then
  MODE=$USER_MODE
fi
case "$MODE" in
  shadow|on) printf '%s\n' "$MODE" ;;
esac
exit 0
