# Search Patterns Reference

## Contents
- [Think-After-Search Pattern](#think-after-search-pattern)
- [Query Construction](#query-construction)
- [Parallel Research](#parallel-research)
- [Domain-Specific Searches](#domain-specific-searches)
- [Deduplication](#deduplication)
- [Iteration Strategies](#iteration-strategies)

## Think-After-Search Pattern

**CRITICAL: Reflect after EVERY search.** This prevents aimless searching and creates strategic research.

### Reflection Template
After each `web_search`, pause and complete:

```
SEARCH: [query used]
RESULTS QUALITY: [Good/Partial/Poor]

REFLECTION:
1. Key facts found:
   - [Fact 1] (Confidence: [N])
   - [Fact 2] (Confidence: [N])

2. Gaps remaining:
   - [What's still missing]

3. Source agreement:
   - [Do sources agree? Any contradictions?]

4. Decision:
   - [ ] Search again (reason: [gap to fill])
   - [ ] Move to next sub-question
   - [ ] Have enough - proceed to refinement
```

### Example Reflection

```
SEARCH: "NIF fusion ignition December 2022 results"
RESULTS QUALITY: Good

REFLECTION:
1. Key facts found:
   - NIF achieved ignition Dec 5, 2022 (Confidence: 95)
   - Produced 3.15 MJ from 2.05 MJ input (Confidence: 95)
   - First time fusion produced net energy gain (Confidence: 90)

2. Gaps remaining:
   - Private sector landscape unknown
   - Timeline projections not addressed

3. Source agreement:
   - All sources agree on basic facts
   - Some variation in "significance" framing

4. Decision:
   - [x] Search again (reason: need private fusion companies)
```

## Query Construction

### Principles
- **Short queries**: 1-6 words optimal
- **Start broad**: Narrow only if too many results
- **No operators by default**: Add site:, OR, quotes only when needed

### Basic Patterns
```
[topic]                         # Start here
"[exact phrase]"                # When precision needed
[topic] site:edu OR site:gov    # Authority filter
[topic] -[exclude term]         # Remove noise
```

### Query Evolution
```
Round 1: "fusion energy progress"          # Broad
Round 2: "NIF ignition results"            # Narrowed after reflection
Round 3: "Commonwealth Fusion funding"     # Specific follow-up
```

## Parallel Research

Pursue multiple search threads simultaneously when:

### Trigger 1: Comparison Questions
```
User asks: "Compare React vs Vue vs Angular"

Parallel searches:
1. "React framework strengths weaknesses"
2. "Vue framework strengths weaknesses"  
3. "Angular framework strengths weaknesses"
```

### Trigger 2: Independent Sub-Questions
```
Research brief has 3 unrelated questions:
1. Market size
2. Key competitors
3. Regulatory environment

→ Can research each independently
```

### Trigger 3: Multiple Source Types Needed
```
Need both academic and practical perspectives:
1. "[topic] research study site:edu"
2. "[topic] industry report"
3. "[topic] user experience reddit OR forum"
```

### When NOT to Parallelize
- Sequential dependencies (need fact A to search for B)
- Simple questions (single search sufficient)
- Already have good coverage

### Parallel Research Format
```
PARALLEL RESEARCH BATCH:
Thread A: [Sub-topic 1]
  - Search 1: [query]
  - Search 2: [query]
  
Thread B: [Sub-topic 2]
  - Search 1: [query]
  
Thread C: [Sub-topic 3]
  - Search 1: [query]

[After all complete, merge findings]
```

## Domain-Specific Searches

### Academic/Scientific
```
[topic] peer-reviewed study
[topic] systematic review
[topic] meta-analysis
[author name] [topic]
```

### Business/Market
```
[company] market share
[industry] report
[company] SEC filing 10-K
[sector] analysis
```

### Technology
```
[technology] documentation
[tool] vs [alternative]
[framework] best practices
[library] changelog
```

### Current Events
```
[topic] news today
[event] latest
[topic] Reuters OR AP
```

### People
```
[name] LinkedIn
[name] interview
[name] [expertise area]
```

## Deduplication

### During Research
Track URLs to avoid redundant processing:

```
SOURCES CONSULTED:
- llnl.gov/news/fusion-ignition ✓
- nature.com/articles/fusion-milestone ✓
- sciencemag.org/news/nif-breakthrough ✓ (similar to nature)
```

### Recognizing Duplicates
- Same facts, different aggregators → cite primary only
- Same press release on multiple sites → cite original
- Wikipedia → trace to cited sources

### Handling Near-Duplicates
When multiple sources report same fact:
```
FACT: [Statement]
Primary source: [Original]
Also reported by: [List] (confirms, not additional evidence)
Confidence: [Higher due to confirmation]
```

## Iteration Strategies

### Expanding (Too Few/Poor Results)
```
"specific technical term" → broader category
"product X limitations" → "product X review"
[topic] [constraint] → [topic] alone
```

### Narrowing (Too Broad/Noisy)
```
[topic] → "[exact phrase]"
[topic] → [topic] [specific year]
[topic] → [topic] site:specific-domain.com
```

### Pivoting (Wrong Direction)
```
If results don't match intent:
1. Re-read research brief
2. Identify misalignment
3. Reformulate with different angle

Example:
"AI safety" → (returns alignment research)
Pivot to: "AI product safety testing" (if that's actual need)
```

### Stopping Criteria
Stop searching when:
- 3+ high-confidence sources agree on key facts
- Last 2 searches returned no new information
- Search budget exhausted (5-10 for complex topics)
- All questions in research brief addressed

### Recognizing Diminishing Returns
```
Search 1: 5 new facts
Search 2: 3 new facts  
Search 3: 1 new fact
Search 4: 0 new facts ← Stop here
```

## Anti-Patterns

### Avoid
- Searching without reflecting
- Repeating similar queries hoping for different results
- Ignoring contradictory sources
- Stopping at first result
- Over-searching simple questions
- Under-searching complex questions

### Recovery
If stuck in unproductive searching:
1. Stop and review research brief
2. List what you have vs what you need
3. Single targeted search for biggest gap
4. Accept "good enough" if budget exhausted
