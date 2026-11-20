extends SceneTree

const Sites := preload("res://game/world/expedition_sites.gd")
const Missions := preload("res://game/sim/expeditions.gd")
const Salvage := preload("res://game/world/structural_salvage.gd")
var session: WastelandSession
var errors := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ",description)
	if not ok: errors += 1

func visit(point: Vector3) -> WastelandChunk:
	session.stream.ensure_landing(point)
	return session.stream.active[WastelandTerrainGen.chunk_at(Vector2(point.x,point.z))]

func audit(chunk: WastelandChunk, prefix: String) -> void:
	var members := 0
	var defects := []
	for id: String in chunk.structures:
		if not id.begins_with(prefix): continue
		members += 1
		if not chunk.footings.has(id) and not chunk.support_graph.has(id):
			defects.append(id)
	for id: String in chunk.support_graph:
		if id.begins_with(prefix) and not chunk.structures.has(id):
			defects.append(id)
	check(members>0 and defects.is_empty(),"%s generated %d supported pieces %s"%[prefix,members,defects])

func demolish(chunk: WastelandChunk, id: String, lost: Array, standing: Array) -> void:
	var before := []
	for other: String in lost:
		if chunk.structures.has(other): before.append(chunk.structures[other][0])
	if not chunk.structures.has(id):
		check(false,"missing target "+id)
		return
	session.hit_wall(chunk.structures[id][0],10000)
	var intact := chunk.structures.has_all(standing)
	var removed := not chunk.structures.has(id) and before.size()==lost.size()
	var damage: Dictionary = session.stream.chunk_diff(chunk.cell).get("site_damage",{})
	for other: String in lost:
		removed = removed and not chunk.structures.has(other) and damage.get(other,1.0)==0.0
	for piece: StaticBody3D in before:
		removed = removed and piece.collision_layer==0 and not piece.visible
	check(removed and intact,id+" falls with its dependents, frees collisions and leaves adjacent supports intact")

func stock() -> Dictionary:
	var totals := {}
	for record: Dictionary in session.fx.drop_records.values():
		for item: String in record.items: totals[item]=int(totals.get(item,0))+int(record.items[item])
	return totals

func verify_girder_salvage(chunk: WastelandChunk) -> void:
	var id := "column/0/-1/2"
	if not chunk.structures.has(id):
		check(false,"hospital has the target ground-floor column")
		return
	var body: StaticBody3D = chunk.structures[id][0]
	var origins := {}
	var yields := {}
	for key: String in chunk.structures:
		origins[key]=Salvage.origin(chunk,key)
		yields[key]=Salvage.materials(chunk,key)
	var previous:=session.fx.drop_records.keys()
	session.hit_wall(body,1)
	check(previous==session.fx.drop_records.keys(),"striking a standing column produces no salvage")
	session.hit_wall(body,10000)
	var expected := {}
	var ruins: Array[Vector2]=[]
	for key: String in origins:
		if chunk.structures.has(key): continue
		var at:Vector3=origins[key]
		ruins.append(Vector2(at.x,at.z))
		for item:String in yields[key]: expected[item]=int(expected.get(item,0))+int(yields[key][item])
	var actual := {}
	var above := false
	var across := false
	var nearby := true
	for drop_id:String in session.fx.drop_records:
		if previous.has(drop_id): continue
		var record:Dictionary=session.fx.drop_records[drop_id]
		var at:Vector3=record.point
		above=above or at.y>body.global_position.y+1.0
		across=across or Vector2(at.x,at.z).distance_to(Vector2(body.global_position.x,body.global_position.z))>2.0
		nearby=nearby and ruins.any(func(p:Vector2): return p.distance_to(Vector2(at.x,at.z))<2.25)
		for item:String in record.items: actual[item]=int(actual.get(item,0))+int(record.items[item])
	check(not chunk.structures.has("girder/0/2") and actual==expected and actual.has("scrap") and actual.has("stone"),"the broken steel column, falling girder and masonry release exactly their materials")
	check(above and across and nearby,"material is released across the damaged upper structure")
	var once:=stock()
	session.hit_wall(body,10000)
	session.stream.record_settlement(chunk)
	check(stock()==once,"repeat hits and support checks cannot award the same debris twice")

