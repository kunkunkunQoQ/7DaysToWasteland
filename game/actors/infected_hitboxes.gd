extends RefCounted

const LAYER := 32

var areas: Dictionary = {}
var bindings: Array[Dictionary] = []

func fit(actor: WastelandCreature) -> void:
	for area: Area3D in areas.values():
		area.collision_layer = 0
		actor.remove_child(area)
		area.queue_free()
	areas.clear()
	bindings.clear()
	var animal: bool = actor.spec.get("animal",false)
	var crawl := actor.type == "crawler"
	for zone: String in (["body"] if animal else ["head","torso","legs"]):
		var area := Area3D.new()
		area.name = "Hit_" + zone
		area.set_meta("hit_zone", zone)
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		actor.add_child(area)
		areas[zone] = area
	if animal:
		for joint: String in actor.body_parts:
			_anatomical_box(actor,"body",joint)
		return
	_box(actor, "head", "head", Vector3(0,0.13,-0.034), Vector3(0.32,0.35,0.35))
	_box(actor, "torso", "torso", Vector3(0,0,0.05) if crawl else Vector3(0,0.19,0), Vector3(0.44,0.30,0.57) if crawl else Vector3(0.52,0.47,0.35))
	_box(actor, "torso", "hips", Vector3.ZERO, Vector3(0.36,0.26,0.32))
	for i in 2:
		var suffix := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		var amount := actor.limb_damage[2 + i]
		var thigh := Vector3(side*0.09,-0.28,-0.143) if crawl else Vector3(0,-0.322,-0.021)
		var calf := Vector3(-side*0.019,-0.060,0.349) if crawl else Vector3(0,-0.316,0.017)
		var remaining := (0.52 if crawl else 0.55) if amount == 2 else (0.87 if crawl else 0.95) if amount == 1 else 1.0
		_segment(actor,"legs","leg"+suffix,thigh,0.19,0.19)
		_segment(actor,"legs","knee"+suffix,calf*remaining,0.15,0.15)
		if amount == 0:
			var sole := Vector3(0,-0.013,0) if crawl else Vector3(0,-0.046,-0.060)
			_box(actor,"legs","ankle"+suffix,sole,Vector3(0.12,0.10,0.20) if crawl else Vector3(0.16,0.09,0.25))
		var upper := Vector3(side*0.113,-0.158,0.11) if crawl else Vector3(0,-0.253,-0.01)
		var forearm := Vector3(side*0.014,-0.134,-0.231) if crawl else Vector3(0,-0.229,-0.06)
		_segment(actor,"torso","arm"+suffix,upper,0.17,0.18)
		_segment(actor,"torso","elbow"+suffix,forearm*(0.55 if actor.limb_damage[i] == 2 else 1.0),0.14,0.14)
		_anatomical_box(actor,"torso","hand"+suffix)

func _anatomical_box(actor: WastelandCreature, zone: String, joint: String) -> void:
	var attachment: BoneAttachment3D = actor.body_parts[joint]
	if not attachment.visible:
		return
	# The first anatomical mesh precedes clothing, face overlays and held equipment.
	for part in attachment.get_children():
		if part is MeshInstance3D and part.visible and part.mesh != null:
			var bounds: AABB = part.transform * part.get_aabb()
			_box(actor,zone,joint,bounds.get_center(),bounds.size.max(Vector3.ONE * 0.01))
			return
	# The neck links the trunk mesh to the head even on species without a neck mesh.
	var children := actor.skeleton.get_bone_children(actor.skeleton.find_bone(joint))
	if not children.is_empty():
		var tip := actor.skeleton.get_bone_rest(children[0]).origin
		if tip.length_squared() > 0.000001:
			var width := maxf(0.015,tip.length()*0.35)
			_segment(actor,zone,joint,tip,width,width)

func _segment(actor: WastelandCreature, zone: String, joint: String, end: Vector3, width: float, depth: float) -> void:
	_box(actor,zone,joint,end*0.5,Vector3(width,end.length(),depth),Basis(Quaternion(Vector3.DOWN,end.normalized())))

func _box(actor: WastelandCreature, zone: String, joint: String, offset: Vector3, size: Vector3, axis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size * actor.rig.scale
	var node := CollisionShape3D.new()
	node.name = joint
	node.shape = shape
	areas[zone].add_child(node)
	bindings.append({"shape": node, "bone": actor.skeleton.find_bone(joint), "offset": offset, "axis":axis})

func bone_at(body: CollisionObject3D, shape_id: int, point: Vector3) -> StringName:
	if body is Area3D and body in areas.values() and shape_id >= 0 and shape_id < body.get_child_count():
		var owner_id := body.shape_find_owner(shape_id)
		var node := body.shape_owner_get_owner(owner_id)
		if node is CollisionShape3D: return node.name
	return closest_contact(point).get("bone",&"")

func closest_contact(point: Vector3) -> Dictionary:
	if not point.is_finite(): return {}
	var nearest: StringName = &""
	var nearest_at := Vector3.INF
	var gap := INF
	var center_gap := INF
	for row in bindings:
		var node: CollisionShape3D = row.shape
		var half: Vector3 = node.shape.size * 0.5
		var local := node.to_local(point)
		var surface := local.clamp(-half,half)
		var distance := local.distance_squared_to(surface)
		if distance < gap or (is_equal_approx(distance,gap) and local.length_squared() < center_gap):
			gap = distance
			center_gap = local.length_squared()
			nearest = node.name
			nearest_at = node.to_global(surface)
	return {"bone":nearest,"at":nearest_at} if nearest != &"" else {}

func enable(value: bool) -> void:
	for area: Area3D in areas.values():
		area.collision_layer = LAYER if value else 0

func pose(actor: WastelandCreature) -> void:
	var root := actor.rig.transform * actor.skeleton.transform
	for row in bindings:
		var joint := root * actor.skeleton.get_bone_global_pose(row.bone)
		row.shape.transform = Transform3D((joint.basis * Basis(row.axis)).orthonormalized(), joint * Vector3(row.offset))
