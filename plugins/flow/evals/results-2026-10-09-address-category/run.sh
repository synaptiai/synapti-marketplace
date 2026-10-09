#!/usr/bin/env bash
# Replay of the address.category decision point for one question wording
# (issue #296). Runs the shipped COMMENT_CATEGORY_BLOCK of commands/address.md
# once per labelled item, from a copy of this plugin whose address.category
# questions are those of current.yaml or alternative.yaml, with the site in
# shadow mode, and keeps the records.
#
# Usage:
#   run.sh --form current|alternative --out <dir>
#          [--items <file>] [--settings <file>]
#
#   --form      which wording: current.yaml or alternative.yaml in this
#               directory
#   --out       where records-<form>.jsonl, meta-<form>.jsonl and
#               run-<form>.json are written
#   --items     the labelled items, one JSON object per line (ref, pr,
#               finding_id, path, line, text, reviewer_priority); default
#               ../results-2026-10-07-address-s1/address-category.jsonl
#   --settings  a JSON file whose systemOne block names the provider; the
#               site's mode is set to shadow on top of it. Default: TypeSafe,
#               model jev-1.13.0, key in TYPESAFE_API_KEY
#
# The copy, its state directory and the working directory are made under
# TMPDIR and must be outside every git repository: the client refuses the
# user's settings when the plugin runs from inside one. Records go to that
# state directory, never to the user's own. An item whose text contains P1,
# P2 or P3, in either case, is not sent, so the label cannot reach the model.
# Each item is sent as a review finding (ITEM_KIND=review), so its record's
# ref is pr:<pr>/review:<id>/<finding>, unique per item.
#
# A form's earlier output files are removed once every setup check has passed,
# just before the first item is asked, and run-<form>.json
# is written only when every item was run or refused, so summarize.py never
# reads a stopped run as a complete one.
#
# Exit: 0 when every item was run or refused; 1 on a usage or setup error,
# after 10 transport failures in a row, or on the first item the client could
# not ask for a reason that would repeat for every item (settings, key, site,
# plugin), or whose block exited non-zero.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN=$(cd "$HERE/../.." && pwd -P)
FORM="" OUT="" ITEMS="$HERE/../results-2026-10-07-address-s1/address-category.jsonl" SETTINGS=""
die() { printf 'run.sh: %s\n' "$1" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --form) FORM="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --items) ITEMS="${2:-}"; shift 2 ;;
    --settings) SETTINGS="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$FORM" in current|alternative) ;; *) die "--form must be current or alternative" ;; esac
[ -n "$OUT" ] || die "--out is required"
[ -f "$ITEMS" ] || die "no items file: $ITEMS"
[ -z "$SETTINGS" ] || [ -f "$SETTINGS" ] || die "no settings file: $SETTINGS"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
mkdir -p "$OUT" || die "cannot make $OUT"
OUT=$(cd "$OUT" && pwd -P)
META="$OUT/meta-$FORM.jsonl" RECORDS="$OUT/records-$FORM.jsonl" RUNFILE="$OUT/run-$FORM.json"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/flow-ac-replay.XXXXXX") || die "mktemp failed"
# On any exit, a run stopped part way included, the records written so far are
# kept before the scratch directory goes. When they cannot be copied, the
# scratch directory is left where it is and named.
_keep_records() {
  if [ -f "$SCRATCH/state/system-one.jsonl" ] && ! cp "$SCRATCH/state/system-one.jsonl" "$RECORDS"; then
    printf 'run.sh: the records could not be copied to %s; they are kept in %s\n' "$RECORDS" "$SCRATCH/state" >&2
    return
  fi
  rm -rf -- "$SCRATCH"
}
trap _keep_records EXIT
if git -C "$SCRATCH" rev-parse --show-toplevel >/dev/null 2>&1; then
  die "the scratch directory $SCRATCH is inside a git repository; set TMPDIR to a directory outside every repository"
fi
COPY="$SCRATCH/flow" STATE="$SCRATCH/state" WORK="$SCRATCH/work" ITMP="$SCRATCH/tmp"
mkdir -p "$STATE" "$WORK" "$ITMP" || die "cannot make the scratch directories"
# The plugin without its evals and tests, which the block does not use.
mkdir -p "$COPY" && tar -C "$PLUGIN" --exclude ./evals --exclude ./tests -cf - . | tar -C "$COPY" -xf - \
  || die "cannot copy the plugin"
[ -x "$COPY/bin/flow-s1.sh" ] || die "the plugin copy has no bin/flow-s1.sh"

# Every python3 below runs from the scratch working directory, and each inline
# script first drops sys.path entries that are relative or name the working
# directory, so a yaml.py or json.py where run.sh was started is never loaded
# while the provider key is in the environment. PYTHONPATH is kept: it can hold
# a per-user PyYAML.
# The form's wording replaces the copy's address.category site.
__patched=$(cd "$WORK" && python3 - "$COPY" "$HERE/$FORM.yaml" <<'PY'
import os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)
               and not (os.path.isdir(p) and os.path.samefile(p, os.curdir))]
