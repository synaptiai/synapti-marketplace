# Review round 4

Branch docs/issue-316-flow-prompt-audit. Findings below are copied verbatim from each reviewer subagent's final report: the section headings (which carry the severity) and every finding row or line that names tier-gate.sh, block-unchecked-merge.sh, block-destructive.sh, command-parse.sh, or their test files. Lines that do not name those files are omitted.

## Round-4 security review (f3a39d72)

- Source: `<transcripts>/148019cc-de64-4bee-8c80-932a311792cc/subagents/agent-ae053db82555b3627.jsonl` (final assistant message)
- Timestamp: 2026-10-30T02:54:54.321Z

## Security review: round 4 of the tier gate (`d8d5eae0..f3a39d72`)
The three permitted suites pass at head: e2e-tier-gate 2191/0, block-unchecked-merge 193/0, e2e-guard-refusals 209/0. None of them covers the payloads below.
### P1 — Critical Security Issues (Blocks Merge)
| **SEC-1 · security/bypass · `plugins/flow/hooks/scripts/tier-gate.sh:1402`** (also `_tg_scan` at :1324)<br>**Regression.** The new word reader keeps `gh\ release` as one word, which is correct, because bash passes it as one argument (`printf %q` shows `gh\ pr`, `merge`, `1`). But `watch` and `ssh` join all their arguments with spaces and give the result to a shell. Since round 3, `_tg_may_run` only reads a word that contains both gh/git and one of push/merge/release/api, so the words `gh release` and `create` are never read together. Base asked on every one of these; head is silent:<br>`watch gh\ release create v9`<br>`ssh h gh\ release create v9`<br>`watch git\ push --tags`<br>`ssh h git\ push --tags`<br>The merge forms (`watch gh\ pr merge 1`) are still blocked by block-unchecked-merge. Release and tag push have no other guard. The quoted form `watch "gh pr" merge 1` and `ssh h 'gh pr' merge 1` was already silent at base. _(HIGH)_ | When the command word is a program the hook does not know, or ssh, also read all the words after it joined with spaces as one command (the way watch and ssh build it). Apply the existing 16-read limit to that joined text. Add each payload above as a must-ask test. |
| **SEC-2 · security/bypass · `plugins/flow/hooks/scripts/tier-gate.sh:1426`** (`_tg_set_names`)<br>**Regression.** Base flagged any word naming a git variable (`GIT_DIR`, `GIT_CONFIG_*` and so on) anywhere in a simple command. The new `_tg_set_names` only looks for assignments when the command word itself is export, declare, typeset, local, readonly or unset. With `eval` (or `builtin eval`) as the command word, nothing is flagged:<br>`eval export GIT_DIR=../other/.git; git push`<br>base=ask, head=SILENT. The dry run shows `* [new tag] vO -> vO`, because the other repository has `push.followTags`. _(HIGH)_ | When the command word is `eval` (or `source` / `.`), read its unquoted arguments as a command in place, or simply count any `eval`/`source` earlier in the command as changing git's environment (set gpend=1 and TG_CDOTHER=1). Add a must-ask test for the payload. |
| **SEC-3 · security/bypass · `plugins/flow/hooks/scripts/tier-gate.sh:402`** (`_tg_is_assignment`, used by `_tg_command_word` :515 and `_tg_set_names` :1426)<br>**Left open by this round's assignment detection; already silent at base.** An append assignment such as `GIT_DIR+=x` fails the name check, because `GIT_DIR+` contains `+`. bash still sets the variable, and as a prefix it is exported. Silent at both base and head, with a dry run showing the tag push for each:<br>`GIT_DIR+=../other/.git git push`<br>`export GIT_DIR+=../other/.git; git push`<br>`set -a; GIT_DIR+=../other/.git; git push`<br>`declare -x GIT_DIR+=../other/.git; git push`<br>The same gap applies to `GH_REPO+=` and `GH_HOST+=`. _(HIGH)_ | In `_tg_is_assignment`, accept `NAME+=value` (and `NAME[...]=value`) and return `NAME` without the `+`. Add the payloads as tests. |
### P2 — Security Concerns
| **SEC-4 · security/bypass · `plugins/flow/hooks/scripts/tier-gate.sh:1635`** (`_tg_read_text`)<br>The text handed to `eval` or `source` is appended after the whole command and read last. The round-3 pre-scan catches `git config` in that text, but not a `cd` or an `export`. In bash, eval and source run in the current shell, so both change what the later push does. Silent at both base and head, with a dry run showing `[new tag] vO`:<br>`eval 'cd ../other'; git push`<br>`eval cd ../other; git push`<br>`eval "export GIT_DIR=../other/.git"; git push`<br>`source /dev/stdin <<<'cd ../other'; git push`<br>None of these is a command built at run time, so the header's "Not covered" list does not cover them. _(HIGH)_ | Same fix as SEC-2: any `eval`, `source` or `.` earlier in the command sets TG_CDOTHER=1 and TG_GITENV=1. Alternatively, extend `_tg_config_prescan` to also catch cd, pushd and assignments. |
| **SEC-5 · security/bypass · `plugins/flow/hooks/scripts/tier-gate.sh:1461`** (`_tg_config_write`)<br>The round-3 promise that config changes earlier in a command make a push ask only covers `git config` and `git remote`. These other commands also set `branch.<name>.remote` and are silent at both base and head when a remote has `push = refs/tags/*`:<br>`git branch -u mir/main && git push` (dry run in a copy of the repo: `[new tag] v1 -> v1`)<br>`git branch --set-upstream-to=mir/main; git push`<br>`git push -u mir main && git push`<br>`git checkout -b x mir/main && git push`<br>`git switch -c y --track mir/main && git push`<br>`git config --rename-section x push` is also missed: the key test is `push.*` and the new section name `push` has no dot. I did not run this one, since running `git config` was not permitted. _(MEDIUM)_ | In `_tg_config_write`, count `branch -u`, `--set-upstream-to`, `--track`, `checkout -b`/`-t`, `switch -c`/`--track` and `push -u`/`--set-upstream`. Match section names with or without a dot (`push`, `remote`, `branch`, `include`, `includeif`), so `--rename-section` and `rename-section` are caught. |
### P3 — Security Improvements
| **SEC-6 · security/docs · `plugins/flow/hooks/scripts/tier-gate.sh:281`**<br>The "Not covered" list does not mention writing git's configuration file directly. `printf '[push]\n\tfollowTags = true\n' >> .git/config && git push` and `cp ../other/.git/config .git/config && git push` are silent at both base and head. _(HIGH)_ | Make a later push ask when a redirection target or argument names `.git/config`, `config.worktree` or `.gitconfig`, or list this case under "Not covered". |
### What I checked that held

