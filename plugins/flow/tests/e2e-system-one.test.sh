# shellcheck shell=bash
# End-to-end: the System One client (bin/flow-s1.sh) asks a configured
# provider typed questions and prints normalized answers, or says "no answer"
# so its caller keeps today's behavior.
#
# Each scenario runs the shipped script in a scratch repository with its own
# HOME, against stub servers (tests/lib/s1_stub.py) that log every request they
# receive. The providers are real contracts: the TypeSafe stub requires a
# bearer key and names the model that answered; the imajev stub takes no key and
# adds `abstained` and `unknown_probability`. Scenarios that need questions run
# against a copy of the plugin whose system-one/questions.yaml is the fixture
# below; the shipped file has no sites. One artifact per scenario is written to
# $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   S1  provider none still sends a request (a baseUrl being present is taken
#       as permission)
#   S2  the repository's settings choose provider, baseUrl or apiKeyEnv
#   S3  a refusal by cascade-resolve is treated as "no value" and a preset
#       fills in
#   S4  a remote http:// URL, a malformed env var name or an unknown provider
#       still sends
#   S5  TypeSafe with its key unset sends a request anyway
#   S6  the key reaches stdout, stderr or a record
#   S7  noul confidence is taken as p, so a confident "no" falls below the
#       threshold
#   S8  the threshold is looked up by the configured alias, not the model that
#       answered
#   S9  one abstained or low answer and the rest are returned (not
#       all-or-nothing)
#   S10 a missing answer or a wrong-typed answer is passed through
#   S11 truncation counts bytes instead of characters, or splits a multibyte
#       character
#   S12 the timeout applies per socket read, so a slow-drip server holds the
#       caller
#   S13 an HTTP error (429, 5xx, 529) or a malformed body gives exit 0 or a
#       traceback
#   S14 a redirect is followed and the bearer key forwarded (on 302 Python's
#       default opener does this)
#   S15 shadow mode returns the answer
#   S16 a dotted site id is read as a nested settings key, so its mode is
#       always off
#   S17 the repository cannot enable a site
#   S18 records are written through a planted symlink, or into a new
#       directory for a --run-id with no run
#   S19 the state text is written into a record
#   S20 exit 3 prints partial JSON on stdout
#   S21 a "no answer" scenario passes because the stub was never reached, or a
#       stub is left running. Rule: every scenario that expects a request
#       asserts that the stub logged exactly one.
#   S22 a yaml.py in the working directory is imported on a Python that
#       ignores PYTHONSAFEPATH (older than 3.11, such as macOS /usr/bin/python3)
#   S23 an HTTP_PROXY in the environment receives the request, key and state
#       meant for a server on this machine
#   S24 a value that starts with "-" (--current -keep) is read as an option,
#       and the client exits 2 instead of answering
#   S25 shortening a large JSON state takes time proportional to its size
#       squared, holding the caller far past timeoutMs
#   S26 a choice or score reply without a confidence field is treated as fully
#       confident
#   S27 records after a failed request are not written, so shadow data loses
#       every failure
#   S28 a string from the server containing a line separator splits the one
#       JSON line on stdout into two
#   S29 an empty element in the user's PYTHONPATH puts the working directory
#       on sys.path as an absolute path, which a filter of "" and "." misses
#   S30 shortening gives up, or empties every string, on a state whose
#       strings are mostly escaped characters (newlines, quotes)
#   S31 a lone surrogate from the server or in the state ends the call as
#       internal-error, with no record, instead of malformed or state-invalid
#   S32 an answer about something other than the question asked is accepted:
#       a choice outside its options, a score outside its levels, or a
#       probability named for a level that does not exist; or the top level
#       itself is refused (off by one)
#   S33 option names YAML reads as booleans or numbers (yes, no, 1, 2) are
#       sent as "true" or "1", so no answer can ever match them
#   S34 an answer that contradicts itself is accepted. TypeSafe's API defines
#       a choice as the most probable option, its probabilities as covering
#       every option and summing to 1, and a score as each level times its
#       probability, added up. A partial map with no confidence was scored
#       over the options it named (one option at 0.4 gave confidence 1.0); a
#       choice the provider put 0.05 on, probabilities summing to 3, a score
#       of -1 and a score far from its probabilities all answered. The
#       opposite error: values rounded as TypeSafe sends them (two decimals)
#       are refused by a check that allows no rounding
#   S35 timeoutMs is not read at all: every timeout scenario sets a small
#       value, which a client fixed at the 3000 ms default also passes
#   S36 question ids YAML reads as a number, a boolean or null (1, yes, 1.5,
#       ~) are sent as "1", "true", "1.5" or "null", but the reply's answers
#       are looked up by the value YAML read, which never matches: the state
#       is sent and every such question ends as missing-answer. 1 and yes are
#       even one key to Python (True == 1)
#   S37 a choice or score reply whose confidence field is present but not a
#       number from 0 to 1 (a string, 1.5, true) is given the computed
#       confidence instead of being malformed
#   S38 a record after an answered reply names the configured model (an
#       alias such as jev-latest) instead of the model the reply names
#   S39 an unknown_probability that is present but not a number from 0 to 1
#       (a string, 1.5, true) is dropped from the answer instead of making it
#       malformed, the way an invalid confidence does
#   S40 a threshold models key YAML reads as a number (1.13) never equals the
#       model id the reply names, so the default threshold applies with no
#       warning; it must be refused like a question id that is not a string
#   S41 an abstained field that is present but not true or false ("true",
#       1, "yes") is read as "did not abstain", so the answer is used; 0 is
#       read the same way by a check written as `in (None, False)`, because
#       0 == False in Python
#   S42 a question value TypeSafe's API does not take is sent anyway: YAML
#       reads unquoted yes, no and numbers as booleans and numbers, so
#       instructions, a choice option's description or a score level stop
#       being the text that was written; noul criteria keys true and false
#       unquoted are booleans; and a date, .inf or a key that is not a string
#       inside a structured value cannot be sent as JSON at all (a date ends
#       as internal-error, not questions-invalid)
#   S43 a check for S42 that accepts only text rejects the structured
#       instructions and criteria the API documents: an object or a list for
#       instructions, criteria and score levels, null for a choice option
#   S44 a score outside its levels but within the rounding allowance of its
#       weighted sum (-0.01 or 2.01 with all probability on one end) passes
#       when the range check is dropped: every other out-of-range stub is far
#       from its weighted sum, so that check refuses it first
#   S45 a reply whose model id is null is refused instead of counting as
#       having none; or one whose model id is a number, true, false, 0 or an
#       object is treated as having none instead of being malformed (false and
#       0 catch `reply.get("model") or <configured>`)
#   S46 a number in a reply that is an integer too large for a float (401
#       digits) makes the range check raise OverflowError, so the call ends as
#       internal-error with no record, where 1e400 is malformed with one
#   S47 a questions file that cannot be read (a byte that is not UTF-8, an
#       invalid date, lists nested too deep to parse) or whose questions cannot
#       be encoded as JSON (a lone surrogate in a key or an id, an integer too
#       long for Python to print, nesting deeper than the interpreter's JSON
#       encoder takes, a threshold of 401 digits) ends as internal-error
#       instead of questions-invalid. How deep the encoder goes depends on the
#       interpreter: Python 3.9's stops before 1500 levels, 3.14's does not
#   S48 a questions file PyYAML raises some other error on (!!float "",
#       !!int "-", !!bool maybe, !!timestamp garbage, a sexagesimal float of
#       200 groups) ends as internal-error: each fix that named one more
#       exception type left the next one out
#   S49 the questions are checked by encoding them alone, but the request
#       encodes the body around them, one level deeper, so a question exactly
#       at the encoder's depth limit passes the check and fails when sent
#   S50 a YAML ordered map or pairs (!!omap, !!pairs) is a tuple in Python,
#       which JSON sends as an array, so its keys, 1 among them, are neither
#       checked nor sent as written
#   S51 a key or a question id holding a newline or an escape sequence
#       reaches stderr in the reason's detail and writes a second line that
#       looks like another reason
#   S52 a baseUrl urllib cannot parse ("http://[::1") ends as internal-error
#       instead of invalid-settings
#   S53 a catch around everything that handles an input also catches a crash
#       in the client's own checks and reports it as that input's fault, so a
#       deleted check passes every scenario; and a message that shows an
#       untrusted value with repr raises on Python 3.11 and later when the
#       value is an integer of more than 4300 digits
#   S54 a baseUrl whose port is not a number or out of range ("http://127.0.0.1:abc",
#       ":99999"), or a key a header cannot carry (a newline, a character
#       outside Latin-1), fails only when the request is made, as connection,
#       instead of invalid-settings before it
#   S55 records are best effort, but an error other than the ones named (a
#       state directory 1000 levels deep makes os.makedirs recurse too far)
#       reaches main: an answered call, or a connection failure, becomes
#       internal-error
#   S56 the state file is read whole whatever the cap, so a very large (or
#       sparse) file exhausts memory
#   S57 YAML aliases repeat what they name, so a few hundred bytes of
#       questions expand to a body of gigabytes when encoded
#   S58 run directly (not through flow-s1.sh), a model id that cannot be
#       encoded, or a python3 without PyYAML, ends as internal-error
#   S59 a walk that keeps each value's path as text holds, for a cycle that
#       branches (&a [*a, *a]), strings that grow with the depth, so it runs
#       for minutes and gigabytes before the size bound stops it; and a
#       message that shows a whole structure (a YAML pairs over an alias
#       expansion) builds its full repr first
#   S60 a size estimate that counts characters is several times low for text
#       the encoder escapes (a NUL becomes \u0000), so questions of several
#       MB are sent
#   S61 a baseUrl whose path holds a space, a control character or a
#       character outside ASCII passes the settings and fails at the request,
#       as connection; and a model id holding a tab reaches the request and is
#       then blamed on the reply
#   S62 run directly, a state file that is missing, a directory or a device
#       ends as internal-error or is read without bound; and a JSON state of
#       64 MiB takes gigabytes to parse
#   S63 the state's size bound and its parser choose between text and JSON
#       by two different tests, so a state format that is neither (a direct
#       run without --state-format) gets the text bound and the JSON parser
#   S64 opening a FIFO waits for a writer, before any check that it is not a
#       regular file, so a FIFO as the state file or the questions file hangs
#   S65 a host outside ASCII is not sent in its IDNA form: the Host header
#       carries it raw, and one outside Latin-1 fails as connection; a
#       baseUrl with a query, a fragment or a user and password is sent to
#       the wrong path, and a warning prints the password
#   S66 a size count that is not a lower bound (a float counted as 24 bytes
#       where 0.5 is 3; a one-element list counted 3 where [0] is 2) refuses
#       questions under 1 MiB
#   S67 a warning prints the password when it holds /, ? or #, which end
#       the user part a pattern looks for, or when urllib's own message for
#       an unparsable port quotes it; and an empty query or fragment (a bare
#       ? or #) passes a check of the parsed query and fragment
#   S68 a warning that prints the baseUrl, or urllib's message about it,
#       prints a key in its query or fragment, or a password written with a
#       full-width @ that urllib's normalization check quotes
#   S69 Python 3.9's urllib reads a port with int(), so +65422 and 65_422
#       pass and are sent as written in the Host header
#   S70 Python 3.9's urllib takes the host inside the first [...] even with
#       text around it (a[::1].127.0.0.1.nip.io), so the client judges the
#       host this machine while http.client connects to the whole name, over
#       plain http with the key
#   S71 Python 3.9 parses a long integer in a reply or a JSON state in time
#       that grows with the square of its digits, outside the request's
#       timeout (a million digits: about 30 s), where 3.11 and later refuse
#       more than 4300 digits
#   S72 [::ffff:127.0.0.1] is this machine to Python 3.13 and later's
#       ipaddress and not to 3.9's, so one interpreter sends plain http to it
#       and the other refuses
#   S73 flow-s1.sh's usage message prints an argument value as given, so a
#       newline in it writes a second line that looks like a reason
#   S74 PyYAML's work doubles with each line of a chain of merge keys (<<),
#       and Python 3.9 reads a long integer in time that grows with the
#       square of its digits, so a short questions file holds the client
#       before any timeout starts
#   S75 the one setting a repository may supply, a site's mode, is passed
#       on python3's command line whatever its length, and a value over the
#       system's argument limit fails with an exit status the client never
#       documents
#   S76 brackets shaped like an IPv6 literal but holding an IPv4 address or a
#       name ([127.0.0.1], [localhost], [api.example]) pass on Python 3.9,
#       which reads the name inside; and [[:cntrl:]] misses U+2028 and U+0085
#   S77 a limit on an integer's text that leaves room for a 0x prefix lets
#       a decimal integer of 4301 or 4302 digits through on Python 3.9; and
#       an IPv6 address checked without its zone id passes a zone Python
#       3.9 cannot use ([::1%])
#   S78 urllib connects to the host percent-decoded, while the checks read
#       it as written: a zone id holding %5d closes the bracket early
#       ([::1%5d.example] is judged this machine and connects to a name), %3a
#       moves a port into the host past the digits check, and [::1%3a1] is
#       judged this machine though it decodes to another address
#   S79 timeoutMs and stateTokenCap are read with int(), which Python 3.9
#       takes at any length and 3.14 refuses past 4300 digits; 20000.0 is
#       called "not a number"; and a setting longer than the system's
#       argument limit fails on python3's command line
#   S80 on Python 3.9 a socket's timeout is socket.timeout, which is not
#       TimeoutError there (it is from 3.10), so when the request's own
#       timeout ends it before the wait for it does, a late reply or a
#       request the server never reads is reported as connection
#   S81 Python 3.9's urllib does not check a bracketed host as written, which
#       3.14's does, so a zone id holding a second percent-encoded character
#       ([::1%25%0a], which decodes to a line break) passes on 3.9 alone

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

S1_BIN="bin/flow-s1.sh"
S1_RECORDS=".claude/flow-state/system-one.jsonl"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Sites used by the scenarios. Every threshold is a hand-picked number the
# scenario's expected result is computed from.
S1_FIXTURE='sites:
  e2e.contract:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
      q2: {type: choice, instructions: "Which team should handle it?", criteria: {x: null, y: null}}
      q3: {type: score, instructions: "How frustrated is the customer?", criteria: [calm, annoyed, angry]}
    thresholds:
      q1: {default: 0.5}
      q2: {default: 0.5}
      q3: {default: 0.5}
  e2e.one:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds:
      q1: {default: 0.8}
  e2e.alias:
    questions:
      q1: {type: choice, instructions: "Pick one.", criteria: {a: null, b: null, c: null}}
    thresholds:
      q1: {default: 0.95, models: {jev-1.13.0: 0.5}}
  e2e.pair:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
      q2: {type: noul, instructions: "The ticket is about billing."}
    thresholds:
      q1: {default: 0.5}
      q2: {default: 0.5}
  e2e.nothreshold:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds: {}
  e2e.abc:
    questions:
      q1: {type: choice, instructions: "Pick one.", criteria: {a: null, b: null, c: null}}
    thresholds:
      q1: {default: 0.5}
  e2e.abc-low:
    questions:
      q1: {type: choice, instructions: "Pick one.", criteria: {a: null, b: null, c: null}}
    thresholds:
      q1: {default: 0.2}
  e2e.edge:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds:
      q1: {default: 0.2}
  review.dedup-a:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds:
      q1: {default: 0.5}'

