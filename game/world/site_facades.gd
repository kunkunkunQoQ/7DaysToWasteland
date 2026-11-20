extends RefCounted

# Each wall bay is still one removable facade. Identical bays share geometry
# and collision across chunks, including the four rotations of the building.
static var models: Dictionary = {}

const IVORY := Color("#d9cbb0")
const STEEL := Color("#48565b")
const RUST := Color("#9a6850")
const RED := Color("#995448")
const GREEN := Color("#54786c")
const TIMBER := Color("#75553c")

static func bay(chunk: WastelandChunk, point: Vector3, orientation: Basis, width: float,
		level: int, side: int, index: int, floors: int, tint: Color, trim: Color, door: bool, window: bool) -> void:
	var style := chunk.site
	if style == "lodge" and chunk.cell != WastelandSite.SHORE_CELL:
		style = "outpost"
	var crown := level == floors - 1
	var corner := index in [0, 4]
	var hand := -1 if index < 2 else 1
	var front := side == 0
	var key := [style, width, crown, corner, hand, front, door, window, index == 2, tint, trim]
	if not models.has(key):
		var parts: Array = []
		var apron := trim.darkened(0.13)
		var timber := style in ["lodge", "outpost", "cabin"]
		parts.append([Vector3(0, 2.94, 0), Vector3(width + 0.012, 0.12, 0.10), apron])
		if door:
			for x: int in [-1, 1]:
				parts.append([Vector3(x * width * 0.46, 1.29, 0.035), Vector3(0.106, 2.58, 0.085), trim])
			parts.append([Vector3(0, 2.65, 0.02), Vector3(width * 0.99, 0.14, 0.12), trim.lightened(0.12)])
		elif window:
			for x: int in [-1, 1]:
				parts.append([Vector3(x * (width * 0.5 - 0.065), 1.58, 0.03), Vector3(0.105, 1.13, 0.11), apron])
			parts.append([Vector3(0, 1.045, 0.07), Vector3(width - 0.01, 0.10, 0.27), trim])
			parts.append([Vector3(0, 2.13, 0.03), Vector3(width, 0.10, 0.16), trim])
		if timber:
			_timber(parts, style, width, tint, door, window, corner, hand)
		else:
			_masonry(parts, style, width, door, window, crown, corner, hand, front, index == 2)
		var solid_count := parts.size()
		_room_face(parts,style,width,door,window,corner,hand,tint)
		var mesh := preload("res://game/world/building_mesh.gd").boxes(parts)
		var volume := 0.0
		for i in solid_count:
			var size: Vector3 = parts[i][1]
			volume += size.x * size.y * size.z
		models[key] = {"mesh":mesh, "volume":volume, "solid_count":solid_count}
	var model: Dictionary = models[key]
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.transform = Transform3D(orientation, point)
	chunk.poi_root.add_child(body)
	body.set_meta("salvage_volume", model.volume)
	var image := MeshInstance3D.new()
	image.mesh = model.mesh
	image.material_override = WastelandLook.colored_material()
	body.add_child(image)
	if not chunk.stream.is_preview:
		if not model.has("shape"):
			var shape := ConcavePolygonShape3D.new()
			# The index buffer expands to 36 collision points per box. Interior paint and
			# millimetre-thick liners share the rendering surface only.
			shape.set_faces(image.mesh.get_faces().slice(0,36 * int(model.solid_count)))
			shape.backface_collision = true
			model.shape = shape
		var collision := CollisionShape3D.new()
		collision.shape = model.shape
		body.add_child(collision)
		chunk.obstacles.append(body)
	chunk.track_structure(body, "wall/%d/%d/%d" % [level, side, index], 205 if style in ["lodge","outpost","cabin"] else 480)

