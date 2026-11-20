extends SceneTree

const T := preload("res://game/world/terrain_gen.gd")
const SEEDS := [2817,-9251,182]
const REQUIRED := ["meadow","taiga","alpine","mesa","marsh","canyon","desert"]
var climate_points:={}
var passed:=0
var failures:=0
var session: WastelandSession
var app: Node
var port:=19167

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	WastelandSave.root_override="user://verification/open-world-%d"%OS.get_process_id()
	var flags:=OS.get_cmdline_user_args()
	for value in flags:
		if value.begins_with("--port="):port=int(value.get_slice("=",1))
	if "--host" in flags or "--guest" in flags:
		await loopback("--host" in flags)
	else:
		historic_heights()
		var patterns:={}
		for seed_value: int in SEEDS:
			var gen:=T.new(seed_value)
			var sample:=regions(gen)
			if seed_value==SEEDS[0]:climate_points=sample
			var signature := []
			for i in 14:
				signature.append(roundi(gen.raw_height(-2140+i*87,1050+i*33)))
			patterns[str(signature)]=true
			check(not sample.is_empty(),"regional survey finished for seed "+str(seed_value))
			check(reachable_climates(gen),"sampled terrain route to desert and alpine from each starting district")
			edges(gen,Vector2i(-39,22))
			edges(gen,gen.starting_outpost("seeded"))
		check(patterns.size()==SEEDS.size(),"seeds produce different distant elevation profiles")
		await save_route()
	if is_instance_valid(session):
		session.simulation_paused=true
		await session.stream.quiesce()
		if is_instance_valid(session.audio):await session.audio.finish_playback()
	if is_instance_valid(app):
		app.network.stop()
		app.queue_free()
	elif is_instance_valid(session): session.queue_free()
	await process_frame
	print("OPEN WORLD QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)

func historic_heights() -> void:
	var coords:=[Vector2(9,44),Vector2(-120,31),Vector2(34,-152),Vector2(-1748,743)]
	var old:=[[6.850723,0.700000,5.048512,0.700000],[6.850723,16.929532,42.307875,11.848639]]
	for revision in [1,2]:
		var gen:=T.new(2817,revision)
		var correct:=true
		for i in coords.size():correct=correct and absf(gen.ground(coords[i].x,coords[i].y)-float(old[revision-1][i]))<0.002
		check(correct,"revision %d retains four pre-expansion heights on both axes"%revision)

func regions(gen: WastelandTerrainGen) -> Dictionary:
	var start:=gen.starting_outpost("seeded")
	var center:=Vector2(start*T.SIZE)+Vector2(16,16)
	var options:={}
	for mode in ["grassland","foothills","seeded"]:
		var cell:=gen.starting_outpost(mode)
		var p:=Vector2(cell*T.SIZE)+Vector2(16,16)
		options[mode]=cell
		check(gen.site_for(cell)=="lodge" and gen.ground(p.x,p.y)>0.5 and p.distance_to(T.START)>180 and gen.starting_outpost(mode)==cell,"dry inland lodge for "+mode+" seed "+str(gen.seed_value))
	check(options.grassland!=options.foothills and start in [options.grassland,options.foothills],"distinct outpost choices and deterministic seeded selection")
	var found:={}
	var sites:={}
	var waters:=[]
	for z in range(-1536,1537,48):
		for x in range(-1536,1537,48):
			var p:=center+Vector2(x,z)
			var cell:=T.chunk_at(p)
			var site:=gen.site_for(cell)
			if not site.is_empty():sites[site]=true
			var region:=gen.region_kind(p.x,p.y)
			var h:=gen.ground(p.x,p.y)
			if h>1.0 and (not found.has(region) or (region=="alpine" and h>gen.ground(found[region].x,found[region].y))):
				found[region]=p
			if h < -0.45 and gen.water_basin(p.x,p.y) and p.distance_to(T.START)>350 and waters.size()<3:waters.append(p)
	check(REQUIRED.all(func(id):return found.has(id)),"all seven terrestrial regions walkable within 1.54 km on each axis; seed "+str(gen.seed_value)+" found "+str(found.keys()))
	check(sites.size()>=4 and not waters.is_empty(),"multiple regional sites and distant natural water")
	if found.has("alpine") and found.has("desert"):
		var snow:Vector2=found.alpine
		var sand:Vector2=found.desert
		var snow_y:=gen.ground(snow.x,snow.y)
		var sand_y:=gen.ground(sand.x,sand.y)
		var snow_color:=gen.ground_color(snow.x,snow.y,snow_y)
		var sand_color:=gen.ground_color(sand.x,sand.y,sand_y)
		check(snow_color.to_html()!=sand_color.to_html() and gen.temperature_offset(snow.x,snow.y)+4.0<gen.temperature_offset(sand.x,sand.y),"actual snow and sand surfaces and their thermal offsets differ")
	return found

func reachable_climates(gen: WastelandTerrainGen) -> bool:
	# Walk or swim between samples, rejecting segments steeper than the survivor can climb.
	var start:=Vector2(gen.starting_outpost("seeded")*T.SIZE)+Vector2(16,26)
	var queue: Array[Vector2i]=[Vector2i.ZERO]
	var visited:={Vector2i.ZERO:true}
	var reached:={}
	var cursor:=0
	while cursor<queue.size():
		var offset:=queue[cursor]
		cursor+=1
		var origin:=start+Vector2(offset*32)
		var climate:=gen.region_kind(origin.x,origin.y)
		if climate in ["alpine","desert"] and gen.ground(origin.x,origin.y)>1.0:
			reached[climate]=true
			if reached.size()==2:return true
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:Vector2i=offset+direction
			if maxi(absi(next.x),absi(next.y))>48 or visited.has(next):continue
			var accessible:=true
			var previous:=origin
			var last:=maxf(0.0,gen.ground(origin.x,origin.y))
			for j in range(1,9):
				var at:=origin+Vector2(direction)*4.0*j
				var h:=gen.ground(at.x,at.y)
				if h<0.0 and not gen.water_basin(at.x,at.y):
					accessible=false
					break
				h=maxf(0.0,h)
				if absf(h-last)>previous.distance_to(at)*tan(deg_to_rad(48.0)):
					accessible=false
					break
				last=h
				previous=at
			if accessible:
				visited[next]=true
				queue.append(next)
	return false

func edges(gen: WastelandTerrainGen, cell: Vector2i) -> void:
	var middle:PackedVector3Array=gen.build(cell,{},false).points
	var east:PackedVector3Array=gen.build(cell+Vector2i.RIGHT,{},false).points
	var south:PackedVector3Array=gen.build(cell+Vector2i.DOWN,{},false).points
	var equal:=true
	for i in T.GRID:
		equal=equal and is_equal_approx(middle[i*T.GRID+T.GRID-1].y,east[i*T.GRID].y) and is_equal_approx(middle[(T.GRID-1)*T.GRID+i].y,south[i].y)
	check(equal,"all shared edge vertices match at "+str(cell))

func new_world(snapshot: Dictionary={}) -> void:
	var cfg:=WastelandSave.default_world()
	cfg.seed=SEEDS[0]
	if not snapshot.is_empty():cfg=snapshot.settings
	session=WastelandSession.new()
	root.add_child(session)
	var options:=WastelandSettings.new()
	options.storage_path=WastelandSave.root_override+"/settings.cfg"
	options.load_options()
	session.configure(cfg,snapshot,1,WastelandCatalog.new(),options)
	session.simulation_paused=true

func remote_field(gen: WastelandTerrainGen) -> Vector2i:
	for z in range(12):
		for x in range(12):
			var cell:=Vector2i(-97+x,-81+z)
			var p:=cell*T.SIZE+Vector2i(12,13)
			if gen.site_for(cell).is_empty() and gen.ground(p.x,p.y)>1.2:
				return p
	return Vector2i.ZERO

func distant_water(gen: WastelandTerrainGen) -> Vector2:
	var field:=remote_field(gen)
	for z in range(-1536,1537,31):
		for x in range(-1536,1537,31):
			var p:=Vector2(field)+Vector2(x,z)
			if gen.water_basin(p.x,p.y) and gen.ground(p.x,p.y)<-1.0:return p
	return Vector2.INF

func save_route() -> void:
	new_world()
	var start:=session.start_position()
	var gen:=session.stream.generator
	var field:=remote_field(gen)
	var at:=Vector3(field.x,0,field.y)
	session.stream.ensure_landing(at)
	var before:=session.stream.ground_at(at)
	check(field.x<0 and field.y<0 and session.stream.excavate(at),"excavate a marked site kilometers away in a negative quadrant")
	var key:=T.grid_key(field)
	session.player.global_position=Vector3(at.x,before+0.2,at.z)
	session.add_marker(Vector2(field),"远方营地")
	check(session.save_now(false)==OK,"save normal world while at the distant site")
	var saved:=WastelandSave.read(1)
	await session.stream.quiesce()
	await session.audio.finish_playback()
	session.queue_free()
	await process_frame
	new_world(saved)
	session.stream.ensure_landing(at)
	check(session.player.global_position.distance_to(Vector3(at.x,before+0.2,at.z))<0.1 and session.stream.digs.has(key) and absf(session.stream.ground_at(at)-(before-0.58))<0.003 and session.marker_records.size()==1,"saved player, marker and changed ground restore far from the origin")
	session.stream.refresh(at,1)
	session.stream.refresh(start,1)
	check(not session.stream.active.has(T.chunk_at(Vector2(field))),"travel back to the outpost actually unloads the distant terrain")
	session.stream.ensure_landing(start)
	session.stream.refresh(at,1)
	session.stream.ensure_landing(at)
	check(absf(session.stream.ground_at(at)-(before-0.58))<0.003,"returning to the marked tile preserves the excavation")
	var wet:=distant_water(gen)
	if wet.is_finite():
		var p:=Vector3(wet.x,-0.5,wet.y)
		session.stream.ensure_landing(p)
		check(session.stream.water_at(p) and not session.stream.water_at(at),"stream water query agrees on distant water and dry camp")
	else:check(false,"find distant water")
	var temperatures:={}
	for climate in ["desert","alpine"]:
		var position_xz:Vector2=climate_points[climate]
		var position3:=Vector3(position_xz.x,0,position_xz.y)
		session.stream.refresh(position3,1)
		session.stream.ensure_landing(position3)
		position3.y=session.stream.ground_at(position3)
		session.player.position=position3+Vector3.UP*0.2
		await physics_frame
		await physics_frame
		var ray:=PhysicsRayQueryParameters3D.create(position3+Vector3.UP*2.0,position3+Vector3.DOWN*2.0,1)
		var hit:=session.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider.get_meta("kind","")=="terrain" and absf(hit.position.y-position3.y)<0.10,"actual walkable collision in the "+climate+" district")
		session.player._survival(0.31)
		temperatures[climate]=session.player.ambient
		var expected:=session.clock.temperature()+session.stream.generator.temperature_offset(position3.x,position3.z)-maxf(0.0,session.player.position.y-11.0)*0.14
		expected-=preload("res://game/world/expedition_sites.gd").pass_wind(session.stream.generator,session.player.global_position)
		check(absf(session.player.ambient-expected)<1.6,"survivor experiences local climate at "+climate)
	check(float(temperatures.alpine)<float(temperatures.desert)-5.0,"player experiences colder air on the snow mountain than in the desert")
	await biome_supplies()

