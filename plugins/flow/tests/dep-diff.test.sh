# Tests for dependency judgment — issue #217.
#
# Contract under test:
#   - bin/flow-dep-diff.sh reads the manifests a range touches and prints what
#     the range adds, bumps and drops, with the manifest file:line each package
#     is declared on. Deterministic and offline.
#   - Three answers that must never collapse into one another:
#       STATE=none        no dependency manifest was in the diff  (EXAMINED=0)
#       STATE=ok          a manifest was read                     (EXAMINED>=1)
#       STATE=unavailable a manifest could not be read            (UNPARSED named)
#     Reporting an unreadable manifest as "no dependency changed" is the defect
#     class issue #214 spent eleven review cycles removing. It is pinned here.
#   - The baseline for the near-name (typosquat) check is read at the BASE
#     commit, so a pull request cannot supply both the mimic and the name it
#     mimics and have them compared against each other.
#   - agents/security-reviewer.md invokes the helper and emits DEP- findings
#     into the canonical schema, rather than keeping dependency results out of
#     the FLOW_REVIEW_CYCLE marker as telemetry.
#
# Prereq: git and python3. SKIPS gracefully if absent.

if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "git and python3 prerequisite"
  _flow_assert_pass "SKIP: git or python3 not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
DEP_DIFF="$PLUGIN_DIR/bin/flow-dep-diff.sh"
SECURITY_MD="$PLUGIN_DIR/agents/security-reviewer.md"
SCHEMA_MD="$PLUGIN_DIR/references/finding-schema.md"
REVIEW_MD="$PLUGIN_DIR/commands/review.md"
PR_MD="$PLUGIN_DIR/commands/pr.md"
CAPDISC_MD="$PLUGIN_DIR/skills/capability-discovery/SKILL.md"
PROBES_MD="$PLUGIN_DIR/references/runtime-verification-probes.md"

DD_CLEANUP=()
_dd_cleanup() { local p; for p in "${DD_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _dd_cleanup EXIT

DD_SCRATCH=$(mktemp -d -t flow-dd-scratch.XXXXXX); DD_CLEANUP+=("$DD_SCRATCH")

# _dd_repo — create a scratch git repo, echo its path.
_dd_repo() {
  local d
  d=$(mktemp -d -t "flow-dd.XXXXXX") || return 1
  DD_CLEANUP+=("$d")
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "flow test"
  git -C "$d" config commit.gpgsign false
  printf '%s\n' "$d"
}

# _dd_commit <repo> <message> — stage everything and commit.
_dd_commit() {
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit --quiet --allow-empty -m "$2" >/dev/null 2>&1
}

# _dd_run <repo> <base> <head> — run the helper inside the repo.
_dd_run() { ( cd "$1" && "$DEP_DIFF" --base "$2" --head "$3" 2>&1 ); }

# =============================================================================
# The three states must stay distinguishable
# =============================================================================

_flow_test_begin "no manifest in the diff reports none with zero examined"
R=$(_dd_repo)
printf 'hello\n' > "$R/README.md"; _dd_commit "$R" "base"
printf 'hello there\n' > "$R/README.md"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "STATE=none" "$OUT" "no manifest touched is none"
assert_contains "MANIFESTS_EXAMINED=0" "$OUT" "nothing was examined"
assert_not_contains "DEP_ADDED=" "$OUT" "no packages reported"

_flow_test_begin "a manifest changed but no dependency did is examined, not none"
# This is the case the issue's wording collapses with the one above. A reader
# must be able to tell "looked, clean" from "never looked": only the first is
# evidence that the dependencies are unchanged.
R=$(_dd_repo)
printf '# a note\nflask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf '# a different note\nflask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "STATE=ok" "$OUT" "a read manifest is ok, not none"
assert_contains "MANIFESTS_EXAMINED=1" "$OUT" "the manifest was examined"
assert_not_contains "DEP_ADDED=" "$OUT" "a comment edit adds nothing"
assert_not_contains "DEP_CHANGED=" "$OUT" "a comment edit changes nothing"
assert_not_contains "STATE=none" "$OUT" "never reports none for a manifest it read"

_flow_test_begin "an unreadable manifest is unavailable and names itself"
# The #214 defect class: an input that cannot be read must not produce the same
# answer as one that is legitimately absent.
R=$(_dd_repo)
printf '{"dependencies":{"left-pad":"1.0.0"}}\n' > "$R/package.json"; _dd_commit "$R" "base"
printf '{"dependencies":{"left-pad": oops\n' > "$R/package.json"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "STATE=unavailable" "$OUT" "an unreadable manifest is unavailable"
assert_contains "MANIFEST_UNPARSED=package.json" "$OUT" "the file that failed is named"
assert_contains "REASON=" "$OUT" "the reason is printed"
assert_not_contains "STATE=none" "$OUT" "never reports none for a file it could not read"
assert_not_contains "STATE=ok" "$OUT" "never reports ok for a file it could not read"

_flow_test_begin "a Gemfile whose gem name is not a literal is unparsed, not empty"
# A Gemfile is Ruby, not a data format. Guessing would report a dependency the
# reviewer is told does not exist.
R=$(_dd_repo)
printf "source 'https://rubygems.org'\ngem 'rails', '7.0.0'\n" > "$R/Gemfile"; _dd_commit "$R" "base"
printf "source 'https://rubygems.org'\ngem 'rails', '7.0.0'\ngem SOME_CONST\n" > "$R/Gemfile"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "STATE=unavailable" "$OUT" "a dynamic gem line makes the file unreadable"
assert_contains "MANIFEST_UNPARSED=Gemfile" "$OUT" "the Gemfile is named"
assert_not_contains "STATE=none" "$OUT" "not reported as no-change"

_flow_test_begin "a readable manifest beside an unreadable one still reports its packages"
# Withholding what was read helps nobody; the answer is incomplete and says so.
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"
printf '{"dependencies":{}}\n' > "$R/package.json"
_dd_commit "$R" "base"
printf 'flask==2.0.0\nrequests==2.31.0\n' > "$R/requirements.txt"
printf '{"dependencies": BROKEN\n' > "$R/package.json"
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_ADDED=requests@2.31.0" "$OUT" "the manifest that parsed is still reported"
assert_contains "MANIFEST_UNPARSED=package.json" "$OUT" "the one that did not is named"
assert_contains "STATE=unavailable" "$OUT" "the overall answer is incomplete"
assert_contains "MANIFESTS_EXAMINED=2" "$OUT" "both were attempted"

# =============================================================================
# Per-ecosystem: added, version-changed, removed
# =============================================================================

# _dd_eco <label> <file> <base-content> <head-content> <added> <changed> <removed>
_dd_eco() {
  local label="$1" file="$2" base="$3" head="$4" exp_a="$5" exp_c="$6" exp_r="$7"
  local R OUT
  R=$(_dd_repo)
  mkdir -p "$(dirname "$R/$file")"
  printf '%s' "$base" > "$R/$file"; _dd_commit "$R" "base"
  printf '%s' "$head" > "$R/$file"; _dd_commit "$R" "head"
  OUT=$(_dd_run "$R" HEAD~1 HEAD)
  assert_contains "STATE=ok" "$OUT" "$label: readable"
  assert_contains "MANIFESTS_EXAMINED=1" "$OUT" "$label: one manifest examined"
  assert_contains "$exp_a" "$OUT" "$label: added"
  assert_contains "$exp_c" "$OUT" "$label: version-changed"
  assert_contains "$exp_r" "$OUT" "$label: removed"
}

# _dd_untouched <label> <file> <content> <non-dep-edit>
# The fourth per-ecosystem state: the manifest is in the diff, but nothing
# about its dependencies changed. The edit must be a real one a person would
# make — a JSON manifest admits no comments, so "change a comment" is not a
# case that exists for package.json, package-lock.json or Cargo.lock, and an
# untouched fixture built only on comments never reaches them.
_dd_untouched() {
  local label="$1" file="$2" base="$3" head="$4"
  local R OUT
  R=$(_dd_repo)
  mkdir -p "$(dirname "$R/$file")"
  printf '%s' "$base" > "$R/$file"; _dd_commit "$R" "base"
  printf '%s' "$head" > "$R/$file"; _dd_commit "$R" "non-dependency edit"
  OUT=$(_dd_run "$R" HEAD~1 HEAD)
  assert_contains "MANIFESTS_EXAMINED=1" "$OUT" "$label untouched: the manifest was examined"
  assert_not_contains "STATE=none" "$OUT" "$label untouched: not reported as never looked at"
  assert_not_contains "DEP_ADDED=" "$OUT" "$label untouched: nothing added"
  assert_not_contains "DEP_CHANGED=" "$OUT" "$label untouched: nothing changed"
  assert_not_contains "DEP_REMOVED=" "$OUT" "$label untouched: nothing removed"
}

_flow_test_begin "npm package.json: added, changed, removed"
_dd_eco "package.json" "package.json" \
'{
  "dependencies": {
    "left-pad": "1.0.0",
    "lodash": "4.17.0"
  }
}
' \
'{
  "dependencies": {
    "left-pad": "1.1.0",
    "express": "4.18.2"
  }
}
' \
"DEP_ADDED=express@4.18.2" "DEP_CHANGED=left-pad 1.0.0->1.1.0" "DEP_REMOVED=lodash"

