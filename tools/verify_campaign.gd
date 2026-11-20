extends SceneTree

# New-world campaign smoke test. Player travel and aim are automated; loot,
# material consumption, weapon damage, patrols, waves and job rewards use game logic.
const STEP := 0.25
var s: WastelandSession
var app: Node
var passed := 0
var failures := 0
var ending_shown := false
var hunting_ground := Vector3.ZERO
var home_cell := Vector2i.ZERO
var waves_fought := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	WastelandSave.root_override="user://verification/campaign-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	var settings: Dictionary=app._default_config()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--campaign-seed="): settings.seed=int(arg.get_slice("=",1))
		if arg.begins_with("--start="): settings.start_id=arg.get_slice("=",1)
	settings.minutes=5.0
	app._enter_world(settings,{},1,false)
	s=app.session
	s.simulation_paused=true
	s.panel.connect(func(id: String,_context: Variant): if id=="ending": ending_shown=true)
	check(s.bag.counts.is_empty() and s.bag.current()=="","fresh world has no starting items")
	var spawn:=Vector2(s.player.position.x,s.player.position.z)
	home_cell=WastelandTerrainGen.chunk_at(s.board_destination().at)
	if settings.start_id=="random":
		check(spawn==s.stream.generator.wild_start and spawn.distance_to(WastelandSite.board_at(home_cell))>60,"new survivor follows the compass from wilderness to a real station")
	else:
		check(WastelandTerrainGen.chunk_at(spawn)==s.stream.generator.starting_outpost(settings.start_id),"historical station start")
	var camp:=Vector2(home_cell*32)+Vector2(16,16)
	for i in 24:
		var spot:=camp+Vector2.from_angle(TAU*i/24.0)*28.0
		if s.stream.generator.ground(spot.x,spot.y)>1.5 and not s.stream.generator.water_basin(spot.x,spot.y):
			hunting_ground=Vector3(spot.x,0,spot.y)
			break
	var home:=home_cell
	for z in range(-2,3):
		for x in range(-2,3):
			load_cell(home+Vector2i(x,z))
	load_cell(home_cell)
	await physics_frame
	for job in 6:
		if not await board(job,false): break
		match job:
			0: await gather()
			1: await purify_samples()
			2: build_defense()
			3: await fight_patrols()
			4: await guard_night()
			5: await search_caches(true)
		if failures or not await board(job,true): break
	check(s.progress.job==6,"all six storyline deliveries settled")
	if s.progress.job==6:
		check(ending_shown and int(s.progress.snapshot().get("finish_day",0))>0,"last delivery records the finish day and opens the ending")
		check(s.bag.count("beacon_log")==0 and s.bag.count("solar")==1,"final trade consumes the recovered beacon and pays once")
		s.ui_command("job")
		check(s.bag.count("solar")==1,"revisiting the board gives no duplicate ending reward")
		var finish_day:=int(s.progress.snapshot().get("finish_day",0))
		print("CAMPAIGN RESULT seed=%d start=%s finish_day=%d jobs=%d waves=%d solar=%d"%[settings.seed,settings.start_id,finish_day,s.progress.job,waves_fought,s.bag.count("solar")])
		check(app.panels.active=="ending" and app.panels.visible,"the ending is the visible panel")
		var automatic:=WastelandSave.read(1)
		check(int(automatic.get("progress",{}).get("finish_day",0))==finish_day and automatic.get("bag",{}).get("counts",{}).get("solar",0)==1,"the ending autosaves progress and reward before any manual save")
		check(press_button("继续自由生存"),"the ending offers a working free-survival button")
		check(not app.panels.visible and s.controls_enabled and not s.simulation_paused,"closing the ending restores gameplay controls")
		check(s.save_now(false)==OK and int(WastelandSave.read(1).progress.get("finish_day",0))==finish_day,"finished campaign survives save serialization")
		await s.stream.quiesce()
		await s.audio.finish_playback()
		var old_id:=s.get_instance_id()
		app.open_world(1)
		for i in 12:
			await process_frame
			if app.session.get_instance_id()!=old_id: break
		s=app.session
		check(s.get_instance_id()!=old_id and s.progress.job==6 and int(s.progress.snapshot().get("finish_day",0))==finish_day and s.bag.count("solar")==1,"reopening the saved world resumes the completed campaign once")
		app.open_panel("journal")
		await process_frame
		check(press_button("回看结局") and app.panels.active=="ending","journal reopens the completed ending after reload")
		await process_frame
		press_button("继续自由生存")
		s.simulation_paused=true
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	print("CAMPAIGN QA passed=%d failed=%d waves=%d"%[passed,failures,waves_fought])
	quit(1 if failures else 0)

