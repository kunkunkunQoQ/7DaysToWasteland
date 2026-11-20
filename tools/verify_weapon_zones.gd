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