_flow_test_begin "npm package-lock.json: added, changed, removed"
_dd_eco "package-lock.json" "package-lock.json" \
'{
  "lockfileVersion": 3,
  "packages": {
    "node_modules/left-pad": { "version": "1.0.0" },
    "node_modules/lodash": { "version": "4.17.0" }
  }
}
' \
'{
  "lockfileVersion": 3,
  "packages": {
    "node_modules/left-pad": { "version": "1.1.0" },
    "node_modules/express": { "version": "4.18.2" }
  }
}
' \
"DEP_ADDED=express@4.18.2" "DEP_CHANGED=left-pad 1.0.0->1.1.0" "DEP_REMOVED=lodash"

_flow_test_begin "npm yarn.lock v1: added, changed, removed"
_dd_eco "yarn.lock" "yarn.lock" \
'left-pad@^1.0.0:
  version "1.0.0"

lodash@^4.17.0:
  version "4.17.0"
' \
'left-pad@^1.1.0:
  version "1.1.0"

express@^4.18.2:
  version "4.18.2"
' \
"DEP_ADDED=express@4.18.2" "DEP_CHANGED=left-pad 1.0.0->1.1.0" "DEP_REMOVED=lodash"

_flow_test_begin "npm pnpm-lock.yaml: added, changed, removed"
_dd_eco "pnpm-lock.yaml" "pnpm-lock.yaml" \
'lockfileVersion: 5.4
packages:
  /left-pad/1.0.0:
    dev: false
  /lodash/4.17.0:
    dev: false
' \
'lockfileVersion: 5.4
packages:
  /left-pad/1.1.0:
    dev: false
  /express/4.18.2:
    dev: false
' \
"DEP_ADDED=express@4.18.2" "DEP_CHANGED=left-pad 1.0.0->1.1.0" "DEP_REMOVED=lodash"

_flow_test_begin "python requirements.txt: added, changed, removed"
_dd_eco "requirements.txt" "requirements.txt" \
'# pinned here
flask==2.0.0
click==8.0.0
' \
'# pinned here
flask==2.1.0
requests==2.31.0
' \
"DEP_ADDED=requests@2.31.0" "DEP_CHANGED=flask 2.0.0->2.1.0" "DEP_REMOVED=click"

