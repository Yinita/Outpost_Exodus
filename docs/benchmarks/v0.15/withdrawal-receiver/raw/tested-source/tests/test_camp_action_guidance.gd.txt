extends SceneTree
## Focused ownership/UI guidance regressions. Camp placement is a controlled
## fixture; evacuation, emergency abandonment and exit commissioning use their
## unchanged actual commands. These checks are not a full-mission playtest.

const Simulation = preload("res://scripts/campaign_simulation.gd")
const Main = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/campaign_catalog.gd")
var guide_script: Script = preload("res://scripts/campaign_guide.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--baseline"):
		guide_script = load("res://work/guide-before.gd")
	if guide_script == null or not guide_script.can_instantiate():
		printerr("Guide ownership implementation failed to compile")
		quit(2)
		return
	_test_withdrawal_selection()
	_test_exit_supplier_and_bound_owner()
	print("Camp action guidance checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - ", failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)


func _snapshot(sim: Variant) -> String:
	return JSON.stringify(sim.save_state())


func _test_withdrawal_selection() -> void:
	var sim: Variant = Simulation.new()
	_check(sim.reset(42), "withdrawal fixture initializes actual canyon rules")
	var origin: Dictionary = sim.camps[0]
	origin["name"] = "西部医疗营"
	# A funded receiving camp makes optional immediate withdrawal actionable.
	var receiver: Dictionary = sim._make_camp(Vector2(54, 20), "河谷接收营", 250.0, 100.0, 100.0)
	var app: Node2D = Main.new()
	app.sim = sim
	app.menu = ""
	app.selected_camp = int(receiver["id"])
	var guide: RefCounted = guide_script.new()
	guide.update(sim, [], app.selected_camp)
	var hint: Dictionary = guide.get_hint()
	_check(String(hint.text).contains("先选中「西部医疗营」"), "active withdrawal names the actual source when the receiver is selected")
	_check(String(hint.text).contains("“撤收驻点”"), "active source guidance uses the actual initial button name")
	_check(Vector2(hint.target) == Vector2(origin.pos), "initial withdrawal focus points to its actual source")
	_check(sim.evacuate_camp(int(origin.id)), "actual public evacuation command starts source packing")
	_check(origin.state == "packing" and int(origin.evac_target_id) == int(receiver.id), "actual order binds this origin and receiver")
	var truck: Dictionary = sim.get_unit(int(sim.main_truck_id))
	# Distinguish action focus from the old in-transit truck focus, without ticks.
	truck["pos"] = Vector2(35, 20)
	var before: String = _snapshot(sim)
	guide.update(sim, [], app.selected_camp)
	hint = guide.get_hint()
	_check(hint.title == "后营撤收：等待运输或紧急弃营", "funded receiving camp reveals optional immediate withdrawal")
	_check(String(hint.text).contains("先选中「西部医疗营」"), "wrong-camp packing guidance explicitly selects its actual source first")
	_check(String(hint.text).contains("接收营「河谷接收营」"), "local funding readout names the actual receiving camp")
	_check(String(hint.text).contains("“紧急弃营”") and not String(hint.text).contains("“撤收驻点”"), "packing guidance uses the current emergency button label")
	_check(Vector2(hint.target) == Vector2(origin.pos), "emergency action focus returns to source instead of in-transit truck")
	_check(app.selected_camp == int(receiver.id) and _snapshot(sim) == before, "guidance never automatically changes selection, orders, economy or RNG")
	# Verify there is no hidden retarget: clicking while the wrong camp remains
	# selected still goes to that camp under the original command rules.
	app.ui_action("evacuate")
	_check(receiver.state == "active" and origin.state == "packing", "wrong-camp button cannot silently abandon the source")
	app.selected_camp = int(origin.id)
	before = _snapshot(sim)
	guide.update(sim, [], app.selected_camp)
	_check(String(guide.get_hint().text).contains("当前已选中「西部医疗营」"), "source-selected packing guidance acknowledges actual selection")
	_check(_snapshot(sim) == before and app.selected_camp == int(origin.id), "source-selected guidance remains read-only")
	var unshipped: float = sim._camp_stock(origin)
	var receiver_before: float = sim._camp_stock(receiver)
	app.ui_action("evacuate")
	_check(origin.state == "abandoned" and receiver.state == "active", "explicit source button executes actual emergency abandonment")
	_check(sim._camp_stock(origin) == unshipped and sim._camp_stock(receiver) == receiver_before, "emergency guidance adds no resource grants or hidden delivery")
	_check(truck.order == "evacuate_transport" and int(truck.evac_origin_id) == int(origin.id) and int(truck.evac_destination_id) == int(receiver.id), "actual transport retains source/receiver identities after abandonment")
	app.free()


