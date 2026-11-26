extends RefCounted

const Rag := preload("res://game/actors/physical_ragdoll.gd")
const ActiveMotion := preload("res://game/actors/active_ragdoll.gd")
const Hits := preload("res://game/actors/ragdoll_hits.gd")
const Heron := preload("res://game/art/heron_rig.gd")
const Fish := preload("res://game/art/lake_fish_rig.gd")
const HEALTH := {"heron": 18.0, "lake_fish": 6.0, "pond_turtle": 26.0, "crayfish": 8.0}
var rows := {}
var bodies := {}
var _joining := {}

func identity(kind: String, home: Vector3, member := 0) -> String:
	return "%s/%d/%d/%d" % [kind, roundi(home.x * 10.0), roundi(home.z * 10.0), member]

func absent(id: String) -> bool:
	return rows.has(id) and (rows[id].hp <= 0.0 or rows[id].until >= 0.0)

func rejoin(id: String, target: Vector3, now: float) -> Vector3:
	if not _joining.has(id): return target
	var amount := smoothstep(0.0, 0.85, now - float(_joining[id].start))
	if amount >= 1.0:
		_joining.erase(id)
		return target
	return Vector3(_joining[id].from).lerp(target, amount)

func weapon_hit(lake: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	if from.is_equal_approx(to): return {}
	var best := {}
	for id: String in bodies:
		if rows[id].hp <= 0.0: continue
		var body: Dictionary = bodies[id]
		if not _near(body.rig.center(), from, to): continue
		_trace(best, from, to, id, rows[id].kind, body.model, body.skeleton, body.model.global_transform)
	for patch in lake.habitats:
		var heron: Node3D = lake.drivers.get(patch.heron_id)
		if heron != null and _near(heron.center(), from, to):
			_trace(best, from, to, patch.heron_id, "heron", patch.upper, patch.upper.bones, patch.upper.global_transform)
		for i in patch.fish_ids.size():
			var pose: Transform3D = patch.fish_poses[i]
			if not pose.origin.is_finite() or absent(patch.fish_ids[i]): continue
			var fish: Node3D = lake.drivers.get(patch.fish_ids[i])
			if fish == null or not _near(fish.center(), from, to, 0.8): continue
			var live: Dictionary = lake.individual_fish[patch.fish_ids[i]]
			_trace(best, from, to, patch.fish_ids[i], "lake_fish", live.model, live.skeleton, pose, patch.beats[i], patch.dart)
	for animal in lake.bottom_life:
		var id: String = animal.get_meta("lake_id")
		var drive: Node3D = lake.drivers.get(id)
		if drive != null and _near(drive.center(), from, to):
			_trace(best, from, to, id, animal.species, animal, animal.bones, animal.global_transform)
	return best

func _near(at: Vector3, from: Vector3, to: Vector3, radius := 2.5) -> bool:
	return at.distance_squared_to(Geometry3D.get_closest_point_to_segment(at, from, to)) < radius * radius

func _trace(best: Dictionary, from: Vector3, to: Vector3, id: String, kind: String, model: Node3D,
		skeleton: Skeleton3D, source: Transform3D, beat := 0.0, effort := 0.0) -> void:
	var nearest := float(best.get("distance", INF))
	var bounds_by_bone := Rag.skeleton_bounds(skeleton)
	for index: int in bounds_by_bone:
		if bounds_by_bone[index] == null: continue
		var bounds: AABB = bounds_by_bone[index]
		var name := skeleton.get_bone_name(index)
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		var radii := (bounds.size * 0.5).max(Vector3.ONE * 0.009)
		pose *= Transform3D(Basis.from_scale(radii), bounds.get_center())
		var inv := pose.affine_inverse()
		var start := inv * from
		var dir := inv * to - start
		var a := dir.length_squared()
		var b := start.dot(dir)
		var c := start.length_squared() - 1.0
		var disc := b * b - a * c
		if disc < 0.0 or a < 0.000001: continue
		var t := 0.0 if c <= 0.0 else (-b - sqrt(disc)) / a
		if t < 0.0 or t > 1.0: continue
		var point := from.lerp(to, t)
		var distance := from.distance_to(point)
		if distance >= nearest: continue
		nearest = distance
		var normal := (inv.basis.transposed() * (start + dir * t)).normalized()
		var hand_damage := 2 if name == &"Shell" else 1 if kind == "crayfish" and not String(name).begins_with("Feeler") else 0
		best.assign({"aquatic":id, "kind":kind, "collider":model, "position":point, "normal":normal, "distance":distance,
			"source":source, "skeleton":skeleton, "beat":beat, "effort":effort, "hand_damage":hand_damage, "bone":name})

func strike(lake: Node3D, hit: Dictionary, damage: float, origin: Vector3, heavy: bool) -> bool:
	if lake.session.replica or damage <= 0.0 or not hit.has("aquatic"): return false
	var id: String = hit.aquatic
	var kind: String = hit.kind
	if not HEALTH.has(kind): return false
	var row: Dictionary = rows.get(id, {})
	if row.is_empty():
		row = {"hp":HEALTH[kind], "kind":kind, "form":"", "face":0, "until":-1.0, "home":hit.source.origin}
		if kind == "heron" or kind == "lake_fish":
			for patch in lake.habitats:
				if id == patch.heron_id:
					row.home = patch.perches[0]
					row.form = "young" if patch.juvenile else ""
					row.face = lake._face_at(patch.perches[0], kind, 0)
					patch.bird.hide()
					break
				var slot: int = patch.fish_ids.find(id)
				if slot >= 0:
					row.home = patch.fishes
					row.form = "local" if patch.mottled else ""
					row.face = patch.face_slots[slot].x
					break
		else:
			row.form = hit.collider.morph
			row.face = hit.collider.face_variant
			row.home = hit.collider.anchor
	if row.hp <= 0.0: return false
	row.hp = maxf(0.0, float(row.hp) - damage)
	row.revision = int(row.get("revision", 0)) + 1
	if row.hp <= 0.0:
		row.return_at = float(lake.session.clock.hours) + 24.0
	row.until = float(lake.session.clock.elapsed) + (Rag.CORPSE_SECONDS if row.hp <= 0.0 else 1.05)
	var dir := (Vector3(hit.position) - origin).normalized()
	row.hit_point = hit.position
	row.hit_bone = hit.bone
	row.impact = dir * (2.5 if heavy else 1.2) + Vector3.UP * 0.28
	rows[id] = row
	if not bodies.has(id):
		row.source = hit.source
		row.beat = hit.beat
		row.effort = hit.effort
		row.erase("pose")
		row.erase("settled")
		_spawn(lake,id,row)
	else:
		bodies[id].rig.kick_at(row.impact, row.hit_point, row.hit_bone)
		bodies[id].final_sent = false
		Hits.enable(bodies[id].rig, row.hp <= 0.0, "lake", id)
	if kind == "lake_fish":
		for patch in lake.habitats:
			var slot: int = patch.fish_ids.find(id)
			if slot >= 0:
				lake._hide_member(patch, slot)
				break
	elif not (bodies.has(id) and hit.collider == bodies[id].model):
		if kind == "heron": hit.collider.get_parent().hide()
		else: hit.collider.hide()
	lake.impact_changed.emit()
	return true

func _spawn(lake: Node3D, id: String, row: Dictionary) -> void:
	var model: Node3D
	match row.kind:
		"heron": model = Heron.new()
		"lake_fish": model = Fish.new()
		_: model = WastelandBenthicAnimal.new()
	lake.add_child(model)
	model.global_transform = row.source
	var skeleton: Skeleton3D
	if row.kind == "lake_fish":
		skeleton = model.build_physical(row.form, row.face, row.beat, row.effort)
	else:
		if row.kind == "heron": model.build(row.form == "young", row.face)
		else: model.build(row.kind, row.form, row.face)
		skeleton = model.bones
	var rig: ActiveMotion = lake.take_driver(id)
	if rig != null:
		rig.rebind_skeleton(skeleton)
	else:
		# A saved or newly replicated body can enter before its living route loads.
		rig = ActiveMotion.start(lake,skeleton,lake.stream)
		if rig == null:
			model.queue_free()
			return
	rig.let_go(row.impact,row.get("hit_point",Vector3.INF),row.get("hit_bone",&""))
	var offset := rig.center() - model.global_position
	bodies[id] = {"model":model, "skeleton":skeleton, "rig":rig, "offset":offset, "final_sent":row.get("settled",false)}
	Hits.enable(rig, row.hp <= 0.0, "lake", id)
	_apply(row, rig)

func _apply(row: Dictionary, rig: Rag) -> void:
	if row.has("pose") and rig.apply_pose(row.pose) and not row.get("settled", false):
		rig.kick(row.get("motion", Vector3.ZERO))

func _save_pose(id: String, row: Dictionary) -> void:
	if bodies.has(id):
		var rig: Rag = bodies[id].rig
		row.pose = rig.pose_snapshot()
		row.settled = rig.is_settled()
		row.motion = rig.motion()

func snapshot() -> Dictionary:
	var result := rows.duplicate(true)
	for id: String in bodies: _save_pose(id, result[id])
	return result

func restore(lake: Node3D, incoming: Dictionary) -> void:
	for id: String in bodies.keys():
		var row: Dictionary = incoming.get(id, {})
		if row.is_empty() or row.get("until", -1.0) < 0.0:
			_remove_body(lake,id,float(lake.session.clock.elapsed),float(row.get("hp",rows[id].hp))>0.0)
		elif row.has("pose") and row.get("revision", 0) != rows.get(id, {}).get("revision", -1):
			_apply(row, bodies[id].rig)
			bodies[id].final_sent = row.get("settled", false)
			Hits.enable(bodies[id].rig, row.hp <= 0.0, "lake", id)
	rows = incoming.duplicate(true)
	lake.countdown = 0.0

func _remove_body(lake: Node3D, id: String, now: float, recover: bool) -> void:
	if not bodies.has(id): return
	var body: Dictionary = bodies[id]
	var resumed := false
	if recover:
		var at: Transform3D = body.model.global_transform
		at.origin = body.rig.center()-Vector3(body.offset)
		_joining[id] = {"from":at.origin,"start":now}
		if lake.stream.at_surface(at.origin):
			resumed = lake.resume_animal(id,rows[id].kind,body.rig,at)
			if resumed: Hits.enable(body.rig,false,"lake",id)
	if not resumed: body.rig.stop_driving()
	body.model.hide()
	body.model.queue_free()
	bodies.erase(id)

func advance(lake: Node3D, now: float, eyes: Array[Vector3]) -> void:
	var changed := false
	var replenished: Array[String] = []
	for id: String in rows:
		var row: Dictionary = rows[id]
		if row.until < 0.0:
			if row.hp <= 0.0 and not lake.session.replica and float(lake.session.clock.hours) >= float(row.return_at):
				var unobserved := true
				for eye in eyes:
					if eye.distance_squared_to(row.home) < 80.0 * 80.0:
						unobserved = false
						break
				if unobserved: replenished.append(id)
			continue
		if now >= float(row.until):
			_remove_body(lake,id,now,row.hp>0.0)
			rows[id] = {"kind":row.kind, "hp":row.hp, "until":-1.0, "form":row.form, "face":row.face,
				"home":row.home, "revision":int(row.revision) + 1, "return_at":row.get("return_at", -1.0)}
			changed = true
			continue
		var point: Vector3 = bodies[id].rig.center() if bodies.has(id) else Vector3(row.source.origin)
		if lake.stream.at_surface(point):
			if not bodies.has(id): _spawn(lake, id, row)
			if bodies.has(id):
				var body: Dictionary = bodies[id]
				if not lake.session.replica and body.final_sent != body.rig.is_settled():
					body.final_sent = body.rig.is_settled()
					row.revision = int(row.revision) + 1
					changed = true
		elif bodies.has(id):
			_save_pose(id, row)
			row.settled = true
			_remove_body(lake,id,now,false)
			if not lake.session.replica:
				row.revision = int(row.revision) + 1
				changed = true
	for id in replenished:
		rows.erase(id)
	if (changed or not replenished.is_empty()) and not lake.session.replica:
		lake.impact_changed.emit()
