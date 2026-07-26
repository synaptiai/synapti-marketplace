# Change triggers and blast radius

Which documents a change reaches, and when a document has gone stale even though
nothing changed.

`bin/dossier-blast-radius.sh` implements the matrix below. This file is the
explanation; the script is the behaviour. If they disagree, the script is what
runs and the disagreement is a defect in this file.

## Why a matrix at all

A refresh has two failure modes and they pull in opposite directions.

Regenerate everything on every merge and a dependency bump rewrites all
twenty-three documents. The run costs what a baseline costs, the diff is too
large to read, and the reviewer approves it without reading — which converts an
evidence-first package into a package that merely looks reviewed.

Regenerate only the obviously-affected document and the package contradicts
itself. A new API endpoint lands in `interfaces-and-integrations.md` while
`technical-partner-guide.md` still lists the old surface and the claim register
still approves the old claim. Both documents are internally consistent and the
package as a whole is now wrong.

The matrix is the middle. A change event implies a set of documents; a document
whose triggering event did not fire is left exactly as it was, including its
`last verified` date. Not touching a document is a claim in itself — it asserts
that the range contained no evidence bearing on it — so the mapping has to be
explicit enough to argue with.

## The source of the event list

The events come from the maintenance triggers the documentation system already
names: a change to product capability or limitation; architecture, interface,
schema, dependency or model; data collection, use, retention or location; a
security or privacy control; infrastructure, deployment, recovery or operational
ownership; a public claim, contractual commitment, supported platform or
integration behaviour; a material incident, audit finding or technical decision;
a release, or evidence older than the freshness threshold.

Every one of those is something a merged pull request routinely is. The matrix
turns each into a path pattern so the mapping can run without a human in the
loop.

## Events

Events are evaluated independently and a path may fire several. A migration
under `api/` is both a schema change and an interface change, and both document
sets are correct. Matching is case-sensitive and against the repository-relative
path.

### `dependency`

Dependency manifests and lockfiles: `package.json`, `package-lock.json`,
`yarn.lock`, `pnpm-lock.yaml`, `bun.lockb`, `pyproject.toml`, `poetry.lock`,
`uv.lock`, `Pipfile[.lock]`, `requirements*.txt`, `setup.py`, `setup.cfg`,
`go.mod`, `go.sum`, `Cargo.toml`, `Cargo.lock`, `Gemfile[.lock]`,
`composer.json`, `composer.lock`, `pom.xml`, `build.gradle[.kts]`,
`gradle.lockfile`, `packages.lock.json`, `*.csproj`, `Package.swift`,
`Package.resolved`, `Podfile[.lock]`, `mix.exs`, `mix.lock`, `pubspec.yaml`,
`pubspec.lock`, `dependabot.yml`, `renovate.json`.

Reaches:

- `05-due-diligence/assets-dependencies-and-licenses.md`
- `02-architecture/components-and-codebase.md`
- `03-assurance/security-privacy-and-compliance.md`
- `04-operating/onboarding-and-local-development.md`

A single changed line in a lockfile can move a licensing or supply-chain
conclusion that a thousand lines of application code would not, which is why
this event exists separately and why the evidence bundle extracts `deps.diff`.

### `interface`

`openapi*.{yaml,yml,json}`, `swagger*`, `asyncapi*`, `*.proto`, `*.graphql`,
`*.graphqls`, and anything under `api/`, `apis/`, `routes/`, `controllers/`,
`handlers/`, `endpoints/`, `graphql/`, `proto/`, `rpc/`, `sdk/`, `sdks/`.

Reaches:

- `02-architecture/interfaces-and-integrations.md`
- `02-architecture/system-architecture.md`
- `06-public/technical-partner-guide.md`
- `00-control/claim-and-disclosure-register.md`
- `00-control/terminology-and-ownership.md`

The public guide and the claim register are on this list because an interface
change is the most common way a public document silently becomes wrong. The
partner guide describes a surface; when the surface moves and the guide does
not, the package publishes a false statement.

### `data-and-schema`

`migrations/`, `migration/`, `db/`, `database/`, `prisma/`, `schema[s]/`,
`model[s]/`, `entities/`, `datastore/`, plus `schema.{sql,prisma,rb,graphql}`,
`*.sql` and `alembic.ini`.

