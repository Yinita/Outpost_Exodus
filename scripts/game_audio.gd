extends Node
## Original precomputed sound effects; observation never edits simulation or RNG.
## Six world voices plus two UI voices bound mixer cost during large battles.

const WORLD_VOICES: int = 6
const UI_VOICES: int = 2
const STREAMS: Dictionary = {
	"shot_a": preload("res://assets/audio/sfx_shot_a.wav"),
	"shot_b": preload("res://assets/audio/sfx_shot_b.wav"),
	"impact": preload("res://assets/audio/sfx_impact.wav"),
	"loot": preload("res://assets/audio/sfx_loot.wav"),
	"confirm": preload("res://assets/audio/sfx_confirm.wav"),
	"reject": preload("res://assets/audio/sfx_reject.wav"),
	"build": preload("res://assets/audio/sfx_build.wav"),
	"warning": preload("res://assets/audio/sfx_warning.wav"),
}
const COOLDOWNS: Dictionary = {"shot": 0.105, "impact": 0.13, "loot": 0.22, "build": 0.25, "warning": 8.0}

var world_players: Array[AudioStreamPlayer] = []
var ui_players: Array[AudioStreamPlayer] = []
var play_counts: Dictionary = {}
var dropped: int = 0
var peak_world_voices: int = 0
var observed_updates: int = 0
var gameplay_active: bool = false
var _seen_effects: Dictionary = {}
var _completed: Dictionary = {}
var _last_play: Dictionary = {}
var _last_time: float = -1.0
var _phase: String = ""
var _urgent: bool = false
var _shot_variant: int = 0
var _next_ui: int = 0


func configure(primary_ui_player: AudioStreamPlayer) -> void:
	primary_ui_player.bus = "SFX"
	ui_players.append(primary_ui_player)
	for index: int in range(UI_VOICES - 1):
		ui_players.append(_new_player())
	for index: int in range(WORLD_VOICES):
		world_players.append(_new_player())


func _new_player() -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = "SFX"
	add_child(player)
	return player


func set_gameplay_active(active: bool, simulation: Variant) -> void:
	if gameplay_active == active: return
	gameplay_active = active
	# Consume extant effects when a menu/pause closes, so nothing saved or aged
	# during an inactive state becomes a new audible event on resume.
	prime(simulation, false)


func prime(simulation: Variant, stop_ui: bool = true) -> void:
	stop_world()
	if stop_ui:
		for player: AudioStreamPlayer in ui_players: player.stop()
	_seen_effects = _effect_keys(simulation)
	_completed = _building_states(simulation)
	_last_time = float(simulation.time)
	_phase = String(simulation.phase)
	_urgent = float(simulation.pursuit_eta) <= 25.0
	_last_play.clear()


func _effect_key(effect: Dictionary, time: float) -> String:
	# Expiry is invariant as simulation time increases and ttl decreases. A
	# millisecond bucket tolerates float roundoff. Identical simultaneous effects
	# intentionally coalesce. Keys live only while their effects live (<=121).
	return "%s|%s|%s|%d" % [String(effect.get("kind", "")), str(effect.get("pos", Vector2.ZERO)), str(effect.get("to", Vector2.ZERO)), roundi((time + float(effect.get("ttl", 0.0))) * 1000.0)]


func _effect_keys(simulation: Variant) -> Dictionary:
	var result: Dictionary = {}
	for effect: Dictionary in simulation.effects:
		result[_effect_key(effect, float(simulation.time))] = true
	return result


func _building_states(simulation: Variant) -> Dictionary:
	var result: Dictionary = {}
	for building: Dictionary in simulation.buildings:
		result[int(building.id)] = float(building.progress) >= 1.0
	return result


func observe_sim(simulation: Variant, listener_tile: Vector2) -> void:
	# Called immediately after each real fixed simulation step, not per render.
	if _last_time == float(simulation.time): return
	if not gameplay_active or simulation.paused:
		prime(simulation, false)
		return
	observed_updates += 1
	var current: Dictionary = {}
	for effect: Dictionary in simulation.effects:
		var key: String = _effect_key(effect, float(simulation.time))
		if not _seen_effects.has(key) and not current.has(key):
			var position: Vector2 = effect.get("pos", Vector2.ZERO)
			match String(effect.get("kind", "")):
				"shot":
					play_world("shot", position, listener_tile)
					play_world("impact", effect.get("to", position), listener_tile)
				"hit": play_world("impact", position, listener_tile)
				"loot": play_world("loot", position, listener_tile)
		current[key] = true
	_seen_effects = current
	var completed: Dictionary = {}
	for building: Dictionary in simulation.buildings:
		var id: int = int(building.id)
		var done: bool = float(building.progress) >= 1.0
		if done and _completed.has(id) and not bool(_completed[id]) and float(building.hp) > 0.0:
			play_world("build", Vector2(building.pos), listener_tile)
		completed[id] = done
	_completed = completed
	var phase: String = String(simulation.phase)
	var urgent: bool = float(simulation.pursuit_eta) <= 25.0
	if phase != _phase or (urgent and not _urgent):
		# A soft two-pulse cue accompanies existing visual/text pursuit warnings.
		play_world("warning", listener_tile, listener_tile)
	_phase = phase
	_urgent = urgent
	_last_time = float(simulation.time)


func _enabled() -> bool:
	var sfx: int = AudioServer.get_bus_index("SFX")
	return sfx >= 0 and not AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(sfx)


func play_ui(cue: String, gain: float = 1.0) -> bool:
	if not STREAMS.has(cue) or ui_players.is_empty() or not _enabled(): return false
	# UI has two reserved voices; an order remains immediate during combat.
	var player: AudioStreamPlayer = ui_players[_next_ui % ui_players.size()]
	_next_ui += 1
	player.stop()
	player.stream = STREAMS[cue]
	player.pitch_scale = 1.0
	player.volume_db = -12.0 + linear_to_db(clampf(gain, 0.05, 1.0))
	player.play()
	_count(cue)
	return true


func play_world(cue: String, position: Vector2, listener_tile: Vector2) -> bool:
	if not gameplay_active or not _enabled(): return false
	var distance: float = position.distance_to(listener_tile)
	if distance >= 32.0: return false
	var now: float = Time.get_ticks_usec() / 1000000.0
	if now - float(_last_play.get(cue, -100.0)) < float(COOLDOWNS.get(cue, 0.15)):
		dropped += 1
		return false
	var free_player: AudioStreamPlayer
	for player: AudioStreamPlayer in world_players:
		if not player.playing:
			free_player = player
			break
	if free_player == null:
		dropped += 1
		return false
	var sample: String = cue
	if cue == "shot":
		sample = "shot_a" if _shot_variant % 2 == 0 else "shot_b"
		_shot_variant += 1
	if not STREAMS.has(sample): return false
	_last_play[cue] = now
	free_player.stream = STREAMS[sample]
	free_player.pitch_scale = 1.0
	free_player.volume_db = -18.0 + linear_to_db(1.0 - maxf(0.0, distance - 7.0) / 25.0)
	free_player.play()
	_count(cue)
	peak_world_voices = maxi(peak_world_voices, active_world_voices())
	return true


func _count(cue: String) -> void:
	play_counts[cue] = int(play_counts.get(cue, 0)) + 1


func active_world_voices() -> int:
	var result: int = 0
	for player: AudioStreamPlayer in world_players:
		if player.playing: result += 1
	return result


func stop_world() -> void:
	for player: AudioStreamPlayer in world_players: player.stop()


func release() -> void:
	gameplay_active = false
	for player: AudioStreamPlayer in world_players + ui_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
