extends SceneTree

const Guide:=preload("res://game/ui/material_guide.gd")
var app:Node
var failures:=0
var passes:=0
var mobile:=false

func _initialize()->void: run.call_deferred()

func check(ok:bool,what:String)->bool:
	if ok: passes+=1
	else: failures+=1
	print("PASS " if ok else "FAIL ",what)
	return ok

func settle()->void:
	for i in 8: await process_frame

func press(button:Button)->void:
	if not is_instance_valid(button): return
	var at:=button.get_global_transform_with_canvas()*(button.size*0.5)
	if not mobile:
		var motion:=InputEventMouseMotion.new()
		motion.position=at
		root.push_input(motion,true)
		await process_frame
	for down:bool in [true,false]:
		if mobile:
			var touch:=InputEventScreenTouch.new()
			touch.position=root.get_final_transform()*at
			touch.pressed=down
			Input.parse_input_event(touch)
		else:
			var mouse:=InputEventMouseButton.new()
			mouse.position=at
			mouse.button_index=MOUSE_BUTTON_LEFT
			mouse.pressed=down
			root.push_input(mouse,true)
		await process_frame
	await settle()

func button(caption:String)->Button:
	for candidate:Button in app.panels.content.find_children("*","Button",true,false):
		if candidate.text==caption and candidate.is_visible_in_tree(): return candidate
	return null

func guide()->Guide:
	for node in app.panels.content.find_children("*","VBoxContainer",true,false):
		if node.get_script()==Guide: return node
	return null

func audit(g:Guide)->void:
	var catalog:WastelandCatalog=app.catalog
	var total:=0
	for id:String in catalog.items:
		if not catalog.is_material(id): continue
		total+=1
		var ok:=g.entries.has(id) and not g.use_paths(id).is_empty()
		if not ok:
			check(false,"missing route for "+id)
			continue
		g.entries[id].pressed.emit()
		var words:=PackedStringArray()
		for line:Label in g.details.find_children("*","Label",false,false): words.append(line.text)
		for path:Array in g.use_paths(id):
			var names:=PackedStringArray()
			for i in path.size():
				names.append(catalog.title(path[i]))
				if i>0:
					var edge:=false
					for r:Dictionary in catalog.recipes.values():
						if r.inputs.has(path[i-1]) and r.id==path[i]: edge=true; break
					ok=ok and edge
			ok=ok and path[0]==id and Guide.USES.has(path[-1]) and (" → ".join(names) in "\n".join(words))
		for r:Dictionary in catalog.recipes.values():
			if r.inputs.has(id):
				var title:String=r.get("name",catalog.title(r.id))
				var output:=catalog.title(r.id)
				var row_present:=false
				for line in words:
					if title in line and output in line and "×%d"%r.amount in line: row_present=true; break
				ok=ok and row_present
		check(ok and g.selected==id and words.has(catalog.title(id)),"visible recipe outputs and reachable route: "+id)
	check(g.entries.size()==total,"index covers all current materials: "+str(total))

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	if mobile: Input.emulate_mouse_from_touch=true
	WastelandSave.root_override="user://verification/material-ui-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.terrain_revision=2
	app._enter_world(cfg,{},1,false)
	app.session.bag.add("packed_snow",1)
	app.open_panel("bag")
	await settle()
	var tile:Button=app.panels.inventory_buttons[0]
	await press(tile)
	check(app.panels.selection=="packed_snow" and app.panels.material_link.visible,"select owned snow in bag")
	await press(button("材料用途"))
	var g:=guide()
	if check(is_instance_valid(g) and g.selected=="packed_snow","bag opens the selected material"):
		var screen:=root.get_visible_rect()
		var scroll:ScrollContainer=g.entries.packed_snow.get_parent().get_parent()
		check(screen.encloses(g.get_global_rect()) and scroll.get_global_rect().intersects(g.entries.packed_snow.get_global_rect()) and screen.encloses(button("返回背包").get_global_rect()),"list, selected deep row, article and back button fit landscape")
		audit(g)
		await settle()
		await press(button("返回背包"))
		check(app.panels.active=="bag" and app.panels.selection=="packed_snow","return restores the source bag selection")
	await press(button("获取方式"))
	g=guide()
	if check(g!=null and g.selected=="packed_snow" and "新雪" in "\n".join(g.sources.stable.packed_snow),"bag opens the selected item's sources"):
		for id:String in app.catalog.items:
			check(g.entries.has(id) and not (g.sources.stable[id].is_empty() and g.sources.random[id].is_empty()),"documented acquisition: "+id)
		var search:LineEdit=g.find_child("ItemSourceSearch",true,false)
		search.text="回弹簧"
		search.text_changed.emit(search.text)
		var spring:="\n".join(g.sources.stable.spring)
		check(g.selected=="spring" and "废弃泵机" in spring and "拆解扳手" in spring and "远行运单" in spring and "巡线" in spring,"search includes harvest tool, contracts and patrol routes")
		check("废弃泵机" not in "\n".join(g.sources.stable.parts),"pump wreck does not advertise machine parts")
		check("≥28" in "\n".join(g.sources.random.bike) and not g.sources.stable.bike.is_empty(),"gated chest is separate from guaranteed motorcycle recipe")
		check("成就" in "\n".join(g.sources.stable.meme_clock) and "地方色赤狐" in "\n".join(g.sources.random.meme_clock),"clock lists achievement and variant-specific rare route")
		check("工兵铲" in "\n".join(g.sources.stable.sapling_oak) and "感染者巢穴" in "\n".join(g.sources.random.pistol),"sapling recovery and nest loot list the real interactions")
		var radio_places: PackedStringArray = g.sources.random.electronics
		check(Array(radio_places).any(func(line): return line.begins_with("无线电检修柜") and "观测塔" in line and "荒原前哨" in line and "指挥所" in line),
			"radio parts list the lookout, outpost and spillway control room in the same source")
		check("山麓林场" in "\n".join(g.sources.random.honey) and "回声医院" not in "\n".join(g.sources.random.rifle),
			"item sources distinguish timber stations and exclude hospital medicine lockers from rifle locations")
		check("守夜补给" in "\n".join(g.sources.stable.bandage) and "17%" in "\n".join(g.sources.random.bandage),"blood moon supplies and infected rolls stay distinct")
		search.text="no such item"
		search.text_changed.emit(search.text)
		check(g.selected=="","empty source filter clears the previous article")
		search.clear()
		search.text_changed.emit("")
		check(g.selected!="" and g.entries.rifle.visible,"clearing search restores the index")
		await press(button("返回背包"))
		check(app.panels.active=="bag" and app.panels.selection=="packed_snow","browsing sources preserves the original bag selection")
	app.open_panel("field")
	await settle()
	await press(button("材料用途"))
	g=guide()
	if check(is_instance_valid(g) and g.selected=="fiber","field guide opens material index"):
		await press(g.entries.stone)
		check(g.selected=="stone","switch visible material with pointer input")
		await press(button("返回探索手记"))
		check(app.panels.active=="field" and button("材料用途")!=null,"index returns to field guide")
	await press(button("获取方式"))
	check(guide()!=null and guide().entries.has("rifle"),"field guide includes the full item index")
	app._handle_back()
	check(app.panels.active=="field","system back returns to the exploration guide")
	app.open_panel("craft")
	await settle()
	app.close_overlay()
	app.session.simulation_paused=true
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.queue_free()
	await settle()
	print("MATERIAL UI passed=",passes," failed=",failures)
	quit(1 if failures else 0)
