extends SceneTree
## Reproducible headless simulation benchmark, NOT a renderer/FPS benchmark.
## Example: Godot --headless --path . -s tests/benchmark_campaign.gd -- --runs=3 --samples=600

const Simulation = preload("res://scripts/campaign_simulation.gd")
const STEP: float = 0.05
const FRONT_CAMP: int = 5000
const OUTPUT_DIR: String = "res://work/benchmarks"
var runs: int = 3
var samples: int = 600
var warmup: int = 120
var save_every: int = 150
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--runs="): runs = clampi(argument.trim_prefix("--runs=").to_int(), 1, 10)
		elif argument.begins_with("--samples="): samples = clampi(argument.trim_prefix("--samples=").to_int(), 100, 10000)
		elif argument.begins_with("--warmup="): warmup = clampi(argument.trim_prefix("--warmup=").to_int(), 0, 2000)
		elif argument.begins_with("--save-every="): save_every = clampi(argument.trim_prefix("--save-every=").to_int(), 50, 10000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var report: Dictionary = {
		"recorded_utc": Time.get_datetime_string_from_system(true, true) + "Z",
		"runtime": Engine.get_version_info(),
		"platform": OS.get_name(), "os_version": OS.get_version(),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"display_server": DisplayServer.get_name(),
		"debug_build": OS.is_debug_build(), "editor_capable_runtime": OS.has_feature("editor"),
		"system_memory": _proc_memory("/proc/meminfo", ["MemTotal", "MemAvailable"]),
		"simulation_sha256": FileAccess.get_sha256("res://scripts/campaign_simulation.gd"),
		"benchmark_sha256": FileAccess.get_sha256("res://tests/benchmark_campaign.gd"),
		"method": {
			"fixed_step_seconds": STEP, "runs": runs, "warmup_ticks": warmup,
			"sample_ticks_per_run": samples, "save_every_sample_ticks": save_every,
			"percentiles": "Nearest-rank over individual timed sim.tick(0.05) calls; non-overlapping runs use the same seed and fixture.",
			"timed_tick_scope": "Simulation call only; state inspection, JSON, disk writes, memory probes and reporting are outside tick timing and reported separately.",
			"fixture": "32 live friendly actors (2 trucks, 6 workers, 4 engineers, 20 rifles) and 100 live zombies on the actual mission terrain; close combat, powered production, real queued construction, connected salvage hauling and periodic save/write/read/validate.",
			"stability_control": "Actor and existing building HP are increased to keep the requested workload alive for each measured run. Combat, orders, paths, separation, production, construction and hauling still execute normally. No performance claim about balanced combat is implied.",
			"limits": "Headless local CPU simulation measurement, not 60 FPS evidence. No drawing, input, GPU, audio, Steam, clean-machine or minimum-hardware validation. OS/other processes are not controlled. RSS high-water values are cumulative for this process.",
		},
		"runs": [],
	}
	var aggregate_ticks: Array = []
	for index: int in range(runs):
		var result: Dictionary = _measure_run(index)
		report.runs.append(result)
		aggregate_ticks.append_array(result.tick_samples_usec)
		print("BENCH_RUN %d tick_ms=%s workload=%s" % [index + 1, JSON.stringify(result.tick_ms), str(result.valid_workload)])
	report["aggregate_tick_ms"] = _stats(aggregate_ticks)
	report["memory_at_end"] = _memory_snapshot()
	report["simulation_sha256_at_end"] = FileAccess.get_sha256("res://scripts/campaign_simulation.gd")
	report["source_changed_during_run"] = report.simulation_sha256 != report.simulation_sha256_at_end
	if report.source_changed_during_run: errors.append("simulation source changed during measurement; rerun against a stable candidate")
	report["errors"] = errors
	report["valid_workload"] = errors.is_empty()
	var output: String = OUTPUT_DIR + "/campaign-benchmark.json"
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write benchmark report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BENCHMARK_REPORT ", ProjectSettings.globalize_path(output))
	print("BENCHMARK_AGGREGATE ", JSON.stringify(report.aggregate_tick_ms))
	for error: String in errors:
		printerr("BENCHMARK_INVALID ", error)
	quit(0 if errors.is_empty() else 1)

func _make_busy_scene() -> Dictionary:
	var sim: Variant = Simulation.new()
	sim.reset(42)
	var templates: Dictionary = {}
	for unit: Dictionary in sim.units:
		if not templates.has(str(unit.kind)):
			templates[str(unit.kind)] = unit.duplicate(true)
	for building: Dictionary in sim.buildings:
		building.hp = 1000000.0
		building.max_hp = 1000000.0
	for camp: Dictionary in sim.camps:
		camp.materials = 10000.0
		camp.supplies = 10000.0
		camp.fuel = 10000.0
		camp.recipe = "idle"
	var front: Dictionary = {
		"id": FRONT_CAMP, "name": "Busy-scene forward camp", "pos": Vector2(26, 23),
		"state": "active", "materials": 10000.0, "supplies": 10000.0,
		"fuel": 10000.0, "salvage": 60.0, "crude": 60.0, "power": 0.0,
		"priority": "defense", "recipe": "materials", "recruit_queue": [],
	}
	sim.camps.append(front)
	sim.buildings.append(_building(5100, "camp", Vector2(26, 23)))
	sim.buildings.append(_building(5101, "generator", Vector2(27, 27)))
	sim.buildings.append(_building(5102, "workshop", Vector2(25, 27)))
	sim.buildings.append(_building(5103, "tower", Vector2(27, 19)))
	sim.buildings.append(_building(5104, "tower", Vector2(27, 24)))
	for x: int in range(9, 36): _road(sim, Vector2i(x, 21))
	for y: int in range(10, 32): _road(sim, Vector2i(35, y))
	for y: int in range(21, 28): _road(sim, Vector2i(26, y))
	for x: int in range(24, 30): _road(sim, Vector2i(x, 27))
	for y: int in range(19, 24): _road(sim, Vector2i(27, y))
	for x: int in range(26, 34): _road(sim, Vector2i(x, 23))
	for y: int in range(23, 26): _road(sim, Vector2i(33, y))
	sim.sites.append({"id": 6000, "kind": "quarry", "name": "Nearby benchmark salvage", "pos": Vector2(33, 25), "captured": true, "progress": 1.0, "stock": {"salvage": 100000.0}})
	sim.units.clear()
	var army: Array = []
	for index: int in range(32):
		var kind: String = "truck" if index < 2 else ("worker" if index < 8 else ("engineer" if index < 12 else "rifle"))
		var position: Vector2
		if kind == "truck": position = Vector2(24 + index, 23)
		elif kind == "worker": position = Vector2(24 + (index - 2) % 3 * 0.65, 24 + (index - 2) / 3 * 0.65)
		elif kind == "engineer": position = Vector2(24 + (index - 8) * 0.65, 26)
		else: position = Vector2(26 + (index - 12) % 5 * 0.65, 18.7 + (index - 12) / 5 * 0.65)
		position = _free_position(sim, position)
		var unit: Dictionary = _clone_actor(templates[kind], 1000 + index, position, FRONT_CAMP)
		sim.units.append(unit)
		if kind == "rifle": army.append(int(unit.id))
	for index: int in range(100):
		var position: Vector2 = Vector2(30 + index % 10 * 0.55, 17.5 + index / 10 * 0.55)
		var enemy: Dictionary = _clone_actor(templates["zombie"], 2000 + index, position, -1)
		enemy.pursuer = false
		sim.units.append(enemy)
	sim.main_truck_id = 1000
	sim.pursuit_start = 1000000.0
	sim.pursuit_x = -10000.0
	sim.effects.clear()
	sim.messages.clear()
	var state: Dictionary = sim.save_state()
	for pair: Array in state.payload.entries:
		if pair[0] == "next_id": pair[1] = 20000
	if not sim.load_state(state): errors.append("busy fixture failed semantic save validation")
	var construction_ids: Array = []
	for order: Array in [["tower", Vector2i(29, 26)], ["barracks", Vector2i(24, 30)], ["barricade", Vector2i(28, 29)], ["road", Vector2i(39, 27)]]:
		if not sim.build(order[0], order[1]): errors.append("busy construction order was rejected: " + str(order))
		elif order[0] != "road": construction_ids.append(int(sim.buildings.back().id))
	sim.command_task(army, "guard", Vector2(29, 20))
	return {"sim": sim, "construction_ids": construction_ids}

func _clone_actor(template: Dictionary, id_value: int, position: Vector2, owner: int) -> Dictionary:
	var unit: Dictionary = template.duplicate(true)
	unit.id = id_value
	unit.pos = position
	unit.target = position
	unit.guard_pos = position
	unit.camp_id = owner
	unit.hp = 1000000.0
	unit.max_hp = 1000000.0
	unit.path = []
	unit.path_index = 0
	unit.order = "idle"
	unit.state = "idle" if owner >= 0 else "guard"
	unit.manual = false
	unit.job_id = 0
	unit.cargo = {}
	unit.haul_site = 0
	unit.haul_stage = ""
	return unit

func _building(id_value: int, kind: String, position: Vector2) -> Dictionary:
	return {
		"id": id_value, "kind": kind, "pos": position, "camp_id": FRONT_CAMP,
		"hp": 1000000.0, "max_hp": 1000000.0, "progress": 1.0,
		"powered": false, "power_radius": 10.0 if kind == "generator" else 0.0,
		"required_power": 4.0 if kind == "workshop" else (3.0 if kind == "tower" else 0.0),
		"range": 7.0 if kind == "tower" else 0.0, "cooldown": 0.0,
	}

func _road(sim: Variant, tile: Vector2i) -> void:
	if int(sim.terrain[tile.y][tile.x]) >= 0:
		sim.roads[tile] = {"progress": 1.0, "camp_id": FRONT_CAMP}

func _free_position(sim: Variant, candidate: Vector2) -> Vector2:
	# Free tile centers also leave room for the largest .46-radius vehicle body.
	if sim.is_walkable(Vector2i(candidate.round())): return Vector2(Vector2i(candidate.round()))
	for distance: int in range(1, 5):
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP]:
			var test: Vector2 = candidate + Vector2(offset * distance)
			if sim.is_walkable(Vector2i(test.round())): return Vector2(Vector2i(test.round()))
	return candidate

