extends SceneTree

const TerrainView := preload("res://game/ui/atlas_terrain_view.gd")
const Landmarks := preload("res://game/ui/atlas_landmarks.gd")

var failures:=0
var app:Node

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,label:String)->void:
	if ok: print("PASS ",label)
	else:
		failures+=1
		printerr("FAIL ",label)

func click(button:Button)->void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.position=button.get_global_rect().get_center()
	event.pressed=true
	root.push_input(event,true)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event,true)

func capture()->bool:
	return "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"

func check_terrain(atlas: Control) -> void:
	var generator := preload("res://game/ui/atlas_records.gd").terrain
	var locations := {}
	for row: Dictionary in atlas.entries:
		locations[Landmarks.site(generator, row).center] = true
	check(locations.size() == atlas.entries.size(), "every terrain entry has a distinct survey window")
	var view := atlas.detail.find_child("TerrainView", true, false) as TerrainView
	if view == null:
		check(false, "terrain viewer opens")
		return
	var start := view.camera.transform
	click(view.plan_button)
	check(view.camera.basis.z.dot(Vector3.UP) > 0.999, "plan button shows the terrain from directly above")
	var rect := Rect2(Vector2.ZERO, Vector2(view.scene.size))
	var fits := true
	for corner in 8:
		if not rect.has_point(view.camera.unproject_position(view.bounds.get_endpoint(corner))):
			fits = false
			break
	check(fits, "plan view includes the complete terrain sample")
	click(view.plan_button)
	check(view.camera.transform.is_equal_approx(start), "switching back restores the oblique view")

func run()->void:
	WastelandSave.root_override="user://verification/title-atlas-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var landscape:int=app.front.landscape_index
	var opening:Array=app.front.shell.find_children("*","Button",true,false).filter(func(button):return button.text=="荒原图鉴")
	check(opening.size()==1,"main menu offers atlas")
	click(opening[0])
	await process_frame
	var atlas:Control=app.front.shell.find_child("TitleAtlas",true,false)
	check(atlas!=null and app.front.screen=="atlas","pointer opens atlas without entering a world")
	check(atlas.category=="terrain" and not atlas.entries.is_empty(),"fresh profile opens on browsable terrain")
	check_terrain(atlas)
	click(atlas.tabs.get_node("achievements"))
	await process_frame
	check(atlas.buttons.size()==app.catalog.achievements.size() and atlas.entries.all(func(e):return not e.unlocked),"fresh profile has one dark tile per achievement")
	check(atlas.buttons.all(func(b):return b.tooltip_text=="" and b.text=="●"),"locked tiles conceal real achievement names and hints")
	atlas.buttons.back().grab_focus()
	await process_frame
	check(atlas.list_scroll.scroll_vertical>0,"focused achievement scrolls into view")
	atlas.buttons.back().pressed.emit()
	check(atlas.selection==atlas.buttons.size()-1,"last locked tile remains individually selectable")
	for category:String in ["terrain","creatures","characters"]:
		click(atlas.tabs.get_node(category))
		await process_frame
		check(atlas.category==category and not atlas.entries.is_empty(),category+" list opens by mouse")
		atlas.buttons.back().grab_focus()
		var accept:=InputEventAction.new()
		accept.action="ui_accept"
		accept.pressed=true
		root.push_input(accept,true)
		accept=accept.duplicate()
		accept.pressed=false
		root.push_input(accept,true)
		await process_frame
		check(atlas.selection==atlas.entries.size()-1 and atlas.detail.get_child_count()>0,category+" final entry opens by controller")
	if capture():
		atlas.choose_category("creatures")
		var stag:int=atlas.entries.find_custom(func(e):return e.id=="stag")
		atlas.buttons[maxi(0,stag)].grab_focus()
		atlas.select_entry(maxi(0,stag))
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/qa/title-atlas.png"))
	app.front.handle_back()
	check(app.front.screen=="title" and app.front.landscape_index==landscape,"back returns to same landscape")
	preload("res://game/core/atlas_unlocks.gd").remember(WastelandSave.save_root(),["inspect"])
	app.front.atlas()
	atlas=app.front.shell.find_child("TitleAtlas",true,false)
	atlas.choose_category("achievements")
	check(atlas.entries[atlas.selection].id=="inspect","reopening selects the earned entry")
	var icons:Array=atlas.detail.find_children("*","TextureRect",true,false)
	check(icons.size()==1 and icons[0].texture!=null,"earned achievement shows reward art")
	if capture():
		await process_frame
		await process_frame
		atlas.buttons[atlas.selection].grab_focus()
		atlas.list_scroll.ensure_control_visible(atlas.buttons[atlas.selection])
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/qa/title-atlas-achievements.png"))
	await app.session.stream.quiesce()
	if is_instance_valid(app.session.audio): await app.session.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
