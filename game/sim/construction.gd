class_name WastelandConstruction
extends Node3D

const Fire:=preload("res://game/sim/station_fire.gd")
const BuildShapes := preload("res://game/art/construction_shapes.gd")
const BuildDevices := preload("res://game/art/construction_devices.gd")

const HP := [50.0, 250.0, 1000.0, 2500.0, 5000.0]
const OLD_HP := [72.0, 245.0, 520.0, 1280.0, 2400.0]
const MASS := [3.0, 5.0, 10.0, 15.0, 20.0]
const SUPPORT := [18.0, 40.0, 120.0, 240.0, 400.0]
const UPGRADE := [{"wood": 8}, {"cobble": 10}, {"concrete": 10}, {"steel": 12}]
const REPAIR := [{"wood": 1}, {"wood": 1}, {"cobble": 1}, {"concrete": 1}, {"steel": 1}]
const TONES := ["b68a62", "9d6946", "8c8578", "b1aaa0", "778695"]
const DIRS := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
const EDGES := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
const DEVICE_COLOR := {
	"campfire": "#dc8f64", "bench": "#957056", "forge": "#958287", "chemistry": "#779897",
	"spikes": "#ae8157", "barbed": "#9495a1", "mine": "#9f846c", "generator": "#bb8157",
	"solar": "#657299", "battery": "#7f8999", "floodlight": "#e8ca8c", "blade": "#9897a8",
	"fence": "#8287ad", "turret": "#7d7a85",
}

var session: Node3D
var blocks: Dictionary = {}
var chunk_index: Dictionary = {}
var station_index: Dictionary = {}
var fired: Dictionary = {}
var crops: Dictionary = {}
var crop_nodes: Dictionary = {}
var nodes: Dictionary = {}
var wires: Array = []
var wire_nodes: Array[MeshInstance3D] = []
var powered: Dictionary = {}
var pause_wire := false
var selected_wire = null
var place_preview: Node3D
var preview_mesh: MeshInstance3D
var preview_cache := ""
var ghost := ShaderMaterial.new()
var ghost_shader: Shader
var unloaded_devices: Array = []
var materials: Dictionary = {}
var shape_meshes: Dictionary = {}
var next_sim := 0.0
var device_elapsed:=0.0
var tool_jobs: Dictionary = {}
var trap_probe := PhysicsShapeQueryParameters3D.new()

