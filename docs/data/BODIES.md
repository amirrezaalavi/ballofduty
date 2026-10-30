# Character bodies (L2/L8)

**Status:** Step 1 implemented and merged; Step 2 (per-class sizes) is pending.
Source: the L2/L8 research answer received 2026-10-30 (the full report file was
never committed; this is the executive summary plus the decisions actually
applied).

Code: `scripts/components/character_body_stats.gd`,
`scripts/components/character_body_registry.gd`,
`resources/players/body_*.tres`.

## Decisions

- Dedicated `CharacterBodyStats` resource for rigid spatial/geometric data:
  capsule, hurtbox, visual scale, camera offsets, eye/muzzle origins. Keep
  `PlayerStats` for kinematic tuning (speed, jump, acceleration).
- Author explicit dimensions in metres. Root `CharacterBody3D.scale` and every
  `CollisionShape3D.scale` stay `Vector3.ONE`; visual variation is only
  `Visual.scale = Vector3.ONE * visual_scale`.
- No protocol change: snapshot rows stay 18 B; `class_id` selects the profile.
  Mid-match class changes are banned.
- Stateless `CharacterBodyStats.apply_to_actor(actor, role)` with no
  `NodePath`/`Node` exports. Applies identically to LOCAL, REMOTE and headless
  SERVER; the server disables visual processing.
- Single capsule hurtbox 0.80 m vs 0.82 m movement capsule. Camera/muzzle
  physical offsets live in the body profile; FOV/sensitivity stay in user
  settings; the server evaluates a fixed canonical muzzle ray.
- Two-step rollout: Step 1 extracts today's exact values with no regression;
  Step 2 enables per-class sizes (Mage 0.856, Knight 0.820, Barbarian 0.773,
  Rogue 0.703).
- Training dummy can share the body-profile concept.

## Corrections applied by the implementation session

1. **No headshots.** The report's mathematical headshot cutoff conflicts with
   the locked one-body-capsule/no-headshot decision. Step 1 keeps one
   `BodyHurtbox` and changes no damage rules.
2. **Step 1 only.** All five profiles reproduce today's dimensions; per-class
   sizing is deferred.
3. **gdUnit4, not GUT.** New test path:
   `tests/gdunit/test_character_body_parity.gd`.
4. **No protocol change.** The 18 B snapshot row and `class_id` selection stay.

## Implementation sequence

1. `CharacterBodyStats` + five identical class profiles.
2. Apply to LOCAL/REMOTE/SERVER; keep root/shape scale identity.
3. Replace duplicated `server_combat.gd` camera/muzzle constants with profile
   reads.
4. Parity tests: capsule/hurtbox/camera/muzzle/role, validation, 18 B snapshot,
   no headshot path.
5. Keep `test_smoke`, `test_movement`, `test_rig`, `test_server_combat`,
   `test_class_weapons`, `test_world_geometry`, `test_prediction` and
   `test_net_loopback` green.
