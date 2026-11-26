extends "res://tools/verify_infected_looks.gd"

const Motion := preload("res://game/actors/active_ragdoll.gd")
var at: Vector3

func run() -> void:
	WastelandSave.root_override = "user://verification/balance-%d" % OS.get_process_id()
	cfg = WastelandSave.default_world()
	enter()
	at = s.player.global_position+Vector3.UP*22
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(26,1,26)
	collision.shape = box
	floor_body.add_child(collision)
	s.add_child(floor_body)
	floor_body.global_position = at-Vector3.UP*0.50
	s.player.global_position = at+Vector3.BACK*5
	s.player.camera.look_at(at+Vector3.UP)
	s.player.camera.make_current()
	await _ticks(3)
	await _verify_survivor()
	for kind: String in WastelandHordes.KINDS + WastelandHordes.WILDLIFE:
		await _verify_creature(kind)
	await _verify_creature("walker",54)
	await _verify_creature("walker",72)
	await _verify_water()
	await leave()
	print("REACTIVE BALANCE QA checks=%d failures=%d" % [checks,failures])
	quit(int(failures>0))

func _ticks(n: int) -> void:
	for i in n: await physics_frame

func _verify_survivor() -> void:
	var avatar := WastelandPartyAvatar.new()
	avatar.show_tag = false
	s.add_child(avatar)
	avatar.global_position = at+Vector3.UP*0.02
	var rig := Motion.start(avatar,avatar,null,true)
	await _ticks(45)
	var hip := rig.body_for(&"hips")
	var torso := rig.body_for(&"torso")
	var hit := rig.body_for(&"hand_r")
	var home := torso.global_position
	rig.kick_at(Vector3.RIGHT*5.4,hit.global_position,&"hand_r")
	var wrist_gain := rig.balance.frequency_scale(rig._index_by_bone[&"hand_r"])
	var other_gain := rig.balance.frequency_scale(rig._index_by_bone[&"hand_l"])
	var wrist_peak := 0.0
	for i in 65:
		await physics_frame
		wrist_peak = maxf(wrist_peak,torso.global_position.distance_to(home))
	check(wrist_gain<0.55 and other_gain>0.97 and rig.balance.strain==0.0,"a right-hand strike gives only that limb and its parent yielding motors and recovers")
	var lead := rig.body_for(&"ankle_r")
	var other := rig.body_for(&"ankle_l")
	var start_foot := lead.global_position
	var start_other := other.global_position
	home = torso.global_position
	rig.kick_at(Vector3.RIGHT*5.4,torso.global_position,&"torso")
	await physics_frame
	check(rig.balance.stepping_foot==1,"a rightward torso impact on solid ground selects the right support foot")
	var peak := 0.0
	var foot_peak := 0.0
	var opposite := 0.0
	var elevation := 0.0
	for i in 75:
		await physics_frame
		peak = maxf(peak,torso.global_position.distance_to(home))
		foot_peak = maxf(foot_peak,lead.global_position.x-start_foot.x)
		opposite = maxf(opposite,other.global_position.x-start_other.x)
		elevation = maxf(elevation,lead.global_position.y-start_foot.y)
	print("Survivor physical excursion (mm): hand-hit trunk %.1f, torso-hit trunk %.1f, catching/support foot %.1f/%.1f, lift %.1f" % [wrist_peak*1000,peak*1000,foot_peak*1000,opposite*1000,elevation*1000])
	check(peak>wrist_peak*1.3 and foot_peak>opposite+0.015 and elevation>0.012,"the torso hit shifts the real trunk and raises the catching foot while its partner bears weight")
	check(rig.balance.stepping_foot<0 and torso.global_position.distance_to(home)<0.025 and lead.global_position.distance_to(start_foot)<0.03,"motors return to the standing pose after the recovery step")
	rig.kick_at(Vector3.LEFT*5.4,torso.global_position,&"torso")
	await physics_frame
	check(rig.balance.stepping_foot==0,"reversing the impact selects the opposite foot")
	for i in 52:
		await physics_frame
		avatar.global_position.z -= 0.030
	check(absf(hip.global_position.z-avatar.global_position.z)<0.25 and rig.driving,"forward control still advances the articulated hips during a lateral stumble")
	await _ticks(18)
	var ball := RigidBody3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	var collision := CollisionShape3D.new()
	collision.shape = sphere
	ball.add_child(collision)
	ball.mass = 24.0
	ball.gravity_scale = 0.0
	ball.collision_mask = rig.CONTACT_LAYER
	s.add_child(ball)
	ball.global_position = torso.global_position+Vector3.LEFT*1.35
	ball.linear_velocity = Vector3.RIGHT*8.5
	var collision_strain := 0.0
	var collision_excursion := 0.0
	home = torso.global_position
	for i in 24:
		await physics_frame
		collision_strain = maxf(collision_strain,rig.balance.strain)
		collision_excursion = maxf(collision_excursion,torso.global_position.distance_to(home))
	ball.queue_free()
	print("Moving-body collision strain %.2f; physical torso excursion %.1f mm" % [collision_strain,collision_excursion*1000])
	check(collision_strain>0.12 and collision_excursion>0.008,"a real moving rigid body triggers collision recovery without a scripted hit")
	await _ticks(90)
	check(rig.balance.strain==0 and rig.balance.stepping_foot<0,"collision response settles after the obstacle moves away")
	rig.balance.support_enabled = false
	rig.kick_at(Vector3.RIGHT*6,torso.global_position,&"torso")
	check(rig.balance.strain>0 and rig.balance.stepping_foot==-1,"swimming or airborne motion keeps localized yielding and disables ground steps")
	avatar.global_position = at+Vector3(12.8,0.02,0)
	rig.balance.support_enabled = true
	await _ticks(40)
	rig.kick_at(Vector3.RIGHT*6,torso.global_position,&"torso")
	await physics_frame
	check(rig.balance.stepping_foot==0,"near a ledge the rig catches with a foot that has ground at its landing position")
	rig.let_go()
	check(not rig.driving and rig.balance.strain==0,"a released ragdoll relinquishes its active recovery")
	avatar.queue_free()
	await _ticks(2)