static func _timber(parts: Array, style: String, width: float, tint: Color, door: bool, window: bool, corner: bool, hand: int) -> void:
	var paint := Color("#517b82") if style == "lodge" else GREEN if style == "outpost" else Color("#916443")
	if door:
		parts.append([Vector3(0, 2.79, 0.06), Vector3(width, 0.14, 0.19), paint])
		return
	# Overlapping weatherboards alternate pale exposed timber and old paint.
	for course in 7:
		var y := 0.24 + course * 0.415
		if window and y > 1.02 and y < 2.16: continue
		var shade := tint.lerp(TIMBER, 0.12 + 0.09 * (course % 3))
		parts.append([Vector3(0, y, -0.005), Vector3(width - 0.014, 0.405, 0.059), shade, Basis(Vector3.RIGHT, -0.06)])
	if corner:
		parts.append([Vector3(hand * (width * 0.5 - 0.11), 1.49, 0.075), Vector3(0.19, 2.91, 0.14), paint])
	if window:
		# Remnants of a hinged shutter stay attached to a jamb; the opening reads through to the room.
		var x := hand * (width * 0.5 - 0.245)
		parts.append([Vector3(x, 1.58, 0.085), Vector3(0.36, 0.92, 0.10), paint])
		for y: float in [1.26, 1.88]:
			parts.append([Vector3(x, y, 0.144), Vector3(0.36, 0.072, 0.028), TIMBER.darkened(0.24)])
		if style == "cabin":
			parts.append([Vector3(0, 2.21, 0.11), Vector3(width, 0.10, 0.37), TIMBER, Basis(Vector3.RIGHT, 0.12)])
		else:
			parts.append([Vector3(0, 1.89, 0), Vector3(width - 0.15, 0.063, 0.085), paint])

static func _masonry(parts: Array, style: String, width: float, door: bool, window: bool,
		crown: bool, corner: bool, hand: int, front: bool, middle: bool) -> void:
	match style:
		"hospital":
			parts.append([Vector3(0, 0.76 if not door else 2.78, 0.018), Vector3(width, 0.22, 0.075), GREEN])
			if window:
				var slope := Basis(Vector3.RIGHT, 0.15)
				parts.append([Vector3(0, 2.29, 0.19), Vector3(width - 0.06, 0.10, 0.52), IVORY, slope])
				for x: int in [-1, 1]:
					parts.append([Vector3(x * width * 0.36, 2.18, 0.12), Vector3(0.055, 0.067, 0.35), GREEN, Basis(Vector3.RIGHT, -0.48)])
			if crown: _coping(parts, width, 0.25, IVORY)
		"police":
			parts.append([Vector3(0, 2.79, 0.022), Vector3(width, 0.23, 0.10), Color("#3a5068")])
			if window:
				for bar in 4:
					parts.append([Vector3((bar - 1.5) * width * 0.195, 1.58, 0.045), Vector3(0.048, 1.05, 0.07), STEEL])
				parts.append([Vector3(0, 1.54, 0.065), Vector3(width - 0.12, 0.06, 0.08), STEEL])
			elif corner and not door:
				parts.append([Vector3(hand * (width * 0.5 - 0.16), 1.52, 0), Vector3(0.29, 2.91, 0.23), Color("#778595")])
			if crown: _coping(parts, width, 0.30, STEEL)
		"bunker":
			if corner and not door:
				parts.append([Vector3(hand * width * 0.31, 1.4, 0.10), Vector3(0.49, 2.77, 0.40), Color("#627368"), Basis.IDENTITY, 0.72])
			if door or crown:
				parts.append([Vector3(0, 2.83, 0.027), Vector3(width, 0.15, 0.14), STEEL])
			if crown: _coping(parts, width, 0.19, Color("#677b72"))
		"tower":
			if crown:
				parts.append([Vector3(0, 2.98, 0.065), Vector3(width, 0.21, 0.29), Color("#b19676")])
			if window:
				parts.append([Vector3(0, 1.83, -0.035), Vector3(width - 0.12, 0.067, 0.077), STEEL])
			elif not door:
				var brace := Basis(Vector3.BACK, -hand * atan2(width * 0.79, 2.6))
				parts.append([Vector3(0, 1.55, 0.047), Vector3(0.14, Vector2(width * 0.79, 2.6).length(), 0.13), STEEL, brace])
		"fuel":
			parts.append([Vector3(0, 2.80, 0.017), Vector3(width, 0.22, 0.09), RED])
			if window:
				parts.append([Vector3(0, 2.20, 0.13), Vector3(width, 0.11, 0.35), IVORY])
			if crown: _coping(parts, width, 0.15, IVORY)
		"granary":
			if window:
				for slat in 4:
					parts.append([Vector3(0, 1.21 + slat * 0.24, 0.023), Vector3(width - 0.14, 0.12, 0.16), TIMBER, Basis(Vector3.RIGHT, 0.24)])
			elif not door:
				for i in 3:
					parts.append([Vector3((i - 1) * width * 0.35, 1.49, 0.018), Vector3(0.077, 2.85, 0.105), Color("#967a50")])
			if crown: _coping(parts, width, 0.19, TIMBER)
		"garage":
			if front and corner and not door:
				parts.append([Vector3(0, 1.41, 0.011), Vector3(width - 0.20, 2.42, 0.085), STEEL])
				for slat in 6:
					parts.append([Vector3(0, 0.42 + slat * 0.39, 0.065), Vector3(width - 0.22, 0.066, 0.064), Color("#778588")])
			elif window:
				parts.append([Vector3(0, 1.72, 0), Vector3(width, 0.08, 0.075), STEEL])
			if crown: _coping(parts, width, 0.17, RUST)
		"post":
			if window:
				parts.append([Vector3(0, 1.86, -0.012), Vector3(width - 0.13, 0.062, 0.085), RED])
				parts.append([Vector3(0, 2.22, 0.025), Vector3(width, 0.14, 0.24), IVORY])
			if corner and not door:
				for course in 4:
					parts.append([Vector3(hand * (width * 0.5 - 0.16), 0.37 + course * 0.69, 0.016), Vector3(0.31, 0.28, 0.15), IVORY.darkened(0.10)])
			if crown:
				var rise := (0.62 if middle else 0.36) if front and not corner else 0.17
				_coping(parts, width, rise, RED)

