extends "res://tools/verify_avatar_ui.gd"

# Run with --resolution 1920x1080 or --resolution 2400x1080 -- --touch-controls.
# --capture saves the full rendered viewport, without resizing the screenshot.
func click(button_node:Control)->void:
	if not mobile:
		move(button_node.get_global_rect().get_center())
		await frames(2)
	await super.click(button_node)

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	WastelandSave.root_override="user://verification/equipment-layout-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await frames()
	app._enter_world(app._default_config(),{},1,false)
	await frames(14)
	if mobile:
		var controls:Control=app.hud.get_node("TouchControls")
		var at:Vector2=controls.layout.inventory.get_center()
		press(at,true)
		await frames(2)
		press(at,false)
	else:
		var key:=InputEventKey.new()
		key.physical_keycode=KEY_TAB
		key.keycode=KEY_TAB
		key.pressed=true
		Input.parse_input_event(key)
		await frames(2)
		key=key.duplicate()
		key.pressed=false
		Input.parse_input_event(key)
	await frames(8)
	var panels:WastelandPanels=app.panels
	if not panels.visible or panels.active!="bag":
		check(false,"gameplay backpack control opens the real equipment panel")
		quit(1)
		return
	var slots:Dictionary=panels.bag_list.get_meta("gear_slots")
	var avatar:WastelandPartyAvatar=panels.bag_avatar
	check(app.session.bag.counts.is_empty() and panels.item_grid.get_child_count()==27,"fresh empty world displays all 27 cells")
	check(avatar.preview_mainhand=="" and avatar.offhand_id=="","fresh character has two empty hands")
	var viewport:=root.get_visible_rect()
	var portrait:Control=panels.content.find_child("BagSurvivor",true,false)
	var stage:Control=panels.content.find_child("AvatarEquipmentStage",true,false)
	check(viewport.encloses(panels.content.get_global_rect()) and stage.get_global_rect().encloses(portrait.get_global_rect()),"full panel and character viewport fit the landscape")
	var frame:=portrait.get_global_rect()
	var rects:Array[Rect2]=[]
	for key:String in ["head","body","legs","feet","offhand","hands","eyes","muzzle","back","pack"]:
		var control:Control=slots[key]
		var rect:=control.get_global_rect()
		check(control.is_visible_in_tree() and viewport.encloses(rect) and not frame.intersects(rect) and not rects.any(func(other):return rect.intersects(other)),key+" fits with no overlap")
		rects.append(rect)
	await capture_state("empty")
	# The sample inventory is a fixture. All assignments use pointer or finger input.
	var session:WastelandSession=app.session
	for id:String in ["stone_axe","hardhat","canvas_pants","improvised_shield","canvas_pack","meme_shades","fiber","stone"]:
		session.bag.add(id,1,WastelandBag.PACK)
	await frames(18)
	var grid:=panels.item_grid
	for pair:Array in [["hardhat","head"],["canvas_pants","legs"],["canvas_pack","pack"],["meme_shades","eyes"],["improvised_shield","offhand"]]:
		await click(gear_item(grid,pair[0]))
		await frames(12)
		if pair[1] in ["head","eyes","pack"]: await click(button(panels.content,slots[pair[1]].NAMES[pair[1]]))
		else: await click(slots[pair[1]])
		await frames(12)
		check(slots[pair[1]].item==pair[0],"assign "+str(pair[1])+" by two clicks or taps")
	await drag_item(gear_item(grid,"stone_axe"),panels.quick_slots.get_child(0))
	await click(panels.quick_slots.get_child(0))
	await frames(18)
	check(grid.get_child_count()==36,"worn pack adds nine usable cells")
	check(avatar.preview_mainhand=="stone_axe" and avatar.grip.has_node("PreviewMainhand") and avatar.offhand_id=="improvised_shield" and avatar.left_grip.is_ancestor_of(avatar.offhand_prop),"distinct axe and shield on opposite animated hands")
	check(slots.body.item=="" and slots.feet.item=="" and slots.legs.item=="canvas_pants" and slots.pack.item=="canvas_pack","empty outlines coexist with filled slots")
	await capture_state("equipped")
	session.bag.add("expedition_pack",1,WastelandBag.PACK)
	await frames(12)
	await click(gear_item(grid,"expedition_pack"))
	await click(slots.pack)
	await frames(12)
	check(grid.get_child_count()==45 and session.bag.capacity()==45,"large pack shows all five rows")
	var scroll:=panels.bag_list.get_parent() as ScrollContainer
	var last_rect:Rect2=grid.get_child(-1).get_global_rect()
	check(scroll.scroll_vertical==0 and scroll.get_global_rect().encloses(last_rect),"complete fifth row visible immediately at zero scroll")
	print("FIFTH ",scroll.get_global_rect()," last=",last_rect," scroll=",scroll.scroll_vertical)
	await capture_state("five-rows")
	scroll.scroll_vertical=0
	await frames(8)
	await click(gear_item(grid,"stone"))
	await click(panels.material_link)
	check(panels.active=="materials","item detail opens materials handbook from new left column")
	if panels.active=="materials":
		await click(button(panels.content,"返回背包"))
		check(panels.active=="bag" and panels.selection=="stone" and panels.item_grid.get_child_count()==45,"return restores material selection and five-row pack")
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.queue_free()
	await frames(2)
	print("EQUIPMENT LAYOUT failures=",fails)
	quit(1 if fails else 0)

func capture_state(state:String)->void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await frames(6)
	await RenderingServer.frame_post_draw
	var studio:Control=app.panels.bag_studio
	var texture:Image=studio.scene.get_texture().get_image()
	var bounds:=texture.get_used_rect()
	var extent:=texture.get_size()
	check(bounds.has_area() and bounds.position.x>0 and bounds.position.y>0 and bounds.end.x<extent.x and bounds.end.y<extent.y,"full alpha silhouette stays clear of all four viewport edges")
	var ratios:=Vector2(bounds.size)/Vector2(extent)
	print("FIT ",state," bounds=",bounds," viewport=",extent," width/height=",ratios)
	var image:=root.get_texture().get_image()
	var target:=Vector2i(2400,1080) if mobile else Vector2i(1920,1080)
	check(image.get_size()==target,"native capture resolution "+str(target))
	var path:="res://build/qa/equipment-%s-%s.png"%["touch" if mobile else "desktop",state]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	check(image.save_png(ProjectSettings.globalize_path(path))==OK,"write "+path)
