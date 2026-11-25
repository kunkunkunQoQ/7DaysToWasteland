extends RefCounted

const FACE := preload("res://assets/fusion-pixel-12px-zh-hans.ttf")
const TYPE_SIZE := 48
const ENAMELS := {
	"lodge":Color("#355e58"), "cabin":Color("#4e6249"), "granary":Color("#71603d"),
	"police":Color("#354c66"), "bunker":Color("#505951"), "tower":Color("#485d67"),
	"fuel":Color("#864839"), "post":Color("#754746"), "hospital":Color("#475f59"),
	"garage":Color("#3c575a")
}
static var paints := {}
static var capitals: FontVariation

# All dimensions are metres in the plane of the board. Use the font shipped with the game
# for both measurement and drawing so a phone's fallback fonts cannot change the layout.
static func letter(parent: Node3D, words: String, center: Vector3, area: Vector2, typeface: Font = FACE) -> Label3D:
	var rows := words.split("\n")
	var width := 1.0
	for row in rows:
		width = maxf(width,typeface.get_string_size(row,HORIZONTAL_ALIGNMENT_LEFT,-1,TYPE_SIZE).x)
	var text_height := typeface.get_height(TYPE_SIZE)*rows.size()
	var ink := Label3D.new()
	ink.name = "PaintedLetters"
	ink.font = typeface
	ink.text = words
	ink.font_size = TYPE_SIZE
	ink.outline_size = 1
	ink.line_spacing = 0
	ink.pixel_size = minf(area.x/(width+4),area.y/(text_height+4))
	ink.modulate = Color("#e6d6af")
	ink.outline_modulate = Color("#494335")
	ink.double_sided = false
	ink.position = center
	ink.set_meta("print_area",area)
	parent.add_child(ink)
	return ink

static func enamel(visual: MeshInstance3D, color: Color, condition: int, key: int) -> void:
	var variation := posmod(key,4)
	var paint_key := [color,condition,variation]
	if not paints.has(paint_key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/sign_enamel.gdshader")
		material.set_shader_parameter("enamel",color)
		material.set_shader_parameter("wear",0.32 + condition * 0.19)
		material.set_shader_parameter("variation",float(variation))
		paints[paint_key] = material
	visual.material_override = paints[paint_key]

static func facade(board: Node3D, words: String, width: float, condition: int, key: int, site: String) -> void:
	var color: Color = ENAMELS[site]
	var panel := WastelandLook.box(board,Vector3(width-0.08,0.46,0.026),Vector3(0,0,0.095),color)
	enamel(panel,color,condition,key)
	if not capitals:
		capitals = FontVariation.new()
		capitals.base_font = FACE
		capitals.variation_embolden = 0.85
		# Single-line capitals have no descenders. Fill the enamel strip with the letterforms.
		capitals.spacing_top = -8
		capitals.spacing_bottom = -8
	var ink := letter(board,words,Vector3(0,0,0.119),Vector2(width*(0.52/0.56),0.38),capitals)
	ink.modulate = Color("#eadebf").lerp(Color("#cfc3a6"),condition*0.14)
	ink.outline_modulate = color.darkened(0.32)