# Replies in each provider's shape. The three answers are the same judgments;
# only the provider-specific fields differ.
TS_CONTRACT='{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.6,"legend":{"0":"calm","1":"annoyed","2":"angry"},"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}},"usage":{"input_tokens":40,"output_tokens":3}}'
IMJ_CONTRACT='{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.8,"unknown_probability":0.02,"abstained":false},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8,"unknown_probability":0.02,"abstained":false},"q3":{"type":"score","score":1.6,"legend":{"0":"calm","1":"annoyed","2":"angry"},"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55,"unknown_probability":0.02,"abstained":false}},"usage":{"total_ms":120.5,"input_tokens":40}}'
# The normalized answers both contract replies must give, built by hand from
# the reply fields: a noul's confidence is |2p - 1| = 0.6; a choice's and a
# score's are the provider's own; provider-only fields (abstained, legend) are
# not part of a normalized answer.
EXPECTED_CONTRACT='{"q1":{"type":"noul","p":0.8,"confidence":0.6},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.6,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}'
ONE_CONFIDENT='{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}'
PAIR_CONFIDENT='{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95},"q2":{"type":"noul","noul":0.1}}}'

# _s1_setup <scenario> <purpose> [fixture] — scratch repo, and with a third
# argument "fixture", a plugin copy carrying the fixture questions.
_s1_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/s1
  [ "${3:-}" = fixture ] && e2e_plugin_copy system-one/questions.yaml "$S1_FIXTURE"
  printf 'Customer: I was charged twice and need the duplicate refunded today.\n' > "$E2E_REPO/state.txt"
}

# _s1_settings <json> — user settings; the JSON is built with jq so the stub
# URLs are quoted correctly.
_s1_settings() { e2e_user_settings "$1"; }

# _s1_ask <site> [extra args] — run the client on the scratch state.
_s1_ask() {
  local site="$1"; shift
  e2e_run_bin "${S1_ENV[@]+"${S1_ENV[@]}"}" "$S1_BIN" ask --site "$site" --state-file state.txt "$@"
}

_jq() { jq -r "$1" <<<"$E2E_OUT"; }

_expect_no_answer() {
  e2e_expect_equal 3 "$E2E_RC" "exit status"
  e2e_expect_equal "" "$E2E_OUT" "stdout"
  e2e_expect_err "flow-s1: no answer: $1"
}

_expect_requests() {
  e2e_expect_equal "$2" "$(e2e_stub_requests "$1")" "requests received by stub $1"
}

_expect_no_traceback() {
  case "$E2E_ERR" in
    *Traceback*) _e2e_result fail "stderr has no Python traceback" ;;
    *) _e2e_result pass "stderr has no Python traceback" ;;
  esac
}

_now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# ----------------------------------------------------------------- usage

if _want usage-errors; then
  _flow_test_begin "usage-errors"
  _s1_setup usage-errors "arguments the client must refuse with exit 2: no site, a site id that is not a lowercase dotted name (it is put into a settings expression), a missing state file, an unknown subcommand, a run id that climbs out of .flow/runs"
  S1_ENV=()
  e2e_run_bin "$S1_BIN" ask --state-file state.txt
  e2e_expect_equal 2 "$E2E_RC" "exit status without --site"
  for bad in 'Review.X' 'a..b' '../x' 'a"]|.x'; do
    e2e_run_bin "$S1_BIN" ask --site "$bad" --state-file state.txt
    e2e_expect_equal 2 "$E2E_RC" "exit status for site id '$bad'"
  done
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file missing.txt
  e2e_expect_equal 2 "$E2E_RC" "exit status for a missing state file"
  e2e_run_bin "$S1_BIN" tell --site e2e.one --state-file state.txt
  e2e_expect_equal 2 "$E2E_RC" "exit status for an unknown subcommand"
  # A value holding a newline is shown on one line (S73).
  for args in "--site|e2e.one"$'\n'"flow-s1: no answer: shadow" "--state-file|x"$'\n'"flow-s1: no answer: shadow" "--bogus"$'\n'"flow-s1: no answer: shadow|x" \
      "--site|e2e"$'\xe2\x80\xa8'"flow-s1: no answer: shadow" "--site|e2e"$'\xc2\x85'"flow-s1: no answer: shadow"; do
    e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.txt "${args%%|*}" "${args#*|}"
    e2e_expect_equal "2 0" "$E2E_RC $(python3 -c 'import sys; print(sum(1 for l in sys.stdin.read().splitlines() if l.startswith("flow-s1: no answer:")))' <<<"$E2E_ERR")" "exit status and lines, as Python splits them, that start as a no-answer line, for ${args%%|*}"
  done
  for bad in ../x . -r1; do
    e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.txt --run-id "$bad"
    e2e_expect_equal 2 "$E2E_RC" "exit status for run id '$bad'"
  done
  e2e_expect_equal "" "$E2E_OUT" "stdout"
fi

# ----------------------------------------------------------------- provider none

if _want provider-none; then
  _flow_test_begin "provider-none"
  _s1_setup provider-none "provider none with a server address present and the site switched on: no request, no record" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"none",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  _expect_requests a 0
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record file" || _e2e_result pass "no record file"
fi

if _want provider-unset; then
  _flow_test_begin "provider-unset"
  _s1_setup provider-unset "no user settings at all: the plugin default is provider none, so no request and no record" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  _expect_requests a 0
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record file" || _e2e_result pass "no record file"
fi

if _want python-missing; then
  _flow_test_begin "python-missing"
  _s1_setup python-missing "python3 without PyYAML (a stub python3 that fails): no answer, no request" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  printf '#!/bin/sh\nexit 1\n' > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer python-missing
  _expect_requests a 0
fi

# ----------------------------------------------------------------- settings

if _want repo-settings-ignored; then
  _flow_test_begin "repo-settings-ignored"
  _s1_setup repo-settings-ignored "user settings name stub A and USER_KEY; both repository settings files name stub B and REPO_KEY. The request must go to A with the user's key" fixture
  e2e_stub_start a "{\"bearer\":\"u-secret\",\"body\":$ONE_CONFIDENT}"
  e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"USER_KEY",uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"REPO_KEY"}}' > "$E2E_REPO/.claude/settings.flow.json"
  cp "$E2E_REPO/.claude/settings.flow.json" "$E2E_REPO/.claude/settings.flow.local.json"
  S1_ENV=(USER_KEY=u-secret REPO_KEY=r-secret)
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  _expect_requests b 0
  e2e_expect_equal "Bearer u-secret" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization received by stub a"
  e2e_expect_err "cascade-resolve: WARN: ignoring"
  e2e_expect_no_out "u-secret"
  case "$E2E_ERR" in *u-secret*|*r-secret*) _e2e_result fail "stderr does not contain a key" ;; *) _e2e_result pass "stderr does not contain a key" ;; esac
fi

if _want repo-provider-ignored; then
  _flow_test_begin "repo-provider-ignored"
  _s1_setup repo-provider-ignored "only the repository's settings name a provider and a server: the user never chose one, so no request" fixture
  e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  _expect_requests b 0
fi

if _want cascade-refused; then
  _flow_test_begin "cascade-refused"
  _s1_setup cascade-refused "the plugin itself lives inside the repository, so cascade-resolve refuses to read provider settings: that is no answer, never a preset" fixture
  cp -R "$E2E_ACTIVE_PLUGIN" "$E2E_REPO/plugin-copy"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugin-copy"
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer settings-refused
  e2e_expect_err "cascade-resolve: ERROR"
  _expect_requests a 0
fi

if _want insecure-url; then
  _flow_test_begin "insecure-url"
  _s1_setup insecure-url "a remote server over plain http: the key and the state would cross the network unencrypted" fixture
  _s1_settings '{"systemOne":{"provider":"custom","baseUrl":"http://example.invalid:8080","uses":{"e2e.one":"on"}}}'
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer insecure-url
  e2e_expect_err "WARN"
fi

if _want bad-key-env-name; then
  _flow_test_begin "bad-key-env-name"
  _s1_setup bad-key-env-name "an apiKeyEnv that is not an environment variable name" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"lower-case;x",uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer invalid-settings
  e2e_expect_err "WARN"
  _expect_requests a 0
fi

if _want unknown-provider; then
  _flow_test_begin "unknown-provider"
  _s1_setup unknown-provider "a provider name Flow does not know" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"openai",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer invalid-settings
  e2e_expect_err "WARN"
  _expect_requests a 0
fi

if _want typesafe-no-key; then
  _flow_test_begin "typesafe-no-key"
  _s1_setup typesafe-no-key "TypeSafe requires a key and TYPESAFE_API_KEY is unset" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"typesafe",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer no-api-key
  _expect_requests a 0
fi

if _want imajev-no-auth-header; then
  _flow_test_begin "imajev-no-auth-header"
  _s1_setup imajev-no-auth-header "imajev with apiKeyEnv naming a variable that is set but empty: no Authorization header is sent" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,apiKeyEnv:"IMJ_KEY",uses:{"e2e.one":"on"}}}')"
  S1_ENV=(IMJ_KEY=)
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "null" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization received"
fi

# ----------------------------------------------------------------- contract

if _want typesafe-contract; then
  _flow_test_begin "typesafe-contract"
  _s1_setup typesafe-contract "a noul, a choice and a score against the TypeSafe contract; expected values are the reply's fields, and for the noul |2p-1|" fixture
  e2e_stub_start a "{\"bearer\":\"ts-secret\",\"body\":$TS_CONTRACT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"typesafe",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
  S1_ENV=(TYPESAFE_API_KEY=ts-secret)
  _s1_ask e2e.contract
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "/v1/systemone" "$(jq -r '.path' "$(e2e_stub_log a)")" "request path"
  e2e_expect_equal "Bearer ts-secret" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization"
  e2e_expect_equal "jev-1.13.0" "$(jq -r '.body.model' "$(e2e_stub_log a)")" "model sent (the pinned default)"
  e2e_expect_equal "false" "$(jq -r '.body | has("images")' "$(e2e_stub_log a)")" "request has an images field"
  e2e_expect_equal "q1,q2,q3" "$(jq -r '.body.questions | keys | join(",")' "$(e2e_stub_log a)")" "questions sent"
  e2e_expect_equal "application/json" "$(jq -r '.headers["content-type"]' "$(e2e_stub_log a)")" "request Content-Type"
  e2e_expect_equal "$(jq -S -c . <<<"$EXPECTED_CONTRACT")" "$(_jq '.answers' | jq -S -c .)" "normalized answers, every field"
  e2e_expect_equal "0.8 0.6" "$(_jq '"\(.answers.q1.p) \(.answers.q1.confidence)"')" "q1 p and confidence"
  e2e_expect_equal "y 0.8 0.9" "$(_jq '"\(.answers.q2.choice) \(.answers.q2.confidence) \(.answers.q2.probabilities.y)"')" "q2 choice, confidence, p(y)"
  e2e_expect_equal "1.6 0.55 0.7" "$(_jq '"\(.answers.q3.score) \(.answers.q3.confidence) \(.answers.q3.probabilities["2"])"')" "q3 score, confidence, p(level 2)"
  e2e_expect_equal "e2e.contract typesafe jev-1.13.0 false" "$(_jq '"\(.site) \(.provider) \(.model) \(.truncated)"')" "site, provider, model, truncated"
  e2e_expect_no_out "ts-secret"
fi

if _want imajev-contract; then
  _flow_test_begin "imajev-contract"
  _s1_setup imajev-contract "the same judgments against the imajev contract (no key, abstained and unknown_probability on each answer): with the provider-only field removed, the answers must equal the same hand-built object the TypeSafe scenario expects" fixture
  e2e_stub_start a "{\"body\":$IMJ_CONTRACT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.contract
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "null" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization"
  e2e_expect_equal "0.02 0.02 0.02" "$(_jq '"\(.answers.q1.unknown_probability) \(.answers.q2.unknown_probability) \(.answers.q3.unknown_probability)"')" "unknown_probability copied"
  e2e_expect_equal "imajev imajev-4b" "$(_jq '"\(.provider) \(.model)"')" "provider and model"
  e2e_expect_equal "0.8 0.6" "$(_jq '"\(.answers.q1.p) \(.answers.q1.confidence)"')" "q1 p and confidence"
  e2e_expect_equal "y 0.8 0.9" "$(_jq '"\(.answers.q2.choice) \(.answers.q2.confidence) \(.answers.q2.probabilities.y)"')" "q2 choice, confidence, p(y)"
  e2e_expect_equal "1.6 0.55 0.7" "$(_jq '"\(.answers.q3.score) \(.answers.q3.confidence) \(.answers.q3.probabilities["2"])"')" "q3 score, confidence, p(level 2)"
  e2e_expect_equal "$(jq -S -c . <<<"$EXPECTED_CONTRACT")" "$(_jq '.answers | map_values(del(.unknown_probability))' | jq -S -c .)" "normalized answers without unknown_probability, every field (the same object typesafe-contract expects)"
fi

if _want noul-confidence; then
  _flow_test_begin "noul-confidence"
  _s1_setup noul-confidence "a confident no: p=0.05 has confidence |2*0.05-1| = 0.9, above the 0.8 threshold" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.05}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "0.05 0.9" "$(_jq '"\(.answers.q1.p) \(.answers.q1.confidence)"')" "q1 p and confidence"
fi

if _want threshold-by-answering-model; then
  _flow_test_begin "threshold-by-answering-model"
  _s1_setup threshold-by-answering-model "configured model jev-latest, the reply names jev-1.13.0; its threshold (0.5) applies, not the default (0.95), so confidence 0.7 answers" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.7,"b":0.2,"c":0.1},"confidence":0.7}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-latest",uses:{"e2e.alias":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.alias
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "a 0.7 jev-1.13.0" "$(_jq '"\(.answers.q1.choice) \(.answers.q1.confidence) \(.model)"')" "choice, confidence, model"
  e2e_expect_equal "jev-latest" "$(jq -r '.body.model' "$(e2e_stub_log a)")" "model sent"
fi

if _want abstained; then
  _flow_test_begin "abstained"
  _s1_setup abstained "q1 is confident, q2 abstained: the whole call is no answer" fixture
  e2e_stub_start a '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"abstained":false},"q2":{"type":"noul","noul":0.5,"unknown_probability":0.9,"abstained":true}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer abstained
  _expect_requests a 1
fi

if _want below-threshold; then
  _flow_test_begin "below-threshold"
  _s1_setup below-threshold "p=0.6 has confidence 0.2, below the 0.8 threshold" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.6}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer below-threshold
  _expect_requests a 1
fi

if _want partial-below-threshold; then
  _flow_test_begin "partial-below-threshold"
  _s1_setup partial-below-threshold "two questions, each at threshold 0.5: q1 answers with p=0.95 (confidence 0.9) and q2 with p=0.6 (confidence |2*0.6-1| = 0.2, below its threshold). The whole call is no answer; q1 is never returned alone (S9)" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95},"q2":{"type":"noul","noul":0.6}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer below-threshold
  _expect_requests a 1
fi