import yaml
copy, form = sys.argv[1], sys.argv[2]
path = copy + "/system-one/questions.yaml"
with open(path) as f:
    doc = yaml.safe_load(f)
with open(form) as f:
    doc["sites"]["address.category"] = yaml.safe_load(f)["sites"]["address.category"]
with open(path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False, allow_unicode=True, width=1000)
PY
) || die "cannot patch the copy's questions"
# The sha256 of the copy's address.category questions as the client loads
# them, from the same function summarize.py checks it with.
SENT=$(cd "$WORK" && python3 "$HERE/summarize.py" --hash "$COPY/system-one/questions.yaml") || die "cannot hash the copy's questions"
[ "$SENT" = "$(cd "$WORK" && python3 "$HERE/summarize.py" --hash "$HERE/$FORM.yaml")" ] \
  || die "the copy's address.category questions do not match $FORM.yaml"
printf 'SENT_SHA256=%s\n' "$SENT"

# The user settings: the given provider, or TypeSafe, with the site in shadow.
USER_SETTINGS="$SCRATCH/settings.flow.json"
if [ -n "$SETTINGS" ]; then
  jq '.systemOne.uses["address.category"] = "shadow"' "$SETTINGS" > "$USER_SETTINGS" || die "cannot read $SETTINGS"
else
  [ -n "${TYPESAFE_API_KEY:-}" ] || die "TYPESAFE_API_KEY is not set"
  jq -n '{systemOne: {provider: "typesafe", model: "jev-1.13.0", apiKeyEnv: "TYPESAFE_API_KEY", uses: {"address.category": "shadow"}}}' > "$USER_SETTINGS"
fi
# The state limit the client applies: systemOne.stateTokenCap when it is a
# positive whole number, otherwise the provider's default.
CAP=$(cd "$WORK" && python3 - "$COPY" "$USER_SETTINGS" <<'PY'
import os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)
               and not (os.path.isdir(p) and os.path.samefile(p, os.curdir))]
import json
sys.path.insert(0, sys.argv[1] + "/bin")
import _flow_s1 as s
with open(sys.argv[2]) as f:
    one = json.load(f).get("systemOne") or {}
raw = one.get("stateTokenCap")
# As the client reads it: a whole number of up to 9 digits (a trailing .0
# allowed), with 0 or anything else meaning the provider's default.
cap = s.whole_number(json.dumps(raw).strip('"')) if raw is not None else 0
if not cap:
    cap = s.PRESETS[one.get("provider") or "custom"]["cap"]
print(cap)
PY
) || die "cannot read the provider's state limit"

BLOCK="$SCRATCH/block.sh"
sed -n '/^# COMMENT_CATEGORY_BLOCK_BEGIN$/,/^# COMMENT_CATEGORY_BLOCK_END$/p' "$COPY/commands/address.md" > "$BLOCK"
[ -s "$BLOCK" ] || die "COMMENT_CATEGORY_BLOCK not found in the copy's commands/address.md"

