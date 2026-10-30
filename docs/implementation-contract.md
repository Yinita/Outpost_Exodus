# First campaign implementation contract

Working title: 逐营突围 / Outpost Exodus. Godot 4.7.2, typed GDScript, fixed 2D camera, cartoon wasteland. This is the first substantial implementation toward the full Steam-release goal, not a claim of release readiness.

Project root is this folder's parent. Coordinate system: world/tile units. Map size 80 × 40. Drawing scales by TILE_SIZE=48. Forward/east is right; pursuit enters from west/left. Two terrain heights; explicit ramp/bridge connectivity. Early squad control, branching scavenging, roads, production/fuel, local power, eventual evacuation and delaying choke points must be real simulation behavior.

## Shared state/API

`scripts/campaign_simulation.gd` extends RefCounted (no mandatory global class name). Root loads with preload. Public fields:

- `time: float`, `phase: String` (preparation/advance/evacuation), `outcome: String` (playing/victory/defeat), `paused: bool`.
- `map_size: Vector2i = Vector2i(80,40)`, `terrain: Array` of row Arrays, values -1 impassable, 0 low, 1 high.
- `roads: Dictionary` keyed Vector2i, `ramps: Dictionary` keyed Vector2i.
- `units: Array` of Dictionaries: `id:int`, `kind:String` (rifle/engineer/worker/truck/zombie/runner/brute), `team:String` (friendly/enemy), `pos:Vector2`, `hp:float`, `max_hp:float`, `state:String`, `target:Vector2`, `camp_id:int`, `squad:int`; extra fields allowed.
- `buildings: Array` of Dictionaries: `id:int`, `kind:String` (command/camp/generator/workshop/tower/barricade/quarry/fuel/exit), `pos:Vector2`, `hp:float`, `max_hp:float`, `camp_id:int`, `progress:float` (0..1), `powered:bool`; extra fields allowed.
- `camps: Array` of Dictionaries: `id:int`, `name:String`, `pos:Vector2`, `state:String` (active/packing/abandoned), `materials:float`, `supplies:float`, `fuel:float`, `power:float`, `priority:String` (production/defense/evacuation).
- `sites: Array` of Dictionaries: `id:int`, `kind:String` (quarry/fuel/cache/exit), `pos:Vector2`, `captured:bool`, `progress:float`.
- `effects: Array` of Dictionaries: `kind:String` (shot/hit/loot), `pos:Vector2`, `to:Vector2`, `ttl:float`.
- `messages: Array` strings, capped recent messages, `pursuit_x:float`, `pursuit_eta:float`, `exit_progress:float`, `evacuated:int`, `seed_value:int`.

Methods:

- `reset(seed:int=42)`, `tick(delta:float)`.
- `command_move(ids:Array, target:Vector2, attack_move:bool=false)`.
- `command_task(ids:Array, task:String, target:Vector2)`; tasks clear/escort/guard/repair.
- `build(kind:String, tile:Vector2i) -> bool`; road/camp/generator/workshop/tower/barricade. Checks resources and reachable terrain; construction progresses through engineers/workers.
- `set_production(camp_id:int, recipe:String)`; materials/supplies/fuel/idle, prerequisites and actual resource consumption.
- `set_priority(camp_id:int, priority:String)`.
- `evacuate_camp(camp_id:int) -> bool`; actual pack/transfer sequence, no teleporting inventories.
- `seal_choke(index:int) -> bool`; refuse or defer sealing while designated friendlies remain behind; a visible destructible delaying barricade.
- `get_summary() -> Dictionary` (materials,supplies,fuel,power,people,zombies,phase,outcome,exit_progress,evacuated,pursuit_eta).
- `get_unit(id:int) -> Dictionary`, `get_camp(id:int) -> Dictionary`, `is_walkable(tile:Vector2i) -> bool`.
- `save_state() -> Dictionary` and `load_state(data:Dictionary) -> bool`, JSON-compatible coordinates encoded/decoded internally; validate version and data before replacing state.

Simulation owns meaningful game rules, pathfinding and combat. Root main owns input/UI/camera/audio/options and calls simulation. Stable IDs; never store Node references inside simulation. Fixed simulation step from root; drawing interpolations optional. No multiplayer in current spec.

## World view interface

`scripts/world_view.gd` extends Node2D. Public `sim` reference, `selected_ids:Array=[]`, `hover_tile:Vector2i`, `build_kind:String=""`, `show_logistics:bool=true`, `show_ranges:bool=false`. The entire renderer uses tile-unit positions multiplied by TILE_SIZE=48; no Camera logic. `_draw()` draws the world and sim state. `tile_to_world(p:Vector2)->Vector2` and `world_to_tile(p:Vector2)->Vector2i`. Use procedural original cartoon game art first, with clear cliffs, roads, modular outlined buildings, moving characters, smoke/muzzle flashes, readable energy and friendly/enemy colors. World must remain readable at strategic zoom. Root can queue_redraw each frame. Defensive dictionary `.get` defaults for optional fields; do not mutate sim state from draw.

## Initial mission geometry

Starting camp near (9,22); first rear choke near (21,20); northern salvage near (35,10); southern fuel near (35,31); forward camp/site near (53,21); second choke near (61,20); exit near (72,19). Renderer should derive walkability/elevation from `sim.terrain`, not rely on a static screenshot. Missions can adjust these positions later.

## Engineering requirements

Use explicit types for ambiguous Variant expressions to avoid GDScript inference errors. Avoid reserved identifier `seed`. Unit group movement must route through walkable terrain and explicit crossings. Provide tests of real resource, road, power, retreat and save/load behavior. No fake victories driven only by a timer or a screenshot. Early implementation rough edges are tracked; the Steam release objective stays active until product and release gates are met.
