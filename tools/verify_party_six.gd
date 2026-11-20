extends SceneTree

# Start one --host and five --guest=N processes with the same --run and --port.
# All use real ENet, real world sessions and isolated save/option locations.
const PROFILES := ["ferryman","surveyor","mechanic","medic","climber"]
const HANDS := ["torch","torch","improvised_shield","improvised_shield","field_glasses"]
const WAIT_MS := 90000
var app: Node
var failures := 0
var checks := 0
var port := 18666
var guest := 0
var run_id := ""
var expected_version := ""
var ticket := ""

func _initialize() -> void:
	run.call_deferred()

func check(value:bool, label:String)->bool:
	checks+=1
	if not value: failures+=1
	print("PASS " if value else "FAIL ",label)
	return value

func until(condition:Callable,timeout:=WAIT_MS)->bool:
	var deadline:=Time.get_ticks_msec()+timeout
	while Time.get_ticks_msec()<deadline:
		if condition.call(): return true
		await process_frame
	return false

func mark(stage:String)->void:
	var file:=FileAccess.open(ticket+"-"+stage,FileAccess.WRITE)
	file.store_line(stage)
	file.close()

func marked(stage:String)->bool:
	return FileAccess.file_exists(ticket+"-"+stage)

func all_marked(stage:String)->bool:
	for i in range(1,6):
		if not marked(stage+str(i)): return false
	return true

func identity(index:int)->String:
	return (run_id+"/guest/"+str(index)).md5_text()

func state(index:int)->WastelandLan.MemberState:
	return app.network.member_with_token(identity(index))

func name_for(index:int)->String:
	return "Team%d"%index

