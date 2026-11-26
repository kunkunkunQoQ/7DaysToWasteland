class_name WastelandLakeWildlife
extends Node3D

signal impact_changed
const LakeCombat := preload("res://game/world/lake_combat.gd")
const ActiveMotion := preload("res://game/actors/active_ragdoll.gd")
var combat := LakeCombat.new()
var drivers := {}
var individual_fish := {}

func weapon_hit(from: Vector3, to: Vector3) -> Dictionary:
	return combat.weapon_hit(self, from, to)

func strike(hit: Dictionary, damage: float, origin: Vector3, heavy := false) -> bool:
	return combat.strike(self, hit, damage, origin, heavy)

func combat_snapshot() -> Dictionary:
	return combat.snapshot()

func restore_combat(rows: Dictionary) -> void:
	combat.restore(self, rows)

const SCHOOL_SIZE := 6
const FLIGHT_TIME := 3.6
const WATCH_RANGE := 78.0
const APRIL_FACE := preload("res://game/art/april_face.gd")
const SpeciesFaces := preload("res://game/art/species_faces.gd")
const HeronRig := preload("res://game/art/heron_rig.gd")
const FishRig := preload("res://game/art/lake_fish_rig.gd")
const FISH_SKULL := FishRig.SKULL
const FISH_RADII := FishRig.RADII
const FISH_FACE_CENTER := FishRig.MASK_AT
const FISH_FACE_SIZE := FishRig.MASK_SIZE

class Habitat:
	var perches: Array[Vector3] = []
	var perch := 0
	var next_perch := 1
	var took_off := -100.0
	var flight_start := Vector3.ZERO
	var takeoff_yaw := 0.0
	var flight_yaw := 0.0
	var wading := true
	var perched_since := 0.0
	var fishes := Vector3.ZERO
	var phase := 0.0
	var juvenile := false
	var mottled := false
	var fish_center := Vector3.INF
	var bird := Node3D.new()
	var upper := HeronRig.new()
	var school: MultiMeshInstance3D
	var segments: Array[MultiMeshInstance3D] = []
	var beats := PackedFloat32Array()
	var last_swim_time := -INF
	var escape_offset := Vector2.ZERO
	var faces: MultiMeshInstance3D
	var natural_faces: Array[MultiMeshInstance3D]=[]
	var face_slots: Array[Vector2i]=[]
	var rings: MultiMeshInstance3D
	var dart := 0.0
	var swim_angle := 0.0
	var heron_id := ""
	var fish_ids: Array[String] = []
	var fish_poses: Array[Transform3D] = []

var habitats: Array[Habitat] = []
var inland:Dictionary={}
var models:Dictionary={}
var bottom_life: Array[WastelandBenthicAnimal] = []
var stream: WastelandStream
var session: Node
var countdown := 0.0
var last_time := -1.0

func configure(owner_stream: WastelandStream) -> void:
	stream = owner_stream
	session = stream.get_parent()
	var ripple := TorusMesh.new()
	ripple.inner_radius = 0.46
	ripple.outer_radius = 0.50
	ripple.rings = 18
	ripple.ring_segments = 4
	var water_sheen := StandardMaterial3D.new()
	water_sheen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_sheen.albedo_color = Color(0.71, 0.88, 0.79, 0.59)
	water_sheen.render_priority = 2
	models={"ripple":ripple,"water_sheen":water_sheen}
	for x in [-2.0, 28.0, -39.0]:
		var patch := Habitat.new()
		var at := _shore_point(x, -0.20)
		var other := _shore_point(x + 12.0, -0.20)
		var shoal := _shore_point(x + 2.0, -1.05)
		if not at.is_finite() or not other.is_finite() or not shoal.is_finite():
			patch.bird.free()
			patch.upper.free()
			continue
		patch.perches = [at, other]
		patch.fishes = shoal
		patch.juvenile = habitats.size() == 1
		patch.mottled = habitats.size() % 2 == 0
		patch.phase = fposmod(x * 3.1 + stream.generator.seed_value * 0.003, TAU)
		_mount_habitat(patch)
	var wrecks := WastelandSunkenSites.landmarks(stream.generator)
	# Older shorelines have the same species without introducing wrecks into their saves.
	var routes := [wrecks.get("ferry",Vector3(-8,0,7)),wrecks.get("pump",Vector3(24,0,4)),wrecks.get("bridge",Vector3(-20,0,-44))]
	for i in routes.size():
		for species: String in ["pond_turtle","crayfish"]:
			var turtle := species=="pond_turtle"
			var home: Vector3 = routes[i] + Vector3(4.5 if turtle else 5.6,0,-3.6 if i==0 else 3.7)
			home.y = stream.generator.ground(home.x,home.z)
			if home.y > -1.8 or not stream.generator.water_basin(home.x,home.z):
				continue
			var animal := WastelandBenthicAnimal.new()
			add_child(animal)
			animal.build(species,"local" if (i==1 and turtle) or (i==2 and not turtle) else "",_face_at(home,species,0))
			animal.anchor = home
			animal.set_meta("lake_id", combat.identity(species, home))
			animal.position = home
			animal.phase = i*1.93 + (0.45 if turtle else 1.18)
			animal.hide()
			bottom_life.append(animal)

	if stream.generator.revision>=3:
		stream.chunk_loaded.connect(_load_inland)
		stream.chunk_unloaded.connect(_unload_inland)
		for cell:Vector2i in stream.active: _load_inland(cell)