if _want missing-answer; then
  _flow_test_begin "missing-answer"
  _s1_setup missing-answer "the reply answers q1 and leaves out q2" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer missing-answer
  _expect_requests a 1
fi

if _want wrong-type; then
  _flow_test_begin "wrong-type"
  _s1_setup wrong-type "the reply gives p as the string \"0.95\"" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":"0.95"}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer malformed
  _expect_requests a 1
  _expect_no_traceback
fi

if _want state-truncation; then
  _flow_test_begin "state-truncation"
  _s1_setup state-truncation "stateTokenCap 10 allows 40 characters; the state is 100 two-byte characters, so 40 of them (80 bytes) are sent" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:10,uses:{"e2e.one":"on"}}}')"
  python3 -c 'import sys; sys.stdout.write("é" * 100)' > "$E2E_REPO/state.txt"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "40 80 true" "$(jq -r '.body.state | "\(length) \(utf8bytelength) \(test("^é+$"))"' "$(e2e_stub_log a)")" "characters, bytes, all é"
  e2e_expect_equal "true" "$(_jq '.truncated')" "truncated"
fi

if _want json-state-truncation; then
  _flow_test_begin "json-state-truncation"
  _s1_setup json-state-truncation "a JSON state over the cap: it is sent as JSON, and strings longer than one common length are cut to it, so the short title keeps its full text and the serialized state fits in 4 x cap characters" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:30,uses:{"e2e.one":"on"}}}')"
  python3 -c 'import json; print(json.dumps({"title": "Charged twice", "body": "x" * 500}))' > "$E2E_REPO/state.json"
  S1_ENV=()
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.json --state-format json
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "object Charged twice" "$(jq -r '.body.state | "\(type) \(.title)"' "$(e2e_stub_log a)")" "state type and untouched field"
  e2e_expect_equal "true" "$(jq -r '(.body.state | tojson | length) <= 120' "$(e2e_stub_log a)")" "serialized state fits in 120 characters"
  e2e_expect_equal "true" "$(jq -r '(.body.state.body | length) > 50' "$(e2e_stub_log a)")" "the long field is shortened, not dropped"
fi

if _want unknown-site; then
  _flow_test_begin "unknown-site"
  _s1_setup unknown-site "the shipped questions file has no sites, so any site is unknown: no request"
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"any.site":"on"}}}')"
  S1_ENV=()
  _s1_ask any.site
  _expect_no_answer unknown-site
  _expect_requests a 0
fi

if _want no-threshold; then
  _flow_test_begin "no-threshold"
  _s1_setup no-threshold "a question with no threshold entry is a questions-file error, never an implicit 0" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.nothreshold":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.nothreshold
  _expect_no_answer no-threshold
  _expect_requests a 0
fi

# ----------------------------------------------------------------- transport

if _want timeout; then
  _flow_test_begin "timeout"
  _s1_setup timeout "timeoutMs 200 against a server that waits 8 s before replying" fixture
  e2e_stub_start a "{\"delay_ms\":8000,\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:200,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  t0=$(_now_ms); _s1_ask e2e.one; t1=$(_now_ms)
  _expect_no_answer timeout
  _expect_requests a 1
  e2e_expect_equal true "$([ $((t1 - t0)) -lt 5000 ] && echo true || echo false)" "returned within 5 s (the server would take 6 s or more)"
fi

if _want timeout-honored; then
  _flow_test_begin "timeout-honored"
  _s1_setup timeout-honored "timeoutMs 10000 against a server that waits 4 s: the reply arrives inside the limit and answers; a client that ignored the setting and used the 3000 ms default would report timeout" fixture
  e2e_stub_start a "{\"delay_ms\":4000,\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:10000,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "0.95" "$(_jq '.answers.q1.p')" "p"
fi

if _want timeout-drip; then
  _flow_test_begin "timeout-drip"
  _s1_setup timeout-drip "timeoutMs 500 against a server that sends one byte every 100 ms for 6 s: each read is fast, the whole request is not" fixture
  e2e_stub_start a '{"drip_ms":100,"drip_count":60}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:500,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  t0=$(_now_ms); _s1_ask e2e.one; t1=$(_now_ms)
  _expect_no_answer timeout
  _expect_requests a 1
  e2e_expect_equal true "$([ $((t1 - t0)) -lt 5000 ] && echo true || echo false)" "returned within 5 s (the server would take 6 s or more)"
fi

if _want timeout-clamp; then
  _flow_test_begin "timeout-clamp"
  _s1_setup timeout-clamp "timeoutMs 1 is raised to the 200 ms floor, so a reply after 60 ms still answers" fixture
  e2e_stub_start a "{\"delay_ms\":60,\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:1,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

for code in 500 429 529; do
  if _want "http-$code"; then
    _flow_test_begin "http-$code"
    _s1_setup "http-$code" "the server replies HTTP $code" fixture
    e2e_stub_start a "{\"status\":$code,\"body\":{\"detail\":\"error\"}}"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    S1_ENV=()
    _s1_ask e2e.one
    _expect_no_answer "http-$code"
    _expect_requests a 1
    _expect_no_traceback
    f="$E2E_HOME/$S1_RECORDS"
    e2e_expect_equal "http-$code null" "$( [ -f "$f" ] && jq -r '"\(.result) \(.answer)"' "$f")" "the one record's result and answer"
  fi
done

if _want malformed-json; then
  _flow_test_begin "malformed-json"
  _s1_setup malformed-json "HTTP 200 with a body that is not JSON" fixture
  e2e_stub_start a '{"body":"not json{"}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer malformed
  _expect_requests a 1
  _expect_no_traceback
fi

for code in 307 302; do
  if _want "redirect-$code"; then
    _flow_test_begin "redirect-$code"
    _s1_setup "redirect-$code" "TypeSafe with its key; stub A replies $code to stub B. No redirect is followed, so B never sees the request or the key" fixture
    e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
    e2e_stub_start a "$(jq -nc --arg l "$(e2e_stub_url b)/v1/systemone" --argjson s "$code" '{status:$s,location:$l}')"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"typesafe",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    S1_ENV=(TYPESAFE_API_KEY=ts-secret)
    _s1_ask e2e.one
    _expect_no_answer redirect
    _expect_requests a 1
    _expect_requests b 0
  fi
done

if _want connection-refused; then
  _flow_test_begin "connection-refused"
  _s1_setup connection-refused "a loopback port with nothing listening (a stub that was stopped)" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  url=$(e2e_stub_url a)
  _e2e_stop_stubs; sleep 0.2
  _s1_settings "$(jq -nc --arg u "$url" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer connection
  _expect_no_traceback
fi

# ----------------------------------------------------------------- modes and records

if _want shadow-mode; then
  _flow_test_begin "shadow-mode"
  _s1_setup shadow-mode "shadow mode with two confident answers: the request is made and both are recorded, and the caller gets no answer. The configured model is jev-latest and the reply names jev-1.13.0: each record names jev-1.13.0, the model that answered (S38)" fixture
  e2e_stub_start a "{\"body\":$PAIR_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-latest",uses:{"e2e.pair":"shadow"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair --current keep
  _expect_no_answer shadow
  _expect_requests a 1
  e2e_expect_equal "jev-latest" "$(jq -r '.body.model' "$(e2e_stub_log a)")" "model sent (the configured one)"
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal 2 "$( [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0)" "records written"
  e2e_expect_equal "q1 q2" "$( [ -f "$f" ] && jq -r '.question' "$f" | tr '\n' ' ' | sed 's/ $//')" "questions recorded"
  e2e_expect_equal "jev-1.13.0 jev-1.13.0" "$( [ -f "$f" ] && jq -r '.model' "$f" | tr '\n' ' ' | sed 's/ $//')" "models recorded (the one the reply names, not the configured jev-latest)"
  e2e_expect_equal "keep keep" "$( [ -f "$f" ] && jq -r '.current' "$f" | tr '\n' ' ' | sed 's/ $//')" "current decision recorded"
  e2e_expect_equal "answered answered" "$( [ -f "$f" ] && jq -r '.result' "$f" | tr '\n' ' ' | sed 's/ $//')" "results recorded"
  e2e_expect_equal "shadow" "$( [ -f "$f" ] && jq -r '.mode' "$f" | head -1)" "mode recorded"
fi

if _want on-mode-records; then
  _flow_test_begin "on-mode-records"
  _s1_setup on-mode-records "on mode: the caller gets the answers and each question is recorded" fixture
  e2e_stub_start a "{\"body\":$PAIR_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c .)" "stdout lines"
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal 2 "$( [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0)" "records written"
fi

if _want partial-records; then
  _flow_test_begin "partial-records"
  _s1_setup partial-records "shadow mode, q1 answered and q2 abstained: both are recorded, with q1's answer kept" fixture
  e2e_stub_start a '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"abstained":false},"q2":{"type":"noul","noul":0.5,"abstained":true}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.pair":"shadow"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer abstained
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal "answered abstained" "$( [ -f "$f" ] && jq -r '.result' "$f" | tr '\n' ' ' | sed 's/ $//')" "results recorded"
  e2e_expect_equal "0.95" "$( [ -f "$f" ] && jq -r 'select(.question == "q1") | .answer.p' "$f")" "q1's answer recorded"
fi

if _want mode-off; then
  _flow_test_begin "mode-off"
  _s1_setup mode-off "a provider is configured and the site is not switched on: no request, no record" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer mode-off
  _expect_requests a 0
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record file" || _e2e_result pass "no record file"
fi

if _want mode-from-repo-settings; then
  _flow_test_begin "mode-from-repo-settings"
  _s1_setup mode-from-repo-settings "the user chose the provider; the repository switches on the dotted site review.dedup-a" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"review.dedup-a":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  S1_ENV=()
  _s1_ask review.dedup-a
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
fi

if _want unknown-mode; then
  _flow_test_begin "unknown-mode"
  _s1_setup unknown-mode "a mode value that is not off, shadow or on counts as off" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"yes"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer mode-off
  e2e_expect_err "WARN"
  _expect_requests a 0
fi

if _want records-in-run-dir; then
  _flow_test_begin "records-in-run-dir"
  _s1_setup records-in-run-dir "--run-id names an existing run: records go to that run's directory" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_file_has ".flow/runs/r1/system-one.jsonl" '"question": "q1"'
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record in the user state directory" || _e2e_result pass "no record in the user state directory"
fi

if _want run-id-missing-dir; then
  _flow_test_begin "run-id-missing-dir"
  _s1_setup run-id-missing-dir "--run-id names a run that does not exist: records go to the user state directory, and no run directory is created" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one --run-id r2
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  [ -e "$E2E_REPO/.flow/runs/r2" ] && _e2e_result fail "no run directory created" || _e2e_result pass "no run directory created"
  e2e_expect_equal 1 "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && wc -l < "$E2E_HOME/$S1_RECORDS" | tr -d ' ' || echo 0)" "records in the user state directory"
fi

if _want records-symlink-file; then
  _flow_test_begin "records-symlink-file"
  _s1_setup records-symlink-file "the run's record file is a planted symlink to another file: nothing is written through it, and the answer still returns" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  printf 'victim\n' > "$E2E_DIR/victim.txt"
  before=$(_e2e_sha256 "$E2E_DIR/victim.txt")
  ln -s "$E2E_DIR/victim.txt" "$E2E_REPO/.flow/runs/r1/system-one.jsonl"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "$before" "$(_e2e_sha256 "$E2E_DIR/victim.txt")" "victim file sha256"
  e2e_expect_err "WARN"
fi

if _want records-symlink-dir; then
  _flow_test_begin "records-symlink-dir"
  _s1_setup records-symlink-dir "the run directory itself is a symlink to a directory elsewhere: nothing is written there" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_DIR/elsewhere" "$E2E_REPO/.flow/runs"
  ln -s "$E2E_DIR/elsewhere" "$E2E_REPO/.flow/runs/r1"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/elsewhere")" "files written in the symlink's target"
  e2e_expect_err "WARN"
fi

if _want state-not-recorded; then
  _flow_test_begin "state-not-recorded"
  _s1_setup state-not-recorded "the record holds the state's sha256, never the state" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  printf 'S1-MARKER-7f3 customer text\n' > "$E2E_REPO/state.txt"
  S1_ENV=()
  _s1_ask e2e.one
  f="$E2E_HOME/$S1_RECORDS"
  if [ -f "$f" ] && grep -q 'S1-MARKER-7f3' "$f"; then _e2e_result fail "record lacks the state text"; else _e2e_result pass "record lacks the state text"; fi
  e2e_expect_equal "$(_e2e_sha256 "$E2E_REPO/state.txt")" "$( [ -f "$f" ] && jq -r '.state_sha256' "$f")" "state_sha256"
fi

# ----------------------------------------------------------------- review round 1

if _want planted-yaml; then
  _flow_test_begin "planted-yaml"
  _s1_setup planted-yaml "a yaml.py in the repository, and a python3 that ignores PYTHONSAFEPATH (as Python before 3.11 does): the planted module must never run, whatever the provider" fixture
  printf 'open(%s, "w").write("ran")\n' "'$E2E_DIR/marker'" > "$E2E_REPO/yaml.py"
  real=$(command -v python3)
  printf '#!/bin/sh\nunset PYTHONSAFEPATH\nexec %s "$@"\n' "$real" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  [ -e "$E2E_DIR/marker" ] && _e2e_result fail "the planted yaml.py did not run (provider none)" || _e2e_result pass "the planted yaml.py did not run (provider none)"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status with a provider"
  [ -e "$E2E_DIR/marker" ] && _e2e_result fail "the planted yaml.py did not run (provider set)" || _e2e_result pass "the planted yaml.py did not run (provider set)"
fi

if _want loopback-ignores-proxy; then
  _flow_test_begin "loopback-ignores-proxy"
  _s1_setup loopback-ignores-proxy "imajev on this machine with a key, and HTTP_PROXY pointing at stub P: the request goes straight to the server, and P never sees the key or the state" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  e2e_stub_start p "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,apiKeyEnv:"IMJ_KEY",uses:{"e2e.one":"on"}}}')"
  S1_ENV=(IMJ_KEY=i-secret "HTTP_PROXY=$(e2e_stub_url p)" "http_proxy=$(e2e_stub_url p)" "ALL_PROXY=$(e2e_stub_url p)")
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  _expect_requests p 0
fi

if _want dash-values; then
  _flow_test_begin "dash-values"
  _s1_setup dash-values "--current -keep: a value that starts with a dash is still a value" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one --current -keep
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "-keep" "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && jq -r '.current' "$E2E_HOME/$S1_RECORDS")" "current recorded"
fi

if _want large-json-state; then
  _flow_test_begin "large-json-state"
  _s1_setup large-json-state "a 500 KB JSON state of 5000 strings at the default cap (7000 tokens, 28000 characters): it is shortened in well under the time a caller waits, and still sent" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  python3 -c 'import json; print(json.dumps(["y" * 100 for _ in range(5000)]))' > "$E2E_REPO/state.json"
  S1_ENV=()
  t0=$(_now_ms); e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.json --state-format json; t1=$(_now_ms)
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal true "$([ $((t1 - t0)) -lt 5000 ] && echo true || echo false)" "returned within 5 s"
  e2e_expect_equal "true 5000" "$(jq -r '"\((.body.state | tojson | length) <= 28000) \(.body.state | length)"' "$(e2e_stub_log a)")" "fits in 28000 characters, all 5000 strings kept"
fi

if _want confidence-fallback; then
  _flow_test_begin "confidence-fallback"
  _s1_setup confidence-fallback "a choice reply without a confidence field, probabilities 0.5/0.3/0.2: TypeSafe's formula gives (3*0.5-1)/2 = 0.25, below a 0.5 threshold and above a 0.2 one" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.5,"b":0.3,"c":0.2}}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.abc":"on","e2e.abc-low":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.abc
  _expect_no_answer below-threshold
  _s1_ask e2e.abc-low
  e2e_expect_equal 0 "$E2E_RC" "exit status at threshold 0.2"
  e2e_expect_equal "0.25" "$(_jq '.answers.q1.confidence')" "computed confidence"
