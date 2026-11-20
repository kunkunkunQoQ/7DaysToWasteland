extends SceneTree

class SessionSettings extends WastelandSettings:
	func save_options() -> void:
		pass # Loopback peers must not overwrite the desktop user's preferences.

var game:Node
var is_host:=false
var port:=17357
var failures:=0
const TEST_GEAR:={"head":"alpine_cap","body":"sun_cape","legs":"quilted_pants","hands":"work_gloves","feet":"trail_boots","eyes":"meme_shades","muzzle":"meme_whiskers","back":"meme_tail"}

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var flags:=OS.get_cmdline_user_args()
	is_host="--host" in flags
	for argument in flags:
		if argument.begins_with("--port="):
			port=argument.get_slice("=",1).to_int()
	WastelandSave.root_override="user://verification/party-%d" % OS.get_process_id()
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.options = SessionSettings.new()
	game.options.load_options()
	game.network.local_token = Crypto.new().generate_random_bytes(16).hex_encode()
	game.set_process_input(false)
	Engine.max_fps=120
	if is_host:
		_host()
	else:
		_client()

func _host() -> void:
	game.set_player_name("渡口的风")
	game.set_appearance("ferryman")
	var coastal:Dictionary=game._default_config()
	coastal.terrain_revision=2 # Historic Gray Bay boat and water fixtures.
	game._enter_world(coastal,{},1,false)
	var session:WastelandSession=game.session
	session.hordes.next_patrol=1000.0
	session.hordes.next_herd=1000.0
	session.bag.add("cloth",9)
	session.bag.add("frame",2)
	# Automatic shortcuts now assign new items; reserve slot 0 for the bare-hand test.
	session.bag.assign("cloth",5)
	session.bag.assign("frame",6)
	var animal_at := session.player.global_position + Vector3(-4, 0, -8)
	animal_at.y = session.stream.ground_at(animal_at) + 0.15
	session.hordes._spawn("fox", animal_at, false, {"morph":"local"})
	# Exceed one actor page throughout the initial handshake.
	for index in WastelandLan.ACTORS_PER_PAGE:
		var field := session.player.global_position + Vector3(12+index,0,-15)
		field.y=session.stream.ground_at(field)+0.15
		session.hordes._spawn("hare",field,false,{})
	_check(game.network.listen(port)==OK,"loopback host opens")
	if not await _until(func(): return not game.network.joined_members().is_empty() and is_instance_valid(game.network.joined_members()[0].avatar),10.0):
		_check(false,"guest handshake")
		_done()
		return
	_check(true,"guest handshake")
	var guest_bag:WastelandBag=game.network.joined_members()[0].bag
	_check(guest_bag.counts.is_empty() and session.bag.count("cloth")==9,"new guest starts with an empty private bag")
	var initial:Vector3=game.network.joined_members()[0].survivor.global_position
	_check(_overhead(game.network.joined_members()[0].avatar,"鹿溪","surveyor"),"joining guest displays its nickname alongside the character name")
	_check(await _until(func(): return game.network.joined_members()[0].avatar.outfit == "surveyor", 4.0), "host sees guest's chosen surveyor outfit")
	_check(game.options.appearance == "ferryman", "guest joins without replacing host's appearance")
	_check(session.player.max_health() == 105.0 and game.network.joined_members()[0].survivor.max_health() == 90.0 and game.network.joined_members()[0].survivor.max_stamina() == 120.0, "host simulates distinct character capacities")
	var guest_avatar: WastelandPartyAvatar = game.network.joined_members()[0].avatar
	_check(await _until(func(): return guest_avatar.action_kind=="punch" and guest_avatar.get_meta("swings",0)==1,4.0), "host sees one guest punch on the third-person avatar")
	_check(game.network.joined_members()[0].survivor.hand.model_id=="" and game.network.joined_members()[0].survivor.hand.swing_serial==1, "guest punched with a genuinely empty hand")
	session.bag.add("stone_axe",1)
	session.bag.assign("stone_axe",2)
	session.bag.active=2
	_check(await _until(func(): return session.player.hand.model_id=="stone_axe",3.0), "host selects its owned axe before swinging")
	Input.action_press("fire")
	_check(await _until(func(): return session.player.hand.swing_serial==1,2.0),"host attack input swings the selected axe")
	Input.action_release("fire")
	_check(await _until(func(): return game.network.joined_members()[0].survivor.crouch > 0.7, 4.0), "host receives crouch from the shorter surveyor")
	session.bag.active=0
	session.bag.assign("",2)
	session.bag.spend({"stone_axe":1})
	_check(await _until(func(): return initial.distance_to(game.network.joined_members()[0].survivor.global_position)>0.65,8.0),"guest input moves server's character")
	session.bag.add("coat", 1)
	session.bag.armor = "coat"
	guest_bag.add("cloth",2)
	guest_bag.assign("cloth",5)
	session.player.health = session.player.max_health() * 0.6
	game.set_player_name("临时")
	game.set_player_name("北堤")
	game.set_appearance("mechanic")
	_check(session.bag.armor == "coat" and is_equal_approx(session.player.health, 69.0) and session.player.max_health() == 115.0, "changing host character preserves equipment and health fraction")
	_check(await _until(func(): return game.network.joined_members()[0].avatar.outfit == "ranger", 5.0), "guest's live wardrobe change reaches host")
	_check(game.options.appearance == "mechanic", "host and guest retain independent choices")
	_check(await _until(func(): return _overhead(game.network.joined_members()[0].avatar,"秋叶","ranger"),4.0),"host sees final guest rename and new character in the same tag")
	_check(game.options.player_name=="北堤","guest name does not overwrite the host nickname")
	_check(game.network.joined_members()[0].survivor.max_health() == 100.0 and game.network.joined_members()[0].survivor.max_stamina() == 110.0, "host applies new capacities only to the switching guest")
	_check(game.network.joined_members()[0].avatar.equipped == "" and session.bag.armor=="coat", "changing the guest outfit preserves the host's own coat")
	_check(await _until(func(): return guest_bag.count("bandage")==2,9.0) and guest_bag.count("cloth")==0 and session.bag.count("cloth")==9 and session.bag.count("bandage")==0,"guest crafting spends and produces items in the guest bag")
	var here:=session.player.global_position
	for offset in [Vector2i(2,3),Vector2i(-3,2),Vector2i(2,-4),Vector2i(-5,-1),Vector2i(4,2)]:
		var point:=Vector3(here.x+offset.x,0,here.z+offset.y)
		var cell:=Vector3i(floori(point.x),ceili(session.stream.ground_at(point)-0.42),floori(point.z))
		if session.construction.place(cell,"frame",0,0,here):
			_check(true,"host places replicated frame")
			break
	session.player.toggle_lamp()
	_check(not session.player.headlamp.visible, "host needs a personal lantern to turn on the lamp")
	session.bag.active=7
	session.bag.add("torch",1)
	guest_bag.add("torch",1)
	guest_bag.assign("torch",4)
	session.player.toggle_lamp()
	_check(await _until(func(): return game.network.joined_members()[0].survivor.headlamp.visible, 6.0), "guest can light a carried lamp on the host")
	session.discard("torch")
	_check(await _until(func(): return not session.player.headlamp.visible and game.network.joined_members()[0].survivor.headlamp.visible, 2.0) and guest_bag.count("torch")==1, "discarding the host's lamp leaves the guest's lamp lit")
	_check(await _until(func(): return session.marker_records.size()>0,8.0),"guest map marker mutates shared world")
	var member: WastelandSurvivor = game.network.joined_members()[0].survivor
	var order := session.daily_orders()[0]
	for id in order.inputs:
		guest_bag.add(id, int(order.inputs[id]) * 2)
	var lodge := Vector3(WastelandSite.BOARD_POSITION.x, 0, WastelandSite.BOARD_POSITION.y)
	lodge.y = session.stream.ground_at(lodge) + 0.18
	member.global_position = lodge
	member.velocity = Vector3.ZERO
	_check(await _until(func(): return session.progress.delivery_day == session.clock.day(), 6.0), "guest delivery settles with host")
	_check(session.progress.records.get("delivery", 0) == 1 and guest_bag.count("berries") == int(order.inputs.berries) and session.bag.count("berries")==0, "two requests debit only the delivering guest once")
	member.invulnerable = 0.0
	var before := member.health
	member.damage(18.0, "heavy", member.global_position + member.global_basis.x * 4.0)
	_check(is_equal_approx(member.health, before - 18.0) and session.player.injury.last_source == "",
		"host applies the hit only to the damaged guest")
	var launch := member.global_position + Vector3(0, 3.0, -3.0)
	session.fx.projectile(launch,Vector3.FORWARD*4.0+Vector3.UP*1.4,null,"acid",1.0)
	await create_timer(0.8).timeout
	var water := _deep_water(session)
	_check(water.is_finite(), "loaded water deep enough for the guest")
	if water.is_finite():
		member.global_position = water
		member.velocity = Vector3.ZERO
		member.breath = 8.0
		_check(await _until(func(): return member.submerged, 3.0), "host simulates guest submersion")
		await create_timer(0.7).timeout
		session.player_died(member)
		_check(await _until(func(): return not game.network.joined_members()[0].downed, 6.0), "guest revive processed")
		_check(member.breath == member.max_breath() and not member.wet_feet, "revive restores guest air")
		_check(game.network.joined_members()[0].avatar.outfit == "ranger", "revived guest keeps selected character")
		await create_timer(0.5).timeout
		var boat: WastelandVehicle = session.vehicles.landing_boat
		member.global_position = boat.global_position + Vector3.RIGHT * 1.9
		member.velocity = Vector3.ZERO
		for material in WastelandSession.BOAT_REPAIR:
			guest_bag.add(material, int(WastelandSession.BOAT_REPAIR[material]) * 2)
		var wood := guest_bag.count("wood")
		_check(await _until(func(): return not boat.record.needs_repair, 7.0), "host accepts guest's delivery of hull repair materials")
		_check(guest_bag.count("wood") == wood - 6 and session.bag.count("wood")==0 and session.progress.records.get("repair_boat") == 1, "concurrent repair requests consume one set of the guest's supplies")
		var buoy: Vector3 = session.fx.drop_records.shore_float.point
		boat.global_position = buoy + Vector3(0, -0.15, 2.8)
		member.health = member.max_health() * 0.47
		member.ride(boat)
		_check(session.save_now(false) == OK and WastelandSave.read(1).guests[game.network.joined_members()[0].token].bag==guest_bag.snapshot(), "host save includes the identified guest's full inventory")
		_check(await _until(func(): return not session.fx.drop_records.has("shore_float"), 8.0), "guest can salvage from the helm on the host")
		_check(member.mount_vehicle == boat and session.progress.records.get("salvage_buoy", 0) == 1, "network salvage leaves the guest aboard and pays once")
		session.add_marker(Vector2.ZERO, "打捞确认")
	_check(await _until(func(): return game.network.joined_members().is_empty(), 7.0), "host detects departing guest")
	_check(await _until(func(): return not game.network.joined_members().is_empty() and game.network.joined_members()[0].appearance == "bronx" and game.network.joined_members()[0].avatar.outfit == "bronx", 8.0), "reconnecting guest advertises the Bronx survivor selected on the title screen")
	_check(_overhead(game.network.joined_members()[0].avatar,"秋叶","bronx") and game.session.guest_states.has(game.network.joined_members()[0].token) and not game.session.guest_states.has("秋叶"),"renamed guest reconnects under the same save token and tag")
	_check(game.network.joined_members()[0].survivor.health / game.network.joined_members()[0].survivor.max_health() < 0.55, "injured guest reconnects with its own saved health")
	_check(await _until(func(): return session.marker_records.any(func(marker): return marker.name == "重连确认"), 4.0), "host receives reconnected guest's acknowledgement")
	game.set_appearance("medic")
	_check(await _until(func(): return game.network.joined_members()[0].survivor.profile == "climber", 4.0), "reconnected guest can switch to climber")
	game.set_player_name("秋叶")
	game.set_appearance("surveyor")
	var saved_ok := session.save_now(false)==OK
	var saved := WastelandSave.read(1)
	_check(saved_ok and game.options.player_name=="秋叶" and _overhead(game.network.joined_members()[0].avatar,"秋叶","climber") and saved.guests.size()==1 and saved.guests.has(game.network.joined_members()[0].token) and saved.player.profile=="surveyor" and saved.guests[game.network.joined_members()[0].token].profile=="climber","matching nicknames save two separate character profiles under the original guest token")
	await _host_fieldwork(session)
	_done()

