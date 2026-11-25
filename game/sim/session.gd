class_name WastelandSession
extends Node3D

signal message(text: String, duration: float)
signal panel(id: String, context: Variant)
signal failed
signal stored(slot: int)

const WORLD_SAVE_INTERVAL_MS := 30000
const QUICK_SAVE_DELAY_MS := 5000
const BOAT_REPAIR := {"wood":6, "fiber":3, "scrap":2}
const TRADE_COST := {"scrap":8}
const TRADE_REWARD := {"clean_water":2,"canned":2,"bandage":1}
const LANDING_CARGO := {
	"shore_float":{"clean_water":2,"canned":1,"tape":2},
	"survey_float":{"parts":5,"electronics":2,"fuel":3}
}
const VEHICLE_SALVAGE := {"scrap":4,"parts":1}
const Chest := preload("res://game/art/supply_chest.gd")
const StructuralSalvage := preload("res://game/world/structural_salvage.gd")
const SaplingPlanting := preload("res://game/sim/sapling_planting.gd")
var timber := preload("res://game/sim/timber.gd").new()
var grove := preload("res://game/sim/grove.gd").new()
const Fire := preload("res://game/sim/station_fire.gd")
const OutpostOrders := preload("res://game/sim/outpost_orders.gd")
const Patrol := preload("res://game/sim/relay_patrol.gd")
const Expeditions := preload("res://game/sim/expeditions.gd")
const TitleWildlife := preload("res://game/world/title_wildlife.gd")
const PartyFalls := preload("res://game/net/party_falls.gd")
const RagdollHits := preload("res://game/actors/ragdoll_hits.gd")

const LOOSE_MATERIALS := {"boulder":{"stone":3}, "ore":{"stone":3}}
const HARVEST_TOOLS := {"cactus":"field_sickle","herb_patch":"field_sickle","reed_bed":"field_sickle","iron_vein":"iron_pick","machine_wreck":"salvage_wrench"}
const HARVEST_SAMPLES := {"cactus":"cactus_fruit","herb_patch":"medicinal_herb","reed_bed":"reed_stem","iron_vein":"iron_ore","machine_wreck":"scrap"}
const PICKUPS := ["fallen_stick","pebble","grass"]
const LOOSE_SCENERY := ["fallen_stick","grass","reeds","pebble","pondweed","silt","driftwood"]
const RESOURCES := {
	"fallen_stick":["地面枯枝",4,{"stick":1}],
	"grass":["草丛",6,{"fiber":1}],
	"reeds":["野芦丛",8,{"reed_stem":1,"fiber":1}],
	"pebble":["碎石",6,{"stone":1}],
	"pondweed":["沉水草",7,{"fiber":2}],
	"bedrock":["水底岩石",38,{"stone":5}],
	"driftwood":["沉木",20,{"wood":3}],
	"silt":["淤泥堆",8,{"clay":2}],
	"cactus":["挂果仙人掌",27,{"cactus_fruit":2,"fiber":1}],
	"herb_patch":["林间药草",34,{"medicinal_herb":3,"fiber":2}],
	"reed_bed":["岸边芦苇",42,{"reed_stem":5,"fiber":3}],
	"iron_vein":["赤铁矿脉",98,{"iron_ore":5,"stone":3}],
	"machine_wreck":["废弃泵机",108,{"spring":2,"scrap":6}],
	"oak": ["秋叶橡树", 56, {"wood": 17, "fiber": 3}],
	"pine": ["黑杉", 67, {"wood": 21, "fiber": 4}],
	"boulder": ["风化岩块", 50, {"stone": 15, "sand": 4}],
	"clay_bank": ["湖滩黏土", 38, {"clay": 13, "sand": 7}],
	"brush": ["浆果灌木", 15, {"berries": 4, "fiber": 5, "seed_potato": 1}],
	"ore": ["露头矿石", 78, {"coal":5, "stone": 9, "scrap": 13, "lead": 5, "mineral": 4}],
	"salvage": ["金属残骸", 60, {"scrap": 10, "brass": 6, "parts": 2}],
}

var options: WastelandSettings
var world_settings: Dictionary
var catalog: WastelandCatalog
var clock := WastelandClock.new()
var bag: WastelandBag
var progress: WastelandProgression
var achievements := preload("res://game/sim/achievement_book.gd").new()
var player: WastelandSurvivor
var atmosphere := WastelandAtmosphere.new()
var stream := WastelandStream.new()
var audio: WastelandAudio
var fx: WastelandEffects
var construction: WastelandConstruction
var hordes: WastelandHordes
var slot := 0
var preview_only := false
var forward_down_ms := -1
var last_forward_tap_ms := -1
var double_forward_sprint := false
var controls_enabled := false:
	set(value):
		controls_enabled=value
		if not value: reset_forward_taps()
var simulation_paused := false
var death_screen := false
var deaths := 0
var guest_states: Dictionary = {}
var marker_records: Array = []
var map_serial := 0
var vehicle_records: Dictionary = {}
var vehicles: Dictionary = {}
var vehicle_serial := 0
var next_vehicles := 0.0
var hand_queue: Array = []
var craft_serial:=0
var shape := 0
var turn := 0
var interaction := {}
var building_hit := {}
var next_hint := 0.0
var hint := ""
var focus_damage := -1.0
var cache_inventory:=preload("res://game/sim/cache_inventory.gd").new()
var replica_chest:Dictionary={}
var loot_target: StaticBody3D
var loot_time := 0.0
var loot_full := 0.0
var loot_ratio := 0.0
var search_start:=Vector3.ZERO
var search_slot:=-1
var search_held:=""
var action_lock := 0.0
var reload_id := ""
var reload_left := 0.0
var reload_span := 0.0
var heavy_charge := 0.0
var heavy_pending := false
var world_save_at_ms := 0
var last_autosave_error := OK
var light_tick := 0.0
var vehicle_sync := 0.0
var trade_day := 0
var route_sites: Dictionary = {}
var order_cache := {}
var tracked_order := ""
var tracked_row := {}
var recent_trails: Array = []
var starting_cell := WastelandSite.SHORE_CELL
var preview_camera: Camera3D
var preview_wildlife: TitleWildlife
var preview_time := 0.0
var preview_index := -1
var preview_eye := Vector3.ZERO
var preview_target := Vector3.ZERO
var preview_hour := 0.0
var preview_travel := 0.0
var preview_clearance := 1.4
var network: Node
var replica := false
var actor_peer_id := WastelandLan.HOST_ID
var remote_actor: bool:
	get: return actor_peer_id!=WastelandLan.HOST_ID

func living_players() -> Array[WastelandSurvivor]:
	var result: Array[WastelandSurvivor]=[]
	var owner: WastelandSurvivor=network.owner_player(self) if is_instance_valid(network) and network.server() else player
	if is_instance_valid(owner) and owner.health>0.0: result.append(owner)
	if is_instance_valid(network) and network.server(): result.append_array(network.living_guests())
	return result

func team_distance_squared(point:Vector3)->float:
	var distance:=INF
	for person:WastelandSurvivor in living_players():
		distance=minf(distance,person.global_position.distance_squared_to(point))
	return distance

func guest_positions()->Array[Vector3]:
	var result:Array[Vector3]=[]
	if is_instance_valid(network) and network.server():
		for person:WastelandSurvivor in network.living_guests(): result.append(person.global_position)
	return result

func create_bag(saved: Dictionary) -> WastelandBag:
	var inventory := WastelandBag.new(catalog, saved)
	inventory.acquired.connect(achievements.acquired_item)
	if slot > 0:
		inventory.changed.connect(_schedule_world_save)
	return inventory

func _schedule_world_save(delay_ms: int = QUICK_SAVE_DELAY_MS) -> void:
	if slot <= 0 or replica or preview_only: return
	var deadline := Time.get_ticks_msec() + delay_ms
	# A time-sensitive change can bring the world's single checkpoint forward.
	if world_save_at_ms == 0 or deadline < world_save_at_ms:
		world_save_at_ms = deadline

func configure(config: Dictionary, snapshot: Dictionary, slot_number: int, data: WastelandCatalog, opts: WastelandSettings, preview: bool = false) -> void:
	options = opts
	catalog = data
	world_settings = config.duplicate()
	clock.configure(config, snapshot)
	preview_only = preview
	set_process(preview)
	set_physics_process(not preview)
	slot = slot_number
	add_child(atmosphere)
	add_child(stream)
	stream.radius = int(options.display.radius)
	stream.refill_days = int(config.loot_days)
	stream.loot_day = clock.day()
	stream.start(int(config.seed), catalog, atmosphere, snapshot, preview, int(config.get("terrain_revision", 1)))
	stream.generator.site_revision = int(config.get("site_revision",0)) if stream.generator.revision>=3 else 0
	if preview:
		preview_camera = Camera3D.new()
		preview_camera.name = "LandscapeCamera"
		preview_camera.far = 230.0
		preview_camera.near = 0.08
		preview_camera.fov = 61.0
		add_child(preview_camera)
		preview_camera.make_current()
		preview_wildlife = TitleWildlife.new()
		preview_wildlife.name = "TitleWildlife"
		add_child(preview_wildlife)
		return
	if stream.generator.revision>=3 and str(world_settings.get("start_id","seeded"))=="random":
		if not world_settings.has("spawn_point"):
			if not world_settings.has("spawn_roll"):
				world_settings.spawn_roll = stream.generator.seed_at(Vector2i.ZERO,6187)
			world_settings.spawn_point = stream.generator.wilderness_start(int(world_settings.spawn_roll))
		stream.generator.wild_start = world_settings.spawn_point
		starting_cell = WastelandTerrainGen.chunk_at(stream.generator.wild_start)
	elif stream.generator.revision>=3:
		starting_cell = stream.generator.starting_outpost(str(world_settings.get("start_id","seeded")))
	NavigationServer3D.map_set_edge_connection_margin(get_world_3d().navigation_map, 0.52)
	var initial := start_position()
	progress = WastelandProgression.new(snapshot.get("progress", {}))
	var old_threat:Dictionary=snapshot.get("threat",{})
	if not snapshot.get("progress",{}).has("quest_revision") and int(old_threat.get("died",0))>0 and int(old_threat.get("cleared",0))>0 and old_threat.cleared==old_threat.get("event",0):
		progress.records.failed_horde_day=int(old_threat.cleared)
		progress.repair_base=int(progress.records.get("build",0))
	achievements.configure(self)
	bag = create_bag(snapshot.get("bag", {}))
	if progress.job >= catalog.quests.size() and progress.finish_day == 0:
		progress.finish_day = -1 # Historical saves recorded completion, but did not store its date.
	if snapshot.is_empty():
		progress.records["first_axe_guide"] = 1
	marker_records = snapshot.get("markers", []).duplicate(true)
	map_serial = int(snapshot.get("map_serial", 0))
	vehicle_records = snapshot.get("vehicles", {}).duplicate(true)
	vehicle_serial = int(snapshot.get("vehicle_serial", 0))
	hand_queue = snapshot.get("hand_queue", []).duplicate(true)
	trade_day = int(snapshot.get("trade_day", 0))
	tracked_row=snapshot.get("tracked_order",{}).duplicate()
	tracked_order=str(tracked_row.get("id",""))
	deaths = int(snapshot.get("deaths", 0))
	guest_states = snapshot.get("guests", {}).duplicate(true)
	shape = int(snapshot.get("shape", 0))
	turn = int(snapshot.get("turn", 0))
	audio = WastelandAudio.new()
	fx = WastelandEffects.new()
	construction = WastelandConstruction.new()
	hordes = WastelandHordes.new()
	add_child(audio)
	add_child(fx)
	add_child(construction)
	add_child(hordes)
	fx.configure(self, snapshot)
	construction.configure(self, snapshot.get("construction", {}))
	craft_serial=int(snapshot.get("craft_serial",0))
	_label_jobs(hand_queue)
	for station_cell:Vector3i in construction.station_index:
		var station_data:Dictionary=construction.blocks[station_cell]
		Fire.restore(station_data,clock.elapsed)
		_label_jobs(station_data.get("queue",[]))
	hordes.configure(self, snapshot)
	player = WastelandSurvivor.new()
	add_child(player)
	player.configure(self, snapshot.get("player", {}), initial)
	player.ragdoll_changed.connect(_player_fell.bind(player))
	player.ragdoll_struck.connect(_player_part_hit.bind(player))
	audio.listener = player.camera
	grove.configure(self)
	stream.prime(player.global_position)
	stream.lake_wildlife.restore_combat(snapshot.get("lake_combat",{}))
	stream.lake_wildlife.impact_changed.connect(_lake_impact_changed)
	timber.configure(self, snapshot.get("falling_trees",{}))
	if snapshot.is_empty() or stream.below_terrain(player.global_position):
		player.position.y = stream.ground_at(player.global_position) + 0.12
	atmosphere.sync(clock, 0.0, player.camera.global_position, -player.camera.global_basis.z)
	if snapshot.is_empty() and stream.generator.revision >= 2:
		_stock_landing()
	_sync_vehicles()
	if not snapshot.get("mounted", "").is_empty() and vehicles.has(snapshot.mounted):
		player.ride(vehicles[snapshot.mounted])
	if player.health <= 0.0:
		respawn()
	PartyFalls.restore_corpses(self,snapshot.get("survivor_corpses",[]))

func start_position() -> Vector3:
	var spawn := WastelandTerrainGen.START
	if stream.generator.wild_start.is_finite():
		spawn = stream.generator.wild_start
	elif stream.generator.revision>=3:
		spawn = Vector2(starting_cell*WastelandTerrainGen.SIZE)+Vector2(16,26)
	var initial := Vector3(spawn.x,0,spawn.y)
	initial.y = stream.ground_at(initial) + 0.22
	if stream.generator.ground(spawn.x,spawn.y)-initial.y < 0.8: return initial
	for radius in range(2,34,2):
		for i in 12:
			var candidate := initial + Vector3(sin(TAU*i/12.0),0,cos(TAU*i/12.0))*radius
			candidate.y = stream.ground_at(candidate)+0.22
			if candidate.y > 0.6 and absf(stream.generator.ground(candidate.x,candidate.z)-candidate.y)<0.6:
				return candidate
	return initial

func start_name() -> String:
	if stream.generator.revision<3: return "南岸湖务站"
	if stream.generator.wild_start.is_finite():
		var p := stream.generator.wild_start
		var region := stream.generator.region_kind(p.x,p.y)
		return str({"meadow":"草甸","taiga":"针叶林","desert":"沙漠","mesa":"台地","marsh":"湿地","canyon":"峡谷"}.get(region,"荒原"))+"野地"
	return _station_name(starting_cell)