fi

if _want confidence-invalid; then
  _flow_test_begin "confidence-invalid"
  _s1_setup confidence-invalid "a reply whose confidence field is present but not a number from 0 to 1 is malformed, never given the computed confidence (S37): choice replies with confidence \"high\", 1.5 and true, and a score reply with \"high\". Their probabilities compute confidences above the 0.5 threshold (choice 0.9/0.05/0.05: (3*0.9-1)/2 = 0.85; score 0.1/0.2/0.7: (3*0.7-1)/2 = 0.55), so a client that replaced the field would answer. A null confidence counts as absent, as a null model id does, and gets the computed 0.85" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.05,"c":0.05},"confidence":"high"}}}}'
  e2e_stub_start b '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.05,"c":0.05},"confidence":1.5}}}}'
  e2e_stub_start c '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.05,"c":0.05},"confidence":true}}}}'
  e2e_stub_start d '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.05,"c":0.05},"confidence":null}}}}'
  e2e_stub_start e '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.6,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":"high"}}}}'
  S1_ENV=()
  for st in a b c d e; do
    site=e2e.abc; [ "$st" = e ] && site=e2e.contract
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" --arg s "$site" '{systemOne:{provider:"custom",baseUrl:$u,uses:{($s):"on"}}}')"
    _s1_ask "$site"
    case $st in
      d) e2e_expect_equal "0 0.85" "$E2E_RC $(_jq '.answers.q1.confidence')" "exit status and computed confidence for a null confidence" ;;
      *) _expect_no_answer malformed ;;
    esac
    _expect_requests $st 1
  done
fi

if _want records-symlink-flow; then
  _flow_test_begin "records-symlink-flow"
  _s1_setup records-symlink-flow ".flow itself is a symlink to a directory outside the repository that holds runs/r1: nothing is written there" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_DIR/outside/runs/r1"
  ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/outside/runs/r1")" "files written under the symlink's target"
  e2e_expect_err "WARN"
fi

if _want unsafe-reply-strings; then
  _flow_test_begin "unsafe-reply-strings"
  _s1_setup unsafe-reply-strings "the reply's model id contains U+2028, a line separator: the reply is malformed, and nothing it sent reaches stdout or a record" fixture
  e2e_stub_start a '{"body":{"model":"jev x","answers":{"q1":{"type":"noul","noul":0.95}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer malformed
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal "malformed " "$( [ -f "$f" ] && jq -r '"\(.result) \(.model)"' "$f")" "the one record's result and model (the configured one, empty for custom)"
  if [ -f "$f" ] && grep -q "$(printf '\342\200\250')" "$f"; then
    _e2e_result fail "no record contains the separator"
  else
    _e2e_result pass "no record contains the separator"
  fi
fi

if _want unsafe-option-name; then
  _flow_test_begin "unsafe-option-name"
  _s1_setup unsafe-option-name "a choice reply whose option name contains U+2028: malformed" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a\u2028","probabilities":{"a\u2028":0.9,"b":0.05,"c":0.05},"confidence":0.85}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.abc":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.abc
  _expect_no_answer malformed
  _expect_requests a 1
fi

if _want lone-surrogate; then
  _flow_test_begin "lone-surrogate"
  _s1_setup lone-surrogate "a lone surrogate (JSON \\ud800) as the reply's model id is malformed, with a record; in a JSON state it is state-invalid" fixture
  e2e_stub_start a '{"body":"{\"model\":\"jev\\ud800\",\"answers\":{\"q1\":{\"type\":\"noul\",\"noul\":0.95}}}"}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer malformed
  e2e_expect_equal "malformed" "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && jq -r '.result' "$E2E_HOME/$S1_RECORDS")" "the one record's result"
  printf '{"text": "a\\ud800b"}\n' > "$E2E_REPO/state.json"
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.json --state-format json
  _expect_no_answer state-invalid
fi

if _want pythonpath-empty-element; then
  _flow_test_begin "pythonpath-empty-element"
  _s1_setup pythonpath-empty-element "PYTHONPATH=:/nonexistent (an empty element, as export PYTHONPATH=\"\$PYTHONPATH:/x\" leaves when it was unset) puts the repository on sys.path as an absolute path: neither a planted yaml.py nor a planted json.py may run" fixture
  printf 'open(%s, "w").write("yaml")\n' "'$E2E_DIR/marker-yaml'" > "$E2E_REPO/yaml.py"
  printf 'open(%s, "w").write("json")\n' "'$E2E_DIR/marker-json'" > "$E2E_REPO/json.py"
  printf 'open(%s, "w").write("site")\n' "'$E2E_DIR/marker-site'" > "$E2E_REPO/sitecustomize.py"
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  # Keep what run.sh put on PYTHONPATH (it carries a user-site PyYAML);
  # the empty first element is the point.
  S1_ENV=("PYTHONPATH=:/nonexistent${PYTHONPATH:+:$PYTHONPATH}")
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  [ -e "$E2E_DIR/marker-yaml" ] && _e2e_result fail "the planted yaml.py did not run" || _e2e_result pass "the planted yaml.py did not run"
  [ -e "$E2E_DIR/marker-json" ] && _e2e_result fail "the planted json.py did not run" || _e2e_result pass "the planted json.py did not run"
  [ -e "$E2E_DIR/marker-site" ] && _e2e_result fail "the planted sitecustomize.py did not run (imported at interpreter startup)" || _e2e_result pass "the planted sitecustomize.py did not run (imported at interpreter startup)"
fi

if _want escaped-state; then
  _flow_test_begin "escaped-state"
  _s1_setup escaped-state "a JSON state of 200 strings, each 300 newlines (each serializes as two characters), at cap 1000 (4000 characters): it answers, and the cut is the largest that fits, checked against an independent linear search" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:1000,uses:{"e2e.one":"on"}}}')"
  python3 -c 'import json; print(json.dumps(["\n" * 300] * 200))' > "$E2E_REPO/state.json"
  S1_ENV=()
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.json --state-format json
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  best=$(python3 -c '
import json
full = json.load(open("'"$E2E_REPO"'/state.json"))
size = lambda v: len(json.dumps(v, ensure_ascii=False))
best = max(c for c in range(0, 301) if size([s[:c] for s in full]) <= 4000)
print(best)')
  e2e_expect_equal "$best" "$(jq -r '.body.state | map(length) | max' "$(e2e_stub_log a)")" "longest string sent (largest cut that fits, by linear search)"
fi

# ----------------------------------------------------------------- review round 3

if _want deep-json; then
  _flow_test_begin "deep-json"
  _s1_setup deep-json "JSON nested 100000 levels deep, in the state and in the reply (Python before 3.12 cannot parse it; 3.12 and later can, and the state is then too deep to shorten): a named reason, never internal-error, and the reply case still writes its record" fixture
  python3 -c 'print("[" * 100000 + "]" * 100000)' > "$E2E_REPO/state.json"
  e2e_stub_start a '{"body":"{\"model\":\"jev-1.13.0\",\"answers\":{\"q1\":'"$(python3 -c 'print("[" * 100000 + "]" * 100000)')"'}}"}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.json --state-format json
  _expect_no_answer state-invalid
  _s1_ask e2e.one
  _expect_no_answer malformed
  e2e_expect_equal "malformed" "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && jq -r '.result' "$E2E_HOME/$S1_RECORDS")" "the reply case's record"
  # Python 3.12 and later parse this reply (its answer is then just the wrong
  # type); older versions raise RecursionError, which only this run reaches.
  # It needs an older python3 that can import PyYAML from its own user site.
  old_py=/usr/bin/python3
  old_site=$("$old_py" -c 'import site, sys; print(site.getusersitepackages() if sys.version_info < (3, 12) else "")' 2>/dev/null)
  if [ -n "$old_site" ] && PYTHONPATH="$old_site" "$old_py" -c 'import yaml' 2>/dev/null; then
    printf '#!/bin/sh\nexport PYTHONPATH="%s"\nexec %s "$@"\n' "$old_site" "$old_py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    : > "$E2E_HOME/$S1_RECORDS"
    _s1_ask e2e.one
    _expect_no_answer malformed
    e2e_expect_equal "malformed" "$(jq -r '.result' "$E2E_HOME/$S1_RECORDS")" "the reply case's record under $("$old_py" -V 2>&1)"
  else
    printf 'skipped: the reply case under a Python older than 3.12 (none with PyYAML at %s)\n' "$old_py" | _e2e_art
    printf 'SKIP deep-json — the reply case under a Python older than 3.12: none with PyYAML at %s, so the RecursionError catch in the reply parser is untested here\n' "$old_py"
  fi
fi

if _want current-not-utf8; then
  _flow_test_begin "current-not-utf8"
  _s1_setup current-not-utf8 "--current holds a byte that is not UTF-8: the call still answers, and its record is written with the byte replaced" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one --current "$(printf 'keep\377')"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal 1 "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && wc -l < "$E2E_HOME/$S1_RECORDS" | tr -d ' ' || echo 0)" "records written"
  e2e_expect_equal "keep?" "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && jq -r '.current' "$E2E_HOME/$S1_RECORDS")" "current recorded, the byte replaced by '?'"
fi

if _want cwd-deleted; then
  _flow_test_begin "cwd-deleted"
  _s1_setup cwd-deleted "the client is started from a working directory that has been deleted: no answer, internal-error, before any python3 runs" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  printf '#!/bin/sh\nmkdir gone && cd gone && rmdir ../gone && exec "$(dirname "$0")/flow-s1.sh" "$@"\n' > "$E2E_ACTIVE_PLUGIN/bin/from-deleted-dir.sh"
  chmod +x "$E2E_ACTIVE_PLUGIN/bin/from-deleted-dir.sh"
  S1_ENV=()
  e2e_run_bin bin/from-deleted-dir.sh ask --site e2e.one --state-file "$E2E_REPO/state.txt"
  _expect_no_answer internal-error
  _expect_requests a 0
fi

if _want reply-without-model; then
  _flow_test_begin "reply-without-model"
  _s1_setup reply-without-model "configured model jev-1.13.0 and a reply with no model id: it is taken as answered by jev-1.13.0, so that model's threshold (0.5) applies to confidence 0.85, not the default (0.95)" fixture
  e2e_stub_start a '{"body":{"answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.05,"c":0.05},"confidence":0.85}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-1.13.0",uses:{"e2e.alias":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.alias
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "jev-1.13.0" "$(_jq '.model')" "model"
fi

if _want reply-model-invalid; then
  _flow_test_begin "reply-model-invalid"
  _s1_setup reply-model-invalid "configured model jev-1.13.0: a reply whose model id is null counts as having none, so jev-1.13.0's threshold (0.5) applies to confidence 0.85, not the default (0.95), and the answer is used; a model id that is a number (1.13), true, false, 0 or an object is malformed, and its record names the configured model" fixture
  n=0
  for m in null 1.13 true false 0 '{"id":"jev-1.13.0"}'; do
    n=$((n+1))
    e2e_stub_start "m$n" "{\"body\":{\"model\":$m,\"answers\":{\"q1\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":0.9,\"b\":0.05,\"c\":0.05},\"confidence\":0.85}}}}"
  done
  S1_ENV=()
  f="$E2E_HOME/$S1_RECORDS"
  for st in m1 m2 m3 m4 m5 m6; do
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-1.13.0",uses:{"e2e.alias":"on"}}}')"
    _s1_ask e2e.alias
    case $st in
      m1) e2e_expect_equal "0 jev-1.13.0" "$E2E_RC $(_jq '.model')" "exit status and model for a null model id"
          e2e_expect_equal "jev-1.13.0 answered" "$( [ -f "$f" ] && tail -1 "$f" | jq -r '"\(.model) \(.result)"')" "the record's model and result" ;;
      *) _expect_no_answer malformed
         e2e_expect_equal "jev-1.13.0 malformed" "$( [ -f "$f" ] && tail -1 "$f" | jq -r '"\(.model) \(.result)"')" "the record's model and result" ;;
    esac
    _expect_requests $st 1
  done
fi

# ----------------------------------------------------------------- holdout round

if _want threshold-boundary; then
  _flow_test_begin "threshold-boundary"
  _s1_setup threshold-boundary "a confidence exactly at its threshold answers (the docs say the answer must reach it): p=0.6 gives |2*0.6-1| = 0.2 by hand, which floating point computes as 0.19999999999999996, against a 0.2 threshold" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.6}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.edge":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.edge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "0.2" "$(_jq '.answers.q1.confidence')" "confidence"
fi

if _want answer-outside-question; then
  _flow_test_begin "answer-outside-question"
  _s1_setup answer-outside-question "a choice outside the question's options (z, for options x and y) and a score outside its levels (42, for three levels) are malformed, even when the reply's own probabilities name them" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"z","probabilities":{"z":0.9,"y":0.1},"confidence":0.8},"q3":{"type":"score","score":1.6,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  e2e_stub_start b '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":42,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  S1_ENV=()
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
  _s1_ask e2e.contract
  _expect_no_answer malformed
  _expect_requests a 1
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
  _s1_ask e2e.contract
  _expect_no_answer malformed
  _expect_requests a 1
  _expect_requests b 1
fi

if _want score-levels; then
  _flow_test_begin "score-levels"
  _s1_setup score-levels "three levels are 0, 1 and 2: score 2 answers; score 3 and a probability named \"3\" are malformed. Scores just outside the levels and within the rounding allowance of their weighted sum (0.005 * (1 + 3) = 0.02 for three levels), -0.01 with all probability on level 0 and 2.01 with all on level 2, are malformed too, so only the range check can refuse them; score 0 with all on level 0 answers" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":2,"probabilities":{"0":0.0,"1":0.0,"2":1.0},"confidence":1.0}}}}'
  e2e_stub_start b '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":3,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  e2e_stub_start c '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.6,"probabilities":{"0":0.1,"1":0.2,"3":0.7},"confidence":0.55}}}}'
  e2e_stub_start d '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":-0.01,"probabilities":{"0":1.0,"1":0.0,"2":0.0},"confidence":1.0}}}}'
  e2e_stub_start e '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":2.01,"probabilities":{"0":0.0,"1":0.0,"2":1.0},"confidence":1.0}}}}'
  e2e_stub_start f '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":0,"probabilities":{"0":1.0,"1":0.0,"2":0.0},"confidence":1.0}}}}'
  S1_ENV=()
  for st in a b c d e f; do
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
    _s1_ask e2e.contract
    case $st in
      a) e2e_expect_equal 0 "$E2E_RC" "exit status for score 2 (the top level)"; e2e_expect_equal "2" "$(_jq '.answers.q3.score')" "score" ;;
      f) e2e_expect_equal 0 "$E2E_RC" "exit status for score 0 (the bottom level)"; e2e_expect_equal "0" "$(_jq '.answers.q3.score')" "score" ;;
      *) _expect_no_answer malformed ;;
    esac
    _expect_requests $st 1
  done