func _verify_creature(kind: String, injury := 0) -> void:
	var actor := spawn(kind,{"wardrobe_index":0,"limb_index":injury,"facing":0.0,"stride_phase":0.0,"fsm":WastelandCreatureBrain.State.CHASE})
	actor.global_position = at+Vector3.UP*0.025
	for i in 3:
		await physics_frame
		actor.velocity = Vector3.DOWN*2.5
		actor.move_and_slide()
	actor.velocity = Vector3.ZERO
	actor._pose(0.05,4.0,0.0)
	var rig := actor.active_motion
	if not rig:
		check(false,kind+" starts live articulated motion")
		s.hordes.release(actor)
		return
	await _ticks(28)
	var part := rig.body_for(&"torso")
	var home := part.global_position
	rig.kick_at(Vector3(4.4,0,-2.2),part.global_position,&"torso")
	await physics_frame
	var foot := rig.balance.stepping_foot
	var support := ""
	var step_body: RigidBody3D
	var foot_start := Vector3.ZERO
	if foot>=0:
		step_body = rig._parts[rig.balance._feet[foot]].body
		support = str(step_body.name)
		foot_start = step_body.global_position
	var peak := 0.0
	var target_peak := 0.0
	var foot_peak := 0.0
	for i in 75:
		await physics_frame
		peak = maxf(peak,part.global_position.distance_to(home))
		target_peak = maxf(target_peak,rig.balance.step_offset(foot).length())
		if step_body: foot_peak = maxf(foot_peak,step_body.global_position.distance_to(foot_start))
	print(kind,"/",injury," support=",support," physical torso/foot (mm)=",snappedf(peak*1000,0.1),"/",snappedf(foot_peak*1000,0.1))
	var expected := ["Body_paw3","Body_paw2","Body_paw1","Body_paw0"] if kind in WastelandHordes.WILDLIFE else ["Body_hand_l","Body_hand_r"] if kind=="crawler" or actor.low_crawl() else ["Body_ankle_l","Body_ankle_r"]
	check(expected.has(support) and peak>0.008 and target_peak>0.012 and foot_peak>0.005,"actual "+kind+" rig braces using its surviving standing, crawling or four-foot anatomy")
	check(rig.balance.strain==0 and rig.balance.stepping_foot<0 and rig.driving,kind+" remains controlled and recovers from the impulse")
	s.hordes.release(actor)
	await _ticks(2)

func _verify_water() -> void:
	for species: String in ["pond_turtle","crayfish","heron","lake_fish"]:
		var model: Node3D
		var bones: Skeleton3D
		if species=="lake_fish":
			model = preload("res://game/art/lake_fish_rig.gd").new()
			bones = model.build_physical("",0,0.0,0.0)
		elif species=="heron":
			model = preload("res://game/art/heron_rig.gd").new()
			model.build(false,0)
		else:
			model = WastelandBenthicAnimal.new()
			model.build(species,"",0)
		s.add_child(model)
		model.global_position = at+Vector3.UP*2.8
		var rig := Motion.start(model,bones if bones!=null else model.bones,null)
		var core: RigidBody3D = rig._parts[0].body
		rig.kick_at(Vector3.RIGHT*5,core.global_position,core.name.trim_prefix("Body_"))
		await _ticks(10)
		check(rig.balance.stepping_foot<0 and rig.balance.lean.length()>0.002,species+" deflects without placing a foot in midair or water")
		model.queue_free()
		await _ticks(2)
