#!/usr/bin/env bash
# No `!` block in any plugin's commands or skills uses a bare $0-$9.
#
# Claude Code replaces $N in a command's or skill's text with argument N
# (0-based) whenever that argument exists, inside `!` blocks too, before the
# shell sees them. So a shell function's $1 receives the second word the user
# typed, and awk's $0 receives the first: /flow:resume <run-id> once fed the run
# id to awk in place of each porcelain line. The spellings Claude Code leaves
# alone are ${1} in the shell and $(N) in awk.
#
# Ways this check could be wrong, written down first:
#   - it reads fences that are not `!` blocks (a ```bash example in prose is
#     text for the model, not run by Claude Code, and is not substituted);
#   - it misses a `!` block whose opening fence has trailing spaces;
#   - it passes because it found no files (a moved directory reads as clean).

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PASS=0
FAIL=0

FILES=$(cd "$REPO_ROOT" && ls plugins/*/commands/*.md plugins/*/skills/*/SKILL.md 2>/dev/null)
N_FILES=$(printf '%s\n' "$FILES" | grep -c . || true)
N_BANG=0
HITS=""
for f in $FILES; do
  n=$(grep -c '^```![[:space:]]*$' "$REPO_ROOT/$f" || true)
  N_BANG=$((N_BANG + n))
  HIT=$(awk -v F="$f" '
    /^```![[:space:]]*$/ && !inb { inb = 1; next }
    /^```/ && inb { inb = 0; next }
    inb && /\$[0-9]/ { print F ":" NR ": " $0 }' "$REPO_ROOT/$f")
  [ -n "$HIT" ] && HITS="$HITS$HIT
"
done

if [ "$N_FILES" -ge 10 ] && [ "$N_BANG" -ge 10 ]; then
  echo "PASS: read $N_FILES command and skill files holding $N_BANG ! blocks"; PASS=$((PASS + 1))
else
  echo "FAIL: found only $N_FILES files and $N_BANG ! blocks; the scan is not reading the plugins"; FAIL=$((FAIL + 1))
fi
if [ -z "$HITS" ]; then
  echo "PASS: no ! block uses a bare \$0-\$9"; PASS=$((PASS + 1))
else
  echo "FAIL: these ! block lines use a bare \$N, which Claude Code replaces with an argument (write \${1} or awk \$(N)):"
  printf '%s' "$HITS"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && exit 1
[ "$FAIL" -gt 0 ] && exit 1
exit 0