## Round-4 code review (f3a39d72)

- Source: `<transcripts>/148019cc-de64-4bee-8c80-932a311792cc/subagents/agent-a4a424547cc589d72.jsonl` (final assistant message)
- Timestamp: 2026-10-30T02:57:27.006Z

## Code Review Findings: round 4, `d8d5eae0..f3a39d72`
I found one regression in a guard the diff did not mention, one Tier 3 regression in tier-gate, and three smaller gaps. I reproduced each finding with a scratch repository: a bare origin, an annotated tag `v1.0` pushed there, branch `master`, and a second worktree `../wt`. The same commands went to the hook at `d8d5eae0` (exported with `git archive`) and to the hook at HEAD `f3a39d72`. In the repro blocks, `base` and `new` mean those two versions. `rc=2` means refused, and `ask` / `none` is the `permissionDecision` the hook returned. The probe uses the payload you specified, `FLOW_USER_SETTINGS` points to a `{}` file, and it runs with cwd set to the scratch repo.
### P1 — Critical (Blocks Merge)
| **F1 · breaking-change · `plugins/flow/hooks/scripts/lib/command-parse.sh:717`**<br>block-destructive now lets through destructive commands it blocked at `d8d5eae0`. `_BD_SEG_AWK` no longer splits a command at the `&` of `&>`. block-destructive still tokenises with `_rm_tokenise` (`block-destructive.sh:99`), so `--hard&>/dev/null` reaches it as a single token and matches no flag. This diff moved only tier-gate to `_bd_words`. A related form, `git reset --hard>/dev/null` (a bare `>` glued to the word), was already allowed at base; the cause is the same tokeniser. _(HIGH)_ | Move block-destructive's word reading to `_bd_words` (drop the redirection and its target, then match). Alternatively, have `_rm_tokenise` split a glued `<`/`>`/`&>` as `_bd_words` does. Add the four glued forms below to `e2e-guard-refusals.test.sh` as must-block cases. |
**F1 repro** (`HOOK=…/block-destructive.sh probe.sh`):
### P2 — Should Fix
| **F2 · correctness · `plugins/flow/hooks/scripts/tier-gate.sh:1426`**<br>A release on another repository is now created without a prompt when `GH_REPO` is exported through `eval`. `_bd_expand_interpreter_args` adds `eval`'s text after every other command, so `_tg_set_names` sees the export only after the `gh release create` has been judged. Base caught this with its "any token naming GH_REPO" scan. The new `_tg_config_prescan` (lines 1635-1637) fixes this ordering for `git config`/`git remote` only. `eval` and `source` run in the current shell, so an export or `cd` inside them also applies from the start. The same ordering already let `eval 'cd ../other'; git push origin master` and `eval 'export GIT_DIR=…'` through at base. The header at lines 111-116 ("set or exported earlier in the same command") claims coverage the code does not give for these. `bash -c 'export GH_REPO=o/r'; …` changing from ask to none is correct, because a child shell's export does not reach the parent. _(HIGH)_ | Extend the prescan of `added` to everything a segment can change for later commands: the `_tg_set_names` names (set `pend`/`gpend` from the start) and `cd`/`pushd`/`popd` (set `TG_CDOTHER`). Limit this to text from `eval`/`source`/`.`, the ones that run in this shell. Add tests for the `eval` export and `eval 'cd …'` cases. |
| **F3 · correctness · `plugins/flow/hooks/scripts/block-unchecked-merge.sh:230`**<br>The new bare-operator list (`>`, `>>`, `<`, `<<<`, `N>`, `N>>`, `N<`) leaves out `>&`, `<&`, `&>`, `&>>`, `>\|`, `<>` and `<<`. A redirect written with a space before its target is skipped by one word only, so the target becomes a subcommand word and the merge is not seen. Only `2>&1`, `2>/dev/null` and the other listed forms are covered. The same list is at line 288. tier-gate does ask for these forms, so the merge is still confirmed, but the "checked merge" refusal that the CHANGELOG describes is skipped. _(HIGH)_ | Add `'>&'\|'<&'\|'&>'\|'&>>'\|'>\|'\|'<>'\|'<<'\|'<<-'\|[0-9]'>&'\|[0-9]'<&'\|[0-9]'<>'` to both lists. Add the two cases below to `block-unchecked-merge.test.sh`. |
| **F4 · correctness · `plugins/flow/hooks/scripts/tier-gate.sh:1461`**<br>`_tg_config_write` treats a `git config` with no key word as no write. Under `xargs`, the key and value come from the command's input. So `xargs git config` before a push leaves the push unasked, while `git config "$K" true` asks. The header already applies the xargs rule to refspecs ("words appended from its input may be refspecs, so the push asks"). With `push.followTags` set this way, `git push origin master` pushes tags. _(HIGH)_ | When `TG_XARGS=1`, or the program word is `xargs`, and `config` has no key word (and no `--get`/`--list`), count it as a write. |
**F2 repro** (tier-gate):
**F3 repro** (`HOOK=…/block-unchecked-merge.sh`):
**F4 repro** (tier-gate):
### P3 — Consider
| **F5 · correctness · `plugins/flow/hooks/scripts/lib/command-parse.sh:309`**<br>`_bd_words` reads the locale string `$"merge"` as the word `$merge`, with its expansion flag set to 0. Bash hands the program `merge` (checked: `printf "[%s]" $"--tags" m$"erge"` prints `[--tags][merge]`). The new reader's header says it reads words "as bash reads them". Both hooks miss the resulting Tier 3 commands, though they already did so at base. A related gap that the diff does not cause: a gh subcommand or push word that is a variable (`gh pr $A 7`, `git push $OPTS`) is also unasked in both hooks. The header documents only the ANSI-C `$'…'` subcommand as an exception. _(HIGH)_ | In the awk, treat an unescaped `$` right before `"` as removed, so the double-quoted string is read as usual. In `_tg_gh`, ask when `w1` or `w2` is unreadable (`_tg_unreadable`). In `_tg_git_push`, ask when the remote word is unreadable and no refspec follows. |
### Checked and correct
### Summary
- **Tests:** `e2e-tier-gate`, `block-unchecked-merge`, `e2e-guard-refusals` and `e2e-release-versions` all exited 0, with `TOTAL pass=551 fail=0` in the release log and no FAIL lines in any log. None of them covers F1-F5.
  - `_bd_segments` (splitter changed): 5 files. block-destructive is the regression in F1. block-unchecked-merge and tier-gate are checked. s1-guard pre-rewrites `&>`.
  - `_bd_is_redirection` (patterns widened): block-unchecked-merge lines 232 and 290, block-destructive lines 328, 525, 542 and 581.
  - `_bd_words` (new): 4 call sites, in command-parse.sh and tier-gate.sh.

