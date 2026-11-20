extends SceneTree

const Salvage:=preload("res://game/world/structural_salvage.gd")
var failures := 0
var app: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: print("PASS ",label)
	else:
		failures += 1
		printerr("FAIL ",label)

func walk(s: WastelandSession, frames: int) -> void:
	Input.action_press("up")
	for i in frames:
		await physics_frame
		s.player.simulate(1.0/60.0,true)
	Input.action_release("up")

func run() -> void:
	WastelandSave.root_override="user://verification/structures-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg: Dictionary=app._default_config()
	cfg.terrain_revision=2
	app._enter_world(cfg,{},1,false)
	var s: WastelandSession=app.session
	s.simulation_paused=true
	s.stream.ensure_landing(Vector3(-16,2,48))
	var c: WastelandChunk=s.stream.active[WastelandSite.SHORE_CELL]
	var key:="wall/0/2/2"
	var wall: StaticBody3D=c.structures[key][0]
	var at:=wall.global_position
	var before:int=c.structures[key].size()
	check(before>=2,"wall core and decorative facade share one key")
	check(c.structures.has("door/entrance") and c.structures.has("slab/0") and c.structures.has("roof/-1"),"door, floor and roof registered")
	s.player.global_position=at+Vector3(0,-1.28,1.8)
	s.player.rotation.y=0
	s.player.pitch=0
	s.player.eyes.rotation.x=0
	await walk(s,55)
	check(s.player.global_position.z>at.z,"intact wall stops forward walking")
	for i in 5:
		s._melee(s.catalog.items.sledge,1.0)
		await physics_frame
		if not c.structures.has(key): break
	check(not c.structures.has(key),"normal camera melee destroys core and facade")
	await walk(s,95)

	check(s.player.global_position.z<at.z-0.8,"walked through demolished wall")
	s.stream.ensure_landing(Vector3(5,0,12))
	var dock:WastelandChunk=s.stream.active[Vector2i.ZERO]
	check(Salvage.materials(dock,"dock/plank/10").has("wood"),"dock planks yield wood")
	s.hit_wall(dock.structures["dock/plank/10"][0],120)
	check(not dock.structures.has("dock/plank/10") and dock.structures.has("dock/plank/11") and dock.structures.has("dock/platform"),"single dock plank breaks independently of neighbors and platform")
	for area: String in WastelandSunkenSites.landmarks(s.stream.generator):
		var pos:Vector3=WastelandSunkenSites.landmarks(s.stream.generator)[area]
		s.stream.ensure_landing(pos)
		var underwater:WastelandChunk=s.stream.active[WastelandTerrainGen.chunk_at(Vector2(pos.x,pos.z))]
		var target: String={"ferry":"hull/6/1","pump":"tank","bridge":"arch/6"}[area]
		var id:="wreck/"+area+"/"+target
		check(underwater.structures.has(id),area+" individual wreck section exists")
		var expected:String={"ferry":"wood","pump":"scrap","bridge":"stone"}[area]
		check(Salvage.materials(underwater,id).has(expected),area+" wreck recovers "+expected)
		if underwater.structures.has(id): s.hit_wall(underwater.structures[id][0],1000)
		check(not underwater.structures.has(id),area+" collision section removed")
	s.save_now(false)
	var state:=WastelandSave.read(1)
	app._enter_world(state.settings,state,1,false)
	s=app.session
	s.stream.ensure_landing(Vector3(-16,2,48))
	c=s.stream.active[WastelandSite.SHORE_CELL]
	check(not c.structures.has(key),"destroyed core and trim survive disk reload")
	s.hit_wall(c.structures["wall/0/3/2"][0],10000)
	check(c.structures.has("roof/-1"),"legacy roof spans a single missing wall section")
	for bay in [0,1,3,4]:
		s.hit_wall(c.structures["wall/0/3/"+str(bay)][0],10000)
	check(not c.structures.has("roof/-1") and c.structures.has("roof/1"),"legacy roof loses only the unsupported slope")
	var remote:=s.stream.diffs.duplicate(true)
	var grid:=WastelandTerrainGen.grid_key(c.cell)
	remote[grid].site_damage["slab/0"]=133.0
	s.stream.mirror_deltas(remote,s.stream.digs.duplicate(true))
	check(float(c.structures["slab/0"][0].get_meta("hp"))==133.0,"client mirror applies partial hit")
	remote=remote.duplicate(true)
	remote[grid].site_damage["slab/0"]=0.0
	s.stream.mirror_deltas(remote,s.stream.digs.duplicate(true))
	check(not c.structures.has("slab/0"),"client mirror removes destroyed slab")
	var hospital_cell:=Vector2i(3,-4)
	s.stream.ensure_landing(Vector3(112,0,-112))
	var hospital:WastelandChunk=s.stream.active[hospital_cell]
	for side in [1,0]:
		for bay in 5: s.hit_wall(hospital.structures["wall/0/%d/%d"%[side,bay]][0],10000)
		if side==1: check(hospital.structures.has("slab/2"),"legacy floors bridge between the other pair of opposing walls")
	check(not hospital.structures.has("slab/1") and not hospital.structures.has("slab/2") and hospital.structures.has("slab/0"),"legacy upper floors collapse after both opposing wall spans are broken")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)


