# Documentation

Everything lives under one of four areas. If a document does not fit one of
them, it probably should not be committed.

| Area | What belongs here |
|---|---|
| [`ci/`](ci/) | Pipeline, browser matrix, deployment and release qualification |
| [`development/`](development/) | Setup, architecture, testing, branches, checkpoint history |
| [`data/`](data/) | Content standard and the numbers behind classes, weapons, bodies and maps |
| [`research/`](research/) | Source research reports and the decision summaries derived from them |

Top level:

- [`STATUS.md`](STATUS.md) — current state, stability, what is left, open questions
- [`ROADMAP.md`](ROADMAP.md) — sequencing and acceptance criteria
- [`BACKLOG.md`](BACKLOG.md) — open items, decisions and their status

## ci/

- [`ci/README.md`](ci/README.md) — what GitHub Actions runs and what it does not
- [`ci/BROWSER-MATRIX.md`](ci/BROWSER-MATRIX.md) — 13-cell browser matrix, tiers, manual protocol
- [`ci/DEPLOY.md`](ci/DEPLOY.md) — deployment plan and rollback

## development/

- [`development/SETUP.md`](development/SETUP.md) — local setup
- [`development/ARCHITECTURE.md`](development/ARCHITECTURE.md) — authority model, layers, events
- [`development/TESTING.md`](development/TESTING.md) — suites, reports, tooling
- [`development/FEATURE-BRANCHES.md`](development/FEATURE-BRANCHES.md) — branch and PR workflow
- [`development/CHECKPOINTS.md`](development/CHECKPOINTS.md) — CP0–CP5 history and evidence

## data/

- [`data/CONTENT-STANDARD.md`](data/CONTENT-STANDARD.md) — manifest, packs, entries, budgets
- [`data/WEAPONS.md`](data/WEAPONS.md) — class weapons and damage decisions
- [`data/BODIES.md`](data/BODIES.md) — `CharacterBodyStats` dimensions and parity rules
- [`data/MAPS.md`](data/MAPS.md) — map candidates, spawns and budgets

## research/

- [`research/L9-BROWSER-MATRIX.md`](research/L9-BROWSER-MATRIX.md) — full browser-matrix report
- [`research/L9-ANSWER-SUMMARY.md`](research/L9-ANSWER-SUMMARY.md) — what was adopted, rejected, deferred
- [`research/PERFORMANCE-AUDIT-2026-10-30.md`](research/PERFORMANCE-AUDIT-2026-10-30.md) — measured baseline
- [`research/OPTIMIZATION-ANSWERS-REVIEW.md`](research/OPTIMIZATION-ANSWERS-REVIEW.md) — optimization decisions

## License

Code is under the [Apache License 2.0](../LICENSE). Third-party assets keep their own
licenses, listed in [`../assets/CREDITS.md`](../assets/CREDITS.md).

## Rules

1. A document that records a **decision** must say what was rejected and why.
2. Research is not accepted blindly: verify claims against the code before
   implementing, and record the rejection in the answer summary.
3. Numbers in docs must come from a command someone actually ran.
4. Answered question briefs are deleted, not archived — git history keeps them.