Reaches:

- `02-architecture/data-and-ai.md`
- `03-assurance/security-privacy-and-compliance.md`
- `05-due-diligence/technical-due-diligence-report.md`
- `02-architecture/system-architecture.md`

### `ai-model`

`prompts/`, `models/`, `agents/`, `evals/`, `embeddings/`, `rag/`, `inference/`,
and source files whose names contain `prompt`, `llm`, `openai`, `anthropic`,
`bedrock`, `vertex`, `embedding` or `inference`.

Reaches:

- `02-architecture/data-and-ai.md`
- `03-assurance/security-privacy-and-compliance.md`
- `06-public/customer-product-and-trust-guide.md`
- `00-control/claim-and-disclosure-register.md`

The customer guide is here because AI involvement, its limitations and its human
oversight are things the product has to state accurately to users, and they
change with the model layer rather than with the interface.

### `security-control`

`auth/`, `authn/`, `authz/`, `security/`, `iam/`, `rbac/`, `permissions/`,
`crypto/`, `secrets/`, `policies/`, plus `SECURITY.md`, `.trivyignore`,
`.snyk`, `codeql*.yml`, and source files whose names contain `auth`, `oauth`,
`oidc`, `jwt`, `session`, `password`, `encrypt`, `tls` or `cert`.

Reaches:

- `03-assurance/security-privacy-and-compliance.md`
- `02-architecture/system-architecture.md`
- `05-due-diligence/technical-due-diligence-report.md`
- `06-public/customer-product-and-trust-guide.md`
- `00-control/claim-and-disclosure-register.md`

The widest radius in the matrix, deliberately. A security control is the class
of claim the package is least allowed to get wrong, and a control change that
does not reach the claim register can leave an approved public statement about
encryption or access control standing after the control behind it moved.

### `infrastructure`

`infra/`, `infrastructure/`, `terraform/`, `deploy/`, `deployment/`, `k8s/`,
`kubernetes/`, `helm/`, `charts/`, `ansible/`, `pulumi/`, `cdk/`, plus
`Dockerfile*`, `docker-compose*.yml`, `*.tf`, `*.tfvars`, `Chart.yaml`,
`values*.yml`, `serverless.yml`, `fly.toml`, `vercel.json`, `netlify.toml`,
`Procfile`, `wrangler.{toml,json,jsonc}`, `app.yaml`, `cloudbuild.yml`.

Reaches:

- `02-architecture/infrastructure-and-deployment.md`
- `04-operating/operations-and-incident-response.md`
- `03-assurance/reliability-performance-and-observability.md`
- `05-due-diligence/technical-due-diligence-report.md`

### `ci-delivery`

`.github/workflows/`, `.github/actions/`, `.gitlab-ci.yml`, `Jenkinsfile`,
`azure-pipelines.yml`, `.circleci`, `.buildkite`, `.travis.yml`,
`.pre-commit-config.yaml`.

Reaches:

- `03-assurance/testing-quality-and-delivery.md`
- `02-architecture/infrastructure-and-deployment.md`
- `04-operating/onboarding-and-local-development.md`

### `testing`

`test[s]/`, `spec[s]/`, `e2e/`, `__tests__/`, `testdata/`, `fixtures/`,
`*.test.*`, `*.spec.*`, and the common runner configs (`jest.config*`,
`vitest.config*`, `pytest.ini`, `tox.ini`, `playwright.config*`,
`cypress.config*`, `karma.conf*`).

Reaches:

- `03-assurance/testing-quality-and-delivery.md`

The narrowest radius in the matrix. A test change is evidence about quality
strategy and coverage and almost nothing else; widening it would make every
routine test edit regenerate the architecture documents for no gain.

### `observability`

`monitoring/`, `observability/`, `dashboards/`, `alerting/`, `telemetry/`, plus
`prometheus*.yml`, `alerts*.yml`, `otel*.yml`, `opentelemetry*.yml`,
`datadog*.yml`, `grafana/`.

Reaches:

- `03-assurance/reliability-performance-and-observability.md`
- `04-operating/operations-and-incident-response.md`

### `operations`

