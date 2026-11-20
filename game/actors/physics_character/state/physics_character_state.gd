class_name PhysicsCharacterState
extends RefCounted
## One fixed-step observation. Positions, velocities and poses use world coordinates.
## Keep a snapshot to compare ticks. The sampler publishes a new instance each step.

enum SupportFoot { NONE = 0, LEFT = 1, RIGHT = 2, BOTH = 3 }

# Owned exclusively by the snapshot once the sampler publishes it.
class Measurements:
	var tick_index: int
	var step_seconds: float
	var left_sole_position: Vector3
	var right_sole_position: Vector3
	var eye_position: Vector3
	var center_of_mass: Vector3
	var linear_velocity: Vector3
	var angular_velocity: Vector3
	var angular_momentum: Vector3
	var total_mass: float
	var left_support_load_n: float
	var right_support_load_n: float
	var nonfoot_ground_contact: bool
	var body_angular_velocities: Dictionary[StringName, Vector3] = {}
	var body_linear_velocities: Dictionary[StringName, Vector3] = {}
	var support_feet: int
	var body_grounded: bool
	var fallen: bool
	var left_support_points: PackedVector3Array
	var right_support_points: PackedVector3Array
	var body_poses: Dictionary[StringName, Transform3D] = {}

var _frame: Measurements

var tick_index: int:
	get: return _frame.tick_index
var step_seconds: float:
	get: return _frame.step_seconds
var left_sole_position: Vector3:
	get: return _frame.left_sole_position
var right_sole_position: Vector3:
	get: return _frame.right_sole_position
## Midpoint between the two sole landmarks, including when either foot is airborne.
var foot_position: Vector3:
	get: return (left_sole_position + right_sole_position) * 0.5
var pelvis_position: Vector3:
	get: return _frame.body_poses[&"pelvis"].origin
var eye_position: Vector3:
	get: return _frame.eye_position
var center_of_mass: Vector3:
	get: return _frame.center_of_mass
## Mass-weighted linear velocity of all body segments, equal to the COM velocity.
var linear_velocity: Vector3:
	get: return _frame.linear_velocity
## Pelvis angular velocity, in world-space radians per second.
var angular_velocity: Vector3:
	get: return _frame.angular_velocity
## World angular momentum about the whole-body COM, including orbital terms (kg m²/s).
var angular_momentum: Vector3:
	get: return _frame.angular_momentum
var total_mass: float:
	get: return _frame.total_mass
var body_angular_velocities: Dictionary[StringName, Vector3]:
	get: return _frame.body_angular_velocities
var body_linear_velocities: Dictionary[StringName, Vector3]:
	get: return _frame.body_linear_velocities
var left_support_load_n: float:
	get: return _frame.left_support_load_n
var right_support_load_n: float:
	get: return _frame.right_support_load_n
var nonfoot_ground_contact: bool:
	get: return _frame.nonfoot_ground_contact
## SupportFoot bit mask based on confirmed sole contacts from the physics solver.
var support_feet: int:
	get: return _frame.support_feet
var grounded: bool:
	get: return support_feet != SupportFoot.NONE
## Any segment has an upward-facing external contact, even when both soles are off the floor.
var body_grounded: bool:
	get: return _frame.body_grounded
## Sampled torso tilt and contact with a body segment other than a sole indicate a fall.
var fallen: bool:
	get: return _frame.fallen
## Contact points are copied on read so each consumer can work with them independently.
var left_support_points: PackedVector3Array:
	get: return _frame.left_support_points.duplicate()
var right_support_points: PackedVector3Array:
	get: return _frame.right_support_points.duplicate()
## Read-only value transforms for one-way visual sync. Contains no physics objects.
var body_poses: Dictionary[StringName, Transform3D]:
	get: return _frame.body_poses

func _init(measurements: Measurements) -> void:
	_frame = measurements
	_frame.body_poses.make_read_only()
	_frame.body_angular_velocities.make_read_only()
	_frame.body_linear_velocities.make_read_only()
