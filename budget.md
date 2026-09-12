# Budget baseline

What one dispatch costs at Anthropic list price, one turn per API response, measured from the foreman plugin build (session `b26d3e91`, seven tasks), the team smoke run (`8f426bbe`), and the token-budget plan review, all with Fable 5.1 as the session model. The lead's calls per phase are the least certain input; each plan's `spend.md` corrects them.

| Dispatch | Model | Measured | Budget figure |
|---|---|---|---|
| architect, one pair member including the joint report | session model | $1.0 to $6.8 | $6 |
| implementer, one task | session model | $0.44 to $1.15 | $1 |
| implementer, one fix round | session model | $0.52 to $1.01 | $1 |
| reviewer, one task | Opus | $0.26 to $1.34 | $1 |
| reviewer, one re-review | Opus | $0.29 to $1.86 | $1 |
| reviewer, final pair member including the joint report | Opus | $1.81 to $2.68, plus $1.51 joint | $3 |
| final fix wave | session model | $1.93 to $5.71 | $4 |
| qa, one pass | Sonnet | $1.35 | $1.50 |
| lead, one API call | session model | $0.11 to $0.33 | $0.35 |

## Recipe

- intake: lead calls × $0.35. Fifty calls for a small feature, a hundred for a large one.
- plan-review: 2 × $6 + 10 lead calls ($3.50).
- execution, per task: $1 implementer + $1 reviewer + 30% fix allowance ($0.60) + 6 lead calls ($2.10). About $5 a task.
- qa: $1.50 + one fix cycle ($2) + 5 lead calls ($1.75).
- final-review: 2 × $3 + $4 fix wave + $1 re-review + 15 lead calls ($5.25).

Round to whole dollars. Put the counts you multiplied in the table's Counts cell so the architects can check the arithmetic.
