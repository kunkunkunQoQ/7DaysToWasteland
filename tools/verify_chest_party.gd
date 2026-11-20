extends "res://tools/verify_lan_discovery.gd"

const CACHE_UI := preload("res://game/ui/chest_panel.gd")
const SHORE := WastelandSite.SHORE_CELL
const CHECKPOINT_MARKER := "补给点"

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

func autosaved(key:String, token:String, host_wood:int, guest_wood:int, chest_wood:int, guest_head:String) -> bool:
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		var saved:=WastelandSave.read(1)
		var chunk:Dictionary=saved.get("diffs",{}).get(WastelandTerrainGen.grid_key(SHORE),{})
		var chest:Dictionary=chunk.get("containers",{}).get(key,{})
		var bag:Dictionary=saved.get("guests",{}).get(token,{}).get("bag",{})
		if chest.has("items") and bag.has("counts"):
			if (saved.bag.counts.get("wood",0)==host_wood
					and bag.counts.get("wood",0)==guest_wood
					and chest.items.get("wood",0)==chest_wood
					and bag.gear.head==guest_head):
				return true
		await create_timer(0.25).timeout
	return false

func saves_world_marker(session:WastelandSession, key:String, token:String) -> bool:
	var previous:=WastelandSave.read(1)
	var writes:Array[int]=[]
	session.stored.connect(func(saved_slot:int):writes.append(saved_slot), CONNECT_ONE_SHOT)
	session.ui_command("marker",[Vector2(12,21),CHECKPOINT_MARKER])
	var previous_speed:=Engine.time_scale
	Engine.time_scale=0.25
	var saved_world:=await until(func():return not writes.is_empty(),32000)
	Engine.time_scale=previous_speed
	if not check(saved_world,"world edits reach disk on a wall-clock deadline even while simulation time advances slowly"): return false
	var saved:=WastelandSave.read(1)
	if not check(saved.markers==session.marker_records and saved.markers.back().name==CHECKPOINT_MARKER,"the periodic world save records the new map marker without touching either bag"): return false
	var chunk_key:=WastelandTerrainGen.grid_key(SHORE)
	var same_supplies:bool=(saved.bag==previous.bag
			and saved.guests[token].bag==previous.guests[token].bag
			and saved.diffs[chunk_key].containers[key]==previous.diffs[chunk_key].containers[key])
	return check(same_supplies,"the marker, shared chest and both inventories belong to the same world checkpoint")

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
	# Dispatch both taps within the input window even on a slow headless renderer.
	await process_frame
	return true

func exchange(is_host:bool) -> bool:
	var role:="host" if is_host else "guest"
	var peer:="guest" if is_host else "host"
	flag(role+"opened")
	if not check(await acknowledged(peer+"opened"),"both players see the opened chest"): return false
	if not check(quantity("bag")== (3 if is_host else 0),"each panel opens on its owner's inventory"): return false
	if not is_host and not check(await tap_stack("chest",true),"guest double taps the actual chest tile by finger"): return false
	if not check(await until(func(): return quantity("chest")==0 and quantity("bag")==(3 if is_host else 6)),"guest receives all six wood while the host keeps its three"): return false
	if not check(app.session.bag.bar.count("wood")==1,"each player's wood appears once on its own hotbar"): return false
	flag(role+"received")
	if not check(await acknowledged(peer+"received"),"both players received the empty chest"): return false
	if is_host:
		var token:String=app.network.joined_members()[0].token
		if not check(await autosaved(app.session.chest_key(),token,3,6,0,""),"guest's pickup automatically saves both bags and the empty chest while both players are online"): return false
	if is_host and not check(await tap_stack("bag",false),"host double clicks the real bag tile by mouse"): return false
	if not check(await until(func(): return quantity("chest")==3 and quantity("bag")==(0 if is_host else 6)),"host deposits its three wood while the guest keeps its six"): return false
	for stage:String in ["take","put"]:
		var side:="chest" if stage=="take" else "bag"
		flag(role+stage)
		if not check(await acknowledged(peer+stage),"both panels ready for "+stage): return false
		if not check(await press_one(side),"select actual tile and click "+stage+" one"): return false
		var expected:=1 if stage=="take" else 3
		var personal:=(0 if is_host else 6)+int(stage=="take")
		if not check(await until(func(): return quantity("chest")==expected and quantity("bag")==personal),"both "+stage+" requests reconcile the chest and each player's bag"): return false
	return true

