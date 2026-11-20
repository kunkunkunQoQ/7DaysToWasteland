extends RefCounted

const FACE := preload("res://assets/fusion-pixel-12px-zh-hans.ttf")
const TYPE_SIZE := 48

# All dimensions are metres in the plane of the board. Use the font shipped with the game
# for both measurement and drawing so a phone's fallback fonts cannot change the layout.
static func letter(parent: Node3D, words: String, center: Vector3, area: Vector2) -> Label3D:
	var rows := words.split("\n")
	var width := 1.0
	for row in rows:
		width = maxf(width,FACE.get_string_size(row,HORIZONTAL_ALIGNMENT_LEFT,-1,TYPE_SIZE).x)
	var text_height := FACE.get_height(TYPE_SIZE)*rows.size()
	var ink := Label3D.new()
	ink.name = "PaintedLetters"
	ink.font = FACE
	ink.text = words
	ink.font_size = TYPE_SIZE
	ink.outline_size = 1
	ink.line_spacing = 0
	ink.pixel_size = minf(area.x/(width+4),area.y/(text_height+4))
	ink.modulate = Color("#f3e4bd")
	ink.outline_modulate = Color("#494335")
	ink.double_sided = false
	ink.position = center
	ink.set_meta("print_area",area)
	parent.add_child(ink)
	return ink

static func facade(board: Node3D, words: String, width: float, condition: int, key: int) -> void:
	var enamel := Color("#3d574b")
	WastelandLook.box(board,Vector3(width-0.08,0.46,0.026),Vector3(0,0,0.095),enamel)
	var ink := letter(board,words,Vector3(0,0,0.119),Vector2(width*(0.52/0.56),0.38))
	if condition<1: return
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	# Exposed primer near the board edges and small flakes through individual brush strokes.
	# Leave the character shapes recognisable even on a heavily damaged station.
	for i in range(2+condition):
		var length := rng.randf_range(0.045,0.14)*width
		var x := rng.randf_range(-1,1)*(width-length-0.15)*0.5
		var y := rng.randf_range(0.165,0.205)*(1 if i%2==0 else -1)
		var scar := WastelandLook.box(board,Vector3(length,rng.randf_range(0.008,0.018),0.005),Vector3(x,y,0.113),Color("#946e50"))
		scar.rotation.z = rng.randf_range(-0.04,0.04)
	if condition>=2:
		var extent := FACE.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,TYPE_SIZE).x*ink.pixel_size
		for i in condition-1:
			var flake := WastelandLook.box(board,Vector3(rng.randf_range(0.075,0.14),0.009,0.004),
				Vector3(rng.randf_range(-0.38,0.38)*extent,rng.randf_range(-0.085,0.085),0.126),enamel)
			flake.rotation.z = rng.randf_range(-0.10,0.10)
