extends RefCounted
## Observes rendered frame intervals only; never advances or edits game state.
## Histograms and phase/state keys have fixed sizes for an arbitrarily long run.
const PHASES: Array[String] = ["opening", "home_transfer", "middle_economy", "middle_withdrawal", "forward_rebuild", "exit_build", "exit_arrival", "other"]
const EXCLUDED: Array[String] = ["not_started", "menu", "non_playing", "paused", "unfocused", "outside_cycle", "transition"]
const BIN_WIDTH_USEC: int = 1000
const FINITE_BINS: int = 256

var _context: Callable
var _running: bool = false
var _previous: Dictionary = {}
var _global: Dictionary = {}
var _cycle: Dictionary = {}
var _cycle_previous: Dictionary = {}
var _cycle_open: bool = false


func start(read_context: Callable) -> void:
	stop()
	_context = read_context
	_previous.clear()
	_cycle_previous.clear()
	_cycle.clear()
	_cycle_open = false
	_global = _new_series()
	_running = true
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func stop() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	_running = false


func begin_cycle() -> void:
	_cycle = _new_series()
	_cycle_previous.clear()
	_cycle_open = true


func end_cycle() -> Dictionary:
	_cycle_open = false
	return _snapshot(_cycle)


func snapshot_global() -> Dictionary:
	return _snapshot(_global)


func _new_bucket() -> Dictionary:
	var histogram: Array[int] = []
	histogram.resize(FINITE_BINS + 1)
	histogram.fill(0)
	return {"count": 0, "sum_usec": 0, "max_usec": 0, "over_33333_usec": 0, "over_50000_usec": 0, "over_100000_usec": 0, "histogram": histogram}


func _new_series() -> Dictionary:
	var phases: Dictionary = {}
	var excluded: Dictionary = {}
	for phase: String in PHASES: phases[phase] = _new_bucket()
	for state: String in EXCLUDED: excluded[state] = _new_bucket()
	return {"all": _new_bucket(), "active": _new_bucket(), "phases": phases, "excluded": excluded,
		"endpoint_count": 0, "first_endpoint_usec": 0, "last_endpoint_usec": 0, "phase_boundary_count": 0,
		"state_boundary_count": 0, "invalid_nonpositive_intervals": 0, "unknown_phase_endpoints": 0, "unknown_state_endpoints": 0}


func _on_frame_post_draw() -> void:
	if not _running or not _context.is_valid(): return
	# Timestamp first, before context reads, so this observer's own cost remains
	# in the following interval, just like normal save/load and capture stalls.
	var now: int = Time.get_ticks_usec()
	var provided: Dictionary = _context.call()
	var phase: String = str(provided.get("phase", "other"))
	var state: String = str(provided.get("state", "outside_cycle"))
	# Own this snapshot; never annotate a caller's potentially shared Dictionary.
	var current: Dictionary = {"time_usec": now}
	current["unknown_phase"] = not PHASES.has(phase)
	current["unknown_state"] = state != "active" and not EXCLUDED.has(state)
	current["phase"] = "other" if current.unknown_phase else phase
	current["state"] = "outside_cycle" if current.unknown_state else state
	_record_endpoint(_global, _previous, current)
	_previous = current
	if _cycle_open:
		_record_endpoint(_cycle, _cycle_previous, current)
		_cycle_previous = current


func _record_endpoint(series: Dictionary, previous: Dictionary, current: Dictionary) -> void:
	series.endpoint_count += 1
	if series.endpoint_count == 1: series.first_endpoint_usec = int(current.time_usec)
	series.last_endpoint_usec = int(current.time_usec)
	if current.unknown_phase: series.unknown_phase_endpoints += 1
	if current.unknown_state: series.unknown_state_endpoints += 1
	if previous.is_empty(): return
	var elapsed: int = int(current.time_usec) - int(previous.time_usec)
	if elapsed <= 0:
		series.invalid_nonpositive_intervals += 1
		return
	_add(series["all"], elapsed)
	if str(previous.phase) != str(current.phase): series.phase_boundary_count += 1
	if str(previous.state) != str(current.state): series.state_boundary_count += 1
	if str(previous.state) == "active" and str(current.state) == "active":
		_add(series.active, elapsed)
		# Whole (previous,current] interval belongs to the LEFT endpoint phase.
		# A phase boundary is counted explicitly, never interpolated or dropped.
		_add(series.phases[str(previous.phase)], elapsed)
	else:
		var state: String = str(previous.state) if str(previous.state) == str(current.state) else "transition"
		_add(series.excluded[state], elapsed)


