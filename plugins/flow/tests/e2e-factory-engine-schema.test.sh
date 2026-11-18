# shellcheck shell=bash
# The factory's job and directive schemas, and the standard-library validator
# the engine checks job.json, directives, leases, results, stored events and
# shell report lines with, compared against jsonschema as the reference.
#
# Ways it can be wrong, written down before the checks:
#   S1 the stdlib validator accepts an instance jsonschema refuses
#   S2 it refuses an instance jsonschema accepts
#   S3 a schema keyword the validator does not implement is ignored silently,
#      including one nested in a $defs entry that nothing references
#   S4 additionalProperties: false is not enforced
#   S5 a $ref into $defs is not followed, or def_name is ignored
#   S6 Python's own rules leak in: true taken as an integer or as 1 in an
#      enum or const, 1.0 refused as an integer, minimum or pattern applied to
#      a value of another type (null beside a minimum), pattern matched at the
#      start only instead of searched, a keyword beside a $ref dropped
#   S7 an invalid fixture is refused for a reason other than the one change
#      it was written with, so the agreement on "invalid" proves nothing; or
#      a missing required field is reported at its parent, not at its own
#      name (the engine reports `schema: <path of the first error>`)
#   S8 the schema's state list drifts from the state table, or its stage
#      list from the directive id pattern
#   S9 a property whose name is a keyword the validator lacks (format) is
#      refused as if it were that keyword

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

FS_FIX="$REPO_ROOT/plugins/flow/tests/fixtures/factory/schema"
FS_SCHEMAS="$E2E_PLUGIN_DIR/schemas/v1"
FS_BIN="$E2E_PLUGIN_DIR/bin"

