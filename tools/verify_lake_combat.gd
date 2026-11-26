extends "res://tools/verify_party.gd"

func _start() -> void:
	if "--host" in OS.get_cmdline_user_args() or "--guest" in OS.get_cmdline_user_args():
		super._start()
		return
	WastelandSave.root_override = "user://verification/lake-combat-%d" % OS.get_process_id()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.options = SessionSettings.new()
	game.set_process_input(false)
	var s := _coast()
	s.simulation_paused = true
	var lake := s.stream.lake_wildlife
	var patch := lake.habitats[0]
	_prepare(s,patch)
	s.player.global_position = patch.fishes + Vector3(0,2.5,1.8)
	s.player.camera.look_at(patch.fishes)
	_advance(s,0.1)
	_check(lake.drivers.has(patch.heron_id) and not lake.individual_fish.is_empty(),"nearby wading heron and individual swimming fish use active joint drives")
	var initial_rigs := {}
	for id in patch.fish_ids:
		if lake.drivers.has(id) and not lake.drivers[id].balance.support_enabled:
			initial_rigs[id] = lake.drivers[id].get_instance_id()
	_check(initial_rigs.size()==lake.SCHOOL_SIZE and patch.school.visible and lake.individual_fish[patch.fish_ids[0]].model.visible==false,"six swimming rigs have independent bodies, no ground steps and one school rendering each segment")
	if not lake.individual_fish.is_empty():
		var id: String = lake.individual_fish.keys()[0]
		var drive: Node3D = lake.drivers[id]
		var start: Vector3 = drive.center()
		_check(drive.body_for("PectoralL") != null and drive.body_for("PectoralR") != null and drive.body_for("DorsalRear") != null and drive.body_for("Tail") != null,"individual paired pectorals, dorsal fins and tail have real moving bodies")
		for i in 18:
			_advance(s,1.0/60.0)
			await physics_frame
		_check(drive.center().distance_to(start) > 0.01,"physical fish swims along the moving school route")
	await physics_frame
	var fish_id := _clear_fish(s,patch)
	_check(not fish_id.is_empty(),"a weapon ray acquires a particular member of a school")
	if fish_id.is_empty():
		await _done()
		return
	var point: Vector3 = patch.fish_poses[patch.fish_ids.find(fish_id)].origin
	var swimming_rids := _joint_rids(lake.drivers[fish_id])
	var origin := point + Vector3.UP * 2.0
	var barrier := WastelandLook.solid(s,Vector3(1.0,0.20,1.0),point+Vector3.UP*0.9,Color.BROWN)
	await physics_frame
	await physics_frame
	var blocked := s.weapon_hit(origin,point,[])
	_check(blocked.get("collider") == barrier and not blocked.has("aquatic"),"world collision shields a nearby fish from the weapon ray")
	_bullet(s,origin,point)
	_check(not lake.combat_snapshot().has(fish_id),"firing into cover leaves the fish untouched")
	barrier.queue_free()
	await physics_frame
	await physics_frame
	_bullet(s,origin,point)
	_advance(s,0.10)
	var records := lake.combat_snapshot()
	var dead: bool = records.has(fish_id) and records[fish_id].hp <= 0 and lake.combat.bodies.has(fish_id)
	_check(dead,"an unobstructed projectile creates a physical fish corpse (%s, damaged %s, bodies %s)" % [fish_id,records.keys(),lake.combat.bodies.keys()])
	_check(dead and _joint_rids(lake.combat.bodies[fish_id].rig)==swimming_rids,"the seven swimming body RIDs become the dead fish's same seven bodies")
	_check(records.size() == 1 and _visible_fish(patch) == lake.SCHOOL_SIZE-1,"five other members of the same school continue swimming")
	var eye := patch.fish_center + Vector3.UP*2.0
	_check(lake.observation(eye,Vector3.DOWN,3.0).get("type") == "lake_fish","the remaining school can still be observed")
	if dead:
		_check(s.save_now(false) == OK and WastelandSave.read(1).get("lake_combat",{}).has(fish_id),"world save includes the dead individual's identity")
		lake.restore_combat({})
		lake.restore_combat(records)
		_advance(s,0.016)
		_check(lake.combat.bodies.has(fish_id) and not lake.drivers.has(fish_id) and lake.combat_snapshot()[fish_id].pose.size()==records[fish_id].pose.size(),"a saved or incoming pose recreates the missing fish corpse before its live route exists")
		var remaining: float = records[fish_id].until-s.clock.elapsed
		_advance(s,remaining-0.25)
		_check(lake.combat.bodies.has(fish_id),"fish remains visible shortly before its 20 seconds elapse")
		_advance(s,0.35)
		_check(not lake.combat.bodies.has(fish_id) and _visible_fish(patch)==lake.SCHOOL_SIZE-1 and lake.combat_snapshot()[fish_id].hp <= 0,"expired remains disappear without reviving the missing fish")
		var saved := lake.combat_snapshot()
		lake.restore_combat({})
		lake.restore_combat(saved)
		s.clock.hours += 24.1
		_advance(s,0.1)
		_check(lake.combat.absent(fish_id),"observed habitat stays empty across a save and a full world day")
		s.player.global_position += Vector3.RIGHT * 150.0
		_advance(s,0.1)
		var continuous := 0
		for id: String in initial_rigs:
			if id!=fish_id and lake.drivers.has(id) and lake.drivers[id].get_instance_id()==initial_rigs[id]: continuous+=1
		_check(not lake.combat_snapshot().has(fish_id) and lake.drivers.has(fish_id) and continuous==5,"offscreen replenishment restores the sixth fish while the five survivors keep their same bodies 150 metres away")
	_prepare(s,patch)
	var survivor := _clear_fish(s,patch)
	var fish_recovered := false
	if survivor!="":
		var fish_rig: Node3D = lake.drivers[survivor]
		var rids := _joint_rids(fish_rig)
		var target: Vector3 = patch.fish_poses[patch.fish_ids.find(survivor)].origin
		var hit := s.weapon_hit(target+Vector3.UP*2.0,target,[])
		lake.strike(hit,1.0,target+Vector3.UP)
		var same_fish: bool = lake.combat.bodies.has(survivor) and _joint_rids(lake.combat.bodies[survivor].rig)==rids
		_advance(s,1.2)
		fish_recovered = same_fish and lake.drivers.get(survivor)==fish_rig and _joint_rids(fish_rig)==rids and fish_rig.pose_applied.get_connections().size()==1
	_check(fish_recovered,"a wounded fish resumes the school batch once with the same seven physics bodies")
	var seen := {}
	for specimen in lake.bottom_life:
		if seen.has(specimen.species): continue
		s.player.global_position=specimen.anchor + Vector3.UP*2.5
		s.stream.ensure_landing(specimen.anchor)
		_advance(s,0.1)
		var label := "Shell" if specimen.species == "pond_turtle" else "Carapace"
		var target := _joint(specimen,label) + Vector3.UP*0.06
		var id: String = specimen.get_meta("lake_id")
		var distal := "PaddleR1" if specimen.species == "pond_turtle" else "PincerL"
		var driving: Node3D = lake.drivers.get(id)
		var before_fall := _joint_rids(driving)
		_check(driving != null and driving.body_for(distal) != null and driving.find_children("*","RigidBody3D",false,false).size() == specimen.bones.get_bone_count(),"every visible joint follows active physics, including " + distal)
		if driving != null:
			var turtle := specimen.species=="pond_turtle"
			_check(driving.balance.support_enabled!=turtle and specimen.travel_speed>0.0 and (turtle or specimen.basis.y.dot(s.stream.ground_normal_at(specimen.position))>0.96),"live "+specimen.species+" stroke follows travel with swimming or lakebed support")
		var probe := s.weapon_hit(target+Vector3.UP*0.65,target,[])
		_check(probe.get("aquatic") == id,"weapon ray picks the articulated " + specimen.species)
		if probe.get("aquatic") == id:
			s.projectile_hit("bullet",1.0,probe,s.player,target + Vector3.UP)
			_check(lake.combat.bodies.has(id) and lake.combat_snapshot()[id].hp > 0,specimen.species + " survives a hit in a physical knockdown")
			var same_fallen: bool = lake.combat.bodies.has(id) and _joint_rids(lake.combat.bodies[id].rig)==before_fall
			_advance(s,2.0)
			_check(not lake.combat.bodies.has(id) and not lake.combat.absent(id),specimen.species + " returns to its route after recovering")
			_check(same_fallen and lake.drivers.has(id) and lake.drivers[id]==driving and _joint_rids(lake.drivers[id])==before_fall,specimen.species+" keeps every physics body RID from walking or swimming through knockdown and recovery")
		seen[specimen.species] = true
	_check(seen.has_all(["pond_turtle","crayfish"]),"both bottom-dwelling species exercised")
	_prepare(s,patch)
	await _natural_flight(s,patch)
	var bird := _joint(patch.upper,"Breast")
	s.player.camera.global_position = bird+Vector3.UP*1.2
	s.player.camera.look_at(bird,Vector3.FORWARD)
	var confirms := s.player.confirmed_hit
	var heron_rids := _joint_rids(lake.drivers[patch.heron_id])
	s._melee({},1.0)
	_check(s.player.confirmed_hit == confirms+1 and lake.combat_snapshot().has(patch.heron_id),"an actual bare-handed swing hits the heron and confirms to the attacker")
	var same_bird: bool = lake.combat.bodies.has(patch.heron_id) and _joint_rids(lake.combat.bodies[patch.heron_id].rig)==heron_rids
	_advance(s,1.2)
	_check(same_bird and lake.drivers.has(patch.heron_id) and _joint_rids(lake.drivers[patch.heron_id])==heron_rids,"the landed heron resumes its route with its original physics bodies")
	s.stream.refresh(patch.fishes+Vector3.RIGHT*600.0,1)
	_advance(s,0.1)
	_check(patch.fish_ids.all(func(id): return not lake.drivers.has(id) and not lake.individual_fish.has(id)),"unloading physical terrain releases the whole school's bodies")
	await _done()