func frame_landscape(index: int) -> void:
	if not preview_only or preview_index==index: return
	preview_index = index
	preview_time = 0.0
	var frame := preload("res://game/world/title_landscapes.gd").frame(index,stream.generator)
	preview_eye = frame.eye
	preview_target = frame.target
	preview_hour = frame.hour
	preview_travel = frame.travel
	preview_clearance = frame.clearance
	clock.hours = preview_hour
	preview_camera.position = preview_eye
	preview_camera.look_at(preview_target)
	stream.frame_preview(preview_camera, preview_eye.lerp(preview_target, 0.40))
	preview_wildlife.configure(stream, catalog, frame.wildlife)
	preview_wildlife.advance(preview_camera, preview_time, 0.0)
	atmosphere.sync(clock,0.0,preview_eye,-preview_camera.global_basis.z)

func _process(delta: float) -> void:
	if preview_index < 0: return
	preview_time += delta
	clock.elapsed += delta
	clock.hours = preview_hour + 0.35 * sin(preview_time * 0.055)
	var forward := preview_target - preview_eye
	forward.y = 0.0
	forward = forward.normalized()
	var across := forward.cross(Vector3.UP)
	var slide := sin(preview_time * 0.18) * preview_travel
	var push := (1.0 - cos(preview_time * 0.18)) * minf(0.36, preview_travel * 0.2)
	var eye := preview_eye + across * slide + forward * push
	eye.y = maxf(eye.y, stream.ground_at(eye) + preview_clearance)
	preview_camera.position = eye
	preview_camera.look_at(preview_target + across * slide * 0.15)
	preview_wildlife.advance(preview_camera, preview_time, delta)
	atmosphere.sync(clock, delta, eye, -preview_camera.global_basis.z)

func _station_name(cell: Vector2i) -> String:
	return WastelandSite.station_name(stream.generator,cell)

func _nearby_sites() -> Dictionary:
	var loc := WastelandTerrainGen.chunk_at(Vector2(player.position.x,player.position.z))
	if route_sites.has(loc): return route_sites[loc]
	var sites := WastelandTerrainGen.FIXED.duplicate()
	if stream.generator.revision>=3:
		for station: Vector2i in stream.generator.nearby_outposts(Vector2(player.position.x,player.position.z)):
			sites[station] = "lodge"
			var archive := stream.generator.outpost_beacon_cell(station)
			sites[archive] = stream.generator.site_for(archive)
		for id: String in ["grassland","foothills"]:
			var station: Vector2i = stream.generator.starting_outpost(id)
			sites[station] = "lodge"
			var relay: Vector2i = stream.generator.outpost_beacon_cell(station)
			sites[relay] = stream.generator.site_for(relay)
		for z in range(-6,7):
			for x in range(-6,7):
				var cell := loc+Vector2i(x,z)
				var site := stream.generator.site_for(cell)
				if site in ["lodge","tower","hospital","police"]: sites[cell] = site
	if route_sites.size()>=12: route_sites.clear()
	route_sites[loc] = sites
	return sites

func board_destination() -> Dictionary:
	var closest := INF
	var best := WastelandSite.SHORE_CELL
	var sites := _nearby_sites()
	for cell: Vector2i in sites:
		if sites[cell]!="lodge": continue
		var distance := Vector2(player.position.x,player.position.z).distance_squared_to(WastelandSite.board_at(cell))
		if distance<closest:
			closest = distance
			best = cell
	return {"at":WastelandSite.board_at(best),"name":_station_name(best)+("公告板遗址" if _fixture_gone(best,"trader") else "公告板")}

func _stock_landing() -> void:
	var tip_z := maxf(2.0, WastelandSite.landing_shore(stream.generator) - 11.0)
	var mooring := _lake_point(Vector2(9.6, tip_z - 0.5))
	if mooring.is_finite():
		vehicle_records["landing_boat"] = {"type":"boat", "point":mooring + Vector3.UP * 0.10, "yaw":0.0, "fuel":23.0, "needs_repair":true}
	var supplies := [
		{"at":Vector2(9, tip_z - 22), "id":"shore_float", "items":LANDING_CARGO.shore_float.duplicate()},
		{"at":Vector2(23, -42), "id":"survey_float", "items":LANDING_CARGO.survey_float.duplicate()},
	]
	for supply in supplies:
		var point := _lake_point(supply.at)
		if point.is_finite():
			fx.store_drop(supply.id,{"items":supply.items, "point":point + Vector3.UP * 0.25, "buoy":true})
	fx._resync_drops()

func _lake_point(start: Vector2) -> Vector3:
	for offset in range(0, 33, 2):
		var z := start.y - float(offset)
		if stream.generator.water_basin(start.x, z) and stream.generator.ground(start.x, z) < -0.9:
			return Vector3(start.x, WastelandTerrainGen.WATER_LEVEL, z)
	return Vector3.INF

func _physics_process(delta: float) -> void:
	if stream.generator == null:
		return
	if replica:
		network.client_tick(self,delta)
		grove.tick(delta)
		timber.tick(delta)
		return
	if player == null:
		return
	# Between simulation steps every transfer is complete and the host is selected.
	# A pending checkpoint also finishes if the world has since been paused.
	if world_save_at_ms > 0 and Time.get_ticks_msec() >= world_save_at_ms:
		var error := save_now(false)
		if error != OK and error != last_autosave_error:
			notify("自动保存失败，将重试 · 错误 %d" % error)
		last_autosave_error = error
	if simulation_paused:
		return
	if death_screen:
		player.update_ragdoll_camera(delta)
		if not is_instance_valid(network) or not network.server():
			hordes.tick_corpses(delta)
			return
	if world_save_at_ms == 0:
		_schedule_world_save(WORLD_SAVE_INTERVAL_MS)
	clock.advance(delta)
	stream.advance_loot_day(clock.day())
	action_lock = maxf(0, action_lock - delta)
	if not death_screen:
		player.simulate(delta, controls_enabled)
		achievements.tick(delta)
	var at := player.global_position
	stream.refresh(at, clampi(int(options.display.radius), 2, 6),guest_positions())
	atmosphere.sync(clock, delta, player.camera.global_position, -player.camera.global_basis.z, audio)
	light_tick -= delta
	if light_tick < 0.0:
		light_tick = 0.28
		var near_water := 1.0 - smoothstep(0.95, 1.52, stream.generator.lake_factor(at.x, at.z))
		audio.sync(atmosphere.rain_strength, clock.blood(), near_water)
	_finish_crafting()
	_tick_reload(delta)
	hordes.simulate(delta)
	construction.simulate(delta)
	grove.tick(delta)
	timber.woodland(delta)
	timber.tick(delta)
	fx.simulate(delta)
	next_vehicles -= delta
	if next_vehicles <= 0.0:
		next_vehicles = 0.71
		Patrol.tick(self)
		_sync_vehicles()
		for person:WastelandSurvivor in living_players(): _discover_site(person)
	if controls_enabled and not death_screen and not player.is_knocked_down():
		_process_controls(delta)
	else:
		loot_target = null
		loot_ratio = 0.0
		heavy_charge = 0.0
		heavy_pending = false
		construction.place_preview.hide()
	if is_instance_valid(network):
		network.host_tick(self,delta)

func mouse_look(screen_delta: Vector2) -> void:
	if not controls_enabled or simulation_paused or death_screen or player == null or player.is_knocked_down():
		return
	var scale := float(options.display.sensitivity)
	var invert := -1.0 if options.display.invert_y else 1.0
	player.look(screen_delta * Vector2(scale, scale * invert))

func action_pressed(id: String) -> bool:
	return network.remote_button("pressed",id) if remote_actor else Input.is_action_just_pressed(id)

func action_held(id: String) -> bool:
	if remote_actor: return network.remote_button("held",id)
	if id=="sprint" and double_forward_sprint and controls_enabled and not death_screen and Input.is_action_pressed("up"): return true
	return Input.is_action_pressed(id)

func reset_forward_taps()->void:
	forward_down_ms=-1
	last_forward_tap_ms=-1
	double_forward_sprint=false

func forward_key(event:InputEventKey)->void:
	if event.echo or not event.is_action("up"): return
	if not controls_enabled or death_screen or simulation_paused or preview_only:
		reset_forward_taps()
		return
	var now:=Time.get_ticks_msec()
	if event.pressed:
		if forward_down_ms>=0: return
		double_forward_sprint=last_forward_tap_ms>=0 and now-last_forward_tap_ms<=270
		forward_down_ms=now
		last_forward_tap_ms=-1
	else:
		last_forward_tap_ms=now if not double_forward_sprint and forward_down_ms>=0 and now-forward_down_ms<=225 else -1
		forward_down_ms=-1
		double_forward_sprint=false

func optics_active()->bool:
	return (bag.current()=="field_glasses" and action_held("alternate")) or (bag.offhand=="field_glasses" and InputMap.has_action("offhand_use") and action_held("offhand_use"))

func movement_axis() -> Vector2:
	return network.current_input().get("drive",Vector2.ZERO) if remote_actor else Input.get_vector("left","right","up","down")

func _open_for_player(id: String, context: Variant) -> void:
	if remote_actor:
		network.panel_for_member(id,context)
	else:
		panel.emit(id,context)

func _process_controls(delta: float) -> void:
	if InputMap.has_action("swap_hands") and action_pressed("swap_hands"): bag.swap_hands()
	for index in range(WastelandBag.HOTBAR_SIZE):
		if action_pressed("slot_%d" % (index + 1)):
			bag.active = index
	if action_pressed("slot_next"):
		bag.active = posmod(bag.active + 1, WastelandBag.HOTBAR_SIZE)
	if action_pressed("slot_prev"):
		bag.active = posmod(bag.active - 1, WastelandBag.HOTBAR_SIZE)
	if action_pressed("flashlight"):
		player.toggle_lamp()
	if action_pressed("shape"):
		shape = (shape + 1) % WastelandCatalog.SHAPE_NAMES.size()
		notify(WastelandCatalog.SHAPE_NAMES[shape], 1.4)
	if action_pressed("rotate"):
		turn = (turn + 1) % 4
	var held := bag.current()
	if held == "stone_axe":
		progress.records.erase("first_axe_guide")
	var item: Dictionary = catalog.items.get(held, {})
	var kind: String = item.get("kind", "")
	player.hand.charge = heavy_charge
	if action_pressed("discard") and held != "":
		discard(held)
	if action_pressed("reload") and kind == "ranged":
		start_reload(held)
	next_hint -= delta
	if next_hint <= 0.0:
		next_hint = 0.077
		if not action_pressed("use"): fx.collect_nearby()
		interaction = _interaction_trace()
		building_hit = _trace(5.6, 3)
		if not remote_actor:
			construction.preview(building_hit, held, shape, turn, player.global_position)
		_update_prompt(held)
	if construction.tick_work(delta, held):
		return
	if is_instance_valid(loot_target):
		_tick_loot(delta)
	if action_pressed("use"):
		_use()
	if InputMap.has_action("offhand_use") and action_pressed("offhand_use") and not action_pressed("use") and not action_held("fire") and not heavy_pending and action_lock<=0.0:
		_use_offhand()
	if action_pressed("alternate") and held!="field_glasses":
		if held.is_empty() and not is_instance_valid(player.mount_vehicle) and (remote_actor or not preload("res://game/ui/touch_layout.gd").active):
			var chest_hit:=_interaction_trace()
			var chest:=chest_hit.get("collider") as StaticBody3D
			if _ordinary_chest(chest):
				if not action_pressed("use"): _inspect_chest(chest,chest_hit)
				return
		var context := _trace(5.5, 3)
		var target: Object = context.get("collider")
		var nearby: Object = interaction.get("collider")
		var managing_vehicle:bool=is_instance_valid(nearby) and nearby.get_meta("kind","")=="vehicle"
		if kind=="ranged" and not managing_vehicle:
			start_reload(held)
		elif target is StaticBody3D and target.get_meta("kind","") == "block":
			if held == "connector":
				construction.connect_device(target.get_meta("block"))
			elif construction.maintenance_tool(held) and construction.blocks.get(target.get_meta("block"), {}).get("device", "-") == "":
				if action_lock <= 0.0:
					construction.begin_work(target.get_meta("block"), held)
				return
			elif kind in ["weapon","tool"]:
				heavy_pending = true
		elif kind in ["weapon","tool"] or (_uses_fists(held) and bag.offhand.is_empty() and not managing_vehicle):
			heavy_pending = true
		if managing_vehicle:
			_open_for_player("vehicle", nearby.get_meta("vehicle_id"))
		elif not action_held("fire") and action_lock<=0.0 and not heavy_pending:
			if kind in ["food","med"]:
				player.consume(held)
				action_lock=0.42
			elif kind in ["build","device"] and not context.is_empty() and (not is_instance_valid(target) or target.get_meta("kind","")!="block"):
				if construction.place(construction.target_position(context),held,shape,turn,player.global_position): action_lock=0.28
			elif alternate_uses_offhand() and not action_pressed("offhand_use"):
				_use_offhand()
	if heavy_pending:
		if kind not in ["weapon", "tool"] and not _uses_fists(held):
			heavy_pending = false
			heavy_charge = 0.0
		elif action_held("alternate"):
			heavy_charge = minf(1.0, heavy_charge + delta * 1.85)
		else:
			if action_lock <= 0.0:
				_melee(item, 1.50 + heavy_charge * 0.64)
			heavy_pending = false
			heavy_charge = 0.0
	if kind=="sapling" and not heavy_pending and action_lock<=0.0 and action_pressed("fire"):
		if SaplingPlanting.plant(self,held): action_lock=0.36
		return
	if not heavy_pending and action_lock <= 0.0 and action_held("fire"):
		match kind:
			"ranged":
				_shoot(held, item)
			"weapon", "tool":
				_melee(item, 1.0)
			"", "material":
				_melee({}, 1.0)
			"food", "med":
				if action_pressed("fire"):
					player.consume(held)
					action_lock = 0.42
			"build", "device":
				if action_pressed("fire"):
					var hit := _trace(5.6, 3)
					if not hit.is_empty():
						construction.place(construction.target_position(hit), held, shape, turn, player.global_position)
						action_lock = 0.28
			"vehicle":
				if action_pressed("fire"):
					_place_vehicle(held)

