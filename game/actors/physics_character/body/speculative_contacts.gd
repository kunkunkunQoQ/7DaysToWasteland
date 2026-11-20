extends RefCounted
## Optional phase-2 experiment. Predict free-flight shape contact one step ahead.
## The native contact solver handles resting and penetrating configurations.

const MAX_IMPULSE_PER_KG := 12.0
const SLOP := 0.0001
const Response := preload("contact_response.gd")

class Part:
	var body: RigidBody3D
	var shape: Shape3D
	var radius: float
	var half := Vector3.ZERO
	var shaft := 0.0
	var bound: float
	var pose: Transform3D
	var future: Transform3D
	var v: Vector3
	var w: Vector3
	var inv_i: Basis
	var exclude_except_self: Array[RID] = []

	func support(normal: Vector3, near: Vector3) -> Vector3:
		var local := pose.basis.transposed() * normal
		var witness := pose.affine_inverse() * near
		if radius > 0.0:
			var y := signf(local.y) * shaft if absf(local.y) > 0.0001 else clampf(witness.y,-shaft,shaft)
			return pose * (Vector3.UP * y + local * radius)
		witness = witness.clamp(-half,half)
		for i in 3:
			if absf(local[i]) > 0.0001:
				witness[i] = signf(local[i]) * half[i]
		return pose * witness

var _parts: Array[Part] = []
var _pairs: Array[Vector2i] = []
var _own_rids: Array[RID] = []
var _space: PhysicsDirectSpaceState3D
var _environment_mask: int
var _body_layer: int
var articulated := false
var _response := Response.new()
var applied_static := 0
var applied_self := 0

func prepare(rig: Node3D, config: Resource) -> bool:
	# This optional predictor uses exactly one centered primitive per body.
	# Compound soles use the native solver and the compound-aware geometry probe.
	for body: RigidBody3D in rig.bodies.values():
		var shapes := body.find_children("*", "CollisionShape3D", false, false)
		if shapes.size() != 1 or not (shapes[0] as CollisionShape3D).transform.is_equal_approx(Transform3D.IDENTITY):
			push_warning("Experimental contact prediction requires one centered collider per segment. Using native contacts.")
			return false
	_space = rig.get_world_3d().direct_space_state
	_environment_mask = config.body_mask
	_body_layer = config.body_layer
	if articulated:
		_response.prepare(rig,config)
	var indices := {}
	for id: StringName in rig.bodies:
		var part := Part.new()
		part.body = rig.bodies[id]
		part.shape = (part.body.get_node("Collider") as CollisionShape3D).shape
		if part.shape is CapsuleShape3D:
			var capsule := part.shape as CapsuleShape3D
			part.radius = capsule.radius
			part.shaft = capsule.height * 0.5 - part.radius
			part.bound = capsule.height * 0.5
		else:
			part.half = (part.shape as BoxShape3D).size * 0.5
			part.bound = part.half.length()
		indices[id] = _parts.size()
		_own_rids.append(part.body.get_rid())
		_parts.append(part)
	var connected := {}
	for joint: Dictionary in config.build_joints():
		var a: int = indices[joint.parent]
		var b: int = indices[joint.child]
		connected[Vector2i(mini(a,b),maxi(a,b))] = true
	for i in _parts.size():
		_parts[i].exclude_except_self.assign(_own_rids)
		_parts[i].exclude_except_self.erase(_parts[i].body.get_rid())
		for j in range(i+1,_parts.size()):
			if not connected.has(Vector2i(i,j)):
				_pairs.append(Vector2i(i,j))
	return true

func step(dt: float) -> void:
	if articulated:
		_response.begin_step(dt)
	for index in _parts.size():
		var part := _parts[index]
		part.pose = part.body.global_transform
		part.v = part.body.linear_velocity
		part.w = part.body.angular_velocity
		part.inv_i = part.body.get_inverse_inertia_tensor()
		part.future = part.pose
		part.future.origin += part.v * dt
		if articulated:
			var direct := PhysicsServer3D.body_get_direct_state(part.body.get_rid())
			if direct != null:
				part.future.origin += direct.total_gravity * dt*dt
				_existing_contacts(part,direct,index)
		var speed := part.w.length()
		if speed > 0.0001:
			part.future.basis = part.pose.basis.rotated(part.w / speed, speed * dt)
		if (part.v.length() + speed * part.bound) * dt > SLOP:
			_predict(part, null, part.future, _own_rids, _environment_mask, dt)
	for pair in _pairs:
		var a := _parts[pair.x]
		var b := _parts[pair.y]
		var displacement := (a.v - b.v).length() * dt
		if a.pose.origin.distance_to(b.pose.origin) > a.bound + b.bound + displacement:
			continue
		if displacement + dt * (a.w.length()*a.bound + b.w.length()*b.bound) < SLOP:
			continue
		# Express the end pose of A relative to B's current pose. Native queries
		# now see B fixed, while both bodies' translation/rotation are predicted.
		var relative_end := b.pose * b.future.affine_inverse() * a.future
		_predict(a, b, relative_end, b.exclude_except_self, _body_layer, dt)
	if articulated:
		_response.solve()