fi

if _want answer-consistency-choice; then
  _flow_test_begin "answer-consistency-choice"
  _s1_setup answer-consistency-choice "choice replies that contradict TypeSafe's definition of a choice (probabilities for every option, summing to 1; the choice the most probable) are malformed; the same shapes rounded to two decimals, as TypeSafe sends them, answer" fixture
  # Refused, one stub each (site e2e.abc: choice a/b/c at threshold 0.5).
  # Expected values from docs.typesafe.ai/primitives/choice.md ("the option
  # with the highest probability"; "the full probability distribution across
  # every option. The sum of all values is 1").
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.4}}}}}'
  e2e_stub_start b '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.1},"confidence":0.85}}}}'
  e2e_stub_start c '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"c","probabilities":{"a":0.9,"b":0.05,"c":0.05},"confidence":0.85}}}}'
  e2e_stub_start d '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":1,"b":1,"c":1},"confidence":1}}}}'
  # Answered: probabilities summing to 1.01 after rounding.
  e2e_stub_start h '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.67,"b":0.17,"c":0.17},"confidence":0.5}}}}'
  # Each limit from both sides. Rounding to two decimals keeps the order of
  # the values, so the chosen option must be the most probable one exactly
  # (a tie still answers); a sum of three values may be off by 3 * 0.005 =
  # 0.015, so 1.015 answers and 1.016 does not.
  e2e_stub_start j '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"b","probabilities":{"a":0.5,"b":0.49,"c":0.01},"confidence":0.9}}}}'
  e2e_stub_start k '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"b","probabilities":{"a":0.5,"b":0.5,"c":0.0},"confidence":0.5}}}}'
  e2e_stub_start l '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.675,"b":0.17,"c":0.17},"confidence":0.5}}}}'
  e2e_stub_start m '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.676,"b":0.17,"c":0.17},"confidence":0.5}}}}'
  # The sum limit from below: 0.985 answers, 0.984 does not.
  e2e_stub_start p '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.655,"b":0.165,"c":0.165},"confidence":0.5}}}}'
  e2e_stub_start q '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.654,"b":0.165,"c":0.165},"confidence":0.5}}}}'
  S1_ENV=()
  for st in a b c d h j k l m p q; do
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.abc":"on"}}}')"
    _s1_ask e2e.abc
    case $st in
      h) e2e_expect_equal 0 "$E2E_RC" "exit status for probabilities summing to 1.01 after rounding"
         e2e_expect_equal "a" "$(_jq '.answers.q1.choice')" "choice" ;;
      k) e2e_expect_equal 0 "$E2E_RC" "exit status for a choice tied with the most probable option"
         e2e_expect_equal "b" "$(_jq '.answers.q1.choice')" "choice" ;;
      l) e2e_expect_equal 0 "$E2E_RC" "exit status for three probabilities summing to 1.015, the limit"
         e2e_expect_equal "a" "$(_jq '.answers.q1.choice')" "choice" ;;
      p) e2e_expect_equal 0 "$E2E_RC" "exit status for three probabilities summing to 0.985, the lower limit"
         e2e_expect_equal "a" "$(_jq '.answers.q1.choice')" "choice" ;;
      *) _expect_no_answer malformed ;;
    esac
    _expect_requests $st 1
  done
fi

if _want answer-consistency-score; then
  _flow_test_begin "answer-consistency-score"
  _s1_setup answer-consistency-score "score replies that contradict TypeSafe's definition of a score (a probability for every level, summing to 1; the score each level times its probability, added up) are malformed; the same shapes rounded to two decimals, as TypeSafe sends them, answer" fixture
  # Refused, one stub each (site e2e.contract: noul, choice x/y, score over 3
  # levels, thresholds 0.5). Expected values from
  # docs.typesafe.ai/primitives/score.md ("each level number multiplied by its
  # probability, added up"; probabilities "keyed by level number as a string.
  # The sum of all values is 1"). Stub t breaks only the sum: its score equals
  # its weighted sum.
  e2e_stub_start e '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":-1,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  e2e_stub_start f '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":0.2,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  e2e_stub_start g '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":2,"probabilities":{"2":0.4}}}}}'
  e2e_stub_start t '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.5,"probabilities":{"0":0.5,"1":0.5,"2":0.5},"confidence":0.55}}}}'
  # Answered: TypeSafe's own live reply to a three-level score (score 1.77
  # against 0.22 + 2 * 0.78 = 1.78), recorded 2026-09-29 from jev-1.13.0.
  e2e_stub_start i '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.77,"probabilities":{"0":0.0,"1":0.22,"2":0.78},"confidence":0.66}}}}'
  # Each limit from both sides: a three-level score may be off its weighted sum
  # by 0.005 * (1 + 3) = 0.02 (each of three rounded probabilities, weighted by
  # its level, and the rounded score), so 0.02 above answers and 0.021 does not.
  e2e_stub_start n '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.62,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  e2e_stub_start o '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.621,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  # The score limit from below: 0.02 under its weighted sum answers, 0.021
  # does not.
  e2e_stub_start r '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.58,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  e2e_stub_start s '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.579,"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}}}}'
  S1_ENV=()
  for st in e f g t i n o r s; do
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
    _s1_ask e2e.contract
    case $st in
      i) e2e_expect_equal 0 "$E2E_RC" "exit status for TypeSafe's rounded score reply"
         e2e_expect_equal "1.77" "$(_jq '.answers.q3.score')" "score" ;;
      n) e2e_expect_equal 0 "$E2E_RC" "exit status for a score 0.02 from its weighted sum, the limit"
         e2e_expect_equal "1.62" "$(_jq '.answers.q3.score')" "score" ;;
      r) e2e_expect_equal 0 "$E2E_RC" "exit status for a score 0.02 under its weighted sum, the lower limit"
         e2e_expect_equal "1.58" "$(_jq '.answers.q3.score')" "score" ;;
      *) _expect_no_answer malformed ;;
    esac
    _expect_requests $st 1
  done
fi

if _want questions-shape; then
  _flow_test_begin "questions-shape"
  _s1_setup questions-shape "questions files the client must refuse before sending anything: a choice without options, a score with one level, a score with eleven, and options YAML reads as booleans or numbers; quoted, the same options work"
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"yes","probabilities":{"yes":0.9,"no":0.1},"confidence":0.8}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
  S1_ENV=()
  for bad in \
    'q1: {type: choice, instructions: "Pick."}' \
    'q1: {type: score, instructions: "Rate.", criteria: [only]}' \
    'q1: {type: score, instructions: "Rate.", criteria: [a, b, c, d, e, f, g, h, i, j, k]}' \
    'q1: {type: choice, instructions: "Pick.", criteria: {yes: null, no: null}}' \
    'q1: {type: choice, instructions: "Pick.", criteria: {1: null, 2: null}}'; do
    e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      %s\n    thresholds:\n      q1: {default: 0.5}\n' "$bad")"
    _s1_ask e2e.q
    _expect_no_answer questions-invalid
  done
  _expect_requests a 0
  e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      q1: {type: choice, instructions: "Pick.", criteria: {"yes": null, "no": null}}\n    thresholds:\n      q1: {default: 0.5}\n')"
  _s1_ask e2e.q
  e2e_expect_equal 0 "$E2E_RC" "exit status with quoted yes and no"
  _expect_requests a 1
fi

if _want question-ids; then
  _flow_test_begin "question-ids"
  _s1_setup question-ids "question ids YAML reads as a number, a boolean or null (1, yes, 1.5, ~) are refused before anything is sent (S36): each stub's reply answers the id as JSON spells it, so a client that sent the question would find no answer to it. Quoted, the id \"1\" works"
  # One stub per case, so each count is that case's own.
  reply='{"body":{"model":"jev-1.13.0","answers":{"1":{"type":"noul","noul":0.95},"true":{"type":"noul","noul":0.95},"1.5":{"type":"noul","noul":0.95},"null":{"type":"noul","noul":0.95}}}}'
  e2e_stub_start a "$reply"
  e2e_stub_start b "$reply"
  e2e_stub_start c "$reply"
  e2e_stub_start d "$reply"
  e2e_stub_start e "$reply"
  S1_ENV=()
  for pair in 'a 1' 'b yes' 'c 1.5' 'd ~'; do
    st=${pair%% *}; id=${pair#* }
    e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      %s: {type: noul, instructions: "The ticket is urgent."}\n    thresholds:\n      %s: {default: 0.5}\n' "$id" "$id")"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
    _s1_ask e2e.q
    _expect_no_answer questions-invalid
    _expect_requests "$st" 0
  done
  e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      "1": {type: noul, instructions: "The ticket is urgent."}\n    thresholds:\n      "1": {default: 0.5}\n')"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url e)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
  _s1_ask e2e.q
  e2e_expect_equal "0 0.95" "$E2E_RC $(_jq '.answers["1"].p')" "exit status and the answer to the quoted id \"1\""
  _expect_requests e 1
fi

if _want unknown-probability-invalid; then
  _flow_test_begin "unknown-probability-invalid"
  _s1_setup unknown-probability-invalid "imajev-shaped noul replies whose unknown_probability is a string, 1.5 or true are malformed (S39), as an invalid confidence is; null counts as absent, and the answer carries no unknown_probability" fixture
  # One stub per case, so each count is that case's own.
  e2e_stub_start a '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"unknown_probability":"high","abstained":false}}}}'
  e2e_stub_start b '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"unknown_probability":1.5,"abstained":false}}}}'
  e2e_stub_start c '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"unknown_probability":true,"abstained":false}}}}'
  e2e_stub_start d '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"unknown_probability":null,"abstained":false}}}}'
  S1_ENV=()
  for st in a b c; do
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    _expect_no_answer malformed
    _expect_requests $st 1
  done
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url d)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  _s1_ask e2e.one
  e2e_expect_equal "0 0.95 false" "$E2E_RC $(_jq '.answers.q1.p') $(_jq '.answers.q1 | has("unknown_probability")')" "exit status, p and whether unknown_probability is present, for a null one"
  _expect_requests d 1
fi

if _want threshold-model-key; then
  _flow_test_begin "threshold-model-key"
  _s1_setup threshold-model-key "a threshold models key YAML reads as a number (1.13) is refused before anything is sent (S40); quoted, \"1.13\" is the reply's model id and its threshold (0.5) applies instead of the default (0.95) to a confidence of 0.7"
  e2e_stub_start a '{"body":{"model":"1.13","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.8,"b":0.1,"c":0.1},"confidence":0.7}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
  S1_ENV=()
  e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      q1: {type: choice, instructions: "Pick one.", criteria: {a: null, b: null, c: null}}\n    thresholds:\n      q1: {default: 0.95, models: {1.13: 0.5}}\n')"
  _s1_ask e2e.q
  _expect_no_answer questions-invalid
  _expect_requests a 0
  e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      q1: {type: choice, instructions: "Pick one.", criteria: {a: null, b: null, c: null}}\n    thresholds:\n      q1: {default: 0.95, models: {"1.13": 0.5}}\n')"
  _s1_ask e2e.q
  e2e_expect_equal "0 a 1.13" "$E2E_RC $(_jq '.answers.q1.choice') $(_jq '.model')" "exit status, choice and model with the quoted key"
  _expect_requests a 1
fi

if _want abstained-invalid; then
  _flow_test_begin "abstained-invalid"
  _s1_setup abstained-invalid "a confident noul (p 0.95, confidence 0.9, above e2e.one's 0.8) whose abstained field is \"true\", 1, \"yes\", 0 or a list is malformed (S41); null counts as absent and the answer is used" fixture
  # One stub per case, so each count is that case's own.
  n=0
  for v in '"true"' 1 '"yes"' 0 '[true]'; do
    n=$((n+1))
    e2e_stub_start "m$n" "{\"body\":{\"model\":\"imajev-4b\",\"answers\":{\"q1\":{\"type\":\"noul\",\"noul\":0.95,\"abstained\":$v}}}}"
  done
  e2e_stub_start z '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"abstained":null}}}}'
  S1_ENV=()
  for st in m1 m2 m3 m4 m5; do
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url $st)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    _expect_no_answer malformed
    _expect_requests $st 1
  done
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url z)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  _s1_ask e2e.one
  e2e_expect_equal "0 0.95" "$E2E_RC $(_jq '.answers.q1.p')" "exit status and p for a null abstained"
  _expect_requests z 1
fi

if _want question-value-types; then
  _flow_test_begin "question-value-types"
  _s1_setup question-value-types "question values TypeSafe's API does not take (S42) are refused before anything is sent: instructions YAML reads as true or 42, a choice description read as true or 1, score levels read as false/true or as a date, noul criteria keyed by unquoted true/false, noul criteria without \"false\" or with a third key, and a date, .inf or a numeric key inside a structured value. Each stub's reply answers the question, so a client that sent it would answer"
  S1_ENV=()
  n=0
  # Each line: the question, then ||| and the answer its stub gives.
  while IFS= read -r line; do
    n=$((n+1)); st="v$n"; q=${line%% ||| *}; ans=${line#* ||| }
    e2e_stub_start "$st" "{\"body\":{\"model\":\"jev-1.13.0\",\"answers\":{\"q1\":$ans}}}"
    e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.q:\n    questions:\n      q1: %s\n    thresholds:\n      q1: {default: 0.5}\n' "$q")"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
    _s1_ask e2e.q
    _expect_no_answer questions-invalid
    _expect_requests "$st" 0
    _expect_no_traceback
  done <<'CASES'
{type: noul, instructions: yes} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: 42} ||| {"type":"noul","noul":0.95}
{type: choice, instructions: "Pick one.", criteria: {a: yes, b: null}} ||| {"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.1}}
{type: choice, instructions: "Pick one.", criteria: {a: 1, b: null}} ||| {"type":"choice","choice":"a","probabilities":{"a":0.9,"b":0.1}}
{type: score, instructions: "How angry is the customer?", criteria: [no, partly, yes]} ||| {"type":"score","score":1.85,"probabilities":{"0":0.05,"1":0.05,"2":0.9}}
{type: score, instructions: "When is it due?", criteria: [2026-01-01, later]} ||| {"type":"score","score":0.9,"probabilities":{"0":0.1,"1":0.9}}
{type: noul, instructions: "The ticket is urgent.", criteria: {true: "It asks for action today.", false: "It can wait."}} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: "The ticket is urgent.", criteria: {"true": "It asks for action today."}} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: "The ticket is urgent.", criteria: {"true": "It asks for action today.", "false": "It can wait.", "maybe": "Unclear."}} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: {question: "Is the ticket urgent?", since: 2026-01-01}} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: {question: "Is the ticket urgent?", limit: .inf}} ||| {"type":"noul","noul":0.95}
{type: score, instructions: "How angry is the customer?", criteria: [{1: calm}, angry]} ||| {"type":"score","score":0.9,"probabilities":{"0":0.1,"1":0.9}}
{type: noul, instructions: "The ticket is urgent.", criteria: {"true": yes, "false": "It can wait."}} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: !!pairs [{ctx: {1: calm, 2: angry}}]} ||| {"type":"noul","noul":0.95}
{type: noul, instructions: !!omap [{question: "Is the ticket urgent?"}, {since: "Monday"}]} ||| {"type":"noul","noul":0.95}
CASES
  e2e_expect_equal 15 "$n" "cases run"