func alternate_uses_offhand() -> bool:
	var id:=bag.current()
	var kind:String=catalog.items.get(id,{}).get("kind","")
	if bag.offhand=="" or id=="field_glasses" or kind in ["weapon","tool","ranged","food","med","build","device"]: return false
	if is_instance_valid(player.mount_vehicle) or action_held("fire"): return false
	var hit:=_trace(5.5,3)
	var target:=hit.get("collider") as StaticBody3D
	if target!=null:
		var target_kind:String=target.get_meta("kind","")
		if target_kind=="vehicle" or (target_kind=="block" and (id=="" or id=="connector")): return false
		if id=="" and _ordinary_chest(target): return false
	return true

func _use_offhand() -> void:
	var id:=bag.offhand
	if replica or id.is_empty() or player.offhand_cooldown>0.0: return
	var used:=false
	match str(catalog.items[id].kind):
		"food","med":
			player.consume(id)
			used=true
		"light":
			if id=="torch":
				player.toggle_lamp()
				used=true
		"build","device":
			var hit:=_trace(5.6,3)
			if not hit.is_empty():
				used=construction.place(construction.target_position(hit),id,shape,turn,player.global_position)
		"seed":
			var hit:=_trace(4.1,3)
			var target: Object=hit.get("collider")
			if is_instance_valid(target) and target.get_meta("kind","")=="crop":
				var plot:Vector3i=target.get_meta("block")
				if construction.crops.has(plot) and str(construction.crops[plot].seed).is_empty():
					construction.farm(plot,id)
					used=true
		"armor":
			bag.toggle_gear(id)
			used=true
		"wire":
			var hit:=_trace(5.5,3)
			var target:Object=hit.get("collider")
			if is_instance_valid(target) and target.get_meta("kind","")=="block":
				construction.connect_device(target.get_meta("block"))
				used=true
		"vehicle":
			var before:=bag.count(id)
			_place_vehicle(id)
			used=bag.count(id)<before
		"tool":
			var hit:=_interaction_trace()
			if id=="filter_pump" and (hit.has("water") or hit.has("cistern")): used=_draw_water(hit.position,true)
			elif id=="hoe" and hit.has("collider") and hit.collider.get_meta("kind","")=="terrain": used=construction.till(hit.position)
	if used: player.offhand_cooldown=0.36

func weapon_hit(from:Vector3, to:Vector3, excluded:Array[RID])->Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(from,to,15 | 32 | RagdollHits.LAYER,excluded)
	query.collide_with_areas=true
	var space:=get_world_3d().direct_space_state
	var hit:=space.intersect_ray(query)
	# Movement capsules fill gaps around the limbs. Only the separate hurt areas count.
	while hit.get("collider") is WastelandCreature:
		var creature:WastelandCreature=hit.collider
		excluded.append(creature.get_rid())
		query.exclude=excluded
		hit=space.intersect_ray(query)
	var lake := stream.lake_wildlife
	if is_instance_valid(lake):
		var wildlife := lake.weapon_hit(from, to if hit.is_empty() else hit.position)
		if not wildlife.is_empty(): return wildlife
	return hit

func _trace(length: float, mask: int, water: bool = false, nature := false, weapon := false) -> Dictionary:
	var from := player.camera.global_position
	var ray := -player.camera.global_basis.z
	var exclusions: Array[RID] = [player.get_rid()]
	if is_instance_valid(player.mount_vehicle):
		exclusions.append(player.mount_vehicle.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from + ray * length, mask, exclusions)
	var hit := weapon_hit(from,from+ray*length,exclusions) if weapon else get_world_3d().direct_space_state.intersect_ray(query)
	if nature:
		var limit: Vector3 = from+ray*length if hit.is_empty() else hit.position
		var first := WastelandTerrainGen.chunk_at(Vector2(minf(from.x,limit.x)-2.5,minf(from.z,limit.z)-2.5))
		var last := WastelandTerrainGen.chunk_at(Vector2(maxf(from.x,limit.x)+2.5,maxf(from.z,limit.z)+2.5))
		for x in range(first.x,last.x+1):
			for z in range(first.y,last.y+1):
				var chunk: WastelandChunk = stream.active.get(Vector2i(x,z))
				if not chunk: continue
				var pick := chunk.trace_nature(from,limit)
				if not pick.is_empty():
					limit = pick.position
					hit = pick
	if water and ray.y < -0.04 and from.y > 0.03:
		var t := -from.y / ray.y
		if t < length and (hit.is_empty() or (hit.position as Vector3).distance_to(from) > t):
			var p := from + ray * t
			if stream.water_at(p):
				return {"water":true,"position":p,"normal":Vector3.UP}
	return hit

func _interaction_trace() -> Dictionary:
	var hit := _trace(4.1, 15 | WastelandEffects.PICKUP_LAYER, true, true)
	if hit.has("collider"):
		var body:Object=hit.collider
		if body.get_meta("kind","")=="terrain":
			var id:=Expeditions.ground_id(self,hit.position)
			if id!="": hit.expedition_id=id
			else:
				var tracks:=hordes.get_node_or_null("Hoofprints")
				if tracks and tracks.has_method("clue"):
					var clue:Dictionary=tracks.clue(hit.position)
					if not clue.is_empty(): hit.trail=clue
			var point:=Vector2(hit.position.x,hit.position.z)
			var loc:=WastelandTerrainGen.chunk_at(point)
			var local:=point-Vector2(loc*32)
			if local.distance_to(OutpostOrders.VAT)<1.15 and stream.generator.site_for(loc)=="lodge":
				hit.cistern=true
			if local.distance_to(OutpostOrders.DEPOT)<1.15 and stream.generator.site_for(loc) in OutpostOrders.RELAYS:
				hit.dispatch_locker=loc
		elif body.has_meta("expedition_id"): hit.expedition_id=body.get_meta("expedition_id")
		elif body.has_meta("cistern"): hit.cistern=true
		elif body.has_meta("dispatch_locker"): hit.dispatch_locker=body.get_meta("cell")
		return hit
	var observation_range := 100.0 if optics_active() else 32.0
	if hit.is_empty():
		var distant := _trace(observation_range, 15)
		var target: Object = distant.get("collider")
		if target is WastelandCreature and target.type in WastelandHordes.WILDLIFE:
			return distant
	var lake_life := stream.lake_wildlife
	if is_instance_valid(lake_life):
		var eye := player.camera.global_position
		var sight: Dictionary = lake_life.observation(eye, -player.camera.global_basis.z, observation_range)
		if not sight.is_empty() and not progress.records.has(_observation_key(sight.type, sight.get("morph", ""))):
			var excluded: Array[RID] = [player.get_rid()]
			if is_instance_valid(player.mount_vehicle):
				excluded.append(player.mount_vehicle.get_rid())
			var ray := PhysicsRayQueryParameters3D.create(eye, sight.point, 1 | 2 | 8, excluded)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				return {"wildlife":sight}
	return hit

func _discover_site(explorer: WastelandSurvivor) -> void:
	var at := Vector2(explorer.global_position.x, explorer.global_position.z)
	var cell := WastelandTerrainGen.chunk_at(at)
	var center := Vector2(cell * WastelandTerrainGen.SIZE) + Vector2.ONE * 16.0
	if at.distance_squared_to(center) > 144.0 or not stream.active.has(cell):
		return
	var site_id := stream.generator.site_for(cell)
	if site_id.is_empty() or progress.records.has("visit_" + site_id):
		return
	var center3 := Vector3(center.x, 0.0, center.y)
	center3.y = stream.ground_at(center3)
	if center3.distance_squared_to(explorer.global_position) > 144.0:
		return
	var site: Dictionary = catalog.sites[site_id]
	var xp := 20 + 5 * int(site.tier)
	gain(xp, "visit_" + site_id)
	var words := "发现%s · 已记入地图  +%d 经验" % [site.name, xp]
	notify(words, 4.0)
	if is_instance_valid(network):
		network.tell(words, 4.0)

func _prompt_action(id:String)->String:
	# A paired client may use touch, a different language layout, or rebound keys.
	return "{action/" + id + "}" if remote_actor else options.action_name(id)

func localized_prompt(text:String)->String:
	if not text.contains("{action/"): return text
	for id:String in ["use","alternate","fire","shape","reload","journal"]:
		text=text.replace("{action/"+id+"}",options.action_name(id))
	return text

func _uses_fists(held: String) -> bool:
	return held.is_empty() or catalog.items.get(held, {}).get("kind") == "material"

func _update_prompt(held: String) -> void:
	var use := _prompt_action("use")
	var alt := _prompt_action("alternate")
	var fire := _prompt_action("fire")
	hint = ""
	focus_damage = -1.0
	var juvenile := interaction.get("collider") as StaticBody3D
	if is_instance_valid(juvenile) and juvenile.get_meta("kind","")=="sapling" and not is_instance_valid(player.mount_vehicle):
		hint=grove.describe(juvenile)
		if held=="shovel" and player.camera.global_position.distance_to(interaction.position)<=float(catalog.items.shovel.reach):
			hint+=" · [%s] 挖起树苗"%fire
		return
	if catalog.items.get(held,{}).get("kind","")=="sapling" and not is_instance_valid(player.mount_vehicle):
		var reason:=SaplingPlanting.obstruction(self,SaplingPlanting.aim(self))
		hint="[%s] 种下%s" % [fire,catalog.title(held)] if reason.is_empty() else reason
		return
	if interaction.has("expedition_id"):
		hint="[%s] %s"%[use,Expeditions.prompt(self,interaction.expedition_id)]
		return
	if interaction.has("dispatch_locker"):
		hint="[%s] 查看中继寄存柜"%use
		var task := Patrol.locker_prompt(self, interaction.dispatch_locker)
		if task != "" and not _dispatch_waiting(interaction.dispatch_locker): hint="[%s] %s"%[use, task]
		return
	if interaction.has("trail"):
		hint="[%s] 足迹 · %s"%[use,interaction.trail.label]
		return
	if interaction.has("wildlife"):
		hint = "%s · [%s] 观察" % [interaction.wildlife.name, use]
		return
	var wildlife: Object = interaction.get("collider")
	if wildlife is WastelandCreature and wildlife.type in WastelandHordes.WILDLIFE:
		var known := _observed(wildlife)
		hint = "%s · %s" % [wildlife.display_name(), "已记录" if known else "[%s] 观察" % use]
		if not known or not is_instance_valid(player.mount_vehicle):
			return
	if is_instance_valid(player.mount_vehicle):
		var fuel: float = player.mount_vehicle.record.fuel
		var target: Object = interaction.get("collider")
		if is_instance_valid(target) and target.get_meta("kind", "") == "buoy":
			hint = fx.pickup_hint(target.get_meta("drop_id"), use)
		else:
			var leave := "离船" if player.mount_vehicle.record.type == "boat" else "下车"
			hint = "[%s] %s  ·  %s" % [use, leave, "脚踏驱动" if player.mount_vehicle.record.type == "bicycle" else "燃料 %.0f" % fuel]
		return
	if interaction.has("water") or interaction.has("cistern"):
		hint = "[%s] 取水 · 营火可煮沸" % use
		if held=="filter_pump":
			hint = "[%s] 复合滤芯 ×1 → 净水 ×4" % use if bag.available_count("composite_filter")>0 else "[%s] 压取净水 · 植物纤维 %d/1" % [use,bag.count("fiber")]
		if held == "boat":
			hint = "[%s] 放下摩托艇  ·  %s" % [fire, hint]
		return
	var object: Object = interaction.get("collider")
	if is_instance_valid(object):
		if object.has_meta("hp_max"):
			focus_damage = float(object.get_meta("hp"))/maxf(1.0,float(object.get_meta("hp_max")))
		match str(object.get_meta("kind","")):
			"loot":
				var record: Dictionary = stream.chunk_diff(object.get_meta("cell")).get("containers",{}).get(object.get_meta("key"),{})
				var title := _cache_title(object)
				var state := Chest.state(record,clock.day(),int(world_settings.loot_days),object.has_meta("submerged_site"))
				var open_key:="[%s]"%use
				if held.is_empty() and _ordinary_chest(object) and not remote_actor and not preload("res://game/ui/touch_layout.gd").active:
					open_key+=" / [%s]"%alt
				if is_instance_valid(loot_target) and loot_target==object:
					hint="%s · 调查中，移开视线取消"%title
				elif _archive_copy(object,record):
					hint = "%s · %s 打开信标备份" % [title,open_key]
				elif state == 2:
					hint = title+" · 已搜空 · %s 打开储物"%open_key
					if not object.has_meta("submerged_site") and int(world_settings.loot_days)>0 and int(record.get("next",-1))>=0:
						hint += " · 第 %d 日补给" % int(record.next)
				else:
					hint = "%s (已搜刮) · %s 打开" % [title,open_key] if state>0 else "%s 搜刮%s (%.1f 秒)" % [open_key,title,_search_duration(object)]
			"note":
				hint = "[%s] 阅读撤离记录" % use
			"trader":
				hint = "[%s] 查看%s公告板" % [use,_station_name(object.get_meta("cell"))]
			"drop", "buoy":
				hint = fx.pickup_hint(object.get_meta("drop_id"), use)
			"stump":
				hint = "[%s] 清除树桩" % fire if held in timber.AXES else "树桩 · 斧头或铲子可清除"
			"vehicle":
				hint = "[%s] 检查待修摩托艇" % use if object.record.get("needs_repair", false) else "[%s] 驾驶  ·  [%s] 维护选项" % [use, alt]
				if object.record.has("hp"): focus_damage=float(object.record.hp)/object.max_hp()
			"crop":
				hint = "[%s] %s" % [use, "收割作物" if construction.crop_ready(object.get_meta("block")) else "播种／查看作物"]
			"terrain":
				if held=="shovel" and _fresh_snow(interaction.position):
					hint="[%s] 铲取积雪 · 营火可融煮净水"%fire
				elif held in ["shovel","iron_pick"]:
					var layer := _dig_layer(interaction.position)
					hint = "[%s] 挖掘%s · %s" % [fire,layer[0],"铁镐高效" if layer[1] else "工兵铲高效"]
			"resource":
				var resource: String = object.get_meta("resource")
				hint = RESOURCES[resource][0] + ("  ·  [%s] 采集" % fire)
				var hp := float(RESOURCES[resource][1])
				var partial: Dictionary=stream.chunk_diff(object.get_meta("cell")).get("resources",{})
				focus_damage=float(partial.get(object.get_meta("index"),hp))/hp
				if HARVEST_TOOLS.has(resource):
					var best: String=HARVEST_TOOLS[resource]
					hint += "  ·  " + ("专精采集" if held==best else "推荐"+catalog.title(best))
					if focus_damage<1.0:
						hint += "  ·  余量 %d%%" % ceili(focus_damage*100.0)
				if resource=="grass":
					hint="[%s] 打破草丛，捡植物纤维"%fire
				elif resource in PICKUPS:
					hint="[%s] 拾取%s · %s"%[use,RESOURCES[resource][0],catalog.requirements(RESOURCES[resource][2])]
				elif _uses_fists(held) and resource in ["oak","pine"]:
					hint="[%s] 徒手砍树 · 每拳损失 %d 生命" % [fire, _hand_impact_damage(object, interaction.position)]
				elif object.has_meta("tree_model"):
					hint="[%s] 砍伐%s" % [fire,timber.NAMES.get(object.get_meta("tree_model"),RESOURCES[resource][0])]
					if focus_damage<0.36: hint+=" · 即将倾倒"
				elif _uses_fists(held) and LOOSE_MATERIALS.has(resource):
					var picked: Dictionary = stream.chunk_diff(object.get_meta("cell")).get("hand_picked",{})
					if picked.has(object.get_meta("index")):
						hint = "%s · 余下部分需用工具采集" % RESOURCES[resource][0]
					else:
						hint = "[%s] 敲落松石 · 每拳损失 %d 生命" % [fire, _hand_impact_damage(object, interaction.position)]
			"poi_wall":
				if object.has_meta("timber_wall"):
					var reach:=float(catalog.items.get(held,{}).get("reach",2.58))
					if player.camera.global_position.distance_to(interaction.position)<=reach:
						var wall_type:="木墙" if object.get_meta("timber_wall") else "砌体墙"
						if _uses_fists(held) or catalog.items.get(held,{}).get("kind","") in ["tool","weapon"]:
							hint="%s · 按住[%s]拆墙"%[wall_type,fire]
					else: focus_damage=-1.0
			"block":
				var cell: Vector3i = object.get_meta("block")
				var info: Dictionary = construction.blocks.get(cell, {})
				if not info.is_empty():
					var device: String = info.device
					focus_damage = float(info.hp) / construction._max_hp(info)
					if held=="reinforcement_kit" and (device != "" or int(info.tier) > 0):
						hint = "[%s] "%use + construction.reinforcement_text(cell)
					elif device != "":
						hint = "[%s] %s" % [use, catalog.title(device)]
						if held == "connector":
							hint += "  ·  [%s] 接线" % alt
					else:
						var actions := PackedStringArray()
						if int(info.tier) == 0:
							actions.append("[%s] 回收木框架" % use)
						elif int(info.shape) == 4:
							actions.append("[%s] 开关活板门" % use)
						if construction.maintenance_tool(held) and (int(info.tier) < 4 or focus_damage < 1.0):
							actions.append("[%s] %s" % [alt, construction.upgrade_text(cell)])
						if actions.is_empty():
							actions.append("%s %d/%d" % [WastelandCatalog.TIER_NAMES[int(info.tier)], ceili(info.hp), int(construction._max_hp(info))])
						hint = "  ·  ".join(actions)
			_:
				if object is WastelandCreature and object.active:
					hint = object.display_name()
					focus_damage = object.hp / object.max_health()
	if held == "frame" and hint.is_empty() and not building_hit.is_empty():
		hint = "[%s] 放置%s  ·  [%s] 切换形状" % [fire, WastelandCatalog.SHAPE_NAMES[shape], _prompt_action("shape")]
	if catalog.items.get(held, {}).get("kind") == "ranged" and int(bag.magazine.get(held, 0)) <= 0 and hint.is_empty():
		hint = "[%s] 装填" % _prompt_action("reload")
	if held=="field_glasses" and hint.is_empty():
		hint = "三倍观测 · 对准动物按 [%s] 记录" % use if action_held("alternate") else "按住 [%s] 使用三倍观测镜" % alt
	if near_board(true):
		hint = "[%s] 从委托手记重建公告板" % _prompt_action("journal")

