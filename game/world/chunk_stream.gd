class_name WastelandStream
extends Node3D

const SIZE := WastelandTerrainGen.SIZE
const CONCURRENT := 3
const GUEST_RADIUS := 2

class BuildJob:
	extends RefCounted
	var seed_value: int
	var revision: int
	var cell: Vector2i
	var delta: Dictionary
	var terrain_only: bool
	var product: Dictionary
	func run() -> void:
		product = WastelandTerrainGen.new(seed_value, revision).build(cell, delta, not terrain_only)

signal chunk_loaded(cell: Vector2i)
signal chunk_unloaded(cell: Vector2i)
signal plantings_changed(cell: Vector2i)
signal terrain_updated(cell: Vector2i)
signal structure_changed(cell: Vector2i)

var catalog: WastelandCatalog
var atmosphere: WastelandAtmosphere
var generator: WastelandTerrainGen
var radius := 4
var active: Dictionary = {}
var diffs: Dictionary = {}
var digs: Dictionary = {}
var dig_cells: Dictionary = {}
var pending_settling: Dictionary = {}
var discovered: Dictionary = {}
var get_blockers := Callable()
var get_body := Callable()
var queued: Array[Vector2i] = []
var nav_dirty: Dictionary = {}
var jobs: Dictionary = {}
var dirty: Dictionary = {}
var nav_inflight: Array[NavigationMesh] = []
var center := Vector2i(-99999, -99999)
var guest_centers: Array[Vector2i]=[]
var ready_for_streaming := false
var is_preview := false
var loot_day := 1
var refill_days := 0
var lake_wildlife: WastelandLakeWildlife

func start(seed_value: int, data: WastelandCatalog, atmosphere_node: WastelandAtmosphere, snapshot: Dictionary, preview: bool = false, revision: int = WastelandTerrainGen.CURRENT_REVISION) -> void:
	catalog = data
	atmosphere = atmosphere_node
	generator = WastelandTerrainGen.new(seed_value, revision)
	atmosphere.set_distant_basin(generator)
	diffs = snapshot.get("diffs", {}).duplicate(true)
	digs = snapshot.get("digs", {}).duplicate()
	for key: String in digs:
		_index_dig(key, false)
	discovered = snapshot.get("discovered", {}).duplicate()
	is_preview = preview

func prime(p: Vector3) -> void:
	center = WastelandTerrainGen.chunk_at(Vector2(p.x, p.z))
	_install(center, generator.build(center, _delta_for(center)))
	if not is_preview and lake_wildlife == null:
		lake_wildlife = WastelandLakeWildlife.new()
		add_child(lake_wildlife)
		lake_wildlife.configure(self)
	ready_for_streaming = true
	_queue_neighborhood()

func refresh(at: Vector3, next_radius: int, guests:Array[Vector3]=[]) -> void:
	var new_cell := WastelandTerrainGen.chunk_at(Vector2(at.x, at.z))
	var next_centers:Array[Vector2i]=[]
	for point:Vector3 in guests:
		var cell:=WastelandTerrainGen.chunk_at(Vector2(point.x,point.z))
		if cell!=new_cell and not next_centers.has(cell): next_centers.append(cell)
	if new_cell!=center or radius!=next_radius or next_centers!=guest_centers:
		radius = next_radius
		center = new_cell
		guest_centers=next_centers
		_queue_neighborhood()
	if not is_preview:
		var observers:Array[Vector2i]=[center]
		observers.append_array(guest_centers)
		for cell:Vector2i in observers:
			for offset in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				discovered[WastelandTerrainGen.grid_key(cell+offset)]=true

func ensure_landing(at: Vector3) -> void:
	var loc := WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))
	if active.has(loc):
		return
	var data: Dictionary
	if jobs.has(loc):
		var entry: Array=jobs[loc]
		WorkerThreadPool.wait_for_task_completion(entry[0])
		data=entry[1].product
		if entry[1].terrain_only or dirty.has(loc):
			data=generator.build(loc,_delta_for(loc))
			dirty.erase(loc)
		jobs.erase(loc)
	else:
		data=generator.build(loc,_delta_for(loc))
	queued.erase(loc)
	_install(loc,data)

