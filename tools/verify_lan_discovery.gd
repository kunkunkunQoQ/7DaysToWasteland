extends SceneTree

var app: Node
var port := 17962
var ticket := ""
var world_name := ""
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
	return value

func until(predicate: Callable, limit := 30000) -> bool:
	var deadline := Time.get_ticks_msec() + limit
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func listing() -> Button:
	for button: Button in app.front.room_list.find_children("*","Button",true,false):
		if button.text.begins_with(world_name+" "): return button
	return null

func host() -> void:
	var settings: Dictionary = app._default_config()
	settings.name = world_name
	app._enter_world(settings,{},1,false)
	app.session.bag.add("wood",7)
	app.leave_world()
	if not check(await until(func(): return app.session.preview_only),"single-player world saved and closed"): return
	app.front.lan_room()
	var go: Button
	for button: Button in app.front.find_children("*","Button",true,false):
		if button.text=="开放选中世界": go=button
	if not check(is_instance_valid(go) and not go.disabled,"saved slot can be opened from host form"): return
	for entry: LineEdit in go.get_parent().find_children("*","LineEdit",true,false): entry.text=str(port)
	go.pressed.emit()
	if not check(await until(func(): return app.network.server()),"selected save opened on configured port"): return
	check(app.network.port==port and app.session.bag.count("wood")==7,"host restored original inventory")
	if not check(await until(func(): return not app.network.joined_members().is_empty()),"guest connected to existing world"): return
	if not check(await until(func(): return app.session.marker_records.size()==1),"guest marker reached host"): return
	if not check(await until(func(): return FileAccess.file_exists(ticket)),"guest reopened browser and saw host advertising"): return
	app.leave_world()
	if not check(await until(func(): return app.session.preview_only and not app.network.active()),"host closed and saved"): return
	app.open_world(1)
	if not check(await until(func(): return not app.session.preview_only),"host reopened saved slot offline"): return
	check(app.session.marker_records.size()==1 and app.session.bag.count("wood")==7,"host reload retained guest marker and original supplies")

func guest() -> void:
	app.front.lan_room()
	if not check(await until(func(): return is_instance_valid(listing())),"browser automatically listed named host"): return
	var button := listing()
	check("1/6" in button.text and not button.disabled,"room button shows current occupancy and permits joining")
	button.pressed.emit()
	if not check(await until(func(): return app.session.replica),"joining through room row bootstrapped actual ENet session"): return
	check(app.session.world_settings.name==world_name and app.session.bag.count("wood")==7,"guest received selected saved world")
	app.session.ui_command("marker",[Vector2.ONE,"discovery QA"])
	if not check(await until(func(): return app.session.marker_records.size()==1),"host acknowledged guest marker"): return
	app.leave_world()
	if not check(await until(func(): return app.session.preview_only),"guest left cooperatively"): return
	app.front.lan_room()
	if not check(await until(func(): return is_instance_valid(listing()) and not listing().disabled),"same host rediscovered after disconnect"): return
	var signal_file := FileAccess.open(ticket,FileAccess.WRITE)
	signal_file.store_line("visible")
	signal_file.close()
	check(await until(func(): return listing()==null and app.network.discovery.rooms.values().filter(func(r): return r.name==world_name).is_empty(),16000),"stale host expired from live menu and discovery cache")

func run() -> void:
	var flags := OS.get_cmdline_user_args()
	var run_id := ""
	for flag in flags:
		if flag.begins_with("--port="): port=flag.get_slice("=",1).to_int()
		if flag.begins_with("--run="): run_id=flag.get_slice("=",1).validate_filename()
	if run_id=="" or (not "--host" in flags and not "--guest" in flags):
		printerr("Provide --host or --guest, --port=N and a shared unique --run=ID")
		quit(2)
		return
	world_name="Room "+run_id
	WastelandSave.root_override="user://verification/discovery-%s-%d"%[run_id,OS.get_process_id()]
	ticket=OS.get_temp_dir().path_join("wasteland-discovery-"+run_id+".ready")
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	app.network.local_token=Crypto.new().generate_random_bytes(16).hex_encode()
	if "--host" in flags: await host()
	else: await guest()
	app.network.stop()
	app.session.simulation_paused=true
	await app.session.stream.quiesce()
	if is_instance_valid(app.session.audio): await app.session.audio.finish_playback()
	app.free()
	if "--guest" in flags and FileAccess.file_exists(ticket): DirAccess.remove_absolute(ticket)
	print("DISCOVERY failures=",failures)
	quit(1 if failures else 0)
