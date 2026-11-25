extends SceneTree

var errors:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool, detail:String)->void:
	print("PASS " if ok else "FAIL ",detail)
	if not ok: errors+=1

func run()->void:
	WastelandSave.root_override="user://verification/weapon-zones-%d"%OS.get_process_id()
	var app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	app._enter_world(app._default_config(),{},0,false)
	var s:WastelandSession=app.session
	s.simulation_paused=true
	var at:=s.player.position+Vector3(0,10,-4)
	s.hordes._spawn("walker",at,false,{"limbs":Vector4i.ZERO})
	var actor:WastelandCreature=s.hordes.alive.back()
	await physics_frame
	await physics_frame
	var tested:={}
	for node in actor.get_children():
		if not node is Area3D or not node.has_meta("hit_zone"): continue
		var zone:String=node.get_meta("hit_zone")
		if tested.has(zone): continue
		var shape:=node.find_children("*","CollisionShape3D",true,false)[0] as CollisionShape3D
		var to:=shape.global_position
		var from:=to+Vector3.BACK*3
		var excluded:Array[RID]=[s.player.get_rid()]
		var hit:=s.weapon_hit(from,to,excluded)
		check(hit.get("collider")==node,"weapon ray resolves "+zone+" ahead of movement capsule")
		if hit.get("collider")!=node: continue
		var before:=actor.hp
		s.projectile_hit("bullet",4.0,hit,s.player,from)
		var factor:float={"head":2.0,"torso":1.0,"legs":0.8}[zone]
		check(is_equal_approx(before-actor.hp,4*factor),"projectile applies "+zone+" multiplier")
		check(s.player.confirmed_head==(zone=="head"),"shooter receives matching confirmation")
		tested[zone]=true
	check(tested.size()==3,"three independently hittable regions")
	check(actor.hand_impact_damage("torso",at) == 0,"ordinary infected expose their torso to a punch")
	await check_hard_cover(s,at+Vector3.RIGHT*5)
	var wall:=StaticBody3D.new()
	wall.collision_layer=2
	s.add_child(wall)
	wall.global_position=at+Vector3(0,0.8,1.0)
	WastelandLook.collider(wall,Vector3(2,3,0.3),Vector3.ZERO)
	await physics_frame
	await physics_frame
	var omitted:Array[RID]=[]
	var wall_hit:=s.weapon_hit(at+Vector3(0,0.9,3.0),at+Vector3.UP*0.9,omitted)
	check(wall_hit.get("collider")==wall,"solid cover intercepts shot before the infected")
	var player:=s.player
	player.global_position=wall.global_position+Vector3.BACK*1.2-Vector3.UP*player.eyes.position.y
	player.camera.look_at(wall.global_position)
	var stamina:=player.stamina
	s._melee(s.catalog.items.club,1.0)
	var light:=stamina-player.stamina
	stamina=player.stamina
	s._melee(s.catalog.items.club,2.14)
	check(is_equal_approx(stamina-player.stamina,light*2.2),"heavy real club swing consumes 2.2 times light stamina")
	check(is_equal_approx(player.hit_stop,0.045) and player.impact_kick>0,"melee contact applies 45ms stop and a local camera impulse")
	var phase:=player.hand.pose_time
	player.hand.animate(0.040,0.0,0.0,1.0,0.045)
	check(player.hand.pose_time==phase,"viewmodel really freezes through the hit-stop window")
	player.velocity=Vector3.ZERO
	player.crouch=1
	var rested:=player.shot_spread()
	player.velocity=Vector3.RIGHT*7.3
	player.crouch=0
	check(player.shot_spread()>rested,"movement and crouching change the spread used for real projectiles")
	var pitch:=player.pitch
	s.bag.add("pistol",1)
	s.bag.magazine.pistol=2
	s._shoot("pistol",s.catalog.items.pistol)
	check(player.pitch>pitch and player.hand.flash>0 and s.bag.magazine.pistol==1,"pistol recoils up, flashes its muzzle and spends the matching loaded round")
	check(player.heard_radius()==35.0 and s.hordes.sounds.back().radius==35.0,"HUD and infected hear the same actual gunshot radius")
	for id:String in ["step_grass","step_leaves","step_stone","step_wood","splash","hammer","search","growl","scream","alarm"]:
		check(s.audio.samples.has(id),"loaded spatial sample "+id)
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	print("WEAPON ZONE FAILURES ",errors)
	quit(int(errors>0))

