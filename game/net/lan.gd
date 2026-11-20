class_name WastelandLan
extends Node

const DEFAULT_PORT := 7357
var discovery := preload("res://game/net/lan_discovery.gd").new()
const ID_PATH := "user://coop_identity.cfg"
const MAX_PACKET := 3 * 1024 * 1024
const EFFECTS := ["step_soil","step_grass","step_leaves","step_wood","step_stone","chop","stone","hit","place","search","bow","shot","boom","growl","scream","alarm","splash","thunder","reload",
	"attack_tell","spit_tell","scream_tell","hammer","collapse","tree_split","tree_rustle","tree_land"]
const KEYS := ["jump","sprint","crouch","use","fire","alternate","reload","shape","rotate","flashlight","discard","slot_next","slot_prev",
	"slot_1","slot_2","slot_3","slot_4","slot_5","slot_6","slot_7","slot_8","offhand_use","swap_hands"]
static var key_mask := (1 << KEYS.size()) - 1
const DEVICE_COMMANDS := ["craft","cancel","collect","fuel","rest","enable","feed_fire","smelt_input"]
static var ACTIONS := DEVICE_COMMANDS + ["slot","assign","assign_slot","quick_equip","offhand","swap_hands","consume","discard","learn","job","barter","deliver","dispatch","patrol_start","patrol_claim","rebuild_board","recover_archive","marker","unmark","vehicle","repair_vehicle","revive","chest_take","chest_put","chest_all","chest_close"]
const CONTEXT := ["interaction","building_hit","next_hint","hint","focus_damage","loot_target","loot_time","loot_full","loot_ratio",
	"search_start","search_slot","search_held","action_lock","reload_id","reload_left","reload_span","heavy_charge","heavy_pending","shape","turn"]

var game: Node
var transport: ENetMultiplayerPeer
var host := false
var remote_id := 0
var port := DEFAULT_PORT
var joining := false
var replica_position := Vector3.ZERO
var replica_state: Dictionary = {}
var remote_input: Dictionary = {}
var remote_pressed := 0
var remote_updated := 0
var member_context: Dictionary = {}
var member_slot := 0
var owner_slot_during_guest_action := 0
var member_offhand := ""
var wire_endpoint: Variant
var member: WastelandSurvivor
var member_avatar: WastelandPartyAvatar
var member_appearance := ""
var member_token := ""
var pending_name := ""
var next_name_send := 0
var next_name_receive := 0
var received_name := ""
var local_token := ""
var member_dead := false
var host_avatar: WastelandPartyAvatar
var host_lamp: SpotLight3D
var smooth_actors: Dictionary = {}
var actors_now: Dictionary = {}
const ACTORS_PER_PAGE := 6
const FRAME_FIELDS := ["time","elapsed","active","hint","loot","target_hp","shape","turn","wave","ride","charge","reload","confirm","noise"]
const PLAYER_FIELDS := ["point","health","profile","limits","crouch","body_height","eye_height","stamina","hunger","hydration","temp","bleed","infection","fracture","lamp","breath","provisions","sprain","wet"]
const MOTION_FIELDS := ["member_swings","member_shots","swing_power","owner_held","owner_swings","owner_shots","owner_swim","owner_mounted","submerged","swimming","wet_feet","owner_at","owner_yaw","owner_speed","owner_duck","owner_lamp","owner_eye","owner_pitch","owner_offhand","owner_guard","owner_flame","member_guard"]
var actor_frame := 0
var applied_actor_frame := -1
var posed_actor_frame := -1
var actor_pages := {}
var replica_actors := []
var fast_timer := 0.0
var slow_timer := 0.0
var manifest_hash := 0
var connected_since := 0
var commands: Array = []
var activity_budget := 0
var budget_tick := 0.0
var shared_clock := 0.0
var last_chest_state := -1

func _ready() -> void:
	multiplayer.peer_connected.connect(_registered)
	multiplayer.peer_disconnected.connect(_departed)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_closed)

func active() -> bool:
	return transport != null and (host or joining or remote_id == 1)

func server() -> bool:
	return active() and host

func listen(target_port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(target_port,1,3)
	if result != OK:
		return result
	host=true
	transport=peer
	port=target_port
	multiplayer.multiplayer_peer=peer
	return OK

func connect_to(address: String, target_port: int) -> Error:
	if not _local_address(address):
		return ERR_INVALID_PARAMETER
	stop()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address,target_port,3)
	if result != OK:
		return result
	joining=true
	connected_since=Time.get_ticks_msec()
	transport=peer
	port=target_port
	multiplayer.multiplayer_peer=peer
	return OK

func _local_address(address: String) -> bool:
	if address=="::1":
		return true
	address=address.trim_prefix("::ffff:")
	if not address.is_valid_ip_address() or address.contains(":"):
		return false
	var parts := address.split(".")
	var a := int(parts[0])
	var b := int(parts[1])
	return a in [10,127] or (a==192 and b==168) or (a==172 and b>=16 and b<=31) or (a==169 and b==254)

func stop() -> void:
	discovery.close()
	if is_instance_valid(member):
		store_guest(member.session)
		member.session.chest_leave(true)
		member.session.bag.partner_offhand=""
	member_offhand=""
	if transport!=null:
		transport.close()
		multiplayer.multiplayer_peer=null
	transport=null
	if is_instance_valid(member):
		if is_instance_valid(member.mount_vehicle):
			member.dismount(true)
		member.queue_free()
	if is_instance_valid(host_avatar):
		host_avatar.queue_free()
	member=null
	member_avatar=null
	member_appearance=""
	member_token=""
	pending_name=""
	next_name_send=0
	next_name_receive=0
	received_name=""
	host_avatar=null
	host_lamp=null
	host=false
	joining=false
	remote_id=0
	remote_pressed=0
	member_context={}
	remote_input={}
	commands.clear()
	smooth_actors.clear()
	actors_now.clear()

