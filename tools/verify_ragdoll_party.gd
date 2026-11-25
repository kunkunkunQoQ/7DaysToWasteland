extends "res://tools/verify_party.gd"

func _host() -> void:
	var config: Dictionary = game._default_config()
	config.terrain_revision = 2
	game._enter_world(config,{},1,false)
	var s: WastelandSession = game.session
	s.hordes.next_patrol = 1000.0
	s.hordes.next_herd = 1000.0
	_check(game.network.listen(port) == OK,"ragdoll host opens")
	game.network.multiplayer.peer_connected.connect(func(_id):
		s.player.damage(200,"heavy",s.player.position + Vector3.FORWARD)
		s.respawn()
		game.close_overlay()
		var at := s.player.position + Vector3.RIGHT*2.4
		at.y = s.stream.ground_at(at) + 0.15
		s.hordes._spawn("fox",at,false)
		s.hordes.alive.back().take_hit(200,at + Vector3.FORWARD)
	,CONNECT_ONE_SHOT)
	if not await _until(func(): return _marked(s,"看见遗体"),25.0):
		_check(false,"guest finds both retained bodies at join")
		_done()
		return
	var member: WastelandLan.MemberState = game.network.joined_members()[0]
	var guest := member.survivor
	_check(guest.live_avatar == member.avatar and is_instance_valid(member.avatar.active_motion),
		"host drives the visible guest's live body before impact")
	guest.invulnerable = 0.0
	guest.damage(24,"heavy",guest.position + Vector3.FORWARD)
	_check(guest.ragdoll_mode == guest.RagdollMode.KNOCKED_DOWN,"host simulates guest knockdown")
	_check(await _until(func(): return _marked(s,"已起身"),12.0),"guest recovers and regains input")
	guest.damage(200,"heavy",guest.position + Vector3.FORWARD)
	var remains := guest.ragdoll_body
	_check(await _until(func(): return not member.downed and guest.health > 0,12.0),"host processes guest respawn")
	_check(is_instance_valid(remains) and remains.remaining > 0 and guest.ragdoll_body == null,"respawn leaves the old body in place")
	if await _until(func(): return _marked(s,"客人复活"),10.0):
		s.player.damage(200,"heavy",s.player.position + Vector3.FORWARD)
		_check(await _until(func(): return _marked(s,"主机倒下"),10.0),"guest still acts while host is on the death screen")
	else:
		_check(false,"guest confirms their own corpse")
	await _until(func(): return game.network.joined_members().is_empty(),6.0)
	_done()

func _client() -> void:
	_check(game.network.connect_to("127.0.0.1",port) == OK,"guest connects")
	if not await _until(func(): return game.session != null and game.session.replica,25.0):
		_check(false,"ragdoll guest joins")
		_done()
		return
	var s: WastelandSession = game.session
	var falls = game.network.party_falls
	var driver_ready := func():
		var avatar: WastelandPartyAvatar = game.network.replica_avatar(WastelandLan.HOST_ID)
		return is_instance_valid(avatar) and is_instance_valid(avatar.active_motion) and is_instance_valid(s.player.live_avatar) and is_instance_valid(s.player.live_avatar.active_motion)
	_check(await _until(driver_ready,5.0),"guest simulates both its own moving body and the host's visible joints")
	_check(await _until(func(): return not falls.bodies.is_empty() and game.network.smooth_actors.values().any(
		func(a): return a.type == "fox" and a.hp <= 0 and a.ragdoll != null),6.0),"late join receives host's detached corpse and dead wildlife")
	_check(not falls.current.has(WastelandLan.HOST_ID),"host's previous corpse is separate from the live avatar")
	s.ui_command("marker",[Vector2.ZERO,"看见遗体"])
	_check(await _until(func(): return s.player.ragdoll_mode == s.player.RagdollMode.KNOCKED_DOWN,8.0),"local guest sees own physical knockdown")
	_check(s.player.hand.visible == false and s.player.camera.top_level,"fallen guest has an unobstructed follow camera")
	_check(await _until(func(): return not s.player.is_knocked_down() and s.player.hand.visible,8.0),"guest returns to first person")
	_check(await _until(_fox_at_rest,7.0),"settled fox uses the host's final joint transforms and a compact roster entry")
	s.ui_command("marker",[Vector2.ZERO,"已起身"])
	_check(await _until(func(): return s.death_screen and is_instance_valid(s.player.ragdoll_body),8.0),"dead guest receives body and death screen")
	var remains := s.player.ragdoll_body
	s.ui_command("revive")
	_check(await _until(func(): return not s.death_screen and not s.player.is_knocked_down(),8.0),"guest respawns from normal revive command")
	_check(is_instance_valid(remains) and remains.remaining > 0.0,"guest can still see previous body after respawn")
	s.ui_command("marker",[Vector2.ZERO,"客人复活"])
	_check(await _until(func(): return falls.current.has(WastelandLan.HOST_ID) and not game.network.replica_avatar(WastelandLan.HOST_ID).visible,8.0),"guest sees host's new death in real time")
	s.ui_command("marker",[Vector2.ZERO,"主机倒下"])
	await _until(func(): return _marked(s,"主机倒下"),6.0)
	_done()

func _marked(s: WastelandSession, label: String) -> bool:
	return s.marker_records.any(func(row): return row.name == label)

func _fox_at_rest() -> bool:
	var net: WastelandLan = game.network
	for row in net.replica_actors:
		var id: int = row[0]
		if row.size() != 1 or not net.smooth_actors.has(id) or not net.resting_creatures.has(id): continue
		var fox: WastelandCreature = net.smooth_actors[id]
		if fox.type != "fox" or fox.ragdoll == null: continue
		var local := fox.ragdoll_pose()
		var host_pose: PackedFloat32Array = net.resting_creatures[id].pose
		if local.size() != host_pose.size() or local.is_empty(): return false
		for i in range(0,local.size(),7):
			if Vector3(local[i]-host_pose[i],local[i+1]-host_pose[i+1],local[i+2]-host_pose[i+2]).length() > 0.01:
				return false
		return true
	return false
