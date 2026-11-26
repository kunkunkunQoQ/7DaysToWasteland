extends RefCounted

# Local direction from the attachment towards the free edge, then maximum travel in metres.
# A reversal of motion excites the spring. The garment comes to rest without an idle wave.
const PROFILES := {
	&"Undershirt": Vector4(0,-1,0,0.004), &"BaseShorts": Vector4(0,-1,0,0.006),
	&"CoatBody": Vector4(0,-1,0,0.035), &"OilskinVest": Vector4(0,-1,0,0.014),
	&"CoatSleeve": Vector4(0,-1,0,0.006), &"CoatCuff": Vector4(0,-1,0,0.012),
	&"TrouserLeg": Vector4(0,-1,0,0.012), &"sun_cape": Vector4(0,-1,0,0.11),
	&"meme_shawl": Vector4(0,-1,0,0.085), &"WornPack": Vector4(0,-1,0,0.016),
	&"meme_tail": Vector4(0,0,1,0.115), &"meme_fins": Vector4(0,0,-1,0.038),
	&"meme_duck": Vector4(0,0,-1,0.012), &"meme_alien": Vector4(0,-1,0,0.023),
	&"meme_antenna": Vector4(0,1,0,0.019), &"meme_ears": Vector4(0,1,0,0.015),
	&"meme_whiskers": Vector4(1,0,0,0.009), &"meme_clock": Vector4(0,-1,0,0.018),
	&"AlpineCap": Vector4(0,1,0,0.009), &"WorkGlove": Vector4(0,-1,0,0.003),
	&"meme_claws": Vector4(0,-1,0,0.008),
}
const SURFACE := preload("res://shaders/survivor_surface.gdshader")

var piece: MeshInstance3D
var material: ShaderMaterial
var anchor: Vector3
var rest_pose: Transform3D
var rigid := false
var reach: float
var previous_pin := Vector3.INF
var previous_basis := Basis.IDENTITY
var previous_speed := Vector3.ZERO
var displacement := Vector3.ZERO
var velocity := Vector3.ZERO
var turn := 0.0
var turn_speed := 0.0
var at_rest := true

func _init(node: MeshInstance3D) -> void:
	piece = node
	var profile: Vector4 = PROFILES[node.name]
	var axis := Vector3(profile.x, profile.y, profile.z)
	reach = profile.w
	var bounds := node.mesh.get_aabb()
	var span := bounds.size.abs().dot(axis.abs())
	var center := bounds.get_center()
	anchor = center - axis * span * 0.5
	var start := anchor.dot(axis) + span * 0.23
	var end := center.dot(axis) + span * 0.5
	if node.name == &"meme_whiskers":
		anchor.x = 0.0
		start = 0.016
	elif node.name == &"meme_duck":
		start = 0.31  # Keep the inflatable ring fixed at the waist.
	elif node.name == &"meme_shawl":
		start = 0.105 # Pin the collar, including its front clasp and cords.
	elif node.name == &"meme_antenna":
		start = 0.105 # Only the aerials extend above the shell.
	elif node.name == &"AlpineCap":
		start = 1.736 # Pin the ribbed cuff against the head.
	rest_pose = node.transform
	rigid = node.name == &"meme_clock"
	if rigid: return
	material = ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("hem_axis", axis)
	material.set_shader_parameter("hem_limits", Vector2(start, maxf(start + 0.001, end)))
	material.set_shader_parameter("two_ends", node.name == &"meme_whiskers")
	material.set_shader_parameter("wraps_body", node.name in [&"Undershirt",&"CoatBody",&"OilskinVest",&"sun_cape",&"meme_shawl",&"meme_alien"])
	piece.material_override = material
	piece.extra_cull_margin = reach * 1.5

func reset() -> void:
	previous_pin = Vector3.INF
	previous_speed = Vector3.ZERO
	velocity = Vector3.ZERO
	turn_speed = 0.0
	if displacement != Vector3.ZERO or turn != 0.0:
		displacement = Vector3.ZERO
		turn = 0.0
		apply_motion()
	at_rest = true

func inherit_motion(source: RefCounted) -> void:
	if not source.previous_pin.is_finite(): return
	var frame := piece.get_parent_node_3d().global_transform * rest_pose
	previous_pin = frame * anchor
	previous_basis = frame.basis.orthonormalized()
	var to_local: Basis = previous_basis.transposed() * source.previous_basis
	displacement = (to_local * source.displacement).limit_length(reach)
	velocity = to_local * source.velocity
	previous_speed = source.previous_speed
	turn = source.turn
	turn_speed = source.turn_speed
	at_rest = false
	apply_motion()

func step(dt: float, swimming: bool) -> void:
	# Reading the unmodified attachment avoids feeding the swinging clock back into its spring.
	var frame := piece.get_parent_node_3d().global_transform * rest_pose
	var pin := frame * anchor
	var basis := frame.basis.orthonormalized()
	if not previous_pin.is_finite() or pin.distance_squared_to(previous_pin) > 2.25:
		reset()
		previous_pin = pin
		previous_basis = basis
		return
	var world_speed := ((pin - previous_pin) / dt).limit_length(14.0)
	var inverse := basis.transposed()
	var local_speed := inverse * world_speed
	var reverse_accel := inverse * (previous_speed - world_speed)
	var yaw_rate := atan2(previous_basis.z.dot(basis.x), previous_basis.z.dot(basis.z)) / dt
	previous_pin = pin
	previous_basis = basis
	previous_speed = world_speed
	# Gravity changes direction in garment space when the wearer leans or falls over.
	var gravity := inverse * Vector3.DOWN - Vector3.DOWN
	var target := (-local_speed * 0.13 + gravity * 0.31).limit_length(0.80) * reach
	var target_turn := clampf(yaw_rate * 0.16, -0.9, 0.9) * reach * 2.7
	if at_rest and displacement.distance_squared_to(target) < 0.00000001 and absf(turn - target_turn) < 0.0005 and reverse_accel.length_squared() < 0.0001:
		return
	velocity += reverse_accel * (reach * 0.34)
	var damping := 16.0 if swimming else 10.0
	# Bounded timesteps keep the damped spring stable at low frame rates.
	var count := maxi(1, ceili(dt * 90.0))
	var h := dt / count
	for i in count:
		velocity += ((target - displacement) * 70.0 - damping * velocity) * h
		displacement = (displacement + velocity * h).limit_length(reach)
		turn_speed += ((target_turn - turn) * 80.0 - damping * turn_speed) * h
		turn = clampf(turn + turn_speed * h, -reach * 3.0, reach * 3.0)
	at_rest = displacement.distance_squared_to(target) < 0.00000001 and velocity.length_squared() < 0.0000001 and absf(turn - target_turn) + absf(turn_speed) < 0.001
	if at_rest:
		displacement = target
		turn = target_turn
		velocity = Vector3.ZERO
		turn_speed = 0.0
	apply_motion()

func apply_motion() -> void:
	if rigid:
		var swing := Basis.from_euler(Vector3(-displacement.z, turn * 0.2, displacement.x) * 4.0)
		var pose := rest_pose
		pose.basis = rest_pose.basis * swing
		pose.origin += rest_pose.basis * anchor - pose.basis * anchor
		piece.transform = pose
	else:
		material.set_shader_parameter("hem_motion", Vector4(displacement.x, displacement.y, displacement.z, turn))
