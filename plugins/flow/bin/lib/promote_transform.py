#!/usr/bin/env python3
"""Turn a validated skill proposal into a skill.

Usage: promote_transform.py <skill-path> <evidence-path>

Rewrites <skill-path> in place and writes the removed material to
<evidence-path>. Exits 1 with an explanation when the result would not be a
well-formed skill, leaving the caller to roll back.

A proposal argues for its own promotion: it opens with the pattern it claims to
have found, cites journal entries from the project it was mined in, and ends
with a checklist for the reviewer. The promoted file is read by an agent about
to act, and none of that is addressed to it. So those sections come out, along
with the frontmatter that carries the same foreign provenance, and the caller
puts them where a reviewer will see them.

This lives in a file rather than a heredoc inside promote-proposal.sh because
the dry run and the real run must execute the same code — a dry run that cannot
reach the transform cannot report any of the ways it refuses.
"""

import datetime
import os
import sys

# Defensive sys.path filter — see bin/validate-skill-input.sh for rationale.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import proposal_sections  # noqa: E402
import yaml  # noqa: E402

# Sections written for the promotion reviewer, not for the skill's reader.
PROPOSAL_ONLY = ("Pattern Detected", "Evidence", "Enforcement point", "Promotion Checklist")

# Frontmatter naming the project the pattern came from. `source-sessions` cites
# issue numbers that resolve in no repository the skill is installed into, which
# is the same reason the Evidence section is removed; applying the rule to the
# body and not the header left half the provenance published.
PROPOSAL_ONLY_FRONTMATTER = ("source-sessions", "evidence-count", "proposed")

CONTRACT_MAX_WORDS = 120
BODY_MAX_WORDS = 600


class TransformError(Exception):
    def __init__(self, problems):
        self.problems = problems
        super().__init__("; ".join(problems))


def transform(content, today=None):
    """Return (new_content, evidence_text, report) or raise TransformError."""
    if not content.startswith("---\n"):
        raise TransformError(["the file has no YAML frontmatter"])
    end = content.find("\n---\n", 4)
    if end == -1:
        raise TransformError(["the frontmatter is not closed"])
    try:
        fm = yaml.safe_load(content[4:end])
    except yaml.YAMLError as e:
        raise TransformError([f"malformed YAML frontmatter: {e}"])
    if not isinstance(fm, dict):
        raise TransformError(["frontmatter is not a YAML mapping"])

    body = content[end + 5:]
    today = today or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

    provenance = {k: fm.pop(k) for k in PROPOSAL_ONLY_FRONTMATTER if k in fm}
    fm["status"] = "promoted"
    fm["promoted"] = today

    # Boundaries come from the shared parser, which ignores `## ` lines inside
    # fenced code. A line regex split on them, relocated the rest of the
    # enclosing section into the evidence, and left the skill holding an
    # unterminated fence — at exit 0, because the shape checks still passed.
    preamble, sections = proposal_sections.split(body)
    kept = [s for s in sections if s.title not in PROPOSAL_ONLY]
    dropped = [s for s in sections if s.title in PROPOSAL_ONLY]

    evidence = []
    if provenance:
        evidence.append("## Provenance (removed from the skill frontmatter)\n")
        evidence.append(yaml.safe_dump(provenance, sort_keys=False, allow_unicode=True, width=10**6).rstrip())
        evidence.append("")
    for s in dropped:
        evidence.append(proposal_sections.render([], [s]).rstrip())
        evidence.append("")
    evidence_text = "\n".join(evidence).rstrip() + "\n" if evidence else ""

    new_body = proposal_sections.render(preamble, kept)

    # Verify the output rather than trusting the transform: a silent pass here
    # installs an unreadable skill, which is what this exists to prevent.
    problems = []
    if not kept or kept[0].title != "Contract":
        first = kept[0].title if kept else "(no H2 sections)"
        problems.append(f"first H2 after promotion is {first!r}, expected 'Contract'")
    else:
        cwords = len(kept[0].text().split())
        if cwords > CONTRACT_MAX_WORDS:
            problems.append(f"Contract is {cwords} words (max {CONTRACT_MAX_WORDS})")
    bwords = len(new_body.split())
    if bwords > BODY_MAX_WORDS:
        problems.append(f"body is {bwords} words (max {BODY_MAX_WORDS})")
    if proposal_sections.unclosed_fence(new_body):
        problems.append("the promoted body ends inside an unterminated code fence")
    leftover = [s.title for s in kept if s.title in PROPOSAL_ONLY]
    if leftover:
        problems.append(f"proposal-only sections survived: {leftover}")
    if problems:
        raise TransformError(problems)

    front = yaml.safe_dump(fm, sort_keys=False, default_flow_style=False, allow_unicode=True, width=10**6)
    new_content = f"---\n{front}---\n{new_body.rstrip()}\n"

    # "matched no reviewer sections" and "there were none" must not look alike.
    if dropped or provenance:
        moved = [s.title for s in dropped] + ([f"frontmatter: {', '.join(provenance)}"] if provenance else [])
        report = f"kept {len(kept)} sections, moved {', '.join(moved)} to the pull request, {bwords} body words"
    else:
        report = (
            f"kept {len(kept)} sections, NO reviewer sections matched {PROPOSAL_ONLY} "
            f"and no provenance frontmatter was present — nothing moved, {bwords} body words"
        )
    return new_content, evidence_text, report


def main(argv):
    if len(argv) != 3:
        print("usage: promote_transform.py <skill-path> <evidence-path>", file=sys.stderr)
        return 2
    target, evidence_path = argv[1], argv[2]
    with open(target, encoding="utf-8") as f:
        content = f.read()
    try:
        new_content, evidence_text, report = transform(content)
    except TransformError as e:
        print("ERROR: proposal does not promote to a well-formed skill:", file=sys.stderr)
        for p in e.problems:
            print(f"  - {p}", file=sys.stderr)
        print("  Fix the proposal and re-run; see templates/skill-proposal.md.", file=sys.stderr)
        return 1
    with open(target, "w", encoding="utf-8") as f:
        f.write(new_content)
    with open(evidence_path, "w", encoding="utf-8") as f:
        f.write(evidence_text)
    print(f"promote: {report}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
