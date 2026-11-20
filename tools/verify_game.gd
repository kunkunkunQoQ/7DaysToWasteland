extends SceneTree

var app: Node
var session: WastelandSession
var failures: Array[String] = []
var passed := 0
var visual := false
var output_dir := "res://build/qa"

func _initialize() -> void:
	_prepare.call_deferred()

func _prepare() -> void:
	visual = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if "--compat-capture" in OS.get_cmdline_user_args():
		output_dir+="/compatibility"
	if visual:
		DirAccess.make_dir_recursive_absolute(output_dir)
	WastelandSave.root_override = "user://verification/%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	Engine.max_fps = 0
	if visual:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait_for_chunks(25)
	_assert(app.front.screen == "title", "main menu starts")
	_assert(app.session.stream.active.size() >= 20, "preview streams terrain")
	if visual:
		await _capture("01-main-menu")
	app.front.creation()
	await _frames(4)
	_assert(app.front.screen == "create", "world creator opens")
	var play: Button = app.front.shell.find_children("*","Button",true,false).filter(func(button): return button.text == "进入荒原")[0]
	_assert(play.get_global_rect().end.y <= app.interface_root.size.y, "world creation button fits below the selected character")
	if visual:
		await _capture("02-world-creator")
	var config: Dictionary = app._default_config()
	config.terrain_revision=2 # Historic Gray Bay coastal fixture.
	config.minutes = 8.0
	app._enter_world(config,{},1,true)
	session = app.session
	await _frames(70)
	_assert(session.player.is_on_floor(), "survivor stands on terrain")
	_assert(session.player.health > 90.0 and session.bag.counts.is_empty() and session.bag.current().is_empty()
		and session.bag.bar.all(func(id): return id == "") and session.bag.armor.is_empty()
		and session.bag.magazine.is_empty(),"new survivor enters with no supplies, equipment or hotbar assignments")
	var legacy_bag:={"counts":{"club":1,"frame":10,"bandage":2},"bar":["club","frame","bandage"],"active":1,"armor":"","magazine":{}}
	var loaded_bag:=WastelandBag.new(session.catalog,legacy_bag)
	_assert(loaded_bag.counts==legacy_bag.counts and loaded_bag.current()=="frame","existing survivor retains inventory and equipped shortcut")
	_verify_quickbar(loaded_bag)
	_assert(session.progress.records.has("first_axe_guide") and app.hud.toast.contains("地上的枯枝") and app.hud.toast.contains("伤手"),"fresh world shows the first gathering step")
	app.open_panel("craft")
	var axe_title:="%s ×1"%session.catalog.title("stone_axe")
	_assert(app.panels.selection=="stone_axe" and app.panels.craft_quantity==1 and app.panels.detail_title.text==axe_title,"new survivor's handcrafting page opens on one stone axe")
	app.close_overlay()
	await _verify_first_axe()
	_assert(not session.progress.records.has("first_axe_guide"),"equipping the first axe completes onboarding")
	if visual:
		await _capture("03-lakeside")
		await _capture_models()
		await _capture_creature_hands()
		await _verify_mouse_look()
	var terrain := session.stream.generator
	var west := terrain.build(Vector2i(0, 0), {}, false)
	var east := terrain.build(Vector2i(1, 0), {}, false)
	var a: PackedVector3Array = west.points
	var b: PackedVector3Array = east.points
	var seam := true
	var grid := WastelandTerrainGen.GRID
	for i in grid:
		seam = seam and is_equal_approx(a[i*grid+grid-1].y,b[i*grid].y)
	_assert(seam, "neighboring heightfields join at the chunk boundary")
	var repeat := terrain.build(Vector2i(0,0),{},false)
	_assert(west.points == repeat.points and west.nav == repeat.nav, "seed determinism")
	var before := session.player.global_position
	Input.action_press("up")
	for tick in 39:
		await physics_frame
	Input.action_release("up")
	await _frames(7)
	_assert(before.distance_to(session.player.global_position)>1.1,"movement uses its mapped action")
	app.open_panel("bag")
	await _frames(4)
	_assert(app.panels.visible and not session.controls_enabled, "backpack routes to gameplay overlay")
	_assert(app.panels.item_grid.get_child_count()==27 and session.bag.capacity()==27,"an unequipped survivor has three rows of nine inventory cells")
	if visual:
		var original_counts:=session.bag.counts.duplicate()
		var original_bar:=session.bag.bar.duplicate()
		var original_automatic:=session.bag.automatic_shortcuts.duplicate()
		for id in ["steel_axe","rifle","pistol","bow","arrow","fuel","medkit","generator","solar","boat","armor","seed_potato","beacon_log"]:
			session.bag.add(id,2 if id=="arrow" else 1)
		app.panels.selection="stone_axe"
		app.panels._refresh_bag()
		await _frames(4)
		_assert(app.panels.quick_slots.get_global_rect().end.y<root.get_visible_rect().end.y,"backpack hotbar stays inside the viewport")
		await _capture("04-inventory")
		session.bag.counts=original_counts
		session.bag.bar=original_bar
		session.bag.automatic_shortcuts=original_automatic
	app.open_panel("craft")
	app.panels._filter_recipes("绷带")
	_assert(app.panels.recipe_list.get_child_count() == 1, "crafting material and name search")
	session.bag.add("cloth",5)
	var old_bandages := session.bag.count("bandage")
	session.queue_craft("bandage",1,null)
	await _frames(9)
	_assert(session.hand_queue.size()==1 and session.bag.count("cloth")==3,"craft reserves materials")
	session.hand_queue[0].done = session.clock.elapsed+0.016
	await _frames(8)
	_assert(session.bag.count("bandage")==old_bandages+2, "craft completes with inventory output")
	app.open_panel("skills")
	await _frames(3)
	session.gain(130,"test")
	_assert(session.progress.learn("craft",session.catalog.skills.craft), "experience unlocks a level-gated perk")
	app.open_panel("map")
	await _frames(4)
	session.add_marker(Vector2(11,-15),"泵站")
	_assert(app.panels.map_canvas.visible and session.marker_records.size()==1, "map receives a persistent marker")
	if visual:
		await _capture("05-world-map")
	app.close_overlay()
	var starter: WastelandChunk = session.stream.active.get(Vector2i(-1,1))
	await _verify_lodge_roof(starter)
	var first_loot: StaticBody3D
	for object in starter.decoration_root.get_children():
		if object.get_meta("kind","")=="loot":
			first_loot=object
			break
	_assert(first_loot!=null,"starter POI contains a real loot collider")
	if first_loot != null:
		preload("res://tools/chest_actions.gd").take_all(session,first_loot)
		var key: String = first_loot.get_meta("key")
		var loot_state: Dictionary = session.stream.chunk_diff(starter.cell).containers[key]
		_assert(loot_state.earned and loot_state.items.is_empty(),"loot transfers once and persists the container contents")
	session.bag.add("frame",2)
	var structure := session.construction
	var cell := _build_cell(5)
	_assert(cell != Vector3i(0,-990,0),"find buildable ground")
	if cell != Vector3i(0,-990,0):
		_assert(structure.place(cell,"frame",0,0,session.player.global_position),"place anchored frame")
		_assert(structure.place(cell+Vector3i.UP,"frame",2,0,session.player.global_position),"place supported upper part")
		session.bag.add("wood",40)
		structure.upgrade(cell)
		_assert(int(structure.blocks.get(cell,{}).get("tier",0))==1,"reinforcement consumes materials")
		structure.damage(cell,10000.0)
		_assert(not structure.blocks.has(cell+Vector3i.UP),"destroying a support collapses the upper part")
	var station_cell := _build_cell(4, "campfire")
	if station_cell != Vector3i(0,-990,0):
		var camp_point := WastelandConstruction.position_of(station_cell)
		session.player.global_position = Vector3(camp_point.x-2.1,session.stream.ground_at(camp_point)+0.4,camp_point.z)
		_assert(structure.place(station_cell,"campfire",0,0,session.player.global_position),"place a workstation")
		session.bag.add("dirty_water",2)
		session.queue_craft("clean_water",1,station_cell)
		_assert(structure.blocks[station_cell].queue.size()==1, "campfire queues potable water")
		session.refuel(station_cell)
		_assert(session.campfire_warmth(camp_point)>10.0,"lit campfire contributes temperature")
	else:
		_assert(false,"find campfire ground")
	_verify_power_and_vehicle()
	await _verify_projectiles()
	var day_seven := 6.0*24.0
	var clock := session.clock
	clock.hours = day_seven+21.9
	_assert(not clock.horde_active(),"horde respects the start boundary")
	clock.hours = day_seven+22.0
	_assert(clock.horde_active() and clock.event_day()==7,"day seven horde activates at 22:00")
	for i in range(250):
		if session.hordes.wave_index >= 1 and session.hordes.alive.any(func(actor): return actor.wave):
			break
		await physics_frame
	_assert(session.hordes.wave_index >= 1 and session.hordes.alive.any(func(actor): return actor.wave),"director spawns a pooled blood moon wave")
	if visual:
		await _capture("06-blood-moon")
	clock.hours = 7.0*24.0+3.99
	_assert(clock.horde_active() and clock.event_day()==7,"horde carries past midnight")
	clock.hours = 7.0*24.0+4.0
	_assert(not clock.horde_active(),"horde ends at 04:00")
	session.simulation_paused = true
	_assert(session.save_now(false)==OK,"manual save updates existing slot")
	_assert(session.save_now(false)==OK,"slot can commit while a backup exists")
	var saved := WastelandSave.read(1)
	_assert(not saved.is_empty() and saved.settings.seed==config.seed,"snapshot round-trips the seed")
	_assert(saved.get("markers",[]).size()==1 and not saved.get("diffs",{}).is_empty(),"snapshot includes exploration and chunk changes")
	_assert(saved.get("bag",{}).get("counts",{}).get("bandage",0)==old_bandages+2,"snapshot contains inventory")
	_assert(saved.diffs.values().any(func(row): return not row.get("removed",{}).is_empty()),"loose branches and stones remain collected across saves")
	if station_cell != Vector3i(0,-990,0):
		_assert(saved.construction.blocks.has(station_cell),"snapshot contains placed station")
	var corrupt := FileAccess.open(WastelandSave.path_for(1),FileAccess.WRITE)
	corrupt.store_string("truncated")
	corrupt.close()
	_assert(not WastelandSave.read(1).is_empty(),"backup recovers a truncated primary")
	app.open_world(1)
	await _frames(70)
	session=app.session
	_assert(session.marker_records.size()==1 and session.progress.rank("craft")==1,"reload restores markers and skills")
	_assert(session.stream.active.size()>=20,"reload restarts streaming")
	var from_count := session.stream.active.size()
	var far := Vector3(590.0,25.0,560.0)
	far.y = session.stream.ground_at(far)+0.25
	session.player.global_position = far
	await _frames(88)
	_assert(not session.stream.active.has(Vector2i(0,1)) and session.stream.active.size()<=maxi(125,from_count+20),"moving far unloads the prior neighborhood")
	WastelandSave.delete_slot(1)
	_validate_assets()
	session.simulation_paused=true
	await session.stream.quiesce()
	app._remove_session()
	app.queue_free()
	await process_frame
	var audio_finish := Time.get_ticks_msec()+450
	while Time.get_ticks_msec()<audio_finish: await process_frame
	print("WASTELAND QA  passed=%d  failed=%d" % [passed, failures.size()])
	for issue in failures:
		printerr("FAILED: "+issue)
	quit(0 if failures.is_empty() else 1)

