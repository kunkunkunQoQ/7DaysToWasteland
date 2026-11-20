class_name WastelandHordes
extends Node3D

const CAP := 30
const KINDS := ["walker", "feral_runner", "crawler", "radiant", "spitter", "brute", "screamer","mudwalker","sandrunner","bloater","bulwark","rimecaller"]
const WILDLIFE := ["stag", "boar", "fox", "hare", "wolf", "badger","argali","jerboa","otter"]
const WILDLIFE_CAP := 10
const SOUND_LIMIT := 24
const PATHS_PER_TICK := 3
const FORMATIONS := [
	{"name":"盾壳护鸣", "tip":"打断霜鸣，绕击盾壳", "pair":["bulwark","rimecaller"]},
	{"name":"酸囊群", "tip":"横移避酸，在远处击倒胀囊者", "pair":["spitter","bloater"]},
	{"name":"荧蚀侧袭", "tip":"留出退路，提防低处包抄", "pair":["radiant","crawler"], "flank":true},
	{"name":"工兵破障", "tip":"先击倒举锤工兵，守住缺口", "pair":["brute","crawler"]},
]
var session: Node3D
var pool: Array[WastelandCreature] = []
var alive: Array[WastelandCreature] = []
var rng := RandomNumberGenerator.new()
const RARE_ODDS := 50000
const TROPHIES := {
	"walker":["meme_shades","meme_traffic"], "crawler":["meme_fins","meme_duck"],
	"radiant":["meme_alien","meme_antenna"], "spitter":["meme_fins","meme_pot"],
	"brute":["meme_hammer","meme_traffic"], "screamer":["meme_antenna","meme_duck"],
	"bloater":["meme_pot","meme_duck"], "bulwark":["meme_pot","meme_hammer"], "rimecaller":["meme_antenna","meme_alien"],
	"stag":["meme_ears","meme_antenna"], "boar":["meme_pot","meme_hammer"],
	"fox":["meme_tail","meme_whiskers"], "hare":["meme_ears","meme_whiskers"],
	"wolf":["meme_claws","meme_tail"], "badger":["meme_claws","meme_shades"]}
var trophy_rng := RandomNumberGenerator.new()
var heat: Dictionary = {}
var fresh: Array = []
var event_day := 0
var wave_index := 0
var wave_total := 3
var assault_until := 0.0
var next_surge := 0.0
var assault_budget := 0.0
var opening_remaining := 0
var game_stage := 1
var spawn_ground := preload("res://game/sim/spawn_ground.gd").new()
var pack_requests: Array = []
var pack_cooldown := 0.0
var next_wave := 0.0
var approach_angle := 0.0
var approach_announced := false
var event_kills := 0
var herd_serial := 0
var next_herd := 0.0
var wildlife_count := 0
var next_patrol := 0.0
var next_heat := 0.0
var next_sim := 0.0
var survived_recorded := 0
var event_deaths := 0
var saw_event := false
var sounds: Array[Dictionary] = []
var sound_serial := 0
var spawn_serial := 0
var next_looks := {}
var actors_by_serial := {}
var path_budget := PATHS_PER_TICK

func configure(owner_session: Node3D, snapshot: Dictionary) -> void:
	session = owner_session
	var saved: Dictionary = snapshot.get("threat", {})
	heat = saved.get("heat", {}).duplicate(true)
	for key in heat:
		if float(heat[key].amount) >= 100.0:
			heat[key].amount = 0.0
			heat[key].pending = int(heat[key].get("pending", 0)) + 1
	fresh = saved.get("actors", []).duplicate(true)
	spawn_serial = int(saved.get("spawn_serial",0))
	next_looks = saved.get("next_looks", {}).duplicate()
	for row in fresh:
		spawn_serial = maxi(spawn_serial,int(row.get("serial",0)))
		if not row.has("look_index") and WastelandCreature.InfectedLooks.count_for(row.id) > 0:
			row.look_index = 0
		if row.id in KINDS and not row.has("wardrobe_index") and int(row.get("serial", 0)) <= 0:
			row.wardrobe_index = posmod(hash([session.world_settings.seed, row.id, row.at]), WastelandCreature.WARDROBE_COUNT)
		if row.id in KINDS and not row.has("limb_index"):
			row.limb_index = 0
		if not row.has("face_variant") and int(row.get("serial", 0)) <= 0:
			row.face_variant = hash([session.world_settings.seed, row.id, row.at, "face"]) & 1
	event_day = int(saved.get("event",0))
	wave_index = int(saved.get("wave",0))
	wave_total = int(saved.get("wave_total", 3))
	assault_until = float(saved.get("assault_until", 0.0))
	next_surge = float(saved.get("next_surge", 0.0))
	assault_budget = float(saved.get("assault_budget", 0.0))
	opening_remaining = int(saved.get("opening_remaining", 0))
	game_stage = int(saved.get("game_stage", 1))
	pack_requests = saved.get("pack_requests", []).duplicate(true)
	pack_cooldown = float(saved.get("pack_cooldown", 0.0))
	next_wave = float(saved.get("next",0.0))
	approach_angle = float(saved.get("approach_angle", 0.0))
	approach_announced = bool(saved.get("approach_announced", false))
	event_kills = int(saved.get("kills", 0))
	herd_serial = int(saved.get("herd_serial", 0))
	next_herd = float(saved.get("next_herd", 0.0))
	survived_recorded = int(saved.get("cleared",0))
	event_deaths = int(saved.get("died",0))
	rng.seed = int(session.world_settings.seed) ^ 0x38cba7
	trophy_rng.seed = int(session.world_settings.seed) ^ 0x727465
	if saved.has("trophy_rng"): trophy_rng.state = int(saved.trophy_rng)
	if saved.has("rng"):
		rng.state = int(saved.rng)
	for i in CAP + WILDLIFE_CAP:
		var actor := WastelandCreature.new()
		add_child(actor)
		actor.configure(self)
		pool.append(actor)