func _process(_delta:float) -> void:
	if server() and is_instance_valid(game.session) and not game.session.preview_only:
		discovery.answer(_local_address,game.session.world_settings.name,game.options.player_name,game.session.clock.day(),port,2 if remote_id else 1)
	elif not active() and is_instance_valid(game.front) and game.front.visible and game.front.screen=="lan":
		discovery.browse(_local_address)
	elif discovery.browser != null:
		discovery.close()
	if not pending_name.is_empty() and Time.get_ticks_msec()>=next_name_send and _can_exchange_names():
		_nickname.rpc_id(remote_id,pending_name)
		pending_name=""
		next_name_send=Time.get_ticks_msec()+300
	if not received_name.is_empty() and Time.get_ticks_msec()>=next_name_receive and _can_exchange_names():
		var avatar := member_avatar if host else host_avatar
		avatar.set_player_name(received_name)
		received_name=""
		next_name_receive=Time.get_ticks_msec()+300
	if joining and Time.get_ticks_msec()-connected_since>9000:
		_failed()

func _registered(peer: int) -> void:
	if not server():
		return
	if not is_instance_valid(game.session) or game.session.preview_only or remote_id!=0:
		transport.disconnect_peer(peer)
		return
	var endpoint := transport.get_peer(peer)
	if endpoint==null or not _local_address(endpoint.get_remote_address()):
		transport.disconnect_peer(peer)
		return
	remote_id=peer
	_welcome.rpc_id(peer)

@rpc("authority","call_remote","reliable",0)
func _welcome() -> void:
	if host or not joining or multiplayer.get_remote_sender_id() != 1:
		return
	if local_token.is_empty():
		var identity := ConfigFile.new()
		identity.load(ID_PATH)
		local_token = str(identity.get_value("coop", "identity", ""))
		if local_token.length() != 32 or not local_token.is_valid_hex_number(false):
			local_token = Crypto.new().generate_random_bytes(16).hex_encode()
			identity.set_value("coop","identity",local_token)
			identity.save(ID_PATH)
	_identify.rpc_id(1, local_token, game.options.appearance,game.options.player_name)

@rpc("any_peer","call_remote","reliable",0)
func _identify(token: String, outfit: String, nickname: String) -> void:
	if not server() or remote_id == 0 or multiplayer.get_remote_sender_id() != remote_id or not member_token.is_empty():
		return
	if nickname.length()>12 or token.length() != 32 or not token.is_valid_hex_number(false) or not WastelandPartyAvatar.OUTFITS.has(outfit):
		transport.disconnect_peer(remote_id)
		return
	member_token = token
	member_appearance = outfit
	var session: WastelandSession = game.session
	var previous: Dictionary = session.guest_states.get(token, {})
	member_dead=false
	member_slot=clampi(int(previous.get("slot",0)),0,7)
	member_offhand=str(previous.get("offhand",""))
	_validate_member_slot(session.bag)
	wire_endpoint=null
	remote_updated=0
	manifest_hash=0
	fast_timer=0.0
	slow_timer=0.0
	member=WastelandSurvivor.new()
	session.add_child(member)
	var at:=session.player.global_position+session.player.global_basis.x*1.38
	at.y=maxf(at.y,session.stream.ground_at(at)+0.14)
	member.configure(session,previous,at,false,outfit)
	if member.global_position.distance_squared_to(at) > 80.0 * 80.0:
		member.global_position = at
	member_dead = bool(previous.get("downed", false)) or member.health <= 0.0
	if member_dead:
		member.collision_layer = 0
		member.collision_mask = 0
	member_avatar=WastelandPartyAvatar.new()
	member.add_child(member_avatar)
	member_avatar.apply_outfit(outfit)
	member_avatar.set_player_name(WastelandSettings.clean_player_name(nickname))
	member_avatar.visible = not member_dead
	member_context={}
	for key in CONTEXT:
		member_context[key]=session.get(key)
	member_context.interaction={}
	member_context.building_hit={}
	member_context.loot_target=null
	member_context.loot_ratio=0.0
	member_context.reload_id=""
	member_context.heavy_pending=false
	member_context.heavy_charge=0.0
	member_context.action_lock=0.0
	member_context.hint=""
	session.audio.relay=cue
	var payload: Dictionary={"settings":session.world_settings,"time":session.clock.hours,"elapsed":session.clock.elapsed,
		"player":member.snapshot(),"bag":_guest_bag(session.bag),"progress":session.progress.snapshot(),"acid_pools":session.fx.acid_snapshot(),
		"acid_shots":session.fx.acid_flights(member.global_position),"acid_serial":session.fx.acid_serial,
		"host_name":game.options.player_name,"host_appearance":game.options.appearance, "downed":member_dead}
	_bootstrap.rpc_id(remote_id,payload)
	session.notify("队友已加入世界")

func _validate_member_slot(bag:WastelandBag)->void:
	if not member_offhand.is_empty() and bag.count(member_offhand)<=int(bag.offhand==member_offhand)+int(bag.is_worn(member_offhand)):
		member_offhand=""
	bag.partner_offhand=member_offhand

func _guest_bag(bag:WastelandBag)->Dictionary:
	var saved:=bag.snapshot()
	saved.active=member_slot
	saved.partner_offhand=bag.offhand
	saved.gear.erase("offhand")
	if member_offhand!="": saved.gear.offhand=member_offhand
	return saved

func store_guest(session: WastelandSession) -> void:
	if not host or not is_instance_valid(member) or member.session != session or member_token.is_empty():
		return
	var saved := member.snapshot()
	saved.downed = member_dead
	saved.offhand=member_offhand
	saved.slot=member_slot
	session.guest_states[member_token] = saved

func _departed(peer:int) -> void:
	if not server() or peer!=remote_id:
		return
	if is_instance_valid(member):
		store_guest(member.session)
		member.session.chest_leave(true)
		member.session.bag.partner_offhand=""
	member_offhand=""
	if is_instance_valid(member):
		if is_instance_valid(member.mount_vehicle):
			member.dismount(true)
		member.queue_free()
	member=null
	member_avatar=null
	member_appearance=""
	member_token=""
	pending_name=""
	next_name_send=0
	next_name_receive=0
	received_name=""
	remote_id=0
	remote_input={}
	commands.clear()
	game.session.notify("队友已离开")

func _connected() -> void:
	if not host and transport!=null:
		remote_id=1

func _failed() -> void:
	if not joining and remote_id==0:
		return
	stop()
	game.connection_notice("连接超时或主机不可达")

func _closed() -> void:
	if host or transport==null:
		return
	stop()
	if game.closing:
		return
	game._show_title.call_deferred()
	game.connection_notice.call_deferred("已与主机断开")