`runbook[s]/`, `ops/`, `operations/`, `playbook[s]/`, `oncall/`, plus
`RUNBOOK*.md`, `INCIDENT*.md`, `ONCALL*.md`, `DISASTER*.md`.

Reaches:

- `04-operating/operations-and-incident-response.md`
- `03-assurance/reliability-performance-and-observability.md`

### `public-claim`

`README*`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `LICENSE*`,
`NOTICE*`, `PRIVACY*.md`, `TERMS*.md`, and anything under `website/`, `site/`,
`www/`, `marketing/`, `landing/`, `public/`, `docs/public/`.

Reaches:

- `06-public/customer-product-and-trust-guide.md`
- `06-public/technical-partner-guide.md`
- `00-control/claim-and-disclosure-register.md`
- `01-project/executive-project-brief.md`
- `05-due-diligence/assets-dependencies-and-licenses.md`

A README edit is a public claim edit. It is the single most common way a project
starts asserting something it cannot evidence, which is why this event always
reaches the claim register rather than only the public documents.

### `release`

`CHANGELOG[.md]`, `HISTORY.md`, `RELEASES.md`, `VERSION`, `version.txt`,
`.release-please-manifest.json`, `release-please-config.json`.

Reaches:

- `01-project/executive-project-brief.md`
- `03-assurance/testing-quality-and-delivery.md`
- `06-public/customer-product-and-trust-guide.md`

A release changes the applicable product version in every header, which is
handled by the package contract rather than by this event. What the event
carries is the substantive change: what shipped, and what a customer can now
expect.

### `decision`

`adr[s]/`, `decisions/`, `architecture-decisions/`, `rfc[s]/` (at the repository
root or under `docs/`), and `ADR-<n>*.md`.

Reaches:

- `04-operating/decisions-technical-debt-and-risks.md`
- `02-architecture/system-architecture.md`
- `00-control/terminology-and-ownership.md`

### `onboarding`

`scripts/`, `tools/`, `bin/`, `hack/`, `.devcontainer/`, plus `Makefile`,
`justfile`, `Taskfile.yml`, `.tool-versions`, `.nvmrc`, `.python-version`,
`.ruby-version`, `docker-compose.{dev,local}*.yml`, `.env.example`,
`.env.sample`.

Reaches:

- `04-operating/onboarding-and-local-development.md`
- `02-architecture/components-and-codebase.md`

### `configuration`

`config/`, `configs/`, `settings/`, `conf/`, plus `config*.{yml,yaml,json,toml,ini}`,
`settings*.{yml,yaml,json,toml,ini}` and `*.env.*`.

Reaches:

- `02-architecture/components-and-codebase.md`
- `02-architecture/infrastructure-and-deployment.md`

### `product-capability`

The application source roots: `src/`, `lib/`, `app/`, `apps/`, `packages/`,
`internal/`, `cmd/`, `pkg/`, `components/`, `features/`, `pages/`, `server/`,
`services/`, `core/`, `domain/`, `web/`, `client/`, `frontend/`, `backend/`,
`ui/`.

Reaches:

- `01-project/product-and-domain.md`
- `01-project/executive-project-brief.md`
- `02-architecture/components-and-codebase.md`
- `02-architecture/system-architecture.md`
- `06-public/customer-product-and-trust-guide.md`
- `05-due-diligence/technical-due-diligence-report.md`
- `00-control/terminology-and-ownership.md`

The broadest matcher and therefore the most frequently fired. It is the reason
the exclude filters matter: without `**/*.test.*` and friends in
`dossier.ci.pathFilters.exclude`, every test file under `src/` would fire it.

## Always regenerated

Four documents are regenerated on every refresh, whatever fired:

- `00-control/documentation-index.md`
- `00-control/evidence-ledger.md`
- `00-control/assumptions-questions-and-contradictions.md`
- `07-verification/documentation-verification-report.md`

They are not views over the project. They are views over the package: the index
carries every document's status and last-verified date, the ledger carries the
evidence rows the refresh just added, the register carries whatever the refresh
could not resolve, and the verification report records what was and was not
checked this round. Any change to any document changes all four by definition.

## Reverse index

Which events reach each of the twenty-three canonical documents. A document with
no listed event is regenerated only by a full `/dossier:baseline`.

