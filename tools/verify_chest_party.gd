extends "res://tools/verify_lan_discovery.gd"

const CACHE_UI := preload("res://game/ui/chest_panel.gd")
const SHORE := WastelandSite.SHORE_CELL

func panel() -> Node:
	if not app.panels.visible or app.panels.active!="chest": return null
	for child in app.panels.body.get_children():
		if child.get_script()==CACHE_UI: return child
	return null

func quantity(side:String) -> int:
	var ui:=panel()
	if ui==null: return -1
	ui.refresh()
	for tile in ui.grids[side].get_children():
		if tile.item=="wood": return tile.quantity
	return 0

func press_one(side:String) -> bool:
	var ui:=panel()
	if not ui: return false
	for tile in ui.grids[side].get_children():
		if tile.item=="wood":
			tile.pressed.emit()
			await process_frame
			if ui.single.disabled: return false
			ui.single.pressed.emit()
			return true
	return false

func flag(stage:String) -> void:
	var output:=FileAccess.open(ticket+stage,FileAccess.WRITE)
	output.store_line(stage)
	output.close()

func acknowledged(stage:String) -> bool:
	return await until(func(): return FileAccess.file_exists(ticket+stage))

func tap_stack(side:String,mobile:bool) -> bool:
	for i in 2:
		var ui:=panel()
		if not ui: return false
		var at:=Vector2.ZERO
		for tile in ui.grids[side].get_children():
			if tile.item=="wood": at=tile.get_global_rect().get_center(); break
		if at==Vector2.ZERO: return false
		for down in [true,false]:
			if mobile:
				var touch:=InputEventScreenTouch.new()
				touch.position=root.get_final_transform()*at
				touch.pressed=down
				Input.parse_input_event(touch)
				Input.flush_buffered_events()
			else:
				var click:=InputEventMouseButton.new()
				click.position=at
				click.button_index=MOUSE_BUTTON_LEFT
				click.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
				click.pressed=down
				root.push_input(click,true)
			await process_frame
	return true

func exchange(is_host:bool) -> bool:
	var role:="host" if is_host else "guest"
	var peer:="guest" if is_host else "host"
	flag(role+"opened")
	if not check(await acknowledged(peer+"opened"),"both players see the opened chest"): return false
	if not is_host and not check(await tap_stack("chest",true),"guest double taps the actual chest tile by finger"): return false
	if not check(await until(func(): return quantity("chest")==0 and quantity("bag")==6),"both inventories show the complete guest transfer"): return false
	if not check(app.session.bag.bar.count("wood")==1,"guest pickup appears once on the shared hotbar"): return false
	flag(role+"received")
	if not check(await acknowledged(peer+"received"),"both players received the empty chest"): return false
	if is_host and not check(await tap_stack("bag",false),"host double clicks the real bag tile by mouse"): return false
	if not check(await until(func(): return quantity("chest")==6 and quantity("bag")==0),"both inventories show the complete return transfer"): return false
	for stage:String in ["take","put"]:
		var side:="chest" if stage=="take" else "bag"
		flag(role+stage)
		if not check(await acknowledged(peer+stage),"both panels ready for "+stage): return false
		if not check(await press_one(side),"select actual tile and click "+stage+" one"): return false
		var expected:=4 if stage=="take" else 6
		if not check(await until(func(): return quantity("chest")==expected),"both "+stage+" requests reconciled to "+str(expected)): return false
	return true

func host() -> void:
	var cfg:Dictionary=app._default_config()
	cfg.terrain_revision=3 if "--procedural" in OS.get_cmdline_user_args() else 2
	cfg.start_id="shore"
	cfg.name=world_name
	app._enter_world(cfg,{},1,false)
	var session:WastelandSession=app.session
	session.bag.add("hardhat",1)
	session.stream.ensure_landing(Vector3(-16,3,48))
	var chunk:WastelandChunk=session.stream.active[SHORE]
	var key:String=chunk.supply_caches.keys()[0]
	var model:Node3D=chunk.supply_caches[key]
	var body:StaticBody3D=model.get_parent()
	var diff:=session.stream.edit_chunk(SHORE)
	diff.containers={key:{"items":{"wood":6},"next":3,"earned":false}}
	var point:=body.global_position+Vector3.BACK
	session.player.global_position=point
	if not check(app.network.listen(port)==OK,"real ENet host listening"): return
	if not check(await until(func(): return is_instance_valid(app.network.member)),"guest joined"): return
	app.network.member.global_position=point
	session._open_loot(body)
	app.network._as_member(session,func(): session._open_loot(body))
	if not check(await until(func(): return quantity("chest")==6),"host panel displays six wood"): return
	if not await exchange(true): return
	if not check(await acknowledged("guestclosed"),"guest closed storage panel"): return
	if not check(await until(func(): return session.chest_key(true)=="" and session.chest_key()==key and model.opened),"guest close leaves host session and lid open"): return
	if not check(await press_one("chest") and quantity("chest")==5,"remaining host can still take one"): return
	app.close_overlay()
	check(not model.opened,"closing final viewer shuts lid")
	check(session.save_now(false)==OK,"host saved final transfer")
	app.network.stop()
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	session=app.session
	await process_frame
	session.stream.ensure_landing(Vector3(-16,3,48))
	chunk=session.stream.active[SHORE]
	body=chunk.supply_caches[key].get_parent()
	session.player.global_position=body.global_position+Vector3.BACK
	session._open_loot(body)

	check(await until(func(): return quantity("chest")==5 and quantity("bag")==1,2000),"reopened disk save shows five wood in chest and one in bag")

func guest() -> void:
	if not check(app.network.connect_to("127.0.0.1",port)==OK,"guest started ENet connection"): return
	if not check(await until(func(): return quantity("chest")==6),"remote chest panel opens through RPC with six visible wood"): return
	if not await exchange(false): return
	app.close_overlay()
	check(not app.panels.visible,"guest closed own panel")
	app.open_panel("bag")
	# Send two explicit equips before a new authority inventory snapshot can arrive.
	app.session.ui_command("quick_equip",["hardhat"])
	app.session.ui_command("quick_equip",["hardhat"])
	check(await until(func(): return app.session.bag.is_worn("hardhat")),"repeated remote equip requests leave the helmet worn")
	app.close_overlay()
	flag("guestclosed")
	await create_timer(1.0).timeout
