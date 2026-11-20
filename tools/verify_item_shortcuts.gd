extends "res://tools/verify_avatar_ui.gd"

func wait_for_gesture_time(seconds:float)->void:
	var deadline:=Time.get_ticks_msec()+ceili(seconds*1000.0)
	while Time.get_ticks_msec()<deadline: await process_frame
	await frames(12)

func tap_pair(grid:Control,id:String)->void:
	for i in 2:
		var pos:=gear_item(grid,id).get_global_rect().get_center()
		press(pos,true)
		await process_frame
		press(pos,false)
		await process_frame
	await frames(4)

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless":
		root.size=Vector2i(2400,1080) if mobile else Vector2i(1920,1080)
	WastelandSave.root_override="user://verification/item-gestures-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await frames()
	var cfg:Dictionary=app._default_config()
	cfg.seed=77026023
	cfg.start_id="grassland"
	app._enter_world(cfg,{},1,false)
	var s:WastelandSession=app.session
	s.set_physics_process(false)
	for id:String in ["stone_axe","hardhat","bandage","beacon_log"]: s.bag.add(id,1)
	s.ui_command("slot",[s.bag.bar.find("")])
	app.open_panel("bag")
	await frames(10)
	var p:WastelandPanels=app.panels
	var grid:=p.item_grid
	check(p.use_item_button.disabled and p.discard_button.disabled,"empty selection has no destructive action")
	await click(gear_item(grid,"stone_axe"))
	check(s.bag.current()=="" and p.selection=="stone_axe","single press selects without equipping")
	var pos:=gear_item(grid,"stone_axe").get_global_rect().get_center()
	press(pos,true)
	move(pos+Vector2(16,2),Vector2(16,2),true)
	await process_frame
	press(pos+Vector2(16,2),false)
	await frames(4)
	check(s.bag.current()=="","moving a held pointer does not complete a double tap")
	press(pos,true)
	await wait_for_gesture_time(0.48)
	press(pos,false)
	await process_frame
	await click(gear_item(grid,"stone_axe"))
	check(s.bag.current()=="","a long press followed by a tap cannot equip")
	await wait_for_gesture_time(0.48)
	await tap_pair(grid,"stone_axe")
	check(s.bag.current()=="stone_axe","two taps equip the selected tool")
	await tap_pair(grid,"hardhat")
	check(s.bag.gear.head=="hardhat","two taps wear armor")
	await tap_pair(grid,"hardhat")
	check(s.bag.gear.head=="hardhat","repeating armor shortcut does not undress")
	await tap_pair(grid,"bandage")
	check(s.bag.count("bandage")==1,"two taps never consume medicine")
	await click(gear_item(grid,"beacon_log"))
	check(p.discard_button.disabled,"quest item cannot be discarded")
	s.ui_command("discard",["beacon_log"])
	s.ui_command("discard",["beacon_log"])
	check(s.bag.count("beacon_log")==1,"authority rejects a direct quest discard twice")
	await click(gear_item(grid,"stone_axe"))
	await click(p.discard_button)
	check(s.bag.count("stone_axe")==1 and p.discard_button.text.contains("确认"),"first discard warns in place")
	app.close_overlay()
	app.open_panel("bag")
	await frames(4)
	await click(p.discard_button)
	check(s.bag.count("stone_axe")==1 and p.discard_button.text.contains("确认"),"a fresh panel requires its own confirmation")
	await wait_for_gesture_time(3.4)
	check(not p.discard_button.text.contains("确认"),"the timed confirmation label expires")
	await click(p.discard_button)
	check(s.bag.count("stone_axe")==1,"an expired confirmation starts a new warning")
	await click(p.discard_button)
	check(s.bag.count("stone_axe")==0,"explicit second discard drops one held item")
	app.close_overlay()
	var chunk:WastelandChunk=s.stream.active[s.stream.generator.starting_outpost("grassland")]
	var id:String=chunk.supply_caches.keys()[0]
	var box:StaticBody3D=chunk.supply_caches[id].get_parent()
	s.player.global_position=box.global_position+Vector3.BACK
	s._open_loot(box)
	var record:=s._container_record(box)
	record.items={"fiber":5}
	await create_timer(0.2).timeout
	var panel:Control
	for child in p.body.get_children():
		if child.get_script()==preload("res://game/ui/chest_panel.gd"): panel=child
	if not panel: check(false,"chest UI opened"); quit(1); return
	var bag_grid:Rect2=panel.grids.bag.get_global_rect()
	var chest_grid:Rect2=panel.grids.chest.get_global_rect()
	var viewport:=root.get_visible_rect()
	check(panel.grids.bag.columns==9 and panel.grids.bag.get_child_count()==s.bag.capacity(),"chest view uses the equipped backpack's nine-slot rows")
	print("CHEST LAYOUT window=",root.size," viewport=",viewport," bag=",bag_grid," chest=",chest_grid)
	check(viewport.encloses(bag_grid) and viewport.encloses(chest_grid)
		and bag_grid.has_area() and chest_grid.has_area() and bag_grid.end.x<=chest_grid.position.x,
		"backpack grid is fully visible to the left of the chest grid")
	for side in ["bag","chest"]:
		var heading:Rect2=panel.labels[side].get_global_rect()
		var grid_rect:Rect2=panel.grids[side].get_global_rect()
		check(heading.has_point(Vector2(grid_rect.get_center().x,heading.get_center().y))
			and heading.end.y<=grid_rect.position.y,"%s heading appears above its own item grid"%side)
	await tap_pair(panel.grids.chest,"fiber")
	check(s.bag.count("fiber")==5 and not record.items.has("fiber"),"double tap takes exactly one physical stack")
	await create_timer(0.2).timeout
	await tap_pair(panel.grids.bag,"fiber")
	check(s.bag.count("fiber")==0 and record.items.fiber==5,"double tap returns the stack to its chest")
	if not mobile:
		for side:String in ["chest","bag"]:
			var tile:=gear_item(panel.grids[side],"fiber")
			var center:=tile.get_global_rect().get_center()
			for down:bool in [true,false]:
				var mouse:=InputEventMouseButton.new()
				mouse.button_index=MOUSE_BUTTON_LEFT
				mouse.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
				mouse.pressed=down
				mouse.shift_pressed=true
				input_at(mouse,center)
				await frames()
			await create_timer(0.2).timeout
			check(s.bag.count("fiber")== (5 if side=="chest" else 0),"Shift-click transfers one visible stack from "+side)
	s.bag.add("sledge",s.bag.capacity())
	await create_timer(0.2).timeout
	await click(gear_item(panel.grids.chest,"fiber"))
	check(panel.single.disabled and panel.stack.disabled and panel.everything.disabled,"full destination disables unavailable transfers")
	await tap_pair(panel.grids.chest,"fiber")
	check(s.bag.count("fiber")==0 and record.items.fiber==5,"full inventory leaves the complete stack in the chest")
	s.bag.spend({"sledge":1})
	s.bag.add("fiber",s.bag.stack_size("fiber")-2)
	await create_timer(0.2).timeout
	await tap_pair(panel.grids.chest,"fiber")
	check(s.bag.count("fiber")==s.bag.stack_size("fiber") and record.items.fiber==3,"a nearly full destination takes only the two that fit")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await frames()
	print("ITEM SHORTCUTS failures=",fails)
	quit(1 if fails else 0)
