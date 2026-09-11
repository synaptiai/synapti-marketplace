"""Split a skill-proposal body into H2 sections, ignoring fenced code.

`bin/promote-proposal.sh` reads a proposal twice: once to validate it and once
to transform it into a skill. Those two passes used different rules — the
validator asked whether the string "## Evidence" appeared anywhere in the body,
the transform matched exact heading names with a line regex. A proposal could
satisfy one and not the other, and a `## ` line inside a fenced example block
counted as a real heading to both. The transform split there, wrote a skill
whose code fence was never closed, moved the prose after it into the commit
message, and exited 0 reporting success.

That is not a matcher needing another exclusion; it is a small grammar. This
module is that grammar, and both passes import it, so they cannot disagree.

A fence opens on a line whose first non-space run is three or more backticks or
tildes, and closes on a later line whose fence character matches and whose run
is at least as long — CommonMark's rule: a longer closer is legal, a shorter one
is not, and a tilde fence is not closed by backticks. Headings found while a
fence is open belong to the fence.

The split is exact: `render(*split(body)) == body` for any input. Sections carry
their body as a list of lines rather than a joined string, because joining loses
the difference between a section with no lines and a section with one empty
line, and a transform that cannot reproduce its input is not safe to write back.
"""

import re

_FENCE = re.compile(r"^[ ]{0,3}(?P<run>`{3,}|~{3,})")
_H2 = re.compile(r"^##[ \t]+(?P<title>.+?)[ \t]*$")


class Section:
    """One H2 section: its title, its heading line verbatim, and its lines."""

    __slots__ = ("title", "heading", "lines")

    def __init__(self, title, heading, lines):
        self.title = title
        self.heading = heading
        self.lines = lines

    def text(self):
        return "\n".join(self.lines)

    def __repr__(self):
        return f"Section({self.title!r}, {len(self.lines)} lines)"


def _fence_state(line, char, length):
    """Advance fence state for one line. Returns (char, length, is_delimiter)."""
    m = _FENCE.match(line)
    if not m:
        return char, length, False
    run = m.group("run")
    if char is None:
        return run[0], len(run), True
    if run[0] == char and len(run) >= length:
        return None, 0, True
    return char, length, True


def split(body):
    """Return (preamble_lines, [Section, ...]).

    `preamble_lines` is everything before the first H2 — typically the H1 and
    any prose under it.
    """
    preamble = []
    sections = []
    char = None
    length = 0

    for line in body.split("\n"):
        char, length, is_delim = _fence_state(line, char, length)
        heading = None if (is_delim or char is not None) else _H2.match(line)
        if heading:
            sections.append(Section(heading.group("title"), line, []))
        else:
            (sections[-1].lines if sections else preamble).append(line)

    return preamble, sections


def render(preamble_lines, sections):
    """The exact inverse of `split`."""
    out = list(preamble_lines)
    for s in sections:
        out.append(s.heading)
        out.extend(s.lines)
    return "\n".join(out)


def titles(body):
    """The exact H2 titles in `body`, in order, ignoring fenced code."""
    return [s.title for s in split(body)[1]]


def unclosed_fence(body):
    """True when the body ends inside an open code fence.

    Promoting a body like that produces a skill whose rendering is broken from
    the unterminated block onward, so it is refused rather than shipped.
    """
    char = None
    length = 0
    for line in body.split("\n"):
        char, length, _ = _fence_state(line, char, length)
    return char is not None