static func _coping(parts: Array, width: float, rise: float, tone: Color) -> void:
	parts.append([Vector3(0, 3.03 + rise * 0.5, -0.045), Vector3(width, rise, 0.23), tone.darkened(0.09)])
	parts.append([Vector3(0, 3.06 + rise, -0.045), Vector3(width, 0.07, 0.31), tone])

static func _room_face(parts: Array, style: String, width: float, door: bool, window: bool, corner: bool, hand: int, tint: Color) -> void:
	# The outside face of a structural bay is at 0; the inside face is -0.317.
	# Paint below sill height stays continuous past a window and ends at each door.
	var inner := -0.325
	var liner: Color
	var rail: Color
	match style:
		"lodge","outpost","cabin":
			liner = tint.lerp(TIMBER,0.37)
			rail = Color("#5b4639")
		"hospital":
			liner = Color("#99ada0")
			rail = Color("#4f766e")
		"police":
			liner = Color("#748792")
			rail = Color("#435767")
		"bunker":
			liner = Color("#69766a")
			rail = Color("#ac9d66")
		"fuel","garage":
			liner = Color("#707c78")
			rail = RED if style == "fuel" else Color("#b79b61")
		"post","granary":
			liner = Color("#9e8061")
			rail = Color("#755941")
		_:
			liner = tint.darkened(0.08)
			rail = STEEL
	if door:
		parts.append([Vector3(0,2.66,inner),Vector3(width - 0.03,0.12,0.038),rail])
		return
	parts.append([Vector3(0,0.55,inner),Vector3(width - 0.012,0.87,0.028),liner])
	parts.append([Vector3(0,0.20,inner - 0.020),Vector3(width,0.16,0.038),rail.darkened(0.17)])
	parts.append([Vector3(0,0.96,inner - 0.038),Vector3(width,0.093,0.078),rail])
	if style in ["lodge","outpost","cabin","post","granary"]:
		for x in 3:
			parts.append([Vector3((x - 1) * width * 0.32,0.58,inner - 0.019),Vector3(0.028,0.64,0.019),rail])
	elif style in ["garage","bunker","tower"] and corner:
		# A junction box and exposed conduit follow the edge of the intact wall.
		var x := hand * width * 0.34
		parts.append([Vector3(x,2.00,inner - 0.019),Vector3(0.048,1.82,0.063),STEEL])
		parts.append([Vector3(x,1.38,inner - 0.036),Vector3(0.23,0.31,0.095),rail])
	if corner or (window and hand < 0):
		# Two adjoining irregular chips expose the substrate where the paint ends.
		var patch := Vector3(hand * width * 0.28,0.36 if corner else 0.76,inner - 0.018)
		var substrate := tint.lerp(Color("#a3927e"),0.53)
		parts.append([patch,Vector3(0.30,0.09,0.010),substrate,Basis(Vector3.BACK,hand * 0.08),0.63])
		parts.append([patch + Vector3(hand * 0.14,-0.01,0),Vector3(0.12,0.042,0.012),substrate,Basis.IDENTITY,0.47])
	if window:
		parts.append([Vector3(0,1.05,inner),Vector3(width - 0.06,0.078,0.21),liner.lightened(0.12)])

