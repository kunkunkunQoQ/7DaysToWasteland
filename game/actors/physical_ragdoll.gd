extends Node3D
## The solver owns world-space bodies. The character keeps its original meshes, skin and equipment.

signal physics_pose_written(delta: float)
signal landing_contact(bone: StringName, point: Vector3, normal: Vector3, closing_speed: float)

const WORLD_MASK := 1 | 2 | 8
const CORPSE_SECONDS := 20.0
const CONTACT_LAYER := 1 << 17
const ACTIVE_GROUP := &"simulating_ragdolls"
const ACTIVE_BUDGET := 12
const PACKED_STRIDE := 7
const MIN_SIZE := 0.016

class Segment:
	var body: RigidBody3D
	var node: Node3D
	var bone := -1
	var parent := -1
	var bind: Transform3D
	var original: Transform3D
	var radius := 0.1
	var extents := Vector3.ONE * 0.1
	var previous: Transform3D
	var incoming := Vector3.ZERO
	var incoming_spin := Vector3.ZERO
	var saved_contacts := 0
	var saved_ccd := false

var _parts: Array[Segment] = []
var _named_parts := {}
var _own_rids: Array[RID] = []
var _skeleton: Skeleton3D
var _avatar: WastelandPartyAvatar
var _face_model: Node3D
var _held := false
var _quiet_time := 0.0
var _sample_time := 0.0
var _elapsed := 0.0
var _released := false
var _support_timer: Timer
var _support_part: Segment
var _support_rid: RID
var _support_point: Vector3
var _support_transform: Transform3D
var _water_source: Node3D
var _water_poll := 0.0
var _submerged := false
var _watching_landing := false
static var _skin_bounds := {}

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	set_physics_process(false)

func begin(model: Node3D, impact := Vector3.ZERO, at := Vector3.INF, bone: StringName = &"") -> bool:
	if not is_inside_tree() or not is_instance_valid(model) or not model.is_inside_tree() or not _parts.is_empty():
		return false
	if model is WastelandPartyAvatar:
		_avatar = model
		if _avatar.legs.size() == 2:
			_build_avatar()
	else:
		_skeleton = model as Skeleton3D
		if _skeleton == null:
			var rigs := model.find_children("*", "Skeleton3D", true, false)
			if not rigs.is_empty():
				_skeleton = rigs[0]
		if _skeleton != null and _skeleton.get_bone_count() > 0:
			if _skeleton.get_parent().has_method("sync_head"):
				_face_model = _skeleton.get_parent()
			_build_skeleton()
	if _parts.is_empty():
		return false
	_add_to_budget()
	if (at.is_finite() or not bone.is_empty()) and not impact.is_zero_approx():
		kick_at(impact, at, bone)
		return true
	var hub := _parts[0].body
	var push: Vector3 = impact.limit_length(13.0)
	var fall_dir := Vector3(push.x, 0, push.z)
	if fall_dir.length_squared() < 0.04:
		fall_dir = hub.global_basis * Vector3(0.65, 0, 0.76)
		fall_dir.y = 0.0
		push += fall_dir.normalized() * 0.48
	var spin := Vector3.UP.cross(fall_dir.normalized()) * clampf(2.3 + push.length() * 0.21, 2.3, 4.6)
	for part in _parts:
		part.body.linear_velocity = push + spin.cross(part.body.global_position - hub.global_position)
		part.body.angular_velocity = spin
	set_physics_process(true)
	return true

func center() -> Vector3:
	return _parts[0].body.global_position if not _parts.is_empty() else global_position

func motion() -> Vector3:
	return _parts[0].body.linear_velocity if not _parts.is_empty() else Vector3.ZERO

func set_motion(incoming: Vector3) -> void:
	var shift := incoming - motion()
	for part in _parts: part.body.linear_velocity += shift

func watch_landing(enabled: bool) -> void:
	if enabled == _watching_landing: return
	_watching_landing = enabled
	for part in _parts:
		var body := part.body
		if enabled:
			part.saved_contacts = body.max_contacts_reported
			part.saved_ccd = body.continuous_cd
			part.incoming = body.linear_velocity
			part.incoming_spin = body.angular_velocity
			body.max_contacts_reported = maxi(4, part.saved_contacts)
			body.continuous_cd = true
		else:
			body.max_contacts_reported = part.saved_contacts
			body.continuous_cd = part.saved_ccd

