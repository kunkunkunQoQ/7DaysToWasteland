extends "res://tools/verify_combat.gd"

func _run() -> void:
	WastelandSave.root_override = "user://verification/creature-ragdoll-%d" % OS.get_process_id()
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override + "/options.cfg"
	root.add_child(app)
	app._enter_world(app._default_config(), {}, 0, false)
	session = app.session
	session.simulation_paused = true
	player = session.player
	_make_arena()
	await _ticks(4)
	var at := anchor + Vector3(0,0.04,5)
	for kind: String in WastelandHordes.KINDS + WastelandHordes.WILDLIFE:
		var actor := _spawn(kind,at,at+Vector3.LEFT,{"limb_index":0})
		session.hordes.defeated(actor)
		_check_anatomy(actor)
		session.hordes.release(actor)
	var amputee := _spawn("walker",at,at+Vector3.LEFT,{"limb_index":80})
	session.hordes.defeated(amputee)
	_check_anatomy(amputee)
	check(amputee.ragdoll.body_for("hand_l")==null and amputee.ragdoll.body_for("ankle_r")==null and amputee.ragdoll.body_for("elbow_l")!=null,"missing hands and feet have neither shapes nor rigid bodies; remaining stumps still respond")
	session.hordes.release(amputee)
	var plated := _spawn("walker",at,at+Vector3.LEFT,{"limb_index":0,"morph":"armored"})
	check(plated.hand_impact_damage("torso",at,&"arm_l") == 4 and plated.hand_impact_damage("torso",at,&"hand_l")==0 and plated.hand_impact_damage("torso",at,&"elbow_r")==0,
		"striking an upper-arm plate bruises the hand while the exposed palm and forearm remain soft")
	session.hordes.release(plated)
	await _direct_hits(at)
	await _locomotion(at)
	for kind: String in ["walker","boar"]:
		var actor := _spawn(kind,at,at+Vector3.LEFT,{"limb_index":0})
		actor.take_hit(23.0,at+Vector3.LEFT,true)
		var down_at := actor.physical_position()
		await _ticks(45,[actor])
		var moved := actor.physical_position() - down_at
		check(actor.hp > 0.0 and actor.ragdoll != null and moved.x > 0.25 and actor.brain.action == BRAIN.Action.NONE,kind+" yields to the impact and stops attacking while down")
		var saved_hp := actor.hp
		var target: Vector3 = actor.hurtboxes.areas.body.get_node("torso").global_position if actor.brain.animal else actor.hurtboxes.areas.torso.get_child(0).global_position
		var hit := session.weapon_hit(target+Vector3.UP*2,target,[])
		if not hit.is_empty():
			session.projectile_hit("bullet",1.0,hit,player)
		check(actor.hp < saved_hp,kind+" can be hit at its fallen body's actual position")
		var peak := 0.0
		for i in 108:
			await _ticks(1,[actor])
			if actor.brain.animal and actor.ragdoll != null:
				for label: StringName in [&"ear_l",&"ear_r",&"paw0",&"paw1",&"paw2",&"paw3"]:
					var body := actor.ragdoll.body_for(label)
					var shape: CapsuleShape3D = body.get_child(0).shape
					peak = maxf(peak,body.linear_velocity.length()+body.angular_velocity.length()*shape.height*0.5)
		if actor.brain.animal:
			check(peak < 20.0,"a second small hit keeps ear and paw speeds bounded (peak %.2f m/s)" % peak)
		check(actor.ragdoll == null and actor.brain.state != BRAIN.State.KNOCKDOWN and actor.global_position.y >= anchor.y-0.1 and actor.global_position.distance_to(at)>0.25,
			"%s regains control at the landing point (state %d, feet %s, physical %s relative to impact)" % [kind,actor.brain.state,actor.global_position-at,actor.physical_position()-at])
		session.hordes.release(actor)
	var prey := _spawn("hare",at,at+Vector3.LEFT)
	var wolf := _spawn("wolf",at+Vector3.LEFT*0.5,at)
	var hunt_credit := int(session.progress.records.get("kill_hare",0))
	prey.hp = 1.0
	wolf.brain._pursue(prey)
	check(prey.ragdoll != null and session.hordes.corpses.has(prey) and int(session.progress.records.get("kill_hare",0)) == hunt_credit,"natural predation leaves physical remains without a player kill")
	await _ticks(70,[prey])
	var saved := prey.serialize()
	var before := prey.physical_position()
	session.hordes.release(prey)
	session.hordes._spawn("hare",saved.at,false,saved)
	var loaded := session.hordes.corpses.back() as WastelandCreature
	check(loaded.ragdoll != null and loaded.physical_position().distance_to(before)<0.03 and is_equal_approx(loaded.brain.state_left,saved.state_left),"reloading a wildlife corpse restores its physical location and remaining lifetime")
	session.hordes.tick_corpses(loaded.brain.state_left+0.05)
	check(not loaded.active,"corpse expiry advances even when living AI is paused")
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	for issue in failures: printerr(issue)
	print("CREATURE RAGDOLL passed=%d failed=%d" % [passes,failures.size()])
	quit(int(not failures.is_empty()))

