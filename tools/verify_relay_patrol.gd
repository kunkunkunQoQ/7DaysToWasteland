extends "res://tools/verify_frontier_economy.gd"

var app: Node

func press(prefix: String) -> bool:
	for button: Button in app.panels.content.find_children("*","Button",true,false):
		if button.text.begins_with(prefix) and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit()
			return true
	return false

func visit() -> void:
	var leg := s.Patrol.stop(s)
	var cell: Vector2i = leg.cell
	var at: Vector2 = s.Patrol.destination(s).at
	s.stream.ensure_landing(Vector3(at.x,0,at.y))
	await physics_frame
	await physics_frame
	var chunk: WastelandChunk = s.stream.active[cell]
	var locker: StaticBody3D = chunk.structures["dispatch/locker"][0]
	var before: int = s.progress.patrol.index
	match str(leg.task):
		"audit":
			for visual: Node3D in chunk.supply_caches.values():
				var box: StaticBody3D = visual.get_parent()
				if not aim(box): continue
				s._use()
				if is_instance_valid(s.loot_target):
					s.interaction = s._interaction_trace()
					s._tick_loot(s.loot_full + 0.1)
				if app.panels.visible: app.close_overlay()
				s.simulation_paused=true
				break
		"repair":
			check(aim(locker), "repair locker visible to first-person interaction")
			s._use()
			check(s.progress.patrol.index==before, "unstocked repairs cannot complete")
			s.bag.add("scrap",2)
			s.bag.add("fiber",1)
			s._use()
			check(s.bag.count("scrap")==0 and s.bag.count("fiber")==0,"repair consumes supplies")
		"listen":
			check(aim(locker), "working radio reachable")
			s._use()
			s.player.position.x+=13.0
			s.Patrol.tick(s)
			check(not s.progress.patrol.has("listen_until") and s.progress.patrol.index==before,"abandoning radio breaks contact")
			check(aim(locker),"return to restart radio")
			s._use()
			s.clock.advance(17)
			s.Patrol.tick(s)
			check(s.progress.patrol.index==before,"must keep listening for the whole transmission")
			s.clock.advance(1.1)
			s.Patrol.tick(s)
	check(s.progress.patrol.index==before+1, "%s advances once at a physical site" % leg.task)

