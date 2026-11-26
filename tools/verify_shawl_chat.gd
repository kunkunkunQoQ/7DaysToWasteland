extends SceneTree

var app: Node
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(result: bool, label: String) -> void:
	if not result: failures += 1
	print("PASS " if result else "FAIL ", label)

func press(key: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		root.push_input(event, true)

func submit(words: String) -> void:
	press(KEY_ENTER)
	app.chat.editor.insert_text_at_caret(words)
	press(KEY_ENTER)

func run() -> void:
	WastelandSave.root_override = "user://verification/shawl-chat-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	app._enter_world(app._default_config(), {}, 1, false)
	var world: WastelandSession = app.session
	press(KEY_ENTER)
	check(app.chat.editing and app.chat.editor.has_focus() and not world.controls_enabled, "Enter focuses chat and suspends gameplay inputs")
	app.chat.editor.insert_text_at_caret("草稿")
	press(KEY_ESCAPE)
	check(not app.chat.editing and world.controls_enabled and app.chat.lines.is_empty(), "Escape discards a draft without sending")
	world.achievements.record_chat("host", "旧话", Time.get_ticks_msec() - 60001)
	submit("集合")
	submit(" 集合 ")
	world.send_chat("　")
	submit("[b]带水[/b]")
	check(world.bag.count("meme_shawl") == 0 and not world.achievements.unlocked("shiver_chat"), "expired, blank and duplicate messages cannot complete the challenge")
	check(app.chat.lines.size() == 3 and app.chat.log_view.get_parsed_text().contains("[b]带水[/b]"), "accepted messages appear as plain text including duplicate lines")
	submit("出发")
	check(world.bag.count("meme_shawl") == 1 and world.achievements.unlocked("shiver_chat"), "three distinct submissions award the sender a shawl")
	submit("到了")
	check(world.bag.count("meme_shawl") == 1 and not app.chat.editing and world.controls_enabled, "submission returns control and cannot duplicate the reward")
	var captions: Array[String] = []
	world.shawl_spoke.connect(func(caption: String): captions.append(caption))
	world.record_shawl_action("捡起了碎石")
	check(captions.is_empty(), "unworn shawl is silent")
	world.ui_command("consume", ["meme_shawl"])
	check(world.bag.is_worn("meme_shawl") and captions.size() == 1 and captions[0].ends_with("捡起了碎石"), "equipping the reward captions the last action")
	world.ui_command("consume", ["meme_shawl"])
	world.record_shawl_action("采集了野草")
	check(captions.size() == 1 and not world.bag.is_worn("meme_shawl"), "removing the shawl silences the next action")
	var touch: Control = app.hud.get_node_or_null("TouchControls")
	if touch != null:
		touch.expanded = true
		touch._layout()
		var chat_button: Vector2 = touch.layout.chat.get_center()
		for down: bool in [true, false]:
			var tap := InputEventScreenTouch.new()
			tap.position = chat_button
			tap.pressed = down
			root.push_input(tap, true)
		check(app.chat.editing and app.chat.editor.has_focus(), "touch More menu opens chat")
		app.close_overlay()
	world.simulation_paused = true
	await world.stream.quiesce()
	await world.audio.finish_playback()
	print("SHAWL CHAT QA failures=", failures)
	quit(1 if failures else 0)
