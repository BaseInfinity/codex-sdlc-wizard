# AI Setup Lanes

Adaptive GPT-5.6 guidance for repositories installed by this wizard. Sol `high` is the normal standing root driver for meaningful SDLC work. Terra and Luna remain available for bounded support work and measured experiments, but the wizard does not route ordinary coding away from Sol merely because a task looks routine.

This is guidance, not a hard lock. Maintainers may choose another profile explicitly, and update preserves that choice.

## Current Model Baseline

| Tier | Model | Standard API token price | Best fit |
|------|-------|--------------------------|----------|
| **Sol** | `gpt-5.6-sol` | $5 / 1M input, $30 / 1M output | Ambiguous, difficult, high-value coding and research |
| **Terra** | `gpt-5.6-terra` | $2.50 / 1M input, $15 / 1M output | Bounded implementation and supporting work with explicit verification |
| **Luna** | `gpt-5.6-luna` | $1 / 1M input, $6 / 1M output | Clear, repeatable, high-volume support tasks |

OpenAI's model guidance starts demanding agentic work on Sol and positions Terra and Luna for lighter or clearer work. Price alone does not determine the driver: independent coding results and developer reports remain harness-sensitive and mixed, and this repo has no completed representative local slices proving that its Terra-led profile preserves quality. The quality-first default therefore stays on Sol `high`.

## Adaptive Decision Stack

Make the decisions in this order:

1. **Start meaningful SDLC work on Sol `high`.** The root agent owns planning, implementation, verification, and synthesis.
2. **Keep clear low-risk support work bounded.** Terra or Luna may handle extraction, scans, summaries, or mechanical transforms when a Sol-owned task has an explicit verification boundary.
3. **Escalate only the difficult slice to `xhigh`.** Good triggers include security review, migrations, destructive operations, long-running research, and challenging coding where `high` leaves unresolved risk.
4. **Use Max for one exceptionally hard task.** Max gives one selected model more reasoning time.
5. **Use Ultra when parallelism is the point.** Ultra uses subagents and fits work that divides cleanly into independent workstreams.

Most tasks do not need `xhigh`, Max, or Ultra. None is a standing consumer default.

## Roles Are Optional

Codex does not require a permanent advisor/driver pair. The Sol `high` root normally owns the full task. Add an explorer, reviewer, or planner only when specialization removes real uncertainty or creates useful parallelism. The workflow must remain correct when heterogeneous subagent routing is unavailable or inherited from the root session.

## Setup A: Sol Quality-First

Recommended default for meaningful SDLC work.

| Work | Model | Effort |
|------|-------|--------|
| Root agent / driver | `gpt-5.6-sol` | `high` |
| Review | `gpt-5.6-sol` | `high` |
| Difficult or high-risk slice | `gpt-5.6-sol` | `xhigh` |
| Exceptional single task | `gpt-5.6-sol` | Max, only when justified |
| Parallel independent work | Sol root plus task-appropriate subagents | Ultra, only when the task divides cleanly |

Use this lane for normal agentic coding as well as architecture, complex features, releases, security-sensitive behavior, installer changes, migrations, and work that can damage a consumer repo. Repo scanning adapts escalation triggers and verification, not the standing driver.

## Setup B: Experimental Mixed

Explicit opt-in profile for measured efficiency trials, not a routine-work recommendation.

| Work | Model | Effort |
|------|-------|--------|
| Main pass | `gpt-5.6-terra` | `medium` |
| Review | `gpt-5.6-sol` | `high` via explicit command override |
| Difficult review or unresolved risk | `gpt-5.6-sol` | `xhigh` |

Use `mixed` only when the task is bounded, verification is strong, and the maintainer accepts the quality/latency tradeoff. `review_model` selects Sol but does not override the profile's global reasoning effort, so run `codex -c 'model_reasoning_effort="high"' review ...` for the required review gate. Record representative results before promoting it. Existing repos that explicitly selected `mixed` keep that choice during update; the wizard does not select it automatically.

## Setup C: Lightweight Support

Manual support lane for clear, low-risk, repeatable work. It is not a normal SDLC driver profile.

| Work | Model | Effort |
|------|-------|--------|
| Bounded support task | `gpt-5.6-terra` or `gpt-5.6-luna` | lowest reliable effort |
| Integration and acceptance | Sol root | `high` |

Good candidates include extraction, classification, structured summaries, tagging, and mechanical transforms. Secrets, security advisories, migrations, destructive bulk operations, and production-impacting changes are not lightweight support work.

## Repo-Aware Escalation

Setup scans the repository and records risk surfaces such as deployment tooling, databases, CI, and firmware. Generated `AGENTS.md` keeps Sol `high` as the normal baseline and names the detected surfaces where an agent should consider `xhigh` for the affected task.

This is task-scoped. A repository containing a database does not need every documentation edit to run at `xhigh`; a schema migration in that same repository often does.

## Wizard Model Profiles

The shipped profile names remain stable:

| Wizard profile | Main model | Review model | Use |
|----------------|------------|--------------|-----|
| `maximum` | `gpt-5.6-sol` high | Sol high in the same session | Default and normal quality-first driver |
| `mixed` | `gpt-5.6-terra` medium | `gpt-5.6-sol` high via explicit override | Experimental explicit opt-in efficiency trial |

`maximum` means the maximum **model tier** supplied by the wizard. It does not select Max reasoning. Luna remains manual because the lightweight lane is support work, not a standing root profile.

Fresh installs and profile-less updates select `maximum`. Updates preserve an explicitly selected `mixed` profile instead of silently overriding a maintainer decision.

## Evidence And Promotion Gate

This decision is quality-based, not pricing-only:

- official guidance supports Sol for demanding agentic work and lighter tiers for clearer supporting tasks
- public benchmark and developer reports vary by harness, token use, latency, and repository shape, so no single leaderboard or Reddit post is treated as universal proof
- the local [`benchmarks/model-experiment.csv`](benchmarks/model-experiment.csv) ledger must contain representative completed slices before `mixed` can become a recommendation
- until that gate passes, Sol `high` remains the default and `mixed` remains experimental

## Maintainer Exception

The `codex-sdlc-wizard` repository itself remains on `gpt-5.6-sol` at `xhigh` while its Sol `high` benchmark is unfinished. This is a narrow repo-maintainer exception for unusually meta, downstream-enforcement work; it is not the consumer default.

## See Also

- [`AGENTS.md`](AGENTS.md) - maintainer contract for this repo
- [OpenAI Codex model guidance](https://learn.chatgpt.com/docs/models) - models, efforts, Max, and Ultra
- [OpenAI reasoning guidance](https://developers.openai.com/api/docs/guides/reasoning#reasoning-effort) - high and xhigh use cases
- [OpenAI API pricing](https://developers.openai.com/api/docs/pricing) - current token pricing
- [Community Sol/Terra/Luna report](https://www.reddit.com/r/codex/comments/1uz7pua/sol_vs_terra_vs_luna_what_actually_worked_for_me/) - anecdotal evidence, not the promotion gate
- [claude-sdlc-wizard `AI_SETUP_LANES.md`](https://github.com/BaseInfinity/claude-sdlc-wizard/blob/main/AI_SETUP_LANES.md) - sibling lanes document
