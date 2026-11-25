extends "res://tools/verify_harvest.gd"

func run() -> void:
	WastelandSave.root_override = "user://verification/facades-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 27491
	config.terrain_revision = 5
	config.start_id = "grassland"
	open_world({})
	var gen: WastelandTerrainGen = session.stream.generator
	var cells := WastelandTerrainGen.FIXED.keys()
	cells.append_array([Vector2i(-7,-9),Vector2i(-10,-17),Vector2i(-13,-18),gen.starting_outpost("grassland")])
	for z in range(-20,21):
		var found := false
		for x in range(-20,21):
			var cell := Vector2i(x,z)
			if gen.site_for(cell) == "cabin":
				cells.append(cell)
				found = true
				break
		if found: break
	var facades: Dictionary = {}
	for cell: Vector2i in cells:
		var world := Vector2(cell * WastelandTerrainGen.SIZE) + Vector2(16,16)
		session.stream.ensure_landing(Vector3(world.x,0,world.y))
		var c: WastelandChunk = session.stream.active[cell]
		var side_parts: Array = c.structures["wall/0/1/3"]
		var back_parts: Array = c.structures["wall/0/2/3"]
		var side: StaticBody3D = side_parts.back()
		var back: StaticBody3D = back_parts.back()
		var visual: MeshInstance3D = side.get_child(0)
		var rendered:=visual.mesh.get_faces()
		var solids:PackedVector3Array=side.get_child(1).shape.get_faces()
		check(side.get_child_count() == 2 and visual.mesh.get_surface_count() == 1 and side.get_child(1).shape == back.get_child(1).shape
			and back.get_child(0).mesh == visual.mesh and solids.size()<rendered.size() and solids==rendered.slice(0,solids.size()),
			c.site + " matching bays share one mesh and collider with cosmetic interior linings excluded from physics")
		var finish := visual.material_override as ShaderMaterial
		check(finish != null and finish.shader == preload("res://shaders/site_weathering.gdshader")
			and finish == back.get_child(0).material_override, c.site + " adjoining bays share their weathered finish")
		var family := "outpost" if c.site == "lodge" and c.cell != WastelandSite.SHORE_CELL else c.site
		var signature := hash([visual.mesh.get_faces(),visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]])
		if facades.has(family):
			check(facades[family] == signature,family + " facade is stable across cells")
		facades[family] = signature
		if c.site in ["lodge","cabin"]:
			await physics_frame
			_check_roof_tear(c)
		if c.site in ["garage","granary"]:
			var key := "roof/plate/1/3"
			var section: Array = c.structures[key].duplicate()
			check(section.size() == 2,c.site + " roof plant belongs to its deck")
			session.hit_wall(section[0],9999)
			check(not c.structures.has(key) and section[1].collision_layer == 0 and not section[1].visible,c.site + " roof plant follows demolition")
	var unique: Dictionary = {}
	for signature: int in facades.values(): unique[signature] = true
	check(facades.size() == 11 and unique.size() == 11,"all ten site types and the inland outpost have distinct wall profiles")
	await close_world()
	print("FACADE QA passed=%d failed=%d" % [passed, failures])
	quit(1 if failures else 0)

func _check_roof_tear(c: WastelandChunk) -> void:
	var bay := 1 if c.ruin.end < 0 else 3
	var panels: Array = c.structures["roof/timber/1/%d" % bay]
	var panel: StaticBody3D = panels[0]
	var depth: float = c.ruin.span / 5.0
	var x: float = 16 + c.ruin.span * 0.5 + WastelandSite.ROOF_OVERHANG - 0.15
	var start := c.to_global(Vector3(x,c.ruin.base_y + 5.0,16 + (bay - 2) * depth))
	var space := c.get_world_3d().direct_space_state
	var torn := start + Vector3.BACK * depth * 0.31
	var mended := start - Vector3.BACK * depth * 0.31
	var gap := space.intersect_ray(PhysicsRayQueryParameters3D.create(torn,torn + Vector3.DOWN * 2.5,2))
	var tin := space.intersect_ray(PhysicsRayQueryParameters3D.create(mended,mended + Vector3.DOWN * 2.5,2))
	check(panels.size() == 1 and panel.get_child(0).mesh.get_surface_count() == 1 and gap.is_empty() and tin.get("collider") == panel,
		c.site + " folded and missing sheets share one draw surface and the actual eave tear is open")
