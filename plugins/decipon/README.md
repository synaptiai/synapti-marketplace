# Decipon - Content Analysis & Deep Research Plugin

A Claude Code plugin combining two powerful capabilities:

1. **NCI Protocol** — Detects manipulation, propaganda, and disinformation patterns across 20 indicators
2. **Deep Research** — Comprehensive research using Time-Tested Diffusion methodology with source verification

---

## Why Decipon?

### The Problem with Traditional Fact-Checking

Most content evaluation tools ask: "Is this true or false?" But this binary framing misses crucial nuances:

- **Factually accurate content can still manipulate** — statistics can be cherry-picked, context can be omitted, emotional triggers can be exploited, all while every claim is technically true
- **False claims can be presented without manipulation** — genuine mistakes, outdated information, and honest errors aren't propaganda
- **Truth verification is slow and often impossible** — by the time claims are verified, the narrative has already spread

### What Decipon Does Differently

Decipon asks a different question: **"How is this content trying to influence me?"**

This pattern-based approach:
- **Works instantly** — no external fact-checking databases required
- **Catches sophisticated manipulation** — identifies techniques even when claims are true
- **Provides actionable guidance** — severity levels with clear recommended actions
- **Generates balanced perspectives** — shows both manipulative and legitimate interpretations

### Who Benefits

| Role | How Decipon Helps |
|------|-------------------|
| **Journalists** | Quick triage of sources, identify propaganda campaigns |
| **Researchers** | Systematic analysis framework, reproducible methodology |
| **Analysts** | Detect influence operations, track narrative patterns |
| **Educators** | Teach media literacy with concrete examples |
| **Anyone online** | Develop critical thinking about content consumption |

---

## Design Philosophy

### Pattern Detection, Not Truth Arbitration

Decipon deliberately avoids declaring content "true" or "false." Instead, it identifies **manipulation techniques** — the rhetorical and psychological methods used to influence audiences. This design choice reflects several principles:

1. **Truth is often unknowable in real-time** — verification takes time; manipulation detection doesn't
2. **Techniques reveal intent** — heavy use of manipulation patterns suggests persuasion goals beyond information sharing
3. **Users make final judgments** — Decipon provides evidence and scores; users decide what to believe

### Dual Perspectives by Default

Every analysis generates two interpretations:
- **Manipulative interpretation** — how this content could be designed to deceive
- **Legitimate interpretation** — how this content could be genuine despite surface patterns

This forces intellectual honesty. Content that scores "high risk" might still be legitimate; content that scores "low risk" might still mislead. The dual perspective prevents false certainty.

### Tiered Depth for Different Needs

Not every piece of content needs a 20-category deep dive:
- **Quick triage** (`/score`) — 5 seconds, single number, rapid filtering
- **Full analysis** (`/analyze`) — comprehensive breakdown when scores warrant attention
- **Verification** (`/verify`) — fact-checking integration when claims need confirmation
- **Formal report** (`/report`) — archival documentation for serious concerns

---

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

**What's Good About /analyze:**
1. **Complete picture** — Scores all 20 manipulation categories with specific evidence from the content
2. **Dual perspective generation** — Forces consideration of both manipulative and legitimate interpretations
3. **Automatic deep research triggers** — When scores exceed thresholds, verification is recommended
4. **Evidence-grounded** — Every score backed by specific quotes and patterns, not subjective impressions

### `/decipon:score <content>`

Quick manipulation score (0-100) for rapid triage.

```bash
/decipon:score https://example.com/article
```

**What's Good About /score:**
1. **Instant filtering** — Get a single number in seconds to decide if deeper analysis is worthwhile
2. **Batch processing** — Quickly triage multiple pieces of content before committing time
3. **Clear thresholds** — Severity indicators ([·], [!], [!!], [!!!]) with recommended actions
4. **Gateway to depth** — Low scores mean move on; high scores trigger full analysis

### `/decipon:verify <content>`

Verify factual claims using deep research methodology. Fact-checks key assertions and can update NCI scores.

```bash
/decipon:verify https://example.com/article
/decipon:verify --claims "90% of experts agree" "Studies show..."
```

