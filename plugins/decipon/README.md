# Decipon - Content Analysis & Deep Research Plugin

A Claude Code plugin combining two powerful capabilities:

1. **NCI Protocol** — Detects manipulation, propaganda, and disinformation patterns across 20 indicators
2. **Deep Research** — Comprehensive research using Time-Tested Diffusion methodology with source verification

## Overview

### NCI Analysis

Decipon analyzes content (text or URLs) across 20 manipulation indicators grouped into 5 composite factors:

| Factor | Weight | Categories |
|--------|--------|------------|
| Emotional Manipulation | 25% | Base emotional triggers, urgency, novelty, repetition, manufactured outrage |
| Suspicious Timing | 20% | Timing correlation, beneficiary analysis, historical parallels |
| Uniform Messaging | 20% | Message uniformity, bandwagon effects, rapid shifts |
| Tribal Division | 15% | Us-vs-them framing, simplistic narratives, false dilemmas |
| Missing Information | 20% | Context gaps, authority issues, dissent suppression, cherry-picking, fallacies, framing |

### Deep Research

Decipon also provides standalone deep research capabilities using Time-Tested Diffusion methodology:
- Iterative refinement through critique → research → refine cycles
- Source scoring with confidence levels (1-100)
- Contradiction detection and resolution
- Comprehensive reports with methodology transparency

## Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install decipon
```

## Commands

### `/decipon:analyze <content>`

Full NCI analysis with 20-category scoring and dual perspectives.

```bash
/decipon:analyze https://example.com/article
/decipon:analyze "BREAKING: Shocking report reveals what they don't want you to know!"
```

### `/decipon:score <content>`

Quick manipulation score (0-100) for rapid triage.

```bash
/decipon:score https://example.com/article
```

### `/decipon:verify <content>`

Verify factual claims using deep research methodology. Fact-checks key assertions and can update NCI scores.

```bash
/decipon:verify https://example.com/article
/decipon:verify --claims "90% of experts agree" "Studies show..."
```

### `/decipon:report <content> [--format json|markdown] [--output filename]`

Generate formal report for sharing/archiving.

```bash
/decipon:report https://example.com/article --format json --output analysis.json
```

### `/decipon:deep-research <topic>`

Conduct comprehensive research using Time-Tested Diffusion methodology.

```bash
/decipon:deep-research "Current state of nuclear fusion energy"
```

### `/decipon:quick-research <question>`

Quick research with source verification (2-3 searches, lighter than deep-research).

```bash
/decipon:quick-research "When did NIF achieve fusion ignition?"
```

### `/decipon:critique <content>`

Red team adversarial critique of a document or claim.

```bash
/decipon:critique /path/to/document.md
/decipon:critique "90% of experts agree that..."
```

## Recommended Workflow

1. **Quick triage**: `/decipon:score` - Get initial manipulation score
2. **Full analysis**: `/decipon:analyze` - If score > 25 (Moderate or higher)
3. **Fact-check**: `/decipon:verify` - If score > 50 (High or higher)
4. **Document**: `/decipon:report` - For formal records

## Severity Scale

| Score | Indicator | Risk Level |
|-------|-----------|------------|
| 0-25 | [·] | Low - Normal consumption |
| 26-50 | [!] | Moderate - Verify claims |
| 51-75 | [!!] | High - Cross-reference, strong skepticism |
| 76-100 | [!!!] | Severe - Likely manipulation |

## Key Features

- **Pattern-based detection**: Identifies manipulation techniques regardless of truth value
- **Dual perspectives**: Generates both manipulative and legitimate interpretations
- **Evidence-grounded**: Every score backed by specific quotes/patterns
- **URL support**: Fetches and analyzes web content via WebFetch
- **Deep research**: Comprehensive research with iterative refinement and source verification

---

## Deep Research Methodology

Decipon includes a complete deep research capability using **Time-Tested Diffusion** — an iterative methodology that treats research like a diffusion process: start with noise (rough draft), apply guidance (research brief), and denoise through cycles of critique → research → refine.

### When to Use Deep Research

| Use Case | Command |
|----------|---------|
| Complex questions requiring multiple sources | `/decipon:deep-research` |
| State-of-the-art surveys | `/decipon:deep-research` |
| Due diligence investigations | `/decipon:deep-research` |
| Quick factual verification | `/decipon:quick-research` |
| Adversarial critique of documents | `/decipon:critique` |

### The Deep Research Workflow

```
1. Clarify scope (if ambiguous)
2. Write research brief (guidance signal)
3. Generate initial draft from knowledge (noisy starting point)
4. Red team critique (identify gaps and weaknesses)
5. Targeted web search with reflection
6. Score sources and track contradictions
7. Refine draft (denoise)
8. Evaluate quality (score < 7? repeat 4-7, max 3 cycles)
9. Finalize report
```

### Key Principles

**Think After Every Search**: After each search, pause and reflect:
- What key facts did I find?
- What gaps remain?
- Do sources agree or conflict?
- Is another search needed?

**Source Scoring (1-100)**:
| Source Type | Confidence Range |
|-------------|------------------|
| Peer-reviewed, official docs | 85-100 |
| Government/institutional | 75-90 |
| Major news (Reuters, AP) | 70-85 |
| Industry publications | 50-75 |
| Blogs, forums | 20-50 |

**Contradiction Handling**:
1. Note contradictions explicitly
2. Check publication dates (prefer recent)
3. Evaluate source authority
4. Search for tie-breaker sources
5. If unresolved, present both views with confidence levels

### Output Format

```markdown
# Research Report