func _measure_run(index: int) -> Dictionary:
	var errors_before: int = errors.size()
	var setup: Dictionary = _make_busy_scene()
	var sim: Variant = setup.sim
	var start_memory: Dictionary = _memory_snapshot()
	for step: int in range(warmup): sim.tick(STEP)
	var ticks: Array = []
	var saves: Array = []
	var min_friendly: int = 99999
	var max_friendly: int = 0
	var min_enemy: int = 99999
	var max_enemy: int = 0
	var nonempty_cargo_samples: int = 0
	var hauling_cargo_samples: int = 0
	var hauling_deliveries: int = 0
	var previous_hauling: Dictionary = {}
	var shot_samples: int = 0
	var construction_peak: float = 0.0
	var completed_buildings: int = 0
	var sampled_rss_peak: int = 0
	var wall_started: int = Time.get_ticks_usec()
	for step: int in range(samples):
		var started: int = Time.get_ticks_usec()
		sim.tick(STEP)
		ticks.append(Time.get_ticks_usec() - started)
		var friendly_count: int = 0
		var enemy_count: int = 0
		for unit: Dictionary in sim.units:
			if unit.team == "friendly": friendly_count += 1
			else: enemy_count += 1
			var has_cargo: bool = not Dictionary(unit.get("cargo", {})).is_empty()
			if has_cargo: nonempty_cargo_samples += 1
			var hauling: bool = str(unit.get("order", "")) == "haul" and has_cargo
			if hauling: hauling_cargo_samples += 1
			if bool(previous_hauling.get(int(unit.id), false)) and not has_cargo:
				var owner: Dictionary = sim.get_camp(int(unit.camp_id))
				if not owner.is_empty() and Vector2(unit.pos).distance_to(Vector2(owner.pos)) <= 2.5: hauling_deliveries += 1
			previous_hauling[int(unit.id)] = hauling
		min_friendly = mini(min_friendly, friendly_count)
		max_friendly = maxi(max_friendly, friendly_count)
		min_enemy = mini(min_enemy, enemy_count)
		max_enemy = maxi(max_enemy, enemy_count)
		for effect: Dictionary in sim.effects:
			if effect.kind == "shot" or effect.kind == "hit": shot_samples += 1
		for building: Dictionary in sim.buildings:
			if setup.construction_ids.has(int(building.id)):
				construction_peak = maxf(construction_peak, float(building.progress))
		if step % 60 == 0:
			sampled_rss_peak = maxi(sampled_rss_peak, int(_proc_memory("/proc/self/status", ["VmRSS"]).get("VmRSS_bytes", 0)))
		if (step + 1) % save_every == 0: saves.append(_measure_save(sim, index, step))
	for building: Dictionary in sim.buildings:
		if setup.construction_ids.has(int(building.id)) and float(building.progress) >= 1.0: completed_buildings += 1
	if min_friendly != 32 or max_friendly != 32 or min_enemy != 100 or max_enemy != 100:
		errors.append("run %d did not retain its requested 32/100 actor population" % (index + 1))
	if sim.outcome != "playing": errors.append("run %d stopped gameplay during the workload" % (index + 1))
	if nonempty_cargo_samples == 0: errors.append("run %d never performed physical cargo work" % (index + 1))
	if hauling_cargo_samples == 0 or hauling_deliveries == 0: errors.append("run %d did not observe real resource-hauling pickup and delivery; lengthen the sample or investigate logistics" % (index + 1))
	if shot_samples == 0: errors.append("run %d never performed actual combat" % (index + 1))
	if construction_peak <= 0.0: errors.append("run %d never advanced real paid construction" % (index + 1))
	return {
		"run": index + 1, "tick_ms": _stats(ticks), "tick_samples_usec": ticks,
		"wall_clock_ms_including_measurement": float(Time.get_ticks_usec() - wall_started) / 1000.0,
		"simulated_seconds_including_warmup": float(sim.time),
		"friendly_count_min_max": [min_friendly, max_friendly], "enemy_count_min_max": [min_enemy, max_enemy],
		"nonempty_cargo_actor_samples": nonempty_cargo_samples, "combat_effect_samples": shot_samples,
		"resource_hauling_cargo_actor_samples": hauling_cargo_samples, "resource_parcels_delivered": hauling_deliveries,
		"paid_construction_peak_progress": construction_peak, "completed_ordered_buildings": completed_buildings,
		"remaining_nearby_salvage": _site_stock(sim, 6000, "salvage"),
		"sampled_rss_peak_bytes": sampled_rss_peak,
		"memory_start": start_memory, "memory_end": _memory_snapshot(),
		"save_measurements": saves, "valid_workload": errors.size() == errors_before,
	}

