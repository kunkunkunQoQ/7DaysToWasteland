extends RefCounted
## Finite passive contact response in virtual velocity space. Joint rows transmit
## only the velocity change introduced by these contacts, with no positional bias.

const ITERATIONS := 8
const MAX_CONTACT_IMPULSE_PER_KG := 12.0
const MAX_INTERNAL_IMPULSE_PER_KG := 15.0

class Velocity:
	var body: RigidBody3D
	var inv_mass: float
	var inv_inertia: Basis
	var v: Vector3
	var w: Vector3
	var dv := Vector3.ZERO
	var dw := Vector3.ZERO
	var angular_impulse := Vector3.ZERO

	func impulse(j: Vector3, r: Vector3) -> void:
		var torque := r.cross(j)
		dv += j * inv_mass
		dw += inv_inertia * torque
		angular_impulse += torque

	func point_response(j: Vector3, r: Vector3) -> Vector3:
		return j * inv_mass + (inv_inertia * r.cross(j)).cross(r)

	func step_velocity(r: Vector3) -> Vector3:
		return v + dv + (w + dw).cross(r)

class Anchor:
	var a: Velocity
	var b: Velocity
	var offset_a: Vector3
	var offset_b: Vector3
	var ra: Vector3
	var rb: Vector3
	var mass_matrix: Basis
	var accumulated: Vector3
	var cap: float

	func reset() -> void:
		var pa := a.body.global_transform * offset_a
		var pb := b.body.global_transform * offset_b
		# A shared line of application preserves total angular momentum even
		# when the native solver has already incurred positional error.
		var point := (pa + pb) * 0.5
		ra = point - a.body.global_position
		rb = point - b.body.global_position
		var k := Basis.IDENTITY
		for axis in 3:
			var dir := Basis.IDENTITY[axis]
			k[axis] = a.point_response(dir,ra) + b.point_response(dir,rb)
		mass_matrix = k.inverse()
		accumulated = Vector3.ZERO

	func transmit() -> void:
		var mismatch := (b.dv + b.dw.cross(rb)) - (a.dv + a.dw.cross(ra))
		var next := (accumulated + mass_matrix * mismatch).limit_length(cap)
		var j := next - accumulated
		accumulated = next
		a.impulse(j,ra)
		b.impulse(-j,rb)

class Contact:
	var a: Velocity
	var b: Velocity
	var ra: Vector3
	var rb: Vector3
	var normal: Vector3
	var min_velocity: float
	var mass: float
	var cap: float
	var accumulated := 0.0

	func solve() -> void:
		var relative := a.step_velocity(ra)
		if b != null:
			relative -= b.step_velocity(rb)
		var next := clampf(accumulated + (min_velocity - relative.dot(normal))*mass, 0.0, cap)
		var j := normal * (next - accumulated)
		accumulated = next
		a.impulse(j,ra)
		if b != null:
			b.impulse(-j, rb)

var _velocities: Dictionary[RID,Velocity] = {}
var _anchors: Array[Anchor] = []
var _contacts: Array[Contact] = []
var _dt: float

func prepare(rig: Node3D, config: Resource) -> void:
	var centers := {}
	for seg: Dictionary in config.build_segments():
		centers[seg.id] = seg.position
		var v := Velocity.new()
		v.body = rig.bodies[seg.id]
		v.inv_mass = 1.0 / v.body.mass
		_velocities[v.body.get_rid()] = v
	for row: Dictionary in config.build_joints():
		var link := Anchor.new()
		link.a = _velocities[rig.bodies[row.parent].get_rid()]
		link.b = _velocities[rig.bodies[row.child].get_rid()]
		link.offset_a = row.position - centers[row.parent]
		link.offset_b = row.position - centers[row.child]
		link.cap = MAX_INTERNAL_IMPULSE_PER_KG * minf(link.a.body.mass,link.b.body.mass)
		_anchors.append(link)

func begin_step(dt: float) -> void:
	_dt = dt
	_contacts.clear()
	for v: Velocity in _velocities.values():
		var state := PhysicsServer3D.body_get_direct_state(v.body.get_rid())
		var gravity := state.total_gravity if state != null else Vector3.ZERO
		v.inv_inertia = v.body.get_inverse_inertia_tensor()
		v.v = v.body.linear_velocity + gravity * dt
		v.w = v.body.angular_velocity
		v.dv = Vector3.ZERO
		v.dw = Vector3.ZERO
		v.angular_impulse = Vector3.ZERO

func add_contact(body_a: RigidBody3D, body_b: RigidBody3D, point: Vector3, normal: Vector3, gap: float) -> void:
	var row := Contact.new()
	row.a = _velocities[body_a.get_rid()]
	row.ra = point - body_a.global_position
	row.normal = normal
	row.min_velocity = -maxf(0.0,gap) / _dt
	var k := row.a.point_response(normal,row.ra).dot(normal)
	row.cap = MAX_CONTACT_IMPULSE_PER_KG * body_a.mass
	if body_b != null:
		row.b = _velocities[body_b.get_rid()]
		row.rb = point - body_b.global_position
		row.cap = minf(row.cap, MAX_CONTACT_IMPULSE_PER_KG * body_b.mass)
		k += row.b.point_response(normal,row.rb).dot(normal)
	if k > 0.0:
		row.mass = 1.0 / k
		_contacts.append(row)

func solve() -> void:
	if _contacts.is_empty():
		return
	for link in _anchors:
		link.reset()
	for turn in ITERATIONS:
		for row in _contacts:
			row.solve()
		if turn % 2 == 0:
			for link in _anchors:
				link.transmit()
		else:
			for i in range(_anchors.size()-1,-1,-1):
				_anchors[i].transmit()
	for v: Velocity in _velocities.values():
		if not v.dv.is_zero_approx():
			v.body.apply_central_impulse(v.dv / v.inv_mass)
		if not v.angular_impulse.is_zero_approx():
			v.body.apply_torque_impulse(v.angular_impulse)
