#!/usr/bin/env bash
# [flow] Add Claude Code ask rules for merges, releases and tag pushes to a
# settings file at the repository top, for /flow:setup.
#
# Claude Code matches each rule against the command as written, also when the
# command is joined to others with &&, ; or |, or sits inside $(...), and asks
# before running it (in `claude -p`, which has no one to ask, it refuses). A
# trailing " *" also matches the bare command; a * inside a rule stands for
# any text.
#
# Usage: flow-setup-permissions.sh shared|local
#   shared  .claude/settings.json, committed with the repository
#   local   .claude/settings.local.json, on this machine only
#
# The rules that are missing are added to permissions.ask after the rules
# already there; everything else in the file is kept. Prints one of
#   PERMISSIONS=written    with ADDED=<n>
#   PERMISSIONS=unchanged  every rule is there; the file is not rewritten
#   PERMISSIONS=refused    with REASON=; nothing is written (the file is not a
#                          JSON object, it or .claude is a symlink, the choice
#                          is neither shared nor local, or the write failed)
#   PERMISSIONS=skipped    with REASON=; jq is missing
# and FILE=<path>. Exits 0 in every case: the result is in the output.

# An exported CDPATH makes cd print the directory it found.
unset CDPATH

RULES='["Bash(gh pr merge *)","Bash(gh release create *)","Bash(gh release edit *)","Bash(gh release delete *)","Bash(gh release upload *)","Bash(gh release delete-asset *)","Bash(git push *--tags*)","Bash(git push *--follow-tags*)","Bash(git push *refs/tags/*)"]'

top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$(pwd)
case "${1:-}" in
  shared) file="$top/.claude/settings.json" ;;
  local) file="$top/.claude/settings.local.json" ;;
  *)
    printf '%s\n' "PERMISSIONS=refused" "REASON=the choice must be shared or local, got '${1:-}'" "FILE="
    exit 0 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "PERMISSIONS=skipped" "REASON=jq is not installed; the ask rules were not written" "FILE=$file"
  exit 0
fi
if [ -L "$file" ] || [ -L "$top/.claude" ]; then
  printf '%s\n' "PERMISSIONS=refused" "REASON=$file or its directory is a symlink; nothing was written through it" "FILE=$file"
  exit 0
fi
if [ -e "$file" ]; then
  # One JSON object, whose permissions (when present) is an object and whose
  # permissions.ask (when present) is an array: the only shape the rules can
  # be added to without changing what the file means.
  shape=$(jq -rs 'if length != 1 or (.[0] | type) != "object" then "the file is not one JSON object"
    elif (.[0].permissions // {} | type) != "object" then "permissions is not an object"
    elif (.[0].permissions.ask // [] | type) != "array" then "permissions.ask is not a list"
    else "ok" end' "$file" 2>/dev/null) || shape="the file is not valid JSON"
  if [ "$shape" != ok ]; then
    printf '%s\n' "PERMISSIONS=refused" "REASON=$file: $shape; it was left as it is" "FILE=$file"
    exit 0
  fi
  old=$(cat "$file")
else
  old='{}'
fi
missing='(.permissions.ask // []) as $a | [$r[] | select(. as $x | $a | index($x) | not)]'
added=$(printf '%s' "$old" | jq --argjson r "$RULES" "$missing | length" 2>/dev/null)
case "$added" in
  0) printf '%s\n' "PERMISSIONS=unchanged" "FILE=$file"; exit 0 ;;
  ''|*[!0-9]*) printf '%s\n' "PERMISSIONS=refused" "REASON=$file could not be read as settings; it was left as it is" "FILE=$file"; exit 0 ;;
esac

# The mode the file keeps: its own, or for a new file what the umask gives
# a file created by a redirection. mktemp makes the temporary file 0600.
if [ -e "$file" ]; then
  mode=$(stat -f %Lp "$file" 2>/dev/null || stat -c %a "$file" 2>/dev/null) || mode=""
else
  mode=$(printf '%o' $(( 0666 & ~0$(umask) )))
fi

# Written beside the file and renamed over it, so a reader never sees half a
# file and a failed write leaves the old one in place.
tmp=""
if mkdir -p "$top/.claude" &&
   tmp=$(mktemp "$top/.claude/.flow-settings.XXXXXX") &&
   printf '%s' "$old" | jq --argjson r "$RULES" "(.permissions.ask // []) as \$a | .permissions.ask = \$a + ($missing)" > "$tmp" &&
   { [ -z "$mode" ] || chmod "$mode" "$tmp"; } &&
   mv -f "$tmp" "$file"; then
  printf '%s\n' "PERMISSIONS=written" "ADDED=$added" "FILE=$file"
else
  [ -z "$tmp" ] || rm -f "$tmp"
  printf '%s\n' "PERMISSIONS=refused" "REASON=$file could not be written" "FILE=$file"
fi
exit 0