func _client() -> void:
	game.set_player_name("鹿溪")
	game.set_appearance("surveyor")
	_check(game.network.connect_to("127.0.0.1",port)==OK,"connect to loopback")
	if not await _until(func(): return is_instance_valid(game.session) and game.session.replica,10.0):
		_check(false,"client receives world")
		_done()
		return
	var session:WastelandSession=game.session
	_check(true,"client receives world")
	_verify_actor_pages()
	_check(_overhead(game.network.replica_avatar(1),"渡口的风","ferryman"),"bootstrap displays host nickname and fixed character name")
	_check(game.network.replica_avatar(1).outfit == "ferryman" and game.options.appearance == "surveyor", "guest receives distinct host outfit at bootstrap")
	_check(session.player.health == 90.0 and session.player.max_breath() == 19.0, "new guest starts with full selected vitals")
	_check(session.bag.counts.is_empty(),"new guest receives an empty inventory even with a stocked host")
	_check(await _until(func(): return game.network.smooth_actors.values().any(func(actor): return actor.type == "fox" and actor.morph == "local"), 4.0), "guest sees the host's wildlife identity and local morph")
	var host_avatar: WastelandPartyAvatar = game.network.replica_avatar(1)
	_check(session.bag.current()=="" and session.player.hand.model_id=="" and session.player.hand.swing_serial==0,"guest starts empty-handed before its first punch")
	_check(await _until(func(): return game.network.smooth_actors.size()>WastelandLan.ACTORS_PER_PAGE,3.0),"actual multi-page wildlife group reaches the guest")
	Input.action_press("fire")
	await create_timer(0.10).timeout
	Input.action_release("fire")
	_check(await _until(func(): return session.player.hand.swing_serial==1,3.0),"guest attack input receives its authoritative punch serial")
	_check(await _until(func(): return host_avatar.action_kind=="tool" and host_avatar.get_meta("swings",0)==1,4.0),"guest sees the host's single tool swing")
	var grip: Node3D = host_avatar.grip
	var held := grip.get_node_or_null("HeldItem") as MeshInstance3D
	_check(grip.name=="RightGrip" and grip.get_meta("held","")=="stone_axe" and is_instance_valid(held) and held.visible and held.mesh==WastelandItemArt.mesh("stone_axe",session.catalog.items.stone_axe),"guest sees the selected axe mesh in the host's right grip")
	var settled:=await _until(func():return host_avatar.action_kind=="",3.0)
	await create_timer(0.20).timeout
	_check(settled and host_avatar.action_kind=="" and host_avatar.get_meta("swings",0)==1 and session.player.hand.swing_serial==1,"repeated snapshots finish both swings without replaying either")
	Input.action_press("crouch")
	_check(await _until(func(): return session.player.crouch > 0.9 and session.player.eyes.position.y < 1.07, 3.0), "guest camera follows its authoritative crouched body")
	Input.action_release("crouch")
	var point:=session.player.global_position
	Input.action_press("up")
	await create_timer(0.9).timeout
	Input.action_release("up")
	_check(session.player.global_position.distance_to(point)>0.65,"client mirrors remote movement")
	_check(await _until(func(): return game.network.replica_avatar(1).outfit == "mechanic", 4.0), "guest sees host's live wardrobe change")
	game.set_player_name("暂用名")
	game.set_player_name("秋叶")
	game.set_appearance("ranger")
	_check(await _until(func(): return _overhead(game.network.replica_avatar(1),"北堤","mechanic"),4.0),"guest sees host rename and new character independently")
	_check(game.options.player_name=="秋叶","host rename does not replace guest nickname")
	session.ui_command("craft",["bandage",1,null])
	_check(await _until(func(): return session.bag.count("bandage")>=2,8.0),"craft result replicates to guest")
	_check(await _until(func(): return not session.construction.blocks.is_empty(),6.0),"placed frame replicates to guest")
	_check(await _until(func(): return game.network.replica_lamp(1).visible and session.bag.count("torch") == 1, 4.0), "guest sees light from host's carried lantern")
	Input.action_press("flashlight")
	await create_timer(0.14).timeout
	Input.action_release("flashlight")
	_check(await _until(func(): return not game.network.replica_lamp(1).visible and session.player.headlamp.visible and session.bag.count("torch") == 1, 4.0), "guest keeps a lit lantern after the host discards its own")
	session.ui_command("marker",[Vector2(14,30),"队伍标记"])
	_check(await _until(func(): return session.marker_records.size()>0,5.0),"guest receives shared marker")
	var order := session.daily_orders()[0]
	_check(await _until(func(): return session.bag.count("berries") >= 2*int(order.inputs.berries) and session.player.global_position.x < -15.0, 5.0), "guest sees lodge and its delivery goods")
	session.ui_command("deliver", [order.id])
	session.ui_command("deliver", [order.id])
	_check(await _until(func(): return session.progress.delivery_day == session.clock.day() and session.bag.count("berries") == int(order.inputs.berries), 5.0), "guest receives shared delivery settlement")
	_check(await _until(func(): return session.player.injury.last_source == "heavy" and session.player.health < 90.0, 4.0),
		"guest receives authoritative damage and its feedback")
	var directions := session.player.injury.directions
	_check(not directions.is_empty() and directions[0].bearing.dot(session.player.global_basis.x) > 0.98,
		"guest sees the bearing of the attack")
	_check(await _until(func(): return session.fx.shots.any(func(shot): return shot.kind == "acid" and shot.life > 0.0), 3.0),
		"guest receives an acid projectile visual")
	_check(await _until(func(): return session.player.swimming and session.player.submerged and session.player.wet_feet and session.player.breath < 9.0, 5.0), "guest receives underwater state and remaining air")
	if await _until(func(): return session.death_screen, 4.0):
		session.ui_command("revive")
		_check(await _until(func(): return not session.death_screen and not session.player.swimming and session.player.breath == session.player.max_breath(), 4.0), "guest sees cleared water state after revive")
	else:
		_check(false, "guest receives defeat")
	_check(session.vehicles.has("landing_boat") and session.fx.drop_records.has("shore_float"), "guest sees shared launch and buoy")
	_check(await _until(func(): return session.vehicles.landing_boat.record.needs_repair and session.player.global_position.distance_to(session.vehicles.landing_boat.global_position) < 3.8 and session.bag.has_all(WastelandSession.BOAT_REPAIR), 5.0), "guest sees wreck and its own repair materials")
	game.open_panel("vehicle", "landing_boat")
	var repair_button := _button("修复摩托艇")
	var pack_button := _button("收回为套件")
	_check(await _until(func(): return is_instance_valid(repair_button) and is_instance_valid(pack_button) and repair_button.visible and not repair_button.disabled and not pack_button.visible, 2.0), "wreck maintenance panel offers repair with sufficient supplies")
	if is_instance_valid(repair_button):
		repair_button.pressed.emit()
	session.ui_command("repair_vehicle", ["landing_boat"])
	_check(await _until(func(): return not session.vehicles.landing_boat.record.needs_repair and not session.vehicles.landing_boat.repair_marker.visible, 4.0), "repaired boat state and visuals reach the guest")
	_check(await _until(func(): return is_instance_valid(pack_button) and pack_button.visible and not repair_button.visible, 2.0), "open maintenance panel switches to operational controls after repair")
	game.close_overlay()
	session.player.rotation.y = 0.0
	session.player.pitch = -0.35
	session.player.eyes.rotation.x = session.player.pitch
	_check(await _until(func(): return session.hint.contains("打捞浮标"), 5.0), "guest receives authoritative buoy prompt")
	Input.action_press("use")
	await create_timer(0.15).timeout
	Input.action_release("use")
	_check(await _until(func(): return not session.fx.drop_records.has("shore_float") and session.progress.records.get("salvage_buoy", 0) == 1, 4.0), "recovered cache is removed and recorded on guest")
	_check(await _until(func(): return session.marker_records.any(func(marker): return marker.name == "打捞确认"), 4.0), "host confirms guest stayed aboard before disconnect")
	game.leave_world()
	_check(await _until(func(): return game.session.preview_only and not game.network.active(), 3.0), "guest returns to title with local selection")
	game.set_appearance("bronx")
	await create_timer(0.4).timeout
	_check(game.network.connect_to("127.0.0.1", port) == OK, "guest reconnects to same host")
	_check(await _until(func(): return game.session.replica and is_instance_valid(game.network.replica_avatar(1)), 7.0), "reconnected guest receives a fresh avatar")
	if is_instance_valid(game.network.replica_avatar(1)):
		_check(game.session.bag.count("torch")==1 and game.session.bag.count("bandage")>=2 and game.session.bag.count("coat")==0,"guest reconnects with personal tools and supplies")
		_check(game.network.replica_avatar(1).outfit == "mechanic" and game.options.appearance == "bronx" and game.session.player.profile=="bronx", "reconnect preserves both players' distinct last choices")
		_check(_overhead(game.network.replica_avatar(1),"北堤","mechanic") and game.options.player_name=="秋叶","both nicknames survive reconnect")
		game.session.ui_command("marker",[Vector2(15,31),"重连确认"])
		_check(await _until(func(): return game.network.replica_avatar(1).outfit == "medic", 4.0), "guest sees the medic after reconnect")
		game.set_appearance("climber")
		_check(game.session.player.max_breath() == 21.0 and game.session.player.health < 53.0, "guest changes profile on reconnect without free healing")
		_check(await _until(func(): return game.network.replica_avatar(1).outfit == "surveyor", 4.0), "both peers finish exchanging character updates")
		_check(await _until(func(): return _overhead(game.network.replica_avatar(1),"秋叶","surveyor"),3.0) and game.options.player_name=="秋叶" and game.session.player.profile=="climber","same nickname on both peers keeps their character names distinct")
		await _guest_fieldwork(game.session)
	_done()

