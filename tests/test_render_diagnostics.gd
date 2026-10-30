extends SceneTree
## Run headless with fresh isolated XDG vars set BEFORE engine startup, then:
## ./run.sh --headless -s tests/test_render_diagnostics.gd -- --render-diagnostics
## This test never starts the renderer, main scene or performance measurement.

const Runner = preload("res://scripts/diagnostics/render_runner.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var preflight: Array[String] = Runner.validate_environment()
	if not preflight.is_empty():
		for error: String in preflight: printerr("RENDER_DIAGNOSTICS_TEST_REQUIRES_FRESH_ISOLATION ", error)
		quit(1)
		return
	_test_environment()
	_test_arguments()
	_test_symlink_boundaries()
	_test_canonical_fixture()
	print("RENDER_DIAGNOSTICS_TEST checks=", checks, " failures=", failures.size())
	for failure: String in failures: printerr("RENDER_DIAGNOSTICS_TEST_FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _test_environment() -> void:
	var isolation: String = OS.get_environment("BENCH_ISOLATION_ROOT")
	_check(not isolation.is_empty(), "test must start with dedicated isolated XDG environment")
	if isolation.is_empty(): return
	_check(Runner.validate_environment().is_empty(), "fresh isolated XDG and valid args accepted")
	OS.unset_environment("BENCH_ISOLATION_ROOT")
	var missing: Array[String] = Runner.validate_environment()
	_check(not missing.is_empty() and missing[0].contains("BENCH_ISOLATION_ROOT"), "missing isolation rejected early")
	OS.set_environment("BENCH_ISOLATION_ROOT", isolation)
	var original_data: String = OS.get_environment("XDG_DATA_HOME")
	OS.set_environment("XDG_DATA_HOME", OS.get_environment("HOME").path_join(".local/share"))
	_check(not Runner.validate_environment().is_empty(), "real data directory rejected")
	OS.set_environment("XDG_DATA_HOME", original_data)
	var user_dir: String = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(user_dir)
	var sentinel: String = user_dir.path_join("settings.cfg")
	var file: FileAccess = FileAccess.open(sentinel, FileAccess.WRITE)
	_check(file != null, "test settings sentinel can be written in isolated directory")
	if file != null:
		file.store_string("fresh-isolation-sentinel")
		file.close()
		_check(not Runner.validate_environment().is_empty(), "preexisting settings rejected before application initialization")
		DirAccess.remove_absolute(sentinel)
	_check(Runner.validate_environment().is_empty(), "fresh isolation remains valid after sentinel cleanup")

func _test_arguments() -> void:
	var valid: Dictionary = Runner.parse_arguments(PackedStringArray(["--render-diagnostics"]))
	_check(valid.errors.is_empty() and valid.frames == 600 and valid.warmup == 120, "full defaults preserve 600/120 frame scope")
	_check(valid.output_dir == OS.get_environment("BENCH_ISOLATION_ROOT").path_join("output"), "default output is absolute isolated root/output")
	var quick: Dictionary = Runner.parse_arguments(PackedStringArray(["--render-diagnostics", "--quick"]))
	_check(quick.errors.is_empty() and (quick.frames + quick.warmup) * 2 < 60, "quick remains under 60 frame warmup/sample scope")
	var prepare: Dictionary = Runner.parse_arguments(PackedStringArray(["--render-diagnostics", "--prepare-only"]))
	_check(prepare.errors.is_empty() and prepare.frames == 1 and prepare.warmup == 0, "prepare-only is bounded")
	for arguments: PackedStringArray in [
		PackedStringArray([]),
		PackedStringArray(["--render-diagnostics", "--capture=/tmp/unsafe.png"]),
		PackedStringArray(["--render-diagnostics", "--smoke"]),
		PackedStringArray(["--render-diagnostics", "--quick", "--prepare-only"]),
		PackedStringArray(["--render-diagnostics", "--frames=wrong"]),
		PackedStringArray(["--render-diagnostics", "--frames=600=garbage"]),
		PackedStringArray(["--render-diagnostics", "--warmup=120=garbage"]),
		PackedStringArray(["--render-diagnostics", "--max-seconds=180=garbage"]),
		PackedStringArray(["--render-diagnostics", "--frames=0"]),
		PackedStringArray(["--render-diagnostics", "--warmup=20"]),
		PackedStringArray(["--render-diagnostics", "--max-seconds=9999"]),
		PackedStringArray(["--render-diagnostics", "--zoom=invalid"]),
		PackedStringArray(["--render-diagnostics", "--quick", "--quick"]),
		PackedStringArray(["--render-diagnostics", "--output-dir=res://work/unsafe"]),
		PackedStringArray(["--render-diagnostics", "--output-dir=/tmp/outside-isolation"]),
		PackedStringArray(["--render-diagnostics", "--output-dir=" + OS.get_environment("BENCH_ISOLATION_ROOT").path_join("../escaped")]),
	]:
		_check(not Runner.parse_arguments(arguments).errors.is_empty(), "reject unsupported/mixed arguments: " + str(arguments))

func _test_symlink_boundaries() -> void:
	var isolation: String = OS.get_environment("BENCH_ISOLATION_ROOT")
	var link: String = isolation.path_join("outside-link")
	var destination: String = isolation.get_base_dir().path_join("uncreated-outside-diagnostics-target")
	var directory: DirAccess = DirAccess.open(isolation)
	var result: Error = directory.create_link(destination, link)
	_check(result == OK, "test can create an isolated dangling symlink without writing its target")
	if result != OK: return
	var arguments: PackedStringArray = PackedStringArray(["--render-diagnostics", "--output-dir=" + link.path_join("new-output")])
	_check(not Runner.parse_arguments(arguments).errors.is_empty(), "new output below an escaping symlink is rejected")
	var original_data: String = OS.get_environment("XDG_DATA_HOME")
	OS.set_environment("XDG_DATA_HOME", link.path_join("data"))
	_check(not Runner.validate_environment().is_empty(), "XDG data below an escaping symlink is rejected")
	OS.set_environment("XDG_DATA_HOME", original_data)
	OS.set_environment("BENCH_ISOLATION_ROOT", link)
	_check(not Runner.validate_environment().is_empty(), "symlink isolation root is rejected")
	OS.set_environment("BENCH_ISOLATION_ROOT", isolation)
	DirAccess.remove_absolute(link)
	_check(Runner.validate_environment().is_empty(), "isolation valid after symlink cleanup")

func _test_canonical_fixture() -> void:
	var fingerprint: Dictionary = Runner.fixture_fingerprint()
	_check(bool(fingerprint.valid), "runner fixture fingerprint matches canonical and prevalidated constant")
	var source: String = Runner._fixture_source("res://tests/benchmark_campaign.gd")
	_check(not source.is_empty(), "canonical fixture text available for prebuild test")
	if source.is_empty(): return
	var canonical_script: GDScript = GDScript.new()
	canonical_script.source_code = "extends RefCounted\nconst Simulation = preload(\"res://scripts/campaign_simulation.gd\")\nconst FRONT_CAMP: int = 5000\nvar errors: Array[String] = []\n\n" + source
	var compile_result: Error = canonical_script.reload()
	_check(compile_result == OK, "canonical fixture compiles independently without creating another SceneTree")
	if compile_result != OK: return
	var canonical: RefCounted = canonical_script.new()
	var runner: Node = Runner.new()
	var expected: Dictionary = canonical._make_busy_scene()
	var actual: Dictionary = runner._make_busy_scene()
	_check(canonical.errors.is_empty() and runner.errors.is_empty(), "both fixtures pass semantic load and paid build orders")
	_check(actual.construction_ids == expected.construction_ids and actual.construction_ids.size() == 3, "canonical construction IDs match")
	_check(actual.sim.save_state() == expected.sim.save_state(), "full serialized runner fixture state equals canonical fixture")
	var counts: Dictionary = runner._actor_counts(actual.sim)
	_check(counts.friendly == 32 and counts.enemy == 100, "fixture retains requested 32/100 population")
	# Advancing both fixtures catches divergent orders, RNG, paths or cached setup.
	for index: int in range(12):
		actual.sim.tick(0.05)
		expected.sim.tick(0.05)
	_check(actual.sim.save_state() == expected.sim.save_state(), "fixture state still equals canonical after real simulation ticks")
	runner.free()
