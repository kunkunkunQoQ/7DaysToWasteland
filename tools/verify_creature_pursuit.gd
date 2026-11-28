extends "res://tools/verify_survivor_fall.gd"

func run() -> void:
	WastelandSave.root_override = "user://verification/creature-pursuit-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 2817
	open_world({})
	session.clock.hours = 12.0
	session.hordes.next_sim = 1000.0
	session.simulation_paused = false
	var floor_at := session.player.global_position + Vector3.UP * 12.0
	_slab(floor_at - Vector3.UP*0.2,Vector3(28,0.4,28),false)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	for kind: String in ["walker","boar","crawler","wolf"]:
		if not only.is_empty() and kind!=only: continue
		session.player.global_position = floor_at + Vector3.UP*0.04
		for i in 36: await physics_frame
		await _pursue(kind,floor_at)
	await close_world()
	print("CREATURE PURSUIT checks=",passed + failures," failures=",failures)
	quit(int(failures > 0))

func _pursue(kind: String, floor_at: Vector3) -> void:
	var charging_animal: bool = session.catalog.enemies[kind].ai.has("charge_threshold")
	var distance := 5.6 if charging_animal else 7.2
	var start := floor_at + Vector3.BACK*distance + Vector3.UP*0.05
	var saved := {"facing":0.0,"wardrobe_index":0,"limb_index":0,"stride_phase":0.0,"wildlife_cycle":0.0}
	if charging_animal: saved.hp = float(session.catalog.enemies[kind].hp)*0.45
	var spawned := session.hordes._spawn(kind,start,false,saved)
	check(spawned,kind+" spawns through the active horde director")
	if not spawned: return
	var actor := session.hordes.alive.back() as WastelandCreature
	var rig := actor.active_motion
	check(is_instance_valid(rig),kind+" spawns with an active physics rig")
	if not is_instance_valid(rig): return
	var labels := ["ankle_l","ankle_r"]
	if actor.brain.animal: labels = ["paw3","paw2","paw1","paw0"]
	if kind == "crawler": labels = ["hand_l","hand_r","ankle_l","ankle_r"]
	var parts: Array[RigidBody3D] = []
	for label: String in labels: parts.append(rig.body_for(label))
	var reaches := PackedFloat32Array()
	for label: String in labels:
		var index: int = rig._index_by_bone[StringName(label)]
		var point := rig._parts[index].body.global_position
		var length := 0.0
		while rig._parts[index].parent >= 0:
			var part := rig._parts[index]
			var joint := (part.body.global_transform * part.bind).origin
			length += point.distance_to(joint)
			point = joint
			index = part.parent
		reaches.append(length + point.distance_to(rig.center()))
	var axis := (session.player.global_position-start).slide(Vector3.UP).normalized()
	var hip_start := rig.center()
	var capsule_start := actor.global_position
	var starting_gap := (hip_start-session.player.global_position).slide(Vector3.UP).length()
	var min_gap := starting_gap
	var seen := false
	var chase := false
	var masks := {}
	var first_contacts := 0
	var replanted := 0
	var off_ticks := PackedInt32Array()
	off_ticks.resize(parts.size())
	var intent_ticks := 0
	var excess_reach := 0.0
	var phase := actor.wildlife_cycle*TAU if actor.brain.animal else actor.pose_phase
	var stride_turns := 0.0
	var trace := "--trace" in OS.get_cmdline_user_args()
	if trace:
		for part in rig._parts: part.body.max_contacts_reported = 8
		print(kind," spawn root=",actor.global_position-floor_at," hub=",rig.center()-floor_at,
			" first=",rig._parts[0].body.name," rest=",actor.skeleton.get_bone_rest(0).origin,
			" goal=",rig._targets[0].origin," foot3=",parts[0].global_position-floor_at)
	for i in 190:
		await physics_frame
		seen = seen or actor.brain.seen == session.player
		chase = chase or (actor.brain.seen==session.player and actor.brain.mode in [WastelandCreatureBrain.Mode.CHASE,WastelandCreatureBrain.Mode.FLANK])
		min_gap = minf(min_gap,(rig.center()-session.player.global_position).slide(Vector3.UP).length())
		for j in parts.size():
			excess_reach = maxf(excess_reach,rig.center().distance_to(parts[j].global_position)-reaches[j])
		if trace and i%30==0:
			var real_contacts := []
			var feet_y := []
			var inertia := []
			for part in rig._parts:
				if _floor_contact(part.body): real_contacts.append(part.body.name)
			for part in parts:
				feet_y.append(snappedf(part.global_position.y-floor_at.y,0.01))
			var root_body := rig._parts[0].body
			inertia = [snappedf(root_body.global_basis.y.y,0.01),snappedf(root_body.global_basis.z.y,0.01)]
			print(kind," tick=",i," seen=",actor.brain.seen==session.player," mode=",actor.brain.mode,
				" command=",actor.ground_intent," height=",snappedf(rig.center().y-floor_at.y,0.01)," rot=",inertia,
				" feet_y=",feet_y," ground=",real_contacts," phase_support=",actor.foot_contacts.stance_bones)
		if actor.ground_intent.dot(axis) > 0.15:
			intent_ticks += 1
			var next_phase := actor.wildlife_cycle*TAU if actor.brain.animal else actor.pose_phase
			stride_turns += angle_difference(phase,next_phase)/TAU
			phase = next_phase
			var mask := 0
			for j in parts.size():
				var bit := 1 << j
				if _floor_contact(parts[j]):
					mask |= bit
					if (first_contacts & bit) and off_ticks[j]>=2: replanted |= bit
					first_contacts |= bit
					off_ticks[j] = 0
				else:
					off_ticks[j] += 1
			masks[mask] = int(masks.get(mask,0)) + 1
		if i > 50 and min_gap < 1.45: break
	var hip_advance := (rig.center()-hip_start).dot(axis)
	var capsule_advance := (actor.global_position-capsule_start).dot(axis)
	print(kind," intent_ticks=",intent_ticks," actual_foot_masks=",masks," replanted=",replanted,
		" hip_forward=",snappedf(hip_advance,0.001)," capsule_forward=",snappedf(capsule_advance,0.001),
		" gap_start/end/min=",[snappedf(starting_gap,0.001),snappedf((rig.center()-session.player.global_position).slide(Vector3.UP).length(),0.001),snappedf(min_gap,0.001)],
		" strides=",snappedf(stride_turns,0.01)," excess_limb_reach=",snappedf(excess_reach,0.001))
	check(seen and chase and intent_ticks >= 12,kind+" sees the real player and chooses pursuit")
	check(minf(hip_advance,capsule_advance)>1.10 and starting_gap-min_gap>1.10,kind+" physically closes on the player")
	var opposite_support := false
	for a: int in masks:
		for b: int in masks:
			if (a & ~b) and (b & ~a) and mini(masks[a],masks[b])>=2:
				opposite_support = true
	check(stride_turns>0.45 and opposite_support and (replanted & (replanted-1))!=0,kind+" advances its gait, exchanges actual floor loads and replants two limbs")
	check(excess_reach < 0.09,kind+" keeps its extremities within their articulated reach during pursuit")
	session.hordes.release(actor)

func _floor_contact(body: RigidBody3D) -> bool:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null: return false
	for i in state.get_contact_count():
		var floor_body := state.get_contact_collider_object(i) as PhysicsBody3D
		var normal := state.get_contact_local_normal(i)
		if floor_body and (floor_body.collision_layer & 3) and normal.y>0.6:
			if state.get_contact_impulse(i).dot(normal)>maxf(0.0001,body.mass*0.001): return true
	return false