func snapshot() -> Dictionary:
	var actors := fresh.duplicate(true)
	for actor in alive:
		if actor.active:
			actors.append(actor.serialize())
	return {"heat":heat, "actors":actors, "spawn_serial":spawn_serial, "next_looks":next_looks.duplicate(), "event":event_day, "wave":wave_index, "next":next_wave,
		"cleared":survived_recorded, "died":event_deaths, "rng":rng.state,"trophy_rng":trophy_rng.state,
		"approach_angle":approach_angle, "approach_announced":approach_announced, "kills":event_kills,
		"herd_serial":herd_serial, "next_herd":next_herd, "game_stage":stage(),
		"wave_total":wave_total, "assault_until":assault_until, "next_surge":next_surge, "assault_budget":assault_budget,
		"opening_remaining":opening_remaining, "pack_requests":pack_requests.duplicate(true), "pack_cooldown":pack_cooldown}

func stage() -> int:
	var surviving: int = session.clock.day() - 1
	var level: int = session.progress.level
	if not session.replica:
		game_stage = floori((surviving * 1.5 + level * 1.2) * float(session.world_settings.difficulty))
	return game_stage

func active_cap(blood: bool) -> int:
	return mini(CAP if blood else CAP-6, (13 if blood else 7) + floori(stage() * (0.48 if blood else 0.29)))

func _health_scale() -> float:
	return 1.0 + minf(1.5, stage() * 0.016)

func regional_snapshot(region: Vector2i) -> Dictionary:
	var nearby := {}
	for key in heat:
		var at: Vector3 = heat[key].point
		var offset := (WastelandTerrainGen.chunk_at(Vector2(at.x, at.z)) - region).abs()
		if maxi(offset.x, offset.y) <= 6: nearby[key] = heat[key]
	return {"game_stage":stage(),"heat":nearby,"wave_total":wave_total,"next_wave":next_wave,"assault_until":assault_until}

func mirror_threat(row: Dictionary) -> void:
	game_stage = int(row.get("game_stage",game_stage))
	heat = row.get("heat",heat)
	wave_total = int(row.get("wave_total",wave_total))
	next_wave = float(row.get("next_wave",next_wave))
	assault_until = float(row.get("assault_until",assault_until))

func add_heat(at: Vector3, amount: float) -> void:
	var at_cell := WastelandTerrainGen.chunk_at(Vector2(at.x, at.z))
	var key := WastelandTerrainGen.grid_key(at_cell)
	var prior: Dictionary = heat.get(key, {"amount":0.0, "time":session.clock.elapsed, "point":at})
	_decay_heat(prior)
	prior.amount = clampf(float(prior.amount) + amount, 0.0, 100.0)
	prior.point = at
	heat[key] = prior
	if prior.amount >= 100.0:
		prior.amount = 0.0
		prior.pending = int(prior.get("pending",0)) + 1
		_heat_arrival(prior)

func _decay_heat(entry: Dictionary) -> void:
	var minutes := floori(maxf(0.0, session.clock.elapsed - float(entry.time)) / 60.0)
	if minutes > 0:
		entry.amount = maxf(0.0, float(entry.amount) - minutes * 6.0)
		entry.time = float(entry.time) + minutes * 60.0

func add_noise(at: Vector3, radius: float, from_player := true) -> void:
	sound_serial += 1
	if sounds.size() == SOUND_LIMIT:
		sounds.pop_front()
	sounds.append({"id": sound_serial, "point": at, "radius": radius, "from_player":from_player, "until": session.clock.elapsed + 2.4})

func spend_path_query() -> bool:
	if path_budget <= 0:
		return false
	path_budget -= 1
	return true

