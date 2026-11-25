class_name WastelandChunk
extends Node3D

var spring_at:=Vector3.INF

const TERRAIN := preload("res://game/world/terrain_gen.gd")
static var nature_meshes: Dictionary = {}
static var terrain_accessory_shader: ShaderMaterial
static var nav_box_faces := PackedVector3Array()
var cell: Vector2i
var stream: Node3D
var terrain_body: StaticBody3D
var ground_visual: MeshInstance3D
var water: MeshInstance3D
var region: NavigationRegion3D
var navigation_data: Dictionary
var instances: Dictionary = {}
var timber_visuals: Dictionary = {}
var standing_trees: Dictionary = {}
var planted: Dictionary = {}
# Small plants stay in MultiMeshes. Only the handful under a player's aim need a node.
var nature_bins: Dictionary = {}
var small_nature: Dictionary = {}
var aim_bodies: Dictionary = {}
var supply_caches: Dictionary = {}
const FIXTURE_HP := {"trader":75.0,"note":5.0,"loot":65.0}
var fixtures := {}
var board_missing := false
var obstacles: Array[StaticBody3D] = []
var structures: Dictionary = {}
var wall_finishes: Dictionary = {}
var support_graph: Dictionary = {}
var footings: Dictionary = {}
var ruin := preload("res://game/world/site_ruins.gd").new()
var sleeper_anchors: Array[Vector3] = []
var cave_origin := Vector3.INF

func track_structure(body: StaticBody3D, id: String, health: float) -> void:
	body.set_meta("site_id",id)
	if stream.is_preview:
		if stream.generator.site_revision>0:
			if not structures.has(id): structures[id]=[]
			structures[id].append(body)
		return
	body.set_meta("kind","poi_wall")
	body.set_meta("cell",cell)
	body.set_meta("hp_max",health)
	var hp := float(stream.chunk_diff(cell).get("site_damage",{}).get(id,health))
	body.set_meta("hp",hp)
	if id.begins_with("wall/") or id.begins_with("gable/"):
		body.set_meta("timber_wall",site=="lodge" or site=="cabin")
		if hp>0.0 and hp<health: preload("res://game/art/site_wall_damage.gd").update(self,body,hp)
	if not structures.has(id): structures[id]=[]
	structures[id].append(body)
	if hp<=0: set_structure_health(id,0)

func set_structure_health(id: String,hp: float,falling := false) -> void:
	for node: StaticBody3D in structures.get(id,[]):
		if not is_instance_valid(node) or node.is_queued_for_deletion(): continue
		node.set_meta("hp",hp)
		if node.has_meta("timber_wall"): preload("res://game/art/site_wall_damage.gd").update(self,node,hp)
		if hp<=0:
			if falling and not stream.is_preview:
				preload("res://game/world/falling_structure.gd").release(self,node,id)
			node.collision_layer=0
			node.hide()
			node.queue_free()
	if hp<=0: structures.erase(id)

func _grounded(id: String) -> bool:
	if not footings.has(id) or stream.digs.is_empty(): return true
	var samples: Array = footings[id]
	var bearing: Array[Vector2] = []
	var longest := 0.0
	for p: Vector2 in samples:
		if stream.excavation_at(p)>-0.55: bearing.append(p)
		for q: Vector2 in samples: longest=maxf(longest,p.distance_squared_to(q))
	if samples.size()==1: return not bearing.is_empty()
	for i in bearing.size():
		for j in range(i+1,bearing.size()):
			if bearing[i].distance_squared_to(bearing[j])>=longest*0.35: return true
	return false

func settle_structures(animate := false, before_fall: Callable = Callable()) -> Array[String]:
	var loose: Array[String] = []
	if support_graph.is_empty() and footings.is_empty(): return loose
	var anchored := {}
	for id: String in structures:
		var groups: Array = support_graph.get(id,[])
		if groups.is_empty() and _grounded(id): anchored[id]=true
		else: loose.append(id)
	# Only transmit loads from a real foundation. A closed loop in a broken frame
	# cannot support itself. Alternative spans survive when one full set still bears.
	var searching := true
	while searching:
		searching=false
		for i in range(loose.size()-1,-1,-1):
			var id := loose[i]
			for bearings: Array in support_graph.get(id,[]):
				if not bearings.is_empty() and anchored.has_all(bearings) and _grounded(id):
					anchored[id]=true
					loose.remove_at(i)
					searching=true
					break
	for id in loose:
		if before_fall.is_valid(): before_fall.call(id)
		set_structure_health(id,0,animate)
	return loose