func _check_anatomy(actor: WastelandCreature) -> void:
	var names := {}
	for row in actor.hurtboxes.bindings:
		names[row.shape.name] = true
	var present := 0
	var exact := actor.ragdoll != null
	for i in actor.skeleton.get_bone_count():
		var name := actor.skeleton.get_bone_name(i)
		var exists: bool = actor.body_parts[name].visible
		var body := actor.ragdoll.body_for(name)
		exact = exact and (body != null) == exists and names.has(name) == exists
		if not exists: continue
		present += 1
		var parent := actor.skeleton.get_bone_parent(i)
		if parent < 0: continue
		var joint := actor.ragdoll.get_node_or_null("Joint_" + String(name).to_lower()) as Joint3D
		exact = exact and joint != null and joint.get_node(joint.node_b) == body and joint.get_node(joint.node_a) == actor.ragdoll.body_for(actor.skeleton.get_bone_name(parent))
	exact = exact and actor.ragdoll.find_children("*","RigidBody3D",false,false).size() == present and actor.ragdoll.find_children("*","Joint3D",false,false).size() == present-1
	check(exact,"%s/%d has exactly one physical body and hit shape per visible bone, linked to its anatomical parent" % [actor.type,actor.limb_index])

func _ray_at(actor: WastelandCreature, label: StringName) -> Dictionary:
	var shape: CollisionShape3D
	for row in actor.hurtboxes.bindings:
		if row.shape.name == label:
			shape = row.shape
			break
	if not shape: return {}
	var point := shape.global_position
	var exterior := (point - actor.global_position - Vector3.UP*actor.body_height()*0.5).normalized()
	for side: Vector3 in [exterior,Vector3.UP,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT,Vector3.FORWARD,Vector3.DOWN]:
		var from := point + side * 0.42
		var hit := session.weapon_hit(from,point+side*0.001,[])
		if hit.get("collider") == shape.get_parent() and actor.impact_bone(hit.collider,hit.shape,hit.position) == label:
			hit.origin = from
			return hit
	return {}

func _direct_hits(at: Vector3) -> void:
	for pair: Array in [["walker","arm_l","arm_r"],["walker","arm_r","arm_l"],["walker","hand_l","hand_r"],
			["fox","tail_tip","torso"],["fox","paw0","paw1"],["hare","ear_r","ear_l"]]:
		var actor := _spawn(pair[0],at,at+Vector3.FORWARD,{"limb_index":0})
		await _ticks(2)
		var hit := _ray_at(actor,pair[1])
		if hit.is_empty():
			check(false,"%s ray reaches %s" % [pair[0],pair[1]])
			session.hordes.release(actor)
			continue
		var start := player.global_position
		player.global_position = hit.origin
		session.projectile_hit("bullet",1000,hit,player,hit.origin)
		player.global_position = start
		var selected := actor.ragdoll.body_for(pair[1])
		var opposite := actor.ragdoll.body_for(pair[2])
		var struck := PhysicsServer3D.body_get_direct_state(selected.get_rid())
		var other := PhysicsServer3D.body_get_direct_state(opposite.get_rid())
		check(actor.ragdoll_hit_bone == StringName(pair[1]) and actor.ragdoll_hit_at.distance_squared_to(hit.position)<0.0001 and struck.linear_velocity.length() > other.linear_velocity.length()+0.2,
			"%s ray through %s applies the first impulse to that limb instead of %s" % pair)
		if pair[1] in ["hand_l","paw0"]:
			await _repeat_corpse_hit(actor,selected,opposite)
		session.hordes.release(actor)