func _load_inland(cell:Vector2i)->void:
	if inland.has(cell): return
	var base:=Vector2(cell*WastelandTerrainGen.SIZE)
	var mid:=base+Vector2(16,16)
	var kind:=stream.generator.region_kind(mid.x,mid.y)
	if kind not in ["desert","marsh"]: return
	var salt:=absi(stream.generator.seed_at(cell,711))
	if kind=="marsh" and salt%4!=0: return
	var chunk:WastelandChunk=stream.active[cell]
	if not chunk.water or not chunk.water.visible: return
	var shallows:Array[Vector3]=[]
	var bed:=Vector3.INF
	for z in range(2,32,4):
		for x in range(2,32,4):
			var p:=Vector3(base.x+x,0,base.y+z)
			p.y=stream.ground_at(p)
			if p.y>0.05 or not stream.generator.water_basin(p.x,p.z): continue
			if p.y> -0.70: shallows.append(p)
			elif not bed.is_finite() or p.y<bed.y: bed=p
	if not bed.is_finite(): return
	var animals:Array[WastelandBenthicAnimal]=[]
	var season:=floori((session.clock.day()-1)/7.0)
	var roll:=salt+season
	for i in (2 if bed.y< -1.5 else 1):
		var at:=bed+Vector3(i*1.1,0,i*0.7)
		at.y=stream.ground_at(at)
		if at.y> -0.55 or not stream.water_at(at): continue
		var specimen:=WastelandBenthicAnimal.new()
		add_child(specimen)
		var species:="pond_turtle" if (roll+i)%2==0 else "crayfish"
		specimen.build(species,"local" if (roll+i)%5==0 else "",_face_at(at,species,i))
		specimen.anchor=at
		specimen.set_meta("lake_id", combat.identity(species, at))
		specimen.position=at
		specimen.phase=fposmod(roll*0.13+i*1.37,TAU)
		specimen.hide()
		bottom_life.append(specimen)
		animals.append(specimen)
	var patch:Habitat
	if shallows.size()>=2:
		var perch:=shallows[roll%shallows.size()]
		var other:=perch
		for at in shallows:
			if at.distance_squared_to(perch)>other.distance_squared_to(perch): other=at
		if other.distance_squared_to(perch)>12:
			patch=Habitat.new()
			patch.perches=[perch,other]
			patch.fishes=bed
			patch.mottled=roll%3==0
			patch.juvenile=roll%4==0
			patch.phase=fposmod(salt*0.17,TAU)
			_mount_habitat(patch)
			patch.bird.hide()
	inland[cell]={"patch":patch,"animals":animals}
	countdown=0.0

func _unload_inland(cell:Vector2i)->void:
	if not inland.has(cell): return
	var row:Dictionary=inland[cell]
	var patch:Habitat=row.patch
	if patch:
		_drop_driver(patch.heron_id)
		for id in patch.fish_ids: _drop_driver(id)
		habitats.erase(patch)
		for instance:Node3D in [patch.bird,patch.school,patch.rings]: instance.queue_free()
	for animal:WastelandBenthicAnimal in row.animals:
		_drop_driver(animal.get_meta("lake_id"))
		bottom_life.erase(animal)
		animal.queue_free()
	inland.erase(cell)

