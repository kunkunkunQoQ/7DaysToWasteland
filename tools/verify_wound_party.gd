extends "res://tools/verify_party.gd"

func _host() -> void:
	var config: Dictionary = game._default_config()
	config.start_id = "seeded"
	game._enter_world(config,{},1,false)
	var world: WastelandSession = game.session
	world.hordes.next_patrol = INF
	world.hordes.next_herd = INF
	world.bag.add("splint",1)
	_check(game.network.listen(port) == OK, "medical host opens")
	if not await _until(func(): return not game.network.joined_members().is_empty(),12):
		_check(false,"guest joined")
		_done()
		return
	var state:WastelandLan.MemberState=game.network.joined_members()[0]
	var member: WastelandSurvivor = state.survivor
	for item: String in ["splint","honey","bandage"]: state.bag.add(item,1)
	var owner_hp := world.player.health
	member.infection = 18
	member.bleed = 12
	member.sprain = 60
	member.hunger = 15
	member.hydration = 14
	member.wet = 0.8
	member.stamina = member.max_stamina() * 0.5
	_check(await _until(func(): return member.sprain == 0 and member.bleed == 0 and member.infection < 10.0 and state.bag.counts.is_empty(),12) and world.bag.count("splint")==1, "guest treatment uses the guest's medical supplies while the host keeps its splint")
	_check(world.player.health == owner_hp and world.player.sprain == 0.0 and world.player.infection == 0.0, "remote wound treatment leaves host physiology independent")
	_check(world.save_now(false) == OK, "host saves both players after treatment")
	var saved := WastelandSave.read(1)
	var guest_data: Dictionary = saved.guests.values()[0]
	_check(guest_data.get("sprain",-1)==0 and guest_data.get("wet",0.0)>0.0 and guest_data.hunger < 24.0, "guest snapshot persists moisture, injuries and nutrition in the world slot")
	await create_timer(0.8).timeout
	_done()

func _client() -> void:
	_check(game.network.connect_to("127.0.0.1",port) == OK,"medical guest connects")
	if not await _until(func(): return is_instance_valid(game.session) and game.session.replica,12):
		_check(false,"guest receives world")
		_done()
		return
	var world: WastelandSession = game.session
	var p := world.player
	var base := float(WastelandSurvivor.Profiles.STATS[p.profile].stamina)
	_check(await _until(func(): return p.sprain > 0 and p.wet > 0.3 and p.infection > 17 and p.bleed > 0 and p.max_stamina() < base * 0.72,5), "guest receives hunger-dependent cap and current injuries over ENet")
	for item: String in ["splint","bandage","honey"]: world.ui_command("consume",[item])
	_check(await _until(func(): return p.sprain == 0.0 and p.bleed == 0.0 and p.infection < 10.0 and world.bag.count("honey") == 0,5),"guest sees the treated leg, sealed wound, suppressed infection and inventory debit")
	await create_timer(0.25).timeout
	_done()
