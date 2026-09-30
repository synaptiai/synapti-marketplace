"""The Python half of bin/flow-s1.sh: validate, ask, normalize, record.

flow-s1.sh resolves the settings and hands them over as arguments; this file
never reads a settings file itself. It exits 0 with one JSON line on stdout
when every question answered with enough confidence, and 3 with an empty
stdout and "flow-s1: no answer: <reason>" on stderr otherwise. A reason is one
of the names documented in references/system-one.md. No traceback reaches the
caller: an unexpected error is the reason "internal-error".

Provider presets (TypeSafe from docs.typesafe.ai/api and /models; imajev from
the quickstart in github.com/mohit67890/imajev):

  typesafe  https://api.typesafe.ai, model jev-1.13.0 (a pinned version:
            "jev-latest" moves between releases, and thresholds are tuned
            per version), key in TYPESAFE_API_KEY, required. Jev allows 32k
            tokens for the state plus the longest question.
  imajev    http://127.0.0.1:8765, no key, no model. The server accepts a
            32 KB record (about 8k tokens).
  custom    baseUrl required; model and key optional.
"""

# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import argparse  # noqa: E402 — after the guard on purpose
import hashlib
import ipaddress
import json
import math
import re
import stat
import threading
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

PRESETS = {
    "typesafe": {"base_url": "https://api.typesafe.ai", "model": "jev-1.13.0",
                 "key_env": "TYPESAFE_API_KEY", "key_required": True, "cap": 28000},
    "imajev": {"base_url": "http://127.0.0.1:8765", "model": "",
               "key_env": "", "key_required": False, "cap": 7000},
    "custom": {"base_url": "", "model": "", "key_env": "", "key_required": False, "cap": 7000},
}
MODES = ("off", "shadow", "on")
TYPES = ("noul", "choice", "score")
MAX_BODY = 4 * 1024 * 1024
# How far one value a provider sends may be from the exact one: TypeSafe
# rounds to two decimals, so by half of 0.01. A sum of n such values is off by
# up to n times this. Rounding keeps the order of values, so it never makes the
# chosen option less probable than another.
ROUNDING = 0.005


class NoAnswer(Exception):
    def __init__(self, reason, detail=""):
        super().__init__(reason)
        self.reason = reason
        self.detail = detail


def printable(s, cap=300):
    """s as one line of stderr: a line break becomes a space (YAML's error
    messages span lines) and any other control character, lone surrogate or
    line or paragraph separator (from a key, an id or a file) is escaped, so
    no text can start another line; s is cut at cap characters."""
    s = " ".join(s.splitlines())
    s = "".join(("\\x%02x" % ord(c) if ord(c) < 0x100 else "\\u%04x" % ord(c))
                if unicodedata.category(c) in ("Cc", "Cs", "Zl", "Zp") else c for c in s)
    return s if len(s) <= cap else s[:cap] + "..."


def warn(msg):
    sys.stderr.write("flow-s1: WARN: " + printable(msg) + "\n")


def url_shown(url):
    """A baseUrl for a warning. One that holds "@" may hold a password,
    which can itself hold "/", "?" or "#", so no part of it is shown."""
    if "@" in url:
        return "(a URL holding @, not shown: it may hold a password)"
    return show(url)


