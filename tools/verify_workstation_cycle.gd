extends "res://tools/verify_equipment.gd"

func advance(seconds:float)->void:
	session.clock.advance(seconds)
	session.construction.simulate(seconds)

func test_leaf_recipes(stove:Vector3i)->void:
	var p:WastelandPanels=app.panels
	session.bag.add("tree_leaf",19)
	session.bag.add("stick",1)
	session.bag.add("cloth",6)
	session.bag.add("fiber",3)
	session.bag.add("corn",2)
	app.open_panel("craft")
	p._filter_recipes("落叶")
	check(p.recipe_list.get_child_count()==2,"ingredient search finds both hand recipes for leaves")
	p._filter_recipes("斗篷")
	var keys:=[]
	for row:Button in p.recipe_list.get_children():
		row.pressed.emit()
		keys.append(p.selection)
	check(keys==["sun_cape","leaf_sun_cape"] and p.detail_title.text.contains("沙漠遮阳斗篷"),"reed and leaf variants select separately and preview the same cape")
	p.craft_submit.pressed.emit()
	p._filter_recipes("引火束")
	p.craft_submit.pressed.emit()
	advance(20)
	session._finish_crafting()
	check(session.bag.count("tree_leaf")==8 and session.bag.count("sun_cape")==1 and session.bag.count("leaf_kindling")==1,"hand recipes spend eleven leaves and award wearable cape and kindling")
	app.open_panel("craft",stove)
	var before:float=session.construction.blocks[stove].fuel
	var feed:=button_with_text("加引火束")
	if feed: feed.pressed.emit()
	check(feed!=null and session.bag.count("leaf_kindling")==0 and is_equal_approx(session.construction.blocks[stove].fuel,before+24.0),"campfire fuel button spends one actual bundle for 24 burn seconds")
	var lab:Variant=place_station("chemistry")
	check(lab!=null and not session.can_craft("leaf_biofuel","hand"),"biomass fuel requires a chemistry station")
	if lab!=null:
		app.open_panel("craft",lab)
		p._filter_recipes("燃料")
		keys.clear()
		for row:Button in p.recipe_list.get_children():
			if session.catalog.recipes[row.get_meta("recipe")].id!="fuel": continue
			row.pressed.emit()
			keys.append(p.selection)
		check(keys==["fuel","leaf_biofuel"] and p.detail_title.text.contains("×2"),"the lab offers both fuel recipes and previews two units for the leaf variant")
		p.craft_submit.pressed.emit()
		advance(17)
		session.ui_command("collect",[lab])
		check(session.bag.count("tree_leaf")==0 and session.bag.count("corn")==0 and session.bag.count("clean_water")==1 and session.bag.count("fuel")==2,"plant fuel consumes eight leaves, two corn and one water and yields two usable fuel")
	for id:String in ["tree_leaf","leaf_kindling"]:
		var model:=WastelandItemArt.mesh(id,session.catalog.items[id])
		check(model.get_faces().size()>30 and WastelandItemArt.icon(id,session.catalog.items[id]).get_width()==36,"sculpted mesh and inventory icon for "+id)
	app.close_overlay()
	session.simulation_paused=true