static func position_of(cell: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3.ONE * 0.5

static func cell_at(at: Vector3) -> Vector3i:
	return Vector3i(floori(at.x), floori(at.y), floori(at.z))

func configure(owner_session: Node3D, state: Dictionary) -> void:
	session = owner_session
	var contact_shape := BoxShape3D.new()
	contact_shape.size = Vector3(0.88, 0.88, 0.88)
	trap_probe.shape = contact_shape
	trap_probe.collision_mask = 4
	blocks = state.get("blocks", {}).duplicate(true)
	crops = state.get("crops", {}).duplicate(true)
	wires = state.get("wires", []).duplicate(true)
	for cell in blocks:
		var data: Dictionary = blocks[cell]
		if data.device == "" and int(state.get("integrity_version", 0)) == 0:
			var tier := int(data.tier)
			data.hp = clampf(float(data.hp) / OLD_HP[tier], 0.0, 1.0) * HP[tier]
		_index(cell, blocks[cell])
	for cell: Vector3i in crops:
		if not crops[cell].has("soil_depth"):
			crops[cell].soil_depth = _soil_depth(cell)
	place_preview = Node3D.new()
	place_preview.visible = false
	add_child(place_preview)
	preview_mesh = MeshInstance3D.new()
	preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	place_preview.add_child(preview_mesh)
	ghost.shader = preload("res://shaders/build_grid.gdshader")
	preview_mesh.material_override = ghost
	session.stream.get_blockers = get_blockers
	session.stream.get_body = _get_body
	session.stream.chunk_loaded.connect(on_chunk_loaded)
	session.stream.chunk_unloaded.connect(on_chunk_unloaded)
	session.stream.terrain_updated.connect(_foundation_changed)
	session.stream.structure_changed.connect(_site_bearings_changed)

func state() -> Dictionary:
	return {"integrity_version": 1, "blocks": blocks, "crops": crops, "wires": wires}

func get_blockers(loc: Vector2i) -> Dictionary:
	return chunk_index.get(loc, {})

func _get_body(cell: Vector3i) -> StaticBody3D:
	return nodes.get(cell)

func _foundation_changed(chunk: Vector2i) -> void:
	if not session.replica:
		settle(get_blockers(chunk).keys())
		for cell: Vector3i in crops.keys():
			if WastelandTerrainGen.chunk_at(Vector2(cell.x,cell.z))==chunk and _soil_depth(cell)<float(crops[cell].soil_depth)-0.42:
				remove_plot(cell)

func _site_bearings_changed(owner: Vector2i) -> void:
	if session.replica: return
	var affected: Array[Vector3i]=[]
	for dz in range(-1,2):
		for dx in range(-1,2):
			for cell: Vector3i in get_blockers(owner+Vector2i(dx,dz)):
				for ref: Array in blocks[cell].get("site_bearings",[]):
					if ref[0]==owner:
						affected.append(cell)
						break
	if not affected.is_empty(): settle(affected)

func _index(cell: Vector3i, data: Dictionary) -> void:
	var chunk := WastelandTerrainGen.chunk_at(Vector2(cell.x, cell.z))
	if not chunk_index.has(chunk):
		chunk_index[chunk] = {}
	chunk_index[chunk][cell] = true
	if data.device != "":
		station_index[cell] = str(data.device)

func _unindex(cell: Vector3i) -> void:
	var chunk := WastelandTerrainGen.chunk_at(Vector2(cell.x, cell.z))
	if chunk_index.has(chunk):
		chunk_index[chunk].erase(cell)
		if chunk_index[chunk].is_empty():
			chunk_index.erase(chunk)
	station_index.erase(cell)

func on_chunk_loaded(chunk: Vector2i) -> void:
	for cell in get_blockers(chunk):
		_mount(cell)
		session.stream.nav_dirty[chunk] = true
	for cell in crops:
		if WastelandTerrainGen.chunk_at(Vector2(cell.x, cell.z)) == chunk:
			_show_crop(cell)
	_rebuild_wires()

func on_chunk_unloaded(chunk: Vector2i) -> void:
	for cell in get_blockers(chunk):
		_unmount(cell)
	for cell in crop_nodes.keys():
		if WastelandTerrainGen.chunk_at(Vector2(cell.x, cell.z)) == chunk:
			crop_nodes[cell].queue_free()
			crop_nodes.erase(cell)
	_rebuild_wires()

func target_position(hit: Dictionary) -> Vector3i:
	var at: Vector3 = hit.position
	var body: Object = hit.get("collider")
	if is_instance_valid(body) and body.get_meta("kind","") == "terrain":
		return Vector3i(floori(at.x), ceili(at.y - 0.42), floori(at.z))
	if is_instance_valid(body) and body.get_meta("kind","")=="poi_wall" and hit.normal.y>0.85:
		return Vector3i(floori(at.x),roundi(at.y),floori(at.z))
	return cell_at(at + hit.normal * 0.29)

func can_place(cell: Vector3i, player: Vector3, item: String) -> bool:
	if blocks.has(cell) or crops.has(cell) or position_of(cell).distance_to(player + Vector3.UP * 0.85) < 1.20:
		return false
	if session.bag.count(item) <= 0 or not session.stream.at_surface(position_of(cell)):
		return false
	var ground: float = session.stream.ground_at(position_of(cell))
	if cell.y + 0.60 < ground or cell.y > 240:
		return false
	if not _on_ground(cell) and _site_bearings(cell).is_empty():
		var supported := false
		for direction in DIRS:
			if blocks.has(cell + direction):
				supported = true
				break
		if not supported:
			return false
	var probe := BoxShape3D.new()
	probe.size = Vector3.ONE * 0.78
	var check := PhysicsShapeQueryParameters3D.new()
	check.shape = probe
	check.transform.origin = position_of(cell)
	check.collision_mask = 2 | 4 | 8
	return get_world_3d().direct_space_state.intersect_shape(check, 1).is_empty()

func preview(hit: Dictionary, item: String, shape: int, rotation_step: int, player: Vector3) -> void:
	place_preview.visible = not hit.is_empty() and (item == "frame" or DEVICE_COLOR.has(item))
	if not place_preview.visible:
		return
	var cell := target_position(hit)
	var device := item if item != "frame" else ""
	place_preview.position = position_of(cell)
	place_preview.rotation.y = rotation_step * PI / 2.0
	var key := str(shape) + device
	if preview_cache != key:
		preview_mesh.mesh = _mesh(0, shape, device, false)
		preview_cache = key
	ghost.set_shader_parameter("valid", can_place(cell, player, item))

func place(cell: Vector3i, item: String, shape: int, rotation_step: int, player: Vector3) -> bool:
	if not can_place(cell, player, item) or not session.bag.spend({item: 1}):
		return false
	var device := item if item != "frame" else ""
	blocks[cell] = {
		"tier": 0, "shape": shape, "turn": rotation_step, "hp": HP[0] if device == "" else 260.0,
		"device": device, "open": false, "enabled": device not in ["generator","campfire","forge"], "charge": 0.0,
		"fuel": 0.0, "ammo": 0, "queue": [], "out": {},
	}
	if not _on_ground(cell):
		var bearings := _site_bearings(cell)
		if not bearings.is_empty(): blocks[cell].site_bearings=bearings
	_index(cell, blocks[cell])
	_mount(cell)
	session.stream.invalidate_at(cell)
	var fallen := settle([cell])
	session.audio.play_at("place", position_of(cell), 0.92)
	if fallen > 0:
		session.notify("支撑不足 · %d 个构件坍塌" % fallen)
	else:
		session.gain(7, "build")
	return fallen == 0

func _max_hp(block: Dictionary) -> float:
	return HP[int(block.tier)] if block.device == "" else 260.0

func reinforcement_text(cell:Vector3i)->String:
	var info:Dictionary=blocks.get(cell,{})
	if info.is_empty() or (info.device=="" and int(info.tier)<2): return "加固包适用于石质以上构件及设施"
	var missing:=_max_hp(info)-float(info.hp)
	if missing<=0: return "结构完好 · 已保留加固包"
	return "使用加固包修复 %d 耐久"%ceili(minf(480,missing))

func reinforce(cell:Vector3i)->bool:
	var info:Dictionary=blocks.get(cell,{})
	if info.is_empty(): return false
	var full:=_max_hp(info)
	if (info.device=="" and int(info.tier)<2) or info.hp>=full:
		session.notify(reinforcement_text(cell))
		return false
	if not session.bag.spend({"reinforcement_kit":1}): return false
	info.hp=minf(full,float(info.hp)+480.0)
	_refresh_surface(cell)
	session.audio.play_at("hammer",position_of(cell),1.05)
	session.notify("结构已加固 · 耐久 %d/%d"%[roundi(info.hp),roundi(full)])
	return true

static func maintenance_tool(id: String) -> bool:
	return id in ["stone_axe", "iron_axe", "steel_axe", "iron_hammer", "sledge", "salvage_wrench"]

func upgrade_text(cell: Vector3i) -> String:
	var info: Dictionary = blocks.get(cell, {})
	if info.is_empty() or info.device != "":
		return ""
	var tier := int(info.tier)
	if float(info.hp) < HP[tier]:
		return "维修%s %d/%d（消耗 %s）" % [WastelandCatalog.TIER_NAMES[tier], ceili(info.hp), int(HP[tier]), session.catalog.requirements(REPAIR[tier])]
	if tier < HP.size() - 1:
		return "升级为%s（消耗 %s）" % [WastelandCatalog.TIER_NAMES[tier + 1], session.catalog.requirements(UPGRADE[tier])]
	return "锻钢装甲完好 · 5000/5000"

func begin_work(cell: Vector3i, tool: String) -> void:
	var info: Dictionary = blocks.get(cell, {})
	if session.replica or not nodes.has(cell) or not maintenance_tool(tool) or info.is_empty() or info.device != "":
		return
	var tier := int(info.tier)
	var repair: bool = float(info.hp) < HP[tier]
	if not repair and tier == HP.size() - 1:
		session.notify(upgrade_text(cell))
		return
	var cost: Dictionary = REPAIR[tier] if repair else UPGRADE[tier]
	if not session.bag.has_all(cost):
		session.notify("缺少建材 · " + session.catalog.requirements(cost))
		return
	var span := (0.48 if repair else 0.80 + tier * 0.12) * (0.78 if tool in ["iron_hammer", "sledge"] else 1.0)
	tool_jobs[session.player.get_instance_id()] = {"cell":cell, "body":nodes[cell], "tool":tool, "tier":tier, "repair":repair,
		"elapsed":0.0, "span":span, "last":session.clock.elapsed}
	session.action_lock = span
	session.player.hand.swing_attack(1.05)
	session.hint = "敲击中 · 0%"

func tick_work(delta: float, held: String) -> bool:
	var operator_id: int = session.player.get_instance_id()
	if not tool_jobs.has(operator_id):
		return false
	var job: Dictionary = tool_jobs[operator_id]
	var cell: Vector3i = job.cell
	var info: Dictionary = blocks.get(cell, {})
	var aimed: Object = session._trace(5.5, 3).get("collider")
	if info.is_empty() or not is_instance_valid(job.body) or job.body != aimed or held != job.tool or int(info.tier) != int(job.tier) or session.clock.elapsed - float(job.last) > 0.35 or session.action_pressed("fire") or session.action_pressed("use"):
		tool_jobs.erase(operator_id)
		return false
	job.last = session.clock.elapsed
	job.elapsed = float(job.elapsed) + delta
	session.hint = "敲击中 · %d%%" % mini(100, roundi(100.0 * float(job.elapsed) / float(job.span)))
	if float(job.elapsed) >= float(job.span):
		tool_jobs.erase(operator_id)
		# A teammate or a zombie can change the required operation during a swing.
		if bool(job.repair) == (float(info.hp) < HP[int(info.tier)]):
			upgrade(cell)
		session.next_hint = 0.0
	return true

func recover_frame(cell: Vector3i) -> bool:
	var info: Dictionary = blocks.get(cell, {})
	if session.replica or info.is_empty() or info.device != "" or int(info.tier) != 0:
		return false
	if session.bag.add("frame", 1) != 1:
		session.notify("背包已满，木框架仍在原处")
		return false
	destroy(cell, false, true)
	session.audio.play_at("place", position_of(cell), 0.65)
	return true

func upgrade(cell: Vector3i) -> void:
	var info: Dictionary = blocks.get(cell, {})
	if session.replica or info.is_empty() or info.device != "":
		return
	var tier := int(info.tier)
	if float(info.hp) < HP[tier]:
		if not session.bag.spend(REPAIR[tier]):
			session.notify("缺少建材 · " + session.catalog.requirements(REPAIR[tier]))
			return
		info.hp = minf(HP[tier], float(info.hp) + ceilf(HP[tier] * 0.2))
		_refresh_surface(cell)
		session.audio.play_at("hammer", position_of(cell), 1.05)
		return
	if tier == HP.size() - 1:
		return
	elif session.bag.spend(UPGRADE[tier]):
		info.tier = tier + 1
		info.hp = HP[tier + 1]
		session.gain(15, "build")
	else:
		session.notify("缺少建材 · " + session.catalog.requirements(UPGRADE[tier]))
		return
	_unmount(cell)
	_mount(cell)
	settle([cell])
	session.audio.play_at("hammer", position_of(cell), 1.05)

func damage(cell: Vector3i, amount: float) -> void:
	if session.replica or amount <= 0.0 or not blocks.has(cell):
		return
	var info: Dictionary = blocks[cell]
	info.hp = float(info.hp) - amount
	if info.hp <= 0.0:
		destroy(cell)
		return
	_refresh_surface(cell)

func surface_material(cell: Vector3i) -> String:
	var info: Dictionary = blocks.get(cell, {})
	if info.is_empty(): return ""
	match str(info.device):
		"": return REPAIR[int(info.tier)].keys()[0]
		"bench", "spikes": return "wood"
		"campfire": return "stone"
		"forge": return "brick"
		_: return "metal"

func _salvage(info: Dictionary) -> Dictionary:
	var device: String = info.device
	if device.is_empty():
		var tier := clampi(int(info.tier),0,UPGRADE.size())
		if tier==0: return {"stick":1}
		var material: String = UPGRADE[tier-1].keys()[0]
		var count := int(UPGRADE[tier-1][material])
		if material=="concrete":
			# Cured concrete breaks into aggregate. It cannot be poured again.
			var aggregate := {}
			var mix: Dictionary = session.catalog.recipes.concrete
			for id: String in mix.inputs:
				var quantity := floori(float(mix.inputs[id])*count*0.4/int(mix.amount))
				if quantity>0: aggregate[id]=quantity
			return aggregate
		return {"stone" if material=="cobble" else material: floori(count*0.5)}
	if device=="mine": return {"scrap":1}
	var recipe: Dictionary = session.catalog.recipes.get(device,{})
	var pieces := {}
	for id: String in recipe.get("inputs",{}):
		if session.catalog.items[id].kind!="material": continue
		# One placed device may be only one of several produced by a batch.
		var count := floori(float(recipe.inputs[id])*0.4/maxi(1,int(recipe.amount)))
		if count>0:
			var material := "scrap" if id=="ingot" else "stone" if id=="cobble" else id
			pieces[material]=int(pieces.get(material,0))+count
	return pieces

func destroy(cell: Vector3i, debris: bool = true, recovered: bool = false) -> void:
	if session.replica or not blocks.has(cell):
		return
	_remove_block(cell, debris, recovered)
	settle(DIRS.map(func(offset): return cell + offset))

func _remove_block(cell: Vector3i, debris: bool, recovered: bool = false) -> void:
	if session.replica or not blocks.has(cell):
		return
	var info: Dictionary = blocks[cell]
	if debris and nodes.has(cell):
		session.fx.collapse(position_of(cell), Color.html(TONES[info.tier]))
	var contents := {} if recovered else _salvage(info)
	var stored: Dictionary = info.get("out",{}).duplicate()
	for job: Dictionary in info.get("queue",[]):
		if (not Fire.thermal(info) and float(job.done)<=session.clock.elapsed) or not job.has("inputs"):
			# Older queues retained only the output ID. Preserve the paid job once.
			stored[job.id]=int(stored.get(job.id,0))+int(job.amount)
		else:
			for item: String in job.inputs:
				stored[item]=int(stored.get(item,0))+int(job.inputs[item])
	if info.device=="turret":
		stored.heavy_round=int(stored.get("heavy_round",0))+int(info.get("ammo",0))
	elif info.device=="generator":
		stored.fuel=int(stored.get("fuel",0))+floori(float(info.get("fuel",0))/88.0)
	elif Fire.thermal(info):
		Fire.recover_store(info,stored)
		if not info.has("fuel_slots") and info.device=="campfire":
			stored.wood=int(stored.get("wood",0))+floori(float(info.get("fuel",0))/38.0)
	for item: String in stored:
		if int(stored[item])>0: contents[item]=int(contents.get(item,0))+int(stored[item])
	_unmount(cell)
	_unindex(cell)
	blocks.erase(cell)
	powered.erase(cell)
	fired.erase(cell)
	var old_size := wires.size()
	wires = wires.filter(func(edge): return edge[0] != cell and edge[1] != cell)
	if old_size != wires.size():
		contents.wire=int(contents.get("wire",0))+old_size-wires.size()
		_rebuild_wires()
	if selected_wire==cell: selected_wire=null
	session.stream.invalidate_at(cell)
	if not contents.is_empty(): session.drop_materials(position_of(cell),contents)

func _on_ground(cell: Vector3i) -> bool:
	var at := position_of(cell)
	return float(cell.y) - float(session.stream.ground_at(at)) <= 0.44

func _site_bearings(cell: Vector3i) -> Array:
	var contacts: Array = []
	var base := position_of(cell)-Vector3.UP*0.5
	for x: float in [-0.28,0.28]:
		for z: float in [-0.28,0.28]:
			var p := base+Vector3(x,0,z)
			var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.11,p-Vector3.UP*0.16,2)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.normal.y<0.85: continue
			var bearing: Object = hit.collider
			if not bearing.is_queued_for_deletion() and bearing.get_meta("kind","")=="poi_wall":
				contacts.append([bearing.get_meta("cell"),bearing.get_meta("site_id")])
	return contacts if contacts.size()>=2 else []

