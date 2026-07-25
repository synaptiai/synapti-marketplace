#!/usr/bin/env bash
# THE LOAD-BEARING TEST.
#
# Verification-pass independence is what makes three passes worth more than one.
# It is enforced by five structural properties, not by instructions in prose —
# prose drifts, and a verifier that has quietly gained access to reconciliation
# logic still produces a plausible-looking findings table. Nothing else in the
# suite would catch that.
#
# If this file fails, the three passes are no longer independent and the audit
# result is worth less than it appears to be.

_dossier_test_begin "agent-independence"

A="plugins/dossier/agents/dossier-pass-a-evidence.md"
B="plugins/dossier/agents/dossier-pass-b-falsification.md"
C="plugins/dossier/agents/dossier-pass-c-audience.md"
SCORER="plugins/dossier/agents/dossier-scorer.md"
AUDIT_CMD="plugins/dossier/commands/audit.md"

for f in "$A" "$B" "$C" "$SCORER"; do
  assert_file_exists "$f" "$(basename "$f") exists"
done

fm() { # field | file — read a frontmatter value
  awk -F': ' -v k="^$1:" '$0 ~ k {sub(/^[^:]*: */,""); print; exit}' "$2"
}

# --- Property 1: no project memory carryover ---------------------------------
for f in "$A" "$B" "$C" "$SCORER"; do
  assert_equal "none" "$(fm memory "$f")" "$(basename "$f" .md): memory is none"
done

# --- Property 2: the skill firewall ------------------------------------------
# A verifier that could load finding-reconciliation would carry the merge and
# corroboration logic into its context and drift toward the consensus it
# expects the other passes to reach. That is precisely the correlated-error
# failure three passes exist to prevent.
for f in "$A" "$B" "$C" "$SCORER"; do
  SKILLS=$(fm skills "$f")
  case "$SKILLS" in
    *finding-reconciliation*)
      _dossier_assert_fail "$(basename "$f" .md) loads finding-reconciliation — the skill firewall is breached" ;;
    *)
      _dossier_assert_pass "$(basename "$f" .md): no reconciliation logic in context" ;;
  esac
done

# --- Property 3: divergent analytical priors ---------------------------------
# Each pass loads verification-protocol plus a DIFFERENT second skill, so the
# three lenses differ by construction rather than by instruction.
second() { fm skills "$1" | awk -F', ' '{print $2}'; }
SA=$(second "$A"); SB=$(second "$B"); SC=$(second "$C")
DISTINCT=$(printf '%s\n%s\n%s\n' "$SA" "$SB" "$SC" | sort -u | grep -c .)
assert_equal "3" "$DISTINCT" "the three passes load three distinct second skills ($SA / $SB / $SC)"

for f in "$A" "$B" "$C"; do
  case "$(fm skills "$f")" in
    verification-protocol*) _dossier_assert_pass "$(basename "$f" .md): verification-protocol is first" ;;
    *) _dossier_assert_fail "$(basename "$f" .md): verification-protocol must be the first skill" ;;
  esac
done

# --- Property 4: no pass references another pass -----------------------------
assert_not_contains "dossier-pass-b" "$(cat "$A")" "pass A does not reference pass B"
assert_not_contains "dossier-pass-c" "$(cat "$A")" "pass A does not reference pass C"
assert_not_contains "dossier-pass-a" "$(cat "$B")" "pass B does not reference pass A"
assert_not_contains "dossier-pass-c" "$(cat "$B")" "pass B does not reference pass C"
assert_not_contains "dossier-pass-a" "$(cat "$C")" "pass C does not reference pass A"
assert_not_contains "dossier-pass-b" "$(cat "$C")" "pass C does not reference pass B"