func run()->void:
	WastelandSave.root_override="user://verification/workstation-cycle-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/settings.cfg"
	root.add_child(app)
	app._enter_world(app._default_config(),{},1,false)
	session=app.session
	session.simulation_paused=true
	var stove:Vector3i=place_station("campfire")
	var furnace:Vector3i=place_station("forge")
	var row:Dictionary=session.construction.blocks[stove]
	var forge:Dictionary=session.construction.blocks[furnace]
	session.bag.add("dirty_water",3)
	session.bag.add("wood",2)
	session.ui_command("craft",["clean_water",3,stove])
	advance(8)
	check(row.queue.size()==3 and row.out.is_empty() and row.queue[0].left==6.0,"cold stove cannot finish paid water")
	session.ui_command("feed_fire",[stove,"wood"])
	advance(5)
	check(not row.enabled and row.fuel==38.0 and row.queue[0].left==6.0,"unlit fuel keeps both its time and its work")
	session.ui_command("enable",[stove])
	advance(2)
	check(is_equal_approx(row.queue[0].left,4.0) and row.fuel==36.0,"burning advances only real work seconds")
	var canceled:int=row.queue[1].ticket
	session.ui_command("cancel",[stove,canceled])
	session.ui_command("cancel",[stove,canceled])
	check(row.queue.size()==2 and session.bag.count("dirty_water")==1,"cancelling the middle job twice refunds once")
	session.ui_command("enable",[stove])
	advance(8)
	check(is_equal_approx(row.queue[0].left,4.0) and row.fuel==36.0,"extinguishing pauses both clocks")
	session.bag.add("scrap",8)
	session.ui_command("craft",["ingot",1,furnace])
	check(forge.queue.is_empty(),"raw backpack scrap is unavailable to forging")
	session.bag.add("coal",1)
	session.ui_command("feed_fire",[furnace,"coal"])
	session.ui_command("smelt_input",[furnace,"scrap"])
	session.ui_command("enable",[furnace])
	advance(5)
	check(forge.molten.scrap==2 and forge.smelt_input.count==6 and forge.smelt_input.partial==1.0,"forge meters eight real raw items into internal stock")
	check(session.save_now(false)==OK,"save both physical stations")
	var saved:=WastelandSave.read(1)
	var before:Dictionary=saved.construction.blocks[furnace]
	check(before==forge and saved.construction.blocks[stove]==row,"disk carries fuel slots, partial smelt, molten stock, queue identity and remaining times")
	await session.stream.quiesce()
	app._remove_session()
	app._enter_world(saved.settings,saved,1,false)
	session=app.session
	session.simulation_paused=true
	row=session.construction.blocks[stove]
	forge=session.construction.blocks[furnace]
	advance(11)
	check(forge.molten.scrap==8 and not forge.has("smelt_input"),"loaded forge resumes fractional smelting")
	session.ui_command("craft",["ingot",1,furnace])
	check(forge.queue.size()==1 and forge.molten.scrap==0,"crafting reserves molten stock at this forge")
	session.ui_command("cancel",[furnace,forge.queue[0].ticket])
	check(forge.molten.scrap==8 and session.bag.count("scrap")==0,"cancel returns smelted metal to the same furnace")
	session.ui_command("craft",["ingot",1,furnace])
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		app.open_panel("craft",furnace)
		app.panels._filter_recipes("铁锭")
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://build/qa/060-forge.png")==OK,"capture actual Chinese forge interface")
		app.close_overlay()
	advance(12)
	session.ui_command("collect",[furnace])
	check(session.bag.count("ingot")==4 and forge.queue.is_empty(),"forge output is collected through the real station")
	session.ui_command("enable",[stove])
	advance(10)
	session.ui_command("collect",[stove])
	check(session.bag.count("clean_water")==2 and row.queue.is_empty(),"resuming stove completes both surviving orders exactly")
	var legacy:={"device":"campfire","enabled":true,"fuel":50.0,"queue":[{"id":"clean_water","amount":1,"span":6.0,"done":104.0}]}
	WastelandSession.Fire.restore(legacy,100.0)
	check(legacy.fuel_slots=={"wood":1} and legacy.ember==12.0 and legacy.queue[0].left==4.0,"previous release fuel and paid recipe migrate without duplication")
	legacy={"device":"campfire","enabled":true,"fuel":0.0,"queue":[]}
	WastelandSession.Fire.restore(legacy,100.0)
	check(not legacy.enabled,"old empty campfire requires ignition after adding new fuel")
	test_leaf_recipes(stove)
	var coal_stove:Vector3i=place_station("campfire")
	session.bag.add("packed_snow",2)
	var water_before:=session.bag.count("clean_water")
	var wood_before:=session.bag.count("wood")
	heat_station(coal_stove,{})
	session.ui_command("craft",["melt_snow",1,coal_stove])
	advance(8)
	session.ui_command("collect",[coal_stove])
	check(session.bag.count("packed_snow")==0 and session.bag.count("wood")==wood_before and session.bag.count("clean_water")==water_before+1,"two snow melt into one clean water in a coal-fired campfire")
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.free()
	print("WORKSTATION CYCLE ",passed," passed / ",failed," failed")
	quit(int(failed>0))