fi

if _want questions-unsendable; then
  _flow_test_begin "questions-unsendable"
  _s1_setup questions-unsendable "a questions file that cannot be read, or whose questions cannot be sent as JSON, is refused as questions-invalid before anything is sent, never internal-error (S47, S48): a byte that is not UTF-8, 2026-02-30 as a score level, a lone surrogate in instructions, in an option name and in a question id, lists nested 1200 deep (too deep for PyYAML to parse), a threshold default of 401 digits, five values PyYAML raises on (!!float \"\", !!int \"-\", !!bool maybe, !!timestamp garbage, a sexagesimal float of 200 groups), a question id and a set member that are integers of 5000 hexadecimal digits (which repr cannot print on Python 3.11 and later, S53), and aliases that expand a few hundred bytes to about 70 MB, or one 200000-character string to 2 MB (S57). Then, with each python3 here that can run the client, a hexadecimal integer of 5000 digits and a chain of 1500 aliases: refused where that interpreter's JSON encoder cannot encode them (Python 3.11 and later print an integer of more than 4300 decimal digits only on request; older encoders stop before 1500 levels), which the scenario asks the interpreter first, and sent and answered where it can. Each file is written byte for byte; the artifact names it by case and sha256"
  S1_ENV=()
  mkdir -p "$E2E_DIR/unsendable"
  python3 - "$E2E_DIR/unsendable" <<'PY'
import os, sys
d = sys.argv[1]
def site(q, qid="q1", default="0.5", pre=""):
    return (pre + "sites:\n  e2e.q:\n    questions:\n      %s: %s\n    thresholds:\n      %s: {default: %s}\n"
            % (qid, q, qid, default))
urgent = '{type: noul, instructions: "The ticket is urgent."}'
cases = [
    ("a byte that is not UTF-8", site(urgent, pre="# caf\xe9\n").encode("latin-1")),
    ("2026-02-30 as a score level", site('{type: score, instructions: "When is it due?", criteria: [2026-02-30, later]}')),
    ("a lone surrogate in instructions", site('{type: noul, instructions: "Is the ticket urgent? \\ud800"}')),
    ("a lone surrogate in an option name", site('{type: choice, instructions: "Pick one.", criteria: {"a\\ud800": null, b: null}}')),
    ("a lone surrogate in a question id", site(urgent, qid='"q\\ud800"')),
    ("lists nested 1200 deep", site("{type: noul, instructions: %s}" % ("[" * 1200 + "]" * 1200))),
    ("a threshold default of 401 digits", site(urgent, default="1" + "0" * 400)),
    ('!!float ""', site(urgent, pre='x: !!float ""\n')),
    ('!!int "-"', site(urgent, pre='x: !!int "-"\n')),
    ("!!bool maybe", site(urgent, pre="x: !!bool maybe\n")),
    ("!!timestamp garbage", site(urgent, pre="x: !!timestamp garbage\n")),
    ("a sexagesimal float of 200 groups in instructions", site('{type: noul, instructions: {question: "Is the ticket urgent?", n: 1%s.5}}' % (":0" * 199))),
    # Explicit keys (?): YAML limits a plain key to 1024 characters, and a
    # longer one would fail the parse before any message is built.
    ("a question id of 5000 hexadecimal digits",
     "sites:\n  e2e.q:\n    questions:\n      ? 0x%s\n      : %s\n    thresholds:\n      ? 0x%s\n      : {default: 0.5}\n" % ("f" * 5000, urgent, "f" * 5000)),
    ("a set holding an integer of 5000 hexadecimal digits",
     "sites:\n  e2e.q:\n    questions:\n      q1:\n        type: noul\n        instructions:\n          question: Is the ticket urgent?\n          ids: !!set\n            ? 0x%s\n    thresholds:\n      q1: {default: 0.5}\n" % ("f" * 5000)),
    ("aliases ten wide and six deep (a body of about 70 MB)", "bomb:\n  l0: &l0 [aaaaaaaaaa]\n" + "".join("  l%d: &l%d [%s]\n" % (i, i, ", ".join(["*l%d" % (i - 1)] * 10)) for i in range(1, 7)) + site("{type: noul, instructions: *l6}")),
    ("a string of 200000 characters named by ten aliases", "big: &big %s\n" % ("x" * 200000) + site("{type: noul, instructions: [%s]}" % ", ".join(["*big"] * 10))),
    ("a hexadecimal integer of 5000 digits", site('{type: noul, instructions: {question: "Is the ticket urgent?", n: 0x%s}}' % ("f" * 5000))),
    ("1000 NULs named by 1040 aliases (1 MB counted, 6 MB sent)", 'nul: &nul "%s"\n' % ("\\0" * 1000) + site("{type: noul, instructions: [%s]}" % ", ".join(["*nul"] * 1040))),
    ("a chain of 1500 aliases", "chain:\n" + "".join("  x%d: &a%d [%s]\n" % (i, i, "*a%d" % (i - 1) if i else "end") for i in range(1500))
     + site("{type: noul, instructions: *a1499}")),
]
for i, (label, text) in enumerate(cases, 1):
    with open(os.path.join(d, "%d.yaml" % i), "wb") as f:
        f.write(text if isinstance(text, bytes) else text.encode("utf-8"))
    with open(os.path.join(d, "%d.label" % i), "w") as f:
        f.write(label)
PY
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
    st="u$i"
    e2e_stub_start "$st" '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
    [ -d "$E2E_DIR/plugin" ] || cp -R "$E2E_PLUGIN_DIR" "$E2E_DIR/plugin"
    E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
    cp "$E2E_DIR/unsendable/$i.yaml" "$E2E_ACTIVE_PLUGIN/system-one/questions.yaml"
    printf 'plugin for this scenario: a copy whose system-one/questions.yaml holds %s (sha256 %s)\n' \
      "$(cat "$E2E_DIR/unsendable/$i.label")" "$(_e2e_sha256 "$E2E_DIR/unsendable/$i.yaml")" | _e2e_art
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
    _s1_ask e2e.q
    _expect_no_answer questions-invalid
    _expect_requests "$st" 0
    _expect_no_traceback
  done
  # S59: a cycle that branches, and YAML pairs over an alias expansion, each
  # under a watchdog that ends the client after 10 s, so a walk that grows
  # without bound fails the scenario instead of exhausting the machine.
  e2e_plugin_copy bin/with-limit.sh "$(printf '%s\n' '#!/bin/sh' \
    'limit=$1; shift' \
    '"$@" & p=$!' \
    '( sleep "$limit"; kill -9 "$p" 2>/dev/null ) & w=$!' \
    'wait "$p"; rc=$?' \
    'kill "$w" 2>/dev/null' \
    'exit "$rc"')"
  # Each file under each python3 here that can run the client (S74: a long
  # integer is slow only on Python 3.9).
  n=0
  while IFS= read -r label; do
    n=$((n+1))
    python3 - "$E2E_DIR/unsendable/w$n.yaml" "$n" <<'PY'
import sys
path, n = sys.argv[1], int(sys.argv[2])
site = "sites:\n  e2e.q:\n    questions:\n      q1: {type: noul, instructions: %s}\n    thresholds:\n      q1: {default: 0.5}\n"
if n == 1:
    text = "cyc: &a [*a, *a]\n" + site % "*a"
elif n == 2:
    text = "bomb:\n  l0: &l0 [aaaaaaaaaa]\n" + "".join("  l%d: &l%d [%s]\n" % (i, i, ", ".join(["*l%d" % (i - 1)] * 10)) for i in range(1, 9)) + site % "!!pairs [k: *l8]"
elif n == 3:
    text = "x0: &x0 {a: 1, b: 2}\n" + "".join("x%d: &x%d {<<: [*x%d, *x%d]}\n" % (i, i, i - 1, i - 1) for i in range(1, 26)) + site % '"The ticket is urgent."'
elif n == 4:
    text = "big: " + "1" * 2000000 + "\n" + site % '"The ticket is urgent."'
elif n == 5:
    text = site % ('{question: "Is the ticket urgent?", n: 0x%s}' % ("f" * 3700))
else:
    text = site % '"The ticket is urgent."' + "  e2e.other:\n    note: " + "1" * 4301 + "\n"
open(path, "w").write(text)
PY
    printf '%s\n' "$label" > "$E2E_DIR/unsendable/w$n.label"
  done <<'LABELS'
a cycle that branches, &a [*a, *a], as instructions
YAML pairs over aliases ten wide and eight deep
a chain of 26 merge keys, each naming the one before twice
an integer of two million digits
a hexadecimal integer of 3700 digits (about 4450 decimal digits)
a decimal integer of 4301 digits under another site
LABELS
  seen=""; k=0
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    case " $seen " in *" $v "*) continue ;; esac
    seen="$seen $v"
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    for n in 1 2 3 4 5 6; do
      k=$((k+1)); st="w$k"
      cp "$E2E_DIR/unsendable/w$n.yaml" "$E2E_ACTIVE_PLUGIN/system-one/questions.yaml"
      printf '%s, a copy whose system-one/questions.yaml holds %s (sha256 %s)\n' "$v" "$(cat "$E2E_DIR/unsendable/w$n.label")" "$(_e2e_sha256 "$E2E_DIR/unsendable/w$n.yaml")" | _e2e_art
      e2e_stub_start "$st" '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
      _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
      e2e_run_bin bin/with-limit.sh 10 "$E2E_ACTIVE_PLUGIN/$S1_BIN" ask --site e2e.q --state-file state.txt
      _expect_no_answer questions-invalid
      _expect_requests "$st" 0
      # The message names the value to change by its path.
      [ "$n" = 2 ] && e2e_expect_err "question q1.instructions[0] is a YAML ordered map"
    done
  done
  rm -f "$E2E_BIN/python3"

  # File 19 (the alias chain) with each
  # interpreter: a shim named python3 in the scenario's bin runs the client
  # under it. The interpreter is asked first whether its JSON encoder takes
  # the file's questions inside a request body, as the client encodes them.
  n=0; seen=""
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    case " $seen " in *" $v "*) continue ;; esac
    seen="$seen $v"
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    for i in 19; do
      how=$(HOME=/nonexistent "$py" - "$E2E_DIR/unsendable/$i.yaml" 2>/dev/null <<'PY'
import json, sys, yaml
q = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["sites"]["e2e.q"]["questions"]
try:
    json.dumps({"state": "", "questions": q}, ensure_ascii=False, allow_nan=False).encode("utf-8")
    print("encodes")
except (ValueError, RecursionError):
    print("cannot-encode")
PY
) || continue
      n=$((n+1)); st="c$n"
      cp "$E2E_DIR/unsendable/$i.yaml" "$E2E_ACTIVE_PLUGIN/system-one/questions.yaml"
      printf '%s, questions file holding %s (sha256 %s): its JSON encoder says %s\n' "$v" \
        "$(cat "$E2E_DIR/unsendable/$i.label")" "$(_e2e_sha256 "$E2E_DIR/unsendable/$i.yaml")" "$how" | _e2e_art
      e2e_stub_start "$st" '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
      _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
      _s1_ask e2e.q
      case $how in
        encodes) e2e_expect_equal "0 0.95" "$E2E_RC $(_jq '.answers.q1.p')" "exit status and p under $v ($i)"; _expect_requests "$st" 1 ;;
        *) _expect_no_answer questions-invalid; _expect_requests "$st" 0 ;;
      esac
      _expect_no_traceback
    done
  done
  rm -f "$E2E_BIN/python3"
  e2e_expect_equal yes "$([ "$n" -ge 1 ] && echo yes || echo no)" "at least one interpreter ran the chain"
fi

if _want stderr-one-line; then
  _flow_test_begin "stderr-one-line"
  _s1_setup stderr-one-line "a key and a question id holding a newline and an escape sequence reach the reason's detail on stderr escaped, so stderr has exactly one no-answer line and no raw control character (S51): a choice option \"ctx<newline>flow-s1: no answer: forged<ESC>[31m\" above the key 1, and a question id with a newline and no threshold. A warning is escaped the same way: FLOW_STATE_DIR naming a symlink with that text in its name gives one warning line and no forged reason"
  S1_ENV=()
  n=0
  while IFS= read -r q; do
    n=$((n+1)); st="s$n"
    e2e_stub_start "$st" '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
    e2e_plugin_copy system-one/questions.yaml "$q"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
    _s1_ask e2e.q
    e2e_expect_equal 3 "$E2E_RC" "exit status ($st)"
    e2e_expect_equal 1 "$(grep -c '^flow-s1: no answer:' <<<"$E2E_ERR")" "lines on stderr that start as a no-answer line ($st)"
    e2e_expect_equal 0 "$(LC_ALL=C tr -d '\n' <<<"$E2E_ERR" | LC_ALL=C tr -cd '\000-\037\177' | wc -c | tr -d ' ')" "control characters in stderr other than line ends ($st)"
    _expect_requests "$st" 0
  done <<'CASES'
