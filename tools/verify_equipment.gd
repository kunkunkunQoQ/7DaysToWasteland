extends SceneTree

const LOADOUT := {"head":"hardhat","body":"oilskin_vest","hands":"work_gloves","feet":"trail_boots"}
const RECIPES := ["field_sickle","reed_spear","iron_pick","work_gloves","trail_boots","smelt_ore","salvage_wrench","baton","field_crossbow","oilskin_vest","hardhat","alpine_cap","sun_cape","canvas_pants","quilted_pants","improvised_shield"]
var app:Node
var session:WastelandSession
var passed:=0
var failed:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,detail:String)->void:
	if ok:
		passed+=1
		print("PASS ",detail)
	else:
		failed+=1
		printerr("FAIL ",detail)

func run()->void:
	WastelandSave.root_override="user://verification/equipment-%s"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	app._enter_world(app._default_config(),{},1,true)
	session=app.session
	for i in 35: await physics_frame
	var old:=WastelandBag.new(session.catalog,{"counts":{"coat":1},"armor":"coat"})
	check(old.gear=={"head":"","body":"coat","hands":"","feet":""},"legacy armor migrates into the torso slot")
	var invalid:=WastelandBag.new(session.catalog,{"counts":{"coat":1},"gear":{"head":"coat","feet":"trail_boots"}})
	check(invalid.gear.head=="" and invalid.gear.feet=="","invalid and unowned equipment are removed on load")
	test_crafting()
	await test_loadout()
	test_bonuses()
	test_climate_clothing()
	test_crossbow()
	await test_portraits()
	await test_field_gear()
	test_losses()
	session.simulation_paused=true
	await session.stream.quiesce()
	app._remove_session()
	app.queue_free()
	await process_frame
	var cleanup_deadline:=Time.get_ticks_msec()+450
	while Time.get_ticks_msec()<cleanup_deadline: await process_frame
	WastelandSave.delete_slot(1)
	print("EQUIPMENT QA passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)

func test_field_gear()->void:
	session.simulation_paused=true
	var player:=session.player
	var previous:=player.transform
	var original_eyes:=player.eyes.transform
	for id in ["filter_pump","field_glasses"]:
		check(WastelandItemArt.mesh(id,session.catalog.items[id]).get_faces().size()>30 and WastelandItemArt.icon(id,session.catalog.items[id]).get_width()>20,"distinct held model and inventory icon for "+id)
	var water:=Vector3(12,0,-48)
	session.stream.ensure_landing(water)
	player.global_position=water+Vector3.UP*0.48
	player.eyes.rotation.x=-1.45
	session.bag.assign("filter_pump",session.bag.active)
	session.bag.spend({"fiber":session.bag.count("fiber")})
	var bottles:=session.bag.count("clean_water")
	await physics_frame
	session.action_lock=0
	session._use()
	check(session.bag.count("clean_water")==bottles,"drawing water with a spent filter requires a fibre refill")
	session.bag.add("fiber",2)
	session.action_lock=0
	session._use()
	check(session.bag.count("fiber")==1 and session.bag.count("clean_water")==bottles+1 and session.bag.count("filter_pump")==1,"water interaction produces safe water, spends one fibre and retains pump")
	session.bag.assign("field_glasses",session.bag.active)
	player.global_position=Vector3(0,80,0)
	player.rotation=Vector3.ZERO
	player.eyes.rotation=Vector3.ZERO
	var target:=player.camera.global_position+Vector3.FORWARD*60.0-Vector3.UP*0.6
	var spawned:=session.hordes._spawn("stag",target,false)
	await physics_frame
	await physics_frame
	check(spawned and not session._interaction_trace().get("collider") is WastelandCreature,"animal at sixty metres is outside normal observation range")
	Input.action_press("alternate")
	player.update_optics(0.4,true)
	session._use()
	check(player.camera.fov<30.0 and not player.hand.visible and session.progress.records.has("observe_stag"),"three-power optics record the distant deer through the normal interaction")
	Input.action_release("alternate")
	player.update_optics(0.4,false)
	check(is_equal_approx(player.camera.fov,76.0) and player.hand.visible,"lowering the optics restores the player's normal view and held model")
	player.transform=previous
	player.eyes.transform=original_eyes

func place_station(id:String)->Variant:
	var start:=session.player.global_position
	session.bag.add(id,1)
	for z in range(-3,4):
		for x in range(-3,4):
			var p:=Vector3(floorf(start.x)+x+0.5,0,floorf(start.z)+z+0.5)
			var ground:=session.stream.ground_at(p)
			var cell:=Vector3i(floori(p.x),ceili(ground-0.42),floori(p.z))
			if ground>0.3 and session.construction.can_place(cell,start,id) and session.construction.place(cell,id,0,0,start):
				return cell
	return null

func heat_station(cell:Variant,inputs:Dictionary)->void:
	if cell==null: return
	var row:Dictionary=session.construction.blocks[cell]
	if not WastelandSession.Fire.thermal(row): return
	session.bag.add("coal",1)
	session.ui_command("feed_fire",[cell,"coal"])
	if not row.enabled: session.ui_command("enable",[cell])
	for id:String in inputs:
		if not WastelandSession.Fire.uses_stock(row,id): continue
		while int(row.get("molten",{}).get(id,0))<int(inputs[id]) and session.bag.count(id)>0:
			session.ui_command("smelt_input",[cell,id])
			if row.get("smelt_input",{}).is_empty(): break
			session.clock.advance(20.0)
			session.construction.simulate(20.0)

func test_crafting()->void:
	var stations:={"hand":null,"bench":place_station("bench"),"forge":place_station("forge")}
	check(stations.bench!=null and stations.forge!=null,"bench and forge are placed within interaction range")
	for key:String in RECIPES+["field_glasses","filter_pump"]:
		var recipe:Dictionary=session.catalog.recipes[key]
		var cell:Variant=stations[recipe.station]
		if cell==null and recipe.station!="hand": continue
		for input:String in recipe.inputs: session.bag.add(input,recipe.inputs[input])
		heat_station(cell,recipe.inputs)
		var record:Dictionary={} if cell==null else session.construction.blocks[cell]
		var before:={}
		for input:String in recipe.inputs: before[input]=WastelandSession.Fire.available(session.bag,record,input)
		session.ui_command("craft",[key,1,cell])
		var queue:Array=session.hand_queue if cell==null else session.construction.blocks[cell].queue
		check(queue.size()==1 and queue[0].id==recipe.id,"UI queues the correct result for "+key)
		if queue.is_empty(): continue
		var consumed:=true
		for input:String in recipe.inputs:
			consumed=consumed and WastelandSession.Fire.available(session.bag,record,input)==int(before[input])-int(recipe.inputs[input])
		check(consumed,"recipe consumes its stated ingredients for "+key)
		session.clock.elapsed=float(queue[0].done)+0.01
		if cell==null: session._finish_crafting()
		else:
			session.construction.simulate(float(recipe.seconds)+0.5)
			session.ui_command("collect",[cell])
		check(session.bag.count(recipe.id)==int(before.get(recipe.id,0))+int(recipe.amount),"player collects completed "+key)
	check(session.bag.count("ingot")>=6 and not session.bag.counts.has("smelt_ore"),"forge produces six usable iron ingots")

func equip(id:String)->void:
	session.ui_command("consume",[id])

func button_with_text(caption:String)->Button:
	for button:Button in app.panels.content.find_children("*","Button",true,false):
		if button.text==caption: return button
	return null

func test_loadout()->void:
	app.open_panel("bag")
	await process_frame
	var use_button:=button_with_text("使用／装备所选")
	check(use_button!=null,"bag provides the equipment action")
	for id:String in LOADOUT.values():
		for tile:Button in app.panels.inventory_buttons:
			if tile.get_meta("item")==id:
				tile.pressed.emit()
				if use_button: use_button.pressed.emit()
				break
	app.close_overlay()
	check(session.bag.gear==LOADOUT,"inventory use fills four independent slots")
	var restored:=WastelandBag.new(session.catalog,session.bag.snapshot())
	check(restored.gear==LOADOUT,"all four slots survive save and reload")
	session.bag.add("coat",1)
	equip("coat")
	check(session.bag.armor=="coat" and session.bag.gear.head=="hardhat" and session.bag.gear.hands=="work_gloves" and session.bag.gear.feet=="trail_boots","changing torso retains the other three slots")
	equip("coat")
	check(session.bag.armor=="" and session.bag.count("coat")==1,"unequip leaves the item in the bag")
	equip("oilskin_vest")

func test_bonuses()->void:
	var p:=session.player
	var health:=p.health
	p.invulnerable=0
	p.damage(20,"test")
	check(is_equal_approx(health-p.health,15),"all four protection values reduce an actual hit by 25 percent")
	var stamina:=p.stamina
	session._melee(session.catalog.items.iron_pick,1)
	check(is_equal_approx(stamina-p.stamina,5.6*0.84),"work gloves reduce stamina spent on a pick swing")
	Input.action_press("sprint")
	p.stamina=80
	p._walk(0.10,Vector2.UP,true)
	Input.action_release("sprint")
	check(p.sprinting and is_equal_approx(80-p.stamina,1.36*0.86),"boots reduce stamina spent on a sprint")
	session.atmosphere.rain_strength=1
	p.wet=0.50
	p.survival_tick=0
	p._survival(1)
	var protected:=p.wet
	equip("oilskin_vest")
	p.wet=0.50
	p._survival(1)
	check(p.wet>protected,"oilskin reduces rain exposure in the survival tick")
	equip("oilskin_vest")

func test_climate_clothing()->void:
	var player:=session.player
	var origin:=player.global_position
	var hours:=session.clock.hours
	var previous_temp:=player.body_temp
	var previous_water:=player.hydration
	var terrain:=session.stream.generator
	for region:String in ["alpine","desert"]:
		var site:=Vector3.INF
		for z in range(-2200,2200,80):
			for x in range(-2200,2200,80):
				if terrain.region_kind(x,z)!=region: continue
				var y:=terrain.ground(x,z)
				if region=="alpine" and y<45 or region=="desert" and (y>20 or y<1): continue
				site=Vector3(x,y+1,z)
				break
			if site.is_finite(): break
		check(site.is_finite(),"find real "+region+" test climate")
		if not site.is_finite(): continue
		player.global_position=site
		session.clock.hours=3.0 if region=="alpine" else 15.0
		var counter:=Vector2.ZERO
		for geared:bool in [false,true]:
			if geared: equip("alpine_cap" if region=="alpine" else "sun_cape")
			player.wet=0
			player.body_temp=37
			player.hydration=95
			player.survival_tick=0
			player._survival(1)
			if not geared: counter=Vector2(player.body_temp,player.hydration)
			elif region=="alpine": check(player.body_temp>counter.x+0.01,"soft cap slows cooling in alpine night air")
			else: check(player.body_temp<counter.x and player.hydration>counter.y,"cape reduces both desert heat and water loss")
	check(session.save_now(false)==OK,"climate outfit writes to save")
	var saved:=WastelandSave.read(1)
	var restored:=WastelandBag.new(session.catalog,saved.bag)
	check(restored.gear.head=="alpine_cap" and restored.gear.body=="sun_cape","soft cap and cape survive disk serialization")
	for id:String in ["alpine_cap","sun_cape"]:
		check(WastelandItemArt.icon(id,session.catalog.items[id]).get_image().get_used_rect().has_area(),"visible gear icon for "+id)
		equip(id)
	check(session.bag.gear.head=="" and session.bag.gear.body=="","both climate items can be removed")
	equip("hardhat")
	equip("oilskin_vest")
	player.global_position=origin
	session.clock.hours=hours
	player.body_temp=previous_temp
	player.hydration=previous_water

func test_crossbow()->void:
	var id:="field_crossbow"
	var hand:=session.player.hand
	session.ui_command("assign",[id])
	session.player.simulate(0.016,false)
	check(session.bag.current()==id and hand.model_id==id and hand.muzzle==null and is_instance_valid(hand.crossbow_bolt) and not hand.crossbow_bolt.visible,"equipped empty crossbow has no bolt or muzzle flash")
	session.bag.add("arrow",1)
	Input.action_press("fire")
	session.action_lock=0
	session._process_controls(0.016)
	Input.action_release("fire")
	check(session.bag.count("arrow")==1 and session.reload_id==id,"reload starts without spending the arrow early")
	session._tick_reload(session.reload_span+0.01)
	session.player.simulate(0.016,false)
	check(session.bag.count("arrow")==0 and session.bag.magazine.get(id,0)==1 and hand.crossbow_bolt.visible,"finished reload chambers exactly one arrow and presents it")
	var serial:=hand.shot_serial
	Input.action_press("fire")
	session.action_lock=0
	session._process_controls(0.016)
	Input.action_release("fire")
	check(hand.shot_serial==serial+1 and session.bag.magazine[id]==0 and not hand.crossbow_bolt.visible,"one shot empties and hides the bolt")
	Input.action_press("fire")
	session.action_lock=0
	session._process_controls(0.016)
	Input.action_release("fire")
	check(hand.shot_serial==serial+1 and session.reload_id=="","an empty crossbow cannot shoot or reload without arrows")

func test_portraits()->void:
	app.open_panel("survivor")
	await process_frame
	var picker:=app.panels.content.find_child("OutfitPicker",true,false) as OptionButton
	var avatar:WastelandPartyAvatar=app.panels.portrait
	for i in picker.item_count:
		picker.select(i)
		picker.item_selected.emit(i)
		var valid:=avatar.equipped=="oilskin_vest" and avatar.sleeves.size()==5 and avatar.equipment.get_child_count()>0
		for m:MeshInstance3D in avatar.sleeves: valid=valid and m.mesh!=null and m.material_override!=null
		check(valid,"character sheet dresses helmet, vest, two gloves and two boots on "+avatar.outfit)
	check(session.player.hand.gloves_worn and bool(session.player.hand.skin_material.get_shader_parameter("work_gloves")),"first-person material shows equipped work gloves")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		var zoom:=button_with_text("全身")
		check(zoom!=null,"character sheet offers a full-body preview")
		if zoom: zoom.pressed.emit()
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://build/qa/equipped-survivor.png")==OK,"capture the equipped survivor sheet")
	app.close_overlay()

func test_losses()->void:
	session.ui_command("discard",["hardhat"])
	check(session.bag.gear.head=="hardhat","first discard protects the worn helmet")
	session.ui_command("discard",["hardhat"])
	check(session.bag.gear.head=="" and session.bag.count("hardhat")==0 and session.bag.gear.feet=="trail_boots","discarding the last helmet clears only its worn slot")
	session.player_died(session.player)
	check(session.death_screen and session.bag.gear=={"head":"","body":"","hands":"","feet":""},"death clears slots for lost equipment")
	var found:=false
	for record:Dictionary in session.fx.drop_records.values():
		if record.items.get("work_gloves")==1 and record.items.get("oilskin_vest")==1 and record.items.get("trail_boots")==1: found=true
	check(found,"lost equipped pieces enter the death drop")