func biome_supplies() -> void:
	var desert_point: Vector2=climate_points.desert
	var desert:=T.chunk_at(desert_point)
	var cactus: StaticBody3D
	for dx in range(-2,3):
		for dz in range(-2,3):
			var cell:=desert+Vector2i(dx,dz)
			var center:=Vector2(cell*T.SIZE)+Vector2(16,16)
			if session.stream.generator.region_kind(center.x,center.y)!="desert":continue
			session.stream.ensure_landing(Vector3(center.x,0,center.y))
			for node in session.stream.active[cell].decoration_root.get_children():
				if node.get_meta("resource","")=="cactus":
					cactus=node
					break
			if cactus!=null:break
		if cactus!=null:break
	if cactus==null:
		check(false,"generated desert has reachable fruiting cacti")
		return
	var location:=cactus.global_position
	session.player.global_position=location+Vector3.BACK*1.35
	session.player.position.y=session.stream.ground_at(session.player.position)+0.10
	await physics_frame
	aim_at(location)
	session.bag.assign("",0)
	session.bag.active=0
	check(session._trace(2.58,15).get("collider")==cactus,"empty-hand attack targets an actual generated fruiting cactus")
	for i in 6:
		if not is_instance_valid(cactus) or cactus.is_queued_for_deletion():break
		attack()
	collect_nearby_drops()
	var count:=session.bag.count("cactus_fruit")
	var thirst:=session.player.hydration
	session.ui_command("consume",["cactus_fruit"])
	check(count>=2 and session.bag.count("cactus_fruit")==count-1 and session.player.hydration>thirst,"harvested cactus fruit can be eaten and restores water")
	var clock_before:=session.clock.hours
	var thirst_rate:=[]
	for hour in [3.0,14.0]:
		session.clock.hours=hour
		var before:=session.player.hydration
		session.player._survival(1.0)
		thirst_rate.append(before-session.player.hydration)
	session.clock.hours=clock_before
	check(thirst_rate[1]>thirst_rate[0],"unshaded desert daylight consumes water faster than desert night")
	check(not session._fresh_snow(location),"desert sand cannot supply alpine snow")

	# The fixture supplies common recipe ingredients. Tools, campfire, snow and water use game actions.
	for id in {"wood":11,"stone":13,"fiber":2}:
		session.bag.add(id,{"wood":11,"stone":13,"fiber":2}[id])
	for id in ["shovel","campfire"]:
		session.ui_command("craft",[id,1,null])
		session.clock.advance(5.0)
		session._finish_crafting()
	var snow_point:=Vector2.INF
	var summit:Vector2=climate_points.alpine
	for x in range(-24,25,3):
		for z in range(-24,25,3):
			var pos:=summit+Vector2(x,z)
			var height:=session.stream.generator.ground(pos.x,pos.y)
			if session._fresh_snow(Vector3(pos.x,height,pos.y)):
				snow_point=pos
				break
		if snow_point.is_finite():break
	if not snow_point.is_finite():
		check(false,"find fresh snow beneath the alpine snowline shader")
		return
	var at:=Vector3(snow_point.x,0,snow_point.y)
	session.stream.refresh(at,1)
	session.stream.ensure_landing(at)
	at.y=session.stream.ground_at(at)
	session.player.global_position=at+Vector3.BACK*0.55+Vector3.UP*0.08
	await physics_frame
	aim_at(at)
	attack()
	check(session.bag.count("packed_snow")==0,"empty hands cannot dig snow")
	session.ui_command("assign",["shovel"])
	session.interaction=session._interaction_trace()
	session._update_prompt("shovel")
	check(session.hint.contains("铲取积雪"),"pointing a crafted shovel at the snowy ground offers snow collection")
	attack()
	collect_nearby_drops()
	var snow:=session.bag.count("packed_snow")
	attack()
	collect_nearby_drops()
	check(snow==2 and session.bag.count("packed_snow")==2 and session.bag.count("clay")>=2,"shovel removes one snow layer, then excavates normal ground underneath")

	var fire_cell:=Vector3i.ZERO
	var placed:=false
	for x in range(-3,4):
		for z in range(-3,4):
			var offset:=at+Vector3(x,0,z)
			var cell:=Vector3i(floori(offset.x),ceili(session.stream.ground_at(offset)-0.42),floori(offset.z))
			if session.construction.place(cell,"campfire",0,0,session.player.global_position):
				fire_cell=cell
				placed=true
				break
		if placed:break
	if not placed:
		check(false,"place the crafted campfire within reach")
		return
	session.ui_command("craft",["melt_snow",1,fire_cell])
	check(session.construction.blocks[fire_cell].queue.size()==1 and session.bag.count("packed_snow")==0,"campfire recipe consumes the two gathered snow portions")
	session.clock.advance(8.0)
	session.construction.simulate(0.35)
	session.ui_command("collect",[fire_cell])
	check(session.bag.count("clean_water")==1,"collect one boiled clean water from the campfire output")
	check(session.save_now(false)==OK and WastelandSave.read(1).digs.has(T.grid_key(Vector2i(roundi(at.x),roundi(at.z)))),"saving records the harvested snow layer")
	session.bag.add("medicinal_herb",2)
	session.bag.add("wood",1)
	session.bag.add("berries",2)
	session.bag.add("cooked_meat",1)
	session.ui_command("craft",["herbal_tea",1,fire_cell])
	session.ui_command("craft",["trail_ration",1,null])
	session.clock.advance(7)
	session._finish_crafting()
	session.construction.simulate(0.5)
	session.ui_command("collect",[fire_cell])
	check(session.bag.count("herbal_tea")==1 and session.bag.count("trail_ration")==1,"craft herbal tea at the campfire and assemble trail rations by hand")
	var player:=session.player
	player.body_temp=35.0
	player._survival(0.5)
	var unprotected:=player.body_temp
	player.stamina=30.0
	player._walk(0.10,Vector2.ZERO,false)
	var normal_recovery:=player.stamina-30.0
	session.ui_command("consume",["herbal_tea"])
	session.ui_command("consume",["trail_ration"])
	player.stamina=30.0
	player._walk(0.10,Vector2.ZERO,false)
	player.body_temp=35.0
	player._survival(0.5)
	check(player.body_temp>unprotected and is_equal_approx(player.stamina-30.0-normal_recovery,0.4),"warm drink limits cold loss and ration increases actual walking stamina recovery")
	for i in 15:player.simulate(1.0/60.0,false)
	var left:=Vector2(player.warm_drink_left,player.ration_left)
	check(left.x<120.0 and left.y<90.0 and left.y>89.0,"provision effects count down in simulation time")
	check(session.save_now(false)==OK,"save partially consumed provision durations")
	var effects_save:=WastelandSave.read(1)
	await session.stream.quiesce()
	await session.audio.finish_playback()
	session.queue_free()
	await process_frame
	new_world(effects_save)
	player=session.player
	check(Vector2(player.warm_drink_left,player.ration_left).is_equal_approx(left),"reopening the save preserves both provision durations")
	var last_seconds:=player.snapshot()
	last_seconds.provisions=Vector2(0.03,0.03)
	player.restore_vitals(last_seconds)
	for frame in 4:player.simulate(1.0/60.0,false)
	check(player.warm_drink_left==0.0 and player.ration_left==0.0,"both temporary bonuses expire on ordinary simulation ticks")
	var legacy:=player.snapshot()
	legacy.erase("provisions")
	player.restore_vitals(legacy)
	check(player.warm_drink_left==0.0 and player.ration_left==0.0,"older saves have no phantom provision bonuses")
	for id in ["cactus_fruit","packed_snow","herbal_tea","trail_ration"]:
		var icon:=WastelandItemArt.icon(id,session.catalog.items[id])
		check(icon.get_image().get_used_rect().get_area()>200 and WastelandItemArt.mesh(id,session.catalog.items[id]).get_faces().size()>36,"visible resource icon and held mesh for "+id)