sites: {e2e.q: {questions: {q1: {type: noul, instructions: {"ctx\nflow-s1: no answer: forged\e[31m": {1: calm}}}}, thresholds: {q1: {default: 0.5}}}}
sites: {e2e.q: {questions: {"q\nflow-s1: no answer: forged\e[31m": {type: noul, instructions: "The ticket is urgent."}}, thresholds: {}}}
CASES
  # A warning carries a path from the environment: FLOW_STATE_DIR names a
  # symlink whose name holds a newline and an escape sequence, so the call
  # answers and warns that it is not writing records, on one line.
  e2e_plugin_copy system-one/questions.yaml "$S1_FIXTURE"
  e2e_stub_start w "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url w)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  odd="$E2E_DIR/st"$'\n'"flow-s1: no answer: forged"$'\e'"[31m"
  mkdir -p "$E2E_DIR/real-state" && ln -s "$E2E_DIR/real-state" "$odd"
  S1_ENV=("FLOW_STATE_DIR=$odd")
  _s1_ask e2e.one
  S1_ENV=()
  e2e_expect_equal "0 0 1" "$E2E_RC $(grep -c '^flow-s1: no answer:' <<<"$E2E_ERR") $(grep -c 'flow-s1: WARN: not writing records' <<<"$E2E_ERR")" "exit status, lines that start as a no-answer line, and record warnings, on stderr (a warning)"
  e2e_expect_equal 0 "$(LC_ALL=C tr -d '\n' <<<"$E2E_ERR" | LC_ALL=C tr -cd '\000-\037\177' | wc -c | tr -d ' ')" "control characters in stderr other than line ends (a warning)"
fi

if _want settings-unparsable-url; then
  _flow_test_begin "settings-unparsable-url"
  _s1_setup settings-unparsable-url "a baseUrl urllib cannot parse (http://[::1, an IPv6 address without its closing bracket; S52), a port that is not a number or is out of range (S54), a path holding a space, a control character (refused by the settings lookup itself, as for any setting) or a character outside ASCII (S61), a host outside ASCII (bücher.example, 例え.テスト; use the xn-- form), a query, a fragment, or a user and password (S65), a port written with a sign or an underscore, or a host with text around its brackets (a[::1].127.0.0.1.nip.io), under each python3 here (S69, S70), and a key a header cannot carry, with a newline or a character outside Latin-1 (S54), are each invalid-settings before any request, never internal-error or connection, and nothing is recorded; neither the key nor the baseUrl is ever printed, so no password or key in it reaches stderr (S67, S68)" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  S1_ENV=()
  for u in 'http://[::1' 'http://127.0.0.1:abc' 'http://[::1]:abc' 'http://127.0.0.1:99999' \
      "$(e2e_stub_url a)/a b" "$(e2e_stub_url a)/ü" "$(e2e_stub_url a)/"$'\x01' \
      'https://bücher.example' 'https://例え.テスト' "$(e2e_stub_url a)/?tenant=a" "$(e2e_stub_url a)#x" \
      "http://u:s3cr3t@$(e2e_stub_url a | sed 's|^http://||')" 'https://u:s3cr3t@127.0.0.1:1/ü' \
      'https://user:s3cr3t/x@api.example' 'https://u:s3#cr3t@api.example' 'https://u:s3?cr3t@api.example' \
      'u:s3cr3t@api.example' "$(e2e_stub_url a)/?" "$(e2e_stub_url a)#" \
      'https://api.example/v1?key=k9zqx7wv' 'https://api.example#token=k9zqx7wv' 'api.example?key=k9zqx7wv' \
      'https://u:s3cr3t＠api.example' 'https://api.example？key＝k9zqx7wv' 'https://api.example/k9zqx7wv/ü'; do
    _s1_settings "$(jq -nc --arg u "$u" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    _expect_no_answer invalid-settings
    _expect_no_traceback
    e2e_expect_equal 0 "$(grep -c -e s3cr3t -e 's3#cr3t' -e 's3?cr3t' -e k9zqx7wv <<<"$E2E_ERR")" "stderr lines holding the password or a key"
  done
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"E2E_ODD_KEY",uses:{"e2e.one":"on"}}}')"
  for k in "k9zq"$'\n'"x7wv" "k9zq-€-x7wv"; do
    S1_ENV=("E2E_ODD_KEY=$k")
    _s1_ask e2e.one
    _expect_no_answer invalid-settings
    e2e_expect_equal 0 "$(grep -c -e k9zq -e x7wv <<<"$E2E_ERR")" "lines of stderr holding part of the key"
  done
  S1_ENV=()
  _expect_requests a 0
  e2e_expect_equal no "$([ -e "$E2E_HOME/$S1_RECORDS" ] && echo yes || echo no)" "a record file exists"
  # A port written with a sign or an underscore, under each python3 here
  # that can run the client (Python 3.9's urllib reads a port with int()).
  port=$(e2e_stub_url a | sed 's|.*:||')
  seen=""
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    case " $seen " in *" $v "*) continue ;; esac
    seen="$seen $v"
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    for u in "http://127.0.0.1:+$port" "http://127.0.0.1:${port%?}_${port#${port%?}}" \
        "http://a[::1].127.0.0.1.nip.io:$port" "http://[::1]x.127.0.0.1.nip.io:$port" \
        "http://[127.0.0.1]:$port" "http://[localhost]:$port" 'https://[v1.fe]' "https://[::1%]:$port" \
        "http://[::1%5d.127.0.0.1.nip.io]:$port" "http://[::1%25]:$port" "http://127.0.0.1%3a$port" \
        "http://[::1%25%0a]:$port" "http://[::1%25%5d]:$port" "http://[::1%25%e2%80%a8]:$port"; do
      _s1_settings "$(jq -nc --arg u "$u" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
      _s1_ask e2e.one
      _expect_no_answer invalid-settings
      _expect_no_traceback
    done
  done
  # [::1%3a1] decodes to ::1:1, which is not this machine: plain http to it
  # is insecure-url. A real zone id is accepted: [::1%25lo0] is not refused.
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    _s1_settings "$(jq -nc --arg u "http://[::1%3a1]:$port" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    _expect_no_answer insecure-url
    _s1_settings "$(jq -nc --arg u "http://[::1%25lo0]:$port" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    e2e_expect_equal 0 "$(grep -c -e 'no answer: invalid-settings' -e 'no answer: insecure-url' <<<"$E2E_ERR")" "refusals of [::1%25lo0] under $("$py" --version 2>&1)"
  done
  rm -f "$E2E_BIN/python3"
  _expect_requests a 0
fi

if _want settings-numbers; then
  _flow_test_begin "settings-numbers"
  _s1_setup settings-numbers "timeoutMs and stateTokenCap are whole numbers of up to 9 digits, a trailing .0 allowed, under each python3 here (S79): 20000.0 is 20000 ms with no warning; 999999999 is used (clamped to 30000 ms) with no warning, while 1000000000 is warned about and 3000 ms is used; a stateTokenCap that is not a whole number is warned about and the provider's default is used; and a baseUrl longer than 4096 characters is invalid-settings before python3 runs" fixture
  e2e_stub_start a "{\"delay_ms\":4000,\"body\":$ONE_CONFIDENT}"
  e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
  S1_ENV=()
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    # 20000.0 ms waits for a reply that takes 4 s; 3000 ms would not.
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:20000.0,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    e2e_expect_equal "0 0" "$E2E_RC $(grep -c WARN <<<"$E2E_ERR")" "exit status and warnings for timeoutMs 20000.0 under $v"
    # Nine digits is a whole number, clamped to 30000 ms: the reply arrives.
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:999999999,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    e2e_expect_equal "0 0" "$E2E_RC $(grep -c WARN <<<"$E2E_ERR")" "exit status and warnings for timeoutMs 999999999 under $v"
    # Ten digits is not: warned about, and 3000 ms used, so the reply is late.
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:1000000000,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    _expect_no_answer timeout
    e2e_expect_err "systemOne.timeoutMs is not a whole number"
    # A stateTokenCap that is not a whole number: warned about.
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:"lots",uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    e2e_expect_equal 0 "$E2E_RC" "exit status for stateTokenCap lots under $v"
    e2e_expect_err "systemOne.stateTokenCap is not a whole number"
  done
  rm -f "$E2E_BIN/python3"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url b)/$(printf 'a%.0s' $(seq 1 4100))" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  _s1_ask e2e.one
  _expect_no_answer invalid-settings
fi

if _want timeout-classified; then
  _flow_test_begin "timeout-classified"
  _s1_setup timeout-classified "a request that its own timeout ends, before the wait for it does, is timeout under each python3 here (S80): a reply later than timeoutMs, and a request of 32 MiB that the server never reads, so sending it stalls; the client is run with the wait made 5 s longer, so the request's own timeout always ends it first, as it can by chance in a normal run" fixture
  e2e_stub_start a "{\"delay_ms\":3000,\"body\":$ONE_CONFIDENT}"
  # The client, run directly as flow-s1.sh runs it, with every thread wait
  # given 5 s more than asked, and a 500 ms timeout; the third argument, when
  # given, is the state token cap.
  e2e_plugin_copy bin/late-wait-s1.sh "$(printf '%s\n' '#!/bin/sh' \
    'd=$(cd "$(dirname "$0")" && pwd)' \
    'exec python3 -c "import runpy, sys, threading; j = threading.Thread.join; threading.Thread.join = lambda self, timeout=None: j(self, None if timeout is None else timeout + 5); sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name=\"__main__\")" "$d/_flow_s1.py" --site=e2e.one --state-file="$1" --state-format=text --current= --run-id= --provider=custom --base-url="$2" --model=jev-1.13.0 --api-key-env= --timeout-ms=500 --state-token-cap="${3:-0}" --mode=on --questions="$d/../system-one/questions.yaml" --repo-top="$(pwd -P)" --state-dir="$HOME/.claude/flow-state"')"
  # A server that never accepts a connection, so never reads a request: the
  # kernel completes the connection, and sending a request larger than both
  # ends' socket buffers (4 MiB each at most on macOS, 4 and 6 MiB on Linux
  # by default) stalls. The state is 32 MiB of text, under a cap that keeps
  # all of it.
  cat > "$E2E_DIR/no-reader.py" <<'PY'
import socket, sys, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(8)
open(sys.argv[1], "w").write("%d\n" % s.getsockname()[1])
time.sleep(120)
PY
  python3 "$E2E_DIR/no-reader.py" "$E2E_DIR/no-reader.port" & fq=$!
  for _ in $(seq 1 50); do [ -s "$E2E_DIR/no-reader.port" ] && break; sleep 0.1; done
  fport=$(cat "$E2E_DIR/no-reader.port" 2>/dev/null)
  e2e_expect_equal yes "$([ -n "$fport" ] && echo yes || echo no)" "the server that never reads is listening"
  head -c 33554432 /dev/zero | tr '\0' a > "$E2E_REPO/big.state"
  S1_ENV=()
  n=0
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    n=$((n + 1))
    # A reply 3 s late against a 500 ms timeout.
    e2e_run_bin bin/late-wait-s1.sh "$E2E_REPO/state.txt" "$(e2e_stub_url a)"
    e2e_expect_equal "3 1 0" "$E2E_RC $(grep -c 'no answer: timeout$' <<<"$E2E_ERR") $(grep -c -e 'no answer: connection' -e Traceback <<<"$E2E_ERR")" "exit status, timeout lines and connection or traceback lines for a late reply under $v"
    # A request of 32 MiB that the server never reads.
    e2e_run_bin bin/late-wait-s1.sh "$E2E_REPO/big.state" "http://127.0.0.1:$fport" 999999999
    e2e_expect_equal "3 1 0" "$E2E_RC $(grep -c 'no answer: timeout$' <<<"$E2E_ERR") $(grep -c -e 'no answer: connection' -e Traceback <<<"$E2E_ERR")" "exit status, timeout lines and connection or traceback lines for a request never read under $v"
  done
  rm -f "$E2E_BIN/python3"
  kill "$fq" 2>/dev/null; wait "$fq" 2>/dev/null
  e2e_expect_equal yes "$([ "$n" -ge 1 ] && echo yes || echo no)" "at least one interpreter ran"
fi

if _want mode-too-long; then
  _flow_test_begin "mode-too-long"
  _s1_setup mode-too-long "a repository's settings give a site the mode value of 1.1 MB, over the system's argument limit (S75): the value is not a mode, so the call is off with its warning, exit 3 and no answer: mode-off, never an unlisted exit status" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  mkdir -p "$E2E_REPO/.claude"
  python3 -c 'import json, sys; json.dump({"systemOne": {"uses": {"e2e.one": "x" * 1100000}}}, open(sys.argv[1], "w"))' "$E2E_REPO/.claude/settings.flow.json"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer mode-off
  _expect_requests a 0
fi

if _want mapped-loopback; then
  _flow_test_begin "mapped-loopback"
  _s1_setup mapped-loopback "a baseUrl naming this machine as an IPv4-mapped IPv6 address, http://[::ffff:127.0.0.1]:PORT, is this machine under each python3 here, so plain http is allowed and the call answers (S72); the stub listens on 127.0.0.1, which the mapped address reaches only where the system maps it, so the scenario checks that the client did not refuse it as insecure-url" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  port=$(e2e_stub_url a | sed 's|.*:||')
  S1_ENV=()
  seen=""; n=0
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    case " $seen " in *" $v "*) continue ;; esac
    seen="$seen $v"
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    n=$((n+1))
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    _s1_settings "$(jq -nc --arg u "http://[::ffff:127.0.0.1]:$port" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    _s1_ask e2e.one
    e2e_expect_equal 0 "$(grep -c 'no answer: insecure-url' <<<"$E2E_ERR")" "insecure-url refusals under $v"
    e2e_expect_equal yes "$( { [ "$E2E_RC" = 0 ] || grep -q 'no answer: connection' <<<"$E2E_ERR"; } && echo yes || echo no)" "answered, or failed only to connect, under $v"
    _expect_no_traceback
  done
  rm -f "$E2E_BIN/python3"
  e2e_expect_equal yes "$([ "$n" -ge 1 ] && echo yes || echo no)" "at least one interpreter ran"
fi

if _want json-long-integers; then
  _flow_test_begin "json-long-integers"
  _s1_setup json-long-integers "under each python3 here (S71): a reply holding an integer of 5000 digits is malformed while it is parsed, with the 4300-digit limit named, as Python 3.11 and later refuse it, never parsed into a number first; and a JSON state holding one of a million digits is state-invalid within a 10 s watchdog, where Python 3.9 would take about 30 s to parse it" fixture
  python3 -c 'print("[" + "1" * 1000000 + "]")' > "$E2E_REPO/long.json"
  python3 -c 'import json; print(json.dumps({"body": "{\"model\":\"jev-1.13.0\",\"answers\":{\"q1\":{\"type\":\"noul\",\"noul\":" + "1" * 5000 + "}}}"}))' > "$E2E_DIR/long-reply.json"
  e2e_stub_start a "$(cat "$E2E_DIR/long-reply.json")"
  e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
  e2e_plugin_copy bin/with-limit.sh "$(printf '%s\n' '#!/bin/sh' \
    'limit=$1; shift' \
    '"$@" & p=$!' \
    '( sleep "$limit"; kill -9 "$p" 2>/dev/null ) & w=$!' \
    'wait "$p"; rc=$?' \
    'kill "$w" 2>/dev/null' \
    'exit "$rc"')"
  S1_ENV=()
  seen=""; n=0
  for py in "$(command -v python3)" /usr/bin/python3; do
    [ -x "$py" ] || continue
    v=$("$py" --version 2>&1)
    case " $seen " in *" $v "*) continue ;; esac
    seen="$seen $v"
    HOME=/nonexistent "$py" -c 'import yaml' 2>/dev/null || continue
    n=$((n+1))
    printf '#!/bin/sh\nexec %s "$@"\n' "$py" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:30000,uses:{"e2e.one":"on"}}}')"
    e2e_run_bin bin/with-limit.sh 10 "$E2E_ACTIVE_PLUGIN/$S1_BIN" ask --site e2e.one --state-file state.txt
    _expect_no_answer malformed
    e2e_expect_err "an integer of more than 4300 digits"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    e2e_run_bin bin/with-limit.sh 10 "$E2E_ACTIVE_PLUGIN/$S1_BIN" ask --site e2e.one --state-file long.json --state-format json
    _expect_no_answer state-invalid
    e2e_expect_err "an integer of more than 4300 digits"
  done
  rm -f "$E2E_BIN/python3"
  _expect_requests b 0
  e2e_expect_equal yes "$([ "$n" -ge 1 ] && echo yes || echo no)" "at least one interpreter ran"
fi