func _road(sim: Variant, camp: Dictionary, target: Vector2) -> void:
	for tile: Vector2i in Catalog.path(sim.mission_data, Vector2i(camp.pos), Vector2i(target)):
		sim.roads[tile] = {"progress": 1.0, "camp_id": int(camp.id)}


func _test_exit_supplier_and_bound_owner() -> void:
	var sim: Variant = Simulation.new()
	_check(sim.reset(42), "exit ownership fixture initializes actual canyon rules")
	var exit_building: Dictionary = sim._get_building(int(sim.exit_building_id))
	var exit_site: Dictionary = sim._get_site(int(sim.exit_site_id))
	var target: Vector2 = exit_site.pos
	# The more easterly camp is farther away north/south. Only the real nearest
	# supplier has the road and local funds required for commissioning.
	var source: Dictionary = sim._make_camp(target + Vector2(-4, 0), "出口工程营", 250.0, 100.0, 100.0)
	var east: Dictionary = sim._make_camp(target + Vector2(0, 15), "东南观察营", 250.0, 100.0, 100.0)
	sim.camps[0]["state"] = "abandoned"
	# Both forward camps are within the same five-column stage. The guide can
	# reach the exit through its normal update without demanding a rear transfer.
	for kind: String in ["generator", "workshop"]:
		var utility: Dictionary = sim._add_building(kind, Vector2(east.pos) + (Vector2(2, -1) if kind == "generator" else Vector2(4, 1)), int(east.id), 1.0)
		utility["powered"] = true
		_road(sim, east, utility.pos)
	exit_site["captured"] = true
	_road(sim, source, target)
	_check(int(sim._nearest_camp(target).id) == int(source.id) and Vector2(east.pos).x > Vector2(source.pos).x, "actual supplier differs from the camp with greatest x")
	_check(sim.road_connected(source.pos, target) and not sim.road_connected(east.pos, target), "only the actual supply camp has an exit road")
	var guide: RefCounted = guide_script.new()
	var before: String = _snapshot(sim)
	guide.update(sim)
	var hint: Dictionary = guide.get_hint()
	_check(hint.title == "备齐撤离站施工物资", "planned exit inspects real supplier connection instead of unrelated eastern camp")
	_check(Vector2(hint.target) == Vector2(source.pos) and String(hint.text).contains("「出口工程营」"), "funding guidance names and focuses the actual nearest supply camp")
	_check(_snapshot(sim) == before, "planned-exit observation preserves complete simulation and RNG")
	var source_materials: float = float(source.materials)
	var east_materials: float = float(east.materials)
	sim._update_exit(0.0)
	_check(bool(exit_building.construction_started) and int(exit_building.camp_id) == int(source.id), "unchanged real exit commissioning records actual source ownership")
	_check(float(source.materials) == source_materials - float(sim.BUILD_COSTS.exit.materials) and float(east.materials) == east_materials, "actual commissioning charges only the source camp")
	# A new closer camp must not replace the owner of an already paid job.
	var closer: Dictionary = sim._make_camp(target + Vector2(0, 3), "后建补给营", 250.0, 100.0, 100.0)
	_check(int(sim._nearest_camp(target).id) == int(closer.id), "later camp changes uncommitted nearest-camp selection")
	before = _snapshot(sim)
	guide.update(sim, [], int(east.id))
	hint = guide.get_hint()
	_check(hint.title == "为出口施工提供本地电力", "bound exit bypasses unrelated later-camp road blockers")
	_check(String(hint.text).contains("「出口工程营」") and not String(hint.text).contains("「后建补给营」"), "bound exit power guidance names recorded job owner")
	_check(_snapshot(sim) == before and int(exit_building.camp_id) == int(source.id), "bound-exit guide cannot reassign paid job or mutate economy/RNG")
	# Loss of the recorded owner is not silently presented as a fresh project.
	source["state"] = "abandoned"
	before = _snapshot(sim)
	guide.update(sim)
	hint = guide.get_hint()
	_check(hint.title == "检查撤离站所属营地" and String(hint.text).contains("出口工程营") and String(hint.text).contains("不会自动接管"), "lost-owner guidance explains existing project instead of promising another camp can fund it")
	_check(_snapshot(sim) == before, "lost-owner explanation never transfers or restarts the job")
