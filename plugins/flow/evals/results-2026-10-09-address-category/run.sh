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
# state directory, never to the user's own. An item whose text names a
# priority (P1, P2 or P3) is not sent, so the label cannot reach the model.
# Each item is sent as a review finding (ITEM_KIND=review), so its record's
# ref is pr:<pr>/review:<id>/<finding>, unique per item.
#
# Exit: 0 when every item was run or refused; 1 on a usage or setup error, or
# after 10 transport failures in a row.
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

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/flow-ac-replay.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$SCRATCH"' EXIT
if git -C "$SCRATCH" rev-parse --show-toplevel >/dev/null 2>&1; then
  die "the scratch directory $SCRATCH is inside a git repository; set TMPDIR to a directory outside every repository"
fi
COPY="$SCRATCH/flow" STATE="$SCRATCH/state" WORK="$SCRATCH/work" ITMP="$SCRATCH/tmp"
mkdir -p "$STATE" "$WORK" "$ITMP" || die "cannot make the scratch directories"
# The plugin without its evals and tests, which the block does not use.
mkdir -p "$COPY" && tar -C "$PLUGIN" --exclude ./evals --exclude ./tests -cf - . | tar -C "$COPY" -xf - \
  || die "cannot copy the plugin"
[ -x "$COPY/bin/flow-s1.sh" ] || die "the plugin copy has no bin/flow-s1.sh"

# The form's wording replaces the copy's address.category site. The sent hash
# is the sha256 of the site's questions as the client loads them, in
# canonical JSON; it must equal the form file's.
SENT=$(python3 - "$COPY" "$HERE/$FORM.yaml" <<'PY'
import hashlib, json, sys
copy, form = sys.argv[1], sys.argv[2]
sys.path.insert(0, copy + "/bin")
import yaml
import _flow_s1 as s
path = copy + "/system-one/questions.yaml"
doc = yaml.safe_load(open(path))
doc["sites"]["address.category"] = yaml.safe_load(open(form))["sites"]["address.category"]
with open(path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False, allow_unicode=True, width=1000)
h = lambda p: hashlib.sha256(json.dumps(s.load_site(p, "address.category")[0], sort_keys=True,
                                        separators=(",", ":")).encode()).hexdigest()
sent, want = h(path), h(form)
if sent != want:
    sys.exit("the copy's address.category questions do not match " + form)
print(sent)
PY
) || die "cannot patch the copy's questions"
printf 'SENT_SHA256=%s\n' "$SENT"

# The user settings: the given provider, or TypeSafe, with the site in shadow.
USER_SETTINGS="$SCRATCH/settings.flow.json"
if [ -n "$SETTINGS" ]; then
  jq '.systemOne.uses["address.category"] = "shadow"' "$SETTINGS" > "$USER_SETTINGS" || die "cannot read $SETTINGS"
else
  [ -n "${TYPESAFE_API_KEY:-}" ] || die "TYPESAFE_API_KEY is not set"
  jq -n '{systemOne: {provider: "typesafe", model: "jev-1.13.0", apiKeyEnv: "TYPESAFE_API_KEY", uses: {"address.category": "shadow"}}}' > "$USER_SETTINGS"
fi

BLOCK="$SCRATCH/block.sh"
sed -n '/^# COMMENT_CATEGORY_BLOCK_BEGIN$/,/^# COMMENT_CATEGORY_BLOCK_END$/p' "$COPY/commands/address.md" > "$BLOCK"
[ -s "$BLOCK" ] || die "COMMENT_CATEGORY_BLOCK not found in the copy's commands/address.md"

COMMIT=$(git -C "$PLUGIN" rev-parse HEAD 2>/dev/null || echo unknown)
DIRTY=false
[ -z "$(git -C "$PLUGIN" status --porcelain -- . 2>/dev/null)" ] || DIRTY=true
STARTED=$(date -u +%FT%TZ)
META="$OUT/meta-$FORM.jsonl"
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
  if jq -e '.text | test("\\bP[123]\\b")' <<<"$line" >/dev/null; then
    jq -nc --arg r "$REF" '{ref: $r, refused: true, reason: "text names a priority"}' >> "$META"
    REFUSED=$((REFUSED + 1))
    continue
  fi
  ITEM=$(TMPDIR="$ITMP" mktemp "$ITMP/tmp.XXXXXX") || die "mktemp failed"
  jq -c '{text: .text, path: (.path // ""), line: ((.line // "") | tostring), finding: (.finding_id // "")}' <<<"$line" > "$ITEM"
  # The state the block sends, rebuilt the same way, for its sha256 and size.
  STATE_FILE="$SCRATCH/state.json"
  jq '{comment: {text: .text, path: (.path // ""), line: ((.line // "") | tostring)}}' "$ITEM" > "$STATE_FILE"
  INFO=$(python3 - "$COPY" "$STATE_FILE" <<'PY'
import hashlib, json, sys
sys.path.insert(0, sys.argv[1] + "/bin")
import _flow_s1 as s
_, truncated, digest = s.load_state(sys.argv[2], "json", s.PRESETS["typesafe"]["cap"])
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
  case "$REASON" in
    timeout|connection|redirect|http-*|malformed) FAILS=$((FAILS + 1)) ;;
    *) FAILS=0 ;;
  esac
  [ "$FAILS" -lt 10 ] || die "10 transport failures in a row; stopped after $N items"
  [ -n "$SETTINGS" ] || sleep 0.6
done < "$ITEMS"

cp "$STATE/system-one.jsonl" "$OUT/records-$FORM.jsonl" 2>/dev/null || : > "$OUT/records-$FORM.jsonl"
jq -n --arg f "$FORM" --arg s "$SENT" --arg c "$COMMIT" --argjson d "$DIRTY" --arg a "$STARTED" \
  --arg b "$(date -u +%FT%TZ)" --argjson n "$N" --argjson r "$REFUSED" \
  --arg m "$(jq -r '.systemOne.model // "jev-1.13.0"' "$USER_SETTINGS")" \
  '{form: $f, sent_sha256: $s, model: $m, commit: $c, uncommitted_changes: $d, started: $a, ended: $b, sent: $n, refused: $r}' \
  > "$OUT/run-$FORM.json"
printf 'SENT=%s\nREFUSED=%s\n' "$N" "$REFUSED"