def open_regular(path):
    """The file at path opened for reading, or None when it is not a regular
    file. O_NONBLOCK: opening a FIFO would otherwise wait for a writer before
    anything could check what it is. A symlink is followed, as flow-s1.sh's
    own check follows it."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        return None
    return os.fdopen(fd, "rb")


def show(v, cap=80):
    """repr(v) for a message, or its type name where repr fails (an integer
    of more than 4300 digits on Python 3.11 and later), cut at cap."""
    try:
        s = repr(v)
    except Exception:  # noqa: BLE001 — a message must never raise
        return "a value of type %s" % type(v).__name__
    return s if len(s) <= cap else s[:cap] + "..."


def is_number(v):
    # math.isfinite would convert an int to a float, which fails for one too
    # large; an int is finite, and range checks compare it exactly.
    if isinstance(v, bool):
        return False
    return isinstance(v, int) or (isinstance(v, float) and math.isfinite(v))


def prob(v):
    return is_number(v) and 0.0 <= v <= 1.0


# ----------------------------------------------------------------- settings

def check_settings(a):
    """Provider, address, key and limits. Returns a dict the request uses."""
    if a.provider not in PRESETS:
        warn("systemOne.provider must be none, typesafe, imajev or custom (got %r)" % a.provider)
        raise NoAnswer("invalid-settings")
    p = PRESETS[a.provider]
    base = str(a.base_url or p["base_url"])
    if not base:
        warn("systemOne.baseUrl is required for provider %s" % a.provider)
        raise NoAnswer("invalid-settings")
    try:
        u = urllib.parse.urlsplit(base)
        u.port  # a port that is not a number or is out of range raises here
    except ValueError as e:
        # urllib's message can quote the URL's text, a password included.
        warn("systemOne.baseUrl cannot be parsed%s: %s" % ("" if "@" in base else " (%s)" % e, url_shown(base)))
        raise NoAnswer("invalid-settings")
    if u.scheme not in ("https", "http") or not u.hostname:
        warn("systemOne.baseUrl must be an http(s) URL (got %s)" % url_shown(base))
        raise NoAnswer("invalid-settings")
    # The request goes to <baseUrl>/v1/systemone: a user and password, a
    # query or a fragment would change where it goes or what it sends.
    if "@" in u.netloc or u.query or u.fragment or "?" in base or "#" in base:
        warn("systemOne.baseUrl must not hold a user and password, a query or a fragment: %s" % url_shown(base))
        raise NoAnswer("invalid-settings")
    # The request line and the Host header carry ASCII only: urllib sends
    # the host as written, not in its IDNA form, so a host outside ASCII must
    # be written in its xn-- form.
    if any(c.isspace() or unicodedata.category(c) == "Cc" or ord(c) > 127 for c in base):
        warn("systemOne.baseUrl holds a space, a control character, or a character outside ASCII "
             "(write a host outside ASCII in its xn-- form): %s" % url_shown(base))
        raise NoAnswer("invalid-settings")
    if u.scheme == "http" and not is_loopback(u.hostname):
        # The key and the state would cross the network unencrypted.
        warn("systemOne.baseUrl uses plain http for a host that is not this machine; use https")
        raise NoAnswer("insecure-url")

    key_env = str(a.api_key_env or p["key_env"])
    key = ""
    if key_env:
        if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", key_env):
            warn("systemOne.apiKeyEnv must be an environment variable name like TYPESAFE_API_KEY")
            raise NoAnswer("invalid-settings")
        key = os.environ.get(key_env, "")
    # The key goes in a header, which carries Latin-1 on one line; never print it.
    try:
        key.encode("latin-1")
        sendable = "\r" not in key and "\n" not in key
    except UnicodeEncodeError:
        sendable = False
    if not sendable:
        warn("the key in $%s holds a character a request header cannot carry" % key_env)
        raise NoAnswer("invalid-settings")
    if p["key_required"] and not key:
        warn("provider %s needs a key in $%s" % (a.provider, key_env))
        raise NoAnswer("no-api-key")

    try:
        timeout_ms = int(a.timeout_ms)
    except ValueError:
        warn("systemOne.timeoutMs is not a number; using 3000")
        timeout_ms = 3000
    timeout_ms = min(max(timeout_ms, 200), 30000)
    try:
        cap = int(a.state_token_cap)
    except ValueError:
        cap = 0
    if cap <= 0:
        cap = int(p["cap"])
    model = a.model or p["model"]
    if model and not clean(model):
        warn("systemOne.model must be plain text (got %s)" % show(model))
        raise NoAnswer("invalid-settings")
    return {"url": base.rstrip("/") + "/v1/systemone", "model": model,
            "key": key, "timeout": timeout_ms / 1000.0, "cap": cap,
            "local": is_loopback(u.hostname)}


def is_loopback(host):
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


# ----------------------------------------------------------------- questions

# What TypeSafe's API takes for instructions, a noul's criteria, a choice
# option's description and a score level: text, an object or a list (and null
# for a choice option).
PART = (str, dict, list)


# The largest the questions may be once encoded. YAML aliases repeat what they
# name, so a short file can stand for a very large body.
QUESTIONS_MAX_BYTES = 1024 * 1024


def _path(link):
    """The text of a path kept as (parent link, piece) pairs."""
    pieces = []
    while link is not None:
        link, piece = link
        pieces.append(piece)
    return "".join(reversed(pieces))


def value_problem(questions):
    """The first value in the questions that is not sent as written, as a
    message, or None. JSON has objects with string keys, arrays, strings,
    numbers, booleans and null. A key YAML read as a number, a boolean or null
    would become a string, and a YAML ordered map or pairs (a tuple) an array,
    so both are refused; a date, a set or bytes cannot be sent at all. Every
    value is counted where it appears, repeats through aliases included, and
    the walk stops once the questions would be more than QUESTIONS_MAX_BYTES,
    so a value that contains itself stops it too. Each value on the stack
    keeps only a link to its parent, so the walk's memory grows with the
    number of values counted, not with their depth, and the count stops at
    the bound. This count is a lower bound (escapes make text
    longer); the encoded size is checked after. Whether the encoder takes the
    rest (.inf, a lone surrogate, a long integer, deep nesting) is decided
    where the request is encoded."""
    stack = [(q, (None, "question %s" % qid)) for qid, q in questions.items()]
    size = 0
    while stack:
        x, link = stack.pop()
        # The smallest each value encodes to, so the count never exceeds
        # what is sent: a string with its quotes, null or true (4), a float
        # (0.5, 3), an integer (its decimal digits, which a bit length of b
        # gives at least (b - 1) * 3 // 10 + 1 of, and a minus sign), a list
        # its brackets and a ", " between elements, an object its braces and
        # each key with its quotes and ": ".
        if isinstance(x, str):
            size += len(x) + 2
        elif isinstance(x, bool) or x is None:
            size += 4
        elif isinstance(x, int):
            size += max(1, (x.bit_length() - 1) * 3 // 10 + 1) + (x < 0)
        elif isinstance(x, float):
            size += 3
        elif isinstance(x, dict):
            size += 2 + sum(len(k) + 4 if isinstance(k, str) else 4 for k in x)
            for k, y in x.items():
                if not isinstance(k, str):
                    return "%s has the key %s (read by YAML as %s), not a string; quote it" % (_path(link), show(k), type(k).__name__)
                stack.append((y, (link, "." + k)))
        elif isinstance(x, list):
            size += 2 + 2 * max(0, len(x) - 1)
            stack.extend((y, (link, "[%d]" % n)) for n, y in enumerate(x))
        elif isinstance(x, (tuple, set, frozenset)):
            # A container JSON has no form for; shown by its type, since its
            # repr could be as large as whatever it holds.
            return "%s is a YAML ordered map, pairs or set (read by YAML as %s), which is not sent as written" % (_path(link), type(x).__name__)
        else:
            return "%s is %s (read by YAML as %s), which is not sent as written; quote it" % (_path(link), show(x), type(x).__name__)
        if size > QUESTIONS_MAX_BYTES:
            break
    if size > QUESTIONS_MAX_BYTES:
        return ("the questions would be more than %d bytes when sent (YAML aliases repeat what they name)"
                % QUESTIONS_MAX_BYTES)
    return None


def load_site(path, site):
    try:
        import yaml  # PyYAML is a Flow requirement; flow-s1.sh checks for it first.
    except ImportError:
        raise NoAnswer("python-missing", "PyYAML cannot be imported")
    # Any error reading or parsing the file is the file's fault. The checks
    # below work on what YAML built and must not raise; an error there is a
    # defect in the client and is reported as internal-error.
    try:
        f = open_regular(path)
        if f is None:
            raise NoAnswer("questions-invalid", "the questions file is not a regular file")
        with f:
            doc = yaml.safe_load(f.read().decode("utf-8")) or {}
    except NoAnswer:
        raise
    except Exception as e:  # noqa: BLE001
        raise NoAnswer("questions-invalid", "cannot read the questions file: %s: %s" % (type(e).__name__, e))
    sites = doc.get("sites") if isinstance(doc, dict) else None
    if not isinstance(sites, dict):
        raise NoAnswer("questions-invalid", "no sites mapping")
    entry = sites.get(site)
    if entry is None:
        raise NoAnswer("unknown-site")
    questions = entry.get("questions") if isinstance(entry, dict) else None
    thresholds = entry.get("thresholds") if isinstance(entry, dict) else None
    if not isinstance(questions, dict) or not questions or not isinstance(thresholds, dict):
        raise NoAnswer("questions-invalid", "site %s needs questions and thresholds" % site)
    for qid, q in questions.items():
        if not isinstance(qid, str):
            # YAML reads 1, yes, 1.5 and ~ as a number, a boolean or null. Sent
            # as JSON they become "1", "true", "1.5" or "null", and the reply's
            # answer, keyed by that string, is never found by the value YAML
            # read. 1 and yes are even one key to Python (True == 1).
            raise NoAnswer("questions-invalid", "question id %s (read by YAML as %s) is not a string; quote it"
                           % (show(qid), type(qid).__name__))
        if not isinstance(q, dict) or q.get("type") not in TYPES:
            raise NoAnswer("questions-invalid", "question %s needs a type: noul, choice or score" % qid)
        # YAML reads unquoted yes, no, on, off, ~, numbers and dates as other
        # types, so text written that way would not be sent as written.
        if not isinstance(q.get("instructions"), PART) or not q["instructions"]:
            raise NoAnswer("questions-invalid", "question %s needs instructions: text, an object or a list; quote yes, no, numbers and dates" % qid)
        crit = q.get("criteria")
        if q["type"] == "noul" and "criteria" in q and not (
                isinstance(crit, dict) and set(crit) == {"true", "false"}
                and all(isinstance(v, PART) for v in crit.values())):
            raise NoAnswer("questions-invalid", 'noul %s: criteria are optional, and describe "true" and "false" (quoted) as text, an object or a list' % qid)
        if q["type"] == "choice" and not (isinstance(crit, dict) and crit):
            raise NoAnswer("questions-invalid", "choice %s needs its options as criteria" % qid)
        if q["type"] == "choice" and not all(isinstance(k, str) for k in crit):
            # YAML reads yes, no, on, off, 1, 2 as booleans or numbers; sent as
            # JSON they become "true" or "1", and no answer could match them.
            raise NoAnswer("questions-invalid", "choice %s has option names that are not strings; quote them" % qid)
        if q["type"] == "choice" and not all(v is None or isinstance(v, PART) for v in crit.values()):
            raise NoAnswer("questions-invalid", "choice %s describes an option with something other than text, an object, a list or null; quote yes, no, numbers and dates" % qid)
        if q["type"] == "score" and not (isinstance(crit, list) and 2 <= len(crit) <= 10):
            raise NoAnswer("questions-invalid", "score %s needs 2 to 10 levels as criteria" % qid)
        if q["type"] == "score" and not all(isinstance(v, PART) for v in crit):
            raise NoAnswer("questions-invalid", "score %s has a level that is not text, an object or a list; quote yes, no, numbers and dates" % qid)
        t = thresholds.get(qid)
        if t is None:
            raise NoAnswer("no-threshold", "question %s" % qid)
        models = t.get("models", {}) if isinstance(t, dict) else None
        if not isinstance(t, dict) or not prob(t.get("default")) or not isinstance(models, dict) \
                or not all(prob(v) for v in models.values()):
            raise NoAnswer("questions-invalid", "threshold for %s must be {default: 0..1, models: {id: 0..1}}" % qid)
        # A model id is compared with the one the reply names, a string; a key
        # YAML reads as a number (1.13) would never match and silently leave
        # the default in force.
        for key in models:
            if not isinstance(key, str):
                raise NoAnswer("questions-invalid", "threshold for %s names model %s (read by YAML as %s), not a string; quote it"
                               % (qid, show(key), type(key).__name__))
    problem = value_problem(questions)
    if problem:
        raise NoAnswer("questions-invalid", problem)
    # The walk's count is a lower bound (an escaped character is longer
    # than one), and at most several times low, so the questions are encoded
    # once here to measure them. What cannot be encoded is named where the
    # request body is.
    try:
        encoded = len(encode({"questions": questions}))
    except (TypeError, ValueError, RecursionError):
        encoded = 0
    if encoded > QUESTIONS_MAX_BYTES:
        raise NoAnswer("questions-invalid", "the questions would be %d bytes when sent, more than %d"
                       % (encoded, QUESTIONS_MAX_BYTES))
    return questions, thresholds


# ----------------------------------------------------------------- state

def load_state(path, fmt, cap):
    """(state, truncated, sha256). The cap is in tokens, estimated as 4
    characters each; there is no tokenizer."""
    try:
        return _load_state(path, fmt, cap)
    except RecursionError:
        raise NoAnswer("state-invalid", "the JSON state is nested too deeply")


# The largest state file read. A larger one, whatever the cap, is
# state-too-large before it is read. Parsing JSON takes many times the file's
# size in memory, so a JSON state has a lower bound.
STATE_MAX_BYTES = 64 * 1024 * 1024
STATE_JSON_MAX_BYTES = 8 * 1024 * 1024


def _load_state(path, fmt, cap):
    # flow-s1.sh passes only a readable regular file; a direct run may not.
    # Any format other than text is read as JSON, here and below.
    try:
        f = open_regular(path)
    except OSError as e:
        raise NoAnswer("state-invalid", "the state file cannot be opened (%s)" % type(e).__name__)
    if f is None:
        raise NoAnswer("state-invalid", "the state file is not a regular file")
    with f:
        bound = STATE_MAX_BYTES if fmt == "text" else STATE_JSON_MAX_BYTES
        if os.fstat(f.fileno()).st_size > bound:
            raise NoAnswer("state-too-large", "the %s state file is larger than %d bytes"
                           % ("text" if fmt == "text" else "JSON", bound))
        raw = f.read()
    digest = hashlib.sha256(raw).hexdigest()
    text = raw.decode("utf-8", "replace")
    limit = cap * 4
    if fmt == "text":
        return (text[:limit], True, digest) if len(text) > limit else (text, False, digest)
    try:
        state = json.loads(text)
    except ValueError as e:
        raise NoAnswer("state-invalid", "the state file cannot be read as JSON: %s" % e)
    if size(state) <= limit:
        return state, False, digest
    # Cut every string longer than one common length, the largest length at
    # which the state fits: short strings keep their full text, and the work
    # is a sort and a few passes, not one pass per string.
    strings = []
    collect(state, strings)
    skeleton = size(replace_strings(state, lambda s: ""))
    if skeleton > limit:
        raise NoAnswer("state-too-large", "the state's structure alone is over the limit")
    # The size grows with the cut, so a binary search over the real serialized
    # size finds the largest cut that fits, whatever the escapes cost.
    lo, hi = 0, max((len(s) for s in strings), default=0)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if size(replace_strings(state, lambda s: s[:mid])) <= limit:
            lo = mid
        else:
            hi = mid - 1
    return replace_strings(state, lambda s: s[:lo]), True, digest


def size(v):
    return len(json.dumps(v, ensure_ascii=False))


def collect(v, out):
    if isinstance(v, str):
        out.append(v)
    elif isinstance(v, dict):
        for c in v.values():
            collect(c, out)
    elif isinstance(v, list):
        for c in v:
            collect(c, out)


def replace_strings(v, f):
    if isinstance(v, str):
        return f(v)
    if isinstance(v, dict):
        return {k: replace_strings(c, f) for k, c in v.items()}
    if isinstance(v, list):
        return [replace_strings(c, f) for c in v]
    return v



# ----------------------------------------------------------------- request

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    # The default handler follows 301/302/303 as a GET and carries the
    # Authorization header to wherever Location points. Nothing is followed.
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def encode(v):
    return json.dumps(v, ensure_ascii=False, allow_nan=False).encode("utf-8")


def encode_body(body):
    """The request body as it is sent. What JSON or UTF-8 cannot hold, or
    what this interpreter's encoder will not nest that deep, is blamed on the
    part that cannot be encoded on its own, in the same place and wrapped the
    same way, so a question at the encoder's depth limit is judged at the
    depth it is sent."""
    try:
        return encode(body)
    except (TypeError, ValueError, RecursionError):
        pass
    for part, reason in (("questions", "questions-invalid"), ("state", "state-invalid")):
        try:
            encode({part: body[part]})
        except (TypeError, ValueError, RecursionError) as e:
            raise NoAnswer(reason, "the %s cannot be sent as JSON: %s" % (part, e))
    # The model id, the body's other part, is plain text by check_settings,
    # so the body fails only if one of the parts above does; this line
    # re-raises the original error if that ever changes.
    return encode(body)


def post(cfg, data):
    """The reply as a dict. One request; the timeout covers all of it, not
    each socket read, so a server that sends one byte at a time cannot hold
    the caller."""
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if cfg["key"]:
        headers["Authorization"] = "Bearer " + cfg["key"]
    req = urllib.request.Request(cfg["url"], data=data, headers=headers, method="POST")
    handlers = [_NoRedirect()]
    if cfg["local"]:
        # A server on this machine is reached directly. Through an HTTP_PROXY
        # the key and the state would leave the machine, in plain text.
        handlers.append(urllib.request.ProxyHandler({}))
    opener = urllib.request.build_opener(*handlers)
    result = {}

    def run():
        try:
            with opener.open(req, timeout=cfg["timeout"]) as r:
                result["status"] = r.status
                result["body"] = r.read(MAX_BODY + 1)
        except urllib.error.HTTPError as e:
            result["status"] = e.code
        except Exception as e:  # noqa: BLE001 — every failure is a reason
            result["error"] = e

    t = threading.Thread(target=run, daemon=True)
    t.start()
    t.join(cfg["timeout"])
    if t.is_alive():
        raise NoAnswer("timeout")
    if "error" in result:
        e = result["error"]
        reason = getattr(e, "reason", None)
        if isinstance(e, TimeoutError) or isinstance(reason, TimeoutError):
            raise NoAnswer("timeout")
        raise NoAnswer("connection", type(e).__name__)
    status = result["status"]
    if 300 <= status < 400:
        raise NoAnswer("redirect")
    if status != 200:
        raise NoAnswer("http-%d" % status)
    if len(result["body"]) > MAX_BODY:
        raise NoAnswer("malformed", "reply larger than %d bytes" % MAX_BODY)
    try:
        reply = json.loads(result["body"].decode("utf-8"))
    except (ValueError, RecursionError):
        raise NoAnswer("malformed", "reply is not JSON, or is nested too deeply")
    if not isinstance(reply, dict) or not isinstance(reply.get("answers"), dict):
        raise NoAnswer("malformed", "reply has no answers object")
    return reply


# ----------------------------------------------------------------- answers

def clean(s):
    """A string from the server that may be printed or recorded: no control
    character and no line or paragraph separator, which would split the one
    JSON line a caller reads into two."""
    return isinstance(s, str) and not any(unicodedata.category(c) in ("Cc", "Cs", "Zl", "Zp") for c in s)


def distribution_confidence(probs):
    """TypeSafe's documented confidence for a distribution over n options:
    (n * largest - 1) / (n - 1). For a noul (n = 2) it is |2p - 1|."""
    n = len(probs)
    if n < 2:
        return 1.0
    return min(1.0, max(0.0, (n * max(probs) - 1) / (n - 1)))


def normalize(qid, q, a):
    """(normalized answer, None) or (None, reason)."""
    if a is None:
        return None, "missing-answer"
    if not isinstance(a, dict) or a.get("type") != q["type"]:
        return None, "malformed"
    # imajev's abstained is true or false; null counts as absent, and any other
    # value (the string "true", 1, 0) makes the answer malformed.
    abstained = a.get("abstained")
    if abstained is not None and not isinstance(abstained, bool):
        return None, "malformed"
    if abstained:
        return None, "abstained"
    t = q["type"]
    if t == "noul":
        p = a.get("noul")
        if not prob(p):
            return None, "malformed"
        p = float(p)
        out = {"type": "noul", "p": p, "confidence": round(abs(2 * p - 1), 6)}
    else:
        probs = a.get("probabilities")
        if not isinstance(probs, dict) or not probs or not all(prob(v) for v in probs.values()) \
                or not all(clean(k) for k in probs):
            return None, "malformed"
        # The answer must be about the question that was asked, and agree with
        # itself as the TypeSafe API defines it: a probability for every option
        # (every level, keyed "0", "1", ...), summing to 1; the choice is the
        # most probable option; the score is each level times its probability,
        # added up. Providers round what they send (TypeSafe to two decimals),
        # so the sum and the score allow ROUNDING for every rounded value they
        # combine; the choice needs none, as rounding keeps the order.
        if t == "choice":
            allowed = set(q["criteria"])
        else:
            allowed = {str(i) for i in range(len(q["criteria"]))}
        if set(probs) != allowed:
            return None, "malformed"
        n = len(probs)
        if abs(sum(float(v) for v in probs.values()) - 1) > ROUNDING * n + 1e-9:
            return None, "malformed"
        # The provider's confidence when it sends one; TypeSafe's formula only
        # when the field is absent (null counts as absent, as for the model
        # id). A confidence that is not a number from 0 to 1 is not replaced.
        conf = a.get("confidence")
        if conf is None:
            conf = distribution_confidence([float(v) for v in probs.values()])
        elif prob(conf):
            conf = float(conf)
        else:
            return None, "malformed"
        if t == "choice":
            choice = a.get("choice")
            if not isinstance(choice, str) or choice not in probs \
                    or float(probs[choice]) < max(float(v) for v in probs.values()):
                return None, "malformed"
            out = {"type": "choice", "choice": choice, "probabilities": probs,
                   "confidence": round(conf, 6)}
        else:
            score = a.get("score")
            if not is_number(score) or not 0 <= score <= n - 1:
                return None, "malformed"
            expected = sum(int(k) * float(v) for k, v in probs.items())
            if abs(score - expected) > ROUNDING * (1 + n * (n - 1) / 2) + 1e-9:
                return None, "malformed"
            out = {"type": "score", "score": score, "probabilities": probs,
                   "confidence": round(conf, 6)}
    # unknown_probability is imajev's: copied when it is a probability, absent
    # when it is missing or null, and any other value makes the answer
    # malformed, as an invalid confidence does.
    unknown = a.get("unknown_probability")
    if unknown is not None:
        if not prob(unknown):
            return None, "malformed"
        out["unknown_probability"] = unknown
    return out, None


def threshold_for(t, model):
    return t.get("models", {}).get(model, t["default"])


# ----------------------------------------------------------------- records

def record_path(a):
    """Where records go, or None when the path is not safe to write."""
    if a.run_id:
        parts = [os.path.join(a.repo_top, ".flow"), os.path.join(a.repo_top, ".flow", "runs"),
                 os.path.join(a.repo_top, ".flow", "runs", a.run_id)]
        if os.path.lexists(parts[-1]):
            for p in parts:
                if os.path.islink(p) or not os.path.isdir(p):
                    warn("not writing records: %s is a symlink or not a directory" % p)
                    return None
            return os.path.join(parts[-1], "system-one.jsonl")
    d = a.state_dir
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
    except OSError as e:
        warn("not writing records: cannot create %s: %s" % (d, e))
        return None
    if os.path.islink(d) or not stat.S_ISDIR(os.lstat(d).st_mode):
        warn("not writing records: %s is a symlink or not a directory" % d)
        return None
    return os.path.join(d, "system-one.jsonl")


def write_records(a, cfg, model, results, digest):
    """Best effort: whatever goes wrong writing records is a warning, and the
    call's answer, or its reason for none, stands."""
    try:
        _write_records(a, cfg, model, results, digest)
    except Exception as e:  # noqa: BLE001
        warn("not writing records: %s" % type(e).__name__)