func check_hard_cover(session: WastelandSession, at: Vector3) -> void:
	session.hordes._spawn("walker",at,false,{"morph":"armored","limb_index":0})
	var plated: WastelandCreature = session.hordes.alive.back()
	check(plated.hand_impact_damage("torso",at) == 4 and plated.hand_impact_damage("head",at) == 0 and plated.hand_impact_damage("legs",at) == 0,
		"mutation plates protect the torso and arms while exposing the head and legs")
	await physics_frame
	await physics_frame
	check_punch(session,plated,"torso",Vector3.BACK,4.0,"punching the plated torso costs four health")
	check_punch(session,plated,"head",Vector3.BACK,0.0,"punching the exposed head spares the hand")
	session.hordes.release(plated)
	check(plated.hand_impact_damage("torso",at) == 0,"inactive plated infected cannot bruise a fist")
	for limb_index: int in [0,2,8]:
		session.hordes._spawn("bulwark",at,false,{"facing":0.0,"limb_index":limb_index})
		var guard: WastelandCreature = session.hordes.alive.back()
		var front := at + Vector3.FORWARD
		var pieces := int(guard.limb_damage.x < 2) + int(guard.limb_damage.y < 2)
		check(guard.hand_impact_damage("torso",front) == (4 if pieces > 0 else 0) and guard.hand_impact_damage("torso",at + Vector3.BACK) == 0,
			"bulwark guards only its front with %d remaining plates" % pieces)
		await physics_frame
		await physics_frame
		check_punch(session,guard,"torso",Vector3.FORWARD,4.0 if pieces > 0 else 0.0,
			"frontal punch meets %d remaining shield plates" % pieces)
		check_punch(session,guard,"torso",Vector3.BACK,0.0,"a punch from behind clears the shield")
		var before := guard.hp
		guard.take_hit(10.0,front)
		check(is_equal_approx(before - guard.hp,10.0 * (1.0 - 0.35 * pieces)),
			"light weapon damage still accounts for %d shield plates" % pieces)
		before = guard.hp
		guard.take_hit(10.0,front,true)
		check(is_equal_approx(before - guard.hp,10.0 * (1.0 - 0.16 * pieces)),
			"heavy weapon damage still accounts for %d shield plates" % pieces)
		guard.brain.action = WastelandCreatureBrain.Action.MELEE
		check(guard.hand_impact_damage("torso",front) == 0,"the bulwark opens its shield during windup")
		guard.brain.action = WastelandCreatureBrain.Action.NONE
		guard.attack = 0.3
		check(guard.hand_impact_damage("torso",front) == 0,"the bulwark opens its shield during a strike")
		session.hordes.release(guard)

func check_punch(session: WastelandSession, actor: WastelandCreature, zone: String, side: Vector3, injury: float, detail: String) -> void:
	var player := session.player
	var camera := player.camera
	var old_location := player.global_position
	var old_pose := camera.transform
	var area: Area3D = actor.hurtboxes.areas[zone]
	var target := (area.get_child(0) as CollisionShape3D).global_position
	player.global_position = actor.global_position + side * 1.5
	camera.global_position = target + side * 1.5
	camera.look_at(target)
	var health := player.health
	var enemy_hp := actor.hp
	session._melee({},1.0)
	check(actor.hp < enemy_hp and is_equal_approx(health - player.health,injury),detail)
	player.global_position = old_location
	camera.transform = old_pose