if _want records-best-effort; then
  _flow_test_begin "records-best-effort"
  _s1_setup records-best-effort "records are best effort (S55): a state directory 1000 levels deep, which os.makedirs cannot create, leaves an answered call answered with one warning, and a refused connection still reports connection" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  deep="$E2E_DIR/sd$(printf '/y%.0s' $(seq 1 1000))"
  S1_ENV=("FLOW_STATE_DIR=$deep")
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  _s1_ask e2e.one
  e2e_expect_equal "0 0.95 1" "$E2E_RC $(_jq '.answers.q1.p') $(grep -c 'flow-s1: WARN: not writing records' <<<"$E2E_ERR")" "exit status, p and record warnings"
  _expect_requests a 1
  _expect_no_traceback
  _s1_settings '{"systemOne":{"provider":"custom","baseUrl":"http://127.0.0.1:1","uses":{"e2e.one":"on"}}}'
  _s1_ask e2e.one
  _expect_no_answer connection
  _expect_no_traceback
  S1_ENV=()
fi

if _want state-file-size; then
  _flow_test_begin "state-file-size"
  _s1_setup state-file-size "a state file larger than 64 MiB (a sparse file one byte over) is state-too-large before it is read, as text and as JSON (S56); a JSON state larger than 8 MiB is state-too-large too, since parsing JSON takes many times its size (S62), while a text state of that size is read and shortened; the stub is asked only for the text state of 8 MiB" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  python3 -c 'import sys; f = open(sys.argv[1], "wb"); f.truncate(64 * 1024 * 1024 + 1)' "$E2E_REPO/huge.state"
  python3 -c 'import sys; f = open(sys.argv[1], "wb"); f.truncate(8 * 1024 * 1024 + 1)' "$E2E_REPO/big.state"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  for fmt in text json; do
    e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file huge.state --state-format "$fmt"
    _expect_no_answer state-too-large
    _expect_no_traceback
  done
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file big.state --state-format json
  _expect_no_answer state-too-large
  _expect_requests a 0
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file big.state --state-format text
  e2e_expect_equal "0 true" "$E2E_RC $(_jq '.truncated')" "exit status and truncated for a text state of 8 MiB"
  _expect_requests a 1
fi

if _want direct-run; then
  _flow_test_begin "direct-run"
  _s1_setup direct-run "the Python client run directly, with the arguments flow-s1.sh passes (S58, S61, S62, S63, S64): a model id holding a byte that is not UTF-8, or a tab, and a baseUrl holding a control character, are invalid-settings before any request, never internal-error; a state file that is missing, a directory or a device (/dev/null) is state-invalid, before any read of the device; a FIFO as the state file is state-invalid and as the questions file questions-invalid, without waiting for a writer; a JSON state over 8 MiB with no state format given is state-too-large; and with no PyYAML importable, python-missing, where python3 without the user's site-packages cannot import it here" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  # The fourth argument, when given, is the state format (empty: none given).
  e2e_plugin_copy bin/direct-s1.sh "$(printf '%s\n' '#!/bin/sh' \
    'd=$(cd "$(dirname "$0")" && pwd)' \
    'exec python3 "$d/_flow_s1.py" --site=e2e.one --state-file="$1" --state-format="${4-text}" --current= --run-id= --provider=custom --base-url="$2" --model="$3" --api-key-env= --timeout-ms=3000 --state-token-cap=0 --mode=on --questions="${QUESTIONS:-$d/../system-one/questions.yaml}" --repo-top="$(pwd -P)" --state-dir="$HOME/.claude/flow-state"')"
  e2e_plugin_copy bin/with-limit.sh "$(printf '%s\n' '#!/bin/sh' \
    'limit=$1; shift' \
    '"$@" & p=$!' \
    '( sleep "$limit"; kill -9 "$p" 2>/dev/null ) & w=$!' \
    'wait "$p"; rc=$?' \
    'kill "$w" 2>/dev/null' \
    'exit "$rc"')"
  S1_ENV=()
  # Through flow-s1.sh the settings lookup refuses a control character and
  # uses the default model; run directly, the client refuses a model id that
  # is not plain text itself.
  for m in "jev"$'\xff' "jev"$'\t'"1.13.0"; do
    e2e_run_bin bin/direct-s1.sh "$E2E_REPO/state.txt" "$(e2e_stub_url a)" "$m"
    _expect_no_answer invalid-settings
    _expect_no_traceback
  done
  _expect_requests a 0
  mkdir -p "$E2E_REPO/a-directory"
  for f in "$E2E_REPO/missing.txt" "$E2E_REPO/a-directory" /dev/null; do
    e2e_run_bin bin/direct-s1.sh "$f" "$(e2e_stub_url a)" "jev-1.13.0"
    _expect_no_answer state-invalid
    _expect_no_traceback
  done
  # A FIFO as the state file and as the questions file, each under a
  # watchdog: opening one waits for a writer (S64).
  mkfifo "$E2E_REPO/state.fifo" "$E2E_DIR/questions.fifo"
  e2e_run_bin bin/with-limit.sh 10 "$E2E_ACTIVE_PLUGIN/bin/direct-s1.sh" "$E2E_REPO/state.fifo" "$(e2e_stub_url a)" "jev-1.13.0"
  _expect_no_answer state-invalid
  e2e_run_bin "QUESTIONS=$E2E_DIR/questions.fifo" bin/with-limit.sh 10 "$E2E_ACTIVE_PLUGIN/bin/direct-s1.sh" "$E2E_REPO/state.txt" "$(e2e_stub_url a)" "jev-1.13.0"
  _expect_no_answer questions-invalid
  # A JSON state over 8 MiB with no state format given is the JSON bound's
  # (S63): the client reads any format other than text as JSON.
  python3 -c 'import sys; f = open(sys.argv[1], "wb"); f.truncate(8 * 1024 * 1024 + 1)' "$E2E_REPO/big.state"
  e2e_run_bin bin/direct-s1.sh "$E2E_REPO/big.state" "$(e2e_stub_url a)" "jev-1.13.0" ""
  _expect_no_answer state-too-large
  # A control character in the baseUrl reaches the client only when it is run
  # directly: the settings lookup refuses it first.
  for u in "$(e2e_stub_url a)/a"$'\x01'"b" "$(e2e_stub_url a)/a"$'\x7f'"b"; do
    e2e_run_bin bin/direct-s1.sh "$E2E_REPO/state.txt" "$u" "jev-1.13.0"
    _expect_no_answer invalid-settings
    _expect_no_traceback
  done
  _expect_requests a 0
  if PYTHONNOUSERSITE=1 PYTHONPATH= python3 -c 'import yaml' 2>/dev/null; then
    printf 'python3 imports PyYAML without the user site here; the python-missing half checks nothing\n' | _e2e_art
    _e2e_result pass "skipped: python3 imports PyYAML without the user site here"
  else
    e2e_run_bin PYTHONNOUSERSITE=1 PYTHONPATH= bin/direct-s1.sh "$E2E_REPO/state.txt" "$(e2e_stub_url a)" "jev-1.13.0"
    _expect_no_answer python-missing
    _expect_no_traceback
    _expect_requests a 0
  fi
fi

if _want reply-huge-integer; then
  _flow_test_begin "reply-huge-integer"
  _s1_setup reply-huge-integer "a reply number that is an integer of 401 digits, too large for a float, is malformed and recorded, as 1e400 is (S46): as a noul, as an unknown_probability beside a confident noul, as a choice's confidence, and as a score" fixture
  BIG="1$(printf '%0400d' 0)"
  e2e_stub_start n1 "{\"body\":{\"model\":\"imajev-4b\",\"answers\":{\"q1\":{\"type\":\"noul\",\"noul\":$BIG}}}}"
  e2e_stub_start n2 "{\"body\":{\"model\":\"imajev-4b\",\"answers\":{\"q1\":{\"type\":\"noul\",\"noul\":0.95,\"unknown_probability\":$BIG}}}}"
  e2e_stub_start n3 "{\"body\":{\"model\":\"jev-1.13.0\",\"answers\":{\"q1\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":0.9,\"b\":0.05,\"c\":0.05},\"confidence\":$BIG}}}}"
  e2e_stub_start n4 "{\"body\":{\"model\":\"jev-1.13.0\",\"answers\":{\"q1\":{\"type\":\"noul\",\"noul\":0.8},\"q2\":{\"type\":\"choice\",\"choice\":\"y\",\"probabilities\":{\"x\":0.1,\"y\":0.9},\"confidence\":0.8},\"q3\":{\"type\":\"score\",\"score\":$BIG,\"probabilities\":{\"0\":0.1,\"1\":0.2,\"2\":0.7},\"confidence\":0.55}}}}"
  S1_ENV=()
  f="$E2E_HOME/$S1_RECORDS"
  for pair in 'n1 e2e.one' 'n2 e2e.one' 'n3 e2e.abc' 'n4 e2e.contract'; do
    st=${pair%% *}; site=${pair#* }
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "$st")" --arg s "$site" '{systemOne:{provider:"custom",baseUrl:$u,uses:{($s):"on"}}}')"
    _s1_ask "$site"
    _expect_no_answer malformed
    _expect_requests "$st" 1
    _expect_no_traceback
    e2e_expect_equal malformed "$( [ -f "$f" ] && tail -1 "$f" | jq -r '.result')" "the last record's result ($st)"
  done
fi

if _want questions-many-small-values; then
  _flow_test_begin "questions-many-small-values"
  _s1_setup questions-many-small-values "questions that encode to under 1 MiB are sent, however many small values they hold (S66): 100 copies of 0.5 named by 420 aliases (about 0.2 MiB), 1000 copies of 9 named by 262 aliases (about 0.75 MiB), and a binary tree of [0] leaves 16 levels deep (about 0.88 MiB, where one-element lists counted 3 bytes each would pass 1 MiB)"
  S1_ENV=()
  n=0
  for v in '0.5 100 420' '9 1000 262' 'tree 0 0'; do
    n=$((n+1)); set -- $v
    python3 - "$E2E_DIR/small$n.yaml" "$1" "$2" "$3" <<'PY'
import sys
path, v, width, refs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
if v == "tree":
    # A binary tree of [0] leaves, 16 levels: about 0.9 MB encoded.
    text = "l0: &l0 [0]\nt0: &t0 [*l0, *l0]\n" + "".join("t%d: &t%d [*t%d, *t%d]\n" % (i, i, i - 1, i - 1) for i in range(1, 17))
    values = "*t16"
else:
    text = "v: &v [%s]\n" % ", ".join([v] * width)
    values = "[%s]" % ", ".join(["*v"] * refs)
text += "sites:\n  e2e.q:\n    questions:\n      q1: {type: noul, instructions: {question: \"Is the ticket urgent?\", values: %s}}\n    thresholds:\n      q1: {default: 0.5}\n" % values
open(path, "w").write(text)
PY
    e2e_stub_start "m$n" '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
    e2e_plugin_copy system-one/questions.yaml "$(cat "$E2E_DIR/small$n.yaml")"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url "m$n")" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
    _s1_ask e2e.q
    e2e_expect_equal "0 0.95" "$E2E_RC $(_jq '.answers.q1.p')" "exit status and p ($1 by $2 by $3)"
    _expect_requests "m$n" 1
  done
fi

if _want question-structured; then
  _flow_test_begin "question-structured"
  _s1_setup question-structured "structured instructions and criteria of the kinds TypeSafe's API documents (S43) are sent as written and answered: noul instructions as an object holding a number and criteria with quoted \"true\" and \"false\", one of them an object; choice instructions as a list and an option described by a list, another by null; score levels as objects"
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.9},"q2":{"type":"choice","choice":"billing","probabilities":{"billing":0.9,"support":0.1},"confidence":0.8},"q3":{"type":"score","score":0.8,"probabilities":{"0":0.2,"1":0.8},"confidence":0.6}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.q":"on"}}}')"
  S1_ENV=()
  e2e_plugin_copy system-one/questions.yaml 'sites:
  e2e.q:
    questions:
      q1:
        type: noul
        instructions: {question: "Is the customer asking for a refund?", policy: "Refunds need a receipt.", max_days: 30}
        criteria: {"true": "Asks for money back.", "false": {text: "Anything else.", examples: ["a question", "a complaint"]}}
      q2: {type: choice, instructions: ["Which team should handle it?", "Billing handles charges."], criteria: {billing: ["charges", "refunds"], support: null}}
      q3: {type: score, instructions: "How frustrated is the customer?", criteria: [{level: calm}, {level: angry, sign: "capital letters"}]}
    thresholds:
      q1: {default: 0.5}
      q2: {default: 0.5}
      q3: {default: 0.5}
'
  _s1_ask e2e.q
  e2e_expect_equal "0 0.9 billing 0.8" "$E2E_RC $(_jq '.answers.q1.p') $(_jq '.answers.q2.choice') $(_jq '.answers.q3.score')" "exit status and the three answers"
  _expect_requests a 1
  # The questions exactly as TypeSafe's API documents them: instructions text,
  # an object or a list; noul criteria "true" and "false"; a choice option
  # described by text, an object, a list or null; score levels likewise.
  e2e_expect_equal '{"q1":{"criteria":{"false":{"examples":["a question","a complaint"],"text":"Anything else."},"true":"Asks for money back."},"instructions":{"max_days":30,"policy":"Refunds need a receipt.","question":"Is the customer asking for a refund?"},"type":"noul"},"q2":{"criteria":{"billing":["charges","refunds"],"support":null},"instructions":["Which team should handle it?","Billing handles charges."],"type":"choice"},"q3":{"criteria":[{"level":"calm"},{"level":"angry","sign":"capital letters"}],"instructions":"How frustrated is the customer?","type":"score"}}' \
    "$(jq -cS '.body.questions' "$(e2e_stub_log a)")" "questions sent"
fi

if _want score-level-bounds; then
  _flow_test_begin "score-level-bounds"
  # 2 to 10 levels: docs.typesafe.ai/api, Score ("A Score should have at least
  # two levels; the API accepts up to 10").
  _s1_setup score-level-bounds "a score with exactly 2 levels and one with exactly 10 are valid question sets and answer (the edges of the 2-10 range TypeSafe's API accepts)"
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"score","score":1,"probabilities":{"0":0.0,"1":1.0},"confidence":1.0}}}}'
  e2e_stub_start b '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"score","score":9,"probabilities":{"0":0.0,"1":0.0,"2":0.0,"3":0.0,"4":0.0,"5":0.0,"6":0.0,"7":0.0,"8":0.0,"9":1.0},"confidence":1.0}}}}'
  S1_ENV=()
  e2e_plugin_copy system-one/questions.yaml "$(printf 'sites:\n  e2e.two:\n    questions:\n      q1: {type: score, instructions: "Rate.", criteria: [low, high]}\n    thresholds:\n      q1: {default: 0.5}\n  e2e.ten:\n    questions:\n      q1: {type: score, instructions: "Rate.", criteria: [l0, l1, l2, l3, l4, l5, l6, l7, l8, l9]}\n    thresholds:\n      q1: {default: 0.5}\n')"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.two":"on"}}}')"
  _s1_ask e2e.two
  e2e_expect_equal "0 1" "$E2E_RC $(_jq '.answers.q1.score')" "exit status and score with 2 levels"
  _expect_requests a 1
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.ten":"on"}}}')"
  _s1_ask e2e.ten
  e2e_expect_equal "0 9" "$E2E_RC $(_jq '.answers.q1.score')" "exit status and score with 10 levels"
  _expect_requests b 1
fi

_e2e_stop_stubs