func _sample_landing() -> void:
	var speed := 0.0
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var bone: StringName
	for part in _parts:
		var body := part.body
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state:
			for i in state.get_contact_count():
				var surface := state.get_contact_local_normal(i)
				if surface.y < 0.30: continue
				var other := state.get_contact_collider_object(i) as CollisionObject3D
				if not other or (other.collision_layer & WORLD_MASK) == 0: continue
				var at := state.get_contact_local_position(i)
				var ground_speed := state.get_contact_collider_velocity_at_position(i)
				var incoming := part.incoming + part.incoming_spin.cross(at - body.global_position)
				var closing := maxf((ground_speed-incoming).dot(surface), (ground_speed-state.get_contact_local_velocity_at_position(i)).dot(surface))
				if not bone.is_empty() and closing <= speed: continue
				speed = maxf(0.0, closing)
				point = at
				normal = surface
				bone = StringName(String(body.name).trim_prefix("Body_"))
		part.incoming = body.linear_velocity
		part.incoming_spin = body.angular_velocity
	if not bone.is_empty():
		watch_landing(false)
		landing_contact.emit(bone, point, normal, speed)

func set_water_source(stream: Node3D) -> void:
	_water_source = stream

func body_for(bone: StringName) -> RigidBody3D:
	var part: Segment = _named_parts.get(String(bone).to_lower())
	return part.body if part != null else null

func inherit_motion(source: Node3D) -> bool:
	if not is_instance_valid(source) or not source.has_method("body_for") or _parts.is_empty(): return false
	for label: String in _named_parts:
		if source.body_for(label) == null: return false
	kick(Vector3.ZERO)
	for label: String in _named_parts:
		var from: RigidBody3D = source.body_for(label)
		var to: RigidBody3D = body_for(label)
		to.global_transform = from.global_transform
		to.linear_velocity = from.linear_velocity
		to.angular_velocity = from.angular_velocity
	_sync_model()
	return true

func kick_at(velocity: Vector3, at: Vector3, bone: StringName = &"") -> void:
	if _released or _parts.is_empty() or not velocity.is_finite(): return
	var selected: Segment = _named_parts.get(String(bone).to_lower())
	if selected == null and at.is_finite():
		var nearest := INF
		for part in _parts:
			var local := part.body.to_local(at)
			var distance := local.distance_squared_to(local.clamp(-part.extents, part.extents))
			if distance < nearest:
				nearest = distance
				selected = part
	if selected == null: selected = _parts[0]
	kick(Vector3.ZERO)
	var body := selected.body
	var offset := (at - body.global_position).limit_length(selected.radius) if at.is_finite() else Vector3.ZERO
	# GodotPhysics can still report unit inverse mass during the first registration tick.
	# Apply Δv = J/m and Δω = I⁻¹(r × J) from this segment's authored mass and inertia.
	var delta_v := velocity.limit_length(13.0)
	var axes := body.global_basis
	var local_momentum := axes.transposed() * offset.cross(delta_v * body.mass)
	body.linear_velocity += delta_v
	body.angular_velocity = (body.angular_velocity + axes * (local_momentum / body.inertia)).limit_length(38.0)

func kick(impact: Vector3) -> void:
	if _released or _parts.is_empty() or not impact.is_finite():
		return
	_held = false
	_quiet_time = 0.0
	_elapsed = 0.0
	if _support_timer != null: _support_timer.stop()
	_add_to_budget()
	for part in _parts:
		part.body.freeze = false
		part.body.sleeping = false
		if not impact.is_zero_approx():
			part.body.linear_velocity += impact.limit_length(13.0)
	set_physics_process(true)

func is_settled() -> bool:
	return _held or not is_physics_processing()

func settle() -> void:
	if _parts.is_empty() or _released:
		return
	_held = true
	if _support_timer != null: _support_timer.stop()
	for part in _parts:
		part.body.freeze = true
		part.body.linear_velocity = Vector3.ZERO
		part.body.angular_velocity = Vector3.ZERO
	_sync_model()
	_remove_from_budget()
	set_physics_process(false)