func _anchored(cell: Vector3i) -> bool:
	if _on_ground(cell): return true
	var bearing_count := 0
	for ref: Array in blocks[cell].get("site_bearings",[]):
		var chunk: WastelandChunk=session.stream.active.get(ref[0])
		if chunk!=null and not chunk.structures.has(ref[1]): continue
		if chunk==null and float(session.stream.chunk_diff(ref[0]).get("site_damage",{}).get(ref[1],1.0))<=0.0: continue
		bearing_count+=1
		if bearing_count>=2: return true
	return false

func is_support_column(cell: Vector3i) -> bool:
	return _column_grounded(cell, {})

func _column_grounded(cell: Vector3i, cache: Dictionary) -> bool:
	var trail: Array[Vector3i] = []
	var grounded := false
	while blocks.has(cell):
		if cache.has(cell):
			grounded = cache[cell]
			break
		trail.append(cell)
		if _anchored(cell):
			grounded = true
			break
		cell += Vector3i.DOWN
	for visited in trail:
		cache[visited] = grounded
	return grounded

func settle(seeds: Array) -> int:
	# Build the affected connected component, then transmit support from foundations.
	var component: Dictionary = {}
	var columns := {}
	var open: Array = []
	for cell in seeds:
		if blocks.has(cell) and not component.has(cell):
			component[cell] = true
			open.append(cell)
	var cursor := 0
	while cursor < open.size():
		var cell: Vector3i = open[cursor]
		cursor += 1
		var grounded := _column_grounded(cell, columns)
		for offset in DIRS:
			var other: Vector3i = cell + offset
			if blocks.has(other) and not component.has(other):
				# Independent grounded blocks are separate bearings. A ground floor can cover
				# several chunks without sending every hammer strike through the whole base.
				if grounded and _column_grounded(other, columns):
					continue
				component[other] = true
				open.append(other)
	if component.is_empty():
		return 0
	var failed := _unsupported_members(component, columns)
	if not failed.is_empty():
		show_collapse(failed)
		if is_instance_valid(session.network):
			session.network.mirror_collapse(failed)
		for cell in failed:
			_remove_block(cell, false)
	return failed.size()

