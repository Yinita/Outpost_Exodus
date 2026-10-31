extends SceneTree
## Actual Godot players/buses and saved-state integration. Dummy mixer works
## headless; --require-rendered insists on a rendered native audio run.
## XDG_DATA_HOME="$PWD/work/audio-test-data" ./run.sh --headless
##   --audio-driver Dummy --script res://tests/test_game_audio.gd

const Simulation = preload("res://scripts/campaign_simulation.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
var app: Variant
var failures: Array[String] = []
var checks: int = 0
var isolated_root: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	isolated_root = ProjectSettings.globalize_path("res://work/audio-test-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated_root + "/"):
		printerr("Refusing audio test without isolated XDG_DATA_HOME: ", OS.get_user_data_dir())
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--require-rendered") and (DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy"):
		printerr("Rendered audio test requires DISPLAY and native audio driver")
		quit(2)
		return
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	app = scene.instantiate()
	root.add_child(app)
	app.set_process(false)
	app.volume = 0.6
	app.effects_volume = 0.7
	app.muted = false
	app._apply_audio_settings()
	for test: Callable in [_test_preloads_and_routing, _test_music_loop_sample_frames, _test_events_and_state_identity, _test_voices_and_ui_priority, _test_mute_and_boundaries, _test_inactive_and_reset, _test_load_primes_saved_effects, _test_native_mixer_signal]:
		var previous: int = failures.size()
		await test.call()
		print("%s %s" % ["PASS" if previous == failures.size() else "FAIL", test.get_method()])
	print("Audio checks: %d; failures: %d; driver=%s display=%s; voices=%d+%d; streams=%d" % [checks, failures.size(), AudioServer.get_driver_name(), DisplayServer.get_name(), app.game_audio.world_players.size(), app.game_audio.ui_players.size(), GameAudio.STREAMS.size()])
	print("Audio play counts: ", app.game_audio.play_counts, "; peak world voices=", app.game_audio.peak_world_voices, "; dropped=", app.game_audio.dropped)
	for failure: String in failures: printerr(" - ", failure)
	app._release_audio()
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)


func _count(cue: String) -> int:
	return int(app.game_audio.play_counts.get(cue, 0))


func _start() -> void:
	app.start_campaign()
	app.set_process(false)
	app.game_audio.set_gameplay_active(true, app.sim)


func _tick(count: int = 1) -> void:
	for index: int in range(count):
		app.sim.tick(0.05)
		app.game_audio.observe_sim(app.sim, app.camera.position / app.TILE)


func _test_preloads_and_routing() -> void:
	_check(GameAudio.STREAMS.size() == 8, "eight distinct original files are preloaded")
	var bytes: int = 0
	for cue: String in GameAudio.STREAMS:
		var stream: AudioStreamWAV = GameAudio.STREAMS[cue]
		bytes += stream.data.size()
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050 and not stream.stereo, "PCM16 mono sample format: " + cue)
		_check(stream.get_length() > 0.10 and stream.get_length() < 0.60, "short bounded sample: " + cue)
	_check(bytes == 88640, "preloaded PCM payload remains 88,640 bytes")
	var maximum_sfx_peak: float = 0.54 * (6.0 * db_to_linear(-18.0) + 2.0 * db_to_linear(-12.0))
	_check(maximum_sfx_peak < 0.70, "all eight maximum-gain SFX voices retain mathematical mixer headroom at unity user settings")
	_check(app.game_audio.world_players.size() == 6 and app.game_audio.ui_players.size() == 2, "fixed six world/two UI voice pool")
	for player: AudioStreamPlayer in app.game_audio.world_players + app.game_audio.ui_players:
		_check(player.bus == &"SFX" and player.max_polyphony == 1, "actual player routes to SFX with one playback")
	_check(app.music_player.bus == &"Music" and app.sound_player.bus == &"SFX", "legacy player and independent Music bus remain compatible")
	_check(not app.game_audio.play_ui("unknown"), "unknown sample cannot allocate or play")