# _fs_stdlib <mode> <arguments> — the plugin's validator with no site
# packages at all (-I -S), so it can only be using the standard library.
# Modes:
#   fixtures <fixture dir> <schema dir>  one line per fixture:
#                                        <file> TAB <valid|invalid> TAB <errors joined by " | ">
#   pairs <schema> <instances.jsonl>     one line per instance: <n> TAB <valid|invalid>
#   load <schema>                        ok, or <exception name>(<keyword>)
_fs_stdlib() {
  python3 -I -S - "$FS_BIN" "$@" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import _flow_factory_schema as fs
mode = sys.argv[2]
SHAPES = {"job": ("factory-job.schema.json", None), "directive": ("factory-directive.schema.json", None),
          "lease": ("factory-directive.schema.json", "lease"), "result": ("factory-directive.schema.json", "result"),
          "pending_event": ("factory-directive.schema.json", "pending_event"),
          "pending_report": ("factory-directive.schema.json", "pending_report")}
if mode == "fixtures":
    fix, schemas = sys.argv[3], sys.argv[4]
    for name in sorted(os.listdir(fix)):
        if not name.endswith(".json"):
            continue
        shape = name.split("-valid-")[0].split("-invalid-")[0]
        sfile, d = SHAPES[shape]
        with open(os.path.join(fix, name), encoding="utf-8") as f:
            inst = json.load(f)
        errs = fs.validate(inst, os.path.join(schemas, sfile), d)
        print("%s\t%s\t%s" % (name, "invalid" if errs else "valid", " | ".join(errs)))
elif mode == "pairs":
    with open(sys.argv[4], encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            errs = fs.validate(json.loads(line), sys.argv[3])
            print("%d\t%s" % (n, "invalid" if errs else "valid"))
elif mode == "load":
    try:
        fs.load(sys.argv[3])
        print("ok")
    except Exception as e:  # the exception's name is what the scenario checks
        print("%s(%s)" % (type(e).__name__, e))
PY
}

# _fs_reference <mode> <arguments> — the same verdicts from jsonschema's
# Draft202012Validator, the reference implementation. Modes fixtures and pairs
# as above (the fixtures mode prints <file> TAB <valid|invalid>).
_fs_reference() {
  python3 - "$@" <<'PY'
import json, os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != os.path.realpath(os.getcwd())]
import jsonschema
mode = sys.argv[1]
SHAPES = {"job": ("factory-job.schema.json", None), "directive": ("factory-directive.schema.json", None),
          "lease": ("factory-directive.schema.json", "lease"), "result": ("factory-directive.schema.json", "result"),
          "pending_event": ("factory-directive.schema.json", "pending_event"),
          "pending_report": ("factory-directive.schema.json", "pending_report")}
def schema_for(path, d):
    with open(path, encoding="utf-8") as f:
        s = json.load(f)
    if d is None:
        return s
    return {"$schema": s["$schema"], "$ref": "#/$defs/" + d, "$defs": s["$defs"]}
if mode == "fixtures":
    fix, schemas = sys.argv[2], sys.argv[3]
    for name in sorted(os.listdir(fix)):
        if not name.endswith(".json"):
            continue
        shape = name.split("-valid-")[0].split("-invalid-")[0]
        sfile, d = SHAPES[shape]
        with open(os.path.join(fix, name), encoding="utf-8") as f:
            inst = json.load(f)
        ok = jsonschema.Draft202012Validator(schema_for(os.path.join(schemas, sfile), d)).is_valid(inst)
        print("%s\t%s" % (name, "valid" if ok else "invalid"))
elif mode == "pairs":
    v = jsonschema.Draft202012Validator(schema_for(sys.argv[2], None))
    with open(sys.argv[3], encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            print("%d\t%s" % (n, "valid" if v.is_valid(json.loads(line)) else "invalid"))
PY
}

FS_HAVE_JSONSCHEMA=0
python3 -c 'import jsonschema' >/dev/null 2>&1 && FS_HAVE_JSONSCHEMA=1

# _fs_agree <shape> — every fixture of one shape: its name, the stdlib
# validator and jsonschema give the same verdict, and an invalid fixture's
# only stdlib error is at the path expected-errors.txt names for it.
_fs_agree() {
  local shape="$1" file want got_std got_ref errs path n_valid=0 n_invalid=0
  e2e_new "fs-agree-$shape"
  e2e_describe "every $shape fixture through the stdlib validator and jsonschema; the verdicts match the fixture names, and each invalid fixture's one error is at its hand-written path"
  cd "$E2E_DIR" || return 1
  local std
  std=$(_fs_stdlib fixtures "$FS_FIX" "$FS_SCHEMAS" 2>&1); local std_rc=$?
  local ref="" ref_rc=0
  if [ "$FS_HAVE_JSONSCHEMA" = 1 ]; then
    ref=$(_fs_reference fixtures "$FS_FIX" "$FS_SCHEMAS" 2>&1); ref_rc=$?
    e2e_expect_equal 0 "$ref_rc" "jsonschema run exit status"
  else
    printf 'jsonschema: not installed for python3; only the stdlib column is checked\n' >> "$E2E_ARTIFACT"
  fi
  e2e_expect_equal 0 "$std_rc" "stdlib validator exit status"
  [ "$std_rc" = 0 ] || printf 'stdlib output:\n%s\n' "$std" >> "$E2E_ARTIFACT"
  [ "$ref_rc" = 0 ] || printf 'jsonschema output:\n%s\n' "$ref" >> "$E2E_ARTIFACT"
  for file in $(cd "$FS_FIX" && LC_ALL=C ls -- "$shape"-valid-*.json "$shape"-invalid-*.json 2>/dev/null); do
    case "$file" in *-valid-*) want=valid; n_valid=$((n_valid + 1)) ;; *) want=invalid; n_invalid=$((n_invalid + 1)) ;; esac
    got_std=$(printf '%s\n' "$std" | awk -F'\t' -v f="$file" '$1 == f { print $2 }')
    errs=$(printf '%s\n' "$std" | awk -F'\t' -v f="$file" '$1 == f { print $3 }')
    got_ref=$(printf '%s\n' "$ref" | awk -F'\t' -v f="$file" '$1 == f { print $2 }')
    [ "$FS_HAVE_JSONSCHEMA" = 1 ] || got_ref=skipped
    printf '%s: stdlib=%s jsonschema=%s\n' "$file" "${got_std:-none}" "${got_ref:-none}" >> "$E2E_ARTIFACT"
    [ -n "$errs" ] && printf '  errors: %s\n' "$errs" >> "$E2E_ARTIFACT"
    e2e_expect_equal "$want" "$got_std" "stdlib verdict on $file"
    [ "$FS_HAVE_JSONSCHEMA" = 1 ] && e2e_expect_equal "$want" "$got_ref" "jsonschema verdict on $file"
    if [ "$want" = invalid ]; then
      path=$(awk -v f="$file" '$1 == f { print $2 }' "$FS_FIX/expected-errors.txt")
      e2e_expect_equal "1" "$(printf '%s' "$errs" | awk -F' [|] ' '{ print NF }')" "number of stdlib errors on $file"
      e2e_expect_equal "$path" "${errs%%: *}" "path of the stdlib error on $file"
    fi
  done
  e2e_expect_equal "yes" "$([ "$n_valid" -ge 2 ] && [ "$n_invalid" -ge 3 ] && echo yes || echo no)" \
    "$shape has at least 2 valid and 3 invalid fixtures ($n_valid, $n_invalid)"
  cd "$REPO_ROOT" || return 1
}