func show_collapse(cells: Array) -> void:
	var clusters := {}
	var span := 1 if cells.size() < 25 else clampi(ceili(pow(cells.size() / 16.0, 1.0 / 3.0)), 2, 6)
	for cell: Vector3i in cells:
		if not nodes.has(cell): continue
		var bin := Vector3i((Vector3(cell) / span).floor())
		var tier := int(blocks[cell].tier)
		var piece = preload("res://game/world/falling_structure.gd").release(self, nodes[cell], str(cell), MASS[tier], clusters.get(bin))
		if piece == null: continue
		if not clusters.has(bin):
			session.fx.burst(position_of(cell), Color.html(TONES[tier]), 0.85)
		clusters[bin] = piece
		if session.replica:
			_unmount(cell)
			_unindex(cell)
			blocks.erase(cell)
			session.stream.invalidate_at(cell)
	if not clusters.is_empty() and not session.replica:
		session.audio.play_at("collapse", clusters.values()[0].global_position, 0.91)

func _unsupported_members(component: Dictionary, columns: Dictionary) -> Array[Vector3i]:
	var grounded := {}
	var supported := {}
	var capacity_used := {}
	var frontier: Array[Vector3i] = []
	# A continuous vertical column transfers compression directly to terrain or an intact site floor.
	for cell: Vector3i in component:
		if columns[cell]:
			grounded[cell] = true
			supported[cell] = true
			frontier.append(cell)
	frontier.sort()
	var cursor := 0
	while cursor < frontier.size():
		var bearing := frontier[cursor]
		cursor += 1
		for offset: Vector3i in DIRS:
			var next := bearing + offset
			if not component.has(next) or supported.has(next):
				continue
			if _carry_mass(next, grounded, supported, capacity_used):
				supported[next] = true
				frontier.append(next)
	var failed: Array[Vector3i] = []
	for cell: Vector3i in component:
		if not supported.has(cell): failed.append(cell)
	return failed

