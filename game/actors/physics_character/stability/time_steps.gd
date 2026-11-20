extends SceneTree
## Dedicated real-time benchmark. Run headless at --max-fps 360 without --fixed-fps.
## Timestamp the physics_frame signal through the following process_frame; this brackets
## character updates and the synchronous server step, excluding the frame limiter.

const Character := preload("../physics_character.tscn")
const Experiment := preload("experiment_config.gd")
var hz := 60
var profile := "baseline"
var output := ""
var actor: Node3D
var tick := 0
var start_us := -1
var multi_step := false
var skipped := 0
var samples := PackedFloat64Array()
var engine_max_ms := 0.0
var wall_start_us := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = arg.trim_prefix("--hz=").to_int()
		if arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if hz not in [60, 120] or profile not in Experiment.PROFILES or "--fixed-fps" in OS.get_cmdline_args():
		printerr("Expected real-time 60/120 Hz and a known profile.")
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	_setup.call_deferred()

func _setup() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.1
	root.add_child(floor_body)
	actor = Character.instantiate()
	actor.get_node("Visual").free()
	actor.config = Experiment.create(profile)
	actor.position.y = 3
	actor.rotation.z = 1.32
	root.add_child(actor)
	Experiment.configure_space(profile, actor.get_world_3d().space)
	wall_start_us = Time.get_ticks_usec()
	physics_frame.connect(_begin)
	process_frame.connect(_end)

func _begin() -> void:
	tick += 1
	if start_us >= 0:
		multi_step = true
	start_us = Time.get_ticks_usec()
	if tick % hz == 0:
		var rig := actor.get_node("PhysicsRig")
		var direction := 1.0 if floori(float(tick) / hz) % 2 == 0 else -1.0
		rig.bodies[&"chest"].apply_central_impulse(Vector3(direction * 8.0, 12.0, 0))

func _end() -> void:
	if start_us < 0: return
	var ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	if tick > hz and multi_step: skipped += 1
	if tick > hz and not multi_step:
		samples.append(ms)
	if tick > hz * 2:
		engine_max_ms = maxf(engine_max_ms, 1000.0 * Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	start_us = -1
	multi_step = false
	if tick >= hz * 7:
		process_frame.disconnect(_end)
		physics_frame.disconnect(_begin)
		# Godot can consume --fixed-fps before exposing command-line arguments
		# to GDScript. Enforce real pacing on the measured run itself as well.
		if Time.get_ticks_usec() - wall_start_us < 6_700_000:
			printerr("Timing requires seven seconds of real-time physics. Remove --fixed-fps and keep the normal simulation clock.")
			quit(2)
			return
		samples.sort()
		if samples.size() < hz * 5:
			printerr("Too few isolated physics steps to profile.")
			quit(1)
			return
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("Could not open timing output: ", output)
			quit(2)
			return
		file.store_csv_line(["profile", "hz", "samples", "multi_step_windows_skipped", "p50_ms", "p95_ms", "p99_ms", "max_ms", "engine_physics_window_max_ms"])
		file.store_csv_line([profile, str(hz), str(samples.size()), str(skipped), str(_p(0.50)), str(_p(0.95)), str(_p(0.99)), str(samples[-1]), str(engine_max_ms)])
		file.close()
		print("TIMING ", profile, " ", hz, " Hz  n=", samples.size(), " p95_ms=", _p(0.95))
		quit()

func _p(q: float) -> float:
	return samples[ceili(q * samples.size()) - 1]
