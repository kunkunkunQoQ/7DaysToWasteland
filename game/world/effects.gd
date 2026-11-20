class_name WastelandEffects
extends Node3D

const PARTICLES := 16
const DEBRIS := 18
const PROJECTILES := 48
const DROPS := 56
const PICKUP_LAYER := 1 << 4
const PICKUP_RADIUS := 1.65
const ACID_GRAVITY := 5.2
const ACID_RADIUS := 1.36
const ACID_POOLS := 12
const ACID_LIFE := 3.0
const FLOATING_ITEMS := ["wood","stick","tree_leaf","fiber","reed_stem","medicinal_herb","frame","spikes","club","bow","reed_spear","meme_duck"]
const DROP_GRAVITY := 18.0

var session: Node3D
var particles: Array[GPUParticles3D] = []
var particle_time := PackedFloat32Array()
var debris: Array[RigidBody3D] = []
var shots: Array[Dictionary] = []
var pools: Array[Dictionary] = []
var acid_glob := SphereMesh.new()
var drops: Array[StaticBody3D] = []
var drop_records: Dictionary = {}
var drop_chunks: Dictionary = {}
var drop_live: Dictionary = {}
var serial := 0
var acid_serial := 0
var particle_cursor := 0
var debris_cursor := 0
var shot_cursor := 0
var drop_ticker := 0.0
var drop_motion := PhysicsTestMotionParameters3D.new()
var drop_contact := PhysicsTestMotionResult3D.new()
var replica_motion := {}
var needle_bundle: ArrayMesh
var needle_tint: StandardMaterial3D

func configure(owner_session: Node3D, snapshot: Dictionary) -> void:
	session = owner_session
	acid_glob.radial_segments = 10
	acid_glob.rings = 5
	drop_records = snapshot.get("drops", {}).duplicate(true)
	serial = int(snapshot.get("drop_serial", 0))
	for key in drop_records:
		if str(key).is_valid_int(): serial=maxi(serial,int(key))
		_index_drop(key,_drop_cell(drop_records[key].point))
	for index in PARTICLES:
		var fx := GPUParticles3D.new()
		fx.amount = 15
		fx.one_shot = true
		fx.lifetime = 0.54
		fx.explosiveness = 0.98
		fx.emitting = false
		fx.hide()
		fx.visibility_aabb = AABB(Vector3(-5,-4,-5), Vector3(10,9,10))
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3.UP
		mat.spread = 79.0
		mat.initial_velocity_min = 2.0
		mat.initial_velocity_max = 4.8
		mat.gravity = Vector3(0,-15,0)
		mat.scale_min = 0.54
		mat.scale_max = 1.3
		fx.process_material = mat
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.079
		var paint := StandardMaterial3D.new()
		paint.vertex_color_use_as_albedo = true
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material = paint
		fx.draw_pass_1 = box
		add_child(fx)
		particles.append(fx)
		particle_time.append(0.0)
	for index in DEBRIS:
		var falling := RigidBody3D.new()
		falling.collision_layer = 0
		falling.collision_mask = 3
		falling.freeze = true
		falling.visible = false
		WastelandLook.box(falling, Vector3.ONE * 0.64, Vector3.ZERO, Color("#927484"))
		WastelandLook.collider(falling, Vector3.ONE * 0.62, Vector3.ZERO)
		add_child(falling)
		debris.append(falling)
	for index in PROJECTILES:
		var effect := WastelandLook.box(self, Vector3(0.042, 0.042, 0.29), Vector3.ZERO, Color("#ffcc7b"), 0.5)
		effect.hide()
		shots.append({"node": effect, "life": 0.0, "vel": Vector3.ZERO, "origin": Vector3.ZERO, "owner": null, "kind": "", "hit": 0.0, "id":0, "shooter":0})
	for index in DROPS:
		var body := StaticBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		body.hide()
		body.set_meta("kind", "drop")
		WastelandLook.form(body, Vector3(0.39, 0.24, 0.35), Vector3.ZERO, Color("#c79b67"),0.24)
		WastelandLook.form(body, Vector3(0.43, 0.05, 0.06), Vector3(0, 0.12, 0), Color("#f9d590"),0.14)
		WastelandLook.form(body, Vector3(0.13,0.075,0.065),Vector3(0,0.082,0.18),Color("#d5b07e"),0.11)
		var item:=MeshInstance3D.new()
		item.name="Item"
		item.rotation=Vector3(0.42,0.37,-0.57)
		item.scale=Vector3.ONE*0.70
		item.material_override=WastelandLook.colored_material()
		body.add_child(item)
		var pickup_shape := WastelandLook.collider(body, Vector3(0.58, 0.34, 0.51), Vector3.ZERO)
		pickup_shape.name = "PickupShape"
		add_child(body)
		drops.append(body)
	drop_motion.margin=0.002
	for row: Dictionary in snapshot.get("acid_pools",[]):
		_place_acid(row.at,row.normal,float(row.life),float(row.next))
	for row: Dictionary in snapshot.get("acid_shots",[]):
		_restore_acid(row)
	acid_serial = maxi(acid_serial,int(snapshot.get("acid_serial",0)))