var decoration_root: Node3D
var poi_root: Node3D
var site := ""
var nav_revision := 0
var baked_revision := 0

func install(owner_stream: Node3D, coord: Vector2i, data: Dictionary) -> void:
	stream = owner_stream
	cell = coord
	position = Vector3(cell.x * TERRAIN.SIZE, 0.0, cell.y * TERRAIN.SIZE)
	name = "地块_%d_%d" % [cell.x, cell.y]
	terrain_body = StaticBody3D.new()
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 0
	terrain_body.set_meta("kind", "terrain")
	add_child(terrain_body)
	ground_visual = MeshInstance3D.new()
	ground_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_visual.material_override = stream.atmosphere.terrain_mat
	terrain_body.add_child(ground_visual)
	if not stream.is_preview:
		region = NavigationRegion3D.new()
		region.use_edge_connections = true
		add_child(region)
	decoration_root = Node3D.new()
	add_child(decoration_root)
	poi_root = Node3D.new()
	add_child(poi_root)
	site = data.site
	update_ground(data)
	var dressing := WastelandSite.starter_dressing(self,data.dressing)
	if site.is_empty():
		var caves := preload("res://game/world/nest_caves.gd")
		cave_origin = caves.location(self)
		if cave_origin.is_finite():
			dressing = dressing.filter(func(row): return not caves.inside_footprint(row.point, cave_origin))
			caves.build(self)
			spring_at=preload("res://game/world/mineral_spring.gd").build(self)
	_dress(dressing)
	if site != "":
		WastelandSite.populate(self, stream.catalog.sites[site], float(data.pad))
	elif not stream.is_preview:
		preload("res://game/world/regional_caches.gd").wilderness(self,data.dressing)
	if cell == Vector2i.ZERO:
		WastelandSite.landing(self)
	if data.water and stream.generator.revision >= 2:
		WastelandSunkenSites.populate(self)
	preload("res://game/world/expedition_sites.gd").populate(self)
	settle_structures()
	sync_fixtures()
	rebuild_navigation()

func sync_fixtures() -> void:
	var diff: Dictionary = stream.chunk_diff(cell)
	var health: Dictionary = diff.get("fixture_health",{})
	var board_key := object_key("trader")
	if board_missing and float(health.get(board_key,1))>0:
		var point := WastelandSite.board_at(cell)-Vector2(position.x,position.z)
		WastelandSite._notice_board(self,Vector3(point.x,float(diff.board_y),point.y))
		board_missing = false
	for key: String in fixtures.keys():
		var body: StaticBody3D = fixtures[key]
		var kind: String = body.get_meta("kind")
		var hp := float(health.get(key,FIXTURE_HP[kind]))
		body.set_meta("hp",hp)
		if hp<=0.0:
			if kind=="trader": board_missing = true
			supply_caches.erase(key)
			fixtures.erase(key)
			body.collision_layer = 0
			body.hide()
			body.queue_free()
		elif kind=="trader" and diff.has("board_y"):
			body.position.y = float(diff.board_y)+1.05

func sync_cache(key: String, animate := true) -> void:
	var record: Dictionary = stream.chunk_diff(cell).get("containers",{}).get(key,{})
	var model: Node3D = supply_caches[key]
	var underwater := model.get_parent().has_meta("submerged_site")
	var state := preload("res://game/art/supply_chest.gd").state(record,stream.loot_day,stream.refill_days,underwater)
	model.show_state(state,animate)

func update_ground(data: Dictionary) -> void:
	navigation_data = {"points": data.points, "nav": data.nav, "floor_faces": data.arrays[Mesh.ARRAY_VERTEX]}
	var ground := ArrayMesh.new()
	ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.arrays)
	ground_visual.mesh = ground
	for child in terrain_body.get_children():
		if child is CollisionShape3D:
			terrain_body.remove_child(child)
			child.queue_free()
	if not stream.is_preview:
		var collision := CollisionShape3D.new()
		var heightmap:=HeightMapShape3D.new()
		heightmap.map_width=TERRAIN.GRID
		heightmap.map_depth=TERRAIN.GRID
		var heights:=PackedFloat32Array()
		heights.resize(TERRAIN.GRID*TERRAIN.GRID)
		for i in heights.size(): heights[i]=data.points[i].y
		heightmap.map_data=heights
		collision.shape=heightmap
		collision.position=Vector3(TERRAIN.SIZE*0.5,0,TERRAIN.SIZE*0.5)
		terrain_body.add_child(collision)
	if data.water and water == null:
		if WastelandLook.water_plane == null:
			WastelandLook.water_plane = PlaneMesh.new()
			WastelandLook.water_plane.size = Vector2.ONE * TERRAIN.SIZE
		water = MeshInstance3D.new()
		water.mesh = WastelandLook.water_plane
		water.position = Vector3(TERRAIN.SIZE * 0.5, 0.015, TERRAIN.SIZE * 0.5)
		water.material_override = stream.atmosphere.water_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
	if water != null:
		water.visible = data.water

