extends "res://tools/verify_chest_party.gd"

func station(id: String) -> Vector3i:
	for cell: Vector3i in app.session.construction.station_index:
		if app.session.construction.station_index[cell]==id: return cell
	return Vector3i.MAX

func record(cell: Vector3i) -> Dictionary:
	return app.session.construction.blocks.get(cell,{})

func arrange(s: WastelandSession,id: String) -> Vector3i:
	s.bag.add(id,1)
	var base := s.player.global_position
	for z in range(-5,6):
		for x in range(-4,5):
			var pt:=Vector3(floorf(base.x)+x+0.5,0,floorf(base.z)+z+0.5)
			var ground:=s.stream.ground_at(pt)
			var cell:=Vector3i(floori(pt.x),ceili(ground-0.42),floori(pt.z))
			if ground>0.4 and s.construction.place(cell,id,0,0,base): return cell
	return Vector3i.MAX

func position_guest(cell: Vector3i) -> bool:
	var s: WastelandSession=app.session
	var at:=WastelandConstruction.position_of(cell)
	for angle in 16:
		var point:=at+Vector3.BACK.rotated(Vector3.UP,TAU*angle/16.0)*1.75
		point.y=s.stream.ground_at(point)+0.08
		var q:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.50,at,3)
		if s.get_world_3d().direct_space_state.intersect_ray(q).get("collider")==s.construction.nodes[cell]:
			app.network.joined_members()[0].survivor.global_position=point
			app.network.joined_members()[0].survivor.velocity=Vector3.ZERO
			return true
	return false

func open_as_guest(cell: Vector3i) -> bool:
	if app.panels.visible: app.close_overlay()
	var s: WastelandSession=app.session
	var player:=s.player
	var at:=WastelandConstruction.position_of(cell)
	if not await until(func():return player.global_position.distance_to(at)<2.9): return false
	for attempt in 3:
		var direction:=at-player.camera.global_position
		player.rotation.y=atan2(-direction.x,-direction.z)
		player.pitch=atan2(direction.y,Vector2(direction.x,direction.z).length())
		player.eyes.rotation.x=player.pitch
		if not await until(func():return s.hint.contains(s.catalog.title(record(cell).device)),3000): continue
		Input.action_press("use")
		await physics_frame
		await physics_frame
		Input.action_release("use")
		if await until(func():return app.panels.visible and app.panels.active=="craft" and app.panels.current_context==cell,1800):
			return true
	return false

func host() -> void:
	var cfg: Dictionary=app._default_config()
	cfg.seed=27491
	cfg.start_id="grassland"
	app._enter_world(cfg,{},1,false)
	var s: WastelandSession=app.session
	s.hordes.next_herd=INF
	s.hordes.next_patrol=INF
	var forge:=arrange(s,"forge")
	var fire:=arrange(s,"campfire")
	if not check(forge!=Vector3i.MAX and fire!=Vector3i.MAX,"host places two physical stations"): return
	if not check(app.network.listen(port)==OK and await until(func():return not app.network.joined_members().is_empty()),"ENet guest joins"): return
	var member:WastelandLan.MemberState=app.network.joined_members()[0]
	for id: String in ["coal","wood","scrap","dirty_water"]:
		member.bag.add(id,8 if id=="scrap" else 2 if id=="dirty_water" else 1)
	var host_near:=WastelandConstruction.position_of(forge)+Vector3.BACK*2.3
	host_near.y=s.stream.ground_at(host_near)+0.08
	s.player.global_position=host_near
	var away:=WastelandConstruction.position_of(forge)+Vector3.RIGHT*12
	away.y=s.stream.ground_at(away)+0.08
	app.network.joined_members()[0].survivor.global_position=away
	flag("far")
	if not check(await until(func():return s.marker_records.size()==1),"guest's ordinary marker acknowledges ordered requests"): return
	check(record(forge).fuel==0.0 and not record(forge).has("smelt_input") and not record(forge).enabled and record(fire).queue.is_empty() and member.bag.count("coal")==1 and member.bag.count("scrap")==8,"out-of-reach requests leave both stations and the guest bag intact")
	s.player.global_position=away
	if not check(position_guest(forge),"guest stands within reach of forge"): return
	flag("forge")
	if not check(await acknowledged("forged"),"guest completed forge interactions"):return
	check(not record(forge).enabled and record(forge).queue.size()==1 and record(forge).molten.scrap==0 and member.bag.count("scrap")==0,"host sees forge job paid from guest supplies")
	if not check(position_guest(fire),"guest stands within reach of campfire"):return
	flag("stove")
	if not check(await acknowledged("cooked"),"guest collected boiled water"):return
	check(record(fire).queue.is_empty() and record(fire).out.is_empty() and member.bag.count("clean_water")==1 and member.bag.count("dirty_water")==1 and s.bag.count("clean_water")==0,"output and one refund reach the guest")
	check(s.save_now(false)==OK,"host saves shared stations")
	var saved:=WastelandSave.read(1)
	check(saved.construction.blocks[forge]==record(forge) and saved.construction.blocks[fire]==record(fire) and saved.bag.counts==s.bag.counts and saved.guests[member.token].bag.counts==member.bag.counts,"disk contains the authoritative stations and distinct host and guest inventories")
	flag("saved")
	await acknowledged("finished")