func press_button(caption: String) -> bool:
	for button: Button in app.panels.content.find_children("*","Button",true,false):
		if button.text==caption and button.visible and not button.disabled:
			button.pressed.emit()
			return true
	return false

func load_cell(cell: Vector2i) -> void:
	s.stream.ensure_landing(Vector3(cell.x*32+16,0,cell.y*32+16))

func board(job: int, settle: bool) -> bool:
	var notice: StaticBody3D
	var destination:Dictionary=s.board_destination()
	var cell:=WastelandTerrainGen.chunk_at(destination.at)
	load_cell(cell)
	check(cell.distance_to(home_cell)<12.0,"quest uses a local outpost board")
	for node in s.stream.active[cell].decoration_root.get_children():
		if node.get_meta("kind","")=="trader": notice=node
	if notice==null or not aim(notice):
		check(false,"reachable lodge board")
		return false
	s._use()
	await process_frame
	if app.panels.active!="trade":
		check(false,"interacting with the board opens its jobs")
		return false
	s.ui_command("job")
	await process_frame
	if app.panels.visible and app.panels.active!="ending": app.close_overlay()
	s.simulation_paused=true
	var ok:=s.progress.job==job+1 if settle else s.progress.job==job and s.progress.accepted
	check(ok,("settled " if settle else "accepted ")+str(s.catalog.quests[job].name))
	return ok

func aim(node: Node3D) -> bool:
	var target:=node.global_position
	var head: Area3D
	if node is WastelandCreature:
		head = node.hurtboxes.areas.get("head")
		if head == null or not node.active or node.hp <= 0.0: return false
		target = head.get_child(0).global_position
	for i in 12:
		var direction:=Vector3.FORWARD.rotated(Vector3.UP,i*TAU/12.0)
		var foot:=target+direction*(1.45 if not node is WastelandCreature else 1.95)
		foot.y=s.stream.ground_at(foot)+0.06
		if not node is WastelandCreature:
			# Shelves and upstairs caches can sit above outdoor ground.
			foot.y=maxf(foot.y,target.y-1.1)
		s.player.global_position=foot
		s.player.velocity=Vector3.ZERO
		var ray: Vector3=target-s.player.camera.global_position
		s.player.rotation.y=atan2(-ray.x,-ray.z)
		s.player.pitch=atan2(ray.y,Vector2(ray.x,ray.z).length())
		s.player.eyes.rotation.x=s.player.pitch
		s.player.camera.force_update_transform()
		var target_hit:=s._trace(3.0,15)
		if head != null: target_hit=s._trace(3.1,15,false,true,true)
		elif node.get_meta("kind","") in ["drop","loot"]: target_hit=s._interaction_trace()
		if target_hit.get("collider")==node or (head != null and target_hit.get("collider")==head):
			return true
	return false

func nodes(kind: String, key: String="", value: Variant=null) -> Array:
	var result:=[]
	for chunk: WastelandChunk in s.stream.active.values():
		for node in chunk.decoration_root.get_children():
			if not node.is_queued_for_deletion() and node.get_meta("kind","")==kind and (key=="" or node.get_meta(key,null)==value):
				result.append(node)
	return result

func harvest(kind: String, material: String, needed: int) -> void:
	for node in nodes("resource","resource",kind):
		if s.bag.count(material)>=needed: return
		if not is_instance_valid(node) or not aim(node): continue
		var at:Vector3=node.global_position
		for i in 12:
			if not is_instance_valid(node) or node.is_queued_for_deletion() or s.bag.count(material)>=needed: break
			if not aim(node): break
			swing()
			for frame in 420:
				if s.timber.active.is_empty(): break
				s.timber.tick(1.0/60.0)
			await collect_nearby(at)
			if s.bag.current()=="" and kind in ["oak","pine","boulder"]: break

func collect_nearby(at:Vector3)->void:
	# Multiple items can land together. Pick up anything within reach of the
	# felled resource so the frontmost bundle cannot hide the remaining pieces.
	for pass_index in 6:
		await physics_frame
		var collected:=false
		for key:String in s.fx.drop_live.keys():
			var body:StaticBody3D=s.fx.drop_live[key]
			if body.global_position.distance_to(at)<7 and not s.fx.drop_records[key].get("buoy",false) and aim(body):
				s._use()
				collected=collected or not s.fx.drop_records.has(key)
		if not collected: break

func equip(id: String) -> void:
	s.ui_command("assign",[id])

func swing() -> void:
	var id:=s.bag.current()
	var cooldown:=float(s.catalog.items.get(id,{}).get("cooldown",0.61))
	s.clock.advance(cooldown)
	s.action_lock=maxf(0.0,s.action_lock-cooldown)
	# Process the same stamina recovery as a player waiting for their next strike.
	for frame in ceili(cooldown*60.0):
		s.player.simulate(1.0/60.0,false)
	Input.action_press("fire")
	s._process_controls(cooldown)
	Input.action_release("fire")