func _measure_save(sim: Variant, run_index: int, sample_index: int) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var text: String = JSON.stringify(sim.save_state())
	var serialization_us: int = Time.get_ticks_usec() - start
	var path: String = ProjectSettings.globalize_path(OUTPUT_DIR + "/save-run-%d.json" % (run_index + 1))
	start = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		errors.append("benchmark save file cannot be opened")
		return {"valid": false}
	file.store_string(text)
	file.close()
	var rename_result: Error = DirAccess.rename_absolute(path + ".tmp", path)
	var write_us: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded: Variant = Simulation.new()
	loaded.reset(42)
	var valid: bool = parsed is Dictionary and loaded.load_state(parsed)
	var load_us: int = Time.get_ticks_usec() - start
	if rename_result != OK or not valid: errors.append("busy-scene written save failed read/semantic validation")
	return {
		"sample_tick": sample_index + 1, "bytes": text.to_utf8_buffer().size(),
		"serialization_ms": float(serialization_us) / 1000.0,
		"atomic_write_ms": float(write_us) / 1000.0,
		"read_parse_validate_ms": float(load_us) / 1000.0,
		"valid": valid and rename_result == OK,
	}

func _site_stock(sim: Variant, site_id: int, resource: String) -> float:
	for site: Dictionary in sim.sites:
		if int(site.id) == site_id: return float(Dictionary(site.get("stock", {})).get(resource, 0.0))
	return 0.0

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"samples": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: Variant in sorted: total += float(value)
	return {
		"samples": sorted.size(), "p50_ms": float(sorted[maxi(0, ceili(sorted.size() * 0.50) - 1)]) / 1000.0,
		"p95_ms": float(sorted[maxi(0, ceili(sorted.size() * 0.95) - 1)]) / 1000.0,
		"p99_ms": float(sorted[maxi(0, ceili(sorted.size() * 0.99) - 1)]) / 1000.0,
		"max_ms": float(sorted.back()) / 1000.0, "mean_ms": total / sorted.size() / 1000.0,
	}

func _memory_snapshot() -> Dictionary:
	return {
		"process_linux": _proc_memory("/proc/self/status", ["VmRSS", "VmHWM"]),
		"godot_static_bytes": OS.get_static_memory_usage(),
		"godot_static_peak_bytes": OS.get_static_memory_peak_usage(),
	}

func _proc_memory(path: String, keys: Array) -> Dictionary:
	var result: Dictionary = {"source": path, "available": FileAccess.file_exists(path)}
	if not FileAccess.file_exists(path): return result
	# Linux procfs reports size zero: read lines to EOF rather than get_as_text.
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.available = false
		return result
	while not file.eof_reached():
		var line: String = file.get_line()
		var fields: PackedStringArray = line.replace("\t", " ").split(" ", false)
		if fields.size() < 2: continue
		var key: String = fields[0].trim_suffix(":")
		if keys.has(key): result[key + "_bytes"] = fields[1].to_int() * 1024
	file.close()
	return result