func _aim_at_resource(kinds: Array) -> StaticBody3D:
	var origin := session.player.global_position
	var candidates: Array[StaticBody3D] = []
	for chunk: WastelandChunk in session.stream.active.values():
		for body in chunk.decoration_root.get_children():
			if body is StaticBody3D and not body.is_queued_for_deletion() and body.collision_layer!=0 and body.get_meta("resource","") in kinds:
				candidates.append(body)
	for id:String in session.fx.drop_live:
		for material:String in session.fx.drop_records[id].items:
			if material+"_drop" in kinds: candidates.append(session.fx.drop_live[id])
	candidates.sort_custom(func(a,b): return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	for target in candidates:
		var at := target.global_position
		for child in target.get_children():
			if child is CollisionShape3D:
				at=child.global_position
				break
		if target.get_meta("kind","")!="drop": at.y=minf(at.y,session.stream.ground_at(at)+1.2)
		for i in 8:
			var pos := at+Vector3(sin(i*PI/4),0,cos(i*PI/4))*1.20
			pos.y=session.stream.ground_at(pos)+0.05
			session.player.global_position=pos
			session.player.velocity=Vector3.ZERO
			session.player.camera.look_at(at)
			if session._interaction_trace().get("collider")==target and (target.get_meta("kind","")=="drop" or session._trace(2.58,15,false,true).get("collider")==target):
				return target
	session.player.global_position=origin
	return null

func _strike_resource() -> void:
	Input.action_press("fire")
	session._process_controls(1.0/60.0)
	Input.action_release("fire")
	while session.action_lock>0.0:
		await physics_frame

func _verify_quickbar(bag: WastelandBag) -> void:
	bag.spend({"club":1})
	bag.add("wood",3)
	bag.add("wood",4)
	_assert(bag.bar[0]=="club" and bag.bar[3]=="wood" and bag.bar.count("wood")==1 and bag.count("wood")==7 and bag.current()=="frame","pickups stack once and preserve custom bindings and the selected slot")
	bag.add("club",1)
	_assert(bag.bar[0]=="club" and bag.bar.count("club")==1,"reacquired equipment uses its saved shortcut")
	bag.assign("wood",5)
	for id in ["stick","stone","fiber","cloth"]:
		bag.add(id,1)
	var full := bag.bar.duplicate()
	bag.add("scrap",2)
	_assert(not full.has("") and bag.bar==full and bag.count("scrap")==2,"a full hotbar sends the item to the bag without replacing shortcuts")
	var restored:=WastelandBag.new(bag.catalog,bag.snapshot())
	restored.spend({"wood":7,"stone":1})
	restored.add("scrap",1)
	_assert(restored.bar[5]=="wood" and restored.bar[full.find("stone")]=="scrap" and restored.count("scrap")==3,"depleted automatic shortcuts become available after loading while a manually moved shortcut stays reserved")
	var packed:=WastelandBag.new(bag.catalog,{"counts":{"sledge":WastelandBag.STACK_SLOTS}})
	_assert(packed.add("wood",1)==0 and not packed.bar.has("wood"),"a rejected pickup leaves the shortcut bar alone")

func _verify_first_axe() -> void:
	var player := session.player
	var origin := player.global_position
	var camera_rotation:=player.camera.rotation
	var full_health:=player.health
	for pair:Array in [["fallen_stick","stick"],["pebble","stone"],["grass","fiber"]]:
		var required:=int(session.catalog.recipes.stone_axe.inputs[pair[1]])
		for n in required:
			var target:=_aim_at_resource([pair[0]])
			if target==null: break
			if pair[0]=="grass":
				var previous:=session.bag.count("fiber")
				await _strike_resource()
				if session.bag.count("fiber")>previous: continue
				if _aim_at_resource(["fiber_drop"])==null: break
			Input.action_press("use")
			session._process_controls(1.0/60.0)
			Input.action_release("use")
			await physics_frame
			await physics_frame
		_assert(session.bag.count(pair[1])>=required,"gather "+str(pair[1])+" safely from ground")
		_assert(session.bag.bar.count(pair[1])==1,"first pickups bind "+str(pair[1])+" once")
	_assert(is_equal_approx(player.health,full_health),"first axe ingredients cost no health")
	var trunk:=_aim_at_resource(["oak","pine"])
	if trunk:
		await _strike_resource()
	_assert(trunk!=null and player.health<full_health,"only punching a live tree hurts the bare hand")
	if session.bag.has_all(session.catalog.recipes.stone_axe.inputs):
		session.ui_command("craft",["stone_axe",1,null])
		for i in 160:
			if session.bag.count("stone_axe")>0:
				break
			await physics_frame
	_assert(session.bag.count("stone_axe")==1 and session.bag.bar.count("stone_axe")==1,"the crafted stone axe appears in a shortcut freed by its ingredients")
	session.ui_command("assign",["stone_axe"])
	var tree:=_aim_at_resource(["oak","pine"])
	if tree!=null and session.bag.current()=="stone_axe":
		var before:=session.bag.count("wood")
		for i in 8:
			if not _aim_at_resource(["oak","pine"]): break
			await _strike_resource()
			await physics_frame
			for wait_frame in 420:
				if session.timber.active.is_empty(): break
				await physics_frame
			if session.bag.count("wood")>before: break
			if _aim_at_resource(["wood_drop"]):
				session._use()
				break
		_assert(session.bag.count("wood")>before,"equipped crafted axe fells a generated tree and collects timber")
	else:
		_assert(false,"equip the first axe near a tree")
	player.global_position=origin
	player.camera.rotation=camera_rotation
	player.velocity=Vector3.ZERO

func _wait_for_chunks(count: int) -> void:
	for step in range(350):
		if app.session.stream.active.size() >= count:
			return
		if not visual:
			OS.delay_msec(2)
		await process_frame

func _verify_mouse_look() -> void:
	await _frames(2)
	var player := session.player
	var original := Vector2(player.rotation.y, player.pitch)
	var original_height: int = app.scene_height
	var sensitivity := float(session.options.display.sensitivity)
	var inverted := -1.0 if session.options.display.invert_y else 1.0
	var physical_delta := Vector2(45, -24)
	_send_mouse_motion(physical_delta)
	var expected := original - physical_delta * Vector2(sensitivity, sensitivity * inverted)
	_assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _aim_matches(expected), "root mouse motion controls both camera axes")

	app.open_panel("bag")
	var before_panel_motion := Vector2(player.rotation.y, player.pitch)
	_send_mouse_motion(Vector2(-70, 54))
	_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _aim_matches(before_panel_motion), "inventory releases cursor and freezes aiming")
	app.close_overlay()
	await _frames(2)
	app.scene_height = 238
	app.resize_scene()
	var restored := Vector2(player.rotation.y, player.pitch)
	_send_mouse_motion(-physical_delta)
	expected = restored + physical_delta * Vector2(sensitivity, sensitivity * inverted)
	_assert(_aim_matches(expected), "resuming restores mouse look at a lower render resolution")
	app.scene_height = original_height
	app.resize_scene()
	player.rotation.y = original.x
	player.pitch = original.y
	player.eyes.rotation.x = original.y