func _test_music_loop_sample_frames() -> void:
	var music: AudioStreamWAV = app.music_player.stream as AudioStreamWAV
	_check(music != null, "actual imported ambience is assigned to Music player")
	if music == null: return
	# Independently read the original RIFF frame count. The checked-in import
	# uses QOA compression, so compressed byte count is not the decoded length.
	var source: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/audio/canyon_ambient.wav")
	var source_frames: int = 0
	var source_rate: int = 0
	var channels: int = 0
	var bits: int = 0
	var cursor: int = 12
	while cursor + 8 <= source.size():
		var kind: String = source.slice(cursor, cursor + 4).get_string_from_ascii()
		var size: int = source.decode_u32(cursor + 4)
		var payload: int = cursor + 8
		if payload + size > source.size(): break
		if kind == "fmt " and size >= 16:
			channels = source.decode_u16(payload + 2)
			source_rate = source.decode_u32(payload + 4)
			bits = source.decode_u16(payload + 14)
		elif kind == "data" and channels > 0 and bits > 0:
			source_frames = size / (channels * bits / 8)
		cursor = payload + size + size % 2
	_check(source_frames > 0 and source_rate > 0, "original RIFF header independently supplies frame count/rate")
	var expected_frames: int = roundi(float(source_frames) * music.mix_rate / maxi(source_rate, 1))
	_check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD and music.loop_begin == 0, "actual ambience loops forward from frame zero")
	_check(music.loop_end == expected_frames, "actual loop endpoint spans every decoded source frame despite QOA compression")
	_check(roundi(music.get_length() * music.mix_rate) == expected_frames, "engine decoded duration agrees with independent WAV frame count")
	_check(music.loop_end != music.data.size() / 2, "regression fixture distinguishes decoded frames from compressed-byte shortcut")
	print("Music import: format=%d stereo=%s bytes=%d rate=%d length=%.9f loop_end=%d source_frames=%d old_byte_endpoint=%d" % [music.format, music.stereo, music.data.size(), music.mix_rate, music.get_length(), music.loop_end, source_frames, music.data.size() / 2])


func _test_events_and_state_identity() -> void:
	_start()
	var twin: Variant = Simulation.new()
	twin.load_state(app.sim.save_state())
	# The observer accompanies real fixed simulation updates. Equal complete
	# serialized states include effects, RNG, paths, jobs and campaign metadata.
	for index: int in range(120):
		app.sim.tick(0.05)
		twin.tick(0.05)
		var before: String = JSON.stringify(app.sim.save_state())
		app.game_audio.observe_sim(app.sim, app.camera.position / app.TILE)
		_check(before == JSON.stringify(app.sim.save_state()), "audio observer is read-only tick %d" % index)
	_check(JSON.stringify(app.sim.save_state()) == JSON.stringify(twin.save_state()), "audio-observed and silent campaign states/RNG are byte-identical after 120 ticks")
	var position: Vector2 = app.camera.position / app.TILE
	app.game_audio.prime(app.sim)
	var loot_before: int = _count("loot")
	app.sim._add_effect("loot", position, position, 1.8)
	_tick()
	_check(_count("loot") == loot_before + 1, "new actual simulation loot effect produces one cue")
	await create_timer(0.27).timeout
	_tick(10)
	_check(_count("loot") == loot_before + 1, "long-lived loot is consumed once even after cooldown")
	await create_timer(0.15).timeout
	var attacker: Dictionary = app.sim._add_unit("rifle", "friendly", position, int(app.sim.camps[0].id), 1)
	var target: Dictionary = app.sim._add_unit("zombie", "enemy", position + Vector2(1, 0), 0, 0)
	# _attack is the same combat path used by _update_units; both effects and
	# damage originate in simulation, while audio only consumes the result.
	var shot_before: int = _count("shot")
	var hit_before: int = _count("impact")
	app.sim._attack(attacker, target)
	_tick()
	_check(_count("shot") > shot_before and _count("impact") > hit_before, "real combat attack produces separate shot and impact textures")
	await create_timer(0.28).timeout
	var building: Dictionary = app.sim.buildings[0]
	building.progress = 0.9
	app.game_audio.prime(app.sim)
	building.progress = 1.0
	var build_before: int = _count("build")
	_tick()
	_check(_count("build") == build_before + 1, "construction completion crossing produces one build cue")
	var warning_before: int = _count("warning")
	app.sim.phase = "evacuation"
	_tick()
	_check(_count("warning") == warning_before + 1, "phase change produces one soft pursuit warning")
	_tick(4)
	_check(_count("warning") == warning_before + 1, "warning does not repeat on following ticks")


func _test_voices_and_ui_priority() -> void:
	_start()
	var audio: Node = app.game_audio
	var position: Vector2 = app.camera.position / app.TILE
	for index: int in range(100):
		audio.play_world("shot", position, position)
		audio.play_world("impact", position, position)
	_check(audio.active_world_voices() <= 6 and audio.peak_world_voices <= 6, "100 simultaneous attackers never exceed the fixed world voice budget")
	_check(audio.dropped > 0, "combat event storm is coalesced by wall-time cooldown")
	# Saturate actual world players to verify a reserved UI voice immediately.
	for player: AudioStreamPlayer in audio.world_players:
		player.stream = GameAudio.STREAMS.warning
		player.play()
	var confirm_before: int = _count("confirm")
	app._play_sfx("confirm")
	_check(_count("confirm") == confirm_before + 1, "UI confirmation remains immediate with all six world voices occupied")
	var active_ui: int = 0
	for player: AudioStreamPlayer in audio.ui_players:
		if player.playing: active_ui += 1
	_check(active_ui > 0 and active_ui <= 2, "actual reserved UI playback is active and bounded")
	var rejected_before: int = _count("reject")
	app._play_tone(140.0, 0.08)
	_check(_count("reject") == rejected_before + 1, "existing rejection input maps to distinct preloaded rejection cue")
	_check(not audio.play_world("loot", position + Vector2(40, 0), position), "distant off-camera world events are inaudible")
	await create_timer(0.75).timeout
	_check(audio.active_world_voices() == 0, "actual short WAV playbacks retire without queued bursts")