_flow_test_begin "factory schema: every fixture name has a shape and a polarity, and every invalid one an expected error path (S7)"
e2e_new fs-fixture-names
e2e_describe "the fixture folder holds only <shape>-valid-*.json and <shape>-invalid-*.json, and expected-errors.txt names exactly the invalid ones"
FS_BAD=""; FS_INVALID=""
for f in $(cd "$FS_FIX" && LC_ALL=C ls); do
  case "$f" in
    expected-errors.txt) ;;
    job-valid-*.json|directive-valid-*.json|lease-valid-*.json|result-valid-*.json|pending_event-valid-*.json|pending_report-valid-*.json) ;;
    job-invalid-*.json|directive-invalid-*.json|lease-invalid-*.json|result-invalid-*.json|pending_event-invalid-*.json|pending_report-invalid-*.json)
      FS_INVALID="$FS_INVALID$f"$'\n' ;;
    *) FS_BAD="$FS_BAD $f" ;;
  esac
done
printf 'files with no shape or polarity:%s\n' "${FS_BAD:- none}" >> "$E2E_ARTIFACT"
e2e_expect_equal "" "$FS_BAD" "files with no shape or polarity"
e2e_expect_equal "$(printf '%s' "$FS_INVALID")" "$(grep -v '^#' "$FS_FIX/expected-errors.txt" | awk '{ print $1 }' | LC_ALL=C sort)" \
  "the invalid fixtures and the files expected-errors.txt names"

# Without jsonschema the stdlib verdicts are still checked against the
# fixture names and the expected error paths; only the reference column and
# the keyword scenario need it.
for FS_SHAPE in job directive lease result pending_event pending_report; do
  _flow_test_begin "factory schema: $FS_SHAPE fixtures, stdlib validator against jsonschema (S1, S2, S4, S5, S7)"
  _fs_agree "$FS_SHAPE"
done