func run() -> void:
	WastelandSave.root_override="user://verification/patrol-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	var flags:=OS.get_cmdline_user_args()
	if "--host" in flags or "--guest" in flags:
		await party("--host" in flags)
	else:
		await solo()
	if is_instance_valid(s):
		s.simulation_paused=true
		await s.stream.quiesce()
		await s.audio.finish_playback()
	app.network.stop()
	app.queue_free()
	await process_frame
	print("RELAY PATROL QA checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func create() -> void:
	cfg=WastelandSave.default_world()
	cfg.seed=2817
	cfg.start_id="grassland"
	app._enter_world(cfg,{},1,false)
	s=app.session
	s.simulation_paused=true
	at_board(s.starting_cell)

func solo() -> void:
	create()
	s.ui_command("patrol_start",[1])
	check(s.progress.patrol.is_empty(),"fresh campaign retains early survival pacing")
	s.progress.job=2
	app.open_panel("trade")
	check(press("登记第 1 趟巡线"),"midgame route begins through board UI")
	app.close_overlay()
	s.simulation_paused=true
	var first: Array = s.progress.patrol.stops.duplicate(true)
	check(first.size()==2 and first[0].cell!=first[1].cell,"midgame has two distinct locations")
	check(s.Patrol.reward(s.progress.patrol,"watch").get("round")==8,"midgame watch supplies fit the campaign pistol")
	await visit()
	s.clock.hours+=24
	check(s.save_now(false)==OK,"cross-day in-flight patrol written to disk")
	var saved:=WastelandSave.read(1)
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	s.simulation_paused=true
	check(s.progress.patrol.index==1 and s.progress.patrol.stops==first and app.hud.destination().at==s.Patrol.destination(s).at,"reopened checkpoint and compass resume second leg")
	await visit()
	at_board(s.starting_cell)
	s.ui_command("patrol_claim",[1,"unknown"])
	check(s.Patrol.completed(s)==0,"invalid crate cannot settle the route")
	app.open_panel("trade")
	check(press("工坊物资"),"workshop payout selected in journal UI")
	s.ui_command("patrol_claim",[1,"workshop"])
	check(s.Patrol.completed(s)==1 and s.bag.count("steel")==3,"single material payout despite duplicate claim")
	app.close_overlay()
	s.simulation_paused=true
	s.progress.job=s.catalog.quests.size()
	for serial in [2,3]:
		at_board(s.starting_cell)
		s.ui_command("patrol_start",[serial])
		var run:=s.progress.patrol
		var types:={}
		var cells:={}
		for leg: Dictionary in run.stops:
			types[leg.task]=true
			cells[leg.cell]=true
		check(types.size()==3 and cells.size()==3 and run.stops[0].cell!=first[0].cell,"postgame draws three distinct stops and task types")
		first=run.stops.duplicate(true)
		for i in 3: await visit()
		s.ui_command("patrol_claim",[serial,"watch"])
		check(s.Patrol.completed(s)==serial-1,"claim must reach a living noticeboard")
		at_board(s.starting_cell)
		s.ui_command("patrol_claim",[serial,"watch"])
	check(s.Patrol.completed(s)==3 and s.bag.count("heavy_round")==24 and s.bag.count("spring")==4,"repeatable watch pay and third-route bonus")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	cfg.terrain_revision=1
	cfg.site_revision=0
	app._enter_world(cfg,{"progress":{"job":6}},1,false)
	s=app.session
	s.simulation_paused=true
	at_board(WastelandSite.SHORE_CELL)
	s.ui_command("patrol_start",[1])
	check(s.progress.finish_day==-1 and s.progress.patrol.get("stops",[]).size()==3,"pre-patrol legacy world can immediately begin a postgame route")
	for leg: Dictionary in s.progress.patrol.stops:
		var cell: Vector2i=leg.cell
		var at:=Vector2(cell*WastelandTerrainGen.SIZE)+s.OutpostOrders.DEPOT
		s.stream.ensure_landing(Vector3(at.x,0,at.y))
		check(s.stream.active[cell].structures.has("dispatch/locker"),"legacy site has a physical relay cabinet")

func party(host: bool) -> void:
	var port:=19482
	app.set_process_input(false)
	if host:
		create()
		s.progress.job=s.catalog.quests.size()
		s.simulation_paused=false
		check(app.network.listen(port)==OK,"host opens shared patrol session")
		if not await until(func():return not app.network.joined_members().is_empty(),18.0):
			check(false,"guest joins")
			return
		app.network.joined_members()[0].survivor.global_position=s.player.global_position+Vector3.RIGHT
		if not await until(func():return not s.progress.patrol.is_empty(),15.0):
			check(false,"guest registered from board")
			return
		check(s.progress.patrol.stops.size()==3,"guest registers the team's three-stop route")
		for i in 3: await visit()
		at_board(s.starting_cell)
		app.network.joined_members()[0].survivor.global_position=s.player.global_position+Vector3.RIGHT
		s.simulation_paused=false
		var recipient: String = app.network.joined_members()[0].token
		check(await until(func():return s.Patrol.completed(s)==1,15.0),"guest cashes in host's field work")
		await until(func():return app.network.joined_members().is_empty(),10.0)
		check(s.save_now(false)==OK and WastelandSave.read(1).guests[recipient].bag.counts.get("steel")==4 and s.bag.count("steel")==0 and s.progress.records.get("relay_patrol")==1,"one patrol reward persists in the claimant's inventory")
	else:
		check(app.network.connect_to("127.0.0.1",port)==OK,"client connects")
		if not await until(func():return is_instance_valid(app.session) and app.session.replica,15.0):
			check(false,"client bootstrap")
			return
		s=app.session
		await until(func():return s.near_board(false))
		s.ui_command("patrol_start",[1])
		check(await until(func():return not s.progress.patrol.is_empty() and s.progress.patrol.index==3 and s.near_board(false),22.0),"client receives team itinerary and three finished field records")
		s.ui_command("patrol_claim",[1,"workshop"])
		s.ui_command("patrol_claim",[1,"workshop"])
		check(await until(func():return s.Patrol.completed(s)==1 and s.progress.patrol.is_empty() and s.bag.count("steel")==4),"client sees the same single payout")