func simulate(delta: float) -> void:
	var player: WastelandSurvivor = session.player
	var teammates:Array[WastelandSurvivor]=session.living_players()
	teammates.erase(player)
	path_budget = PATHS_PER_TICK
	for actor in alive.duplicate():
		actor.think(delta,player,teammates)
	next_sim -= delta
	if next_sim > 0.0:
		return
	next_sim = 0.49
	while not sounds.is_empty() and float(sounds.front().until) < session.clock.elapsed:
		sounds.pop_front()
	for i in range(fresh.size() - 1, -1, -1):
		var row: Dictionary = fresh[i]
		if session.stream.at_surface(row.at) and (str(row.get("nest","")).is_empty() or session.team_distance_squared(row.at)<65.0*65.0):
			if _spawn(row.id, row.at, row.wave, row):
				fresh.remove_at(i)
	_activate_nests(player.global_position)
	for person:WastelandSurvivor in teammates: _activate_nests(person.global_position)
	if session.clock.horde_active():
		var day: int = session.clock.event_day()
		var warning:=14.0 if session.progress.records.has("exp_weather") else 6.0
		if event_day != day:
			event_day = day
			wave_index = 0
			wave_total = 4 if stage() >= 18 else 3
			assault_until = 0.0
			assault_budget = 0.0
			next_wave = session.clock.elapsed + (1.4 if day==session.clock.period else warning)
			event_deaths = 0
			event_kills = 0
			approach_announced = false
			session.audio.play_at("alarm", player.camera.global_position + Vector3(0,2,-4), 1.28, false)
			_announce("血月升起 · 守到 04:00", 6.0)
			var supplies:={}
			if session.progress.records.has("exp_well"): supplies.clean_water=2
			if session.progress.records.has("exp_bridge"): supplies.bandage=2
			if not supplies.is_empty():
				session.award(supplies,player.global_position)
				_announce("远征线路送达守夜补给 · "+session.catalog.requirements(supplies),5.0)
		saw_event = true
		if wave_index < wave_total and not approach_announced and session.clock.elapsed >= next_wave - warning:
			approach_angle = _select_approach(player.global_position)
			approach_announced = true
			var incoming := formation(day,wave_index+1)
			if wave_index > 0 or not incoming.is_empty():
				var bearings := ["东", "东南", "南", "西南", "西", "西北", "北", "东北"]
				var bearing: String = bearings[posmod(roundi(approach_angle / TAU * 8.0), 8)]
				if incoming.is_empty():
					_announce("第 %d 波 · %s方传来动静" % [wave_index + 1, bearing], 4.5)
				else:
					_announce("第%d波 · %s方%s · %s" % [wave_index+1,bearing,incoming.name,incoming.tip],warning)
		if wave_index < wave_total and session.clock.elapsed >= next_wave:
			_wave()
		elif wave_index > 0 and session.clock.elapsed < assault_until and session.clock.elapsed >= next_surge:
			_reinforce_wave()
	elif event_day > 0 and event_day != survived_recorded and (saw_event or session.clock.day() > event_day):
		for actor in alive:
			if actor.wave and actor.hp > 0.0:
				actor.wave = false
				actor.brain.retreat_from(player.global_position)
		# Deferred actors are outside the streamed world and can disperse immediately.
		fresh = fresh.filter(func(row): return not row.get("wave",false))
		assault_budget = 0.0
		survived_recorded = event_day
		if event_deaths == 0:
			var reward := 160 + stage() * 4
			session.gain(reward, "horde")
			_announce("第 %d 夜守住了 · %d 波 / 击退 %d · +%d 经验" % [event_day, wave_index, event_kills, reward], 6.0)
		else:
			if not session.progress.records.has("failed_horde_day"):
				session.progress.records.failed_horde_day=event_day
				session.progress.repair_base=int(session.progress.records.get("build",0))
			_announce("天亮了 · 第 %d 夜遭遇 %d 波，击退 %d" % [event_day, wave_index, event_kills], 5.0)
			if session.progress.job<=4: _announce("驻地开放补防 · 天亮后补建四段防线，交两份绷带可继续主线",6.0)
		saw_event = false
	if session.clock.elapsed >= next_heat:
		next_heat = session.clock.elapsed + 2.0
		_scan_heat()
	_fill_pack()
	if session.clock.elapsed >= next_herd:
		var observers:Array[WastelandSurvivor]=session.living_players()
		var observer:WastelandSurvivor=observers[rng.randi_range(0,observers.size()-1)] if observers.size()>1 else player
		var formed := wildlife_count < WILDLIFE_CAP and _new_herd(observer.global_position, WILDLIFE_CAP - wildlife_count)
		next_herd = session.clock.elapsed + (28.0 if formed else 12.0)
	if session.clock.elapsed >= next_patrol and not session.clock.horde_active():
		next_patrol = session.clock.elapsed + (12.0 if session.clock.hour() > 7.0 and session.clock.hour() < 20.0 else 7.5)
		_patrol()

func _announce(words: String, duration: float) -> void:
	session.notify(words, duration)
	if is_instance_valid(session.network):
		session.network.tell(words, duration)