func _add(bucket: Dictionary, elapsed: int) -> void:
	bucket.count += 1
	bucket.sum_usec += elapsed
	bucket.max_usec = maxi(int(bucket.max_usec), elapsed)
	if elapsed > 33333: bucket.over_33333_usec += 1
	if elapsed > 50000: bucket.over_50000_usec += 1
	if elapsed > 100000: bucket.over_100000_usec += 1
	var index: int = mini(FINITE_BINS, int(elapsed / BIN_WIDTH_USEC))
	bucket.histogram[index] += 1


func _percentile_interval(bucket: Dictionary, fraction: float) -> Variant:
	if int(bucket.count) == 0: return null
	var rank: int = ceili(float(bucket.count) * fraction)
	var cumulative: int = 0
	for index: int in range(FINITE_BINS + 1):
		cumulative += int(bucket.histogram[index])
		if cumulative >= rank:
			if index == FINITE_BINS:
				return {"lower_usec_inclusive": FINITE_BINS * BIN_WIDTH_USEC, "upper_usec_inclusive": int(bucket.max_usec), "overflow_bin": true}
			return {"lower_usec_inclusive": index * BIN_WIDTH_USEC, "upper_usec_exclusive": (index + 1) * BIN_WIDTH_USEC, "overflow_bin": false}
	return null


func _bucket_snapshot(bucket: Dictionary) -> Dictionary:
	var result: Dictionary = bucket.duplicate(true)
	result["mean_ms"] = float(bucket.sum_usec) / float(bucket.count) / 1000.0 if int(bucket.count) > 0 else null
	result["observed_frames_per_second"] = float(bucket.count) * 1000000.0 / float(bucket.sum_usec) if int(bucket.sum_usec) > 0 else null
	result["p50_interval"] = _percentile_interval(bucket, 0.50)
	result["p95_interval"] = _percentile_interval(bucket, 0.95)
	result["p99_interval"] = _percentile_interval(bucket, 0.99)
	result["overflow_count"] = int(bucket.histogram[FINITE_BINS])
	return result


func _snapshot(series: Dictionary) -> Dictionary:
	if series.is_empty(): return {}
	var result: Dictionary = {"schema_version": 1, "clock": "Time.get_ticks_usec", "signal": "RenderingServer.frame_post_draw",
		"scope": "Observed app frame-post-draw wall intervals, including normal gameplay save/load, autosave, diagnostics and presentation pacing. Not isolated GPU time, physical scanout, minimum hardware or a performance pass verdict. Native-export identity belongs to the containing runner report.",
		"performance_acceptance": "not_assessed", "interval": "(previous_post_draw,current_post_draw]",
		"raw_frame_intervals_retained": false,
		"phase_attribution": "Entire interval uses the previous endpoint phase; phase-boundary intervals are counted without interpolation.",
		"active_policy": "Both endpoints must be active; mixed states go to excluded.transition. Excluded intervals remain in all. No time rebase, clamp or exclusion around normal save/load.",
		"first_endpoint_policy": "First endpoint establishes a baseline and produces no interval.",
		"histogram_spec": {"bin_width_usec": BIN_WIDTH_USEC, "finite_bins": FINITE_BINS, "overflow_lower_usec_inclusive": FINITE_BINS * BIN_WIDTH_USEC,
			"percentiles": "Nearest-rank histogram bin bounds, not exact sample percentiles. Overflow upper bound is the exact observed max."},
		"phase_limit": PHASES.size(), "phase_names": PHASES.duplicate(), "all": _bucket_snapshot(series["all"]), "active": _bucket_snapshot(series.active), "phases": {}, "excluded": {}}
	for key: String in ["endpoint_count", "first_endpoint_usec", "last_endpoint_usec", "phase_boundary_count", "state_boundary_count", "invalid_nonpositive_intervals", "unknown_phase_endpoints", "unknown_state_endpoints"]:
		result[key] = series[key]
	for phase: String in PHASES: result.phases[phase] = _bucket_snapshot(series.phases[phase])
	for state: String in EXCLUDED: result.excluded[state] = _bucket_snapshot(series.excluded[state])
	return result
