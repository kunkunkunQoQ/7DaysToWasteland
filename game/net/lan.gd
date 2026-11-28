class_name WastelandLan
extends Node

const DEFAULT_PORT := 7357
const DISCOVERY := preload("res://game/net/lan_discovery.gd")
const MAX_PLAYERS := DISCOVERY.MAX_PLAYERS
const PROTOCOL_VERSION := 6
const HOST_ID := 1
const JOIN_TIMEOUT_MS := 20000
var discovery := DISCOVERY.new()
const ID_PATH := "user://coop_identity.cfg"
const MAX_PACKET := 3 * 1024 * 1024
const EFFECTS := ["step_soil","step_grass","step_leaves","step_wood","step_stone","chop","stone","hit","place","search","bow","shot","boom","growl","scream","alarm","splash","thunder","reload",
	"attack_tell","spit_tell","scream_tell","hammer","collapse","tree_split","tree_rustle","tree_land"]
const KEYS := ["jump","sprint","crouch","use","fire","alternate","reload","shape","rotate","flashlight","discard","slot_next","slot_prev",
	"slot_1","slot_2","slot_3","slot_4","slot_5","slot_6","slot_7","slot_8","offhand_use","swap_hands"]
static var key_mask := (1 << KEYS.size()) - 1
const THIRD_PERSON_HELD_BIT := 1 << 30
const DEVICE_COMMANDS := ["craft","cancel","collect","fuel","rest","enable","feed_fire","smelt_input"]
static var ACTIONS := DEVICE_COMMANDS + ["save","chat","slot","assign","assign_slot","pack_slot","move_slot","quick_equip","offhand","swap_hands","consume","discard","learn","job","barter","deliver","dispatch","patrol_start","patrol_claim","rebuild_board","recover_archive","marker","unmark","vehicle","repair_vehicle","revive","chest_take","chest_put","chest_all","chest_close"]
const CONTEXT := ["interaction","building_hit","next_hint","hint","focus_damage","loot_target","loot_time","loot_full","loot_ratio",
	"search_start","search_slot","search_held","action_lock","reload_id","reload_left","reload_span","heavy_charge","heavy_pending","shape","turn"]

var game: Node
var transport: ENetMultiplayerPeer
var host := false
var port := DEFAULT_PORT
var joining := false
var connected_to_host := false

# The transport reserves a slot as soon as a connection arrives. Every piece of
# mutable authority state belongs to that peer, including pending handshakes.
class MemberState:
	extends RefCounted
	var peer_id: int
	var joined_at := Time.get_ticks_msec()
	var survivor: WastelandSurvivor
	var avatar: WastelandPartyAvatar
	var token := ""
	var appearance := ""
	var nickname := ""
	var input: Dictionary = {}
	var pressed := 0
	var updated_at := 0
	var context: Dictionary = {}
	var bag: WastelandBag
	var hand_queue: Array = []
	var wire_endpoint: Variant
	var downed := false
	var save_requested := false
	var commands: Array = []
	var activity_budget := 0
	var budget_tick := 0.0
	var pending_name := ""
	var next_name_receive := 0
	var fast_timer := 0.0
	var slow_timer := 0.0
	var manifest_hash: Variant
	var actor_frame := 0
	var last_chest_state := -1
	var settled_sent := {}
	func _init(id: int) -> void:
		peer_id=id

class ReplicaMember:
	extends RefCounted
	var avatar: WastelandPartyAvatar
	var lamp: SpotLight3D
	var motion: Dictionary = {}

var members: Dictionary = {}
var replicas: Dictionary = {}
# While executing a guest's input, the shared simulation temporarily selects its
# survivor. The owner's state remains available for nested damage callbacks.
var active_member: MemberState
var owner_state: MemberState
var replica_position := Vector3.ZERO
var replica_state: Dictionary = {}
var local_pressed := 0
var pending_name := ""
var next_name_send := 0
var local_token := ""
var smooth_actors: Dictionary = {}
var actors_now: Dictionary = {}
var party_falls := preload("res://game/net/party_falls.gd").new()
var resting_creatures := {}
const ACTORS_PER_PAGE := 5
const FRAME_FIELDS := ["time","elapsed","active","hint","loot","target_hp","shape","turn","wave","ride","charge","reload","confirm","noise"]
const PLAYER_FIELDS := ["point","health","profile","limits","crouch","body_height","eye_height","stamina","hunger","hydration","temp","bleed","infection","fracture","lamp","breath","provisions","sprain","wet"]
const MOTION_FIELDS := ["member_swings","member_shots","swing_power","submerged","swimming","wet_feet","member_guard"]
const PARTY_FIELDS := ["peer","at","yaw","speed","duck","swim","hidden","held","swings","shots","offhand","guard","flame","lamp","eye","pitch","loaded"]
var applied_actor_frame := -1
var posed_actor_frame := -1
var actor_pages := {}
var replica_actors := []
var client_timer := 0.0
var connected_since := 0
var shared_clock := 0.0
var next_guest_save := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_registered)
	multiplayer.peer_disconnected.connect(_departed)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_closed)

func active() -> bool:
	return transport != null and (host or joining or connected_to_host)

func server() -> bool:
	return active() and host