## Executive Summary
[Key findings in 2-3 paragraphs]

## Findings
[Organized by research questions, with inline citations]

## Methodology
[Sources consulted, confidence levels, unresolved contradictions]

## Limitations
[Gaps, uncertainties, disputed claims]

## Sources
[Numbered list with confidence indicators]
```

### Quick Research vs Deep Research

| Aspect | Quick Research | Deep Research |
|--------|----------------|---------------|
| Search budget | 2-3 searches | 5-10 searches |
| Iterations | Single pass | Up to 3 refinement cycles |
| Use when | Simple verification | Complex multi-faceted questions |
| Output | Brief answer with sources | Comprehensive report |

---

## Agents

The plugin includes specialized agents that can be invoked for specific tasks:

| Agent | Purpose |
|-------|---------|
| `nci-analyzer` | Performs full NCI content analysis |
| `perspective-generator` | Generates balanced dual perspectives |
| `claim-verifier` | Verifies claims using deep research |
| `deep-researcher` | Comprehensive research using TTD methodology |
| `fact-checker` | Verification specialist for claims |

## Deep Research + NCI Integration

Deep research integrates directly with NCI analysis for automated fact-checking. When analyzing content, deep research is **automatically triggered** based on NCI scores.

### Analysis Workflow (7 Steps)

```
1. Input Processing (text or URL)
2. Score all 20 categories (1-5 scale)
3. Calculate 5 composite factors
4. Calculate overall score (0-100)
5. Check deep research triggers ← Automatic verification
6. Generate perspectives (manipulative + legitimate)
7. Output report (includes verification results)
```

### Automatic Triggers

Deep research is automatically triggered when ANY condition is met:

| Trigger | Threshold | Verification Focus |
|---------|-----------|-------------------|
| Overall NCI Score | > 40 | Verify key claims |
| Suspicious Timing | > 3 | Correlate events, timeline |
| Authority Issues (Cat 16) | > 3 | Verify credentials |
| Cherry-Picking (Cat 18) | > 3 | Find omitted context |
| Historical Parallels | > 2 | Research precedent campaigns |

### When Triggers Met

1. Extract 3-5 key factual claims
2. Invoke `fact-checker` agent
3. Apply deep research methodology
4. Track verification results
5. Adjust NCI scores based on findings

### Verification Capabilities

- **Claim extraction**: Identifies key factual assertions
- **Source evaluation**: Scores source confidence (1-100)
- **Contradiction handling**: Tracks and resolves conflicting sources
- **Score adjustment**: Updates NCI scores based on verification findings

### Output Includes Verification

When deep research is triggered, the report includes:

```markdown
## Claim Verification
| Claim | Status | Confidence | Source |
|-------|--------|------------|--------|
| "90% of experts..." | CONTRADICTED | 85% | reuters.com |
| "Studies show..." | VERIFIED | 90% | nature.com |

**Score Adjustment**: 55 → 62 (+7 due to verification)
```

### Source Confidence Scale

| Source Type | Confidence |
|-------------|------------|
| Peer-reviewed research | 85-100 |
| Official documentation | 85-95 |
| Government/institutional | 75-90 |
| Major news (Reuters, AP) | 70-85 |
| Industry publications | 50-75 |
| Blogs/forums | 20-50 |

## The 20 Categories

### Emotional Manipulation
1. Base Emotional Triggers - Fear, anger, hope exploitation
2. Urgency Creation - Artificial time pressure
3. Novelty/Exclusivity - "Only we know" framing
4. Strategic Repetition - Key phrase hammering
5. Manufactured Outrage - Anger amplification

### Suspicious Timing
6. Timing Correlation - Convenient narrative emergence
7. Beneficiary Analysis - Who gains from belief
8. Historical Parallels - Matches known campaigns

### Uniform Messaging
9. Message Uniformity - Identical talking points
10. Bandwagon Effects - Social proof manipulation
11. Rapid Narrative Shifts - Coordinated pivots

### Tribal Division
12. Us-vs-Them Framing - Enemy creation
13. Simplistic Narratives - False simplicity
14. False Dilemmas - Binary choice forcing

### Missing Information
15. Context Gaps - Strategic omissions
16. Authority Issues - Credential manipulation
17. Dissent Suppression - Alternative silencing
18. Cherry-Picking - Selective evidence
19. Logical Fallacies - Reasoning errors
20. Framing/Priming - Perspective manipulation

## Methodology

The NCI Protocol uses pattern recognition rather than truth evaluation:
- Scores indicate manipulation risk, not accuracy
- Low scores don't mean "true"
- High scores don't mean "false"
- Focus is on HOW content persuades, not WHAT it claims

## License

MIT License - See LICENSE file for details.

## Author

Daniel Bentes

## Repository

https://github.com/synaptiai/synapti-marketplace
