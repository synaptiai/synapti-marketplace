# Synthesis Document Template

Template for per-pillar synthesis documents (`SYN-<pillar>.md`).

---

# [Pillar] Synthesis

**Generated:** {date}
**Evidence Objects Analyzed:** {count}
**Synthesis Confidence:** {high|medium|low}

---

## Executive Summary

{3-5 bullet points capturing the most important findings}

- **[Finding 1]** - {brief description} (EV-ids)
- **[Finding 2]** - {brief description} (EV-ids)
- **[Finding 3]** - {brief description} (EV-ids)
- **[Finding 4]** - {brief description} (EV-ids)
- **[Finding 5]** - {brief description} (EV-ids)

---

## Key Insights

### Insight 1: {Title}

**Observation:** {What the evidence shows}

**Evidence:**
- {EV-id-1} ({confidence}): {claim summary}
- {EV-id-2} ({confidence}): {claim summary}

**Implication:** {What this means for the product}

**Confidence:** {0.0-1.0} - {Why this confidence level}

---

### Insight 2: {Title}

**Observation:** {What the evidence shows}

**Evidence:**
- {EV-id-1} ({confidence}): {claim summary}
- {EV-id-2} ({confidence}): {claim summary}

**Implication:** {What this means for the product}

**Confidence:** {0.0-1.0} - {Why this confidence level}

---

### Insight 3: {Title}

{Continue pattern for each insight}

---

## Evidence Clusters

### Theme: {Theme Name}

| Evidence ID | Claim | Confidence |
|-------------|-------|------------|
| {EV-id} | {claim summary} | {confidence} |
| {EV-id} | {claim summary} | {confidence} |
| {EV-id} | {claim summary} | {confidence} |

**Pattern:** {What these evidence objects collectively show}

---

### Theme: {Theme Name}

{Continue pattern for each theme}

---

## Contradictions

### Contradiction 1: {Topic}

**Conflicting Evidence:**
- **{EV-id-1}** ({confidence}): {claim}
- **{EV-id-2}** ({confidence}): {claim}

**Analysis:**
- Confidence delta: {difference}
- Recency: {which is more recent}
- Authority: {which source is more authoritative}

**Resolution:** {Resolved|Unresolved}

{If resolved:}
**Winner:** {EV-id} because {reason}

{If unresolved:}
**Recommendation:** {How to handle - defer to decision, research more, etc.}

---

### Contradiction 2: {Topic}

{Continue pattern for each contradiction}

---

## Gaps and Uncertainties

### Gap 1: {Topic}

**What's Missing:** {Description of missing information}

**Impact:** {How this gap affects synthesis quality}

**Mitigation:** {How to proceed despite gap}

---

### Gap 2: {Topic}

{Continue pattern for each gap}

---

## Assumptions

Assumptions underlying this synthesis:

1. {Assumption from evidence objects}
2. {Assumption from evidence objects}
3. {Synthesis-level assumption}

---

## Recommended Decisions

The following topics require explicit decisions (DEC-*):

### Decision Needed: {Topic}

**Context:** {What the evidence shows}

**Options:**
1. {Option A} - supported by {EV-ids}
2. {Option B} - supported by {EV-ids}
3. {Option C} - supported by {EV-ids}

**Trade-offs:** {Brief trade-off analysis}

---

### Decision Needed: {Topic}

{Continue pattern for each decision}

---

## Cross-Pillar Connections

Connections to other pillars that should inform cross-synthesis:

| This Pillar Insight | Related Pillar | Connection |
|---------------------|----------------|------------|
| {insight} | {pillar} | {how they connect} |
| {insight} | {pillar} | {how they connect} |

---

## Evidence Index

All evidence objects used in this synthesis:

| ID | Claim Summary | Confidence | Used In |
|----|---------------|------------|---------|
| {EV-id} | {claim} | {conf} | {sections} |
| {EV-id} | {claim} | {conf} | {sections} |

---

## Usage Notes

When writing a synthesis:

1. **Every insight must cite evidence** - No unsupported claims
2. **Contradictions must be explicit** - Don't hide disagreements
3. **Gaps must be acknowledged** - Be honest about what's missing
4. **Decisions must be deferred** - Don't make decisions in synthesis

### Quality Checklist

- [ ] Every insight cites ≥2 evidence objects
- [ ] All contradictions are documented
- [ ] Gaps are identified with impact assessment
- [ ] Cross-pillar connections noted
- [ ] Decisions deferred (not made in synthesis)
