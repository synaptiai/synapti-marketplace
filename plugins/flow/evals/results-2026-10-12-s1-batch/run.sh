#!/usr/bin/env bash
# The comparison of issue #295: System One answers about items asked one per
# request against the same items asked together (bin/flow-s1.sh ask-many),
# as pre-registered in .decisions/issue-295.md. For each group of items (the
# criteria of one goal, or the findings of one review run) it makes four
# sends, from a copy of this plugin outside any repository, in shadow mode:
#
#   A1, A2  every item alone, through flow-s1.sh ask, one call after another
#   S       one ask-many call with systemOne.batch items-in-state
#   Q       one ask-many call with systemOne.batch items-in-questions
#
# The order of the four rotates from group to group (A1 S A2 Q, then
# S A2 Q A1, ...), so drift over the session falls on every send alike.
#
# Usage:
#   run.sh --set goal|review --out <dir> [--settings <file>]
#          [--goal-items <file>] [--review-dir <dir>]
#
#   --set         goal: the 2026-10-07 goal replay (goal.judge), grouped by
#                 goal; review: the 2026-10-04 review.confidence states,
#                 grouped by run
#   --out         where inputs-<set>.jsonl, records-<set>-<send>.jsonl,
#                 meta-<set>.jsonl and run-<set>.json are written
#   --settings    a JSON file whose systemOne block names the provider; the
#                 site's mode and batch are set on top of it. Default:
#                 TypeSafe, model jev-1.13.0, key in TYPESAFE_API_KEY
#   --goal-items  the goal replay's items.jsonl (each line: goal, ref, label,
#                 kind, state_file relative to the file's directory); default
#                 ~/flow-s1-work/replay/A/items.jsonl
#   --review-dir  the directory holding <model>/review-b/<case>/<trap>/<n>/
#                 run/system-one-state/confidence-<id>.json; default
#                 ../results-2026-09-25-review/replay/shadow/base
#
# The goal states stay where they are; inputs-goal.jsonl names each by the
# sha256 of its file, and so does every record. The copy, its state
# directories and the working directory are made under TMPDIR, outside every
# git repository: the client refuses the user's settings when the plugin runs
# from inside one. Records never go to the user's own state directory.
#
# A set's earlier output is removed once every setup check has passed, and
# run-<set>.json is written only when every group was sent, so summarize.py
# never reads a stopped run as a complete one.
#
# Exit: 0 when every group was sent; 1 on a usage or setup error, on an ask
# call that gave no answer for a reason that would repeat for every item
# (settings, key, site, plugin), or on an ask-many call that did not exit 0.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN=$(cd "$HERE/../.." && pwd -P)
SET="" OUT="" SETTINGS=""
GOAL_ITEMS="$HOME/flow-s1-work/replay/A/items.jsonl"
REVIEW_DIR="$HERE/../results-2026-09-25-review/replay/shadow/base"
die() { printf 'run.sh: %s\n' "$1" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --set) SET="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --settings) SETTINGS="${2:-}"; shift 2 ;;
    --goal-items) GOAL_ITEMS="${2:-}"; shift 2 ;;
    --review-dir) REVIEW_DIR="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$SET" in
  goal) SITE=goal.judge ;;
  review) SITE=review.confidence ;;
  *) die "--set must be goal or review" ;;
esac
[ -n "$OUT" ] || die "--out is required"
[ -z "$SETTINGS" ] || [ -f "$SETTINGS" ] || die "no settings file: $SETTINGS"
if [ "$SET" = goal ]; then [ -f "$GOAL_ITEMS" ] || die "no goal items file: $GOAL_ITEMS"; fi
if [ "$SET" = review ]; then [ -d "$REVIEW_DIR" ] || die "no review directory: $REVIEW_DIR"; fi
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
mkdir -p "$OUT" || die "cannot make $OUT"
OUT=$(cd "$OUT" && pwd -P)
INPUTS="$OUT/inputs-$SET.jsonl" META="$OUT/meta-$SET.jsonl" RUNFILE="$OUT/run-$SET.json"
SENDS=(A1 S A2 Q)

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/flow-batch-replay.XXXXXX") || die "mktemp failed"
# On any exit, a run stopped part way included, the records written so far are
# kept before the scratch directory goes. When one cannot be copied, the
# scratch directory is left where it is and named.
_keep_records() {
  local s ok=1
  for s in "${SENDS[@]}"; do
    if [ -f "$SCRATCH/state-$s/system-one.jsonl" ] && ! cp "$SCRATCH/state-$s/system-one.jsonl" "$OUT/records-$SET-$s.jsonl"; then
      printf 'run.sh: the %s records could not be copied; they are kept in %s\n' "$s" "$SCRATCH/state-$s" >&2
      ok=0
    fi
  done
  [ "$ok" = 1 ] && rm -rf -- "$SCRATCH"
}
trap _keep_records EXIT
if git -C "$SCRATCH" rev-parse --show-toplevel >/dev/null 2>&1; then
  die "the scratch directory $SCRATCH is inside a git repository; set TMPDIR to a directory outside every repository"