func host()->void:
	app.set_player_name("Owner")
	app.set_appearance("ranger")
	var settings:Dictionary=app._default_config()
	settings.terrain_revision=2
	settings.name="Six "+run_id
	app._enter_world(settings,{},1,false)
	var s:WastelandSession=app.session
	s.hordes.next_herd=100000.0
	s.hordes.next_patrol=100000.0
	s.bag.add("torch",3)
	s.bag.add("improvised_shield",2)
	s.bag.add("field_glasses",1)
	s.bag.set_offhand("torch")
	s.bag.active=7
	if not check(app.network.listen(port)==OK,"host listens with five guest slots"): return
	mark("ready")
	if not check(await until(func():return app.network.joined_members().size()==5),"five distinct identified guests join the same room"): return
	check(app.network.player_count()==6 and s.living_players().size()==6,"room and authoritative survivor count include owner")
	var unique:Dictionary={}
	for i in range(1,6):
		var person:=state(i)
		if check(person!=null and person.survivor.profile==PROFILES[i-1] and person.avatar.player_name==name_for(i),"guest %d has its own survivor, outfit and nickname"%i):
			unique[person.peer_id]=true
	check(unique.size()==5,"each guest has a unique ENet peer ID")
	mark("full")
	# The discovery service and a real sixth client must both respect the cap.
	var browser:=WastelandLan.DISCOVERY.new()
	var advertised:=await until(func():
		browser.browse(app.network._local_address)
		return browser.rooms.values().any(func(room):return room.port==port and room.name==settings.name and room.players==6),15000)
	check(advertised,"LAN discovery advertises 6/6")
	browser.close()
	var extra:=ENetMultiplayerPeer.new()
	var result:=extra.create_client("127.0.0.1",port,3)
	var rejected:=result!=OK
	if result==OK:
		await until(func():
			extra.poll()
			return extra.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTING,12000)
		rejected=extra.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED
		extra.close()
	check(rejected and app.network.player_count()==6,"seventh participant cannot enter a full room")
	if not check(await until(func():
		if s.marker_records.size()!=5: return false
		for i in range(1,6):
			var person:=state(i)
			if person==null or person.slot!=i-1 or person.offhand!=HANDS[i-1] or person.input.is_empty(): return false
			if absf(float(person.input.get("yaw",0.0))-float(i)*0.4)>0.05: return false
			if bool(int(person.input.get("held",0)) & app.network._bit("crouch"))!=(i%2==0): return false
		return true),"five independent input streams, slots, offhands and commands"): return
	check(s.bag.active==7 and s.bag.offhand=="torch" and s.bag.partner_offhands.count("torch")==2 and s.bag.partner_offhands.count("improvised_shield")==2 and s.bag.partner_offhands.count("field_glasses")==1,"host keeps slot and own offhand; all five reservations coexist")
	s.bag.set_offhand("improvised_shield")
	check(s.bag.offhand=="torch" and s.bag.available_count("improvised_shield")==0,"host cannot take either of two reserved shields")
	mark("locked")
	if not check(await until(func():return all_marked("locked")),"all clients receive full roster, private state and shared markers"): return
	check(state(1).offhand=="torch" and state(5).offhand=="field_glasses","failed competing offhand request cannot steal last item")
	mark("rename")
	if not check(await until(func():return state(3).nickname=="Renamed" and state(3).appearance=="bronx" and all_marked("rename")),"live guest nickname and outfit relay to every other peer"): return
	# Deliberately damage a different guest while guest 2 owns the simulation
	# context. The victim, the interrupted guest and the owner must not mix.
	var victim:=state(4)
	var interrupted:=state(2)
	victim.survivor.invulnerable=0.0
	var before:=victim.survivor.health
	var other_before:=interrupted.survivor.health
	var owner_before:=s.player.health
	app.network._as_member(s,interrupted,func():
		victim.survivor.damage(18.0,"fall")
		check(s.player==interrupted.survivor and s.actor_peer_id==interrupted.peer_id and s.bag.offhand==interrupted.offhand,"nested damage restores interrupted guest context"))
	check(is_equal_approx(victim.survivor.health,before-18.0) and is_equal_approx(interrupted.survivor.health,other_before) and is_equal_approx(s.player.health,owner_before) and s.actor_peer_id==1 and s.bag.offhand=="torch","damage is attributed only to actual victim and host context is restored")
	mark("hurt")
	if not check(await until(func():return all_marked("hurt")),"only the victim receives damage"): return
	victim.survivor.damage(1000.0,"fall")
	check(victim.downed and s.living_players().size()==5 and not state(5).downed,"downing one guest preserves all other players")
	mark("down")
	if not check(await until(func():return all_marked("down")),"only victim enters defeat; peers see its avatar hidden"): return
	mark("revive")
	if not check(await until(func():return not victim.downed and victim.survivor.health>0 and all_marked("revive")),"victim revives without disrupting any other peer"): return
	# Host streaming and regional interest include a guest near (but inside)
	# the original 84 m tether rather than only the first guest.
	var last:=state(5)
	var old_at:=last.survivor.global_position
	var far:=s.player.global_position+Vector3.RIGHT*75.0
	far.y=s.stream.ground_at(far)+0.2
	last.survivor.global_position=far
	s.stream.refresh(s.player.global_position,2,s.guest_positions())
	var far_cell:=WastelandTerrainGen.chunk_at(Vector2(far.x,far.z))
	check(s.team_distance_squared(far)<0.01 and s.stream.guest_centers.has(far_cell) and s.stream.discovered.has(WastelandTerrainGen.grid_key(far_cell)),"guest 5 extends authority interest, streaming and exploration")
	last.survivor.global_position=far+Vector3.UP*12.0
	var target_point:=last.survivor.global_position+Vector3.UP*last.survivor.stand_shape.height*0.5
	last.survivor.invulnerable=0.0
	var last_health:=last.survivor.health
	var first_health:=state(1).survivor.health
	s.hordes.damage_near(target_point+Vector3.UP*0.1,2.0,8.0,"heavy")
	check(last.survivor.health<last_health-5.0 and is_equal_approx(state(1).survivor.health,first_health),"area damage finds the fifth guest and not a distant teammate")
	if check(s.hordes._spawn("walker",last.survivor.global_position+Vector3.BACK*1.4,false,{}),"spawn AI test actor near guest 5"):
		var actor:WastelandCreature=s.hordes.alive.back()
		actor.rotation.y=0.0
		var teammates:=s.living_players()
		teammates.erase(s.player)
		actor.brain._survey(s.player,teammates)
		check(actor.brain.seen==last.survivor,"AI chooses the actual visible fifth guest")
		s.hordes.release(actor)
	last.survivor.global_position=old_at
	var tree_targets:=s.timber._targets(s.player.global_position,100.0)
	for i in range(1,6):
		check(tree_targets.any(func(row):return row.id=="guest/"+identity(i)),"falling-tree contacts include guest %d independently"%i)
	# Clear any ordinary spawn pressure and open a real shared loot container.
	s.stream.ensure_landing(Vector3(-16,3,48))
	var chunk:WastelandChunk=s.stream.active[WastelandSite.SHORE_CELL]
	var key:String=chunk.supply_caches.keys()[0]
	var model:Node3D=chunk.supply_caches[key]
	var body:StaticBody3D=model.get_parent()
	var diff:=s.stream.edit_chunk(chunk.cell)
	if not diff.has("containers"): diff.containers={}
	diff.containers[key]={"items":{"wood":3},"next":3,"earned":false}
	var initial_wood:=s.bag.count("wood")
	var at:=body.global_position+Vector3.BACK
	s.player.global_position=at
	s.player.velocity=Vector3.ZERO
	s._open_loot(body)
	for i in range(1,6):
		var person:=state(i)
		person.survivor.global_position=at+Vector3.RIGHT*0.15*i
		person.survivor.velocity=Vector3.ZERO
		app.network._as_member(s,person,func():s._open_loot(body))
	check(s.cache_inventory.actors.size()==6 and s.chest_lids()==[key],"six independent chest viewers share one open lid")
	mark("chest")
	if not check(await until(func():return all_marked("chest")),"all guests receive their own chest panels"): return
	mark("take")
	if not check(await until(func():return all_marked("take") and s.bag.count("wood")==initial_wood+3),"five concurrent requests on a three-unit stack transfer exactly three units"): return
	check(s.chest_view(key).items.is_empty(),"shared stack is empty, not duplicated")
	# Only guest 5 leaves while the other five viewers remain.
	last.survivor.health=last.survivor.max_health()*0.55
	var old_peer:=last.peer_id
	mark("leave")
	if not check(await until(func():return state(5)==null and all_marked("leave")),"one guest departs while four others remain connected"): return
	check(app.network.player_count()==5 and not s.cache_inventory.actors.has(old_peer) and s.cache_inventory.actors.size()==5 and model.opened,"departing guest clears only its own chest viewer")
	check(s.bag.partner_offhands.size()==4 and s.bag.available_count("field_glasses")==1,"departing guest releases only its offhand")
	check(s.save_now(false)==OK,"authority saves with one guest offline")
	var save:=WastelandSave.read(1)
	check(save.guests.size()==5 and save.guests[identity(5)].slot==4 and save.guests[identity(5)].offhand=="field_glasses","all five identities persist separately including the departed player")
	mark("rejoin")
	if not check(await until(func():return state(5)!=null and all_marked("rejoin")),"departed person rejoins and all other clients see the roster recover"): return
	var returning:=state(5)
	check(returning.peer_id!=old_peer and returning.slot==4 and returning.offhand=="field_glasses" and absf(returning.survivor.health/returning.survivor.max_health()-0.55)<0.06,"reconnect restores that guest's own health, slot and offhand")
	check(app.network.player_count()==6 and s.bag.partner_offhands.size()==5,"reused slot returns room to 6/6")
	mark("finish")
	check(await until(func():return all_marked("finish")),"all five clients finish while the room is still open")