func _carry_mass(cell: Vector3i, grounded: Dictionary, supported: Dictionary, used: Dictionary) -> bool:
	# Reserve the new block's complete mass. A bridge may divide it between bearings.
	# Vertical contacts transfer load freely. Every sideways contact charges its supporting block.
	var remaining: float = MASS[int(blocks[cell].tier)]
	var reserved := {}
	while remaining > 0.001:
		var queue: Array[Vector3i] = [cell]
		var toward_load := {cell: cell}
		var cursor := 0
		var bearing := cell
		while cursor < queue.size() and bearing == cell:
			var from := queue[cursor]
			cursor += 1
			for offset: Vector3i in DIRS:
				var base := from + offset
				if not supported.has(base) or toward_load.has(base):
					continue
				if offset.y == 0 and float(used.get(base, 0.0)) + float(reserved.get(base, 0.0)) >= SUPPORT[int(blocks[base].tier)]:
					continue
				toward_load[base] = from
				if grounded.has(base):
					bearing = base
					break
				queue.append(base)
		if bearing == cell:
			return false
		var share := remaining
		var contacts: Array[Vector3i] = []
		while bearing != cell:
			var child: Vector3i = toward_load[bearing]
			if child.y == bearing.y:
				share = minf(share, SUPPORT[int(blocks[bearing].tier)] - float(used.get(bearing, 0.0)) - float(reserved.get(bearing, 0.0)))
				contacts.append(bearing)
			bearing = child
		for contact in contacts:
			reserved[contact] = float(reserved.get(contact, 0.0)) + share
		remaining -= share
	for contact: Vector3i in reserved:
		used[contact] = float(used.get(contact, 0.0)) + float(reserved[contact])
	return true

func toggle_hatch(cell: Vector3i) -> void:
	if not blocks.has(cell) or blocks[cell].shape != 4:
		return
	blocks[cell].open = not blocks[cell].open
	_unmount(cell)
	_mount(cell)
	session.stream.invalidate_at(cell)
	session.audio.play_at("place", position_of(cell), 0.63)

func till(at: Vector3) -> bool:
	var cell := cell_at(at + Vector3.UP * 0.13)
	if crops.has(cell) or blocks.has(cell) or at.y < 0.2:
		return false
	crops[cell] = {"seed": "", "when": 0.0, "soil_depth":_soil_depth(cell)}
	_show_crop(cell)
	session.gain(4, "farm")
	return true

func _soil_depth(cell: Vector3i) -> float:
	return session.stream.excavation_at(Vector2(cell.x+0.5,cell.z+0.5))

func crop_ready(cell: Vector3i) -> bool:
	var row: Dictionary = crops.get(cell, {})
	return not row.is_empty() and row.seed != "" and session.clock.hours >= float(row.when) + 35.0

func remove_plot(cell: Vector3i) -> void:
	if session.replica or not crops.has(cell): return
	var seed_id: String = crops[cell].seed
	var harvest := {}
	var at := position_of(cell)
	at.y=session.stream.ground_at(at)+0.19
	if not seed_id.is_empty():
		harvest[seed_id]=1
		if crop_ready(cell): harvest[session.catalog.items[seed_id].crop]=3
	crops.erase(cell)
	if crop_nodes.has(cell):
		var body: StaticBody3D = crop_nodes[cell]
		body.collision_layer=0
		body.hide()
		body.queue_free()
		crop_nodes.erase(cell)
	if not harvest.is_empty(): session.drop_materials(at,harvest)

func farm(cell: Vector3i, id: String) -> void:
	if not crops.has(cell):
		return
	var row: Dictionary = crops[cell]
	if crop_ready(cell):
		var crop: String = session.catalog.items[row.seed].crop
		session.award({crop: 3 + session.progress.rank("harvest"), row.seed: 1}, position_of(cell))
		row.seed = ""
		session.gain(26, "farm")
	elif row.seed == "" and session.catalog.items.get(id, {}).get("kind") == "seed" and session.bag.spend({id: 1}):
		row.seed = id
		row.when = session.clock.hours
		session.gain(6, "farm")
	else:
		session.notify("选中种子播种" if row.seed == "" else "作物正在生长")
	_show_crop(cell)