COMMIT=$(git -C "$PLUGIN" rev-parse HEAD 2>/dev/null || echo unknown)
# Uncommitted changes in the plugin, apart from the output files this harness
# and summarize.py write, whose copies from an earlier form would otherwise
# count. The scripts themselves still count. "unknown" when git cannot say.
EXCL=()
case "$OUT/" in
  "$PLUGIN"/*)
    for __g in 'records-*.jsonl' 'meta-*.jsonl' 'run-*.json' 'summary.md' 'summary.json' 'rulings.jsonl'; do
      EXCL+=(":(exclude,glob)${OUT#"$PLUGIN"/}/$__g")
    done ;;
esac
if __st=$(git -C "$PLUGIN" status --porcelain -- . ${EXCL[@]+"${EXCL[@]}"} 2>/dev/null); then
  if [ -z "$__st" ]; then DIRTY=false; else DIRTY=true; fi
else
  DIRTY='"unknown"'
fi
# Every setup check has passed: the earlier output goes now, and not before,
# so a run that cannot start leaves the previous one's records in place.
rm -f -- "$META" "$RECORDS" "$RUNFILE" || die "cannot remove the earlier output of $FORM"
STARTED=$(date -u +%FT%TZ)
: > "$META"
FAILS=0 N=0 REFUSED=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  REF=$(jq -r .ref <<<"$line")
  # replay:pr-finding:pr<pr>-review<id>-<finding>; the finding may hold dashes.
  if [[ ! "$REF" =~ ^replay:pr-finding:pr([0-9]+)-review([0-9]+)-([A-Za-z][A-Za-z0-9_-]*)$ ]]; then
    die "item ref not in the expected shape: $REF"
  fi
  PR=${BASH_REMATCH[1]} ID=${BASH_REMATCH[2]} FINDING=${BASH_REMATCH[3]}
  if jq -e '.text | test("P[123]"; "i")' <<<"$line" >/dev/null; then
    jq -nc --arg r "$REF" '{ref: $r, refused: true, reason: "text names a priority"}' >> "$META"
    REFUSED=$((REFUSED + 1))
    continue
  fi
  ITEM=$(TMPDIR="$ITMP" mktemp "$ITMP/tmp.XXXXXX") || die "mktemp failed"
  jq -c '{text: .text, path: (.path // ""), line: ((.line // "") | tostring), finding: (.finding_id // "")}' <<<"$line" > "$ITEM"
  # The state the block sends, rebuilt the same way, for its sha256 and size.
  STATE_FILE="$SCRATCH/state.json"
  jq '{comment: {text: .text, path: (.path // ""), line: ((.line // "") | tostring)}}' "$ITEM" > "$STATE_FILE"
  INFO=$(cd "$WORK" && python3 - "$COPY" "$STATE_FILE" "$CAP" <<'PY'
import os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)
               and not (os.path.isdir(p) and os.path.samefile(p, os.curdir))]
import json
sys.path.insert(0, sys.argv[1] + "/bin")
import _flow_s1 as s
_, truncated, digest = s.load_state(sys.argv[2], "json", int(sys.argv[3]))
print(json.dumps({"state_sha256": digest, "truncated": truncated}))
PY
) || die "cannot read the rebuilt state"
  LABEL=$(jq -r .reviewer_priority <<<"$line")
  # The caller's environment, less what could choose other settings, another
  # plugin or a run directory. PYTHONPATH stays: it can hold the PyYAML a
  # per-user install put under the real HOME.
  OUTPUT=$(cd "$WORK" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_PROJECT_DIR -u RUN_ID -u CDPATH \
      TMPDIR="$ITMP" CLAUDE_PLUGIN_ROOT="$COPY" FLOW_USER_SETTINGS="$USER_SETTINGS" FLOW_STATE_DIR="$STATE" \
      SESSION_CATEGORY="$LABEL" PR_NUM="$PR" ITEM_KIND=review ITEM_ID="$ID" ITEM_FILE="$ITEM" \
      bash "$BLOCK" < /dev/null 2> "$SCRATCH/block.err")
  RC=$?
  [ -e "$ITEM" ] && { rm -f "$ITEM"; die "the block left the item file behind for $REF"; }
  REASON=$(sed -n 's/^flow-s1: no answer: \([a-z0-9-]*\).*/\1/p' "$SCRATCH/block.err" | head -n 1)
  jq -nc --arg r "$REF" --arg rec "pr:$PR/review:$ID/$FINDING" --argjson i "$INFO" --argjson rc "$RC" \
    --arg out "$OUTPUT" --arg reason "$REASON" \
    '{ref: $r, record_ref: $rec, refused: false, block_rc: $rc, block_stdout: $out, reason: $reason} + $i' >> "$META"
  N=$((N + 1))
  [ "$RC" -eq 0 ] || die "the block exited $RC for $REF: $(head -c 400 "$SCRATCH/block.err")"
  # shadow and below-threshold are answers; the transport reasons may pass; an
  # abstention, a missing answer or a state too large concern this item only.
  # Any other reason (or none) would repeat for every item, so the run stops.
  case "$REASON" in
    shadow|below-threshold) FAILS=0 ;;
    timeout|connection|redirect|http-*|malformed) FAILS=$((FAILS + 1)) ;;
    abstained|missing-answer|state-too-large) FAILS=0 ;;
    *) die "the client gave no answer for $REF (${REASON:-no reason}); stopped after $N items: $(head -c 400 "$SCRATCH/block.err")" ;;
  esac
  [ "$FAILS" -lt 10 ] || die "10 transport failures in a row; stopped after $N items"
  [ -n "$SETTINGS" ] || sleep 0.6
done < "$ITEMS"

if [ -f "$STATE/system-one.jsonl" ]; then
  cp "$STATE/system-one.jsonl" "$RECORDS" || die "cannot copy the records to $RECORDS"
else
  : > "$RECORDS"
fi
jq -n --arg f "$FORM" --arg s "$SENT" --arg c "$COMMIT" --argjson d "$DIRTY" --arg a "$STARTED" \
  --arg b "$(date -u +%FT%TZ)" --argjson n "$N" --argjson r "$REFUSED" \
  --arg m "$(jq -r '.systemOne.model // "jev-1.13.0"' "$USER_SETTINGS")" \
  '{form: $f, sent_sha256: $s, model: $m, commit: $c, uncommitted_changes: $d, started: $a, ended: $b, asked: $n, refused: $r}' \
  > "$RUNFILE"
printf 'ASKED=%s\nREFUSED=%s\n' "$N" "$REFUSED"