fi
COPY="$SCRATCH/flow" WORK="$SCRATCH/work" ITMP="$SCRATCH/tmp"
mkdir -p "$WORK" "$ITMP" || die "cannot make the scratch directories"
for s in "${SENDS[@]}"; do mkdir -p "$SCRATCH/state-$s" || die "cannot make the scratch directories"; done
mkdir -p "$COPY" && tar -C "$PLUGIN" --exclude ./evals --exclude ./tests -cf - . | tar -C "$COPY" -xf - \
  || die "cannot copy the plugin"
[ -x "$COPY/bin/flow-s1.sh" ] || die "the plugin copy has no bin/flow-s1.sh"

# One user settings file per send: the given provider, or TypeSafe, with the
# site in shadow and batch off (A1, A2) or the send's layout (S, Q).
BASE="$SCRATCH/base.json"
if [ -n "$SETTINGS" ]; then
  jq . "$SETTINGS" > "$BASE" || die "cannot read $SETTINGS"
else
  [ -n "${TYPESAFE_API_KEY:-}" ] || die "TYPESAFE_API_KEY is not set"
  jq -n '{systemOne: {provider: "typesafe", model: "jev-1.13.0", apiKeyEnv: "TYPESAFE_API_KEY"}}' > "$BASE"
fi
for s in "${SENDS[@]}"; do
  case "$s" in A1|A2) b=off ;; S) b=items-in-state ;; Q) b=items-in-questions ;; esac
  jq --arg site "$SITE" --arg b "$b" '.systemOne.uses[$site] = "shadow" | .systemOne.batch = $b' "$BASE" \
    > "$SCRATCH/settings-$s.json" || die "cannot write the settings for $s"
done
TIMEOUT_MS=$(jq -r '.systemOne.timeoutMs // 3000' "$BASE")
MODEL=$(jq -r '.systemOne.model // "jev-1.13.0"' "$BASE")

# The items, one JSON line each: {group, key, ref, state_file, sha256} and,
# for the goal set, label and kind. Every python3 runs from the scratch
# working directory with sys.path entries that are relative or name it
# dropped, so no module where run.sh was started is loaded while the key is
# in the environment.
ITEMS="$SCRATCH/items.jsonl"
(cd "$WORK" && python3 - "$SET" "$GOAL_ITEMS" "$REVIEW_DIR" > "$ITEMS" <<'PY'
import os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)
               and not (os.path.isdir(p) and os.path.samefile(p, os.curdir))]
import hashlib, json, re
which, goal_items, review_dir = sys.argv[1:4]
def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()
out, counts = [], {}
if which == "goal":
    base = os.path.dirname(os.path.abspath(goal_items))
    with open(goal_items, encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            it = json.loads(line)
            path = it["state_file"] if os.path.isabs(it["state_file"]) else os.path.join(base, it["state_file"])
            g = it["goal"]
            n = counts.get(g, 0)
            counts[g] = n + 1
            out.append({"group": g, "key": "c%d" % n, "ref": it["ref"], "state_file": path, "sha256": sha(path),
                        "label": it["label"], "kind": it["kind"]})
else:
    for root, dirs, files in sorted(os.walk(review_dir)):
        dirs.sort()
        if os.path.basename(root) != "system-one-state":
            continue
        run = os.path.relpath(os.path.dirname(os.path.dirname(root)), review_dir)
        for name in sorted(files):
            m = re.fullmatch(r"confidence-([A-Za-z][A-Za-z0-9_-]*)\.json", name)
            if not m:
                continue
            path = os.path.join(root, name)
            out.append({"group": run, "key": m.group(1), "ref": "batch:%s/%s" % (run, m.group(1)),
                        "state_file": path, "sha256": sha(path)})
for it in out:
    print(json.dumps(it, sort_keys=True))
PY
) || die "cannot read the $SET items"
[ -s "$ITEMS" ] || die "no $SET items found"
# Refs must be ones the client takes (letters, digits and . _ : / # @ + -).
jq -e -s 'all(.[]; .ref | test("^[A-Za-z0-9][A-Za-z0-9._:/#@+-]{0,199}$"))' "$ITEMS" >/dev/null \
  || die "an item's ref is not one the client takes"
GROUPS_FILE="$SCRATCH/groups"
jq -r .group "$ITEMS" | awk '!seen[$0]++' > "$GROUPS_FILE"

