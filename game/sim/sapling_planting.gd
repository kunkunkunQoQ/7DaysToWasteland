extends RefCounted

const REACH := 4.1
const TREE_SPACING := preload("res://game/sim/grove.gd").SPACING
const MIN_UP := 0.82
const CLEAR_HEIGHT := 16.0
static var clearance: CylinderShape3D

static func aim(session: WastelandSession) -> Dictionary:
	return session._trace(REACH, 15, true)

static func obstruction(session: WastelandSession, hit: Dictionary) -> String:
	if is_instance_valid(session.player.mount_vehicle): return "下车或靠岸后种树"
	if session.player.swimming or session.player.submerged or hit.has("water"): return "树苗需要干燥的陆地"
	var ground := hit.get("collider") as StaticBody3D
	if not is_instance_valid(ground) or not hit.has("position") or ground.get_meta("kind","")!="terrain":
		return "瞄准近处的天然地面"
	var point: Vector3 = hit.position
	var root_xz := Vector2(point.x,point.z)
	var chunk: WastelandChunk = session.stream.active.get(WastelandTerrainGen.chunk_at(root_xz))
	if chunk==null or ground!=chunk.terrain_body: return "瞄准近处的天然地面"
	if point.distance_squared_to(session.player.camera.global_position)>REACH*REACH+0.001: return "走近一些再种树"
	if session.stream.water_at(point): return "树苗需要干燥的陆地"
	if chunk.spring_at.is_finite():
		var spring_offset := (root_xz-Vector2(chunk.spring_at.x,chunk.spring_at.z))/Vector2(1.82,1.3)
		if spring_offset.length_squared()<=1.0: return "树苗需要干燥的陆地"
	if Vector3(hit.normal).y<MIN_UP: return "坡面太陡，换一块缓地"
	var feet := session.player.global_position
	if root_xz.distance_squared_to(Vector2(feet.x,feet.z))<0.85*0.85: return "后退一步，给树苗留出位置"
	if session.grove.near_tree(point,TREE_SPACING) or _wild_tree_near(session,root_xz): return "距其他树木至少 3 米"
	if session.stream.in_nest_cave(point): return "树苗上方需要露天空间"
	if clearance==null:
		clearance=CylinderShape3D.new()
		clearance.radius=0.8
		clearance.height=CLEAR_HEIGHT
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=clearance
	query.transform.origin=point+Vector3.UP*(CLEAR_HEIGHT*0.5-0.12)
	query.collision_mask=2 | 4 | 8
	query.exclude=[session.player.get_rid()]
	for contact: Dictionary in session.get_world_3d().direct_space_state.intersect_shape(query):
		var body: Object=contact.collider
		if body.get_meta("resource","") in WastelandSession.LOOSE_SCENERY: continue
		return "四周和上方需要留出空间"
	var sky:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*(CLEAR_HEIGHT-0.15),point+Vector3.UP*2048.0,2)
	sky.hit_from_inside=true
	if not session.get_world_3d().direct_space_state.intersect_ray(sky).is_empty(): return "树苗上方需要露天空间"
	return ""

static func _wild_tree_near(session: WastelandSession, point: Vector2) -> bool:
	var first := WastelandTerrainGen.chunk_at(point-Vector2.ONE*TREE_SPACING)
	var last := WastelandTerrainGen.chunk_at(point+Vector2.ONE*TREE_SPACING)
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			var chunk: WastelandChunk=session.stream.active.get(Vector2i(x,z))
			if not chunk: continue
			for tree: StaticBody3D in chunk.standing_trees.values():
				var p := tree.global_position
				if point.distance_squared_to(Vector2(p.x,p.z))<TREE_SPACING*TREE_SPACING: return true
	return false

static func plant(session: WastelandSession, id: String) -> bool:
	var item: Dictionary=session.catalog.items.get(id,{})
	if session.replica or session.bag.current()!=id or item.get("kind","")!="sapling": return false
	var hit := aim(session)
	var reason := obstruction(session,hit)
	if not reason.is_empty():
		session.notify(reason,1.5)
		return false
	var bag := session.bag
	var automatic := bag.automatic_shortcuts.has(id)
	if not bag.spend({id:1}): return false
	if not session.grove.plant(item.tree_model,hit.position):
		# Restore the originating shortcut even if spending the last seedling cleared it.
		bag.counts[id]=bag.count(id)+1
		if automatic:
			bag.bar[bag.active]=id
			bag.automatic_shortcuts[id]=true
		session.notify("此处暂时无法种树",1.5)
		return false
	session.player.hand.swing_attack(0.45)
	session.notify("已种下"+session.catalog.title(id),1.6)
	return true
