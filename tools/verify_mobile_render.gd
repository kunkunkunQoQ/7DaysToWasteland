extends SceneTree

var app:Node
var failed:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,label:String)->void:
	if ok: print("PASS ",label)
	else:
		printerr("FAIL ",label)
		failed+=1

func settled()->void:
	for i in 5: await process_frame

func on_screen(control:Control)->bool:
	return Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(control.get_global_rect())

func touch(finger:int,at:Vector2,pressed:bool)->void:
	var event:=InputEventScreenTouch.new()
	event.index=finger
	event.pressed=pressed
	event.position=at
	root.push_input(event,true)

func drag(finger:int,at:Vector2,delta:Vector2)->void:
	var event:=InputEventScreenDrag.new()
	event.index=finger
	event.position=at
	event.relative=delta
	root.push_input(event,true)

func run()->void:
	WastelandSave.root_override="user://verification/mobile-render-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	var options:=WastelandSettings.new()
	options.storage_path=WastelandSave.save_root()+"/mobile.cfg"
	options.load_options(true)
	check(options.display.pixel_height==340 and options.display.radius==2 and options.display.fps==30 and options.display.dynamic,"first Android launch chooses 340p, two chunks, adaptive resolution and 30 FPS")
	options.display.full=false
	options.display.fps=45
	options.save_options()
	options=WastelandSettings.new()
	options.storage_path=WastelandSave.save_root()+"/mobile.cfg"
	options.load_options(true)
	check(options.display.fps==45,"saved quality overrides Android defaults")
	options.display.fps=30
	options.save_options()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=options.storage_path
	root.add_child(app)
	await settled()
	check(RenderingServer.get_current_rendering_method()=="gl_compatibility","OpenGL compatibility renderer active")
	check(app.world_view.size.y==340 and app.hands_view.size==app.world_view.size,"world and first-person passes use the mobile resolution")
	for screen in ["title","settings","create","atlas"]:
		match screen:
			"settings": app.front.settings("title")
			"create": app.front.creation()
			"atlas": app.front.atlas()
		await settled()
		var focus:Control=root.gui_get_focus_owner()
		check(app.front.screen==screen and focus!=null and on_screen(focus),screen+" primary action is reachable")
		var panels:Array=app.front.shell.find_children("*","PanelContainer",true,false)
		if not panels.is_empty(): check(on_screen(panels[0]),screen+" dialog fits landscape viewport")
	var cfg:Dictionary=app._default_config()
	app._enter_world(cfg,{},1,false)
	await settled()
	check(app.session.player.camera.current and app.hud.visible,"inland game renders through player camera and HUD")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(WastelandSave.save_root()+"/mobile-render.png")
	if "--touch-controls" in OS.get_cmdline_user_args() or OS.has_feature("android"):
		var controls:Control=app.hud.get_node("TouchControls")
		for mirrored:bool in [false,true]:
			app.options.touch_left_handed=mirrored
			for control_scale:float in [0.85,1.0,1.15]:
				app.options.touch_control_scale=control_scale
				controls._layout()
				var vitals:=Rect2(controls.size.x-216 if mirrored else 28.0,controls.size.y-155,188,137)
				var reserved: Array[Rect2]=[vitals,WastelandHUD.quickbar_rect(controls.size),WastelandHUD.offhand_rect(controls.size)]
				var clear:=true
				for button:Rect2 in controls.layout.values():
					if not controls.bounds.encloses(button): clear=false
					for previous in reserved:
						if button.intersects(previous): clear=false
					reserved.append(button)
				check(clear,"tap targets, vitals, eight slots and offhand do not overlap: mirror %s scale %.2f"%[mirrored,control_scale])
		app.options.touch_left_handed=false
		app.options.touch_control_scale=1.0
		controls._layout()
		app.open_panel("map")
		await settled()
		var canvas:WastelandMap=app.panels.map_canvas
		var point:=canvas.get_global_rect().get_center()+Vector2(41,-16)
		var count:int=app.session.marker_records.size()
		app.panels.marker_title.text="南线会合点"
		touch(1,point,true)
		await create_timer(0.65).timeout
		touch(1,point,false)
		check(canvas.touch_navigation and app.session.marker_records.size()==count+1 and app.session.marker_records.back().name=="南线会合点","native long press stores named map marker once")
		touch(1,point,true)
		touch(1,point,false)
		check(canvas.selected>=0 and app.session.marker_records.size()==count+1,"tapping existing marker selects without duplication")
		var old_center:=canvas.center
		touch(1,point,true)
		drag(1,point+Vector2(34,24),Vector2(34,24))
		touch(1,point+Vector2(34,24),false)
		check(canvas.center.distance_to(old_center)>5,"single finger map pan")
		var old_zoom:=canvas.zoom
		touch(1,point-Vector2(30,0),true)
		touch(2,point+Vector2(30,0),true)
		drag(2,point+Vector2(65,0),Vector2(35,0))
		touch(2,point+Vector2(65,0),false)
		touch(1,point-Vector2(30,0),false)
		check(canvas.zoom>old_zoom*1.3 and app.session.marker_records.size()==count+1,"pinch zoom avoids accidental marks")
		canvas.reset_center()
		check(canvas.center.is_equal_approx(Vector2(app.session.player.position.x,app.session.player.position.z)),"map recenters on survivor")
		for key:String in app.catalog.items:
			app.session.bag.add(key,1)
	app.open_panel("bag")
	await settled()
	check(app.panels.visible and on_screen(app.panels.content),"inventory fits landscape play area")
	if "--touch-controls" in OS.get_cmdline_user_args():
		var inventory:ScrollContainer=app.panels.bag_list.get_parent()
		inventory.scroll_vertical=10000
		await process_frame
		var last_slot:Control=app.panels.item_grid.get_child(-1)
		check(inventory.get_global_rect().has_point(last_slot.get_global_rect().get_center()),"last inventory slot is reachable on a phone")
		app.open_panel("craft")
		await settled()
		var recipes:ScrollContainer=app.panels.recipe_list.get_parent()
		recipes.scroll_vertical=10000
		check(recipes.scroll_vertical>0,"recipe catalogue scrolls beyond its first page")
	app.close_overlay()
	app._pause()
	await settled()
	check(app.front.screen=="pause" and on_screen(root.gui_get_focus_owner()),"pause actions fit landscape play area")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