func _natural_flight(s: WastelandSession,patch: WastelandLakeWildlife.Habitat) -> void:
	var lake := s.stream.lake_wildlife
	for perch in patch.perches: s.stream.ensure_landing(perch)
	s.player.global_position = patch.perches[0]+Vector3.UP*13.0
	_advance(s,lake.FLIGHT_TIME+1.1)
	s.player.global_position = patch.bird.position+Vector3.UP*1.0
	_advance(s,1.0/60.0)
	var departure := patch.took_off
	s.player.global_position = patch.perches[0]+Vector3.UP*13.0
	var drive: Node3D = lake.drivers.get(patch.heron_id)
	var no_air_steps := drive!=null and is_equal_approx(departure,s.clock.elapsed)
	var tucked := 2.0
	var extended := 0.0
	var springs := 0.0
	var peak_bank := 0.0
	var forward_sum := 0.0
	var samples := 0
	for i in 255:
		var old := patch.fish_poses[0].origin
		_advance(s,1.0/60.0)
		await physics_frame
		var elapsed := s.clock.elapsed-departure
		if drive!=null:
			if elapsed>0.22 and elapsed<lake.FLIGHT_TIME:
				no_air_steps = no_air_steps and not drive.balance.support_enabled and drive.balance.stepping_foot<0
			var length_y := _joint(patch.upper,"ThighL").y-_joint(patch.upper,"FootL").y
			if elapsed>1.1 and elapsed<2.0: tucked = minf(tucked,length_y)
			if elapsed>3.10 and elapsed<3.5: extended = maxf(extended,length_y)
			if elapsed>3.60 and elapsed<3.92:
				springs = maxf(springs,patch.upper.HIP.y-patch.upper.bones.get_bone_pose_position(patch.upper.bone_ids.Breast).y)
		var pose := patch.fish_poses[0]
		if i>30 and old.is_finite() and pose.origin.is_finite() and old.distance_to(pose.origin)>0.001:
			peak_bank = maxf(peak_bank,absf(pose.basis.orthonormalized().get_euler().z))
			forward_sum += (-pose.basis.z.normalized()).dot(old.direction_to(pose.origin))
			samples+=1
	_check(no_air_steps and drive.balance.support_enabled and not lake.combat_snapshot().has(patch.heron_id),"lake heron flies and lands on the same active rig without ground steps in flight or a fall injury")
	_check(extended>tucked+0.20 and springs>0.04,"live heron retracts and extends legs before contact and absorbs touchdown (%.2f/%.2f m leg height, %.2f m breast drop)"%[tucked,extended,springs])
	_check(samples>45 and forward_sum/maxi(1,samples)>0.90 and peak_bank>0.012,"school banks and faces its measured world displacement across a real lake route")