_flow_test_begin "python requirements-dev.txt matches the requirements pattern"
_dd_eco "requirements-dev.txt" "requirements-dev.txt" \
'pytest==7.0.0
mypy==1.5.0
' \
'pytest==8.0.0
black==24.1.0
' \
"DEP_ADDED=black@24.1.0" "DEP_CHANGED=pytest 7.0.0->8.0.0" "DEP_REMOVED=mypy"

_flow_test_begin "python pyproject.toml PEP 621: added, changed, removed"
_dd_eco "pyproject.toml" "pyproject.toml" \
'[project]
name = "demo"
dependencies = [
  "flask==2.0.0",
  "click==8.0.0",
]
' \
'[project]
name = "demo"
dependencies = [
  "flask==2.1.0",
  "requests==2.31.0",
]
' \
"DEP_ADDED=requests@2.31.0" "DEP_CHANGED=flask 2.0.0->2.1.0" "DEP_REMOVED=click"

_flow_test_begin "python poetry.lock: added, changed, removed"
_dd_eco "poetry.lock" "poetry.lock" \
'[[package]]
name = "flask"
version = "2.0.0"

[[package]]
name = "click"
version = "8.0.0"
' \
'[[package]]
name = "flask"
version = "2.1.0"

[[package]]
name = "requests"
version = "2.31.0"
' \
"DEP_ADDED=requests@2.31.0" "DEP_CHANGED=flask 2.0.0->2.1.0" "DEP_REMOVED=click"

_flow_test_begin "go go.mod: added, changed, removed"
_dd_eco "go.mod" "go.mod" \
'module example.com/demo

go 1.21

require (
	github.com/pkg/errors v0.9.0
	github.com/spf13/cobra v1.7.0
)
' \
'module example.com/demo

go 1.21

require (
	github.com/pkg/errors v0.9.1
	github.com/stretchr/testify v1.9.0
)
' \
"DEP_ADDED=github.com/stretchr/testify@v1.9.0" \
"DEP_CHANGED=github.com/pkg/errors v0.9.0->v0.9.1" \
"DEP_REMOVED=github.com/spf13/cobra"

_flow_test_begin "go go.sum: added, changed, removed"
_dd_eco "go.sum" "go.sum" \
'github.com/pkg/errors v0.9.0 h1:aaa=
github.com/spf13/cobra v1.7.0 h1:bbb=
' \
'github.com/pkg/errors v0.9.1 h1:ccc=
github.com/stretchr/testify v1.9.0 h1:ddd=
' \
"DEP_ADDED=github.com/stretchr/testify@v1.9.0" \
"DEP_CHANGED=github.com/pkg/errors v0.9.0->v0.9.1" \
"DEP_REMOVED=github.com/spf13/cobra"

_flow_test_begin "rust Cargo.toml: added, changed, removed"
_dd_eco "Cargo.toml" "Cargo.toml" \
'[package]
name = "demo"

[dependencies]
serde = "1.0.180"
regex = "1.9.0"
' \
'[package]
name = "demo"

[dependencies]
serde = "1.0.190"
tokio = { version = "1.35.0", features = ["full"] }
' \
"DEP_ADDED=tokio@1.35.0" "DEP_CHANGED=serde 1.0.180->1.0.190" "DEP_REMOVED=regex"

_flow_test_begin "rust Cargo.lock: added, changed, removed"
_dd_eco "Cargo.lock" "Cargo.lock" \
'[[package]]
name = "serde"
version = "1.0.180"

[[package]]
name = "regex"
version = "1.9.0"
' \
'[[package]]
name = "serde"
version = "1.0.190"

[[package]]
name = "tokio"
version = "1.35.0"
' \
"DEP_ADDED=tokio@1.35.0" "DEP_CHANGED=serde 1.0.180->1.0.190" "DEP_REMOVED=regex"

_flow_test_begin "ruby Gemfile: added, changed, removed"
_dd_eco "Gemfile" "Gemfile" \
"source 'https://rubygems.org'
gem 'rails', '7.0.0'
gem 'puma', '6.0.0'
" \
"source 'https://rubygems.org'
gem 'rails', '7.1.0'
gem 'sidekiq', '7.2.0'
" \
"DEP_ADDED=sidekiq@7.2.0" "DEP_CHANGED=rails 7.0.0->7.1.0" "DEP_REMOVED=puma"

_flow_test_begin "ruby Gemfile.lock: added, changed, removed"
_dd_eco "Gemfile.lock" "Gemfile.lock" \
'GEM
  remote: https://rubygems.org/
  specs:
    rails (7.0.0)
    puma (6.0.0)
' \
'GEM
  remote: https://rubygems.org/
  specs:
    rails (7.1.0)
    sidekiq (7.2.0)
' \
"DEP_ADDED=sidekiq@7.2.0" "DEP_CHANGED=rails 7.0.0->7.1.0" "DEP_REMOVED=puma"

# -----------------------------------------------------------------------------
# The fourth state, per ecosystem: the manifest changed, the dependencies did not
# -----------------------------------------------------------------------------

_flow_test_begin "an untouched dependency set is examined, per manifest format"

_dd_untouched "package.json" "package.json" \
'{
  "name": "demo",
  "dependencies": { "left-pad": "1.0.0" }
}
' \
'{
  "name": "demo-renamed",
  "dependencies": { "left-pad": "1.0.0" }
}
'

_dd_untouched "package-lock.json" "package-lock.json" \
'{
  "name": "demo",
  "lockfileVersion": 3,
  "packages": { "node_modules/left-pad": { "version": "1.0.0" } }
}
' \
'{
  "name": "demo-renamed",
  "lockfileVersion": 3,
  "packages": { "node_modules/left-pad": { "version": "1.0.0" } }
}
'

_dd_untouched "yarn.lock" "yarn.lock" \
'# yarn lockfile v1
left-pad@^1.0.0:
  version "1.0.0"
' \
'# yarn lockfile v1
# regenerated
left-pad@^1.0.0:
  version "1.0.0"