**What's Good About /verify:**
1. **Bridges patterns to facts** — Combines manipulation detection with truth verification
2. **Automatic claim extraction** — Identifies key factual assertions without manual selection
3. **Score adjustment** — Updates NCI scores based on verification findings
4. **Source confidence tracking** — Shows reliability of verification sources (1-100 scale)

### `/decipon:report <content> [--format json|markdown] [--output filename]`

Generate formal report for sharing/archiving.

```bash
/decipon:report https://example.com/article --format json --output analysis.json
```

**What's Good About /report:**
1. **Archival quality** — Structured format suitable for records and evidence
2. **Shareable** — Export to JSON for systems or Markdown for humans
3. **Complete methodology** — Includes analysis parameters for reproducibility
4. **Timestamped** — Documents when analysis was performed

### `/decipon:deep-research <topic>`

Conduct comprehensive research using Time-Tested Diffusion methodology.

```bash
/decipon:deep-research "Current state of nuclear fusion energy"
```

**What's Good About /deep-research:**
1. **Iterative refinement** — Multiple cycles of critique → research → improve, like academic peer review
2. **Contradiction tracking** — Explicitly identifies when sources disagree and attempts resolution
3. **Source scoring** — Every fact tagged with confidence level and source type
4. **Quality thresholds** — Continues refining until comprehensiveness and accuracy reach acceptable levels
5. **Methodology transparency** — Report includes how research was conducted, not just conclusions

### `/decipon:quick-research <question>`

Quick research with source verification (2-3 searches, lighter than deep-research).

```bash
/decipon:quick-research "When did NIF achieve fusion ignition?"
```

**What's Good About /quick-research:**
1. **Right-sized for simple questions** — 2-3 searches instead of 5-10+
2. **Still verifies sources** — Maintains confidence scoring even for quick lookups
3. **Clear scope** — Single-pass research for factual questions, not complex analysis
4. **Escalation path** — Easy to upgrade to deep-research if complexity warrants

### `/decipon:critique <content>`

Red team adversarial critique of a document or claim.

```bash
/decipon:critique /path/to/document.md
/decipon:critique "90% of experts agree that..."
```

**What's Good About /critique:**
1. **Adversarial by design** — Actively tries to find weaknesses, not confirm strengths
2. **Systematic weakness categories** — Logic flaws, evidence gaps, missing perspectives, accuracy issues
3. **Severity scoring** — Prioritizes which weaknesses matter most
4. **Actionable fixes** — Suggests how to address each identified weakness
5. **Quality assurance** — Use on your own research reports before sharing

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
- **Interactive workflows**: Structured dialogues using AskUserQuestion tool for better collaboration

---

## Interactive User Experience

All Decipon commands, agents, and skills use Claude Code's **AskUserQuestion tool** to enable structured, interactive dialogues at key decision points. This creates a better user experience through clear options with tradeoffs rather than open-ended questions.

### When Interactive Dialogue Triggers

| Trigger | Example |
|---------|---------|
| **Ambiguous input** | `/analyze` without content → asks for URL, text, or file |
| **Borderline scores** | Score 35-55 → offers full analysis, verification, or accept |
| **Multiple options** | 8 claims found → asks which to prioritize for verification |
| **Contradictions** | Sources disagree → presents resolution options |
| **Quality checkpoints** | After iteration 2 → continue refining or finalize? |

### Example Interaction

```
User: /analyze https://example.com/article

Claude: Analyzing content...

Score: 48/100 [!] (Moderate)

[Uses AskUserQuestion tool]
Question: "This content scores 48 (Moderate) - in the borderline range. What next?"
Options:
  1. Run full analysis for detailed breakdown (Recommended)
  2. Verify key claims with fact-checking
  3. Generate formal report for sharing
  4. Score is sufficient, no further action

User selects: Option 2

Claude: [Proceeds to verify claims using deep research methodology]
```

### Benefits

- **Clearer user intent**: Reduces misinterpretation of ambiguous requests
- **Informed decisions**: Users see tradeoffs for each option
- **Appropriate depth**: User controls triage vs. comprehensive analysis
- **Transparent workflows**: Users understand what's happening and why

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

## Architecture

### Context Isolation

Decipon leverages Claude Code's **forked context** feature for heavy analysis operations. Skills run in isolated sub-agent contexts, keeping the main conversation clean while performing multi-step analysis.