func _send_mouse_motion(motion: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(640, 360)
	event.relative = motion * 0.5
	event.screen_relative = motion
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _aim_matches(angles: Vector2) -> bool:
	var player := session.player
	return absf(angle_difference(player.rotation.y, angles.x)) < 0.0001 and absf(player.eyes.rotation.x - angles.y) < 0.0001

func _verify_lodge_roof(chunk: WastelandChunk) -> void:
	var origin := chunk.to_global(Vector3(16, 0, 16))
	origin.y = session.stream.ground_at(origin)
	var span := float(session.catalog.sites[chunk.site].span)
	await physics_frame
	var space := chunk.get_world_3d().direct_space_state
	for side in [-1, 1]:
		var name := "RoofWest" if side < 0 else "RoofEast"
		var inner := origin + Vector3(side * 0.72, 0, 0)
		var outer := origin + Vector3(side * span * 0.43, 0, 0)
		var high := space.intersect_ray(PhysicsRayQueryParameters3D.create(inner + Vector3.UP * 8.0, inner, 2))
		var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(outer + Vector3.UP * 8.0, outer, 2))
		_assert(not high.is_empty() and not low.is_empty() and high.collider.name == name and low.collider.name == name
			and high.position.y > low.position.y + 0.6 and high.normal.y > 0.8 and high.normal.x * side > 0.0,
			"%s rises toward the ridge and exposes upward-facing collision" % name)
	var ridge := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 8.0, origin, 2))
	_assert(not ridge.is_empty() and ridge.collider.name == "RoofRidge", "roof ridge covers the seam")
	for side in [-1, 1]:
		var name := "GableNorth" if side < 0 else "GableSouth"
		var at := origin + Vector3.UP * (WastelandSite.STOREY_HEIGHT + 0.72)
		var result := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.BACK * side * (span * 0.5 + 1.3), at, 2))
		_assert(not result.is_empty() and result.collider.name == name, "%s closes the roof opening above the wall" % name)
	if visual:
		await _capture_lodge_roof(origin)

