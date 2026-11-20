extends "res://tools/verify_lan_discovery.gd"

var s:WastelandSession
const THROW_DECK:=Vector3(9,13,44)

func settings()->Dictionary:
	var cfg:Dictionary=app._default_config()
	cfg.seed=2817
	cfg.start_id="shore"
	cfg.terrain_revision=2
	return cfg

func drop(at:Vector3,items:Dictionary,velocity:Vector3)->String:
	s.fx.add_items(at,items,velocity)
	return str(s.fx.serial)

func steps(count:int)->void:
	for i in count: s.fx.simulate(1.0/60.0)

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--guest" in args or "--host" in args:
		await super.run()
		return
	WastelandSave.root_override="user://verification/drop-motion-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app._enter_world(settings(),{},1,false)
	s=app.session
	s.simulation_paused=true
	await physics_frame
	var base:=s.player.global_position+Vector3.UP*10
	var deck:=WastelandLook.solid(s,Vector3(8,0.12,4),base,Color.GRAY)
	WastelandLook.solid(s,Vector3(0.10,3,4),base+Vector3(1.3,1.5,0),Color.GRAY)
	var ramp:=WastelandLook.solid(s,Vector3(4,0.14,2),base+Vector3(0,1.7,3.5),Color.GRAY)
	ramp.rotation.z=0.49
	await physics_frame
	var id:=drop(base+Vector3(-1,1.3,0),{"stone":7},Vector3(10,0,0))
	steps(120)
	var resting:Vector3=s.fx.drop_records[id].point
	check(resting.x<base.x+1.3 and resting.x>base.x+0.15,"moving pile collides with a thin vertical wall")
	check(absf(resting.y-base.y-0.23)<0.055 and s.fx.drop_records[id].get("resting",false),"pile settles on the upper physical deck")
	steps(120)
	check(resting.distance_to(s.fx.drop_live[id].global_position)<0.005,"settled pickup and saved center stay still")
	var loose:=drop(base+Vector3(-2,0.65,-1),{"fiber":2},Vector3.ZERO)
	var pickup:StaticBody3D=s.fx.drop_live[loose]
	s.player.global_position=base+Vector3(-2,0.13,0.5)
	await physics_frame
	check(not s.player.test_move(s.player.global_transform,Vector3.FORWARD*2.7),"the actual survivor capsule can pass through a pickup")
	s.player.camera.look_at(pickup.global_position)
	s.player.camera.force_update_transform()
	check(s._interaction_trace().get("collider")==pickup and s._trace(3,15,false,true).get("collider")!=pickup,"interaction targets the pile while a melee trace passes through")
	s._use()
	check(not s.fx.drop_records.has(loose) and s.bag.count("fiber")==2,"the normal use action collects the nonblocking pile")
	var roll:=drop(ramp.position+Vector3.UP*0.7+Vector3.RIGHT,{"stone":1},Vector3.ZERO)
	steps(70)
	check(s.fx.drop_records[roll].point.x<ramp.position.x-0.15,"gravity slides material downhill on a sloped collider")
	deck.queue_free()
	await physics_frame
	await physics_frame
	steps(100)
	check(s.fx.drop_records[id].point.y<resting.y-1.0,"removing the supporting deck wakes the pile")
	var buoy:Vector3=s.fx.drop_records.shore_float.point
	s.stream.ensure_landing(buoy)
	s.player.global_position=buoy+Vector3.RIGHT*4
	var lake:=buoy+Vector3.RIGHT*1.8
	check(s.stream.water_at(lake) and s.stream.ground_at(lake)<-0.65,"test lake has actual submerged ground")
	var log_id:=drop(lake+Vector3.UP,{"wood":4},Vector3.ZERO)
	var iron:=drop(lake+Vector3.BACK*0.8+Vector3.UP,{"steel":3},Vector3.ZERO)
	await physics_frame
	steps(360)
	check(absf(s.fx.drop_records[log_id].point.y-0.045)<0.025,"wood rises and rests at the waterline")
	var iron_pos:Vector3=s.fx.drop_records[iron].point
	check(iron_pos.y< -0.5 and absf(iron_pos.y-s.stream.ground_at(iron_pos)-0.17)<0.32,"steel sinks and rests on the lake bed")
	check(s.fx.drop_records.shore_float.point==buoy and s.fx.drop_live.shore_float.get_meta("kind")=="buoy","mission buoy stays anchored with its original pickup")
	var moving:=drop(lake+Vector3.UP*3,{"scrap":9},Vector3(0.3,1,0))
	steps(4)
	var airborne:Dictionary=s.fx.drop_records[moving].duplicate(true)
	check(s.save_now(false)==OK,"save while a pile is airborne")
	await s.stream.quiesce()
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	s.simulation_paused=true
	s.stream.ensure_landing(lake)
	s.fx._resync_drops()
	check(s.fx.drop_records[moving]==airborne,"reloading preserves the same ID, position, momentum and contents")
	s.bag.spend({"fiber":2})
	s.bag.add("sledge",s.bag.capacity()-1)
	s.bag.add("scrap",s.bag.stack_size("scrap")-2)
	s.fx.take_drop(moving)
	check(s.fx.drop_records[moving].items.scrap==7 and s.bag.count("scrap")==s.bag.stack_size("scrap"),"partial pickup preserves seven units in the same moving pile")
	s.bag.spend({"sledge":1})
	s.fx.take_drop(moving)
	s.fx.take_drop(moving)
	check(not s.fx.drop_records.has(moving) and s.bag.count("scrap")==s.bag.stack_size("scrap")+7,"repeat pickup cannot duplicate a finished transfer")
	s.bag=WastelandBag.new(s.catalog)
	var boat:WastelandVehicle=s.vehicles.landing_boat
	s.player.global_position=boat.global_position+Vector3.RIGHT
	for material in WastelandSession.BOAT_REPAIR: s.bag.add(material,WastelandSession.BOAT_REPAIR[material])
	s.ui_command("repair_vehicle",["landing_boat"])
	s.player.ride(boat)
	boat.global_position=buoy+Vector3(0,-0.15,2.6)
	s.player.global_position=boat.global_position+Vector3.UP*boat.seat_height()
	s.player.camera.look_at(buoy+Vector3.UP*0.45)
	await physics_frame
	s._use()
	s.fx.take_drop("shore_float")
	check(s.player.mount_vehicle==boat and s.bag.count("tape")==2 and s.progress.records.get("salvage_buoy",0)==1 and not s.fx.drop_records.has("shore_float"),"interacting from the helm claims buoy cargo and its reward exactly once")
	await check_proximity(iron,iron_pos)
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	print("DROP MOTION failures=",failures)
	quit(1 if failures else 0)

