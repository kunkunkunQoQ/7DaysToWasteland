extends "res://tools/verify_combat.gd"

var platform: StaticBody3D
var diagnose := false

func _run() -> void:
	diagnose = "--boar-diagnosis" in OS.get_cmdline_user_args()
	WastelandSave.root_override = "user://verification/unarmed-stability-%d" % OS.get_process_id()
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	var config: Dictionary = app._default_config()
	config.seed = 77026023
	config.difficulty = 1.0
	app._enter_world(config,{},0,false)
	session = app.session
	player = session.player
	session.simulation_paused = true
	session.bag.assign("",session.bag.active)
	_make_arena()
	platform = arena.get_child(0)
	platform.name = "PunchTestFloor"
	session.stream.ensure_landing(anchor+Vector3.BACK*5.0)
	await _ticks(3)
	if diagnose:
		await _one_punch("boar","body",false)
		await _one_punch("boar","body",true)
	else:
		for region: String in ["head","legs"]: await _one_punch("walker",region)
		await _one_punch("crawler","torso")
		for species: String in ["wolf","boar"]: await _one_punch(species,"body")
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	print("UNARMED STABILITY passed=%d failed=%d" % [passes,failures.size()])
	for issue in failures: printerr("FAILED: ",issue)
	quit(0 if failures.is_empty() else 1)

func _one_punch(kind: String, zone: String, strike := true) -> void:
	var label := kind+"/"+zone
	var at := anchor+Vector3(0,0.035,5)
	player.global_position = at+Vector3.BACK*4.0
	player.stamina = player.max_stamina()
	player.crouch = 0.0
	var actor := _spawn(kind,at,player.global_position,{"stride_phase":0.0,"limb_index":0,"wardrobe_index":0,"look_index":0,"morph":""})
	# A landing capsule or one trailing hoof can briefly register as grounded during a fall.
	var settled := 0
	for tick in 180:
		await _ticks(1,[actor])
		if diagnose and tick==0: _diagnostic(actor,"spawn")
		var grounded := is_instance_valid(actor.active_motion) and actor.grounded() and absf(actor.global_position.y-anchor.y)<0.16 and absf(actor.active_motion.motion().y)<1.0
		settled = settled+1 if grounded else 0
		if settled>=6 and _platform_supports(actor.active_motion): break
	var rig := actor.active_motion
	var hp := actor.hp
	var fixture := is_instance_valid(rig) and is_equal_approx(hp,actor.max_health()) and session.bag.current()=="" and settled>=6 and _platform_supports(rig)
	check(fixture,label+" starts on the floor at full health with an active rig and empty hands (rig=%s floor=%s hp=%.1f/%.1f held=%s y=%.3f)" % [rig!=null,actor.grounded(),hp,actor.max_health(),session.bag.current(),actor.global_position.y-anchor.y])
	if not fixture:
		session.hordes.release(actor)
		return
	var hit := _aim(actor,zone)
	if diagnose: _diagnostic(actor,"aim before strike=%s" % strike)
	check(not hit.is_empty(),label+" resolves through the player's melee ray")
	if hit.is_empty():
		session.hordes.release(actor)
		return
	var bone := actor.impact_bone(hit.collider,int(hit.shape),hit.position)
	var part := rig.body_for(bone)
	var before_velocity := part.linear_velocity
	var head := rig.body_for(&"head")
	var start_height := head.global_position.y-anchor.y
	var lowest := start_height
	var confirmations := player.confirmed_hit
	var previous_serial := actor.limb_hit_serial
	session.action_lock = 0.0
	if strike:
		Input.action_press("fire")
		session._process_controls(STEP)
		Input.action_release("fire")
	var loss := hp-actor.hp
	var impulse := (part.linear_velocity-before_velocity).length()
	var expected := 18.0 if zone=="head" else 7.2 if zone=="legs" else 9.0
	if strike:
		check(player.confirmed_hit==confirmations+1 and player.confirmed_melee and is_equal_approx(loss,expected),label+" confirms a single ordinary punch with the expected damage")
		check(actor.limb_hit_serial==previous_serial+1 and actor.ragdoll_hit_bone==bone and impulse>0.10,label+" applies a local velocity change to the struck body")
	var stayed_active := true
	var grounded_frames := 0
	for tick in 48:
		await _ticks(1,[actor])
		if diagnose and tick==47: _diagnostic(actor,"after 48 frames strike=%s" % strike)
		stayed_active = stayed_active and actor.active_motion==rig and actor.ragdoll==null and actor.brain.state!=BRAIN.State.KNOCKDOWN
		if not stayed_active: break
		if actor.grounded(): grounded_frames+=1
		lowest = minf(lowest,head.global_position.y-anchor.y)
	check(stayed_active and grounded_frames>=24 and lowest>start_height*0.55,label+" keeps its original active joints and supported stance for 0.8 seconds")
	print("PUNCH %s bone=%s health=%.1f->%.1f hit_dv=%.3f m/s head_height=%.3f(min %.3f) grounded=%d/48" % [label,bone,hp,actor.hp,impulse,start_height,lowest,grounded_frames])
	session.hordes.release(actor)
	await _ticks(2)