func _queue_neighborhood() -> void:
	queued.clear()
	var wanted: Dictionary={}
	_queue_around(wanted,center,radius)
	for loc:Vector2i in guest_centers: _queue_around(wanted,loc,GUEST_RADIUS)
	for cell:Vector2i in wanted:
		if not active.has(cell) and not jobs.has(cell): queued.append(cell)
	queued.sort_custom(func(a:Vector2i,b:Vector2i):return wanted[a]<wanted[b])
	for coord in active.keys():
		if not _inside(coord, radius + 1):
			chunk_unloaded.emit(coord)
			active[coord].queue_free()
			active.erase(coord)
			nav_dirty.erase(coord)
			dirty.erase(coord)

func _queue_around(wanted:Dictionary,loc:Vector2i,extent:int)->void:
	for z in range(-extent,extent+1):
		for x in range(-extent,extent+1):
			var cell:=loc+Vector2i(x,z)
			var distance:=x*x+z*z
			wanted[cell]=mini(int(wanted.get(cell,distance)),distance)

func _inside(cell: Vector2i, extent: int) -> bool:
	var offset := (cell - center).abs()
	if maxi(offset.x,offset.y)<=extent: return true
	for loc:Vector2i in guest_centers:
		offset=(cell-loc).abs()
		if maxi(offset.x,offset.y)<=GUEST_RADIUS+extent-radius: return true
	return false

func _process(_delta: float) -> void:
	if not ready_for_streaming:
		return
	if not nav_inflight.is_empty():
		nav_inflight = nav_inflight.filter(NavigationServer3D.is_baking_navigation_mesh)
	var applied := 0
	for cell in jobs.keys():
		var tuple: Array = jobs[cell]
		if not WorkerThreadPool.is_task_completed(tuple[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(tuple[0])
		var job: BuildJob = tuple[1]
		jobs.erase(cell)
		if _inside(cell, radius + 1):
			if active.has(cell):
				active[cell].update_ground(job.product)
				settle_interactables(cell)
				nav_dirty[cell] = true
				terrain_updated.emit(cell)
			elif not job.terrain_only:
				_install(cell, job.product)
			else:
				queued.append(cell)
			applied += 1
			if applied >= 2:
				break
	while jobs.size() < CONCURRENT:
		var key: Vector2i
		var terrain_only := not dirty.is_empty()
		if terrain_only:
			key = dirty.keys()[0]
			if jobs.has(key):
				break
			dirty.erase(key)
		elif not queued.is_empty():
			key = queued.pop_front()
		else:
			break
		var item := BuildJob.new()
		item.seed_value = generator.seed_value
		item.revision = generator.revision
		item.cell = key
		item.delta = _delta_for(key)
		item.terrain_only = terrain_only and active.has(key)
		jobs[key] = [WorkerThreadPool.add_task(item.run), item]
	if not nav_dirty.is_empty() and applied < 2:
		var cell: Vector2i = nav_dirty.keys()[0]
		nav_dirty.erase(cell)
		if active.has(cell):
			active[cell].rebuild_navigation()

func _exit_tree() -> void:
	_finish_workers()

func _finish_workers() -> void:
	for tuple in jobs.values():
		WorkerThreadPool.wait_for_task_completion(tuple[0])
	jobs.clear()

func quiesce() -> void:
	ready_for_streaming = false
	_finish_workers()
	while not nav_inflight.is_empty():
		nav_inflight = nav_inflight.filter(NavigationServer3D.is_baking_navigation_mesh)
		if not nav_inflight.is_empty():
			await get_tree().process_frame

func _install(cell: Vector2i, data: Dictionary) -> void:
	var chunk := WastelandChunk.new()
	add_child(chunk)
	chunk.install(self, cell, data)
	active[cell] = chunk
	if dig_cells.has(cell) or chunk_diff(cell).has("site_damage"): settle_interactables(cell)
	chunk_loaded.emit(cell)

func chunk_diff(cell: Vector2i) -> Dictionary:
	var key := WastelandTerrainGen.grid_key(cell)
	if not diffs.has(key):
		return {}
	return diffs[key]

func advance_loot_day(current: int) -> void:
	if loot_day == current: return
	loot_day = current
	for chunk: WastelandChunk in active.values():
		for key: String in chunk.supply_caches:
			chunk.sync_cache(key)

func edit_chunk(cell: Vector2i) -> Dictionary:
	var key := WastelandTerrainGen.grid_key(cell)
	if not diffs.has(key):
		diffs[key] = {}
	return diffs[key]

func _delta_for(cell: Vector2i) -> Dictionary:
	return dig_cells.get(cell, {}).duplicate()

func _index_dig(key: String, invalidate: bool) -> void:
	var coords := key.split(",")
	var point := Vector2i(int(coords[0]), int(coords[1]))
	atmosphere.set_horizon_sample(point,float(digs.get(key,0.0)))
	var cell := WastelandTerrainGen.chunk_at(Vector2(point))
	var cols := 2 if point.x % SIZE == 0 else 1
	var rows := 2 if point.y % SIZE == 0 else 1
	for dx in cols:
		for dz in rows:
			var owner := cell - Vector2i(dx,dz)
			if digs.has(key):
				if not dig_cells.has(owner): dig_cells[owner] = {}
				dig_cells[owner][key] = digs[key]
			elif dig_cells.has(owner):
				dig_cells[owner].erase(key)
				if dig_cells[owner].is_empty(): dig_cells.erase(owner)
			if invalidate and (active.has(owner) or jobs.has(owner)): dirty[owner] = true

func excavate(at: Vector3, depth: float = 0.58) -> bool:
	if not at.is_finite() or not is_finite(depth) or depth <= 0.0: return false
	var center_point := Vector2i(roundi(at.x),roundi(at.z))
	for dz in range(-1,2):
		for dx in range(-1,2):
			var offset := Vector2i(dx,dz)
			var key := WastelandTerrainGen.grid_key(center_point + offset)
			var weight := 1.0 - Vector2(offset).length() / 1.7
			digs[key] = float(digs.get(key,0.0)) - depth * weight
			_index_dig(key,true)
	# Piles on a long dock or bridge can stand across the owning chunk's boundary.
	var owner:=WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))
	for dz in range(-1,2):
		for dx in range(-1,2):
			var neighbor:=owner+Vector2i(dx,dz)
			if not active.has(neighbor): continue
			active[neighbor].uproot_small(at)
			if not active[neighbor].footings.is_empty():
				settle_interactables(neighbor)
	return true