func _host_fieldwork(session: WastelandSession) -> void:
	var plant: StaticBody3D
	var best := INF
	for chunk: WastelandChunk in session.stream.active.values():
		for node in chunk.decoration_root.get_children():
			if node.get_meta("resource","")!="herb_patch": continue
			var d:=session.player.global_position.distance_squared_to(node.global_position)
			if d<best:
				best=d
				plant=node
	if not is_instance_valid(plant):
		_check(false,"host locates forest herbs around the spawn")
		return
	var id: String=plant.get_meta("index")
	var cell: Vector2i=plant.get_meta("cell")
	var where:=plant.global_position+Vector3.BACK*1.20
	where.y=session.stream.ground_at(where)+0.12
	game.network.joined_members()[0].survivor.global_position=where
	game.network.joined_members()[0].survivor.velocity=Vector3.ZERO
	var guest_bag:WastelandBag=game.network.joined_members()[0].bag
	for piece:String in TEST_GEAR.values(): guest_bag.add(piece,1)
	guest_bag.add("herbal_tea",1)
	guest_bag.add("trail_ration",1)
	guest_bag.add("field_sickle",1)
	guest_bag.assign("field_sickle",6)
	guest_bag.active=6
	session.add_marker(Vector2(plant.global_position.x,plant.global_position.z),"采药验证"+id)
	_check(await _until(func(): return session.stream.chunk_diff(cell).get("removed",{}).has(id) and guest_bag.count("medicinal_herb")>=4,9.0) and session.bag.count("medicinal_herb")==0,"host credits harvested herbs only to the guest who swung the sickle")
	_check(await _until(func(): return session.marker_records.any(func(row): return row.name=="采药确认"),4.0),"host receives guest confirmation after replicated resource removal")
	_check(await _until(func(): return guest_bag.gear==TEST_GEAR and _gear_visible(game.network.joined_members()[0].avatar) and game.network.joined_members()[0].survivor.hand.gloves_worn,5.0),"host renders the guest's own eight worn slots")
	_check(await _until(func(): return guest_bag.gear.hands=="" and guest_bag.gear.head==TEST_GEAR.head and not game.network.joined_members()[0].survivor.hand.gloves_worn,5.0),"guest removing gloves clears only the guest's hands slot")
	_check(await _until(func():return not game.network.joined_members().is_empty() and game.network.joined_members()[0].survivor.warm_drink_left>115 and game.network.joined_members()[0].survivor.ration_left>85,4.0) and session.player.warm_drink_left==0.0 and session.player.ration_left==0.0,"guest provisions affect only the consuming member on the authority")
	var trunk:StaticBody3D
	for node in session.stream.active[Vector2i(-1,1)].decoration_root.get_children():
		if node.get_meta("resource","") in ["oak","pine"] and node.get_meta("index","")=="4600":
			trunk=node
			break
	if not trunk:
		_check(false,"locate a tree for the remote strike")
		return
	var member:WastelandSurvivor=game.network.joined_members()[0].survivor
	var foot:=trunk.global_position+Vector3.BACK*1.4
	foot.y=session.stream.ground_at(foot)+0.08
	member.global_position=foot
	member.velocity=Vector3.ZERO
	guest_bag.assign("",7)
	guest_bag.active=7
	var tree_cell:Vector2i=trunk.get_meta("cell")
	var tree_key:String=trunk.get_meta("index")
	session.add_marker(Vector2(foot.x,foot.z),"验树")
	_check(await _until(func():return session.stream.chunk_diff(tree_cell).get("resources",{}).has(tree_key),6.0) and session.player.injury.last_source!="bark","guest damages the real trunk without injuring the host")
	_check(await _until(func():return session.marker_records.any(func(row):return row.name=="验树已收"),3.0),"guest received its own bark injury")
	_check(await _until(func():return session.marker_records.any(func(row):return row.name=="丢弃首击"),4.0) and guest_bag.count("alpine_cap")==1,"authority preserves last worn cap after first guest discard")
	session.add_marker(Vector2.ZERO,"允许二击")
	_check(await _until(func():return guest_bag.count("alpine_cap")==0,4.0),"second guest confirmation produces an authoritative drop")
	await _until(func(): return game.network.joined_members().is_empty(),2.0)

