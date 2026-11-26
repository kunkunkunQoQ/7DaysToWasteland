extends Node3D

const Sculpt := WastelandBestiary.Sculpture
const Faces := preload("res://game/art/species_faces.gd")
const April := preload("res://game/art/april_face.gd")
const SKULL := Vector3(0,0.005,-0.160)
const RADII := Vector3(0.093,0.106,0.182)
const MASK_AT := Vector3(0,0.014,-0.319)
const MASK_SIZE := Vector2(0.227,0.244)
const SPINE := Vector3(0,0,0.070)
const PEDUNCLE := Vector3(0,0,0.180)

static var forms := {}
static var physical_forms := {}
const SEGMENTS := ["FishBody", "Spine", "Tail", "PectoralL", "PectoralR", "DorsalFront", "DorsalRear"]
const PARENTS := [-1, 0, 1, 0, 0, 0, 1]
const PIVOTS := [Vector3.ZERO, SPINE, PEDUNCLE, Vector3(-0.076,-0.038,-0.085), Vector3(0.076,-0.038,-0.085), Vector3(0,0.10,-0.018), Vector3(0,0.105,0.028)]
var spine := MeshInstance3D.new()
var tail := MeshInstance3D.new()
var phase := 0.0

static func geometry(mottled: bool) -> Array:
	if forms.has(mottled): return forms[mottled]
	var side_color := Color("#75968c") if mottled else Color("#c3d9ce")
	var along := Basis(Vector3.RIGHT,PI/2.0)
	var fore := Sculpt.new(68)
	fore.loft([Vector4(-0.33,0.012,0.022,0),Vector4(-0.25,0.069,0.086,0),Vector4(-0.12,0.095,0.117,0),Vector4(0.025,0.096,0.122,0),Vector4(0.080,0.089,0.110,0),Vector4(0.117,0.066,0.079,0)],side_color,Vector3.ZERO,along)
	var hind := Sculpt.new(70)
	hind.loft([Vector4(-0.044,0.073,0.093,0),Vector4(0.012,0.089,0.110,0),Vector4(0.096,0.072,0.086,0),Vector4(0.174,0.032,0.047,0),Vector4(0.211,0.018,0.032,0)],side_color,Vector3.ZERO,along)
	if mottled:
		for i in 2:
			fore.oval(Vector3(0,0.068,-0.14+i*0.12),Vector3(0.082,0.053,0.030),Color("#405f61"))
		hind.oval(Vector3(0,0.063,0.038),Vector3(0.076,0.042,0.024),Color("#405f61"))
	var fore_core := fore.commit()
	var hind_core := hind.commit()
	var fin_parts := [Sculpt.new(68), Sculpt.new(68), Sculpt.new(68), Sculpt.new(70)]
	for side in [Vector3.LEFT,Vector3.RIGHT]:
		_fin_triangle(fore,fin_parts[2],PIVOTS[5],Vector3(0,0.096,-0.06),Vector3(0,0.20,0.06),Vector3(0,0.107,0.090),side,Color("#506f72"))
		_fin_triangle(hind,fin_parts[3],PIVOTS[6],Vector3(0,0.107,-0.02),Vector3(0,0.18,-0.02),Vector3(0,0.075,0.12),side,Color("#58777a"))
		var shoulder: Vector3 = side*0.076+Vector3(0,-0.038,-0.085)
		for normal in [Vector3.UP,Vector3.DOWN]:
			_fin_triangle(fore,fin_parts[0 if side == Vector3.LEFT else 1],shoulder,shoulder,shoulder+Vector3(0,-0.018,0.094),shoulder+side*0.075+Vector3(0,-0.070,0.12),normal,Color("#789491"))
	var fin := Sculpt.new(69)
	for normal in [Vector3.LEFT,Vector3.RIGHT]:
		fin.triangle(Vector3(0,0.036,-0.026),Vector3(0,0.17,0.25),Vector3(0,0.006,0.17),normal,Color("#718e89"))
		fin.triangle(Vector3(0,0.036,-0.026),Vector3(0,0.006,0.17),Vector3(0,-0.032,-0.026),normal,Color("#718e89"))
		fin.triangle(Vector3(0,-0.032,-0.026),Vector3(0,0.006,0.17),Vector3(0,-0.15,0.23),normal,Color("#628380"))
	forms[mottled] = [fore.commit(),hind.commit(),fin.commit()]
	physical_forms[mottled] = [fore_core, hind_core, forms[mottled][2]]
	for part in fin_parts: physical_forms[mottled].append(part.commit())
	return forms[mottled]

static func _fin_triangle(whole: Sculpt, fin: Sculpt, pivot: Vector3, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	whole.triangle(a, b, c, normal, color)
	fin.triangle(a - pivot, b - pivot, c - pivot, normal, color)

static func spine_transform(beat: float, effort: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,sin(beat)*(0.24+0.16*effort)),SPINE)

static func tail_transform(beat: float, effort: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,sin(beat-0.98)*(0.55+0.32*effort)),PEDUNCLE)

func build(form: String, variant: int) -> void:
	var meshes := geometry(form=="local")
	var front := MeshInstance3D.new()
	add_child(front)
	add_child(spine)
	spine.add_child(tail)
	var segments := [front,spine,tail]
	for i in 3:
		segments[i].mesh = meshes[i]
		segments[i].material_override = WastelandLook.colored_material()
	Faces.attach_aquatic(self,"lake_fish",form,variant,SKULL,RADII)
	April.attach(self,MASK_AT,MASK_SIZE)
	animate(0,0)

func animate(beat: float, effort: float) -> void:
	spine.transform = spine_transform(beat,effort)
	tail.transform = tail_transform(beat,effort)

# The school draws these segments in batches using the same bones as an individual fish.
func build_physical(form: String, variant: int, beat: float, effort: float) -> Skeleton3D:
	set_process(false)
	var skeleton := Skeleton3D.new()
	add_child(skeleton)
	geometry(form == "local")
	var meshes: Array = physical_forms[form == "local"]
	for i in SEGMENTS.size():
		var label: String = SEGMENTS[i]
		skeleton.add_bone(label)
		skeleton.set_bone_parent(i, PARENTS[i])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, PIVOTS[i]))
		skeleton.reset_bone_pose(i)
		var bone := BoneAttachment3D.new()
		bone.bone_name = label
		skeleton.add_child(bone)
		var piece := spine if i == 1 else tail if i == 2 else MeshInstance3D.new()
		bone.add_child(piece)
		piece.mesh = meshes[i]
		piece.material_override = WastelandLook.colored_material()
		if i == 0:
			Faces.attach_aquatic(bone, "lake_fish", form, variant, SKULL, RADII)
			April.attach(bone, MASK_AT, MASK_SIZE)
	pose_physical(skeleton, beat, effort)
	return skeleton

static func pose_physical(skeleton: Skeleton3D, beat: float, effort: float) -> void:
	skeleton.set_bone_pose(1, spine_transform(beat, effort))
	skeleton.set_bone_pose(2, tail_transform(beat, effort))
	for i in [3, 4]:
		var fan := (0.12 + 0.15 * effort) * sin(beat + PI * (i - 3))
		skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.FORWARD, fan))
	for i in [5, 6]:
		skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.BACK, (0.06 + effort * 0.08) * sin(beat - 0.7 * (i - 4))))

func _process(delta: float) -> void:
	phase += delta*6.8
	animate(phase,0.2)