func _capture_lodge_roof(origin: Vector3) -> void:
	var player := session.player
	var original := player.global_position
	var heading := player.rotation.y
	var pitch := player.pitch
	var time := session.clock.hours
	session.simulation_paused = true
	player.global_position = origin + Vector3(9.7, 5.6, 12.0)
	var toward := origin + Vector3.UP * 2.55 - player.camera.global_position
	player.rotation.y = atan2(-toward.x, -toward.z)
	player.pitch = atan2(toward.y, Vector2(toward.x, toward.z).length())
	player.eyes.rotation.x = player.pitch
	session.clock.hours = 15.9
	session.atmosphere.sync(session.clock, 0.0, player.camera.global_position, -player.camera.global_basis.z)
	app.hud.hide()
	app.pixel_paint.set_shader_parameter("hands_visible", false)
	await _frames(3)
	await _capture("09-lodge-roof")
	app.pixel_paint.set_shader_parameter("hands_visible", true)
	app.hud.show()
	player.global_position = original
	player.rotation.y = heading
	player.pitch = pitch
	player.eyes.rotation.x = pitch
	session.clock.hours = time
	session.atmosphere.sync(session.clock, 0.0, player.camera.global_position, -player.camera.global_basis.z)
	session.simulation_paused = false

func _build_cell(radius: int, id: String = "frame") -> Vector3i:
	if not session.bag.count(id):
		session.bag.add(id,1)
	var start := session.player.global_position
	for z in range(-radius,radius+1):
		for x in range(-radius,radius+1):
			var point := Vector3(floorf(start.x)+x+0.5,0,floorf(start.z)+z+0.5)
			var ground := session.stream.ground_at(point)
			var cell := Vector3i(floori(point.x),ceili(ground-0.42),floori(point.z))
			if ground>0.3 and session.construction.can_place(cell,start,id):
				return cell
	return Vector3i(0,-990,0)

