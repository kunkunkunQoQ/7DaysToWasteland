extends RefCounted

# Days to maturity, first crown expansion, pole stage, and height-growth exponent.
const PROFILES := {
	"birch": Vector4(2.5, 0.20, 0.58, 1.12),
	"pine": Vector4(3.0, 0.25, 0.62, 1.22),
	"oak": Vector4(4.0, 0.27, 0.67, 1.40),
	"frost_fir": Vector4(4.5, 0.31, 0.69, 1.44),
	"snow_fir": Vector4(5.0, 0.34, 0.72, 1.52)
}
const TIER_COUNT := 6
const GOLDEN_ANGLE := 2.399963
static var juvenile_meshes := {}
static var item_meshes := {}
static var bark_material: ShaderMaterial

class GrowingTree extends Node3D:
	var species: String
	var variant: int
	var adult: MeshInstance3D
	var stem: MeshInstance3D
	var tiers: Array[MeshInstance3D] = []
	var height: float
	var leader_height: float

static func duration_days(model: String) -> float:
	return PROFILES[model].x if PROFILES.has(model) else 0.0

static func stage_name(model: String, progress: float) -> String:
	if not PROFILES.has(model): return ""
	var profile: Vector4 = PROFILES[model]
	if progress >= 1.0: return "成树"
	if progress >= profile.z: return "近熟树"
	if progress >= profile.y: return "幼树"
	if progress >= profile.y * 0.35: return "抽梢苗"
	return "新栽苗"

static func build(model: String, variant: int, adult_mesh: Mesh) -> Node3D:
	if not PROFILES.has(model) or adult_mesh == null: return null
	var tree := GrowingTree.new()
	tree.species = model
	tree.variant = posmod(variant, 4)
	tree.height = adult_mesh.get_aabb().end.y
	var meshes := _juvenile_meshes(model, tree.variant)
	tree.adult = _piece(tree, adult_mesh)
	tree.stem = _piece(tree, meshes[0])
	for i in TIER_COUNT:
		tree.tiers.append(_piece(tree, meshes[i + 1]))
	update_visual(tree, 0.0)
	return tree

static func _piece(tree: Node3D, mesh: Mesh) -> MeshInstance3D:
	if bark_material == null:
		bark_material = ShaderMaterial.new()
		bark_material.shader = preload("res://shaders/scenery.gdshader")
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = bark_material
	tree.add_child(piece)
	return piece

static func height(node: Node3D) -> float:
	var tree := node as GrowingTree
	return tree.leader_height if tree != null else 0.0

static func update_visual(node: Node3D, progress: float) -> void:
	var tree := node as GrowingTree
	if tree == null: return
	var p := clampf(progress, 0.0, 1.0)
	var profile: Vector4 = PROFILES[tree.species]
	var height_ratio := lerpf(0.048, 1.0, pow(p, profile.w))
	var height := tree.height * height_ratio
	tree.leader_height = height
	# The adult leader rises inside the seedling. Branches spread out from it
	# as the juvenile foliage is shaded out, retaining this exact adult variant.
	var spread := smoothstep(profile.y * 0.52, profile.z + 0.12, p)
	# The lower end of the adult trunk must reach the ground before secondary
	# thickening replaces the first stem at the start of the pole stage.
	var crown_length := lerpf(0.018, 1.0, smoothstep(profile.y * 0.52, profile.z - 0.08, p))
	var width_ratio := height_ratio * spread * lerpf(0.66, 1.0, smoothstep(profile.z, 1.0, p))
	tree.adult.visible = spread > 0.0001
	tree.adult.scale = Vector3(maxf(width_ratio, 0.0001), height_ratio * crown_length, maxf(width_ratio, 0.0001))
	var stem_loss := 1.0 - smoothstep(profile.z - 0.08, profile.z + 0.04, p)
	tree.stem.visible = stem_loss > 0.001
	var stem_width := (0.45 + height * 0.72) * maxf(stem_loss, 0.001)
	tree.stem.scale = Vector3(stem_width, height, stem_width)
	# The first adult foliage unfolds at the leader's existing tip. Its lower
	# branches take up progressively more of the stem as the crown deepens.
	tree.adult.position = _stem_point(tree.species, tree.variant, 1.0) * tree.stem.scale * (1.0 - crown_length)
	for i in TIER_COUNT:
		var tier := tree.tiers[i]
		var level := _level(i)
		var bud_break := maxf(0.0, i - 1.0) * profile.y * 0.15
		var opening := smoothstep(bud_break, bud_break + profile.y * 0.55, p)
		# Several prior shoots and the terminal bud survive transplant.
		if i < 2 or i == TIER_COUNT - 1: opening = lerpf(0.72, 1.0, opening)
		elif i == 3: opening = lerpf(0.45, 1.0, opening)
		var shed_at := profile.z - 0.20 + i * 0.023
		var retained := 1.0 - smoothstep(shed_at, shed_at + 0.17, p)
		var size := (0.40 + height * 0.45) * opening * retained
		tier.visible = size > 0.001
		if tier.visible:
			tier.position = _stem_point(tree.species, tree.variant, level) * tree.stem.scale
			tier.scale = Vector3.ONE * size

