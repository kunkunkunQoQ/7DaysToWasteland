extends RefCounted

const Art := preload("res://game/art/sapling_art.gd")
const SPACING := 3.0
var session: WastelandSession
var growing_chunks := {}
var next_update := 0.0

func configure(world: WastelandSession) -> void:
	session = world
	session.stream.chunk_loaded.connect(sync_chunk)
	session.stream.plantings_changed.connect(sync_chunk)
	session.stream.chunk_unloaded.connect(func(cell: Vector2i): growing_chunks.erase(cell))

func near_tree(point: Vector3, spacing: float) -> bool:
	var here := Vector2(point.x,point.z)
	var first := WastelandTerrainGen.chunk_at(here - Vector2.ONE * spacing)
	var last := WastelandTerrainGen.chunk_at(here + Vector2.ONE * spacing)
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell := Vector2i(x,z)
			var origin := Vector2(cell) * WastelandTerrainGen.SIZE
			for row: Dictionary in session.stream.chunk_diff(cell).get("planted_trees",{}).values():
				var root: Vector3 = row.pose.origin
				if here.distance_squared_to(origin + Vector2(root.x,root.z)) < spacing * spacing: return true
	return false

func plant(model: String, point: Vector3) -> bool:
	if session.replica or not point.is_finite() or Art.duration_days(model)<=0.0: return false
	var cell := WastelandTerrainGen.chunk_at(Vector2(point.x,point.z))
	var chunk: WastelandChunk = session.stream.active.get(cell)
	if chunk == null or near_tree(point,SPACING): return false
	var diff := session.stream.edit_chunk(cell)
	if not diff.has("planted_trees"): diff.planted_trees = {}
	# Natural dressing has nonnegative indices. Never reuse a felled tree's
	# identity, even when planting again at the same spot after stump removal.
	var serial := int(diff.get("grove_serial",0)) + 1
	var id := str(-serial)
	diff.grove_serial = serial
	var rng := RandomNumberGenerator.new()
	rng.seed = session.stream.generator.seed_at(cell,-serial)
	var shape := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE * rng.randf_range(0.85,1.18))
	diff.planted_trees[id] = {"model":model,"variant":rng.randi_range(0,3),
		"pose":Transform3D(shape,chunk.to_local(point)),"planted_at":session.clock.hours,
		"soil_offset":session.stream.excavation_at(Vector2(point.x,point.z))}
	sync_chunk(cell)
	if is_instance_valid(session.network): session.network.slow_timer = 0.0
	return true

func _progress(row: Dictionary) -> float:
	return clampf((session.clock.hours - float(row.planted_at)) / (Art.duration_days(row.model)*24.0),0.0,1.0)

func describe(body: StaticBody3D) -> String:
	var row: Dictionary = session.stream.chunk_diff(body.get_meta("cell")).get("planted_trees",{}).get(body.get_meta("index"),{})
	if row.is_empty(): return ""
	var progress := _progress(row)
	var hours := ceili((1.0-progress)*24.0*Art.duration_days(row.model))
	return "%s · %s · 约 %s 成熟" % [session.timber.NAMES[row.model],Art.stage_name(row.model,progress),
		("%.1f 天" % (hours / 24.0)) if hours >= 24 else ("%d 小时" % maxi(1,hours))]

func uproot(body: StaticBody3D) -> void:
	if session.replica or body.is_queued_for_deletion() or body.get_meta("kind","")!="sapling": return
	var cell: Vector2i = body.get_meta("cell")
	var id: String = body.get_meta("index")
	var chunk: WastelandChunk = session.stream.active.get(cell)
	if chunk == null or chunk.planted.get(id)!=body: return
	var rows: Dictionary = session.stream.edit_chunk(cell).get("planted_trees",{})
	if not rows.has(id): return
	var row: Dictionary = rows[id]
	if _progress(row)>=1.0:
		sync_chunk(cell)
		return
	rows.erase(id)
	sync_chunk(cell)
	session.drop_materials(chunk.to_global(row.pose.origin)+Vector3.UP*0.18,{"sapling_"+str(row.model):1})
	if is_instance_valid(session.network): session.network.slow_timer = 0.0

func tick(dt: float) -> void:
	if growing_chunks.is_empty(): return
	next_update -= dt
	if next_update > 0.0: return
	next_update = 1.0
	for cell: Vector2i in growing_chunks.keys(): sync_chunk(cell)

func sync_chunk(cell: Vector2i) -> void:
	var chunk: WastelandChunk = session.stream.active.get(cell)
	if chunk == null: return
	var diff := session.stream.chunk_diff(cell)
	var rows: Dictionary = diff.get("planted_trees",{})
	for id: String in chunk.planted.keys():
		if not rows.has(id): chunk.remove_resource(chunk.planted[id])
	var growing := false
	for id: String in rows:
		if chunk.standing_trees.has(id): continue
		var row: Dictionary = rows[id]
		var progress := 1.0 if diff.get("tree_cuts",{}).has(id) else _progress(row)
		var body: StaticBody3D = chunk.planted.get(id)
		if body == null:
			body = chunk.object_body("nature/"+id,"sapling",row.pose.origin,Vector3.ONE*0.2,
				{"index":id,"tree_model":row.model,"tree_variant":row.variant})
			chunk.planted[id] = body
		if progress >= 1.0:
			_mature(chunk,body,row,id)
		else:
			_grow(body,row,progress)
			growing = true
	if growing: growing_chunks[cell] = true
	else: growing_chunks.erase(cell)

func _grow(body: StaticBody3D, row: Dictionary, progress: float) -> void:
	var plant_mesh := body.get_node_or_null("Standing") as Node3D
	if plant_mesh == null:
		plant_mesh = Art.build(row.model,row.variant,WastelandChunk._nature_mesh(row.model,row.variant,true))
		plant_mesh.name = "Standing"
		body.add_child(plant_mesh)
	Art.update_visual(plant_mesh,progress)
	var scale_m: float = row.pose.basis.y.length()
	var h := clampf(Art.height(plant_mesh),0.20,3.8)*scale_m
	var width := lerpf(0.24,0.54,progress)*scale_m
	_fit(body,plant_mesh,row.pose,Vector3(width,h,width))

func _mature(chunk: WastelandChunk, body: StaticBody3D, row: Dictionary, id: String) -> void:
	var juvenile := body.get_node_or_null("Standing")
	if juvenile != null:
		body.remove_child(juvenile)
		juvenile.queue_free()
	var mesh := WastelandChunk.tree_piece(WastelandChunk._nature_mesh(row.model,row.variant,true))
	mesh.name = "Standing"
	body.add_child(mesh)
	var distant := WastelandChunk.tree_piece(WastelandChunk._nature_mesh(row.model,row.variant,false))
	mesh.visibility_range_end = 58.0
	distant.visibility_range_begin = mesh.visibility_range_end
	mesh.add_child(distant)
	var resource := "oak" if row.model in ["oak","birch"] else "pine"
	_fit(body,mesh,row.pose,WastelandChunk._nature_shape(resource)*row.pose.basis.y.length())
	body.set_meta("kind","resource")
	body.set_meta("resource",resource)
	body.set_meta("tree_pose",row.pose)
	chunk.standing_trees[id] = body
	if chunk.timber_visuals.has(id): mesh.hide()

func _fit(body: StaticBody3D, visual: Node3D, pose: Transform3D, size: Vector3) -> void:
	var center := Vector3.UP * size.y * 0.5
	body.position = pose.origin + center
	var collider := body.get_child(0) as CollisionShape3D
	(collider.shape as BoxShape3D).size = size
	visual.transform = Transform3D(pose.basis,-center)