# Low roofs can be seen from the road. Each assembly stays within the footprint
# of its own deck panel so a missing bay takes exactly that rooflight or vent.
static func roof_plant(chunk: WastelandChunk, center: Vector3, span: float, floors: int) -> void:
	if chunk.site not in ["granary", "garage"]: return
	for bay_index: int in ([2, 3] if chunk.site == "garage" else [3]):
		var id := "roof/plate/1/%d" % bay_index
		if not chunk.structures.has(id): continue
		var base := center + Vector3(0, floors * 3.05 + 0.135, (bay_index - 2) * span * 0.2)
		var parts: Array = []
		if chunk.site == "garage":
			# A shed roof with a broken vertical strip of wired glass.
			var depth := 1.65
			var height := 0.91
			parts.append([base + Vector3(0, 0.10, 0), Vector3(4.25, 0.20, depth), STEEL])
			var cap := Basis(Vector3.RIGHT, atan2(height, depth))
			parts.append([base + Vector3(0, 0.21 + height * 0.5, 0), Vector3(4.40, 0.11, Vector2(depth, height).length() + 0.10), RUST, cap])
			for x in 5:
				var jamb := base + Vector3((x - 2) * 1.04, 0.66, -depth * 0.5)
				parts.append([jamb, Vector3(0.082, height, 0.10), STEEL])
				if x < 4 and x != (bay_index % 3):
					parts.append([jamb + Vector3.RIGHT * 0.52, Vector3(0.97, 0.77, 0.042), Color("#76908f")])
		else:
			# A capped grain-dust exhaust with a skirt, tapered hood and louvres.
			parts.append([base + Vector3.UP * 0.21, Vector3(1.72, 0.42, 1.42), STEEL, Basis.IDENTITY, 0.78])
			for x: int in [-1, 1]:
				for z: int in [-1, 1]:
					parts.append([base + Vector3(x * 0.62, 0.79, z * 0.48), Vector3(0.10, 0.78, 0.10), TIMBER])
			for row in 3:
				parts.append([base + Vector3.UP * (0.49 + row * 0.24), Vector3(1.42, 0.16, 1.12), STEEL.lightened(0.12), Basis.IDENTITY, 0.87])
			parts.append([base + Vector3.UP * 1.29, Vector3(1.81, 0.40, 1.48), RUST, Basis.IDENTITY, 0.35])
		var unit := WastelandSite._cluster(chunk,id,parts,320)
		unit.set_meta("salvage_material","scrap")

