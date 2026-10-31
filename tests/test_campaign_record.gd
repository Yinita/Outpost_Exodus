extends SceneTree
## Actual failed native snapshot regression; no simulated ticks or game orders.
## Corrupted financial records below are copies, not playable-state fixtures.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const Route = preload("res://scripts/diagnostics/campaign_route.gd")
const FIXTURE: String = "res://tests/fixtures/native-exit-funded.json"
const FIXTURE_SHA256: String = "94f0b5e4c623cc23af1c47c637792b05d8d999c9c89d8e3965035754c0080e4a"
const FRONT_ID: int = 210
const BUILDING_ID: int = 19
const JOB_ID: int = 286

class RecordApp:
	extends Node2D
	var sim: RefCounted

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FileAccess.get_sha256(FIXTURE) == FIXTURE_SHA256, "fixture is the unchanged actual failed native snapshot")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/native-exit-funded.provenance.json"))
	_check(provenance.get("sha256", "") == FIXTURE_SHA256 and provenance.get("source_commit", "") == "2a00c7e97ff7954b0756bc49445866d92aec6b07", "provenance binds original native source/payload and snapshot SHA")
	var sim: RefCounted = Simulation.new()
	var loaded: bool = sim.load_state(saved)
	_check(loaded, "actual native full-run snapshot passes real Simulation.load_state")
	if loaded:
		_check(sim.outcome == "playing" and is_equal_approx(float(sim.time), 1574.15) and float(sim.exit_progress) >= 1.0, "fixture records the genuine pre-final-movement completed exit state")
		_check(int(sim.exit_building_id) == BUILDING_ID and not sim.get_camp(FRONT_ID).is_empty(), "actual loaded exit and forward camp retain recorded IDs")
		var app: Node2D = RecordApp.new()
		app.sim = sim
		var route: RefCounted = Route.new()
		route.app = app
		var before: String = _canonical(sim.save_state())
		var record: Dictionary = route._exit_job_record(FRONT_ID)
		_check(_matches_actual_job(record), "instance query recovers funded/done exit286 from actual encoded state")
		_check(_canonical(sim.save_state()) == before, "record query preserves full live simulation and RNG exactly")
		_check(route._exit_job_record(FRONT_ID + 1).is_empty(), "instance query refuses wrong forward camp")
		_check(_canonical(sim.save_state()) == before, "negative instance query also leaves simulation and RNG unchanged")
		if record.has("costs"): record.costs["materials"] = 0.0
		_check(_matches_actual_job(route._exit_job_record(FRONT_ID)), "caller mutation cannot change subsequent actual funded record")
		_check(_canonical(sim.save_state()) == before, "returned financial record cannot mutate the live campaign")
		app.free()
	_test_extraction(saved)
	_test_dictionary_decoder()
	print("CAMPAIGN_RECORD_TEST checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: printerr("CAMPAIGN_RECORD_TEST_FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)


