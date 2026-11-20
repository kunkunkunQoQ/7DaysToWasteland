extends SceneTree

class Stage extends Node3D:
	var catalog := WastelandCatalog.new()
	var world_settings := {"difficulty":1.0}
	var replica := true

var problems := PackedStringArray()
var cycles := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var director := WastelandHordes.new()
	stage.add_child(director)
	director.session = stage
	var actor := WastelandCreature.new()
	stage.add_child(actor)
	actor.configure(director)
	for kind: String in WastelandHordes.WILDLIFE:
		for morph: String in ["","local","young"]:
			actor.revive(kind,Vector3.ZERO,false,{"morph":morph,"wildlife_cycle":0.125})
			if not is_equal_approx(actor.wildlife_cycle,0.125):
				problems.append(kind + " restored stride")
			var torso := actor.skeleton.find_bone("torso")
			actor._animal_pose(0, 0, 0.1)
			var flat_body := actor.skeleton.get_bone_global_pose(torso).basis
			for angle: Vector2 in [Vector2.ZERO, Vector2(0,14), Vector2(0,-12), Vector2(10,0), Vector2(-11,0)]:
				var normal := Vector3(tan(deg_to_rad(angle.x)),1,tan(deg_to_rad(angle.y))).normalized()
				actor.motion_floor_normal = normal
				actor._animal_pose(0,0,0.1)
				var body := actor.skeleton.get_bone_global_pose(torso).basis
				if (body.y - flat_body.y).dot(normal - Vector3.UP) < (normal - Vector3.UP).length_squared() * 0.39:
					problems.append("%s body fails to follow slope %s" % [kind,angle])
				for ratio: float in [0.18,0.52,1.0]:
					for index in (2 if kind == "jerboa" else 4):
						check_cycle(actor, ratio, index)
			actor.motion_floor_normal = Vector3.UP
			actor.brain.forage_left = 2.0
			actor._animal_pose(0, 0, 0.7)
			var neck := actor.skeleton.find_bone("neck")
			var feed := actor.skeleton.get_bone_pose_rotation(neck)
			actor.alerted = true
			actor._animal_pose(0, 0, 0.7)
			if feed.angle_to(actor.skeleton.get_bone_pose_rotation(neck)) < 0.19:
				problems.append(kind + " failed to raise head on alert")
			if kind == "otter":
				var phase := actor.wildlife_cycle
				var dry := actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("paw0"))
				actor.motion_water = true
				actor._animal_pose(0, 0, 0.7)
				var wet := actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("paw0"))
				if dry.origin.distance_to(wet.origin) < 0.02 or not is_equal_approx(actor.wildlife_cycle, phase):
					problems.append("otter water pose")
				actor.motion_floor_normal = Vector3(0.25,1,0).normalized()
				actor._animal_pose(0,0,0.7)
				var on_bank := actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("paw0"))
				if not wet.is_equal_approx(on_bank):
					problems.append("submerged otter paddles forced to follow bank")
			actor.deactivate()
	stage.queue_free()
	await process_frame
	for reason in problems:
		push_error(reason)
	print("Wildlife gait QA: ",cycles," limb cycles across 9 species, 3 morphs, 3 speeds on flat ground and 4 slope directions; failures=", problems.size())
	quit(int(not problems.is_empty()))

func check_cycle(actor: WastelandCreature, ratio: float, index: int) -> void:
	cycles += 1
	var leg := actor.wildlife_motion.limbs[index]
	var rest: Vector3 = leg.rest_paw
	var length: float = actor.wildlife_motion.leg_length
	var speed := float(actor.spec.speed) * ratio
	var high := -INF
	var low := INF
	var planted := 0
	var previous := Vector3.ZERO
	var previous_height := INF
	var normal: Vector3 = actor.motion_floor_normal
	var normal_basis := actor.rig.basis.inverse().transposed()
	var stride := 0.0
	var dt := 1.0 / 180.0
	actor.wildlife_cycle = 0.0
	for frame in 720:
		var before := actor.wildlife_cycle
		actor.motion_clock += dt
		actor._animal_pose(speed,0,dt)
		stride += fposmod(actor.wildlife_cycle - before,1.0)
		var paw := actor.skeleton.get_bone_global_pose(leg.paw)
		var foot := actor.rig.basis * (paw * (Vector3.DOWN * rest.y))
		var clearance := foot.dot(normal) / actor.rig.scale.y
		high = maxf(high,clearance)
		low = minf(low,clearance)
		if absf(clearance) < length * 0.045 and absf(previous_height) < length * 0.045:
			var local_speed := (foot.z - previous.z) / dt
			var sole_normal := (normal_basis * paw.basis.y).normalized()
			if absf(local_speed - speed) < speed * 0.15 and sole_normal.dot(normal) > cos(deg_to_rad(3.0)):
				planted += 1
		previous = foot
		previous_height = clearance
		if stride >= 1.0:
			break
	var id := "%s %s paw%d %.2fx on %s" % [actor.type,actor.morph,index,ratio,normal]
	if low < -length * 0.045 or low > length * 0.05 or high < length * 0.075:
		problems.append("%s hoof clearance %.3f..%.3f over leg %.3f" % [id, low, high, length])
	if planted < 2:
		problems.append("%s planted foot drifts at %.2f m/s" % [id,speed])
