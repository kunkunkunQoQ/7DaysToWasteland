extends "res://tools/verify_lan_discovery.gd"

const Salvage := preload("res://game/world/structural_salvage.gd")
const SHORE := WastelandSite.SHORE_CELL
const MP_KEY := "wall/0/2/0"

var s: WastelandSession

func run() -> void:
	var args := OS.get_cmdline_user_args()
	port = 19623
	for arg: String in args:
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	WastelandSave.root_override = "user://verification/wall-demolition-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	if "--guest" in args:
		await guest()
	else:
		var cfg: Dictionary = app._default_config()
		cfg.seed = 2817
		cfg.spawn_roll = 74
		app._enter_world(cfg, {}, 1, false)
		s = app.session
		if "--host" in args: await host()
		else: await offline()
	app.network.stop()
	if is_instance_valid(s):
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	print("WALL DEMOLITION failures=",failures)
	quit(1 if failures else 0)

func load_site(cell: Vector2i) -> WastelandChunk:
	var center := Vector2(cell*32)+Vector2(16,16)
	s.stream.ensure_landing(Vector3(center.x,0,center.y))
	await physics_frame
	await physics_frame
	return s.stream.active[cell]

func site_cells() -> Dictionary:
	var cells := {}
	for cell: Vector2i in WastelandTerrainGen.FIXED:
		cells[WastelandTerrainGen.FIXED[cell]] = cell
	for radius in range(1,32):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				if maxi(absi(x),absi(z)) != radius: continue
				var cell := Vector2i(x,z)
				var kind := s.stream.generator.site_for(cell)
				if not kind.is_empty() and not cells.has(kind): cells[kind]=cell
		if cells.size()==s.catalog.sites.size(): break
	return cells

func wall_point(c: WastelandChunk, id: String) -> Vector3:
	var floor_index := int(id.get_slice("/",1))
	var side := int(id.get_slice("/",2))
	var bay := int(id.get_slice("/",3))
	var span := float(s.catalog.sites[c.site].span)
	var center := c.to_global(Vector3(16,c.ruin.base_y+floor_index*WastelandSite.STOREY_HEIGHT,16))
	return center + Basis(Vector3.UP,side*PI/2)*Vector3((bay-2)*span/5,0,span/2)

func outside(id: String) -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP,int(id.get_slice("/",2))*PI/2)

func aim(at: Vector3) -> void:
	var ray := at-s.player.camera.global_position
	s.player.rotation.y = atan2(-ray.x,-ray.z)
	s.player.pitch = atan2(ray.y,Vector2(ray.x,ray.z).length())
	s.player.eyes.rotation.x = s.player.pitch

func sees(c: WastelandChunk, id: String) -> bool:
	var hit := s._trace(float(s.catalog.items.sledge.reach),15,false,true,true)
	var body: Object = hit.get("collider")
	return is_instance_valid(body) and body.get_meta("cell",Vector2i.MAX)==c.cell and body.get_meta("site_id","")==id

func stage_at(c: WastelandChunk, id: String, side: float) -> void:
	var wall := wall_point(c,id)
	s.player.global_position = wall+outside(id)*side*1.20+Vector3.UP*0.19
	s.player.velocity = Vector3.ZERO
	aim(wall+Vector3.UP*1.49)

func sum_items(total: Dictionary, items: Dictionary) -> void:
	for key: String in items:
		total[key] = int(total.get(key,0))+int(items[key])

func estimate(c: WastelandChunk) -> Dictionary:
	var values := {}
	for id: String in c.structures:
		values[id] = Salvage.materials(c,id)
	return values

func expected_loss(c: WastelandChunk, before: Dictionary) -> Dictionary:
	var total := {}
	for id: String in before:
		if not c.structures.has(id): sum_items(total,before[id])
	return total

func spawned_since(serial: int) -> Dictionary:
	var items := {}
	for key: String in s.fx.drop_records:
		if key.is_valid_int() and int(key)>serial:
			sum_items(items,s.fx.drop_records[key].items)
	return items

func passage(c: WastelandChunk, id: String, direction: float) -> bool:
	stage_at(c,id,direction)
	# Move the actual standing CharacterBody through the old wall plane.
	var step := -outside(id)*direction*0.055
	for i in 43:
		var collision := s.player.move_and_collide(step)
		if collision!=null:
			if not c.structures.has(id):
				var body: Object = collision.get_collider()
				print("Blocked ",c.site," ",id," by ",body.get_meta("site_id",body.get_meta("kind","unknown"))," at ",collision.get_position())
			return false
	return (s.player.global_position-wall_point(c,id)).dot(outside(id)*direction)<-0.95

func mark(c: WastelandChunk, id: String) -> Vector3:
	return c.stream.chunk_diff(c.cell).get("wall_marks",{}).get(id,Vector3.INF)