@rpc("authority","call_remote","reliable",0)
func _bootstrap(start: Dictionary) -> void:
	if host or not joining or multiplayer.get_remote_sender_id()!=1:
		return
	if not start.get("settings") is Dictionary:
		_failed()
		return
	joining=false
	game._enter_world(start.settings,start,0,false)
	var session: WastelandSession=game.session
	session.replica=true
	preload("res://game/core/atlas_unlocks.gd").remember(WastelandSave.save_root(),session.progress.achieved.keys())
	session.network=self
	session.clock.hours=float(start.time)
	session.clock.elapsed=float(start.elapsed)
	replica_position=session.player.global_position
	replica_state={}
	applied_actor_frame=-1
	posed_actor_frame=-1
	actor_pages.clear()
	replica_actors.clear()
	host_avatar=WastelandPartyAvatar.new()
	session.add_child(host_avatar)
	host_lamp = session.player.headlamp.duplicate() as SpotLight3D
	host_avatar.add_child(host_lamp)
	host_lamp.hide()
	var outfit := str(start.get("host_appearance", "ranger"))
	host_avatar.apply_outfit(outfit if WastelandPartyAvatar.OUTFITS.has(outfit) else "ranger")
	host_avatar.set_player_name(WastelandSettings.clean_player_name(str(start.get("host_name",""))))
	host_avatar.hide()
	fast_timer=0.0
	remote_pressed=0
	appearance_changed(game.options.appearance)
	player_name_changed(game.options.player_name)
	session.notify("已加入 " + str(start.settings.name))
	if start.get("downed", false):
		session.death_screen = true
		game._failure()

func appearance_changed(outfit: String) -> void:
	if active() and remote_id != 0 and not joining and WastelandPartyAvatar.OUTFITS.has(outfit):
		_outfit.rpc_id(remote_id, outfit)

@rpc("any_peer","call_remote","reliable",0)
func _outfit(outfit: String) -> void:
	if not WastelandPartyAvatar.OUTFITS.has(outfit):
		return
	if server():
		if _is_member_sender() and member_appearance != outfit:
			member_appearance = outfit
			member.set_profile(outfit)
			member_avatar.apply_outfit(outfit)
	elif multiplayer.get_remote_sender_id() == 1 and is_instance_valid(host_avatar):
		host_avatar.apply_outfit(outfit)

func _can_exchange_names() -> bool:
	return active() and not joining and remote_id!=0 and is_instance_valid(member_avatar if host else host_avatar)

func player_name_changed(value: String) -> void:
	if _can_exchange_names():
		# Coalesce edits, keeping the last change when several arrive in one frame.
		pending_name=WastelandSettings.clean_player_name(value)

@rpc("any_peer","call_remote","reliable",0)
func _nickname(value: String) -> void:
	if not _can_exchange_names() or value.length()>12:
		return
	if server():
		if not _is_member_sender():
			return
	elif multiplayer.get_remote_sender_id()!=1:
		return
	received_name=WastelandSettings.clean_player_name(value)

func send_request(id: String, args: Array) -> void:
	if remote_id==1 and not host and id in ACTIONS:
		_invoke.rpc_id(1,id,args)

@rpc("any_peer","call_remote","reliable",2)
func _invoke(id: String,args: Array) -> void:
	if _is_member_sender() and id in ACTIONS and args.size()<=3 and commands.size()<18:
		if var_to_bytes(args).size()<=1024 and _spend_budget():
			commands.append([id,args])

func _is_member_sender() -> bool:
	return server() and remote_id!=0 and multiplayer.get_remote_sender_id()==remote_id and is_instance_valid(member)

func _spend_budget() -> bool:
	if activity_budget>=130:
		return false
	activity_budget+=1
	return true

@rpc("any_peer","call_remote","unreliable_ordered",1)
func _pilot(drive: Vector2, yaw: float, pitch: float, held_keys: int, enabled: bool, auto_step := true) -> void:
	if not _is_member_sender() or not _spend_budget() or not drive.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	remote_input={"drive":drive.limit_length(),"yaw":wrapf(yaw,-PI,PI),"pitch":clampf(pitch,-1.49,1.49),"held":held_keys & key_mask,"enabled":enabled,"auto_step":auto_step}
	remote_updated=Time.get_ticks_msec()

@rpc("any_peer","call_remote","reliable",2)
func _edges(buttons: int) -> void:
	if _is_member_sender() and _spend_budget():
		remote_pressed |= buttons & key_mask

func _bit(id: String) -> int:
	var index:=KEYS.find(id)
	return 0 if index<0 else 1<<index

func remote_button(mode: String,id: String) -> bool:
	return (int(remote_input.get(mode,0)) & _bit(id))!=0

func host_tick(session: WastelandSession,delta:float) -> void:
	if not server() or not is_instance_valid(member):
		return
	budget_tick+=delta
	if budget_tick>=1.0:
		activity_budget=0
		budget_tick=0.0
	if not remote_input.is_empty():
		var nearby:=member.global_position.distance_to(session.player.global_position)<84.0
		var fresh:=Time.get_ticks_msec()-remote_updated<750
		remote_input.pressed=remote_pressed if fresh else 0
		if not fresh:
			remote_input.held=0
			remote_input.drive=Vector2.ZERO
		var enabled:=bool(remote_input.enabled) and not member_dead and fresh
		member.rotation.y=float(remote_input.yaw)
		member.pitch=float(remote_input.pitch)
		member.eyes.rotation.x=member.pitch
		if not nearby:
			var anchor:=session.player.global_position+Vector3(0.95,0.17,1.0)
			member.dismount(true)
			member.global_position=anchor
			member.velocity=Vector3.ZERO
			_party_message.rpc_id(remote_id,"离队过远，已回到主机附近",2.7)
		if not member_dead:
			_as_member(session,func():
				member.simulate(delta,enabled)
				session.action_lock=maxf(0.0,session.action_lock-delta)
				session._tick_reload(delta)
				if enabled and not member_dead:
					session._process_controls(delta))
		remote_pressed=0
	var actions:=commands.duplicate()
	commands.clear()
	for action in actions:
		if action[0]=="revive" and member_dead:
			_reset_member(session)
		elif not member_dead:
			_as_member(session,func(): session.apply_ui_command(str(action[0]),action[1]))
	if is_instance_valid(member_avatar):
		member_avatar.wear_loadout(session.bag.gear)
		member_avatar.set_offhand(member_offhand,member.guarding,member.flashlight and not member.submerged)
		member_avatar.visible=not member_appearance.is_empty() and not member_dead and not is_instance_valid(member.mount_vehicle)
		_avatar_motion(member_avatar,session.catalog,member.hand.model_id,member.hand.swing_serial,member.hand.shot_serial,int(session.bag.magazine.get(member.hand.model_id,0))>0)
		member_avatar.pose(delta,Vector2(member.velocity.x,member.velocity.z).length(),member.crouch,member.swimming)
	fast_timer-=delta
	slow_timer-=delta
	if fast_timer<=0.0:
		fast_timer=0.064
		_send_fast(session)
	if slow_timer<=0.0:
		slow_timer=0.61
		_send_world(session)
		var trails:=session.hordes.trail_snapshot(member.global_position)
		var raw:=var_to_bytes(trails)
		var packed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
		while packed.size()>1000 and trails.size()>1:
			trails.pop_back()
			raw=var_to_bytes(trails)
			packed=raw.compress(FileAccess.COMPRESSION_ZSTD)
		_trail_marks.rpc_id(remote_id,raw.size(),packed)
		var key:=session.chest_key(true)
		if not key.is_empty():
			_as_member(session,func():
				var view:=session.chest_view(key)
				if hash(view)!=last_chest_state:
					last_chest_state=hash(view)
					_chest_update.rpc_id(remote_id,key,view)
				if view.is_empty(): session.chest_close(key))

