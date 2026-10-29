# Questions for the external research agent

Project: Ball of Duty — Godot 4.7.2, web/Compatibility, 30 Hz server snapshots,
25–45 ms RTT on a local/LAN server, 60 fps client, low-poly third-person shooter.

## Q1 — Remote player “jump render” at low RTT

Testers see other characters occasionally jump/slide instead of moving continuously, even at
25–45 ms RTT. Current client: 30 Hz binary snapshots (position/yaw/state/velocity), 60 fps render,
`NetworkInterpolator` rendering 2 ticks behind newest, extrapolation capped at 1 tick, then hold;
Godot physics interpolation is enabled.

Research and recommend, with numbers or references:

1. The best render delay / jitter buffer for 30 Hz snapshots at 25–45 ms RTT and ~60 fps.
2. Whether to extrapolate using snapshot velocity to “now” (dead reckoning) and how to smooth the
   correction when the next snapshot disagrees (visual offset decay vs rewind).
3. Common causes of visible snaps in a 30 Hz authoritative shooter beyond packet loss: tick jitter,
   server frame hitches, teleports (respawn), animation/root-motion changes, quantization, physics
   interpolation settings.
4. Whether raising snapshot rate to 45/60 Hz (with the same 22 B row) is worth the bandwidth/CPU for
   an 8-player web match, or whether 30 Hz + better interpolation is enough.
5. Any Godot 4.7-specific pitfalls with `CharacterBody3D.global_position` being written every
   physics tick while `physics/common/physics_interpolation=true` is enabled.

Please give a concrete recommended algorithm (pseudocode is fine), not just general advice.

## Q2 — Visible projectile readability

At 81 m/s, a 0.28 m glowing projectile plus a 0.72 m additive trail. Players still lose track of
rounds against a bright low-poly nature arena. Research practical readability techniques for
web/WebGL low-end GPUs: ideal angular size/lifetime, additive vs alpha, color/contrast, trail length,
impact flash duration, and whether a short-lived line/trail is better than a moving mesh. Include
examples from shipped third-person shooters if available.

## Q3 — KayKit animation set

(Being researched in parallel; only answer if you find something the vendor page omits.)
Which KayKit pack/version contains rifle **strafe** locomotion and an aim-walk set, what are the
exact clip names, and what is the current license/price? Do the Adventurers characters share the
same skeleton as the animation pack?