```
┌─────────────────────────────────────────────────┐
│              Main Conversation                   │
│  (stays clean, receives final results only)     │
└──────────────────────┬──────────────────────────┘
                       │ invokes
          ┌────────────┴────────────┐
          ▼                         ▼
┌──────────────────┐      ┌──────────────────┐
│  nci-analysis    │      │ deep-research    │
│  skill (forked)  │      │ skill (forked)   │
│                  │      │                  │
│ - 20 categories  │      │ - Research brief │
│ - Calculations   │      │ - 3 iterations   │
│ - Perspectives   │      │ - Source scoring │
└──────────────────┘      └──────────────────┘
```

### Benefits

- **Reduced context usage** — Heavy analysis doesn't pollute main conversation
- **Better isolation** — Skills do multi-step work independently
- **Clean results** — Final reports returned without intermediate noise

### Skills

| Skill | Context | Agent | Purpose |
|-------|---------|-------|---------|
| `nci-manipulation-analysis` | `fork` | `general-purpose` | 20-category manipulation detection |
| `conducting-deep-research` | `fork` | `general-purpose` | Time-Tested Diffusion methodology |

### Agents

The plugin includes specialized agents, each designed for a specific analytical task:

| Agent | Tools | Skills | Purpose |
|-------|-------|--------|---------|
| `deep-researcher` | Read, Write, Bash, Grep, Glob, WebSearch, WebFetch, AskUserQuestion | `conducting-deep-research` | Comprehensive research using TTD methodology |
| `fact-checker` | Read, Bash, Grep, Glob, WebSearch, WebFetch, AskUserQuestion | `conducting-deep-research` | Verification specialist for claims |
| `nci-analyzer` | Read, WebFetch, Grep, AskUserQuestion | `nci-manipulation-analysis` | Full NCI content analysis |
| `claim-verifier` | Read, Grep, Glob, WebSearch, WebFetch, AskUserQuestion | `conducting-deep-research`, `nci-manipulation-analysis` | Verifies claims with both methodologies |
| `perspective-generator` | Read, Grep, AskUserQuestion | `nci-manipulation-analysis` | Balanced dual perspectives |

#### When to Use Each Agent

| Scenario | Agent | Why |
|----------|-------|-----|
| "I need to understand a complex topic thoroughly" | `deep-researcher` | Multi-iteration research with source verification |
| "Is this specific claim true?" | `fact-checker` | Focused verification with confidence scoring |
| "How manipulative is this content?" | `nci-analyzer` | Full 20-category analysis with severity assessment |
| "I want both pattern analysis AND fact verification" | `claim-verifier` | Combines NCI scoring with deep research |
| "Give me both sides of this content" | `perspective-generator` | Balanced manipulative/legitimate interpretations |

#### What Makes Each Agent Valuable

**deep-researcher** — Goes beyond simple search by using iterative refinement. Each cycle: critique the current draft, research gaps, improve. Results in reports that have been stress-tested before delivery.

**fact-checker** — Specializes in verification rather than discovery. When you already know what claims need checking, this agent focuses on finding authoritative sources that confirm or contradict.

**nci-analyzer** — The core manipulation detection engine. Systematically evaluates content against 20 categories of manipulation techniques, generating quantified scores with specific evidence.

**claim-verifier** — The hybrid specialist. Combines manipulation pattern detection with factual verification, useful when you need both "how is this trying to influence me?" and "are the claims actually true?"

**perspective-generator** — Forces intellectual honesty by generating both charitable (legitimate) and critical (manipulative) interpretations of content, preventing confirmation bias in either direction.

### Agent Skill Auto-Loading

When an agent starts, it automatically loads its configured skills. This ensures:
- **Consistent methodology** — Agents always have access to their skill workflows
- **Reduced setup** — No manual skill invocation needed
- **Cross-skill integration** — `claim-verifier` loads both skills for hybrid analysis

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

## Examples

The `examples/` folder contains real outputs demonstrating Decipon's capabilities:

### Deep Research Report
**[psyops-research-report-2025.md](examples/psyops-research-report-2025.md)**