func finish_matches(c: WastelandChunk, id: String, stage: int, impact: Vector3) -> bool:
	if not c.structures.has(id) or not impact.is_finite() or not mark(c,id).is_equal_approx(impact): return false
	var overlay: ShaderMaterial = c.wall_finishes.get(id)
	if stage>0:
		if not overlay or overlay.shader.resource_path!="res://shaders/site_wall_damage.gdshader": return false
		var center: Vector3 = overlay.get_shader_parameter("impact")
		if not center.is_equal_approx(impact) or bool(overlay.get_shader_parameter("severe"))!=(stage==2): return false
		if bool(overlay.get_shader_parameter("timber"))!=(c.site in ["cabin","lodge"]): return false
	elif overlay!=null:
		return false
	var meshes := 0
	for piece: StaticBody3D in c.structures[id]:
		if int(piece.get_meta("wall_wear",0))!=stage: return false
		for child in piece.get_children():
			if child is MeshInstance3D:
				meshes+=1
				if child.material_overlay!=overlay: return false
	return meshes>0

func mark_cleared(c: WastelandChunk, id: String) -> bool:
	return not c.stream.chunk_diff(c.cell).get("wall_marks",{}).has(id) and not c.wall_finishes.has(id)

func check_saved_hit_and_support() -> void:
	var c := await load_site(SHORE)
	var wall := wall_point(c,MP_KEY)
	stage_at(c,MP_KEY,1)
	aim(wall+Vector3(0.34,1.51,0))
	if not check(sees(c,MP_KEY),"off-center camera trace for partial damage save"): return
	var at: Vector3 = s._trace(3.3,15,false,true,true).position
	s._melee(s.catalog.items.sledge,1.0)
	check(finish_matches(c,MP_KEY,1,at),"light timber split on every section at exact first contact")
	aim(wall+Vector3(-0.28,1.74,0))
	var other := s._trace(3.3,15,false,true,true)
	if not check(sees(c,MP_KEY) and at.distance_to(other.position)>0.4,"second blow strikes a different point on the same wall"): return
	s._melee(s.catalog.items.sledge,1.0)
	check(finish_matches(c,MP_KEY,2,at),"severe split stays at first contact after off-center second blow")
	var health := float(c.structures[MP_KEY][0].get_meta("hp"))
	check(s.save_now(false)==OK,"save visibly damaged standing wall")
	var state := WastelandSave.read(1)
	var disk: Dictionary=state.diffs[WastelandTerrainGen.grid_key(SHORE)]
	check(Vector3(disk.wall_marks[MP_KEY]).is_equal_approx(at) and is_equal_approx(disk.site_damage[MP_KEY],health),"disk stores first world contact and remaining HP together")
	app._enter_world(state.settings,state,1,false)
	s=app.session
	s.simulation_paused=true
	c=await load_site(SHORE)
	check(finish_matches(c,MP_KEY,2,at) and is_equal_approx(c.structures[MP_KEY][0].get_meta("hp"),health),"reload restores severe timber overlay at original world contact")
	var footing: String = c.support_graph[MP_KEY][0][0]
	if not check(c.structures.has(footing),"marked wall has a live bearing"): return
	s.hit_wall(c.structures[footing][0],10000.0)
	check(not c.structures.has(MP_KEY) and mark_cleared(c,MP_KEY),"support collapse removes dependent wall, its impact and its material")
	var diff := s.stream.chunk_diff(SHORE)
	check(float(diff.site_damage.get(MP_KEY,-1))==0 and not diff.get("wall_marks",{}).has(MP_KEY),"collapse delta records destruction and clears contact")