func craft(id: String, count: int) -> void:
	s.ui_command("craft",[id,count,null])
	if not s.hand_queue.is_empty():
		s.clock.advance(maxf(0.0,float(s.hand_queue.back().done)-s.clock.elapsed)+0.01)
		s._finish_crafting()

func gather() -> void:
	for item:String in ["fallen_stick","pebble","grass"]:
		var id:String={"fallen_stick":"stick","pebble":"stone","grass":"fiber"}[item]
		var needed:=1 if id=="stick" else 2
		for node in nodes("resource","resource",item):
			if s.bag.count(id)>=needed: break
			if not aim(node): continue
			if item=="grass":
				var at:Vector3=node.global_position
				swing()
				await collect_nearby(at)
			else:
				s._use()
				await physics_frame
		check(s.bag.count(id)>=needed,"gathered "+id)
	craft("stone_axe",1)
	check(s.bag.count("stone_axe")==1,"bare hands obtain wood, stone and fiber for a crafted axe")
	equip("stone_axe")
	await harvest("oak","wood",30)
	if s.bag.count("wood")<30: await harvest("pine","wood",30)
	check(s.progress.job_count(s.catalog.quests[0])>=20,"harvesting generated trees fills the wood order")

func purify_samples() -> void:
	var vat:StaticBody3D=s.stream.active[home_cell].structures["dispatch/cistern"][0]
	if "--boil" in OS.get_cmdline_user_args():
		await harvest("boulder","stone",8)
		await harvest("oak","wood",22)
		craft("campfire",1)
		if not aim(vat): check(false,"outpost cistern is reachable");return
		for i in 2:
			s.action_lock=0
			s._use()
		check(s.bag.count("dirty_water")==2 and s.progress.job_count(s.catalog.quests[1])==0,"drawing raw water gives no purification credit")
		var placed:=false
		var center:=Vector2i(roundi(s.player.position.x),roundi(s.player.position.z))
		for x in range(-3,4):
			for z in range(-3,4):
				var at:=Vector3(center.x+x+0.5,0,center.y+z+0.5)
				var cell:=Vector3i(floori(at.x),ceili(s.stream.ground_at(at)-0.42),floori(at.z))
				if not s.construction.place(cell,"campfire",0,0,s.player.position): continue
				s.ui_command("craft",["clean_water",2,cell])
				s.ui_command("feed_fire",[cell,"wood"])
				s.ui_command("enable",[cell])
				s.clock.advance(15)
				s.construction.simulate(15)
				s.ui_command("collect",[cell])
				placed=true
				break
			if placed:break
		check(placed and s.progress.job_count(s.catalog.quests[1])==2 and s.bag.count("clean_water")>=2,"campfire route boils and collects both genuine samples")
		return
	await harvest("reed_bed","reed_stem",3)
	await harvest("brush","fiber",5)
	await harvest("boulder","stone",3)
	check(s.bag.has_all({"reed_stem":3,"fiber":5,"stone":3}),"collected the pump and filter supplies from physical drops "+str(s.bag.counts))
	craft("filter_pump",1)
	equip("filter_pump")
	if not aim(vat): check(false,"outpost cistern is reachable");return
	for i in 2:
		s.action_lock=0
		s._use()
	check(s.bag.count("filter_pump")==1 and s.progress.job_count(s.catalog.quests[1])>=2 and s.bag.count("clean_water")>=2,"two pump uses consume filters and count genuine production")

func search_caches(beacon: bool) -> void:
	var destination_cell:=home_cell
	if beacon:
		var signal_route:Dictionary=s.beacon_destination()
		destination_cell=WastelandTerrainGen.chunk_at(signal_route.at)
		check(destination_cell.distance_to(home_cell)<24.0 and destination_cell not in WastelandTerrainGen.FIXED,"the final beacon points to a regional site outside historical Gray Bay")
		load_cell(destination_cell)
	else:
		var buildings:=0
		for radius in range(1,12):
			for x in range(-radius,radius+1):
				for z in range(-radius,radius+1):
					if maxi(absi(x),absi(z))!=radius: continue
					var candidate:=home_cell+Vector2i(x,z)
					if not s.stream.generator.site_for(candidate).is_empty():
						load_cell(candidate)
						buildings+=1
			if buildings>=3: break
	# Physics registers newly streamed cabinet colliders on the next fixed step.
	await physics_frame
	await physics_frame
	var diagnostics := {}
	for box in nodes("loot"):
		if beacon and box.get_meta("cell")!=destination_cell:continue
		if bool(box.get_meta("quest",false))!=beacon: continue
		var key: String=box.get_meta("key")
		diagnostics[key]="aim"
		if not aim(box): continue
		s._use()
		diagnostics[key]="use"
		if s.loot_target!=box: continue
		Input.action_press("use")
		s.interaction=s._interaction_trace()
		s._tick_loot(s.loot_full+0.01)
		diagnostics[key]=s.chest_view(key)
		if beacon: s.apply_ui_command("chest_take",[key,"beacon_log",1])
		s.apply_ui_command("chest_all",[box.get_meta("key")])
		s.apply_ui_command("chest_close",[box.get_meta("key")])
		app.close_overlay()
		Input.action_release("use")
		if s.bag.count("beacon_log")>0 if beacon else s.progress.job_count(s.catalog.quests[1])>=4:
			check(true,"recovered beacon from a generated quest cache" if beacon else "searched four separate generated containers")
			return
	check(false,"sufficient reachable generated caches at %s: %s"%[destination_cell,diagnostics])

