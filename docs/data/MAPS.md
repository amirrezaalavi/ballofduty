# Maps

Date: 2026-10-30
Source: map session, merged into `develop` from `maps-candidates-wip`
Status: **merged, WIP** — loads and walks headless; bake/scatter/detail-texture
pass, per-map budgets and the final rotation are still open.

Three 120 x 120 m map candidates built on the quarry pattern (height field is
the single source of truth for visual chunks + `HeightMapShape3D` collision,
deterministic seeds, MultiMesh scatter, analytic colliders, 8 snapped spawns).
No new downloads: Kenney Nature CC0 models + runtime-generated geometry.

## Candidates

| Map | File | Theme | Signature places |
|---|---|---|---|
| DUNE CANYON | `scenes/maps/arena_dunes.tscn` | desert dunes, hot sky | slot canyon + timber bridge, ruined fort, oasis pond, 2 rock arches |
| STARFALL CRATER | `scenes/maps/arena_crater.tscn` | night basalt + frost, emissive crystals | impact bowl + 4 rim ramps, relay platform ring, ice bridge |
| JUNGLE RUINS | `scenes/maps/arena_jungle.tscn` | humid green jungle | stepped temple + 4 ramps, vine tunnel bore, vine bridge, river cut |

All three are in the menu MAP picker, `?map=` URLs, `--map` CLI, and headless
`--server --map`. Quarry stays the default.

## Evidence

Multi-map smoke (`tests/headless/map_smoke.gd`), all PASS:

- quarry: spawns=8 gap=22.0 draws=49 tris=192842 inst=1832 colliders=387 boundary=69.0
- dunes: spawns=8 gap=22.8 draws=41 tris=118748 inst=966 colliders=218 boundary=54.5
- crater: spawns=8 gap=25.5 draws=30 tris=36294 inst=466 colliders=253 boundary=54.5
- jungle: spawns=8 gap=28.6 draws=49 tris=191596 inst=1614 colliders=370 boundary=54.5

Budgets: ≤150 draw calls, ≤250k tris, 8 spawns ≥15 m apart, boundary contained.

Walkthroughs (real-physics harness, stuck limit 1.5 s, 0 camera clips):

- `DUNES_WALK sections=28 failures=0 distance=152.0 m result=PASS`
- `CRATER_WALK sections=30 failures=0 distance=287.8 m result=PASS`
- `JUNGLE_WALK sections=33 failures=0 distance=391.7 m result=PASS`

Menu/map tests in `tests/gdunit/test_menu.gd` (picker defaults, selection,
fallback, `?map=` sanitization). Full `tools/check.sh` result: **OK**
(import, gdUnit4 suite incl. new map tests, arena budget, quarry walk,
4-bot match, client/server boots, Web + Linux Server exports, payload
14,364 KB gzip). Per-map `--map` solo boots: no errors.

## Fixes applied during the build

- dunes: rim scatter rock blocked the east edge lane → keep-clear rects added.
- crater: rim-lane slope spike (radial feathering), buried platform ramps
  (rebuilt to sample terrain), bridge lips (deck coplanar with banks), short
  test drop (moved).
- jungle: (per builder report).

## Deviations

- Maps are 120 x 120 m, not 150 x 150 m like the quarry: same 3x3-chunk build
  cost, larger than the 90 m minimum, keeps 60 FPS headroom.
- Server/client map agreement is by convention (same `--map` / menu pick both
  ends); no JOIN-time map hash yet — recorded as follow-up.

## Known issues carried forward

- Screenshots of the three maps in a real browser build are still wanted.
- Bot navmesh is still direct steering (CP4d upgrade), unchanged by this pass.
