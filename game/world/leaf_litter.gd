extends Node3D

const Shapes := preload("res://game/art/leaf_shapes.gd")
const LIMITS := {"oak":80, "birch":64, "needles":96}
const SAMPLE_COUNT := 192
const SKIN := 0.019
const WATER := WastelandTerrainGen.WATER_LEVEL
enum { AIR, REST, FLOATING }

class Canopy:
	var points := PackedVector3Array()
	var colours := PackedColorArray()

class Leaf:
	var point := Vector3.ZERO
	var traced := Vector3.ZERO
	var velocity := Vector3.ZERO
	var normal := Vector3.UP
	var colour := Color.WHITE
	var phase := 0.0
	var spin := 0.0
	var yaw := 0.0
	var size := 1.0
	var age := 0.0
	var linger := 0.0
	var check_in := 0.0
	var state := AIR
	var support: WeakRef

class Batch:
	var mesh: MultiMesh
	var leaves: Array[Leaf] = []
	var needles := false

static var _canopies := {}
var _batches := {}
var _ground: Callable
var _water: Callable
var _ray := PhysicsRayQueryParameters3D.new()
var _material := ShaderMaterial.new()

func setup(ground_at: Callable, water_at: Callable) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_ground = ground_at
	_water = water_at
	_ray.collision_mask = 2
	_material.shader = preload("res://shaders/scenery.gdshader")

# Use the same near mesh as the cut and its upper half. Read each variant only
# once. The sampled face centroid and its pigment remain paired through the fall.
static func _canopy(model: String, variant: int) -> Canopy:
	var key := "%s/%d" % [model,variant]
	if _canopies.has(key): return _canopies[key]
	var data := Canopy.new()
	var mesh := WastelandChunk._nature_mesh(model, variant, true)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var ids := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null: ids = arrays[Mesh.ARRAY_INDEX]
	var total := ids.size() if not ids.is_empty() else vertices.size()
	var seen := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	for offset in range(0, total, 3):
		var a := offset if ids.is_empty() else ids[offset]
		var b := offset+1 if ids.is_empty() else ids[offset+1]
		var c := offset+2 if ids.is_empty() else ids[offset+2]
		var point := (vertices[a]+vertices[b]+vertices[c])/3.0
		var pigment := colours[a]
		if model == "snag":
			if point.y < 1.6 or Vector2(point.x,point.z).length_squared() < 0.80: continue
		elif model == "birch" or (model == "oak" and variant == 2):
			# Yellow and russet foliage has a stronger yellow component than bark.
			if pigment.g - pigment.b <= 0.16: continue
		elif pigment.g < pigment.r + 0.012 or pigment.g > 0.82:
			# The other broadleaves and fir sprays are green. Exclude white snow caps.
			continue
		seen += 1
		if data.points.size() < SAMPLE_COUNT:
			data.points.append(point)
			data.colours.append(pigment)
		else:
			var slot := rng.randi_range(0,seen-1)
			if slot < SAMPLE_COUNT:
				data.points[slot] = point
				data.colours[slot] = pigment
	_canopies[key] = data
	return data

static func crown_point(model: String, variant: int, pose: Transform3D, seed_value: int) -> Vector3:
	var canopy := _canopy(model, variant)
	if canopy.points.is_empty(): return pose.origin
	return pose * canopy.points[posmod(hash(seed_value),canopy.points.size())]

func _batch(form: String) -> Batch:
	if _batches.has(form): return _batches[form]
	var batch := Batch.new()
	batch.needles = form == "needles"
	batch.mesh = MultiMesh.new()
	batch.mesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh.use_colors = true
	batch.mesh.mesh = Shapes.build(form)
	batch.mesh.instance_count = LIMITS[form]
	batch.mesh.visible_instance_count = 0
	var draw := MultiMeshInstance3D.new()
	draw.name = "Litter_" + form
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	draw.multimesh = batch.mesh
	draw.material_override = _material
	add_child(draw)
	_batches[form] = batch
	return batch