func _vertex_height(point: Vector2i) -> float:
	return generator.ground(point.x,point.y) + float(digs.get(WastelandTerrainGen.grid_key(point),0.0))

func excavation_at(p: Vector2) -> float:
	var v := Vector2i(p.floor())
	var f := p - Vector2(v)
	var b := float(digs.get(WastelandTerrainGen.grid_key(v+Vector2i.RIGHT),0.0))
	var c := float(digs.get(WastelandTerrainGen.grid_key(v+Vector2i.DOWN),0.0))
	if f.x+f.y<1:
		return float(digs.get(WastelandTerrainGen.grid_key(v),0.0))*(1-f.x-f.y)+b*f.x+c*f.y
	return float(digs.get(WastelandTerrainGen.grid_key(v+Vector2i.ONE),0.0))*(f.x+f.y-1)+b*(1-f.y)+c*(1-f.x)

func settle_interactables(cell: Vector2i) -> void:
	pending_settling[cell] = 2

func _physics_process(_delta: float) -> void:
	for cell: Vector2i in pending_settling.keys():
		pending_settling[cell] -= 1
		if pending_settling[cell] > 0: continue
		pending_settling.erase(cell)
		var chunk: WastelandChunk = active.get(cell)
		if chunk == null: continue
		record_settlement(chunk)
		for body in chunk.decoration_root.get_children():
			if not body is StaticBody3D or body.is_queued_for_deletion(): continue
			if body.get_meta("kind","") not in ["loot","note","trader"]: continue
			for collider in body.get_children():
				if not collider is CollisionShape3D or not collider.shape is BoxShape3D: continue
				var bottom: Vector3 = collider.global_position - Vector3.UP * collider.shape.size.y * 0.5
				var terrain := ground_at(bottom)
				if bottom.y <= terrain + 0.45: break
				var ray := PhysicsRayQueryParameters3D.create(bottom + Vector3.UP * 0.12,Vector3(bottom.x,terrain-1.0,bottom.z),11,[body.get_rid()])
				var hit := get_world_3d().direct_space_state.intersect_ray(ray)
				if not hit.is_empty() and bottom.y - hit.position.y > 0.45:
					body.global_position.y -= bottom.y - hit.position.y - 0.025
				break