func _coast() -> WastelandSession:
	var cfg: Dictionary = game._default_config()
	cfg.terrain_revision = 2
	game._enter_world(cfg,{},1,false)
	var s: WastelandSession = game.session
	s.hordes.next_patrol = INF
	s.hordes.next_herd = INF
	return s

func _prepare(s: WastelandSession, patch: WastelandLakeWildlife.Habitat) -> void:
	s.player.global_position = patch.perches[0]+Vector3.BACK*8.0+Vector3.UP*0.1
	s.player.global_position.y = s.stream.ground_at(s.player.global_position)+0.1
	s.stream.ensure_landing(patch.fishes)
	# The school can swim across a chunk boundary even while its habitat centre stays put.
	for offset: Vector3 in [Vector3(4,0,4),Vector3(4,0,-4),Vector3(-4,0,4),Vector3(-4,0,-4)]:
		s.stream.ensure_landing(patch.fishes+offset)
	_advance(s,0.1)

func _advance(s: WastelandSession, step: float) -> void:
	s.clock.elapsed += step
	s.stream.lake_wildlife.countdown = 0
	s.stream.lake_wildlife._process(step)

func _joint(model: Node3D, label: String) -> Vector3:
	return model.bones.global_transform * model.bones.get_bone_global_pose(model.bone_ids[label]).origin

