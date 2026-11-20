extends SceneTree

var s: WastelandSession
var errors := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: errors+=1

func in_world(id: String) -> int:
	var total := 0
	for record: Dictionary in s.fx.drop_records.values(): total+=int(record.items.get(id,0))
	return total

func place_ground(item: String) -> Vector3i:
	var home:=s.start_position()
	s.bag.add(item,1)
	for i in 64:
		var point:=home+Vector3.BACK.rotated(Vector3.UP,i*2.39996)*(3.0+i/18.0)
		point.y=roundf(s.stream.ground_at(point))
		var cell:=WastelandConstruction.cell_at(point)
		if s.construction.place(cell,item,0,0,home): return cell
	check(false,"could place "+item)
	return Vector3i.ZERO

func run()->void:
	WastelandSave.root_override="user://verification/construction-drops-%d"%OS.get_process_id()
	var app:Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.seed=2817
	cfg.spawn_roll=644
	app._enter_world(cfg,{},1,false)
	s=app.session
	s.simulation_paused=true
	await physics_frame
	var con:=s.construction
	var bench:=place_ground("bench")
	var upper:=bench+Vector3i.UP
	s.bag.add("frame",1)
	check(con.place(upper,"frame",0,0,s.start_position()),"place a frame on a workbench")
	s.bag.add("wood",8)
	s.bag.add("cobble",10)
	s.bag.add("concrete",10)
	for upgrade in 3: con.upgrade(upper)
	var inputs: Dictionary=s.catalog.recipes.composite_filter.inputs
	for id:String in inputs: s.bag.add(id,int(inputs[id]))
	s.queue_craft("composite_filter",1,bench)
	con.blocks[bench].out["bandage"]=2
	var initial_wood:=in_world("wood")
	var stones_before:=in_world("stone")
	var herbs_before:=in_world("reed_stem")
	var bag_wood:=s.bag.count("wood")
	var body:StaticBody3D=con.nodes[bench]
	s.hit_wall(body,5)
	check(in_world("wood")==initial_wood,"partial device damage releases no materials")
	s.hit_wall(body,10000)
	check(not con.blocks.has(bench) and not con.blocks.has(upper) and in_world("wood")==initial_wood+12 and in_world("stone")==stones_before+3,"failed support releases the dismantled bench and the concrete span's aggregate")
	check(in_world("concrete")==0 and in_world("bench")==0 and s.bag.count("wood")==bag_wood,"no fresh concrete, complete device or direct inventory credit")
	check(in_world("bandage")==2 and in_world("reed_stem")==herbs_before+int(inputs.reed_stem) and in_world("composite_filter")==0,"workbench outputs and unfinished ingredients spill once")
	s.hit_wall(body,10000)
	con.destroy(upper)
	check(in_world("wood")==initial_wood+12 and in_world("bandage")==2,"repeated removal cannot produce additional salvage")
	var turret:=place_ground("turret")
	con.blocks[turret].ammo=7
	var generator:=place_ground("generator")
	con.blocks[generator].fuel=122.3
	s.bag.add("wire",1)
	con.connect_device(turret)
	con.connect_device(generator)
	check(con.wires.size()==1,"spend one wire on a live connection")
	var wire_before:=in_world("wire")
	var fuel_before:=in_world("fuel")
	s.hit_wall(con.nodes[turret],10000)
	s.hit_wall(con.nodes[generator],10000)
	check(in_world("heavy_round")==7 and in_world("fuel")==fuel_before+1 and con.wires.is_empty() and in_world("wire")==wire_before+7,"remaining ammo, whole fuel and the cut wire are conserved")
	check(in_world("rifle")==0 and in_world("generator")==0 and in_world("turret")==0,"device salvage never recreates an assembled device or nested weapon")
	var spikes:=place_ground("spikes")
	var before_spikes:=in_world("wood")
	s.hit_wall(con.nodes[spikes],10000)
	check(in_world("wood")==before_spikes+1 and in_world("spikes")==0,"a single spike uses only one share of its three-item crafting batch")
	var soil:=s.start_position()+Vector3(2,0,2)
	soil.y=s.stream.ground_at(soil)
	var cell:=con.cell_at(soil+Vector3.UP*0.13)
	check(con.till(soil),"till the first test plot")
	s.bag.add("seed_corn",1)
	con.farm(cell,"seed_corn")
	var seeds:=in_world("seed_corn")
	s.hit_wall(con.crop_nodes[cell],100)
	check(not con.crops.has(cell) and in_world("seed_corn")==seeds+1 and in_world("corn")==0,"uprooting a seedling returns only the planted seed")
	con.till(soil)
	s.bag.add("seed_corn",1)
	con.farm(cell,"seed_corn")
	s.clock.hours+=36
	var bag_corn:=s.bag.count("corn")
	s.stream.excavate(con.position_of(cell),3.0)
	for tick in 360:
		if not con.crops.has(cell): break
		await physics_frame
	check(not con.crops.has(cell) and in_world("corn")==3 and in_world("seed_corn")==seeds+2 and s.bag.count("corn")==bag_corn,"cutting soil from a ripe crop spills the harvest onto the ground")
	var nature:WastelandChunk=s.stream.active[WastelandTerrainGen.chunk_at(Vector2(soil.x,soil.z))]
	var dug := false
	for key:String in nature.small_nature.keys():
		var entry:Dictionary=nature.small_nature[key]
		if entry.resource!="grass": continue
		var at:Vector3=nature.position+entry.root
		var previous:=in_world("fiber")
		s.stream.excavate(at,4.0)
		dug=not nature.small_nature.has(key) and s.stream.chunk_diff(nature.cell).get("removed",{}).has(key) and in_world("fiber")>previous
		var once:=in_world("fiber")
		s.stream.excavate(at,4.0)
		dug=dug and in_world("fiber")==once
		break
	check(dug,"digging out indexed grass breaks it once and leaves a persistent removal")
	if s.save_now(false)==OK:
		var loaded:=WastelandSave.read(1)
		var wood:=in_world("wood")
		app._enter_world(loaded.settings,loaded,1,false)
		s=app.session
		check(not s.construction.blocks.has(bench) and in_world("wood")==wood and in_world("corn")==3,"disk reload retains exactly the spilled goods")
	else: check(false,"write salvage snapshot")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if errors else 0)