func acid_flights(near := Vector3.INF) -> Array:
	var rows := []
	for shot in shots:
		if shot.life > 0.0 and shot.kind == "acid" and (not near.is_finite() or near.distance_squared_to(shot.node.global_position) < 70.0*70.0):
			rows.append(_acid_row(shot))
	return rows

func _acid_row(shot: Dictionary) -> Dictionary:
	return {"id":shot.id,"at":shot.node.global_position,"vel":shot.vel,"life":shot.life,"origin":shot.origin,"hit":shot.hit,"shooter":shot.shooter}

func receive_acid(row: Dictionary) -> void:
	if int(row.id) > acid_serial:
		_restore_acid(row)

func _restore_acid(row: Dictionary) -> void:
	var shot := _show_projectile(row.at,row.vel,null,"acid",row.hit)
	shot.id = int(row.id)
	shot.shooter = int(row.shooter)
	shot.origin = row.origin
	shot.life = float(row.life)
	acid_serial = maxi(acid_serial,int(row.id))

func acid_snapshot() -> Array:
	var rows := []
	for pool in pools:
		if pool.life > 0.0:
			rows.append({"at":pool.at,"normal":pool.normal,"life":pool.life,"next":pool.next})
	return rows

func infected_effect(kind: String, point: Vector3, normal := Vector3.UP) -> void:
	match kind:
		"residue": _place_acid(point,normal,ACID_LIFE,0.72)
		"mend": burst(point,Color("#94e0e4"),0.90)
		"rupture":
			burst(point,Color("#f7a65a"),2.5)
			burst(point + Vector3.UP * 0.26,Color("#a55941"),1.60)

func _place_acid(point: Vector3, normal: Vector3, life: float, next: float) -> void:
	var slot := -1
	for i in pools.size():
		if slot < 0 or pools[i].life < pools[slot].life: slot = i
	if slot < 0 or (pools[slot].life > 0.0 and pools.size() < ACID_POOLS):
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 16
		mesh.rings = 1
		mesh.top_radius = ACID_RADIUS
		mesh.bottom_radius = ACID_RADIUS * 0.96
		mesh.height = 0.022
		var film := MeshInstance3D.new()
		film.mesh = mesh
		film.material_override = WastelandLook.matte(Color("#93bd49"),0.36)
		film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(film)
		slot = pools.size()
		pools.append({"node":film,"life":0.0})
	var pool := pools[slot]
	pool.at = point
	pool.normal = normal
	pool.life = life
	pool.next = next
	var node: MeshInstance3D = pool.node
	node.global_position = point
	node.quaternion = Quaternion(Vector3.UP,normal)
	node.show()

func burst(at: Vector3, color: Color, strength: float = 1.0) -> void:
	particle_cursor = (particle_cursor + 1) % PARTICLES
	var fx := particles[particle_cursor]
	fx.global_position = at
	var mat: ParticleProcessMaterial = fx.process_material
	mat.color = color
	mat.initial_velocity_min = 1.3 * strength
	mat.initial_velocity_max = 4.6 * strength
	particle_time[particle_cursor] = fx.lifetime * (2.0 - fx.explosiveness)
	fx.show()
	fx.restart()
	fx.emitting = true

func collapse(at: Vector3, color: Color) -> void:
	debris_cursor = (debris_cursor + 1) % DEBRIS
	var falling := debris[debris_cursor]
	falling.freeze = true
	falling.global_transform = Transform3D(Basis.IDENTITY, at)
	falling.get_child(0).material_override = WastelandLook.matte(color)
	falling.visible = true
	falling.set_meta("end", session.clock.elapsed + 4.5)
	falling.freeze = false
	falling.linear_velocity = Vector3(randf_range(-0.9,0.9),randf_range(0.0,1.3),randf_range(-0.9,0.9))
	falling.angular_velocity = Vector3(randf_range(-3.0,3.0), 1.2, randf_range(-3.0,3.0))
	burst(at, color, 0.72)
	session.audio.play_at("collapse", at, 0.77)

func projectile(at: Vector3, vel: Vector3, owner: Node3D, kind: String, damage: float) -> void:
	var shot := _show_projectile(at,vel,owner,kind,damage)
	if kind == "acid":
		acid_serial += 1
		shot.id = acid_serial
		if not session.replica and is_instance_valid(session.network):
			session.network.mirror_acid(_acid_row(shot))