func _use() -> void:
	var hit := _interaction_trace()
	var object: Object = hit.get("collider")
	if is_instance_valid(object) and object.get_meta("kind","")=="resource" and object.get_meta("resource","") in PICKUPS:
		_harvest(object,10,0,hit.position,object.get_meta("resource") in ["fallen_stick","pebble"])
		return
	if hit.has("expedition_id"):
		Expeditions.use(self,hit.expedition_id)
		return
	if hit.has("dispatch_locker"):
		if _dispatch_waiting(hit.dispatch_locker) or not Patrol.use_locker(self, hit.dispatch_locker):
			collect_dispatch(hit.dispatch_locker)
		return
	if hit.has("trail"):
		var trail:Dictionary=hit.trail
		if not recent_trails.has(trail.key):
			if recent_trails.size()>=64: recent_trails.pop_front()
			recent_trails.append(trail.key)
			achievements.add("track_"+str(trail.species))
			preload("res://game/sim/nature_journal.gd").track(self,trail)
		notify(trail.label)
		return
	if hit.has("wildlife"):
		_record_observation(hit.wildlife.type, hit.wildlife.name, hit.wildlife.get("morph", ""))
		return
	if object is WastelandCreature and object.type in ["fox","hare"] and player.crouch>=0.8:
		achievements.mark("cat_interview")
	if object is WastelandCreature and object.type in WastelandHordes.WILDLIFE and not _observed(object):
		_record_observation(object.type, object.display_name(), object.morph)
		return
	if is_instance_valid(object) and object.get_meta("kind", "") == "buoy":
		fx.take_drop(object.get_meta("drop_id"))
		return
	if is_instance_valid(player.mount_vehicle):
		player.dismount()
		return
	if hit.has("water") or hit.has("cistern"):
		if action_lock <= 0.0:
			action_lock = 0.82
			_draw_water(hit.position,bag.current()=="filter_pump")
		return
	if not is_instance_valid(object):
		return
	match str(object.get_meta("kind","")):
		"loot":
			_inspect_chest(object,hit)
		"drop":
			fx.take_drop(object.get_meta("drop_id"))
		"trader":
			_open_for_player("trade", null)
		"note":
			_open_for_player("note", object.get_meta("text"))
		"crop":
			construction.farm(object.get_meta("block"), bag.current())
		"block":
			var cell: Vector3i = object.get_meta("block")
			var info: Dictionary = construction.blocks.get(cell, {})
			if not info.is_empty() and info.device == "" and int(info.tier) == 0:
				construction.recover_frame(cell)
			elif bag.current()=="reinforcement_kit":
				construction.reinforce(cell)
			elif not info.is_empty() and info.device != "":
				_open_for_player("craft" if WastelandCatalog.STATIONS.has(info.device) else "device", cell)
			elif int(info.get("shape",0)) == 4:
				construction.toggle_hatch(cell)
		"vehicle":
			if object.record.get("needs_repair", false) or action_held("alternate"):
				_open_for_player("vehicle", object.get_meta("vehicle_id"))
			elif object.occupied:
				notify("队友正在驾驶该载具")
			else:
				player.ride(object)

func _observed(actor: WastelandCreature) -> bool:
	return progress.records.has(_observation_key(actor.type, actor.morph))

func _observation_key(id: String, morph: String) -> String:
	return "observe_" + id + ("" if morph.is_empty() else "_" + morph)

func _draw_water(at:Vector3,filtered:bool)->bool:
	if filtered and bag.available_count("composite_filter")>0: return draw_filtered_batch(at,4)
	if filtered and not bag.spend({"fiber":1}):
		notify("滤芯需要一份植物纤维")
		return false
	if bag.add("clean_water" if filtered else "dirty_water",1)==0:
		if filtered:bag.add("fiber",1)
		notify("背包已满，腾出空间后再取水")
		return false
	audio.play_at("splash",at,0.53)
	if filtered:
		player.hand.swing_attack(0.45)
		achievements.add("pump_water")
		achievements.add("got_safe_water")
	notify("滤芯已更换 · 取得一份净水" if filtered else "取得生水 · 可在营火煮沸")
	return true

func draw_filtered_batch(at:Vector3, servings:int)->bool:
	if replica or not bag.has_all({"composite_filter":1}): return false
	var free_slots := maxi(0,bag.capacity()-bag.occupied())
	if bag.count("composite_filter")%bag.stack_size("composite_filter")==1 and bag.occupied()<=bag.capacity(): free_slots+=1
	var stack:=bag.stack_size("clean_water")
	if free_slots*stack+posmod(-bag.count("clean_water"),stack)<servings:
		notify("需要容纳 %d 份净水的背包空间，滤芯已保留"%servings)
		return false
	bag.spend({"composite_filter":1})
	bag.add("clean_water",servings)
	achievements.add("pump_water")
	achievements.add("got_safe_water",servings)
	audio.play_at("splash",at,0.66)
	notify("复合滤芯已用完 · 净水 ×%d"%servings)
	return true

func _record_observation(id: String, species_name: String, morph: String = "") -> void:
	var key := "observe_" + id
	var detail := _observation_key(id, morph)
	if progress.records.has(detail):
		return
	var xp := 15 if progress.records.has(key) else 40
	gain(xp, detail)
	progress.records[key] = 1
	preload("res://game/sim/nature_journal.gd").observe(self,id,morph)
	var words := "观察到%s · 已记入地图  +%d 经验" % [species_name, xp]
	notify(words, 4.0)
	if is_instance_valid(network):
		if remote_actor:
			message.emit(words, 4.0)
			network.broadcast_message(words,4.0,actor_peer_id)
		else:
			network.tell(words, 4.0)

func _ordinary_chest(body:Object)->bool:
	return is_instance_valid(body) and body.get_meta("kind","")=="loot" and not body.get_meta("quest",false) and not body.has_meta("submerged_site")

func _inspect_chest(body:StaticBody3D,hit:Dictionary)->void:
	interaction=hit
	if loot_target==body: return
	var record:Dictionary=stream.chunk_diff(body.get_meta("cell")).get("containers",{}).get(body.get_meta("key"),{})
	if Chest.state(record,clock.day(),int(world_settings.loot_days),body.has_meta("submerged_site"))!=0:
		loot_target=null
		loot_ratio=0
		_open_loot(body)
		return
	loot_target=body
	search_start=player.global_position
	search_slot=bag.active
	search_held=bag.current()
	loot_ratio=0
	loot_time=0
	loot_full=_search_duration(body)
	audio.play_at("search",body.global_position,0.75)

func _search_duration(body:Object)->float:
	return float(catalog.loot[body.get_meta("type")].time)*(1.0-progress.rank("scavenger")*0.12)

func _tick_loot(delta: float) -> void:
	loot_ratio = 0.0
	if interaction.get("collider") != loot_target or search_slot!=bag.active or search_held!=bag.current() or search_start.distance_squared_to(player.global_position)>0.85*0.85:
		loot_target = null
		return
	loot_time += delta
	loot_ratio = clampf(loot_time / maxf(0.2, loot_full), 0, 1)
	if loot_ratio < 1.0:
		return
	if _interaction_trace().get("collider")==loot_target:
		_open_loot(loot_target)
	loot_target = null
	loot_ratio = 0.0

func _cache_title(object: Object) -> String:
	var table: String = object.get_meta("type")
	var category: String = catalog.loot[table].name
	if object.get_meta("building_cache",false):
		return "任务保险柜 · "+category if object.get_meta("quest",false) else category
	var profile: String = object.get_meta("cache_profile","")
	if not Chest.NAMES.has(profile): return category
	if table == profile+"_cache" or object.has_meta("submerged_site") or table == "cabin": return Chest.NAMES[profile]
	return "%s · %s" % [Chest.NAMES[profile],category]

func _container_record(object: StaticBody3D) -> Dictionary:
	var loc: Vector2i = object.get_meta("cell")
	var id: String = object.get_meta("key")
	var diff := stream.edit_chunk(loc)
	if not diff.has("containers"):
		diff.containers = {}
	var record: Dictionary = diff.containers.get(id, {})
	var submerged := object.has_meta("submerged_site")
	var stored:Dictionary=record.get("stored",{})
	var reset:=Chest.state(record,clock.day(),int(world_settings.loot_days),submerged)==0
	if not reset and not stored.is_empty() and not submerged and int(world_settings.loot_days)>0:
		reset=record.items==stored and int(record.get("next",-1))>=0 and clock.day()>=int(record.next) and cache_inventory.occupied(self,stored)<cache_inventory.CAPACITY
	if reset:
		var loot_id: String = object.get_meta("type")
		var seed_value := stream.generator.seed_at(loc, id.hash()) ^ clock.day() * 71137
		var loot_stage := hordes.stage()
		if stream.generator.site_revision>0 and record.is_empty():
			# The first stock belongs to the place; later restocks follow world progression.
			seed_value=stream.generator.seed_at(loc,id.hash())
			var site_id:=stream.generator.site_for(loc)
			var tier:=int(catalog.sites.get(site_id,{}).get("tier",1))
			loot_stage=2+(tier-1)*6
		var abundance := float(world_settings.loot) * (1.0 + progress.rank("scavenger") * 0.15)
		record = {"items":catalog.roll_loot(loot_id, seed_value, abundance, loot_stage), "next":-1 if submerged else clock.day()+int(world_settings.loot_days), "earned":false,"searched":true}
		var bonus_table := str(object.get_meta("cache_biome",object.get_meta("cache_profile","")))+"_cache"
		var staples: Array = []
		if object.get_meta("building_cache",false):
			bonus_table = loot_id
			staples = catalog.loot[loot_id].get("staples",[])
		elif loot_id == bonus_table:
			bonus_table = ""
		if catalog.loot.has(bonus_table):
			var bonus := catalog.roll_loot(bonus_table,seed_value^54173,abundance,loot_stage,1,staples)
			for supply in bonus:
				record.items[supply] = int(record.items.get(supply,0))+int(bonus[supply])
		if object.get_meta("quest", false):
			record.items.beacon_log = 1
		if not stored.is_empty():
			var fresh:Dictionary=record.items
			record.items=stored.duplicate()
			record.stored=stored
			for item:String in fresh:
				var add:=mini(fresh[item],cache_inventory.room(self,record.items,item))
				if add>0: record.items[item]=int(record.items.get(item,0))+add
		diff.containers[id] = record
	if _archive_copy(object,record):
		record.items["beacon_log"] = 1
	return record

func _open_loot(object: StaticBody3D) -> void:
	cache_inventory.open(self,object)

func chest_key(peer:int=WastelandLan.HOST_ID)->String:
	return cache_inventory.actors.get(peer,"")

