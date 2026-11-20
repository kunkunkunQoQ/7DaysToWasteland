extends RefCounted
## Internal actuators. All requested torques are applied between two segments.
## Targets are child orientations relative to the parent, in the parent's body axes.

class Muscle:
	var id: StringName
	var parent: RigidBody3D
	var child: RigidBody3D
	var rest_frame: Basis
	var hinge: bool
	var kp: float
	var kd: float

var _muscles: Array[Muscle] = []
var torque_limits: Dictionary[StringName, float] = {}
var last_torques: Dictionary[StringName, Vector3] = {}
var gain_scale := 1.0
var damping_scale := 1.0

func setup(config: Resource, bodies: Dictionary) -> void:
	_muscles.clear()
	torque_limits.clear()
	last_torques.clear()
	for joint: Dictionary in config.build_joints():
		var muscle := Muscle.new()
		muscle.id = joint.child
		muscle.parent = bodies[joint.parent]
		muscle.child = bodies[joint.child]
		muscle.rest_frame = joint.basis
		muscle.hinge = joint.kind == &"hinge"
		var gains := _gains(String(muscle.id))
		muscle.kp = gains.x
		muscle.kd = gains.y
		torque_limits[muscle.id] = gains.z
		last_torques[muscle.id] = Vector3.ZERO
		_muscles.append(muscle)

# Stiffness (N m/rad), damping (N m s/rad), maximum joint torque (N m).
static func _gains(id: String) -> Vector3:
	if id.begins_with("thigh"): return Vector3(850, 55, 230)
	if id.begins_with("calf"): return Vector3(720, 42, 185)
	if id.begins_with("foot"): return Vector3(480, 30, 115)
	if id.begins_with("upper_arm"): return Vector3(100, 7, 75)
	if id.begins_with("lower_arm"): return Vector3(65, 4, 55)
	if id.begins_with("hand"): return Vector3(18, 1.0, 16)
	if id == "head": return Vector3(120, 8, 48)
	return Vector3(950, 55, 220)

## Axis-angle logarithm, continuous through the usual quaternion sign flip.
static func rotation_error(target: Basis, current: Basis) -> Vector3:
	var q := (target * current.transposed()).orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var axis_sin := Vector3(q.x, q.y, q.z)
	var length_sin := axis_sin.length()
	if length_sin < 0.000001:
		return axis_sin * 2.0
	return axis_sin * (2.0 * atan2(length_sin, q.w) / length_sin)

func step(delta: float, targets: Dictionary, feedforward_world: Dictionary = {}, strength := 1.0) -> void:
	for muscle: Muscle in _muscles:
		var torque := Vector3.ZERO
		if delta > 0.0 and strength > 0.0:
			var parent_frame := muscle.parent.global_basis.orthonormalized()
			var world_frame := parent_frame * muscle.rest_frame
			var desired: Basis = targets.get(muscle.id, Basis.IDENTITY)
			var child_frame := muscle.child.global_basis.orthonormalized()
			var pose := world_frame.transposed() * child_frame * muscle.rest_frame
			var target := muscle.rest_frame.transposed() * desired * muscle.rest_frame
			var error := rotation_error(target, pose)
			var omega := world_frame.transposed() * (muscle.child.angular_velocity - muscle.parent.angular_velocity)
			var ia := muscle.parent.get_inverse_inertia_tensor()
			var ib := muscle.child.get_inverse_inertia_tensor()
			var mobility := world_frame.transposed() * Basis(ia.x + ib.x, ia.y + ib.y, ia.z + ib.z) * world_frame
			var kp := muscle.kp * gain_scale * strength
			var kd := muscle.kd * damping_scale * strength
			# Backward Euler for relative rotation e(t+dt)=e(t)-dt*w(t+dt).
			# The feed-forward term carries the planner's anticipated joint load.
			var c := kd + kp * delta
			var rhs := kp * error - c * omega
			var ff: Vector3 = world_frame.transposed() * Vector3(feedforward_world.get(muscle.id, Vector3.ZERO))
			var local_torque: Vector3
			if muscle.hinge:
				local_torque = Vector3.BACK * (rhs.z / (1.0 + c * delta * mobility.z.z) + ff.z)
			else:
				var system := Basis(Vector3.RIGHT + mobility.x * (c * delta),
					Vector3.UP + mobility.y * (c * delta), Vector3.BACK + mobility.z * (c * delta))
				local_torque = system.inverse() * rhs + ff
			torque = (world_frame * local_torque).limit_length(torque_limits[muscle.id] * strength)
			var impulse := torque * delta
			muscle.parent.apply_torque_impulse(-impulse)
			muscle.child.apply_torque_impulse(impulse)
		last_torques[muscle.id] = torque