func listen(target_port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(target_port,MAX_PLAYERS-1,3)
	if result != OK:
		return result
	host=true
	transport=peer
	port=target_port
	# Guests only communicate with the authoritative host, not with each other.
	(multiplayer as SceneMultiplayer).server_relay=false
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
	for peer: int in members.keys():
		_remove_member(peer,false)
	if transport!=null:
		transport.close()
		multiplayer.multiplayer_peer=null
	transport=null
	for peer: int in replicas.keys():
		_remove_replica(peer)
	pending_name=""
	next_name_send=0
	host=false
	joining=false
	connected_to_host=false
	active_member=null
	owner_state=null
	local_pressed=0
	client_timer=0.0
	next_guest_save=0
	replica_state.clear()
	actor_pages.clear()
	replica_actors.clear()
	smooth_actors.clear()
	actors_now.clear()
	resting_creatures.clear()
	party_falls = preload("res://game/net/party_falls.gd").new()

func player_count() -> int:
	return 1+members.size()

func joined_members() -> Array[MemberState]:
	var result: Array[MemberState]=[]
	for state: MemberState in members.values():
		if is_instance_valid(state.survivor):
			result.append(state)
	return result

func member_for(survivor: WastelandSurvivor) -> MemberState:
	if not is_instance_valid(survivor): return null
	for state: MemberState in joined_members():
		if state.survivor==survivor: return state
	return null

func member_with_token(token:String) -> MemberState:
	for state: MemberState in joined_members():
		if state.token==token: return state
	return null

func owner_player(session:WastelandSession) -> WastelandSurvivor:
	return owner_state.survivor if owner_state!=null else session.player

func living_guests() -> Array[WastelandSurvivor]:
	var result: Array[WastelandSurvivor]=[]
	for state: MemberState in joined_members():
		if not state.downed and state.survivor.health>0.0: result.append(state.survivor)
	return result

func invalidate_world() -> void:
	for state: MemberState in joined_members():
		state.slow_timer=0.0

func current_input() -> Dictionary:
	return active_member.input if active_member!=null else {}

func _process(_delta:float) -> void:
	if server() and is_instance_valid(game.session) and not game.session.preview_only:
		discovery.answer(_local_address,game.session.world_settings.name,game.options.player_name,game.session.clock.day(),port,player_count())
		var now:=Time.get_ticks_msec()
		var roster_changed:=false
		for state: MemberState in members.values():
			if not is_instance_valid(state.survivor):
				if now-state.joined_at>JOIN_TIMEOUT_MS:
					transport.disconnect_peer(state.peer_id)
					_remove_member(state.peer_id,false)
				continue
			if not state.pending_name.is_empty() and now>=state.next_name_receive:
				state.nickname=state.pending_name
				state.avatar.set_player_name(state.nickname)
				state.pending_name=""
				state.next_name_receive=now+300
				roster_changed=true
		if roster_changed: _broadcast_roster()
		if game.session.death_screen or game.session.simulation_paused:
			_save_requested_guests(game.session,joined_members())
	elif not active() and is_instance_valid(game.front) and game.front.visible and game.front.screen=="lan":
		discovery.browse(_local_address)
	elif discovery.browser != null:
		discovery.close()
	if not pending_name.is_empty() and Time.get_ticks_msec()>=next_name_send and active() and not joining:
		if host: _broadcast_roster()
		else: _nickname.rpc_id(HOST_ID,pending_name)
		pending_name=""
		next_name_send=Time.get_ticks_msec()+300
	if joining and Time.get_ticks_msec()-connected_since>JOIN_TIMEOUT_MS:
		_failed()

func _registered(peer: int) -> void:
	if not server():
		return
	if not is_instance_valid(game.session) or game.session.preview_only or members.size()>=MAX_PLAYERS-1:
		transport.disconnect_peer(peer)
		return
	var endpoint := transport.get_peer(peer)
	if endpoint==null or not _local_address(endpoint.get_remote_address()):
		transport.disconnect_peer(peer)
		return
	members[peer]=MemberState.new(peer)
	_welcome.rpc_id(peer,PROTOCOL_VERSION)

@rpc("authority","call_remote","reliable",0)
func _welcome(protocol:int) -> void:
	if host or not joining or multiplayer.get_remote_sender_id()!=HOST_ID:
		return
	if protocol!=PROTOCOL_VERSION:
		stop()
		game.connection_notice("联机版本不一致，请升级到相同版本")
		return
	if local_token.is_empty():
		var identity := ConfigFile.new()
		if FileAccess.file_exists(ID_PATH):
			var read_error := identity.load(ID_PATH)
			if read_error != OK:
				stop()
				game.connection_notice("无法读取本机联机身份 · 错误 %d" % read_error)
				return
		local_token = str(identity.get_value("coop", "identity", ""))
		if local_token.length() != 32 or not local_token.is_valid_hex_number(false):
			local_token = Crypto.new().generate_random_bytes(16).hex_encode()
			identity.set_value("coop","identity",local_token)
			var write_error := identity.save(ID_PATH)
			if write_error != OK:
				local_token = ""
				stop()
				game.connection_notice("无法保存本机联机身份 · 错误 %d" % write_error)
				return
	_identify.rpc_id(HOST_ID,PROTOCOL_VERSION,local_token,game.options.appearance,game.options.player_name)

@rpc("any_peer","call_remote","reliable",0)
func _identify(protocol:int, token: String, outfit: String, nickname: String) -> void:
	if not server(): return
	var state: MemberState=members.get(multiplayer.get_remote_sender_id())
	if state==null or not state.token.is_empty():
		return
	if protocol!=PROTOCOL_VERSION or nickname.length()>12 or token.length()!=32 or not token.is_valid_hex_number(false) or not WastelandPartyAvatar.OUTFITS.has(outfit) or member_with_token(token)!=null:
		transport.disconnect_peer(state.peer_id)
		return
	state.token=token
	state.appearance=outfit
	state.nickname=WastelandSettings.clean_player_name(nickname)
	var session: WastelandSession = game.session
	var previous: Dictionary = session.guest_states.get(token, {})
	# Older worlds kept all items in the owner's bag and saved only the guest's selected slot.
	state.bag=session.create_bag(previous.get("bag",{"active":previous.get("slot",0)}))
	state.hand_queue=previous.get("hand_queue",[]).duplicate(true)
	var member:=WastelandSurvivor.new()
	state.survivor=member
	session.add_child(member)
	var at:=_spawn_near_owner(session,state)
	member.configure(session,previous,at,false,outfit,state.bag)
	member.ragdoll_changed.connect(session._player_fell.bind(member))
	member.ragdoll_struck.connect(session._player_part_hit.bind(member))
	if member.global_position.distance_squared_to(at) > 80.0 * 80.0:
		member.global_position = at
	session.stream.ensure_landing(member.global_position)
	state.downed=bool(previous.get("downed",false)) or member.health<=0.0
	if state.downed:
		member.collision_layer = 0
		member.collision_mask = 0
	state.avatar=WastelandPartyAvatar.new()
	member.add_child(state.avatar)
	state.avatar.apply_outfit(outfit)
	state.avatar.set_player_name(state.nickname)
	state.avatar.visible=not state.downed
	member.set_live_avatar(state.avatar)
	if not state.downed: member.pose_ground_motion(0.0)
	for key in CONTEXT:
		state.context[key]=session.get(key)
	state.context.interaction={}
	state.context.building_hit={}
	state.context.next_hint=0.0
	state.context.focus_damage=-1.0
	state.context.loot_target=null
	state.context.loot_ratio=0.0
	state.context.loot_time=0.0
	state.context.loot_full=0.0
	state.context.search_start=Vector3.ZERO
	state.context.search_slot=-1
	state.context.search_held=""
	state.context.reload_id=""
	state.context.reload_left=0.0
	state.context.reload_span=0.0
	state.context.heavy_pending=false
	state.context.heavy_charge=0.0
	state.context.action_lock=0.0
	state.context.hint=""
	session.audio.relay=cue
	var payload: Dictionary={"settings":session.world_settings,"time":session.clock.hours,"elapsed":session.clock.elapsed,
		"player":member.snapshot(),"bag":state.bag.snapshot(),"hand_queue":state.hand_queue,"progress":session.progress.snapshot(),"acid_pools":session.fx.acid_snapshot(),
		"acid_shots":session.fx.acid_flights(member.global_position),"acid_serial":session.fx.acid_serial,
		"roster":_roster_rows(state.peer_id),"downed":state.downed,"falls":party_falls.snapshot(session,self),
		"party":_party_motion(session,joined_members()).filter(func(entry): return int(entry[0])!=state.peer_id),
		"lake_combat":session.stream.lake_wildlife.combat_snapshot()}
	_bootstrap.rpc_id(state.peer_id,payload)
	_broadcast_roster()
	invalidate_world()
	session.notify("队友已加入世界")

func _spawn_near_owner(session:WastelandSession,state:MemberState) -> Vector3:
	var owner:=owner_player(session)
	var index:=joined_members().find(state)
	var offset:=Vector3(1.38,0,0).rotated(Vector3.UP,TAU*maxi(index,0)/(MAX_PLAYERS-1))
	var at:=owner.global_position+owner.global_basis*offset
	at.y=maxf(at.y,session.stream.ground_at(at)+0.14)
	return at

func _store_member(state:MemberState) -> void:
	if not is_instance_valid(state.survivor) or state.token.is_empty(): return
	var saved:=state.survivor.snapshot()
	saved.downed=state.downed
	saved.bag=state.bag.snapshot()
	saved.hand_queue=state.hand_queue.duplicate(true)
	state.survivor.session.guest_states[state.token]=saved

func store_guests(session:WastelandSession) -> void:
	if not host: return
	for state:MemberState in joined_members():
		if state.survivor.session==session: _store_member(state)

func _departed(peer:int) -> void:
	if server(): _remove_member(peer,true)

func _remove_member(peer:int,announce:bool) -> void:
	var state:MemberState=members.get(peer)
	if state==null: return
	members.erase(peer)
	if not is_instance_valid(state.survivor): return
	_store_member(state)
	var session:WastelandSession=state.survivor.session
	session.chest_leave(peer)
	session.construction.tool_jobs.erase(state.survivor.get_instance_id())
	if is_instance_valid(state.survivor.mount_vehicle): state.survivor.dismount(true)
	state.survivor.queue_free()
	if announce:
		var result:=session.save_now(false)
		_broadcast_roster()
		invalidate_world()
		session.notify("队友已离开" if result==OK else "队友已离开，世界保存失败 · 错误 %d" % result)

func _connected() -> void:
	if not host and transport!=null:
		connected_to_host=true

func _failed() -> void:
	if not joining and not connected_to_host:
		return
	stop()
	game.connection_notice("连接失败：房间已满、版本不一致或主机不可达")

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
	if host or not joining or multiplayer.get_remote_sender_id()!=HOST_ID:
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
	_apply_roster(start.get("roster",[]))
	_party_frame(start.get("party",[]))
	for fall in start.get("falls",[]): party_falls.apply(session,multiplayer.get_unique_id(),fall)
	client_timer=0.0
	local_pressed=0
	appearance_changed(game.options.appearance)
	player_name_changed(game.options.player_name)
	session.notify("已加入 " + str(start.settings.name))
	if start.get("downed", false):
		session.death_screen = true
		game._failure()

func appearance_changed(outfit: String) -> void:
	if not active() or joining or not WastelandPartyAvatar.OUTFITS.has(outfit): return
	if host: _broadcast_roster()
	else: _outfit.rpc_id(HOST_ID,outfit)

@rpc("any_peer","call_remote","reliable",0)
func _outfit(outfit: String) -> void:
	if not WastelandPartyAvatar.OUTFITS.has(outfit):
		return
	var state:=_sender()
	if state!=null and state.appearance!=outfit and _spend_budget(state):
		state.appearance=outfit
		state.survivor.set_profile(outfit)
		state.avatar.apply_outfit(outfit)
		_broadcast_roster()

func player_name_changed(value: String) -> void:
	if active() and not joining:
		# Coalesce edits, keeping the last change when several arrive in one frame.
		pending_name=WastelandSettings.clean_player_name(value)

@rpc("any_peer","call_remote","reliable",0)
func _nickname(value: String) -> void:
	var state:=_sender()
	if state!=null and value.length()<=12 and _spend_budget(state):
		state.pending_name=WastelandSettings.clean_player_name(value)

func _roster_rows(except_peer:int)->Array:
	var rows: Array=[[HOST_ID,game.options.player_name,game.options.appearance]]
	for state:MemberState in joined_members():
		if state.peer_id!=except_peer: rows.append([state.peer_id,state.nickname,state.appearance])
	return rows

func _broadcast_roster()->void:
	if not server(): return
	for state:MemberState in joined_members():
		_roster.rpc_id(state.peer_id,_roster_rows(state.peer_id))

@rpc("authority","call_remote","reliable",0)
func _roster(rows:Array)->void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		_apply_roster(rows)

func _apply_roster(rows:Array)->void:
	if rows.size()>MAX_PLAYERS-1: return
	var present: Dictionary={}
	for row in rows:
		if not row is Array or row.size()!=3 or not row[0] is int or row[0]<=0 or row[0]==multiplayer.get_unique_id() or not WastelandPartyAvatar.OUTFITS.has(row[2]): continue
		var peer:int=row[0]
		present[peer]=true
		var view:ReplicaMember=replicas.get(peer)
		if view==null:
			view=ReplicaMember.new()
			view.avatar=WastelandPartyAvatar.new()
			game.session.add_child(view.avatar)
			view.avatar.configure_live_motion(game.session)
			view.lamp=game.session.player.headlamp.duplicate() as SpotLight3D
			view.avatar.add_child(view.lamp)
			view.lamp.hide()
			view.avatar.hide()
			replicas[peer]=view
		if view.avatar.outfit!=row[2]: view.avatar.apply_outfit(row[2])
		view.avatar.set_player_name(WastelandSettings.clean_player_name(str(row[1])))
	for peer:int in replicas.keys():
		if not present.has(peer): _remove_replica(peer)

func _remove_replica(peer:int)->void:
	party_falls.detach(peer)
	var view:ReplicaMember=replicas.get(peer)
	if view!=null and is_instance_valid(view.avatar):
		view.avatar.hide()
		view.avatar.queue_free()
	replicas.erase(peer)

func replica_avatar(peer:int)->WastelandPartyAvatar:
	var view:ReplicaMember=replicas.get(peer)
	return view.avatar if view!=null else null

func replica_lamp(peer:int)->SpotLight3D:
	var view:ReplicaMember=replicas.get(peer)
	return view.lamp if view!=null else null

func replica_positions()->Array[Vector3]:
	var points:Array[Vector3]=[]
	for view:ReplicaMember in replicas.values():
		if is_instance_valid(view.avatar) and view.avatar.visible: points.append(view.avatar.global_position)
	return points

func send_request(id: String, args: Array) -> void:
	if connected_to_host and not host and not joining and id in ACTIONS:
		_invoke.rpc_id(HOST_ID,id,args)

@rpc("any_peer","call_remote","reliable",2)
func _invoke(id: String,args: Array) -> void:
	var state:=_sender()
	if state==null: return
	if id=="save":
		if args.is_empty(): state.save_requested=true
		return
	if id=="chat":
		if args.size()==1 and args[0] is String and args[0].length()<=WastelandSession.CHAT_LENGTH and _spend_budget(state):
			_as_member(game.session,state,game.session.send_chat.bind(args[0]))
		return
	var max_args := 4 if id in ["chest_put","chest_take"] else 3
	if id in ACTIONS and args.size()<=max_args and state.commands.size()<18:
		if var_to_bytes(args).size()<=1024 and _spend_budget(state):
			state.commands.append([id,args])

func _sender() -> MemberState:
	if not server(): return null
	var state:MemberState=members.get(multiplayer.get_remote_sender_id())
	return state if state!=null and is_instance_valid(state.survivor) else null

func _spend_budget(state:MemberState) -> bool:
	if state.activity_budget>=130:
		return false
	state.activity_budget+=1
	return true

@rpc("any_peer","call_remote","unreliable_ordered",1)
func _pilot(drive: Vector2, yaw: float, pitch: float, held_keys: int, enabled: bool, auto_step := true) -> void:
	var state:=_sender()
	if state==null or not _spend_budget(state) or not drive.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	state.input={"drive":drive.limit_length(),"yaw":wrapf(yaw,-PI,PI),"pitch":clampf(pitch,-1.49,1.49),"held":held_keys & key_mask,"enabled":enabled,"auto_step":auto_step}
	state.input.third_person = (held_keys & THIRD_PERSON_HELD_BIT) != 0
	state.updated_at=Time.get_ticks_msec()

@rpc("any_peer","call_remote","reliable",2)
func _edges(buttons: int) -> void:
	var state:=_sender()
	if state!=null and _spend_budget(state):
		state.pressed |= buttons & key_mask

func _bit(id: String) -> int:
	var index:=KEYS.find(id)
	return 0 if index<0 else 1<<index

func remote_button(mode: String,id: String) -> bool:
	return (int(current_input().get(mode,0)) & _bit(id))!=0

func host_tick(session: WastelandSession,delta:float) -> void:
	if not server(): return
	var joined:=joined_members()
	# Do not publish a frame until every player's authoritative simulation has
	# run; every recipient sees the same tick of the rest of the team.
	for state:MemberState in joined:
		_tick_member(session,state,delta)
	_save_requested_guests(session,joined)
	var party:Array=[]
	for state:MemberState in joined:
		state.fast_timer-=delta
		state.slow_timer-=delta
		if state.fast_timer<=0.0:
			state.fast_timer=0.064
			if party.is_empty(): party=_party_motion(session,joined)
			_send_fast(session,state,party)
		if state.slow_timer<=0.0:
			state.slow_timer=0.61
			_send_world(session,state)
			_send_slow_details(session,state)

func _save_requested_guests(session:WastelandSession,joined:Array[MemberState])->void:
	var now:=Time.get_ticks_msec()
	if now<next_guest_save: return
	var requests:=joined.filter(func(member:MemberState): return member.save_requested)
	if requests.is_empty(): return
	next_guest_save=now+3000
	var result:=session.save_now(false)
	for state:MemberState in requests:
		state.save_requested=false
		_save_result.rpc_id(state.peer_id,result)

@rpc("authority","call_remote","reliable",0)
func _save_result(result:int)->void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.connection_notice("世界已保存" if result==OK else "保存失败 · 错误 %d" % result)

func _tick_member(session:WastelandSession,state:MemberState,delta:float)->void:
	var member:=state.survivor
	state.budget_tick+=delta
	if state.budget_tick>=1.0:
		state.activity_budget=0
		state.budget_tick=0.0
	if not state.downed and not state.hand_queue.is_empty() and float(state.hand_queue[0].done)<=session.clock.elapsed:
		_as_member(session,state,session._finish_crafting)
	if not state.input.is_empty():
		var nearby:=member.global_position.distance_to(session.player.global_position)<84.0
		var fresh:=Time.get_ticks_msec()-state.updated_at<750
		state.input.pressed=state.pressed if fresh else 0
		if not fresh:
			state.input.held=0
			state.input.drive=Vector2.ZERO
		var enabled:=bool(state.input.enabled) and not state.downed and fresh
		if not state.downed and not member.is_knocked_down():
			member.rotation.y=float(state.input.yaw)
			member.pitch=float(state.input.pitch)
			member.eyes.rotation.x=member.pitch
			member.third_person=bool(state.input.get("third_person",false))
		if not nearby and not state.downed and not member.is_knocked_down():
			var anchor:=_spawn_near_owner(session,state)
			member.dismount(true)
			member.global_position=anchor
			member.velocity=Vector3.ZERO
			_party_message.rpc_id(state.peer_id,"离队过远，已回到主机附近",2.7)
		if not state.downed:
			_as_member(session,state,func():
				member.simulate(delta,enabled)
				session.action_lock=maxf(0.0,session.action_lock-delta)
				session._tick_reload(delta)
				if enabled and not state.downed and not member.is_knocked_down():
					session._process_controls(delta))
		state.pressed=0
	var actions:=state.commands.duplicate()
	state.commands.clear()
	for action in actions:
		if action[0]=="revive" and state.downed:
			_reset_member(session,state)
		elif not state.downed:
			_as_member(session,state,func(): session.apply_ui_command(str(action[0]),action[1]))
	var avatar:=state.avatar
	if is_instance_valid(avatar):
		avatar.wear_loadout(state.bag.gear)
		avatar.set_offhand(state.bag.offhand,member.guarding,member.flashlight and not member.submerged)
		var upright := not state.downed and not member.is_knocked_down()
		avatar.visible=not state.appearance.is_empty() and upright and not is_instance_valid(member.mount_vehicle)
		avatar.set_seat_vehicle(member.mount_vehicle if upright else null)
		if upright and is_instance_valid(member.mount_vehicle):
			avatar.pose(delta,0.0,0.0,false,Vector3.INF,false,Vector3.UP,true)
		if not avatar.visible: return
		avatar.aim_pitch = member.pitch
		_avatar_motion(avatar,session.catalog,member.hand.model_id,member.hand.swing_serial,member.hand.shot_serial,int(state.bag.magazine.get(member.hand.model_id,0))>0)
		member.pose_ground_motion(delta)

func _send_slow_details(session:WastelandSession,state:MemberState)->void:
	_send_settled_poses(session,state)
	var trails:=session.hordes.trail_snapshot(state.survivor.global_position)
	var raw:=var_to_bytes(trails)
	var packed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
	while packed.size()>1000 and trails.size()>1:
		trails.pop_back()
		raw=var_to_bytes(trails)
		packed=raw.compress(FileAccess.COMPRESSION_ZSTD)
	_trail_marks.rpc_id(state.peer_id,raw.size(),packed)
	var key:=session.chest_key(state.peer_id)
	if not key.is_empty():
		_as_member(session,state,func():
			var view:=session.chest_view(key)
			if hash(view)!=state.last_chest_state:
				state.last_chest_state=hash(view)
				_chest_update.rpc_id(state.peer_id,key,view)
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

func _capture_actor(session:WastelandSession,state:MemberState)->void:
	state.bag=session.bag
	state.hand_queue=session.hand_queue
	state.wire_endpoint=session.construction.selected_wire
	for key in CONTEXT: state.context[key]=session.get(key)

func _restore_actor(session:WastelandSession,state:MemberState)->void:
	session.player=state.survivor
	active_member=state if state.peer_id!=HOST_ID else null
	session.actor_peer_id=state.peer_id
	session.bag=state.bag
	session.hand_queue=state.hand_queue
	session.construction.selected_wire=state.wire_endpoint
	for key in CONTEXT: session.set(key,state.context[key])

func _as_member(session:WastelandSession,state:MemberState,callback:Callable)->void:
	if state==null or not is_instance_valid(state.survivor): return
	if session.player==state.survivor:
		callback.call()
		return
	var outermost:=owner_state==null
	if outermost:
		owner_state=MemberState.new(HOST_ID)
		owner_state.survivor=session.player
	var previous:=active_member if active_member!=null else owner_state
	_capture_actor(session,previous)
	_restore_actor(session,state)
	callback.call()
	_capture_actor(session,state)
	_restore_actor(session,previous)
	if outermost: owner_state=null

# Hits can occur while another guest's controls are being simulated. Switch to
# the actual victim's equipment and restore the interrupted actor afterward.
func as_survivor(session:WastelandSession,victim:WastelandSurvivor,callback:Callable)->bool:
	if not server() or session.player==victim: return false
	var state:=owner_state if owner_state!=null and owner_state.survivor==victim else member_for(victim)
	if state==null: return false
	_as_member(session,state,callback)
	return true

func survivor_fell(session: WastelandSession, person: WastelandSurvivor, mode: int, impact: Vector3) -> void:
	var member := member_for(person)
	var row := session.PartyFalls.capture(person,member.peer_id if member else HOST_ID,mode,impact)
	if not row.is_empty() and server():
		for guest in joined_members(): _survivor_fall.rpc_id(guest.peer_id,row)

@rpc("authority","call_remote","reliable",0)
func _survivor_fall(row: Dictionary) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		party_falls.apply(game.session,multiplayer.get_unique_id(),row)

func mirror_lake_combat(lake: WastelandLakeWildlife) -> void:
	var joined := joined_members()
	if joined.is_empty(): return
	var rows := lake.combat_snapshot()
	for member in joined:
		_lake_combat.rpc_id(member.peer_id,rows)

@rpc("authority","call_remote","reliable",0)
func _lake_combat(rows: Dictionary) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.stream.lake_wildlife.restore_combat(rows,true)

func mirror_player_hit(person: WastelandSurvivor, impact: Vector3, at: Vector3, bone: StringName) -> void:
	var owner := member_for(person)
	var peer := owner.peer_id if owner else HOST_ID
	for guest in joined_members(): _part_hit.rpc_id(guest.peer_id,peer,impact,at,bone)

@rpc("authority","call_remote","reliable",0)
func _part_hit(peer: int, impact: Vector3, at: Vector3, bone: StringName) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica: return
	if peer == multiplayer.get_unique_id():
		game.session.player.sync_part_hit(impact,at,bone)
	elif party_falls.current.has(peer):
		var body = party_falls.bodies.get(party_falls.current[peer])
		if is_instance_valid(body): body.push(impact,at,bone)
	else:
		var avatar := replica_avatar(peer)
		if is_instance_valid(avatar): avatar.push_part(impact,at,bone)

func mirror_corpse_hit(hit: Dictionary) -> void:
	for member in joined_members():
		# A body can come to rest again between slow frames.
		if hit.kind == "creature": member.settled_sent.erase(hit.id)
		elif hit.kind == "survivor": member.settled_sent.erase(-int(hit.id))
		_corpse_hit.rpc_id(member.peer_id,hit)

@rpc("authority","call_remote","reliable",0)
func _corpse_hit(hit: Dictionary) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica: return
	var rig: Node3D
	match hit.kind:
		"survivor":
			var body = party_falls.bodies.get(hit.id)
			if is_instance_valid(body): rig = body.physics
		"creature":
			var actor: WastelandCreature = smooth_actors.get(hit.id)
			if is_instance_valid(actor): rig = actor.ragdoll
		"lake":
			var body: Dictionary = game.session.stream.lake_wildlife.combat.bodies.get(hit.id,{})
			rig = body.get("rig")
	if is_instance_valid(rig): rig.kick_at(hit.impulse,hit.at,hit.bone)

# The initial impact runs immediately on each machine. Only the final resting
# pose needs a joint snapshot, including for peers who approach a corpse later.
func _send_settled_poses(session: WastelandSession, state: MemberState) -> void:
	var nearby := {}
	for actor: WastelandCreature in session.hordes.corpses:
		if actor.physical_position().distance_squared_to(state.survivor.global_position) > 105.0*105.0:
			continue
		var id := actor.spawn_serial
		if actor.ragdoll_settled():
			nearby[id] = true
			if not state.settled_sent.has(id):
				_resting_pose.rpc_id(state.peer_id,id,actor.ragdoll_pose(),_creature_frame(actor))
	for body in session.get_tree().get_nodes_in_group(party_falls.GROUP):
		if not session.is_ancestor_of(body) or body.is_queued_for_deletion() or body.remaining <= 0.0 or not body.physics.is_settled():
			continue
		var id := -body.get_instance_id()
		nearby[id] = true
		if not state.settled_sent.has(id):
			_resting_pose.rpc_id(state.peer_id,id,body.physics.pose_snapshot())
	state.settled_sent = nearby

@rpc("authority","call_remote","reliable",0)
func _resting_pose(id: int, pose: PackedFloat32Array, creature_frame: Array = []) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica or pose.is_empty():
		return
	if id < 0:
		var body = party_falls.bodies.get(-id)
		if is_instance_valid(body): body.physics.apply_pose(pose)
	else:
		# Actor pages travel on an independent channel and may arrive after this RPC.
		var now := Time.get_ticks_msec()
		for serial in resting_creatures.keys():
			if resting_creatures[serial].expires < now: resting_creatures.erase(serial)
		if creature_frame.size() > 24:
			resting_creatures[id] = {"pose":pose, "frame":creature_frame,
				"expires":now + int(WastelandCreature.CORPSE_SECONDS * 1000) + 2000}

func member_failed(state:MemberState) -> void:
	if not server() or state.downed:
		return
	state.downed=true
	var member:=state.survivor
	member.begin_death_ragdoll()
	member.session.chest_leave(state.peer_id)
	member.session.construction.tool_jobs.erase(member.get_instance_id())
	state.pressed=0
	state.commands.clear()
	member.collision_layer=0
	member.collision_mask=0
	if is_instance_valid(member.mount_vehicle):
		member.dismount(true)
		member.collision_layer=0
		member.collision_mask=0
	_member_down.rpc_id(state.peer_id)

func _reset_member(session:WastelandSession,state:MemberState) -> void:
	state.downed=false
	var member:=state.survivor
	member.reset_ragdoll()
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
	member.global_position=_spawn_near_owner(session,state)
	member.velocity=Vector3.ZERO
	_revived.rpc_id(state.peer_id)

@rpc("authority","call_remote","reliable",0)
func _member_down() -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.death_screen=true
		game._failure()

@rpc("authority","call_remote","reliable",0)
func _revived() -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.death_screen=false
		game.session.player.reset_ragdoll()
		game.session.player.clear_damage_feedback()
		game.session.player.reset_water_state()
		game.close_overlay()

func send_member_damage(victim: WastelandSurvivor, before: float, loss: float, source: String, bearing: Vector3, direct: bool) -> bool:
	if not server(): return false
	var state:=member_for(victim)
	if state==null: return false
	_member_damage.rpc_id(state.peer_id,before,loss,source,bearing,direct)
	return true

@rpc("authority","call_remote","reliable",0)
func _member_damage(before: float, loss: float, source: String, bearing: Vector3, direct: bool) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.player.show_damage(before, loss, source, bearing, direct)

func tell(words:String, duration:float) -> void:
	if not server(): return
	if active_member!=null: _party_message.rpc_id(active_member.peer_id,words,duration)
	else: broadcast_message(words,duration)

func broadcast_message(words:String,duration:float,except_peer:=0)->void:
	if not server(): return
	for state:MemberState in joined_members():
		if state.peer_id!=except_peer: _party_message.rpc_id(state.peer_id,words,duration)

func broadcast_chat(sender: String, text: String) -> void:
	if not server(): return
	for state: MemberState in joined_members():
		_party_chat.rpc_id(state.peer_id,sender,text)

@rpc("authority","call_remote","reliable",0)
func _party_chat(sender: String, text: String) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.chat_received.emit(sender,text)

func panel_for_member(id: String, context: Variant) -> void:
	if not server(): return
	if active_member!=null:
		if id=="chest":
			var view:Dictionary=game.session.chest_view(str(context))
			active_member.last_chest_state=hash(view)
			_party_panel.rpc_id(active_member.peer_id,id,view)
		else: _party_panel.rpc_id(active_member.peer_id,id,context)
	elif id!="chest":
		for state:MemberState in joined_members(): _party_panel.rpc_id(state.peer_id,id,context)

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
	if not server() or key not in EFFECTS: return
	for state:MemberState in joined_members():
		if state.survivor.global_position.distance_squared_to(point)<76.0*76.0:
			_effect.rpc_id(state.peer_id,key,point,loudness)

func broadcast_shawl(speaker: WastelandSurvivor, action_text: String) -> void:
	if not server(): return
	var session: WastelandSession = game.session
	var member := member_for(speaker)
	var speaker_name: String = member.nickname if member != null else game.options.player_name
	var at := speaker.global_position
	const HEARING_DISTANCE_SQUARED := 24.0 * 24.0
	if owner_player(session).global_position.distance_squared_to(at) <= HEARING_DISTANCE_SQUARED:
		session.show_shawl_caption(speaker_name, action_text, at)
	for listener in joined_members():
		if listener.survivor.global_position.distance_squared_to(at) <= HEARING_DISTANCE_SQUARED:
			_shawl_caption.rpc_id(listener.peer_id, speaker_name, action_text, at)

@rpc("authority","call_remote","reliable",0)
func _shawl_caption(speaker_name: String, action_text: String, at: Vector3) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.show_shawl_caption(speaker_name, action_text, at)

@rpc("authority","call_remote","unreliable",0)
func _effect(key:String,point:Vector3,loudness:float) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica and key in EFFECTS:
		game.session.audio.play_at(key,point,loudness)

func mirror_collapse(cells: Array[Vector3i]) -> void:
	if not server(): return
	for state:MemberState in joined_members():
		var nearby := cells.filter(func(cell): return WastelandConstruction.position_of(cell).distance_squared_to(state.survivor.global_position)<75.0*75.0)
		if not nearby.is_empty(): _falling_blocks.rpc_id(state.peer_id,nearby)

func mirror_canopy(model: String, variant: int, pose: Transform3D, salt: int, count: int, impulse: Vector3) -> void:
	if not server(): return
	for state:MemberState in joined_members():
		if state.survivor.global_position.distance_squared_to(pose.origin)<65.0*65.0:
			_canopy.rpc_id(state.peer_id,model,variant,pose,salt,count,impulse)

@rpc("authority","call_remote","unreliable",0)
func _canopy(model: String, variant: int, pose: Transform3D, salt: int, count: int, impulse: Vector3) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.timber.litter.shed(model,variant,pose,salt,count,impulse)

@rpc("authority","call_remote","reliable",1)
func _falling_blocks(cells: Array) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.construction.show_collapse(cells)

func mirror_acid(row: Dictionary) -> void:
	if not server(): return
	for state:MemberState in joined_members():
		if state.survivor.global_position.distance_squared_to(row.at)<70.0*70.0:
			_acid_fx.rpc_id(state.peer_id,row)

@rpc("authority","call_remote","reliable",0)
func _acid_fx(row: Dictionary) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.fx.receive_acid(row)

func mirror_infected_effect(kind: String, point: Vector3, normal: Vector3) -> void:
	if not server(): return
	for state:MemberState in joined_members():
		if state.survivor.global_position.distance_squared_to(point)<70.0*70.0:
			_infected_fx.rpc_id(state.peer_id,kind,point,normal)

@rpc("authority","call_remote","reliable",0)
func _infected_fx(kind: String, point: Vector3, normal: Vector3) -> void:
	if not host and is_instance_valid(game.session) and game.session.replica:
		game.session.fx.infected_effect(kind,point,normal)

func _party_motion(session:WastelandSession,joined:Array[MemberState])->Array:
	var rows:Array=[_motion_row(HOST_ID,session.player,session.bag,session.death_screen)]
	for state:MemberState in joined:
		rows.append(_motion_row(state.peer_id,state.survivor,state.bag,state.downed))
	return rows

func _motion_row(peer:int,person:WastelandSurvivor,bag:WastelandBag,downed:bool)->Array:
	var row := [peer,person.global_position,person.rotation.y,Vector2(person.velocity.x,person.velocity.z).length(),person.crouch,person.swimming,
		downed or person.is_knocked_down() or is_instance_valid(person.mount_vehicle),person.hand.model_id,person.hand.swing_serial,person.hand.shot_serial,bag.offhand,person.guarding,
		person.flashlight and not person.submerged,person.headlamp.visible,person.eyes.position.y,person.pitch,int(bag.magazine.get(person.hand.model_id,0))>0]
	if is_instance_valid(person.mount_vehicle) and not downed and not person.is_knocked_down(): row.append(person.mount_vehicle.id)
	return row

func _send_fast(session: WastelandSession,state:MemberState,party:Array) -> void:
	var member:=state.survivor
	var actors: Array=[]
	for actor: WastelandCreature in session.hordes.alive + session.hordes.corpses:
		if not actor.active or actor.physical_position().distance_squared_to(member.global_position)>105.0*105.0:
			continue
		if state.settled_sent.has(actor.spawn_serial) and actor.ragdoll_settled():
			actors.append([actor.spawn_serial])
		else:
			actors.append(_creature_frame(actor))
	var row := {"time":session.clock.hours,"elapsed":session.clock.elapsed,
		"member_guard":member.guarding,
		"member_swings":member.hand.swing_serial,"member_shots":member.hand.shot_serial,"swing_power":member.hand.swing_force,
		"submerged":member.submerged,"swimming":member.swimming,"wet_feet":member.wet_feet,
		"active":state.bag.active,"hint":state.context.hint,"loot":state.context.loot_ratio,"target_hp":state.context.focus_damage,
		"confirm":Vector3i(member.confirmed_hit,int(member.confirmed_head),int(member.confirmed_melee)),"noise":Vector2(member.recent_noise,member.noise_until),
		"shape":state.context.shape,"turn":state.context.turn,"wave":session.hordes.wave_index,
		"ride":member.mount_vehicle.id if is_instance_valid(member.mount_vehicle) else "","charge":state.context.heavy_charge,
		"reload":clampf(float(state.context.reload_left)/maxf(0.01,float(state.context.reload_span)),0.0,1.0) if not str(state.context.reload_id).is_empty() else 0.0}
	# Positional wire fields omit repeated names without changing the save schema.
	_frame.rpc_id(state.peer_id,_values(row,FRAME_FIELDS),_values(member.snapshot(),PLAYER_FIELDS),_values(row,MOTION_FIELDS))
	# Keep the party packet separate from personal vitals to limit fragmentation.
	_party_frame.rpc_id(state.peer_id,party.filter(func(entry): return int(entry[0])!=state.peer_id))
	state.actor_frame+=1
	var count := maxi(1,ceili(float(actors.size())/ACTORS_PER_PAGE))
	for page in count:
		_actor_page.rpc_id(state.peer_id,state.actor_frame,page,count,actors.slice(page*ACTORS_PER_PAGE,(page+1)*ACTORS_PER_PAGE))

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

@rpc("authority","call_remote","unreliable_ordered",2)
func _party_frame(rows:Array)->void:
	if host or not is_instance_valid(game.session) or not game.session.replica or rows.size()>MAX_PLAYERS-1: return
	for values in rows:
		if not values is Array or values.size()<PARTY_FIELDS.size() or values.size()>PARTY_FIELDS.size()+1: continue
		var seated: bool = values.size()>PARTY_FIELDS.size()
		if seated and not values.back() is String: continue
		var view:ReplicaMember=replicas.get(values[0])
		if view==null: continue
		var motion:Dictionary={}
		_unpack(motion,PARTY_FIELDS,values)
		motion.ride = values.back() if seated else ""
		if view.motion.is_empty():
			view.avatar.global_position = motion.at
			view.avatar.rotation.y = motion.yaw
		view.motion=motion

@rpc("authority","call_remote","unreliable",1)
func _actor_page(serial: int, page: int, count: int, rows: Array) -> void:
	if host or not is_instance_valid(game.session) or not game.session.replica:
		return
	if serial<=applied_actor_frame or count<1 or count>128 or page<0 or page>=count or rows.size()>ACTORS_PER_PAGE:
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

func _send_world(session:WastelandSession,state:MemberState) -> void:
	var member:=state.survivor
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
	var loadouts:Dictionary={HOST_ID:session.bag.gear}
	for teammate:MemberState in joined_members():
		if teammate!=state: loadouts[teammate.peer_id]=teammate.bag.gear
	var snapshot: Dictionary={"diffs":chunks,"digs":excavations,"blocks":blocks,"crops":crops,"wires":wires,
		"bag":state.bag.snapshot(),"loadouts":loadouts,"progress":session.progress.snapshot(),"queue":state.hand_queue,
		"vehicles":_near_records(session.vehicle_records,member.global_position),"drops":session.fx.nearby_drops(member.global_position,142.0),
		"markers":session.marker_records,"discovered":session.stream.discovered,"powered":session.construction.powered}
	snapshot.falling_trees=session.timber.snapshot()
	snapshot.lids=session.chest_lids()
	snapshot.threat=session.hordes.regional_snapshot(location)
	var fingerprint:=hash(snapshot)
	if fingerprint==state.manifest_hash:
		return
	var bytes:=var_to_bytes(snapshot)
	if bytes.size()<=MAX_PACKET:
		state.manifest_hash=fingerprint
		_manifest.rpc_id(state.peer_id,bytes.size(),bytes.compress(FileAccess.COMPRESSION_ZSTD))

func _near_records(rows:Dictionary,point:Vector3) -> Dictionary:
	var result:Dictionary={}
	for id in rows:
		var row:Dictionary=rows[id]
		if (row.point as Vector3).distance_squared_to(point)<142.0*142.0:
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
	session.bag.restore(row.bag,false)
	session.hand_queue=row.queue
	for peer:int in row.loadouts:
		var view:ReplicaMember=replicas.get(peer)
		if view!=null: view.avatar.wear_loadout(row.loadouts[peer])
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
	var can_act := session.controls_enabled and not session.death_screen and not p.is_knocked_down()
	if can_act:
		p.read_view_input()
		p.look(p._stick_look()*Vector2(2.7,-2.16 if session.options.display.invert_y else 2.16)*dt)
	var buttons:=0
	var held:=THIRD_PERSON_HELD_BIT if p.third_person else 0
	if can_act:
		for i in range(KEYS.size()):
			if Input.is_action_just_pressed(KEYS[i]):
				buttons|=1<<i
			if session.action_held(KEYS[i]):
				held|=1<<i
	local_pressed|=buttons
	client_timer-=dt
	if client_timer<=0.0:
		client_timer=0.045
		var axis:=Input.get_vector("left","right","up","down") if can_act else Vector2.ZERO
		_pilot.rpc_id(HOST_ID,axis,p.rotation.y,p.pitch,held,can_act,bool(session.options.display.auto_step))
		if local_pressed!=0:
			_edges.rpc_id(HOST_ID,local_pressed)
			local_pressed=0
	if replica_state.is_empty():
		_pose_party(session,dt)
		return
	var speed := p.global_position.distance_to(replica_position) / maxf(0.001,dt)
	p.global_position=p.global_position.lerp(replica_position,1.0 if speed>350.0 else minf(1.0,dt*13.0))
	var row:=replica_state
	p.mount_vehicle = session.vehicles.get(str(row.get("ride", "")))
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
	p.sync_view_lantern(session.bag.offhand)
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
	p.animate_hands(dt,session.atmosphere.sun_strength,minf(3.0,speed*0.11))
	p.update_ragdoll_camera(dt)
	p.update_live_avatar(dt)
	p.hit_stop=maxf(0,p.hit_stop-dt)
	_pose_party(session,dt)
	_pose_actors(session,replica_actors,dt)
	session.fx.simulate_projectiles(dt)
	session.fx.present_drops(dt)

func _pose_party(session:WastelandSession,dt:float)->void:
	for view:ReplicaMember in replicas.values():
		if view.motion.is_empty(): continue
		var row:=view.motion
		var avatar:=view.avatar
		var ride := str(row.get("ride",""))
		var down := party_falls.current.has(row.peer) or (bool(row.hidden) and ride.is_empty())
		avatar.visible = not down and ride.is_empty()
		if down:
			avatar.set_seat_vehicle(null)
			view.lamp.hide()
			continue
		var previous := avatar.global_position
		avatar.global_position=avatar.global_position.lerp(row.at,1.0 if avatar.global_position.distance_to(row.at)>12.0 else minf(1.0,dt*12.0))
		avatar.rotation.y=lerp_angle(avatar.rotation.y,float(row.yaw),minf(1.0,dt*14.0))
		avatar.set_seat_vehicle(session.vehicles.get(ride))
		if not ride.is_empty():
			avatar.pose(dt,0.0,0.0,false,Vector3.INF,false,Vector3.UP,true)
			view.lamp.hide()
			continue
		avatar.set_offhand(row.offhand,row.guard,row.flame)
		var held:=str(row.held)
		avatar.aim_pitch = float(row.pitch)
		_avatar_motion(avatar,session.catalog,held,int(row.swings),int(row.shots),bool(row.loaded))
		var travel := avatar.global_position - previous
		var motion := (travel / maxf(dt, 0.001)).limit_length(12.0) if travel.length_squared() < 2.25 else Vector3.ZERO
		avatar.pose_replica(dt,motion,float(row.duck),bool(row.swim))
		view.lamp.position.y=float(row.eye)
		view.lamp.rotation.x=float(row.pitch)
		view.lamp.visible=bool(row.lamp) and avatar.visible

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
	avatar.mainhand_kind = str(catalog.items.get(held,{}).get("kind",""))
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

func _creature_frame(actor: WastelandCreature) -> Array:
	var row := [actor.spawn_serial, actor.type, actor.global_position, actor.rotation.y, actor.hp, actor.velocity,
		actor.attack, actor.hurt, actor.windup, int(actor.attack_kind), actor.alerted, actor.morph,
		actor.look_index, actor.wardrobe_index, actor.limb_index, actor.face_variant,
		int(actor.brain.state), actor.brain.state_left, actor.brain.wake_span, actor.brain.rage_left,
		actor.stage_health, actor.screamed, actor.limp_left,_actor_motion(actor)]
	if actor.ragdoll != null or actor.limb_hit_serial > 0:
		row.append_array([actor.ragdoll_impact,actor.ragdoll_hit_at,actor.ragdoll_hit_bone,actor.limb_hit_serial])
		if actor.fall.from_fall: row.append(actor.fall.launch_velocity)
	return row

func _pose_actors(session:WastelandSession,rows:Array,delta:float) -> void:
	actors_now.clear()
	var fresh_frame := posed_actor_frame != applied_actor_frame
	posed_actor_frame=applied_actor_frame
	for tuple in rows:
		var id:int=tuple[0]
		var pose := PackedFloat32Array()
		var at_rest: bool = tuple.size() == 1
		if at_rest:
			actors_now[id] = true
			if not resting_creatures.has(id): continue
			if smooth_actors.has(id) and smooth_actors[id].get_meta("rest_frame",-1) == resting_creatures[id].expires:
				var resting: WastelandCreature = smooth_actors[id]
				if resting.cloth_motion and resting.ragdoll_settled(): resting.cloth_motion.tick_resting(delta)
				continue
			tuple = resting_creatures[id].frame
			pose = resting_creatures[id].pose
		var spawning := not smooth_actors.has(id)
		if spawning:
			var actor: WastelandCreature = session.hordes.acquire_actor(tuple[1])
			if actor:
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
		if not smooth_actors.has(id):
			continue
		var actor:WastelandCreature=smooth_actors[id]
		if at_rest:
			actor.set_meta("rest_frame",resting_creatures[id].expires)
		elif actor.has_meta("rest_frame"):
			actor.remove_meta("rest_frame")
			if actor.ragdoll != null: actor.ragdoll.kick(Vector3.ZERO)
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
		actor.sync_ragdoll(pose,tuple[24] if tuple.size() > 24 else Vector3.ZERO,
			tuple[25] if tuple.size() > 25 else Vector3.INF,tuple[26] if tuple.size() > 26 else &"",tuple[28] if tuple.size()>28 else Vector3.INF)
		if tuple.size() > 27 and (fresh_frame or spawning):
			if spawning: actor.limb_hit_serial = tuple[27]
			else: actor.mirror_limb_hit(tuple[27],tuple[24],tuple[25],tuple[26])
		actor._pose(delta,actor.global_position.distance_to(session.player.global_position),travel)
	for id in smooth_actors.keys():
		if not actors_now.has(id):
			if smooth_actors[id].has_meta("rest_frame"):
				smooth_actors[id].remove_meta("rest_frame")
			session.hordes.release(smooth_actors[id])
			smooth_actors.erase(id)
