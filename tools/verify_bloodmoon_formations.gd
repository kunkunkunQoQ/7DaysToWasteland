extends "res://tools/verify_frontier_economy.gd"

var notices: Array[String] = []
var start_types := {}

func prepare() -> void:
	s.message.connect(func(words: String,_duration: float): notices.append(words))
	s.hordes.next_herd = INF
	s.hordes.next_patrol = INF
	s.hordes.next_heat = INF
	var base := s.player.global_position
	for x in range(-2,3):
		for z in range(-2,3):
			s.stream.ensure_landing(base+Vector3(x*32,0,z*32))

func clear_actors() -> void:
	for mob in s.hordes.alive.duplicate(): s.hordes.release(mob)

func spawn_announced() -> Array:
	s.clock.elapsed = s.hordes.next_wave
	s.hordes.simulate(0.51)
	var result: Array = []
	for actor in s.hordes.alive:
		if actor.wave: result.append([actor.type,actor.morph,actor.global_position])
	return result

func run() -> void:
	WastelandSave.root_override="user://verification/formations-%d" % OS.get_process_id()
	cfg=WastelandSave.default_world()
	cfg.start_id="grassland"
	cfg.seed=2817
	enter()
	prepare()
	check(s.hordes.formation(7,1).is_empty(),"first blood moon uses the original graded wave")
	var first: Dictionary = s.hordes.formation(14,1)
	s.world_settings.seed=2818
	check(s.hordes.formation(14,1)!=first,"seed changes the first forecast")
	s.world_settings.seed=2817
	s.clock.period=3
	check(s.hordes.formation(3,1).is_empty() and s.hordes.formation(6,1)==first,"cadence follows custom blood-moon period")
	s.clock.period=7
	for night in [14,21,28]:
		s.clock.hours=(night-1)*24.0+22.05
		notices.clear()
		s.hordes.simulate(0.51)
		var night_types:={}
		for wave in range(1,4):
			clear_actors()
			if wave>1:
				s.clock.elapsed=s.hordes.next_wave-5.5
				s.hordes.simulate(0.51)
			var group:=s.hordes.formation(night,wave)
			var signalled:=s.hordes.approach_announced and notices.any(func(words: String):return words.contains(group.name) and words.contains(group.tip))
			check(signalled and s.hordes.next_wave>s.clock.elapsed,"night %d wave %d gives advance group warning and counter" % [night,wave])
			if wave==1: start_types[group.name]=true
			night_types[group.name]=true
			var saved: Dictionary={}
			if night==21 and wave==2:
				check(s.save_now(false)==OK,"save live approach between warning and arrival")
				saved=WastelandSave.read(1)
			var actors:=spawn_announced()
			if not saved.is_empty():
				await leave()
				enter(saved)
				prepare()
				check(s.hordes.event_day==night and s.hordes.wave_index==wave-1 and s.hordes.approach_announced and s.hordes.formation(night,wave)==group,"old-format threat fields preserve announced wave after reload")
				check(spawn_announced()==actors,"restored wave has identical species, morphs and actual positions")
			var counts:={}
			for actor: Array in actors: counts[actor[0]]=int(counts.get(actor[0],0))+1
			check(s.hordes.wave_index==wave and counts.has(group.pair[0]) and counts.has(group.pair[1]) and counts.has("walker"),"spawned announced pair with ordinary walkers: "+str(counts))
			check(actors.size()<=14 and s.hordes.alive.size()<=s.hordes.CAP,"existing per-wave and global caps respected")
			if actors.size()>1:
				if group.get("flank",false):
					var left: Vector3 = actors[0][2]-s.player.global_position
					var right: Vector3 = actors[1][2]-s.player.global_position
					check(angle_difference(s.hordes.approach_angle,atan2(left.z,left.x))<0 and angle_difference(s.hordes.approach_angle,atan2(right.z,right.x))>0,"flank pair approaches opposite sides of announced bearing")
				else:
					check(actors[0][2].distance_to(actors[1][2])<7.0,"support joins its lead within aid range")
			notices.clear()
		check(night_types.size()==3,"three wave compositions during night %d" % night)
		clear_actors()
		s.clock.hours=night*24.0+4.05
		s.hordes.simulate(0.51)
	check(start_types.size()==3,"nights 14, 21 and 28 open with three different formations")
	clear_actors()
	for i in s.hordes.CAP:
		s.hordes._spawn("walker",s.player.position+Vector3(i,0,12),false)
	var previous:=s.hordes.wave_index
	s.hordes._wave()
	check(s.hordes.wave_index==previous and s.hordes.alive.size()==s.hordes.CAP,"full actor pool defers a themed wave")
	await leave()
	print("BLOODMOON FORMATIONS QA checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