func run() -> void:
	WastelandSave.root_override="user://verification/infrastructure-%d"%OS.get_process_id()
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	var cfg: Dictionary = app._default_config()
	cfg.seed=2817
	cfg.spawn_roll=74
	app._enter_world(cfg,{},1,false)
	session=app.session
	session.simulation_paused=true
	var before_generation:=stock()
	var points: Dictionary = Sites.survey(session.stream.generator).points
	var wrecks := WastelandSunkenSites.landmarks(session.stream.generator)
	for id: String in ["ferry","pump","bridge"]:
		audit(visit(wrecks[id]),"wreck/"+id+"/")
	for id: String in points:
		audit(visit(points[id]),"expedition/"+id+"/")
	var hospital:=visit(Vector3(112,0,-112))
	check(stock()==before_generation,"generating the naturally ruined hospital and facilities releases no salvage")
	var weather := visit(points.weather)
	var rotor_id := "expedition/weather/rotor0"
	var rotor: StaticBody3D = weather.structures[rotor_id][0]
	var rotor_at := rotor.global_position
	demolish(weather,"expedition/weather/mast",[rotor_id,"expedition/weather/rotor1","expedition/weather/rotor2"],["expedition/weather/plate"])
	var moving: RigidBody3D
	for piece: RigidBody3D in get_nodes_in_group("falling_structure"):
		if piece.global_position.is_equal_approx(rotor_at): moving=piece
	for tick in 10: await physics_frame
	check(is_instance_valid(moving) and moving.global_position.y<rotor_at.y-0.04,"detached weather rotor falls under Godot gravity")
	verify_girder_salvage(hospital)
	var dock := visit(Vector3(5,0,12))
	audit(dock,"dock/")
	var shore_end: String = dock.support_graph["dock/stringer/0/-1"][0][0]
	demolish(dock,shore_end,["dock/stringer/0/-1","dock/plank/0","dock/plank/9"],["dock/stringer/0/1","dock/plank/10","dock/platform"])
	var ferry := visit(wrecks.ferry)
	var yard: String = ferry.support_graph["wreck/ferry/rigging"][0][0]
	var spar: String = ferry.support_graph[yard][0][0]
	demolish(ferry,spar,[yard,"wreck/ferry/rigging"],["wreck/ferry/hull/6/1","wreck/ferry/marker"])
	var pump := visit(wrecks.pump)
	demolish(pump,"wreck/pump/member/2",["wreck/pump/member/1"],["wreck/pump/roof/east","wreck/pump/intake/1"])
	var bridge := visit(wrecks.bridge)
	demolish(bridge,"wreck/bridge/member/0",["wreck/bridge/member/6","wreck/bridge/arch/12","wreck/bridge/arch/6"],["wreck/bridge/member/7","wreck/bridge/arch/0"])
	var shelter := visit(points.shelter)
	demolish(shelter,"expedition/shelter/post-1-1",["expedition/shelter/sill-1","expedition/shelter/roof-1","expedition/shelter/windbreak"],["expedition/shelter/roof1","expedition/shelter/ridge"])
	demolish(weather,"expedition/weather/post",["expedition/weather/plate"],[])
	check(Missions.ground_id(session,points.weather)=="weather","survey remains accessible at the base of a fallen plaque")
	var well := visit(points.well)
	demolish(well,"expedition/well/pipe",["expedition/well/lever"],["expedition/well/rim0"])
	var canal := visit(points.canal)
	var bank := "expedition/canal/bank-1"
	var gate := "expedition/canal/gate"
	for contact: Vector2 in canal.footings[bank]:
		session.stream.excavate(Vector3(contact.x,0,contact.y),2.6)
	for tick in 180:
		if not canal.structures.has(bank): break
		await physics_frame
	check(not canal.structures.has(bank) and not canal.structures.has(gate) and canal.structures.has("expedition/canal/bank1"),"digging under one bank drops that bank and its gate")
	var before_save:=stock()
	check(session.save_now(false)==OK,"write the damaged world")
	var save:=WastelandSave.read(1)
	app._enter_world(save.settings,save,1,false)
	session=app.session
	session.simulation_paused=true
	bridge=visit(wrecks.bridge)
	check(not bridge.structures.has("wreck/bridge/arch/6") and bridge.structures.has("wreck/bridge/arch/0"),"disk reload retains the missing bridge span and surviving pier")
	canal=visit(points.canal)
	check(not canal.structures.has(gate) and not canal.structures.has(bank),"the excavated gate remains down after disk reload")
	hospital=visit(Vector3(112,0,-112))
	check(not hospital.structures.has("girder/0/2") and stock()==before_save,"disk reload restores the destroyed girder and exact material quantities without replaying awards")
	var old_damage:={"site_damage":{"wreck/pump/member/2":0.0}}
	var pump_cell:=WastelandTerrainGen.chunk_at(Vector2(wrecks.pump.x,wrecks.pump.z))
	var damage_snapshot:={"diffs":{WastelandTerrainGen.grid_key(pump_cell):old_damage}}
	app._enter_world(cfg,damage_snapshot,1,false)
	session=app.session
	session.simulation_paused=true
	pump=visit(wrecks.pump)
	check(not pump.structures.has("wreck/pump/member/1") and pump.structures.has("wreck/pump/roof/east") and stock().is_empty(),"generation settles a damaged column without a roof damage record or retrospective loot")
	cfg.site_revision=0
	app._enter_world(cfg,damage_snapshot,1,false)
	session=app.session
	session.simulation_paused=true
	pump=visit(wrecks.pump)
	check(not pump.structures.has("wreck/pump/member/2") and pump.structures.has("wreck/pump/member/1") and not pump.structures.has("wreck/pump/roof/east"),"legacy pump retains its demolished column, single roof and original member IDs")
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if errors else 0)
