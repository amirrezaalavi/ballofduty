# Checkpoint evidence

One file per checkpoint: `CP0.md`, `CP1.md`, … Written when the checkpoint is claimed, using the
template in [`../ROADMAP.md`](../ROADMAP.md#checkpoint-evidence-template).

> **Test harness migration (after CP4a):** the SceneTree scripts named in CP0–CP4a evidence were
> ported to gdUnit4 under `tests/gdunit/` with identical measurements. See
> [`../TESTING.md`](../TESTING.md) for the current commands.

Rules:

- Every acceptance criterion gets a measured value, log excerpt, screenshot, or replay link.
- "Feels good" is only valid where the criterion explicitly says **your sign-off**.
- Deviations are listed, not hidden. A deferred criterion needs an owner and a phase.
- The build SHA must match the commit being reviewed.
