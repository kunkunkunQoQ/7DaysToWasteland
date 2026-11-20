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
	for side in [Vector3.LEFT,Vector3.RIGHT]:
		fore.triangle(Vector3(0,0.096,-0.06),Vector3(0,0.20,0.06),Vector3(0,0.107,0.090),side,Color("#506f72"))
		hind.triangle(Vector3(0,0.107,-0.02),Vector3(0,0.18,-0.02),Vector3(0,0.075,0.12),side,Color("#58777a"))
		var shoulder: Vector3 = side*0.076+Vector3(0,-0.038,-0.085)
		for normal in [Vector3.UP,Vector3.DOWN]:
			fore.triangle(shoulder,shoulder+Vector3(0,-0.018,0.094),shoulder+side*0.075+Vector3(0,-0.070,0.12),normal,Color("#789491"))
	if mottled:
		for i in 2:
			fore.oval(Vector3(0,0.068,-0.14+i*0.12),Vector3(0.082,0.053,0.030),Color("#405f61"))
		hind.oval(Vector3(0,0.063,0.038),Vector3(0.076,0.042,0.024),Color("#405f61"))
	var fin := Sculpt.new(69)
	for normal in [Vector3.LEFT,Vector3.RIGHT]:
		fin.triangle(Vector3(0,0.036,-0.026),Vector3(0,0.17,0.25),Vector3(0,0.006,0.17),normal,Color("#718e89"))
		fin.triangle(Vector3(0,0.036,-0.026),Vector3(0,0.006,0.17),Vector3(0,-0.032,-0.026),normal,Color("#718e89"))
		fin.triangle(Vector3(0,-0.032,-0.026),Vector3(0,0.006,0.17),Vector3(0,-0.15,0.23),normal,Color("#628380"))
	forms[mottled] = [fore.commit(),hind.commit(),fin.commit()]
	return forms[mottled]

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

func _process(delta: float) -> void:
	phase += delta*6.8
	animate(phase,0.2)