func _verify_power_and_vehicle() -> void:
	var structures:=session.construction
	var origin:=session.player.global_position
	var generator_cell:=_build_cell(5,"generator")
	var supply:=structures.place(generator_cell,"generator",0,0,origin) if generator_cell.y!=-990 else false
	var lamp_cell:=_build_cell(5,"floodlight")
	var lamp:=structures.place(lamp_cell,"floodlight",0,0,origin) if lamp_cell.y!=-990 else false
	_assert(supply and lamp,"generator and floodlight install as real world objects")
	if supply and lamp:
		session.bag.add("fuel",1)
		session.bag.add("wire",1)
		session.refuel(generator_cell)
		structures.connect_device(generator_cell)
		structures.connect_device(lamp_cell)
		structures._power_grid(0.25)
		_assert(structures.powered.has(lamp_cell) and float(structures.blocks[generator_cell].fuel)<88.0,"powered load receives energy and consumes generator fuel")
	var at:=origin+Vector3(2.4,0,1.4)
	at.y=session.stream.ground_at(at)+0.29
	session.vehicle_serial+=1
	var id:=str(session.vehicle_serial)
	session.vehicle_records[id]={"type":"boat","point":at,"yaw":0.0,"fuel":46.0}
	session._mount_vehicle(id)
	var craft:WastelandVehicle=session.vehicles[id]
	_assert(craft.get_child_count()>=10 and craft.collision_layer==8,"boat has separate hull geometry and collision")
	session.player.ride(craft)
	craft.drive(0.016,Vector2(0,-1),false)
	_assert(craft.drive_speed>0.0 and float(craft.record.fuel)<46.0,"mounted vehicle accepts drive input and consumes fuel")
	session.player.dismount()
	session.player.global_position=origin