func offline() -> void:
	s.simulation_paused = true
	var settings := s.world_settings.duplicate()
	await check_saved_hit_and_support()
	app._enter_world(settings,{},1,false)
	s=app.session
	s.simulation_paused=true
	var cells := site_cells()
	check(cells.size()==10,"ten distinct surface POI types in this seed")
	var destroyed := {}
	# These clear bays face all four directions; the lodge and cabin have loot cabinets behind their central panels.
	var sides := {"police":3, "granary":0, "garage":1}
	for kind: String in cells:
		var c := await load_site(cells[kind])
		var floor_index := 1 if kind=="bunker" else 0
		var side := int(sides.get(kind,2))
		var bay := 0 if kind in ["lodge","cabin"] else (4 if kind=="granary" else 2)
		var id := "wall/%d/%d/%d"%[floor_index,side,bay]
		if not check(c.structures.has(id),kind+" solid wall exists "+id): continue
		var original: Array = c.structures[id].duplicate()
		var sources := estimate(c)
		var serial := s.fx.serial
		var hp := float(original[0].get_meta("hp"))
		stage_at(c,id,1)
		if not check(sees(c,id),kind+" outward-facing skin in real camera trace"): continue
		var blocked := not passage(c,id,1)
		check(blocked,kind+" intact bay stops standing capsule")
		stage_at(c,id,1)
		s.player.stamina=100.0
		var first_contact: Vector3=s._trace(3.3,15,false,true,true).position
		s._melee(s.catalog.items.sledge,1)
		var remaining := float(original[0].get_meta("hp"))
		var same_hp := original.all(func(piece):return is_equal_approx(float(piece.get_meta("hp")),remaining))
		check(remaining>0 and remaining<hp and same_hp and spawned_since(serial).is_empty(),kind+" first blow shares HP without a drop")
		var first_stage := 0 if remaining/hp>0.73 else 1
		var valid_stages := finish_matches(c,id,first_stage,first_contact)
		var observed := {first_stage:true}
		stage_at(c,id,-1)
		if not check(sees(c,id),kind+" inside face in real camera trace"): continue
		for i in 9:
			s._melee(s.catalog.items.sledge,1)
			if not c.structures.has(id): break
			var fraction := float(original[0].get_meta("hp"))/hp
			var stage := 2 if fraction<=0.36 else (1 if fraction<=0.73 else 0)
			observed[stage]=true
			valid_stages = finish_matches(c,id,stage,first_contact) and valid_stages
			await physics_frame
		if not check(not c.structures.has(id),kind+" normal inside blows remove wall "+id): continue
		check(valid_stages and observed.has_all([1,2]),kind+" correct material and both damage stages stay centered at first contact")
		check(mark_cleared(c,id),kind+" direct demolition clears impact and shared overlay")
		check(original.size()>1 and original.all(func(piece):return not is_instance_valid(piece) or (piece.collision_layer==0 and not piece.visible)),kind+" original wall core and every trim body cleared")
		var expected := expected_loss(c,sources)
		check(not expected.is_empty() and spawned_since(serial)==expected,kind+" exact salvage including dependent sections")
		await physics_frame
		check(passage(c,id,1) and passage(c,id,-1),kind+" survivor crosses the new opening in both directions")
		destroyed[c.cell] = id
	check(destroyed.size()==10,"all ten wall breaches recorded")
	check(s.save_now(false)==OK,"save ten demolished walls")
	var state := WastelandSave.read(1)
	var drops: Dictionary = s.fx.drop_records.duplicate(true)
	app._enter_world(state.settings,state,1,false)
	s=app.session
	s.simulation_paused=true
	check(s.fx.drop_records==drops,"saved loose salvage restored once")
	for cell: Vector2i in destroyed:
		var c := await load_site(cell)
		var id: String = destroyed[cell]
		check(not c.structures.has(id) and mark_cleared(c,id) and passage(c,id,1),c.site+" traversable gap persists after reload")

func guest_collectible() -> int:
	var at := wall_point(s.stream.active[SHORE],MP_KEY)
	var count := s.bag.count("wood")
	for row: Dictionary in s.fx.drop_records.values():
		if Vector3(row.point).distance_to(at)<12.0:
			count += int(row.items.get("wood",0))
	return count

func confirmed(label: String) -> bool:
	return s.marker_records.any(func(m):return m.name==label)

func marker_for(prefix: String) -> Dictionary:
	for m: Dictionary in s.marker_records:
		if str(m.name).begins_with(prefix): return m
	return {}

func compare_remote_finish(c: WastelandChunk, stage: int) -> bool:
	var prefix := "wear%d/"%stage
	if not check(await until(func():return not marker_for(prefix).is_empty()),"guest reports material center for stage %d"%stage): return false
	var msg := marker_for(prefix)
	var xz: Vector2=msg.at
	var from_guest := Vector3(xz.x,float(str(msg.name).get_slice("/",1))/1000.0,xz.y)
	var at := mark(c,MP_KEY)
	var ok := finish_matches(c,MP_KEY,stage,at) and at.distance_to(from_guest)<0.001
	check(ok,"host and guest material centers agree to one millimetre at stage %d"%stage)
	s.ui_command("marker",[xz,"wear%d-ok"%stage])
	return ok

func report_guest_finish(c: WastelandChunk, stage: int, target: Vector3) -> bool:
	var old_swings := s.player.hand.swing_serial
	Input.action_press("fire")
	var swung := await until(func():
		aim(target)
		return s.player.hand.swing_serial>old_swings
	,10000)
	Input.action_release("fire")
	if not check(swung,"guest performs single ordinary swing %d"%stage): return false
	if not check(await until(func():return finish_matches(c,MP_KEY,stage,mark(c,MP_KEY)),5000),"guest mirrors authoritative shader and split stage %d"%stage): return false
	var shader: ShaderMaterial = c.wall_finishes[MP_KEY]
	var center: Vector3=shader.get_shader_parameter("impact")
	s.ui_command("marker",[Vector2(center.x,center.z),"wear%d/%d"%[stage,roundi(center.y*1000)]])
	return check(await until(func():return confirmed("wear%d-ok"%stage)),"authority acknowledges same first-hit center")

