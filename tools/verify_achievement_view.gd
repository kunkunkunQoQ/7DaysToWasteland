extends SceneTree

var app:Node
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(condition:bool,label:String)->void:
	if condition: print("PASS ",label)
	else:
		failures+=1
		printerr("FAIL ",label)

func run()->void:
	WastelandSave.root_override="user://verification/achievement-view-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	app._enter_world(app._default_config(),{},1,false)
	app.open_panel("achievements")
	var view:Control=app.panels.find_child("AchievementTree",true,false)
	check(is_instance_valid(view),"Tab achievement page opens")
	check(view.tabs.get_child_count()==6,"six navigable routes")
	var total:=0
	var concealed:=true
	for key:String in view.ROUTES:
		view.tabs.get_node(key).pressed.emit()
		check(view.route==key and not view.buttons.is_empty(),key+" nodes selectable")
		for id:String in view.buttons:
			total+=1
			var button:Button=view.buttons[id]
			button.pressed.emit()
			var style:StyleBoxFlat=button.get_theme_stylebox("normal")
			concealed=concealed and button.text=="未解锁" and button.tooltip_text.is_empty() and style.bg_color.v<0.1 and view.detail.get_child_count()==1 and view.detail.get_child(0).text=="未解锁"
		var last:Button=view.buttons.values().back()
		var last_id:String=last.get_meta("achievement")
		last.grab_focus()
		last.pressed.emit()
		await process_frame
		check(view.selected==last_id and view.buttons[last_id].has_focus(),key+" focused entry opens details")
	check(total==app.session.catalog.achievements.size() and concealed,"new world shows every black slot without names, hints, conditions or reward icons")
	view.choose_route("odd")
	var secret:Button=view.buttons["off_duty"]
	secret.pressed.emit()
	check(secret.text=="未解锁","odd challenge uses the same concealed slot")
	app.session.achievements.add("inspect_frame",7)
	view.buttons.inspect.pressed.emit()
	check(view.buttons.inspect.text=="未解锁" and view.detail.get_child_count()==1,"partial progress stays private")
	app.session.achievements.add("inspect_frame",1)
	app.session.achievements.refresh()
	await create_timer(0.65).timeout
	view.buttons.inspect.grab_focus()
	view.buttons.inspect.pressed.emit()
	check("甲方来验收" in view.buttons.inspect.text and app.session.achievements.rewarded("inspect"),"discovery reveals the real challenge and granted reward")
	check(view.buttons.off_duty.text=="未解锁","neighbor remains concealed after unlock")
	var shown:Array=view.detail.find_children("*","TextureRect",true,false)
	check(shown.size()==1 and shown[0].texture!=null,"unlocked reward displays its item art")
	view.tabs.get_node("camp").grab_focus()
	var confirm:=InputEventAction.new()
	confirm.action="ui_accept"
	confirm.pressed=true
	root.push_input(confirm,true)
	confirm=confirm.duplicate()
	confirm.pressed=false
	root.push_input(confirm,true)
	await process_frame
	check(view.route=="camp","controller accept activates focused route")
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.position=view.tabs.get_node("odd").get_global_rect().get_center()
	click.pressed=true
	root.push_input(click,true)
	click=click.duplicate()
	click.pressed=false
	root.push_input(click,true)
	await process_frame
	check(view.route=="odd","pointer activates odd route")
	view.buttons.inspect.grab_focus()
	view.buttons.inspect.pressed.emit()
	if DisplayServer.get_name()!="headless":
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		if root.size.x>=1200 and "--capture" in OS.get_cmdline_user_args():
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/qa/achievement-rewards.png"))
		app.session.achievements.add("made_campfire")
		app.session.achievements.refresh()
		view.choose_route("camp")
		view.buttons.nightfire.grab_focus()
		view.buttons.nightfire.pressed.emit()
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		if root.size.x>=1200 and "--capture" in OS.get_cmdline_user_args():
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/qa/achievements.png"))
	app.close_overlay()
	check(not app.panels.visible,"closing achievement browser restores play")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