func release() -> void:
	if _released:
		return
	_released = true
	if _support_timer != null: _support_timer.stop()
	set_physics_process(false)
	_remove_from_budget()
	for part in _parts:
		# A replacement controller may already occupy this exact pose in the same physics step.
		part.body.collision_layer = 0
		part.body.collision_mask = 0
		part.body.freeze = true
		if is_instance_valid(part.node):
			part.node.transform = part.original
		elif is_instance_valid(_skeleton) and part.bone >= 0 and part.bone < _skeleton.get_bone_count():
			_skeleton.set_bone_pose(part.bone, part.original)
	if is_instance_valid(_avatar):
		_avatar.sync_joint_skins()
	elif is_instance_valid(_face_model):
		_face_model.sync_head()
	queue_free()

func pose_snapshot() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for part in _parts:
		var pose := part.body.global_transform
		var q := pose.basis.get_rotation_quaternion()
		values.append_array(PackedFloat32Array([pose.origin.x, pose.origin.y, pose.origin.z, q.x, q.y, q.z, q.w]))
	return values

func apply_pose(values: PackedFloat32Array) -> bool:
	if _parts.is_empty() or _released or values.size() != _parts.size() * PACKED_STRIDE:
		return false
	var transforms: Array[Transform3D] = []
	for i in _parts.size():
		var k := i * PACKED_STRIDE
		var point := Vector3(values[k], values[k + 1], values[k + 2])
		var q := Quaternion(values[k + 3], values[k + 4], values[k + 5], values[k + 6])
		if not point.is_finite() or not q.is_finite() or q.length_squared() < 0.001:
			return false
		transforms.append(Transform3D(Basis(q.normalized()), point))
	settle()
	for i in _parts.size():
		_parts[i].body.global_transform = transforms[i]
	_sync_model()
	return true

func _add_to_budget() -> void:
	if not is_in_group(ACTIVE_GROUP):
		add_to_group(ACTIVE_GROUP)

func _remove_from_budget() -> void:
	if is_in_group(ACTIVE_GROUP):
		remove_from_group(ACTIVE_GROUP)

func _on_sleep_changed(body: RigidBody3D) -> void:
	if not _held and not _released and not body.sleeping and not is_physics_processing():
		if _support_timer != null: _support_timer.stop()
		_add_to_budget()
		set_physics_process(true)

func _physics_process(dt: float) -> void:
	if not is_instance_valid(_avatar) and not is_instance_valid(_skeleton):
		queue_free()
		return
	_sync_model()
	physics_pose_written.emit(dt)
	if _watching_landing: _sample_landing()
	if is_instance_valid(_water_source):
		_water_poll -= dt
		if _water_poll <= 0.0:
			_water_poll = 0.20
			var at := center()
			var wet: bool = at.y < WastelandTerrainGen.WATER_LEVEL and _water_source.water_at(at) and at.y >= _water_source.ground_at(at) - 0.22
			if is_instance_valid(_avatar): _avatar.garment_swimming = wet
			if wet != _submerged:
				_submerged = wet
				for part in _parts:
					part.body.gravity_scale = 0.22 if wet else 1.0
					part.body.linear_damp = 2.8 if wet else 0.28
					part.body.angular_damp = 5.8 if wet else 3.5
	var sleeping := true
	var quiet := true
	_sample_time += dt
	var sample := _sample_time >= 0.20
	for part in _parts:
		var body := part.body
		sleeping = sleeping and body.sleeping
		if sample:
			var pose := body.global_transform
			var travel := part.previous.origin.distance_to(pose.origin)
			var rotation := part.previous.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())
			quiet = quiet and travel + rotation * part.radius < 0.012 + 0.08 * part.radius
			part.previous = pose
	_elapsed += dt
	if sample:
		_quiet_time = _quiet_time + _sample_time if quiet else 0.0
		_sample_time = 0.0
	if sleeping:
		_remove_from_budget()
		set_physics_process(false)
		_watch_support()
	elif _quiet_time > 0.24 and _elapsed > 0.6:
		if get_tree().get_node_count_in_group(ACTIVE_GROUP) > ACTIVE_BUDGET:
			settle()
			_watch_support()
		elif _quiet_time > 0.65:
			# Limit-contact jitter can keep the engine awake long after visible motion stops.
			# Keep the island available for impacts while the support probe watches the floor.
			for part in _parts:
				part.body.linear_velocity = Vector3.ZERO
				part.body.angular_velocity = Vector3.ZERO
				part.body.sleeping = true
			_remove_from_budget()
			set_physics_process(false)
			_watch_support()

