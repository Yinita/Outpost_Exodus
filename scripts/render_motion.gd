extends RefCounted
## Read-only display interpolation between actual fixed simulation steps.
## Snap on pause/load/reset, spawn and discontinuous moves; never extrapolate.

const STEP_SECONDS: float = 0.05
const MAX_STEP_DISTANCE_SQUARED: float = 1.0

var previous_positions: Dictionary = {}
var fraction: float = 1.0
var _source: RefCounted
var _mission: String = ""
var _before_time: float = 0.0
var _current_time: float = 0.0
var _valid_step: bool = false


func reset(simulation: RefCounted) -> void:
	_source = simulation
	_mission = str(simulation.mission_id)
	_before_time = float(simulation.time)
	_current_time = _before_time
	previous_positions.clear()
	fraction = 1.0
	_valid_step = false


func before_step(simulation: RefCounted) -> void:
	if not _matches(simulation): reset(simulation)
	previous_positions.clear()
	for unit: Dictionary in simulation.units:
		if float(unit.get("hp", 0.0)) > 0.0:
			previous_positions[int(unit.id)] = Vector2(unit.pos)
	_before_time = float(simulation.time)
	_valid_step = false


func after_step(simulation: RefCounted) -> void:
	var elapsed: float = float(simulation.time) - _before_time
	if _source != simulation or _mission != str(simulation.mission_id) or absf(elapsed - STEP_SECONDS) > 0.000001:
		reset(simulation)
		return
	_current_time = float(simulation.time)
	_valid_step = true


func prepare_frame(simulation: RefCounted, remainder: float, running: bool) -> void:
	if not running or not _matches(simulation):
		reset(simulation)
		return
	fraction = clampf(remainder / STEP_SECONDS, 0.0, 1.0)


func position(unit: Dictionary) -> Vector2:
	var current: Vector2 = unit.get("pos", Vector2.ZERO)
	if not _valid_step or not previous_positions.has(int(unit.get("id", -1))): return current
	var previous: Vector2 = previous_positions[int(unit.id)]
	# Actual normal movement is far below one tile per50ms. Teleports, fixture
	# replacement and discontinuous corrections must not slide through cliffs.
	if previous.distance_squared_to(current) > MAX_STEP_DISTANCE_SQUARED: return current
	return previous.lerp(current, fraction)


func time(simulation: RefCounted) -> float:
	return lerpf(_before_time, _current_time, fraction) if _valid_step else float(simulation.time)


func _matches(simulation: RefCounted) -> bool:
	return _source == simulation and _mission == str(simulation.mission_id) and absf(_current_time - float(simulation.time)) < 0.000001
