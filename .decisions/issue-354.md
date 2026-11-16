---
issue: 354
created: '2026-11-16T12:56:10Z'
artifacts:
- type: escalation-asked
  captured_at: '2026-11-16T12:56:10Z'
  question_id: q-20261116T125609Z-c64bb1
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - 'In 1a the shipped next cannot launch a worker: every launch row of transitions.json
    reads facts that 1b'
  - 1c
  - 1e or 1g compute. So AC3 (every row through next)
  - AC4 (one worker)
  - AC5 (relaunch)
  - AC6 (w
- type: escalation-asked
  captured_at: '2026-11-16T12:56:12Z'
  question_id: q-20261116T125611Z-297f5f
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - '#354''s P5 go item says the cost part must come out go when P5 is re-run'
  - but that part measures what Claude Code reports for a resumed run
  - which the engine cannot change
  - so it stays no-go. The desig
- type: escalation-asked
  captured_at: '2026-11-16T12:56:14Z'
  question_id: q-20261116T125613Z-a7f8cf
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - 1a-1g merge to main with the factory off
  - but today off only means no probe record
  - and this Mac has one. From 1b on
  - each phase lets the shipped next do more.
- type: escalation-asked
  captured_at: '2026-11-16T12:56:16Z'
  question_id: q-20261116T125615Z-b44b95
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - AC12 says 1a ends in a release
  - and the design asks for a live acceptance run before each release. In 1a the engine
    can launch nothing outside tests
  - and the plan puts the first live run and the first
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:49Z'
  escalation_field: options
  outcome:
  - A test-only entry point runs the engine's real next with fixture values for the
    facts later phases compute; flow-factory.sh cannot reach it; each later phase
    replaces its fixtures with the real facts. Meets AC3-AC6 and AC9 as written
  - but those scenarios do not run through the shipped wrapper.
  question_id: q-20261116T125609Z-c64bb1
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:52Z'
  escalation_field: options
  outcome:
  - Resume depends on P5's session parts only; the cost item is closed by an E2E test
    that the engine charges each run's own cost
  - and by a new P5 part engine_charge that a re-run records as go (about $0.75
  - asked at that step).
  question_id: q-20261116T125611Z-297f5f
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:54Z'
  escalation_field: options
  outcome:
  - Add flow.factory.enabled
  - 'default false: next and the acting person subcommands refuse with FACTORY_REFUSED=disabled
    unless it is true; status'
  - rebuild
  - probe and context --mode always work.
  question_id: q-20261116T125613Z-a7f8cf
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:56Z'
  escalation_field: options
  outcome:
  - Merge 1a without a release
  - and release once the factory works end to end
  - 'editing AC12 in #354 to #360.'
  question_id: q-20261116T125615Z-b44b95
---
