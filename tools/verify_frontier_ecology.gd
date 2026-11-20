extends "res://tools/verify_harvest.gd"

func habitat(id:String)->Vector3:
	var gen:=session.stream.generator
	var region:String=session.catalog.enemies[id].ecology.region
	for x in range(1,13):
		for z in range(-2,3):
			var d:=gen.frontier._district(Vector2i(x,z))
			if gen.region_kind(d.x,d.z)!=region: continue
			for dx in range(-88,89,5):
				for dz in range(-82,83,5):
					var at:=Vector3(d.x+dx,0,d.z+dz)
					at.y=gen.ground(at.x,at.z)
					if at.y<0.6 or gen.site_for(gen.chunk_at(Vector2(at.x,at.z)))!="": continue
					if gen.region_kind(at.x,at.z)!=region: continue
					if id in session.hordes.WILDLIFE and id not in session.hordes._candidates_at(at): continue
					if id=="mudwalker" and at.y>3.0: continue
					return at
	return Vector3.INF

func run()->void:
	WastelandSave.root_override="user://verification/trail-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.seed=2817
	open_world({})
	var records:=preload("res://game/ui/atlas_records.gd").rows("creatures",session.catalog)
	for id in ["argali","jerboa","otter","mudwalker","sandrunner","rimecaller","bulwark"]:
		if id in ["rimecaller","bulwark"]: session.progress.level = 12
		session.clock.hours=21 if id=="jerboa" else 9
		var at:=habitat(id)
		check(at.is_finite(),"real seeded habitat for "+id)
		if not at.is_finite(): continue
		session.stream.ensure_landing(at)
		await physics_frame
		check(records.filter(func(row):return row.species==id).size()==3,"atlas has all three variants "+id)
		var spawned:=false
		for attempt in 24:
			if id in session.hordes.WILDLIFE:
				session.hordes._new_herd(at,8)
			else: session.hordes._try_near(at,"walker",1.5,7.0,false)
			for actor:WastelandCreature in session.hordes.alive.duplicate():
				if actor.type==id:
					spawned=true
				else: session.hordes.release(actor)
			if spawned: break
		check(spawned,"regional spawn table produces "+id)
		if not spawned: session.hordes._spawn(id,at+Vector3.UP*0.1,false,{})
		var a:WastelandCreature=session.hordes.alive.back()
		a.global_position=at+Vector3.UP*0.06
		await physics_frame
		if id in session.hordes.WILDLIFE:
			var sight:=a.global_position+Vector3.UP*a.capsule.height*0.52
			session.player.global_position=at+Vector3.BACK*1.7
			session.player.camera.global_position=sight+Vector3.BACK*1.1
			session.player.camera.look_at(sight)
			session._use()
			check(session.progress.records.has("observe_"+id),"actual use observes live "+id)
			session.player.global_position=at+Vector3(33,0,33)
			a.brain.home=at
			a.brain.goal=a.global_position
			a.brain.seen=null
			a.brain.memory=0
			a.brain._survey(session.player,[])
			var forage:=session.hordes.trail_snapshot(at)
			check(a.brain.forage_left>0 and not forage.is_empty() and forage.back().activity=="停步觅食","animal stops to feed and scuffs terrain "+id)
			a.brain.provoke(at-Vector3.RIGHT*5)
			a.brain._escape()
			a.print_distance=1.0
			a.print_position=a.global_position-Vector3.RIGHT*0.24
			a._wildlife_track(6.0)
			var prints:=session.hordes.trail_snapshot(at)
			var pool:=session.hordes.get_node_or_null("Hoofprints")
			if not prints.is_empty() and pool:
				var latest:Dictionary=prints.back()
				var clue:Dictionary=pool.clue(latest.at)
				check(a.brain.mode==WastelandCreatureBrain.Mode.FLEE and latest.species==id and latest.activity=="受惊疾行" and clue.label.contains("受惊"),"fresh frightened trail points after animal "+id)
				var departure:=a.global_position
				var initial_stamp:=int(latest.key)
				session.player.global_position=departure-Vector3.RIGHT*3.5
				for step in 180:
					a.think(1.0/60.0,session.player)
					if step%12==0: await physics_frame
					if a.global_position.distance_to(departure)>2.4: break
				var live_path:=session.hordes.trail_snapshot(departure)
				check(a.global_position.distance_to(departure)>0.85 and live_path.any(func(row):return int(row.key)>initial_stamp and row.activity=="受惊疾行"),"moving animal extends the frightened trail during live AI simulation "+id)
				a.global_position+=Vector3.RIGHT*3.5
				session.player.global_position=latest.at+Vector3.BACK*0.82
				session.player.camera.global_position=latest.at+Vector3.UP*1.6
				session.player.camera.look_at(latest.at+Vector3.FORWARD*0.02)
				await physics_frame
				session._use()
				var fieldnotes:=preload("res://game/sim/nature_journal.gd").lines(session,id)
				check(fieldnotes.size()>=2 and session.progress.records.get("track_"+id,0)>0,"actual interaction records species, direction, region and observation in journal "+id)
				var replica:=WastelandHoofprints.new()
				root.add_child(replica)
				replica.mirror(prints)
				replica.mirror(prints)
				check(replica.nearby(at).size()==prints.size() and replica.clue(latest.at).get("species")==id,"nearby replica mirrors trail only once "+id)
				replica._process(50)
				check(replica.clue(latest.at).is_empty(),"old tracks expire "+id)
				replica.free()
			else: check(false,"terrain tracks available "+id)
		else:
			session.player.global_position=at+Vector3.FORWARD*1.1
			a.rotation.y=0.0
			a.brain.seen=session.player
			a.brain.cooldown=0.0
			a.brain._chase(session.player)
			check(a.brain._prepare_attack() and a.brain.action_span>=0.4,"attack has visible warning interval "+id)
			session.hordes.defeated(a)
			check(session.progress.records.has("kill_"+id),"infected encounter enters field guide "+id)
		for actor:WastelandCreature in session.hordes.alive.duplicate(): session.hordes.release(actor)
	check(session.save_now(false)==OK,"save observations")
	var saved:=WastelandSave.read(1)
	await close_world()
	open_world(saved)
	check(session.progress.records.has("observe_argali") and session.progress.records.has("observe_jerboa") and session.progress.records.has("observe_otter"),"observations persist after disk reload")
	await close_world()
	print("FRONTIER ECOLOGY QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)
