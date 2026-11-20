extends SceneTree

var checks:=0
var failures:=0
var s:WastelandSession

func _initialize()->void:run.call_deferred()

func check(ok:bool,title:String)->void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",title)

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
	bag.partner_offhands=["torch"]
	check(bag.current()=="" and not bag.spend({"torch":2}),"other player's offhand reservation removes a unit from usable inventory")
	bag.partner_offhands=[]
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
	game.set_process_input(false)
	if host:
		game._enter_world(game._default_config(),{},1,false)
		s=game.session
		s.hordes.next_patrol=INF
		s.hordes.next_herd=INF
		for id:String in ["torch","improvised_shield","quilted_pants"]:s.bag.add(id,1)
		s.ui_command("offhand",["torch"])
		check(game.network.listen(port)==OK,"two peers use separate offhands")
		if await until(func():return not game.network.joined_members().is_empty()):
			var guest:WastelandSurvivor=game.network.joined_members()[0].survivor
			check(await until(func():return game.network.joined_members()[0].offhand=="improvised_shield" and s.bag.gear.get("legs")=="quilted_pants"),"guest equips a genuine leg slot and a private left hand")
			s.ui_command("offhand",["improvised_shield"])
			check(s.bag.offhand=="torch" and s.bag.partner_offhands==["improvised_shield"],"host cannot claim the guest's only shield")
			check(await until(func():return guest.guarding and game.network.joined_members()[0].avatar.offhand_block and game.network.joined_members()[0].avatar.leg_rigs[1].has_node("TrouserLeg")),"dedicated guest input raises shield and renders worn legs on host")
			var hp:=guest.health
			guest.invulnerable=0
			guest.damage(12,"claw",guest.position-guest.global_basis.z*2)
			check(is_equal_approx(hp-guest.health,3.0*(1.0-s.bag.gear_bonus("armor"))) and game.network.joined_members()[0].offhand=="dented_shield" and s.bag.offhand=="torch","authority combines shield and worn trousers and wears only guest shield")
			check(await until(func():return not guest.guarding),"releasing dedicated input lowers remote shield")
			check(await until(func():return guest.guarding and game.network.joined_members()[0].avatar.offhand_id=="dented_shield"),"right-click with idle primary raises guest shield")
			s.add_marker(Vector2.ZERO,"guard verified")
			var token:String=game.network.joined_members()[0].token
			check(s.save_now(false)==OK and WastelandSave.read(1).guests[token].offhand=="dented_shield" and WastelandSave.read(1).bag.gear.offhand=="torch","save uses independent owner and member slots")
			check(await until(func():return game.network.joined_members().is_empty()),"guest disconnect releases reservation")
			check(await until(func():return not game.network.joined_members().is_empty() and game.network.joined_members()[0].offhand=="dented_shield",12),"returning guest reclaims its worn shield")
			await until(func():return game.network.joined_members().is_empty())
	else:
		check(game.network.connect_to("127.0.0.1",port)==OK,"guest connects to test host")
		if await until(func():return is_instance_valid(game.session) and game.session.replica):
			s=game.session
			check(s.bag.offhand=="" and s.bag.current()=="","new guest has empty offhand and primary")
			s.ui_command("offhand",["torch"])
			s.ui_command("offhand",["improvised_shield"])
			s.ui_command("consume",["quilted_pants"])
			check(await until(func():return s.bag.offhand=="improvised_shield" and game.network.replica_avatar(1).offhand_id=="torch" and game.network.replica_avatar(1).offhand_lit and game.network.replica_avatar(1).leg_rigs[0].has_node("TrouserLeg")),"client displays a lit host torch and shared trousers beside its own shield")
			Input.action_press("offhand_use")
			check(await until(func():return s.bag.offhand=="dented_shield" and s.player.guarding and s.player.hand.offhand_block),"client receives its own shield guard and wear states")
			Input.action_release("offhand_use")
			await until(func():return not s.player.guarding)
			s.player.pitch=1.15
			Input.action_press("alternate")
			check(await until(func():return s.marker_records.any(func(row):return row.name=="guard verified")),"right-click guard crosses actual network inputs")
			Input.action_release("alternate")
			game.network.stop()
			game._show_title()
			await create_timer(0.6).timeout
			game.network.connect_to("127.0.0.1",port)
			check(await until(func():return is_instance_valid(game.session) and game.session.replica and game.session.bag.offhand=="dented_shield" and game.network.replica_avatar(1).offhand_id=="torch",12),"reconnect restores personal shield and remote host torch")
			s=game.session
	if is_instance_valid(s):
		s.simulation_paused=true
		await s.stream.quiesce()
		await s.audio.finish_playback()
	game.network.stop()
	game.queue_free()
	await process_frame