# GodotPhysics leaves sleeping islands suspended when a supporting StaticBody is removed.
# Keep one short, infrequent ray per resting body instead of updating its skeleton every tick.
func _watch_support() -> void:
	_support_part = _parts[0]
	for part in _parts:
		if part.body.global_position.y < _support_part.body.global_position.y:
			_support_part = part
	var support := _ground_support()
	if support.is_empty() and _support_part != _parts[0]:
		_support_part = _parts[0]
		support = _ground_support()
	if support.is_empty():
		kick(Vector3.DOWN * 0.12)
		return
	_support_rid = support.rid
	_support_point = support.position
	_support_transform = support.collider.global_transform
	if _support_timer == null:
		_support_timer = Timer.new()
		_support_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
		_support_timer.wait_time = 0.45 + 0.01 * float(get_instance_id() % 19)
		add_child(_support_timer)
		_support_timer.timeout.connect(_check_support)
	_support_timer.start()

func _ground_support() -> Dictionary:
	var at := _support_part.body.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.20, at + Vector3.DOWN * 0.85, WORLD_MASK | CONTACT_LAYER, _own_rids)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _check_support() -> void:
	var support := _ground_support()
	if support.is_empty() or support.rid != _support_rid or _support_point.distance_squared_to(support.position) > 0.0025 or not _support_transform.is_equal_approx(support.collider.global_transform):
		kick(Vector3.DOWN * 0.12)

func _sync_model() -> void:
	if is_instance_valid(_avatar):
		for part in _parts:
			part.node.global_transform = part.body.global_transform * part.bind
		_avatar.sync_joint_skins()
	elif is_instance_valid(_skeleton):
		var inverse := _skeleton.global_transform.affine_inverse()
		for part in _parts:
			_skeleton.set_bone_global_pose(part.bone, inverse * part.body.global_transform * part.bind)
		if is_instance_valid(_face_model):
			_face_model.sync_head()

func _build_avatar() -> void:
	var a := _avatar
	var leg_ratio := float(a.LEG_LENGTH[a.outfit])
	var hips := _avatar_segment("hips", a.pivot, -1, Vector3(0, 0.86 * leg_ratio, 0), Vector3(0.32, 0.23, 0.25))
	var torso := _avatar_segment("torso", a.jacket, hips, Vector3(0, 1.24, 0), Vector3(0.38, 0.53, 0.26), Vector3(0, 0.97, 0))
	_avatar_segment("head", a.neck, torso, Vector3(0, 0.13, -0.014), Vector3(0.22, 0.29, 0.24))
	for i in 2:
		var side := "l" if i == 0 else "r"
		var arm := _avatar_segment("arm_" + side, a.arms[i], torso, a.elbows[i].position * 0.5, Vector3(0.14, 0.29, 0.15))
		var elbow := _avatar_segment("elbow_" + side, a.elbows[i], arm, a.wrist_joints[i].position * 0.5, Vector3(0.11, 0.25, 0.12))
		_avatar_segment("hand_" + side, a.wrist_joints[i], elbow, Vector3(0, -0.080, 0), Vector3(0.085, 0.16, 0.09))
		var leg := _avatar_segment("leg_" + side, a.legs[i], hips, a.knees[i].position * 0.5, Vector3(0.17, 0.41, 0.19))
		var knee := _avatar_segment("knee_" + side, a.knees[i], leg, a.ankle_joints[i].position * 0.5, Vector3(0.13, 0.37, 0.15))
		_avatar_segment("ankle_" + side, a.ankle_joints[i], knee, Vector3(0, -0.059, -0.040), Vector3(0.12, 0.11, 0.23))

