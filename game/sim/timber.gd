extends RefCounted

const FallingTree := preload("res://game/world/felling_tree.gd")
const LeafLitter := preload("res://game/world/leaf_litter.gd")
const AXES := ["stone_axe","iron_axe","steel_axe","shovel"]
const NAMES := {"oak":"秋叶橡树","pine":"林地松树","birch":"白桦","snag":"枯立木","snow_fir":"积雪冷杉","frost_fir":"霜杉"}
const SAPLING_PERCENT := {"oak":16,"birch":20,"pine":18,"frost_fir":15,"snow_fir":14}
var session: WastelandSession
var active := {}
var records := {}
var finished_mirrors := {}
var litter: LeafLitter
var next_gust := 9.0

func configure(world: WastelandSession, saved: Dictionary) -> void:
	session = world
	litter = LeafLitter.new()
	session.add_child(litter)
	litter.setup(session.stream.ground_at,session.stream.water_at)
	for key: String in saved:
		_spawn(key,saved[key].duplicate(true))

func mark(body: StaticBody3D, impact: Vector3, progress: float, diff: Dictionary) -> Dictionary:
	var chunk: WastelandChunk = session.stream.active[body.get_meta("cell")]
	var id: String = body.get_meta("index")
	var pose: Transform3D = body.get_meta("tree_pose")
	var base := chunk.to_global(pose.origin)
	var away := (base-session.player.global_position).slide(Vector3.UP).normalized()
	if away.is_zero_approx():
		away = -session.player.global_basis.z
	var local_hit := pose.affine_inverse() * chunk.to_local(impact)
	var wound := local_hit.slide(Vector3.UP).normalized()
	if wound.is_zero_approx(): wound = (pose.basis.inverse() * -away).normalized()
	if not diff.has("tree_cuts"): diff.tree_cuts = {}
	var cut: Dictionary = diff.tree_cuts.get(id,{})
	if cut.is_empty():
		cut = {"model":body.get_meta("tree_model"),"variant":body.get_meta("tree_variant"),
			"pose":pose,"face":wound,"height":local_hit.y,"direction":away}
	else:
		# The notch keeps its bearing; changing sides for the last blow steers the fall.
		cut.direction = (away * 0.72 + Vector3(cut.direction) * 0.28).normalized()
	cut.progress = progress
	diff.tree_cuts[id] = cut
	var canopy := chunk.global_transform * pose
	var salt := session.stream.generator.seed_at(chunk.cell,id.to_int())
	if cut.model != "snag":
		var seed_value := salt ^ roundi(progress*1000.0)
		shake(cut.model,cut.variant,canopy,seed_value,5 if progress<0.5 else 9,away*0.42)
		if progress >= 0.5 and not cut.get("leaf_shaken",false):
			cut.leaf_shaken = true
			_drop_leaves(cut.model,cut.variant,canopy,salt,1,away*0.42)
	return cut

func fell(body: StaticBody3D, cut: Dictionary, loot: Dictionary) -> void:
	var cell: Vector2i = body.get_meta("cell")
	var chunk: WastelandChunk = session.stream.active[cell]
	var id: String = body.get_meta("index")
	var key: String = body.get_meta("key")
	var record := {"cut":cut.duplicate(true),"base":chunk.global_position,
		"loot":loot.duplicate(),"elapsed":0.0,"victims":{}}
	var exclude: Array[RID] = [body.get_rid()]
	var parts := WastelandChunk.cut_meshes(cut)
	if chunk.planted.has(id):
		var diff := session.stream.edit_chunk(cell)
		diff.planted_trees.erase(id)
		# Unlike natural scenery, a player-grown trunk has no seed-generated
		# original to suppress on reload. Its stump is stored in tree_cuts.
		diff.removed.erase(id)
	chunk.sync_tree_cut(id,cut,parts)
	exclude.append(chunk.timber_visuals[id].get_rid())
	_spawn(key,record,exclude,parts)
	session.audio.play_at("tree_split",active[key].global_position,1.0)
	session.hordes.add_noise(active[key].global_position,20.0,false)
	if is_instance_valid(session.network): session.network.slow_timer = 0.0