@rpc("authority","call_remote","unreliable_ordered",2)
func _trail_marks(raw_size:int,packed: PackedByteArray) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica or raw_size<=0 or raw_size>8192 or packed.size()>1024: return
	var raw:=packed.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=raw_size: return
	var rows:Variant=bytes_to_var(raw)
	if rows is Array and rows.size()<=24:
		game.session.hordes.mirror_trails(rows)

@rpc("authority","call_remote","reliable",0)
func _chest_update(key:String,view:Dictionary)->void:
	if host or not is_instance_valid(game.session) or not game.session.replica: return
	if not game.panels.visible or game.panels.active!="chest" or game.panels.current_context!=key: return
	game.session.replica_chest=view
	if view.is_empty(): game.close_overlay()

func _as_member(session: WastelandSession,callback: Callable) -> void:
	if session.remote_actor:
		callback.call()
		return
	var owner:=session.player
	_validate_member_slot(session.bag)
	var owner_hand:=session.bag.offhand
	session.bag.partner_offhand=owner_hand
	session.bag.gear.erase("offhand")
	if member_offhand!="": session.bag.gear.offhand=member_offhand
	owner_slot_during_guest_action=session.bag.active
	var wire: Variant=session.construction.selected_wire
	var host_context: Dictionary={}
	for key in CONTEXT:
		host_context[key]=session.get(key)
		session.set(key,member_context[key])
	session.player=member
	session.bag.active=member_slot
	session.construction.selected_wire=wire_endpoint
	session.remote_actor=true
	callback.call()
	member_offhand=session.bag.offhand
	session.bag.gear.erase("offhand")
	if owner_hand!="" and session.bag.count(owner_hand)>int(session.bag.is_worn(owner_hand)): session.bag.gear.offhand=owner_hand
	_validate_member_slot(session.bag)
	for key in CONTEXT:
		member_context[key]=session.get(key)
		session.set(key,host_context[key])
	member_slot=session.bag.active
	wire_endpoint=session.construction.selected_wire
	session.remote_actor=false
	session.player=owner
	session.bag.active=owner_slot_during_guest_action
	session.construction.selected_wire=wire

func member_failed() -> void:
	if not server() or member_dead:
		return
	member_dead=true
	member.collision_layer=0
	member.collision_mask=0
	if is_instance_valid(member.mount_vehicle):
		member.dismount(true)
		member.collision_layer=0
		member.collision_mask=0
	_member_down.rpc_id(remote_id)

func _reset_member(session: WastelandSession) -> void:
	member_dead=false
	member.health=member.max_health()
	member.reset_water_state()
	member.clear_damage_feedback()
	member.hunger=75.0
	member.hydration=75.0
	member.stamina=member.max_stamina()
	member.wet=0.0
	member.sprain=0.0
	member.bleed=0.0
	member.infection=0.0
	member.warm_drink_left=0.0
	member.ration_left=0.0
	member.fracture=0.0
	member.body_temp=36.7
	member.invulnerable=2.5
	member.collision_layer=4
	member.collision_mask=11
	member.global_position=session.player.global_position+session.player.global_basis.x*1.62
	member.velocity=Vector3.ZERO
	_revived.rpc_id(remote_id)

@rpc("authority","call_remote","reliable",0)
func _member_down() -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.death_screen=true
		game._failure()

@rpc("authority","call_remote","reliable",0)
func _revived() -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.death_screen=false
		game.session.player.clear_damage_feedback()
		game.session.player.reset_water_state()
		game.close_overlay()

func send_member_damage(victim: WastelandSurvivor, before: float, loss: float, source: String, bearing: Vector3, direct: bool) -> bool:
	if not server() or victim != member:
		return false
	_member_damage.rpc_id(remote_id, before, loss, source, bearing, direct)
	return true

@rpc("authority","call_remote","reliable",0)
func _member_damage(before: float, loss: float, source: String, bearing: Vector3, direct: bool) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.player.show_damage(before, loss, source, bearing, direct)

func tell(words:String, duration:float) -> void:
	if remote_id!=0 and host:
		_party_message.rpc_id(remote_id,words,duration)

func panel_for_member(id: String, context: Variant) -> void:
	if remote_id!=0 and host:
		if id=="chest":
			var view:Dictionary=game.session.chest_view(str(context))
			last_chest_state=hash(view)
			_party_panel.rpc_id(remote_id,id,view)
			return
		_party_panel.rpc_id(remote_id,id,context)

@rpc("authority","call_remote","reliable",0)
func _party_message(words:String,duration:float) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game._notify(words,duration)

@rpc("authority","call_remote","reliable",0)
func _party_panel(id:String,context:Variant) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		if id=="chest":
			if not context is Dictionary or not context.has("key"): return
			game.session.replica_chest=context
			context=context.key
		game.open_panel(id,context)