func _mount_habitat(patch:Habitat)->void:
	patch.heron_id = combat.identity("heron", patch.perches[0])
	add_child(patch.bird)
	patch.bird.position = patch.perches[0]
	patch.bird.rotation.y = patch.phase
	patch.bird.scale = Vector3.ONE * (0.78 if patch.juvenile else 1.0)
	patch.bird.add_child(patch.upper)
	patch.upper.build(patch.juvenile,_face_at(patch.perches[0],"heron",0))
	FishRig.geometry(patch.mottled)
	var fish: Array = FishRig.physical_forms[patch.mottled]
	var formation: Array[Transform3D] = []
	formation.resize(SCHOOL_SIZE)
	formation.fill(Transform3D(Basis.from_scale(Vector3.ONE*0.00001),patch.fishes))
	patch.school = WastelandLook.instanced(self, fish[0], formation)
	patch.school.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.segments.append(patch.school)
	for part in range(1,fish.size()):
		var segment := WastelandLook.instanced(patch.school,fish[part],formation)
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.segments.append(segment)
	# Stable school-member IDs allow one instanced draw per face, even after chunk reload.
	var counts:=[0,0]
	for i in SCHOOL_SIZE:
		patch.fish_ids.append(combat.identity("lake_fish", patch.fishes, i))
		patch.beats.append(patch.phase + i * 1.7)
		patch.fish_poses.append(Transform3D(Basis.IDENTITY, Vector3.INF))
		var face_index:=_face_at(patch.fishes,"lake_fish",i)
		patch.face_slots.append(Vector2i(face_index,counts[face_index]))
		counts[face_index]+=1
	for face_index in 2:
		if counts[face_index]==0:
			patch.natural_faces.append(null)
			continue
		var batch:=WastelandLook.instanced(patch.school,SpeciesFaces.aquatic_mesh(),formation.slice(0,counts[face_index]))
		batch.material_override=SpeciesFaces.material("lake_fish","local" if patch.mottled else "",0,face_index)
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.natural_faces.append(batch)
	patch.faces = WastelandLook.instanced(patch.school, APRIL_FACE.make_mesh(), formation)
	patch.faces.material_override = null
	patch.faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	APRIL_FACE.register(patch.faces)
	patch.rings = WastelandLook.instanced(self, models.ripple, [Transform3D.IDENTITY, Transform3D.IDENTITY])
	patch.rings.material_override = models.water_sheen
	patch.rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.rings.hide()
	patch.school.hide()
	habitats.append(patch)

func _face_at(home:Vector3,kind:String,member:int)->int:
	return posmod(hash([stream.generator.seed_value,roundi(home.x*10),roundi(home.z*10),kind,member]),2)

func _shore_point(x: float, depth: float) -> Vector3:
	for i in range(180):
		var z := 43.0 - i * 0.35
		if stream.generator.water_basin(x, z):
			var y := stream.generator.ground(x, z)
			if y <= depth:
				return Vector3(x, y, z)
	return Vector3.INF