'

_dd_untouched "pnpm-lock.yaml" "pnpm-lock.yaml" \
'lockfileVersion: 5.4
packages:
  /left-pad/1.0.0:
    dev: false
' \
'lockfileVersion: 5.4
packages:
  /left-pad/1.0.0:
    dev: true
'

_dd_untouched "requirements.txt" "requirements.txt" \
'# pinned
flask==2.0.0
' \
'# pinned, see the release notes
flask==2.0.0
'

_dd_untouched "pyproject.toml" "pyproject.toml" \
'[project]
name = "demo"
dependencies = [
  "flask==2.0.0",
]
' \
'[project]
name = "demo"
description = "a demo"
dependencies = [
  "flask==2.0.0",
]
'

_dd_untouched "poetry.lock" "poetry.lock" \
'[[package]]
name = "flask"
version = "2.0.0"
description = "web framework"
' \
'[[package]]
name = "flask"
version = "2.0.0"
description = "a web framework"
'

_dd_untouched "go.mod" "go.mod" \
'module example.com/demo

go 1.21

require github.com/pkg/errors v0.9.0
' \
'module example.com/demo-renamed

go 1.21

require github.com/pkg/errors v0.9.0
'

_dd_untouched "go.sum" "go.sum" \
'github.com/pkg/errors v0.9.0 h1:aaa=
' \
'github.com/pkg/errors v0.9.0 h1:aaa=
github.com/pkg/errors v0.9.0/go.mod h1:bbb=
'

_dd_untouched "Cargo.toml" "Cargo.toml" \
'[package]
name = "demo"

[dependencies]
serde = "1.0.180"
' \
'[package]
name = "demo"
edition = "2021"

[dependencies]
serde = "1.0.180"
'

_dd_untouched "Cargo.lock" "Cargo.lock" \
'version = 3

[[package]]
name = "serde"
version = "1.0.180"
' \
'version = 4

[[package]]
name = "serde"
version = "1.0.180"
'

_dd_untouched "Gemfile" "Gemfile" \
"source 'https://rubygems.org'
gem 'rails', '7.0.0'
" \
"source 'https://rubygems.org'
# pinned until the next upgrade window
gem 'rails', '7.0.0'
"

_dd_untouched "Gemfile.lock" "Gemfile.lock" \
'GEM
  remote: https://rubygems.org/
  specs:
    rails (7.0.0)

BUNDLED WITH
   2.4.0
' \
'GEM
  remote: https://rubygems.org/
  specs:
    rails (7.0.0)

BUNDLED WITH
   2.5.1
'

_flow_test_begin "a manifest in a subdirectory is examined"
# Matching is on the basename; this repository's own manifest lives at
# plugins/flow/requirements.txt, not at the root.
R=$(_dd_repo)
mkdir -p "$R/services/api"
printf 'flask==2.0.0\n' > "$R/services/api/requirements.txt"; _dd_commit "$R" "base"
printf 'flask==2.0.0\nredis==5.0.1\n' > "$R/services/api/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_ADDED=redis@5.0.1 manifest=services/api/requirements.txt:2" "$OUT" \
  "the nested path and its line are reported"

# =============================================================================
# Location correctness — the line must be the line, not a guess
# =============================================================================

_flow_test_begin "the reported line is where the package is actually declared"
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf '# one\n# two\n# three\nflask==2.0.0\nredis==5.0.1\n' > "$R/requirements.txt"
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "manifest=requirements.txt:5" "$OUT" "redis is on line 5, after three comments"
assert_not_contains "manifest=requirements.txt:1" "$OUT" "not line 1"