func rebuild_navigation() -> void:
	if stream.is_preview: return
	nav_revision += 1
	var vertices: PackedVector3Array = navigation_data.points
	var triangles: PackedInt32Array = navigation_data.nav
	var blocked: Dictionary = stream.get_blockers.call(cell) if stream.get_blockers.is_valid() else {}
	if not stream.is_preview and (site != "" or cave_origin.is_finite() or not blocked.is_empty() or cell == Vector2i.ZERO):
		_bake_navigation(vertices, triangles, blocked)
		if region.navigation_mesh != null:
			return
	var nav := NavigationMesh.new()
	nav.vertices = vertices
	for index in range(0, triangles.size(), 3):
		nav.add_polygon(triangles.slice(index, index + 3))
	region.navigation_mesh = nav

func _bake_navigation(vertices: PackedVector3Array, triangles: PackedInt32Array, blocked: Dictionary) -> void:
	var source := NavigationMeshSourceGeometryData3D.new()
	var floor_faces := PackedVector3Array()
	floor_faces.resize(triangles.size())
	for index in triangles.size():
		floor_faces[index] = vertices[triangles[index]]
	if site == "bunker":
		source.add_faces(navigation_data.floor_faces, Transform3D.IDENTITY)
	elif not floor_faces.is_empty():
		source.add_faces(floor_faces, Transform3D.IDENTITY)
	obstacles = obstacles.filter(func(node): return is_instance_valid(node) and not node.is_queued_for_deletion())
	for body in obstacles:
		_add_obstacle(source, body)
	if stream.get_body.is_valid():
		for key in blocked:
			var body: StaticBody3D = stream.get_body.call(key)
			if is_instance_valid(body) and not body.is_queued_for_deletion():
				_add_obstacle(source, body)
	if not source.has_data():
		return
	var nav := NavigationMesh.new()
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	nav.agent_height = 1.75
	nav.agent_radius = 0.25
	nav.agent_max_climb = 0.50
	nav.agent_max_slope = 49.0
	# Triangulate contours before detail sampling. Large contour polygons at
	# terrain/POI transitions otherwise admit overlapping detail triangles.
	nav.vertices_per_polygon = 3
	nav.region_min_size = 1.0
	nav.region_merge_size = 4.0
	stream.nav_inflight.append(nav)
	_bake_async(weakref(self), nav_revision, nav, source)

func _add_obstacle(source: NavigationMeshSourceGeometryData3D, body: StaticBody3D) -> void:
	var local := global_transform.affine_inverse() * body.global_transform
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var sizes: Vector3 = child.shape.size
			if nav_box_faces.is_empty():
				nav_box_faces = WastelandLook.unit_box.get_faces()
			source.add_faces(nav_box_faces, local * child.transform * Transform3D(Basis.from_scale(sizes), Vector3.ZERO))
		elif child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			source.add_faces(child.shape.get_faces(), local * child.transform)
		elif child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			for mesh in body.get_children():
				if mesh is MeshInstance3D:
					source.add_faces(mesh.mesh.get_faces(), local * mesh.transform)

static func _bake_async(owner_ref: WeakRef, revision: int, nav: NavigationMesh, source: NavigationMeshSourceGeometryData3D) -> void:
	NavigationServer3D.bake_from_source_geometry_data_async(nav, source, func():
		var chunk: Node3D = owner_ref.get_ref()
		if is_instance_valid(chunk) and chunk.is_inside_tree() and chunk.nav_revision == revision and nav.get_polygon_count() > 0:
			chunk.region.navigation_mesh = nav
			chunk.baked_revision = revision)

func object_key(local: String) -> String:
	return TERRAIN.grid_key(cell) + ":" + local