func _show_projectile(at: Vector3, vel: Vector3, owner: Node3D, kind: String, damage: float) -> Dictionary:
	shot_cursor = (shot_cursor + 1) % PROJECTILES
	var slot := shot_cursor
	for offset in PROJECTILES:
		var candidate := (shot_cursor + offset) % PROJECTILES
		if shots[candidate].life <= 0.0:
			slot = candidate
			break
	var shot: Dictionary = shots[slot]
	shot.life = 3.5
	shot.vel = vel
	shot.origin = at
	shot.owner = owner
	shot.id = 0
	shot.shooter = owner.spawn_serial if owner is WastelandCreature else 0
	shot.kind = kind
	shot.hit = damage
	var node: MeshInstance3D = shot.node
	node.mesh = acid_glob if kind == "acid" else WastelandLook.unit_box
	node.material_override = WastelandLook.matte(Color("#accd76") if kind == "acid" else Color("#e7ba71"), 0.34)
	node.scale = Vector3(0.21,0.18,0.40) if kind == "acid" else Vector3(0.042,0.042,0.29)
	node.global_position = at
	node.show()
	_aim_shot(node,vel)
	return shot

func _aim_shot(node: MeshInstance3D, velocity: Vector3) -> void:
	if velocity.length_squared() < 0.0001: return
	var direction := velocity.normalized()
	node.look_at(node.global_position + direction,Vector3.RIGHT if absf(direction.y) > 0.995 else Vector3.UP)

func add_items(at: Vector3, items: Dictionary, impulse:=Vector3.INF, discarded:=false, log_section: Dictionary = {}, leaf_model := "", loose_material := false) -> void:
	if items.is_empty() or session.replica:
		return
	serial += 1
	var id := str(serial)
	if not impulse.is_finite():
		var turn:=Vector2.from_angle(serial*2.39996)
		impulse=Vector3(turn.x*0.62,0.72,turn.y*0.62)
	store_drop(id,{"items":items.duplicate(),"point":at,"velocity":impulse})
	if loose_material: drop_records[id].loose_material=true
	if not log_section.is_empty(): drop_records[id].log_section = log_section
	if items.size()==1 and items.has("tree_leaf"):
		drop_records[id].leaf_phase = fposmod(serial*1.79,TAU)
		if not leaf_model.is_empty(): drop_records[id].leaf_model = leaf_model
	if discarded:
		drop_records[id].discarded_by=session._courier_id()
		drop_records[id].discard_origin=session.player.global_position
		drop_records[id].pickup_after=session.clock.elapsed+1.0
	if is_instance_valid(session.player) and drop_live.size()<DROPS and _observer_distance_squared(at)<=65.0*65.0:
		_show_drop(id)
	if is_instance_valid(session.network) and session.network.server(): session.network.invalidate_world()

func _item_summary(items: Dictionary, limit: int) -> String:
	if items.size() <= limit: return session.catalog.requirements(items)
	var first := {}
	for item: String in items:
		first[item] = items[item]
		if first.size() == limit: break
	return "%s 等 %d 种" % [session.catalog.requirements(first), items.size()]

func pickup_hint(id: String, use: String) -> String:
	var row: Dictionary = drop_records.get(id, {})
	if row.is_empty(): return ""
	var items: Dictionary = row.items
	var action := "[%s] 打捞浮标" % use if row.get("buoy", false) else "靠近拾取"
	if not items.keys().any(func(item): return session.bag.room_for(item) > 0):
		action = "背包已满"
	return _item_summary(items, 2) + " · " + action

func _notify_pickup(received: Dictionary, remaining: Dictionary, buoy: bool) -> void:
	var words := "背包已满"
	if not received.is_empty():
		words = ("已打捞 " if buoy else "已拾取 ") + _item_summary(received, 4 if remaining.is_empty() else 2)
	if not remaining.is_empty():
		words += ("，浮标内剩余 " if buoy else "，地上剩余 ") + _item_summary(remaining, 2)
	session.notify(words)

func collect_nearby() -> void:
	if session.replica or drop_live.is_empty(): return
	var survivor:WastelandSurvivor=session.player
	var reach:=survivor.global_position+Vector3.UP*survivor.eyes.position.y*0.45
	var received := {}
	var remainders: Array[Dictionary] = []
	for id:String in drop_live.keys():
		var row:Dictionary=drop_records[id]
		if row.get("buoy",false) or session.clock.elapsed<float(row.get("pickup_after",0.0)): continue
		if row.has("discarded_by") and row.discarded_by==session._courier_id():
			if survivor.global_position.distance_squared_to(row.discard_origin)<0.75*0.75: continue
			row.erase("discarded_by")
			row.erase("discard_origin")
			row.erase("pickup_after")
		var point:Vector3=row.point
		if row.has("log_section"):
			var half_axis: Vector3 = row.log_section.axis * float(row.log_section.length) * 0.5
			point = Geometry3D.get_closest_point_to_segment(reach,point-half_axis,point+half_axis)
		if reach.distance_squared_to(point)>PICKUP_RADIUS*PICKUP_RADIUS: continue
		var ray:=PhysicsRayQueryParameters3D.create(reach,point,1|2)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		_transfer_drop(id, row, received)
		if not row.items.is_empty(): remainders.append(row.items)
	if received.is_empty(): return
	var remaining := {}
	for pile: Dictionary in remainders:
		for item: String in pile:
			remaining[item] = int(remaining.get(item, 0)) + int(pile[item])
	_notify_pickup(received, remaining, false)

