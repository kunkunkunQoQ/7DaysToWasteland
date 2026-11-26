extends RefCounted

const LAND := ["meadow","taiga","alpine","desert","mesa","marsh","canyon"]
const CAT_OUTFIT := ["meme_ears","meme_whiskers","meme_tail","meme_claws"]
const CHAT_WINDOW_MS := 60000
static var ANIMALS: Array = WastelandHordes.WILDLIFE + ["heron","lake_fish","pond_turtle","crayfish"]
var entries: Array = []
var by_id := {}
var session: Node
var caption := ""
var caption_until := 0
var next_check := 0.0
var recent_chat: Array[Dictionary] = []

func configure(world: Node) -> void:
	session=world
	entries=session.catalog.achievements
	for row: Dictionary in entries: by_id[row.id]=row

func unlocked(id: String) -> bool:
	return session.progress.achieved.has(id)

func rewarded(id: String) -> bool:
	return unlocked(id) and by_id[id].reward!=""

func amount(id: String) -> int:
	var row: Dictionary=by_id[id]
	if unlocked(id): return row.target
	return clampi(_metric(row.metric),0,int(row.target))

func _metric(key: String) -> int:
	var p: WastelandProgression=session.progress
	match key:
		"jobs": return p.job
		"day": return session.clock.day()
		"chunks": return session.stream.discovered.size()
		"biomes": return _seen("region_",LAND)
		"species": return _seen("observe_",ANIMALS)
		"young_species": return _seen("observe_",ANIMALS,"_young")
		"wrecks": return _seen("recover_",["ferry","pump","bridge"])
		"relics":
			var total:=0
			for row: Dictionary in entries:
				if row.reward not in ["","meme_clock","meme_shawl"] and p.records.has("owned_"+str(row.reward)): total+=1
			return total
	return int(p.records.get(key,0))

func _seen(prefix: String, keys: Array, suffix := "") -> int:
	var found:=0
	for id: String in keys:
		if session.progress.records.has(prefix+id+suffix): found+=1
	return found

func add(key: String, quantity := 1.0) -> void:
	if session==null or session.replica or quantity<=0.0: return
	var counters: Dictionary=session.progress.records
	counters[key]=float(counters.get(key,0.0))+quantity

func mark(key: String, value := 1.0) -> void:
	if session==null or session.replica: return
	var counters: Dictionary=session.progress.records
	if value>float(counters.get(key,0.0)): counters[key]=value

func acquired_item(id: String) -> void:
	if id.begins_with("meme_"): mark("owned_"+id)

func record_chat(speaker: String, text: String, now_ms := Time.get_ticks_msec()) -> void:
	if session == null or session.replica or not by_id.has("shiver_chat"): return
	var claimed := "shiver_chat_awarded_" + speaker
	if session.progress.records.has(claimed) or text.is_empty(): return
	var distinct := 1
	for index in range(recent_chat.size()-1,-1,-1):
		var line := recent_chat[index]
		if now_ms-int(line.at) > CHAT_WINDOW_MS or (line.speaker == speaker and line.text == text):
			recent_chat.remove_at(index)
		elif line.speaker == speaker:
			distinct += 1
	var row: Dictionary = by_id.shiver_chat
	mark(row.metric,distinct)
	if distinct < int(row.target):
		recent_chat.append({"speaker":speaker,"text":text,"at":now_ms})
		return
	# The achievement belongs to the world. Each speaker earns their own copy.
	session.progress.records[claimed] = 1
	if not unlocked(row.id):
		session.progress.achieved[row.id] = session.clock.day()
		_announce_unlocks([row.id])
	session.award({row.reward:1},session.player.global_position)
	session.notify("已获得 " + session.catalog.title(row.reward))
	session._schedule_world_save()

func tick(delta: float) -> void:
	next_check-=delta
	if next_check>0: return
	next_check=0.75
	refresh()