func clear_stump(body: StaticBody3D, point: Vector3) -> void:
	if session.replica or body.is_queued_for_deletion(): return
	if session.bag.current() not in AXES:
		session.notify("树桩可以用斧头或铲子清除",1.4)
		return
	var cell: Vector2i = body.get_meta("cell")
	var id: String = body.get_meta("index")
	var cuts: Dictionary = session.stream.edit_chunk(cell).get("tree_cuts",{})
	if not cuts.erase(id): return
	session.stream.active[cell].sync_tree_cut(id,{})
	session.audio.play_at("chop",point,0.8)
	session.fx.burst(point,Color("#bf956a"),0.85)
	session.drop_materials(point,{"wood":1})
	if is_instance_valid(session.network): session.network.slow_timer = 0.0

func _spawn(key: String, record: Dictionary, exclude: Array[RID] = [], parts: Dictionary = {}) -> void:
	var cut: Dictionary = record.cut
	if parts.is_empty(): parts = WastelandChunk.cut_meshes(cut)
	var pose: Transform3D = cut.pose
	var scale_m := pose.basis.y.length()
	var pivot: Vector3 = record.base + pose * Vector3(parts.pivot)
	var tree := FallingTree.new()
	session.add_child(tree)
	var upper := WastelandChunk.tree_piece(parts.upper)
	tree.add_child(upper)
	upper.transform = Transform3D(pose.basis,-(pose.basis * Vector3(parts.pivot)))
	active[key] = tree
	records[key] = record
	tree.struck.connect(_strike.bind(key))
	tree.impacted.connect(_impact.bind(key))
	tree.crown_swing.connect(_shed_moving.bind(key,16,31))
	tree.crown_contact.connect(_brush.bind(key))
	tree.settled.connect(_settle.bind(key))
	var targets := Callable() if session.replica else _targets.bind(pivot,float(parts.height)*scale_m+float(parts.crown_radius)*scale_m+3.0)
	tree.setup(pivot,cut.direction,float(parts.height)*scale_m,float(parts.trunk_radius)*scale_m,
		float(parts.crown_radius)*scale_m,session.stream.ground_at,targets,record.get("plan",{}),record.elapsed,exclude)
	record.plan = tree.get_plan()
	record.radius = float(parts.trunk_radius)*scale_m

func tick(dt: float) -> void:
	litter.advance(dt)
	if active.is_empty(): return
	for tree in active.values(): tree.advance(dt)

# Gusts near occupied woodland bring down an occasional collectible leaf.
# One outstanding natural drop and one harvest day per chunk bound unattended litter.
func woodland(dt: float) -> void:
	next_gust -= dt
	if next_gust > 0.0: return
	var gust_index := floori(session.clock.elapsed / 8.0)
	next_gust = 12.0 + posmod(gust_index,7) - session.atmosphere.rain_strength * 3.0
	var viewers := [session.player]
	if is_instance_valid(session.network) and is_instance_valid(session.network.member) and not session.network.member_dead:
		viewers.append(session.network.member)
	var used := {}
	for viewer: WastelandSurvivor in viewers:
		var at := viewer.global_position
		if at.y < session.stream.ground_at(at)-1.0: continue
		var cell := WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))
		var tree: StaticBody3D
		var best := -1
		for dz in range(-1,2):
			for dx in range(-1,2):
				var chunk: WastelandChunk = session.stream.active.get(cell+Vector2i(dx,dz))
				if chunk==null or used.has(chunk.cell): continue
				for body: StaticBody3D in chunk.standing_trees.values():
					if body.get_meta("tree_model")=="snag" or body.global_position.distance_squared_to(at)>16.0*16.0: continue
					var rank := hash([body.get_meta("key"),gust_index])
					if rank>best:
						best = rank
						tree = body
		if tree==null: continue
		var loc: Vector2i = tree.get_meta("cell")
		used[loc] = true
		var home: WastelandChunk = session.stream.active[loc]
		var pose: Transform3D = home.global_transform * Transform3D(tree.get_meta("tree_pose"))
		var model: String = tree.get_meta("tree_model")
		var variant: int = tree.get_meta("tree_variant")
		var breeze := Vector3(0.42,0,0.20)
		shake(model,variant,pose,best,4,breeze)
		var diff: Dictionary = session.stream.chunk_diff(loc)
		if int(diff.get("leaf_day",0))>=session.clock.day() or session.fx.drop_records.has(diff.get("last_leaf","")): continue
		diff = session.stream.edit_chunk(loc)
		diff.leaf_day = session.clock.day()
		diff.last_leaf = _drop_leaves(model,variant,pose,hash([best,diff.leaf_day]),1,breeze)