func take_drop(id: String, automatic:=false) -> int:
	if session.replica or not drop_records.has(id):
		return 0
	var row: Dictionary = drop_records[id]
	var received := {}
	var moved := _transfer_drop(id, row, received)
	if not automatic: _notify_pickup(received, row.items, row.get("buoy", false))
	return moved

func _transfer_drop(id: String, row: Dictionary, received: Dictionary) -> int:
	var wood_before := int(row.items.get("wood",0))
	var moved: int = session.bag.transfer(row.items, received)
	if moved == 0: return 0
	if wood_before>0 and (row.has("log_section") or row.get("loose_material",false)):
		session.achievements.add("collected_wood",wood_before-int(row.items.get("wood",0)))
	if row.items.is_empty():
		if row.get("buoy", false):
			session.gain(36, "salvage_buoy")
		erase_drop(id)
	else:
		if drop_live.has(id): _dress_drop(drop_live[id], row)
		if not row.get("buoy", false): row.erase("resting")
	if is_instance_valid(session.network) and session.network.server(): session.network.invalidate_world()
	return moved

func _drop_cell(point: Vector3) -> Vector2i:
	return WastelandTerrainGen.chunk_at(Vector2(point.x,point.z))

func _index_drop(id: String, cell: Vector2i) -> void:
	var bucket: Dictionary=drop_chunks.get_or_add(cell,{})
	bucket[id]=true

func _unindex_drop(id: String, cell: Vector2i) -> void:
	var bucket: Dictionary=drop_chunks[cell]
	bucket.erase(id)
	if bucket.is_empty(): drop_chunks.erase(cell)

func store_drop(id: String, row: Dictionary) -> void:
	if drop_records.has(id): erase_drop(id)
	drop_records[id]=row
	_index_drop(id,_drop_cell(row.point))

func erase_drop(id: String) -> void:
	if not drop_records.has(id): return
	_unindex_drop(id,_drop_cell(drop_records[id].point))
	drop_records.erase(id)
	if drop_live.has(id): _release_drop(id)

func _release_drop(id: String) -> void:
	var body: StaticBody3D = drop_live[id]
	body.hide()
	body.collision_layer = 0
	body.collision_mask = 0
	body.remove_meta("drop_id")
	body.remove_meta("floats")
	body.remove_meta("item_types")
	body.set_meta("kind","drop")
	body.get_node("Item").mesh = null
	drop_live.erase(id)
	replica_motion.erase(id)

func _dress_drop(body: StaticBody3D, row: Dictionary) -> void:
	var items: Dictionary = row.items
	var buoy: bool = row.get("buoy",false)
	var log_section: Dictionary = row.get("log_section",{})
	body.set_meta("item_types",hash(items.keys()))
	body.set_meta("floats",items.keys().all(func(id): return id in FLOATING_ITEMS))
	var display: MeshInstance3D=body.get_node("Item")
	display.material_override = WastelandLook.colored_material()
	display.rotation = Vector3(0.42,0.37,-0.57)
	display.scale = Vector3.ONE * 0.70
	var single:=items.size()==1
	for part in body.get_children():
		if part is MeshInstance3D:
			part.visible=not single and not buoy
	display.visible=single and not buoy
	if display.visible:
		var id:String=items.keys().front()
		if log_section.is_empty():
			display.mesh=WastelandItemArt.mesh(id,session.catalog.items.get(id,{}))
		else:
			display.mesh=preload("res://game/art/timber_art.gd").log_mesh(log_section.model,log_section.variant)
	var marker := body.get_node_or_null("Buoy") as Node3D
	if buoy and not marker:
		marker = Node3D.new()
		marker.name = "Buoy"
		body.add_child(marker)
		WastelandLook.form(marker, Vector3(1.35, 0.42, 0.98), Vector3.ZERO, Color("#ed7537"), 0.14)
		WastelandLook.box(marker, Vector3(1.31, 0.08, 1.00), Vector3.UP * 0.06, Color("#fff2c4"))
		WastelandLook.form(marker, Vector3(0.74, 0.40, 0.63), Vector3.UP * 0.36, Color("#4e7276"), 0.09)
		WastelandLook.box(marker, Vector3(0.07, 1.73, 0.07), Vector3(-0.46, 0.94, 0), Color("#50535a"))
		WastelandLook.box(marker, Vector3(0.61, 0.31, 0.04), Vector3(-0.18, 1.60, 0), Color("#ff923c"), 0.22)
		WastelandLook.box(marker, Vector3(0.17, 0.18, 0.17), Vector3(-0.46, 1.86, 0), Color("#ffe09b"), 1.10)
	if marker:
		marker.visible = buoy
	var pickup_shape := body.get_node("PickupShape") as CollisionShape3D
	pickup_shape.basis = Basis.IDENTITY
	(pickup_shape.shape as BoxShape3D).size = Vector3(1.38, 1.67, 1.0) if buoy else Vector3(0.58, 0.34, 0.51)
	pickup_shape.position.y = 0.57 if buoy else 0.0
	if not log_section.is_empty():
		var diameter := float(log_section.radius)*2.0
		(pickup_shape.shape as BoxShape3D).size = Vector3(diameter,diameter,log_section.length)
		_pose_log(body,log_section)
	elif not buoy and single and items.has("tree_leaf"):
		(pickup_shape.shape as BoxShape3D).size = Vector3(0.22,0.05,0.28)
		if _is_needle_drop(row):
			if needle_bundle == null:
				var sprig := preload("res://game/art/leaf_shapes.gd").build("needles")
				var mesh_builder := SurfaceTool.new()
				mesh_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				for i in 3:
					var rotation_y := (i-1)*0.72
					mesh_builder.append_from(sprig,0,Transform3D(Basis(Vector3.UP,rotation_y),Vector3(0.026*(i-1),i*0.005,0)))
				needle_bundle = mesh_builder.commit()
				needle_tint = WastelandLook.colored_material().duplicate()
				needle_tint.albedo_color = Color("#749250")
				needle_tint.cull_mode = BaseMaterial3D.CULL_DISABLED
			display.mesh = needle_bundle
			display.material_override = needle_tint
		_pose_leaf(body,row)
	elif not buoy and single and items.has("stick"):
		_pose_stick(body,row)
	body.set_meta("kind", "buoy" if buoy else "drop")