### Repro blocks from the round-4 code review (verbatim, same source and timestamp as above; they sit outside the findings table in the report)

**F1 repro** (`HOOK=…/block-destructive.sh probe.sh`):
```
                                       base    new
git reset --hard&>/dev/null            rc=2    rc=0
git reset HEAD~1 --hard&>/dev/null     rc=2    rc=0
git restore .&>/dev/null               rc=2    rc=0
git checkout .&>/dev/null              rc=2    rc=0
git checkout -- .&>/dev/null           rc=2    rc=0
git reset --hard>/dev/null             rc=0    rc=0   (gap that already existed)
_rm_tokenise 'git reset --hard&>/dev/null' -> [git][reset][--hard&>/dev/null]
```

**F2 repro** (tier-gate):
```
                                                                      base   new
eval 'export GH_REPO=o/r'; gh release create v1.0 --verify-tag        ask    none
eval export GH_REPO=o/r; gh release create v1.0 --verify-tag          ask    none
eval "export GH_REPO=o/r"; gh release create v1.0 --verify-tag        ask    none
source /dev/stdin <<< 'export GH_REPO=o/r'; gh release create v1.0 --verify-tag   ask   none
export GH_REPO=o/r; gh release create v1.0 --verify-tag              ask    ask
eval 'cd ../other'; gh release create v1.0 --verify-tag               none   none   (already allowed)
```

**F3 repro** (`HOOK=…/block-unchecked-merge.sh`):
```
                                  base   new
gh pr 2>&1 merge 7                rc=0   rc=2   (the case this round fixed)
gh pr 2>/dev/null merge 7         rc=0   rc=2
gh pr >& /dev/null merge 7        rc=0   rc=0
gh pr &> /dev/null merge 7        rc=0   rc=0
```

**F4 repro** (tier-gate):
```
printf 'push.followTags\ntrue\n' | xargs git config; git push origin master   none
xargs git config < /tmp/f; git push origin master                             none
git config "$K" true && git push origin master                                ask
```

**F5 repro** (both hooks: none at base and at f3a39d72):
```
gh pr $"merge" 7          none
gh release $"create" v9   none
git push $"--tags"        none
git push $'--tags'        none
gh pr $A 7                none
git push $OPTS            none
```

