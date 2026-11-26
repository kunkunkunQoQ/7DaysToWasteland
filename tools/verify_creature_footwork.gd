extends "res://tools/verify_creature_motion.gd"

const DT := 1.0/60.0
var failures := PackedStringArray()
var largest_mean_slip := 0.0

func run() -> void:
	var stage := MotionStage.new()
	stage.replica = true
	root.add_child(stage)
	var ground := StaticBody3D.new()
	ground.position.y = -0.5
	stage.add_child(ground)
	WastelandLook.collider(ground, Vector3(24, 1, 24), Vector3.ZERO)
	var director := WastelandHordes.new()
	stage.add_child(director)
	director.session = stage
	var actor := WastelandCreature.new()
	stage.add_child(actor)
	actor.configure(director)
	await physics_frame
	for sample: Array in [["walker",0],["walker",18],["crawler",0],["walker",72],["brute",0],
			["stag",0],["boar",0],["fox",0],["hare",0],["wolf",0],["badger",0],["argali",0],["jerboa",0],["otter",0]]:
		actor.revive(sample[0], Vector3(0,0.025,0), false, {"limb_index":sample[1], "facing":0.0, "stride_phase":0.0, "wildlife_cycle":0.0})
		await _turn_and_stop(actor)
		actor.deactivate()
	stage.queue_free()
	await process_frame
	for issue: String in failures: printerr(issue)
	print("Grounded creature footwork: 14 rigs, highest mean stance slip %.1f mm, failures=%d" % [largest_mean_slip*1000.0,failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _turn_and_stop(actor: WastelandCreature) -> void:
	var animal := actor.brain.animal
	var joints := ["paw3","paw2","paw1","paw0"] if animal else ["hand_l","hand_r"] if actor.type == "crawler" or actor.low_crawl() else ["ankle_l","ankle_r"]
	var previous := {}
	var support_ids := {}
	var drift := 0.0
	var observed := 0
	var speed := minf(1.35, float(actor.spec.speed)*0.54)
	var pose_clock := actor.motion_clock
	for frame in 138:
		var direction := Vector3.FORWARD if frame < 38 else Vector3.RIGHT
		var before := actor.global_position
		var prior_velocity := actor.velocity
		var yaw := actor.rotation.y
		actor._steer(direction*speed if frame < 108 else Vector3.ZERO, direction, DT)
		actor.velocity.y -= 18.0*DT
		actor.move_and_slide()
		actor._pose(DT, 5.0, Vector2(before.x-actor.position.x,before.z-actor.position.z).length())
		if frame == 38:
			_check(absf(angle_difference(yaw,actor.rotation.y)) <= 5.5*DT+0.0001, actor.type+" pivot angular speed")
			_check(Vector2(actor.velocity.x-prior_velocity.x,actor.velocity.z-prior_velocity.z).length() <= 24.0*DT, actor.type+" limited acceleration in a turn")
		if frame == 109:
			_check(actor.velocity.slide(Vector3.UP).length() < speed, actor.type+" slows when stopping")
		if actor.motion_clock != pose_clock:
			pose_clock = actor.motion_clock
			for i in joints.size():
				if not actor.foot_contacts.planted[i].is_finite():
					previous.erase(i)
					continue
				support_ids[i] = true
				var joint: int = actor.skeleton.find_bone(joints[i])
				var actual := actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(joint).origin
				var anchored: Vector3 = actor.foot_contacts.planted[i]
				if previous.has(i) and frame >= 38 and frame < 108 and anchored.is_equal_approx(previous[i][0]):
					drift += Vector2(actual.x-previous[i][1].x,actual.z-previous[i][1].z).length()
					observed += 1
				previous[i] = [anchored, actual]
		await physics_frame
	var name_and_limbs := "%s/%d" % [actor.type, actor.limb_index]
	_check(actor.is_on_floor() and actor.velocity.slide(Vector3.UP).length()<0.001, name_and_limbs+" stops on a real collider")
	var mean_slip := drift / maxi(1,observed)
	largest_mean_slip = maxf(largest_mean_slip, mean_slip)
	_check(observed > 4 and mean_slip < 0.010, "%s support samples=%d avg. planar drift=%.4f m" % [name_and_limbs,observed,mean_slip])
	if actor.type == "jerboa":
		_check(not support_ids.has(0) and not support_ids.has(1) and support_ids.has(2) and support_ids.has(3), "jerboa uses its hind paws")
	elif actor.limb_index == 18:
		_check(not support_ids.has(0) and support_ids.has(1), "severed left foot never plants")
	else:
		_check(support_ids.size() == joints.size(), name_and_limbs+" uses each surviving support")
	actor.motion_water = true
	actor._pose(0.08,5.0,0.0)
	_check(not actor.foot_contacts.enabled, name_and_limbs+" releases on entering water")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