static func _level(i: int) -> float:
	return 0.30 + 0.14 * i

static func _stem_point(model: String, v: int, level: float) -> Vector3:
	var bend := 0.087 if model == "oak" else 0.056 if model == "birch" else 0.012
	var dir := Vector3(cos(v + 0.4), 0, sin(v + 0.4))
	return dir * (level * level * bend + sin(level * TAU) * bend * 0.20) + Vector3.UP * level

static func _juvenile_meshes(model: String, v: int) -> Array:
	var key := "%s/%d" % [model, v]
	if juvenile_meshes.has(key): return juvenile_meshes[key]
	var m := WastelandScenery.new(model.hash() + v)
	var points := PackedVector3Array([Vector3.DOWN * 0.03])
	var radii := PackedFloat32Array([0.027 if model == "oak" else 0.020])
	for i in TIER_COUNT:
		var level := _level(i)
		points.append(_stem_point(model, v, level))
		radii.append(lerpf(radii[0], 0.005, level))
	var bark := Color("#866347") if model == "oak" else Color("#a98364") if model == "birch" else Color("#815c45")
	m.tube(points, radii, 7, bark, v)
	var pieces := [m.commit()]
	for i in TIER_COUNT:
		m = WastelandScenery.new(model.hash() + v * 71 + i)
		var angle := 0.38 + v * 0.53 + i * GOLDEN_ANGLE
		if model in ["oak", "birch"]:
			_broadleaf_shoot(m, model, i, angle, bark)
		else:
			_needle_whorl(m, model, i, angle, bark)
		pieces.append(m.commit())
	juvenile_meshes[key] = pieces
	return pieces

static func _broadleaf_shoot(m: WastelandScenery, model: String, tier: int, angle: float, bark: Color) -> void:
	var oak := model == "oak"
	var end_bud := tier == TIER_COUNT - 1
	var length := (0.25 if oak else 0.20) * (1.0 - 0.08 * tier)
	var dir := Vector3(cos(angle), 0, sin(angle))
	var tip := dir * length + Vector3.UP * length * (0.38 if oak else 0.72)
	if end_bud: tip = Vector3.UP * 0.075
	var elbow := tip * 0.58 + Vector3.UP * 0.034
	m.tube([Vector3.ZERO, elbow, tip], [0.013, 0.009, 0.005], 5, bark, angle)
	var tint := Color("#809950") if oak else Color("#a8b95c")
	if tier < 2: tint = tint.darkened(0.12)
	for j in (3 if oak else 4):
		var t := 0.42 + j * (0.28 if oak else 0.19)
		var at := elbow.lerp(tip, t)
		if not oak:
			t = 0.24 + j * 0.25
			at = Vector3.ZERO.lerp(elbow, t * 2.0) if t < 0.5 else elbow.lerp(tip, (t - 0.5) * 2.0)
		var yaw := angle + (j * GOLDEN_ANGLE if oak else (-1.0 if j % 2 == 0 else 1.0) * 1.05)
		var span := (0.26 if oak else 0.18) * (0.86 + 0.13 * sin(yaw))
		if end_bud: span *= 0.60
		_leaf(m, at, yaw, span, oak, tint.lightened(0.055 * j))
	if oak or end_bud:
		m.lobe(tip + Vector3.UP * 0.017, Vector3(0.013, 0.029, 0.013), Color("#95653f"), angle, false)

static func _leaf(m: WastelandScenery, at: Vector3, angle: float, length: float, oak: bool, tint: Color) -> void:
	var axis := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-axis.z, 0, axis.x).rotated(axis, 0.35 * sin(angle * 1.7) + 0.20)
	# Rounded lobes with deep sinuses on oak; a toothed triangular blade on birch.
	var widths := [0.015, 0.14, 0.23, 0.13, 0.33, 0.19, 0.36, 0.18, 0.23, 0.10, 0.0] if oak else [0.015, 0.26, 0.40, 0.31, 0.35, 0.23, 0.25, 0.14, 0.15, 0.056, 0.0]
	var last_mid := at
	var last_left := at
	var last_right := at
	for i in widths.size():
		var t := float(i) / (widths.size() - 1)
		var width := length * float(widths[i])
		var center := at + axis * t * length + Vector3.UP * length * (sin(t * PI) * 0.21 + t * (0.12 if oak else -0.12))
		var left := center - side * width - Vector3.UP * width * 0.36
		var right := center + side * width * 0.94 - Vector3.UP * width * 0.22
		if i > 0:
			m.triangle(last_mid, last_left, left, Vector3.UP, tint)
			m.triangle(last_mid, left, center, Vector3.UP, tint)
			m.triangle(last_mid, center, right, Vector3.UP, tint.lightened(0.11))
			m.triangle(last_mid, right, last_right, Vector3.UP, tint.lightened(0.11))
		last_mid = center
		last_left = left
		last_right = right

