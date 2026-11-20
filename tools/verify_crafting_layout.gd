extends "res://tools/verify_avatar_ui.gd"

func icon_row(container:Container,id:String,words:String)->bool:
	for row in container.get_children():
		if row.get_meta("item","")!=id: continue
		var image:TextureRect=row.get_child(0)
		return image.texture==WastelandItemArt.icon(id,app.session.catalog.items[id]) and (row.get_child(1) as Label).text.contains(words)
	return false

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	WastelandSave.root_override="user://verification/craft-layout-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await frames()
	app._enter_world(app._default_config(),{},1,false)
	app.open_panel("craft")
	await frames(12)
	var p:WastelandPanels=app.panels
	var s:WastelandSession=app.session
	var search:LineEdit=p.content.find_child("RecipeSearch",true,false)
	search.grab_focus()
	for glyph in "绷带":
		var key:=InputEventKey.new()
		key.unicode=glyph.unicode_at(0)
		key.pressed=true
		root.push_input(key,true)
		key=key.duplicate()
		key.pressed=false
		root.push_input(key,true)
	await frames()
	await click(p.recipe_list.get_child(0))
	check(p.craft_submit.disabled and icon_row(p.craft_materials,"cloth","缺 2"),"search selects a recipe and explains its missing ingredient")
	await click(p.favorite_button)
	await click(button(p.content,"已收藏"))
	check(p.selection=="bandage" and p.recipe_list.get_child_count()==1,"favorites preserve the searched recipe")
	s.bag.add("cloth",11)
	await create_timer(0.35).timeout
	await click(p.craft_max)
	check(p.craft_quantity==5 and p.detail_title.text.contains("×10"),"maximum uses available stacks and previews actual product total")
	await click(p.craft_minus)
	check(p.craft_quantity==4 and icon_row(p.craft_materials,"cloth","11 / 8"),"quantity updates total ingredients")
	check(root.get_visible_rect().encloses(p.craft_submit.get_global_rect()) and root.get_visible_rect().encloses(p.craft_cancel.get_global_rect()),"craft and cancellation remain visible")
	await click(button(p.content,"全部"))
	search.clear()
	search.text_changed.emit("")
	await frames(6)
	await shot("craft-"+("touch" if mobile else "desktop"))
	await click(p.craft_submit)
	check(p.job_buttons.get_child_count()==4 and p.job_buttons.get_child(0).icon==WastelandItemArt.icon("bandage",s.catalog.items.bandage),"each queued job shows its output icon and can be cancelled separately")
	check(s.hand_queue.size()==4 and s.bag.count("cloth")==3,"one press reserves exactly four batches")
	await click(p.craft_cancel)
	check(s.hand_queue.size()==3 and s.bag.count("cloth")==5,"cancelling the queue tail returns its materials")
	s.clock.advance(15)
	s._finish_crafting()
	check(s.bag.count("bandage")==6,"completed handcrafts immediately enter the bag")
	s.bag.add("cloth",11)
	await create_timer(0.35).timeout
	await click(p.craft_max)
	await click(p.craft_submit)
	check(s.hand_queue.size()==8 and s.bag.count("cloth")==0,"the full eight-batch preview queues all eight and debits exactly sixteen cloth")
	app.close_overlay()
	var cell:=Vector3i.ZERO
	var placed:=false
	s.bag.add("campfire",1)
	for x in range(-3,4):
		for z in range(-3,4):
			var spot:=s.player.global_position+Vector3(x,0,z)
			cell=Vector3i(floori(spot.x),ceili(s.stream.ground_at(spot)-0.42),floori(spot.z))
			if s.construction.place(cell,"campfire",0,0,s.player.global_position):
				placed=true
				break
		if placed: break
	check(placed,"set a real campfire within reach")
	if not placed: quit(1); return
	app.open_panel("craft",cell)
	await frames()
	p._filter_recipes("融雪")
	check(p.recipe_list.get_child_count()==1,"campfire has its own recipes")
	var recipe:Dictionary=s.catalog.recipes[p.selection]
	check(p.selection=="melt_snow" and p.recipe_list.get_child(0).icon==WastelandItemArt.icon("clean_water",s.catalog.items.clean_water),"filtered alias recipe shows water output icon")
	check(icon_row(p.craft_materials,"packed_snow","缺 2") and p.fire_button.disabled,"recipe ingredients and empty independent fuel slot are visible")
	for id:String in recipe.inputs: s.bag.add(id,recipe.inputs[id])
	await create_timer(0.3).timeout
	await click(p.craft_submit)
	s.clock.advance(20)
	s.construction.simulate(20)
	check(s.construction.blocks[cell].out.is_empty(),"unlit station keeps unfinished work")
	s.bag.add("wood",1)
	await click(button(p.content,"加"+s.catalog.title("wood")))
	await create_timer(0.30).timeout
	await click(p.fire_button)
	s.clock.advance(8)
	s.construction.simulate(8)
	await create_timer(0.35).timeout
	check(not p.craft_collect.disabled and p.queue_label.text.contains("待领取"),"station products wait for collection")
	check(icon_row(p.craft_outputs.get_node("Products"),"clean_water","待领"),"finished station output shows the actual water icon")
	p._filter_recipes("")
	await frames(4)
	await shot("craft-icons-"+("touch" if mobile else "desktop"))
	await click(p.craft_collect)
	check(s.bag.count(recipe.id)==recipe.amount and p.craft_collect.disabled,"collect transfers station goods once")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await frames()
	print("CRAFT LAYOUT failures=",fails)
	quit(1 if fails else 0)