func _joint_rids(rig: Node3D) -> Array[RID]:
	var result: Array[RID] = []
	if rig != null:
		for part in rig.get_children():
			if part is RigidBody3D: result.append(part.get_rid())
	return result

func _clear_fish(s: WastelandSession, patch: WastelandLakeWildlife.Habitat) -> String:
	for i in patch.fish_ids.size():
		var point := patch.fish_poses[i].origin
		if point.is_finite() and s.weapon_hit(point+Vector3.UP*2,point,[]).get("aquatic") == patch.fish_ids[i]:
			return patch.fish_ids[i]
	return ""

func _visible_fish(patch: WastelandLakeWildlife.Habitat) -> int:
	return patch.fish_poses.filter(func(pose: Transform3D): return pose.origin.is_finite()).size()

func _bullet(s: WastelandSession, origin: Vector3, target: Vector3) -> void:
	s.fx.projectile(origin,origin.direction_to(target)*100.0,s.player,"bullet",150.0)
	s.fx.simulate_projectiles(0.025)

func _host() -> void:
	var s := _coast()
	var lake := s.stream.lake_wildlife
	var patch := lake.habitats[0]
	_prepare(s,patch)
	_check(game.network.listen(port) == OK,"lake host listens")
	game.network.multiplayer.peer_connected.connect(func(_id):
		_advance(s,0.05)
		var id := _clear_fish(s,patch)
		if not id.is_empty():
			var point: Vector3 = patch.fish_poses[patch.fish_ids.find(id)].origin
			_bullet(s,point+Vector3.UP*2,point)
		_check(not id.is_empty() and lake.combat.bodies.has(id),"host kills a single fish before guest bootstrap")
	,CONNECT_ONE_SHOT)
	if await _until(func(): return _marked(s,"看见湖鱼"),25):
		var bird := _joint(patch.upper,"Breast")
		_bullet(s,bird+Vector3.UP*2,bird)
		_check(lake.combat.bodies.has(patch.heron_id),"host projectile fells the living heron")
		_check(await _until(func(): return _marked(s,"看见灰鹭"),10),"guest acknowledges the replicated physical bird")
	else:
		_check(false,"guest observes existing fish corpse")
	await _until(func(): return game.network.joined_members().is_empty(),5)
	await _done()

func _client() -> void:
	_check(game.network.connect_to("127.0.0.1",port) == OK,"lake guest connects")
	if await _until(func(): return is_instance_valid(game.session) and game.session.replica,25):
		var s: WastelandSession = game.session
		var lake := s.stream.lake_wildlife
		var patch := lake.habitats[0]
		var saw_fish := await _until(func(): return patch.fish_ids.any(func(id): return lake.combat.bodies.has(id)) and _visible_fish(patch) == lake.SCHOOL_SIZE-1,5)
		_check(saw_fish,"late join sees the same dead fish and its five living schoolmates")
		s.ui_command("marker",[Vector2.ZERO,"看见湖鱼"])
		var saw_bird := await _until(func(): return lake.combat.bodies.has(patch.heron_id) and not patch.bird.visible,8)
		_check(saw_bird,"reliable live update replaces the guest's animated bird with its corpse")
		s.ui_command("marker",[Vector2.ZERO,"看见灰鹭"])
		await _until(func(): return _marked(s,"看见灰鹭"),3)
	else:
		_check(false,"guest receives lake world")
	await _done()

func _marked(s: WastelandSession, text: String) -> bool:
	return s.marker_records.any(func(row): return row.name == text)