func _process(delta: float) -> void:
	countdown -= delta
	if countdown > 0.0 or not is_instance_valid(session) or session.player == null:
		return
	var now := float(session.clock.elapsed)
	countdown = 0.048
	if now == last_time:
		return
	var step := clampf(now - last_time, 0.0, 0.3)
	last_time = now
	var eyes: Array[Vector3] = [session.player.global_position]
	var network: Node = session.network
	if is_instance_valid(network):
		if network.server():
			eyes.append_array(session.guest_positions())
		elif session.replica:
			eyes.append_array(network.replica_positions())
	combat.advance(self, now, eyes)
	var nearby := false
	for patch in habitats:
		var nearest := eyes[0]
		for at in eyes:
			if at.distance_squared_to(patch.fishes) < nearest.distance_squared_to(patch.fishes):
				nearest = at
		var in_range := nearest.distance_squared_to(patch.fishes) < WATCH_RANGE * WATCH_RANGE
		var rendered := eyes[0].distance_squared_to(patch.fishes) < WATCH_RANGE * WATCH_RANGE
		nearby = nearby or in_range
		patch.rings.visible = false
		if not combat.absent(patch.heron_id):
			_restore_targets(patch.heron_id)
			_update_heron(patch, eyes, now)
			patch.bird.position = combat.rejoin(patch.heron_id, patch.bird.position, now)
			patch.bird.visible = stream.at_surface(patch.bird.position)
			var on_bank := patch.wading and absf(patch.bird.position.y-stream.ground_at(patch.bird.position))<0.16
			_drive(patch.heron_id,patch.upper.bones,patch.bird.visible,on_bank)
		else:
			patch.bird.hide()
			_drop_driver(patch.heron_id)
		_update_school(patch, nearest, now, step, rendered)
		_drive_school(patch)
	for animal in bottom_life:
		var closest := eyes[0]
		for at in eyes:
			if at.distance_squared_to(animal.anchor)<closest.distance_squared_to(animal.anchor):
				closest = at
		var id: String = animal.get_meta("lake_id")
		nearby = nearby or closest.distance_squared_to(animal.anchor)<45.0*45.0
		if combat.absent(id):
			_drop_driver(id)
			animal.hide()
			animal.active_pose = false
			continue
		_restore_targets(id)
		animal.advance(stream,closest,now,step)
		animal.position = combat.rejoin(id,animal.position,now)
		animal.visible = stream.at_surface(animal.position)
		animal.active_pose = animal.visible
		var on_bed := animal.species == "crayfish" and animal.tail_flick<0.40 and absf(animal.position.y-stream.ground_at(animal.position))<0.12
		_drive(id,animal.bones,animal.active_pose,on_bed)
	if not nearby:
		countdown = 0.12 if not drivers.is_empty() else 0.4

func _restore_targets(id: String) -> void:
	if drivers.has(id): drivers[id].restore_targets()

func _drive(id: String, skeleton: Skeleton3D, simulation_ready: bool, grounded: bool) -> void:
	var existing: Node3D = drivers.get(id)
	if not simulation_ready:
		_drop_driver(id)
	elif existing == null:
		var drive: Node3D = ActiveMotion.start(self,skeleton,stream)
		if drive != null:
			drive.balance.support_enabled = grounded
			drivers[id] = drive
	else:
		existing.balance.support_enabled = grounded
		existing.capture_targets()

func _drop_driver(id: String) -> void:
	var rig := take_driver(id)
	if rig != null: rig.stop_driving()

func take_driver(id: String) -> ActiveMotion:
	var rig: ActiveMotion = drivers.get(id)
	drivers.erase(id)
	if individual_fish.has(id):
		var fish: Dictionary = individual_fish[id]
		if rig != null and fish.has("sync"):
			rig.pose_applied.disconnect(fish.sync)
		fish.model.queue_free()
		individual_fish.erase(id)
	return rig

func resume_animal(id: String, kind: String, rig: ActiveMotion, at: Transform3D) -> bool:
	var skeleton: Skeleton3D
	if kind=="heron" or kind=="lake_fish":
		for patch in habitats:
			if id==patch.heron_id:
				patch.bird.global_position = at.origin
				skeleton = patch.upper.bones
				break
			var slot := patch.fish_ids.find(id)
			if slot>=0:
				skeleton = _school_member(patch,slot,at).skeleton
				break
	else:
		for animal in bottom_life:
			if animal.get_meta("lake_id")==id:
				animal.global_position = at.origin
				skeleton = animal.bones
				break
	if skeleton==null: return false
	rig.rebind_skeleton(skeleton)
	rig.resume_driving()
	rig.balance.support_enabled = false
	drivers[id] = rig
	return true

func _school_member(patch: Habitat, index: int, pose: Transform3D) -> Dictionary:
	var id := patch.fish_ids[index]
	if not individual_fish.has(id):
		var fish := FishRig.new()
		add_child(fish)
		fish.hide()
		fish.global_transform = pose
		var skeleton := fish.build_physical("local" if patch.mottled else "",patch.face_slots[index].x,patch.beats[index],patch.dart)
		individual_fish[id] = {"model":fish,"skeleton":skeleton}
	return individual_fish[id]