_flow_test_begin "package.json line numbers come from the file, not the parse order"
# JSON object order and file order can disagree; a line derived from the parse
# would then point at a different package's row.
R=$(_dd_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dd_commit "$R" "base"
cat > "$R/package.json" <<'JEOF'
{
  "name": "demo",
  "dependencies": {
    "alpha": "1.0.0",
    "beta": "2.0.0"
  }
}
JEOF
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_ADDED=alpha@1.0.0 manifest=package.json:4" "$OUT" "alpha is on line 4"
assert_contains "DEP_ADDED=beta@2.0.0 manifest=package.json:5" "$OUT" "beta is on line 5"

# =============================================================================
# Baseline trust — the near-name comparison cannot use the head
# =============================================================================

_flow_test_begin "DEP_BASELINE comes from the base commit, never the head"
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'flask==2.0.0\nrequests==2.31.0\n' > "$R/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_BASELINE=flask" "$OUT" "a package present at the base is in the baseline"
assert_not_contains "DEP_BASELINE=requests" "$OUT" \
  "a package this change adds is NOT in its own baseline"

_flow_test_begin "a near-name to an existing package is reported"
# reqeusts is requests with two characters transposed: two substitutions.
R=$(_dd_repo)
printf 'requests==2.31.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'requests==2.31.0\nreqeusts==0.1.0\n' > "$R/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_NEAR_NAME=reqeusts ~ requests distance=2" "$OUT" \
  "an added name two edits from an existing one is flagged"

_flow_test_begin "two packages added together are not near-names of each other"
# Arriving in the same change is not evidence that one mimics the other; only
# the base names the project already trusted are a baseline. Both added names
# here are within distance 2 of one another, so a head-sourced baseline WOULD
# flag them — that is what makes this discriminating.
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'flask==2.0.0\nrequests==2.31.0\nreqeusts==0.1.0\n' > "$R/requirements.txt"
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_not_contains "DEP_NEAR_NAME=" "$OUT" \
  "two co-added names are not compared with each other"

_flow_test_begin "an unrelated added name raises no near-name"
R=$(_dd_repo)
printf 'requests==2.31.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'requests==2.31.0\nsqlalchemy==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_not_contains "DEP_NEAR_NAME=" "$OUT" "a distant name is not flagged"

# =============================================================================
# The comparison point is the merge base, not the tip of the base branch
# =============================================================================

_flow_test_begin "a package the base branch added after the fork is not a removal"
# With a two-dot diff, everything main did while the change was open reads as a
# reversal. A reviewer would be shown DEP_REMOVED for a package the change
# never touched — and the near-name baseline would contain it too.
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
git -C "$R" checkout --quiet -b feat
printf 'flask==2.0.0\nredis==5.0.1\n' > "$R/requirements.txt"; _dd_commit "$R" "feat adds redis"
git -C "$R" checkout --quiet -
printf 'flask==2.0.0\nnumpy==1.26.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base adds numpy"
BASE_BRANCH=$(git -C "$R" rev-parse --abbrev-ref HEAD)
git -C "$R" checkout --quiet feat
OUT=$( cd "$R" && "$DEP_DIFF" --base "$BASE_BRANCH" --head HEAD 2>&1 )
assert_contains "DEP_ADDED=redis@5.0.1" "$OUT" "what the change did add is reported"
assert_not_contains "DEP_REMOVED=numpy" "$OUT" \
  "what the base branch added is NOT reported as this change removing it"
assert_not_contains "DEP_BASELINE=numpy" "$OUT" \
  "nor does it enter the near-name baseline"
assert_contains "DIFF_BASE=" "$OUT" "the commit actually compared is named"

_flow_test_begin "a manifest only the base branch added is not counted as examined"
# The file listing must come from the merge base too, not only the content
# read. Listed against the base tip, a manifest main added after the fork
# appears in this change's diff as a deletion — and MANIFESTS_EXAMINED then
# counts a file the change never touched, which is the number a reviewer reads
# as "how much of your dependency surface did this look at".
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
git -C "$R" checkout --quiet -b feat
printf 'flask==2.0.0\nredis==5.0.1\n' > "$R/requirements.txt"; _dd_commit "$R" "feat adds redis"
git -C "$R" checkout --quiet -
printf '{"dependencies":{"lodash":"4.17.0"}}\n' > "$R/package.json"; _dd_commit "$R" "base adds package.json"
BASE_BRANCH=$(git -C "$R" rev-parse --abbrev-ref HEAD)
git -C "$R" checkout --quiet feat
OUT=$( cd "$R" && "$DEP_DIFF" --base "$BASE_BRANCH" --head HEAD 2>&1 )
assert_contains "MANIFESTS_EXAMINED=1" "$OUT" \
  "only the manifest this change actually touched is counted"
assert_not_contains "MANIFESTS_EXAMINED=2" "$OUT" \
  "the base branch's own new manifest is not in this change's surface"
assert_contains "DEP_ADDED=redis@5.0.1" "$OUT" "and the real addition is still reported"

# =============================================================================
# A value with whitespace cannot split the record into extra fields
# =============================================================================

_flow_test_begin "a version range carrying a space is quoted, not left bare"
# npm writes ">=1.0.0 <2.0.0" and a Gemfile writes "~> 7.0". Bare, the space
# ends the version field and `manifest=` is no longer the next one.
R=$(_dd_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dd_commit "$R" "base"
printf '{\n  "dependencies": {\n    "ranged": ">=1.0.0 <2.0.0"\n  }\n}\n' > "$R/package.json"
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains 'DEP_ADDED=ranged@">=1.0.0 <2.0.0" manifest=package.json:3' "$OUT" \
  "the range is one quoted field and manifest= still follows it"

_flow_test_begin "a manifest that declares a package on no findable line is file-level"
# A minified single-line package.json has no line to cite. finding-schema.md
# allows a file-level location; inventing :1 would point a reader at the brace.
R=$(_dd_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dd_commit "$R" "base"
printf '{"dependencies":{"minified":"1.0.0"}}\n' > "$R/package.json"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_ADDED=minified@1.0.0 manifest=package.json" "$OUT" "the file is cited"
assert_not_contains "manifest=package.json:1" "$OUT" "without a line it did not find"

_flow_test_begin "a Gemfile pessimistic constraint is quoted too"
R=$(_dd_repo)
printf "source 'https://rubygems.org'\n" > "$R/Gemfile"; _dd_commit "$R" "base"
printf "source 'https://rubygems.org'\ngem 'rails', '~> 7.0'\n" > "$R/Gemfile"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains 'DEP_ADDED=rails@"~> 7.0" manifest=Gemfile:2' "$OUT" \
  "the constraint is quoted"

# =============================================================================
# Requirement shapes that are not a package name
# =============================================================================

_flow_test_begin "a VCS or URL requirement is not read as a package called git"
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'flask==2.0.0\ngit+https://example.invalid/x.git#egg=thing\nhttps://example.invalid/w.whl\n' \
  > "$R/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_not_contains "DEP_ADDED=git@" "$OUT" "the scheme is not a package"
assert_not_contains "DEP_ADDED=https@" "$OUT" "nor is a bare URL"
assert_contains "STATE=ok" "$OUT" "and the manifest still reads"

_flow_test_begin "a Gemfile.lock requirement line is not read as a resolved gem"
# Under specs: a resolved gem is indented four spaces and its own requirements
# six. Matching both would report a transitive requirement as a direct gem.
R=$(_dd_repo)
printf 'GEM\n  specs:\n    rails (7.0.0)\n' > "$R/Gemfile.lock"; _dd_commit "$R" "base"
printf 'GEM\n  specs:\n    rails (7.1.0)\n      activesupport (= 7.1.0)\n' > "$R/Gemfile.lock"
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_CHANGED=rails" "$OUT" "the resolved gem is reported"
assert_not_contains "DEP_ADDED=activesupport" "$OUT" \
  "its six-space requirement line is not a gem the change added"

# =============================================================================
# The baseline is bounded
# =============================================================================

_flow_test_begin "a very large baseline is capped and says it was cut"
# The baseline goes into a reviewer's prompt; a lockfile bump must not crowd
# out the findings it exists to support.
R=$(_dd_repo)
python3 - "$R/requirements.txt" <<'PYEOF2'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(600):
        f.write("pkg%03d==1.0.0\n" % i)
PYEOF2
_dd_commit "$R" "base"
printf 'newthing==1.0.0\n' >> "$R/requirements.txt"; _dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_BASELINE_TRUNCATED=" "$OUT" "the cut is announced"
COUNT=$(printf '%s\n' "$OUT" | grep -c '^DEP_BASELINE=')
assert_equal "500" "$COUNT" "exactly the cap is printed"

# =============================================================================
# Install hooks — readable offline only from a lockfile
# =============================================================================

_flow_test_begin "package-lock hasInstallScript becomes DEP_INSTALL_HOOK"
R=$(_dd_repo)
printf '{"lockfileVersion":3,"packages":{}}\n' > "$R/package-lock.json"; _dd_commit "$R" "base"
cat > "$R/package-lock.json" <<'JEOF'
{
  "lockfileVersion": 3,
  "packages": {
    "node_modules/quiet-pkg": { "version": "1.0.0" },
    "node_modules/hooky": { "version": "2.0.0", "hasInstallScript": true }
  }
}
JEOF
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_contains "DEP_INSTALL_HOOK=hooky" "$OUT" "a package that runs an install script is named"
assert_not_contains "DEP_INSTALL_HOOK=quiet-pkg" "$OUT" "one that does not is not named"

# =============================================================================
# Author-controlled values cannot forge records
# =============================================================================

_flow_test_begin "a version carrying a record separator is refused, not printed"
# The manifest is inside the pull request under review, so its values are
# author-controlled. A value carrying a newline or a pipe would split one line
# into two forged records.
R=$(_dd_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dd_commit "$R" "base"
python3 - "$R/package.json" <<'PYEOF'
import json, sys
json.dump(
    {"dependencies": {"evil": "1.0.0|DEP_ADDED=sudo@9.9.9 manifest=x:1"}},
    open(sys.argv[1], "w"),
)
PYEOF
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_not_contains "DEP_ADDED=sudo@9.9.9" "$OUT" "the forged record does not appear"
assert_contains "DEP_ADDED=evil@(refused)" "$OUT" \
  "the package is still reported, and the refused value is marked as refused"
assert_not_contains "DEP_ADDED=evil@(unpinned)" "$OUT" \
  "not as (unpinned), which is what a manifest declaring no version prints"

_flow_test_begin "a name carrying a newline cannot open a second record"
R=$(_dd_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dd_commit "$R" "base"
python3 - "$R/package.json" <<'PYEOF'
import json, sys
json.dump(
    {"dependencies": {"ok-pkg": "1.0.0",
                      "bad\nDEP_ADDED=ghost@1.0.0 manifest=x:1": "2.0.0"}},
    open(sys.argv[1], "w"),
)
PYEOF
_dd_commit "$R" "head"
OUT=$(_dd_run "$R" HEAD~1 HEAD)
assert_not_contains "DEP_ADDED=ghost@1.0.0" "$OUT" "no forged record is emitted"
assert_contains "MANIFEST_UNPARSED=package.json" "$OUT" "the manifest is reported unreadable"
assert_contains "STATE=unavailable" "$OUT" "and the run says so"

# =============================================================================
# Argument handling
# =============================================================================

_flow_test_begin "a ref that does not resolve is unavailable, not none"
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
OUT=$(_dd_run "$R" "no-such-ref-here" HEAD)
assert_contains "STATE=unavailable" "$OUT" "an unresolvable ref is unavailable"
assert_not_contains "STATE=none" "$OUT" "not reported as no dependency change"

_flow_test_begin "usage errors exit non-zero without inventing a state"
R=$(_dd_repo)
printf 'x\n' > "$R/README.md"; _dd_commit "$R" "base"
( cd "$R" && "$DEP_DIFF" >/dev/null 2>&1 ); assert_exit 1 "$?" "no arguments is a usage error"
( cd "$R" && "$DEP_DIFF" --base HEAD >/dev/null 2>&1 ); assert_exit 1 "$?" "--base alone is a usage error"
( cd "$R" && "$DEP_DIFF" HEAD >/dev/null 2>&1 ); assert_exit 1 "$?" "a bare ref is a usage error"
( cd "$R" && "$DEP_DIFF" "--evil" >/dev/null 2>&1 ); assert_exit 1 "$?" "an option-shaped ref is refused"

_flow_test_begin "the positional form matches the flag form"
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'flask==2.0.0\nredis==5.0.1\n' > "$R/requirements.txt"; _dd_commit "$R" "head"
A=$(_dd_run "$R" HEAD~1 HEAD)
B=$( cd "$R" && "$DEP_DIFF" "HEAD~1..HEAD" 2>&1 )
assert_equal "$A" "$B" "<base>..<head> and --base/--head agree"

_flow_test_begin "mixing the positional and flag forms is refused"
R=$(_dd_repo)
printf 'x\n' > "$R/README.md"; _dd_commit "$R" "base"
( cd "$R" && "$DEP_DIFF" --base HEAD "HEAD~1..HEAD" >/dev/null 2>&1 )
assert_exit 1 "$?" "a half-specified range has no silent winner"

_flow_test_begin "an unimportable parser module is unavailable and exits non-zero"
# Issue #246: a bin/ helper that hands python3 a path it cannot resolve fails
# its import and exits 0 having done nothing. This helper must not join that
# class — a dependency read that did not happen is not a clean one.
R=$(_dd_repo)
printf 'flask==2.0.0\n' > "$R/requirements.txt"; _dd_commit "$R" "base"
printf 'flask==2.0.0\nredis==5.0.1\n' > "$R/requirements.txt"; _dd_commit "$R" "head"
cp "$DEP_DIFF" "$DD_SCRATCH/orphan-dep-diff.sh"   # no _flow_dep_parse.py beside it
chmod +x "$DD_SCRATCH/orphan-dep-diff.sh"
OUT=$( cd "$R" && "$DD_SCRATCH/orphan-dep-diff.sh" --base HEAD~1 --head HEAD 2>/dev/null )
RC=$?
assert_contains "STATE=unavailable" "$OUT" "it reports that it could not run"
assert_not_contains "STATE=none" "$OUT" "never as no dependency change"
assert_not_contains "DEP_ADDED=" "$OUT" "and reports no packages it did not read"
assert_exit 2 "$RC" "and exits non-zero rather than 0 having done nothing"

_flow_test_begin "the helper converts its module path for a native python3"
# The conversion is the identity on POSIX, so the check is that the boundary
# exists at all: on Windows a raw POSIX path is what breaks the import.
HELPER_SRC=$(cat "$DEP_DIFF")
assert_contains "cygpath -m" "$HELPER_SRC" "the documented conversion is used"
assert_contains "py_path" "$HELPER_SRC" "at a single named boundary"
assert_match 'FLOW_DEP_BIN="\$\(py_path' "$HELPER_SRC" \
  "and the module directory goes through it"

# =============================================================================
# This repository's own history — the acceptance criterion's named case
# =============================================================================

_flow_test_begin "the history these tests read is actually present"
# A depth-1 clone has no history, and the helper would then answer
# STATE=unavailable for a reason that has nothing to do with the code. Say so
# here rather than letting the next two tests fail as "unavailable is not ok".
# The workflow sets fetch-depth: 0 for exactly this.
DD_HISTORY=1
for SHA in 92fd253 4519858 6cda10e d6f730d; do
  if git -C "$REPO_ROOT" cat-file -e "$SHA^{commit}" 2>/dev/null; then
    _flow_assert_pass "commit $SHA is present"
  else
    DD_HISTORY=0
    _flow_assert_fail "commit $SHA is missing — the clone is shallow (needs fetch-depth: 0)"
  fi
done

_flow_test_begin "the helper reads this repository's own requirements.txt history"
# 4519858 is the commit that introduced plugins/flow/requirements.txt. Its
# comment block contains pip-install instructions, which is the
# comment-skipping case for free.
OUT=$( cd "$REPO_ROOT" && "$DEP_DIFF" 92fd253..4519858 2>&1 )
assert_contains "STATE=ok" "$OUT" "the range is readable"
assert_contains "MANIFESTS_EXAMINED=1" "$OUT" "one manifest examined"
assert_contains "DEP_ADDED=pyyaml@6.0.2 manifest=plugins/flow/requirements.txt:20" "$OUT" \
  "pyyaml is reported at its real line"
assert_contains "DEP_ADDED=jsonschema@4.23.0 manifest=plugins/flow/requirements.txt:26" "$OUT" \
  "jsonschema is reported at its real line"
assert_not_contains "DEP_ADDED=pip" "$OUT" "an install instruction in a comment is not a package"
assert_not_contains "DEP_ADDED=python3" "$OUT" "nor is the interpreter it names"

_flow_test_begin "a range touching no manifest in this repository reports none"
# Two FIXED commits, not `..HEAD`. Against HEAD this asserted something about
# whatever the current branch happens to touch, so it passed until this very
# branch pinned tomli in requirements.txt — and then failed on CI while still
# passing locally, because the edit was uncommitted when the suite last ran.
# A fixture whose meaning depends on the branch under test is not a fixture.
# 6cda10e..d6f730d changes 34 files and not one of them is a manifest.
OUT=$( cd "$REPO_ROOT" && "$DEP_DIFF" 6cda10e..d6f730d 2>&1 )
assert_contains "MANIFESTS_EXAMINED=0" "$OUT" "nothing was examined"
assert_contains "STATE=none" "$OUT" "and the state says none"

# =============================================================================
# agents/security-reviewer.md — the judgment step
# =============================================================================

SEC=$(cat "$SECURITY_MD")

_flow_test_begin "security-reviewer invokes the helper by name"
assert_contains "flow-dep-diff.sh" "$SEC" "Step 4 names the helper"
assert_contains "cascade-resolve.sh" "$SEC" "it resolves the plugin root the documented way"

_flow_test_begin "the Step 4 fence is syntactically valid bash"
# An unmarked or broken fence cannot be extracted, so nothing would test it.
FENCE=$(awk '/# DEP_STEP4_BEGIN/{f=1;next} /# DEP_STEP4_END/{f=0} f' "$SECURITY_MD")
assert_match "flow-dep-diff" "$FENCE" "the Step 4 block is extractable"
printf '%s\n' "$FENCE" > "$DD_SCRATCH/step4.sh"
bash -n "$DD_SCRATCH/step4.sh" 2>/dev/null
assert_exit 0 "$?" "the Step 4 fence parses as bash"

_flow_test_begin "the Step 4 fence actually runs and reaches the helper"
# A name-grep proves the string is present, not that the script is called —
# and an earlier version of this test accepted DEP_STATE=unavailable, which is
# exactly what the fence prints when it cannot FIND the helper. The assertion
# passed for the failure it was written to rule out.
#
# So: a scratch repository with a real origin, a manifest, and a branch that
# adds a package. Only a genuine helper invocation can produce that package's
# name, and only the helper prints MANIFESTS_EXAMINED.
DD_ORIGIN=$(mktemp -d -t flow-dd-origin.XXXXXX); DD_CLEANUP+=("$DD_ORIGIN")
DD_WORK=$(mktemp -d -t flow-dd-work.XXXXXX); DD_CLEANUP+=("$DD_WORK")
git init --quiet --bare "$DD_ORIGIN/repo.git" 2>/dev/null
git clone --quiet "$DD_ORIGIN/repo.git" "$DD_WORK/repo" 2>/dev/null
git -C "$DD_WORK/repo" config user.email "test@example.invalid"
git -C "$DD_WORK/repo" config user.name "flow test"
git -C "$DD_WORK/repo" config commit.gpgsign false
printf 'flask==2.0.0\n' > "$DD_WORK/repo/requirements.txt"
git -C "$DD_WORK/repo" add -A >/dev/null 2>&1
git -C "$DD_WORK/repo" commit --quiet -m "base" >/dev/null 2>&1
git -C "$DD_WORK/repo" branch -M main >/dev/null 2>&1
git -C "$DD_WORK/repo" push --quiet -u origin main >/dev/null 2>&1
printf 'flask==2.0.0\nredis==5.0.1\n' > "$DD_WORK/repo/requirements.txt"
git -C "$DD_WORK/repo" add -A >/dev/null 2>&1
git -C "$DD_WORK/repo" commit --quiet -m "add redis" >/dev/null 2>&1
OUT=$( cd "$DD_WORK/repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
       DEFAULT_BRANCH=main bash "$DD_SCRATCH/step4.sh" 2>&1 )
assert_contains "DEP_STATE=ok" "$OUT" "the fence reached the helper and it read the manifest"
assert_contains "DEP_ADDED=redis@5.0.1" "$OUT" \
  "and printed the package the branch added — only a real invocation can"
assert_contains "MANIFESTS_EXAMINED=1" "$OUT" "with the count only the helper emits"
assert_not_contains "was not found under the resolved plugin root" "$OUT" \
  "the helper was not merely missing"

_flow_test_begin "dependency findings enter the canonical schema"
assert_contains "category=dependency" "$SEC" "the category is named"
assert_contains "DEP-1" "$SEC" "an example finding ID uses the DEP- prefix"

_flow_test_begin "the claim that dependency results stay out of the marker is gone"
# This sentence is why a critical advisory with a fix available was telemetry
# rather than a merge blocker.
assert_not_contains "does not merge them into the FLOW_REVIEW_CYCLE marker" "$SEC" \
  "the exclusion claim is removed"
assert_not_contains "SEPARATE artifact from the canonical findings table" "$SEC" \
  "and so is the phrasing that carried it"

_flow_test_begin "the Dependency Audit table is kept as telemetry"
assert_contains "### Dependency Audit" "$SEC" "the audit table survives"

_flow_test_begin "the per-package checks are all stated"
# Matched case-insensitively: the prose capitalises these as list headings
# ("Install hooks"), and the contract is that the check is named, not how the
# heading is cased.
for CHECK in "[Aa]dvisory" "[Ll]icense" "[Ii]nstall hook" "[Ii]mport" "[Ee]dit distance"; do
  assert_match "$CHECK" "$SEC" "Step 4 names the $CHECK check"
done

_flow_test_begin "a license conflict is P1 with the six-field escalation"
assert_match "license.*P1|P1.*license" "$SEC" "a license conflict blocks"
assert_contains "six-field" "$SEC" "and escalates rather than deciding"

_flow_test_begin "an undetermined license is not reported as an absent one"
# npm view and go list -m reach the network; pip show only knows what is
# installed. A lookup that fails must not raise the no-license escalation.
assert_contains "undetermined" "$SEC" "the undetermined case is named"
assert_match "undetermined.*P2|P2.*undetermined" "$SEC" "it is P2, not the P1 escalation"

_flow_test_begin "the unimported check is LOW confidence"
# requirements.txt declares pyyaml and the code writes `import yaml`. A package
# name is not an import name, so this check states its real strength.
assert_match "import.*LOW|LOW.*import" "$SEC" "the unimported finding is LOW"
assert_contains "pyyaml" "$SEC" "and the agent is shown the case that proves why"

_flow_test_begin "an unavailable dependency read is reported, not treated as clean"
assert_contains "DEP_STATE=unavailable" "$SEC" "the agent handles the unavailable state"
assert_match "unavailable" "$SEC" "and the state is named in the prose"

# =============================================================================
# references/finding-schema.md — vocabulary
# =============================================================================

SCHEMA=$(cat "$SCHEMA_MD")

_flow_test_begin "the schema carries the dependency category and DEP- prefix"
assert_match '\| .dependency. \|' "$SCHEMA" "dependency is in the category vocabulary"
assert_match '\| .DEP-. \|' "$SCHEMA" "DEP- is in the ID prefix table"

# =============================================================================
# commands/review.md and commands/pr.md — dispatch prose
# =============================================================================

_flow_test_begin "both commands tell the security reviewer to route DEP- findings"
for F in "$REVIEW_MD" "$PR_MD"; do
  C=$(cat "$F")
  assert_contains "DEP-" "$C" "$(basename "$F") names the DEP- prefix"
  assert_contains "category=dependency" "$C" "$(basename "$F") names the category"
done

_flow_test_begin "neither command says dependency results stay out of the marker"
for F in "$REVIEW_MD" "$PR_MD"; do
  assert_not_contains "does not merge them into the FLOW_REVIEW_CYCLE" "$(cat "$F")" \
    "$(basename "$F") makes no exclusion claim"
done

# =============================================================================
# skills/capability-discovery — license tool probes
# =============================================================================

_flow_test_begin "capability-discovery probes for the four license tools"
CAP=$(cat "$CAPDISC_MD")
for TOOL in "license-checker" "pip-licenses" "cargo-license" "go-licenses"; do
  assert_contains "$TOOL" "$CAP" "capability-discovery probes $TOOL"
done
assert_match "(not installed|absent|silently)" "$CAP" \
  "an absent tool is reported rather than passed over"

_flow_test_begin "the probes reference names the per-ecosystem license read"
PROBES=$(cat "$PROBES_MD")
for CMD in "npm view" "pip show" "cargo metadata" "go list -m"; do
  assert_contains "$CMD" "$PROBES" "the reference names: $CMD"
done