func build_defense() -> void:
	craft("frame",3)
	check(s.bag.count("frame")>=12,"actual wood crafts enough frames to build the defense")
	var origin:=Vector2i(floori(hunting_ground.x),floori(hunting_ground.z))
	for z in range(origin.y-3,origin.y+5):
		for x in range(origin.x-3,origin.x+8):
			var at:=Vector3(x,0,z)
			s.player.global_position=at+Vector3(0,0,2)
			s.player.position.y=s.stream.ground_at(s.player.global_position)
			var cell:=Vector3i(x,ceili(s.stream.ground_at(at)-0.42),z)
			s.construction.place(cell,"frame",0,0,s.player.global_position)
			if s.progress.job_count(s.catalog.quests[2])>=12:
				check(true,"twelve supported blocks were actually placed")
				return
	check(false,"valid buildable space for twelve blocks")

func fight_patrols() -> void:
	equip("stone_axe")
	for attempt in 180:
		if s.progress.job_count(s.catalog.quests[3])>=18:
			check(true,"eighteen director-spawned infected killed by real melee ray hits")
			return
		at_hunt()
		s.clock.advance(13.0)
		s.hordes.simulate(0.5)
		await physics_frame
		fight_one(false)
		if s.player.health<=0.0: break
	print("Patrol result health=",s.player.health," kills=",s.progress.records.get("kill",0)," actors=",s.hordes.alive.size()," day=",s.clock.day()," elapsed=",s.clock.elapsed)
	check(false,"survived and defeated required patrols")

func at_hunt() -> void:
	s.player.global_position=hunting_ground
	s.player.position.y=s.stream.ground_at(hunting_ground)+0.1
	s.player.velocity=Vector3.ZERO

func fight_one(wave_only: bool) -> bool:
	for enemy: WastelandCreature in s.hordes.alive.duplicate():
		if enemy.hp<=0.0 or enemy.brain.animal or (wave_only and not enemy.wave): continue
		for n in 24:
			if not enemy.active or enemy.hp<=0.0: return true
			if not aim(enemy): break
			swing()
			s.hordes.simulate(0.12)
			if s.player.health<=0.0: return false
	return false

func guard_night() -> void:
	var target:float=(s.clock.next_horde()-1)*24.0+22.01
	if s.clock.hours<target:
		s.clock.advance((target-s.clock.hours)*s.clock.minutes*2.5)
	equip("stone_axe")
	if s.bag.count("coat")>0 and s.bag.gear.body!="coat": s.ui_command("consume",["coat"])
	at_hunt()
	var event_day:=s.clock.event_day()
	var shelter_cell:=s.stream.generator.outpost_beacon_cell(home_cell)
	load_cell(shelter_cell)
	var shelter:WastelandChunk=s.stream.active[shelter_cell]
	var upper:StaticBody3D=shelter.structures["slab/1"][0]
	var fallback:=upper.global_position+Vector3(0,0.28,1)
	var withdrawn:=false
	for i in 1800:
		s.hordes.simulate(STEP)
		s.clock.advance(STEP)
		if i%3==0:
			await physics_frame
			if s.clock.horde_active() and not withdrawn:
				if s.hordes.event_kills>0 and (s.player.health<70 or s.hordes.wave_index>=2):
					s.player.global_position=fallback
					s.player.velocity=Vector3.ZERO
					withdrawn=true
				else:
					fight_one(true)
					at_hunt()
		if s.player.health<=0.0: break
		if s.hordes.survived_recorded==event_day:
			waves_fought=s.hordes.wave_index
			check(waves_fought>0 and s.hordes.event_kills>0 and s.hordes.event_deaths==0 and s.progress.job_count(s.catalog.quests[4])==1,"natural blood moon settles at dawn after fighting actual waves")
			return
	check(false,"blood moon survived to dawn")

func check(ok: bool, label: String) -> void:
	if ok:
		passed+=1
		print("PASS ",label)
	else:
		failures+=1
		printerr("FAIL ",label)