func cue(key:String,point:Vector3,loudness:float) -> void:
	if remote_id!=0 and host and key in EFFECTS and is_instance_valid(member) and member.global_position.distance_squared_to(point)<76.0*76.0:
		_effect.rpc_id(remote_id,key,point,loudness)

@rpc("authority","call_remote","unreliable",0)
func _effect(key:String,point:Vector3,loudness:float) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica and key in EFFECTS:
		game.session.audio.play_at(key,point,loudness)

func mirror_collapse(cells: Array[Vector3i]) -> void:
	if not server() or not is_instance_valid(member): return
	var nearby := cells.filter(func(cell): return WastelandConstruction.position_of(cell).distance_squared_to(member.global_position) < 75.0 * 75.0)
	if not nearby.is_empty():
		_falling_blocks.rpc_id(remote_id, nearby)

func mirror_canopy(model: String, variant: int, pose: Transform3D, salt: int, count: int, impulse: Vector3) -> void:
	if server() and is_instance_valid(member) and member.global_position.distance_squared_to(pose.origin)<65.0*65.0:
		_canopy.rpc_id(remote_id,model,variant,pose,salt,count,impulse)

@rpc("authority","call_remote","unreliable",0)
func _canopy(model: String, variant: int, pose: Transform3D, salt: int, count: int, impulse: Vector3) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.timber.litter.shed(model,variant,pose,salt,count,impulse)

@rpc("authority","call_remote","reliable",1)
func _falling_blocks(cells: Array) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.construction.show_collapse(cells)

func mirror_acid(row: Dictionary) -> void:
	if server() and is_instance_valid(member) and member.global_position.distance_squared_to(row.at) < 70.0 * 70.0:
		_acid_fx.rpc_id(remote_id,row)

@rpc("authority","call_remote","reliable",0)
func _acid_fx(row: Dictionary) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.fx.receive_acid(row)

func mirror_infected_effect(kind: String, point: Vector3, normal: Vector3) -> void:
	if server() and is_instance_valid(member) and member.global_position.distance_squared_to(point) < 70.0 * 70.0:
		_infected_fx.rpc_id(remote_id,kind,point,normal)

@rpc("authority","call_remote","reliable",0)
func _infected_fx(kind: String, point: Vector3, normal: Vector3) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.fx.infected_effect(kind,point,normal)

func _send_fast(session: WastelandSession) -> void:
	var actors: Array=[]
	for actor in session.hordes.alive:
		if not actor.active or actor.global_position.distance_squared_to(member.global_position)>105.0*105.0:
			continue
		actors.append([actor.spawn_serial, actor.type, actor.global_position, actor.rotation.y, actor.hp, actor.velocity,
			actor.attack, actor.hurt, actor.windup, int(actor.attack_kind), actor.alerted, actor.morph, actor.look_index, actor.wardrobe_index, actor.limb_index, actor.face_variant,
			int(actor.brain.state), actor.brain.state_left, actor.brain.wake_span, actor.brain.rage_left, actor.stage_health, actor.screamed, actor.limp_left,_actor_motion(actor)])
	var owner:=session.player
	var row := {"time":session.clock.hours,"elapsed":session.clock.elapsed,
		"owner_offhand":session.bag.offhand,"owner_guard":owner.guarding,"owner_flame":owner.flashlight and not owner.submerged,"member_guard":member.guarding,
		"member_swings":member.hand.swing_serial,"member_shots":member.hand.shot_serial,"swing_power":member.hand.swing_force,
		"owner_held":owner.hand.model_id,"owner_swings":owner.hand.swing_serial,"owner_shots":owner.hand.shot_serial,"owner_swim":owner.swimming,"owner_mounted":is_instance_valid(owner.mount_vehicle),
		"submerged":member.submerged,"swimming":member.swimming,"wet_feet":member.wet_feet,
		"owner_at":owner.global_position,"owner_yaw":owner.rotation.y,"owner_speed":Vector2(owner.velocity.x,owner.velocity.z).length(),"owner_duck":owner.crouch,
		"owner_lamp":owner.headlamp.visible,"owner_eye":owner.eyes.position.y,"owner_pitch":owner.pitch,
		"active":member_slot,"hint":member_context.hint,"loot":member_context.loot_ratio,"target_hp":member_context.focus_damage,
		"confirm":Vector3i(member.confirmed_hit,int(member.confirmed_head),int(member.confirmed_melee)),"noise":Vector2(member.recent_noise,member.noise_until),
		"shape":member_context.shape,"turn":member_context.turn,"wave":session.hordes.wave_index,
		"ride":member.mount_vehicle.id if is_instance_valid(member.mount_vehicle) else "","charge":member_context.heavy_charge,
		"reload":clampf(float(member_context.reload_left)/maxf(0.01,float(member_context.reload_span)),0.0,1.0) if not str(member_context.reload_id).is_empty() else 0.0}
	# Positional wire fields omit repeated names without changing the save schema.
	_frame.rpc_id(remote_id,_values(row,FRAME_FIELDS),_values(member.snapshot(),PLAYER_FIELDS),_values(row,MOTION_FIELDS))
	actor_frame+=1
	var count := maxi(1,ceili(float(actors.size())/ACTORS_PER_PAGE))
	for page in count:
		_actor_page.rpc_id(remote_id,actor_frame,page,count,actors.slice(page*ACTORS_PER_PAGE,(page+1)*ACTORS_PER_PAGE))

func _values(row: Dictionary, keys: Array) -> Array:
	var packed := []
	for key in keys:
		packed.append(row[key])
	return packed

func _unpack(row: Dictionary, keys: Array, values: Array) -> void:
	for i in keys.size():
		row[keys[i]]=values[i]

@rpc("authority","call_remote","unreliable_ordered",1)
func _frame(fields: Array, player: Array, motion: Array) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica:
		return
	if fields.size()!=FRAME_FIELDS.size() or player.size()!=PLAYER_FIELDS.size() or motion.size()!=MOTION_FIELDS.size():
		return
	var row := {}
	var vitals := {}
	_unpack(row,FRAME_FIELDS,fields)
	_unpack(vitals,PLAYER_FIELDS,player)
	_unpack(row,MOTION_FIELDS,motion)
	row.player=vitals
	replica_state=row
	replica_position=vitals.point