func check_proximity(iron:String,iron_pos:Vector3)->void:
	s.player.dismount(true)
	s.bag=WastelandBag.new(s.catalog)
	s.player.global_position=iron_pos
	s.fx.collect_nearby()
	check(not s.fx.drop_records.has(iron) and s.bag.count("steel")==3,"diving to a submerged pile collects its metal")
	var buoy:Vector3=s.fx.drop_records.survey_float.point
	s.player.global_position=buoy
	s.fx._resync_drops()
	s.fx.collect_nearby()
	check(s.fx.drop_records.has("survey_float"),"proximity leaves an anchored mission buoy for manual salvage")
	var base:=s.player.global_position+Vector3.UP*8
	s.stream.ensure_landing(base)
	WastelandLook.solid(s,Vector3(8,0.12,8),base,Color.GRAY)
	WastelandLook.solid(s,Vector3(0.1,3,3),base+Vector3(0.65,1.5,0),Color.GRAY)
	s.player.global_position=base+Vector3.UP*0.08
	await physics_frame
	var open:=drop(base+Vector3(-0.8,0.3,0.5),{"fiber":4},Vector3.ZERO)
	var blocked:=drop(base+Vector3(1.1,0.3,0),{"stone":3},Vector3.ZERO)
	var below:=drop(base+Vector3.DOWN*0.35,{"scrap":2},Vector3.ZERO)
	var far:=drop(base+Vector3.LEFT*3+Vector3.UP*0.3,{"wood":2},Vector3.ZERO)
	s.next_hint=0.0
	s.simulation_paused=false
	for i in 3: await physics_frame
	s.simulation_paused=true
	check(not s.fx.drop_records.has(open) and s.bag.count("fiber")==4,"ordinary gameplay picks up a nearby pile without a use press")
	check(s.fx.drop_records.has(blocked) and s.fx.drop_records.has(below) and s.fx.drop_records.has(far),"wall, floor and distance each prevent pickup")
	s.bag=WastelandBag.new(s.catalog)
	s.bag.add("sledge",s.bag.capacity()-1)
	s.bag.add("stone",s.bag.stack_size("stone")-1)
	s.player.global_position=base+Vector3(1.25,0.08,0)
	s.fx.collect_nearby()
	s.fx.collect_nearby()
	check(s.fx.drop_records[blocked].items.stone==2 and s.bag.count("stone")==s.bag.stack_size("stone"),"walking around the wall takes only what fits and preserves a full-bag remainder")
	s.bag.spend({"sledge":1})
	s.fx.collect_nearby()
	check(not s.fx.drop_records.has(blocked) and s.bag.count("stone")==s.bag.stack_size("stone")+2,"making space collects the remaining two exactly once")
	s.bag=WastelandBag.new(s.catalog)
	s.bag.add("stone",3)
	s.player.rotation.y=PI*0.5
	s.player.pitch=0.0
	s.player.eyes.rotation.x=0.0
	s.discard("stone")
	var thrown:=str(s.fx.serial)
	s.fx.collect_nearby()
	s.clock.elapsed+=1.2
	steps(100)
	s.fx.collect_nearby()
	check(s.bag.count("stone")==2 and s.fx.drop_records.has(thrown)
		and s.player.global_position.distance_to(s.fx.drop_records[thrown].point)<1.0,
		"a stone thrown against the wall stays at the stationary player's feet")
	check(s.save_now(false)==OK,"save with a newly discarded item")
	await s.stream.quiesce()
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	s.simulation_paused=true
	s.fx._resync_drops()
	s.fx.collect_nearby()
	check(s.bag.count("stone")==2 and s.fx.drop_records.has(thrown),"reloading preserves discard protection")
	s.player.global_position+=Vector3.RIGHT*3.0
	s.fx.collect_nearby()
	s.player.global_position=s.fx.drop_records[thrown].point
	s.fx.collect_nearby()
	check(s.bag.count("stone")==3 and not s.fx.drop_records.has(thrown),"walking away and back recovers a discarded item")