func refresh() -> void:
	if session==null or session.replica or not is_instance_valid(session.player): return
	var bag: WastelandBag=session.bag
	var earned: Array[String]=[]
	if not session.progress.records.has("full_cat"):
		if CAT_OUTFIT.all(bag.is_worn):
			mark("full_cat")
		elif is_instance_valid(session.network) and session.network.server():
			for guest: WastelandLan.MemberState in session.network.joined_members():
				if CAT_OUTFIT.all(guest.bag.is_worn):
					mark("full_cat")
					break
	for row: Dictionary in entries:
		var reward: String=row.reward
		if reward!="" and bag.count(reward)>0: mark("owned_"+reward)
		if unlocked(row.id) or _metric(row.metric)<int(row.target): continue
		session.progress.achieved[row.id]=session.clock.day()
		if reward!="":
			session.award({reward:1},session.player.global_position)
		earned.append(row.id)
	_announce_unlocks(earned)

func _announce_unlocks(earned: Array) -> void:
	announce(earned)
	if not earned.is_empty() and session.slot>0:
		preload("res://game/core/atlas_unlocks.gd").remember(WastelandSave.save_root(),earned)

func announce(ids: Array) -> void:
	if ids.is_empty(): return
	var entry: Dictionary=by_id.get(ids.back(),{})
	if entry.is_empty(): return
	caption="成就达成　"+str(entry.name)
	if entry.reward!="": caption+="　·　"+session.catalog.title(entry.reward)
	if ids.size()>1: caption+="　+%d" % (ids.size()-1)
	caption_until=Time.get_ticks_msec()+4600

func crouched(p: WastelandSurvivor, holding: String) -> void:
	var gen: WastelandTerrainGen=session.stream.generator
	var at:=p.global_position
	if holding=="wood" and gen.region_kind(at.x,at.z)=="taiga": add("forest_squat")
	if gen.site_for(WastelandTerrainGen.chunk_at(Vector2(at.x,at.z)))=="tower": add("tower_squat")

func _streak(p: WastelandSurvivor, key: String, active: bool, dt: float) -> void:
	var value: float=float(p.challenge_streaks.get(key,0.0))+dt if active else 0.0
	p.challenge_streaks[key]=value
	if active: mark(key,value)

func sample(p: WastelandSurvivor, delta: float, controls: bool, drive: Vector2) -> void:
	if session==null or session.replica: return
	if not controls:
		p.challenge_interval=0.0
		p.challenge_streaks.clear()
		p.challenge_position=Vector3.INF
		return
	p.challenge_interval+=delta
	if p.challenge_interval<0.25: return
	var dt:=p.challenge_interval
	p.challenge_interval=0.0
	var at:=p.global_position
	var last:=p.challenge_position
	p.challenge_position=at
	var metres:=Vector2(at.x-last.x,at.z-last.z).length() if last.is_finite() else 0.0
	if metres>dt*12.0: metres=0.0
	var gen: WastelandTerrainGen=session.stream.generator
	var area:=gen.region_kind(at.x,at.z)
	var held: String=session.bag.current()
	var hour:=fposmod(float(session.clock.hours),24.0)
	var night:=hour<5.0 or hour>=21.0
	var glass: bool=held=="field_glasses" and session.action_held("alternate")
	if area in LAND: mark("region_"+area)
	if area=="alpine" and at.y>=60.0 and p.is_on_floor(): mark("snow_peak")
	if p.submerged: add("underwater_s",dt)
	if p.swimming:
		if area=="desert": mark("oasis_swim")
		if held=="filter_pump": add("swim_pump_s",dt)
		if drive.y>0.6: add("reverse_swim_m",metres)
	elif p.crouch>0.8 and (session.bag.is_worn("meme_ears") or session.bag.is_worn("meme_whiskers")):
		add("cat_stalk_m",metres)
	if glass and night and session.bag.is_worn("meme_shades"): add("dark_glasses",dt)
	_streak(p,"star_watch",glass and night and area=="desert" and p.pitch>0.65,dt)
	_streak(p,"storm_signal",held=="torch" and session.atmosphere.weather_kind==3 and p.pitch>0.65,dt)
	_streak(p,"human_sign",not night and held=="" and drive.is_zero_approx() and metres<0.12 and p.is_on_floor() and gen.road_strength(at.x,at.z)>0.75,dt)
