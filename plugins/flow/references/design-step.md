# Design Step

Reference document. The short design a change to a risky area gets before it is planned, so its
structure is chosen once, on purpose, instead of one review finding at a time.

## When it runs

- **`/flow:start` Phase 1**, when `bin/flow-risk-check.sh` prints `RISK=high`: a file the change will
  modify matches a declared risk area (`design.riskAreas`) or is a fix hotspot
  (`design.hotspotFixCommits`). It runs after the files to touch are known and before the
  specification is captured, so the specification, the goal, the plan and the reviewers all receive
  it. A change with `RISK=normal` skips it; `RISK=unknown` (the check could not run) skips it too, and
  the runtime summary says the check did not run.
- **During review and address cycles**, when a fix would change the recorded design, add a subsystem
  (a new module, service, command, configuration option or stored format), or add a trust boundary (new input from
  content the user does not control, per `references/review-scope.md`). That fix is not made inside
  the loop: the cycle stops, the design step runs, and its record is updated before the fix.

Why: when a risky change is designed inside review-fix loops, each fix settles one finding and opens
the next, and the rule that would have ended it (an invariant, a boundary, a format) is written down
only after several rounds. Writing it first lets the fixes follow it.

## What the agent does

The agent runs the step itself. It asks the user only for a product decision it cannot make
(`skills/llm-operator-principles/SKILL.md` § Escalation Triggers).

1. **Read the area.** The risky files, their callers (`findReferences`, or `git grep`), and the
   patterns the code next to them already uses.
2. **Write two or three options.** Each says what it changes, what existing code it reuses, what new
   structure it adds (files, settings, subsystems, code paths), and its main risk. One option is
   always the smallest change that meets the acceptance criteria inside the existing structure.
3. **Choose.** Take the option that meets the acceptance criteria with the least new structure; on a
   tie, the one that reuses more. A larger option is chosen only for a reason the smaller one cannot
   meet, stated in one line.
4. **Record it** in the decision journal, under `## Design`, with `bin/journal-append.sh --file
   "$JOURNAL" --replace-heading '## Design' -`, and record the manifest entry with
   `bin/journal-record.sh --issue <N> --type design --metadata chosen="<option name>"`.

## The record

```markdown
## Design

### Risky files
- `{path}` — {reason from RISK_FILE}

### Options
1. **{name}** — changes {…}; reuses {…}; adds {…}; risk {…}
2. **{name}** — …

### Chosen
{name} — {one-line reason}

### Reuses
- {existing code, pattern or helper this builds on, with file:line}

### Does not add
- {structure deliberately left out: a setting, a file, a code path, a fallback}

### Invariants
- {a property every later change must keep, stated so a test or a reviewer can check it}
```

## Where it goes next

- **Specification.** `skills/specification-capture/SKILL.md` reads `## Design`: each `Does not add`
  item becomes a non-goal and each `Invariants` item an interface contract. From there the goal
  carries them, and every reviewer is handed them: a change that implements a non-goal is a `scope`
  P2, and one that breaks an interface contract is a `breaking-change` P1.
- **Plan.** The `implementation-planner` dispatch receives the record, and each task names the
  option it implements.
- **Later cycles.** A fix that would contradict `Chosen`, add to what `Does not add` lists, or break an
  invariant goes back through this step first, and the record is updated with the reason.