func _drive_school(patch: Habitat) -> void:
	for i in patch.fish_ids.size():
		var id := patch.fish_ids[i]
		var pose := patch.fish_poses[i]
		if not pose.origin.is_finite():
			_drop_driver(id)
			continue
		var beat := patch.beats[i]
		var member := _school_member(patch,i,pose)
		_restore_targets(id)
		member.model.global_transform = pose
		FishRig.pose_physical(member.skeleton, beat, patch.dart)
		_drive(id, member.skeleton, true, false)
		if not member.has("sync") and drivers.has(id):
			var sync := _sync_school_member.bind(patch,i,member.skeleton)
			drivers[id].pose_applied.connect(sync)
			member.sync = sync
			sync.call()

func _update_heron(patch: Habitat, eyes: Array[Vector3], now: float) -> void:
	var elapsed := now - patch.took_off
	if elapsed >= FLIGHT_TIME:
		if patch.took_off > -99.0 and patch.perch!=patch.next_perch:
			patch.perch = patch.next_perch
			patch.perched_since = patch.took_off+FLIGHT_TIME+patch.phase+2.0
		var walk_cycle := now-patch.perched_since+patch.phase+2.0
		var cycle_time := fposmod(walk_cycle,8.6)
		var outward := posmod(floori(walk_cycle/8.6),2)==0
		var stride := smoothstep(2.9,6.3,cycle_time)
		var turn := smoothstep(6.4,8.5,cycle_time)
		var bank := patch.perches[1-patch.perch]-patch.perches[patch.perch]
		var along := minf(0.55,bank.length()*0.10)
		bank = bank.normalized()
		patch.bird.position = patch.perches[patch.perch]+bank*along*(stride if outward else 1.0-stride)
		if stream != null:
			patch.bird.position.y = stream.ground_at(patch.bird.position)
		var wade_yaw := atan2(-bank.x,-bank.z)+PI*(turn if outward else 1.0-turn)
		patch.bird.rotation.y = lerp_angle(patch.flight_yaw,wade_yaw,smoothstep(FLIGHT_TIME,FLIGHT_TIME+0.95,elapsed))
		for at in eyes:
			if elapsed > FLIGHT_TIME + 1.0 and at.distance_squared_to(patch.bird.position) < 6.4 * 6.4:
				patch.next_perch = 1 - patch.perch
				patch.took_off = now
				patch.flight_start = patch.bird.position
				patch.takeoff_yaw = patch.bird.rotation.y
				elapsed = 0.0
				var direction := patch.perches[patch.next_perch] - patch.bird.position
				patch.flight_yaw = atan2(-direction.x, -direction.z)
				break
	var flying := elapsed < FLIGHT_TIME
	const PUSH_OFF := 0.16
	patch.wading = not flying or elapsed <= PUSH_OFF
	if flying:
		var t := clampf(inverse_lerp(PUSH_OFF,FLIGHT_TIME,elapsed),0.0,1.0)
		patch.bird.rotation.y = lerp_angle(patch.takeoff_yaw,patch.flight_yaw,smoothstep(0.0,0.42,elapsed))
		var landing := patch.perches[patch.next_perch]
		if stream != null: landing.y = stream.ground_at(landing)
		patch.bird.position = patch.flight_start.lerp(landing,smoothstep(0.0,1.0,t))
		var arc := 4.0*t*(1.0-t)*smoothstep(0.0,0.07,t)
		patch.bird.position.y += 3.35*arc*lerpf(0.22,1.0,smoothstep(0.0,0.21,1.0-t))
	var spread := smoothstep(0.0,0.38,elapsed)*(1.0-smoothstep(FLIGHT_TIME-0.09,FLIGHT_TIME+0.36,elapsed))
	var tuck := smoothstep(PUSH_OFF,0.71,elapsed)*(1.0-smoothstep(FLIGHT_TIME-1.0,FLIGHT_TIME-0.25,elapsed))
	var flare := smoothstep(FLIGHT_TIME-0.93,FLIGHT_TIME-0.34,elapsed)*(1.0-smoothstep(FLIGHT_TIME-0.15,FLIGHT_TIME+0.11,elapsed))
	var crouch := smoothstep(0.0,PUSH_OFF,elapsed)*(1.0-smoothstep(PUSH_OFF,0.36,elapsed))
	crouch += smoothstep(FLIGHT_TIME-0.04,FLIGHT_TIME+0.12,elapsed)*(1.0-smoothstep(FLIGHT_TIME+0.12,FLIGHT_TIME+0.57,elapsed))
	patch.upper.pose(now-patch.perched_since,patch.phase,spread,elapsed*7.0,tuck,crouch,flare)

