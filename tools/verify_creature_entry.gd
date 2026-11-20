extends "res://tools/verify_harvest.gd"

const DT := 1.0 / 60.0

func run() -> void:
	WastelandSave.root_override = "user://verification/creature-entry-%d" % OS.get_process_id()
	config = WastelandSave.default_world()
	config.seed = 27491
	config.terrain_revision = 5
	config.start_id = "grassland"
	open_world({})
	var outpost := session.stream.generator.starting_outpost("grassland")
	var buildings := {outpost:"lodge", Vector2i(3,-4):"hospital", Vector2i(-3,-2):"bunker",
		Vector2i(-7,-9):"granary", Vector2i(-10,-17):"garage", Vector2i(-13,-18):"post"}
	for cell: Vector2i in buildings:
		var center := Vector2(cell * WastelandTerrainGen.SIZE) + Vector2(16, 16)
		session.stream.ensure_landing(Vector3(center.x, 0, center.y))
		var building: WastelandChunk = session.stream.active[cell]
		check(building.site == buildings[cell], "generated %s at %s" % [buildings[cell], cell])
		await session.stream.quiesce()
		for frame in 3: await physics_frame
		var boards := "door/bunker" if building.site=="bunker" else "door/entrance"
		if building.site!="lodge":
			check(building.structures.has(boards),building.site+" starts boarded")
			session.hit_wall(building.structures[boards][0],999)
			# quiesce pauses the normal stream tick. Consume this breach's queued local bake.
			session.stream.ready_for_streaming=true
			session.stream._process(0)
			await session.stream.quiesce()
			await physics_frame
			await physics_frame
		for kind: String in ["walker", "brute", "hare", "stag"]:
			await enter(kind, building)
		if building.site == "hospital":
			await enter("walker", building, 3.7)
			await enter("stag", building, 3.7)
		var damage: Dictionary = session.stream.chunk_diff(cell).get("site_damage", {})
		check(damage.is_empty() if building.site=="lodge" else damage.size()==1 and float(damage[boards])<=0.0,building.site+" entry causes no additional structural damage")
		if cell == outpost: await solid_wall(building)
	await close_world()
	print("CREATURE ENTRY QA passed=%d failed=%d" % [passed, failures])
	quit(1 if failures else 0)

func enter(kind: String, building: WastelandChunk, approach_x := 0.0) -> void:
	var door := building.to_global(Vector3(16, building.ruin.base_y, 16 + building.ruin.span * 0.5))
	var outside := door + Vector3(approach_x, 0, 3.3)
	outside.y = session.stream.ground_at(outside) + 0.08
	var goal := door + Vector3.FORWARD * 3.2 + Vector3.UP * 0.15
	var animal := bool(session.catalog.enemies[kind].get("animal", false))
	session.player.global_position = goal + Vector3.RIGHT * (42.0 if animal else 0.0)
	var state := {"limb_index": 0, "morph": "swift" if kind == "brute" else ""}
	if not animal:
		state.interest = goal
		state.memory = 10.0
	for candidate: WastelandCreature in session.hordes.pool:
		if not candidate.active: candidate.actor_rng.seed = 123
	if not session.hordes._spawn(kind, outside, false, state):
		check(false, kind + " spawns outside " + building.site)
		return
	var actor: WastelandCreature = session.hordes.alive.back()
	actor.rotation.y = 0
	actor.actor_rng.seed = 123
	if animal:
		# Preserve one ordinary foraging destination long enough to observe the entrance.
		actor.brain.goal = goal
		actor.brain.patrol_left = 20
	var crossed := false
	var used_door := false
	for frame in 600:
		await physics_frame
		session.hordes.path_budget = WastelandHordes.PATHS_PER_TICK
		var before := actor.global_position
		actor.think(DT, session.player)
		if before.z >= door.z and actor.global_position.z < door.z:
			used_door = absf(actor.global_position.x - door.x) < 0.8
		if actor.global_position.z < door.z - 1.3 and used_door and actor.is_on_floor():
			crossed = true
			break
	check(crossed, "%s enters %s from %.1f m off centre, end offset %s" % [kind, building.site, approach_x, actor.global_position - door])
	session.hordes.release(actor)

func solid_wall(lodge: WastelandChunk) -> void:
	var wall: StaticBody3D = lodge.structures["wall/0/2/2"][0]
	var start := wall.global_position + Vector3.FORWARD * 1.1
	start.y = session.stream.ground_at(start) + 0.08
	session.hordes._spawn("walker", start, false, {"limb_index": 0})
	var actor: WastelandCreature = session.hordes.alive.back()
	for frame in 90:
		await physics_frame
		actor.velocity = Vector3(0, -2, 2.4)
		actor.move_and_slide()
	check(actor.is_on_wall() and actor.global_position.z < wall.global_position.z - actor.capsule.radius,
		"an intact rear wall holds the creature capsule outside")
	session.hordes.release(actor)
