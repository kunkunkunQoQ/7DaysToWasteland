extends SceneTree

const TILE := Vector2i(160,112)
const STEPS := 6

class MotionStage extends Node3D:
	var replica := false
	var catalog := WastelandCatalog.new()
	var clock := WastelandClock.new()
	var world_settings := {"difficulty":1.0}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size=TILE
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("#42505a")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=0.83
	var camera := Camera3D.new()
	camera.environment=env
	viewport.add_child(camera)
	var key := DirectionalLight3D.new()
	viewport.add_child(key)
	key.rotation_degrees=Vector3(-48,-48,0)
	var actor := WastelandCreature.new()
	viewport.add_child(actor)
	var stage := MotionStage.new()
	viewport.add_child(stage)
	var director := WastelandHordes.new()
	stage.add_child(director)
	director.session=stage
	actor.configure(director)
	var capture := DisplayServer.get_name()!="headless"
	var kinds: Array = WastelandHordes.WILDLIFE + WastelandHordes.KINDS
	var sheet := Image.create_empty(TILE.x*STEPS,TILE.y*kinds.size(),false,Image.FORMAT_RGB8)
	var passed := true
	for row in kinds.size():
		var kind: String = kinds[row]
		actor.revive(kind,Vector3.ZERO,false,{})
		actor.rotation=Vector3.ZERO
		actor.pose_phase=0.0
		var animal := bool(actor.spec.get("animal",false))
		var label := "leg0" if animal else "arm_r"
		var bone := actor.skeleton.find_bone(label)
		var first := actor.skeleton.get_bone_pose_rotation(bone)
		var largest := 0.0
		var height := float(actor.spec.height)
		var aim := Vector3.UP*height*(0.64 if kind=="stag" else 0.51)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=maxf(1.24,height*(1.53 if animal else 1.20))
		camera.position=aim+Vector3(2.5,0.65,-1.6)
		camera.look_at(aim)
		for col in STEPS:
			for frame in 6:
				var t := (col*6+frame)/35.0
				actor.velocity.z = -float(actor.spec.speed)*(0.62+t*0.38) if animal else -0.45
				if not animal or kind=="boar":
					actor.windup = minf(t/0.60,1.0) if t<0.60 else 0.0
					actor.attack=clampf((1.0-t)/0.40,0.0,1.0) if t>=0.60 else 0.0
					match kind:
						"screamer": actor.attack_kind = WastelandCreatureBrain.Action.SCREAM
						"rimecaller": actor.attack_kind = WastelandCreatureBrain.Action.MEND
						"sandrunner": actor.attack_kind = WastelandCreatureBrain.Action.CHARGE
						"spitter": actor.attack_kind = WastelandCreatureBrain.Action.SPIT
						"bloater": actor.attack_kind = WastelandCreatureBrain.Action.RUPTURE
						_: actor.attack_kind = WastelandCreatureBrain.Action.MELEE
				actor._pose(1.0/60.0,3.0)
				largest=maxf(largest,first.angle_to(actor.skeleton.get_bone_pose_rotation(bone)))
			if capture:
				await process_frame
				await RenderingServer.frame_post_draw
				var tile := viewport.get_texture().get_image()
				tile.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(tile,Rect2i(Vector2i.ZERO,TILE),Vector2i(col*TILE.x,row*TILE.y))
		if largest<=0.08:
			push_error("No visible limb swing on "+kind)
			passed=false
		var moving_phase := actor.pose_phase
		var start_time := actor.motion_clock
		for tick in 24:
			actor._pose(1.0/60.0,3.0,0.0)
		if actor.motion_clock<=start_time or not is_equal_approx(moving_phase,actor.pose_phase):
			push_error("Blocked motion should halt stride and preserve idle time on "+kind)
			passed=false
		if actor.motion_speed>0.05:
			push_error("Feet keep walking against a wall on "+kind)
			passed=false
		var saved_phase := float(actor.serialize().stride_phase)
		actor.deactivate()
		actor.revive(kind,Vector3.ZERO,false,{"stride_phase":saved_phase})
		passed = passed and is_equal_approx(actor.pose_phase,saved_phase) and actor.motion_speed==0.0
		passed = passed and actor.rig.position.is_zero_approx() and actor.attack==0.0 and actor.windup==0.0
		var phase := actor.pose_phase
		actor._pose(0.10,70.0)
		passed = passed and is_equal_approx(phase,actor.pose_phase)
		actor.deactivate()
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
		passed = sheet.save_png("res://build/qa/creature-motion.png")==OK and passed
	viewport.queue_free()
	await process_frame
	await process_frame
	print("Creature motion QA: ",kinds.size()," rigs, six sequential samples each; passed=",passed)
	quit(0 if passed else 1)
