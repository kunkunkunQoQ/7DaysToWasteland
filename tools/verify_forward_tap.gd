extends SceneTree

var s:WastelandSession
var errors:=0

func _initialize()->void: run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: errors+=1

func key(code:Key,down:bool,echo:=false)->void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	event.echo=echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame

func run()->void:
	WastelandSave.root_override="user://verification/forward-tap-%d"%OS.get_process_id()
	var app:Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.spawn_roll=17
	app._enter_world(cfg,{},1,false)
	app.close_overlay()
	s=app.session
	await physics_frame
	var forward:Key=KEY_W
	await key(forward,true)
	check(not s.player.sprinting,"first forward press walks")
	await key(forward,true,true)
	check(not s.player.sprinting,"keyboard autorepeat cannot trigger sprint")
	await key(forward,false)
	await key(forward,true)
	check(s.player.sprinting,"short tap then hold requests a real survivor sprint")
	var stamina:=s.player.stamina
	for i in 6: await physics_frame
	check(s.player.stamina<stamina,"double tap spends normal sprint stamina")
	s.player.stamina=2
	await physics_frame
	await physics_frame
	check(not s.player.sprinting,"fatigue prevents sprint")
	s.player.stamina=95
	await key(forward,false)
	check(not s.double_forward_sprint,"releasing forward ends the latch")
	await key(KEY_SHIFT,true)
	await key(forward,true)
	check(s.player.sprinting,"ordinary Shift plus forward still sprints")
	await key(forward,false)
	await key(KEY_SHIFT,false)
	s.reset_forward_taps()
	await key(forward,true)
	await key(forward,false)
	await create_timer(0.35).timeout
	await key(forward,true)
	check(not s.player.sprinting,"a slow second tap walks")
	await key(forward,false)
	app.open_panel("bag")
	await key(forward,true)
	await key(forward,false)
	app.close_overlay()
	await key(forward,true)
	check(not s.double_forward_sprint,"typing forward in the inventory does not prime a sprint")
	await key(forward,false)
	await key(forward,true)
	check(s.player.sprinting,"fresh pair works after returning to gameplay")
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not s.double_forward_sprint,"window focus loss clears a held sprint")
	await key(forward,false)
	InputMap.action_erase_events("up")
	var rebound:=InputEventKey.new()
	rebound.physical_keycode=KEY_I
	InputMap.action_add_event("up",rebound)
	await key(KEY_I,true)
	await key(KEY_I,false)
	await key(KEY_I,true)
	check(s.player.sprinting,"rebound forward key works")
	app.open_panel("bag")
	check(not s.double_forward_sprint,"opening a menu immediately cancels the hold")
	await key(KEY_I,false)
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if errors else 0)
