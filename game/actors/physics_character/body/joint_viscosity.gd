extends RefCounted
## Passive viscous and dry bearing friction, with no rest pose or target angle.
## Impulses are equal and opposite in world space and vanish in rigid rotation.

const Config := preload("../config/physics_character_config.gd")
var _bodies: Array[RigidBody3D] = []
var _pairs: Array[Vector2i] = []
var _bearing_scales := PackedFloat64Array()
var _inverse_inertias: Array[Basis] = []
var _omega := PackedVector3Array()
var _rate: float
var _torque_limit: float
var _dry_friction: float

func setup(config: Config, bodies: Dictionary) -> void:
	_rate = config.passive_joint_drag
	_torque_limit = config.passive_drag_torque_limit_nm
	_dry_friction = config.dry_joint_friction_nm
	var indices := {}
	var radii := {}
	for segment: Dictionary in config.build_segments():
		var size: Vector3 = segment.size
		radii[segment.id] = 0.5 * minf(size.x, size.z)
	for id in bodies:
		indices[id] = _bodies.size()
		_bodies.append(bodies[id])
	for row: Dictionary in config.build_joints():
		_pairs.append(Vector2i(indices[row.parent], indices[row.child]))
		var scale_factor := 1.0
		if config.bearing_reference_radius_m > 0.0:
			var radius := minf(radii[row.parent], radii[row.child])
			scale_factor = minf(1.0, radius / config.bearing_reference_radius_m)
		_bearing_scales.append(scale_factor)
	_inverse_inertias.resize(_bodies.size())
	_omega.resize(_bodies.size())

func dissipate(delta: float) -> void:
	var fraction := 1.0 - exp(-_rate * delta)
	for i in _bodies.size():
		_inverse_inertias[i] = _bodies[i].get_inverse_inertia_tensor()
		_omega[i] = _bodies[i].angular_velocity
	for index in _pairs.size():
		var pair := _pairs[index]
		var a := pair.x
		var b := pair.y
		var relative := _omega[b] - _omega[a]
		if relative.length_squared() < 1e-10:
			continue
		var inv_a := _inverse_inertias[a]
		var inv_b := _inverse_inertias[b]
		# The rotational mobility of a pair is Ia^-1 + Ib^-1. Account for
		# anisotropic inertia so one small hand cannot reverse its spin in a tick.
		var mobility := Basis(inv_a.x + inv_b.x, inv_a.y + inv_b.y, inv_a.z + inv_b.z)
		if mobility.determinant() <= 0.0:
			continue # Before first integration a body's mass properties may be unavailable.
		var stop_impulse := mobility.inverse() * relative
		var impulse := (stop_impulse * fraction).limit_length(_torque_limit * delta)
		impulse += (stop_impulse - impulse).limit_length(_dry_friction * delta * _bearing_scales[index])
		_bodies[a].apply_torque_impulse(impulse)
		_bodies[b].apply_torque_impulse(-impulse)
		# Track just the impulses already submitted within this pass for shared limbs.
		_omega[a] += inv_a * impulse
		_omega[b] -= inv_b * impulse