func chest_view(key:String)->Dictionary:
	return cache_inventory.view(self,key)

func chest_move(key:String,action:String,item:String="",amount:int=1)->int:
	return cache_inventory.move(self,key,action,item,amount)

func chest_close(key:String)->void:
	if key==chest_key(actor_peer_id): chest_leave(actor_peer_id)

func chest_leave(peer:int)->void:
	cache_inventory.leave(self,peer)

func chest_lids()->Array[String]:
	return cache_inventory.lids()

func apply_chest_lids(keys:Array)->void:
	cache_inventory.apply_lids(self,keys)

func _melee(item: Dictionary, power: float) -> void:
	if replica: return
	var cost := float(item.get("stamina_cost",5.6)) * (2.2 if power>1.2 else 1.0)
	if item.get("kind","")=="tool":
		cost *= 1.0-bag.gear_bonus("tool_saving")
	if player.stamina < cost:
		action_lock = 0.43
		return
	player.stamina -= cost
	action_lock = float(item.get("cooldown", 0.61)) + (0.21 if power > 1.2 else 0.0)
	player.hand.swing_attack(power)
	var hit := _trace(float(item.get("reach", 2.58)), 15, false, true, true)
	if hit.is_empty():
		audio.play_at("bow", player.camera.global_position + Vector3.FORWARD * 0.2, 0.17, false)
		return
	player.hit_stop=0.045
	player.impact_kick=0.105
	var amount := float(item.get("damage", 9.0)) * power * (1.0 + progress.rank("melee") * 0.17)
	var punching: bool = _uses_fists(bag.current()) and item.get("kind", "") in ["", "material"]
	if _strike_remains(hit,player.camera.global_position,amount): return
	if hit.has("aquatic"):
		var landed := _strike_lake_wildlife(hit,amount,player,player.global_position,power>1.35 or item.get("bouncy",false),true)
		if landed and punching and int(hit.get("hand_damage",0)) > 0:
			player.hurt_hand(int(hit.hand_damage),"hard_impact")
		return
	var body: CollisionObject3D = hit.collider
	if body.is_queued_for_deletion(): return
	var hand_damage := _hand_impact_damage(body, hit.position, int(hit.get("shape",-1))) if punching else 0
	var hit_bark: bool = body.get_meta("resource", "") in ["oak", "pine"]
	if body.has_meta("hit_zone") or body is WastelandCreature:
		_strike_creature(hit,amount,player,power>1.35 or item.get("bouncy",false),true)
		if item.get("bouncy",false): audio.play_at("bow",hit.position,0.8,false)
	elif body is WastelandVehicle:
		_damage_vehicle(body,amount,hit.position,hit.normal)
	elif body.has_meta("kind"):
		match str(body.get_meta("kind")):
			"sapling":
				if bag.current()=="shovel": grove.uproot(body)
			"stump":
				timber.clear_stump(body, hit.position)
			"resource":
				_harvest(body, amount, int(item.get("power", 0)), hit.position)
			"block", "poi_wall", "loot", "trader", "note", "crop", "buoy":
				if body.get_meta("kind")=="block" and bag.current().is_empty() and bag.offhand.is_empty():
					var piece: Dictionary=construction.blocks.get(body.get_meta("block"),{})
					if piece.get("tier",-1)==0 and piece.get("device","")=="":
						achievements.add("inspect_frame")
						if power<=1.0: amount=minf(amount,5.0)
				var sound:="chop"
				if body.has_meta("timber_wall"):
					var timber:bool=body.get_meta("timber_wall")
					var held:=bag.current()
					if (timber and held in ["stone_axe","iron_axe","steel_axe"]) or (not timber and held in ["iron_pick","sledge"]):
						amount*=1.65
					sound="chop" if timber else "stone"
					fx.burst(hit.position+hit.normal*0.04,Color("#a78559") if timber else Color("#a39a87"),0.36)
				hit_wall(body,amount*1.1,hit.position,hit.normal)
				audio.play_at(sound, hit.position, 0.59)
				player.emit_noise(hit.position, 14.0 if item.get("kind","")=="tool" else 9.0)
			"terrain":
				var pick := bag.current()=="iron_pick"
				if item.get("dig", false) or pick:
					var layer := _dig_layer(hit.position)
					var depth := 0.76 if pick==bool(layer[1]) else 0.32
					stream.excavate(hit.position,depth*power)
					drop_materials(hit.position,layer[2],hit.normal)
					notify("挖出%s · 靠近拾取" % layer[0],1.5)
					gain(5, "dig")
				elif item.get("till", false) and construction.till(hit.position):
					notify("已开垦 · 选中种子交互")
				audio.play_at("stone", hit.position, 0.53)
				fx.burst(hit.position, Color("#9e786e"), 0.40)
	if hand_damage > 0:
		player.hurt_hand(hand_damage, "bark" if hit_bark else "hard_impact")

func _hand_impact_damage(body: CollisionObject3D, at: Vector3, shape_id := -1) -> int:
	if body.has_meta("hit_zone"):
		var creature := body.get_parent() as WastelandCreature
		if not creature: return 0
		var bone := creature.impact_bone(body,shape_id,at) if shape_id >= 0 else &""
		return creature.hand_impact_damage(body.get_meta("hit_zone"), player.global_position,bone)
	var material := ""
	match str(body.get_meta("kind", "")):
		"resource":
			match str(body.get_meta("resource")):
				"pebble": return 1
				"oak", "pine", "driftwood": material = "wood"
				"boulder", "ore", "bedrock", "iron_vein": material = "stone"
				"machine_wreck", "salvage": material = "scrap"
		"stump", "trader": material = "wood"
		"vehicle": material = "metal"
		"buoy": return 2
		"block": material = construction.surface_material(body.get_meta("block"))
		"loot": material = Chest.casing_material(body.get_meta("cache_profile", ""))
		"poi_wall":
			var chunk: WastelandChunk = stream.active.get(body.get_meta("cell"))
			var site := chunk.site if chunk != null else ""
			return StructuralSalvage.hand_impact_damage(body, site)
		"terrain":
			if body.has_meta("rock_surface") or _dig_layer(at)[1]:
				material = "stone"
	return StructuralSalvage.material_hand_damage(material) if not material.is_empty() else 0

func _fresh_snow(at: Vector3) -> bool:
	var sample:=Vector2i(roundi(at.x),roundi(at.z))
	return (not stream.digs.has(WastelandTerrainGen.grid_key(sample))
		and stream.generator.snow_cover(sample.x,sample.y,at.y)>=0.50)

func _dig_layer(at: Vector3) -> Array:
	var key := WastelandTerrainGen.grid_key(Vector2i(roundi(at.x),roundi(at.z)))
	var depth := -float(stream.digs.get(key,0.0))
	if _fresh_snow(at): return ["积雪",false,{"packed_snow":2}]
	if depth<0.65 and stream.generator.road_strength(at.x,at.z)>0.75: return ["路面",true,{"stone":2}]
	if depth>=2.2 or (stream.generator.region_kind(at.x,at.z) in ["alpine","canyon"] and depth>=1.0):
		return ["岩层",true,{"stone":3}]
	if stream.generator.region_kind(at.x,at.z)=="desert": return ["沙层",false,{"sand":3}]
	return ["泥土",false,{"clay":2,"sand":2}]

func _harvest(body: StaticBody3D, amount: float, tool: int, impact: Vector3, picked_up := false) -> void:
	if replica or not is_instance_valid(body) or body.is_queued_for_deletion(): return
	var kind: String = body.get_meta("resource")
	var row: Array = RESOURCES[kind]
	var loc: Vector2i = body.get_meta("cell")
	var id: String = body.get_meta("index")
	var harvest := stream.edit_chunk(loc)
	if not harvest.has("resources"): harvest.resources = {}
	if not harvest.has("removed"): harvest.removed = {}
	var tree := kind in ["oak","pine","brush"]
	var punching := tool == 0 and _uses_fists(bag.current())
	if harvest.removed.has(id):
		return
	if punching and LOOSE_MATERIALS.has(kind):
		if not harvest.has("hand_picked"):
			harvest.hand_picked = {}
		if harvest.hand_picked.has(id):
			notify("这里的松散材料已取走，余下部分需要工具",1.5)
			return
		harvest.hand_picked[id] = true
		var loose: Dictionary = LOOSE_MATERIALS[kind]
		drop_materials(impact,loose,(player.eyes.global_position-impact).normalized())
		gain(3,"gather",3)
		audio.play_at("stone",impact,0.44)
		fx.burst(impact,Color("#a6a2a0"),0.33)
		player.emit_noise(impact,4.0)
		notify("敲落松石 · 靠近拾取",1.7)
		return
	var plant := kind in ["herb_patch","reed_bed","cactus","grass","reeds","pondweed"]
	if tool == 0 and kind not in LOOSE_SCENERY and kind != "brush" and not (punching and (tree or plant)):
		notify("需要斧头或采集工具")
		return
	var before := float(harvest.resources.get(id, row[1]))
	var specialist: bool=HARVEST_TOOLS.get(kind,"?")==bag.current()
	var effort:=maxf(10.0,amount)*(0.86+tool*0.33)
	if HARVEST_TOOLS.has(kind):
		effort *= 1.65 if specialist else 0.67 if not plant else 0.90
	var after := maxf(0.0,before-effort)
	var trunk := body.has_meta("tree_pose")
	var cut := {}
	if trunk:
		cut = timber.mark(body, impact, 1.0 - after / float(row[1]), harvest)
	if specialist:
		if not harvest.has("specialist_work"):
			harvest.specialist_work={}
		harvest.specialist_work[id]=float(harvest.specialist_work.get(id,0.0))+before-after
	var color := Color("#c09168") if tree else Color("#97879c")
	if plant: color=Color("#99aa67") if kind=="reed_bed" else Color("#d1aecf")
	elif kind=="iron_vein" or kind=="machine_wreck": color=Color("#b47852")
	audio.play_at("chop" if tree or plant else "stone", impact, 0.55 if plant else 0.75)
	fx.burst(impact, color, 0.63)
	hordes.add_heat(impact, 0.41)
	player.emit_noise(impact, 4.0 if plant else 14.0)
	var gained_sample := ""
	if HARVEST_SAMPLES.has(kind) and before>float(row[1])*0.5 and after<=float(row[1])*0.5:
		gained_sample=HARVEST_SAMPLES[kind]
		drop_materials(impact,{gained_sample:1},(player.eyes.global_position-impact).normalized())
		gain(3,"gather_"+kind)
	if after > 0.0:
		harvest.resources[id] = after
		if trunk:
			stream.active[loc].sync_tree_cut(id,cut,{},true)
		var title: String = timber.NAMES.get(cut.model,row[0]) if trunk else row[0]
		notify("%s · 余量 %d%%" % [title, ceili(after*100.0/row[1])] + (" · 掉出"+catalog.title(gained_sample) if gained_sample!="" else ""),1.2)
		return
	harvest.resources.erase(id)
	harvest.removed[id] = true
	var loot: Dictionary = {}
	var work: Dictionary=harvest.get("specialist_work",{})
	var bonus := 1.4 if float(work.get(id,0.0))>=float(row[1])*0.40 else 1.0
	work.erase(id)
	for key in row[2]:
		loot[key] = maxi(1, roundi(float(row[2][key]) * bonus * (1.0 + progress.rank("harvest") * 0.18)))
	if trunk:
		timber.fell(body, cut, loot)
	elif picked_up:
		award(loot, impact)
	else:
		drop_materials(impact,loot,(player.eyes.global_position-impact).normalized())
	gain(2 if kind in LOOSE_SCENERY else 25 if tree else 20, "wood" if loot.has("wood") else "gather", int(loot.get("wood",1)))
	if kind in PICKUPS and not progress.records.has("gather_"+kind):
		gain(1,"gather_"+kind)
	var collected:=loot.duplicate()
	if not gained_sample.is_empty():
		collected[gained_sample]=int(collected.get(gained_sample,0))+1
	if trunk:
		notify("树要倒了！向侧面避开",1.8)
		return
	var verb:="拾取" if picked_up else "掉出"
	notify("%s%s · %s%s" % [row[0]," · 专精采收" if bonus>1.0 else "",verb,catalog.requirements(collected)])
	if kind in ["grass","brush"] and punching and player.crouch>=0.8: achievements.add("weed_paws")
	stream.active[loc].remove_resource(body)

func wall_health(body: StaticBody3D) -> float:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or body.collision_layer == 0:
		return 0.0
	match str(body.get_meta("kind", "")):
		"block":
			return float(construction.blocks.get(body.get_meta("block"), {}).get("hp", 0.0))
		"poi_wall":
			return float(body.get_meta("hp", 0.0))
	return 0.0

func hit_wall(body: StaticBody3D, amount: float, contact:=Vector3.INF, normal:=Vector3.UP) -> void:
	if replica or not is_instance_valid(body) or body.is_queued_for_deletion() or body.collision_layer==0 or amount<=0:
		return
	var at:=contact if contact.is_finite() else body.global_position
	var type := str(body.get_meta("kind",""))
	if type == "block":
		construction.damage(body.get_meta("block"), amount)
	elif WastelandChunk.FIXTURE_HP.has(type):
		var loc: Vector2i = body.get_meta("cell")
		var id: String = body.get_meta("key")
		var diff := stream.edit_chunk(loc)
		if not diff.has("fixture_health"): diff.fixture_health = {}
		var hp := maxf(0.0,float(body.get_meta("hp"))-amount)
		if hp==0.0:
			var contents := {}
			if type=="loot":
				var record := _container_record(body)
				contents = record.items.duplicate()
				record.items.clear()
				var casing := Chest.casing_material(body.get_meta("cache_profile",""))
				contents[casing]=int(contents.get(casing,0))+1
				if not contents.is_empty() and not record.earned:
					gain(21,"loot")
					record.earned = true
			elif type=="trader":
				contents = {"wood":2}
				notify("公告板已拆除 · 可在原址打开委托手记重建",3.0)
			elif type=="note": contents={"fiber":1}
			if not contents.is_empty(): drop_materials(at,contents,normal)
			fx.collapse(body.global_position,Color("#967c60"))
		diff.fixture_health[id]=hp
		stream.active[loc].sync_fixtures()
	elif type=="crop":
		construction.remove_plot(body.get_meta("block"))
	elif type=="buoy":
		var id: String = body.get_meta("drop_id")
		if fx.drop_records.has(id):
			var contents: Dictionary = fx.drop_records[id].items
			var buoy_at := body.global_position
			fx.erase_drop(id)
			fx.collapse(buoy_at,Color("#db9d62"))
			drop_materials(buoy_at,contents,normal)
	elif type == "poi_wall":
		var loc: Vector2i = body.get_meta("cell")
		var id: String = body.get_meta("site_id")
		var diff := stream.edit_chunk(loc)
		if not diff.has("site_damage"): diff.site_damage = {}
		var hp := maxf(0.0, float(body.get_meta("hp")) - amount)
		diff.site_damage[id] = hp
		if body.has_meta("timber_wall"):
			if hp>0:
				if not diff.has("wall_marks"): diff.wall_marks={}
				if not diff.wall_marks.has(id): diff.wall_marks[id]=at
			elif diff.has("wall_marks"): diff.wall_marks.erase(id)
		if hp <= 0.0:
			achievements.add("demolished_structure")
			fx.collapse(body.global_position, Color("#8d7685"))
			stream.nav_dirty[loc] = true
		var chunk: WastelandChunk = stream.active.get(loc)
		if chunk!=null and chunk.structures.has(id):
			var salvage := StructuralSalvage.materials(chunk,id) if hp<=0 else {}
			chunk.set_structure_health(id,hp,hp<=0 and chunk.support_graph.has(id))
			if hp<=0:
				drop_materials(at,salvage,normal)
				stream.record_settlement(chunk,true)
				stream.settle_interactables(loc)
		else:
			body.set_meta("hp",hp)
			if hp<=0:
				body.collision_layer=0
				body.hide()
				body.queue_free()

