# Ask policy

Flow asks a person with `AskUserQuestion` at the points its commands and skills name. Some of those questions only a person can answer; others only ask for a default the agent could take itself. The ask policy says which ones reach the person.

| Policy | Set by | Questions asked |
|---|---|---|
| `attended` | the default (`autonomous: false`) | every question |
| `autonomous` | `autonomous: true` in any settings file (`bin/cascade-resolve.sh`) | decisions and permissions only; a default is taken, recorded and reported |

`bin/flow-ask-policy.sh` prints the policy. The preflight of `/flow:start`, `/flow:pr`, `/flow:address`, `/flow:review`, `/flow:commit` and `/flow:resolve` prints it as `ASK_POLICY=attended` or `ASK_POLICY=autonomous`, and `hooks/scripts/ask-policy.sh` enforces it.

## Question classes

Every place in `commands/` and `skills/` that tells the agent to use `AskUserQuestion` carries one tag. A mention of the tool that is not a place to ask (a rule, a description of another step) carries `[ask: none]`.

| Tag | Class | What the agent does |
|---|---|---|
| `[ask: decision]` | a product or scope decision only a person can make: what the issue means, which approach, which side of a competing conflict, whether criteria the verdict judge could not decide are met | asks in both policies, with `metadata: {"source": "flow:decision"}` |
| `[ask: permission]` | a Tier 3 action (merge, release, a tag push, deleting a trigger, a terminal goal transition, creating rulesets), or a skip outside the runtime-verification list (a required visual or runtime check that cannot run) | asks in both policies, with `metadata: {"source": "flow:permission"}` |
| `[ask: default]` | a question whose answer the agent can take: which uncommitted files to include, whether to fix a closed-loop failure now, whether to go on above a conflict-count limit, whether to apply a settings migration | `attended`: asks (no metadata needed). `autonomous`: takes the recommended option, records it, and says so in the summary |

`metadata` is a field of the `AskUserQuestion` tool input; the person does not see it.

## Recording a default that was taken

Under `ASK_POLICY=autonomous`, a `[ask: default]` site records the choice in the decision journal before going on, so the person can see afterwards what was decided for them:

```bash
"$FLOW_ROOT/bin/journal-record.sh" --issue "$ISSUE_NUM" --type default-taken \
  --metadata site="<command>: <step>" \
  --metadata question="<the question that was not asked>" \
  --metadata choice="<the option taken>"
```

On a branch with no issue number, pass `--session` in place of `--issue "$ISSUE_NUM"`. `FLOW_ROOT` is the plugin root as the command's blocks resolve it. The command's summary or final reply lists every default taken.

## The hook

`hooks/scripts/ask-policy.sh` is a `PreToolUse` hook on `AskUserQuestion`:

| Situation | Decision |
|---|---|
| the payload cannot be read, or the policy cannot be read | allow: a person is there to answer |
| `attended` | allow |
| `autonomous`, `metadata.source` is `flow:decision` or `flow:permission` | allow |
| `autonomous`, any other question | deny, with a reason that tells the agent to take its recommendation, record it with `--type default-taken`, and continue |

Under `autonomous` the hook judges every `AskUserQuestion` in the session, not only flow's: a question from another plugin or from the conversation that does not declare a class is denied the same way. Set `autonomous: false` (the default) to be asked everything.

Tier 3 actions keep their own confirmation as well: `tier-gate.sh` asks when a merge, release or tag push runs, whatever the ask policy.

## How the hook was checked

Before the hook was built on, its mechanism was checked on Claude Code 2.1.319 (`claude --version`), on 2026-11-07:

- In `claude -p`, `AskUserQuestion` is not among the session's tools (the `init` event's tool list).
- With `--input-format stream-json --permission-prompt-tool stdio` (the way a host such as the Agent SDK runs a session and answers its questions in place of the terminal), `AskUserQuestion` is offered.
- In that session, with a `PreToolUse` hook on `AskUserQuestion` that only prints `permissionDecision: "deny"`, the model's call was denied: no permission request reached the host, and the tool result the model received was the hook's reason.
- The hook's payload held `tool_input.metadata.source` exactly as the model wrote it (`"flow:decision"`).

The interactive terminal session itself was not driven in that check, because the environment it ran in had no terminal for it. Claude Code runs `PreToolUse` hooks before its permission rules and before any prompt, in every mode, so the terminal session takes the same path; if a release changes that, the check above is the one to run again.

## Related

- `skills/llm-operator-principles/SKILL.md` — valid escalation triggers and autonomous mode
- `references/escalation-format.md` — the six fields every escalation keeps
- `references/three-tier-safety.md` — Tier 3 actions
- `references/decision-journal-schema.md` — the `default-taken` artifact
