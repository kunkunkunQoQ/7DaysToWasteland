extends "res://tools/verify_party.gd"

func _host() -> void:
	var settings: Dictionary = game._default_config()
	settings.terrain_revision = 2
	game._enter_world(settings,{},1,false)
	var session: WastelandSession = game.session
	session.hordes.next_patrol = 1000
	session.hordes.next_herd = 1000
	_check(game.network.listen(port)==OK,"infected test host opens")
	game.network.multiplayer.peer_connected.connect(func(_peer):
		# Create both hazards before identification sends the initial world state.
		var distant := session.player.global_position + Vector3.RIGHT*13
		session.hordes._spawn("bloater",distant,false)
		session.hordes.alive.back().take_hit(999,distant)
		session.fx.infected_effect("residue",distant+Vector3.UP*0.03)
		var ground := _landing_point(session)
		session.fx.projectile(ground+Vector3.UP*4.4,Vector3(0.06,1.4,0.04),null,"acid",16)
		session.fx.simulate_projectiles(0.08)
	,CONNECT_ONE_SHOT)
	if not await _until(func(): return not game.network.joined_members().is_empty(),30):
		_check(false,"guest joins")
		_done()
		return
	var prior_shot: Dictionary = session.fx.acid_flights().front()
	game.network.mirror_acid(prior_shot)
	var reaches_ground := func():
		return _impact_patches(session,prior_shot.origin)==1
	_check(await _until(reaches_ground,3),"host resolves pre-join airborne shot into one ground patch")
	_check(await _until(func(): return session.marker_records.any(func(row): return row.name=="late shot landed"),15),"guest finishes inspecting the two bootstrap effects")
	var guest: WastelandSurvivor = game.network.joined_members()[0].survivor
	var at := guest.global_position
	var before := guest.health
	session.hordes._spawn("bloater",at+Vector3.RIGHT*0.7,false)
	var corpse: WastelandCreature = session.hordes.alive.back()
	corpse.take_hit(999,at)
	_check(await _until(func(): return session.hordes.corpses.has(corpse) and guest.health < before-12,5),"host resolves delayed blast against remote survivor and keeps its physical remains")
	_check(await _until(func(): return session.marker_records.any(func(row): return row.name=="rupture visible"),15),"guest is ready to observe a new projectile")
	at = guest.global_position
	var launch := Vector3(2,3,-3)
	session.fx.projectile(_landing_point(session)+Vector3.UP*4.4,launch,null,"acid",16)
	_check(await _until(func(): return session.marker_records.any(func(row): return row.name=="acid visible"),10),"guest observes the live acid flight before ground damage")
	before = guest.health
	session.hordes.infected_effect("residue",at+Vector3.UP*0.07)
	_check(await _until(func(): return guest.health < before-2,3),"host simulates ground acid on remote survivor")
	_check(await _until(func(): return session.marker_records.any(func(row): return row.name=="residue confirmed"),10),"guest confirms the final damage before the room closes")
	await _until(func(): return game.network.joined_members().is_empty(),10)
	_done()

func _client() -> void:
	_check(game.network.connect_to("127.0.0.1",port)==OK,"guest connects")
	if not await _until(func(): return is_instance_valid(game.session) and game.session.replica,30):
		_check(false,"guest receives infected test world")
		_done()
		return
	var session: WastelandSession = game.session
	_check(not session.fx.acid_snapshot().is_empty(),"late join restores an existing patch before live effects")
	var flights := session.fx.acid_flights()
	_check(flights.size()==1 and flights[0].life < 3.5 and flights[0].at.distance_to(flights[0].origin)>0.01,"late join displays one moving acid shot at its in-flight position")
	var distant_warning := func():
		return game.network.smooth_actors.values().any(func(actor): return actor.type=="bloater" and actor.hp==0 and actor.global_position.distance_to(session.player.global_position)>8 and is_instance_valid(actor.blast_ring) and actor.blast_ring.visible)
	_check(await _until(distant_warning,1.6),"late join receives the ongoing fuse from actor snapshots")
	if not flights.is_empty():
		var landed := func(): return session.fx.acid_flights().is_empty() and _impact_patches(session,flights[0].origin)==1
		_check(await _until(landed,2.5),"late-join shot continues to its single host-authorized impact")
	session.ui_command("marker",[Vector2.ZERO,"late shot landed"])
	var visible_fuse := func():
		return game.network.smooth_actors.values().any(func(actor): return actor.type=="bloater" and actor.hp==0 and actor.global_position.distance_to(session.player.global_position)<4 and is_instance_valid(actor.blast_ring) and actor.blast_ring.visible)
	_check(await _until(visible_fuse,6),"guest sees primed corpse and warning ring before damage")
	_check(await _until(func(): return session.player.injury.last_source=="rupture" and session.player.health < session.player.max_health()-12,4),"guest receives authoritative rupture damage and cause")
	var last_shot:=session.fx.acid_serial
	session.ui_command("marker",[Vector2.ZERO,"rupture visible"])
	_check(await _until(func(): return session.fx.acid_flights().any(func(shot): return int(shot.id)>last_shot),10),"guest sees the newly mirrored flying poison")
	session.ui_command("marker",[Vector2.ZERO,"acid visible"])
	_check(await _until(func(): return not session.fx.acid_snapshot().is_empty(),3),"guest sees authoritative acid patch")
	_check(await _until(func(): return session.player.injury.last_source=="residue",3),"guest receives ground burn from host")
	session.ui_command("marker",[Vector2.ZERO,"residue confirmed"])
	_check(await _until(func(): return is_instance_valid(session) and session.marker_records.any(func(row): return row.name=="residue confirmed"),5),"guest acknowledges the finished run before disconnecting")
	_done()

func _landing_point(session: WastelandSession) -> Vector3:
	for offset: Vector3 in [Vector3.FORWARD*5,Vector3.LEFT*5,Vector3.BACK*5,Vector3.RIGHT*5]:
		var at := session.player.global_position + offset
		var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*5,at-Vector3.UP*12,3)
		var floor_hit := session.get_world_3d().direct_space_state.intersect_ray(ray)
		if not floor_hit.is_empty() and floor_hit.normal.y>0.7: return floor_hit.position
	return session.player.global_position+Vector3.FORWARD*5

func _impact_patches(session: WastelandSession, origin: Vector3) -> int:
	var count := 0
	for patch in session.fx.acid_snapshot():
		var delta: Vector3 = patch.at-origin
		if delta.y < -2 and Vector2(delta.x,delta.z).length()<0.7: count+=1
	return count