func _avatar_segment(label: String, node: Node3D, parent: int, midpoint: Vector3, size: Vector3, anchor := Vector3.ZERO) -> int:
	var part := Segment.new()
	part.node = node
	part.parent = parent
	part.original = node.transform
	return _segment(part, label, node.global_transform, AABB(midpoint - size * 0.5, size), node.to_global(anchor))

func _build_skeleton() -> void:
	var mapped := {}
	var attachment_bounds := skeleton_bounds(_skeleton)
	for bone in _skeleton.get_bone_count():
		var label := String(_skeleton.get_bone_name(bone)).to_lower()
		var parent_bone := _skeleton.get_bone_parent(bone)
		if parent_bone >= 0 and attachment_bounds.has(bone) and attachment_bounds[bone] == null:
			continue
		var part := Segment.new()
		part.bone = bone
		part.original = _skeleton.get_bone_pose(bone)
		while parent_bone >= 0 and not mapped.has(parent_bone):
			parent_bone = _skeleton.get_bone_parent(parent_bone)
		part.parent = mapped.get(parent_bone, -1)
		var at := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)
		var bounds: AABB = attachment_bounds.get(bone, AABB())
		if bounds.size.is_zero_approx():
			var children := _skeleton.get_bone_children(bone)
			var end := Vector3(0, 0.045, 0)
			if not children.is_empty():
				end = _skeleton.get_bone_rest(children[0]).origin
			var width := maxf(end.length() * 0.32, MIN_SIZE)
			bounds = AABB(Vector3.ZERO, Vector3.ZERO).expand(end).grow(width * 0.5)
		mapped[bone] = _segment(part, label, at, bounds, at.origin)

