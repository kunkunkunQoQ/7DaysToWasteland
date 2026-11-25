extends Node3D

const Heron := preload("res://game/art/heron_rig.gd")
const ActiveMotion := preload("res://game/actors/active_ragdoll.gd")

class AnimalTrack extends Node3D:
	var route: Dictionary
	var bird: Heron
	var animal: WastelandCreature
	var motion: ActiveMotion

	func suspend() -> void:
		hide()
		if motion != null:
			motion.stop_driving()
			motion = null

	func build_model(catalog: WastelandCatalog) -> void:
		var species: String = route.species
		if species == "heron":
			bird = Heron.new()
			add_child(bird)
			bird.build(false, 0)
			return
		# Use the game's skeleton and gait without configuring a gameplay actor.
		animal = WastelandCreature.new()
		animal.type = species
		animal.spec = catalog.enemies[species]
		animal.collision_layer = 0
		animal.collision_mask = 0
		animal.motion_preview = true
		animal.spawn_serial = get_index()
		animal.wildlife_cycle = route.phase
		animal.add_child(animal.rig)
		animal.rig.add_child(animal.skeleton)
		add_child(animal)
		WastelandBestiary.wildlife(animal, species, Color.html(animal.spec.cloth), Color.html(animal.spec.skin))
		WastelandBestiary.attach_april_face(animal)

var stream: WastelandStream
var catalog: WastelandCatalog

func configure(terrain: WastelandStream, data: WastelandCatalog, routes: Array) -> void:
	stream = terrain
	catalog = data
	for previous in get_children():
		remove_child(previous)
		previous.queue_free()
	for route: Dictionary in routes:
		var track := AnimalTrack.new()
		track.name = "%s%d" % [route.species, get_child_count()+1]
		track.route = route
		track.hide()
		add_child(track)

func advance(camera: Camera3D, elapsed: float, delta: float) -> void:
	var planes := camera.get_frustum()
	for track: AnimalTrack in get_children():
		var route := track.route
		var angular_speed := TAU / float(route.period)
		var angle := elapsed * angular_speed + float(route.phase) * TAU
		var along: Vector2 = route.along
		var across: Vector2 = route.across
		var path: Vector2 = route.center + along * cos(angle) + across * sin(angle)
		var at := Vector3(path.x, 0.0, path.y)
		if not stream.at_surface(at):
			track.suspend()
			continue
		at.y = stream.ground_at(at)
		var flying: bool = route.species == "heron"
		if flying:
			at.y = maxf(at.y, WastelandTerrainGen.WATER_LEVEL) + float(route.height)
		var radius := 1.6 if flying else float(catalog.enemies[route.species].height)
		var center := at + Vector3.UP * radius * 0.5
		if not _in_view(center, radius, planes):
			track.suspend()
			continue
		track.position = at
		var velocity := (-along * sin(angle) + across * cos(angle)) * angular_speed
		var yaw := atan2(-velocity.x, -velocity.y)
		if track.bird == null and track.animal == null:
			track.build_model(catalog)
		if track.motion != null: track.motion.restore_targets()
		if flying:
			track.bird.rotation.y = yaw
			track.bird.pose(elapsed, route.phase * TAU, 1.0, elapsed * 6.8 + route.phase * TAU)
		else:
			var animal := track.animal
			var speed := velocity.length()
			animal.rotation.y = yaw
			animal.motion_floor_normal = (animal.global_basis.inverse() * stream.ground_normal_at(at)).normalized()
			animal.brain.forage_left = 1.0 if speed < 0.45 else 0.0
			if not track.visible:
				animal.motion_yaw = yaw
			animal._pose(delta, at.distance_to(camera.global_position), speed * delta)
		track.show()
		if track.motion == null:
			var skeleton := track.bird.bones if flying else track.animal.skeleton
			track.motion = ActiveMotion.start(track,skeleton,stream)
		else:
			track.motion.capture_targets()

func _in_view(center: Vector3, radius: float, planes: Array[Plane]) -> bool:
	for plane in planes:
		if plane.distance_to(center) > radius:
			return false
	return true
