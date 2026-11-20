extends "res://tools/verify_creature_motion.gd"

var failures: Array[String] = []

func run() -> void:
	var stage := MotionStage.new()
	root.add_child(stage)
	var director := WastelandHordes.new()
	stage.add_child(director)
	director.session = stage
	var actor := WastelandCreature.new()
	stage.add_child(actor)
	actor.configure(director)
	for kind: String in ["walker","crawler","brute"]:
		for injury: int in [0,18,74,80]:
			actor.revive(kind,Vector3.ZERO,false,{"limb_index":injury})
			var ankle := actor.skeleton.find_bone("ankle_l")
			var knee := actor.skeleton.find_bone("knee_l")
			_check(actor.skeleton.get_bone_parent(ankle) == knee,kind+" ankle follows the calf")
			_check(actor.body_parts.ankle_l.visible == (actor.limb_damage.z == 0),kind+" boots follow limb damage")
			for normal: Vector3 in [Vector3.UP,Vector3(0,1,-0.22).normalized(),Vector3(0.23,1,0.09).normalized()]:
				actor.motion_floor_normal = normal
				if kind == "walker" and injury in [0,18]:
					_step(actor,"ankle_r")
				elif (kind == "crawler" or actor.low_crawl()) and actor.limb_damage.y == 0 and kind != "brute":
					_step(actor,"hand_r")
			for state: int in [WastelandCreatureBrain.State.SLEEPING,WastelandCreatureBrain.State.DEAD]:
				if state == WastelandCreatureBrain.State.DEAD:
					actor.begin_death()
				else:
					actor.brain.state = state as WastelandCreatureBrain.State
				actor.motion_speed = 0.0
				actor._pose(0.05,0,0)
				var lowest := INF
				for joint: String in actor.body_parts:
					lowest = minf(lowest,_mesh_floor(actor,joint))
				_check(absf(lowest) < 0.025,"%s/%d state %d surface rests on the floor at %.3fm" % [kind,injury,state,lowest])
			var head := actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("head"))
			actor._pose(0.19,0,0)
			_check(head.is_equal_approx(actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("head"))),kind+" settled corpse stops breathing")
			actor.deactivate()
	stage.queue_free()
	await process_frame
	for issue in failures: printerr(issue)
	print("Infected contacts: 12 bodies, level ground and two slopes, standing/crawling support and sleeping-to-death continuity; failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _step(actor: WastelandCreature, joint: String) -> void:
	var high := -INF
	var low := INF
	var planted := 0
	for i in 40:
		actor.motion_speed = 1.8
		actor.pose_phase = TAU*i/40.0
		actor._pose(0.05,0,0.09)
		var floor_y := _mesh_floor(actor,joint)
		high = maxf(high,floor_y)
		low = minf(low,floor_y)
		if absf(floor_y) < 0.025: planted += 1
	_check(low > -0.015 and high > 0.055 and planted >= 14,"%s/%d %s shows support and clearance (%.3f..%.3fm, %d samples planted)" % [actor.type,actor.limb_index,joint,low,high,planted])

func _mesh_floor(actor: WastelandCreature, joint: String) -> float:
	var attachment: Node3D = actor.body_parts[joint]
	if not attachment.visible: return INF
	var bone := actor.rig.transform*actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone(joint))
	var lowest := INF
	for mesh in attachment.get_children():
		if mesh is MeshInstance3D and mesh.visible:
			var at: Transform3D = bone*mesh.transform
			for p in mesh.mesh.get_faces():
				lowest = minf(lowest,actor.motion_floor_normal.dot(at*p))
	return lowest

func _check(valid: bool, issue: String) -> void:
	if not valid: failures.append(issue)