func shed(model: String, variant: int, pose: Transform3D, seed_value: int, count: int, impulse := Vector3.ZERO) -> void:
	if model == "snag" or count <= 0: return
	var canopy := _canopy(model,variant)
	if canopy.points.is_empty(): return
	var batch := _batch(model if model in ["oak","birch"] else "needles")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in mini(count,batch.mesh.instance_count):
		var slot := batch.leaves.size()
		var leaf: Leaf
		if slot == batch.mesh.instance_count:
			# Reuse the oldest bit of litter first when several trees land at once.
			slot = 0
			for j in range(1,batch.leaves.size()):
				if batch.leaves[j].age > batch.leaves[slot].age: slot = j
			leaf = batch.leaves[slot]
		else:
			leaf = Leaf.new()
			batch.leaves.append(leaf)
		var sample := rng.randi_range(0,canopy.points.size()-1)
		var local := canopy.points[sample]
		leaf.point = pose * local
		leaf.point.y = maxf(leaf.point.y,float(_ground.call(leaf.point)) + SKIN)
		leaf.traced = leaf.point
		leaf.phase = rng.randf_range(0,TAU)
		leaf.yaw = rng.randf_range(0,TAU)
		leaf.spin = rng.randf_range(1.6,4.9) * (-1.0 if rng.randf() < 0.5 else 1.0)
		leaf.size = rng.randf_range(0.83,1.37) * clampf(pose.basis.y.length(),0.75,1.45)
		leaf.colour = canopy.colours[sample].lightened(rng.randf_range(0.02,0.14))
		var outward := (pose.basis * Vector3(local.x,0,local.z)).normalized()
		leaf.velocity = impulse * rng.randf_range(0.55,1.10) + outward * rng.randf_range(0.22,0.78)
		leaf.velocity += Vector3(cos(leaf.phase)*0.47,rng.randf_range(0.12,0.78),sin(leaf.phase)*0.47)
		leaf.normal = Vector3.UP
		leaf.age = 0
		leaf.linger = rng.randf_range(12.0,21.0)
		leaf.check_in = rng.randf_range(0.01,0.10)
		leaf.state = AIR
		leaf.support = null
		batch.mesh.set_instance_color(slot,leaf.colour)
		_draw(batch,slot,leaf)
	batch.mesh.visible_instance_count = batch.leaves.size()

func advance(dt: float) -> void:
	if dt <= 0.0 or _batches.is_empty(): return
	for batch: Batch in _batches.values():
		for i in range(batch.leaves.size()-1,-1,-1):
			var leaf := batch.leaves[i]
			leaf.age += dt
			if leaf.age >= leaf.linger:
				var last := batch.leaves.size()-1
				if i != last:
					batch.leaves[i] = batch.leaves[last]
					batch.mesh.set_instance_color(i,batch.leaves[i].colour)
					_draw(batch,i,batch.leaves[i])
				batch.leaves.pop_back()
				batch.mesh.visible_instance_count = batch.leaves.size()
				continue
			if leaf.state == REST:
				leaf.check_in -= dt
				if leaf.check_in <= 0.0:
					leaf.check_in = 0.9 + 0.07 * leaf.phase
					if not _supported(leaf):
						leaf.state = AIR
						leaf.support = null
						leaf.velocity = Vector3.DOWN * 0.45
						leaf.traced = leaf.point
						leaf.check_in = 0.04
				if leaf.state == REST and leaf.linger - leaf.age > 1.4: continue
			if leaf.state == AIR:
				_fall(leaf,dt,batch.needles)
			elif leaf.state == FLOATING:
				_float(leaf,dt)
			_draw(batch,i,leaf)

func _fall(leaf: Leaf, dt: float, needles: bool) -> void:
	var t := leaf.phase + leaf.age * (3.1 if needles else 4.0)
	var flutter := sin(t)
	var wind := Vector3(0.32 + sin(t * 0.49)*0.24,0,0.13 + cos(t*0.61)*0.19)
	var crosswind := Vector3(cos(leaf.phase),0,sin(leaf.phase))
	var slip := crosswind * flutter * (0.34 if needles else 1.24)
	var terminal := 2.55 if needles else 1.66
	var target := wind + slip + Vector3.DOWN * (terminal - 0.34 * flutter * flutter)
	leaf.velocity = leaf.velocity.lerp(target,1.0-exp(-dt*(2.0 if needles else 1.55)))
	leaf.point += leaf.velocity * dt
	leaf.yaw += leaf.spin * dt * (0.72 + 0.28 * flutter)
	leaf.check_in -= dt
	if leaf.check_in > 0.0: return
	leaf.check_in += 0.095
	_touch(leaf)

