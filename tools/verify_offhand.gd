extends SceneTree

var checks:=0
var failures:=0
var s:WastelandSession

func _initialize()->void:run.call_deferred()

func check(ok:bool,title:String)->bool:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",title)
	return ok

func aim(point:Vector3)->void:
	var ray:=point-s.player.camera.global_position
	s.player.rotation.y=atan2(-ray.x,-ray.z)
	s.player.pitch=atan2(ray.y,Vector2(ray.x,ray.z).length())
	s.player.eyes.rotation.x=s.player.pitch
	s.player.camera.force_update_transform()

func run()->void:
	WastelandSave.root_override="user://verification/offhand-%d"%OS.get_process_id()
	var flags:=OS.get_cmdline_user_args()
	if "--host" in flags or "--guest" in flags:
		var port:=19491
		for flag in flags:
			if flag.begins_with("--port="):port=int(flag.get_slice("=",1))
		await online("--host" in flags,port)
		print("OFFHAND LAN QA checks=",checks," failures=",failures)
		quit(1 if failures else 0)
		return
	var opts:=WastelandSettings.new()
	opts.load_options()
	s=WastelandSession.new()
	root.add_child(s)
	s.configure(WastelandSave.default_world(),{},1,WastelandCatalog.new(),opts)
	s.simulation_paused=true
	var bag:=s.bag
	var p:=s.player
	check(bag.offhand=="" and not bag.gear.has("legs") and bag.counts.is_empty(),"fresh survivor starts empty-handed and a legacy empty leg slot has no equipment")
	for item:String in ["stone_axe","torch","quilted_pants","canvas_pants","improvised_shield"]:bag.add(item,1)
	s.ui_command("assign",["stone_axe"])
	s.ui_command("offhand",["torch"])
	check(bag.current()=="stone_axe" and bag.offhand=="torch","equip offhand without changing selected primary")
	s.ui_command("swap_hands")
	check(bag.current()=="torch" and bag.offhand=="stone_axe","swap moves both assignments but preserves totals")
	s.ui_command("offhand",["torch"])
	check(bag.current()=="" and bag.offhand=="torch","one torch cannot be held twice")
	bag.add("torch",1)
	check(bag.current()=="torch","two copies can be held in both hands")
	var teammate:=WastelandBag.new(s.catalog)
	teammate.add("torch",1)
	teammate.set_offhand("torch")
	check(bag.current()=="torch" and bag.available_count("torch")==2 and teammate.current()=="","another backpack holding a torch leaves both of this survivor's torches available")
	s.ui_command("offhand",["quilted_pants"])
	check(bag.gear_bonus("warmth")==0,"holding winter trousers grants no worn stat")
	s.ui_command("consume",["quilted_pants"])
	check(bag.offhand=="" and bag.gear.get("legs")=="quilted_pants" and bag.gear_bonus("warmth")==4,"wearing only copy releases it from hand and grants insulation")
	var saved_pose:=p.position
	var old_time:=s.clock.hours
	s.clock.hours=3.0
	p.position=Vector3(saved_pose.x,95,saved_pose.z)
	p.body_temp=37.0
	p.survival_tick=0
	p._survival(1)
	var insulated:=p.body_temp
	s.ui_command("consume",["quilted_pants"])
	p.body_temp=37.0
	p.survival_tick=0
	p._survival(1)
	check(insulated>p.body_temp,"winter trousers reduce actual overnight cooling at altitude")
	p.position=saved_pose
	s.clock.hours=old_time
	s.ui_command("consume",["canvas_pants"])
	check(bag.gear.get("legs")=="canvas_pants" and is_equal_approx(bag.gear_bonus("armor"),0.06),"canvas replaces winter trousers with its own protection")
	var saved:=WastelandBag.new(s.catalog,bag.snapshot())
	check(saved.gear.legs=="canvas_pants" and not WastelandBag.new(s.catalog,{"counts":{},"gear":{"legs":"canvas_pants"}}).gear.has("legs"),"valid leg loadout restores and nonexistent garments do not")
	var avatar:=WastelandPartyAvatar.new()
	root.add_child(avatar)
	avatar.wear_loadout(bag.gear)
	avatar.pose(0.18,2.0,0.8)
	var worn_ok:=true
	for rig in avatar.leg_rigs:
		var leg:=rig.get_node("TrouserLeg") as MeshInstance3D
		var idx:=rig.find_bone("Lower")
		worn_ok=worn_ok and leg.skin!=null and not leg.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES].is_empty() and absf(rig.get_bone_pose_rotation(idx).x)>0.01
	check(worn_ok,"both pant legs have actual skin bindings and animated knee transforms")
	check(WastelandItemArt.icon("canvas_pants",s.catalog.items.canvas_pants).get_image().get_data()!=WastelandItemArt.icon("quilted_pants",s.catalog.items.quilted_pants).get_image().get_data(),"distinct item icons render from actual canvas and quilted garment meshes")
	s.ui_command("consume",["canvas_pants"])
	avatar.wear_loadout(bag.gear)
	check(not avatar.leg_rigs[0].has_node("TrouserLeg") and not avatar.leg_rigs[1].has_node("TrouserLeg"),"unequipping removes both animated pieces")
	avatar.queue_free()
	s.ui_command("offhand",["improvised_shield"])
	s.ui_command("assign",["stone_axe"])
	Input.action_press("alternate")
	p.simulate(0.02,true)
	check(not p.guarding,"primary tool keeps right-click for its charged swing")
	Input.action_release("alternate")
	s.bag.active=7
	p.rotation.y=0
	p.pitch=1.1
	p.eyes.rotation.x=p.pitch
	p.camera.force_update_transform()
	Input.action_press("alternate")
	p.simulate(0.02,true)
	check(p.guarding,"empty main hand forwards free right-click to the shield")
	Input.action_release("alternate")
	if not InputMap.has_action("offhand_use"):InputMap.add_action("offhand_use")
	Input.action_press("offhand_use")
	p.stamina=100
	p.simulate(0.1,true)
	check(p.guarding and p.stamina<100,"holding shield action enters guard with ongoing stamina cost")
	var from:=p.position-p.global_basis.z*2
	var back:=p.position+p.global_basis.z*2
	var before:=p.health
	p.invulnerable=0
	p.damage(12,"claw",from)
	check(is_equal_approx(before-p.health,3) and bag.offhand=="dented_shield" and p.bleed==0,"forward blow is mitigated, avoids wound and degrades only equipped shield")
	before=p.health
	p.invulnerable=0
	p.damage(12,"claw",back)
	check(is_equal_approx(before-p.health,12) and bag.offhand=="dented_shield","rear strike bypasses shield without damaging it")
	var stored:=WastelandBag.new(s.catalog,bag.snapshot())
	check(stored.offhand=="dented_shield" and stored.count("improvised_shield")==0,"shield condition persists as the exact carried item")
	var old_serial:=s.fx.serial
	s.ui_command("discard",["dented_shield"])
	check(bag.offhand=="dented_shield","first discard protects the held shield")
	s.ui_command("discard",["dented_shield"])
	check(s.fx.serial>old_serial and s.fx.drop_records[str(s.fx.serial)].items.get("dented_shield")==1 and bag.offhand=="","discard creates a world drop with the same durability")
	s.fx.take_drop(str(s.fx.serial))
	s.ui_command("offhand",["dented_shield"])
	for i in 2:
		p.invulnerable=0
		p.damage(4,"claw",from)
	check(bag.offhand=="" and not p.guarding and bag.count("cracked_shield")==0,"third successful block breaks the shield and clears the hand")
	Input.action_release("offhand_use")
	bag.add("clean_water",2)
	p.hydration=40
	s.ui_command("offhand",["clean_water"])
	s._use_offhand()
	s._use_offhand()
	check(p.hydration>40 and bag.count("clean_water")==1 and bag.offhand=="clean_water","offhand drink uses the original hydration effect and respects the action cooldown")
	bag.add("frame",1)
	s.ui_command("offhand",["frame"])
	var home:=s.start_position()
	await physics_frame
	await physics_frame
	for i in 12:
		var at:=home+Vector3.FORWARD.rotated(Vector3.UP,TAU*i/12.0)*2.7
		at.y=s.stream.ground_at(at)
		aim(at)
		p.offhand_cooldown=0
		s._use_offhand()
		if bag.count("frame")==0:break
	check(bag.offhand=="" and s.construction.blocks.size()==1,"offhand frame goes through placement ray and consumes one actual item")
	var plot:=home+Vector3.RIGHT*2.5
	plot.y=s.stream.ground_at(plot)
	s.construction.till(plot)
	await physics_frame
	await physics_frame
	bag.add("seed_potato",1)
	s.ui_command("offhand",["seed_potato"])
	var cell:Vector3i=s.construction.crops.keys()[0]
	var actual:Vector3=s.construction.crop_nodes[cell].global_position+Vector3.UP*0.06
	p.position=actual+Vector3.UP*0.22+Vector3.RIGHT*0.55
	aim(actual)
	p.offhand_cooldown=0
	s._use_offhand()
	check(s.construction.crops[cell].seed=="seed_potato" and bag.offhand=="","offhand seed plants through the existing tillage interaction")
	s.ui_command("offhand",["clean_water"])
	s.ui_command("discard",["clean_water"])
	check(bag.offhand=="clean_water","first discard protects the last held bottle")
	s.ui_command("discard",["clean_water"])
	check(bag.offhand=="" and bag.count("clean_water")==0,"dropping final held unit clears offhand")
	s.ui_command("offhand",["torch"])
	s.bag.spend({"torch":1})
	s.player_died(p)
	check(bag.offhand=="" and bag.count("torch")==0,"death drops the held last torch and clears offhand")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	s.queue_free()
	await process_frame
	print("OFFHAND QA checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func until(action:Callable,seconds:=8.0)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<end:
		if action.call():return true
		await process_frame
	return false

func online(host:bool,port:int)->void:
	var game:Node=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.options.storage_path=WastelandSave.root_override+"/options.cfg"
	game.options.appearance="ranger"
	game.set_process_input(false)
	var token:=("offhand-test-%d"%port).md5_text()
	if host:
		await online_host(game,port,token)
	else:
		game.network.local_token=token
		await online_guest(game,port)
	if is_instance_valid(game.session):
		game.session.simulation_paused=true
		await game.session.stream.quiesce()
		if is_instance_valid(game.session.audio): await game.session.audio.finish_playback()
	game.network.stop()
	game.queue_free()
	await process_frame

func online_host(game:Node,port:int,token:String)->void:
	var legacy_bag:=WastelandBag.new(game.catalog)
	legacy_bag.add("torch",1)
	legacy_bag.add("clean_water",4)
	legacy_bag.set_offhand("torch")
	var legacy:Dictionary={
		"settings":game._default_config(),"bag":legacy_bag.snapshot(),
		"hand_queue":[{"id":"torch","amount":1,"inputs":{"wood":1},"done":600.0,"span":2.0}],
		"guests":{token:{"profile":"ranger","health":75.0,"slot":7,"offhand":"torch"}}
	}
	if not check(WastelandSave.write(1,legacy)==OK,"legacy world with one shared bag written to disk"): return
	game.host_world(1,port)
	if not check(await until(func():return game.network.server()),"host opens legacy save"): return
	s=game.session
	s.hordes.next_patrol=INF
	s.hordes.next_herd=INF
	if not check(await until(func():return s.marker_records.any(func(row):return row.name=="bag checked"),18),"legacy guest checks its initial backpack"): return
	var member:WastelandLan.MemberState=game.network.member_with_token(token)
	check(s.bag.count("clean_water")==4 and s.bag.offhand=="torch" and s.hand_queue[0].id=="torch" and member.bag.counts.is_empty() and member.hand_queue.is_empty(),"legacy shared items and unfinished work are kept once in the host save")
	for id:String in ["improvised_shield","quilted_pants","pistol","cloth"]: member.bag.add(id,2 if id=="cloth" else 1)
	member.bag.magazine.pistol=3
	if not check(await until(func():return member.bag.offhand=="improvised_shield" and member.bag.gear.get("legs")=="quilted_pants"),"guest equips trousers and a shield from its own backpack"): return
	s.ui_command("offhand",["improvised_shield"])
	check(s.bag.offhand=="torch" and not s.bag.gear.has("legs"),"host cannot equip the guest's items")
	if not check(await until(func():return member.survivor.guarding and member.avatar.offhand_block and member.avatar.leg_rigs[1].has_node("TrouserLeg")),"guest input raises shield and renders its own trousers on host"): return
	var hp:=member.survivor.health
	member.survivor.invulnerable=0
	member.survivor.damage(12,"claw",member.survivor.position-member.survivor.global_basis.z*2)
	check(is_equal_approx(hp-member.survivor.health,3.0*(1.0-member.bag.gear_bonus("armor"))) and member.bag.offhand=="dented_shield" and s.bag.offhand=="torch","guest receives its own armor bonus and wears its own shield")
	check(await until(func():return not member.survivor.guarding),"releasing dedicated input lowers remote shield")
	if not check(await until(func():return member.survivor.guarding and member.avatar.offhand_id=="dented_shield"),"right-click with idle primary raises guest shield"): return
	game.network._as_member(s,member,func():s.queue_craft("bandage",1,null))
	if not check(member.hand_queue.size()==1 and member.bag.count("cloth")==0,"guest's hand job consumes only that guest's cloth"): return
	member.hand_queue[0].done=s.clock.elapsed+600.0
	var saves:Array[int]=[]
	s.stored.connect(func(slot:int):saves.append(slot))
	s.add_marker(Vector2.ZERO,"guard verified")
	if not check(await until(func():return not saves.is_empty()),"guest's pause menu saves the world to disk"): return
	var saved:=WastelandSave.read(1)
	var guest_save:Dictionary=saved.guests[token]
	check(guest_save.bag.gear.offhand=="dented_shield" and guest_save.bag.gear.legs=="quilted_pants" and guest_save.bag.magazine.pistol==3 and guest_save.hand_queue[0].id=="bandage" and saved.bag.gear.offhand=="torch" and saved.hand_queue[0].id=="torch","manual guest save stores each backpack, magazine, equipment and hand queue separately")
	s.add_marker(Vector2.ZERO,"disk verified")
	if not check(await until(func():return game.network.joined_members().is_empty()),"guest leaves before the room closes"): return
	game.leave_world()
	if not check(await until(func():return game.session.preview_only and not game.network.active()),"host closes the world and destroys the session"): return
	game.host_world(1,port+1)
	if not check(await until(func():return game.network.server() and not game.session.preview_only),"host reopens the world from the same disk slot"): return
	s=game.session
	check(s.bag.count("clean_water")==4 and s.bag.count("dented_shield")==0 and s.hand_queue.size()==1 and s.hand_queue[0].id=="torch","reopened host keeps its original supplies and job")
	if not check(await until(func():return game.network.member_with_token(token)!=null,20),"same guest joins the reopened room"): return
	member=game.network.member_with_token(token)
	if not check(member.hand_queue.size()==1 and member.bag.offhand=="dented_shield" and member.bag.gear.legs=="quilted_pants" and member.bag.magazine.pistol==3,"reopened room restores the guest's equipment and pending craft"): return
	member.hand_queue[0].done=s.clock.elapsed
	if not check(await until(func():return member.bag.count("bandage")==2 and member.hand_queue.is_empty() and s.marker_records.any(func(row):return row.name=="craft received")),"completed craft reaches only its owner's client after rejoining"): return
	check(s.bag.count("bandage")==0 and s.hand_queue.size()==1,"guest completion leaves the host's backpack and queue alone")
	for item:String in s.achievements.CAT_OUTFIT: member.bag.add(item,1)
	if not check(await until(func():return s.progress.achieved.has("catwalk")) and s.achievements.CAT_OUTFIT.all(member.bag.is_worn) and not s.achievements.CAT_OUTFIT.any(s.bag.is_worn),"one guest's complete outfit earns the shared catwalk achievement with the host wearing none of its pieces"): return
	s.add_marker(Vector2.ZERO,"reload verified")
	await until(func():return game.network.joined_members().is_empty())

func online_guest(game:Node,port:int)->void:
	if not check(game.network.connect_to("127.0.0.1",port)==OK,"guest connects to test host"): return
	if not check(await until(func():return is_instance_valid(game.session) and game.session.replica,15),"guest receives initial private state"): return
	s=game.session
	check(s.bag.counts.is_empty() and s.bag.offhand=="" and s.hand_queue.is_empty() and absf(s.player.health-75.0)<1.0,"legacy guest retains its health and starts with no shared items or queued work")
	s.ui_command("marker",[Vector2.ZERO,"bag checked"])
	if not check(await until(func():return s.bag.count("improvised_shield")==1),"test shield arrives in guest's backpack"): return
	s.ui_command("slot",[7])
	s.ui_command("offhand",["improvised_shield"])
	s.ui_command("consume",["quilted_pants"])
	if not check(await until(func():return s.bag.offhand=="improvised_shield" and game.network.replica_avatar(1).offhand_id=="torch" and game.network.replica_avatar(1).offhand_lit and not game.network.replica_avatar(1).leg_rigs[0].has_node("TrouserLeg")),"client sees the host's lit torch and its own distinct trousers"): return
	Input.action_press("offhand_use")
	check(await until(func():return s.bag.offhand=="dented_shield" and s.player.guarding and s.player.hand.offhand_block),"client receives its own guard and wear states")
	Input.action_release("offhand_use")
	await until(func():return not s.player.guarding)
	s.player.pitch=1.15
	Input.action_press("alternate")
	if not check(await until(func():return s.marker_records.any(func(row):return row.name=="guard verified")),"right-click guard crosses actual network inputs"): return
	Input.action_release("alternate")
	game._pause()
	var button:Button
	for widget:Node in game.front.find_children("*","Button",true,false):
		if widget.text=="保存世界": button=widget as Button
	if not check(is_instance_valid(button) and not button.disabled,"guest can save its backpack from the pause menu"): return
	button.pressed.emit()
	if not check(await until(func():return game.front.visible and game.front.menu_notice.text=="世界已保存"),"guest's open pause menu displays the host's successful world save acknowledgement"): return
	game.close_overlay()
	if not check(await until(func():return s.marker_records.any(func(row):return row.name=="disk verified")),"authority confirms the guest's save was read from disk"): return
	game.leave_world()
	if not check(await until(func():return game.session.preview_only and not game.network.active()),"guest returns to title"): return
	var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline and not game.session.replica:
		if not game.network.active():
			game.network.connect_to("127.0.0.1",port+1)
		await create_timer(0.30).timeout
	if not check(game.session.replica,"guest connects to the newly opened room"): return
	s=game.session
	check(s.bag.offhand=="dented_shield" and s.bag.gear.get("legs")=="quilted_pants" and s.bag.magazine.get("pistol")==3 and s.bag.active==7 and s.bag.count("clean_water")==0,"guest restores its own loadout and shortcut from disk")
	if not check(await until(func():return s.bag.count("bandage")==2 and s.hand_queue.is_empty()),"restored hand job pays its guest"): return
	s.ui_command("marker",[Vector2.ZERO,"craft received"])
	if not check(await until(func():return s.achievements.CAT_OUTFIT.all(func(item):return s.bag.count(item)>0)),"guest receives all four outfit pieces in its own backpack"): return
	for item:String in s.achievements.CAT_OUTFIT: s.ui_command("consume",[item])
	check(await until(func():return s.marker_records.any(func(row):return row.name=="reload verified")),"host verified both reopened backpacks")
