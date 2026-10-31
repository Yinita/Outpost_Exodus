extends SceneTree
## Controlled receiver ownership regression; runtime evidence is retained separately.
## Initial flat, supplied two-camp layout is a controlled valid-save fixture.
## The tested overlap uses public evacuation, paid camp building and normal ticks.
## It is not a native/full-campaign, performance or human playtest proof.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const SaveStore = preload("res://scripts/campaign_save_store.gd")
const Guide = preload("res://scripts/campaign_guide.gd")
const STEP: float = 0.05
const SOURCE_POSITION: Vector2 = Vector2(50, 22)
var guide_script: Script = Guide
var checks: int = 0
var failures: Array[String] = []
var disk_directory: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--baseline"):
		guide_script = load("res://work/receiver-guide-v01/guide-before.gd")
	if guide_script == null or not guide_script.can_instantiate():
		printerr("Receiver guidance implementation failed to compile")
		quit(2)
		return
	disk_directory = "res://work/receiver-guide-test-%d" % OS.get_process_id()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(disk_directory)):
		printerr("Refuse to overwrite prior receiver-guidance disk evidence")
		quit(2)
		return
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(disk_directory)) == OK, "isolated test disk directory can be created")
	var primary: Dictionary = _public_overlap(4)
	if not primary.is_empty():
		_test_actual_receiver(primary)
		_test_new_build_is_not_a_new_transfer(primary)
		_test_real_disk_continuation(primary)
		_test_unavailable_records(primary)
	var boundary: Dictionary = _public_overlap(5)
	if not boundary.is_empty():
		_test_actual_receiver(boundary)
		_test_new_build_is_not_a_new_transfer(boundary)
	var farther: Dictionary = _public_overlap(6)
	if not farther.is_empty(): _test_greater_than_five(farther)
	print("Withdrawal receiver guidance checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	return ok


func _encoded(sim: Variant) -> String:
	return JSON.stringify(sim.save_state(), "", false, true)


func _valid_saved(data: Dictionary) -> bool:
	return Simulation.new().load_state(data)


func _public_overlap(dx: int) -> Dictionary:
	var sim: Variant = Simulation.new()
	if not _check(sim.reset(42), "controlled Canyon initialization"): return {}
	# Fixture-only setup: flat terrain, no combat/exit, genuine camp markers,
	# supplied A and a crew at A. No fixture edits occur after evacuation starts.
	for row: Array in sim.terrain: row.fill(0)
	sim.ramps = {}
	sim.sites = []
	sim.chokes = []
	sim.effects = []
	sim.exit_building_id = 0
	sim.exit_site_id = 0
	sim.pursuit_start = 1000000.0
	sim.pursuit_x = -10000.0
	sim.units = sim.units.filter(func(unit: Dictionary) -> bool: return unit.team == "friendly")
	var home: Dictionary = sim.camps[0]
	home.name = "撤收原营"
	home.materials = 3000.0
	home.supplies = 2000.0
	home.fuel = 1000.0
	home.salvage = 0.0
	home.crude = 0.0
	home.recipe = "idle"
	var command: Dictionary = sim.buildings[0]
	sim.buildings = [command]
	var receiver: Dictionary = sim._make_camp(SOURCE_POSITION, "实际接收营A", 500.0, 200.0, 100.0)
	receiver.recipe = "idle"
	sim._add_building("camp", SOURCE_POSITION, int(receiver.id), 1.0)
	sim.roads = {}
	for x: int in range(9, 58): sim.roads[Vector2i(x, 22)] = {"progress": 1.0, "camp_id": int(home.id)}
	for unit: Dictionary in sim.units:
		if unit.kind == "engineer":
			unit.camp_id = int(receiver.id)
			unit.pos = SOURCE_POSITION + Vector2(0, -2)
			unit.target = unit.pos
			unit.guard_pos = unit.pos
			unit.path = []
			unit.path_index = 0
			unit.order = "idle"
			unit.manual = false
	var home_id: int = int(home.id)
	var receiver_id: int = int(receiver.id)
	if not _check(sim.load_state(sim.save_state().duplicate(true)), "initial controlled fixture passes public save validation"): return {}
	home = sim.get_camp(home_id)
	receiver = sim.get_camp(receiver_id)
	if not _check(sim.evacuate_camp(home_id), "public evacuation starts before new B exists"): return {}
	var truck: Dictionary = sim.get_unit(int(sim.main_truck_id))
	_check(home.state == "packing" and int(home.evac_target_id) == receiver_id and int(truck.evac_destination_id) == receiver_id, "public order records actual receiver A")
	var at: Vector2i = Vector2i(SOURCE_POSITION) + Vector2i(dx, 0)
	var plan: Dictionary = sim.query_build("camp", at)
	if not _check(bool(plan.ok) and int(plan.camp_id) == receiver_id, "active A can genuinely supply B while Home packs"): return {}
	var materials_before: float = float(receiver.materials)
	var supplies_before: float = float(receiver.supplies)
	if not _check(sim.build("camp", at), "new B is ordered with public paid build"): return {}
	_check(float(receiver.materials) == materials_before - float(Simulation.BUILD_COSTS.camp.materials) and float(receiver.supplies) == supplies_before - float(Simulation.BUILD_COSTS.camp.supplies), "A immediately pays the real camp cost; Home stock cannot substitute")
	_check(sim.camps.size() == 2, "unfinished B is not a receiving inventory")
	var newest: Dictionary = {}
	for tick: int in range(1200):
		sim.tick(STEP)
		for camp: Dictionary in sim.camps:
			if Vector2(camp.pos) == Vector2(at): newest = camp
		if not newest.is_empty() or sim.outcome != "playing": break
	if not _check(not newest.is_empty() and sim.outcome == "playing", "ordinary ticks physically deliver and complete paid B"): return {}
	_check(home.state == "packing" and int(home.evac_target_id) == receiver_id and int(truck.evac_destination_id) == receiver_id, "building B never retargets the still-packing real convoy")
	_check(float(newest.materials) == 0.0 and float(newest.fuel) == 0.0, "completed B has no invented receiving stock")
	_check(_valid_saved(sim.save_state()), "completed overlapping state is a valid public save")
	return {"sim": sim, "origin": home_id, "receiver": receiver_id, "newest": int(newest.id), "newest_name": String(newest.name), "dx": dx}


func _query(context: Dictionary, selected: int, label: String, supplied_guide: Variant = null) -> Dictionary:
	var sim: Variant = context.sim
	var guide: Variant = guide_script.new() if supplied_guide == null else supplied_guide
	var before: String = _encoded(sim)
	var rng: String = str(sim._rng.state)
	guide.update(sim, [], selected)
	_check(_encoded(sim) == before and str(sim._rng.state) == rng, label + ": complete encoded state/entry order and RNG remain unchanged")
	return guide.get_hint()


func _test_actual_receiver(context: Dictionary) -> void:
	var sim: Variant = context.sim
	var receiver: Dictionary = sim.get_camp(int(context.receiver))
	var expected: String = "接收营「实际接收营A」当前：建材%d、燃料%d。" % [int(receiver.materials), int(receiver.fuel)]
	for selected: int in [int(context.origin), int(context.receiver), int(context.newest)]:
		var hint: Dictionary = _query(context, selected, "real receiver dx%d selected%d" % [context.dx, selected])
		_check(String(hint.text).contains(expected) and not String(hint.text).contains("接收营「%s」" % String(context.newest_name)), "packing hint reads actual A inventory instead of geometric front B")
		_check(String(hint.title) == "后营撤收：等待运输或紧急弃营", "funding decision uses funded A rather than empty B")
		_check(Vector2(hint.target) == Vector2(sim.get_camp(int(context.origin)).pos), "actual source action stays focused on Home without changing selected camp")


func _test_new_build_is_not_a_new_transfer(context: Dictionary) -> void:
	# Camp construction requires1.7 spacing; a new evacuation receiver needs
	# x>=source.x+5, a path and the actual free command truck. These are distinct.
	var sim: Variant = context.sim
	_check(not sim.evacuate_camp(int(context.receiver)), "building nearby B cannot start a second transfer while Home owns the truck")
	var message: String = String(sim.messages.back())
	if int(context.dx) < 5:
		_check(message.contains("先在东侧建立接收物资"), "dx4 permits building B but does not make it a legal A evacuation receiver")
	else:
		_check(message.contains("指挥运输车尚未空闲"), "dx5 meets the receiver x threshold but the real truck is still busy")
	_check(int(sim.get_camp(int(context.origin)).evac_target_id) == int(context.receiver) and int(sim.get_unit(int(sim.main_truck_id)).evac_destination_id) == int(context.receiver), "failed second public request never retargets the existing Home convoy")


func _test_real_disk_continuation(context: Dictionary) -> void:
	var sim: Variant = context.sim
	var guide: Variant = guide_script.new()
	_query(context, int(context.newest), "before disk write", guide)
	var state: Dictionary = sim.save_state()
	state["ui"] = {"guide": guide.save_state()}
	var path: String = disk_directory + "/campaign-save.json"
	var store: RefCounted = SaveStore.new()
	if not _check(store.write(path, state, Callable(self, "_valid_saved")) == OK, "real transactional disk write validates full save"): return
	var read: Dictionary = store.read(path)
	if not _check(bool(read.get("ok", false)), "real disk read decodes the written snapshot"): return
	var resumed: Variant = Simulation.new()
	if not _check(resumed.load_state(read.data), "disk-loaded overlap passes public simulation validation"): return
	var loaded_guide: Variant = guide_script.new()
	_check(loaded_guide.load_state(read.data.ui.guide), "actual saved Guide state loads")
	var continued: Dictionary = context.duplicate()
	continued.sim = resumed
	var truck: Dictionary = resumed.get_unit(int(resumed.main_truck_id))
	_check(resumed.get_camp(int(context.origin)).state == "packing" and int(truck.evac_destination_id) == int(context.receiver) and int(resumed.get_camp(int(context.origin)).evac_target_id) == int(context.receiver), "disk continuation retains the original public A destination")
	var digest: String = FileAccess.get_sha256(path)
	var hint: Dictionary = _query(continued, int(context.newest), "disk continuation", loaded_guide)
	_check(String(hint.text).contains("接收营「实际接收营A」") and not String(hint.text).contains("接收营「%s」" % String(context.newest_name)), "loaded guidance still names A")
	_check(FileAccess.get_sha256(path) == digest, "observation cannot rewrite the saved file")


func _test_unavailable_records(context: Dictionary) -> void:
	# Focused valid-save fault records, not claims that ordinary orders create
	# these inconsistencies. No tick or transport-rule change is used to fix them.
	var checkpoint: Dictionary = context.sim.save_state()
	for fault: String in ["missing_vehicle", "wrong_order", "wrong_origin", "wrong_receiver_binding", "wrong_kind", "missing_receiver", "inactive_receiver"]:
		var sim: Variant = Simulation.new()
		if not _check(sim.load_state(checkpoint.duplicate(true)), fault + ": controlled overlap loads"): continue
		var home: Dictionary = sim.get_camp(int(context.origin))
		var truck: Dictionary = sim.get_unit(int(sim.main_truck_id))
		match fault:
			"missing_vehicle": home.evac_truck_id = 0
			"wrong_order": truck.order = "idle"
			"wrong_origin": truck.evac_origin_id = int(context.receiver)
			"wrong_receiver_binding": truck.evac_destination_id = int(context.newest)
			"wrong_kind":
				for unit: Dictionary in sim.units:
					if unit.kind == "rifle":
						home.evac_truck_id = int(unit.id)
						break
			"missing_receiver":
				home.evac_target_id = 999999
				truck.evac_destination_id = 999999
			"inactive_receiver": sim.get_camp(int(context.receiver)).state = "abandoned"
		_check(_valid_saved(sim.save_state()), fault + ": unavailable observation remains a schema-valid fixture")
		var focused: Dictionary = context.duplicate()
		focused.sim = sim
		var hint: Dictionary = _query(focused, int(context.newest), fault)
		_check(String(hint.title) in ["检查撤收运输车", "检查撤收记录", "检查撤收接收营"], fault + ": unconfirmed transport is explicit")
		_check(not String(hint.text).contains("接收营「%s」" % String(context.newest_name)) and Vector2(hint.target) == Vector2(home.pos), fault + ": unavailable records never fabricate B as receiver")


func _test_greater_than_five(context: Dictionary) -> void:
	var sim: Variant = context.sim
	var hint: Dictionary = _query(context, int(context.newest), "dx greater than five negative branch")
	_check(String(hint.title) == "先撤收旧营，给新营运入资金" and String(hint.text).contains("先选中「实际接收营A」"), "dx>5 keeps the original active-rear A branch instead of pretending its source is Home")
	_check(Vector2(hint.target) == Vector2(sim.get_camp(int(context.receiver)).pos), "unchanged active-rear hint focuses A")
	# Busy-truck guidance for this different active-rear branch is existing
	# behavior and outside this packing-receiver patch's scope.
	_check(not sim.evacuate_camp(int(context.receiver)) and String(sim.messages.back()).contains("指挥运输车尚未空闲"), "dx>5 remains subject to the actual busy truck; Guide cannot secretly change that rule")
	_check(int(sim.get_unit(int(sim.main_truck_id)).evac_destination_id) == int(context.receiver), "negative branch cannot retarget the active Home convoy")