func _touch(leaf: Leaf) -> void:
	var floor_y := float(_ground.call(leaf.point))
	var wet := floor_y < WATER and leaf.point.y <= WATER + 0.065 and bool(_water.call(leaf.point))
	var stop_y := WATER if wet else floor_y
	_ray.from = leaf.traced + Vector3.UP * SKIN
	_ray.to = leaf.point - Vector3.UP * SKIN
	var hit := _solid_hit()
	if not hit.is_empty() and hit.position.y > stop_y:
		var normal: Vector3 = hit.normal
		leaf.point = Vector3(hit.position) + normal * SKIN
		if normal.y >= 0.50:
			leaf.state = REST
			leaf.normal = normal
			leaf.support = weakref(hit.collider)
			leaf.check_in = 0.9 + leaf.phase * 0.07
		else:
			leaf.velocity = leaf.velocity.slide(normal) + normal * 0.16
	elif leaf.point.y <= stop_y + SKIN:
		leaf.point.y = stop_y + SKIN
		if wet:
			leaf.state = FLOATING
			leaf.normal = Vector3.UP
		else:
			var x_slope := float(_ground.call(leaf.point + Vector3.RIGHT*0.08)) - floor_y
			var z_slope := float(_ground.call(leaf.point + Vector3.BACK*0.08)) - floor_y
			leaf.normal = Vector3(-x_slope,0.08,-z_slope).normalized()
			leaf.state = REST
			leaf.check_in = 0.9 + leaf.phase * 0.07
	elif leaf.state == FLOATING and not wet:
		leaf.state = AIR
		leaf.velocity = Vector3.DOWN * 0.15
	leaf.traced = leaf.point

func _solid_hit() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(_ray)
	if hit.is_empty(): return hit
	var ignored: Array[RID] = []
	# Ignore harvest/pickup boxes that rise above grass and small loose objects.
	while not hit.is_empty():
		var body: Object = hit.collider
		if not passes_through(body,hit.normal): break
		ignored.append(hit.rid)
		_ray.exclude = ignored
		hit = space.intersect_ray(_ray)
	if not ignored.is_empty():
		ignored.clear()
		_ray.exclude = ignored
	return hit

# The flat lid of a trunk's chopping collider sits partway up the rendered
# trunk. A drifting leaf can glance off its side but cannot perch on that lid.
static func passes_through(body: Object, normal: Vector3) -> bool:
	if not body is StaticBody3D: return true
	var kind: String = body.get_meta("kind","")
	if kind in ["crop","drop","buoy"]: return true
	if kind!="resource": return false
	return (body.has_meta("tree_pose") and normal.y>0.45) or body.get_meta("resource","") in preload("res://game/world/felling_tree.gd").SOFT_RESOURCES

func _supported(leaf: Leaf) -> bool:
	if leaf.support != null:
		var body := leaf.support.get_ref() as CollisionObject3D
		return is_instance_valid(body) and not body.is_queued_for_deletion() and (body.collision_layer & 2) != 0
	return float(_ground.call(leaf.point)) >= leaf.point.y - SKIN - 0.035

func _float(leaf: Leaf, dt: float) -> void:
	var t := leaf.phase + leaf.age * 1.8
	leaf.yaw += dt * sin(t*0.52) * 0.15
	leaf.point += Vector3(0.084 + sin(t)*0.036,0,0.035+cos(t)*0.046) * dt
	leaf.point.y = WATER + 0.034 + sin(t)*0.014
	leaf.check_in -= dt
	if leaf.check_in <= 0.0:
		leaf.check_in = 0.3
		_touch(leaf)

func _draw(batch: Batch, slot: int, leaf: Leaf) -> void:
	var basis := Basis(Vector3.UP,leaf.yaw)
	var t := leaf.phase + leaf.age*(3.1 if batch.needles else 4.0)
	if leaf.state == AIR:
		basis *= Basis(Vector3.RIGHT,0.45 + sin(t) * 0.94)
		basis *= Basis(Vector3.BACK,cos(t*0.77) * (1.08 if batch.needles else 0.64))
	elif leaf.state == FLOATING:
		basis *= Basis(Vector3.RIGHT,sin(t)*0.075)
	else:
		basis = Basis(Quaternion(Vector3.UP,leaf.normal)) * basis
	var scale_factor := leaf.size * smoothstep(0.0,1.4,leaf.linger - leaf.age)
	batch.mesh.set_instance_transform(slot,Transform3D(basis.scaled(Vector3.ONE*scale_factor),leaf.point))