func guest() -> void:
	if not check(app.network.connect_to("127.0.0.1",port)==OK and await until(func():return app.session.replica and station("forge")!=Vector3i.MAX and station("campfire")!=Vector3i.MAX),"client mirrors both installed stations"):return
	var s: WastelandSession=app.session
	var forge:=station("forge")
	var fire:=station("campfire")
	if not await acknowledged("far"): return
	s.ui_command("feed_fire",[forge,"coal"])
	s.ui_command("smelt_input",[forge,"scrap"])
	s.ui_command("enable",[forge])
	s.ui_command("craft",["clean_water",1,fire])
	s.ui_command("marker",[Vector2.ONE,"工作台距离检查"])
	if not await acknowledged("forge"): return
	if not check(await open_as_guest(forge),"guest opens forge with use and authority aim trace"):return
	s.ui_command("smelt_input",[forge,"scrap"])
	s.ui_command("feed_fire",[forge,"coal"])
	if not check(await until(func():return record(forge).get("smelt_input",{}).get("count",0)==8 and record(forge).fuel==100 and not record(forge).enabled),"guest deposits ore and separate unlit coal"): return
	s.ui_command("enable",[forge])
	if not check(await until(func():return int(record(forge).get("molten",{}).get("scrap",0))==8),"guest sees real thermal conversion to eight units"): return
	s.ui_command("enable",[forge])
	if not check(await until(func():return not record(forge).enabled),"guest pauses furnace"):return
	s.ui_command("craft",["ingot",1,forge])
	if not check(await until(func():return record(forge).queue.size()==1 and record(forge).molten.scrap==0),"guest reserves internal metal in a timed forge job"):return
	var ticket_id: int=record(forge).queue[0].ticket
	s.ui_command("cancel",[forge,ticket_id])
	s.ui_command("cancel",[forge,ticket_id])
	if not check(await until(func():return record(forge).queue.is_empty() and record(forge).molten.scrap==8 and s.bag.count("scrap")==0),"repeated cancel refunds molten stock once to the same furnace"):return
	s.ui_command("craft",["ingot",1,forge])
	if not check(await until(func():return record(forge).queue.size()==1),"remote furnace holds a paid job for disk verification"):return
	app.close_overlay()
	flag("forged")
	if not await acknowledged("stove"): return
	if not check(await open_as_guest(fire),"guest opens campfire by use within reach"):return
	s.ui_command("feed_fire",[fire,"wood"])
	s.ui_command("craft",["clean_water",2,fire])
	if not check(await until(func():return record(fire).queue.size()==2 and record(fire).fuel==38),"guest loads wood and pays for two cooking jobs"):return
	s.ui_command("cancel",[fire,record(fire).queue[0].ticket])
	s.ui_command("enable",[fire])
	if not check(await until(func():return record(fire).out.get("clean_water",0)==1),"lit campfire cooks exactly the surviving order"):return
	s.ui_command("collect",[fire])
	if not check(await until(func():return s.bag.count("clean_water")==1 and s.bag.count("dirty_water")==1 and record(fire).out.is_empty()),"guest receives water and refunded raw input"):return
	flag("cooked")
	check(await acknowledged("saved"),"host confirms the saved state")
	flag("finished")