func start_reload(id: String) -> void:
	if reload_id == id:
		return
	var item: Dictionary = catalog.items[id]
	if int(bag.magazine.get(id, 0)) >= int(item.mag):
		return
	if bag.count(item.ammo) <= 0:
		notify("缺少 " + catalog.title(item.ammo), 1.4)
		return
	reload_id = id
	reload_span = float(item.delay) * (1.0 - progress.rank("firearms") * 0.085)
	reload_left = reload_span
	audio.play_at("reload", player.camera.global_position + Vector3.DOWN * 0.22, 0.70, false)

func _tick_reload(delta: float) -> void:
	if reload_id == "" or reload_id != bag.current():
		reload_id = ""
		player.hand.reload_ratio = 0.0
		return
	reload_left -= delta
	player.hand.reload_ratio = clampf(reload_left / reload_span, 0.0, 1.0)
	if reload_left > 0.0:
		return
	var item: Dictionary = catalog.items[reload_id]
	var current := int(bag.magazine.get(reload_id,0))
	var moved := mini(int(item.mag) - current, bag.count(item.ammo))
	if bag.spend({item.ammo:moved}):
		bag.set_loaded_rounds(reload_id, current + moved)
	reload_id = ""

func _shoot(id: String, item: Dictionary) -> void:
	if reload_id != "":
		return
	var loaded := int(bag.magazine.get(id, 0))
	if loaded <= 0:
		start_reload(id)
		action_lock = 0.40
		return
	bag.set_loaded_rounds(id, loaded - 1)
	action_lock = float(item.cooldown)
	var origin := player.camera.global_position
	var bow: bool = item.ammo == "arrow"
	var aim:=player.camera.global_basis
	var spread:=player.shot_spread()*(0.55 if bow else 1.0)
	var theta:=randf()*TAU
	var radius:=sqrt(randf())*spread
	var ahead:=(-aim.z+radius*(aim.x*cos(theta)+aim.y*sin(theta))).normalized()
	var speed := 62.0 if id=="field_crossbow" else 40.0 if bow else 122.0
	var hit := float(item.damage) * (1.0 + progress.rank("firearms") * 0.14)
	fx.projectile(origin + ahead * 0.19, ahead * speed, player, "arrow" if bow else "bullet", hit)
	player.hand.recoil(not bow)
	player.look(Vector2(randf_range(-0.015, 0.015), -0.029 if bow else -0.048))
	audio.play_at("bow" if bow else "shot", origin + ahead * 0.5, 0.77 if bow else 1.14, false)
	hordes.add_heat(origin, 0.62 if bow else 6.8)
	player.emit_noise(origin, 9.0 if bow else 35.0)

func _strike_creature(hit:Dictionary, amount:float, source:Node3D, heavy:bool, melee:=false)->void:
	var body: Object = hit.collider
	var zone:=str(body.get_meta("hit_zone","torso"))
	var actor:=body as WastelandCreature if body is WastelandCreature else body.get_parent() as WastelandCreature
	if not is_instance_valid(actor) or not actor.active or actor.hp<=0: return
	var origin:=source.global_position if is_instance_valid(source) else actor.global_position
	var shooter:=source as WastelandSurvivor
	var stealth:=is_instance_valid(shooter) and shooter.crouch>=0.8 and not actor.alerted
	if body.has_meta("hit_zone"):
		var bone := actor.impact_bone(body,int(hit.get("shape",-1)),hit.position)
		actor.hit_zone(zone,amount,origin,heavy,stealth,hit.position,bone)
	else:
		actor.take_hit(amount,origin,heavy)
	if is_instance_valid(shooter):
		if melee: actor.hit_pause=0.045
		_confirm_hit(shooter,zone=="head",melee)

func _confirm_hit(shooter: WastelandSurvivor, head: bool, melee: bool) -> void:
	shooter.confirmed_hit += 1
	shooter.confirmed_head = head
	shooter.confirmation_left = 0.19
	shooter.confirmed_melee = melee

func _strike_lake_wildlife(hit: Dictionary, amount: float, source: Node3D, origin: Vector3, heavy: bool, melee: bool) -> bool:
	if not stream.lake_wildlife.strike(hit,amount,origin,heavy): return false
	if source is WastelandSurvivor: _confirm_hit(source,false,melee)
	audio.play_at("hit",hit.position,0.50)
	return true

func _lake_impact_changed() -> void:
	if not replica:
		_schedule_world_save()
		if is_instance_valid(network) and network.server():
			network.mirror_lake_combat(stream.lake_wildlife)

func _strike_remains(hit: Dictionary, origin: Vector3, amount: float) -> bool:
	var motion := RagdollHits.strike(hit,origin,amount)
	if motion.is_empty(): return false
	if is_instance_valid(network) and network.server(): network.mirror_corpse_hit(motion)
	return true

func projectile_hit(kind: String, damage: float, hit: Dictionary, source: Node3D, origin: Vector3 = Vector3.INF) -> void:
	if _strike_remains(hit,origin,damage): return
	if hit.has("aquatic"):
		_strike_lake_wildlife(hit,damage,source,origin,false,false)
		return
	var body: Object = hit.collider
	var normal:Vector3=hit.get("normal",Vector3.UP)
	if kind == "acid":
		fx.burst(hit.position, Color("#abc876"), 1.15)
		if body is WastelandSurvivor:
			body.damage(damage, "acid", origin,hit.position)
		elif body is WastelandVehicle:
			for person:WastelandSurvivor in living_players():
				if person.mount_vehicle==body:
					person.damage(damage,"acid",origin)
					return
			_damage_vehicle(body,damage,hit.position,normal)
		elif body is StaticBody3D:
			if normal.y > 0.58:
				hordes.infected_effect("residue", hit.position + normal * 0.025,normal)
			hit_wall(body,damage*1.15,hit.position,normal)
		return
	if body.has_meta("hit_zone") or body is WastelandCreature:
		_strike_creature(hit,damage,source,false)
	else:
		fx.burst(hit.position, Color("#cda694"), 0.48)
		if body is StaticBody3D:
			hit_wall(body,damage*0.64,hit.position,normal)
		elif body is WastelandVehicle:
			_damage_vehicle(body,damage*0.64,hit.position,normal)

func can_craft(id: String, station: String) -> bool:
	var def: Dictionary = catalog.recipes.get(id, {})
	if def.is_empty() or def.station != station:
		return false
	var skill: Array = def.skill
	return skill.is_empty() or progress.rank(skill[0]) >= int(skill[1])

func queue_craft(id: String, count: int, cell: Variant) -> void:
	var station := "hand"
	var queue := hand_queue
	var record:Dictionary={}
	if cell != null:
		var data: Dictionary = construction.blocks.get(cell, {})
		if data.is_empty() or player.global_position.distance_to(WastelandConstruction.position_of(cell)) > 5.7:
			return
		station = str(data.device)
		queue = data.queue
		record=data
	if not can_craft(id, station):
		notify("需要对应专长或工作台")
		return
	var recipe: Dictionary = catalog.recipes[id]
	var queued := 0
	for i in mini(count, 8):
		if queue.size() >= 8: break
		var payment:=Fire.reserve(bag,record,recipe.inputs)
		if payment.is_empty(): break
		var start := clock.elapsed if queue.is_empty() else maxf(clock.elapsed, float(queue.back().done))
		var duration := float(recipe.seconds) * (1.0 - progress.rank("craft") * 0.09)
		craft_serial+=1
		payment.merge({"id":recipe.id,"ticket":craft_serial,"amount":recipe.amount,"done":start+duration,"span":duration})
		if Fire.thermal(record): payment.left=duration
		queue.append(payment)
		queued += 1
	if cell == null and queued > 0:
		_schedule_world_save()
	notify("已加入队列 · %s ×%d" % [catalog.title(id), queued] if queued > 0 else "材料不足或队列已满")

func _label_jobs(queue:Array)->void:
	for job:Dictionary in queue:
		if not job.has("ticket"):
			craft_serial+=1
			job.ticket=craft_serial

func cancel_queue(cell: Variant,ticket:int=-1) -> void:
	var queue := hand_queue if cell == null else (construction.blocks.get(cell, {}).get("queue", []) as Array)
	if queue.is_empty():
		return
	var index:=queue.size()-1 if ticket==-1 else queue.find_custom(func(entry):return entry.get("ticket",-2)==ticket)
	if index<0: return
	var job:Dictionary=queue[index]
	var released:=minf(float(job.get("span",0.0)),maxf(0.0,float(job.done)-clock.elapsed))
	queue.remove_at(index)
	if cell == null:
		_schedule_world_save()
	for i in range(index,queue.size()): queue[i].done-=released
	if cell!=null and not job.get("molten",{}).is_empty():
		var stock:Dictionary=construction.blocks[cell].molten
		for id:String in job.molten: stock[id]=int(stock.get(id,0))+int(job.molten[id])
	award(job.get("inputs",{}), player.global_position)
	notify("已取消%s并返还材料"%catalog.title(job.id))

func collect_station(cell: Vector3i) -> void:
	if not construction.blocks.has(cell):
		return
	var output: Dictionary = construction.blocks[cell].out
	var before := output.duplicate()
	var moved := bag.transfer(output)
	if moved > 0:
		for id: String in before:
			var collected := int(before[id])-int(output.get(id,0))
			achievements.add("made_"+id,collected)
			if id=="clean_water" and construction.blocks[cell].device=="campfire":
				achievements.add("boiled_water",collected)
				achievements.add("got_safe_water",collected)
		if bag.current()=="potato" and construction.blocks[cell].device=="campfire": achievements.mark("potato_chef")
		gain(10 * mini(moved, 5), "craft")
		notify("已取出成品 ×%d" % moved)
	else:
		notify("还没有成品" if output.is_empty() else "背包已满")

func _finish_crafting() -> void:
	while not hand_queue.is_empty() and float(hand_queue[0].done) <= clock.elapsed:
		var job: Dictionary = hand_queue.pop_front()
		_schedule_world_save()
		award({job.id:int(job.amount)}, player.global_position)
		achievements.add("made_"+str(job.id),int(job.amount))
		gain(11, "craft")
		notify("制作完成 · %s ×%d" % [catalog.title(job.id), int(job.amount)])

func campfire_warmth(at: Vector3) -> float:
	var strongest := 0.0
	for cell in construction.station_index:
		if construction.station_index[cell] != "campfire":
			continue
		var row: Dictionary = construction.blocks[cell]
		if Fire.lit(row):
			var d := at.distance_to(WastelandConstruction.position_of(cell))
			strongest = maxf(strongest, maxf(0.0, 15.5 - 2.50 * d))
	return strongest

func refuel(cell: Vector3i) -> void:
	if not construction.blocks.has(cell):
		return
	var row: Dictionary = construction.blocks[cell]
	if row.device == "turret" and bag.spend({"heavy_round": 12}):
		row.ammo = int(row.ammo) + 12
	elif row.device == "generator" and bag.spend({"fuel": 1}):
		row.fuel = float(row.fuel) + 88.0
		row.enabled = true
	elif Fire.thermal(row) and Fire.charge(row,bag,"wood"):
		row.enabled = true
	else:
		notify("缺少物资")
		return
	notify("已补充 " + catalog.title(row.device))

func rest(cell: Vector3i) -> void:
	if not construction.blocks.has(cell) or construction.blocks[cell].device != "campfire":
		return
	if is_instance_valid(network) and network.server() and network.player_count()>1:
		notify("当前队伍在线，无法跳过夜晚")
		return
	if hordes.nearest_enemy(player.global_position, 16.0) != null or clock.horde_active() or campfire_warmth(player.global_position) <= 0.0:
		notify("休息需要点燃营火，且附近须安全")
		return
	if clock.hour() >= 7.0 and clock.hour() < 19.0:
		notify("天黑后才可在营火旁休息")
		return
	var duration := fposmod(6.5 - clock.hour(), 24.0)
	if clock.day() % clock.period == 0 and clock.hour() >= 19.0:
		duration = minf(duration, maxf(0.0, 21.75 - clock.hour()))
	if duration < 0.2:
		notify("血月即将到来")
		return
	clock.hours += duration
	player.hunger = maxf(0.0, player.hunger - duration * 2.1)
	player.hydration = maxf(0.0, player.hydration - duration * 2.7)
	player.health = minf(player.max_health(), player.health + duration * 1.22)
	player.stamina = player.max_stamina()
	notify("休息了 %.1f 小时" % duration)
	save_now(false)