func _verify_projectiles() -> void:
	var player:=session.player
	var original:=player.global_position
	var fixture:=original+Vector3.UP*17.0
	session.simulation_paused=true
	player.global_position=fixture
	player.invulnerable=0.0
	var placed:=session.hordes._spawn("walker",fixture+Vector3.FORWARD*4.0,false,{})
	_assert(placed,"spawn projectile target")
	if placed:
		var dummy:WastelandCreature=session.hordes.alive.back()
		var prior_hp:=dummy.hp
		await physics_frame
		await physics_frame
		session.fx.projectile(fixture+Vector3.UP*0.89,Vector3.FORWARD*80.0,player,"bullet",17.0)
		for i in range(8):
			session.fx.simulate(1.0/60.0)
			await physics_frame
		_assert(dummy.hp<prior_hp,"pooled bullet collides with enemy without hitting shooter")
		var health:=player.health
		var prior_bleed:=player.bleed
		var prior_infection:=player.infection
		session.fx.projectile(dummy.global_position+Vector3.UP*0.89,Vector3.BACK*38.0,dummy,"acid",14.0)
		for j in range(12):
			session.fx.simulate(1.0/60.0)
			await physics_frame
		_assert(player.health<health and player.infection>prior_infection,"acid projectile damages and infects survivor")
		player.health=health
		player.bleed=prior_bleed
		player.infection=prior_infection
		player.clear_damage_feedback()
		player.invulnerable=0.0
		session.hordes.release(dummy)
	player.global_position=original
	player.velocity=Vector3.ZERO
	session.simulation_paused=false