func ground_at(at: Vector3) -> float:
	var p := Vector2(at.x, at.z)
	var cell := WastelandTerrainGen.chunk_at(p)
	var chunk: WastelandChunk = active.get(cell)
	if chunk == null and not dig_cells.has(cell):
		return generator.ground(p.x, p.y)
	var step := float(WastelandTerrainGen.STEP)
	var local := (p - Vector2(cell * SIZE)) / step
	var grid := WastelandTerrainGen.GRID
	var x := clampi(floori(local.x), 0, grid - 2)
	var z := clampi(floori(local.y), 0, grid - 2)
	var s := local.x - x
	var t := local.y - z
	var a: float
	var b: float
	var c: float
	var d: float
	if chunk == null:
		var origin := cell*SIZE + Vector2i(x,z)
		a = _vertex_height(origin)
		b = _vertex_height(origin+Vector2i.RIGHT)
		c = _vertex_height(origin+Vector2i.DOWN)
		d = _vertex_height(origin+Vector2i.ONE)
	else:
		var samples: PackedVector3Array = chunk.navigation_data.points
		var index := z * grid + x
		a = samples[index].y
		b = samples[index + 1].y
		c = samples[index + grid].y
		d = samples[index + grid + 1].y
	if s + t < 1.0:
		return a * (1.0 - s - t) + b * s + c * t
	return d * (s + t - 1.0) + b * (1.0 - t) + c * (1.0 - s)

func at_surface(at: Vector3) -> bool:
	return active.has(WastelandTerrainGen.chunk_at(Vector2(at.x, at.z)))

func ground_normal_at(at: Vector3) -> Vector3:
	var position_2d := Vector2(at.x,at.z)
	var cell := WastelandTerrainGen.chunk_at(position_2d)
	var chunk: WastelandChunk = active.get(cell)
	if chunk == null:
		return Vector3.UP
	var step := float(WastelandTerrainGen.STEP)
	var grid := WastelandTerrainGen.GRID
	var local := (position_2d-Vector2(cell*SIZE))/step
	var corner := Vector2i(local.floor()).clamp(Vector2i.ZERO,Vector2i.ONE*(grid-2))
	var offset := local-Vector2(corner)
	var i := corner.y*grid+corner.x
	var points: PackedVector3Array = chunk.navigation_data.points
	if offset.x+offset.y<1.0:
		return Vector3(points[i].y-points[i+1].y,step,points[i].y-points[i+grid].y).normalized()
	return Vector3(points[i+grid].y-points[i+grid+1].y,step,points[i+1].y-points[i+grid+1].y).normalized()

func mineral_warmth(at:Vector3)->float:
	var chunk:WastelandChunk=active.get(WastelandTerrainGen.chunk_at(Vector2(at.x,at.z)))
	if chunk==null or not chunk.spring_at.is_finite() or absf(chunk.spring_at.y-at.y)>1.6: return 0.0
	var delta:=Vector2(at.x-chunk.spring_at.x,at.z-chunk.spring_at.z)
	return 21.0*(1.0-smoothstep(1.2,3.8,delta.length()))

func in_nest_cave(at: Vector3) -> bool:
	var cell := WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))
	var chunk: WastelandChunk = active.get(cell)
	if chunk == null or not chunk.cave_origin.is_finite(): return false
	var inside := at - chunk.position - chunk.cave_origin
	var floor_y := ground_at(at)
	return absf(inside.x) <= 2.1 and inside.z >= -4.7 and inside.z <= 0.0 and at.y >= floor_y - 0.25 and at.y <= floor_y + 2.85

func below_terrain(at: Vector3) -> bool:
	var floor_y := ground_at(at)
	if at.y >= floor_y-5.0: return false
	# At a steep cut the capsule can straddle a lower vertex and a high wall.
	var nearby := Vector3(roundf(at.x),0,roundf(at.z))
	return at.y < minf(floor_y,ground_at(nearby))-5.0

func water_at(at: Vector3) -> bool:
	var cell := WastelandTerrainGen.chunk_at(Vector2(at.x, at.z))
	var chunk: WastelandChunk = active.get(cell)
	return chunk != null and chunk.water != null and chunk.water.visible and generator.water_basin(at.x, at.z) and ground_at(at) < WastelandTerrainGen.WATER_LEVEL