func _existing_contacts(part: Part, direct: PhysicsDirectBodyState3D, own_index: int) -> void:
	for c in direct.get_contact_count():
		var collider := direct.get_contact_collider_object(c)
		var other: RigidBody3D
		var index := _own_rids.find(direct.get_contact_collider(c))
		if index >= 0:
			if index <= own_index:
				continue
			other = _parts[index].body
		elif not _static(collider):
			continue
		var n := direct.get_contact_local_normal(c)
		var pa := direct.get_contact_local_position(c)
		var pb := direct.get_contact_collider_position(c)
		if n.is_normalized():
			_response.add_contact(part.body,other,(pa+pb)*0.5,n,maxf(0.0,(pa-pb).dot(n)))

func _static(obj: Object) -> bool:
	var collider := obj as StaticBody3D
	return collider != null and not collider is AnimatableBody3D and collider.constant_linear_velocity.is_zero_approx() and collider.constant_angular_velocity.is_zero_approx()

func _predict(a: Part, b: Part, relative_end: Transform3D, exclude: Array[RID], mask: int, dt: float) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = a.shape
	q.collision_mask = mask
	q.exclude = exclude
	q.margin = SLOP
	q.transform = relative_end
	var hit := _space.get_rest_info(q)
	if hit.is_empty():
		# Sweep catches translation through thin obstacles when the end pose
		# is clear again. Narrow phase supplies a surface witness at the hit.
		q.transform = a.pose
		q.motion = relative_end.origin - a.pose.origin
		if q.motion.length_squared() < SLOP*SLOP:
			return
		var fractions := _space.cast_motion(q)
		if fractions.size() < 2 or fractions[1] >= 1.0:
			return
		var fraction := minf(1.0, fractions[1] + minf(0.04, 0.003 / q.motion.length()))
		q.transform = a.pose.interpolate_with(relative_end, fraction)
		q.motion = Vector3.ZERO
		hit = _space.get_rest_info(q)
		if hit.is_empty():
			return
	if b != null:
		if hit.rid != b.body.get_rid():
			return
	else:
		if not _static(instance_from_id(hit.collider_id)):
			return
	var n: Vector3 = hit.normal
	if not n.is_normalized():
		return
	var witness: Vector3 = hit.point
	var pa := a.support(-n, witness)
	var pb := b.support(n, pa) if b != null else witness
	var separation := (pa-pb).dot(n)
	if separation <= SLOP:
		return
	# Use one impulse line of action on both bodies to conserve momentum.
	var point := (pa + pb) * 0.5
	if articulated:
		_response.add_contact(a.body, b.body if b != null else null, point, n, separation)
		return
	var ra := point - a.pose.origin
	var relative_velocity := a.v + a.w.cross(ra)
	var angular_a := a.inv_i * ra.cross(n)
	var inverse_mass := 1.0 / a.body.mass + angular_a.cross(ra).dot(n)
	var limit := a.body.mass * MAX_IMPULSE_PER_KG
	var rb := Vector3.ZERO
	var angular_b := Vector3.ZERO
	if b != null:
		rb = point - b.pose.origin
		relative_velocity -= b.v + b.w.cross(rb)
		angular_b = b.inv_i * rb.cross(n)
		inverse_mass += 1.0 / b.body.mass + angular_b.cross(rb).dot(n)
		limit = minf(limit, b.body.mass * MAX_IMPULSE_PER_KG)
	var closure := -relative_velocity.dot(n) - separation / dt
	if closure <= 0.0 or inverse_mass <= 0.0:
		return
	var j := minf(closure / inverse_mass, limit)
	a.body.apply_impulse(n*j, ra)
	a.v += n * (j/a.body.mass)
	a.w += angular_a*j
	if b != null:
		b.body.apply_impulse(-n*j, rb)
		b.v -= n * (j/b.body.mass)
		b.w -= angular_b*j
		applied_self += 1
	else:
		applied_static += 1
