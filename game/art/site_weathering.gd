extends RefCounted

enum { WOOD, BRICK, CONCRETE, METAL, PAINT }

const SHADER := preload("res://shaders/site_weathering.gdshader")
const NOISE := preload("res://game/art/weather_noise.tres")

static func dress(chunk: WastelandChunk, center: Vector3) -> void:
	# Materials are shared by the members of a site and released with its chunk.
	var finishes := {}
	var wall := WOOD if chunk.ruin.wood else BRICK if chunk.site in ["hospital", "post", "fuel", "granary"] else CONCRETE
	for body in chunk.poi_root.get_children():
		if not body is StaticBody3D or not body.has_meta("site_id") or body.is_queued_for_deletion():
			continue
		var visual := body.get_child(0) as MeshInstance3D
		if not visual or not visual.material_override is StandardMaterial3D:
			continue
		var original := visual.material_override as StandardMaterial3D
		var id: String = body.get_meta("site_id")
		var finish := -1
		match id.get_slice("/", 0):
			"wall":
				# Exterior trim and mixed window fittings retain their original painted colours.
				finish = PAINT if wall != WOOD and original.vertex_color_use_as_albedo else wall
			"gable", "porch", "eave", "ridge", "door":
				finish = WOOD
			"canopy", "pump", "column", "girder", "silo", "hoist":
				finish = METAL
			"roof":
				finish = WOOD if id.begins_with("roof/rafter/") else METAL
			"chimney":
				finish = BRICK
			"ruin":
				finish = wall
			"entrance":
				finish = WOOD if chunk.ruin.wood else CONCRETE
			"fixture":
				# Older layouts use position-based IDs for the trim, chimney and steps.
				match body.get_meta("salvage_material", ""):
					"wood": finish = WOOD
					"brick": finish = BRICK
					"stone": finish = CONCRETE
			"landmark":
				finish = PAINT
		if finish >= 0:
			apply(visual, finish, center.y + chunk.global_position.y, finishes)

static func dress_dock(chunk: WastelandChunk, first: int) -> void:
	var finishes := {}
	for index in range(first, chunk.poi_root.get_child_count()):
		var body := chunk.poi_root.get_child(index) as StaticBody3D
		if not body or body.is_queued_for_deletion():
			continue
		var visual := body.get_child(0) as MeshInstance3D
		if visual:
			var finish := METAL if body.get_meta("salvage_material", "") == "scrap" else WOOD
			apply(visual, finish, 0.0, finishes)

static func apply(visual: MeshInstance3D, finish: int, ground_y: float, finishes: Dictionary) -> void:
	var original := visual.material_override as StandardMaterial3D
	if not original or original.emission_enabled:
		return
	var key := Vector2i(finish, original.albedo_color.to_rgba32())
	if not finishes.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("finish", finish)
		material.set_shader_parameter("tone", original.albedo_color)
		material.set_shader_parameter("patina", NOISE)
		material.set_shader_parameter("ground_y", ground_y)
		finishes[key] = material
	visual.material_override = finishes[key]

# Preserve the original texture projection when a rendered section breaks loose.
static func detach(visual: MeshInstance3D) -> void:
	var shared := visual.material_override as ShaderMaterial
	if not shared or shared.shader != SHADER:
		return
	var falling := shared.duplicate() as ShaderMaterial
	falling.set_shader_parameter("detached", true)
	falling.set_shader_parameter("rest_frame", visual.global_transform)
	visual.material_override = falling
