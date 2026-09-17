"""Read a decision journal's artifact manifest, for the commands that report on it.

`commands/address.md` (DISPUTED_ARRAY_BLOCK) builds the `DISPUTED:[...]` array
of a resolution marker from the `finding-dismissed` artifacts; `commands/learn.md`
(DISMISSAL_ARTIFACTS_BLOCK) counts the same artifacts across every journal in the
project. Both used to carry their own copy of this reader.

The copies drifted, three review rounds running, and each round found the one the
previous sweep had missed: one gained O_NONBLOCK and the other kept blocking on a
FIFO forever; one called an empty first fence damage and the other counted it as
zero; and both accepted a fence shape `bin/_journal_atomic.py` refuses, so a
journal that every WRITE treats as having no manifest was read here as a complete
one — a confident, short answer, which is the exact defect this issue exists to
remove. A reader kept in step with the writer by hand is that defect's source,
not its symptom, so the fence predicate is now the writer's own function.

Everything here raises ManifestError rather than returning a sentinel. A row that
cannot be placed is not a row that belongs elsewhere, and dropping it yields the
partial answer both callers refuse.
"""

import sys

# The pull request under review is checked out around these calls, so its author
# controls the working directory: `gh pr checkout` has already filled the tree
# with fork content by the time either command runs. Drop CWD from the import
# path before importing anything that is not built in — a `./yaml.py` would
# otherwise execute. PYTHONSAFEPATH does this from Python 3.11; this line does it
# everywhere, and it must sit ABOVE the imports below rather than after them.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

import errno
import os
import re
import stat

import yaml

from _journal_atomic import JournalAtomicError, parse_frontmatter


class ManifestError(Exception):
    """Raised only by this module, always with a message this module wrote.

    Everything a parse produces is derived from the file, and the file is
    author-controlled on a fork pull request: yaml raises a plain ValueError out
    of its typed-scalar constructors, UnicodeDecodeError is a ValueError
    subclass, and an explicit tag such as !!bool raises KeyError or
    AttributeError carrying the whole scalar. Callers print a ManifestError
    verbatim (through one_line) and print only the class name for anything else.
    """


class NoAliases(yaml.SafeLoader):
    """A journal manifest is a record, not a program.

    `yaml.safe_load` resolves aliases and shares the expansion in memory, but
    `str()` materialises it: a few hundred bytes of nested aliases becomes
    megabytes on one line, and each further level multiplies it. Nothing flow
    writes uses an alias, so refusing them costs nothing.
    """

    def compose_node(self, parent, index):
        if self.check_event(yaml.events.AliasEvent):
            # ManifestError, not YAMLError: this message is ours, and the
            # callers print only a class name for anything derived from the
            # file. It travels out through parse_frontmatter untouched, which
            # catches yaml.YAMLError only.
            raise ManifestError("the manifest uses YAML aliases, which a manifest does not need")
        return super(NoAliases, self).compose_node(parent, index)


# The keys references/finding-ledger-parser.md greps for, plus address.md's own
# DISPUTED_REASON_CODE. Longest first, so a prefix never shadows a longer token.
MARKER_TOKENS = ("DISPUTED_REASON_CODE", "ESCALATED", "DISPUTED", "RESOLVED")

# The longest finding id the writer records and this reader will place in an
# array. Both sides check it; neither invents its own. FINDINGS is deliberately
# absent from MARKER_TOKENS above: references/finding-ledger-parser.md reads
# that array from REVIEW BODIES only, never from the issue comments these two
# blocks write, and escaping a token no consumer looks for here would be a
# guard no test could tell from its own absence.
MAX_FINDING_ID = 64


def one_line(v):
    """Flatten a value to one printable line that cannot forge a ledger marker.

    Both callers print these strings on stdout in the same place an array or a
    count would appear, and the journal, the artifact fields and the configured
    `journal.dir` are all author-controlled on a fork pull request:
    `.claude/settings.flow.json` is a tracked file. Newlines go first, so no
    payload can open a second `KEY=value` line.

    The escape is LOWERCASE and applied ONCE. `%3D` ends in `D`, so escaping
    `RESOLVED=` inside `RESOLVED=ISPUTED:[X]` produced `RESOLVED%3DISPUTED:[X]`
    — the replacement supplied the leading `D` and assembled the exact token the
    escape exists to remove. Iterating to a fixed point only moved the boundary
    rather than removing it: a payload carrying one `ISPUTED=` layer per pass
    walked through a ten-pass cap and shipped its last layer live. `%3d` ends in
    a lowercase `d` and no token begins with one, so a replacement can never
    contribute a character to a match, and one pass is a fixed point by
    construction rather than by counting.

    A fail-closed post-check — re-scan the result and drop the whole string if a
    token survived — was written here and removed again. It could not fire: the
    only tokens it scanned for were the ones this loop had just escaped, so it
    restated the loop rather than checking it, and no test could distinguish its
    presence from its absence. An unreachable guard carrying a confident comment
    is the shape of defect this file exists to stop repeating. Adding a token to
    MARKER_TOKENS adds its escape in the same line, which is the property that
    actually keeps this closed.
    """
    out = " ".join(str(v).splitlines()).strip()[:200]
    for tok in MARKER_TOKENS:
        out = out.replace(tok + "=", tok + "%3d").replace(tok + ":", tok + "%3a")
    return out


