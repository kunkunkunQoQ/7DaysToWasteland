class_name WastelandLook
extends RefCounted

const SHADOW := Color("#30243e")
const PAL := [
	"0c0b16","151324","1d192e","272139","342945","40334f","503d5a","614c68","74607d","897593","a08ba6","b7a2b5","d0bfcb",
	"171e34","1e2b43","2a3b54","304968","3b5b79","4d7391","658da5","86a2bd","a8b9ce","ccd1e1",
	"163133","1d4446","245858","336b68","41867f","55a699","70b9a7","98d3bf","bce4d1",
	"292c27","3e4331","555438","686343","7e754a","8d8757","a6a06b","b5b880","cbd29c",
	"2a202a","4b2b33","663c46","7d4a50","98595d","af6e6d","c58481","db9a93","ecb1a7","f4c4b5",
	"3a1e2d","5a2639","7e2d49","a3354a","bf4653","d95761","ed7275","ffa5a1",
	"3c292a","53362d","6a4735","835938","9f6a3f","b47c4a","d49655","e7ae63","f5c079","ffd594","ffe5b4","fff4d3",
	"39353c","50505a","64656a","7b7d82","949399","b1b2b1","d0cbc3","eee4d6","fff9ee",
	"453b3e","594b46","6e5c52","816d60","958173","a99382","bda994","d6c0a4",
	"3b3046","4b3c58","5b4968","6d5778","856687","a17a98","bc95a9","d7aebd",
	"513c43","644b4d","785b58","906b63","ac8070","c49682","dca891","edc2a3",
]
static var materials: Dictionary = {}
static var unit_box: BoxMesh
static var water_plane: PlaneMesh
static var lookup: ImageTexture
static var shaped_meshes: Dictionary = {}
static var shaped_faces: Dictionary = {}

static func matte(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := color.to_html() + "/" + str(glow)
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.roughness = 0.96
		if glow > 0.0:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = glow
		materials[key] = mat
	return materials[key]

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	if unit_box == null:
		unit_box = BoxMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = unit_box
	instance.position = at
	instance.scale = size
	instance.material_override = matte(color, glow)
	parent.add_child(instance)
	return instance

static func form(parent: Node3D, size: Vector3, at: Vector3, color: Color, rounding: float = 0.12) -> MeshInstance3D:
	var instance := box(parent,size,at,color)
	instance.mesh = _rounded_cube(rounding)
	return instance

static func _rounded_cube(radius: float) -> ArrayMesh:
	var key := roundi(radius*1000.0)
	if shaped_meshes.has(key):
		return shaped_meshes[key]
	var builder := WastelandScenery.new(0)
	var edge := 0.5-radius
	var span := [-0.5,-edge,edge,0.5]
	for orientation in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
		var facing: Vector3 = orientation
		var reference := Vector3.FORWARD if absf(facing.y)>0.5 else Vector3.UP
		var axis := facing.cross(reference)
		var cross := facing.cross(axis)
		for x in range(3):
			for y in range(3):
				var a := _round_corner(facing*0.5+axis*span[x]+cross*span[y],edge,radius)
				var b := _round_corner(facing*0.5+axis*span[x+1]+cross*span[y],edge,radius)
				var c := _round_corner(facing*0.5+axis*span[x]+cross*span[y+1],edge,radius)
				var d := _round_corner(facing*0.5+axis*span[x+1]+cross*span[y+1],edge,radius)
				builder.triangle(a,b,c,facing,Color.WHITE)
				builder.triangle(b,d,c,facing,Color.WHITE)
	var mesh := builder.commit()
	shaped_meshes[key]=mesh
	shaped_faces[key]=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return mesh

static func _round_corner(point: Vector3, edge: float, radius: float) -> Vector3:
	var core := point.clampf(-edge,edge)
	return core+(point-core).normalized()*radius

static func collider(body: CollisionObject3D, size: Vector3, at: Vector3) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	node.position = at
	body.add_child(node)
	return node

static func solid(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	parent.add_child(body)
	body.position = at
	box(body, size, Vector3.ZERO, color)
	collider(body, size, Vector3.ZERO)
	return body

static func mesh_parts(parts: Array, roundness: float = 0.0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var poses := PackedVector3Array()
	if roundness > 0.0:
		_rounded_cube(roundness)
		poses = shaped_faces[roundi(roundness*1000.0)]
	for part in parts:
		var center: Vector3 = part[0]
		var size: Vector3 = part[1]
		var color: Color = part[2]
		var basis: Basis = part[3] if part.size() > 3 else Basis.IDENTITY
		var top: float = part[4] if part.size() > 4 else 1.0
		if not poses.is_empty() and top == 1.0:
			for point in poses:
				surface.set_color(color)
				surface.set_uv(Vector2(point.x+point.z+0.5,point.y+point.z+0.5))
				surface.add_vertex(center + basis*(point*size))
			continue
		var points := PackedVector3Array()
		for p in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,-1,1),Vector3(-1,-1,1),Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(1,1,1),Vector3(-1,1,1)]:
			var point: Vector3 = p * size * 0.5
			if p.y > 0.0:
				point *= Vector3(top, 1.0, top)
			points.append(center + basis * point)
		var faces := [[0,1,2,3],[7,6,5,4],[4,5,1,0],[1,5,6,2],[2,6,7,3],[3,7,4,0]]
		for face in faces:
			for i in [0,2,1,0,3,2]:
				surface.set_color(color)
				surface.set_uv([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN][i])
				surface.add_vertex(points[face[i]])
	surface.generate_normals()
	return surface.commit()

static func colored_material() -> StandardMaterial3D:
	if not materials.has("vertex"):
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.97
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		materials["vertex"] = mat
	return materials["vertex"]

static func instanced(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	instance.multimesh = multimesh
	instance.material_override = colored_material()
	parent.add_child(instance)
	return instance

static func palette() -> ImageTexture:
	if lookup != null:
		return lookup
	var colors: Array[Color] = []
	for hex in PAL:
		colors.append(Color.html(hex))
	var image := Image.create_empty(32, 256, false, Image.FORMAT_RGBA8)
	for z in 16:
		for y in 16:
			for x in 16:
				var sample := Vector3(x + 0.5, y + 0.5, z + 0.5) / 16.0
				var best := INF
				var next := INF
				var first := Color.BLACK
				var second := Color.BLACK
				for color in colors:
					var v := sample - Vector3(color.r, color.g, color.b)
					var difference := v.dot(v * Vector3(0.96, 1.28, 0.86))
					if difference < best:
						next = best
						second = first
						best = difference
						first = color
					elif difference < next:
						next = difference
						second = color
				var a := Vector3(first.r, first.g, first.b)
				var b := Vector3(second.r, second.g, second.b)
				var fraction := (sample - a).dot(b - a) / maxf(0.00001, a.distance_squared_to(b))
				var blend := 1.0 - smoothstep(0.14, 0.29, a.distance_to(b))
				first.a = clampf(fraction * 0.68 * blend, 0.0, 0.39)
				image.set_pixel(x, y + z * 16, first)
				image.set_pixel(x + 16, y + z * 16, second)
	lookup = ImageTexture.create_from_image(image)
	return lookup