func _is_needle_drop(row: Dictionary) -> bool:
	return row.get("leaf_model","") in ["pine","snow_fir","frost_fir"]

func _pose_leaf(body: StaticBody3D, row: Dictionary) -> void:
	var phase := float(row.get("leaf_phase",0.0))
	var heading := fposmod(float(body.get_meta("drop_id"))*2.39996,TAU)
	var normal: Vector3 = row.get("leaf_normal",Vector3.UP)
	var plane := Basis(Quaternion(Vector3.UP,normal)) * Basis(Vector3.UP,heading)
	if not row.has("leaf_normal"):
		plane *= Basis(Vector3.UP,phase*0.63) * Basis(Vector3.BACK,sin(phase)*0.86) * Basis(Vector3.RIGHT,cos(phase*0.77)*0.48)
	if not _is_needle_drop(row): plane *= Basis(Vector3.RIGHT,-PI*0.5)
	body.get_node("Item").basis = plane.scaled(Vector3.ONE * (1.25 if _is_needle_drop(row) else 0.94))
	body.get_node("PickupShape").basis = Basis(Quaternion(Vector3.UP,normal))

func _pose_stick(body: StaticBody3D, row: Dictionary) -> void:
	var yaw := float(body.get_meta("drop_id"))*2.39996
	var normal: Vector3 = row.get("stick_normal",Vector3.UP)
	var orientation := Basis(Quaternion(Vector3.UP,normal)) * Basis(Vector3.UP,yaw)
	var grounded: bool = row.has("stick_normal") or row.get("resting",false)
	orientation *= Basis(Vector3.BACK,PI*0.5 if grounded else float(row.get("stick_spin",yaw)))
	body.get_node("Item").basis = orientation.scaled(Vector3.ONE * 1.18)
	var collider: CollisionShape3D = body.get_node("PickupShape")
	var shape := collider.shape as BoxShape3D
	var size := Vector3(0.11,0.56,0.09) if grounded else Vector3(0.13,0.12,0.13)
	if not shape.size.is_equal_approx(size): shape.size = size
	collider.basis = orientation if grounded else Basis.IDENTITY

func _pose_log(body: StaticBody3D, log: Dictionary) -> void:
	var axis: Vector3 = log.axis
	var orientation := Basis.looking_at(-axis,Vector3.RIGHT if absf(axis.y)>0.98 else Vector3.UP)
	var mesh: MeshInstance3D = body.get_node("Item")
	mesh.basis = orientation * Basis(Vector3.BACK,float(log.get("roll",0))) * Basis.from_scale(Vector3(log.radius,log.radius,log.length))
	body.get_node("PickupShape").basis = orientation

func _observer_distance_squared(point: Vector3) -> float:
	return session.team_distance_squared(point)

func _near_buckets(point: Vector3, radius: float) -> Array[Dictionary]:
	var buckets: Array[Dictionary]=[]
	var extent:=Vector3(radius,0,radius)
	var first:=_drop_cell(point-extent)
	var last:=_drop_cell(point+extent)
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell:=Vector2i(x,z)
			if drop_chunks.has(cell): buckets.append(drop_chunks[cell])
	return buckets

func nearby_drops(point: Vector3, radius: float) -> Dictionary:
	var found: Dictionary={}
	var squared:=radius*radius
	for bucket in _near_buckets(point,radius):
		for id: String in bucket:
			var row: Dictionary=drop_records[id]
			if point.distance_squared_to(row.point)<squared: found[id]=row
	return found

