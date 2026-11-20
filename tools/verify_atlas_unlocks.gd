extends SceneTree

const Atlas := preload("res://game/core/atlas_unlocks.gd")
const View := preload("res://game/ui/title_atlas.gd")
var catalog := WastelandCatalog.new()
var failures := 0
var app: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1

func earned() -> Array:
	return Atlas.rows(catalog).filter(func(row):return row.unlocked).map(func(row):return row.id)

func fixture(progress: Dictionary) -> Dictionary:
	return {"settings":WastelandSave.default_world(),"progress":progress}

func run() -> void:
	WastelandSave.root_override="user://verification/atlas-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var flags:=OS.get_cmdline_user_args()
	if "--host" in flags or "--guest" in flags:
		var port:=19784
		for flag in flags:
			if flag.begins_with("--port="): port=int(flag.get_slice("=",1))
		await multiplayer_history("--host" in flags,port)
	else:
		local_history()
	await process_frame
	print("ATLAS HISTORY QA failures=",failures)
	quit(1 if failures else 0)

func local_history() -> void:
	var rows:=Atlas.rows(catalog)
	var clean:=true
	for row in rows:
		clean=clean and not row.unlocked and row.id=="" and row.name=="未解锁" and row.size()==4 and row.has("category")
	check(rows.size()==catalog.achievements.size() and clean,"fresh profile exposes every anonymous slot without private metadata")
	var view:=View.new()
	root.add_child(view)
	view.setup(catalog,func():pass)
	view.choose_category("achievements")
	var concealed:=true
	for i in view.buttons.size():
		view.select_entry(i)
		var button:Button=view.buttons[i]
		var bg:StyleBoxFlat=button.get_theme_stylebox("normal")
		concealed=concealed and button.text=="●" and button.tooltip_text.is_empty() and bg.bg_color.v<0.1
		concealed=concealed and view.detail.find_children("*","TextureRect",true,false).is_empty()
		var texts:=PackedStringArray()
		for label:Label in view.detail.find_children("*","Label",true,false): texts.append(label.text)
		var entry:Dictionary=catalog.achievements[i]
		var details:=" ".join(texts)
		for private_text:String in [entry.name,entry.desc,entry.hint, catalog.title(entry.reward) if not str(entry.reward).is_empty() else ""]:
			if not private_text.is_empty() and private_text in details: concealed=false
	check(concealed,"all selectable black tiles conceal titles, hints, criteria and reward art")
	view.queue_free()
	Atlas.remember(WastelandSave.save_root(),["inspect","inspect"])
	check(earned()==["inspect"],"remember persists a single history entry idempotently")
	WastelandSave.write(1,fixture({"achieved":{"twigs":2}}))
	WastelandSave.write(2,fixture({"achieved":{"off_duty":3}}))
	WastelandSave.write(2,fixture({"achieved":{"nightfire":4}}))
	var file:=FileAccess.open(WastelandSave.path_for(2),FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	WastelandSave.write(3,fixture({"job":6,"records":{"made_campfire":999,"owned_meme_hammer":1},"level":40}))
	var ids:=earned()
	check(ids.size()==3 and ids.has("twigs") and ids.has("inspect") and ids.has("off_duty"),"combines awarded old slots with local history and recovers the corrupt slot from backup")
	check(not ids.has("nightfire"),"old progress without an achieved dictionary grants no inferred awards")
	WastelandSave.write(4,fixture({"achieved":{"meal":1}}))
	for slot in range(1,5): check(WastelandSave.delete_slot(slot)==OK,"delete test world "+str(slot))
	ids=earned()
	check(ids.size()==4 and ids.has("meal") and ids.has("off_duty") and ids.has("inspect") and ids.has("twigs"),"history survives deletion including a world never browsed")

func wait_for(predicate:Callable) -> bool:
	var end:=Time.get_ticks_msec()+14000
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await process_frame
	return false

func multiplayer_history(host:bool,port:int) -> void:
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	if host:
		app._enter_world(app._default_config(),{},1,false)
		app.session.achievements.add("inspect_frame",8)
		app.session.achievements.refresh()
		check(app.network.listen(port)==OK,"host offers a world with a previously earned challenge")
		if await wait_for(func():return not app.network.joined_members().is_empty()):
			app.session.achievements.add("star_watch",6)
			app.session.achievements.refresh()
			check(await wait_for(func():return app.session.marker_records.any(func(row):return row.name=="history verified")),"client acknowledged its durable history")
			await wait_for(func():return app.network.joined_members().is_empty())
		else:check(false,"client joins")
	else:
		check(earned().is_empty(),"client starts with an independent empty account history")
		check(app.network.connect_to("127.0.0.1",port)==OK,"client opens a real ENet connection")
		if await wait_for(func():return is_instance_valid(app.session) and app.session.replica and app.session.progress.achieved.has("off_duty")):
			var ids:=earned()
			check(ids.has("inspect") and ids.has("off_duty") and WastelandSave.list_slots().is_empty(),"client archives bootstrap and new live team awards without a local world save")
			app.session.ui_command("marker",[Vector2.ZERO,"history verified"])
			await create_timer(0.25).timeout
		else:check(false,"client receives awarded team state")
	if is_instance_valid(app.session):
		app.session.simulation_paused=true
		await app.session.stream.quiesce()
		await app.session.audio.finish_playback()
	app.network.stop()
	app.queue_free()
	await process_frame