func host() -> void:
	var cfg:Dictionary=app._default_config()
	cfg.terrain_revision=3 if "--procedural" in OS.get_cmdline_user_args() else 2
	cfg.start_id="shore"
	cfg.name=world_name
	app._enter_world(cfg,{},1,false)
	var session:WastelandSession=app.session
	# Both players remain at the chest through a full world checkpoint.
	session.player.invulnerable=300.0
	session.bag.add("wood",3)
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
	if not check(await until(func(): return not app.network.joined_members().is_empty()),"guest joined"): return
	var member:WastelandLan.MemberState=app.network.joined_members()[0]
	member.survivor.invulnerable=300.0
	member.bag.add("hardhat",1)
	member.survivor.global_position=point
	session._open_loot(body)
	app.network._as_member(session,app.network.joined_members()[0],func(): session._open_loot(body))
	if not check(await until(func(): return quantity("chest")==6),"host panel displays six wood"): return
	if not await exchange(true): return
	if not check(await acknowledged("guestclosed"),"guest closed storage panel"): return
	if not check(await until(func(): return session.chest_key(app.network.joined_members()[0].peer_id)=="" and session.chest_key()==key and model.opened),"guest close leaves host session and lid open"): return
	if not check(await press_one("chest") and quantity("chest")==2,"remaining host can still take one"): return
	app.close_overlay()
	check(not model.opened,"closing final viewer shuts lid")
	if not check(await autosaved(key,member.token,1,6,2,"hardhat"),"subsequent transfers and equipped helmet are automatically written to the same world slot"): return
	var idle_writes:Array[int]=[]
	session.stored.connect(func(saved_slot:int):idle_writes.append(saved_slot))
	await create_timer(7.0).timeout
	if not check(idle_writes.is_empty(),"unchanged bags do not trigger another inventory save"): return
	if not await saves_world_marker(session,key,member.token): return
	# Preserve exactly the checkpoint written while both peers are online; an orderly
	# departure saves slot one again. Reopen the captured bytes through the host menu.
	if not check(DirAccess.copy_absolute(WastelandSave.path_for(1),WastelandSave.path_for(2))==OK,"capture the online autosave before asking either player to leave"): return
	flag("checkpoint")
	if not check(await until(func():return app.network.joined_members().is_empty()),"guest disconnects after online checkpoint is captured"): return
	app.network.stop()
	app.host_world(2,port)
	if not check(await until(func():return app.network.server() and app.session.slot==2),"host reopens the captured autosave from disk"): return
	session=app.session
	await process_frame
	session.stream.ensure_landing(Vector3(-16,3,48))
	chunk=session.stream.active[SHORE]
	body=chunk.supply_caches[key].get_parent()
	session.player.global_position=body.global_position+Vector3.BACK
	session._open_loot(body)

	check(await until(func(): return quantity("chest")==2 and quantity("bag")==1,2000),"reopened disk save shows two wood in chest and one in the host bag")
	check(session.marker_records.any(func(row):return row.name==CHECKPOINT_MARKER),"normal reload restores the map marker alongside the chest and bags")
	flag("reopened")
	if not check(await acknowledged("rejoined"),"returning client confirms its saved backpack and helmet"): return
	if not check(await until(func():return app.network.joined_members().is_empty()),"returning guest finishes before the host pauses offline"): return
	app.close_overlay()
	app._pause()
	if not check(app.set_world_shared(false)==OK and session.simulation_paused,"the host closes LAN and pauses the saved world"): return
	var paused_writes:Array[int]=[]
	session.stored.connect(func(saved_slot:int):paused_writes.append(saved_slot))
	await create_timer(32.0).timeout
	check(paused_writes.is_empty(),"a paused, already saved world stays idle through a full autosave period")

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
	if not check(await until(func():return FileAccess.file_exists(ticket+"checkpoint"),55000),"guest stays online through the inventory and world autosaves"): return
	app.leave_world()
	if not check(await until(func():return app.session.preview_only and not app.network.active()),"guest returns to title"): return
	if not check(await acknowledged("reopened") and app.network.connect_to("127.0.0.1",port)==OK,"same player joins the reopened world"): return
	if not check(await until(func():return app.session.replica and app.session.bag.count("wood")==6 and app.session.bag.is_worn("hardhat") and app.session.marker_records.any(func(row):return row.name==CHECKPOINT_MARKER)),"reconnect restores the guest's six wood, equipped helmet and world marker together"): return
	flag("rejoined")