func _activate_nests(observer: Vector3) -> void:
	if alive.size() - wildlife_count >= active_cap(false): return
	var center := WastelandTerrainGen.chunk_at(Vector2(observer.x,observer.z))
	for z in range(-2,3):
		for x in range(-2,3):
			var chunk: WastelandChunk = session.stream.active.get(center + Vector2i(x,z))
			if chunk == null or chunk.sleeper_anchors.is_empty(): continue
			var issued: Dictionary = session.stream.chunk_diff(chunk.cell).get("sleeper_slots",{})
			for index in chunk.sleeper_anchors.size():
				if issued.has(index): continue
				var anchor := chunk.position + chunk.sleeper_anchors[index]
				if anchor.distance_squared_to(observer) > 52.0*52.0: continue
				var nest := chunk.object_key("nest/"+str(index))
				for shift: Vector3 in [Vector3.ZERO, Vector3.LEFT*0.65, Vector3.RIGHT*0.65, Vector3.BACK*0.75]:
					var p := anchor + shift
					var ground := PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.40,p-Vector3.UP*0.7,3)
					var hit := get_world_3d().direct_space_state.intersect_ray(ground)
					if hit.is_empty() or hit.normal.y < 0.68: continue
					p = hit.position + Vector3.UP*0.08
					if not spawn_ground.standing_clear(session,p): continue
					var draw := posmod(session.stream.generator.seed_at(chunk.cell,501+index),7)
					var kind := "crawler" if draw == 0 else "feral_runner" if draw == 1 and stage()>=5 else "walker"
					if _spawn(kind,p,false,{"nest":nest,"home":p,"sleeping":true}):
						if not sounds.is_empty():
							alive.back().brain.heard_serial = int(sounds.front().id) - 1
						issued[index]=true
						session.stream.edit_chunk(chunk.cell).sleeper_slots = issued
						return

func _select_approach(origin: Vector3) -> float:
	var initial := rng.randf() * TAU
	for index in 8:
		var angle := initial + index * TAU / 8.0
		var probe := origin + Vector3(cos(angle), 0, sin(angle)) * 29.0
		if session.stream.at_surface(probe) and session.stream.ground_at(probe) > 0.51:
			return angle
	return initial

func formation(day: int, wave: int) -> Dictionary:
	@warning_ignore("integer_division")
	var night: int = day / int(session.clock.period)
	if night < 2 or wave < 1: return {}
	var world_seed: int = session.world_settings.seed
	var opening := posmod(world_seed+night-2,FORMATIONS.size())
	var direction := 1 if (world_seed ^ night) & 1 else -1
	return FORMATIONS[posmod(opening + (wave-1)*direction,FORMATIONS.size())]

func _wave() -> void:
	if not session.clock.horde_active() or wave_index >= wave_total:
		return
	var adjust := stage()
	var spaces := maxi(0, active_cap(true) - (alive.size() - wildlife_count))
	var upcoming := wave_index + 1
	var surge := upcoming % 3 == 0
	var count := mini(spaces, mini(14, 4 + adjust / 4 + upcoming / 3 + (2 if surge else 0)))
	var base: Vector3 = session.player.global_position
	var spawned := 0
	var group := formation(event_day,upcoming)
	for index in count:
		if spawned >= 3: break
		var id: String
		var angle := approach_angle
		if group.is_empty():
			id = _graded(adjust + upcoming / 3, true)
		elif spawned < 2:
			id = group.pair[spawned]
			# The support starts within reach of its partner whenever the ground permits.
			if group.get("flank",false):
				angle += -0.60 if spawned==0 else 0.60
			elif spawned==1 and _try_near(alive.back().global_position,id,2.0,4.2,true):
				spawned+=1
				continue
		else:
			id = "walker"
		if _try_near(base, id, 28.0, 55.0, true, angle):
			spawned += 1
	approach_announced = false
	if spawned == 0 and (spaces > 0 or wave_index == 0):
		next_wave = session.clock.elapsed + 2.0
		return
	wave_index = upcoming
	var dawn: float = event_day * 24.0 + 4.0
	var seconds_to_dawn: float = maxf(0.0, dawn - session.clock.hours) * session.clock.minutes * 2.5
	var interval := seconds_to_dawn / (wave_total - wave_index + 1)
	next_wave = session.clock.elapsed + interval
	var respite := rng.randf_range(15.0, 25.0) if wave_index < wave_total else 0.0
	assault_until = maxf(session.clock.elapsed, next_wave - respite)
	opening_remaining = maxi(0,count-spawned)
	next_surge = session.clock.elapsed + (0.50 if opening_remaining>0 else 5.0)
	# The opening group is already committed. Replacements draw down a finite HP pool.
	assault_budget = (230.0 + adjust * 32.0) * (1.0 + wave_index * 0.21)
	_announce("血月尸潮 · 第 %d / %d 波" % [wave_index, wave_total], 4.0)

func _reinforce_wave() -> void:
	next_surge = session.clock.elapsed + (0.50 if opening_remaining>0 else 5.0)
	for i in 2:
		if alive.size() - wildlife_count >= active_cap(true):
			return
		var id := _graded(stage() + wave_index, true)
		if opening_remaining>0:
			if _try_near(session.player.global_position,id,28.0,55.0,true,approach_angle):
				opening_remaining-=1
			continue
		var cost: float = float(session.catalog.enemies[id].hp) * _health_scale() * float(session.world_settings.difficulty)
		if assault_budget < cost:
			return
		if _try_near(session.player.global_position, id, 28.0, 55.0, true, approach_angle):
			assault_budget = maxf(0.0, assault_budget - alive.back().hp)

