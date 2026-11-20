extends RefCounted

const Chest := preload("res://game/art/supply_chest.gd")

static func spawn(chunk: WastelandChunk, local_id: String, table: String, point: Vector3, meta: Dictionary, profile: String) -> StaticBody3D:
	meta["type"] = table
	meta["cache_profile"] = profile
	var size: Vector3 = Chest.DIMENSIONS[profile]
	var body := chunk.object_body(local_id,"loot",point,size,meta)
	var model := Chest.new()
	body.add_child(model)
	var finish:=0
	if chunk.stream.generator.site_revision>0:
		finish=1+posmod(chunk.stream.generator.seed_at(chunk.cell,0x3511)^local_id.hash(),8)
	body.set_meta("finish_variant",finish)
	model.configure(profile,table,finish)
	var key: String = body.get_meta("key")
	chunk.supply_caches[key] = model
	chunk.sync_cache(key,false)
	return body

static func wilderness(chunk: WastelandChunk, dressing: Array) -> void:
	var gen: WastelandTerrainGen = chunk.stream.generator
	if gen.revision < 2 or chunk.cell.length_squared() < 9: return
	_wild_cache(chunk,dressing,gen,"wilderness/supply",7819,false)
	if gen.site_revision>0 and not chunk.supply_caches.is_empty():
		_wild_cache(chunk,dressing,gen,"wilderness/supply/1",19553,true)

static func _wild_cache(chunk:WastelandChunk,dressing:Array,gen:WastelandTerrainGen,key:String,salt:int,secondary:bool)->void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_at(chunk.cell,salt)
	var mid:=chunk.position+Vector3(16,0,16)
	var dedicated:=gen.region_kind(mid.x,mid.z) in ["alpine","desert"]
	if rng.randf() > (0.20 if secondary else 0.14 if dedicated else 0.10): return
	for attempt in (12 if dedicated else 4):
		var at := Vector3(rng.randf_range(3,29),0,rng.randf_range(3,29))
		var world := chunk.position+at
		var y := gen.ground(world.x,world.z)
		if y < 0.75 or gen.road_strength(world.x,world.z)>0.75: continue
		var dx := absf(gen.ground(world.x+0.75,world.z)-gen.ground(world.x-0.75,world.z))
		var dz := absf(gen.ground(world.x,world.z+0.75)-gen.ground(world.x,world.z-0.75))
		if maxf(dx,dz)>(0.56 if dedicated else 0.36): continue
		var blocked := false
		for entry in dressing:
			var p: Vector3 = entry.point
			if entry.id in WastelandTerrainGen.RESOURCES and Vector2(p.x-at.x,p.z-at.z).length_squared()<4.0:
				blocked = true
				break
		if secondary:
			for cache:Node3D in chunk.supply_caches.values():
				if Vector2(cache.global_position.x-world.x,cache.global_position.z-world.z).length_squared()<20:
					blocked=true
		if blocked: continue
		var profile := Chest.kind_at(gen,world)
		var size: Vector3 = Chest.DIMENSIONS[profile]
		at.y = y+size.y*0.42
		var body := spawn(chunk,key,profile+"_cache",at,{},profile)
		body.rotation.y = rng.randf_range(-PI,PI)
		return
