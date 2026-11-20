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
		await press(button("返回背包"))
		check(app.panels.active=="bag" and app.panels.selection=="packed_snow","return restores the source bag selection")
	app.open_panel("field")
	await settle()
	await press(button("材料用途"))
	g=guide()
	if check(is_instance_valid(g) and g.selected=="fiber","field guide opens material index"):
		await press(g.entries.stone)
		check(g.selected=="stone","switch visible material with pointer input")
		await press(button("返回探索手记"))
		check(app.panels.active=="field" and button("材料用途")!=null,"index returns to field guide")
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