func shake(model: String, variant: int, pose: Transform3D, salt: int, count: int, impulse: Vector3) -> void:
	litter.shed(model,variant,pose,salt,count,impulse)
	if is_instance_valid(session.network) and not session.replica:
		session.network.mirror_canopy(model,variant,pose,salt,count,impulse)

func _drop_leaves(model: String, variant: int, pose: Transform3D, salt: int, amount: int, impulse: Vector3) -> String:
	if session.replica or not SAPLING_PERCENT.has(model) or amount<=0: return ""
	var at := LeafLitter.crown_point(model,variant,pose,salt)
	at.y = maxf(at.y,session.stream.ground_at(at)+0.055)
	session.fx.add_items(at,{"tree_leaf":amount},impulse,false,{},model)
	var leaf_id := str(session.fx.serial)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([session.world_settings.seed,model,salt])
	var seedlings := 0
	for i in amount:
		if rng.randi_range(0,99) < int(SAPLING_PERCENT[model]): seedlings += 1
	if seedlings>0:
		session.spawn_drop(at,{"sapling_"+model:seedlings},impulse+Vector3(0.23,0.12,-0.17))
	return leaf_id

func _shed_moving(key: String, count: int, salt: int) -> void:
	var row: Dictionary = records[key]
	var cut: Dictionary = row.cut
	if cut.model=="snag": return
	var pose: Transform3D = active[key].get_child(0).global_transform
	litter.shed(cut.model,cut.variant,pose,key.hash()^salt,count,Vector3(cut.direction)*1.25)

func _break_branches(key: String) -> void:
	if session.replica: return
	var row: Dictionary = records[key]
	if row.get("canopy_spent",false): return
	row.canopy_spent = true
	var cut: Dictionary = row.cut
	var pose: Transform3D = active[key].get_child(0).global_transform
	var salt := hash([session.world_settings.seed,key])
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var stems := rng.randi_range(2,4) + int(cut.model=="snag")
	var motion := Vector3(cut.direction)*0.8
	for i in mini(2,stems):
		var at := LeafLitter.crown_point(cut.model,cut.variant,pose,salt+i*59)
		var count := floori(stems*0.5) if i==0 else ceili(stems*0.5)
		var outward := Vector3(rng.randf_range(-0.55,0.55),0.38,rng.randf_range(-0.55,0.55))
		session.spawn_drop(at,{"stick":count},motion + outward)
	if cut.model!="snag":
		var leaves := rng.randi_range(4,7) if cut.model in ["oak","birch"] else rng.randi_range(3,5)
		for i in 2:
			var count := floori(leaves*0.5) if i==0 else ceili(leaves*0.5)
			_drop_leaves(cut.model,cut.variant,pose,salt+103+i*13,count,motion*0.6)

func snapshot() -> Dictionary:
	var result := {}
	for key: String in active:
		var row: Dictionary = records[key].duplicate(true)
		row.elapsed = active[key].elapsed
		result[key] = row
	return result

func mirror(authority: Dictionary) -> void:
	for key: String in finished_mirrors.keys():
		if not authority.has(key): finished_mirrors.erase(key)
	for key: String in active.keys():
		if not authority.has(key): _discard(key)
	for key: String in authority:
		var row: Dictionary = authority[key]
		if not active.has(key):
			if not finished_mirrors.has(key): _spawn(key,row.duplicate(true))
		elif row.elapsed > active[key].elapsed:
			active[key].advance(float(row.elapsed)-active[key].elapsed)

func _targets(pivot: Vector3, reach: float) -> Array:
	var result := []
	if session.player.health>0 and session.player.global_position.distance_squared_to(pivot)<reach*reach:
		_survivor_target(result,session.player,"host")
	if is_instance_valid(session.network) and is_instance_valid(session.network.member) and not session.network.member_dead:
		_survivor_target(result,session.network.member,"guest/"+str(session.network.member_token))
	for actor: WastelandCreature in session.hordes.alive:
		if actor.active and actor.hp>0 and actor.global_position.distance_squared_to(pivot)<reach*reach:
			result.append({"id":actor.spawn_serial,"feet":actor.global_position,"radius":actor.capsule.radius,"height":actor.capsule.height})
	return result

