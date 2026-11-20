extends "res://tools/verify_harvest.gd"

const SHORE := Vector2i(-1,1)
const POLICE := Vector2i(3,-1)

func fixture(coord: Vector2i, id: String) -> StaticBody3D:
	if not session.stream.active.has(coord):
		session.stream._install(coord,session.stream.generator.build(coord,{}))
	var chunk: WastelandChunk=session.stream.active[coord]
	return chunk.fixtures.get(chunk.object_key(id))

func shoot(body: Node3D, damage: float) -> void:
	session.projectile_hit("arrow",damage,{"position":body.global_position,"normal":Vector3.BACK,"collider":body},session.player)

func stock() -> Dictionary:
	var items: Dictionary={}
	for row: Dictionary in session.fx.drop_records.values():
		for id: String in row.items:
			items[id]=int(items.get(id,0))+int(row.items[id])
	return items

var app: Node

func run() -> void:
	var flags := OS.get_cmdline_user_args()
	if "--host" in flags or "--guest" in flags:
		await network_test("--host" in flags,flags)
		return
	WastelandSave.root_override="user://verification/fixtures-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.seed=2817
	config.terrain_revision=2
	open_world({})
	var chest:=fixture(SHORE,"container/0")
	var key: String=chest.get_meta("key")
	var initial_hp:=float(chest.get_meta("hp"))
	session.player.camera.global_position=chest.global_position+Vector3(0,0,1.15)
	session.player.camera.look_at(chest.global_position)
	await physics_frame
	session._melee({},1)
	var partial:=float(chest.get_meta("hp"))
	check(partial>0 and partial<initial_hp,"aimed bare-hand swing damages an unopened chest")
	check(not session.stream.chunk_diff(SHORE).get("containers",{}).has(key),"partial damage leaves unopened loot untouched")
	var partial_delta:=session.stream.diffs.duplicate(true)
	check(session.save_now(false)==OK,"save partial fixture health")
	await close_world()
	open_world(WastelandSave.read(1))
	chest=fixture(SHORE,"container/0")
	check(is_equal_approx(float(chest.get_meta("hp")),partial),"partial damage returns from disk")
	var before:=stock()
	shoot(chest,2000)
	var dropped:=stock()
	check(chest.is_queued_for_deletion() and not dropped.is_empty() and dropped!=before,"projectile destroys unopened chest and spills supplies")
	shoot(chest,2000)
	check(stock()==dropped and session.stream.chunk_diff(SHORE).containers[key].items.is_empty(),"repeat hit cannot duplicate contents")
	var used:=fixture(SHORE,"container/1")
	session.player.position=used.global_position+Vector3.BACK
	session._open_loot(used)
	var used_key:String=used.get_meta("key")
	session.bag.add("cloth",5)
	var deposited:=session.chest_move(used_key,"put","cloth",5)
	var withdrawn:=session.chest_move(used_key,"take","cloth",2)
	session.chest_close(used_key)
	check(deposited==5 and withdrawn==2,"a survivor deposits cloth and takes back two before breaking the chest")
	var remainder:Dictionary=session._container_record(used).items.duplicate()
	var casing:="wood" if used.get_meta("cache_profile","") in ["forest","alpine","shore","ferry"] else "scrap"
	var expected:=stock()
	for item:String in remainder: expected[item]=int(expected.get(item,0))+int(remainder[item])
	expected[casing]=int(expected.get(casing,0))+1
	shoot(used,2000)
	check(stock()==expected and session.stream.chunk_diff(SHORE).containers[used_key].items.is_empty(),"the half-looted chest drops its remaining cargo plus exactly one casing")
	shoot(used,2000)
	dropped=stock()
	check(dropped==expected,"repeated hits cannot duplicate the destroyed chest's casing or stored items")
	check(session.save_now(false)==OK,"save destroyed chest and spilled supplies")
	var destroyed_delta:=session.stream.diffs.duplicate(true)
	await close_world()
	open_world(WastelandSave.read(1))
	check(fixture(SHORE,"container/0")==null and stock()==dropped,"destroyed chest and drops persist")
	await close_world()
	open_world({})
	chest=fixture(SHORE,"container/0")
	session.stream.mirror_deltas(partial_delta,{})
	check(is_equal_approx(float(chest.get_meta("hp")),partial),"active replica reflects partial fixture damage")
	session.stream.mirror_deltas(destroyed_delta,{})
	check(fixture(SHORE,"container/0")==null and chest.is_queued_for_deletion(),"active replica removes destroyed chest")
	var board:=fixture(SHORE,"trader")
	session.player.position=board.global_position-Vector3.UP
	session.ui_command("job")
	check(session.progress.accepted,"accept first board contract")
	session.gain(1,"wood",20)
	shoot(board,2000)
	session.ui_command("job")
	check(session.near_board(true) and session.progress.job==0 and session.progress.accepted,"ruined board blocks completed contract delivery")
	session.ui_command("rebuild_board")
	check(fixture(SHORE,"trader")==null,"rebuild requires supplies")
	session.bag.add("wood",3)
	session.bag.add("fiber",2)
	session.ui_command("rebuild_board")
	check(session.near_board(false) and fixture(SHORE,"trader")!=null and session.bag.count("wood")==0,"journal rebuild consumes supplies and restores board")
	session.ui_command("job")
	session.ui_command("job")
	check(session.progress.job==1 and session.progress.accepted,"rebuilt board accepts delivery and next job")
	var safe:=fixture(POLICE,"container/99")
	session.player.position=safe.global_position
	session.progress.job=session.catalog.quests.size()-1
	session.progress.accepted=true
	shoot(safe,3000)
	var page_id: String=""
	for id: String in session.fx.drop_records:
		if session.fx.drop_records[id].items.has("beacon_log"): page_id=id
	check(not page_id.is_empty(),"destroyed quest safe spills mission log")
	if not page_id.is_empty():
		session.fx.take_drop(page_id)
		check(session.bag.count("beacon_log")==1,"spilled mission log can be picked up")
		session.bag.spend({"beacon_log":1})
	session.ui_command("recover_archive")
	session.ui_command("recover_archive")
	check(session.bag.count("beacon_log")==1,"journal recovers exactly one missing mission page at archive ruin")
	var ground:=Vector3(-18,3,51)
	session.player.position=ground
	check(session.construction.till(ground),"till plot")
	var cell:=WastelandConstruction.cell_at(ground+Vector3.UP*0.13)
	session.bag.add("seed_potato",1)
	session.construction.farm(cell,"seed_potato")
	var planted: StaticBody3D=session.construction.crop_nodes[cell]
	var seeds:=int(stock().get("seed_potato",0))
	shoot(planted,20)
	check(not session.construction.crops.has(cell) and planted.is_queued_for_deletion() and int(stock().get("seed_potato",0))==seeds+1,"uproot planted crop and recover its seed")
	session.fx.drop_records["test_buoy"]={"point":ground,"items":{"fiber":5},"buoy":true}
	session.fx._resync_drops()
	var buoy: StaticBody3D=session.fx.drop_live["test_buoy"]
	before=stock()
	shoot(buoy,500)
	check(not session.fx.drop_records.has("test_buoy") and stock()==before,"broken buoy spills its exact cargo")
	session.vehicle_records["test_bike"]={"type":"bicycle","point":ground,"yaw":0.0,"fuel":0.0}
	session._mount_vehicle("test_bike")
	var bike: WastelandVehicle=session.vehicles["test_bike"]
	shoot(bike,20)
	check(bike.record.hp>0 and bike.record.hp<bike.max_hp(),"vehicle takes partial projectile damage")
	session.player.ride(bike)
	var scrap:=int(stock().get("scrap",0))
	shoot(bike,3000)
	check(not session.vehicle_records.has("test_bike") and not session.vehicles.has("test_bike") and session.player.mount_vehicle==null and int(stock().get("scrap",0))==scrap+4,"destroyed vehicle dismounts and yields salvage")
	await close_world()
	print("FIXTURE QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)

func network_test(host: bool, flags: PackedStringArray) -> void:
	var port := 17494
	for flag in flags:
		if flag.begins_with("--port="): port=flag.get_slice("=",1).to_int()
	WastelandSave.root_override="user://verification/fixture-peer-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	app.network.local_token=Crypto.new().generate_random_bytes(16).hex_encode()
	if host:
		var settings: Dictionary=app._default_config()
		settings.terrain_revision=2
		app._enter_world(settings,{},1,false)
		session=app.session
		session.bag.add("wood",3)
		session.bag.add("fiber",2)
		check(app.network.listen(port)==OK,"host listens on selected ENet port")
		if await wait_for(func(): return not app.network.joined_members().is_empty()):
			var board:=fixture(SHORE,"trader")
			var at:=board.global_position+Vector3(1.9,-0.85,0)
			app.network.joined_members()[0].survivor.global_position=at
			app.network.joined_members()[0].survivor.velocity=Vector3.ZERO
			if await wait_for(func(): return session.marker_records.size()==1):
				shoot(board,4000)
				check(fixture(SHORE,"trader")==null,"host destroys board after guest sees it intact")
				check(await wait_for(func(): return fixture(SHORE,"trader")!=null),"authority restores board on guest request")
				check(session.bag.count("wood")==0 and session.bag.count("fiber")==0,"authority charges rebuilding supplies exactly once")
				check(await wait_for(func(): return session.marker_records.size()==2),"guest acknowledges rebuilt board")
			else: check(false,"guest acknowledged initial board")
		else: check(false,"host accepts guest")
	else:
		check(app.network.connect_to("127.0.0.1",port)==OK,"guest connects to loopback")
		if await wait_for(func(): return is_instance_valid(app.session) and app.session.replica):
			session=app.session
			check(await wait_for(func(): return session.near_board(false)),"guest reaches intact board on host")
			session.ui_command("marker",[Vector2.ZERO,"intact"])
			check(await wait_for(func(): return session.near_board(true) and fixture(SHORE,"trader")==null),"guest sees authoritative board disappear")
			var key_event:=InputEventAction.new()
			key_event.action="journal"
			key_event.pressed=true
			app._input(key_event)
			var button: Button
			for child in app.panels.content.find_children("*","Button",true,false):
				if child.text.begins_with("重建此处公告板"): button=child
			check(button!=null,"J journal offers ruin rebuild")
			if button: button.pressed.emit()
			check(await wait_for(func(): return session.near_board(false) and fixture(SHORE,"trader")!=null and session.bag.count("wood")==0),"guest mirrors restored board and consumed stock")
			session.ui_command("marker",[Vector2.ONE,"restored"])
			await create_timer(0.7).timeout
		else: check(false,"guest receives session")
	print("FIXTURE ENET %s passed=%d failed=%d"%["host" if host else "guest",passed,failures])
	app.network.stop()
	if is_instance_valid(app.session):
		app.session.simulation_paused=true
		await app.session.stream.quiesce()
		if is_instance_valid(app.session) and is_instance_valid(app.session.audio): await app.session.audio.finish_playback()
	quit(1 if failures else 0)

func wait_for(condition: Callable) -> bool:
	var end:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<end:
		if condition.call(): return true
		await process_frame
	return false