func _patrol() -> void:
	var at: Vector3 = session.player.global_position
	var observers:Array[WastelandSurvivor]=session.living_players()
	if observers.size()>1: at=observers[rng.randi_range(0,observers.size()-1)].global_position
	var zone: int = session.stream.generator.biome(at.x, at.z)
	var zombies := alive.size() - wildlife_count
	if zombies < active_cap(false):
		if zone == 4 or rng.randf() < 0.72:
			_try_near(at, _graded(stage() + (4 if zone == 4 else 0), false), 15.0, 37.0, false)

func wildlife_activity(id: String) -> String:
	var hour: float = session.clock.hour()
	var ecology: Dictionary = session.catalog.enemies.get(id, {}).get("ecology", {})
	if not ecology.has("hours"):
		return ""
	if id == "stag" and hour >= 9.0 and hour < 16.0:
		return "林间觅食"
	var begin := float(ecology.hours[0])
	var end := float(ecology.hours[1])
	var active := (hour >= begin and hour < end) if begin < end else (hour >= begin or hour < end)
	return str(ecology.active if active else ecology.rest)

func _candidates_at(point: Vector3) -> Array[String]:
	var terrain: WastelandTerrainGen = session.stream.generator
	var zone := terrain.biome(point.x, point.z)
	var near_lake := terrain.lake_factor(point.x, point.z) < 1.20
	var near_stream := terrain.revision >= 2 and point.z > -9.0 and absf(point.x - terrain.river_x(point.z)) < 15.0
	var options: Array[String] = []
	for id: String in WILDLIFE:
		var ecology: Dictionary = session.catalog.enemies[id].ecology
		if ecology.has("region") and (terrain.region_kind(point.x,point.z)!=ecology.region or (id=="argali" and point.y<35) or (id=="otter" and point.y>2.4)): continue
		var activity := wildlife_activity(id)
		if activity == ecology.rest or not PackedInt32Array(ecology.zones).has(zone):
			continue
		if id == "stag":
			if activity == "林间觅食" and zone != 1:
				continue
			if activity == "沿岸饮水" and (point.y >= 3.4 or not (near_lake or near_stream)):
				continue
		options.append(id)
	return options

func _new_herd(origin: Vector3, slots: int) -> bool:
	slots = mini(slots, WILDLIFE_CAP - wildlife_count)
	if slots <= 0:
		return false
	var present: Dictionary = {}
	for actor in alive:
		if actor.brain.animal:
			present[actor.type] = true
	for attempt in 22:
		var anchor := origin + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(24, 44)
		if not session.stream.at_surface(anchor):
			continue
		anchor.y = session.stream.ground_at(anchor)
		if anchor.y < 0.20:
			continue
		var options := _candidates_at(anchor)
		var new_species := options.filter(func(id): return not present.has(id))
		if not new_species.is_empty():
			options.assign(new_species)
		if options.is_empty():
			continue
		var id := options[rng.randi_range(0, options.size() - 1)]
		var group: Array = session.catalog.enemies[id].ecology.group
		if slots < int(group[0]):
			continue
		var members: Array[Vector3] = []
		var size := mini(slots, rng.randi_range(int(group[0]), int(group[1])))
		for probe in 12:
			var p := anchor + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(1.2, 5.0)
			if not session.stream.at_surface(p):
				continue
			p.y = session.stream.ground_at(p)
			var cell := WastelandTerrainGen.chunk_at(Vector2(p.x, p.z))
			var site_center := Vector2(cell * WastelandTerrainGen.SIZE) + Vector2.ONE * 16.0
			if p.y < 0.20 or absf(p.y - anchor.y) > 2.0 or (session.stream.generator.site_for(cell) != "" and site_center.distance_to(Vector2(p.x, p.z)) < 10.0):
				continue
			if members.any(func(other): return p.distance_squared_to(other) < 2.0):
				continue
			members.append(p)
			if members.size() == size:
				break
		if members.size() < int(group[0]):
			continue
		herd_serial += 1
		for point in members:
			_spawn(id, point + Vector3.UP * 0.12, false, {"herd":herd_serial, "home":anchor, "morph":_roll_morph(true)})
		return true
	return false

func wildlife_danger(subject: WastelandCreature) -> Vector3:
	for other in alive:
		if other == subject or other.global_position.distance_squared_to(subject.global_position) > 100.0:
			continue
		if not other.brain.animal or subject.type in other.spec.get("ecology", {}).get("prey", []):
			return other.global_position
		if subject.brain.herd != 0 and subject.brain.herd == other.brain.herd and is_instance_valid(other.brain.seen):
			return other.brain.seen.global_position
	return Vector3.INF

func hunt_target(predator: WastelandCreature, prey: Array) -> WastelandCreature:
	var nearest: WastelandCreature
	var reach := 22.0 * 22.0
	for other in alive:
		if other.type in prey:
			var gap := predator.global_position.distance_squared_to(other.global_position)
			if gap < reach:
				var from := predator.global_position + Vector3.UP * float(predator.spec.height) * 0.6
				var to := other.global_position + Vector3.UP * float(other.spec.height) * 0.6
				if predator.brain.route.ray(from, to).is_empty():
					reach = gap
					nearest = other
	return nearest