func _show_crop(cell: Vector3i) -> void:
	if crop_nodes.has(cell):
		crop_nodes[cell].queue_free()
	var at := position_of(cell)
	at.y = session.stream.ground_at(at)
	var plot := StaticBody3D.new()
	plot.collision_layer = 2
	plot.collision_mask = 0
	plot.position = at
	plot.set_meta("kind", "crop")
	plot.set_meta("block", cell)
	add_child(plot)
	WastelandLook.collider(plot, Vector3(0.88, 0.09, 0.88), Vector3(0, 0.03, 0))
	WastelandLook.box(plot, Vector3(0.92, 0.09, 0.92), Vector3(0, 0.015, 0), Color("#68404a"))
	var row: Dictionary = crops[cell]
	if row.seed != "":
		var mature := crop_ready(cell)
		var high := 0.62 if mature else 0.19
		for index in range(3):
			var stem := Vector3(index * 0.20 - 0.18, high * 0.5, (index % 2) * 0.19 - 0.08)
			WastelandLook.box(plot, Vector3(0.065, high, 0.069), stem, Color("#8e9959"))
			var leaf := WastelandLook.box(plot, Vector3(0.19, 0.075, 0.12), stem + Vector3(0.07, high * 0.22, 0), Color("#a7a565"))
			leaf.rotation.z = 0.42
			if mature and row.seed == "seed_corn":
				WastelandLook.box(plot, Vector3(0.09, 0.19, 0.103), stem + Vector3(0, high * 0.55, 0.044), Color("#dfaf62"))
	plot.set_meta("mature", crop_ready(cell))
	crop_nodes[cell] = plot

func connect_device(cell: Vector3i) -> void:
	var id := str(station_index.get(cell, ""))
	var definition: Dictionary = session.catalog.items.get(id, {})
	if not (definition.has("capacity") or definition.has("produce") or definition.has("draw")):
		session.notify("此设备没有电力接点")
		return
	if selected_wire == null:
		selected_wire = cell
		session.notify("已选定起点，瞄准另一设备连接")
		return
	var source: Vector3i = selected_wire
	selected_wire = null
	if source == cell:
		session.notify("已取消接线")
		return
	if not blocks.has(source) or Vector3(source - cell).length() > 20.0:
		session.notify("电缆最长 20 米")
		return
	for index in wires.size():
		var edge: Array = wires[index]
		if (edge[0] == source and edge[1] == cell) or (edge[0] == cell and edge[1] == source):
			wires.remove_at(index)
			_rebuild_wires()
			session.drop_materials(position_of(cell),{"wire":1})
			session.notify("已拆除电缆")
			return
	if not session.bag.spend({"wire": 1}):
		session.notify("接线需要铜线 ×1")
		return
	wires.append([source, cell])
	_rebuild_wires()
	session.notify("电缆已接通")

func _rebuild_wires() -> void:
	for line in wire_nodes:
		line.queue_free()
	wire_nodes.clear()
	for edge in wires:
		if not nodes.has(edge[0]) or not nodes.has(edge[1]):
			continue
		var a := position_of(edge[0]) + Vector3.UP * 0.42
		var b := position_of(edge[1]) + Vector3.UP * 0.42
		var d := a.distance_to(b)
		var line := WastelandLook.box(self, Vector3(0.047, 0.047, d), (a + b) * 0.5, Color("#9a7b64"))
		if d > 0.02:
			line.look_at(b)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wire_nodes.append(line)

func _power_grid(dt: float) -> void:
	powered.clear()
	var adjacency: Dictionary = {}
	for edge in wires:
		if not blocks.has(edge[0]) or not blocks.has(edge[1]):
			continue
		if not adjacency.has(edge[0]): adjacency[edge[0]] = []
		if not adjacency.has(edge[1]): adjacency[edge[1]] = []
		adjacency[edge[0]].append(edge[1])
		adjacency[edge[1]].append(edge[0])
	var visited: Dictionary = {}
	for root in adjacency:
		if visited.has(root):
			continue
		var component: Array = [root]
		var sources: Array = []
		var batteries: Array = []
		var consumers: Array = []
		visited[root] = true
		var step := 0
		var supply := 0.0
		while step < component.size():
			var cell: Vector3i = component[step]
			step += 1
			for next in adjacency[cell]:
				if not visited.has(next):
					visited[next] = true
					component.append(next)
			var record: Dictionary = blocks[cell]
			if not record.enabled:
				continue
			var item: Dictionary = session.catalog.items.get(record.device, {})
			if item.has("draw"):
				consumers.append([cell, float(item.draw)])
			if item.has("capacity"):
				batteries.append([cell, float(item.capacity)])
			if item.has("produce"):
				var energy := float(item.produce)
				if record.device == "solar":
					supply += energy * session.atmosphere.sun_strength
				elif float(record.fuel) > 0.0:
					supply += energy
					sources.append(cell)
		var from_battery := 0.0
		for battery in batteries:
			from_battery += minf(80.0, float(blocks[battery[0]].charge) / dt)
		consumers.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and str(a[0]) < str(b[0])))
		var consumed := 0.0
		for device in consumers:
			if supply + from_battery - consumed >= device[1]:
				powered[device[0]] = true
				consumed += device[1]
		var balance := (supply - consumed) * dt
		var shifted := 0.0
		for battery in batteries:
			var record: Dictionary = blocks[battery[0]]
			var next_charge := clampf(float(record.charge) + clampf(balance, -80.0 * dt, 80.0 * dt), 0.0, battery[1])
			var shift := next_charge - float(record.charge)
			balance -= shift
			shifted += shift
			record.charge = next_charge
		if consumed > 0.0 or shifted > 0.0:
			for cell in sources:
				blocks[cell].fuel = maxf(0.0, float(blocks[cell].fuel) - dt)
				powered[cell] = true

