extends Button

const Faces := preload("res://game/art/species_faces.gd")
var model: Node3D
var species: String
var morph: String
var variant: int

func setup(subject: Node3D, kind: String, form: String, face: int) -> void:
	name="FaceSelector"
	model=subject
	species=kind
	morph=form
	variant=face
	custom_minimum_size.y=42
	tooltip_text="切换这个变种的另一张面孔"
	refresh()
	pressed.connect(change_face)

func change_face() -> void:
	variant=1-variant
	if model is WastelandCreature:
		var actor:=model as WastelandCreature
		actor.face_variant=variant
		actor._rebuild_model()
		actor._pose(0.08,5.0)
	else:
		var face:=model.get_node("SpeciesFace") as MeshInstance3D
		face.material_override=Faces.material(species,morph,0,variant)
	refresh()

func refresh() -> void:
	if model is WastelandCreature: variant=model.face_variant
	text="面孔 %d/2"%[variant+1]