# Dress a simple collider without spawning another mesh instance. Keep the
# underlying timber/metal volume accessible to structural salvage.
static func clad_box(body: StaticBody3D, parts: Array) -> void:
	var image: MeshInstance3D = body.get_child(0)
	var size := image.scale
	var tone: Color = image.material_override.albedo_color
	var local := [[Vector3.ZERO, size, tone]]
	local.append_array(parts)
	image.transform = Transform3D.IDENTITY
	image.mesh = preload("res://game/world/building_mesh.gd").boxes(local)
	image.material_override = WastelandLook.colored_material()
	if not body.has_meta("salvage_volume"):
		body.set_meta("salvage_volume",size.x * size.y * size.z)

static func dock_plank(body: StaticBody3D, index: int) -> void:
	var size: Vector3 = body.get_child(0).scale
	var depth := size.z
	var parts: Array = []
	# Inset nail heads and split grain read at walking distance.
	var hand := 1 if index % 2 == 0 else -1
	for x: int in [-1, 1]:
		parts.append([Vector3(x * (size.x * 0.5 - 0.16), size.y * 0.5 + 0.006, hand * depth * 0.18), Vector3(0.048, 0.019, 0.049), STEEL])
	var crack := Vector3(hand * size.x * 0.31, size.y * 0.5 + 0.003, -hand * depth * 0.24)
	parts.append([crack, Vector3(size.x * 0.36, 0.009, 0.019), TIMBER.darkened(0.18), Basis(Vector3.UP, hand * 0.027)])
	clad_box(body,parts)

static func dock_pile(body: StaticBody3D, mooring: bool) -> void:
	var h: float = body.get_child(0).scale.y * 0.5
	var parts := [[Vector3(0,h - 0.045,0), Vector3(0.22,0.073,0.22), STEEL]]
	if mooring:
		for wrap in 3:
			parts.append([Vector3(0,h - 0.18 - wrap * 0.058,0), Vector3(0.245,0.052,0.245), Color("#b9a17b"), Basis(Vector3.UP,wrap * 0.19)])
	clad_box(body,parts)

static func gable_face(builder: WastelandScenery, half: float, rise: float, tint: Color, side: int) -> void:
	var normal := Vector3.BACK * side
	var z := 0.14 * side
	var courses := maxi(2, ceili(rise / 0.31))
	for row in courses:
		var low := float(row) / courses
		var high := float(row + 1) / courses
		var bottom := half * (1.0 - low)
		var top := half * (1.0 - high)
		var a := Vector3(-bottom, low * rise, z)
		var b := Vector3(bottom, low * rise, z)
		var c := Vector3(-top, high * rise, z)
		var d := Vector3(top, high * rise, z)
		var color := tint.lerp(TIMBER, 0.10 + 0.14 * (row % 3))
		builder.triangle(a,b,c,normal,color)
		builder.triangle(c,b,d,normal,color)
	var vent_y := rise * 0.43
	var at := Vector3(0, vent_y, z + side * 0.007)
	_gable_board(builder, at, Vector2(0.99,0.54), normal, TIMBER.darkened(0.52))
	for slat in 3:
		_gable_board(builder,at + Vector3(0, -0.18 + 0.17 * slat, side * 0.008),Vector2(0.89,0.082),normal,tint.lightened(0.12))

static func _gable_board(builder: WastelandScenery, at: Vector3, size: Vector2, normal: Vector3, tone: Color) -> void:
	var across := Vector3.RIGHT * size.x * 0.5
	var up := Vector3.UP * size.y * 0.5
	builder.triangle(at - across - up,at + across - up,at - across + up,normal,tone)
	builder.triangle(at - across + up,at + across - up,at + across + up,normal,tone)
