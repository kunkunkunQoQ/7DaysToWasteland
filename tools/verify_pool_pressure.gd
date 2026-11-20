extends "res://tools/verify_frontier_economy.gd"

const ROUNDS := 3
var initial_drops: Array
var ids := {}
var weak_nodes: Array[WeakRef] = []
var base: Vector3

func remember(label: String,nodes: Array) -> void:
	ids[label]=nodes.map(func(node):return node.get_instance_id())
	for node: Node in nodes: weak_nodes.append(weakref(node))

func same(label: String,nodes: Array) -> bool:
	return ids[label]==nodes.map(func(node):return node.get_instance_id())

func shot_nodes() -> Array:
	return s.fx.shots.map(func(row):return row.node)

func run() -> void:
	var orphans_before:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	cfg=WastelandSave.default_world()
	cfg.seed=2817
	cfg.start_id="grassland"
	enter()
	await s.stream.quiesce()
	s.clock.hours=6*24+22.2
	base=s.player.global_position+Vector3.BACK*12+Vector3.UP*2
	initial_drops=s.fx.drop_records.keys()
	remember("actors",s.hordes.pool)
	remember("shots",shot_nodes())
	remember("particles",s.fx.particles)
	remember("drops",s.fx.drops)
	remember("debris",s.fx.debris)
	for round_id in ROUNDS:
		await exercise_actors(round_id)
		await exercise_effects(round_id)
		exercise_drops()
		check(same("actors",s.hordes.pool) and same("shots",shot_nodes()) and same("particles",s.fx.particles) and same("drops",s.fx.drops) and same("debris",s.fx.debris),"round %d recycles the original node identities across all fixed pools"%[round_id+1])
	check(s.hordes.event_kills==s.hordes.CAP*ROUNDS,"blood moon credits exactly one kill for each lethal hit across all cycles")
	await leave()
	await process_frame
	await process_frame
	var retained:=weak_nodes.filter(func(ref):return is_instance_valid(ref.get_ref())).size()
	var orphans_after:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(retained==0 and orphans_after<=orphans_before,"session unload releases all %d pool nodes; orphan count %d → %d"%[weak_nodes.size(),orphans_before,orphans_after])
	print("POOL PRESSURE checks=%d failures=%d rounds=%d"%[checks,failures,ROUNDS])
	quit(int(failures>0))

func exercise_actors(round_id: int) -> void:
	var director:=s.hordes
	var previous:={"limb_index":0,"wardrobe_index":0,"look_index":0,"face_variant":0}
	var complete:=true
	for i in director.CAP:
		var p:=base+Vector3(i%6*1.5,0,floori(i/6.0)*1.5)
		complete=director._spawn("bulwark",p,true,previous) and complete
	for i in director.WILDLIFE_CAP:
		complete=director._spawn("hare",base+Vector3(i,-1,10),false,previous) and complete
	check(complete and director.alive.size()==director.pool.size() and director.actors_by_serial.size()==director.pool.size() and not director._spawn("walker",base,true) and not director._spawn("hare",base,false),"round %d fills separate infected/wildlife capacities and rejects overflow"%[round_id+1])
	var emitter: WastelandCreature=director.alive[0]
	var saved_serial:=emitter.spawn_serial
	s.fx.projectile(base+Vector3.UP*120,Vector3.UP*4,emitter,"acid",9.0)
	var shot: Dictionary=s.fx.shots[s.fx.shot_cursor]
	var fresh:=director.alive.all(func(a):return a.hp==a.max_health() and a.limp_left==0 and a.brain.rage_left==0 and a.brain.slot_target==null)
	var idempotent:=true
	for actor in director.alive.duplicate():
		actor.take_hit(10000,base+Vector3.LEFT*5,true)
		var paid_serial:=s.fx.serial
		var paid_score:=director.event_kills
		director.defeated(actor)
		idempotent=idempotent and paid_serial==s.fx.serial and paid_score==director.event_kills
	check(fresh and idempotent and director.wildlife_count==0 and director.alive.size()==director.CAP,"fresh actor state, one death payout, wildlife released while infected corpses remain")
	for actor in director.alive.duplicate(): actor.think(3.1,s.player)
	check(director.alive.is_empty() and director.actors_by_serial.is_empty() and director.pool.all(func(a):return not a.active and not a.visible and a.collision_layer==0 and a.brain.seen==null),"corpse hold expires and every active actor index is emptied")
	director._spawn("bulwark",base,false,previous)
	var replacement: WastelandCreature=director.alive.front()
	s.fx.simulate_projectiles(0.05)
	check(replacement==emitter and replacement.spawn_serial!=saved_serial and shot.owner==null and shot.shooter==saved_serial,"an old acid flight does not bind to a recycled shooter's new identity")
	director.release(replacement)
	await process_frame

