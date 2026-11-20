extends SceneTree

var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ",title)
	if not ok: failures+=1

func run() -> void:
	WastelandSave.root_override="user://verification/trophies-%d"%OS.get_process_id()
	var world:=WastelandSession.new()
	root.add_child(world)
	var cfg:=WastelandSave.default_world()
	cfg.seed=2817
	world.configure(cfg,{},1,WastelandCatalog.new(),WastelandSettings.new())
	world.simulation_paused=true
	var director:=world.hordes
	var probe:=RandomNumberGenerator.new()
	probe.seed=0x7423
	var winners:={}
	var losing:=probe.state
	# Find deterministic states for each of the two pool indices without simulating kills.
	for i in 500000:
		var state_before:=probe.state
		var ticket:=probe.randi_range(1,director.RARE_ODDS)
		if ticket==1:
			winners[probe.randi_range(0,1)]=state_before
		else: losing=state_before
		if winners.size()==2:break
	check(director.RARE_ODDS==50000 and winners.size()==2,"one winning ticket in 50,000; both pool selections reproducible")
	var seen:={}
	var awards:=0
	var at:=world.start_position()+Vector3.RIGHT*2
	for species:String in director.TROPHIES:
		for i in 2:
			var id:String=director.TROPHIES[species][i]
			if seen.has(id): continue
			director._spawn(species,at,false,{"morph":""})
			var actor:WastelandCreature=director.alive[-1]
			director.trophy_rng.state=winners[i]
			var before:=world.fx.serial
			actor.take_hit(9999,at)
			awards+=1
			var actual:Dictionary=world.fx.drop_records.get(str(world.fx.serial),{}).get("items",{})
			check(not actor.active and world.fx.serial>before and actual.has(id) and world.catalog.items.has(id),"real lethal hit yields collectible "+id)
			world.fx.take_drop(str(world.fx.serial))
			check(world.bag.count(id)==1,"world drop can be picked up: "+id)
			var after:=director.trophy_rng.state
			director.defeated(actor)
			check(director.trophy_rng.state==after and int(world.progress.records.get("rare_drop",0))==awards,"duplicate defeat consumes no roll or award")
			seen[id]=true
	director._spawn("fox",at,false)
	director.trophy_rng.state=losing
	director.alive[-1].take_hit(9999,at)
	check(world.progress.records.get("rare_drop")==awards and seen.size()==12,"losing ticket preserves ordinary drops and all twelve unique prizes are reachable")
	var clock_prize:=false
	for attempt in 1500000:
		var before:=probe.state
		if probe.randi_range(1,director.RARE_ODDS)==1 and probe.randi_range(0,2)==2:
			director._spawn("fox",at,false,{"morph":"local"})
			director.trophy_rng.state=before
			director.alive[-1].take_hit(9999,at)
			world.fx.take_drop(str(world.fx.serial))
			clock_prize=world.bag.count("meme_clock")==1
			break
	check(clock_prize,"local fox can drop the extra clock accessory through its variant-specific pool")
	check(world.save_now(false)==OK,"store dropped trophies and the independent roll sequence")
	var saved:=WastelandSave.read(1)
	var next:=director.trophy_rng.randi()
	await world.stream.quiesce()
	await world.audio.finish_playback()
	world.queue_free()
	await process_frame
	world=WastelandSession.new()
	root.add_child(world)
	world.configure(cfg,saved,1,WastelandCatalog.new(),WastelandSettings.new())
	world.simulation_paused=true
	check(world.hordes.trophy_rng.randi()==next and world.progress.records.get("rare_drop")==13 and world.bag.count("meme_shades")==1,"reload preserves the next roll, earned trophies and achievement count")
	await world.stream.quiesce()
	await world.audio.finish_playback()
	world.queue_free()
	await process_frame
	print("RARE DROP QA failures=",failures)
	quit(1 if failures else 0)
