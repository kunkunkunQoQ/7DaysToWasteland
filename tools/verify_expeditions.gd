extends SceneTree

const Sites:=preload("res://game/world/expedition_sites.gd")
const Missions:=preload("res://game/sim/expeditions.gd")
var app:Node
var fails:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,msg:String)->void:
	if ok: print("PASS ",msg)
	else:
		printerr("FAIL ",msg)
		fails+=1

func aim(s:WastelandSession,id:String)->void:
	var target:Vector3=Sites.survey(s.stream.generator).points[id]
	s.stream.ensure_landing(target)
	var focus:=target+Vector3.UP*0.83
	s.player.position=focus+Vector3(0,-s.player.eyes.position.y,1.55)
	s.player.rotation.y=0
	s.player.pitch=0
	s.player.eyes.rotation.x=0
	for i in 3: await physics_frame
	var hit:=s._interaction_trace()
	var body:Object=hit.get("collider")
	check(body!=null and body.get_meta("expedition_id","")==id,"actual first-person ray sees "+id)

func walk_trail(s:WastelandSession,kind:String)->void:
	var trail:Array=Sites.survey(s.stream.generator).trails[kind]
	for point:Vector3 in trail: s.stream.ensure_landing(point)
	var goals:Array[Vector2]=[]
	for i in trail.size():
		var a:Vector3=trail[maxi(0,i-1)]
		var b:Vector3=trail[mini(trail.size()-1,i+1)]
		var along:=Vector2(b.x-a.x,b.z-a.z).normalized()
		goals.append(Vector2(trail[i].x,trail[i].z)-Vector2(along.y,-along.x)*2.2)
	var begin:=goals[1]
	s.player.position=Vector3(begin.x,s.stream.generator.ground(begin.x,begin.y)+0.15,begin.y)
	s.player.velocity=Vector3.ZERO
	Input.action_press("up")
	var index:=2
	var travelled:=0.0
	var last:=begin
	for i in 2500:
		await physics_frame
		var pos:=Vector2(s.player.position.x,s.player.position.z)
		travelled+=last.distance_to(pos)
		last=pos
		if pos.distance_to(goals[index])<1.25:
			index+=1
			if index>=goals.size()-1: break
		var heading:=goals[index]-pos
		s.player.rotation.y=atan2(-heading.x,-heading.y)
		s.player.simulate(1.0/60,true)
	Input.action_release("up")
	if index<goals.size()-1:
		for j in s.player.get_slide_collision_count():
			var body:=s.player.get_slide_collision(j).get_collider()
			print("BLOCK ",body.get_meta_list()," ",body.get_meta("key","")," ",body.get_meta("structure_key","")," ",body.global_position," vs ",s.player.position," goal ",goals[index])
	check(index>=goals.size()-1,"%s marked route traversed on foot: %.1f m, waypoint %d/%d"%[kind,travelled,index,goals.size()-1])

func dive(s:WastelandSession,id:String)->void:
	var target:Vector3=Sites.survey(s.stream.generator).points[id]
	s.stream.ensure_landing(target)
	s.player.global_position=Vector3(target.x,-1.08,target.z+1.55)
	s.player.velocity=Vector3.ZERO
	s.player.rotation.y=0
	var minimum_breath:=s.player.max_breath()
	s.player.breath=minimum_breath
	Input.action_press("crouch")
	var reached:=false
	for i in 480:
		await physics_frame
		s.player.simulate(1.0/60,true)
		var axis:Vector3=(target+Vector3.UP*0.83-s.player.camera.global_position).normalized()
		s.player.pitch=asin(clampf(axis.y,-1,1))
		s.player.eyes.rotation.x=s.player.pitch
		minimum_breath=minf(minimum_breath,s.player.breath)
		var hit:=s._interaction_trace()
		if hit.get("expedition_id","")==id and s.player.submerged:
			s._use()
			reached=true
			break
	Input.action_release("crouch")
	Input.action_press("jump")
	for i in 380:
		await physics_frame
		s.player.simulate(1.0/60,true)
		minimum_breath=minf(minimum_breath,s.player.breath)
		if not s.player.submerged: break
	Input.action_release("jump")
	check(reached and not s.player.submerged and minimum_breath>0,id+" real descent, read and ascent with remaining oxygen")

