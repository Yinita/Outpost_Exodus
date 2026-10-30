extends SceneTree
## Public player commands only. No inventory, health, terrain or clock edits.
const Simulation = preload("res://scripts/campaign_simulation.gd")
var sim: RefCounted
var failures: Array[String] = []
var sealed_west: bool = false
var emergency_used: bool = false
var abandoned_stock: Dictionary = {}
var delivered_trips: Dictionary = {}
var last_stage: String = ""

func _initialize() -> void:
	sim = Simulation.new()
	sim.reset(42)
	var home_id: int = sim.camps[0].id
	sim.set_production(home_id, "materials")
	clear_to(Vector2(25,20),40.0)
	construct("road",Vector2i(26,21),40.0)
	construct("camp",Vector2i(26,23),45.0)
	if sim.camps.size()<2:
		finish("NO MIDDLE CAMP")
		return
	var middle_id: int = sim.camps[1].id
	if not sim.evacuate_camp(home_id): failures.append("Home evacuation rejected")
	wait_for(func() -> bool:
		if sim.get_camp(home_id).state!="abandoned": return false
		if sim.get_unit(sim.main_truck_id).get("order","")=="evacuate_transport": return false
		for unit: Dictionary in sim.units:
			if unit.team=="friendly" and Vector2(unit.pos).x<21.8: return false
		return true, 200.0, "home convoy and everyone cross west gate")
	sealed_west=sim.seal_choke(0)
	if not sealed_west: failures.append("West gate rejected after actual crossing")
	construct("road",Vector2i(29,24),30.0)
	construct("generator",Vector2i(28,22),30.0)
	construct("workshop",Vector2i(30,24),35.0)
	# Paid local defense covers the longer, physical middle-camp withdrawal.
	construct("tower",Vector2i(25,20),30.0)
	sim.set_production(middle_id,"materials")
	clear_to(Vector2(35,10),50.0)
	construct("road",Vector2i(35,10),70.0)
	clear_to(Vector2(35,31),50.0)
	construct("road",Vector2i(35,31),70.0)
	advance(100.0)
	print("MIDDLE STOCK ",sim.get_camp(middle_id)," time=",sim.time)
	clear_to(Vector2(53,21),60.0)
	construct("road",Vector2i(53,22),90.0)
	construct("camp",Vector2i(54,23),90.0)
	if sim.camps.size()<3 or not failures.is_empty():
		finish("NO FORWARD CAMP")
		return
	var front_id: int = sim.camps[2].id
	sim.command_task(army_ids(),"guard",Vector2(27,19))
	if not sim.evacuate_camp(middle_id): failures.append("Middle evacuation rejected")
	wait_for(func() -> bool:
		var front: Dictionary=sim.get_camp(front_id)
		return float(front.materials)>=320.0 and float(front.supplies)>=35.0 and float(front.fuel)>=45.0 and float(front.get("crude",0.0))>=50.0 and int(delivered_trips.get(middle_id,0))>=3,
		360.0,"three or more delivered loads and viable forward stocks")
	if not failures.is_empty():
		finish("MIDDLE TRANSPORT FAILED")
		return
	print("RECEIVED BEFORE ABANDON ",sim.get_camp(front_id)," trips=",delivered_trips.get(middle_id,0)," time=",sim.time)
	if sim.get_camp(middle_id).state=="packing":
		for key: String in ["materials","supplies","fuel","salvage","crude"]:
			abandoned_stock[key]=float(sim.get_camp(middle_id).get(key,0.0))
		emergency_used=sim.evacuate_camp(middle_id)
		if not emergency_used: failures.append("Emergency abandonment rejected")
	else:
		failures.append("No remaining rear stock to deliberately abandon")
	wait_for(func() -> bool:
		var truck: Dictionary=sim.get_unit(sim.main_truck_id)
		return not truck.is_empty() and str(truck.get("order",""))!="evacuate_transport" and Vector2(truck.pos).distance_to(Vector2(sim.get_camp(front_id).pos))<3.0,
		70.0,"last loaded truck arrives at forward camp")
	advance(35.0)
	print("ABANDONED INVENTORY ",abandoned_stock," time=",sim.time)
	print("FRONT ",sim.get_camp(front_id))
	construct("road",Vector2i(57,23),25.0)
	construct("generator",Vector2i(56,21),30.0)
	construct("workshop",Vector2i(57,25),40.0)
	sim.set_production(front_id,"fuel")
	wait_for(func() -> bool: return float(sim.get_camp(front_id).fuel)>=85.0,140.0,"refine transported crude to fuel margin")
	sim.set_production(front_id,"supplies")
	wait_for(func() -> bool: return float(sim.get_camp(front_id).supplies)>=80.0,150.0,"produce rations before exit construction")
	sim.set_production(front_id,"idle")
	# Stop outside capture radius, fund and finish local exit power first.
	clear_to(Vector2(68,20),65.0)
	construct("road",Vector2i(68,22),90.0)
	construct("generator",Vector2i(68,22),45.0)
	print("EXIT PREPARATION STOCK ",sim.get_camp(front_id)," time=",sim.time)
	clear_to(Vector2(72,19),35.0)
	construct("road",Vector2i(72,19),60.0)
	wait_for(func() -> bool: return float(sim.exit_progress)>=1.0,180.0,"actual funded powered exit finishes")
	var everyone: Array=[]
	for unit: Dictionary in sim.units:
		if unit.team=="friendly": everyone.append(unit.id)
	sim.command_move(everyone,Vector2(72,19),true)
	wait_for(func() -> bool: return sim.outcome=="victory",90.0,"command truck and survivors arrive")
	finish("COMPLETE")