func _repeat_corpse_hit(actor: WastelandCreature, selected: RigidBody3D, other: RigidBody3D) -> void:
	await _ticks(3)
	var point := selected.global_position
	var incoming := {}
	var origin := point
	var outward := (point-actor.ragdoll.center()).normalized()
	for side: Vector3 in [outward,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,Vector3.UP,Vector3.DOWN]:
		origin = point + side * 0.32
		incoming = session.weapon_hit(origin,point,[])
		if incoming.get("collider") == selected:
			break
	if incoming.get("collider") != selected:
		check(false,actor.type+" corpse exposes its "+String(selected.name)+" to a real weapon ray")
		return
	var kills := int(session.progress.records.get("kill_"+actor.type,0))
	var loot := session.fx.serial
	var selected_before := PhysicsServer3D.body_get_direct_state(selected.get_rid()).linear_velocity
	var other_before := PhysicsServer3D.body_get_direct_state(other.get_rid()).linear_velocity
	session.projectile_hit("bullet",32,incoming,player,origin)
	var selected_delta := PhysicsServer3D.body_get_direct_state(selected.get_rid()).linear_velocity.distance_to(selected_before)
	var other_delta := PhysicsServer3D.body_get_direct_state(other.get_rid()).linear_velocity.distance_to(other_before)
	check(selected_delta > 0.5 and other_delta < 0.02 and int(session.progress.records.get("kill_"+actor.type,0))==kills and session.fx.serial==loot and actor.hp==0.0,
		actor.type+" corpse takes the second shot on "+String(selected.name)+" without a second kill or drop")

func _locomotion(at: Vector3) -> void:
	var start := player.global_transform
	player.global_position = at + Vector3.BACK*3.0
	player.camera.look_at(at+Vector3.UP)
	var actor := _spawn("walker",at,player.global_position,{"limb_index":0})
	actor._pose(0.05,3.0,0.0)
	var active := actor.active_motion
	check(active != null,"a nearby living creature creates the articulated motor rig")
	if active != null:
		var hand := active.body_for("hand_l")
		var before := hand.global_position
		for i in 24:
			actor.attack = 0.8 if i > 12 else 0.0
			actor._pose(STEP,3.0,0.022)
			await physics_frame
		check(actor.active_motion == active and hand.global_position.distance_to(before) > 0.018,"gait and attack targets move a real hand body")
		actor.take_hit(1000.0,player.global_position,true,false,hand.global_position,&"hand_l")
		check(actor.ragdoll == active and actor.ragdoll.body_for("hand_l") == hand,"a lethal hand strike releases the same live joint system")
	session.hordes.release(actor)
	for kind: String in ["boar","jerboa"]:
		actor = _spawn(kind,at,at+Vector3.FORWARD)
		actor._pose(0.05,3.0,0.01)
		active = actor.active_motion
		var paw := active.body_for("paw0") if active != null else null
		var start_offset := paw.global_position-actor.global_position if paw != null else Vector3.ZERO
		var swing := 0.0
		for i in 45:
			var travel := STEP * (1.5 if i < 18 else 4.5)
			actor.global_position += Vector3.FORWARD*travel
			actor._pose(STEP,3.0,travel)
			await physics_frame
			if paw != null:
				swing = maxf(swing,(paw.global_position-actor.global_position).distance_to(start_offset))
		check(active != null and actor.active_motion == active and swing > 0.025 and paw.global_position.distance_to(actor.global_position) < actor.body_height()+0.45,
			kind+" walks and runs with an independently moving physical paw that stays attached")
		session.hordes.release(actor)
	player.global_transform = start