def _write_records(a, cfg, model, results, digest):
    path = record_path(a)
    if path is None:
        return
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        from _journal_atomic import append_jsonl, JournalAtomicError
    except ImportError as e:
        warn("not writing records: %s" % e)
        return
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for qid, (answer, result) in results.items():
        rec = {"ts": ts, "site": a.site, "question": qid, "mode": a.mode, "provider": a.provider,
               "model": model, "result": result, "answer": answer,
               "current": a.current or None, "state_sha256": digest}
        try:
            append_jsonl(path, rec)
        except (JournalAtomicError, OSError, ValueError) as e:
            warn("not writing records: %s" % type(e).__name__)
            return


# ----------------------------------------------------------------- main

def ask(a):
    mode = a.mode
    if mode not in MODES:
        warn("systemOne.uses[%r] must be off, shadow or on (got %r); treating it as off" % (a.site, mode))
        mode = "off"
    a.mode = mode
    if mode == "off":
        raise NoAnswer("mode-off")
    cfg = check_settings(a)
    questions, thresholds = load_site(a.questions, a.site)
    state, truncated, digest = load_state(a.state_file, a.state_format, cfg["cap"])

    body = {"state": state, "questions": questions}
    if cfg["model"]:
        body["model"] = cfg["model"]
    data = encode_body(body)
    try:
        reply = post(cfg, data)
    except NoAnswer as e:
        write_records(a, cfg, cfg["model"], {q: (None, e.reason) for q in questions}, digest)
        raise
    # A reply without a model id is answered by the configured model; one that
    # is not a plain string cannot be recorded or printed.
    model = reply.get("model")
    if model is None:
        model = cfg["model"]
    if not clean(model):
        write_records(a, cfg, cfg["model"], {q: (None, "malformed") for q in questions}, digest)
        raise NoAnswer("malformed", "the reply's model id is not a plain string")

    results, answers, first_failure = {}, {}, None
    for qid, q in questions.items():
        out, reason = normalize(qid, q, reply["answers"].get(qid))
        if out is not None and out["confidence"] < threshold_for(thresholds[qid], model):
            reason = "below-threshold"
        results[qid] = (out, reason or "answered")
        if reason and first_failure is None:
            first_failure = reason
        answers[qid] = out
    write_records(a, cfg, model, results, digest)
    if first_failure:
        raise NoAnswer(first_failure)
    if mode == "shadow":
        raise NoAnswer("shadow")
    return {"site": a.site, "provider": a.provider, "model": model,
            "truncated": truncated, "answers": answers}


def main():
    ap = argparse.ArgumentParser()
    for name in ("site", "state-file", "state-format", "current", "run-id", "provider",
                 "base-url", "model", "api-key-env", "timeout-ms", "state-token-cap", "mode",
                 "questions", "repo-top", "state-dir"):
        ap.add_argument("--" + name, default="")
    a = ap.parse_args()
    # A byte that is not UTF-8 arrives as a lone surrogate, which no record
    # can hold; it is replaced so the record is written.
    a.current = a.current.encode("utf-8", "replace").decode("utf-8")
    try:
        out = ask(a)
    except NoAnswer as e:
        sys.stderr.write("flow-s1: no answer: %s%s\n" % (e.reason, " (%s)" % printable(e.detail) if e.detail else ""))
        return 3
    except Exception as e:  # noqa: BLE001 — the caller must get "no answer", never a traceback
        sys.stderr.write("flow-s1: no answer: internal-error (%s)\n" % type(e).__name__)
        return 3
    sys.stdout.write(json.dumps(out, ensure_ascii=True, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