A comprehensive research report on the current state of psychological operations (PSYOP) techniques, produced using the `/decipon:deep-research` command. Demonstrates:
- Time-Tested Diffusion methodology in action
- Multi-source synthesis with confidence ratings
- Balanced coverage of multiple state actors (Russia, China, Iran, US, Israel)
- Structured findings with executive summary
- Full source tracking with confidence levels (1-100)

### Red Team Critique
**[psyops-critique-2025.md](examples/psyops-critique-2025.md)**

An adversarial critique of the research report above, produced using the `/decipon:critique` command. Demonstrates:
- Systematic weakness identification across 4 categories (Logic, Evidence, Coverage, Accuracy)
- Severity scoring (1-10) with prioritization
- Actionable fix recommendations
- Quality assurance for research outputs

### NCI Manipulation Analysis
**[psyops-research-report-2025-nci-analysis.md](examples/psyops-research-report-2025-nci-analysis.md)**

A full NCI analysis of the PSYOP research report, produced using the `/decipon:analyze` command. Demonstrates:
- Complete 20-category scoring with evidence for each category
- Composite factor calculations with weighted formulas
- Overall manipulation score: **11/100 [·]** (Low risk)
- Dual perspective generation (manipulative vs legitimate interpretations)
- Deep research trigger checking
- Visual "Information Nutrition Label" format

Key finding: The research report scored low for manipulation despite covering manipulation techniques, demonstrating the NCI's ability to distinguish educational content from propaganda.

### Example Workflow

```bash
# 1. Generate comprehensive research
/decipon:deep-research "Current state of psyops techniques"

# 2. Red team the output for weaknesses
/decipon:critique @research-report.md

# 3. Analyze for manipulation patterns (meta-analysis)
/decipon:analyze @research-report.md

# 4. Iterate based on critique and analysis findings
```

---

## Real-World Scenarios

### Scenario 1: News Article Triage

**Situation:** A breaking news article is circulating on social media with alarming claims. You want to assess it quickly before sharing.

```bash
/decipon:score https://news-site.com/breaking-story

# Output: 62/100 [!!] (High)
# "Recommend: Cross-reference sources, strong skepticism"
```

**Next step:** The high score warrants deeper investigation.

```bash
/decipon:analyze https://news-site.com/breaking-story
```

**What you learn:** The article uses heavy emotional language (Category 1: 4/5), creates artificial urgency (Category 2: 4/5), and lacks source attribution (Category 16: 4/5). The dual perspective reveals the content could be legitimate reporting on an emotional topic, but the pattern of techniques suggests amplification for engagement.

### Scenario 2: Due Diligence Research

**Situation:** You're evaluating a company for investment and need comprehensive background research.

```bash
/decipon:deep-research "TechCorp Inc business history and reputation"
```

**What you get:**
- Multi-source synthesis from news, regulatory filings, industry publications
- Confidence scores for each finding (peer-reviewed sources: 85-100, industry blogs: 20-50)
- Explicit tracking of contradictions between sources
- Quality-checked output after up to 3 refinement cycles

### Scenario 3: Content Creator Quality Check

**Situation:** You've written a research report and want to ensure it's credible and doesn't inadvertently use manipulation techniques.

```bash
# First, critique for weaknesses
/decipon:critique @my-research-report.md

# Then, analyze for unintentional manipulation patterns
/decipon:analyze @my-research-report.md
```

**What you learn:** The critique identifies logical gaps and missing perspectives. The NCI analysis confirms your report scores low for manipulation (educational content typically scores 5-20), but flags one area where emotional language crept in unintentionally.

### Scenario 4: Viral Claim Investigation

**Situation:** A specific claim is going viral: "Studies show that X causes Y in 90% of cases."

```bash
/decipon:verify "Studies show that X causes Y in 90% of cases"
```

**What you get:**
- Automatic extraction of verifiable assertions
- Deep research verification of each claim
- Source confidence ratings
- Status: VERIFIED / PARTIALLY TRUE / CONTRADICTED / UNVERIFIABLE
- Adjustment to any existing NCI scores based on findings

## License

Apache-2.0 - see the [LICENSE](../../LICENSE) file at the repository root.

## Author

Daniel Bentes

## Repository

https://github.com/synaptiai/synapti-marketplace
