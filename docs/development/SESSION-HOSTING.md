# Session hosting (V2 direction)

Status: **design, not implemented**. V1 keeps auto-join with one match per
server. This document records the direction so the V1 code does not grow
assumptions that block it.

## Target model

Two planes:

- **Service (control plane).** Static hosting, `POST /games`, `GET /games/{id}`,
  heartbeats, TTL. Returns `{game_id, endpoint, admin_token}` to the creator and
  `{game_id, endpoint}` to joiners.
- **Game servers (data plane).** Run one or more matches, register with the
  service, report load, exit when their matches end.

A game is created before anyone connects. It sits in `LOBBY`, expires if the
creator never shows, and only builds its arena when the match starts.

## Identity

The creator gets a **secret admin token at creation time**. The client presents
it on join; the server marks that peer as admin.

"First to join is the creator" is not a security model. Anyone holding a game
ID could take admin by connecting first. First-join can stay as a fallback for
local play but never as the rule for a public service.

Game IDs are random, not sequential, and short enough to read aloud (six
characters of base32). The join link carries the ID, never the admin token and
never a raw IP, so a game can move hosts without breaking.

## Lifecycle

| State | World | Accepts joins | Clock |
|---|---|---|---|
| `CREATED` | none | yes, lobby | stopped |
| `LOBBY` | none | yes | stopped |
| `LOADING` | instantiating | queues them | not yet |
| `RUNNING` | live | yes, current round | running |
| `DRAINING` | live, no humans | yes, cancels teardown | paused |
| `CLOSED` | freed | no | — |

Teardown starts when the last human leaves: the reconnect grace (8 s) plus a
linger (30–60 s) before the arena is freed. Without the linger, every alt-tab
costs a map rebuild.

## Mid-session joins

Pick one and write it into the UI:

- spawn immediately into the running round;
- spectate until the next round;
- restart the round when a human joins late.

Recommended: spawn immediately, plus a minimum-time rule. Under 60 s left, the
joiner spectates and spawns next round. Bots are replaced by humans on join and
refilled on leave, so the arena stays at the configured size.

## Density

| Approach | Needs | Isolation | When |
|---|---|---|---|
| One process per match, supervisor on the host | process spawn, port range, health checks | full | first |
| Several matches per process | `GameManager` and `NetworkManager` become per-match nodes with their own `World3D` and tick | weak | only if measurement demands it |

Both autoloads are singletons today, so the second option is a refactor, not a
config change. Start with process per match.

## Protocol

`JOIN_REQ` gains `map_id`, `bot_count` (first join only) and `admin_token` when
the service routes by game ID. `JOIN_OK` echoes the authoritative map and bot
count. This is a layout change, so it needs a version bump, unlike the additive
`SCORE` and `MATCH` messages.

## Abuse controls

Public creation needs them from day one: max games per IP, TTL on empty lobbies,
a cap on bots per game, and a per-session token even for anonymous players. One
script should not be able to exhaust the host.

## Phases

| Phase | Work | Cost |
|---|---|---|
| A | Extract a `MatchInstance` from the `GameManager` autoload (world, roster, tick, scores) | 2–3 days |
| B | Game ID, admin token, lobby state machine, server-owned map and bots, protocol v3 | 3–4 days |
| C | Service API and supervisor, one process per game | 3–4 days |
| D | Client create/join UI, lobby roster, admin controls | 2–3 days |
| E | Late-join policy, bot replacement, optional spectator | 2 days |
| F | Optional: several matches per process | ~1 week, measure first |

Phase A is worth doing regardless: it makes the current single-match code
testable and is the prerequisite for everything else.

## Near-term, before any of this

The map must be server-owned now, not at phase B, because the 2026-11-02
playtest showed the client and server can run different arenas. The interim fix
is authoritative server map plus client adoption on `JOIN_OK`. It is thrown away
when phase B lands, and it is worth it anyway.

## Open decisions

1. Process per match first, or multi-game per process from the start?
2. Public IDs, or invite-only with a secret link?
3. Late join: spawn immediately, spectate, or restart the round?
4. Admin transfer when the creator leaves, or close the game after a grace?
5. Bots replaced by humans on join, or fixed count?
6. Service on one VPS with a supervisor, or a managed container platform?
