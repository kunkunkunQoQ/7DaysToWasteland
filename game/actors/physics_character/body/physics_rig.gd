extends Node3D
## The rig owns physical nodes. Gameplay reads the enclosing character's state interface.

const Segment = preload("body_segment.gd")
const Config = preload("../config/physics_character_config.gd")
const Viscosity := preload("joint_viscosity.gd")
const Speculative := preload("speculative_contacts.gd")

var bodies: Dictionary[StringName, RigidBody3D] = {}
var joints: Dictionary[StringName, Joint3D] = {}
var _viscosity: Viscosity
var _prediction: Speculative

func _ready() -> void:
	set_physics_process(_viscosity != null or _prediction != null)

func build(config: Config, initial_poses: Dictionary = {}) -> void:
	if not bodies.is_empty():
		return
	var surface := PhysicsMaterial.new()
	surface.friction = config.surface_friction
	for row in config.build_segments():
		var body := Segment.new()
		body.name = row.id
		body.config = config
		body.is_foot = row.id == &"foot_l" or row.id == &"foot_r"
		body.position = row.position
		body.mass = row.mass
		if row.has("inertia"):
			body.inertia = row.inertia
		body.linear_damp = config.linear_damping
		body.angular_damp = config.angular_damping
		body.collision_layer = config.body_layer
		body.collision_mask = config.body_mask
		body.physics_material_override = surface
		body.continuous_cd = config.continuous_collision_detection
		body.contact_monitor = true
		body.max_contacts_reported = config.contacts_per_body
		body.can_sleep = false # Refresh contacts even when a support is removed beneath a resting limb.
		if row.has("mass_center"):
			body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			body.center_of_mass = row.mass_center
		for primitive: Dictionary in row.get("collision_parts", [row]):
			var collider := CollisionShape3D.new()
			collider.name = primitive.get("name", &"Collider")
			collider.shape = _make_shape(primitive)
			collider.shape.custom_solver_bias = config.shape_contact_bias
			collider.transform = primitive.get("transform", Transform3D.IDENTITY)
			body.add_child(collider)
		add_child(body)
		bodies[row.id] = body

	for row in config.build_joints():
		var joint := _make_joint(row, config)
		joint.solver_priority = config.joint_solver_priority
		joint.name = "Joint_" + String(row.child)
		joint.transform = Transform3D(row.basis, row.position)
		joint.exclude_nodes_from_collision = true
		joint.node_a = NodePath("../" + String(row.parent))
		joint.node_b = NodePath("../" + String(row.child))
		add_child(joint)
		var stop_torque := float(row.get("limit_torque_nm", config.multi_axis_limit_torque_nm))
		if joint is Generic6DOFJoint3D and stop_torque > 0.0:
			# Set after native joint registration. In 4.6.3 replaying the cached
			# motor-force field during initialization also writes this stop limit.
			var limited := joint as Generic6DOFJoint3D
			limited.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_FORCE_LIMIT, stop_torque)
			limited.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_FORCE_LIMIT, stop_torque)
			limited.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_FORCE_LIMIT, stop_torque)
		joints[row.child] = joint
	# The native joints acquired their independent anatomical reference frames
	# above. Assemble the requested spawn pose once, before the first solve.
	if not initial_poses.is_empty():
		if initial_poses.size() != bodies.size() or not initial_poses.has_all(bodies.keys()):
			push_error("Incomplete initial articulated pose.")
			return
		for id: StringName in bodies:
			bodies[id].transform = initial_poses[id]
			bodies[id].force_update_transform()
	if config.passive_joint_drag > 0 or config.dry_joint_friction_nm > 0:
		_viscosity = Viscosity.new()
		_viscosity.setup(config, bodies)
		set_physics_process(true)
	if config.predict_contacts:
		var prediction := Speculative.new()
		prediction.articulated = config.articulated_contact_response
		if prediction.prepare(self, config):
			_prediction = prediction
			set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _viscosity != null:
		_viscosity.dissipate(delta)
	if _prediction != null:
		_prediction.step(delta)

func _make_shape(row: Dictionary) -> Shape3D:
	var size: Vector3 = row.size
	if row.shape == &"capsule":
		var capsule := CapsuleShape3D.new()
		capsule.radius = size.x * 0.5
		capsule.height = size.y
		return capsule
	var box := BoxShape3D.new()
	box.size = size
	return box

func _make_joint(row: Dictionary, config: Config) -> Joint3D:
	if row.kind == &"hinge" and not config.use_multi_axis_hinges:
		var hinge := HingeJoint3D.new()
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, row.lower)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, row.upper)
		return hinge
	# Native 6DOF joints lock translation at the shared anchor by default.
	var multi_axis := Generic6DOFJoint3D.new()
	multi_axis.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, config.multi_axis_limit_damping)
	multi_axis.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, config.multi_axis_limit_damping)
	multi_axis.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, config.multi_axis_limit_damping)
	multi_axis.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_ERP, config.angular_limit_erp)
	multi_axis.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_ERP, config.angular_limit_erp)
	multi_axis.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_ERP, config.angular_limit_erp)
	if row.kind == &"hinge":
		multi_axis.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, row.lower)
		multi_axis.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, row.upper)
		return multi_axis
	var symmetric := Vector3(row.twist, row.swing, row.swing)
	var low: Vector3 = row.get("lower_angles", -symmetric)
	var high: Vector3 = row.get("upper_angles", symmetric)
	multi_axis.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, low.x)
	multi_axis.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, high.x)
	multi_axis.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, low.y)
	multi_axis.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, high.y)
	multi_axis.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, low.z)
	multi_axis.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, high.z)
	return multi_axis

func has_ground_contact(id: StringName) -> bool:
	var body := bodies.get(id) as Segment
	return body != null and body.has_ground_contact

func get_support_contacts(id: StringName) -> PackedVector3Array:
	var body := bodies.get(id) as Segment
	if body == null:
		return PackedVector3Array()
	return body.sole_contacts