func roster_ok(count:int,all_visible:=false)->bool:
	if app.network.replicas.size()!=count: return false
	for peer in app.network.replicas:
		var view:WastelandLan.ReplicaMember=app.network.replicas[peer]
		if view.motion.is_empty() or (all_visible and not view.avatar.visible): return false
	return true

func avatar_named(value:String)->WastelandPartyAvatar:
	for view:WastelandLan.ReplicaMember in app.network.replicas.values():
		if view.avatar.player_name==value: return view.avatar
	return null

func client()->void:
	app.set_player_name(name_for(guest))
	app.set_appearance(PROFILES[guest-1])
	app.network.local_token=identity(guest)
	if not check(await until(func():return marked("ready")),"host ready"): return
	if not check(app.network.connect_to("127.0.0.1",port)==OK,"guest connects to real ENet host"): return
	if not check(await until(func():return app.session.replica and marked("full") and roster_ok(5,true)),"guest receives five distinct replicated players"): return
	var s:WastelandSession=app.session
	check(app.network.replica_avatar(1).player_name=="Owner" and app.network.replica_avatar(1).outfit=="ranger","guest sees owner's nickname and outfit")
	for i in range(1,6):
		if i==guest: continue
		var other:=avatar_named(name_for(i))
		check(is_instance_valid(other) and other.outfit==PROFILES[i-1] and other.visible,"guest sees peer %d's own appearance and pose"%i)
	s.player.rotation.y=float(guest)*0.4
	if guest%2==0: Input.action_press("crouch")
	s.ui_command("slot",[guest-1])
	s.ui_command("offhand",[HANDS[guest-1]])
	s.ui_command("marker",[Vector2(guest*3,guest*2),"six-%d"%guest])
	if not check(await until(func():return marked("locked") and s.bag.active==guest-1 and s.bag.offhand==HANDS[guest-1] and s.bag.partner_offhands.size()==5 and s.marker_records.size()==5),"private slot and offhand alongside five shared updates"): return
	if guest==1:
		s.ui_command("offhand",["field_glasses"])
		await create_timer(1.0).timeout
		check(s.bag.offhand=="torch","guest cannot take another guest's last reserved item")
	mark("locked"+str(guest))
	if not await until(func():return marked("rename")): check(false,"rename phase"); return
	if guest==3:
		app.set_player_name("Renamed")
		app.set_appearance("bronx")
	else:
		check(await until(func():
			var other:=avatar_named("Renamed")
			return is_instance_valid(other) and other.outfit=="bronx"),"another guest's nickname and outfit update")
	mark("rename"+str(guest))
	var before:=s.player.health
	if not await until(func():return marked("hurt")): check(false,"damage phase"); return
	if guest==4:
		check(await until(func():return s.player.health<before-12.0),"recipient sees its authoritative injury")
	else:
		check(absf(s.player.health-before)<2.0 and not s.death_screen,"uninjured guest retains its own vitals")
	mark("hurt"+str(guest))
	if not await until(func():return marked("down")): check(false,"down phase"); return
	if guest==4:
		check(await until(func():return s.death_screen),"only downed guest sees defeat")
	else:
		check(await until(func():
			var other:=avatar_named(name_for(4))
			return not s.death_screen and is_instance_valid(other) and not other.visible),"other guest sees victim hidden, not local defeat")
	mark("down"+str(guest))
	if not await until(func():return marked("revive")): check(false,"revive phase"); return
	if guest==4: s.ui_command("revive",[])
	check(await until(func():return not s.death_screen and (guest!=4 or s.player.health>1.0) and (guest==4 or avatar_named(name_for(4)).visible)),"victim returns without other guests being reset")
	mark("revive"+str(guest))
	Input.action_release("crouch")
	if not check(await until(func():return marked("chest") and app.panels.visible and app.panels.active=="chest" and s.replica_chest.get("items",{}).get("wood",0)==3),"guest opens own shared storage panel"): return
	mark("chest"+str(guest))
	if not await until(func():return marked("take")): check(false,"take phase"); return
	s.ui_command("chest_take",[s.replica_chest.key,"wood",1])
	check(await until(func():return s.replica_chest.get("items",{}).is_empty() and not s.replica_chest.is_empty()),"guest sees exact final shared chest contents")
	mark("take"+str(guest))
	if not await until(func():return marked("leave")): check(false,"leave phase"); return
	if guest==5:
		app.leave_world()
		check(await until(func():return app.session.preview_only and not app.network.active()),"guest leaves room")
	else:
		check(await until(func():return roster_ok(4) and app.panels.visible and app.panels.active=="chest"),"remaining guest keeps chest and sees smaller roster")
	mark("leave"+str(guest))
	if not await until(func():return marked("rejoin")): check(false,"rejoin phase"); return
	if guest==5:
		check(app.network.connect_to("127.0.0.1",port)==OK,"same identity reconnects")
		check(await until(func():return app.session.replica and roster_ok(5) and app.session.bag.active==4 and app.session.bag.offhand=="field_glasses" and app.session.player.health/app.session.player.max_health()<0.65),"reconnected guest receives restored private state")
	else:
		check(await until(func():return roster_ok(5) and is_instance_valid(avatar_named(name_for(5)))),"rejoined teammate appears again")
	mark("rejoin"+str(guest))
	check(await until(func():return marked("finish")),"host completes checks")
	mark("finish"+str(guest))
	# Let the host observe every final acknowledgement before anyone leaves.
	await create_timer(2.0).timeout

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="): port=argument.get_slice("=",1).to_int()
		if argument.begins_with("--guest="): guest=argument.get_slice("=",1).to_int()
		if argument.begins_with("--run="): run_id=argument.get_slice("=",1).validate_filename()
		if argument.begins_with("--expect-version="): expected_version=argument.get_slice("=",1)
	if run_id.is_empty() or guest<0 or guest>5:
		printerr("Provide --run=ID --port=N and --guest=1..5 for guests")
		quit(2)
		return
	ticket=OS.get_temp_dir().path_join("7dw-six-"+run_id)
	if not expected_version.is_empty():
		check(str(ProjectSettings.get_setting("application/config/version"))==expected_version,"running expected game build "+expected_version)
	WastelandSave.root_override="user://verification/six-%s-%d"%[run_id,guest]
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	Engine.max_fps=40
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	app.options.display.radius=2
	app.set_process_input(false)
	if guest==0: await host()
	else: await client()
	print("SIX role=%d checks=%d failures=%d"%[guest,checks,failures])
	app.network.stop()
	if is_instance_valid(app.session):
		app.session.simulation_paused=true
		await app.session.stream.quiesce()
		if is_instance_valid(app.session.audio): await app.session.audio.finish_playback()
	app.free()
	quit(0 if failures==0 else 1)
