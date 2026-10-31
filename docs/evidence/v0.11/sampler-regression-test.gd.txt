extends SceneTree
## Arithmetic plus direct headless callback/cycle checks. No Main/simulation.
## start() is deliberately never called; this does not prove native frame pacing.
const Sampler = preload("res://scripts/diagnostics/frame_sampler.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_histogram_boundaries()
	_phase_and_state_boundaries()
	_excluded_states_and_invalid_time()
	_cycle_and_snapshot_boundaries()
	_callback_cycle_boundaries()
	_unknown_context_is_bounded_and_detached()
	print("Frame sampler arithmetic checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _endpoint(time_usec: int, phase: String = "opening", state: String = "active") -> Dictionary:
	return {"time_usec": time_usec, "phase": phase, "state": state, "unknown_phase": false, "unknown_state": false}


func _record(sampler: RefCounted, series: Dictionary, endpoints: Array[Dictionary]) -> void:
	var previous: Dictionary = {}
	for current: Dictionary in endpoints:
		sampler._record_endpoint(series, previous, current)
		previous = current


func _conservation(snapshot: Dictionary, label: String) -> void:
	var count: int = int(snapshot.active.count)
	var duration: int = int(snapshot.active.sum_usec)
	var phase_count: int = 0
	var phase_duration: int = 0
	var buckets: Array[Dictionary] = [snapshot["all"], snapshot.active]
	for phase: String in snapshot.phases:
		phase_count += int(snapshot.phases[phase].count)
		phase_duration += int(snapshot.phases[phase].sum_usec)
		buckets.append(snapshot.phases[phase])
	for state: String in snapshot.excluded:
		count += int(snapshot.excluded[state].count)
		duration += int(snapshot.excluded[state].sum_usec)
		buckets.append(snapshot.excluded[state])
	_check(count == int(snapshot["all"].count) and duration == int(snapshot["all"].sum_usec), label + ": active and excluded conserve count/time")
	_check(phase_count == int(snapshot.active.count) and phase_duration == int(snapshot.active.sum_usec), label + ": phases conserve active count/time")
	_check(int(snapshot["all"].count) + int(snapshot.invalid_nonpositive_intervals) == int(snapshot.endpoint_count) - 1, label + ": first endpoint is a baseline, not a frame")
	for bucket: Dictionary in buckets:
		var total: int = 0
		for value: int in bucket.histogram: total += value
		_check(bucket.histogram.size() == 257 and total == int(bucket.count), label + ": fixed histogram conserves samples")


func _histogram_boundaries() -> void:
	var sampler: RefCounted = Sampler.new()
	var series: Dictionary = sampler._new_series()
	var points: Array[Dictionary] = [_endpoint(1000000)]
	var time_usec: int = 1000000
	for interval: int in [1000, 1001, 33333, 33334, 50000, 50001, 100000, 100001, 255999, 256000, 1234567]:
		time_usec += interval
		points.append(_endpoint(time_usec))
	_record(sampler, series, points)
	var result: Dictionary = sampler._snapshot(series)
	var active: Dictionary = result.active
	_check(active.count == 11 and active.sum_usec == 2115236 and active.max_usec == 1234567, "actual sums and raw max retain the entire long stall")
	_check(active.over_33333_usec == 8 and active.over_50000_usec == 6 and active.over_100000_usec == 4, "long-frame comparisons are strictly greater than each threshold")
	_check(active.histogram[1] == 2 and active.histogram[33] == 2 and active.histogram[50] == 2 and active.histogram[100] == 2, "exact and adjacent bucket boundaries classify correctly")
	_check(active.histogram[255] == 1 and active.overflow_count == 2, "256ms boundary enters explicit overflow without clipping max")
	_check(active.p50_interval == {"lower_usec_inclusive": 50000, "upper_usec_exclusive": 51000, "overflow_bin": false}, "median reports a 1ms interval, not a fabricated exact sample")
	_check(active.p95_interval == {"lower_usec_inclusive": 256000, "upper_usec_inclusive": 1234567, "overflow_bin": true} and active.p99_interval == active.p95_interval, "overflow quantiles preserve their honest interval")
	_check(int(result.last_endpoint_usec) - int(result.first_endpoint_usec) == active.sum_usec, "monotonic endpoint span equals accumulated real intervals")
	_conservation(result, "thresholds")


func _phase_and_state_boundaries() -> void:
	var sampler: RefCounted = Sampler.new()
	var series: Dictionary = sampler._new_series()
	_record(sampler, series, [_endpoint(1000000), _endpoint(1010000), _endpoint(1030000, "middle_withdrawal"),
		_endpoint(1090000, "middle_withdrawal"), _endpoint(1130000, "middle_withdrawal", "menu"),
		_endpoint(1330000, "middle_withdrawal", "menu"), _endpoint(1360000, "exit_build"), _endpoint(1365000, "exit_build")])
	var result: Dictionary = sampler._snapshot(series)
	_check(result["all"].count == 7 and result["all"].sum_usec == 365000, "all intervals include menu and mixed-state boundaries")
	_check(result.active.count == 4 and result.active.sum_usec == 95000, "active intervals require two active endpoints")
	_check(result.phases.opening.sum_usec == 30000 and result.phases.middle_withdrawal.sum_usec == 60000 and result.phases.exit_build.sum_usec == 5000, "whole interval belongs to its left phase without interpolation")
	_check(result.phase_boundary_count == 2 and result.state_boundary_count == 2, "phase and state boundaries are separately counted")
	_check(result.excluded.transition.sum_usec == 70000 and result.excluded.menu.sum_usec == 200000, "menu transition time remains visible outside active")
	_check(result.phases.middle_withdrawal.max_usec == 60000 and result.phases.middle_withdrawal.over_50000_usec == 1, "a save-like active stall is retained, not rebased away")
	_conservation(result, "phase/state")


func _excluded_states_and_invalid_time() -> void:
	var sampler: RefCounted = Sampler.new()
	for state: String in ["not_started", "non_playing", "paused", "unfocused", "outside_cycle"]:
		var series: Dictionary = sampler._new_series()
		_record(sampler, series, [_endpoint(1000000, "other", state), _endpoint(1250000, "other", state)])
		var result: Dictionary = sampler._snapshot(series)
		_check(result.active.count == 0 and result.excluded[state].sum_usec == 250000 and result["all"].sum_usec == 250000, state + ": excluded time is retained in all")
	var invalid: Dictionary = sampler._new_series()
	_record(sampler, invalid, [_endpoint(1000), _endpoint(1000), _endpoint(2000)])
	var result: Dictionary = sampler._snapshot(invalid)
	_check(result.invalid_nonpositive_intervals == 1 and result["all"].count == 1 and result["all"].sum_usec == 1000, "zero duration is explicitly invalid rather than a fictitious fast frame")
	_conservation(result, "zero duration")
	var backwards: Dictionary = sampler._new_series()
	_record(sampler, backwards, [_endpoint(2000), _endpoint(1000)])
	_check(backwards.invalid_nonpositive_intervals == 1 and backwards["all"].count == 0, "backwards clock is explicitly invalid")
	var empty: Dictionary = sampler._snapshot(sampler._new_series())
	_check(empty.active.p50_interval == null and empty.active.mean_ms == null and empty.active.observed_frames_per_second == null, "empty samples are unavailable, not zero-time performance")


func _cycle_and_snapshot_boundaries() -> void:
	var sampler: RefCounted = Sampler.new()
	sampler._global = sampler._new_series()
	_record(sampler, sampler._global, [_endpoint(1000), _endpoint(11000), _endpoint(31000, "other", "menu"),
		_endpoint(41000, "other", "menu"), _endpoint(91000), _endpoint(111000)])
	sampler._previous = _endpoint(111000)
	var global_before: String = JSON.stringify(sampler.snapshot_global())
	var global_endpoint_before: String = JSON.stringify(sampler._previous)
	sampler.begin_cycle()
	_record(sampler, sampler._cycle, [_endpoint(1000), _endpoint(11000)])
	sampler._cycle_previous = _endpoint(11000)
	var first: Dictionary = sampler.end_cycle()
	sampler.begin_cycle()
	_check(sampler._cycle_previous.is_empty(), "new cycle resets only its own endpoint baseline")
	_record(sampler, sampler._cycle, [_endpoint(91000), _endpoint(111000)])
	var second: Dictionary = sampler.end_cycle()
	_check(first["all"].count == 1 and first["all"].sum_usec == 10000 and second["all"].count == 1 and second["all"].sum_usec == 20000, "new cycle does not invent an interval across intervening menus")
	_check(not sampler._cycle_open and JSON.stringify(sampler.snapshot_global()) == global_before and JSON.stringify(sampler._previous) == global_endpoint_before, "cycle begin/end leave continuous global history and its endpoint intact")
	var original_second: String = JSON.stringify(second)
	second.active.histogram[20] = 99999
	second.phases.opening.count = 99999
	second.phase_names[0] = "changed"
	_check(JSON.stringify(sampler._snapshot(sampler._cycle)) == original_second and Sampler.PHASES[0] == "opening", "snapshot mutations cannot write back into counters, histogram or fixed phase names")
	_conservation(sampler.snapshot_global(), "global across cycles")


func _callback_cycle_boundaries() -> void:
	var sampler: RefCounted = Sampler.new()
	var context: Dictionary = {"phase": "other", "state": "menu"}
	# Every call supplies a new Dictionary, just like runner._frame_context().
	sampler._context = func() -> Dictionary: return {"phase": context.phase, "state": context.state}
	sampler._global = sampler._new_series()
	sampler._running = true
	var cycles: Array[Dictionary] = []
	for cycle_index: int in range(7):
		sampler.begin_cycle()
		context.phase = "other"
		context.state = "menu"
		OS.delay_usec(500)
		sampler._on_frame_post_draw()
		context.phase = "opening"
		context.state = "active"
		OS.delay_usec(500)
		sampler._on_frame_post_draw()
		OS.delay_usec(500)
		sampler._on_frame_post_draw()
		cycles.append(sampler.end_cycle())
	sampler._running = false
	var result: Dictionary = sampler.snapshot_global()
	_check(result.endpoint_count == 21 and result["all"].count == 20, "actual callback path retains every interval across seven cycle resets")
	_check(result["all"].sum_usec == result.last_endpoint_usec - result.first_endpoint_usec, "actual callback monotonic span equals all interval durations across cycle resets")
	_check(result.excluded.transition.count == 13 and result.active.count == 7, "six between-cycle transition intervals remain in global accounting")
	for cycle: Dictionary in cycles:
		_check(cycle.endpoint_count == 3 and cycle["all"].count == 2 and cycle["all"].sum_usec == cycle.last_endpoint_usec - cycle.first_endpoint_usec, "actual callback cycle retains its own baseline and exact span")
	_conservation(result, "actual callbacks across seven cycles")


func _unknown_context_is_bounded_and_detached() -> void:
	var sampler: RefCounted = Sampler.new()
	var shared: Dictionary = {"phase": "unexpected_phase", "state": "unexpected_state"}
	var original: String = JSON.stringify(shared)
	sampler._context = func() -> Dictionary: return shared
	sampler._global = sampler._new_series()
	sampler._running = true
	# One direct callback tests normalization only; no signal or render is used.
	sampler._on_frame_post_draw()
	sampler._running = false
	var result: Dictionary = sampler.snapshot_global()
	_check(result.unknown_phase_endpoints == 1 and result.unknown_state_endpoints == 1 and result.phase_limit == 8 and result.phases.size() == 8 and result.excluded.size() == 7, "unknown context is counted without expanding fixed phase/state maps")
	_check(JSON.stringify(shared) == original and sampler._previous.phase == "other" and sampler._previous.state == "outside_cycle", "sampler normalization owns its snapshot and leaves caller data unchanged")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
