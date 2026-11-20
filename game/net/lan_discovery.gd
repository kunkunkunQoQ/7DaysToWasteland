extends RefCounted

signal changed

const PORT := 47357
const PORT_COUNT := 4
const MAX_PLAYERS := 6
const QUERY := "7DW/find/2"
const ANSWER := "7DW/room/2"
const INTERVAL := 1500
const EXPIRY := 5500
var browser: PacketPeerUDP
var announcer: PacketPeerUDP
var rooms := {}
var seen := {}
var room_id := ""
var next_scan := 0
var next_bind := 0

func advertise() -> void:
	if announcer != null or Time.get_ticks_msec() < next_bind: return
	next_bind = Time.get_ticks_msec()+EXPIRY
	var socket := PacketPeerUDP.new()
	for offset in PORT_COUNT:
		if socket.bind(PORT+offset,"0.0.0.0") == OK:
			announcer = socket
			if room_id.is_empty(): room_id = Crypto.new().generate_random_bytes(8).hex_encode()
			return

func answer(address_ok: Callable, world: String, owner: String, day: int, port: int, players: int) -> void:
	advertise()
	if announcer == null: return
	for n in mini(32,announcer.get_available_packet_count()):
		var bytes := announcer.get_packet()
		var ip := announcer.get_packet_ip()
		var reply_port := announcer.get_packet_port()
		if bytes.size() != QUERY.length() or bytes.get_string_from_ascii() != QUERY or not address_ok.call(ip): continue
		var info := [ANSWER,room_id,ProjectSettings.get_setting("application/config/version"),world.left(48),owner.left(12),day,port,players]
		announcer.set_dest_address(ip,reply_port)
		announcer.put_packet(JSON.stringify(info).to_utf8_buffer())

func browse(address_ok: Callable) -> void:
	var now := Time.get_ticks_msec()
	if browser == null:
		if now < next_scan: return
		browser = PacketPeerUDP.new()
		if browser.bind(0,"0.0.0.0") != OK:
			browser = null
			next_scan = now+INTERVAL
			return
		browser.set_broadcast_enabled(true)
	if now >= next_scan:
		next_scan = now+INTERVAL
		for address: String in ["255.255.255.255","127.0.0.1"]:
			for offset in PORT_COUNT:
				browser.set_dest_address(address,PORT+offset)
				browser.put_packet(QUERY.to_ascii_buffer())
	var dirty := false
	for n in mini(48,browser.get_available_packet_count()):
		var bytes := browser.get_packet()
		var ip := browser.get_packet_ip()
		if bytes.size()>640 or not address_ok.call(ip): continue
		var row: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not row is Array or row.size()!=8 or row[0]!=ANSWER or not row[1] is String: continue
		var id: String = row[1]
		if id.length()!=16 or not id.is_valid_hex_number(false): continue
		if not row[2] is String or not row[3] is String or not row[4] is String: continue
		if typeof(row[5])!=TYPE_FLOAT or typeof(row[6])!=TYPE_FLOAT or typeof(row[7])!=TYPE_FLOAT: continue
		var port := int(row[6])
		if port<1024 or port>65535 or (not rooms.has(id) and rooms.size()>=64): continue
		var old: Dictionary = rooms.get(id,{})
		if not old.is_empty() and ip.begins_with("127."): ip = old.address
		var room := {"id":id,"version":row[2].left(16),"name":row[3].left(48),"owner":row[4].left(12),"day":maxi(1,int(row[5])),"port":port,"players":clampi(int(row[7]),1,MAX_PLAYERS),"address":ip}
		dirty = dirty or old != room
		rooms[id] = room
		seen[id] = now
	for id in seen.keys():
		if now-int(seen[id])>EXPIRY:
			seen.erase(id)
			rooms.erase(id)
			dirty=true
	if dirty: changed.emit()

func close() -> void:
	if browser != null: browser.close()
	if announcer != null: announcer.close()
	browser=null
	announcer=null
	next_scan=0
	next_bind=0
	room_id=""
	seen.clear()
	if not rooms.is_empty():
		rooms.clear()
		changed.emit()