if [ "$FS_HAVE_JSONSCHEMA" = 1 ]; then
  _flow_test_begin "factory schema: every supported keyword agrees with jsonschema on edge values (S1, S2, S5, S6, S9)"
  e2e_new fs-keywords
  e2e_describe "a scratch schema that uses each supported keyword once, and instances on each keyword's edge; the stdlib verdict equals jsonschema's on every one"
  cat > "$E2E_DIR/keywords.schema.json" <<'JSON'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "i": { "type": "integer", "minimum": 0, "maximum": 2 },
    "n": { "type": "number" },
    "b": { "type": "boolean" },
    "e": { "enum": [1, "a", null, true] },
    "c": { "const": 0 },
    "s": { "type": ["string", "null"], "minLength": 2, "pattern": "x" },
    "nb": { "type": ["number", "null"], "minimum": 0.01 },
    "arr": { "type": "array", "items": { "$ref": "#/$defs/pos" } },
    "one": { "oneOf": [{ "type": "integer" }, { "type": "number", "minimum": 10 }] },
    "any": { "anyOf": [{ "type": "string" }, { "type": "integer", "minimum": 5 }] },
    "ref": { "$ref": "#/$defs/pos", "maximum": 9 },
    "map": { "type": "object", "additionalProperties": { "type": "boolean" } },
    "o": { "type": "object", "required": ["k"], "additionalProperties": false, "properties": { "k": { "type": "string" } } },
    "format": { "type": "string" }
  },
  "$defs": { "pos": { "type": "integer", "minimum": 1 } }
}
JSON
  cat > "$E2E_DIR/instances.jsonl" <<'JSONL'
{"i": 1}
{"i": 1.0}
{"i": true}
{"i": 3}
{"i": -1}
{"i": "1"}
{"n": true}
{"n": 1}
{"n": 0.5}
{"b": 1}
{"b": false}
{"e": 1}
{"e": true}
{"e": 1.0}
{"e": null}
{"e": "b"}
{"e": false}
{"c": 0}
{"c": 0.0}
{"c": false}
{"s": null}
{"s": "xy"}
{"s": "ax"}
{"s": "x"}
{"s": "ab"}
{"s": 3}
{"nb": null}
{"nb": 0}
{"nb": 0.01}
{"arr": [1, 2]}
{"arr": [1, 0]}
{"arr": [1, true]}
{"arr": "x"}
{"one": 3}
{"one": 12.5}
{"one": 12}
{"one": "q"}
{"any": "q"}
{"any": 6}
{"any": 2}
{"ref": 5}
{"ref": 10}
{"ref": 0}
{"map": {"a": true}}
{"map": {"a": 1}}
{"map": {}}
{"o": {"k": "v"}}
{"o": {}}
{"o": {"k": "v", "z": 1}}
{"format": "x"}
{"zz": 1}
[]
"str"
null
JSONL
  cd "$E2E_DIR" || exit 1
  FS_STD=$(_fs_stdlib pairs "$E2E_DIR/keywords.schema.json" "$E2E_DIR/instances.jsonl" 2>&1); FS_STD_RC=$?
  FS_REF=$(_fs_reference pairs "$E2E_DIR/keywords.schema.json" "$E2E_DIR/instances.jsonl" 2>&1); FS_REF_RC=$?
  cd "$REPO_ROOT" || exit 1
  e2e_expect_equal 0 "$FS_STD_RC" "stdlib validator exit status"
  e2e_expect_equal 0 "$FS_REF_RC" "jsonschema run exit status"
  FS_N=0
  while IFS= read -r FS_LINE; do
    FS_N=$((FS_N + 1))
    FS_S=$(printf '%s\n' "$FS_STD" | awk -F'\t' -v n="$FS_N" '$1 == n { print $2 }')
    FS_R=$(printf '%s\n' "$FS_REF" | awk -F'\t' -v n="$FS_N" '$1 == n { print $2 }')
    printf '%s: stdlib=%s jsonschema=%s\n' "$FS_LINE" "${FS_S:-none}" "${FS_R:-none}" >> "$E2E_ARTIFACT"
    e2e_expect_equal "$FS_R" "$FS_S" "stdlib verdict on $FS_LINE (jsonschema's)"
  done < "$E2E_DIR/instances.jsonl"
  [ "$FS_STD_RC" = 0 ] || printf 'stdlib output:\n%s\n' "$FS_STD" >> "$E2E_ARTIFACT"
  # The reference's verdicts on the edges S6 names, so a jsonschema that
  # changed its rules shows here and not as a silent agreement.
  for FS_EDGE in '{"i": 1.0}=valid' '{"i": true}=invalid' '{"e": true}=valid' '{"e": 1.0}=valid' '{"c": false}=invalid' \
                 '{"nb": null}=valid' '{"s": "ax"}=valid' '{"ref": 10}=invalid' '{"one": 12}=invalid' '{"format": "x"}=valid'; do
    FS_N=$(grep -nxF -- "${FS_EDGE%=*}" "$E2E_DIR/instances.jsonl" | cut -d: -f1)
    e2e_expect_equal "${FS_EDGE##*=}" "$(printf '%s\n' "$FS_REF" | awk -F'\t' -v n="$FS_N" '$1 == n { print $2 }')" \
      "jsonschema verdict on ${FS_EDGE%=*}"
  done
else
  _flow_test_begin "factory schema: every supported keyword agrees with jsonschema on edge values (S1, S2, S5, S6, S9)"
  _flow_assert_pass "SKIP: python3 has no jsonschema; CI installs it from plugins/flow/requirements.txt"
fi

