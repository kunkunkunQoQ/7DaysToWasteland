extends "res://tools/verify_infected_looks.gd"

const STEP := 1.0/60.0

func run() -> void:
	WastelandSave.root_override = "user://verification/cloth-%d" % OS.get_process_id()
	cfg = WastelandSave.default_world()
	cfg.seed = 2817
	enter()
	var triangles := 0
	for i in WastelandCreature.WARDROBE_COUNT:
		var individual := spawn("walker",{"wardrobe_index":i,"limb_index":0})
		for node: MeshInstance3D in individual.skeleton.find_children("*","MeshInstance3D",true,false):
			if node.name in [&"OuterShirt",&"ShirtSleeve",&"PersonalEffects"]:
				triangles += node.mesh.get_faces().size()/3
		s.hordes.release(individual)
	print("Walker wardrobe triangles across 36 combinations: ",triangles," (previously 16356)")
	check(triangles < 11000,"outfits keep a smaller mesh budget including sleeves, buttons, patches and carry kits")
	for kind: String in ["walker","crawler"]:
		var actor := spawn(kind,{"wardrobe_index":18,"limb_index":0,"facing":0.0,"stride_phase":1.0})
		_verify_motion(actor)
		s.hordes.release(actor)
	await _verify_ragdolls()
	await leave()
	print("INFECTED CLOTH QA checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func _verify_motion(actor: WastelandCreature) -> void:
	var cloth := actor.cloth_motion
	var cam := s.player.camera
	cam.global_position = actor.global_position + Vector3(0,1.5,6)
	cam.look_at(actor.global_position+Vector3.UP)
	cam.make_current()
	actor.motion_preview = true
	actor.rotation.y = 0
	var peak := 0.0
	for i in 20:
		actor.global_position.x += 0.055
		actor._pose(1.0/30.0,6.0,0.055)
		peak = maxf(peak,cloth.offset.length())
	print(actor.type," movement deflection (mm): ",snappedf(1000*peak,0.1))
	check(peak>0.005 and peak<=cloth.TRAVEL,"motion of the "+actor.type+" torso drives a bounded cloth response")
	check(cloth.shirt.get_blend_shape_value(0)<-0.01 and cloth.accessory.get_blend_shape_value(0)<-0.005,"jacket and carried object trail sideways acceleration")
	var shape: ArrayMesh = cloth.shirt.mesh
	var points: PackedVector3Array = shape.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var target: PackedVector3Array = shape.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
	var top_motion := 0.0
	var hem_motion := 0.0
	for i in points.size():
		var movement := points[i].distance_to(target[i])
		if points[i].y>0.22: top_motion=maxf(top_motion,movement)
		if points[i].y<0.0: hem_motion=maxf(hem_motion,movement)
	check(top_motion<0.0002 and hem_motion>0.02,"shoulder vertices stay pinned while the hem has real displacement")
	for i in 40: actor._pose(1.0/30.0,6.0,0.0)
	check(absf(cloth.offset.x)<peak*0.3,"sideways swing damps after a stop")
	cam.rotate_y(PI)
	actor._pose(0.12,6.0,0.0)
	check(not cloth.anchor.is_finite() and cloth.offset.is_zero_approx(),"offscreen garment returns to rest and stops integrating")
	cam.look_at(actor.global_position+Vector3.UP)
	actor._pose(0.12,60.0,0.0)
	check(not cloth.anchor.is_finite(),"distant actors skip cloth integration")
	actor._pose(0.12,6.0,0.0)
	check(cloth.anchor.is_finite() and cloth.offset.is_zero_approx(),"returning to the foreground reseeds without a catch-up swing")
	if DisplayServer.get_name() != "headless": _verify_rendered_mix(cloth.shirt)
	actor.motion_preview = false

func _verify_rendered_mix(shirt: MeshInstance3D) -> void:
	shirt.set_blend_shape_value(0,-0.5)
	var original := shirt.mesh.surface_get_arrays(0)
	var baked := shirt.bake_mesh_from_current_blend_shape_mix().surface_get_arrays(0)
	var collar_error := 0.0
	var collar_lighting_error := 0.0
	var hem_motion := 0.0
	for i in original[Mesh.ARRAY_VERTEX].size():
		var point: Vector3 = original[Mesh.ARRAY_VERTEX][i]
		var moved := point.distance_to(baked[Mesh.ARRAY_VERTEX][i])
		if point.y>0.22:
			collar_error = maxf(collar_error,moved)
			collar_lighting_error = maxf(collar_lighting_error,original[Mesh.ARRAY_NORMAL][i].angle_to(baked[Mesh.ARRAY_NORMAL][i]))
		if point.y<0.0: hem_motion = maxf(hem_motion,moved)
	check(collar_error<0.0002 and collar_lighting_error<0.005 and hem_motion>0.015,"rendered blend holds the collar and its lighting while displacing the hem")
	shirt.set_blend_shape_value(0,0.0)

func _verify_ragdolls() -> void:
	var at := s.player.global_position+Vector3.UP*22.0
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24,1,24)
	collision.shape = box
	floor_body.add_child(collision)
	s.add_child(floor_body)
	floor_body.global_position = at-Vector3.UP*0.5
	s.player.global_position = at+Vector3.BACK*6
	var cam := s.player.camera
	cam.global_position = at+Vector3(0,2.0,6)
	cam.look_at(at+Vector3.UP)
	cam.make_current()
	for i in 3: await physics_frame

	var outfit := {"wardrobe_index":18,"limb_index":0,"face_variant":0,"facing":0.0,"stride_phase":1.0}
	var actor := spawn("walker",outfit)
	actor.global_position = at+Vector3.UP*0.04
	actor._pose(0.05,6.0,0.0)
	var live := actor.active_motion
	check(live != null,"a nearby walker wears the jacket on its active articulated bodies")
	if live == null:
		s.hordes.release(actor)
		return
	for i in 12: await physics_frame
	var cloth := actor.cloth_motion
	var torso := live.body_for(&"torso")
	var idle := cloth.offset
	actor.take_hit(1.0,torso.global_position+Vector3.LEFT,false,false,torso.global_position,&"torso")
	var peak := 0.0
	var error := 0.0
	for i in 20:
		await physics_frame
		peak = maxf(peak,cloth.offset.distance_to(idle))
		error = maxf(error,cloth.anchor.distance_to(_torso_anchor(actor)))
	check(peak>0.001 and error<0.0002,"an active torso strike moves the jacket without animation ticks and samples the written bone (%.1f mm)" % (peak*1000))

	actor.take_hit(4.0,torso.global_position+Vector3.LEFT,true,true,torso.global_position,&"torso")
	check(actor.ragdoll==live and actor.ragdoll.body_for(&"torso")==torso,"knockdown keeps the clothing on the same physical torso")
	var upright := cloth.anchor
	var falling := cloth.offset
	peak = 0.0
	error = 0.0
	for i in 36:
		await physics_frame
		actor.think(STEP,s.player)
		peak = maxf(peak,cloth.offset.distance_to(falling))
		error = maxf(error,cloth.anchor.distance_to(_torso_anchor(actor)))
	print("Physical knockdown cloth change (mm): ",snappedf(peak*1000,0.1))
	check(cloth.anchor.distance_to(upright)>0.15 and peak>0.004 and error<0.0002,"passive falling torso drives actual cloth deflection through its last written pose")
	for i in 150:
		await physics_frame
		actor.think(STEP,s.player)
		if actor.ragdoll==null and actor.rise_from.is_empty(): break
	await physics_frame
	check(actor.ragdoll==null and actor.active_motion!=null and cloth.anchor.is_finite() and cloth.anchor.distance_to(_torso_anchor(actor))<0.001,
		"get-up hands the same outfit back to the living rig (state %d, pose error %.2f mm)" % [actor.brain.state,cloth.anchor.distance_to(_torso_anchor(actor))*1000])
	s.hordes.release(actor)
	check(not cloth.anchor.is_finite() and cloth.offset.is_zero_approx(),"return to pool clears cloth velocity and both weights")

	actor = spawn("walker",outfit)
	actor.global_position = at+Vector3.UP*0.4
	s.hordes.defeated(actor)
	cloth = actor.cloth_motion
	check(actor.ragdoll!=null and actor.ragdoll!=live and actor.active_motion==null,"cold-start death creates an independent physical corpse simulation")
	for i in 55:
		await physics_frame
		s.hordes.tick_corpses(STEP)
	check(cloth.anchor.is_finite() and cloth.offset.length()>0.003,"corpse clothing continues moving when only the corpse director runs")
	actor.ragdoll.settle()
	for i in 75:
		await physics_frame
		s.hordes.tick_corpses(STEP)
	var garment := actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(cloth.torso) * cloth.shirt.transform
	var gravity := garment.basis.orthonormalized().transposed() * (Vector3.DOWN*3.5)
	var drape := Vector2(gravity.x,gravity.z)/(cloth.SPRING*cloth.SPRING)
	check(cloth.offset.distance_to(drape)<0.001,"a settled corpse finishes draping in its final orientation")
	_verify_replica_rest(actor,drape)
	torso = actor.ragdoll.body_for(&"torso")
	var contact := {"collider":torso,"position":torso.global_position,"normal":Vector3.LEFT}
	s.projectile_hit("bullet",64.0,contact,s.player,torso.global_position+Vector3(-0.9,-0.3,0))
	check(not actor.ragdoll_settled(),"a second projectile hit wakes the existing corpse rig")
	peak = 0.0
	var pack_peak := 0.0
	var pack_initial := Vector2(cloth.accessory.get_blend_shape_value(0),cloth.accessory.get_blend_shape_value(1))
	for i in 24:
		await physics_frame
		s.hordes.tick_corpses(STEP)
		peak = maxf(peak,cloth.offset.distance_to(drape))
		var pack := Vector2(cloth.accessory.get_blend_shape_value(0),cloth.accessory.get_blend_shape_value(1))
		pack_peak = maxf(pack_peak,pack.distance_to(pack_initial)*cloth.TRAVEL)
	print("Corpse re-impact cloth change (mm): ",snappedf(peak*1000,0.1))
	check(peak>0.003 and pack_peak>0.002 and cloth.anchor.distance_to(_torso_anchor(actor))<0.0002,"the woken torso and its carried gear respond to repeated impacts")
	s.hordes.tick_corpses(actor.brain.state_left+0.1)
	check(not actor.active and not cloth.anchor.is_finite() and cloth.shirt.get_blend_shape_value(0)==0.0,"expiring the corpse clears its physics and clothes for the next occupant")

