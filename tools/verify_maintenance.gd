extends SceneTree

var failures := 0
var s:WastelandSession
const Art=preload("res://game/art/item_art.gd")

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1

func aim(point:Vector3)->void:
	s.player.position=point+Vector3(0,-s.player.eyes.position.y,1.48)
	s.player.rotation.y=0
	s.player.pitch=0
	s.player.eyes.rotation.x=0
	for i in 2: await physics_frame

func run()->void:
	WastelandSave.root_override="user://verification/maintenance-%d"%OS.get_process_id()
	var app:Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	if "--host" in OS.get_cmdline_user_args() or "--guest" in OS.get_cmdline_user_args():
		await network_check(app,"--host" in OS.get_cmdline_user_args())
		quit(1 if failures else 0)
		return
	var cfg:Dictionary=app._default_config()
	cfg.spawn_roll=644
	app._enter_world(cfg,{},1,false)
	s=app.session
	s.simulation_paused=true
	var home:=s.start_position()
	var cell:=Vector3i.ZERO
	s.bag.add("bench",1)
	await physics_frame
	var placed:=false
	for i in 20:
		var at:=home+Vector3.FORWARD.rotated(Vector3.UP,TAU*i/20.0)*3
		at.y=roundf(s.stream.ground_at(at))
		cell=WastelandConstruction.cell_at(at)
		if s.construction.place(cell,"bench",0,0,home):
			placed=true
			break
	check(placed,"workbench placed on actual ground")
	if not placed: quit(1);return
	for id:String in ["composite_filter","reinforcement_kit"]:
		var inputs:Dictionary=s.catalog.recipes[id].inputs
		for part:String in inputs: s.bag.add(part,2*int(inputs[part]))
		s.queue_craft(id,2,cell)
		check(not s.bag.has_all(inputs) and Art.icon(id,s.catalog.items[id])!=null,id+" ingredients consumed and distinct item model renders")
	s.clock.advance(60)
	s.construction.simulate(1)
	s.collect_station(cell)
	check(s.bag.count("reinforcement_kit")==2 and s.bag.count("composite_filter")==2,"take both finished kits from the workbench")
	s.bag.assign("reinforcement_kit",s.bag.active)
	await aim(WastelandConstruction.position_of(cell))
	s._use()
	check(s.bag.count("reinforcement_kit")==2,"interacting with a healthy facility preserves the kit")
	s.construction.damage(cell,140)
	s._use()
	check(s.construction.blocks[cell].hp==260 and s.bag.count("reinforcement_kit")==1,"first-person interaction restores a damaged facility")
	s._use()
	check(s.bag.count("reinforcement_kit")==1,"repeat interaction on full health spends nothing")
	var wall:=cell+Vector3i.UP
	s.player.position=home
	s.bag.add("frame",1)
	s.construction.place(wall,"frame",0,0,home)
	s.bag.add("wood",8)
	s.bag.add("cobble",10)
	s.bag.add("concrete",10)
	for i in 3: s.construction.upgrade(wall)
	s.construction.damage(wall,600)
	await aim(WastelandConstruction.position_of(wall))
	s._use()
	check(s.construction.blocks[wall].hp==2380 and s.bag.count("reinforcement_kit")==0,"damaged reinforced concrete gains exactly 480 health and consumes one kit")
	s.bag.add("filter_pump",1)
	s.bag.assign("filter_pump",s.bag.active)
	check(s._draw_water(home,true) and s.bag.count("clean_water")==4 and s.bag.count("composite_filter")==1,"portable pump exchanges a cartridge for four clean water")
	s.bag.add("fiber",1)
	s.bag.assign("composite_filter",s.bag.active)
	var well:Vector3=preload("res://game/world/expedition_sites.gd").survey(s.stream.generator).points.well
	s.progress.records.exp_canal=1
	s.progress.records.exp_well=1
	s.stream.ensure_landing(well)
	await aim(well+Vector3.UP*0.83)
	s._use()
	check(s.bag.count("clean_water")==10 and s.bag.count("composite_filter")==0,"actual repaired desert pump yields six more water")
	check(s._draw_water(home,true) and s.bag.count("clean_water")==11,"when cartridges are gone the existing fiber filter still works")
	s.bag.add("composite_filter",2)
	s.bag.add("clean_water",9)
	s.bag.add("stone",3000)
	check(not s._draw_water(home,true) and s.bag.count("composite_filter")==2 and s.bag.count("clean_water")==20,"full bag preserves cartridge and prevents partial batch")
	check(s.save_now(false)==OK,"save repaired facility and spent materials")
	var data:=WastelandSave.read(1)
	app._enter_world(data.settings,data,1,false)
	s=app.session
	check(s.construction.blocks[cell].hp==260 and s.construction.blocks[wall].hp==2380 and s.bag.count("composite_filter")==2 and s.bag.count("reinforcement_kit")==0,"reload preserves health and exact remaining consumables")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)

func until(condition:Callable)->bool:
	var end:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<end:
		if condition.call(): return true
		await process_frame
	return false

func network_check(app:Node,host:bool)->void:
	var sites:=preload("res://game/world/expedition_sites.gd")
	if host:
		var cfg:Dictionary=app._default_config()
		cfg.spawn_roll=644
		app._enter_world(cfg,{},1,false)
		s=app.session
		var well:Vector3=sites.survey(s.stream.generator).points.well
		s.stream.ensure_landing(well)
		s.player.position=well+Vector3(2,0.1,2)
		s.progress.records.exp_canal=1
		s.progress.records.exp_well=1
		s.bag.add("composite_filter",1)
		s.bag.assign("composite_filter",0)
		check(app.network.listen(19468)==OK,"host starts")
		if await until(func():return is_instance_valid(app.network.member)):
			app.network.member.global_position=well+Vector3(0,0.12,1.85)
			check(await until(func():return s.bag.count("clean_water")==6),"guest use consumes one shared filter on authority")
			check(s.bag.count("composite_filter")==0,"host sees exact shared debit")
			await until(func():return not is_instance_valid(app.network.member))
		else: check(false,"guest joined")
	else:
		check(app.network.connect_to("127.0.0.1",19468)==OK,"guest connects")
		if await until(func():return is_instance_valid(app.session) and app.session.replica):
			s=app.session
			var well:Vector3=sites.survey(s.stream.generator).points.well
			var end:=Time.get_ticks_msec()+12500
			while s.bag.count("clean_water")<6 and Time.get_ticks_msec()<end:
				var ray:=well+Vector3.UP*0.83-s.player.camera.global_position
				s.player.rotation.y=atan2(-ray.x,-ray.z)
				s.player.pitch=atan2(ray.y,Vector2(ray.x,ray.z).length())
				s.player.eyes.rotation.x=s.player.pitch
				Input.action_press("use")
				await create_timer(0.075).timeout
				Input.action_release("use")
				await create_timer(0.075).timeout
			check(s.bag.count("clean_water")==6 and s.bag.count("composite_filter")==0,"guest sees authoritative batch and inventory after normal use input")
		else: check(false,"guest replica loads")
	app.network.stop()
	if is_instance_valid(s):
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.queue_free()
	await process_frame
