"""The factory's test entry point (E): runs the engine's own main with a seam
of fixture inputs registered.

Usage:
  engine_under_test.py --plugin <plugin dir> --fixtures <file.json> <subcommand> [args]

The shipped wrapper cannot reach this file: it lives under tests/, which a
plugin install does not carry, and nothing under the plugin's bin/, hooks/ or
commands/ names it (tests/e2e-factory-engine-seam.test.sh checks that). It
reads nothing from the environment; the fixture comes only from --fixtures.

The fixture is a JSON object with at most these keys (plan 2.11):
  unbuilt          {"<job key or *>": {fact: bool}}, unbuilt facts only
  default_unbuilt  bool, the value of every unbuilt fact the fixture does not name
  derived_inputs   {"confirm_keys": [write kinds], "prepush_fails": bool}
  built_inputs     {"group_gone": bool, "unvouched_session_action": bool}
  bodies           {"<kind>:<stage>": outcome}
Any other key, or a fact under unbuilt or built_inputs that the seam may not
give, prints SEAM_REFUSED=<name> provider=<built|derived|unknown_key> and
exits 2 before main runs. A fixture that cannot be read, is not JSON or has
a value of the wrong shape prints one line on stderr and exits 2.

While main runs, a decision Blocked because the seam gives no value for an
unbuilt fact the pair reads writes SEAM_MISSING=<fact> state=<s> event=<e>
to stderr. Creation row 1 has no from state, so its line says state=none.
"""

# The guard below must stay verbatim (tests/syspath-guard.test.sh matches it)
# and must run before the other imports, so ruff's rules on one import per
# line and imports at the top do not apply to this file.
# ruff: noqa: E401, E402
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import argparse
import json

PROG = "engine_under_test.py"
SEAM_KEYS = ("unbuilt", "default_unbuilt", "derived_inputs", "built_inputs", "bodies")


def _usage_error(message):
    sys.stderr.write("%s: %s\n" % (PROG, message))
    return 2


def _load_fixture(path):
    """The fixture object, or a string saying why it cannot be used."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except OSError as e:
        return "cannot read the fixture %s: %s" % (path, e.strerror or e)
    except ValueError as e:
        return "the fixture %s is not JSON: %s" % (path, e)
    if not isinstance(data, dict):
        return "the fixture %s is not a JSON object" % path
    return data


def _report_missing(table_module):
    """Wrap choose and choose_creation so a Blocked decision whose fact the
    seam gives no value for writes the SEAM_MISSING line. The wrappers replace
    the module's attributes before main imports any engine module, so a later
    `from _flow_factory_table import choose` and the module's own calls get
    them too."""
    choose, choose_creation = table_module.choose, table_module.choose_creation

    def missing(decision, state, event):
        if isinstance(decision, table_module.Blocked) and decision.missing:
            sys.stderr.write("SEAM_MISSING=%s state=%s event=%s\n" % (decision.fact, state, event))
            sys.stderr.flush()
        return decision

    def choose_reporting(table, job, event, ctx):
        return missing(choose(table, job, event, ctx), job.get("state"), event)

    def choose_creation_reporting(table, key, ctx):
        return missing(choose_creation(table, key, ctx), "none", table.creation[0].get("event"))

    table_module.choose = choose_reporting
    table_module.choose_creation = choose_creation_reporting


def run(argv):
    parser = argparse.ArgumentParser(prog=PROG)
    parser.add_argument("--plugin", required=True)
    parser.add_argument("--fixtures", required=True)
    parser.add_argument("rest", nargs=argparse.REMAINDER)
    a = parser.parse_args(argv)
    if not a.rest:
        return _usage_error("no subcommand")

    # The engine comes from --plugin's bin/ and from nowhere else: this file's
    # own folder (the test fixtures) leaves sys.path, and bin/ goes first.
    here = os.path.dirname(os.path.realpath(__file__))
    bin_dir = os.path.realpath(os.path.join(a.plugin, "bin"))
    if not os.path.isfile(os.path.join(bin_dir, "_flow_factory.py")):
        return _usage_error("no bin/_flow_factory.py under --plugin %s" % a.plugin)
    sys.path[:] = [bin_dir] + [p for p in sys.path if os.path.realpath(p) not in (here, bin_dir)]

    fixture = _load_fixture(a.fixtures)
    if not isinstance(fixture, dict):
        return _usage_error(fixture)
    unknown = sorted(k for k in fixture if k not in SEAM_KEYS)
    if unknown:
        print("SEAM_REFUSED=%s provider=unknown_key" % unknown[0])
        return 2

    import _flow_factory
    import _flow_factory_table
    for m in (_flow_factory, _flow_factory_table):
        if os.path.dirname(os.path.realpath(m.__file__)) != bin_dir:
            return _usage_error("%s loaded from %s, not from %s" % (m.__name__, m.__file__, bin_dir))
    # One copy of _flow_factory for every engine module (plan 2.7's identity
    # rule): imported by name here, it is already the entry under that name.
    sys.modules["_flow_factory"] = _flow_factory

    try:
        _flow_factory_table.set_seam(fixture)
    except _flow_factory_table.SeamRefused as r:
        print(r.line)
        return 2
    except ValueError as e:
        return _usage_error("the fixture %s: %s" % (a.fixtures, e))
    _report_missing(_flow_factory_table)

    return _flow_factory.main(list(a.rest))


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
