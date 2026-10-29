# Remote smoothing & bullet readability — research answers

Source: external research agent, 2026-10-29. Applied to Phase 0.

## Remote player “jump render” (25–45 ms RTT, 30 Hz snapshots, 60 fps)

Recommended and implemented:

- **Render delay: 2.5 ticks (83 ms).** At 30 Hz a 2-tick buffer leaves only 16 ms of
  headroom against browser event-loop coalescing. 2.5 ticks keeps two surrounding
  snapshots available without noticeable sluggishness.
- **Virtual server clock.** Advance a client-side timeline by render delta, then render at
  `timeline - 83 ms`. Do **not** drive interpolation directly from packet arrival times.
- **Bounded extrapolation.** On buffer underrun, extrapolate at most **1 tick** with
  velocity damped to **0.65×**, then hold. Do not dead-reckon far into the future.
- **Correction smoothing.** Never teleport or rewind on a late snapshot. Apply the error as
  a render offset on the visual child and decay it over ~80–120 ms.
- **Disable physics interpolation on remote puppets** and update them in `_process`, not
  `_physics_process`. Godot's physics interpolation otherwise adds a second, conflicting
  30 Hz pass.
- **Keep 30 Hz snapshots.** 45/60 Hz is cheap in bandwidth but does not fix stutter caused
  by buffer/interpolation configuration.
- **Teleport detection:** >4 m displacement resets the buffer (respawn).
- Yaw uses shortest-arc interpolation.

Code: `scripts/networking/network_interpolator.gd`,
`PlayerController._apply_remote()` / `make_remote()`.

## Visible projectile readability at 81 m/s

- At 60 fps the round moves **1.35 m per frame**. A 0.28 m bullet + 0.72 m trail (1.0 m)
  is shorter than one frame's travel, so it strobes.
- **Trail length: 2.5–3.2 m**, camera-readable, with a saturated core and a dark rim for
  contrast on bright grass/sand/sky. Additive-only blending washes out.
- Impact flash **80–110 ms** (we use 100 ms).
- Prefer a two-point ribbon/streak over a small 3D sphere; keep a minimum on-screen width.

Code: `scripts/weapons/bullet_field.gd`, `bullet_visual.gd` (2.5 m trail, 2.8 m dark rim,
0.18 m core, 100 ms impact, 64-node pool).

## KayKit (option B)

- Adventurers and Character Animations share the **`Rig_Medium`** skeleton; no retargeting.
- The animation pack has **no dedicated strafe clips**. Use an `AnimationTree` blend of
  `Aim_TwoHanded_Loop` / `Shoot_TwoHanded` over `Walk` / `Run`, with bone filtering, and
  reverse `speed_scale` for backpedaling.
- The procedural upper-body aim in Phase 0 remains useful as the fallback and for the
  torso/legs split until the KayKit blend tree lands in Phase 1.