func _roll_morph(animal: bool) -> String:
	var roll := rng.randf()
	if roll < 0.19:
		return "young" if animal else "swift"
	if roll < 0.32:
		return "local" if animal else "armored"
	return ""

func _scan_heat() -> void:
	for key in heat.keys():
		var entry: Dictionary = heat[key]
		_decay_heat(entry)
		if int(entry.get("pending", 0)) > 0:
			_heat_arrival(entry)
		elif float(entry.amount) <= 0.0:
			heat.erase(key)

func _heat_arrival(entry: Dictionary) -> void:
	var source: Vector3 = entry.point
	if not session.stream.at_surface(source) or alive.size() - wildlife_count >= active_cap(session.clock.horde_active()):
		return
	var cell := WastelandTerrainGen.chunk_at(Vector2(source.x, source.z))
	var origin := Vector2(cell * WastelandTerrainGen.SIZE)
	var extent := float(WastelandTerrainGen.SIZE)
	for attempt in 32:
		var side := rng.randi_range(0,3)
		var along := rng.randf_range(0.55, extent - 0.55)
		var near := rng.randf_range(0.55, 2.0)
		var offset: Vector2 = [Vector2(along,near),Vector2(along,extent-near),Vector2(near,along),Vector2(extent-near,along)][side]
		var edge := origin + offset
		var p := spawn_ground.surface(session, Vector3(edge.x,0,edge.y))
		if not p.is_finite() or p.distance_to(source)<8.0 or session.team_distance_squared(p)<9.0*9.0:
			continue
		if _spawn("screamer",p,false,{"interest":source,"memory":35.0}):
			entry.pending = int(entry.pending) - 1
			return

func call_pack(at: Vector3, last_seen: Vector3) -> void:
	if session.replica or session.clock.elapsed < pack_cooldown: return
	pack_cooldown = session.clock.elapsed + 24.0
	add_noise(at, 32.0, false)
	pack_requests.append({"at":at, "target":last_seen,"count":rng.randi_range(4,8),"blood":session.clock.horde_active()})
	_fill_pack()

func _fill_pack() -> void:
	if pack_requests.is_empty(): return
	var request: Dictionary = pack_requests.front()
	var blood: bool = request.blood
	if (blood and not session.clock.horde_active()) or not session.stream.at_surface(request.at):
		pack_requests.pop_front()
		return
	if blood and session.clock.elapsed >= assault_until: return
	for i in int(request.count):
		if alive.size() - wildlife_count >= active_cap(blood): break
		var center: Vector3 = session.player.global_position if blood else request.at
		if _try_near(center,_graded(stage(),blood),28.0 if blood else 14.0,55.0 if blood else 29.0,blood,INF,{"interest":request.target,"memory":18.0}):
			request.count = int(request.count) - 1
	if int(request.count) == 0: pack_requests.pop_front()

func _graded(difficulty: int, allow_brute: bool) -> String:
	var valid := ["walker", "walker", "walker","walker","crawler"]
	for id in KINDS:
		if id not in ["screamer","walker","mudwalker","sandrunner"] and session.catalog.enemies.has(id) and difficulty >= int(session.catalog.enemies[id].min) and (id != "rimecaller" or allow_brute):
			valid.append(id)
			var dark: bool = session.clock.hour() < 5.0 or session.clock.hour() >= 21.0
			if id == "feral_runner" and (dark or allow_brute):
				for i in mini(5, 1 + floori(difficulty / 9.0)): valid.append(id)
			elif id == "brute" and allow_brute and difficulty >= 15:
				valid.append(id)
	return valid[rng.randi_range(0, valid.size() - 1)]

func _try_near(center: Vector3, type: String, low: float, high: float, is_wave: bool, hinted_angle: float = INF, cue: Dictionary = {}) -> bool:
	if alive.size() - wildlife_count >= CAP:
		return false
	var shared_party:bool=session.living_players().size()>1
	for attempt in range(12):
		var a := hinted_angle + rng.randf_range(-0.52, 0.52) if hinted_angle != INF else rng.randf() * TAU
		var p := center + Vector3(cos(a),0,sin(a)) * rng.randf_range(low, high)
		p = spawn_ground.surface(session, p)
		if not p.is_finite():
			continue
		if is_wave:
			var range_to_player: float = p.distance_to(session.player.global_position)
			if range_to_player < 28.0 or range_to_player > 55.0:
				continue
			if session.team_distance_squared(p)<28.0*28.0:
				continue
		elif shared_party and session.team_distance_squared(p)<8.0*8.0:
			continue
		var locator := WastelandTerrainGen.chunk_at(Vector2(p.x,p.z))
		var midpoint := Vector2(locator * WastelandTerrainGen.SIZE) + Vector2.ONE * 16.0
		if session.stream.generator.site_for(locator) != "" and midpoint.distance_to(Vector2(p.x,p.z)) < 8.8:
			continue
		var spawn_data := cue.duplicate()
		if type=="walker" and not is_wave and rng.randf()<0.55:
			var district:=str(session.stream.generator.region_kind(p.x,p.z))
			if district=="marsh" and p.y<3.5: type="mudwalker"
			elif district=="desert": type="sandrunner"
			elif district=="alpine" and stage() >= int(session.catalog.enemies.rimecaller.min): type="rimecaller"
			elif district in ["canyon","mesa"] and stage() >= int(session.catalog.enemies.bulwark.min): type="bulwark"
		spawn_data.morph = _roll_morph(type in WILDLIFE)
		return _spawn(type, p, is_wave, spawn_data)
	return false