func job_action() -> void:
	if replica or not _at_board(): return
	var def := progress.active_job(catalog.quests)
	if def.is_empty():
		return
	if not progress.accepted:
		progress.baseline = int(progress.records.get(def.record, 0))
		progress.accepted = true
		notify("已接下委托 · " + def.name)
		return
	var complete := bag.count("beacon_log") > 0 if def.record == "beacon" else progress.job_count(def) >= int(def.amount)
	if not complete:
		notify("委托尚未完成")
		return
	if def.has("inputs") and not bag.spend(def.inputs):
		notify("交付还需要 · "+catalog.requirements(def.inputs))
		return
	if def.record == "beacon":
		bag.spend({"beacon_log":1})
	award(def.reward, player.global_position)
	gain(int(def.xp), "quest")
	progress.job += 1
	progress.legacy_water=false
	progress.accepted = false
	if def.record=="beacon" and progress.job==catalog.quests.size() and progress.finish_day==0:
		progress.finish_day = clock.day()
		progress.finish_stats = {"jobs":progress.job,"nights":int(progress.records.get("horde",0)),
			"built":int(progress.records.get("build",0)),"searches":int(progress.records.get("loot",0)),
			"station":_station_name(WastelandTerrainGen.chunk_at(Vector2(player.position.x,player.position.z)))}
		if remote_actor:
			_finish_campaign.call_deferred() # Restore the host player before serializing the party.
		else:
			_finish_campaign()
		return
	notify("完成委托 · " + def.name)

func _fixture_gone(cell: Vector2i, local_id: String) -> bool:
	var key := WastelandTerrainGen.grid_key(cell)+":"+local_id
	return float(stream.chunk_diff(cell).get("fixture_health",{}).get(key,1.0))<=0

func near_board(ruined: bool) -> bool:
	var cell := WastelandTerrainGen.chunk_at(Vector2(player.position.x,player.position.z))
	if stream.generator.site_for(cell)!="lodge" or _fixture_gone(cell,"trader")!=ruined: return false
	var position_2d := WastelandSite.board_at(cell)
	var at := Vector3(position_2d.x,0,position_2d.y)
	at.y = stream.ground_at(at)
	if not ruined and stream.active.has(cell):
		var chunk: WastelandChunk = stream.active[cell]
		var board: StaticBody3D = chunk.fixtures.get(chunk.object_key("trader"))
		if is_instance_valid(board): at.y = board.global_position.y-1.05
	return player.global_position.distance_squared_to(at)<36.0

func _at_board() -> bool:
	return near_board(false)

func rebuild_board() -> void:
	if not near_board(true): return
	if not bag.spend({"wood":3,"fiber":2}):
		notify("重建公告板需要木料 ×3 和植物纤维 ×2")
		return
	var cell := WastelandTerrainGen.chunk_at(Vector2(player.position.x,player.position.z))
	var chunk: WastelandChunk = stream.active[cell]
	var diff := stream.edit_chunk(cell)
	diff.fixture_health.erase(chunk.object_key("trader"))
	var pos := WastelandSite.board_at(cell)
	diff.board_y = stream.ground_at(Vector3(pos.x,0,pos.y))+0.14
	chunk.sync_fixtures()
	notify("公告板已重建")
	_open_for_player("trade",null)

func _finish_campaign() -> void:
	var result := save_now(false)
	var receipt := progress.finish_stats.duplicate()
	receipt.day = progress.finish_day
	receipt.save_error = int(result)
	panel.emit("ending",receipt)
	if is_instance_valid(network) and network.server():
		network.panel_for_member("ending",receipt)

func beacon_destination() -> Dictionary:
	var closest := INF
	var best := {}
	var backup := {}
	var backup_dist := INF
	var ruins := {}
	var ruins_dist := INF
	var sites := _nearby_sites()
	for cell: Vector2i in sites:
		var site: String = sites[cell]
		if site not in ["police","hospital","tower"]: continue
		if site=="police" and stream.generator.revision<3 and cell!=Vector2i(3,-1): continue
		var at := Vector2(cell*WastelandTerrainGen.SIZE)+Vector2(16.4,12.2)
		var dist := Vector2(player.position.x,player.position.z).distance_squared_to(at)
		if _fixture_gone(cell,"container/99"):
			if dist<ruins_dist:
				ruins_dist=dist
				ruins={"at":at,"cell":cell,"name":"保险柜遗址 · 查找散页","ruins":true}
			continue
		if dist < backup_dist:
			backup_dist = dist
			backup = {"at":at,"cell":cell,"name":str(catalog.sites[site].name)+" · 信标备份","backup":true}
		var key := WastelandTerrainGen.grid_key(cell)+":container/99"
		var record: Dictionary = stream.chunk_diff(cell).get("containers",{}).get(key,{})
		var renewed := Chest.state(record,clock.day(),int(world_settings.loot_days),false)==0
		if not renewed and int(record.get("items",{}).get("beacon_log",0))==0: continue
		if dist < closest:
			closest = dist
			best = {"at":at,"name":str(catalog.sites[site].name)+" · 顶层保险柜"}
	for row: Dictionary in fx.drop_records.values():
		if not row.items.has("beacon_log"): continue
		var point: Vector3 = row.point
		var dist := player.global_position.distance_squared_to(point)
		if dist<closest and dist<backup_dist:
			closest=dist
			best={"at":Vector2(point.x,point.z),"name":"散落的信标记录"}
	if not ruins.is_empty() and (minf(closest,backup_dist)>256.0*256.0 and ruins_dist<minf(closest,backup_dist)*0.25):
		return ruins
	if best.is_empty() or (closest>256.0*256.0 and backup_dist<closest*0.25): return backup
	return best

func near_ruined_archive() -> bool:
	if bag.count("beacon_log")>0 or not progress.accepted or progress.active_job(catalog.quests).get("record")!="beacon": return false
	var cell := WastelandTerrainGen.chunk_at(Vector2(player.position.x,player.position.z))
	if not _fixture_gone(cell,"container/99"): return false
	for row: Dictionary in fx.drop_records.values():
		if row.items.has("beacon_log") and WastelandTerrainGen.chunk_at(Vector2(row.point.x,row.point.z))==cell: return false
	var at := Vector2(cell*WastelandTerrainGen.SIZE)+Vector2(16.4,12.2)
	return Vector2(player.position.x,player.position.z).distance_squared_to(at)<25.0

func _archive_copy(object: Object, record: Dictionary) -> bool:
	if not object.get_meta("quest",false): return false
	if not progress.accepted or progress.active_job(catalog.quests).get("record")!="beacon": return false
	if bag.count("beacon_log")>0 or record.is_empty() or record.get("items",{}).has("beacon_log"): return false
	var target := beacon_destination()
	return target.get("backup",false) and target.cell==object.get_meta("cell")

func daily_orders() -> Array[Dictionary]:
	var origin:=WastelandTerrainGen.chunk_at(board_destination().at)
	var key:=Vector3i(origin.x,clock.day(),origin.y)
	if not order_cache.has(key):
		if order_cache.size()>12: order_cache.clear()
		order_cache[key]=OutpostOrders.orders(self,origin)
	return order_cache[key]

func track_order(id:String) -> void:
	tracked_order=""
	tracked_row={}
	for row in daily_orders():
		if row.id==id:
			tracked_order=id
			tracked_row=row
			break

func order_destination() -> Dictionary:
	if tracked_row.is_empty() or progress.delivery_day==clock.day() or not tracked_order.ends_with("_"+str(clock.day())): return {}
	var returning:bool=bag.has_all(tracked_row.inputs)
	if tracked_row.tier=="expedition": returning=returning and bool(progress.dispatch.get("signed",false))
	return {"at":tracked_row.board if returning else tracked_row.at,"name":"交回 · "+str(tracked_row.name) if returning else tracked_row.source}

func _courier_id() -> String:
	return "guest-"+str(network.active_member.token).sha256_text() if remote_actor and is_instance_valid(network) and network.active_member!=null else "host"

func start_dispatch(id:String) -> void:
	if replica or not _at_board() or progress.delivery_day==clock.day(): return
	for row in daily_orders():
		if row.id!=id or row.tier!="expedition": continue
		if progress.dispatch.get("day",0)==clock.day():
			notify("远行运单已登记 · 请按原站线路取件")
			return
		if bag.count("dispatch_parcel")>0: bag.spend({"dispatch_parcel":bag.count("dispatch_parcel")})
		progress.dispatch={"id":id,"day":clock.day(),"origin":row.origin,"relay":row.relay,"signed":false,"courier":_courier_id()}
		if not remote_actor: track_order(id)
		notify("已登记 · 前往"+str(row.source))
		return

func collect_dispatch(cell:Vector2i) -> void:
	if replica or progress.delivery_day==clock.day(): return
	var record:=progress.dispatch
	if record.get("day",0)!=clock.day() or record.get("relay")!=cell:
		notify("这里没有你的货包 · 先到出发驻地登记远行运单")
		return
	var depot:=Vector2(cell*32)+OutpostOrders.DEPOT
	if Vector2(player.position.x,player.position.z).distance_to(depot)>5.5: return
	if record.signed:
		notify("货包已签收，请带回原驻地")
		return
	if bag.count("dispatch_parcel")==0 and bag.add("dispatch_parcel",1)==0:
		notify("背包已满")
		return
	record.signed=true
	record.same_courier=record.courier==_courier_id() and WastelandSite.board_at(record.origin).distance_to(depot)>=320.0
	notify("已签收货包 · 今日返回发单公告板交货")

func _dispatch_waiting(cell: Vector2i) -> bool:
	var order := progress.dispatch
	return order.get("day",0)==clock.day() and progress.delivery_day!=clock.day() and order.get("relay")==cell and not order.get("signed",false)

func deliver_order(id: String) -> void:
	if replica or not _at_board(): return
	if progress.delivery_day == clock.day():
		notify("今天的交付单已结清，明天再来")
		return
	for order in daily_orders():
		if order.id != id:
			continue
		if order.tier=="expedition" and (progress.dispatch.get("id","")!=id or not progress.dispatch.get("signed",false)):
			notify("请先登记并到中继寄存柜签收")
			return
		if not bag.spend(order.inputs):
			notify("交付需要 · " + catalog.requirements(order.inputs))
			return
		progress.delivery_day = clock.day()
		if order.tier=="expedition" and progress.dispatch.get("same_courier",false) and progress.dispatch.courier==_courier_id() and clock.hour()>=17.0 and clock.hour()<18.0:
			achievements.mark("clockout_dispatch")
		award(order.reward, player.global_position)
		gain(int(order.xp), "delivery")
		notify("交付完成 · %s  +%d 经验" % [order.name, order.xp])
		return
	notify("交付单已换新，请查看今天的需求")

func trader_exchange() -> void:
	if trade_day == clock.day():
		notify("今日储备已换完")
		return
	if not bag.spend(TRADE_COST):
		notify("交换需要" + catalog.requirements(TRADE_COST))
		return
	trade_day = clock.day()
	award(TRADE_REWARD, player.global_position)
	notify("已换取驻地储备")

func gain(amount: int, record: String = "", count: int = 1) -> void:
	if progress.gain(amount, record, count):
		notify("已升至 %d 级 · 获得专长点" % progress.level, 4.0)

func award(items: Dictionary, at: Vector3) -> void:
	var remainder := items.duplicate()
	bag.transfer(remainder)
	if not remainder.is_empty():
		spawn_drop(at, remainder)

func discard_protected(id:String)->bool:
	return bag.available_count(id)==1 and (bag.is_worn(id) or bag.current()==id or bag.offhand==id)