@rpc("authority","call_remote","unreliable",1)
func _actor_page(serial: int, page: int, count: int, rows: Array) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica:
		return
	if serial<=applied_actor_frame or count<1 or count>16 or page<0 or page>=count or rows.size()>ACTORS_PER_PAGE:
		return
	# Keep the last complete roster while up to two consecutive frames assemble.
	for pending: int in actor_pages.keys():
		if pending<serial-1:
			actor_pages.erase(pending)
		elif pending>serial+1:
			return
	if not actor_pages.has(serial):
		actor_pages[serial]={}
	var pages: Dictionary=actor_pages[serial]
	pages[page]=rows
	if pages.size()!=count:
		return
	var complete := []
	for i in count:
		complete.append_array(pages[i])
	replica_actors=complete
	applied_actor_frame=serial
	for pending: int in actor_pages.keys():
		if pending<=serial:
			actor_pages.erase(pending)

func _send_world(session:WastelandSession) -> void:
	var location:=WastelandTerrainGen.chunk_at(Vector2(member.global_position.x,member.global_position.z))
	var chunks: Dictionary={}
	var blocks: Dictionary={}
	var crops: Dictionary={}
	var excavations: Dictionary={}
	for z in range(-6,7):
		for x in range(-6,7):
			var cell:=location+Vector2i(x,z)
			var delta:=session.stream.chunk_diff(cell)
			if not delta.is_empty():
				chunks[WastelandTerrainGen.grid_key(cell)]=delta
			for key in session.construction.get_blockers(cell):
				blocks[key]=session.construction.blocks[key]
			excavations.merge(session.stream._delta_for(cell))
	for cell in session.construction.crops:
		var d: Vector2i=(WastelandTerrainGen.chunk_at(Vector2(cell.x,cell.z))-location).abs()
		if maxi(d.x,d.y)<=6:
			crops[cell]=session.construction.crops[cell]
	var wires:=session.construction.wires.filter(func(row): return blocks.has(row[0]) and blocks.has(row[1]))
	var snapshot: Dictionary={"diffs":chunks,"digs":excavations,"blocks":blocks,"crops":crops,"wires":wires,
		"bag":_guest_bag(session.bag),"progress":session.progress.snapshot(),"queue":session.hand_queue,
		"vehicles":_near_records(session.vehicle_records),"drops":_near_records(session.fx.drop_records),
		"markers":session.marker_records,"discovered":session.stream.discovered,"powered":session.construction.powered}
	snapshot.bag.active=member_slot
	snapshot.falling_trees=session.timber.snapshot()
	snapshot.lids=session.chest_lids()
	snapshot.threat=session.hordes.regional_snapshot(location)
	var fingerprint:=hash(snapshot)
	if fingerprint==manifest_hash:
		return
	manifest_hash=fingerprint
	var bytes:=var_to_bytes(snapshot)
	if bytes.size()<=MAX_PACKET:
		_manifest.rpc_id(remote_id,bytes.size(),bytes.compress(FileAccess.COMPRESSION_ZSTD))

func _near_records(rows:Dictionary) -> Dictionary:
	var result:Dictionary={}
	for id in rows:
		var row:Dictionary=rows[id]
		if (row.point as Vector3).distance_squared_to(member.global_position)<142.0*142.0:
			result[id]=row
	return result