func _assert(condition: bool,label: String) -> void:
	if condition:
		passed+=1
		print("PASS "+label)
	else:
		failures.append(label)

func _frames(count: int) -> void:
	for index in count:
		await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var file := output_dir+"/"+name+".png"
	var result := frame.save_png(file)
	_assert(result==OK,"capture "+name)

func _capture_models() -> void:
	var survivor:=session.player
	var origin:=survivor.global_position
	var clock:=session.clock.hours
	var facing:=survivor.rotation.y
	var head_angle:=survivor.pitch
	session.clock.hours=16.60
	survivor.rotation.y=PI
	survivor.pitch=-0.085
	survivor.eyes.rotation.x=survivor.pitch
	var style: Array = ["crawler","brute","spitter","radiant","screamer"]
	var lineup: Array[WastelandCreature] = []
	for index in range(style.size()):
		var point:=origin+Vector3((index-2)*1.55,0.0,4.30+sin(index*1.14)*0.43)
		point.y=session.stream.ground_at(point)+0.07
		if session.hordes._spawn(style[index],point,false,{}):
			var enemy:WastelandCreature=session.hordes.alive.back()
			enemy.look_at(Vector3(origin.x,point.y,origin.z))
			enemy._pose(0.06,3.5)
			lineup.append(enemy)
	session.atmosphere.sync(session.clock,0.0,survivor.camera.global_position,-survivor.camera.global_basis.z)
	session.simulation_paused=true
	await _frames(4)
	await _capture("07-creature-detail")
	for actor in lineup:
		session.hordes.release(actor)
	survivor.rotation.y=facing
	survivor.pitch=head_angle
	survivor.eyes.rotation.x=head_angle
	session.clock.hours=clock
	session.atmosphere.sync(session.clock,0.0,survivor.camera.global_position,-survivor.camera.global_basis.z)
	var selected:=session.bag.active
	session.bag.active=session.bag.bar.find("stone_axe")
	survivor.hand.hold("stone_axe",session.catalog.items.stone_axe)
	survivor.hand.animate(0.02,0.0,0.0,0.9,0.0)
	await _frames(3)
	await _capture("08-stone-axe")
	session.bag.active=selected
	session.simulation_paused=false

func _capture_creature_hands() -> void:
	var player := session.player
	var origin := player.global_position
	var previous_pitch := player.pitch
	var lamp_was_on := player.headlamp.visible
	var forward := -player.global_basis.z
	var right := player.global_basis.x
	var group: Array[WastelandCreature] = []
	session.simulation_paused = true
	player.pitch = -0.23
	player.eyes.rotation.x = player.pitch
	player.headlamp.show()
	for fixture: Array in [
		["walker", -1.16, 2.86, 0.91, 0.0, -0.32],
		["crawler", 0.10, 2.17, 0.80, 0.0, 0.21],
		["brute", 1.17, 3.04, 0.0, 0.85, 0.24],
	]:
		var at := origin + right * float(fixture[1]) + forward * float(fixture[2])
		at.y = session.stream.ground_at(at) + 0.06
		if not session.hordes._spawn(fixture[0], at, false):
			continue
		var actor: WastelandCreature = session.hordes.alive.back()
		actor.look_at(Vector3(origin.x, at.y, origin.z))
		actor.rotation.y += float(fixture[5])
		actor.alerted = true
		actor.attack = fixture[3]
		actor.windup = fixture[4]
		actor._pose(0.07, 3.0)
		group.append(actor)
	app.hud.hide()
	app.pixel_paint.set_shader_parameter("hands_visible", false)
	await _frames(4)
	await _capture("11-zombie-hands")
	app.pixel_paint.set_shader_parameter("hands_visible", true)
	app.hud.show()
	for actor in group:
		session.hordes.release(actor)
	player.pitch = previous_pitch
	player.eyes.rotation.x = previous_pitch
	player.headlamp.visible = lamp_was_on
	session.simulation_paused = false