func _guest_fieldwork(session: WastelandSession) -> void:
	if not await _until(func(): return session.marker_records.any(func(row): return row.name.begins_with("采药验证")) and session.bag.current()=="field_sickle",5.0):
		_check(false,"guest receives harvest site and equipped sickle")
		return
	var mark: Dictionary=session.marker_records.filter(func(row): return row.name.begins_with("采药验证"))[0]
	var point: Vector2=mark.at
	var id:=str(mark.name).trim_prefix("采药验证")
	var cell:=WastelandTerrainGen.chunk_at(point)
	await _until(func(): return Vector2(session.player.global_position.x,session.player.global_position.z).distance_to(point)<1.7,3.0)
	session.player.rotation.y=0.0
	session.player.pitch=-0.87
	session.player.eyes.rotation.x=session.player.pitch
	_check(await _until(func(): return session.hint.contains("林间药草") and session.hint.contains("专精采集"),3.0),"guest can aim at a natural herb patch with the specialty tool")
	Input.action_press("fire")
	_check(await _until(func(): return session.stream.chunk_diff(cell).get("removed",{}).has(id) and session.bag.count("medicinal_herb")>=4 and session.progress.records.get("gather_herb_patch",0)==1,6.0),"guest receives harvested medicinal herbs and the shared gathering record")
	Input.action_release("fire")
	session.ui_command("marker",[point,"采药确认"])
	for piece:String in TEST_GEAR.values():
		session.ui_command("consume",[piece])
	_check(await _until(func(): return session.bag.gear==TEST_GEAR and game.network.replica_avatar(1).equipped=="coat" and session.player.hand.gloves_worn,5.0),"guest wears its eight pieces and sees the host's separate coat")
	session.ui_command("consume",["work_gloves"])
	_check(await _until(func(): return session.bag.gear.hands=="" and not session.player.hand.gloves_worn and session.bag.gear.feet=="trail_boots" and game.network.replica_avatar(1).accessories.get("feet","")=="",5.0),"removing gloves preserves the guest's boots and the host's bare feet")
	session.ui_command("consume",["herbal_tea"])
	session.ui_command("consume",["trail_ration"])
	_check(await _until(func():return session.player.warm_drink_left>115 and session.player.ration_left>85 and session.bag.count("trail_ration")==0,4.0),"guest sees its own food effects and stack debit")
	_check(await _until(func():return session.marker_records.any(func(row):return row.name=="验树") and session.bag.current()=="",5.0),"guest switches to empty hand by the tree")
	session.player.rotation.y=0.0
	session.player.pitch=0.0
	session.player.eyes.rotation.x=0.0
	_check(await _until(func():return session.hint.contains("徒手砍树"),4.0),"guest sees the bark injury warning on a real tree")
	Input.action_press("fire")
	_check(await _until(func():return session.player.injury.last_source=="bark" and session.player.injury.last_amount==2.0,3.0),"guest punch receives an authoritative two-health bark injury")
	Input.action_release("fire")
	session.ui_command("marker",[point,"验树已收"])
	session.ui_command("discard",["alpine_cap"])
	session.ui_command("marker",[point,"丢弃首击"])
	_check(await _until(func():return session.marker_records.any(func(row):return row.name=="允许二击"),3.0) and session.bag.count("alpine_cap")==1,"guest sees its worn cap protected without local inventory loss")
	session.ui_command("discard",["alpine_cap"])
	_check(await _until(func():return session.bag.count("alpine_cap")==0,3.0),"confirmed discard removes the guest's cap")
	await create_timer(0.4).timeout

