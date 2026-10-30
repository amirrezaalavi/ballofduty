# Class weapons

Decision memo for the five class weapons. The source report was a chat summary;
these are the decisions actually implemented in `resources/weapons/` and
`scripts/content/`.

Numbers are authoritative here; the code is the source of truth if they diverge.

## Recommendations

| # | Decision | Recommendation | Why |
|---|---|---|---|
| 1 | Weapon assignment | **Pre-match class picker, class locked for the match. Add a 1-byte `class_id` to `JOIN_REQ` / `JOIN_OK` / roster.** | `net_id % 5` makes the host always the Knight and join order decides everyone else's class. Players need agency; the picker is one field, not a combat-protocol change. |
| 2 | Bot loadouts | **Class weapons, assigned round-robin from the same five classes.** | Exercises all five weapons server-side, gives visual variety, and matches the class-locked model. |
| 3 | Arena scale | **150 × 150 m, greybox first.** | The report's cave/vertical plan needs room; 8 players still meet through the quarry and cave bypass. Playtest 120 vs 150 after greybox. |
| 4 | M4 rifle | **Retire from the V1 class kit; keep the asset and `WeaponStats` for a later power-weapon pass.** | A central pedestal needs ground-item replication, pickup authority, 60 s respawn and limited-ammo state. That is a separate feature; do it after the five classes are stable. |

## Technical review

- **Combat packets stay unchanged.** Class id in the roster lets the server derive damage, speed,
  splash/pierce and animation; `SHOT`/`HIT` remain as-is.
- **Charge/burst/heat** can be tracked server-side from held fire. The client HUD predicts them;
  if drift becomes visible, add one state byte (heat/ammo) to the snapshot later (still <300 B).
- **Splash/pierce** resolve on the server with shape queries; the projectile must stop at the first
  blocking surface but may continue through actors for pierce.
- **Animations are covered**: `Throw`, `Ranged_1H_*`, `Ranged_2H_*`, `Ranged_Bow_*`,
  `Ranged_Magic_*`; no new clip import required. Per-class upper-body overlays need mapping.
- **Weapon assignment refactor**: `ServerCombat` is currently one stats object; it must become
  per-player. `WeaponController` and `CharacterVisual` need per-class stats/clips. This is the main
  cost of Phase 2A.
- **Arena**: Terrain3D rejected for web; 3×3 chunk grid + `HeightMapShape3D` is the right path.
  Double-wall caves and rock skirts are necessary; keep interior clearance ≥3.8 m.

## Implementation phases

### Phase 2A — five class weapons + picker (~3–4 days, 2 agents)

- **Manager:** `class_id` protocol, GameManager assignment/roster, integration, tests.
- **Agent D — combat/server:** weapon registry, five stats/projectile profiles, splash/pierce/
  bleed/knockback hooks, charge/burst/heat validation, bot ballistics, server tests.
- **Agent E — client/visual/UI:** class picker cards, five weapon models and hand/muzzle offsets,
  per-class animation overlays, crosshair/charge/heat HUD, client tests.

### Phase 2B — Sunken Quarry & Cavern Pass (~3–5 days, 1–2 agents)

- 3×3 50 m mesh chunks, heightmap/collision, cliff terraces, double-wall cave bypass, rock skirts,
  MultiMesh foliage, sunlight fade, 8 spawn points, greybox flow then art pass.
- Budget: 85–105 draw calls, <74k triangles, <18 MB texture VRAM.

### Later

- M4 central power weapon (pickup replication + 60 s respawn).
- Remote death polish (already plays `Death_A` + red marker; add remote hit reactions).
- Firefox compatibility pass and CP4d/CP5 match loop.

## Sign-off

Recommended defaults above. On confirmation, Phase 2A starts with the picker + five weapons; the
arena follows once the class kit is stable.