# --- Property 5: single-message dispatch -------------------------------------
# Sequential dispatch puts pass A's findings into the orchestrator's context
# before pass B is spawned. The command must say so and must not be edited to
# dispatch one at a time.
AUDIT=$(cat "$AUDIT_CMD")
assert_contains "One message. Three calls." "$AUDIT" "audit.md mandates single-message dispatch"
assert_contains "SINGLE-MESSAGE DISPATCH IS LOAD-BEARING" "$AUDIT" "audit.md carries the dispatch warning"

for a in dossier-pass-a-evidence dossier-pass-b-falsification dossier-pass-c-audience; do
  assert_contains "Agent($a)" "$AUDIT" "audit.md dispatches $a"
done

# --- The orchestrator must not merge -----------------------------------------
# Anything in the audit command's context is one dispatch away from a verifier's.
assert_contains "must not" "$AUDIT" "audit.md states its non-goals"
case "$(sed -n '/## Required Skills/,/^## /p' "$AUDIT_CMD")" in
  *finding-reconciliation*)
    _dossier_assert_fail "audit.md requires finding-reconciliation — the orchestrator must not merge" ;;
  *)
    _dossier_assert_pass "audit.md does not load reconciliation logic" ;;
esac

# --- The independence protocol is stated in every pass -----------------------
for f in "$A" "$B" "$C"; do
  body=$(cat "$f")
  assert_contains "Independence Protocol" "$body" "$(basename "$f" .md): states the independence protocol"
  assert_contains "MUST NOT" "$body" "$(basename "$f" .md): carries an explicit denial list"
done

# --- Findings precede repair -------------------------------------------------
for f in "$A" "$B" "$C"; do
  assert_contains "before" "$(sed -n '/## Output/,$p' "$f")" \
    "$(basename "$f" .md): emits findings before repair"
done

# --- Reconciliation-only fields never appear as pass OUTPUT -------------------
# A pass that emits a corroboration count or adjudicates a contradiction has
# seen the other passes. The words are allowed in the denial list — that is the
# pass being told it may not have them — but must not appear in the output
# contract, which starts at the "## Output" heading.
for f in "$A" "$B" "$C"; do
  out=$(sed -n '/^## Output/,$p' "$f")
  for field in "corroboration" "N/3"; do
    case "$out" in
      *"$field"*) _dossier_assert_fail "$(basename "$f" .md): emits '$field' — a reconciliation-only field" ;;
      *)          _dossier_assert_pass "$(basename "$f" .md): does not emit '$field'" ;;
    esac
  done
done

# --- Persona ownership agrees with the protocol ------------------------------
# The protocol assigns the technical-executive persona to pass A (its question
# is about grounding) and the other six to pass C (theirs are about
# navigation). The agents and the reference disagreeing about who simulates
# whom is the same cross-document contradiction the package format exists to
# surface — shipping it would be the plugin failing its own dimension 4.
PROTO="plugins/dossier/references/independent-audit-protocol.md"
if [ -f "$PROTO" ]; then
  assert_contains "six of the seven personas" "$(cat "$PROTO")" "protocol states the 6/1 persona split"

  C_TABLE=$(sed -n '/| Reader | Task | Fails when |/,/^$/p' "$C")
  assert_not_contains "Technical executive" "$C_TABLE" "pass C does not claim the technical-executive persona"

  # Data rows only: drop the header and the `|---|` separator, which has no
  # space after its pipe and so needs excluding by content, not by position.
  C_PERSONAS=$(printf '%s' "$C_TABLE" | grep '^| ' | grep -v '^| Reader ' | grep -c .)
  assert_equal "6" "$C_PERSONAS" "pass C simulates exactly 6 personas"

  assert_contains "technical executive" "$(cat "$A")" "pass A carries the technical-executive persona"
fi

# --- The scorer sees outcomes, not process -----------------------------------
SC_BODY=$(cat "$SCORER")
assert_contains "repair rationale" "$SC_BODY" "scorer is denied the repair rationale"
assert_contains "self-score" "$SC_BODY" "scorer is denied prior self-scores"

_dossier_test_summary