func _gear_visible(avatar:WastelandPartyAvatar)->bool:
	return is_instance_valid(avatar) and avatar.equipped==TEST_GEAR.body and avatar.accessories.legs=="quilted_pants" and avatar.leg_rigs[0].has_node("TrouserLeg") and avatar.leg_rigs[1].has_node("TrouserLeg") and avatar.accessories.head==TEST_GEAR.head and avatar.accessories.hands==TEST_GEAR.hands and avatar.accessories.feet==TEST_GEAR.feet and avatar.find_child("meme_shades",true,false)!=null and avatar.find_child("meme_whiskers",true,false)!=null and avatar.find_child("meme_tail",true,false)!=null

func _overhead(avatar: WastelandPartyAvatar, nickname: String, style: String) -> bool:
	if not is_instance_valid(avatar) or avatar.outfit!=style:
		return false
	for tag: Label3D in avatar.find_children("*","Label3D",true,false):
		if tag.text.contains(nickname) and tag.text.contains(str(WastelandPartyAvatar.NAMES[style])):
			return true
	return false

func _verify_actor_pages() -> void:
	var net: WastelandLan = game.network
	var original := net.replica_actors
	var serial := net.applied_actor_frame
	var pending := net.actor_pages
	net.actor_pages={}
	var next := serial+1
	net._actor_page(next,1,2,[[20]])
	net._actor_page(next,1,2,[[20]])
	_check(net.applied_actor_frame==serial and net.replica_actors==original,"partial and duplicate actor pages preserve the visible roster")
	net._actor_page(next+1,0,2,[[30]])
	net._actor_page(next,0,2,[[10]])
	_check(net.replica_actors==[[10],[20]],"out-of-order actor pages publish one complete ordered roster")
	net._actor_page(next+2,0,1,[])
	net._actor_page(next+1,1,2,[[40]])
	_check(net.replica_actors.is_empty() and net.actor_pages.is_empty(),"a delayed page cannot revive actors after a newer complete empty roster")
	net.replica_actors=original
	net.applied_actor_frame=serial
	net.actor_pages=pending

func _button(caption: String) -> Button:
	for item in game.panels.content.find_children("*", "Button", true, false):
		if item.text == caption:
			return item
	return null

func _deep_water(session: WastelandSession) -> Vector3:
	var origin := session.player.global_position
	for distance in range(6, 75, 4):
		for bearing in range(16):
			var angle := bearing * TAU / 16.0
			var point := origin + Vector3(cos(angle), 0, sin(angle)) * distance
			if session.stream.water_at(point) and session.stream.ground_at(point) < -3.3:
				point.y = -3.0
				return point
	return Vector3.INF

func _until(condition:Callable,timeout:float) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000.0)
	while Time.get_ticks_msec()<end:
		if condition.call():
			return true
		await process_frame
	return false

func _check(ok:bool,words:String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+words)

func _done() -> void:
	print("PARTY %s failures=%d" % ["host" if is_host else "guest",failures])
	game.network.stop()
	if is_instance_valid(game.session):
		game.session.simulation_paused=true
		await game.session.stream.quiesce()
		if is_instance_valid(game.session.audio):
			await game.session.audio.finish_playback()
	quit(0 if failures==0 else 1)