COMMIT=$(git -C "$PLUGIN" rev-parse HEAD 2>/dev/null || echo unknown)
EXCL=()
case "$OUT/" in
  "$PLUGIN"/*)
    for __g in 'inputs-*.jsonl' 'records-*.jsonl' 'meta-*.jsonl' 'run-*.json' 'summary.md' 'summary.json'; do
      EXCL+=(":(exclude,glob)${OUT#"$PLUGIN"/}/$__g")
    done ;;
esac
if __st=$(git -C "$PLUGIN" status --porcelain -- . ${EXCL[@]+"${EXCL[@]}"} 2>/dev/null); then
  if [ -z "$__st" ]; then DIRTY=false; else DIRTY=true; fi
else
  DIRTY='"unknown"'
fi

# _client <send> <args...> — the copy's flow-s1.sh with that send's settings
# and state directory; sets C_OUT, C_ERR, C_RC and C_MS (wall time in ms).
_client() {
  local s="$1" t0 t1; shift
  t0=$(python3 -c 'import time; print(time.monotonic_ns() // 1000000)')
  C_OUT=$(cd "$WORK" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_PROJECT_DIR -u RUN_ID -u CDPATH \
      TMPDIR="$ITMP" CLAUDE_PLUGIN_ROOT="$COPY" FLOW_USER_SETTINGS="$SCRATCH/settings-$s.json" \
      FLOW_STATE_DIR="$SCRATCH/state-$s" "$COPY/bin/flow-s1.sh" "$@" < /dev/null 2> "$SCRATCH/client.err")
  C_RC=$?
  t1=$(python3 -c 'import time; print(time.monotonic_ns() // 1000000)')
  C_MS=$((t1 - t0))
  C_ERR=$(head -c 400 "$SCRATCH/client.err")
}

# Every setup check has passed: the earlier output goes now, and not before.
rm -f -- "$INPUTS" "$META" "$RUNFILE" "$OUT"/records-"$SET"-*.jsonl || die "cannot remove the earlier output of $SET"
cp "$ITEMS" "$INPUTS.tmp" && jq -c 'del(.state_file)' "$INPUTS.tmp" > "$INPUTS" && rm -f "$INPUTS.tmp" \
  || die "cannot write $INPUTS"
STARTED=$(date -u +%FT%TZ)
: > "$META"
G=0
while IFS= read -r group; do
  jq -c --arg g "$group" 'select(.group == $g)' "$ITEMS" > "$SCRATCH/group.jsonl"
  jq -sc '{items: map({key, state_file, current: "replay", ref})}' "$SCRATCH/group.jsonl" > "$SCRATCH/group-items.json"
  for k in 0 1 2 3; do
    s=${SENDS[$(( (G + k) % 4 ))]}
    case "$s" in
      A1|A2)
        while IFS= read -r it; do
          _client "$s" ask --site "$SITE" --state-file "$(jq -r .state_file <<<"$it")" --state-format json \
            --current replay --ref "$(jq -r .ref <<<"$it")"
          REASON=$(sed -n 's/^flow-s1: no answer: \([a-z0-9-]*\).*/\1/p' <<<"$C_ERR" | head -n 1)
          jq -nc --arg g "$group" --arg s "$s" --arg k "$(jq -r .key <<<"$it")" --argjson rc "$C_RC" \
            --argjson ms "$C_MS" --arg reason "$REASON" \
            '{group: $g, send: $s, call: "ask", keys: [$k], rc: $rc, ms: $ms, reason: $reason}' >> "$META"
          case "$C_RC:$REASON" in
            0:*|3:shadow|3:below-threshold|3:timeout|3:connection|3:redirect|3:http-*|3:malformed|3:abstained|3:missing-answer|3:state-too-large) ;;
            *) die "send $s, group $group: the client gave no answer (${REASON:-exit $C_RC}): $C_ERR" ;;
          esac
        done < "$SCRATCH/group.jsonl"
        ;;
      S|Q)
        _client "$s" ask-many --site "$SITE" --items-file "$SCRATCH/group-items.json"
        jq -nc --arg g "$group" --arg s "$s" --argjson rc "$C_RC" --argjson ms "$C_MS" \
          --slurpfile keys <(jq -r .key "$SCRATCH/group.jsonl" | jq -R .) --arg out "$C_OUT" \
          '{group: $g, send: $s, call: "ask-many", keys: $keys, rc: $rc, ms: $ms,
            lines: ($out | split("\n") | map(select(length > 0) | fromjson))}' >> "$META" \
          || die "send $s, group $group: the client's output is not JSON lines"
        [ "$C_RC" = 0 ] || die "send $s, group $group: ask-many exited $C_RC: $C_ERR"
        ;;
    esac
  done
  G=$((G + 1))
done < "$GROUPS_FILE"

for s in "${SENDS[@]}"; do
  if [ -f "$SCRATCH/state-$s/system-one.jsonl" ]; then
    cp "$SCRATCH/state-$s/system-one.jsonl" "$OUT/records-$SET-$s.jsonl" || die "cannot copy the $s records"
  else
    : > "$OUT/records-$SET-$s.jsonl"
  fi
done
jq -n --arg set "$SET" --arg site "$SITE" --arg c "$COMMIT" --argjson d "$DIRTY" --arg a "$STARTED" \
  --arg b "$(date -u +%FT%TZ)" --argjson groups "$G" --argjson items "$(wc -l < "$ITEMS" | tr -d ' ')" \
  --arg m "$MODEL" --argjson t "$TIMEOUT_MS" \
  '{set: $set, site: $site, model: $m, timeout_ms: $t, commit: $c, uncommitted_changes: $d,
    started: $a, ended: $b, groups: $groups, items: $items, sends: ["A1", "A2", "S", "Q"]}' > "$RUNFILE"
printf 'GROUPS=%s\nITEMS=%s\n' "$G" "$(wc -l < "$ITEMS" | tr -d ' ')"
