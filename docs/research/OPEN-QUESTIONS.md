# Open research / decision questions

**How this file works:** only *unanswered* questions live here. Answer in chat or by editing
this file; the manager removes answered entries. Context and the asker are included so the
external research agent can answer without the full chat history.

Last updated: 2026-10-29 (Phase 1 start).

---

## Q1 — Bullet visual size: 5% of what?

**Asked by:** manager
**Status:** open (implemented literally as 5% overall; easy to retune)
**Context:** You said the bullets were too big and “5% of the current size is ok”. Phase 0 had a
0.36 m core, 2.5 m trail and 2.8 m dark rim. I applied **5% to every dimension**:
core 0.018 m, trail 0.125 m, rim 0.14 m, impact 5%. That is a small dart, and at 81 m/s it moves
1.35 m per 60 fps frame, so it can strobe.

**Question:** did you mean 5% of the **overall size** (current behaviour), or 5% of the
**thickness** while keeping a ~1.5–2.5 m streak for tracking? If the latter, say “thickness only”.

---

## Q2 — Final rifle model

**Asked by:** Agent A / manager
**Status:** open (manager assumes Quaternius M4)
**Context:** KayKit Adventurers is a cute low-poly style. Candidates:

- **Quaternius CC0 M4** (Poly Pizza `/m/Bgvuu4CUMV`, 1,930 tris, 3 materials) — recommended.
- Quaternius AK (`/m/fpLucho45C`, 1,388 tris, 5 materials).
- KayKit Adventurers `shotgun.gltf` — exact style match but a shotgun and possibly tied to the
  paid Engineer material.
- Quaternius period musket (`/m/neEjwx9bBJ`) — cute but anachronistic.

**Question:** confirm the M4, or prefer one of the others?

---

## Q3 — Five-character roster

**Asked by:** Agent A
**Status:** open (A will pick if no answer)
**Context:** You asked for five different characters, each with the full animation set. The free
Adventurers 2.0 roster is Knight, Mage, Rogue, Rogue_Hooded and Barbarian, all on `Rig_Medium`
(so every clip works). The plan is one shared character per player/bot slot, with per-player
textures optional.

**Question:** any roster preference, or should A use all five as listed? Should bots use the same
five or a separate subset?
