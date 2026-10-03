# Optional companion controller

`src/companion/companion_controller.gd` is a ground companion using the same
`PlayerActions` and `PlayerCharacter` as a human participant. It never calls Agro,
mounts, teleports, grabs/climbs a colossus, strikes sword weak points, changes boss
rules or performs a whole encounter. Create it only when companion play is enabled.

```gdscript
const Controller = preload("res://src/companion/companion_controller.gd")
var controller := Controller.new()
controller.name = "CompanionController"
game.region.add_child(controller)
controller.setup(game, player_two, seed)
controller.mode = &"programmed" # or &"local_model"
```

The actor must be a descendant of `game.region`, with a stable name such as
`Player2`. The controller is a region child (an actor child also works). Physics
priority is -10, before the player reads actions. The controller finds GameWorld
through ancestors, so its snapshot contains no reference outside the region.
Setup does not persist or transmit anything. Include the actor in BossEncounter's
participants; the encounter owns deaths and revival.

`allowed_intents() -> Array[StringName]` returns `follow`, `hold`, `support`,
`evade`, `regroup`. `accept_decision(intent: StringName)` accepts only this whitelist.
A model decision lasts at most six seconds, applies only in `local_model` mode,
and cannot suppress safety or force support when no legitimate target is present.
The programmed policy remains active if the model is absent or stops responding.
Its seeded decisions take place every 4–6 seconds.

`observation() -> Dictionary` returns scalar values only:

| Key | Meaning |
| --- | --- |
| health | Actor health, 0–100 |
| stamina | Actor stamina ratio, 0–1 |
| leader_distance | Distance in metres; -1 if unavailable |
| enemy_distance | Distance in metres; -1 without an active colossus |
| threat | Actor inside a current telegraphed danger zone |
| enemy_active | An undefeated colossus is awake |
| leader_climbing | Host is climbing |
| support_available | Standing safely, target 12–80m away, host nearby, clear shot |
| near_cliff | A proposed navigation direction lacked safe floor |
| mounted | Actor is riding; controller does not manage rides |
| player_downed / leader_downed | Actor / host is dead or unavailable |
| ground_safe | Floor probe found a walkable surface beneath the actor |
| navigation_blocked | No short safe detour was available |
| intent | One of the five fixed intent names |

Navigation runs at most ten times per second, without catch-up query bursts.
A short bounded fan checks floor slope/drop, shoulders and physical obstacles.
There are at most five directions, three floor and three wall rays per direction,
one current floor ray and one optional support line ray. An existing detour may
add one further checked direction: at most 38 queries per
navigation update; ordinary following uses seven. At most sixteen danger zones
come directly from the active boss. No per-frame scene or group scans are used.
Cached movement still enters PlayerActions every physics tick. This is local
obstacle avoidance, not a global pathfinding mesh; deep gaps and enclosed maze
routes may require the host to change route or an integration-owned regroup.

Support uses actual charged bow arrows aimed at the colossus' focus point, with
7.5–10 seconds between shots. Host proximity uses horizontal distance so ground
support remains useful while the host climbs. Drawing and releasing use ordinary weapon actions,
including cancelling unsafe draws by putting the bow away. No additional weak
point mechanics or compulsory helper are introduced. The controller preserves
readable solo encounters and never changes the player's running speed.

`external_drive = true` returns immediately, without clearing actions, advancing
timers or consuming RNG. Replay integration must set this before and after codec
restore, because transport ownership belongs to the live session. Keep stable
node names and create the same actor/controller before WorldSnapshot.restore.
All controller timers, the accepted intent and the policy's RandomNumberGenerator
are supported by the existing generic binary codec.

When GameWorld is stopped, fading, or either participant is downed, the controller
clears its own input. GameWorld should freeze actor gameplay and reset a drawn bow
at fade/title transitions, since any PlayerCharacter interprets releasing an
already drawn attack as firing. No controller input can undo a shot from a prior
frame. The controller does not own respawn or campaign transitions.

Tests: `tests/test_companion_policy.tscn` checks seeds, policy bounds and binary
codec continuation. `tests/test_companion_controller.tscn` exercises real actor
movement, external replay ownership, fade/title/death silence, physical walls and
cliffs, danger overrides, model expiry, and one real bow shot with a bounded rate.
It also restores a full GameWorld binary checkpoint and verifies subsequent actor
movement, RNG state, decision timers and navigation cadence.
`tests/test_companion_controller_review.tscn` adds regressions for capsule-safe
joining, replay from tick zero through removal/rejoining, and a recorded regroup
after player physics. It fails with a nonzero exit code on divergence and runs
with both headless physics and native Compatibility rendering.