func run()->void:
	for seed:int in [127,6641,39182,9,107]:
		var g:=WastelandTerrainGen.new(seed,3)
		var data:=Sites.survey(g)
		for kind:String in ["alpine","desert"]:
			var trail:Array=data.trails[kind]
			var maximum:=0.0
			for i in range(1,trail.size()):
				var a:Vector3=trail[i-1]
				var b:Vector3=trail[i]
				maximum=maxf(maximum,absf(a.y-b.y)/Vector2(a.x-b.x,a.z-b.z).length())
			check(maximum<0.7 and g.region_kind(trail[0].x,trail[0].z)==kind and trail[0].distance_to(trail[-1])>66,"seed %d %s route max grade %.2f"%[seed,kind,maximum])
	WastelandSave.root_override="user://verification/expeditions-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg:Dictionary=app._default_config()
	app._enter_world(cfg,{},1,false)
	var s:WastelandSession=app.session
	s.simulation_paused=true
	check(Missions.journal(s).size()==3,"fresh world lists all three expeditions")
	await aim(s,"weather")
	s._use()
	check(not s.progress.records.has("exp_weather"),"station requires trailhead first")
	await aim(s,"shelter")
	s._use()
	check(not s.progress.records.has("exp_shelter"),"repair requires material")
	for pair:Array in [["wood",6],["stone",3],["fiber",3],["scrap",5]]:
		s.bag.add(pair[0],pair[1])
	for id:String in ["shelter","weather","canal","well"]:
		if id=="weather": await walk_trail(s,"alpine")
		if id=="well": await walk_trail(s,"desert")
		await aim(s,id)
		s._use()
		check(s.progress.records.has("exp_"+id),"in-world repair "+id)
	check(s.bag.count("scrap")==0 and s.bag.count("wood")==0,"actual repair materials consumed once")
	s.player.hydration=17
	s._use()
	check(s.player.hydration>=50,"restored desert pump rehydrates player")
	await aim(s,"shelter")
	s._use()
	check(s.player.warm_drink_left>=99,"repaired shelter gives thermal protection")
	for id:String in ["ferry","pump","bridge"]:
		var p:Vector3=WastelandSunkenSites.landmarks(s.stream.generator)[id]
		s.stream.ensure_landing(p)
		var chunk:WastelandChunk=s.stream.active[WastelandTerrainGen.chunk_at(Vector2(p.x,p.z))]
		var key:=chunk.object_key("submerged/"+id)
		var diff:Dictionary=s.stream.edit_chunk(chunk.cell)
		if not diff.has("containers"): diff.containers={}
		diff.containers[key]={"items":{},"day":1}
	await aim(s,"pump")
	s._use()
	check(not s.progress.records.has("exp_pump"),"out-of-sequence dive leaves progress unchanged")
	await dive(s,"ferry")
	check(s.progress.records.has("exp_ferry"),"old searched ferry can still be investigated")
	s.player.position=s.start_position()
	s.save_now(false)
	var state:=WastelandSave.read(1)
	app._enter_world(state.settings,state,1,false)
	s=app.session
	s.simulation_paused=true
	check(s.progress.records.has("exp_well") and Missions.journal(s)[2].id=="pump","retreat and disk reload preserve facilities and dive stage")
	for id:String in ["pump","bridge"]:
		await dive(s,id)
		check(s.progress.records.has("exp_"+id),"dive record "+id)
	var reward:int=s.bag.count("spring")
	await aim(s,"bridge")
	s._use()
	check(reward==2 and s.bag.count("spring")==reward and Missions.journal(s)[2].complete,"final salvage reward issued once")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if fails else 0)