func advance(seconds: float) -> void:
	for _index in range(ceili(seconds/0.1)):
		if sim.outcome!="playing" or not failures.is_empty(): break
		sim.tick(0.1)
		var truck: Dictionary=sim.get_unit(sim.main_truck_id)
		if truck.is_empty(): continue
		var stage: String=str(truck.get("haul_stage",""))
		if last_stage=="outbound" and stage!="outbound" and Dictionary(truck.get("cargo",{})).is_empty():
			var origin_id: int=int(truck.get("evac_origin_id",0))
			delivered_trips[origin_id]=int(delivered_trips.get(origin_id,0))+1
		last_stage=stage

func wait_for(condition: Callable, timeout: float, description: String) -> void:
	var deadline: float=float(sim.time)+timeout
	while not condition.call() and float(sim.time)<deadline and sim.outcome=="playing" and failures.is_empty():
		advance(0.1)
	if not condition.call():
		failures.append("Timed out: "+description)
		var diagnostic_path: String=ProjectSettings.globalize_path("res://work/mission-playthrough-failure.json")
		DirAccess.make_dir_recursive_absolute(diagnostic_path.get_base_dir())
		var diagnostic: FileAccess=FileAccess.open(diagnostic_path,FileAccess.WRITE)
		if diagnostic!=null:
			diagnostic.store_string(JSON.stringify(sim.save_state()))
			diagnostic.close()
		print("DIAGNOSTIC_SAVE written=",diagnostic!=null," path=",diagnostic_path)
		var truck: Dictionary=sim.get_unit(sim.main_truck_id)
		if not truck.is_empty():
			print("TRUCK_DIAGNOSTIC pos=",truck.pos," target=",truck.target," path_index=",truck.get("path_index",0)," pathlen=",Array(truck.get("path",[])).size()," nav_wait=",truck.get("nav_wait",0.0)," haul_stage=",truck.get("haul_stage","")," HP=",truck.hp," cargo=",truck.get("cargo",{}))
			for camp: Dictionary in sim.camps:
				print("TRUCK_CAMP_DISTANCE id=",camp.id," state=",camp.state," pos=",camp.pos," distance=",Vector2(truck.pos).distance_to(Vector2(camp.pos)))
	print("WAIT ",description," reached=",condition.call()," time=",sim.time)

func army_ids() -> Array:
	var result: Array=[]
	for unit: Dictionary in sim.units:
		if unit.team=="friendly" and unit.kind=="rifle": result.append(unit.id)
	return result

func clear_to(position: Vector2, seconds: float) -> void:
	if not failures.is_empty(): return
	sim.command_move(army_ids(),position,true)
	advance(seconds)
	print("CLEAR ",position," time=",sim.time," people=",sim.get_summary().people," outcome=",sim.outcome)

func construct(kind: String, tile: Vector2i, seconds: float) -> void:
	if not failures.is_empty(): return
	var accepted: bool=sim.build(kind,tile)
	print("BUILD ",kind," ",tile," accepted=",accepted," time=",sim.time," materials=",sim.get_summary().materials)
	if not accepted: failures.append("Rejected construction: %s %s (%s)" % [kind,tile,sim.messages.back()])
	advance(seconds)

func finish(label: String) -> void:
	if sim.camps.size()<3: failures.append("Fewer than three actual camps")
	for kind: String in ["quarry","fuel"]:
		var found: bool=false
		for site: Dictionary in sim.sites:
			if site.kind==kind and bool(site.captured): found=true
		if not found: failures.append("Uncaptured branch: "+kind)
	if not sealed_west: failures.append("No real sealed rear choke")
	if not emergency_used: failures.append("No explicit urgent abandonment")
	var abandoned_total: float=0.0
	for amount: Variant in abandoned_stock.values(): abandoned_total+=float(amount)
	if abandoned_total<=0.0: failures.append("No actual inventory deliberately left behind")
	if sim.outcome!="victory" or float(sim.exit_progress)<1.0 or int(sim.evacuated)<4:
		failures.append("Actual exit and survivor victory conditions not reached")
	print(label," SUMMARY ",sim.get_summary())
	print("CAMPS ",sim.camps)
	print("DELIVERED TRIPS ",delivered_trips)
	print("ABANDONED INVENTORY ",abandoned_stock)
	print("PENDING BUILDINGS ",sim.buildings.filter(func(b:Dictionary)->bool:return float(b.progress)<1.0))
	print("MESSAGES ",sim.messages)
	for failure: String in failures: printerr("PLAYTHROUGH FAILURE: ",failure)
	quit(0 if failures.is_empty() else 1)