func _update_school(patch: Habitat, observer: Vector3, now: float, delta: float, rendered: bool) -> void:
	var proximity := 1.0 - smoothstep(1.2, 7.0, observer.distance_to(patch.fishes))
	patch.dart = move_toward(patch.dart, proximity, delta * 1.5)
	patch.swim_angle = now * (0.25 if patch.mottled else 0.40) + patch.phase
	var away := Vector2(patch.fishes.x - observer.x, patch.fishes.z - observer.z).normalized()
	patch.escape_offset = patch.escape_offset.move_toward(away*Vector2(1.35,1.0)*patch.dart,delta*1.85)
	var sample_time := now - patch.last_swim_time
	patch.last_swim_time = now
	var lead := Vector3.INF
	var center := Vector3.ZERO
	var count := 0
	for i in SCHOOL_SIZE:
		var id: String = patch.fish_ids[i]
		if combat.absent(id):
			_hide_member(patch, i)
			continue
		var angle := patch.swim_angle + i * 0.29 + patch.dart * sin(now * 1.5) * 0.4
		var radius := (1.35 + (i % 3) * 0.44) * (1.15 if patch.mottled else 0.73)
		var point := patch.fishes + Vector3(sin(angle)*radius+patch.escape_offset.x,0,cos(angle)*0.85-i*0.17+patch.escape_offset.y)
		point.y = -0.13 - 0.06 * sin(angle + i) - patch.dart * 0.12
		# Keep fish under the surface and above the revised or edited lake bed.
		var bed := stream.ground_at(point)
		if bed > point.y - 0.09:
			point.z -= 2.3
			if stream.ground_at(point) > point.y - 0.09:
				_hide_member(patch, i)
				continue
		var scale_factor := (0.78 + 0.08 * (i % 3)) * (1.20 if patch.mottled else 0.89)
		point = combat.rejoin(id, point, now)
		if not stream.at_surface(point):
			_hide_member(patch,i)
			continue
		var tangent := Vector3(cos(angle)*radius,-0.06*cos(angle+i),-sin(angle)*0.85)*(0.25 if patch.mottled else 0.40)
		var previous := patch.fish_poses[i]
		var velocity := tangent
		var turning := previous.origin.is_finite() and sample_time>0.0 and sample_time<=0.32
		if turning:
			var travel := point-previous.origin
			turning = travel.length()<sample_time*4.0+0.10
			if turning: velocity = travel/sample_time
		var angles := previous.basis.orthonormalized().get_euler() if turning else Vector3.ZERO
		var speed := velocity.length()
		var flat := Vector2(velocity.x,velocity.z)
		var heading := atan2(-flat.x,-flat.y) if flat.length_squared()>0.0004 else angles.y
		var yaw := rotate_toward(angles.y,heading,5.8*delta) if turning else heading
		var pitch := clampf(atan2(velocity.y,maxf(0.03,flat.length())),-0.46,0.46)
		var roll := 0.0
		if turning:
			var turn_rate := angle_difference(angles.y,yaw)/sample_time
			var response := 1.0-exp(-delta*8.0)
			pitch = lerpf(angles.x,pitch,response)
			roll = lerpf(angles.z,clampf(turn_rate*speed*0.26,-0.55,0.55),response)
		var pose := Transform3D(Basis.from_euler(Vector3(pitch,yaw,roll)).scaled(Vector3.ONE*scale_factor),point)
		patch.fish_poses[i] = pose
		patch.beats[i] = fmod(patch.beats[i]+delta*clampf(2.9+speed*8.5,3.0,16.0),TAU)
		center += point
		count += 1
		if not lead.is_finite():
			lead = point
	patch.fish_center = center / count if count else Vector3.INF
	patch.school.visible = count>0
	if not lead.is_finite():
		return
	var cycle := fposmod(now * (0.63 + patch.dart * 0.6) + patch.phase, 2.0)
	patch.rings.visible = rendered and cycle < 1.0
	if patch.rings.visible:
		for ring in 2:
			var radius := 0.10 + cycle * 0.92 + ring * 0.25
			var surface := Vector3(lead.x, 0.042, lead.z)
			patch.rings.multimesh.set_instance_transform(ring, Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 1.25, 0.23, radius)), surface))