func simulate(dt: float) -> void:
	device_elapsed+=dt
	next_sim -= dt
	if next_sim > 0.0:
		return
	var tick := device_elapsed
	device_elapsed=0.0
	next_sim = 0.24
	_power_grid(tick)
	for cell in station_index.keys():
		if not blocks.has(cell): continue
		var info: Dictionary = blocks[cell]
		while not Fire.thermal(info) and not info.queue.is_empty() and float(info.queue[0].done) <= session.clock.elapsed:
			var job: Dictionary = info.queue.pop_front()
			var id := str(job.id)
			info.out[id] = int(info.out.get(id, 0)) + int(job.amount)
		var loaded := nodes.has(cell)
		match info.device:
			"campfire","forge":
				var burned:=Fire.tick(info,tick,session.clock.elapsed)
				if loaded:
					var fire: OmniLight3D = nodes[cell].get_node_or_null("Lamp")
					if fire!=null: fire.visible=Fire.lit(info)
				if burned>0: session.hordes.add_heat(position_of(cell),burned*(0.90 if info.device=="forge" else 0.38))
			"generator":
				if powered.has(cell) and loaded and session.clock.elapsed >= float(fired.get(cell, 0.0)):
					fired[cell] = session.clock.elapsed + 1.3
					session.audio.play_at("generator", position_of(cell), 0.68, false)
					session.hordes.add_heat(position_of(cell), 1.2)
			"floodlight":
				if loaded:
					var lamp: OmniLight3D = nodes[cell].get_node_or_null("Lamp")
					if lamp != null: lamp.visible = powered.has(cell)
			"turret", "blade", "fence", "spikes", "barbed", "mine":
				if loaded and info.enabled:
					_trap(cell, info)
		if loaded and nodes.has(cell):
			_refresh_device(cell, info)
	for cell in crop_nodes.keys():
		if not bool(crop_nodes[cell].get_meta("mature")) and crop_ready(cell):
			_show_crop(cell)

func _trap(cell: Vector3i, info: Dictionary) -> void:
	var id := str(info.device)
	if id in ["blade", "fence", "turret"] and not powered.has(cell):
		return
	if id == "turret" and int(info.ammo) <= 0:
		return
	if session.clock.elapsed < float(fired.get(cell, 0.0)):
		return
	var at := position_of(cell)
	if id in ["spikes", "barbed"]:
		trap_probe.transform.origin = at - Vector3.UP * 0.05
		var wear := 0.0
		for hit in get_world_3d().direct_space_state.intersect_shape(trap_probe, 32):
			var body: Object = hit.collider
			if body is WastelandCreature and body.active and body.hp > 0.0 and body.type not in WastelandHordes.WILDLIFE:
				body.apply_trap_slow(1.35, 0.60 if id == "spikes" else 0.40)
				body.take_hit(19.0 if id == "spikes" else 11.0, at)
			elif id == "spikes" and body is WastelandSurvivor and body.health > 0.0:
				body.damage(4.0, "spikes", at)
			else:
				continue
			wear += 6.0 if id == "spikes" else 4.0
			if wear >= float(info.hp): break
		if wear > 0.0:
			fired[cell] = session.clock.elapsed + 0.92
			damage(cell, wear)
		return
	var radius := 15.0 if id == "turret" else 1.23
	var enemy = session.hordes.nearest_enemy(at, radius)
	if not is_instance_valid(enemy):
		return
	var gap: Vector3 = enemy.global_position + Vector3.UP * 0.6
	if id == "turret":
		var obstruction := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.64, gap, 3, [nodes[cell].get_rid()]))
		if not obstruction.is_empty():
			return
	fired[cell] = session.clock.elapsed + (0.56 if id == "turret" else 0.92)
	match id:
		"mine":
			session.fx.burst(at, Color("#e79e63"), 2.2)
			session.audio.play_at("boom", at)
			session.hordes.add_noise(at, 50.0)
			session.hordes.add_heat(at, 22.0)
			for actor: WastelandCreature in session.hordes.alive.duplicate():
				if actor.physical_position().distance_to(at) < 4.6:
					actor.take_hit(95.0, at, true)
			destroy(cell)
		"turret":
			info.ammo = int(info.ammo) - 1
			session.fx.burst(at + Vector3.UP * 0.68, Color("#ffce78"), 0.6)
			session.audio.play_at("shot", at)
			session.hordes.add_heat(at, 3.0)
			enemy.take_hit(33.0, at)
		"blade", "fence":
			enemy.stagger = maxf(enemy.stagger, 0.32)
			enemy.take_hit(42.0 if id == "blade" else 24.0, at)
			session.fx.burst(gap, Color("#ad92ed"), 0.57)

func _mount(cell: Vector3i) -> void:
	if nodes.has(cell):
		return
	var record: Dictionary = blocks[cell]
	var body := StaticBody3D.new()
	body.name = "Block"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = position_of(cell)
	body.rotation.y = int(record.turn) * PI / 2.0
	body.set_meta("kind", "block")
	body.set_meta("block", cell)
	add_child(body)
	var visual := MeshInstance3D.new()
	var active := _device_active(cell, record)
	visual.mesh = _mesh(int(record.tier), int(record.shape), record.device, bool(record.open), active)
	if record.device != "":
		visual.set_meta("active", active)
	if record.device == "":
		visual.material_override = _material(int(record.tier), crack_stage(record), hash(cell) & 7)
	else:
		visual.material_override = _device_material(crack_stage(record))
	body.add_child(visual)
	if record.device in ["spikes", "barbed", "mine", "fence"]:
		var height := 0.23 if record.device == "mine" else 0.48
		WastelandLook.collider(body, Vector3(0.83, height, 0.83), Vector3(0, -0.49 + height * 0.5, 0))
	elif record.device != "":
		WastelandLook.collider(body, Vector3(0.9, 0.67, 0.9), Vector3(0, -0.125, 0))
	elif int(record.shape) == 1:
		var slope := ConvexPolygonShape3D.new()
		slope.points = PackedVector3Array([Vector3(-0.5,-0.5,-0.5),Vector3(0.5,-0.5,-0.5),Vector3(0.5,-0.5,0.5),Vector3(-0.5,-0.5,0.5),Vector3(-0.5,0.5,-0.5),Vector3(0.5,0.5,-0.5)])
		var hit := CollisionShape3D.new()
		hit.shape = slope
		body.add_child(hit)
	elif int(record.shape) == 2:
		WastelandLook.collider(body, Vector3(1, 0.5, 1), Vector3(0, -0.25, 0))
	elif int(record.shape) == 3:
		WastelandLook.collider(body, Vector3(1.0, 0.96, 0.26), Vector3.ZERO)
	elif int(record.shape) == 4:
		var opened := bool(record.open)
		WastelandLook.collider(body, Vector3(1.0,0.88,0.14) if opened else Vector3(1.0,0.14,1.0), Vector3(0,-0.06,-0.44) if opened else Vector3(0,-0.43,0))
	else:
		WastelandLook.collider(body, Vector3.ONE, Vector3.ZERO)
	if Fire.thermal(record) or record.device == "floodlight":
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp"
		lamp.light_color = Color("#ffc176") if Fire.thermal(record) else Color("#fbe9c0")
		lamp.omni_range = 7.0 if Fire.thermal(record) else 18.0
		lamp.light_energy = 1.06
		lamp.position.y = 0.45
		lamp.visible = active
		body.add_child(lamp)
	nodes[cell] = body