func _spawn(id: String, at: Vector3, is_wave: bool, previous: Dictionary = {}) -> bool:
	if not session.catalog.enemies.has(id):
		return false
	var animal := id in WILDLIFE
	if (animal and wildlife_count >= WILDLIFE_CAP) or (not animal and alive.size() - wildlife_count >= CAP):
		return false
	var choice: WastelandCreature
	for actor in pool:
		if actor.active:
			continue
		if choice == null:
			choice = actor
		if actor.type == id:
			choice = actor
			break
	if choice == null:
		return false
	var serial := int(previous.get("serial",0))
	if serial <= 0 or actors_by_serial.has(serial):
		spawn_serial += 1
		serial = spawn_serial
	spawn_serial = maxi(spawn_serial,serial)
	choice.spawn_serial = serial
	previous = previous.duplicate()
	if not animal and not previous.has("stage_health"):
		previous.stage_health = _health_scale()
	if not previous.has("face_variant"):
		previous.face_variant = hash(Vector3i(int(session.world_settings.seed), serial, 0x46414345)) & 1
	if not animal:
		if not previous.has("wardrobe_index"):
			# Stable per individual, including retries and deferred chunk loads.
			var identity := Vector2i(int(session.world_settings.seed), serial)
			previous.wardrobe_index = posmod(hash(identity), WastelandCreature.WARDROBE_COUNT)
		if not previous.has("limb_index"):
			previous.limb_index = WastelandCreature.InfectedLimbs.roll(int(session.world_settings.seed), serial)
	var look_count := WastelandCreature.InfectedLooks.count_for(id)
	if look_count > 0 and not previous.has("look_index"):
		var group := id + "/" + str(previous.get("morph", ""))
		previous.look_index = _next_look(group, look_count)
	choice.revive(id, at, is_wave, previous)
	alive.append(choice)
	actors_by_serial[serial] = choice
	if animal:
		wildlife_count += 1
	return true

@warning_ignore("integer_division")
func _next_look(group: String, count: int) -> int:
	var cursor := maxi(0, int(next_looks.get(group, 0)))
	var batch := cursor / count
	var world_seed := int(session.world_settings.seed)
	var draw := RandomNumberGenerator.new()
	draw.seed = hash([world_seed, group, batch])
	var order := range(count)
	for i in range(count - 1, 0, -1):
		var j := draw.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	if batch > 0 and count >= 3:
		# The first shuffle draw places the preceding batch's last entry.
		# Swap only the first two so the next batch can reproduce this tail.
		draw.seed = hash([world_seed, group, batch-1])
		if order[0] == draw.randi_range(0, count-1):
			var first: int = order[0]
			order[0] = order[1]
			order[1] = first
	next_looks[group] = cursor+1
	return order[cursor % count]

func release(actor: WastelandCreature) -> void:
	if actor.active:
		if actor.type in WILDLIFE:
			wildlife_count -= 1
		actor.deactivate()
		actors_by_serial.erase(actor.spawn_serial)
		alive.erase(actor)

func defeated(actor: WastelandCreature) -> void:
	if session.replica or not actor.active or not alive.has(actor): return
	if actor.brain.state == WastelandCreatureBrain.State.DEAD: return
	var animal := actor.type in WILDLIFE
	if actor.wave and session.clock.horde_active():
		event_kills += 1
	var p := actor.global_position
	if animal:
		var harvest := {}
		for material in actor.spec.ecology.harvest:
			var limits: Array = actor.spec.ecology.harvest[material]
			var amount := rng.randi_range(int(limits[0]), int(limits[1]))
			if amount > 0:
				harvest[material] = amount
		session.spawn_drop(p + Vector3.UP * 0.1, harvest)
	elif actor.spec.has("salvage"):
		session.spawn_drop(p + Vector3.UP * 0.1, {str(actor.spec.salvage):rng.randi_range(1,2)})
	elif rng.randf() < (0.27 if actor.wave else 0.17):
		var id: String = ["cloth","scrap","powder","round","bandage"][rng.randi_range(0,4)]
		session.spawn_drop(p + Vector3.UP * 0.1, {id:rng.randi_range(1,4)})
	if TROPHIES.has(actor.type) and trophy_rng.randi_range(1,RARE_ODDS)==1:
		var pool_items: Array = TROPHIES[actor.type].duplicate()
		if actor.morph=="armored": pool_items.append("meme_pot")
		elif actor.morph=="swift": pool_items.append("meme_fins")
		elif actor.type=="fox" and actor.morph=="local": pool_items.append("meme_clock")
		var trophy: String = pool_items[trophy_rng.randi_range(0,pool_items.size()-1)]
		session.spawn_drop(p+Vector3.UP*0.35,{trophy:1})
		session.gain(0,"rare_drop")
	session.gain(int(actor.spec.xp), "hunt" if animal else "kill")
	var record := "kill_" + actor.type
	session.progress.records[record] = int(session.progress.records.get(record, 0)) + 1
	if not actor.morph.is_empty():
		var morph_record := record + "_" + actor.morph
		session.progress.records[morph_record] = int(session.progress.records.get(morph_record, 0)) + 1
	session.audio.play_at("growl" if not animal else "hit", p + Vector3.UP * 0.47, 0.42)
	if animal: release(actor)
	else: actor.begin_death()

