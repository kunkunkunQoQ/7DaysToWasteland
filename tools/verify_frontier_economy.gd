extends SceneTree

var failures:=0
var checks:=0
var s:WastelandSession
var cfg:Dictionary

func _initialize()->void: run.call_deferred()

func check(value:bool,text:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",text)

func enter(snapshot:Dictionary={}) -> void:
	s=WastelandSession.new()
	root.add_child(s)
	s.configure(cfg,snapshot,1,WastelandCatalog.new(),WastelandSettings.new())
	s.simulation_paused=true

func leave()->void:
	await s.stream.quiesce()
	await s.audio.finish_playback()
	s.queue_free()
	await process_frame

func at_board(origin:Vector2i)->void:
	var p:=WastelandSite.board_at(origin)
	s.stream.ensure_landing(Vector3(p.x,0,p.y))
	var chunk:WastelandChunk=s.stream.active[origin]
	var board:StaticBody3D=chunk.fixtures[chunk.object_key("trader")]
	s.player.global_position=board.global_position-Vector3.UP*0.7

func aim(body:StaticBody3D)-> bool:
	for i in 12:
		var target:=body.global_position
		s.player.global_position=target+Vector3.FORWARD.rotated(Vector3.UP,i*TAU/12.0)*1.5
		s.player.position.y=maxf(s.stream.ground_at(s.player.position)+0.1,target.y-1.0)
		var ray:=target-s.player.camera.global_position
		s.player.rotation.y=atan2(-ray.x,-ray.z)
		s.player.eyes.rotation.x=atan2(ray.y,Vector2(ray.x,ray.z).length())
		s.player.camera.force_update_transform()
		if s._interaction_trace().get("collider")==body:return true
	return false

func run()->void:
	WastelandSave.root_override="user://verification/steward-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var flags:=OS.get_cmdline_user_args()
	if "--guest" in flags or "--host" in flags:
		var port:=19377
		for flag in flags:
			if flag.begins_with("--port="): port=int(flag.get_slice("=",1))
		await online("--host" in flags,port)
		print("FRONTIER ECONOMY LAN QA checks=",checks," failures=",failures)
		quit(1 if failures else 0)
		return
	cfg=WastelandSave.default_world()
	cfg.seed=2817
	enter()
	var old:=WastelandProgression.new({"job":1,"accepted":true,"baseline":7,"records":{"loot":10}})
	var legacy:=old.active_job(s.catalog.quests)
	check(legacy.record=="loot" and old.job_count(legacy)==3 and WastelandProgression.new(old.snapshot()).active_job(s.catalog.quests).record=="loot","historic accepted search job preserves exact partial progress across another save")
	check(WastelandProgression.new({"job":1}).active_job(s.catalog.quests).record=="got_safe_water","unaccepted historical water job adopts the new route")
	var origin:=WastelandTerrainGen.chunk_at(s.board_destination().at)
	at_board(origin)
	var pair:=s.daily_orders()
	var local:=pair[0]
	var far:=pair[1]
	check(local.tier=="local" and local.at.distance_to(local.board)<128 and far.tier=="expedition" and far.at.distance_to(far.board)>=320,"board provides two measured routes, one local and one distant")
	s.track_order(local.id)
	check(s.order_destination().at==local.at,"local wayfinding identifies an actual source")
	s.track_order(far.id)
	s.ui_command("dispatch",[far.id])
	check(s.progress.dispatch.get("id")==far.id and not s.progress.dispatch.signed,"take registered dispatch at a real board")
	s.collect_dispatch(far.relay)
	check(s.bag.count("dispatch_parcel")==0,"remote mailbox cannot issue a parcel from the board")
	s.stream.ensure_landing(Vector3(far.at.x,0,far.at.y))
	await physics_frame
	await physics_frame
	var locker:StaticBody3D=s.stream.active[far.relay].structures["dispatch/locker"][0]
	check(aim(locker),"actual distant locker can be targeted")
	s._use()
	s._use()
	check(s.progress.dispatch.signed and s.bag.count("dispatch_parcel")==1 and s.order_destination().at==far.board,"sign once and point back to departure station")
	check(s.save_now(false)==OK,"signed parcel and departure survive save")
	var save:=WastelandSave.read(1)
	await leave()
	enter(save)
	at_board(origin)
	s.clock.hours=17.5
	s.ui_command("deliver",[far.id])
	s.ui_command("deliver",[far.id])
	s.achievements.refresh()
	check(s.bag.count("dispatch_parcel")==0 and s.progress.records.get("delivery")==1 and s.achievements.unlocked("clock_out") and s.bag.count("meme_clock")==1,"same courier on-time turn-in unlocks the cosmetic exactly once")
	var h:=s.hordes
	s.progress.job=4
	s.progress.accepted=true
	s.progress.records.build=19
	s.progress.records.exp_well=1
	s.progress.records.exp_bridge=1
	s.progress.records.exp_weather=1
	var bottles:=s.bag.count("clean_water")
	var med:=s.bag.count("bandage")
	s.clock.hours=6*24+22
	h.simulate(0.55)
	h.simulate(0.55)
	check(s.bag.count("clean_water")==bottles+2 and s.bag.count("bandage")==med+2,"completed expeditions supply the blood moon exactly once")
	h.wave_index=1
	h.approach_announced=false
	h.next_wave=s.clock.elapsed+12
	h.simulate(0.55)
	check(h.approach_announced,"restored weather station gives warning twelve seconds ahead")
	h.event_deaths=1
	s.clock.hours=7*24+4.1
	h.simulate(0.55)
	var repair:=s.progress.active_job(s.catalog.quests)
	check(repair.record=="rebuild_watch" and s.progress.job_count(repair)==0 and not s.progress.records.has("horde"),"dawn opens repair commission without awarding an undefeated night")
	s.ui_command("job")
	check(s.progress.job==4,"pre-existing buildings do not count as new repairs")
	s.bag.add("frame",4)
	var made:=0
	for x in range(4,28):
		var p:=Vector3(origin.x*32+x+0.5,0,origin.y*32+28.5)
		var cell:=Vector3i(floori(p.x),roundi(s.stream.ground_at(p)),floori(p.z))
		if s.construction.place(cell,"frame",0,0,s.player.position):made+=1
		if made==4:break
	check(made==4 and s.progress.job_count(repair)==4,"four actual supported placements after dawn count as repair work")
	s.ui_command("job")
	check(s.progress.job==5 and not s.progress.records.has("horde"),"repair consumes materials and opens the beacon without a true-defense award")
	await leave()
	for world_seed:int in [2817,-9251,182]:
		for start:String in ["seeded","grassland","foothills"]:
			cfg.seed=world_seed
			cfg.start_id=start
			enter()
			at_board(s.starting_cell)
			var routes:=s.daily_orders()
			var near:Dictionary=routes[0]
			var local_point:=Vector3(near.at.x,0,near.at.y)
			s.stream.ensure_landing(local_point)
			var found:=false
			var source_cell:=WastelandTerrainGen.chunk_at(near.at)
			for resource in s.stream.active[source_cell].decoration_root.get_children():
				if resource.get_meta("kind","")=="resource" and resource.get_meta("resource","")=="brush" and Vector2(resource.global_position.x,resource.global_position.z).distance_to(near.at)<0.2:
					found=true
					break
			check(found and near.at.distance_to(near.board)<128 and routes[1].at.distance_to(routes[1].board)>=320,"physical day-one source and distant relay for %s / %d"%[start,world_seed])
			await leave()
	print("FRONTIER ECONOMY QA checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func until(condition:Callable,seconds:float=30.0)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if condition.call(): return true
		await process_frame
	return false

func online(host:bool,port:int)->void:
	var app:Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	app.set_process_input(false)
	if host:
		cfg=WastelandSave.default_world()
		cfg.seed=2817
		app._enter_world(cfg,{},1,false)
		s=app.session
		var origin:=WastelandTerrainGen.chunk_at(s.board_destination().at)
		at_board(origin)
		var order:=s.daily_orders()[1]
		check(app.network.listen(port)==OK,"host accepts courier")
		if await until(func():return not app.network.joined_members().is_empty()):
			var guest:WastelandSurvivor=app.network.joined_members()[0].survivor
			guest.global_position=s.player.position+Vector3.RIGHT*0.8
			check(await until(func():return s.progress.dispatch.get("id")==order.id),"guest registers independent authenticated departure")
			var at:Vector2=order.at
			s.stream.ensure_landing(Vector3(at.x,0,at.y))
			var locker:StaticBody3D=s.stream.active[order.relay].structures["dispatch/locker"][0]
			s.player.global_position=locker.global_position+Vector3.RIGHT*1.8
			guest.global_position=s.player.position+Vector3.RIGHT
			await physics_frame
			await physics_frame
			check(aim(locker),"relay and physical locker exist on host")
			guest.global_position=s.player.position
			guest.velocity=Vector3.ZERO
			s.player.global_position+=Vector3.RIGHT*6
			check(await until(func():return s.progress.dispatch.get("signed",false),18),"guest use key at the remote locker reaches host")
			check(await until(func():return s.marker_records.any(func(row):return row.name=="parcel received")),"courier sees the parcel before the return trip")
			s.player.global_position=locker.global_position+Vector3.RIGHT
			s.collect_dispatch(order.relay)
			check(s.bag.count("dispatch_parcel")==0,"a second player cannot issue another copy of the signed parcel")
			at_board(origin)
			guest.global_position=s.player.position+Vector3.RIGHT*0.8
			s.clock.hours=17.4
			check(await until(func():return s.achievements.unlocked("clock_out")),"same guest completes on time and team earns one accessory")
			await until(func():return app.network.joined_members().is_empty())
			check(s.save_now(false)==OK,"save authority after guest delivers")
			app.network.stop()
			var old_id:=s.get_instance_id()
			app.open_world(1)
			check(await until(func():return is_instance_valid(app.session) and app.session.get_instance_id()!=old_id),"normal load creates a fresh authoritative session")
			s=app.session
			check(s.progress.dispatch.get("signed",false) and s.progress.delivery_day==s.clock.day() and s.bag.count("meme_clock")==1 and s.achievements.unlocked("clock_out"),"reloaded host preserves remote signature, daily settlement and unique shared reward")
		else:check(false,"guest joins")
	else:
		check(app.network.connect_to("127.0.0.1",port)==OK,"guest connects")
		if await until(func():return is_instance_valid(app.session) and app.session.replica):
			s=app.session
			var origin:=WastelandTerrainGen.chunk_at(s.board_destination().at)
			var board:=WastelandSite.board_at(origin)
			await until(func():return Vector2(s.player.position.x,s.player.position.z).distance_to(board)<4)
			var order:=s.daily_orders()[1]
			s.ui_command("dispatch",[order.id])
			var depot:Vector2=order.at
			if await until(func():return Vector2(s.player.position.x,s.player.position.z).distance_to(depot)<4 and s.stream.active.has(order.relay)):
				var locker:StaticBody3D=s.stream.active[order.relay].structures["dispatch/locker"][0]
				var hinted:=false
				for step in 60:
					var ray:=locker.global_position-s.player.camera.global_position
					s.player.rotation.y=atan2(-ray.x,-ray.z)
					s.player.pitch=atan2(ray.y,Vector2(ray.x,ray.z).length())
					s.player.eyes.rotation.x=s.player.pitch
					if s.hint.contains("寄存柜"):
						hinted=true
						Input.action_press("use")
					await create_timer(0.10).timeout
					Input.action_release("use")
					await create_timer(0.05).timeout
					if s.bag.count("dispatch_parcel")>0:break
				check(hinted,"replica shows authoritative prompt for courier locker")
			if await until(func():return is_instance_valid(s) and s.bag.count("dispatch_parcel")==1):
				s.ui_command("marker",[depot,"parcel received"])
			check(await until(func():return s.bag.count("dispatch_parcel")==1 and Vector2(s.player.position.x,s.player.position.z).distance_to(board)<5),"guest receives parcel and reaches departure board")
			s.ui_command("deliver",[order.id])
			s.ui_command("deliver",[order.id])
			check(await until(func():return s.bag.count("dispatch_parcel")==0 and s.achievements.unlocked("clock_out") and s.progress.records.get("delivery")==1),"duplicate remote request settles the guest's parcel once and unlocks the team achievement")
		else:check(false,"guest world bootstrap")
	if is_instance_valid(s):
		s.simulation_paused=true
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.network.stop()
	app.queue_free()
	await process_frame
