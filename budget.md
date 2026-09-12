# Budget baseline

What one dispatch costs at Anthropic list price, one turn per API response. Fable figures were measured from the foreman plugin build (session `b26d3e91`, seven tasks), the team smoke run (`8f426bbe`), and the token-budget plan review, all with Fable 5.1 as the session model. Rows marked estimated moved to Opus in 0.3.0 and take the Fable measurement halved until the next run's `spend.md` corrects them. The lead's calls per phase are the least certain input; each plan's `spend.md` corrects them.

| Dispatch | Model | Measured | Budget figure |
|---|---|---|---|
| architect, solo or one pair member including the joint report | Opus | $1.0 to $6.8 on Fable | $3 (estimated) |
| implementer, one task | Opus | $0.44 to $1.15 on Fable | $0.50 (estimated) |
| implementer, one fix round | Opus | $0.52 to $1.01 on Fable | $0.50 (estimated) |
| reviewer, one task | Opus | $0.26 to $1.34 | $1 |
| reviewer, one re-review | Opus | $0.29 to $1.86 | $1 |
| reviewer, final solo or one pair member including the joint report | Opus | $1.81 to $2.68, plus $1.51 joint | $3 |
| final fix wave | Opus | $1.93 to $5.71 on Fable | $2 (estimated) |
| qa, one pass | Sonnet | $1.35 | $1.50 |
| lead, one API call | session model | $0.11 to $0.33 | $0.35 |

## Recipe

- intake: lead calls × $0.35. Fifty calls for a small feature, a hundred for a large one.
- plan-review: architects × $3 (one for small, two for standard) + 10 lead calls ($3.50).
- execution, per task: $0.50 implementer + $1 reviewer + 30% fix allowance ($0.45) + 6 lead calls ($2.10). About $4 a task.
- final-review: reviewers × $3 (one for small, two for standard) + $1.50 qa + $2 fix wave + $1 re-review + 15 lead calls ($5.25).

Round to whole dollars. Put the counts you multiplied in the table's Counts cell so the architect can check the arithmetic.
