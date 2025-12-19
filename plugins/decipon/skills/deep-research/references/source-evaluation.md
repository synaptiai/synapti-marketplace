# Source Evaluation Reference

## Contents
- [Confidence Scoring System](#confidence-scoring-system)
- [Source Type Guidelines](#source-type-guidelines)
- [Fact Tracking Format](#fact-tracking-format)
- [Contradiction Handling](#contradiction-handling)
- [Context Management](#context-management)
- [Common Pitfalls](#common-pitfalls)

## Confidence Scoring System

Every fact should be tracked with a confidence score (1-100) based on source quality.

### Base Scores by Source Type

| Source Type | Base Range | Notes |
|-------------|------------|-------|
| Peer-reviewed research | 85-100 | Highest for recent, high-impact journals |
| Official documentation | 85-95 | Direct from organization/product |
| Government/institutional | 75-90 | Census, regulatory, research agencies |
| Established news (Reuters, AP) | 70-85 | Wire services highest |
| Major newspapers | 60-80 | Higher for investigative pieces |
| Industry publications | 50-75 | Trade journals, analyst reports |
| Company blogs/PR | 40-70 | High for facts about themselves |
| General blogs | 20-50 | Check author credentials |
| Forums/social media | 10-40 | Useful for sentiment, not facts |
| Anonymous/undated | 5-20 | Last resort only |

### Adjustment Factors

**Increase score (+5 to +15) for:**
- Recency (within last year for fast-moving topics)
- Author with relevant credentials
- Multiple independent confirmations
- Primary source (firsthand account)
- Includes methodology/citations

**Decrease score (-5 to -20) for:**
- Outdated information
- Obvious bias or agenda
- No author attribution
- Aggregator/secondary source
- Factual errors elsewhere in source
- SEO-heavy content farms

### Confidence Thresholds

- **90-100**: Can state as fact
- **70-89**: Can state with attribution
- **50-69**: Should note uncertainty
- **Below 50**: Mention only if no better source exists, with strong caveats

## Source Type Guidelines

### Academic/Scientific
```
web_search: "[topic] research paper OR study site:edu"
web_search: "[topic] systematic review"
```
- Prefer recent publications
- Check citation count if visible
- Note if preprint vs peer-reviewed

### Official/Primary
```
web_search: "[company/org] official announcement"
web_search: "[topic] site:gov OR site:org"
```
- Best for facts about organizations themselves
- Check for press release vs substantive content

### News
```
web_search: "[topic] news today"
web_search: "[event] Reuters OR AP"
```
- Wire services for breaking news
- Investigative pieces for depth
- Be cautious of opinion labeled as news

### Technical
```
web_search: "[technology] documentation official"
web_search: "[product] changelog OR release notes"
```
- Official docs trump third-party tutorials
- GitHub repos for open source projects

## Fact Tracking Format

Track every significant fact extracted from research:

```
FACT #[N]
Statement: [The factual claim]
Source: [URL]
Source Type: [Category from table above]
Confidence: [1-100]
Disputed: [Yes/No]
Dispute Notes: [If yes, what contradicts this]
Extracted: [Verbatim quote if available]
```

### Example Fact Tracking

```
FACT #1
Statement: NIF achieved fusion ignition in December 2022
Source: https://www.llnl.gov/news/...
Source Type: Government/institutional
Confidence: 95
Disputed: No
Extracted: "On Dec. 5, 2022, a team... produced more energy 
from fusion than the laser energy used to drive it"

FACT #2
Statement: Commercial fusion expected by 2035
Source: https://techblog.example.com/fusion-timeline
Source Type: General blog
Confidence: 35
Disputed: Yes
Dispute Notes: Official sources cite 2040-2050 range
```

## Contradiction Handling

When sources disagree, follow this protocol:

### Step 1: Identify the Contradiction
```
CONTRADICTION DETECTED:
Claim A: [Statement] (Source: [X], Confidence: [N])
Claim B: [Statement] (Source: [Y], Confidence: [M])
```

### Step 2: Analyze Differences
- Are they actually contradicting, or different aspects?
- Check dates - is one outdated?
- Check scope - different geographies/contexts?

### Step 3: Evaluate Source Authority
Compare using confidence scoring. Higher confidence source wins unless:
- Lower confidence source is more recent AND topic is fast-changing
- Lower confidence source is primary AND higher is secondary

### Step 4: Seek Tiebreaker
```
web_search: "[specific disputed claim]"
```
Find additional sources to resolve. Three sources agreeing typically breaks a tie.

### Step 5: Resolution Strategies

**If resolved:**
```
Initially contradictory reports existed, but [higher confidence source] 
confirms [fact]. The discrepancy appears due to [outdated info/different 
methodology/etc].
```

**If unresolved:**
```
Sources disagree on [topic]. [Source A] reports [X], while [Source B] 
reports [Y]. The discrepancy may reflect [uncertainty/evolving situation/
different definitions]. For this report, we note both perspectives.
```

### Never Do
- Silently pick one side without noting contradiction
- Average contradictory numbers without explanation
- Present disputed claims as certain facts

## Context Management

As research accumulates, manage cognitive load:

### Compression Triggers
Compress when:
- Raw notes exceed ~2000 words
- Same facts appearing from multiple sources
- Moving to a new sub-question

### Compression Process
```
RAW NOTES (before):
[Long excerpt from source 1...]
[Long excerpt from source 2...]
[Long excerpt from source 3...]

COMPRESSED (after):
Key findings on [topic]:
- [Fact 1] (Sources: 1, 2, 3 - Confidence: 85)
- [Fact 2] (Source: 2 - Confidence: 70)
- [Disputed: Fact 3] (Source 1 says X, Source 3 says Y)
```

### What to Preserve
- Specific facts with citations
- Confidence assessments
- Contradictions and disputes
- Key quotes (verbatim)

### What to Discard
- Redundant information (same fact from multiple sources)
- Boilerplate/navigation text
- Tangential information not relevant to research brief
- Low-confidence claims when high-confidence alternatives exist

## Common Pitfalls

### Confirmation Bias
- **Problem**: Only searching for supporting evidence
- **Fix**: Explicitly search for "[topic] criticism OR limitations"

### Source Laundering
- **Problem**: Citing an aggregator that cites the primary source
- **Fix**: Trace to primary source, cite that instead

### Recency Bias
- **Problem**: Assuming newest is most accurate
- **Fix**: Consider if older comprehensive source beats newer brief mention

### Authority Fallacy
- **Problem**: High-authority source on wrong topic
- **Fix**: MIT professor on physics ≠ expert on economics

### Single Source Reliance
- **Problem**: Major claims from one source only
- **Fix**: For critical claims, require 2+ independent confirmations