def read_text(path):
    """Return the journal's text, refusing anything that is not a plain file.

    The messages name the fault, not the file. Callers name the file: commands/learn.md
    prints `JOURNAL_UNREADABLE=<path> — <reason>` while iterating a directory, and
    commands/address.md has one journal and says so in its REASON. Embedding the path
    here as well printed it twice on the learn side.
    """
    try:
        # O_NOFOLLOW, because bin/journal-record.sh refuses a symlinked journal
        # for exactly this reason: a pre-staged .decisions/issue-N.md pointing at
        # a private key would otherwise be opened and its bytes echoed in a parse
        # error.
        #
        # This guards the FINAL component only. A symlinked .decisions DIRECTORY
        # is still followed — deliberately, because journal-record.sh follows it
        # too on the write side, and a reader that refused what the writer
        # accepts is the disagreement this module exists to remove.
        #
        # O_NONBLOCK so a FIFO left at this path cannot hang the read waiting for
        # a writer that never comes; the fstat below then refuses it. Without
        # both, /flow:learn hung with no output at all on a journal directory
        # holding one — worse than any wrong answer it could have given.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as exc:
        if exc.errno in (errno.ELOOP, errno.EMLINK):
            raise ManifestError("the journal is a symlink, and a symlinked journal is refused")
        raise ManifestError("the journal could not be opened (%s)"
                            % errno.errorcode.get(exc.errno, "OSError"))
    with os.fdopen(fd, "r", encoding="utf-8") as fh:
        if not stat.S_ISREG(os.fstat(fh.fileno()).st_mode):
            raise ManifestError("the journal is not a regular file")
        return fh.read()


def read_artifacts(path):
    """Return the artifacts list, or [] when the record holds nothing.

    Exactly one shape is a real absence: a journal that EXISTS and has no
    frontmatter at all. bin/_journal_atomic.py prepends a manifest on the first
    write, so a file without one has had nothing recorded in it. 9 of this
    repository's own 41 journals are in that shape, and reporting them as
    unreadable stopped the resolution comment /flow:address calls mandatory.

    Everything else is an unknown and raises. A journal that is not there is NOT
    an absence: it is indistinguishable from reading the wrong path (a relative
    .decisions resolved from a subdirectory) or from a journal that vanished
    between the write and this read.

    The fence predicate is bin/_journal_atomic.parse_frontmatter — the writer's
    own function, not a second regex that agrees with it by inspection. The
    hand-written one accepted `---` followed by trailing whitespace where the
    writer requires exactly `---\\n`, so a journal opening `--- ` had no manifest
    as far as every write was concerned (journal-record.sh prepends a fresh one
    and keeps the old text as body) while the reader parsed the old text as the
    whole truth.
    """
    text = read_text(path)
    try:
        manifest, _body = parse_frontmatter(text, loader=NoAliases)
    except JournalAtomicError:
        # str() on this can quote the file: its invalid-YAML branch interpolates
        # PyYAML's Mark snippet, which carries the offending line verbatim. This
        # reason is printed onward, so it never goes out. Tell the two shapes
        # apart with the writer's own closing-fence test and say it in our words.
        if text.find("\n---\n", 4) == -1:
            raise ManifestError("the manifest fence does not open and close at the top of the file")
        # Everything else parse_frontmatter refuses behind a closing fence:
        # invalid YAML, and a fence that parses to a blank, comment-only, null,
        # or non-mapping value. One message covers both, deliberately — telling
        # them apart needs either a second parse (the duplicated predicate this
        # module exists to remove) or string-matching the writer's exception
        # text, and neither is worth a more specific sentence. journal-record.sh
        # refuses the file outright either way, so a reader calling it an empty
        # record accepts what the writer rejects. Damage, not absence.
        raise ManifestError("the manifest fence does not hold a YAML mapping, so it is not a manifest")
    if manifest is None:
        # No opening fence. Damage is told apart the way it always was: a
        # fence-shaped line PLUS a manifest key means a manifest that was
        # mangled. "`---` appears somewhere" is not damage on its own: a `---`
        # line is a markdown horizontal rule, and 33 of this repository's own 41
        # journals carry one. (A GFM table separator is `|---|`, which this
        # regex does not match at all; 23 of the 41 have one of those.)
        if re.search(r"(?m)^---[ \t]*$", text) and re.search(r"(?m)^artifacts:", text):
            raise ManifestError("the manifest fence does not start the file")
        return []
    arts = manifest.get("artifacts")
    if arts is None:
        return []
    if not isinstance(arts, list):
        raise ManifestError("artifacts is not a list")
    return arts