func object_body(local: String, kind: String, pos: Vector3, size: Vector3, meta: Dictionary = {}) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = pos
	body.set_meta("kind", kind)
	body.set_meta("key", object_key(local))
	body.set_meta("cell", cell)
	if FIXTURE_HP.has(kind):
		fixtures[object_key(local)] = body
		body.set_meta("hp_max",FIXTURE_HP[kind])
		body.set_meta("hp",FIXTURE_HP[kind])
	for key in meta:
		body.set_meta(key, meta[key])
	decoration_root.add_child(body)
	if not stream.is_preview:
		WastelandLook.collider(body, size, Vector3.ZERO)
	return body

func _dress(rows: Array) -> void:
	var groups: Dictionary = {}
	var diff: Dictionary = stream.chunk_diff(cell)
	var removed: Dictionary = diff.get("removed", {})
	for entry in rows:
		var id: String = entry.id
		var unique := str(entry.index)
		if removed.has(unique):
			continue
		var variant := int(entry.variant)
		if id == "grass" and not entry.get("pickup",false) and (entry.index % 4) == 0:
			id = "reeds"
		var model:=str(entry.get("model",""))
		if model.is_empty(): model=id
		var group := model + str(variant)
		if not groups.has(group):
			groups[group] = {"id": model, "variant": variant, "transforms": []}
		var at: Vector3 = entry.point
		var s := float(entry.scale)
		var basis := Basis(Vector3.UP, float(entry.angle)).scaled(Vector3.ONE * s)
		var count: int = groups[group].transforms.size()
		groups[group].transforms.append(Transform3D(basis, at))
		if stream.is_preview:
			continue
		if id in TERRAIN.RESOURCES or entry.get("pickup",false):
			var shape := _nature_shape(id) * s
			var resource := object_body("nature/" + unique, "resource", at + Vector3.UP * shape.y * 0.5, shape,
				{"resource": id, "index": unique, "group": group, "instance": count})
			if id in ["oak","pine"]:
				resource.set_meta("tree_model", model)
				resource.set_meta("tree_variant", variant)
				resource.set_meta("tree_pose", Transform3D(basis, at))
				standing_trees[unique] = resource
		else:
			index_nature(unique, id, group, count, Transform3D(basis,at), _nature_mesh(model,variant,true))
	if terrain_accessory_shader == null:
		terrain_accessory_shader = ShaderMaterial.new()
		terrain_accessory_shader.shader = preload("res://shaders/scenery.gdshader")
	for group in groups:
		var row: Dictionary = groups[group]
		var transforms: Array[Transform3D] = []
		transforms.assign(row.transforms)
		var tree: bool = row.id in ["oak","pine","snow_fir","frost_fir","birch","snag"]
		var close_range := 58.0 if tree else 31.0
		var near_mesh := _nature_mesh(row.id, row.variant, true)
		var distant_mesh := _nature_mesh(row.id, row.variant, false)
		var high := WastelandLook.instanced(decoration_root, near_mesh, transforms)
		var low := WastelandLook.instanced(decoration_root, distant_mesh, transforms)
		high.material_override = terrain_accessory_shader
		low.material_override = terrain_accessory_shader
		high.visibility_range_end = close_range
		low.visibility_range_begin = close_range
		instances[group] = [high, low]
		if not tree:
			high.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for id: String in diff.get("tree_cuts",{}):
		sync_tree_cut(id, diff.tree_cuts[id])

func sync_tree_cut(id: String, cut: Dictionary, parts: Dictionary = {}, struck := false) -> void:
	var old: Node3D = timber_visuals.get(id)
	if is_instance_valid(old):
		if old is StaticBody3D: old.collision_layer = 0
		old.hide()
		old.queue_free()
		timber_visuals.erase(id)
	if cut.is_empty(): return
	var severed := float(cut.progress) >= 1.0
	var original: StaticBody3D = standing_trees.get(id)
	if is_instance_valid(original):
		if severed:
			remove_resource(original)
		elif planted.has(id):
			original.get_node("Standing").hide()
		else:
			hide_instance(original.get_meta("group"), original.get_meta("instance"))
	if parts.is_empty(): parts = cut_meshes(cut)
	var root: Node3D
	var top: MeshInstance3D
	if severed:
		var stump := StaticBody3D.new()
		stump.collision_layer = 2
		stump.collision_mask = 0
		stump.set_meta("kind","stump")
		stump.set_meta("index",id)
		stump.set_meta("cell",cell)
		var cylinder := CylinderShape3D.new()
		cylinder.height = maxf(0.1, parts.pivot.y)
		cylinder.radius = float(parts.trunk_radius)
		var collision := CollisionShape3D.new()
		collision.position = Vector3(parts.pivot.x, cylinder.height * 0.5, parts.pivot.z)
		collision.shape = cylinder
		stump.add_child(collision)
		root = stump
	else:
		root = Node3D.new()
		top = tree_piece(parts.upper)
		root.add_child(top)
	root.add_child(tree_piece(parts.stump))
	decoration_root.add_child(root)
	root.transform = cut.pose
	timber_visuals[id] = root
	if struck and top != null:
		var pivot: Vector3 = parts.pivot
		var axis := Vector3.UP.cross(-Vector3(cut.face)).normalized()
		var sway := 0.008 + 0.018 * float(cut.progress)
		var tween := top.create_tween()
		tween.tween_method(func(t: float):
			var tilt := Basis(axis,sin(t * TAU) * (1.0-t) * sway)
			top.transform = Transform3D(tilt,pivot - tilt * pivot),0.0,1.0,0.36)