func discard(id: String, allow_confirmation := true) -> void:
	var item:Dictionary=catalog.items.get(id,{})
	if item.is_empty() or bag.count(id)<=0: return
	if item.get("kind","")=="quest":
		notify("任务物品已保护，不能丢弃")
		return
	if discard_protected(id):
		var now:=Time.get_ticks_msec()
		if not allow_confirmation or player.get_meta("discard_item","")!=id or now>int(player.get_meta("discard_until",0)):
			player.set_meta("discard_item",id)
			player.set_meta("discard_until",now+3200)
			notify("这是正在使用的最后一件%s。再次丢弃以确认。"%catalog.title(id),3.2)
			return
	player.set_meta("discard_item","")
	if not bag.spend({id:1}): return
	var ammo: int = int(bag.magazine.get(id, 0))
	var contents:Dictionary={id:1}
	if bag.count(id) == 0 and ammo > 0 and item.has("ammo"):
		bag.magazine.erase(id)
		contents[item.ammo]=ammo
	var direction:Vector3=-player.eyes.global_transform.basis.z.normalized()
	var hand:=player.eyes.global_position-Vector3.UP*0.22
	var obstruction:=PhysicsRayQueryParameters3D.create(hand,hand+direction*0.55,3,[player.get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(obstruction)
	var reach:=0.4 if hit.is_empty() else maxf(0.0,hand.distance_to(hit.position)-0.22)
	spawn_drop(hand+direction*reach,contents,direction*2.2+Vector3.UP*0.55,true)

func drop_materials(at:Vector3,items:Dictionary,normal:=Vector3.UP)->void:
	if replica or not at.is_finite(): return
	var outward:=normal.normalized()
	if outward.is_zero_approx(): outward=Vector3.UP
	var tangent:=outward.cross(Vector3.RIGHT if absf(outward.x)<0.8 else Vector3.FORWARD).normalized()
	var bitangent:=outward.cross(tangent)
	var index:=0
	for id:String in items:
		if int(items[id])>0:
			var angle:=TAU*index/items.size()
			var spread:=(cos(angle)*tangent+sin(angle)*bitangent) if items.size()>1 else Vector3.ZERO
			var loose: bool=catalog.items.get(id,{}).get("kind","")=="material" and id not in ["tree_leaf","stick"]
			spawn_drop(at+outward*0.16+spread*0.03,{id:int(items[id])},outward*0.45+Vector3.UP*0.24+spread*0.62,false,loose)
			index+=1

func spawn_drop(at: Vector3, items: Dictionary, impulse:=Vector3.INF, discarded:=false, loose_material:=false) -> void:
	var point := at
	point.y = maxf(point.y, stream.ground_at(at) + 0.19)
	fx.add_items(point,items,impulse,discarded,{},"",loose_material)

func _place_vehicle(type: String) -> void:
	var hit := _trace(5.5, 3, true)
	if hit.is_empty() or bag.count(type) <= 0:
		return
	var point: Vector3 = hit.position
	if type == "boat" and (not hit.has("water") or stream.ground_at(point) >= -0.14):
		notify("把摩托艇放在稍深的湖面")
		return
	if type != "boat" and hit.has("water"):
		notify("把陆地载具放在岸上")
		return
	if point.distance_to(player.global_position) < 2.0:
		notify("载具需要更宽的放置空间")
		return
	var box := BoxShape3D.new()
	box.size = Vector3(1.72, 0.78, 2.80) if type in ["boat", "pickup"] else Vector3(0.55, 0.78, 1.72)
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = box
	probe.transform = Transform3D(Basis(Vector3.UP, player.rotation.y), point + Vector3.UP * 0.52)
	probe.collision_mask = 2 | 4 | 8
	if not get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty():
		notify("载具位置被占用")
		return
	if not bag.spend({type:1}):
		return
	vehicle_serial += 1
	var id := str(vehicle_serial)
	vehicle_records[id] = {"type":type,"point":point+Vector3.UP*0.18,"yaw":player.rotation.y,"fuel":0.0 if type == "bicycle" else 23.0}
	_mount_vehicle(id)
	notify("已组装 " + catalog.title(type))
	gain(54,"vehicle")

func _damage_vehicle(vehicle: WastelandVehicle,amount: float,contact:=Vector3.INF,normal:=Vector3.UP) -> void:
	if replica or not vehicle_records.has(vehicle.id) or amount<=0: return
	var row: Dictionary = vehicle_records[vehicle.id]
	row.hp = maxf(0.0,float(row.get("hp",vehicle.max_hp()))-amount)
	fx.burst(vehicle.global_position+Vector3.UP*0.4,Color("#9b9a8f"),0.45)
	if row.hp>0: return
	for rider in get_children():
		if rider is WastelandSurvivor and rider.mount_vehicle==vehicle: rider.dismount()
	vehicle_records.erase(vehicle.id)
	vehicles.erase(vehicle.id)
	vehicle.collision_layer=0
	vehicle.hide()
	drop_materials(contact if contact.is_finite() else vehicle.global_position,VEHICLE_SALVAGE,normal)
	vehicle.queue_free()

func _sync_vehicles() -> void:
	if not is_instance_valid(player):
		return
	for id in vehicles.keys():
		var vehicle: WastelandVehicle = vehicles[id]
		if not vehicle.occupied and team_distance_squared(vehicle.global_position)>115.0*115.0:
			vehicle.queue_free()
			vehicles.erase(id)
	for id in vehicle_records:
		var point: Vector3 = vehicle_records[id].point
		if not vehicles.has(id) and team_distance_squared(point)<105.0*105.0:
			_mount_vehicle(id)

func _mount_vehicle(id: String) -> void:
	var node := WastelandVehicle.new()
	add_child(node)
	node.configure(self, id, vehicle_records[id])
	vehicles[id] = node

func vehicle_service(id: String, pack: bool, repair: bool = false) -> void:
	if not vehicle_records.has(id) or not vehicles.has(id):
		return
	var row: Dictionary = vehicle_records[id]
	var vehicle: WastelandVehicle = vehicles[id]
	if vehicle.occupied or vehicle.global_position.distance_to(player.global_position) >= 6.1:
		return
	if repair:
		if not row.get("needs_repair", false):
			var maximum:=vehicle.max_hp()
			var hp:=float(row.get("hp",maximum))
			if hp>=maximum: return
			if not bag.spend({"field_service_kit":1}):
				notify("需要行车维修包")
				return
			row.hp=minf(maximum,hp+120.0)
			notify("已维修 · 耐久 %d / %d"%[ceili(row.hp),ceili(maximum)])
			return
		if not bag.spend(BOAT_REPAIR):
			notify("维修需要 · " + catalog.requirements(BOAT_REPAIR))
			return
		row.needs_repair = false
		vehicle.update_repair_marker()
		gain(35, "repair_boat")
		notify("船体修复 · 可以出航  +35 经验", 4.0)
		return
	if row.get("needs_repair", false):
		notify("先修复船体")
		return
	if pack:
		if bag.add(row.type,1) == 0:
			notify("背包已满")
			return
		vehicle.queue_free()
		vehicles.erase(id)
		vehicle_records.erase(id)
		_open_for_player("",null)
	elif row.type != "bicycle" and bag.spend({"fuel":1}):
		row.fuel = float(row.fuel) + 45.0
		notify("已补充燃料")
	else:
		notify("缺少燃料或载具无需燃料")

func add_marker(at: Vector2, title: String = "") -> void:
	if marker_records.size() >= 30:
		notify("最多保存 30 个标记")
		return
	map_serial += 1
	marker_records.append({"at":at, "name":title.strip_edges() if not title.strip_edges().is_empty() else "标记 %d" % map_serial, "id":map_serial})

func remove_marker(id: int) -> void:
	marker_records = marker_records.filter(func(entry): return int(entry.id) != id)

func player_died(victim: WastelandSurvivor = null) -> void:
	if is_instance_valid(network) and network.server():
		var state:WastelandLan.MemberState=network.member_for(victim)
		if state!=null:
			if not state.downed and clock.horde_active(): hordes.event_deaths+=1
			network.member_failed(state)
			return
	if death_screen:
		return
	player.begin_death_ragdoll()
	deaths += 1
	if clock.horde_active():
		hordes.event_deaths += 1
	if is_instance_valid(player.mount_vehicle):
		player.dismount(true)
	death_screen = true
	controls_enabled = false
	var carried := bag.counts.duplicate()
	var grave: Dictionary = {}
	for id in carried:
		if catalog.items.get(id, {}).get("kind") != "quest":
			var amount := ceili(float(carried[id]) * 0.55)
			if bag.spend({id:amount}):
				grave[id] = amount
				if bag.count(id) == 0 and int(bag.magazine.get(id,0)) > 0:
					var ammo: String = catalog.items[id].ammo
					grave[ammo] = int(grave.get(ammo,0)) + int(bag.magazine[id])
					bag.magazine.erase(id)
	var place := player.global_position
	spawn_drop(place, grave)
	add_marker(Vector2(place.x,place.z), "遗落物资")
	failed.emit()
	save_now(false)

func respawn() -> void:
	player.reset_ragdoll()
	death_screen = false
	player.position = start_position()
	stream.ensure_landing(player.position)
	stream.refresh(player.position,int(options.display.radius),guest_positions())
	player.position.y=stream.ground_at(player.position)+0.14
	player.velocity = Vector3.ZERO
	player.health = player.max_health()
	player.reset_water_state()
	player.clear_damage_feedback()
	player.hunger = 75.0
	player.hydration = 75.0
	player.stamina = player.max_stamina()
	player.sprain = 0.0
	player.wet = 0.0
	player.bleed = 0.0
	player.infection = 0.0
	player.warm_drink_left = 0.0
	player.ration_left = 0.0
	player.fracture = 0.0
	player.invulnerable = 2.5
	player.body_temp = 36.7
	notify("已返回"+start_name()+" · 地图标记了遗落物资")

func _player_fell(mode: int, impact: Vector3, person: WastelandSurvivor) -> void:
	# Damage callbacks select the victim's inventory and input context before firing.
	if mode != 0 and player == person:
		heavy_charge = 0.0
		heavy_pending = false
		loot_target = null
		loot_ratio = 0.0
		focus_damage = -1.0
		hint = ""
		reload_id = ""
		reload_left = 0.0
		construction.tool_jobs.erase(person.get_instance_id())
	if is_instance_valid(network) and not replica:
		network.survivor_fell(self, person, mode, impact)
	elif not replica:
		PartyFalls.capture(person, WastelandLan.HOST_ID, mode, impact)

func _player_part_hit(impact: Vector3, at: Vector3, bone: StringName, person: WastelandSurvivor) -> void:
	if is_instance_valid(network) and network.server():
		network.mirror_player_hit(person,impact,at,bone)

func save_now(report: bool) -> Error:
	if slot <= 0 or preview_only or replica or remote_actor or not is_instance_valid(player):
		return ERR_UNCONFIGURED
	achievements.refresh()
	if is_instance_valid(network):
		network.store_guests(self)
	var snapshot := {
		"guests":guest_states,
		"survivor_corpses":PartyFalls.save_corpses(self),
		"lake_combat":stream.lake_wildlife.combat_snapshot(),
		"falling_trees":timber.snapshot(),
		"settings":world_settings, "time":clock.hours,"elapsed":clock.elapsed,
		"bag":bag.snapshot(),"player":player.snapshot(),"progress":progress.snapshot(),
		"diffs":stream.diffs,"digs":stream.digs,"discovered":stream.discovered,
		"construction":construction.state(),"threat":hordes.snapshot(),
		"markers":marker_records,"map_serial":map_serial,"vehicles":vehicle_records,"vehicle_serial":vehicle_serial,
		"drops":fx.drop_records,"drop_serial":fx.serial,"acid_pools":fx.acid_snapshot(),"hand_queue":hand_queue,
		"acid_shots":fx.acid_flights(),"acid_serial":fx.acid_serial,
		"trade_day":trade_day,"tracked_order":tracked_row,"deaths":deaths,"shape":shape,"turn":turn,"craft_serial":craft_serial,
		"mounted":player.mount_vehicle.id if is_instance_valid(player.mount_vehicle) else "",
	}
	var error := WastelandSave.write(slot, snapshot)
	if error == OK:
		world_save_at_ms = 0
		last_autosave_error = OK
		stored.emit(slot)
		if report: notify("世界已保存")
	else:
		world_save_at_ms = Time.get_ticks_msec() + QUICK_SAVE_DELAY_MS
		if report: notify("保存失败 · 错误 %d" % error)
	return error

func notify(text: String, duration: float = 2.5) -> void:
	if remote_actor:
		network.tell(text,duration)
	else:
		message.emit(text, duration)

func ui_command(id: String, args: Array = []) -> void:
	if replica:
		network.send_request(id,args)
	else:
		apply_ui_command(id,args)

func _near_station(cell: Vector3i) -> bool:
	return construction.blocks.has(cell) and construction.blocks[cell].device!="" and player.global_position.distance_to(WastelandConstruction.position_of(cell))<5.8

func apply_ui_command(id: String, args: Array) -> void:
	if player.is_knocked_down() and id not in ["save","chest_close","marker","unmark"]:
		return
	match id:
		"offhand":
			if args.size()==1 and args[0] is String: bag.set_offhand(args[0])
		"swap_hands":
			if args.is_empty(): bag.swap_hands()
		"chest_take","chest_put":
			if args.size()==3 and args[0] is String and args[1] is String and args[2] is int and args[2]>0:
				chest_move(args[0],"take" if id=="chest_take" else "put",args[1],args[2])
		"chest_all","chest_close":
			if args.size()==1 and args[0] is String:
				if id=="chest_close": chest_close(args[0])
				else: chest_move(args[0],"all")
		"slot":
			if args.size()==1 and args[0] is int: bag.active=clampi(args[0],0,7)
		"assign":
			if args.size()==1 and args[0] is String: bag.assign(args[0],bag.active)
		"quick_equip":
			if args.size()!=1 or not args[0] is String or bag.available_count(args[0])<=0: return
			var item_id:String=args[0]
			match catalog.items.get(item_id,{}).get("kind",""):
				"armor":
					if not bag.is_worn(item_id): bag.toggle_gear(item_id)
				"weapon","ranged","tool","field_gear","light","sapling":
					if bag.offhand==item_id and bag.available_count(item_id)==1: bag.swap_hands()
					else: bag.assign(item_id,bag.active)
		"assign_slot":
			if args.size()==2 and args[0] is String and args[1] is int and args[1]>=0 and args[1]<WastelandBag.HOTBAR_SIZE and bag.count(args[0])>0:
				bag.assign(args[0],args[1])
		"consume":
			if args.size()!=1 or not args[0] is String or bag.count(args[0])<=0:
				return
			if catalog.items.get(args[0],{}).get("kind","")=="armor":
				bag.toggle_gear(args[0])
				notify(("已穿戴 " if args[0] in bag.gear.values() else "已脱下 ") + catalog.title(args[0]))
			else:
				player.consume(args[0])
		"discard":
			if args.size()==1 and args[0] is String: discard(args[0])
			elif args.size()==2 and args[0] is String and args[1] is bool: discard(args[0],args[1])
		"learn":
			if args.size()==1 and args[0] is String and catalog.skills.has(args[0]) and progress.learn(args[0],catalog.skills[args[0]]):
				notify("已学习 "+str(catalog.skills[args[0]].name))
		"craft":
			if args.size()==3 and args[0] is String and args[1] is int and (args[2]==null or (args[2] is Vector3i and _near_station(args[2]))):
				queue_craft(args[0],maxi(args[1],1),args[2])
		"cancel":
			if args.size() in [1,2] and (args[0]==null or (args[0] is Vector3i and _near_station(args[0]))) and (args.size()==1 or args[1] is int):
				cancel_queue(args[0],args[1] if args.size()==2 else -1)
		"feed_fire","smelt_input":
			if args.size()!=2 or not args[0] is Vector3i or not args[1] is String or not _near_station(args[0]): return
			var furnace:Dictionary=construction.blocks[args[0]]
			if id=="feed_fire":
				notify("已添加燃料" if Fire.charge(furnace,bag,args[1]) else "燃料不足或燃料槽已满")
			else:
				var moved:=Fire.load_ore(furnace,bag,args[1])
				notify("装入%s ×%d"%[catalog.title(args[1]),moved] if moved>0 else "请先备料或等待当前原料熔完")
		"collect", "fuel", "rest", "enable":
			if args.size()!=1 or not args[0] is Vector3i or not _near_station(args[0]):
				return
			match id:
				"collect": collect_station(args[0])
				"fuel": refuel(args[0])
				"rest": rest(args[0])
				"enable":
					var record: Dictionary = construction.blocks[args[0]]
					if Fire.thermal(record) and not record.enabled and float(record.fuel)<=0:
						notify("请先添加燃料")
						return
					record.enabled=not record.enabled
		"patrol_start":
			if args.size()==1 and args[0] is int: Patrol.start(self,args[0])
		"patrol_claim":
			if args.size()==2 and args[0] is int and args[1] is String: Patrol.claim(self,args[0],args[1])
		"job", "barter", "deliver", "dispatch":
			if _at_board():
				match id:
					"job": job_action()
					"barter": trader_exchange()
					"dispatch":
						if args.size()==1 and args[0] is String: start_dispatch(args[0])
					"deliver":
						if args.size() == 1 and args[0] is String:
							deliver_order(args[0])
		"rebuild_board":
			rebuild_board()
		"recover_archive":
			if near_ruined_archive():
				notify("找回信标记录" if bag.add("beacon_log",1)>0 else "背包已满")
		"marker":
			if args.size()==2 and args[0] is Vector2 and args[1] is String and args[0].is_finite():
				add_marker(args[0].limit_length(100000.0),args[1].left(20))
		"unmark":
			if args.size()==1 and args[0] is int: remove_marker(args[0])
		"vehicle":
			if args.size()==2 and args[0] is String and args[1] is bool: vehicle_service(args[0],args[1])
		"repair_vehicle":
			if args.size() == 1 and args[0] is String: vehicle_service(args[0], false, true)