static func skeleton_bounds(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for child in skeleton.get_children():
		if child is BoneAttachment3D:
			var bone := skeleton.find_bone(child.bone_name)
			if not child.visible:
				result[bone] = null
				continue
			for mesh in child.get_children():
				if mesh is MeshInstance3D and mesh.visible and mesh.mesh != null:
					# Anatomy is the first mesh. Gear and held tools follow it visually.
					result[bone] = mesh.transform * mesh.get_aabb()
					break
	if not result.is_empty():
		return result
	# Aquatic and bird models share a single weighted mesh. Cache its bone-local bounds per morph.
	for child in skeleton.get_parent().get_children():
		if child is MeshInstance3D and child.mesh != null and child.skin != null and child.get_node_or_null(child.skeleton) == skeleton:
			if _skin_bounds.has(child.mesh):
				return _skin_bounds[child.mesh]
			var bind_bones := PackedInt32Array()
			var inverse_binds: Array[Transform3D] = []
			for bind in child.skin.get_bind_count():
				var bone: int = child.skin.get_bind_bone(bind)
				if bone < 0: bone = skeleton.find_bone(child.skin.get_bind_name(bind))
				bind_bones.append(bone)
				inverse_binds.append(child.skin.get_bind_pose(bind))
			for surface in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if vertices.is_empty() or ids.is_empty():
					continue
				var stride := ids.size() / vertices.size()
				for i in vertices.size():
					var bind := ids[i * stride]
					var bone := bind_bones[bind]
					if bone < 0:
						continue
					var pt := inverse_binds[bind] * vertices[i]
					var bounds: AABB = result.get(bone, AABB(pt, Vector3.ZERO))
					result[bone] = bounds.expand(pt)
			_skin_bounds[child.mesh] = result
			break
	return result

func _segment(part: Segment, label: String, joint_pose: Transform3D, bounds: AABB, anchor: Vector3) -> int:
	var body := RigidBody3D.new()
	body.name = "Body_" + label
	body.collision_layer = CONTACT_LAYER
	body.collision_mask = WORLD_MASK | CONTACT_LAYER
	body.linear_damp = 0.28
	body.angular_damp = 3.5
	var trunk := label in ["torso", "hips", "breast", "shell", "carapace", "fishbody"]
	body.transform = Transform3D(joint_pose.basis.orthonormalized(), joint_pose * bounds.get_center())
	var size := (bounds.size * joint_pose.basis.get_scale().abs() * 0.90).max(Vector3.ONE * MIN_SIZE)
	# Approximate the filled fraction of each segment's bounding box. A horn or fin mustn't
	# weigh as much as the trunk. Limit mass ratios at joints for the 60 Hz solver.
	var mass_kg := clampf(size.x * size.y * size.z * (660.0 if trunk else 470.0), 0.004, 38.0)
	if part.parent >= 0:
		var parent_mass := _parts[part.parent].body.mass
		mass_kg = clampf(mass_kg, parent_mass * 0.14, parent_mass * 3.0)
	body.mass = mass_kg
	# Tiny paws and their centimetre-wide contacts otherwise acquire extreme twist velocities
	# when the solver corrects a joint under the game's 18 m/s² gravity.
	var sq := size * size
	body.inertia = Vector3(sq.y + sq.z, sq.x + sq.z, sq.x + sq.y).max(Vector3.ONE * 0.045) * (body.mass / 12.0)
	part.radius = size.length() * 0.5
	part.extents = size * 0.5
	var shape := CollisionShape3D.new()
	if trunk or label.begins_with("ankle_") or label.begins_with("wing"):
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	else:
		var axis := size.max_axis_index()
		var capsule := CapsuleShape3D.new()
		var diameter := minf(size[axis], (size[(axis + 1) % 3] + size[(axis + 2) % 3]) * 0.5)
		capsule.radius = diameter * 0.5
		capsule.height = size[axis]
		shape.shape = capsule
		if axis == Vector3.AXIS_X:
			shape.rotation.z = PI * 0.5
		elif axis == Vector3.AXIS_Z:
			shape.rotation.x = PI * 0.5
	shape.shape.margin = minf(0.012, size[size.min_axis_index()] * 0.12)
	body.add_child(shape)
	add_child(body)
	# Authored folded wings, attached claws and compact crouches overlap in their start pose.
	# Keep anatomical constraints inside each rig while permitting contacts with other bodies.
	for other in _parts:
		body.add_collision_exception_with(other.body)
	_own_rids.append(body.get_rid())
	body.sleeping_state_changed.connect(_on_sleep_changed.bind(body))
	part.body = body
	part.previous = body.global_transform
	part.bind = body.global_transform.affine_inverse() * joint_pose
	_parts.append(part)
	_named_parts[label] = part
	if part.parent >= 0:
		_join(label, part, joint_pose.basis.orthonormalized(), anchor)
	return _parts.size() - 1

func _join(label: String, part: Segment, axes: Basis, anchor: Vector3) -> void:
	var joint: Joint3D
	if label.begins_with("knee_") or label.begins_with("elbow_"):
		var hinge := HingeJoint3D.new()
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		var flexion := part.original.basis.orthonormalized().get_euler().x
		if label.begins_with("knee_"):
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, minf(0.0, -2.5 - flexion))
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, maxf(0.0, 0.20 - flexion))
		else:
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, minf(0.0, -0.25 - flexion))
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, maxf(0.0, 2.45 - flexion))
		axes *= Basis(Vector3.UP, PI * 0.5)
		joint = hinge
	else:
		var spine := label in ["torso", "head", "neck", "skull"]
		var twist := 0.41 if spine else 0.69
		var swing := 0.56 if spine else 1.05
		# Use the same native limited joint as the passive character rig. A cone-twist
		# constraint can inject angular energy at the swing limit of tiny ears and paws.
		var socket := Generic6DOFJoint3D.new()
		socket.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -twist)
		socket.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, twist)
		socket.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -swing)
		socket.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, swing)
		socket.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -swing)
		socket.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, swing)
		socket.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_ERP, 0.28)
		socket.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_ERP, 0.28)
		socket.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_ERP, 0.28)
		axes *= Basis(Vector3.BACK, PI * 0.5)
		joint = socket
	joint.name = "Joint_" + label
	joint.transform = Transform3D(axes, anchor)
	joint.exclude_nodes_from_collision = true
	joint.node_a = NodePath("../" + String(_parts[part.parent].body.name))
	joint.node_b = NodePath("../" + String(part.body.name))
	add_child(joint)