func host() -> void:
	var c := await load_site(SHORE)
	var wall := wall_point(c,MP_KEY)
	s.hordes.next_patrol=INF
	s.hordes.next_herd=INF
	s.player.global_position=wall+outside(MP_KEY)*6.0+Vector3.UP*0.3
	s.bag.add("sledge",1)
	s.bag.assign("sledge",3)
	var sources := estimate(c)
	var serial := s.fx.serial
	var start := guest_collectible()
	if not check(app.network.listen(port)==OK,"host opens ENet"): return
	if not check(await until(func():return not app.network.joined_members().is_empty()),"independent guest joins"): return
	app.network.joined_members()[0].slot=3
	app.network.joined_members()[0].survivor.global_position=wall+outside(MP_KEY)*2.8+Vector3.UP*0.20
	if not check(await until(func():return confirmed("wall-ready")),"guest aims at intact wall"): return
	if not await compare_remote_finish(c,1): return
	var first_contact := mark(c,MP_KEY)
	if not await compare_remote_finish(c,2): return
	check(mark(c,MP_KEY).is_equal_approx(first_contact),"authority retains first contact after differently aimed guest swing")
	if not check(await until(func():return not c.structures.has(MP_KEY)),"guest's normal fire input removes host wall"): return
	check(mark_cleared(c,MP_KEY),"authority purges mirrored impact and material on demolition")
	var issued := s.fx.serial-serial
	var resources := expected_loss(c,sources)
	print("Host yield expected ",resources," issued ",issued," wood in bag and drops ",guest_collectible()-start)
	check(issued==1 and resources.keys()==["wood"] and guest_collectible()==start+int(resources.wood),"host issues exactly one wall yield")
	check(passage(c,MP_KEY,1),"host character crosses replicated breach")
	check(await until(func():return confirmed("wall-cleared")),"guest confirms missing collision and replicated yield")
	check(s.fx.serial==serial+issued and guest_collectible()==start+int(resources.wood),"no duplicate yield on either acknowledgement")
	if not check(s.save_now(false)==OK,"authority saves guest demolition"): return
	var saved: Dictionary=WastelandSave.read(1).diffs[WastelandTerrainGen.grid_key(SHORE)]
	check(saved.site_damage[MP_KEY]==0.0 and not saved.get("wall_marks",{}).has(MP_KEY),"authority saves gap without a stale impact")
	s.ui_command("marker",[Vector2(wall.x,wall.z),"wall-saved"])
	await until(func():return app.network.joined_members().is_empty(),5000)

func guest() -> void:
	if not check(app.network.connect_to("127.0.0.1",port)==OK,"guest starts ENet connection"): return
	if not check(await until(func():return is_instance_valid(app.session) and app.session.replica and app.session.stream.active.has(SHORE)),"guest streamed target POI"): return
	s=app.session
	var c: WastelandChunk=s.stream.active[SHORE]
	var wall := wall_point(c,MP_KEY)
	if not check(await until(func():
		aim(wall+Vector3.UP*1.46)
		return s.bag.current()=="sledge" and sees(c,MP_KEY)
	),"real guest camera acquires wall with sledge equipped"): return
	var start := guest_collectible()
	var sources := estimate(c)
	s.ui_command("marker",[Vector2(wall.x,wall.z),"wall-ready"])
	for stage in [1,2]:
		if not await report_guest_finish(c,stage,wall+Vector3((stage-1)*0.32,1.46,0)): return
	Input.action_press("fire")
	var removed := await until(func():
		aim(wall+Vector3.UP*1.46)
		return not c.structures.has(MP_KEY)
	)
	Input.action_release("fire")
	if not check(removed,"host replicates guest's wall removal"): return
	check(mark_cleared(c,MP_KEY),"guest purges replicated impact and material on demolition")
	var expected := expected_loss(c,sources)
	print("Guest yield expected ",expected," wood in bag and drops ",guest_collectible()-start)
	check(await until(func():return guest_collectible()==start+int(expected.wood),4000),"guest sees exactly one authoritative salvage yield")
	check(passage(c,MP_KEY,-1),"guest character crosses same breach from inside")
	s.ui_command("marker",[Vector2(wall.x,wall.z),"wall-cleared"])
	check(await until(func():return confirmed("wall-saved")),"guest receives authority's save acknowledgement")
