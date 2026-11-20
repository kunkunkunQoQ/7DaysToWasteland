extends RefCounted

const GROUP := &"april_creature_faces"
static var enabled := false
static var mesh: ArrayMesh

static func set_enabled(value: bool) -> void:
	enabled = value
	preload("res://game/art/species_faces.gd").set_april(value)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.call_group(GROUP, &"set_visible",enabled)

static func register(face: GeometryInstance3D) -> void:
	face.add_to_group(GROUP)
	face.visible = enabled
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func attach(parent: Node3D, at: Vector3, dimensions: Vector2, angles: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var face := MeshInstance3D.new()
	face.name = "AprilFace"
	face.mesh = make_mesh()
	face.position = at
	face.rotation = angles
	face.scale = Vector3(dimensions.x,dimensions.y,minf(dimensions.x,dimensions.y))
	parent.add_child(face)
	register(face)
	return face

static func make_mesh() -> ArrayMesh:
	if mesh != null:
		return mesh
	const SIDES := 26
	const RINGS := 7
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for row in RINGS + 1:
		var radius := maxf(0.0001,float(row)/RINGS)
		for i in SIDES + 1:
			var angle := TAU*i/SIDES
			var y := sin(angle)*radius
			var x := cos(angle)*radius*(0.82+0.18*smoothstep(-0.95,-0.15,y))
			var z := 0.19*radius*radius - 0.04
			z -= 0.13 * exp(-pow(x/0.17,2)-pow((y+0.05)/0.22,2))
			surface.set_uv(Vector2(0.5-x*0.49,0.5-y*0.49))
			surface.add_vertex(Vector3(x*0.5,y*0.5,z))
	for row in RINGS:
		for i in SIDES:
			var a := row*(SIDES+1)+i
			var b := a+SIDES+1
			for index in [a,b,b+1,a,b+1,a+1]:
				surface.add_index(index)
	surface.generate_normals()
	var painted := StandardMaterial3D.new()
	painted.albedo_texture = preload("res://assets/ranger_face.png")
	painted.cull_mode = BaseMaterial3D.CULL_DISABLED
	painted.roughness = 0.90
	surface.set_material(painted)
	mesh = surface.commit()
	return mesh