static func cut_meshes(cut: Dictionary) -> Dictionary:
	var source := _nature_mesh(cut.model,cut.variant,true)
	return preload("res://game/art/timber_art.gd").parts(source,cut.face,cut.progress,cut.progress>=1.0,cut.height)

static func tree_piece(mesh: Mesh) -> MeshInstance3D:
	var child := MeshInstance3D.new()
	child.mesh = mesh
	child.material_override = terrain_accessory_shader
	return child

func index_nature(key: String, id: String, group: String, slot: int, pose: Transform3D, mesh: Mesh) -> void:
	var bounds: AABB = (pose * mesh.get_aabb()).grow(0.04)
	small_nature[key] = {"resource":id,"group":group,"instance":slot,"bounds":bounds,"root":pose.origin}
	var first := Vector2i(floori(bounds.position.x/4.0),floori(bounds.position.z/4.0))
	var last := Vector2i(floori(bounds.end.x/4.0),floori(bounds.end.z/4.0))
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			var bin := Vector2i(x,z)
			if not nature_bins.has(bin): nature_bins[bin] = []
			nature_bins[bin].append(key)

func trace_nature(start: Vector3, end: Vector3) -> Dictionary:
	var a := start-position
	var b := end-position
	var first := Vector2i(floori(minf(a.x,b.x)/4.0),floori(minf(a.z,b.z)/4.0))
	var last := Vector2i(floori(maxf(a.x,b.x)/4.0),floori(maxf(a.z,b.z)/4.0))
	var key := ""
	var closest := INF
	var point := Vector3.ZERO
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			for candidate: String in nature_bins.get(Vector2i(x,z),[]):
				if not small_nature.has(candidate): continue
				var bounds: AABB = small_nature[candidate].bounds
				var hit: Variant = bounds.intersects_segment(a,b)
				if hit == null: continue
				var dist := a.distance_squared_to(hit)
				if dist < closest:
					point = hit
					closest = dist
					key = candidate
	if key.is_empty(): return {}
	if not aim_bodies.has(key):
		if aim_bodies.size() >= 4:
			var oldest: String = aim_bodies.keys()[0]
			aim_bodies[oldest].queue_free()
			aim_bodies.erase(oldest)
		var body := StaticBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = small_nature[key].bounds.get_center()
		for field in ["resource","group","instance"]: body.set_meta(field,small_nature[key][field])
		body.set_meta("kind","resource")
		body.set_meta("cell",cell)
		body.set_meta("index",key)
		body.set_meta("key",object_key("nature/"+key))
		decoration_root.add_child(body)
		aim_bodies[key] = body
	return {"position":point+position,"collider":aim_bodies[key],"normal":Vector3.UP}

func erase_small_nature(key: String) -> void:
	if not small_nature.has(key): return
	var record: Dictionary = small_nature[key]
	hide_instance(record.group,record.instance)
	small_nature.erase(key)
	if aim_bodies.has(key):
		aim_bodies[key].queue_free()
		aim_bodies.erase(key)