func _test_extraction(saved: Dictionary) -> void:
	var before: String = _canonical(saved)
	var payload: Dictionary = Route.serialized_dictionary(saved.get("payload"))
	_check(is_equal_approx(float(payload.get("time", -1.0)), 1574.15), "same one-level decoder recovers actual native snapshot time for slot summaries")
	_check(_matches_actual_job(Route.extract_exit_job(saved, FRONT_ID, BUILDING_ID)), "pure extractor reads actual paid costs140/45/30 from native encoding")
	_check(_canonical(saved) == before, "pure extraction leaves the exact input snapshot unchanged")
	_check(Route.extract_exit_job(saved, FRONT_ID + 1, BUILDING_ID).is_empty(), "wrong source camp argument refuses funding proof")
	_check(Route.extract_exit_job(saved, FRONT_ID, BUILDING_ID + 1).is_empty(), "wrong exit building argument refuses funding proof")
	for change: String in ["materials", "fuel", "supplies", "missing_cost", "unfunded", "missing_funding", "undelivered", "unfinished", "numeric_funding", "fractional_job_id", "wrong_source", "wrong_building", "malformed_costs", "numeric_string", "extra_cost", "raw_costs"]:
		var copied: Dictionary = saved.duplicate(true)
		var job: Dictionary = _encoded_job(copied)
		_check(not job.is_empty(), "negative%s copy locates the actual exit record" % change)
		if job.is_empty(): continue
		var costs: Dictionary = _encoded_value(job, "costs")
		var changed: bool = false
		if change in ["materials", "fuel", "supplies"]:
			var amount: float = {"materials": 139.0, "fuel": 44.0, "supplies": 29.0}[change]
			changed = _set_encoded_value(costs, change, amount)
		elif change == "missing_cost": changed = _remove_encoded_value(costs, "materials")
		elif change == "unfunded": changed = _set_encoded_value(job, "funded", false)
		elif change == "missing_funding": changed = _remove_encoded_value(job, "funded")
		elif change == "undelivered": changed = _set_encoded_value(job, "delivered", false)
		elif change == "unfinished": changed = _set_encoded_value(job, "done", false)
		elif change == "numeric_funding": changed = _set_encoded_value(job, "funded", 1)
		elif change == "fractional_job_id": changed = _set_encoded_value(job, "id", 286.5)
		elif change == "wrong_source": changed = _set_encoded_value(job, "source_camp_id", FRONT_ID + 1)
		elif change == "wrong_building": changed = _set_encoded_value(job, "building_id", BUILDING_ID + 1)
		elif change == "malformed_costs": changed = _set_encoded_value(job, "costs", {"$type": "Dictionary", "entries": [["materials", 140.0], ["fuel"], ["supplies", 30.0]]})
		elif change == "numeric_string": changed = _set_encoded_value(costs, "materials", "140")
		elif change == "extra_cost":
			costs.entries.append(["crude", 1.0])
			changed = true
		elif change == "raw_costs": changed = _set_encoded_value(job, "costs", {"materials": 140.0, "fuel": 45.0, "supplies": 30.0})
		_check(changed, "negative%s changes only a copied financial record" % change)
		var copied_before: String = _canonical(copied)
		_check(Route.extract_exit_job(copied, FRONT_ID, BUILDING_ID).is_empty(), "negative%s cannot masquerade as the funded exit" % change)
		_check(_canonical(copied) == copied_before, "negative%s inspection remains read-only" % change)
	_check(_canonical(saved) == before, "all corrupted-record tests preserve the original native snapshot")


func _test_dictionary_decoder() -> void:
	var nested: Dictionary = {"$type": "Dictionary", "entries": [["materials", 140.0]]}
	var encoded: Dictionary = {"$type": "Dictionary", "entries": [["time", 12.0], ["costs", nested]]}
	var decoded: Dictionary = Route.serialized_dictionary(encoded)
	_check(decoded.get("time", -1.0) == 12.0 and decoded.get("costs", {}) == nested, "decoder unwraps exactly one actual Dictionary level")
	for invalid: Variant in [null, "not a dictionary", [], {}, {"materials": 140.0}, {"$type": "Vector2", "entries": []}, {"$type": "Dictionary"}, {"$type": "Dictionary", "entries": "wrong"}, {"$type": "Dictionary", "entries": ["wrong"]}, {"$type": "Dictionary", "entries": [["fuel"]]}, {"$type": "Dictionary", "entries": [["fuel", 45.0], ["fuel", 45.0]]}, {"$type": "Dictionary", "entries": [[2, 45.0]]}]:
		_check(Route.serialized_dictionary(invalid).is_empty(), "decoder safely refuses raw or malformed value:%s" % str(invalid))


func _matches_actual_job(record: Dictionary) -> bool:
	var costs: Dictionary = record.get("costs", {})
	return int(record.get("id", -1)) == JOB_ID and int(record.get("building_id", -1)) == BUILDING_ID and int(record.get("source_camp_id", -1)) == FRONT_ID and record.get("funded", false) == true and record.get("delivered", false) == true and record.get("done", false) == true and costs.size() == 3 and is_equal_approx(float(costs.get("materials", 0.0)), 140.0) and is_equal_approx(float(costs.get("fuel", 0.0)), 45.0) and is_equal_approx(float(costs.get("supplies", 0.0)), 30.0)


func _encoded_value(dictionary: Dictionary, key: String) -> Variant:
	for pair: Array in dictionary.get("entries", []):
		if pair.size() == 2 and pair[0] == key: return pair[1]
	return null


func _encoded_job(saved: Dictionary) -> Dictionary:
	for job: Dictionary in _encoded_value(saved.payload, "jobs"):
		if int(_encoded_value(job, "id")) == JOB_ID: return job
	return {}


func _set_encoded_value(dictionary: Dictionary, key: String, value: Variant) -> bool:
	for pair: Array in dictionary.get("entries", []):
		if pair.size() == 2 and pair[0] == key:
			pair[1] = value
			return true
	return false


func _remove_encoded_value(dictionary: Dictionary, key: String) -> bool:
	var entries: Array = dictionary.get("entries", [])
	for index: int in range(entries.size()):
		if entries[index].size() == 2 and entries[index][0] == key:
			entries.remove_at(index)
			return true
	return false


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)
