extends SceneTree
const Simulation = preload("res://scripts/campaign_simulation.gd")
var sim: RefCounted

func _initialize() -> void:
	sim = Simulation.new()
	sim.reset(42)
	var home_id: int = sim.camps[0].id
	sim.set_production(home_id,"materials")
	clear_to(Vector2(25,20),40.0)
	construct("road",Vector2i(26,21),40.0)
	construct("camp",Vector2i(26,23),45.0)
	if sim.camps.size()<2:
		finish("NO MIDDLE CAMP")
		return
	print("EVAC HOME ",sim.evacuate_camp(home_id))
	advance(150.0)
	print("SEAL WEST ",sim.seal_choke(0))
	var middle_id: int = sim.camps[1].id
	construct("road",Vector2i(29,24),30.0)
	construct("generator",Vector2i(28,22),30.0)
	construct("workshop",Vector2i(30,24),35.0)
	sim.set_production(middle_id,"materials")
	clear_to(Vector2(35,10),50.0)
	construct("road",Vector2i(35,10),70.0)
	clear_to(Vector2(35,31),50.0)
	construct("road",Vector2i(35,31),70.0)
	advance(100.0)
	print("MIDDLE STOCK ",sim.camps[1],"time=",sim.time)
	clear_to(Vector2(53,21),60.0)
	construct("road",Vector2i(53,22),90.0)
	construct("camp",Vector2i(54,23),90.0)
	if sim.camps.size()<3:
		finish("NO FORWARD CAMP")
		return
	print("EVAC MIDDLE ",sim.evacuate_camp(middle_id))
	advance(130.0)
	if sim.get_camp(middle_id).state == "packing":
		print("EMERGENCY ABANDON ",sim.evacuate_camp(middle_id))
		advance(35.0)
	var front_id: int = sim.camps[2].id
	print("FRONT ",sim.camps[2])
	construct("road",Vector2i(57,23),25.0)
	construct("generator",Vector2i(56,21),30.0)
	construct("workshop",Vector2i(57,25),40.0)
	sim.set_production(front_id,"materials")
	clear_to(Vector2(72,19),65.0)
	construct("road",Vector2i(72,19),100.0)
	construct("generator",Vector2i(70,21),45.0)
	advance(120.0)
	var everyone: Array = []
	for unit in sim.units:
		if unit.team=="friendly": everyone.append(unit.id)
	sim.command_move(everyone,Vector2(72,19),true)
	advance(80.0)
	finish("COMPLETE")

func advance(seconds: float) -> void:
	for index in range(ceili(seconds/0.1)):
		sim.tick(0.1)
		if sim.outcome!="playing": break

func clear_to(position: Vector2, seconds: float) -> void:
	var army: Array = []
	for unit in sim.units:
		if unit.team=="friendly" and unit.kind=="rifle": army.append(unit.id)
	sim.command_move(army,position,true)
	advance(seconds)
	print("CLEAR ",position," t=",sim.time," people=",sim.get_summary().people," outcome=",sim.outcome)

func construct(kind: String, tile: Vector2i, seconds: float) -> void:
	var result: bool = sim.build(kind,tile)
	print("BUILD ",kind," ",tile," accepted=",result," at=",sim.time," mat=",sim.get_summary().materials)
	if not result: print(" REASON ",sim.messages.back())
	advance(seconds)

func finish(label: String) -> void:
	print(label," SUMMARY ",sim.get_summary())
	print("CAMPS ",sim.camps)
	print("JOBS ",sim._jobs.filter(func(j):return not j.done))
	print("MESSAGES ",sim.messages)
	quit(0 if sim.outcome=="victory" else 1)