func _sync_school_member(patch: Habitat, index: int, skeleton: Skeleton3D) -> void:
	_fish_pose(patch,index,skeleton.global_transform,skeleton)

func _fish_pose(patch: Habitat, index: int, frame: Transform3D, skeleton: Skeleton3D = null) -> void:
	var pose := frame
	for part in patch.segments.size():
		var segment := frame*skeleton.get_bone_global_pose(part) if skeleton else frame
		patch.segments[part].multimesh.set_instance_transform(index,segment)
		if part==0: pose = segment
	var face := Transform3D(Basis.IDENTITY.scaled(Vector3(FISH_FACE_SIZE.x, FISH_FACE_SIZE.y, FISH_FACE_SIZE.x)), FISH_FACE_CENTER)
	patch.faces.multimesh.set_instance_transform(index, pose * face)
	var slot:=patch.face_slots[index]
	var skin:=Transform3D(Basis.from_scale(FISH_RADII),FISH_SKULL)
	patch.natural_faces[slot.x].multimesh.set_instance_transform(slot.y,pose*skin)

func _hide_member(patch: Habitat, index: int) -> void:
	if not patch.fish_poses[index].origin.is_finite(): return
	patch.fish_poses[index].origin = Vector3.INF
	_fish_pose(patch, index, Transform3D(Basis.from_scale(Vector3.ONE * 0.00001), patch.fishes))

func preview_model(parent: Node, id: String, morph: String, face:=0) -> Node3D:
	if WastelandBenthicAnimal.NAMES.has(id):
		var animal := WastelandBenthicAnimal.new()
		parent.add_child(animal)
		animal.build(id,morph,face,true)
		return animal
	if id == "heron":
		var bird := HeronRig.new()
		parent.add_child(bird)
		bird.build(morph=="young",face,true)
		bird.scale = Vector3.ONE*(0.78 if morph=="young" else 1.0)
		return bird
	var fish := FishRig.new()
	parent.add_child(fish)
	fish.build(morph,face)
	return fish

func observation(eye: Vector3, forward: Vector3, max_distance: float = 25.0) -> Dictionary:
	var best := {}
	var nearest := max_distance
	var facing := forward.normalized()
	for patch in habitats:
		for species in ["heron", "lake_fish"]:
			var is_heron: bool = species == "heron"
			if is_heron and combat.absent(patch.heron_id):
				continue
			var point := patch.bird.global_position + Vector3.UP * (0.78 if patch.juvenile else 0.94) if is_heron else patch.fish_center
			if not point.is_finite():
				continue
			var offset := point - eye
			var depth := offset.dot(facing)
			var distance := offset.length()
			if depth <= 0.0 or distance > nearest:
				continue
			var width := 0.68 if is_heron else 1.45
			if (offset - facing * depth).length() > width + distance * 0.016:
				continue
			nearest = distance
			var label := "灰鹭幼鸟" if patch.juvenile else "冠羽灰鹭"
			if not is_heron:
				label = "斑纹湖鱼群" if patch.mottled else "银鳞湖鱼群"
			var morph := "young" if is_heron and patch.juvenile else "local" if not is_heron and patch.mottled else ""
			best = {"type": species, "name": label, "morph": morph, "point": point, "distance": distance}
	for animal in bottom_life:
		if not animal.active_pose or combat.absent(animal.get_meta("lake_id")):
			continue
		var point := animal.global_position+Vector3.UP*0.1
		var offset := point-eye
		var distance := offset.length()
		var depth := offset.dot(facing)
		if depth<0.0 or distance>nearest or (offset-facing*depth).length()>0.38+distance*0.012:
			continue
		nearest = distance
		var name_pair: Array = WastelandBenthicAnimal.NAMES[animal.species]
		best = {"type":animal.species,"name":name_pair[int(animal.morph=="local")],"morph":animal.morph,"point":point,"distance":distance}
	return best