# Only the host's live, settled harvest/debris can donate to a stack. The
# bounded live pool also bounds the work per refresh after loading a large camp.
func _stack_resting_materials() -> void:
	var open: Dictionary={}
	var changed:=false
	for id: String in drop_live.keys():
		var row: Dictionary=drop_records[id]
		if not row.get("loose_material",false) or not row.get("resting",false): continue
		# A newly activated record may be visible before its terrain and walls
		# are loaded. Wait until a wall check is meaningful on both sides.
		if not session.stream.at_surface(row.point): continue
		var items: Dictionary=row.items
		var item: String=items.keys().front()
		var limit: int=session.bag.stack_size(item)
		if int(items[item])>=limit: continue
		var stacks: Array=open.get_or_add(item,[])
		var point: Vector3=row.point
		for target: Dictionary in stacks:
			var room:=limit-int(target.items[item])
			if room<=0 or point.distance_squared_to(target.point)>0.8*0.8: continue
			if not point.is_equal_approx(target.point):
				var path:=PhysicsRayQueryParameters3D.create(point,target.point,1|2)
				if not get_world_3d().direct_space_state.intersect_ray(path).is_empty(): continue
			var amount:=mini(room,int(items[item]))
			target.items[item]+=amount
			items[item]-=amount
			changed=true
			if int(items[item])==0: break
		if int(items[item])==0: erase_drop(id)
		else: stacks.append(row)
	if changed and is_instance_valid(session.network) and session.network.server():
		session.network.invalidate_world()

func _resync_drops() -> void:
	if not is_instance_valid(session.player):
		return
	if not session.replica: _stack_resting_materials()
	var selected: Dictionary={}
	for person: WastelandSurvivor in session.living_players():
		var at:=person.global_position
		for bucket in _near_buckets(at,72.0):
			for id: String in bucket:
				var distance:=at.distance_squared_to(drop_records[id].point)
				var radius:=72.0 if drop_live.has(id) else 65.0
				if distance<=radius*radius and distance<float(selected.get(id,INF)):
					selected[id]=distance
	if selected.size()>DROPS:
		var ids:=selected.keys()
		ids.sort_custom(func(a,b): return selected[a]<selected[b] if selected[a]!=selected[b] else a<b)
		for i in range(DROPS,ids.size()): selected.erase(ids[i])
	for id in drop_live.keys():
		if not selected.has(id): _release_drop(id)
	for id in selected:
		if not drop_live.has(id): _show_drop(id)

func _show_drop(id:String)->void:
	var row:Dictionary=drop_records[id]
	for body in drops:
		if body.visible: continue
		body.set_meta("drop_id",id)
		var buoy:bool=row.get("buoy",false)
		_dress_drop(body,row)
		body.global_position=row.point
		body.show()
		body.collision_layer=2 if buoy else PICKUP_LAYER
		body.collision_mask=0 if buoy else 3
		drop_live[id]=body
		if session.replica and not buoy and not row.get("resting",false):
			replica_motion[id]=row.duplicate(true)
		return

func apply_drop_snapshot(records:Dictionary)->void:
	for id in drop_live.keys():
		if not records.has(id): _release_drop(id)
	drop_records=records
	drop_chunks.clear()
	for id: String in records: _index_drop(id,_drop_cell(records[id].point))
	_resync_drops()
	replica_motion.clear()
	for id in drop_live:
		var body:StaticBody3D=drop_live[id]
		var row:Dictionary=records[id]
		body.global_position=row.point
		if body.get_meta("item_types")!=hash(row.items.keys()):
			_dress_drop(body,row)
		elif row.has("log_section"):
			_pose_log(body,row.log_section)
		elif row.items.size()==1 and row.items.has("tree_leaf"):
			_pose_leaf(body,row)
		elif row.items.size()==1 and row.items.has("stick"):
			_pose_stick(body,row)
		if not row.get("buoy",false) and not row.get("resting",false):
			replica_motion[id]=row.duplicate(true)

func present_drops(dt:float)->void:
	drop_ticker-=dt
	if drop_ticker<=0.0:
		drop_ticker=0.9
		_resync_drops()
	for id in replica_motion:
		var row:Dictionary=replica_motion[id]
		if not row.get("resting",false): _step_drop(drop_live[id],row,dt)