def pr_matches(a, pr):
    """Return True when artifact `a` records a dismissal on pull request `pr`."""
    pr_val = a.get("pr")
    if pr_val is None:
        # str(None) is "None", which compares unequal to every pull request
        # number and silently dropped the row. A dismissal that does not say
        # which pull request it belongs to cannot be placed, and leaving it out
        # is the partial array the caller refuses everywhere else.
        raise ManifestError("the journal records a dismissal with no pr field (finding id %s), so it "
                            "cannot be placed against a pull request" % one_line(a.get("finding_id")))
    # bool is an int subclass, so int(True) is 1 and `pr: yes` joined pull
    # request #1. A float truncates. Accept an int, or a string of digits for a
    # journal written by some other route — nothing else.
    if isinstance(pr_val, bool) or not (
        isinstance(pr_val, int) or (isinstance(pr_val, str) and re.match(r"[0-9]+\Z", pr_val))
    ):
        raise ManifestError("the journal records a dismissal whose pr field %s is not an integer, so "
                            "it cannot be placed against a pull request" % one_line(pr_val))
    try:
        return int(pr_val) == int(pr)
    except ValueError:
        # int() refuses a decimal string longer than
        # sys.get_int_max_str_digits() (4300 by default; the similarly-named
        # sys.int_info.str_digits_check_threshold is 640 and is the floor that
        # limit may be set to, not the limit). The
        # digit allowlist above admits any length, so this conversion is the one
        # place a validated value still raises; when it sat outside the caller's
        # handler the block died mid-run and printed a traceback beside a REASON
        # that blamed the wrapper.
        raise ManifestError("the journal records a dismissal whose pr field is %d digits long, which "
                            "is not a pull request number" % len(str(pr_val)))


def finding_id(a):
    """Return the artifact's finding id, refusing anything the ledger cannot carry."""
    fid = a.get("finding_id")
    # str() first would turn the YAML boolean `yes` into "True", which passes the
    # allowlist and lands an id in the array that matches no real finding.
    if not isinstance(fid, str):
        raise ManifestError("the journal records a dismissal whose finding id is %s, not a string; "
                            "refusing to build an array from it" % type(fid).__name__)
    # The journal is a tracked file any contributor can edit, and the array it
    # feeds is parsed by splitting on `,` and `]`. Re-validate on the way out
    # rather than trusting what the writer put in: a `]` truncates the
    # `grep -o 'DISPUTED:\[[^]]*\]'` the consumers extract with, silently
    # dropping the rest of the array, and a comma splits one id into two for the
    # `,`-delimited containment checks. The allowlist is the one
    # bin/flow-finding-route.sh, commands/status.md and
    # references/finding-ledger-parser.md all apply, so this refuses what they
    # would refuse instead of handing them a row they will drop.
    #
    # It is NOT about glob expansion: status.md's containment check writes the
    # id as `*",$ID,"*`, where the quotes make it a literal, and merge.md has no
    # glob at all — its gate is `comm` over sorted lists. One bad row refuses
    # the whole array: a partial array understates the disputes, which is the
    # failure this exists to prevent.
    if not re.match(r"[A-Za-z][A-Za-z0-9_-]*\Z", fid):
        raise ManifestError("the journal records a dismissal whose finding id %s does not match "
                            "[A-Za-z][A-Za-z0-9_-]*; refusing to build an array from it"
                            % one_line(fid[:MAX_FINDING_ID]))
    # Every other file-derived value this module prints is bounded; this one was
    # not, and it is the value that goes into a GitHub comment as part of the
    # array. MAX_FINDING_ID is the same number commands/address.md's
    # FINDING_DISMISSED_BLOCK enforces when it records the artifact, so the
    # reader refuses exactly what that writer refuses. It is NOT
    # bin/journal-record.sh's number: that helper takes the metadata pairs it is
    # given and applies no id bound of its own.
    if len(fid) > MAX_FINDING_ID:
        raise ManifestError("the journal records a dismissal whose finding id is %d characters, "
                            "more than the %d the recording block accepts; refusing to build an "
                            "array from it" % (len(fid), MAX_FINDING_ID))
    return fid
