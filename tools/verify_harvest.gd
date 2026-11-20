extends SceneTree

const KINDS := ["herb_patch","reed_bed","iron_vein","machine_wreck"]
var passed:=0
var failures:=0
var session: WastelandSession
var config: Dictionary
var sites := {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	WastelandSave.root_override="user://verification/harvest-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.terrain_revision=2 # Historic Gray Bay coastal fixture.
	config.seed=2817
	for seed_value in [182,-9251,2817]:
		var generator:=WastelandTerrainGen.new(seed_value,2)
		var found := {}
		var stable := true
		var habitats := true
		for x in range(-5,6):
			for z in range(-4,4):
				var cell:=Vector2i(x,z)
				var start:=Vector2(cell)*WastelandTerrainGen.SIZE
				var center:=start+Vector2.ONE*WastelandTerrainGen.SIZE*0.5
				var site:=generator.site_for(cell)
				var dressing:=generator._dressing(cell,start,center,site)
				var local_seen:={}
				for entry in dressing:
					if entry.id not in KINDS: continue
					stable=stable and not local_seen.has(entry.index) and entry.index>=3100
					local_seen[entry.index]=true
					var world:=start+Vector2(entry.point.x,entry.point.z)
					var road:=generator.road_strength(world.x,world.y)
					var y:=float(entry.point.y)+0.035
					match entry.id:
						"reed_bed": habitats=habitats and y>=-0.381 and y<0.981
						"machine_wreck": habitats=habitats and road>0.034 and road<0.731
						"herb_patch": habitats=habitats and generator.biome(world.x,world.y) in [0,1]
						"iron_vein": habitats=habitats and y>1.29 and road<0.091
					if not found.has(entry.id):
						found[entry.id]=[cell,str(entry.index)]
						stable=stable and dressing==generator._dressing(cell,start,center,site)
		check(found.size()==4 and stable and habitats,"four stable habitat-matched resource types across seed %d"%seed_value)
		if seed_value==2817: sites=found
	if sites.size()!=4:
		quit(1)
		return
	open_world({})
	for kind in KINDS:
		var body:=resource_at(kind)
		check(is_instance_valid(body) and WastelandChunk._nature_mesh(kind,0,true).get_faces().size()>0 and WastelandChunk._nature_mesh(kind,0,false).get_faces().size()>0,"actual collision and both LODs: "+kind)
		var basic := "" if kind in ["herb_patch","reed_bed"] else "stone_axe"
		if basic!="":
			session.bag.add(basic,1)
		session.bag.assign(basic,0)
		session.bag.active=0
		var spec: Array=WastelandSession.RESOURCES[kind]
		var sample: String=WastelandSession.HARVEST_SAMPLES[kind]
		var initial:=session.bag.count(sample)
		if basic!="":
			session.bag.assign("",0)
			strike(body,9,0)
			check(not session.stream.chunk_diff(sites[kind][0]).get("resources",{}).has(sites[kind][1]),"bare hands cannot dismantle hard deposit: "+kind)
			session.bag.assign(basic,0)
		for i in 20:
			strike(body,10,0 if basic=="" else 1)
			if session.bag.count(sample)>initial: break
		check(session.bag.count(sample)==initial+1 and not body.is_queued_for_deletion(),"partial harvest yields the first sample before depletion: "+kind)
		var key:String=sites[kind][1]
		var cell:Vector2i=sites[kind][0]
		var partial:float=session.stream.chunk_diff(cell).resources[key]
		check(partial>0 and partial<=float(spec[1])*0.5,"residual amount survives repeated hits: "+kind)
		var specialist: String=WastelandSession.HARVEST_TOOLS[kind]
		session.bag.add(specialist,1)
		session.bag.assign(specialist,0)
		check(session.save_now(false)==OK,"save a half-harvested "+kind)
		await close_world()
		open_world(WastelandSave.read(1))
		body=resource_at(kind)
		check(is_equal_approx(float(session.stream.chunk_diff(cell).resources[key]),partial) and session.bag.count(sample)==initial+1,"reloading preserves residual amount and spent sample: "+kind)
		strike(body,10,1)
		var after:=float(session.stream.chunk_diff(cell).resources.get(key,0.0))
		check(is_equal_approx(partial-after,minf(partial,10.0*1.19*1.65)),"specialist tool applies the correct work per blow: "+kind)
		for i in 12:
			if body.is_queued_for_deletion(): break
			strike(body,20,2)
		var total:=session.bag.count(sample)
		check(session.progress.records.get("gather_"+kind,0)==1,"a sampled source is recorded once across save/load: "+kind)
		strike(body,40,2)
		check(body.is_queued_for_deletion() and session.stream.chunk_diff(cell).removed.has(key) and total==session.bag.count(sample),"final harvest pays once and removes the collider: "+kind)
		check(session.bag.count(str(spec[2].keys()[0]))>=int(spec[2].values()[0]),"harvest grants its usable primary material: "+kind)
		var delta:=session.stream.diffs.duplicate(true)
		await close_world()
		open_world({})
		var replica_body:=resource_at(kind)
		session.stream.mirror_deltas(delta,{})
		check(replica_body.is_queued_for_deletion(),"playing client removes the same natural instance: "+kind)
		await close_world()
		open_world({})
		body=resource_at(kind)
		session.bag.add(specialist,1)
		session.bag.assign(specialist,0)
		strike(body,1000,2)
		var primary: String=spec[2].keys()[0]
		var expected:=roundi(float(spec[2][primary])*1.4)+(1 if primary==sample else 0)
		check(session.bag.count(primary)==expected and session.progress.records.get("gather_"+kind,0)==1,"one-shot specialist harvest awards the exact premium yield and one discovery: "+kind)
		if kind=="machine_wreck":
			check(session.bag.count("spring")==3 and session.bag.count("scrap")==9 and session.bag.count("parts")==0,"wrench recovers springs and scrap, including the loose scrap sample")
	await close_world()
	print("HARVEST QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)

func open_world(save: Dictionary) -> void:
	session=WastelandSession.new()
	root.add_child(session)
	session.configure(config,save,1,WastelandCatalog.new(),WastelandSettings.new())
	session.simulation_paused=true

func close_world() -> void:
	await session.stream.quiesce()
	await session.audio.finish_playback()
	session.queue_free()
	await process_frame

func resource_at(kind: String) -> StaticBody3D:
	var cell:Vector2i=sites[kind][0]
	var key:String=sites[kind][1]
	if not session.stream.active.has(cell):
		session.stream._install(cell,session.stream.generator.build(cell,{}))
	var chunk:WastelandChunk=session.stream.active[cell]
	for node in chunk.decoration_root.get_children():
		if node.get_meta("index","")==key and node.get_meta("resource","")==kind:
			return node
	return null

func strike(body: StaticBody3D, amount: float, power: int) -> void:
	var before:=session.fx.drop_records.keys()
	var bag_before:=session.bag.counts.duplicate()
	session._harvest(body,amount,power,body.global_position)
	var released:=session.fx.drop_records.keys().filter(func(id):return not before.has(id))
	if not released.is_empty():
		check(session.bag.counts==bag_before,"harvest lands in the world before pickup")
		for id:String in released: session.fx.take_drop(id)

func check(ok: bool, label: String) -> void:
	if ok:
		passed+=1
		print("PASS ",label)
	else:
		failures+=1
		printerr("FAIL ",label)