func can_mend(caller: WastelandCreature, other: WastelandCreature, radius: float) -> bool:
	if other == caller or not other.active or other.hp <= 0.0 or other.brain.animal or other.hp >= other.max_health():
		return false
	if caller.global_position.distance_squared_to(other.global_position) > radius*radius:
		return false
	var source := caller.gland.global_position if is_instance_valid(caller.gland) else caller.global_position + Vector3.UP * caller.body_height()*0.55
	return caller.brain.route.ray(source,other.global_position + Vector3.UP * other.body_height()*0.55).is_empty()

func wounded_ally(caller: WastelandCreature, radius: float) -> WastelandCreature:
	var lowest := 1.0
	var patient: WastelandCreature
	for other in alive:
		var fraction := other.hp / other.max_health()
		if fraction < lowest and can_mend(caller,other,radius):
			lowest = fraction
			patient = other
	return patient

func rupture(actor: WastelandCreature) -> void:
	if session.replica or not actor.active: return
	var origin := actor.gland.global_position
	infected_effect("rupture",origin)
	session.audio.play_at("boom",origin,1.12)
	damage_near(origin,float(actor.spec.ai.blast_radius),float(actor.spec.ai.blast_hit)*float(session.world_settings.difficulty),"rupture")
	defeated(actor)

func infected_effect(kind: String, point: Vector3, normal := Vector3.UP) -> void:
	session.fx.infected_effect(kind, point,normal)
	if is_instance_valid(session.network):
		session.network.mirror_infected_effect(kind,point,normal)

func damage_near(point: Vector3, radius: float, amount: float, source: String) -> void:
	if session.replica: return
	var victims:Array[WastelandSurvivor]=session.living_players()
	for victim in victims:
		if victim.health <= 0.0: continue
		var target := victim.global_position + Vector3.UP * victim.stand_shape.height * (0.16 if source == "residue" else 0.50)
		var distance := target.distance_to(point)
		if distance >= radius: continue
		var ignored: Array[RID] = []
		if is_instance_valid(victim.mount_vehicle): ignored.append(victim.mount_vehicle.get_rid())
		var cover := PhysicsRayQueryParameters3D.create(point,target,WastelandCreatureRoute.SOLIDS,ignored)
		if get_world_3d().direct_space_state.intersect_ray(cover).is_empty():
			var strength := 1.0 if source == "residue" else lerpf(1.0,0.30,distance/radius)
			victim.damage(amount*strength,source,point)

func nearest_enemy(at: Vector3, radius: float) -> WastelandCreature:
	var best := radius * radius
	var result: WastelandCreature
	for actor in alive:
		if not actor.active or actor.hp <= 0.0 or actor.type in WILDLIFE:
			continue
		var d := actor.global_position.distance_squared_to(at)
		if d < best:
			best = d
			result = actor
	return result

func breach_pressure(wall: StaticBody3D, except: WastelandCreature) -> int:
	var count := 0
	for actor in alive:
		if actor != except and actor.active and actor.brain.breach_wall == wall:
			count += 1
	return count

func separation(subject: WastelandCreature) -> Vector3:
	var adjustment := Vector3.ZERO
	var point := subject.global_position
	for neighbor in alive:
		if neighbor == subject or not neighbor.active or neighbor.hp <= 0.0:
			continue
		var difference := point - neighbor.global_position
		var d := difference.length_squared()
		if d <= 0.005:
			var angle := float(posmod(neighbor.spawn_serial + subject.spawn_serial, 13)) * TAU / 13.0
			adjustment += Vector3(cos(angle),0,sin(angle)) * (1.0 if subject.spawn_serial > neighbor.spawn_serial else -1.0)
		elif d < 1.21:
			adjustment += difference.normalized() * (1.0 - d / 1.21)
	adjustment.y = 0.0
	return adjustment.limit_length(1.0)

func trail_snapshot(near:Vector3)->Array:
	var prints:=get_node_or_null("Hoofprints")
	return prints.nearby(near) if prints else []

func mirror_trails(rows:Array)->void:
	if rows.is_empty(): return
	var prints:=get_node_or_null("Hoofprints")
	if not prints:
		prints=WastelandHoofprints.new()
		prints.name="Hoofprints"
		add_child(prints)
	prints.mirror(rows)