| Document | Triggering events |
|---|---|
| `00-control/documentation-index.md` | always |
| `00-control/evidence-ledger.md` | always |
| `00-control/assumptions-questions-and-contradictions.md` | always |
| `00-control/claim-and-disclosure-register.md` | interface, ai-model, security-control, public-claim |
| `00-control/terminology-and-ownership.md` | interface, decision, product-capability |
| `01-project/executive-project-brief.md` | public-claim, release, product-capability |
| `01-project/product-and-domain.md` | product-capability |
| `02-architecture/system-architecture.md` | interface, data-and-schema, security-control, decision, product-capability |
| `02-architecture/components-and-codebase.md` | dependency, onboarding, configuration, product-capability |
| `02-architecture/data-and-ai.md` | data-and-schema, ai-model |
| `02-architecture/interfaces-and-integrations.md` | interface |
| `02-architecture/infrastructure-and-deployment.md` | infrastructure, ci-delivery, configuration |
| `03-assurance/security-privacy-and-compliance.md` | dependency, data-and-schema, ai-model, security-control |
| `03-assurance/reliability-performance-and-observability.md` | infrastructure, observability, operations |
| `03-assurance/testing-quality-and-delivery.md` | ci-delivery, testing, release |
| `04-operating/onboarding-and-local-development.md` | dependency, ci-delivery, onboarding |
| `04-operating/operations-and-incident-response.md` | infrastructure, observability, operations |
| `04-operating/decisions-technical-debt-and-risks.md` | decision |
| `05-due-diligence/technical-due-diligence-report.md` | data-and-schema, security-control, infrastructure, product-capability |
| `05-due-diligence/assets-dependencies-and-licenses.md` | dependency, public-claim |
| `06-public/technical-partner-guide.md` | interface, public-claim |
| `06-public/customer-product-and-trust-guide.md` | ai-model, security-control, public-claim, release, product-capability |
| `07-verification/documentation-verification-report.md` | always |

## Unmatched paths

A changed path that fires no event is reported in `unmatched_sample` rather than
discarded. An unmatched path means the matrix has no rule for it, not that it is
irrelevant to documentation. Read the sample before concluding a refresh is
complete; a repository layout the matrix does not recognise shows up here first,
and the fix is to widen `dossier.ci.pathFilters.include` or the matrix itself,
not to trust a mapping that is quietly covering nothing.

## Staleness

Blast radius answers "what did this change reach". Staleness answers "what has
gone unverified for too long", which is the case the change-driven path cannot
see: a document nobody touched, describing behaviour nobody changed, whose
evidence was gathered against a version that no longer exists.

**The rule.** A document is stale when today minus its `last verified` date
exceeds `dossier.refresh.stalenessDays`, default 90. `docs-state.json` in the
evidence bundle carries every document's `last_verified`, read from its header,
so the check needs no extra pass over the package.

**`last verified` moves only for documents this refresh actually regenerated.**
This is the rule that makes the date mean anything. Stamping the whole package on
every run would produce twenty-three documents that all claim to have been
verified today, of which two were. A date that is always today is a date that
carries no information, and the package would be asserting freshness it never
established — the precise failure the system exists to prevent.

**A missing `last verified` is stale, not fresh.** No date means no evidence that
anyone ever confirmed the document. Treating the absence as "recently written"
would let a document that has never been verified pass a freshness check forever.

**Staleness does not by itself trigger a rewrite.** It is reported, in the index
and in the verification report, and it fails the release gate's freshness
condition. A refresh whose range contains nothing bearing on a stale document has
no new evidence to write into it; regenerating it anyway would produce prose
churn and a new date that stands for nothing. The correct response to staleness
is a verification pass, not a redraft — which is why `/dossier:audit` and
`/dossier:gate` own it and this file only defines it.

**The scheduled sweep is what makes staleness visible.** On a quiet repository
the merge trigger never fires, so without the sweep a package could sit
untouched past its threshold and nothing would say so. The sweep costs a policy
job that exits in well under a minute having spent no tokens, and its output on a
current repository is `reason=up-to-date` — which is itself the evidence that the
package is current rather than merely unexamined.