func _step_drop(body:StaticBody3D,row:Dictionary,dt:float)->void:
	var point:Vector3=row.point
	if not session.stream.at_surface(point): return
	var v:Vector3=row.get("velocity",Vector3.ZERO)
	var wet:bool=point.y<0.12 and session.stream.water_at(point)
	var floating:=wet and bool(body.get_meta("floats",false))
	var leaf: bool = row.items.size()==1 and row.items.has("tree_leaf")
	var stick: bool = row.items.size()==1 and row.items.has("stick")
	var resting: bool = row.get("resting",false)
	var surface_y := 0.028 if leaf else 0.045
	if wet:
		var target_y:=clampf((surface_y-point.y)*4.0,-0.8,1.25) if floating else -1.65
		v.y=move_toward(v.y,target_y,10.0*dt)
		v.x=move_toward(v.x,0.0,2.2*dt)
		v.z=move_toward(v.z,0.0,2.2*dt)
		if floating and row.has("log_section"):
			var axis: Vector3 = row.log_section.axis
			var flat := axis.slide(Vector3.UP).normalized()
			if not flat.is_zero_approx():
				row.log_section.axis = axis.slerp(flat,minf(1.0,dt*3.0))
				_pose_log(body,row.log_section)
	elif leaf and not resting:
		var phase := fmod(float(row.get("leaf_phase",0.0)) + dt*3.7,TAU*100)
		row.leaf_phase = phase
		var yaw := float(body.get_meta("drop_id")) * 2.39996
		var needles := _is_needle_drop(row)
		var drift := Vector2(0.66*sin(phase),0.38*cos(phase*0.83)).rotated(yaw) * (0.65 if needles else 1.0)
		v.x = move_toward(v.x,0.26+drift.x,dt*2.8)
		v.z = move_toward(v.z,0.10+drift.y,dt*2.8)
		v.y = move_toward(v.y,(-1.64 if needles else -1.12)-0.27*cos(phase*1.38),dt*4.8)
	else:
		v.y=maxf(v.y-DROP_GRAVITY*dt,-25.0)
	var motion:=v*dt
	var supported:=false
	var tipping:=false
	for contact in 2:
		if motion.is_zero_approx(): break
		drop_motion.from=Transform3D(Basis.IDENTITY,point)
		drop_motion.motion=motion
		if not _drop_collides(body,leaf or stick):
			point+=motion
			break
		point+=drop_contact.get_travel()
		var normal:=drop_contact.get_collision_normal()
		supported=supported or normal.y>0.55
		var closing := -v.dot(normal)
		if stick and not wet and normal.y>0.55 and closing>2.75 and not row.get("stick_bounced",false):
			row.stick_bounced = true
			v = v.slide(normal)*0.62 + normal*minf(1.15,closing*0.16)
			supported = false
			break
		if v.dot(normal)<0.0: v=v.slide(normal)
		if normal.y>0.55:
			if stick: row.stick_normal = normal.normalized()
			if leaf:
				# A tumbling leaf first catches an edge. Lay the whole blade onto
				# the support instead of leaving its centre at that first height.
				var surface := drop_contact.get_collider()
				if is_instance_valid(surface) and surface.get_meta("kind","")=="terrain":
					normal = session.stream.ground_normal_at(point)
					point.y = session.stream.ground_at(point)+0.027/maxf(normal.y,0.45)
				elif not resting:
					point = drop_contact.get_collision_point() + normal*0.027
				row.leaf_normal = normal.normalized()
				v = Vector3.ZERO
				break
			var friction := 4.0
			if row.has("log_section"):
				var log: Dictionary = row.log_section
				var axis: Vector3 = log.axis
				var shifted := _tip_log(log,point,drop_contact.get_collision_point(),dt)
				tipping = tipping or not shifted.is_equal_approx(point)
				point = shifted
				if not tipping:
					log.erase("tip_speed")
					var flat := axis.slide(normal).normalized()
					if not flat.is_zero_approx():
						log.axis = axis.slerp(flat,minf(1.0,dt*6.0))
				log.roll = fmod(float(log.get("roll",0))+v.dot(normal.cross(axis))*dt / maxf(float(log.radius),0.05),TAU)
				_pose_log(body,log)
				friction = 3.3 if normal.y > 0.97 else 1.9
			v=v.move_toward(Vector3.ZERO,friction*dt)
		motion=v*dt*(1.0-drop_contact.get_collision_safe_fraction())
	if (supported and not tipping and v.length_squared()<0.0004) or (floating and absf(point.y-surface_y)<0.008 and v.length_squared()<0.002):
		row.resting=true
		row.erase("velocity")
	else:
		row.erase("resting")
		row.velocity=v
	body.global_position=point
	if not session.replica:
		var previous:=_drop_cell(row.point)
		var current:=_drop_cell(point)
		if previous!=current:
			var id: String=body.get_meta("drop_id")
			_unindex_drop(id,previous)
			_index_drop(id,current)
	row.point=point
	if leaf:
		if floating: row.leaf_normal = Vector3.UP
		elif not supported: row.erase("leaf_normal")
		_pose_leaf(body,row)
	elif stick:
		if floating: row.stick_normal = Vector3.UP
		elif not supported:
			row.erase("stick_normal")
			row.stick_spin = fmod(float(row.get("stick_spin",float(body.get_meta("drop_id"))*2.39996))+dt*6.2,TAU)
		_pose_stick(body,row)

func _drop_collides(body: StaticBody3D, through_plants: bool) -> bool:
	var hit := PhysicsServer3D.body_test_motion(body.get_rid(),drop_motion,drop_contact)
	if not hit or not through_plants: return hit
	var ignored: Array[RID] = []
	while hit:
		var obstacle := drop_contact.get_collider()
		if not is_instance_valid(obstacle) or not preload("res://game/world/leaf_litter.gd").passes_through(obstacle,drop_contact.get_collision_normal()): break
		var rid := drop_contact.get_collider_rid()
		if ignored.has(rid): break
		ignored.append(rid)
		drop_motion.exclude_bodies = ignored
		hit = PhysicsServer3D.body_test_motion(body.get_rid(),drop_motion,drop_contact)
	if not ignored.is_empty(): drop_motion.exclude_bodies = []
	return hit

