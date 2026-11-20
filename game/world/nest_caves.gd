extends RefCounted

const Chest := preload("res://game/art/supply_chest.gd")
const Containers := preload("res://game/world/regional_caches.gd")
const RINGS := 6
const ARCH := [Vector2(-2.35,-0.65),Vector2(-2.30,1.9),Vector2(-1.55,2.85),Vector2(0,3.2),Vector2(1.65,2.75),Vector2(2.37,1.8),Vector2(2.40,-0.65)]

static func location(chunk: WastelandChunk) -> Vector3:
	var terrain: WastelandTerrainGen = chunk.stream.generator
	if terrain.revision < 3 or chunk.cell.length_squared() < 9 or not chunk.site.is_empty():
		return Vector3.INF
	if posmod(terrain.seed_at(chunk.cell,72821),18) != 0: return Vector3.INF
	for offset: Vector2 in [Vector2(16,16),Vector2(22,12),Vector2(10,21)]:
		var world := Vector2(chunk.position.x,chunk.position.z) + offset
		var floor_y := terrain.ground(world.x,world.y)
		if floor_y < 1.1 or terrain.road_strength(world.x,world.y) > 0.25: continue
		var valid := true
		for axis: Vector2 in [Vector2(-2.6,-5),Vector2(2.6,-5),Vector2(-2.6,5),Vector2(2.6,5),Vector2(0,6)]:
			var p := world + axis
			if absf(terrain.ground(p.x,p.y)-floor_y) > 1.35 or terrain.road_strength(p.x,p.y)>0.35:
				valid = false
				break
		if valid: return Vector3(offset.x,floor_y,offset.y)
	return Vector3.INF

static func inside_footprint(local: Vector3, cave: Vector3) -> bool:
	return absf(local.x - cave.x) < 5.4 and absf(local.z - cave.z) < 7.0

static func ground_point(chunk: WastelandChunk, x: float, z: float) -> Vector3:
	var local := chunk.cave_origin + Vector3(x,0,z)
	local.y = chunk.stream.ground_at(chunk.position + local)
	return local

static func build(chunk: WastelandChunk) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk.stream.generator.seed_at(chunk.cell,5093)
	var rock := WastelandScenery.new(rng.seed)
	var inner: Array[PackedVector3Array] = []
	var outer: Array[PackedVector3Array] = []
	for section in RINGS:
		var z := 5.0 - section * 2.1
		var bore := PackedVector3Array()
		var ridge := PackedVector3Array()
		for profile: Vector2 in ARCH:
			var x := profile.x * rng.randf_range(0.93,1.06)
			var ground := ground_point(chunk,x,z)
			bore.append(ground + Vector3.UP * profile.y)
			var outside := ground_point(chunk,x*1.9,z)
			ridge.append(outside + Vector3.UP * (profile.y*1.40 + (0.60 if profile.y > 0 else 0.0)))
		inner.append(bore)
		outer.append(ridge)
	for section in RINGS:
		for segment in ARCH.size()-1:
			var axis: Vector2 = (ARCH[segment]+ARCH[segment+1])*0.5
			var normal := Vector3(axis.x,axis.y,0).normalized()
			if section < RINGS-1:
				_quad(rock,inner[section][segment],inner[section+1][segment],inner[section+1][segment+1],inner[section][segment+1],-normal,Color("#60596a").lightened(rng.randf()*0.13))
				_quad(rock,outer[section][segment],outer[section][segment+1],outer[section+1][segment+1],outer[section+1][segment],normal,Color("#76736d").darkened(rng.randf()*0.16))
			if section == 0:
				_quad(rock,inner[0][segment],inner[0][segment+1],outer[0][segment+1],outer[0][segment],Vector3.BACK,Color("#817b72"))
			if section == RINGS-1:
				var base := ground_point(chunk,0,-5.5)-Vector3.UP*0.66
				rock.triangle(inner[section][segment],inner[section][segment+1],base,Vector3.BACK,Color("#575566"))
				rock.triangle(outer[section][segment],outer[section][segment+1],base,Vector3.FORWARD,Color("#706c65"))
	var body := StaticBody3D.new()
	body.collision_layer=2
	body.collision_mask=0
	body.set_meta("kind","terrain")
	chunk.poi_root.add_child(body)
	var model := MeshInstance3D.new()
	model.mesh = rock.commit()
	model.material_override = WastelandLook.colored_material()
	body.add_child(model)
	if not chunk.stream.is_preview:
		var collision := CollisionShape3D.new()
		var shape := model.mesh.create_trimesh_shape()
		shape.backface_collision=true
		collision.shape=shape
		body.add_child(collision)
		chunk.obstacles.append(body)
	var mouth := ground_point(chunk,0,4.8)
	WastelandSite.board_door(chunk,mouth,4.55,"cave/boards")
	_waterfall(chunk,ground_point(chunk,-1.5,5.12))
	var table: String = ["weapons","safe","medical","garage_spares"][rng.randi_range(0,3)]
	var chest_at := ground_point(chunk,-0.55,-4.05) + Vector3.UP * (Chest.DIMENSIONS.ridge.y*0.5)
	Containers.spawn(chunk,"nest/cache",table,chest_at,{"cache_floor":0,"cache_approach":chunk.position+chest_at+Vector3.BACK*1.3},"ridge")
	chunk.sleeper_anchors.append(ground_point(chunk,1.1,-2.1))
	chunk.sleeper_anchors.append(ground_point(chunk,-1.2,0.8))

static func _quad(mesh: WastelandScenery, a: Vector3,b: Vector3,c: Vector3,d: Vector3, facing: Vector3,tint: Color) -> void:
	mesh.triangle(a,b,c,facing,tint)
	mesh.triangle(a,c,d,facing,tint.darkened(0.035))

static func _waterfall(chunk: WastelandChunk, at: Vector3) -> void:
	var spray := GPUParticles3D.new()
	spray.amount=48
	spray.lifetime=0.88
	spray.preprocess=0.85
	spray.visibility_aabb=AABB(Vector3(-1,-4.8,-0.8),Vector3(2,5,1.6))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents=Vector3(0.55,0.04,0.05)
	motion.direction=Vector3(0,-1,0.10)
	motion.spread=5.0
	motion.initial_velocity_min=1.2
	motion.initial_velocity_max=1.65
	motion.gravity=Vector3(0,-9.8,0)
	spray.process_material=motion
	var drop := BoxMesh.new()
	drop.size=Vector3(0.085,0.48,0.055)
	drop.material=WastelandLook.matte(Color("#81aeb0"),0.14)
	spray.draw_pass_1=drop
	spray.position=at+Vector3.UP*2.95
	chunk.poi_root.add_child(spray)
