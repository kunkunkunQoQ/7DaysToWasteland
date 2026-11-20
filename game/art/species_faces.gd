extends RefCounted

const LAND_GROUP := &"species_face_heads"
const AQUATIC := ["lake_fish","heron","pond_turtle","crayfish"]
const SPECIAL := ["spitter","bloater","bulwark","rimecaller","sandrunner"]
const LAND_SHADER := preload("res://shaders/species_head.gdshader")
const PATCH_SHADER := preload("res://shaders/species_face_patch.gdshader")
static var atlases: Dictionary = {}
static var aquatic_paints: Dictionary = {}
static var curved_patch: ArrayMesh
static var april := false

# Local landmarks of the sculpted skull: eye height/depth, lateral separation
# from the centerline, vertical face radius and eye-to-nose distance.
const LANDMARKS := {
	"stag":[0.523,-0.294,0.105,0.128,0.224],
	"boar":[0.042,-0.257,0.158,0.18,0.363],
	"fox":[0.044,-0.096,0.078,0.108,0.178],
	"hare":[0.052,-0.071,0.058,0.085,0.052],
	"wolf":[0.061,-0.132,0.108,0.154,0.228],
	"badger":[0.042,-0.092,0.075,0.111,0.182],
	"argali":[0.027,-0.155,0.104,0.119,0.136],
	"jerboa":[0.011,-0.065,0.044,0.050,0.057],
	"otter":[0.021,-0.119,0.080,0.096,0.105]}
# Half the eye spacing, eye height and forward muzzle drop in portrait space.
const PORTRAIT := {
	"stag":Vector3(0.35,0.35,0.20), "boar":Vector3(0.26,0.28,0.20),
	"fox":Vector3(0.25,0.34,0.23), "hare":Vector3(0.31,0.33,0.15),
	"wolf":Vector3(0.24,0.30,0.28), "badger":Vector3(0.24,0.43,0.22),
	"argali":Vector3(0.33,0.34,0.24), "jerboa":Vector3(0.31,0.35,0.31),
	"otter":Vector3(0.30,0.35,0.03)}

static func _atlas(kind: String) -> Texture2D:
	if not atlases.has(kind):
		var path := "res://assets/creature_faces/%s.png" % kind
		if not ResourceLoader.exists(path):
			return null
		atlases[kind] = load(path)
	return atlases[kind]

static func _rect(kind: String, morph: String, look: int, face: int) -> Vector4:
	var special := kind in SPECIAL
	var columns := 6 if special else 2
	var rows := 2 if kind in AQUATIC else 3
	var row := 1 if morph in ["young","armored"] else 2 if morph in ["local","swift"] else 0
	var col := clampi(look,0,2)*2 if special else 0
	col += clampi(face,0,1)
	return Vector4(float(col)/columns,float(mini(row,rows-1))/rows,1.0/columns,1.0/rows)

static func _select_cell(paint: ShaderMaterial, kind: String, morph: String, look: int, face: int) -> void:
	var atlas := _atlas(kind)
	paint.set_shader_parameter("face_atlas",atlas)
	paint.set_shader_parameter("face_rect",_rect(kind,morph,look,face))
	paint.set_shader_parameter("has_atlas",atlas!=null)
	paint.set_shader_parameter("face_enabled",not april)

static func attach_land(actor: Node3D) -> void:
	var head := actor.body_parts.head.get_child(0) as MeshInstance3D
	var field: Array = LANDMARKS.get(actor.type,[0.144,-0.143,0.062,0.147,0.12])
	var paint := ShaderMaterial.new()
	paint.shader = LAND_SHADER
	_select_cell(paint,actor.type,actor.morph,actor.look_index,actor.face_variant)
	paint.set_shader_parameter("landmarks",Vector4(field[0],field[1],field[2],field[3]))
	paint.set_shader_parameter("snout_length",field[4])
	paint.set_shader_parameter("animal",LANDMARKS.has(actor.type))
	paint.set_shader_parameter("feral_eyes",actor.type=="feral_runner")
	paint.set_shader_parameter("portrait_marks",PORTRAIT.get(actor.type,Vector3(0.25,0.27,0.045)))
	var base: Color=Color.html(actor.spec.skin)
	if actor.type in SPECIAL:
		base=preload("res://game/art/infected_looks.gd").skin_for(actor.type,base)
	paint.set_shader_parameter("skin_tone",base)
	head.material_override = paint
	head.set_meta("species_face",true)
	head.add_to_group(LAND_GROUP)
	actor.render_colors["species_face"] = paint

# Aquatic meshes may supply their own 0..1 facial UVs or use the cap below.
static func material(kind: String, morph: String, look: int, face: int) -> ShaderMaterial:
	var key := "%s/%s/%d/%d" % [kind,morph,look,face]
	if not aquatic_paints.has(key):
		var paint := ShaderMaterial.new()
		paint.shader = PATCH_SHADER
		_select_cell(paint,kind,morph,look,face)
		if paint.get_shader_parameter("has_atlas"):
			aquatic_paints[key] = paint
		return paint
	return aquatic_paints[key]

static func set_april(value: bool) -> void:
	april = value
	for paint: ShaderMaterial in aquatic_paints.values():
		paint.set_shader_parameter("face_enabled",not value)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for head: MeshInstance3D in tree.get_nodes_in_group(LAND_GROUP):
			head.material_override.set_shader_parameter("face_enabled",not value)

static func attach_aquatic(parent: Node3D,kind: String,morph: String,face: int,center: Vector3,radii: Vector3) -> MeshInstance3D:
	var patch := MeshInstance3D.new()
	patch.name = "SpeciesFace"
	patch.mesh = aquatic_mesh()
	patch.position = center
	patch.scale = radii
	patch.material_override = material(kind,morph,0,face)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.set_meta("species_face",true)
	parent.add_child(patch)
	return patch

static func aquatic_mesh() -> ArrayMesh:
	if curved_patch:
		return curved_patch
	const COLUMNS := 18
	const ROWS := 12
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in ROWS+1:
		var v := float(j)/ROWS
		var latitude := lerpf(1.18,-1.18,v)
		for i in COLUMNS+1:
			var u := float(i)/COLUMNS
			var longitude := lerpf(-1.40,1.40,u)
			var normal := Vector3(-sin(longitude)*cos(latitude),sin(latitude),-cos(longitude)*cos(latitude))
			cap.set_normal(normal)
			cap.set_uv(Vector2(u,v))
			cap.add_vertex(normal)
	for j in ROWS:
		for i in COLUMNS:
			var a := j*(COLUMNS+1)+i
			var c := a+COLUMNS+1
			for index in [a,a+1,c,c,a+1,c+1]:
				cap.add_index(index)
	curved_patch=cap.commit()
	return curved_patch