func _validate_assets() -> void:
	var every_item:=true
	for id in session.catalog.items:
		var entry:Dictionary=session.catalog.items[id]
		var model:=WastelandItemArt.mesh(id,entry)
		var icon:=WastelandItemArt.icon(id,entry)
		every_item=every_item and model!=null and model.get_surface_count()==1 and icon.get_width()==WastelandItemArt.SIZE
		if visual:
			every_item=every_item and icon.get_image().get_used_rect().has_area()
	_assert(every_item,"catalogue items have a non-empty model and icon")
	var rigs:=true
	for id in session.catalog.enemies:
		var point:=session.player.global_position+Vector3.FORWARD*6.3
		if not session.hordes._spawn(id,point,false,{"limb_index":0}):
			rigs=false
			continue
		var actor:WastelandCreature=session.hordes.alive.back()
		actor._pose(0.09,5.0)
		rigs=rigs and actor.skeleton.get_bone_count()>=7
		if not actor.spec.get("animal", false):
			_verify_zombie_wrists(actor)
		session.hordes.release(actor)
	_assert(rigs,"all zombie and wildlife rigs assemble and animate")
	_assert(session.player.hand.get_parent()==app.hands_camera,"hands have an independent camera and depth buffer")
	_assert(app.ui_group.material.get_shader_parameter("strength")>0.0,"Chinese interface soft focus is active")

func _verify_zombie_wrists(actor: WastelandCreature) -> void:
	var skeleton := actor.skeleton
	var right_wrist := skeleton.find_bone("hand_r")
	var idle_y := skeleton.get_bone_global_pose(right_wrist).origin.y if right_wrist >= 0 else 0.0
	actor.alerted = true
	actor.attack = 1.0
	actor._pose(0.09, 3.0)
	var aligned := true
	var reaches_forward := true
	for side in [-1, 1]:
		var suffix := "l" if side < 0 else "r"
		var wrist := skeleton.find_bone("hand_" + suffix)
		var elbow := skeleton.find_bone("elbow_" + suffix)
		if wrist < 0 or elbow < 0:
			aligned = false
			reaches_forward = false
			continue
		var rest := skeleton.get_bone_rest(wrist)
		var palm: MeshInstance3D = actor.body_parts["hand_" + suffix].get_node_or_null("HandMesh")
		if not is_instance_valid(palm):
			aligned = false
			continue
		var bounds := palm.get_aabb()
		var thumb_reach := (bounds.end.x + bounds.position.x) * -float(side)
		aligned = aligned and thumb_reach > 0.022 and skeleton.get_bone_parent(wrist) == elbow
		aligned = aligned and (-rest.basis.z).dot(rest.origin.normalized()) > 0.93 and rest.basis.determinant() > 0.99
		var pose := skeleton.get_bone_global_pose(wrist)
		var elbow_pose := skeleton.get_bone_global_pose(elbow)
		reaches_forward = reaches_forward and pose.origin.z < elbow_pose.origin.z - 0.14
		reaches_forward = reaches_forward and pose.basis.z.z > 0.60 and pose.origin.x * float(side) > 0.19
	_assert(aligned, actor.type + " has mirrored thumbs and wrists aligned with the forearms")
	_assert(reaches_forward, actor.type + " reaches forward with both hands at the strike pose")
	if actor.type != "brute" or right_wrist < 0:
		return
	var strike := skeleton.get_bone_global_pose(right_wrist)
	actor.attack = 0.0
	actor.windup = 0.92
	actor._pose(0.09, 3.0)
	var lifted := skeleton.get_bone_global_pose(right_wrist)
	var grip: Marker3D = actor.body_parts.hand_r.get_node_or_null("HammerGrip")
	var hammer: MeshInstance3D = grip.get_node_or_null("Hammer") if is_instance_valid(grip) else null
	_assert(lifted.origin.y > idle_y + 0.34 and lifted.origin.y > strike.origin.y + 0.10 and is_instance_valid(hammer)
		and (hammer.transform * WastelandBestiary.SLEDGE_GRIP_POINT).length_squared() < 0.00001,
		"sapper raises the right hand and the hammer stays centered in the grip")
	actor.revive(actor.type, actor.global_position, false, {})
	_assert(skeleton.get_bone_pose(right_wrist).is_equal_approx(skeleton.get_bone_rest(right_wrist))
		and skeleton.get_bone_pose_rotation(skeleton.find_bone("elbow_r")).is_equal_approx(Quaternion.IDENTITY),
		"pooled creature starts with fresh wrist and elbow poses")
