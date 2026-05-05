# Flow Plugin Team Workshop — docs

A 90-minute mixed-audience (engineering + PM/design) workshop for the `/flow` plugin. Mental model + lifecycle walkthrough + 10 conventions decided live.

## What's in here

| File | Purpose | When to use |
|------|---------|-------------|
| `slides.md` | Marp source for the deck (~63 slides) | Project this during the session. Render with `npx -y @marp-team/marp-cli --pdf slides.md`. |
| `HANDBOOK.md` | Long-form reference (~15 pages) | Read after the session. Bookmark for later. |
| `CHEATSHEET.md` | One-page printable, two-column | Pin to the wall. Reach for it daily. |
| `walkthrough-script.md` | Pre-recording shotlist + live-narration timing + dry-run checklist | Producing the recording. Re-recording it later. |
| `CONVENTIONS-WORKSHEET.md` | 10-row fillable template | Project on screen during section 6. Don't advance until each row has an answer. |
| `CONVENTIONS-DECIDED.md` | Empty template for the post-session artifact | Fill in during the session. Commit. Open follow-up PR for `.claude/settings.flow.json`. |
| `faq-and-glossary.md` | Anticipated questions + term lookup | When someone asks "what's ESCALATED again?" |
| `README.md` | This index | First-time onboarding. |

## How to run the session

1. **Two weeks before**: skim `walkthrough-script.md`. Pre-record using a synthetic `sync-cli` repo (the script tells you exactly what to capture). Confirm composite ≤ 20 minutes.
2. **One week before**: dress-rehearse the deck against a 1-person audience matching the target profile. Time each segment. Adjust if any segment is >20% over budget.
3. **Day of, 30 min before**: run the pre-recording checklist in `walkthrough-script.md`. Confirm `/flow:setup` and `/flow:status` work cold from a clean machine.
4. **Day of, 5 min before**: project `CONVENTIONS-WORKSHEET.md`. The forcing function is that the team can see the open rows.
5. **Session**: follow `slides.md` agenda. 90 minutes. Hard buffer in segments 5 and 6.
6. **Right after**: copy the marked rows from `CONVENTIONS-WORKSHEET.md` into `CONVENTIONS-DECIDED.md`. Commit. If non-default settings were chosen, open a follow-up PR adding overrides to `.claude/settings.flow.json`.

## Why a workshop instead of a doc?

The mental model — particularly the verdict-judge's information isolation — needs to be **shown**. The recording solves the "demos break in front of audiences" problem; live narration lets the room interrupt at the right moments. After the session, the docs in this folder are what you reach for; they exist *because* the live session happened, not as a substitute for it.

## Audience

Mixed engineering + PM/design, varied Claude Code experience. The deck deliberately:

- Teaches **principles** before vocabulary (engages PM/design fully).
- Teaches **vocabulary** before the demo (so the demo's terms have slots in your head).
- Puts the **conventions vote** after the demo (the room can't vote on `tddMode: enforce` until they've felt it).
- Puts **hands-on** before Q&A (everyone leaves with a running plugin, not the intent to install tomorrow).

If only one concept lands, it should be **verdict-judge information isolation** (slide 22, pause beat 2). PM/design will ask "but how does the agent know if it's right?" and that's the answer.

## What's the deliverable?

Two:

1. A team-wide shared mental model of how flow works — measurable by everyone being able to explain in one sentence what the verdict-judge does NOT see.
2. A committed `CONVENTIONS-DECIDED.md` that drives `.claude/settings.flow.json` — and a follow-up PR for any non-default values within one week.

If the session ends with no decisions captured: the session was theatre. The forcing function in section 6 prevents that.

## Source-of-truth alignment

Everything in these docs is grounded in `plugins/flow/`. When the plugin source and these docs disagree, the source wins — file an issue with `documentation` label so we can resync.

Quoted material is verbatim from the noted file:line. The verification check (in the original plan) greps each `[QUOTE]` block against its source. If you change a skill's iron law, expect the corresponding slide to need an update.

## Renaming and rerunning

Want to use this workshop format for a different plugin or a different team? Copy this folder, search-and-replace `flow` for the new plugin name, regenerate the conventions worksheet against the new plugin's `settings.json` defaults, re-record the walkthrough using the new plugin's daily five. The structure (principles → skeletons → vocabulary → demo → commands → conventions → hands-on → close) generalizes.