func invalidate_at(p: Vector3i) -> void:
	var cell := WastelandTerrainGen.chunk_at(Vector2(p.x, p.z))
	if active.has(cell):
		nav_dirty[cell] = true

func record_settlement(chunk: WastelandChunk, lost_bearing := false) -> void:
	var session: WastelandSession=get_parent()
	var batches := {}
	var collect_materials := func(id: String):
		var yields := preload("res://game/world/structural_salvage.gd").materials(chunk,id)
		if yields.is_empty(): return
		var at:=preload("res://game/world/structural_salvage.gd").origin(chunk,id)
		if not at.is_finite(): return
		# Neighbouring pieces from the same collapsed bay can land as one stack.
		var bin:=Vector3i((at/1.5).floor())
		if not batches.has(bin): batches[bin]={"point":at,"items":{}}
		var bundle:Dictionary=batches[bin].items
		for item: String in yields: bundle[item]=int(bundle.get(item,0))+int(yields[item])
	var fallen := chunk.settle_structures(true,collect_materials if not session.replica else Callable())
	if fallen.is_empty() and not lost_bearing: return
	nav_dirty[chunk.cell]=true
	if session.replica: return
	var diff:=edit_chunk(chunk.cell)
	if not diff.has("site_damage"): diff.site_damage={}
	for id in fallen:
		diff.site_damage[id]=0.0
		if diff.has("wall_marks"): diff.wall_marks.erase(id)
	for batch: Dictionary in batches.values():
		session.drop_materials(batch.point,batch.items,Vector3.ZERO)
	structure_changed.emit(chunk.cell)

func mirror_deltas(next_diffs: Dictionary,next_digs: Dictionary) -> void:
	var last_diffs:=diffs
	diffs=next_diffs
	for cell in active:
		var key:=WastelandTerrainGen.grid_key(cell)
		var before:Dictionary=last_diffs.get(key,{})
		var after:Dictionary=diffs.get(key,{})
		var collected:Dictionary=after.get("removed",{})
		var old_removed:Dictionary=before.get("removed",{})
		var site_damage:Dictionary=after.get("site_damage",{})
		var chunk:WastelandChunk=active[cell]
		if before.get("fixture_health",{})!=after.get("fixture_health",{}) or before.get("board_y")!=after.get("board_y"):
			chunk.sync_fixtures()
		if before.get("containers",{}) != after.get("containers",{}):
			for id: String in chunk.supply_caches:
				chunk.sync_cache(id)
		if collected!=old_removed:
			for key_id: String in collected:
				if not old_removed.has(key_id): chunk.erase_small_nature(key_id)
			for node in chunk.decoration_root.get_children():
				var id:Variant=node.get_meta("index","")
				if not node.is_queued_for_deletion() and node.get_meta("kind","")=="resource" and collected.has(id) and not old_removed.has(id):
					chunk.remove_resource(node)
		var cuts: Dictionary = after.get("tree_cuts",{})
		var previous_cuts: Dictionary = before.get("tree_cuts",{})
		if before.get("planted_trees",{}) != after.get("planted_trees",{}) or (not chunk.planted.is_empty() and cuts != previous_cuts):
			plantings_changed.emit(cell)
		if cuts != previous_cuts:
			for id: String in previous_cuts:
				if not cuts.has(id): chunk.sync_tree_cut(id,{})
			for id: String in cuts:
				if previous_cuts.get(id) != cuts[id]: chunk.sync_tree_cut(id,cuts[id])
		if site_damage!=before.get("site_damage",{}):
			var removed_structure := false
			for id: String in site_damage:
				var hp := float(site_damage[id])
				if before.get("site_damage",{}).get(id)!=site_damage[id]:
					chunk.set_structure_health(id,hp,hp<=0 and chunk.support_graph.has(id))
					removed_structure = removed_structure or hp<=0
			if removed_structure:
				nav_dirty[cell]=true
				if has_method("settle_interactables"): call("settle_interactables",cell)
	if digs!=next_digs:
		var last_digs:=digs
		digs=next_digs
		var all_points:=last_digs.duplicate()
		all_points.merge(digs,true)
		for point in all_points:
			if last_digs.get(point)==digs.get(point):
				continue
			_index_dig(point,true)