func aim_at(point: Vector3) -> void:
	var ray:=point-session.player.camera.global_position
	session.player.rotation.y=atan2(-ray.x,-ray.z)
	session.player.pitch=atan2(ray.y,Vector2(ray.x,ray.z).length())
	session.player.eyes.rotation.x=session.player.pitch
	session.player.camera.force_update_transform()

func attack() -> void:
	session.action_lock=maxf(0.0,session.action_lock-1.0)
	Input.action_press("fire")
	session._process_controls(0.08)
	Input.action_release("fire")

func collect_nearby_drops() -> void:
	for id: String in session.fx.drop_records.keys():
		var point: Vector3 = session.fx.drop_records[id].point
		if session.player.position.distance_to(point) < 3.5:
			session.fx.take_drop(id)

func loopback(host: bool) -> void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process_input(false)
	if host:
		var cfg:=WastelandSave.default_world()
		cfg.seed=SEEDS[0]
		app._enter_world(cfg,{},1,false)
		session=app.session
		var actual_spawn:Vector2=session.world_settings.spawn_point
		session.add_marker(actual_spawn,"主机开局实测")
		check(session.start_position().distance_to(session.player.position)<2,"host begins at stored wilderness landing")
		check(app.network.listen(port)==OK,"expedition host listens")
		if not await wait_until(func():return not app.network.joined_members().is_empty(),10.0):check(false,"guest joins");return
		var f:=remote_field(session.stream.generator)
		var at:=Vector3(f.x,0,f.y)
		session.stream.ensure_landing(at)
		at.y=session.stream.ground_at(at)+0.2
		session.player.global_position=at
		app.network.joined_members()[0].survivor.global_position=at+Vector3.RIGHT*1.8
		for hit in 12: session.stream.excavate(at)
		session.add_marker(Vector2(f),"远征营地")
		check(await wait_until(func():return session.marker_records.any(func(m):return m.name=="远征到达"),12.0),"remote guest confirms matching excavation and position")
		check(session.save_now(false)==OK and WastelandSave.read(1).guests.has(app.network.joined_members()[0].token),"save both long-distance travelers")
		var home:=session.start_position()
		session.stream.ensure_landing(home)
		session.player.global_position=home
		app.network.joined_members()[0].survivor.global_position=home+Vector3.RIGHT*1.8
		check(await wait_until(func():return session.marker_records.any(func(m):return m.name=="返站确认"),10.0),"both travelers can return to the inland station")
		session.stream.ensure_landing(at)
		session.player.global_position=at
		app.network.joined_members()[0].survivor.global_position=at+Vector3.RIGHT*1.8
		check(await wait_until(func():return session.marker_records.any(func(m):return m.name=="复访确认"),10.0),"guest revisits the previous distant edit after unloading it")
		await wait_until(func():return app.network.joined_members().is_empty(),4.0)
	else:
		check(app.network.connect_to("127.0.0.1",port)==OK,"expedition guest connects")
		if not await wait_until(func():return is_instance_valid(app.session) and app.session.replica,10.0):check(false,"bootstrap travels");return
		session=app.session
		check(await wait_until(func(): return session.marker_records.any(func(m): return m.name=="主机开局实测" and m.at==session.stream.generator.wild_start and m.at==session.world_settings.get("spawn_point")),8.0),"guest uses host random landing, without rerolling spawn")
		var f:=remote_field(session.stream.generator)
		var k:=T.grid_key(f)
		check(await wait_until(func():return session.stream.digs.has(k) and session.marker_records.any(func(m):return m.name=="远征营地") and Vector2(session.player.position.x,session.player.position.z).distance_to(Vector2(f))<5,12.0),"replica follows the party thousands of meters and receives distant edits")
		var at:=Vector3(f.x,0,f.y)
		check(await wait_until(func():return session.stream.at_surface(at) and absf(session.stream.ground_at(at)-(session.stream.generator.ground(f.x,f.y)-6.96))<0.003,7.0),"distant local terrain receives repeated excavation beyond the historic depth limit")
		session.ui_command("marker",[Vector2(f),"远征到达"])
		var home:=session.start_position()
		check(await wait_until(func():return session.player.position.distance_to(home)<6.0 and not session.stream.at_surface(at),10.0),"guest streams out the distant camp on return")
		session.ui_command("marker",[Vector2(home.x,home.z),"返站确认"])
		check(await wait_until(func():return Vector2(session.player.position.x,session.player.position.z).distance_to(Vector2(f))<6.0 and session.stream.at_surface(at) and session.stream.digs.has(k) and absf(session.stream.ground_at(at)-(session.stream.generator.ground(f.x,f.y)-6.96))<0.003,10.0),"revisited guest terrain restores its prior excavated collision surface")
		session.ui_command("marker",[Vector2(f),"复访确认"])
		await create_timer(0.4).timeout

func wait_until(predicate: Callable, timeout: float) -> bool:
	var until:=Time.get_ticks_msec()+roundi(timeout*1000.0)
	while Time.get_ticks_msec()<until:
		if predicate.call():return true
		await process_frame
	return false

func check(ok: bool, title: String) -> void:
	if ok:passed+=1;print("PASS ",title)
	else:failures+=1;printerr("FAIL ",title)