# Keep the initial unchanged manifest behind the bootstrap on the same ordered channel.
@rpc("authority","call_remote","reliable",0)
func _manifest(size:int,compressed:PackedByteArray) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica or size<=0 or size>MAX_PACKET or compressed.size()>MAX_PACKET:
		return
	var raw:=compressed.decompress(size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=size:
		return
	var data:Variant=bytes_to_var(raw)
	if data is Dictionary:
		_apply_world(game.session,data)

func _apply_world(session:WastelandSession,row:Dictionary) -> void:
	session.bag.counts=row.bag.counts
	session.bag.bar=row.bag.bar
	session.bag.automatic_shortcuts=row.bag.get("automatic_shortcuts",{})
	session.bag.partner_offhand=row.bag.get("partner_offhand","")
	session.bag.restore_gear(row.bag)
	session.bag.magazine=row.bag.magazine
	session.hand_queue=row.queue
	var previous_awards:=session.progress.achieved
	session.progress=WastelandProgression.new(row.progress)
	var new_awards := session.progress.achieved.keys().filter(func(id):return not previous_awards.has(id))
	session.achievements.announce(new_awards)
	preload("res://game/core/atlas_unlocks.gd").remember(WastelandSave.save_root(),new_awards)
	session.marker_records=row.markers
	session.stream.discovered=row.discovered
	session.construction.mirror_layout(row.blocks,row.crops,row.wires,row.powered)
	session.stream.mirror_deltas(row.diffs,row.digs)
	session.timber.mirror(row.get("falling_trees",{}))
	session.apply_chest_lids(row.get("lids",[]))
	session.hordes.mirror_threat(row.get("threat",{}))
	for key in session.vehicles.keys():
		if not row.vehicles.has(key):
			session.vehicles[key].queue_free()
			session.vehicles.erase(key)
	for key in row.vehicles:
		if session.vehicles.has(key):
			var body:WastelandVehicle=session.vehicles[key]
			body.record=row.vehicles[key]
			body.update_repair_marker()
			if body.global_position.distance_squared_to(body.record.point)>0.002:
				body.global_position=body.record.point
				body.rotation.y=float(body.record.yaw)
	session.vehicle_records=row.vehicles
	session._sync_vehicles()
	session.fx.apply_drop_snapshot(row.drops)

func client_tick(session:WastelandSession,dt:float) -> void:
	if not active() or host:
		return
	var p:=session.player
	if session.controls_enabled:
		p.look(p._stick_look()*Vector2(2.7,-2.16 if session.options.display.invert_y else 2.16)*dt)
	var buttons:=0
	var held:=0
	if session.controls_enabled and not session.death_screen:
		for i in range(KEYS.size()):
			if Input.is_action_just_pressed(KEYS[i]):
				buttons|=1<<i
			if session.action_held(KEYS[i]):
				held|=1<<i
	remote_pressed|=buttons
	fast_timer-=dt
	if fast_timer<=0.0:
		fast_timer=0.045
		var axis:=Input.get_vector("left","right","up","down") if session.controls_enabled else Vector2.ZERO
		_pilot.rpc_id(1,axis,p.rotation.y,p.pitch,held,session.controls_enabled,bool(session.options.display.auto_step))
		if remote_pressed!=0:
			_edges.rpc_id(1,remote_pressed)
			remote_pressed=0
	if replica_state.is_empty():
		return
	var speed := p.global_position.distance_to(replica_position) / maxf(0.001,dt)
	p.global_position=p.global_position.lerp(replica_position,1.0 if speed>350.0 else minf(1.0,dt*13.0))
	var row:=replica_state
	p.restore_vitals(row.player)
	p.hunger=float(row.player.hunger)
	p.hydration=float(row.player.hydration)
	p.submerged=bool(row.get("submerged", false))
	p.swimming=bool(row.get("swimming", false))
	p.wet_feet=bool(row.get("wet_feet", false))
	p.body_temp=float(row.player.temp)
	p.bleed=float(row.player.bleed)
	p.infection=float(row.player.infection)
	p.fracture=float(row.player.fracture)
	p.sprain=float(row.player.get("sprain",0))
	p.wet=float(row.player.get("wet",0))
	if not session.death_screen:
		p.update_damage_feedback(dt)
	p.flashlight=bool(row.player.lamp)
	p.guarding=bool(row.member_guard)
	p.headlamp.visible=p.flashlight and session.bag.offhand!="torch"
	p.hand.set_offhand(session.bag.offhand,p.guarding,p.flashlight and not p.submerged)
	preload("res://game/art/offhand_art.gd").sync_world_light(p.camera,session.bag.offhand,p.flashlight and not p.submerged)
	if row.player.get("profile", p.profile) == p.profile:
		p.crouch = float(row.player.get("crouch", 0.0))
		p.stand_shape.height = float(row.player.get("body_height", p.stand_shape.height))
		p.capsule.position.y = p.stand_shape.height * 0.5
		p.eyes.position.y = float(row.player.get("eye_height", p.eyes.position.y))
	p.ambient=session.clock.temperature()+session.stream.generator.temperature_offset(p.position.x,p.position.z)-maxf(0,p.position.y-11.0)*0.14
	session.bag.active=int(row.active)
	session.hint=session.localized_prompt(str(row.hint))
	session.loot_ratio=float(row.loot)
	var confirm:Vector3i=row.confirm
	p.confirmation_left=maxf(0,p.confirmation_left-dt)
	if confirm.x>p.confirmed_hit:
		p.confirmed_hit=confirm.x
		p.confirmed_head=confirm.y!=0
		p.confirmation_left=0.19
		if confirm.z!=0:
			p.hit_stop=0.045
			p.impact_kick=0.105
	p.recent_noise=row.noise.x
	p.noise_until=row.noise.y
	session.focus_damage=float(row.target_hp)
	session.shape=int(row.shape)
	session.turn=int(row.turn)
	session.hordes.wave_index=int(row.wave)
	session.clock.hours=float(row.time)
	session.clock.elapsed=float(row.elapsed)
	session.stream.advance_loot_day(session.clock.day())
	session.stream.refresh(p.global_position,int(session.options.display.radius))
	session.atmosphere.sync(session.clock,dt,p.camera.global_position,-p.camera.global_basis.z,session.audio)
	session.audio.sync(session.atmosphere.rain_strength,session.clock.blood(),float(session.stream.water_at(p.global_position)))
	var held_item:=session.bag.current()
	p.update_optics(dt,session.controls_enabled and not session.death_screen and session.optics_active())
	p.hand.set_gloves(session.bag.gear.hands=="work_gloves",session.bag.gear.hands=="meme_claws")
	p.hand.hold(held_item,session.catalog.items.get(held_item,{}))
	p.hand.set_loaded_arrow(int(session.bag.magazine.get(held_item,0))>0)
	p.hand.reload_ratio=float(row.reload)
	p.hand.charge=float(row.charge)
	p.hand.swimming=p.swimming
	p.hand.search_ratio = session.loot_ratio
	var swings := int(row.get("member_swings",0))
	var shots := int(row.get("member_shots",0))
	if swings > p.hand.swing_serial:
		p.hand.swing_attack(float(row.get("swing_power",1.0)))
		p.hand.swing_serial = swings
	if shots > p.hand.shot_serial:
		p.hand.recoil(held_item not in ["bow","field_crossbow"])
		p.hand.shot_serial = shots
	p.hand.animate(dt,minf(3.0,speed*0.11),p.crouch,session.atmosphere.sun_strength,p.hit_stop)
	p.hit_stop=maxf(0,p.hit_stop-dt)
	host_avatar.visible = not bool(row.get("owner_mounted",false))
	host_avatar.wear_loadout(session.bag.gear)
	host_avatar.set_offhand(row.owner_offhand,row.owner_guard,row.owner_flame)
	host_avatar.global_position=host_avatar.global_position.lerp(row.owner_at,1.0 if host_avatar.global_position.distance_to(row.owner_at)>12.0 else minf(1.0,dt*12.0))
	host_avatar.rotation.y=lerp_angle(host_avatar.rotation.y,float(row.owner_yaw),minf(1,dt*14.0))
	var owner_held := str(row.get("owner_held",""))
	_avatar_motion(host_avatar,session.catalog,owner_held,int(row.get("owner_swings",0)),int(row.get("owner_shots",0)),int(session.bag.magazine.get(owner_held,0))>0)
	host_avatar.pose(dt,float(row.owner_speed),float(row.owner_duck),bool(row.get("owner_swim",false)))
	host_lamp.position.y = float(row.get("owner_eye", 1.62))
	host_lamp.rotation.x = float(row.get("owner_pitch", 0.0))
	host_lamp.visible = bool(row.get("owner_lamp", false))
	_pose_actors(session,replica_actors,dt)
	session.fx.simulate_projectiles(dt)
	session.fx.present_drops(dt)

func _avatar_motion(avatar: WastelandPartyAvatar,catalog: WastelandCatalog,held: String,swings: int,shots: int,loaded: bool=false) -> void:
	if int(avatar.get_meta("swings",swings)) != swings: avatar.act("punch" if held.is_empty() else "tool")
	if int(avatar.get_meta("shots",shots)) != shots: avatar.act("fire")
	avatar.set_meta("swings",swings)
	avatar.set_meta("shots",shots)
	var grip := avatar.grip
	var model := "field_crossbow_empty" if held=="field_crossbow" and not loaded else held
	if grip == null or grip.get_meta("shown_model","?") == model: return
	grip.set_meta("held",held)
	grip.set_meta("shown_model",model)
	var mesh := grip.get_node_or_null("HeldItem") as MeshInstance3D
	if not catalog.items.has(held):
		if mesh != null:
			grip.remove_child(mesh)
			mesh.queue_free()
		return
	if mesh == null:
		mesh = MeshInstance3D.new()
		mesh.name = "HeldItem"
		mesh.material_override = WastelandLook.colored_material()
		grip.add_child(mesh)
	mesh.mesh = WastelandItemArt.mesh(model,catalog.items[held])
	mesh.scale = Vector3.ONE*(0.76 if catalog.items[held].kind in ["tool","weapon","ranged"] else 0.42)
	mesh.rotation.x = -0.93 if catalog.items[held].kind in ["tool","weapon"] else 0.0
	if held=="reed_spear": mesh.rotation.x=-1.25
	mesh.visible = true

func _actor_motion(actor:WastelandCreature) -> Vector4i:
	var cycle := actor.wildlife_cycle if actor.brain.animal else fposmod(actor.pose_phase/TAU,1.0)
	var flags := (int(actor.motion_action)<<7) | (int(actor.brain.mode)<<3) | (int(actor.motion_water)<<2) | (int(actor.brain.forage_left>0.0)<<1) | int(actor.brain.charge_left>0.0)
	flags |= roundi(actor.motion_rest*63.0)<<12
	var impact := Vector2i(((actor.impact_tilt.clamp(Vector2(-1,-1),Vector2.ONE)+Vector2.ONE)*127.0).round())
	var slope := Vector2i(((Vector2(actor.motion_floor_normal.x,actor.motion_floor_normal.z)+Vector2.ONE)*127.0).round())
	# One byte per signed component of the upward support normal and the recoil.
	var surfaces := (slope.x<<24) | (slope.y<<16) | (impact.x<<8) | impact.y
	return Vector4i(roundi(cycle*65535.0),roundi(actor.motion_speed*1000.0),flags,surfaces)

func _pose_actors(session:WastelandSession,rows:Array,delta:float) -> void:
	actors_now.clear()
	var fresh_frame := posed_actor_frame != applied_actor_frame
	posed_actor_frame=applied_actor_frame
	for tuple in rows:
		var id:int=tuple[0]
		var spawning := not smooth_actors.has(id)
		if spawning:
			for actor in session.hordes.pool:
				if actor.active:
					continue
				actor.revive(tuple[1],tuple[2],false,{"hp":tuple[4], "morph":tuple[11] if tuple.size() > 11 else "",
					"look_index":tuple[12] if tuple.size() > 12 else 0,
					"wardrobe_index":tuple[13] if tuple.size() > 13 else 0,
					"limb_index":tuple[14] if tuple.size() > 14 else 0,
					"face_variant":tuple[15] if tuple.size() > 15 else 0,
					"stage_health":tuple[20] if tuple.size() > 20 else 1.0,"facing":tuple[3]})
				actor.spawn_serial = id
				actor.collision_layer=4
				actor.collision_mask=0
				smooth_actors[id]=actor
				break
		if not smooth_actors.has(id):
			continue
		var actor:WastelandCreature=smooth_actors[id]
		actors_now[id]=true
		actor.global_position=actor.global_position.lerp(tuple[2],minf(1,delta*11.0))
		actor.rotation.y=lerp_angle(actor.rotation.y,float(tuple[3]),minf(1,delta*15.0))
		actor.hp=float(tuple[4])
		actor.collision_layer=4 if actor.hp>0.0 else 0
		actor.hurtboxes.enable(actor.hp > 0.0)
		if tuple.size() >= 23:
			actor.brain.state = int(tuple[16]) as WastelandCreatureBrain.State
			actor.brain.state_left = float(tuple[17])
			actor.brain.wake_span = float(tuple[18])
			actor.brain.rage_left = float(tuple[19])
			actor.screamed = bool(tuple[21])
			actor.limp_left = float(tuple[22])
		actor.velocity=tuple[5]
		actor.attack=float(tuple[6])
		actor.hurt=float(tuple[7])
		if tuple.size() >= 11:
			var attack_kind := int(tuple[9]) as WastelandCreatureBrain.Action
			actor.windup = lerpf(actor.windup, float(tuple[8]), minf(1.0, delta * 21.0)) if actor.attack_kind == attack_kind else float(tuple[8])
			actor.attack_kind = attack_kind
			actor.alerted = bool(tuple[10])
			if attack_kind != WastelandCreatureBrain.Action.RUPTURE and is_instance_valid(actor.blast_ring):
				actor.blast_ring.hide()
		var travel := -1.0
		if tuple.size()>23:
			var sample: Vector4i = tuple[23]
			travel = float(sample.y)*0.001*delta
			if fresh_frame or spawning:
				var target_phase := float(sample.x)*TAU/65535.0
				var weight := 1.0 if spawning else 0.65
				if actor.brain.animal:
					actor.wildlife_cycle = fposmod(lerp_angle(actor.wildlife_cycle*TAU,target_phase,weight)/TAU,1.0)
				else:
					actor.pose_phase += angle_difference(actor.pose_phase,target_phase)*weight
				actor.brain.mode=((sample.z>>3)&15) as WastelandCreatureBrain.Mode
				actor.motion_action=((sample.z>>7)&15) as WastelandCreatureBrain.Action
				if spawning or actor.brain.state==WastelandCreatureBrain.State.DEAD:
					actor.motion_rest=float((sample.z>>12)&63)/63.0
				actor.motion_water=bool(sample.z&4)
				actor.brain.forage_left=1.0 if sample.z&2 else 0.0
				actor.brain.charge_left=1.0 if sample.z&1 else 0.0
				actor.impact_tilt=Vector2((sample.w>>8)&255,sample.w&255)/127.0-Vector2.ONE
				var slope := Vector2((sample.w>>24)&255,(sample.w>>16)&255)/127.0-Vector2.ONE
				actor.motion_floor_normal=Vector3(slope.x,sqrt(maxf(0.0,1.0-slope.length_squared())),slope.y).normalized()
		actor._pose(delta,actor.global_position.distance_to(session.player.global_position),travel)
	for id in smooth_actors.keys():
		if not actors_now.has(id):
			smooth_actors[id].deactivate()
			smooth_actors.erase(id)