# A single contact can stop translation without supporting the centre of mass.
# Tip the free end around the bearing until another solid surface takes its weight.
func _tip_log(log: Dictionary, center: Vector3, bearing: Vector3, dt: float) -> Vector3:
	var axis: Vector3 = log.axis
	var length: float = log.length
	var lever := clampf((bearing-center).dot(axis),-length*0.5,length*0.5)
	if absf(lever)<length*0.16 or absf(axis.y)>0.97: return center
	var sign_end := signf(lever)
	var free := center-axis*(sign_end*length*0.46)
	var clearance := _log_clearance(free,log.radius,length)
	if clearance<=0.035 or _log_clearance(center,log.radius,length)<=0.035: return center
	var inertia := length*length/12.0 + lever*lever
	var omega := minf(3.0,float(log.get("tip_speed",0))+DROP_GRAVITY*absf(lever)*dt/inertia)
	var turn := minf(omega*dt,clearance/(absf(lever)+length*0.5))
	var tilted := axis.rotated(axis.cross(Vector3.UP).normalized(),turn*sign_end)
	log.axis = tilted
	log.tip_speed = omega
	return center-(tilted-axis)*lever

func _log_clearance(point: Vector3, radius: float, reach: float) -> float:
	var test := PhysicsRayQueryParameters3D.create(point+Vector3.UP*radius*0.5,point-Vector3.UP*(reach+radius),3)
	var hit := get_world_3d().direct_space_state.intersect_ray(test)
	return reach if hit.is_empty() else point.y-radius-float(hit.position.y)

func simulate(delta: float) -> void:
	for body in debris:
		if body.visible and session.clock.elapsed >= float(body.get_meta("end", 0.0)):
			body.hide()
			body.freeze = true
	simulate_projectiles(delta)
	drop_ticker -= delta
	var check_support:=drop_ticker<=0.0
	if check_support:
		drop_ticker = 0.9
		_resync_drops()
	for id in drop_live:
		var row:Dictionary=drop_records[id]
		if row.get("buoy",false): continue
		if check_support or not row.get("resting",false):
			_step_drop(drop_live[id],row,delta)

func simulate_projectiles(delta: float) -> void:
	for i in particles.size():
		if particle_time[i] <= 0.0: continue
		particle_time[i] = maxf(0.0, particle_time[i]-delta)
		if particle_time[i] == 0.0:
			particles[i].emitting=false
			particles[i].hide()
	for pool in pools:
		if pool.life <= 0.0: continue
		pool.life -= delta
		if pool.life <= 0.0:
			pool.node.hide()
			continue
		pool.next -= delta
		if pool.next <= 0.0:
			pool.next = 0.78
			burst(pool.at + pool.normal * 0.06,Color("#c4d562"),0.34)
			if not session.replica:
				session.hordes.damage_near(pool.at + pool.normal * 0.06,ACID_RADIUS,4.0*float(session.world_settings.difficulty),"residue")
	for shot in shots:
		if shot.life <= 0.0:
			continue
		var step := minf(delta,shot.life)
		shot.life -= step
		var node: MeshInstance3D = shot.node
		var from := node.global_position
		var velocity: Vector3 = shot.vel
		velocity.y -= (11.8 if shot.kind == "arrow" else ACID_GRAVITY if shot.kind == "acid" else 2.8) * step
		shot.vel = velocity
		var next := from + velocity * step
		var owner: Node3D = shot.owner if is_instance_valid(shot.owner) else null
		if int(shot.shooter) > 0 and (not is_instance_valid(owner) or not owner.active or owner.spawn_serial != shot.shooter):
			owner = session.network.smooth_actors.get(shot.shooter) if session.replica and is_instance_valid(session.network) else session.hordes.actors_by_serial.get(shot.shooter)
		shot.owner = owner
		var exclude: Array[RID] = []
		if is_instance_valid(owner):
			exclude.append(owner.get_rid())
		var check := PhysicsRayQueryParameters3D.create(from, next, 15, exclude)
		var hit:Dictionary=session.weapon_hit(from,next,exclude) if shot.kind!="acid" else get_world_3d().direct_space_state.intersect_ray(check)
		if not hit.is_empty():
			shot.life = 0.0
			if session.replica:
				burst(hit.position, Color("#abc876"), 1.15)
			else:
				session.projectile_hit(shot.kind, float(shot.hit), hit, owner, shot.origin)
		if shot.life <= 0.0:
			node.hide()
			shot.owner = null
			shot.shooter = 0
			shot.id = 0
			shot.kind = ""
			shot.hit = 0.0
			shot.vel = Vector3.ZERO
			shot.origin = Vector3.ZERO
		else:
			node.global_position = next
			_aim_shot(node,velocity)
