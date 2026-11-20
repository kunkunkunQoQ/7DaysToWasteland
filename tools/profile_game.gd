extends SceneTree

const SAMPLE_TIME := 15.0
var game: Node
var session: WastelandSession
var scene_name := "graybay"

func _initialize() -> void:
	_profile.call_deferred()

func _profile() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("A graphics driver is required for this profile.")
		quit(1)
		return
	WastelandSave.root_override = "user://verification/profile-%d" % OS.get_process_id()
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process_input(false)
	root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	game.options.display.dynamic=false
	game.options.display.pixel_height=340
	game.resize_scene(true)
	var config:Dictionary=game._default_config()
	for option:String in OS.get_cmdline_user_args():
		if option.begins_with("--seed="):
			config.seed=option.trim_prefix("--seed=").to_int()
	print("PROFILE seed=",config.seed," height=340")
	game._enter_world(config,{},0,false)
	session=game.session
	session.controls_enabled=false
	session.hordes.next_patrol=900.0
	session.simulation_paused=true
	var timeout := Time.get_ticks_msec()+25000
	while session.stream.active.size()<70 and Time.get_ticks_msec()<timeout:
		await process_frame
	await create_timer(1.0).timeout
	await _measure("shore")
	session.simulation_paused=false
	session.clock.hours=6.0*24.0+22.0
	session.player.invulnerable=1000.0
	session.hordes.event_day=7
	session.hordes.wave_index=1
	session.hordes.next_wave=session.clock.elapsed+SAMPLE_TIME+6.0
	var kinds:=["walker","crawler","radiant","spitter","brute","screamer"]
	var population := WastelandHordes.CAP if "--full-horde" in OS.get_cmdline_user_args() else 22
	for i in range(population * 3):
		if session.hordes.alive.size() >= population:
			break
		session.hordes._try_near(session.player.global_position,kinds[i%kinds.size()],28.0,55.0,true)
	await create_timer(3.0).timeout
	await _measure("horde")
	if "--measure-only" not in OS.get_cmdline_user_args(): await _travel()
	session.simulation_paused=true
	await session.stream.quiesce()
	await session.audio.finish_playback()
	game.free()
	quit()

func _measure(tag: String) -> void:
	var samples: Array[float] = []
	var measured_triangles: Array[int] = []
	var memory_start := Performance.get_monitor(Performance.MEMORY_STATIC)
	var begin := Time.get_ticks_usec()
	var last := begin
	while Time.get_ticks_usec()-begin < SAMPLE_TIME*1000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		if samples.size()%24==0:
			measured_triangles.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		last=now
	samples.sort()
	var ms: float = samples[samples.size()/2]
	var p95: float = samples[mini(samples.size()-1,floori(samples.size()*0.95))]
	var seconds := float(last-begin)/1000000.0
	measured_triangles.sort()
	var polygons := measured_triangles[measured_triangles.size()/2] if not measured_triangles.is_empty() else 0
	print("PROFILE %s fps=%.1f median_ms=%.2f p95_ms=%.2f chunks=%d triangles=%d enemies=%d memory_start_MB=%.1f memory_end_MB=%.1f" %
		[tag,samples.size()/seconds,ms,p95,session.stream.active.size(),polygons,session.hordes.alive.size(),
		memory_start/1048576.0,Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0])

func _travel() -> void:
	for stop in [Vector2(191,-90),Vector2(-148,-188),Vector2(402,-242),Vector2(9,44)]:
		if not is_instance_valid(session):
			printerr("Profile world was closed.")
			return
		var point := Vector3(stop.x,13.0,stop.y)
		session.stream.ensure_landing(point)
		point.y=session.stream.ground_at(point)+0.35
		session.player.global_position=point
		await create_timer(3.5).timeout
		var expected := WastelandTerrainGen.chunk_at(stop)
		var present := session.stream.center==expected and session.stream.active.has(expected)
		print("TRAVEL %s loaded=%s chunks=%d actors=%d memory_MB=%.1f" %
			[stop,str(present),session.stream.active.size(),session.hordes.alive.size(),Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0])
