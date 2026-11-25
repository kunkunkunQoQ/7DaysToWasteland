extends RefCounted

const SurvivorBody := preload("res://game/actors/survivor_ragdoll.gd")
const GROUP := &"party_ragdolls"
const RECORD := &"party_fall"

# A survivor may have respawned while their previous body is still in the world.
# Body IDs identify individual falls independently of the current peer roster.
var bodies := {}
var current := {}

static func capture(person: WastelandSurvivor, peer: int, mode: int, impact: Vector3) -> Dictionary:
	if mode == 0:
		return {"peer": peer, "mode": 0}
	var body = person.ragdoll_body
	if not is_instance_valid(body):
		return {}
	var row: Dictionary = body.appearance.duplicate()
	row.merge({"peer":peer,"id":body.get_instance_id(),"mode":mode,"impact":impact})
	body.set_meta(RECORD, row)
	if not body.is_in_group(GROUP):
		body.add_to_group(GROUP)
	return row

static func save_corpses(session: WastelandSession) -> Array:
	var rows := []
	for body in session.get_tree().get_nodes_in_group(GROUP):
		if not session.is_ancestor_of(body) or body.is_queued_for_deletion() or body.remaining <= 0.0:
			continue
		var row: Dictionary = body.get_meta(RECORD).duplicate()
		row.remaining = body.remaining
		row.pose = body.physics.pose_snapshot()
		row.settled = body.physics.is_settled()
		rows.append(row)
	return rows

static func restore_corpses(session: WastelandSession, rows: Array) -> void:
	for row: Dictionary in rows:
		if row.get("remaining",0.0) <= 0.0: continue
		var body = _spawn(session,row)
		if not is_instance_valid(body): continue
		body.become_corpse()
		body.remaining = minf(float(row.remaining),body.CORPSE_SECONDS)
		body.physics.apply_pose(row.pose)
		if not row.get("settled",true): body.physics.kick(Vector3.ZERO)
		var record := row.duplicate()
		record.erase("pose")
		record.id = body.get_instance_id()
		body.set_meta(RECORD,record)
		body.add_to_group(GROUP)

static func _spawn(session: WastelandSession, row: Dictionary, source_avatar: WastelandPartyAvatar = null) -> WastelandSurvivorRagdoll:
	return SurvivorBody.spawn(session,row.at,row.profile,row.gear,row.held,row.offhand,row.loaded,
		row.crouch,row.swim,row.velocity,row.impact,row.get("impact_at",Vector3.INF),row.get("impact_bone",&""),source_avatar)

func snapshot(session: WastelandSession, lan: WastelandLan) -> Array:
	var rows := []
	for body in session.get_tree().get_nodes_in_group(GROUP):
		if not session.is_ancestor_of(body) or body.is_queued_for_deletion():
			continue
		var row: Dictionary = body.get_meta(RECORD).duplicate()
		var peer: int = row.peer
		var member: WastelandLan.MemberState = lan.members.get(peer)
		var owner := lan.owner_player(session) if peer == WastelandLan.HOST_ID else member.survivor if member else null
		row.attached = is_instance_valid(owner) and owner.ragdoll_body == body
		if row.mode == 2:
			row.remaining = body.remaining
			if body.physics.is_settled():
				row.pose = body.physics.pose_snapshot()
		rows.append(row)
	return rows

func apply(session: WastelandSession, local_peer: int, row: Dictionary) -> void:
	var peer: int = row.peer
	var mode: int = row.mode
	var attached: bool = row.get("attached",true)
	if mode == 0:
		if peer == local_peer:
			session.player.sync_ragdoll(0,Vector3.ZERO)
			current.erase(peer)
		else:
			detach(peer)
		return
	var id: int = row.id
	var body = bodies.get(id)
	if attached and peer == local_peer:
		if not is_instance_valid(body) and session.player.ragdoll_mode == 0:
			session.player.global_transform = row.at
			session.player.velocity = row.velocity
		session.player.sync_ragdoll(mode,row.impact,row)
		body = session.player.ragdoll_body
	elif not is_instance_valid(body):
		var avatar := session.network.replica_avatar(peer) as WastelandPartyAvatar if attached and is_instance_valid(session.network) else null
		body = _spawn(session,row,avatar)
	elif mode == 2 and body.remaining <= 0.0:
		body.push(row.impact,row.get("impact_at",Vector3.INF),row.get("impact_bone",&""))
	if not is_instance_valid(body):
		return
	if not bodies.has(id):
		bodies[id] = body
		body.tree_exiting.connect(_removed.bind(id,peer),CONNECT_ONE_SHOT)
	if mode == 2:
		body.become_corpse()
		if row.has("remaining"):
			body.remaining = minf(body.remaining,float(row.remaining))
	if attached:
		current[peer] = id
	if row.has("pose"): body.physics.apply_pose(row.pose)

func detach(peer: int) -> void:
	var body = bodies.get(current.get(peer,-1))
	if is_instance_valid(body) and body.remaining <= 0.0:
		body.dismiss()
	current.erase(peer)

func _removed(id: int, peer: int) -> void:
	bodies.erase(id)
	if current.get(peer,-1) == id: current.erase(peer)
