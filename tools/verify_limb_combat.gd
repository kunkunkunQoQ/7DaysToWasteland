extends "res://tools/verify_combat.gd"

func _run() -> void:
	WastelandSave.root_override="user://verification/limb-combat-%d" % OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	app._enter_world(app._default_config(),{},0,false)
	session=app.session
	player=session.player
	await _ticks(28)
	session.simulation_paused=true
	_make_arena()
	await _ticks(3)
	await _attack_choices()
	await _special_organs()
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	print("LIMB COMBAT: ",passes," passed, ",failures.size()," failed")
	for issue in failures:
		printerr("FAILED: ",issue)
	quit(0 if failures.is_empty() else 1)

func _injured(id: String, limb: int, distance: float) -> WastelandCreature:
	return _spawn(id,player.global_position+Vector3.FORWARD*distance,player.global_position,
		{"limb_index":limb,"wardrobe_index":0,"morph":"","look_index":0})

func _attack_choices() -> void:
	_reset_player()
	player.global_position=anchor+Vector3(0,0.04,6.0)
	for limb: int in [0,9,18,72,80]:
		var runner := _injured("sandrunner",limb,4.1)
		await _ticks(6,[runner])
		check((runner.brain.action==BRAIN.Action.CHARGE)==(limb==0),"rush depends on two usable feet (%d)" % limb)
		if limb>=72:
			var before := runner.global_position
			await _ticks(60,[runner])
			check(runner.low_crawl() and runner.global_position.distance_to(before)>0.16 and runner.body_height()<runner.spec.height*0.65,
				"low crawler advances along the ground (%d)" % limb)
		session.hordes.release(runner)
	var worker := _injured("brute",6,1.32)
	await _ticks(65,[worker])
	check(not worker.biting() and player.injury.last_source=="heavy" and player.health<100,
		"worker strikes with the remaining left hand and hammer")
	session.hordes.release(worker)
	_reset_player()
	var biter := _injured("brute",80,0.83)
	await _ticks(65,[biter])
	check(biter.biting() and player.injury.last_source=="claw" and player.health<100 and player.fracture==0,
		"four injured limbs still permit a close bite without hammer fracture")
	check(biter.brain.reach<1.0 and biter.wall_factor()==0,"a bite has a short reach and cannot breach a wall")
	_reset_player()
	var floor_screen := _box(Vector3(0,0.54,5.57),Vector3(1.8,1.08,0.11),2)
	await _ticks(3)
	check(not biter.brain._within_melee(player,Vector3.BACK,biter.brain.reach),"solid low cover interrupts a bite on the impact frame")
	floor_screen.queue_free()
	session.hordes.release(biter)
	await _ticks(2)

func _special_organs() -> void:
	_reset_player()
	player.global_position=anchor+Vector3(0,0.04,9.0)
	var spitter := _injured("spitter",80,7.25)
	await _ticks(17,[spitter],true)
	check(spitter.brain.action==BRAIN.Action.SPIT and spitter.brain._eyes().y-spitter.global_position.y<0.85,
		"prone spitter commits an acid shot from its lowered head")
	await _ticks(78,[spitter],true)
	check(player.injury.last_source=="acid" and player.health<100,"acid projectile from the ground reaches its target")
	session.hordes.release(spitter)
	_reset_player()
	var guard := _injured("bulwark",72,6.0)
	guard.hp*=0.5
	var before := guard.hp
	var medic := _injured("rimecaller",80,7.1)
	await _ticks(92,[medic])
	check(guard.hp>before,"a caller with damaged arms still heals using its crystals")
	session.hordes.release(guard)
	session.hordes.release(medic)
	var bloater := _injured("bloater",80,1.85)
	bloater.take_hit(999,player.global_position)
	await _ticks(115,[bloater])
	check(bloater.brain.state==BRAIN.State.DEAD and player.injury.last_source=="rupture","prone bloater retains its fuse and damages nearby survivors")
	bloater.think(WastelandCreature.CORPSE_SECONDS+0.1,player)
	check(not bloater.active,"the ruptured crawler returns to the pool after its death pose")