# A shovel can dislodge shallow roots or a loose item lying on the surface.
# Called only from an actual excavation, never while replaying removed scenery.
func uproot_small(at: Vector3) -> void:
	if stream.is_preview or stream.get_parent().replica: return
	var cut := Vector2(roundf(at.x),roundf(at.z))
	if not Rect2(Vector2(position.x,position.z),Vector2(TERRAIN.SIZE,TERRAIN.SIZE)).grow(2).has_point(cut): return
	var local := cut-Vector2(position.x,position.z)
	for id: String in planted.keys():
		var sapling: StaticBody3D = planted[id]
		if sapling.get_meta("kind")!="sapling": continue
		var anchor: Vector3 = sapling.get_node("Standing").global_position
		var xz := Vector2(anchor.x,anchor.z)
		if cut.distance_squared_to(xz)>4.0: continue
		var row: Dictionary = stream.chunk_diff(cell).planted_trees[id]
		if float(row.get("soil_offset",0.0))-stream.excavation_at(xz)>0.38:
			stream.get_parent().grove.uproot(sapling)
	var first := Vector2i(((local-Vector2.ONE*2.0)/4.0).floor())
	var last := Vector2i(((local+Vector2.ONE*2.0)/4.0).floor())
	var candidates := {}
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			for key: String in nature_bins.get(Vector2i(x,z),[]):
				if small_nature.has(key):
					var entry: Dictionary = small_nature[key]
					candidates[key]=[entry.resource,position+entry.root,null]
	for body in decoration_root.get_children():
		if body.is_queued_for_deletion() or body.get_meta("kind","")!="resource": continue
		var key: String = body.get_meta("index")
		if not small_nature.has(key):
			candidates[key]=[body.get_meta("resource"),body.global_position,body]
	for key: String in candidates:
		var entry: Array = candidates[key]
		var kind: String = entry[0]
		if kind not in WastelandSession.LOOSE_SCENERY and kind!="brush": continue
		var point: Vector3 = entry[1]
		var root_xz := Vector2(point.x,point.z)
		if cut.distance_squared_to(root_xz)>4.0 or stream.excavation_at(root_xz)>-0.46: continue
		var diff: Dictionary = stream.edit_chunk(cell)
		if not diff.has("removed"): diff.removed={}
		if diff.removed.has(key): continue
		diff.removed[key]=true
		diff.get("resources",{}).erase(key)
		diff.get("specialist_work",{}).erase(key)
		if entry[2]==null: erase_small_nature(key)
		else: remove_resource(entry[2])
		stream.get_parent().drop_materials(point,WastelandSession.RESOURCES[kind][2])

func remove_resource(body: StaticBody3D) -> void:
	var key: String = body.get_meta("index")
	standing_trees.erase(key)
	if small_nature.has(key):
		erase_small_nature(key)
		return
	if planted.erase(key):
		body.hide()
	else:
		hide_instance(body.get_meta("group"),body.get_meta("instance"))
	body.collision_layer = 0
	body.queue_free()

func hide_instance(group: String, index: int) -> void:
	for batch: MultiMeshInstance3D in instances[group]:
		var transform := batch.multimesh.get_instance_transform(index)
		transform.basis = Basis.IDENTITY.scaled(Vector3.ONE * 0.0001)
		batch.multimesh.set_instance_transform(index, transform)

static func _nature_shape(id: String) -> Vector3:
	match id:
		"oak", "pine": return Vector3(0.54, 3.8, 0.54)
		"boulder", "ore": return Vector3(1.1, 1.10, 1.01)
		"fallen_stick","pebble": return Vector3(0.68,0.26,0.58)
		"iron_vein": return Vector3(1.22,0.85,1.10)
		"cactus": return Vector3(0.82,1.62,0.48)
		"herb_patch": return Vector3(0.81,0.56,0.81)
		"reed_bed": return Vector3(0.87,1.22,0.87)
		"machine_wreck": return Vector3(1.14,0.95,0.84)
		"brush": return Vector3(0.72, 0.65, 0.72)
		"salvage": return Vector3(0.75, 0.58, 0.77)
		_: return Vector3(0.82, 0.49, 0.87)

static func _nature_mesh(id: String, variant: int, detail: bool) -> Mesh:
	var key := "%s/%d/%d" % [id, variant, int(detail)]
	if not nature_meshes.has(key):
		if id in ["meadow_grass","sedge","cactus","dry_scrub","snowstone","snow_fir","frost_fir","birch","snag","strata"]:
			nature_meshes[key]=preload("res://game/world/inland_scenery.gd").build(id,variant,detail)
		elif id in ["herb_patch","reed_bed","iron_vein","machine_wreck"]:
			nature_meshes[key]=preload("res://game/art/harvest_nodes.gd").harvest_mesh(id,variant,detail)
		else:
			nature_meshes[key] = WastelandScenery.build(id, variant, detail)
	return nature_meshes[key]