func _torso_anchor(actor: WastelandCreature) -> Vector3:
	var cloth := actor.cloth_motion
	return actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(cloth.torso) * cloth.shirt.transform * Vector3(0,0.20,0.04)

func _verify_replica_rest(actor: WastelandCreature, drape: Vector2) -> void:
	var net := WastelandLan.new()
	var id := actor.spawn_serial
	net.smooth_actors[id] = actor
	net.resting_creatures[id] = {"pose":actor.ragdoll_pose(),"frame":net._creature_frame(actor),"expires":Time.get_ticks_msec()+2000}
	var rows := [[id]]
	actor.cloth_motion.reset()
	for i in 90: net._pose_actors(s,rows,STEP)
	check(actor.has_meta("rest_frame") and actor.cloth_motion.offset.distance_to(drape)<0.001,"a guest applies the final pose and compact one-field corpse updates let the garment settle")
	s.player.camera.rotate_y(PI)
	for i in 12: net._pose_actors(s,rows,STEP)
	check(not actor.cloth_motion.anchor.is_finite(),"offscreen replica corpses suspend their cloth")
	s.player.camera.look_at(actor.physical_position())
	for i in 90: net._pose_actors(s,rows,STEP)
	check(actor.cloth_motion.offset.distance_to(drape)<0.001,"looking back at a settled replica restores gravity draping from its saved pose")
	actor.remove_meta("rest_frame")
	net.free()