func _test_mute_and_boundaries() -> void:
	var audio: Node = app.game_audio
	var before: int = _count("confirm")
	app.muted = true
	app._apply_audio_settings()
	_check(not audio.play_ui("confirm") and AudioServer.is_bus_mute(0), "master mute prevents new SFX and reaches actual audio bus")
	app.muted = false
	app.effects_volume = 0.0
	app._apply_audio_settings()
	_check(not audio.play_ui("confirm") and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero effects level prevents cues while Music is independent")
	_check(_count("confirm") == before, "muted inputs never queue future cues")
	var loot_before: int = _count("loot")
	var position: Vector2 = app.camera.position / app.TILE
	app.sim._add_effect("loot", position, position, 1.8)
	_tick()
	for level: float in [0.0, 0.5, 1.0]:
		app.effects_volume = level
		app._apply_audio_settings()
		_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(maxf(level, 0.0001))), "effects boundary reaches SFX bus %s" % level)
	app.effects_volume = 0.7
	app._apply_audio_settings()
	_tick()
	_check(_count("loot") == loot_before, "events consumed while muted never replay when effects are restored")


func _test_inactive_and_reset() -> void:
	_start()
	var audio: Node = app.game_audio
	var position: Vector2 = app.camera.position / app.TILE
	for mode: String in ["pause", "title", "restart"]:
		audio.play_world("warning", position, position)
		app.menu = mode
		app._process(0.0)
		_check(audio.active_world_voices() == 0 and not audio.gameplay_active, "menu retires world voices immediately: " + mode)
		var before: int = _count("loot")
		app.sim._add_effect("loot", position, position, 1.8)
		app.menu = ""
		app._process(0.05)
		_check(_count("loot") == before, "menu resume primes extant effects without burst: " + mode)
	app.sim.paused = true
	app._process(0.0)
	_check(audio.active_world_voices() == 0, "tactical pause retires world voices")
	var paused_before: String = JSON.stringify(app.sim.save_state())
	app._process(0.1)
	_check(JSON.stringify(app.sim.save_state()) == paused_before, "paused process and audio leave simulation/save exactly unchanged")
	app.start_campaign()
	app._process(0.0)
	_check(audio.active_world_voices() == 0, "campaign restart primes state without previous run cues")


func _test_load_primes_saved_effects() -> void:
	_start()
	var position: Vector2 = app.camera.position / app.TILE
	app.sim._add_effect("loot", position, position, 1.8)
	_check(app.save_campaign(), "actual isolated campaign save succeeds with a persistent loot effect")
	var before: int = _count("loot")
	_check(app.load_campaign(), "actual save reload succeeds")
	var restored: String = JSON.stringify(app.sim.save_state())
	app.game_audio.prime(app.sim)
	_check(JSON.stringify(app.sim.save_state()) == restored, "load priming preserves complete loaded save exactly")
	app._process(0.05)
	await create_timer(0.26).timeout
	app._process(0.05)
	_check(_count("loot") == before, "saved long-lived loot never replays after actual load")
	app._release_audio()
	for player: AudioStreamPlayer in app.game_audio.world_players + app.game_audio.ui_players:
		_check(not player.playing and player.stream == null, "audio release retires each actual playback and stream")


func _test_native_mixer_signal() -> void:
	if AudioServer.get_driver_name() == "Dummy":
		print("Native mixer signal: skipped for explicitly selected Dummy driver")
		return
	app.volume = 0.6
	app.effects_volume = 0.7
	app.muted = false
	app._apply_audio_settings()
	var sfx: int = AudioServer.get_bus_index("SFX")
	_check(app.game_audio.play_ui("warning", 0.4), "native mixer receives a soft preloaded cue")
	var peak_db: float = -200.0
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
		peak_db = maxf(peak_db, AudioServer.get_bus_peak_volume_left_db(sfx, 0))
	_check(peak_db > -75.0 and peak_db < -5.0, "actual native SFX mixer produces a nonzero signal with ample headroom")
	print("Native SFX mixer peak dB: ", peak_db, "; driver: ", AudioServer.get_driver_name())