func _aim(actor: WastelandCreature, zone: String) -> Dictionary:
	var area: Area3D = actor.hurtboxes.areas[zone]
	for shape: CollisionShape3D in area.get_children():
		if zone in ["body","torso"] and shape.name!=&"torso": continue
		for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD]:
			var target := shape.global_position
			player.global_position = Vector3(target.x,anchor.y+0.035,target.z)+direction*1.5
			player.camera.look_at(target)
			var hit := session._trace(2.58,15,false,true,true)
			if hit.get("collider")!=area: continue
			if zone in ["body","torso"] and actor.impact_bone(area,int(hit.shape),hit.position)!=&"torso": continue
			if not _player_overlap().is_empty(): continue
			return hit
	return {}

func _diagnostic(actor: WastelandCreature, stage: String) -> void:
	var rig := actor.active_motion if actor.active_motion!=null else actor.ragdoll as WastelandActiveRagdoll
	if rig==null: return
	var footholds := {}
	var feet: Array[Vector3] = []
	for index in rig.balance._feet:
		var paw: RigidBody3D = rig._parts[index].body
		feet.append(paw.global_position-anchor)
		var state := PhysicsServer3D.body_get_direct_state(paw.get_rid())
		for n in state.get_contact_count():
			var surface := state.get_contact_collider_object(n) as CollisionObject3D
			if surface!=null and state.get_contact_local_normal(n).y>0.45:
				footholds[String(surface.name)+"@"+str(surface.collision_layer)] = surface==platform
	print("BOAR ",stage," root=",actor.global_position-anchor," hip=",rig.center()-anchor," head=",rig.body_for(&"head").global_position-anchor," hooves=",feet," supports=",footholds," capsule=",actor.capsule_grounded," ground=",actor.grounded()," vel=",rig.motion()," state=",BRAIN.State.keys()[actor.brain.state]," player=",player.global_position-anchor," player_overlap=",_player_overlap())

func _player_overlap() -> Array[String]:
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = player.capsule.shape
	probe.transform = player.capsule.global_transform
	probe.collision_mask = 1|2|4|8|WastelandActiveRagdoll.CONTACT_LAYER
	probe.exclude = [player.get_rid()]
	var overlap: Array[String] = []
	for row in session.get_world_3d().direct_space_state.intersect_shape(probe,64):
		var other := row.collider as CollisionObject3D
		if is_instance_valid(player.live_avatar) and is_instance_valid(player.live_avatar.active_motion) and player.live_avatar.active_motion.is_ancestor_of(other):
			continue
		overlap.append(String(other.name)+"@"+str(other.collision_layer))
	return overlap

func _platform_supports(rig: WastelandActiveRagdoll) -> bool:
	for index in rig.balance._feet:
		var paw: RigidBody3D = rig._parts[index].body
		var state := PhysicsServer3D.body_get_direct_state(paw.get_rid())
		for n in state.get_contact_count():
			if state.get_contact_collider_object(n)==platform and state.get_contact_local_normal(n).y>0.45:
				return true
	return false
