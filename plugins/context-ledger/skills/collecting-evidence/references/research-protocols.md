# Research Protocols

Pillar-specific research guidance for evidence collection.

## General Protocol

All pillars follow this base protocol:

1. **Start with research questions** from `PILLARS.md`
2. **Prioritize authoritative sources** (peer-reviewed > industry reports > blogs)
3. **Track contradictions** explicitly
4. **Document assumptions** for every claim
5. **Assign honest confidence** (don't inflate)

---

## Market Pillar Protocol

### Research Priority
1. Market size and growth (TAM/SAM/SOM)
2. Pricing benchmarks
3. Market dynamics and trends
4. Segment analysis

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| Industry reports | Gartner, Forrester, IBISWorld | Market sizing |
| Public filings | SEC filings, annual reports | Competitor financials |
| News coverage | TechCrunch, industry press | Trend identification |
| Pricing pages | Competitor websites | Pricing benchmarks |

### Search Strategies
```
"[market] market size [year]"
"[market] industry report"
"[market] pricing trends"
"[market] growth forecast"
```

### Quality Signals
- Market size claims should cite methodology
- Growth rates should specify time period
- Pricing data should specify segment and geography

---

## Users Pillar Protocol

### Research Priority
1. User personas and segments
2. Pain points and jobs-to-be-done
3. Current workflows and tools
4. Adoption barriers

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| User interviews | Direct conversations | Pain points, workflows |
| Survey data | Internal or published surveys | Quantitative validation |
| Forum discussions | Reddit, Stack Overflow, communities | Unfiltered opinions |
| Review sites | G2, Capterra, ProductHunt | Feature requests, complaints |

### Search Strategies
```
"[user type] pain points"
"[user type] workflow [activity]"
"[tool category] reviews complaints"
"[user type] forum discussion [topic]"
```

### Quality Signals
- User quotes should be specific, not generic
- Pain points should be behavioral, not stated preferences
- Workflows should describe actual behavior, not aspirational

---

## Tech Pillar Protocol

### Research Priority
1. Technical feasibility assessment
2. Architecture options
3. Performance requirements
4. Dependency analysis

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| Documentation | Official docs, RFCs | Capability assessment |
| Benchmarks | Published performance data | Constraint identification |
| GitHub | Issues, discussions | Real-world problems |
| Technical blogs | Engineering blogs | Implementation learnings |

### Search Strategies
```
"[technology] scalability limits"
"[technology] vs [alternative] comparison"
"[technology] production issues"
"[technology] best practices [use case]"
```

### Quality Signals
- Performance claims should include methodology
- Architecture recommendations should cite scale requirements
- Dependency analysis should include version constraints

---

## Competitors Pillar Protocol

### Research Priority
1. Direct competitor identification
2. Feature comparison
3. Pricing analysis
4. Positioning and messaging

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| Product websites | Competitor sites | Features, pricing |
| Review sites | G2, Capterra | User sentiment |
| Job postings | LinkedIn, company sites | Strategic priorities |
| Press coverage | News, funding announcements | Business model, scale |

### Search Strategies
```
"[competitor] pricing"
"[competitor] vs [competitor]"
"[competitor] reviews"
"[competitor] funding valuation"
"alternatives to [competitor]"
```

### Quality Signals
- Feature lists should be verified, not assumed
- Pricing should specify plan/tier
- Market position claims should cite evidence

---

## Design Pillar Protocol

### Research Priority
1. UX patterns in the domain
2. Accessibility requirements
3. User flow best practices
4. Design system considerations

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| Design case studies | Medium, UX blogs | Pattern examples |
| Accessibility standards | WCAG, Section 508 | Compliance requirements |
| Competitor UX | Product screenshots, demos | Pattern analysis |
| User research | Usability studies | Validation |

### Search Strategies
```
"[product type] UX best practices"
"[product type] user flow design"
"[product type] accessibility requirements"
"[product type] design patterns"
```

### Quality Signals
- UX recommendations should cite user research
- Accessibility requirements should reference standards
- Patterns should show evidence of effectiveness

---

## Legal Pillar Protocol

### Research Priority
1. Regulatory requirements
2. Data handling obligations
3. Terms of service considerations
4. Intellectual property issues

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| Regulations | GDPR, CCPA, HIPAA texts | Compliance requirements |
| Legal analysis | Law firm blogs, guidance | Interpretation |
| Enforcement actions | FTC, ICO decisions | Precedent |
| Industry standards | SOC 2, ISO 27001 | Best practices |

### Search Strategies
```
"[regulation] requirements [industry]"
"[data type] legal obligations"
"[activity] terms of service requirements"
"[industry] compliance checklist"
```

### Quality Signals
- Legal claims should cite specific regulations
- Compliance requirements should specify jurisdiction
- Risk assessments should be conservative

---

## Ops Pillar Protocol

### Research Priority
1. Operational requirements
2. Support model needs
3. Infrastructure considerations
4. Monitoring and reliability

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| SRE resources | Google SRE book, blogs | Reliability practices |
| Vendor documentation | AWS, GCP, Vercel docs | Infrastructure options |
| Industry benchmarks | Uptime standards, SLAs | Requirement setting |
| Post-mortems | Public incident reports | Risk identification |

### Search Strategies
```
"[product type] SLA requirements"
"[scale] support volume estimates"
"[technology] operational best practices"
"[industry] uptime requirements"
```

### Quality Signals
- SLA requirements should cite customer expectations
- Infrastructure estimates should specify scale
- Support models should cite volume projections

---

## Economics Pillar Protocol

### Research Priority
1. Unit economics modeling
2. Cost structure analysis
3. Revenue model validation
4. Financial benchmarks

### Recommended Sources
| Source Type | Examples | Use For |
|-------------|----------|---------|
| SaaS benchmarks | OpenView, Bessemer reports | Metric targets |
| Public company data | SEC filings, earnings | Financial models |
| VC research | a16z, First Round blogs | Business model analysis |
| Pricing research | ProfitWell, Paddle data | Pricing optimization |

### Search Strategies
```
"[business model] unit economics benchmarks"
"[industry] CAC LTV benchmarks"
"[business model] gross margin targets"
"[stage] SaaS financial metrics"
```

### Quality Signals
- Financial metrics should specify stage/scale
- Benchmarks should cite sample size/methodology
- Cost models should itemize assumptions