_flow_test_begin "factory schema: a keyword the validator does not implement is refused at load (S3)"
e2e_new fs-unsupported
e2e_describe "a scratch schema with uniqueItems inside a \$defs entry nothing references; load refuses it as SchemaUnsupported(uniqueItems)"
cat > "$E2E_DIR/unsupported.schema.json" <<'JSON'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": { "a": { "type": "string" } },
  "$defs": { "unused": { "type": "object", "properties": { "tags": { "type": "array", "uniqueItems": true } } } }
}
JSON
cd "$E2E_DIR" || exit 1
FS_OUT=$(_fs_stdlib load "$E2E_DIR/unsupported.schema.json" 2>&1)
cd "$REPO_ROOT" || exit 1
printf 'load: %s\n' "$FS_OUT" >> "$E2E_ARTIFACT"
e2e_expect_equal "SchemaUnsupported(uniqueItems)" "$FS_OUT" "load result"

_flow_test_begin "factory schema: both shipped schemas load under the validator's keyword subset (S3)"
e2e_new fs-shipped-load
e2e_describe "the job and directive schemas use only keywords the stdlib validator implements"
cd "$E2E_DIR" || exit 1
for FS_S in factory-job.schema.json factory-directive.schema.json; do
  FS_OUT=$(_fs_stdlib load "$FS_SCHEMAS/$FS_S" 2>&1)
  printf '%s: %s\n' "$FS_S" "$FS_OUT" >> "$E2E_ARTIFACT"
  e2e_expect_equal "ok" "$FS_OUT" "load of $FS_S"
done
cd "$REPO_ROOT" || exit 1

_flow_test_begin "factory schema: the state and stage lists match the state table and the directive id (S8)"
e2e_new fs-enums
e2e_describe "job.state lists the keys of states in the design's transitions.json, and the stage lists name the stages of the directive id pattern"
FS_TABLE_STATES=$(jq -r '.states | keys[]' "$REPO_ROOT/docs/flow-factory/transitions.json" | LC_ALL=C sort | tr '\n' ' ')
FS_JOB="$FS_SCHEMAS/factory-job.schema.json"
FS_DIR_SCHEMA="$FS_SCHEMAS/factory-directive.schema.json"
FS_SCHEMA_STATES=$(jq -r '."$defs".state.enum[]' "$FS_JOB" | LC_ALL=C sort | tr '\n' ' ')
FS_NULL_STATES=$(jq -r '."$defs".state_or_null.enum[] | select(. != null)' "$FS_JOB" | LC_ALL=C sort | tr '\n' ' ')
FS_ID_STAGES=$(jq -r '."$defs".directive_id.pattern' "$FS_DIR_SCHEMA" | sed 's/.*-(\(.*\))-.*/\1/' | tr '|' '\n' | LC_ALL=C sort | tr '\n' ' ')
FS_STAGES=$(jq -r '."$defs".stage.enum[]' "$FS_JOB" | LC_ALL=C sort | tr '\n' ' ')
FS_DSTAGES=$(jq -r '.properties.stage.enum[]' "$FS_DIR_SCHEMA" | LC_ALL=C sort | tr '\n' ' ')
{
  printf 'table states: %s\n' "$FS_TABLE_STATES"
  printf 'directive id stages: %s\n' "$FS_ID_STAGES"
} >> "$E2E_ARTIFACT"
e2e_expect_equal "$FS_TABLE_STATES" "$FS_SCHEMA_STATES" "job state enum"
e2e_expect_equal "$FS_TABLE_STATES" "$FS_NULL_STATES" "resume_state enum"
e2e_expect_equal "null" "$(jq -c '[."$defs".state_or_null.enum[] | select(. == null)] | .[0]' "$FS_JOB")" "resume_state allows null"
e2e_expect_equal "$FS_ID_STAGES" "$FS_STAGES" "job stage enum"
e2e_expect_equal "$FS_ID_STAGES" "$FS_DSTAGES" "directive stage enum"
e2e_expect_equal "$(jq -r '.properties.directive.pattern' "$FS_JOB")" "$(jq -r '."$defs".directive_id.pattern' "$FS_DIR_SCHEMA")" \
  "the job's directive pattern is the directive schema's"
