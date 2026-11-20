extends "res://tools/verify_frontier_economy.gd"

const Caves := preload("res://game/world/nest_caves.gd")

func clear_pool() -> void:
	for actor in s.hordes.alive.duplicate(): s.hordes.release(actor)

func stop_patrols() -> void:
	s.hordes.next_herd = INF
	s.hordes.next_patrol = INF

func run() -> void:
	WastelandSave.root_override="user://verification/director-%d"%OS.get_process_id()
	cfg=WastelandSave.default_world()
	cfg.seed=27491
	cfg.start_id="grassland"
	enter()
	stop_patrols()
	var director := s.hordes
	var origin := s.player.global_position
	for z in range(-2,3):
		for x in range(-2,3): s.stream.ensure_landing(origin+Vector3(32*x,0,32*z))
	await physics_frame
	await physics_frame
	s.clock.hours=144.0+21.49
	s.progress.level=3
	check(director.stage()==12 and s.clock.warning_minutes()==0 and s.clock.blood()==0.0,"stage uses completed days, level and floor")
	s.clock.hours=144.0+21.5
	check(s.clock.warning_minutes()==30 and not s.clock.horde_active(),"30-minute warning starts at 21:30")
	s.clock.hours+=0.25
	check(s.clock.blood()>0.0 and s.clock.blood()<1.0,"red sky, fog and wind share the warning ramp")
	s.clock.hours=166.0
	director.simulate(0.51)
	for index in 3:
		var advance: float=director.next_wave-s.clock.elapsed
		s.clock.advance(advance)
		director.simulate(0.51)
		var wave:=director.alive.filter(func(a): return a.wave)
		check(director.wave_index==index+1 and director.wave_total==3 and not wave.is_empty(),"event actually dispatches wave %d"%[index+1])
		check(wave.all(func(a): return a.global_position.distance_to(origin)>=28.0 and a.global_position.distance_to(origin)<=55.0 and not s.stream.water_at(a.global_position) and not s.stream.below_terrain(a.global_position)),"wave actors on surface within the legal ring")
		if index<2:
			check(director.next_wave-director.assault_until>=15.0 and director.next_wave-director.assault_until<=25.0,"15–25-second intermission")
			clear_pool()
			s.clock.advance(director.assault_until-s.clock.elapsed+0.1)
			director.simulate(0.51)
			check(not director.alive.any(func(a):return a.wave),"no reinforcements during intermission")
	s.clock.hours=172.0
	director.simulate(0.51)
	check(director.alive.all(func(a): return not a.wave) and director.alive.any(func(a): return a.brain.retreat_left>0.0),"04:00 releases targeting and starts dispersal")
	clear_pool()
	s.progress.level=30
	var spot:=Vector3(origin.x, s.stream.ground_at(origin), origin.z)
	var cell:=WastelandTerrainGen.chunk_at(Vector2(spot.x,spot.z))
	var key:=WastelandTerrainGen.grid_key(cell)
	director.add_heat(spot,95.0)
	s.clock.advance(60.0)
	director._scan_heat()
	check(float(director.heat[key].amount)==89.0,"heat decays in real one-minute increments")
	director.add_heat(spot,11.0)
	var scouts:=director.alive.filter(func(a): return a.type=="screamer")
	check(float(director.heat[key].amount)==0.0 and scouts.size()==1,"threshold resets immediately and sends one screamer")
	if not scouts.is_empty():
		var at: Vector3=scouts[0].global_position
		var local:=Vector2(at.x,at.z)-Vector2(cell*32)
		check(minf(minf(local.x,local.y),minf(32-local.x,32-local.y))<=2.01 and scouts[0].brain.interest==spot,"screamer travels from chunk perimeter to the source")
		director.call_pack(at,spot)
		var number:=director.alive.size()-1
		check(number>=4 and number<=8 and director.alive.filter(func(a): return a.type=="screamer").size()==1,"4–8 safe non-recursive reinforcements")
		director.call_pack(at,spot)
		check(director.alive.size()==number+1,"scream cooldown")
	clear_pool()
	var cave_cell:=find_cave()
	check(cave_cell!=Vector2i.MAX,"seed generates an accessible rock cave")
	if cave_cell!=Vector2i.MAX:
		var center:=Vector2(cave_cell*32)+Vector2(16,16)
		s.stream.ensure_landing(Vector3(center.x,0,center.y))
		await physics_frame
		await physics_frame
		var chunk:WastelandChunk=s.stream.active[cave_cell]
		var inner:=chunk.position+chunk.sleeper_anchors[0]
		check(s.stream.in_nest_cave(inner) and not director.spawn_ground.surface(s,inner).is_finite(),"covered cave is cold and excluded from open-sky spawning")
		check(chunk.structures.has("cave/boards") and chunk.supply_caches.has(chunk.object_key("nest/cache")),"breakable boards, interior cache and sleeper volume")
		s.player.global_position=chunk.position+chunk.cave_origin+Vector3.BACK*8
		director._activate_nests(s.player.global_position)
		director._activate_nests(s.player.global_position)
		check(director.alive.any(func(a):return a.brain.state==WastelandCreatureBrain.State.SLEEPING and a.nest!=""),"actual streamed nest spawns sleeping infected")
		var before:=director.alive.size()
		director._activate_nests(s.player.global_position)
		check(director.alive.size()==before,"occupied slots do not duplicate")
		s.hit_wall(chunk.structures["cave/boards"][0],2000)
		check(not chunk.structures.has("cave/boards"),"entrance can be breached")
		director.add_heat(s.player.global_position,17)
		check(s.save_now(false)==OK,"director and cave persist to disk")
		var saved:=WastelandSave.read(1)
		var stage_before:=director.stage()
		await leave()
		enter(saved)
		stop_patrols()
		s.stream.ensure_landing(inner)
		await physics_frame
		await physics_frame
		s.hordes.simulate(0.51)
		var restored:WastelandChunk=s.stream.active[cave_cell]
		check(s.hordes.stage()==stage_before and float(s.hordes.heat[WastelandTerrainGen.grid_key(cave_cell)].amount)==17.0 and not restored.structures.has("cave/boards"),"restores stage, heat and broken entrance")
		check(s.hordes.alive.filter(func(a):return a.nest!="").size()==before,"restores same nest occupants exactly once")
	await leave()
	print("HORDE NEST QA checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func find_cave() -> Vector2i:
	var probe:=WastelandChunk.new()
	probe.stream=s.stream
	for z in range(-9,10):
		for x in range(-9,10):
			probe.cell=Vector2i(x,z)
			probe.position=Vector3(x*32,0,z*32)
			probe.site=s.stream.generator.site_for(probe.cell)
			if Caves.location(probe).is_finite():
				probe.free()
				return Vector2i(x,z)
	probe.free()
	return Vector2i.MAX
