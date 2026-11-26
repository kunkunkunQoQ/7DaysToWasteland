extends "res://tools/verify_frontier_economy.gd"

const DT := 1.0/60.0

func run() -> void:
	WastelandSave.root_override = "user://verification/creature-falls-%d" % OS.get_process_id()
	cfg = WastelandSave.default_world()
	cfg.seed = 2817
	cfg.terrain_revision = 2
	enter()
	var base := s.player.global_position+Vector3.UP*21
	var lower := _platform(base,Vector3(24,0.35,20))
	await _trial("walker",base,5.2,false,false)
	lower.rotation.z = 0.17
	await _trial("wolf",base,14.5,true,false)
	var water := _deep_site()
	if water.is_finite():
		await _trial("boar",water,7.0,false,true)
	else:
		check(false,"find an actual deep-water landing")
	await leave()
	print("CREATURE FALL checks=%d failures=%d" % [checks,failures])
	quit(int(failures>0))

func _platform(top: Vector3, size: Vector3) -> StaticBody3D:
	var platform := StaticBody3D.new()
	platform.collision_layer = 2
	var box := BoxShape3D.new()
	box.size = size
	var collider := CollisionShape3D.new()
	collider.shape = box
	platform.add_child(collider)
	s.add_child(platform)
	platform.global_position = top-Vector3.UP*size.y*0.5
	return platform

func _deep_site() -> Vector3:
	var start := s.player.global_position
	for r in range(12,120,6):
		for i in 16:
			var p := start+Vector3.RIGHT.rotated(Vector3.UP,i*TAU/16.0)*r
			p.y = 0.0
			if s.stream.generator.water_basin(p.x,p.z) and s.stream.generator.ground(p.x,p.z)<-3.8:
				s.stream.ensure_landing(p)
				if s.stream.water_at(p): return p
	return Vector3.INF

func _trial(kind: String, base: Vector3, height: float, fatal: bool, water: bool) -> void:
	var top := base+Vector3.UP*height
	var platform := _platform(top,Vector3(6.0,0.30,6.0))
	s.player.global_position = top+Vector3.BACK*15
	s.player.camera.look_at(s.player.camera.global_position+Vector3.BACK)
	var settings := {"facing":0.0,"wardrobe_index":0,"limb_index":0,"stride_phase":0.0}
	s.hordes._spawn(kind,top+Vector3.UP*0.04,false,settings)
	var actor := s.hordes.alive.back() as WastelandCreature
	var rig := actor.active_motion
	if not rig:
		check(false,kind+" spawns with articulated physics outside the camera")
		s.hordes.release(actor)
		return
	if fatal: actor.hp = minf(actor.hp,actor.max_health()*0.35)
	var initial_hp := actor.hp
	var torso := rig.body_for(&"torso").get_rid()
	var part_name := &"paw0" if actor.brain.animal else &"ankle_l"
	var limb := rig.body_for(part_name).get_rid()
	var xp := s.progress.xp
	var kills := int(s.progress.records.get("kill_"+kind,0))
	var drops := s.hordes.trophy_rng.state
	for i in 12:
		await physics_frame
		actor.think(DT,s.player)
	check(actor.grounded() and actor.active_motion==rig,kind+" stands on a real removable support with driven joints")
	platform.queue_free()
	var free_height := -1.0
	var launch_speed := 0.0
	var contact_height := INF
	var first_loss := 0.0
	var regained := false
	var reached_water := false
	var same_bones := true
	for i in 241:
		await physics_frame
		actor.think(DT,s.player)
		if actor.ragdoll:
			same_bones = same_bones and actor.ragdoll==rig and actor.ragdoll.body_for(&"torso").get_rid()==torso and actor.ragdoll.body_for(part_name).get_rid()==limb
			if free_height<0:
				free_height = actor.ragdoll.center().y-base.y
				launch_speed = -actor.ragdoll.motion().y
		elif free_height>=0 and actor.active_motion:
			regained = actor.active_motion==rig and actor.active_motion.body_for(part_name).get_rid()==limb
		if actor.hp<initial_hp and first_loss==0:
			first_loss = initial_hp-actor.hp
			contact_height = actor.physical_position().y-base.y
		reached_water = reached_water or (actor.motion_water and actor.physical_position().y<0)
		if regained or (water and reached_water) or actor.hp<=0.0: break
	print(kind," drop=",height," released above landing=",snappedf(free_height,0.01),
		" vy=",snappedf(launch_speed,0.1)," first health loss=",snappedf(first_loss,0.1)," at ",snappedf(contact_height,0.01)," m")
	if water:
		check(reached_water and actor.hp==initial_hp and actor.active_motion==rig and free_height<0,"a deep lake catches a high fall into swimming on the same articulated body")
	else:
		check(free_height>1.4 and launch_speed>5.8 and same_bones,kind+" releases its existing torso and extremities in the air with their downward momentum")
		check(first_loss>0.0 and contact_height<actor.capsule.height+0.5,"health changes at a real landing on "+("a slope" if fatal else "the floor"))
		if fatal:
			check(s.hordes.corpses.has(actor) and actor.hp==0.0 and s.progress.xp==xp and s.hordes.trophy_rng.state==drops and int(s.progress.records.get("kill_"+kind,0))==kills,"a lethal environmental landing keeps the corpse without XP, kill credit or trophy roll")
		else:
			check(regained and actor.hp==initial_hp-first_loss and actor.hp>0.0,"a survivor takes one impact and regains motor control of the same body")
	s.hordes.release(actor)
	await physics_frame