func _survivor_target(list: Array, person: WastelandSurvivor, id: String) -> void:
	list.append({"id":id,"feet":person.global_position,"radius":person.stand_shape.radius,"height":person.stand_shape.height})

func _strike(id: Variant, damage: float, point: Vector3, key: String) -> void:
	if session.replica or records[key].victims.has(id): return
	records[key].victims[id] = true
	if id is int:
		var actor: WastelandCreature = session.hordes.actors_by_serial.get(id)
		if is_instance_valid(actor): actor.take_hit(damage,point,damage>=16.0)
	else:
		var player: WastelandSurvivor = session.player if id=="host" else session.network.member
		if is_instance_valid(player):
			player.damage(damage,"timber",point)

func _brush(point: Vector3, key: String) -> void:
	var model: String = records[key].cut.model
	_shed_moving(key,22,83)
	if model in ["snow_fir","frost_fir","snag"]:
		session.fx.burst(point,Color("#9b8063") if model=="snag" else Color("#bac7bf"),0.57)
	_break_branches(key)
	if not session.replica: session.audio.play_at("tree_rustle",point,0.82)

func _impact(point: Vector3, key: String) -> void:
	_shed_moving(key,16,127)
	_break_branches(key)
	var wet := point.y<=0.14 and session.stream.water_at(point)
	session.fx.burst(point, Color("#88b7bd") if wet else Color("#aa9173"),1.25)
	var distance := session.player.global_position.distance_to(point)
	if distance<12.0: session.player.impact_kick = maxf(session.player.impact_kick,0.09*(1.0-distance/12.0))
	if session.replica: return
	session.hordes.add_noise(point,30.0,false)
	session.audio.play_at("splash" if wet else "tree_land",point,clampf(float(records[key].radius)*3.8,0.65,1.3))
	var row: Dictionary = records[key]
	var bearing: Dictionary = row.plan.get("support",{})
	var target: StaticBody3D
	if bearing.has("block"):
		target = session.construction.nodes.get(bearing.block)
	elif bearing.has("cell"):
		var chunk: WastelandChunk = session.stream.active.get(bearing.cell)
		if is_instance_valid(chunk):
			var walls: Array = chunk.structures.get(bearing.id,[])
			if not walls.is_empty(): target = walls[0]
	if is_instance_valid(target):
		var speed: float = active[key].impact_speed()
		session.hit_wall(target,clampf(speed*(2.0+4.0*float(row.radius)),0.0,68.0),point,-Vector3(row.cut.direction))

func _settle(_point: Vector3, key: String) -> void:
	if session.replica:
		finished_mirrors[key] = true
	else:
		var tree: Node3D = active[key]
		var row: Dictionary = records[key]
		_break_branches(key)
		var loot: Dictionary = row.loot.duplicate()
		var wood := int(loot.get("wood",0))
		loot.erase("wood")
		var a: Vector3 = tree.point_along(0.0)
		var end: Vector3 = tree.point_along(0.76)
		# The heel slips off the hinge when the fibres tear. Leave the broken
		# crown where it landed and start the first free billet clear of the stump.
		a = a.move_toward(end,minf(float(row.radius)*1.8+0.09,a.distance_to(end)*0.16))
		var span := a.distance_to(end)
		var count := mini(wood,clampi(roundi(span / 1.65),2,5))
		var axis := a.direction_to(end)
		for i in count:
			var fraction := (i+0.5)/count
			var p := a.lerp(end,fraction)
			var radius := float(row.radius)*lerpf(1.0,0.42,fraction)
			p.y = maxf(p.y,session.stream.ground_at(p)+radius+0.025)
			var section := {"model":row.cut.model,"variant":row.cut.variant,"axis":axis,
				"length":span/count*0.97,"radius":radius}
			var pieces := floori(float(wood)/count)+int(i<wood%count)
			session.fx.add_items(p,{"wood":pieces},axis.slide(Vector3.UP)*0.42+Vector3.UP*0.18,false,section)
		if not loot.is_empty(): session.drop_materials(tree.point_along(0.8),loot)
	_discard(key)

func _discard(key: String) -> void:
	active[key].queue_free()
	active.erase(key)
	records.erase(key)