func exercise_effects(round_id: int) -> void:
	var fx:=s.fx
	var highest:=base+Vector3.UP*150
	for i in fx.PROJECTILES+9:
		fx.projectile(highest,Vector3.UP*3,s.player,"acid" if i%3==0 else "arrow",4+i)
	var transient:=StaticBody3D.new()
	s.add_child(transient)
	fx.projectile(highest,Vector3.UP,transient,"arrow",2)
	var last:Dictionary=fx.shots[fx.shot_cursor]
	transient.queue_free()
	await process_frame
	await process_frame
	fx.simulate_projectiles(0.05)
	check(last.owner==null and fx.shots.size()==fx.PROJECTILES and fx.shots.all(func(row):return row.life>0 and row.node.visible),"48 live shot bodies survive saturation and discard an unloaded owner")
	for i in fx.ACID_POOLS+5:
		fx.infected_effect("residue",highest+Vector3(i,0,0))
	if round_id==0: remember("acid films",fx.pools.map(func(row):return row.node))
	check(fx.acid_snapshot().size()==fx.ACID_POOLS and same("acid films",fx.pools.map(func(row):return row.node)),"simultaneous acid residues stay inside twelve reusable meshes")
	for i in fx.DEBRIS+3: fx.collapse(highest+Vector3(i,0,0),Color.SADDLE_BROWN)
	var tone:=Color("#dd8c65")
	for i in fx.PARTICLES+5: fx.burst(highest+Vector3(i,1,0),tone,1.5)
	check(fx.particles.all(func(p):return p.visible and p.emitting and p.process_material.color.is_equal_approx(tone)),"all particle emitters take the current burst's material after wraparound")
	s.clock.advance(5)
	fx.simulate(5)
	check(fx.shots.all(func(row):return row.life<=0 and row.owner==null and row.shooter==0 and row.id==0 and row.kind=="" and row.hit==0 and not row.node.visible) and fx.acid_flights().is_empty(),"expired shots clear damage, identities, owners and visible geometry")
	check(fx.acid_snapshot().is_empty() and fx.pools.all(func(row):return not row.node.visible) and fx.particles.all(func(p):return not p.visible and not p.emitting) and fx.debris.all(func(body):return body.freeze and not body.visible),"no old particle emission, acid pulse or debris survives retirement")

func exercise_drops() -> void:
	var fx:=s.fx
	for i in fx.DROPS+5: fx.add_items(base+Vector3((i%12)*0.2,0,0),{"stone":1},Vector3.ZERO)
	fx._resync_drops()
	check(fx.drop_live.size()==fx.DROPS and fx.drop_records.size()>fx.DROPS and fx.drops.all(func(body):return body.visible and fx.drop_live.get(body.get_meta("drop_id"))==body),"overflow keeps logical loot while the 56 physical pickups remain bijective")
	var before:=s.bag.count("stone")
	var expected:=0
	var paid:=true
	for key: String in fx.drop_records.keys():
		if key in initial_drops: continue
		expected+=int(fx.drop_records[key].items.get("stone",0))
		paid=fx.take_drop(key)>0 and fx.take_drop(key)==0 and paid
	fx._resync_drops()
	check(paid and s.bag.count("stone")-before==expected and fx.drop_records.size()==initial_drops.size(),"collecting each death drop twice transfers exactly its real stock once")
	check(fx.drops.all(func(body):return body.visible or (body.collision_layer==0 and not body.has_meta("drop_id") and not body.has_meta("item_types"))),"idle pickup slots retain no live identity, collision or item metadata")