func host()->void:
	app._enter_world(settings(),{},1,false)
	s=app.session
	WastelandLook.solid(s,Vector3(14,0.2,14),THROW_DECK,Color.GRAY)
	s.player.global_position=THROW_DECK+Vector3(-3,0.3,1)
	if not check(app.network.listen(port)==OK,"motion host listens"): return
	if not check(await until(func(): return is_instance_valid(app.network.member)),"motion guest joined"): return
	app.network.member.global_position=THROW_DECK+Vector3(-0.55,0.3,1)
	app.network.member.velocity=Vector3.ZERO
	var at:=THROW_DECK+Vector3(3.65,9,1)
	var id:=drop(at,{"stone":7},Vector3.ZERO)
	if not check(await until(func(): return FileAccess.file_exists(ticket)),"guest observed moving and settled authoritative snapshots"): return
	if not check(await until(func(): return not s.fx.drop_records.has(id) and s.bag.count("stone")==7),"guest's walking input collects seven stones authoritatively"): return
	check(s.bag.bar[0]=="stone" and s.player.global_position.distance_to(at-Vector3.UP*9)>5.0 and app.network.member.global_position.x>THROW_DECK.x+1.4,"only the guest approached and the first slot now holds the stone")
	var shared:=THROW_DECK+Vector3(0,0.29,-3.0)
	var shared_id:=drop(shared,{"wood":5,"stone":3},Vector3.ZERO)
	if not check(await until(func(): return FileAccess.file_exists(ticket+"both_waiting")),"guest sees second pile before either player can reach it"): return
	for avatar:WastelandSurvivor in [s.player,app.network.member]:
		avatar.global_position=shared+Vector3.RIGHT*(-0.63 if avatar==s.player else 0.63)
		avatar.velocity=Vector3.ZERO
	if not check(await until(func(): return not s.fx.drop_live.has(shared_id) and not s.fx.drop_records.has(shared_id)),"one pile disappears with both players inside pickup range"): return
	check(s.bag.count("wood")==5 and s.bag.count("stone")==10 and s.bag.bar[0]=="stone" and s.bag.bar[1]=="wood","host credits mixed pile once, reuses the existing shortcut and fills the next one")
	if not check(await until(func(): return FileAccess.file_exists(ticket+"both_received")),"guest confirmed the same bag, slots and removed collider"): return
	s.player.global_position=THROW_DECK+Vector3(-4.5,0.3,1)
	app.network.member.global_position=THROW_DECK+Vector3(0.5,0.3,1)
	app.network.member.velocity=Vector3.ZERO
	s.bag.add("stone_axe",1)
	s.bag.assign("stone_axe",0)
	s.bag.active=0
	if not check(await until(func(): return FileAccess.file_exists(ticket+"guarded")),"guest tested the owner's equipped axe"): return
	check(s.bag.count("stone_axe")==1 and not axe_pile(),"guest requests left the owner's one equipped axe intact")
	s.bag.active=1
	stage("owner_switched")
	if not check(await until(func(): return app.network.member_slot==0),"guest equipped the axe after owner switched away"): return
	s.ui_command("discard",["stone_axe",true])
	s.ui_command("discard",["stone_axe",true])
	check(app.hud.toast.contains("队友主手") and s.bag.count("stone_axe")==1,"owner cannot discard the guest's one equipped axe either")
	stage("guest_can_throw")
	if not check(await until(func(): return FileAccess.file_exists(ticket+"returned")),"guest completed a confirmed G throw and E pickup"): return
	check(s.bag.count("stone_axe")==1 and axe_pile()=="","host finishes with one axe in the bag and no duplicate on the ground")
	var buoy:Vector3=s.fx.drop_records.shore_float.point
	s.stream.ensure_landing(buoy)
	buoy_platform(buoy)
	app.network.member.global_position=buoy+Vector3(1.18,-0.23,0)
	app.network.member.velocity=Vector3.ZERO
	stage("buoy")
	if not check(await until(func(): return FileAccess.file_exists(ticket+"buoy_manual")),"guest stood beside the original mission buoy without automatic salvage"): return
	if not check(await until(func(): return not s.fx.drop_records.has("shore_float") and s.progress.records.get("salvage_buoy",0)==1),"explicit guest use salvages the buoy exactly once on the authority"): return
	if not check(await until(func(): return FileAccess.file_exists(ticket+"buoy_done")),"guest receives the manual salvage and removal"): return
	var expected:=s.bag.bar.duplicate()
	check(s.save_now(false)==OK,"save shared pickups and manual buoy reward")
	app.network.stop()
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	check(s.bag.bar==expected and s.bag.count("stone")==10 and s.bag.count("wood")==5 and s.bag.count("tape")==2 and s.bag.count("stone_axe")==1,"disk reload retains shared inventory quantities and shortcut assignments")
	check(not s.fx.drop_records.has(id) and not s.fx.drop_records.has(shared_id) and not s.fx.drop_records.has("shore_float") and s.fx.drop_records.has("survey_float"),"only the unclaimed buoy survives disk reload")