static func _needle_whorl(m: WastelandScenery, model: String, tier: int, angle: float, bark: Color) -> void:
	var pine := model == "pine"
	var snow := model == "snow_fir"
	var count := 4 if pine else 5 if snow else 6
	var length := (0.36 if snow else 0.31) * (1.0 - tier * 0.13)
	var green := Color("#739654") if pine else Color("#6a9281") if snow else Color("#438478")
	for j in count:
		var yaw := angle + TAU * j / count
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-dir.z, 0, dir.x)
		var tip := dir * length + Vector3.UP * length * (0.49 if pine else -0.16 if snow else 0.13)
		if tier == TIER_COUNT - 1: tip = dir * length * 0.32 + Vector3.UP * length * 0.88
		var elbow := tip * 0.58 - Vector3.UP * length * (0.12 if snow else 0.06)
		m.tube([Vector3.ZERO, elbow, tip], [0.010, 0.007, 0.003], 4, bark, yaw)
		for k in (3 if pine else 5):
			var t := 0.28 + k * (0.32 if pine else 0.16)
			var at := Vector3.ZERO.lerp(elbow, t * 2.0) if t < 0.5 else elbow.lerp(tip, (t - 0.5) * 2.0)
			for sign_value: float in [-1.0, 1.0]:
				var extent := length * (0.48 if pine else 0.34) * (1.12 - 0.52 * t)
				var needle := (side * sign_value + dir * (0.65 if pine else 0.35) + Vector3.UP * (0.88 if pine else 0.18)) * extent
				var wing := dir * (0.023 if pine else 0.025) * (1.0 - tier * 0.09)
				var tone := green.lightened(t * 0.19)
				# Uneven pale snow caps rest on top of alternating outer sprays.
				if snow and k > 0 and (j + tier) % 3 != 1: tone = Color("#c9dbd2").lightened(t * 0.10)
				var fold := at + needle * 0.44 + Vector3.UP * wing.length() * 0.58
				m.triangle(at - wing, fold, at + needle, Vector3.UP, tone)
				m.triangle(at, at + needle * 0.40 + wing, fold, Vector3.UP, tone.lightened(0.07))
				m.triangle(fold, at + needle * 0.40 + wing, at + needle, Vector3.UP, tone.lightened(0.07))
				if pine:
					m.triangle(at, at + needle * 0.38 - wing, at + needle - dir * extent * 0.40, Vector3.UP, tone.darkened(0.10))

static func item_mesh(model: String) -> ArrayMesh:
	if not PROFILES.has(model): return null
	if item_meshes.has(model): return item_meshes[model]
	var root_ball := WastelandScenery.new(7314)
	root_ball.lobe(Vector3.DOWN * 0.065, Vector3(0.12, 0.11, 0.115), Color("#78593e"), 0.8, false)
	root_ball.tube([Vector3.DOWN * 0.154, Vector3.DOWN * 0.083, Vector3.DOWN * 0.016],
		[0.067, 0.125, 0.109], 9, Color("#af8c5c"), 0.3)
	root_ball.tube([Vector3.DOWN * 0.062, Vector3.DOWN * 0.047], [0.122, 0.121], 9, Color("#79613f"), 0.35)
	var parts := _juvenile_meshes(model, 0)
	var item := SurfaceTool.new()
	item.begin(Mesh.PRIMITIVE_TRIANGLES)
	item.append_from(root_ball.commit(), 0, Transform3D.IDENTITY)
	var leader := Vector3(0.54, 0.52, 0.54)
	item.append_from(parts[0], 0, Transform3D(Basis.from_scale(leader), Vector3.ZERO))
	for i in TIER_COUNT:
		var pivot := _stem_point(model, 0, _level(i)) * leader
		item.append_from(parts[i + 1], 0, Transform3D(Basis.from_scale(Vector3.ONE * 0.62), pivot))
	item_meshes[model] = item.commit()
	return item_meshes[model]