func _unmount(cell: Vector3i) -> void:
	if nodes.has(cell):
		var node: StaticBody3D = nodes[cell]
		node.collision_layer = 0
		node.queue_free()
		nodes.erase(cell)

func mirror_layout(next_blocks: Dictionary,next_crops: Dictionary,next_wires: Array,next_powered: Dictionary) -> void:
	for cell in blocks.keys():
		if not next_blocks.has(cell):
			_unmount(cell)
			_unindex(cell)
			blocks.erase(cell)
			session.stream.invalidate_at(cell)
	for cell in next_blocks:
		var previous: Dictionary = blocks.get(cell,{})
		var data: Dictionary = next_blocks[cell]
		blocks[cell]=data
		if previous.is_empty():
			_index(cell,data)
			if session.stream.at_surface(position_of(cell)):
				_mount(cell)
				session.stream.invalidate_at(cell)
		elif [previous.tier,previous.shape,previous.turn,previous.open,previous.device] != [data.tier,data.shape,data.turn,data.open,data.device]:
			var loaded:=nodes.has(cell)
			_unmount(cell)
			_unindex(cell)
			_index(cell,data)
			if loaded:
				_mount(cell)
				session.stream.invalidate_at(cell)
		elif nodes.has(cell) and previous.hp!=data.hp:
			_refresh_surface(cell)
	powered=next_powered
	for cell in nodes:
		if station_index.has(cell):
			_refresh_device(cell, blocks[cell])
		if Fire.thermal(blocks[cell]):
			nodes[cell].get_node("Lamp").visible=Fire.lit(blocks[cell])
		if station_index.get(cell)=="floodlight":
			var lamp:OmniLight3D=nodes[cell].get_node_or_null("Lamp")
			if lamp!=null: lamp.visible=powered.has(cell)
	var old_crops:=crops
	crops=next_crops
	for cell in crop_nodes.keys():
		if not crops.has(cell):
			crop_nodes[cell].queue_free()
			crop_nodes.erase(cell)
	for cell in crops:
		if session.stream.at_surface(position_of(cell)) and (not crop_nodes.has(cell) or old_crops.get(cell)!=crops[cell] or (crop_ready(cell) and not crop_nodes[cell].get_meta("mature"))):
			_show_crop(cell)
	if next_wires!=wires:
		wires=next_wires
		_rebuild_wires()

func crack_stage(info: Dictionary) -> int:
	var ratio := float(info.hp) / _max_hp(info)
	return 2 if ratio < 0.35 else (1 if ratio < 0.70 else 0)

func _refresh_surface(cell: Vector3i) -> void:
	var info: Dictionary = blocks[cell]
	if nodes.has(cell):
		var visual: MeshInstance3D = nodes[cell].get_child(0)
		var stage := crack_stage(info)
		visual.material_override = _material(int(info.tier), stage, hash(cell) & 7) if info.device == "" else _device_material(stage)

func _device_material(stage: int) -> Material:
	return WastelandLook.colored_material() if stage == 0 else _material(TONES.size(), stage)

func _material(tier: int, cracks: int = 0, wear: int = 0) -> ShaderMaterial:
	var key := (tier * 3 + cracks) * 8 + wear
	if not materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/construction_finish.gdshader")
		if tier < TONES.size():
			mat.set_shader_parameter("tint", Color.html(TONES[tier]))
		mat.set_shader_parameter("tier", tier)
		mat.set_shader_parameter("cracks", cracks)
		mat.set_shader_parameter("patina", preload("res://game/art/weather_noise.tres"))
		mat.set_shader_parameter("wear_offset", Vector2(wear * 0.375, wear * 0.625))
		materials[key] = mat
	return materials[key]

func _device_active(cell: Vector3i, record: Dictionary) -> bool:
	match record.device:
		"forge", "campfire":
			return Fire.lit(record)
		"battery":
			return record.enabled and float(record.charge) > 0.0
		"generator", "blade", "turret", "fence", "floodlight":
			return powered.has(cell)
	return false

func _refresh_device(cell: Vector3i, record: Dictionary) -> void:
	var visual: MeshInstance3D = nodes[cell].get_child(0)
	var active := _device_active(cell, record)
	if active != bool(visual.get_meta("active", false)):
		visual.set_meta("active", active)
		visual.mesh = _mesh(int(record.tier), int(record.shape), record.device, bool(record.open), active)

func _mesh(tier: int, shape: int, device: String, opened: bool, active := false) -> Mesh:
	var key := "%s/%s" % [device, active] if device != "" else "%d/%d/%s" % [tier, shape, opened]
	if not shape_meshes.has(key):
		if device != "":
			shape_meshes[key] = BuildDevices.mesh(device, Color.html(DEVICE_COLOR[device]), active)
		else:
			shape_meshes[key] = BuildShapes.mesh(tier, shape, opened)
	return shape_meshes[key]