func buoy_platform(buoy:Vector3)->void:
	WastelandLook.solid(s,Vector3(1.4,0.14,1.6),buoy+Vector3(1.18,-0.38,0),Color.GRAY)

func stage(label:String)->void:
	var output:=FileAccess.open(ticket+label,FileAccess.WRITE)
	output.store_line(label)
	output.close()

func press_key(code:Key)->void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.keycode=code
		event.pressed=down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for i in 4: await physics_frame

func axe_pile()->String:
	for id in s.fx.drop_records:
		if s.fx.drop_records[id].items.get("stone_axe",0)>0: return str(id)
	return ""

func guest()->void:
	if not check(app.network.connect_to("127.0.0.1",port)==OK,"motion guest connects"): return
	if not check(await until(func(): return app.session.replica),"guest joins the flat-platform test world"): return
	s=app.session
	WastelandLook.solid(s,Vector3(14,0.2,14),THROW_DECK,Color.GRAY)
	if not check(await until(func(): return s.fx.drop_records.has("1")),"guest sees the authoritative pile"): return
	var start:Vector3=s.fx.drop_records["1"].point
	if not check(await until(func(): return s.fx.drop_records["1"].get("resting",false)),"guest receives the resting state"): return
	var end:Vector3=s.fx.drop_records["1"].point
	check(start.y>end.y+1 and s.fx.drop_live["1"].global_position.distance_to(end)<0.01,"guest pickup collider comes to rest at the authoritative lower center")
	var flag:=FileAccess.open(ticket,FileAccess.WRITE)
	flag.store_line("settled")
	flag.close()
	s.player.rotation.y=0.0
	Input.action_press("right")
	var collected:=await until(func(): return not s.fx.drop_records.has("1") and not s.fx.drop_live.has("1") and s.bag.count("stone")==7,5500)
	Input.action_release("right")
	if not check(collected and s.bag.bar[0]=="stone","walking sideways without use auto-collects the pile and fills the first shared shortcut"): return
	if not check(await until(func(): return s.fx.drop_live.has("2") and s.fx.drop_records.has("2")),"guest sees mixed pile before simultaneous pickup"): return
	stage("both_waiting")
	if not check(await until(func(): return not s.fx.drop_records.has("2") and not s.fx.drop_live.has("2") and s.bag.count("stone")==10 and s.bag.count("wood")==5 and s.bag.bar[0]=="stone" and s.bag.bar[1]=="wood"),"guest receives exactly one mixed transfer and identical shortcuts"): return
	stage("both_received")
	if not check(await until(func(): return s.bag.current()=="stone_axe"),"guest sees the same single axe selected by both players"): return
	await press_key(KEY_G)
	await press_key(KEY_G)
	if not check(await until(func(): return app.hud.toast.contains("队友主手")),"two physical G presses cannot drop the owner's equipped axe"): return
	s.ui_command("slot",[1])
	if not check(await until(func(): return s.bag.active==1),"guest changes to a different active slot"): return
	app.hud.say("",0)
	s.ui_command("discard",["stone_axe",true])
	s.ui_command("discard",["stone_axe",true])
	if not check(await until(func(): return app.hud.toast.contains("队友主手")) and s.bag.count("stone_axe")==1,"explicit bag confirmation from a different slot still protects owner"): return
	stage("guarded")
	if not await until(func(): return FileAccess.file_exists(ticket+"owner_switched")): return
	s.ui_command("slot",[0])
	if not await until(func(): return s.bag.active==0 and FileAccess.file_exists(ticket+"guest_can_throw")): return
	await press_key(KEY_G)
	if not check(await until(func(): return app.hud.toast.contains("再次丢弃")) and s.bag.count("stone_axe")==1,"first G requests confirmation for the guest's own last axe"): return
	await press_key(KEY_G)
	if not check(await until(func(): return axe_pile()!="" and s.bag.count("stone_axe")==0),"confirmed second G creates a physical axe on both peers"): return
	var thrown:=axe_pile()
	if not check(await until(func(): return s.fx.drop_records[thrown].get("resting",false)),"the thrown axe settles"): return
	var aim_at_axe:=func():
		var aim:Vector3=s.fx.drop_records[thrown].point-s.player.camera.global_position
		s.player.rotation.y=atan2(-aim.x,-aim.z)
		s.player.pitch=atan2(aim.y,Vector2(aim.x,aim.z).length())
		s.player.eyes.rotation.x=s.player.pitch
		s.player.camera.force_update_transform()
		return s.hint.contains("拾取") and s._interaction_trace().get("collider")==s.fx.drop_live[thrown]
	if not check(await until(aim_at_axe,3000),"guest and authority aim at the same settled axe"):
		print("Aim from ",s.player.camera.global_position," to ",s.fx.drop_records[thrown].point," hint=",s.hint," hit=",s._interaction_trace().get("collider"))
		return
	await press_key(KEY_E)
	if not check(await until(func(): return not s.fx.drop_records.has(thrown) and s.bag.count("stone_axe")==1),"physical E restores the axe once and clears the guest pickup"): return
	stage("returned")
	if not check(await until(func(): return FileAccess.file_exists(ticket+"buoy")),"host staged the original mission buoy"): return
	var buoy:Vector3=s.fx.drop_records.shore_float.point
	s.stream.ensure_landing(buoy)
	buoy_platform(buoy)
	if not check(await until(func(): return s.player.global_position.distance_to(buoy)<1.6),"guest is within automatic pickup radius of buoy"): return
	await create_timer(0.56).timeout
	if not check(s.fx.drop_live.has("shore_float") and s.fx.drop_records.has("shore_float") and s.bag.count("tape")==0,"proximity preserves buoy and gives no cargo"): return
	var aim_at_buoy:=func():
		var aim:Vector3=buoy+Vector3.UP*0.23-s.player.camera.global_position
		s.player.rotation.y=atan2(-aim.x,-aim.z)
		s.player.pitch=atan2(aim.y,Vector2(aim.x,aim.z).length())
		s.player.eyes.rotation.x=s.player.pitch
		s.player.camera.force_update_transform()
		return s._interaction_trace().get("collider")==s.fx.drop_live.shore_float and s.hint.contains("打捞")
	if not check(await until(aim_at_buoy,4500),"guest aims at live buoy and sees salvage interaction"): return
	stage("buoy_manual")
	await press_key(KEY_E)
	if not check(await until(func(): return not s.fx.drop_records.has("shore_float") and not s.fx.drop_live.has("shore_float") and s.bag.count("tape")==2 and s.progress.records.get("salvage_buoy",0)==1),"physical E awards buoy cargo and synchronizes its removal"): return
	stage("buoy_done")
	await create_timer(0.65).timeout
