class_name WastelandCreature
extends CharacterBody3D

const Hoofprints := preload("res://game/actors/hoofprints.gd")
const InfectedLooks := preload("res://game/art/infected_looks.gd")
const Wardrobe := preload("res://game/art/infected_wardrobe.gd")
const InfectedLimbs := preload("res://game/art/infected_limbs.gd")
const InfectedMotion := preload("res://game/actors/infected_motion.gd")
const PhysicalRagdoll := preload("res://game/actors/physical_ragdoll.gd")
const ActiveMotion := preload("res://game/actors/active_ragdoll.gd")
const RagdollHits := preload("res://game/actors/ragdoll_hits.gd")
const CORPSE_SECONDS := PhysicalRagdoll.CORPSE_SECONDS
const WARDROBE_COUNT := 3 * 3 * 4

var director: Node3D
var session: Node3D
var spec: Dictionary
var type := ""
var morph := ""
var look_index := 0
var wardrobe_index := 0
var limb_index := 0
var face_variant := 0
var limb_damage := Vector4i.ZERO
var active := false
var wave := false
var spawn_serial := 0
var hp := 0.0
var stagger := 0.0
var hit_pause:=0.0
var hurt := 0.0
var visible_hurt := -1.0
var impact_tilt := Vector2.ZERO
var ragdoll: PhysicalRagdoll
var active_motion: ActiveMotion
var ragdoll_impact := Vector3.ZERO
var ragdoll_hit_at := Vector3.INF
var ragdoll_hit_bone: StringName = &""
var limb_hit_serial := 0
var ragdoll_start_frame := -1
var corpse_hits_enabled := false
var rise_from: Array[Transform3D] = []
var rise_target: Array[Transform3D] = []
var rise_time := 0.0
var print_distance := 0.0
var print_position := Vector3.ZERO
var print_side := 1.0
var voice_clock := 0.0
var pose_phase := 0.0
var phase_clock := 0.0
var motion_speed := 0.0
var motion_turn := 0.0
var motion_clock := 0.0
var motion_water := false
var motion_distance := 0.0
var motion_yaw := 0.0
var motion_preview := false
var motion_floor_normal := Vector3.UP
var support_world := Vector3.UP
var support_poll := 0.0
var wildlife_cycle := 0.0
var offscreen := 0.0
var attack := 0.0
var windup := 0.0
var attack_kind := WastelandCreatureBrain.Action.NONE
var motion_action := WastelandCreatureBrain.Action.NONE
var motion_rest := 0.0
var foot_contacts := preload("res://game/actors/creature_foot_contacts.gd").new()
var fuse_left := 0.0
var blast_ring: MeshInstance3D
var gland: MeshInstance3D
var gland_size := Vector3.ONE
var water_step := 0.0
var alerted := false
var screamed := false
var brain := WastelandCreatureBrain.new()
var wildlife_motion := preload("res://game/actors/wildlife_motion.gd").new()
var rig := Node3D.new()
var skeleton := Skeleton3D.new()
var collider: CollisionShape3D
var capsule := CapsuleShape3D.new()
var body_parts: Dictionary = {}
var cloth_motion: Wardrobe.ClothMotion
var render_colors: Dictionary = {}
var actor_rng := RandomNumberGenerator.new()
var hurtboxes := preload("res://game/actors/infected_hitboxes.gd").new()
var rest_contacts: Array[Dictionary] = []
var stage_health := 1.0
var nest := ""
var leg_hits := 0
var limp_left := 0.0
var hit_chain := 0
var hit_chain_left := 0.0
var ground_step := false
var surface_retry := 0.0
var ground_cast := PhysicsShapeQueryParameters3D.new()
var separation_left := 0.0
var separation_force := Vector3.ZERO
var fall := preload("res://game/actors/creature_fall.gd").new()
var trap_left := 0.0
var trap_scale := 1.0
var scream_ring: MeshInstance3D

func configure(owner_director: Node3D) -> void:
	director = owner_director
	session = director.session
	floor_max_angle = deg_to_rad(53)
	floor_snap_length = 0.37
	collision_layer = 0
	collision_mask = 0
	collider = CollisionShape3D.new()
	collider.shape = capsule
	ground_cast.shape = capsule
	ground_cast.collision_mask = 2 | 8 | 128
	ground_cast.exclude = [get_rid()]
	ground_cast.margin = 0.015
	add_child(collider)
	add_child(rig)
	rig.add_child(skeleton)
	visible = false
	actor_rng.seed = get_instance_id()
	brain.configure(self)

func revive(kind: String, point: Vector3, night_wave: bool, previous: Dictionary) -> void:
	_stop_active_motion()
	rise_from.clear()
	rise_target.clear()
	_clear_ragdoll()
	ragdoll_impact = Vector3.ZERO
	ragdoll_hit_at = Vector3.INF
	ragdoll_hit_bone = &""
	limb_hit_serial = 0
	ragdoll_start_frame = -1
	var next_morph := str(previous.get("morph",""))
	var animal := bool(session.catalog.enemies[kind].get("animal",false))
	if next_morph not in (["young","local"] if animal else ["armored","swift"]):
		next_morph = ""
	var next_look := int(previous.get("look_index", 0))
	if next_look < 0 or next_look >= InfectedLooks.count_for(kind):
		next_look = 0
	var next_wardrobe := int(previous.get("wardrobe_index", 0))
	if animal or next_wardrobe < 0 or next_wardrobe >= WARDROBE_COUNT:
		next_wardrobe = 0
	var next_limb := int(previous.get("limb_index", 0))
	if animal or next_limb < 0 or next_limb >= InfectedLimbs.COUNT:
		next_limb = 0
	var next_face := int(previous.get("face_variant", 0))
	if next_face != 1:
		next_face = 0
	if type != kind or morph != next_morph or look_index != next_look or wardrobe_index != next_wardrobe or limb_index != next_limb or face_variant != next_face:
		type = kind
		morph = next_morph
		look_index = next_look
		wardrobe_index = next_wardrobe
		limb_index = next_limb
		face_variant = next_face
		spec = session.catalog.enemies[kind]
		_rebuild_model()
	stage_health = maxf(0.1, float(previous.get("stage_health", 1.0)))
	hp = clampf(float(previous.get("hp",max_health())),0.0,max_health())
	nest = str(previous.get("nest", ""))
	leg_hits = int(previous.get("leg_hits", 0))
	limp_left = maxf(0.0, float(previous.get("limp_left", 0.0)))
	hit_chain = 0
	hit_chain_left = 0.0
	fall.reset(point)
	ground_step = false
	surface_retry = 0.0
	separation_left = 0.0
	separation_force = Vector3.ZERO
	trap_scale = 1.0
	trap_left = 0.0
	wave = night_wave
	active = true
	visible = true
	collision_layer = 4 if animal else 4 | 128
	collision_mask = 3 | 8 if animal else 3 | 8 | 128
	global_position = point
	print_position = point
	print_distance = 0.0
	print_side = 1.0
	rotation.y = float(previous.get("facing", actor_rng.randf_range(-PI, PI)))
	velocity = Vector3.ZERO
	stagger = 0.0
	impact_tilt = Vector2.ZERO
	rig.rotation = Vector3.ZERO
	rig.position = Vector3.ZERO
	pose_phase = actor_rng.randf() * TAU
	pose_phase = float(previous.get("stride_phase",pose_phase))
	wildlife_cycle = fposmod(float(previous.get("wildlife_cycle",pose_phase/TAU)),1.0)
	motion_clock = pose_phase
	motion_distance = 0.0
	motion_speed = 0.0
	motion_turn = 0.0
	foot_contacts.clear()
	motion_yaw = rotation.y
	motion_water = false
	motion_floor_normal = Vector3.UP
	support_world = Vector3.UP
	support_poll = 0.0
	phase_clock = float(posmod(spawn_serial,7)) * 0.004
	voice_clock = actor_rng.randf_range(1.5, 7.0)
	alerted = bool(previous.get("alerted", wave))
	screamed = bool(previous.get("screamed", false))
	offscreen = 0.0
	hurt = 0.0
	visible_hurt = -1.0
	attack = 0.0
	windup = 0.0
	attack_kind = WastelandCreatureBrain.Action.NONE
	motion_action = WastelandCreatureBrain.Action.NONE
	motion_rest = clampf(float(previous.get("motion_rest",0.0)),0.0,1.0)
	water_step = 0.0
	fuse_left = 0.0
	skeleton.reset_bone_poses()
	brain.revive(previous)
	if animal:
		wildlife_motion.reset(self)
	InfectedLimbs.pose(self, 0.0)
	hurtboxes.enable(hp > 0.0)
	if not animal:
		_posture()
	hurtboxes.pose(self)
	if brain.state != WastelandCreatureBrain.State.DEAD: _ensure_active_motion()
	if brain.state in [WastelandCreatureBrain.State.DEAD, WastelandCreatureBrain.State.KNOCKDOWN]:
		sync_ragdoll(previous.get("ragdoll_pose",PackedFloat32Array()), previous.get("ragdoll_impact",Vector3.ZERO),
			previous.get("ragdoll_hit_at",Vector3.INF),previous.get("ragdoll_hit_bone",&""),previous.get("fall_launch",Vector3.INF))
		if ragdoll != null and not previous.get("ragdoll_settled",false) and not session.replica:
			ragdoll.kick(Vector3.ZERO)
			if previous.has("fall_drop") and hp>0:
				ragdoll.set_motion(previous.get("fall_velocity",Vector3.ZERO))
				_watch_fall(maxf(0.0,float(previous.fall_drop)))
	if type == "bloater" and hp <= 0.0 and brain.state != WastelandCreatureBrain.State.DEAD:
		_prime_rupture(float(previous.get("fuse", spec.ai.fuse)))

func display_name() -> String:
	var prefix: String = {"armored":"披甲","swift":"迅行","young":"幼年","local":"地方色"}.get(morph,"")
	return prefix + str(spec.name)

func max_health() -> float:
	var factor := 1.42 if morph=="armored" else 0.77 if morph=="swift" else 0.62 if morph=="young" else 1.0
	var vitality := 1.0 - 0.045*(limb_damage.x+limb_damage.y) - 0.065*(limb_damage.z+limb_damage.w)
	return float(spec.hp)*float(session.world_settings.difficulty)*factor*vitality*stage_health

func low_crawl() -> bool:
	return limb_damage.z > 0 and limb_damage.w > 0 and limb_damage.z + limb_damage.w >= 3

func biting() -> bool:
	return limb_damage.x > 0 and limb_damage.y > 0

func can_rush() -> bool:
	return limb_damage.z == 0 and limb_damage.w == 0

func melee_factor() -> float:
	return 1.0 - 0.12*(limb_damage.x+limb_damage.y) if not biting() else 0.54 - 0.04*(limb_damage.x+limb_damage.y)

func wall_factor() -> float:
	return 0.0 if biting() else melee_factor() * float(spec.get("breach_multiplier",1.0))

func melee_origin() -> Vector3:
	var joint := "head" if brain.animal or biting() else "hand_l" if limb_damage.y > 0 else "hand_r"
	var bone := skeleton.find_bone(joint)
	if bone == -1:
		return global_position + Vector3.UP * body_height() * 0.54
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin

func body_height() -> float:
	return capsule.height if limb_index > 0 else float(spec.height)

func max_move_speed() -> float:
	var speed := float(spec.speed)
	if not spec.get("animal", false):
		speed *= float(session.world_settings.get("zombie_speed", 1.0))
		if type == "walker" and session.clock != null:
			var hour: float = session.clock.hour()
			speed *= 1.32 if hour < 5.0 or hour >= 21.0 else 0.91
		speed *= 1.25 if brain.rage_left > 0.0 else 1.0
		speed *= 0.5 if limp_left > 0.0 else 1.0
	speed *= trap_scale if trap_left > 0.0 else 1.0
	speed *= 0.81 if morph=="armored" else 1.27 if morph=="swift" else 1.12 if morph=="young" else 1.05 if morph=="local" else 1.0
	if low_crawl():
		return speed * (0.35 - 0.045*(limb_damage.x+limb_damage.y))
	return speed * (1.0 - 0.17*(limb_damage.z+limb_damage.w))

func deactivate() -> void:
	fall.reset()
	if cloth_motion: cloth_motion.reset()
	_stop_active_motion()
	rise_from.clear()
	rise_target.clear()
	_clear_ragdoll()
	hit_pause=0.0
	active = false
	if is_instance_valid(blast_ring): blast_ring.hide()
	if is_instance_valid(scream_ring): scream_ring.hide()
	hurtboxes.enable(false)
	brain.seen = null
	brain.slot_target = null
	brain.slot = -1
	brain._cancel_action()
	brain.route.clear_plan()
	brain.rage_left = 0.0
	brain.retreat_left = 0.0
	brain.state_left = 0.0
	brain.light_dwell = 0.0
	brain.interest = Vector3.INF
	brain.memory = 0.0
	brain.goal = Vector3.INF
	brain.search_left = -1.0
	brain.pursuing_cue = false
	brain.overflow = false
	limp_left = 0.0
	leg_hits = 0
	trap_left = 0.0
	trap_scale = 1.0
	hit_chain = 0
	hit_chain_left = 0.0
	nest = ""
	fuse_left = 0.0
	attack = 0.0
	windup = 0.0
	hurt = 0.0
	stagger = 0.0
	alerted = false
	screamed = false
	wave = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO

func serialize() -> Dictionary:
	var row := {"id": type, "serial":spawn_serial, "at": global_position, "hp": hp, "wave": wave, "alerted": alerted, "screamed": screamed, "face_variant":face_variant}
	row.stride_phase = fposmod(pose_phase,TAU)
	if brain.animal:
		row.wildlife_cycle = wildlife_cycle
	if ragdoll != null:
		row.ragdoll_pose = ragdoll_pose()
		row.ragdoll_impact = ragdoll_impact
		row.ragdoll_hit_at = ragdoll_hit_at
		row.ragdoll_hit_bone = ragdoll_hit_bone
		row.ragdoll_settled = ragdoll_settled()
		row.fsm = brain.state
		row.facing = rotation.y
		row.state_left = brain.state_left
		if fall.from_fall: row.fall_launch = fall.launch_velocity
		if fall.pending:
			row.fall_drop = maxf(0.0,fall.peak-physical_position().y)
			row.fall_velocity = ragdoll.motion()
	if fuse_left > 0.0: row.fuse = fuse_left
	if not morph.is_empty():
		row.morph = morph
	if InfectedLooks.count_for(type) > 0:
		row.look_index = look_index
	if not spec.get("animal", false):
		row.stage_health = stage_health
		row.nest = nest
		row.fsm = brain.state
		if motion_rest > 0.0: row.motion_rest = motion_rest
		row.pursuing_cue = brain.pursuing_cue
		row.state_left = brain.state_left
		row.facing = rotation.y
		row.rage_left = brain.rage_left
		row.wake_span = brain.wake_span
		row.leg_hits = leg_hits
		row.limp_left = limp_left
		if brain.retreat_left > 0.0:
			row.retreat_left = brain.retreat_left
			row.retreat_goal = brain.goal
		row.wardrobe_index = wardrobe_index
		row.limb_index = limb_index
	if brain.herd > 0:
		row.herd = brain.herd
		row.home = brain.home
	if brain.memory > 0.0 and brain.interest.is_finite():
		row.interest = brain.interest
		row.memory = brain.memory
	return row

func _rebuild_model() -> void:
	_stop_active_motion()
	cloth_motion = null
	gland = null
	rest_contacts.clear()
	limb_damage = InfectedLimbs.decode(limb_index)
	for child in skeleton.get_children():
		skeleton.remove_child(child)
		child.queue_free()
	skeleton.clear_bones()
	body_parts.clear()
	render_colors.clear()
	var height := float(spec.height)
	capsule.height = height
	capsule.radius = 0.29 if not spec.get("animal", false) else 0.32
	collider.position.y = height * 0.5
	var coat := Color.html(spec.cloth)
	var skin := Color.html(spec.skin)
	var variant := int(spec.get("rig", spec.variant)) if type not in ["mudwalker","sandrunner"] else 0
	rig.position = Vector3.ZERO
	rig.rotation = Vector3.ZERO
	rig.scale = Vector3.ONE
	if spec.get("animal", false):
		capsule.radius = float({"stag":0.26,"boar":0.28,"wolf":0.22,"fox":0.15,"hare":0.11,"badger":0.15,"argali":0.24,"jerboa":0.10,"otter":0.14}.get(type,0.22))
		capsule.height = height
		if morph=="local":
			var colors: Dictionary = {
				"stag": ["#5a5555","#d4cfc1"], "boar": ["#ae876c","#745b53"], "fox": ["#d9cdb9","#f6eee0"],
				"hare": ["#8c7969","#c6b396"], "wolf": ["#49474e","#aba3a1"], "badger": ["#a48971","#deccb9"], "argali":["#8b8580","#e5d5b6"],"jerboa":["#876f58","#d7cbb7"],"otter":["#564b40","#d7bc93"]}
			coat = Color.html(colors[type][0])
			skin = Color.html(colors[type][1])
		elif morph=="young":
			coat = coat.lightened(0.15)
			skin = skin.lightened(0.08)
		WastelandBestiary.wildlife(self,type,coat,skin)
	elif variant == 1:
		WastelandBestiary.crawler(self,coat,skin)
	else:
		var scale_factor := height / 1.80
		rig.scale = Vector3.ONE * scale_factor
		capsule.radius = 0.38 if variant == 4 else 0.33 if variant == 3 else 0.29
		WastelandBestiary.upright(self,variant,coat,skin)
		if type in ["bloater", "spitter", "rimecaller"]:
			gland = MeshInstance3D.new()
			var gland_joint: Node3D = body_parts.torso
			match type:
				"spitter":
					gland_joint = body_parts.head
					gland.position = Vector3(0.024,-0.004,-0.079)
					gland_size = Vector3(0.100,0.098,0.100)
				"bloater":
					gland.position = Vector3(0.028,0.025,-0.098)
					gland_size = Vector3(0.48,0.46,0.29)
				"rimecaller":
					gland.position = Vector3(0,0.14,-0.16)
					gland_size = Vector3(0.18,0.15,0.12)
			gland_joint.add_child(gland)
			gland.scale = gland_size
			gland.mesh = WastelandBestiary.gland_mesh(type, look_index)
			gland.material_override = WastelandBestiary.gland_material(self)
	if morph=="young":
		rig.scale *= Vector3(0.69,0.67,0.72)
		for piece: Node3D in body_parts.head.get_children():
			piece.scale *= 1.15
		capsule.radius *= 0.72
		capsule.height = height*0.70
	elif morph=="local":
		rig.scale *= Vector3(1.10,1.0,1.05)
		capsule.radius *= 1.07
	elif morph in ["armored","swift"]:
		var armored := morph=="armored"
		rig.scale *= Vector3(1.11,1.02,1.08) if armored else Vector3(0.80,1.06,0.86)
		capsule.radius *= 1.09 if armored else 0.84
		capsule.height = height * (1.02 if armored else 1.06)
		WastelandBestiary.mutation(self,armored)
	if not spec.get("animal", false):
		cloth_motion = Wardrobe.dress(self)
		InfectedLimbs.fit(self)
	WastelandBestiary.attach_april_face(self)
	hurtboxes.fit(self)
	collider.position.y = capsule.height * 0.5

func _joint(label: String, parent_id: int, offset: Vector3, segments: Array, rest_basis: Basis = Basis.IDENTITY) -> void:
	var index := skeleton.add_bone(label)
	skeleton.set_bone_parent(index, parent_id)
	skeleton.set_bone_rest(index, Transform3D(rest_basis, offset))
	skeleton.reset_bone_pose(index)
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = label
	skeleton.add_child(attachment)
	body_parts[label] = attachment
	for segment in segments:
		var dimensions: Vector3 = segment[1]
		var mesh := WastelandLook.form(attachment, dimensions, segment[0], segment[2], 0.17 if dimensions.x > 0.14 else 0.11)
		mesh.material_override = _toon_material(segment[2])

func _hand(side: int, offset: Vector3, pitch_angle: float, skin: Color, gripping: bool = false) -> void:
	var letter := "l" if side < 0 else "r"
	var label := "hand_" + letter
	var rest_basis := Basis(Vector3.RIGHT, pitch_angle)
	if gripping:
		rest_basis *= Basis(Vector3.FORWARD, -side * 0.96)
	_joint(label, skeleton.find_bone("elbow_" + letter), offset, [], rest_basis)
	var hand := MeshInstance3D.new()
	hand.name = "HandMesh"
	hand.mesh = WastelandBestiary.hand_mesh(side, gripping)
	hand.material_override = _toon_material(skin)
	body_parts[label].add_child(hand)

func _toon_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not render_colors.has(key):
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://shaders/toon.gdshader")
		paint.set_shader_parameter("tint", color)
		render_colors[key] = paint
	return render_colors[key]

func apply_trap_slow(seconds: float, movement_scale: float) -> void:
	trap_scale = minf(trap_scale if trap_left > 0.0 else 1.0, clampf(movement_scale, 0.0, 1.0))
	trap_left = maxf(trap_left, seconds)

func impact_bone(body: CollisionObject3D, shape_id: int, point: Vector3) -> StringName:
	return hurtboxes.bone_at(body,shape_id,point)

func hit_zone(zone: String, amount: float, origin: Vector3, heavy := false, stealth := false, hit_at := Vector3.INF, hit_bone: StringName = &"") -> void:
	if not active or hp <= 0.0:
		return
	var knocked := false
	if zone == "head":
		var ambush := stealth and not alerted
		amount *= 3.0 if ambush else 2.0
		knocked = actor_rng.randf() < (0.85 if ambush else 0.65)
		heavy = true
	elif zone == "legs":
		amount *= 0.8
		leg_hits += 1
		if leg_hits >= 2 or heavy:
			limp_left = 3.5
			leg_hits = 0
			knocked = true
	take_hit(amount,origin,heavy,knocked,hit_at,hit_bone)

func begin_death(impact := Vector3.ZERO, hit_at := Vector3.INF, hit_bone: StringName = &"") -> void:
	if brain.state == WastelandCreatureBrain.State.DEAD:
		return
	hp = 0.0
	if fall.pending and ragdoll: ragdoll.watch_landing(false)
	fall.pending = false
	brain._cancel_action()
	brain.state = WastelandCreatureBrain.State.DEAD
	brain.state_left = CORPSE_SECONDS
	brain.rage_left = 0.0
	brain.slot = -1
	brain.slot_target = null
	brain.seen = null
	collision_layer = 0
	hurtboxes.enable(false)
	if ragdoll != null and not impact.is_zero_approx():
		ragdoll.kick_at(impact,hit_at,hit_bone)
	sync_ragdoll(PackedFloat32Array(),impact if not impact.is_zero_approx() else velocity,hit_at,hit_bone)
	velocity = Vector3.ZERO
	attack = 0.0
	attack_kind = WastelandCreatureBrain.Action.NONE
	windup = 0.0
	if is_instance_valid(blast_ring): blast_ring.hide()
	if is_instance_valid(scream_ring): scream_ring.hide()

func physical_position() -> Vector3:
	return ragdoll.center() if ragdoll != null else global_position

func ragdoll_pose() -> PackedFloat32Array:
	return ragdoll.pose_snapshot() if ragdoll != null else PackedFloat32Array()

func ragdoll_settled() -> bool:
	return ragdoll != null and ragdoll.is_settled()

func sync_ragdoll(pose: PackedFloat32Array, impact := Vector3.ZERO, hit_at := Vector3.INF, hit_bone: StringName = &"", fall_launch := Vector3.INF) -> void:
	if brain.state not in [WastelandCreatureBrain.State.DEAD, WastelandCreatureBrain.State.KNOCKDOWN]:
		if ragdoll != null:
			_start_rise(global_position)
		return
	if ragdoll == null:
		foot_contacts.clear()
		ragdoll_start_frame = Engine.get_physics_frames()
		rise_from.clear()
		rise_target.clear()
		ragdoll_impact = impact
		ragdoll_hit_at = hit_at
		ragdoll_hit_bone = hit_bone
		fall.from_fall = fall_launch.is_finite()
		var push := Vector3.ZERO if fall.from_fall else impact
		if active_motion != null:
			ragdoll = active_motion.let_go(push,hit_at,hit_bone)
			active_motion = null
		else:
			ragdoll = PhysicalRagdoll.new()
			add_child(ragdoll)
			if session is WastelandSession:
				ragdoll.set_water_source(session.stream)
			if not ragdoll.begin(skeleton,push,hit_at,hit_bone):
				_clear_ragdoll()
				return
			if cloth_motion:
				ragdoll.physics_pose_written.connect(cloth_motion.tick)
		fall.last = ragdoll.center()
		fall.peak = fall.last.y
		if fall.from_fall:
			fall.launch_velocity = fall_launch
			ragdoll.set_motion(fall_launch)
		hurt = 0.0
		visible_hurt = 0.0
		for paint in render_colors.values():
			paint.set_shader_parameter("hurt", 0.0)
	collision_layer = 4 if brain.animal and hp > 0.0 else 0
	collision_mask = 0
	hurtboxes.enable(hp > 0.0)
	if brain.state == WastelandCreatureBrain.State.DEAD and not corpse_hits_enabled:
		RagdollHits.enable(ragdoll,true,"creature",spawn_serial)
		corpse_hits_enabled = true
	if not pose.is_empty():
		ragdoll.apply_pose(pose)
	_update_downed_hitboxes()

func mirror_limb_hit(serial: int, impulse: Vector3, hit_at: Vector3, hit_bone: StringName) -> void:
	if serial <= limb_hit_serial:
		return
	limb_hit_serial = serial
	ragdoll_impact = impulse
	ragdoll_hit_at = hit_at
	ragdoll_hit_bone = hit_bone
	# The transition to passive physics already applied this snapshot's strike.
	if ragdoll != null:
		if ragdoll_start_frame != Engine.get_physics_frames():
			ragdoll.kick_at(impulse,hit_at,hit_bone)
	elif active_motion != null:
		active_motion.kick_at(impulse,hit_at,hit_bone)

func record_limb_hit(impulse: Vector3, hit_at: Vector3, hit_bone: StringName) -> void:
	limb_hit_serial += 1
	ragdoll_impact = impulse
	ragdoll_hit_at = hit_at
	ragdoll_hit_bone = hit_bone

func _update_downed_hitboxes() -> void:
	if hp <= 0.0 or ragdoll == null:
		return
	if brain.animal:
		# Observing wildlife still uses the body capsule. Weapons trace the individual bones.
		collider.global_position = ragdoll.center()
		var trunk := skeleton.get_bone_global_pose(0)
		collider.global_basis = (skeleton.global_basis * trunk.basis).orthonormalized() * Basis(Vector3.RIGHT, PI * 0.5)
	hurtboxes.pose(self)

func _stop_active_motion() -> void:
	if active_motion != null:
		active_motion.stop_driving()
		active_motion = null

func _ensure_active_motion() -> void:
	if active_motion or ragdoll or motion_preview or get_parent()!=director or not session is WastelandSession: return
	if not session.stream.at_surface(global_position): return
	active_motion = ActiveMotion.start(self,skeleton,session.stream)
	if active_motion:
		active_motion.pose_applied.connect(hurtboxes.pose.bind(self))
		if cloth_motion: active_motion.physics_pose_written.connect(cloth_motion.tick)

func _watch_fall(drop: float) -> void:
	fall.passive(ragdoll.center(),drop)
	if not ragdoll.landing_contact.is_connected(_landed): ragdoll.landing_contact.connect(_landed)
	ragdoll.watch_landing(true)

func _deep_water(at: Vector3) -> bool:
	return at.y<=WastelandTerrainGen.WATER_LEVEL+0.06 and session.stream.water_at(at) and session.stream.ground_at(at)<WastelandTerrainGen.WATER_LEVEL-maxf(0.80,capsule.height*0.56)

func _open_water_landing(at: Vector3, movement: Vector3) -> bool:
	var height := at.y-WastelandTerrainGen.WATER_LEVEL
	if height<=0.0: return _deep_water(at)
	var seconds := (movement.y+sqrt(movement.y*movement.y+36.0*height))/18.0
	var entry := at+Vector3(movement.x,0,movement.z)*seconds
	entry.y = WastelandTerrainGen.WATER_LEVEL
	if not _deep_water(entry): return false
	return brain.route.ray(at,entry+Vector3.UP*0.02,1|2|8).is_empty()

func _landed(_bone: StringName, at: Vector3, _normal: Vector3, closing_speed: float) -> void:
	if not fall.pending or not active or hp<=0.0 or session.replica: return
	fall.pending = false
	ragdoll.watch_landing(false)
	var drop := maxf(0.0,fall.peak-ragdoll.center().y)
	fall.peak = ragdoll.center().y
	var fraction := 0.0 if _deep_water(at) else fall.damage_fraction(drop,closing_speed)
	if fraction>0.0:
		hp = maxf(0.0,hp-max_health()*fraction)
		session.audio.play_at("hit",at,clampf(0.45+fraction,0.45,1.0))
	if hp<=0.0:
		begin_death()
		director.retain_corpse(self)
	else:
		brain.state_left = maxf(brain.state_left,0.60+minf(fraction,1.0)*1.25)

func _follow_fall(delta: float) -> void:
	if session.replica: return
	var point := ragdoll.center()
	if fall.last.is_finite() and fall.last.distance_to(point)>maxf(0.95,ragdoll.motion().length()*delta*2.0+0.35):
		if fall.pending: ragdoll.watch_landing(false)
		fall.reset(point)
	if _deep_water(point):
		if fall.pending: _landed(&"",point,Vector3.UP,0.0)
		fall.last = point
		fall.peak = point.y
		return
	if not fall.pending:
		fall.peak = maxf(fall.peak,point.y)
		if fall.dangerous(fall.peak-point.y,-ragdoll.motion().y,capsule.height):
			_watch_fall(fall.peak-point.y)
	if fall.pending and ragdoll_settled(): _landed(&"",point,Vector3.UP,0.0)
	fall.last = point

func _clear_ragdoll() -> void:
	if ragdoll == null:
		return
	ragdoll.release()
	ragdoll = null
	_restore_capsule()

func _restore_capsule() -> void:
	corpse_hits_enabled = false
	collider.transform = Transform3D(Basis.IDENTITY, Vector3.UP * capsule.height * 0.5)
	if active and hp > 0.0:
		collision_layer = 4 if brain.animal or session.replica else 4 | 128
		collision_mask = 0 if session.replica else 3 | 8 if brain.animal else 3 | 8 | 128
		hurtboxes.enable(true)

func _recover_at() -> Vector3:
	var center := physical_position()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 2 | 8
	query.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	# Try either side if the body came to rest against a wall or below an overhang.
	for offset: Vector3 in [Vector3.ZERO,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var probe := center + offset * (capsule.radius + 0.20)
		var down := brain.route.ray(probe + Vector3.UP * 0.55, probe - Vector3.UP * maxf(capsule.height,1.2), query.collision_mask)
		if down.is_empty() or down.normal.y < cos(floor_max_angle):
			continue
		var foot: Vector3 = down.position + Vector3.UP * (0.035 + capsule.radius * (1.0 / down.normal.y - 1.0))
		query.transform = Transform3D(Basis.IDENTITY,foot + Vector3.UP * capsule.height * 0.5)
		if space.intersect_shape(query,1).is_empty():
			return foot
	if _deep_water(center):
		var foot := Vector3(center.x,maxf(session.stream.ground_at(center)+0.05,WastelandTerrainGen.WATER_LEVEL-0.55),center.z)
		query.transform = Transform3D(Basis.IDENTITY,foot+Vector3.UP*capsule.height*0.5)
		if space.intersect_shape(query,1).is_empty(): return foot
	return Vector3.INF

func _start_rise(foot: Vector3) -> void:
	# Preserve the fallen silhouette when the movement capsule returns to its feet.
	rise_from.clear()
	rise_target.clear()
	for i in skeleton.get_bone_count():
		rise_from.append(skeleton.get_bone_pose(i))
	var pelvis_world := skeleton.global_transform * rise_from[0]
	if ragdoll is ActiveMotion:
		active_motion = ragdoll as ActiveMotion
		ragdoll = null
		active_motion.resume_driving()
		_restore_capsule()
	else:
		_clear_ragdoll()
	global_position = foot
	fall.reset(foot)
	rise_from[0] = skeleton.global_transform.affine_inverse() * pelvis_world
	for i in skeleton.get_bone_count():
		rise_target.append(skeleton.get_bone_pose(i))
		skeleton.set_bone_pose(i,rise_from[i])
	if active_motion: active_motion.capture_targets()
	rise_time = 0.0

func hand_impact_damage(zone: String, origin: Vector3, hit_bone: StringName = &"") -> int:
	if not active or hp <= 0.0:
		return 0
	var plated := zone == "torso" and (hit_bone == &"" or hit_bone in [&"torso",&"hips",&"arm_l",&"arm_r"])
	if (morph == "armored" and plated) or _blocking_shield_pieces(origin) > 0:
		return 4
	return 0

func _blocking_shield_pieces(origin: Vector3) -> int:
	if type != "bulwark" or brain.action != WastelandCreatureBrain.Action.NONE or attack >= 0.1:
		return 0
	var bearing := WastelandCreatureRoute.planar(origin - global_position).normalized()
	if (-global_basis.z).dot(bearing) <= 0.45:
		return 0
	return int(limb_damage.x < 2) + int(limb_damage.y < 2)

func take_hit(amount: float, origin: Vector3, heavy := false, knockdown := false, hit_at := Vector3.INF, hit_bone: StringName = &"") -> void:
	if not active or hp <= 0.0:
		return
	var shield_pieces := _blocking_shield_pieces(origin)
	if shield_pieces > 0:
		amount *= 1.0 - (0.16 if heavy else 0.35) * shield_pieces
		session.audio.play_at("stone",global_position + Vector3.UP,0.68)
	hp -= amount
	hurt = 0.81
	visible_hurt = hurt
	for paint in render_colors.values():
		paint.set_shader_parameter("hurt", hurt)
	alerted = true
	brain.provoke(origin)
	windup = 0.0
	attack_kind = WastelandCreatureBrain.Action.NONE
	if hit_at.is_finite() and hit_bone == &"":
		hit_bone = impact_bone(null,-1,hit_at)
	var dx := (hit_at if hit_at.is_finite() else physical_position()) - origin
	if not hit_at.is_finite():
		dx.y = 0.0
	var push := dx.normalized() * (5.3 if heavy else 2.4) * (0.34 if type == "brute" else 1.0)
	record_limb_hit(push,hit_at,hit_bone)
	var local_push := global_basis.inverse() * dx.normalized()
	impact_tilt = Vector2(local_push.z, -local_push.x) * (0.24 if heavy else 0.14)
	if brain.animal:
		stagger = maxf(stagger, 0.52 if heavy else 0.25)
	else:
		brain.interrupt(false, 0.6 if heavy or type == "feral_runner" else 0.22)
		hit_chain = hit_chain + 1 if hit_chain_left > 0.0 else 1
		hit_chain_left = 1.5
		if hit_chain >= 3:
			brain.try_rage()
			hit_chain = 0
	if ragdoll != null:
		ragdoll.kick_at(push,hit_at,hit_bone)
	else:
		velocity += push
	session.fx.burst(hit_at if hit_at.is_finite() else global_position + Vector3.UP * float(spec.height) * 0.53,
		Color("#8e3f59") if type != "radiant" else Color("#bcba63"), 1.16 if heavy else 0.67)
	if hp <= 0.0:
		if type == "bloater":
			_prime_rupture(float(spec.ai.fuse))
			session.audio.play_at("spit_tell",global_position + Vector3.UP,1.35)
		else:
			director.defeated(self,hit_at,hit_bone)
	else:
		if knockdown or (heavy and amount >= minf(22.0, max_health() * 0.15)):
			brain.interrupt(true, 2.0)
			sync_ragdoll(PackedFloat32Array(),velocity + Vector3.UP * 0.55,hit_at,hit_bone)
		elif active_motion != null:
			active_motion.kick_at(push,hit_at,hit_bone)
		session.audio.play_at("hit", global_position + Vector3.UP * 0.61, 0.56)

func think(delta: float, player: WastelandSurvivor, teammates: Array[WastelandSurvivor] = []) -> void:
	if hit_pause>0:
		var stopped:=minf(hit_pause,delta)
		hit_pause-=stopped
		delta-=stopped
		if delta<=0.0: return
	if not active:
		return
	if brain.state == WastelandCreatureBrain.State.DEAD:
		_fade_hit_flash(delta)
		if cloth_motion and ragdoll_settled(): cloth_motion.tick_resting(delta)
		brain.state_left = maxf(0.0, brain.state_left - delta)
		if brain.state_left <= 0.0:
			director.release(self)
		return
	if fuse_left > 0.0:
		fuse_left = maxf(0.0, fuse_left - delta)
		windup = 1.0 - fuse_left / float(spec.ai.fuse)
		_pose(delta,global_position.distance_to(player.global_position),0.0)
		if fuse_left == 0.0:
			director.rupture(self)
		return
	if ragdoll != null and brain.state == WastelandCreatureBrain.State.KNOCKDOWN:
		_follow_fall(delta)
		if hp<=0.0: return
		if fall.pending and physical_position().y < -34.0 and session.stream.below_terrain(physical_position()):
			director.release(self)
			return
		_fade_hit_flash(delta)
		if cloth_motion and ragdoll_settled(): cloth_motion.tick_resting(delta)
		brain.state_left = maxf(0.0,brain.state_left - delta)
		limp_left = maxf(0.0,limp_left - delta)
		_update_downed_hitboxes()
		if brain.state_left <= 0.0 and not fall.pending:
			var foot := _recover_at()
			if not foot.is_finite():
				brain.state_left = 0.2
				if physical_position().y < -34.0 and session.stream.below_terrain(physical_position()):
					director.release(self)
				return
			_start_rise(foot)
			velocity = Vector3.ZERO
			ground_step = false
			surface_retry = 0.0
			stagger = 0.0
			brain.state = WastelandCreatureBrain.State.WANDER if brain.animal else WastelandCreatureBrain.State.CHASE
			brain.sense_left = 0.0
			brain.route.clear_plan()
			_pose(0.15,global_position.distance_to(player.global_position),0.0)
		return
	stagger = maxf(0.0, stagger - delta)
	limp_left = maxf(0.0, limp_left - delta)
	trap_left = maxf(0.0, trap_left - delta)
	hit_chain_left = maxf(0.0, hit_chain_left - delta)
	attack = maxf(0.0, attack - delta * 2.6)
	var distance := global_position.distance_to(player.global_position)
	for person:WastelandSurvivor in teammates:
		if is_instance_valid(person) and person.health>0.0: distance=minf(distance,global_position.distance_to(person.global_position))
	if distance > 105.0:
		offscreen += delta
	else:
		offscreen = 0.0
	if offscreen > 11.0 or (global_position.y < -34.0 and session.stream.below_terrain(global_position)):
		if offscreen > 11.0 and nest != "" and brain.state == WastelandCreatureBrain.State.SLEEPING:
			director.fresh.append(serialize())
		director.release(self)
		return
	voice_clock -= delta
	var animal := brain.animal
	if voice_clock <= 0.0 and distance < 37.0 and not animal and brain.state not in [WastelandCreatureBrain.State.SLEEPING, WastelandCreatureBrain.State.WAKING] and brain.action == WastelandCreatureBrain.Action.NONE:
		voice_clock = actor_rng.randf_range(6.0, 12.0) if alerted else actor_rng.randf_range(10.0, 19.0)
		session.audio.play_at("growl", global_position + Vector3.UP * float(spec.height) * 0.62, 0.57 if alerted else 0.39)
	var submerged: bool = global_position.y < -0.27 and session.stream.water_at(global_position)
	motion_water = submerged
	var walk := brain.tick(delta, player, teammates, distance)
	if not active:
		return
	windup = brain.windup_progress()
	attack_kind = brain.action
	var move_speed := max_move_speed()
	if low_crawl():
		move_speed *= 0.74 + 0.26*sin(pose_phase*2.0)
	elif limb_damage.z + limb_damage.w > 0:
		var support_side := 1.0 if limb_damage.z >= limb_damage.w else -1.0
		move_speed *= 0.86 + 0.14*sin(pose_phase)*support_side
	move_speed *= brain.speed_factor() * (0.45 if submerged else 1.0)
	var mobile := brain.state not in [WastelandCreatureBrain.State.SLEEPING, WastelandCreatureBrain.State.WAKING, WastelandCreatureBrain.State.STAGGER, WastelandCreatureBrain.State.KNOCKDOWN]
	separation_left -= delta
	if mobile and not animal and separation_left <= 0.0:
		separation_left = 0.095 + 0.01 * posmod(spawn_serial, 4)
		separation_force = director.separation(self)
	var crowd := separation_force if mobile and not animal else Vector3.ZERO
	var drift := (walk + crowd * 1.18).limit_length() * move_speed
	var face := brain.desired_facing if brain.desired_facing != Vector3.ZERO else walk
	_steer(drift, face, delta)
	if active_motion and grounded() and not submerged:
		velocity = active_motion.supported_velocity(velocity)
	if submerged:
		velocity.y = move_toward(velocity.y, (-0.57 - global_position.y) * 3.0, delta * 12.0)
		water_step -= delta
		if water_step < 0.0 and drift.length_squared() > 0.4:
			water_step = 0.57
			session.fx.burst(global_position + Vector3.UP * 0.54, Color("#8ebbc1"), 0.53)
			session.audio.play_at("splash", global_position, 0.44)
	else:
		velocity.y -= delta * 18.0
	var before := global_position
	var next := before + Vector3(velocity.x, 0, velocity.z) * delta
	var loaded: bool = session.stream.at_surface(next)
	var incoming := velocity
	if loaded:
		surface_retry = maxf(0.0, surface_retry - delta)
		if not animal and not submerged and surface_retry <= 0.0:
			var on_structure := not ground_step and is_on_floor() and not brain.route.ray(before + Vector3.UP * 0.16, before - Vector3.UP * 0.14, 2 | 8).is_empty()
			ground_step = not on_structure and _walk_surface(before, next)
			if not ground_step:
				# Keep physics in charge across the toe and face of a low ramp.
				# Projecting a capsule already overlapping a ramp back to the terrain pins its feet.
				surface_retry = 0.32
		else:
			ground_step = false
		if not ground_step:
			move_and_slide()
	if loaded and not submerged and not session.replica:
		if fall.capsule(before,global_position,grounded(),-incoming.y,capsule.height) and not _open_water_landing(global_position,incoming):
			var drop := fall.peak-global_position.y
			brain.interrupt(true,0.65)
			sync_ragdoll(PackedFloat32Array(),incoming,Vector3.INF,&"",incoming)
			if ragdoll:
				_watch_fall(drop)
				return
	else:
		fall.reset(global_position)
		if not loaded:
			ground_step = false
			velocity.y = 0.0
	var travel := global_position - before
	_update_support(delta,distance)
	brain.route.moved(delta, travel, move_speed)
	_pose(delta, distance, Vector2(travel.x,travel.z).length())

func grounded() -> bool:
	return ground_step or is_on_floor()

func _steer(desired: Vector3, face: Vector3, delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z)
	var target := Vector2(desired.x, desired.z)
	var speed := float(spec.speed)
	var heavy := type in ["boar","stag","brute","bloater","bulwark"]
	var response := 0.40 if heavy else 0.27
	var accel := clampf(speed / response, 4.0, 17.0)
	if planar.dot(target - planar) < 0.0:
		accel *= 1.4
	if brain.charge_left > 0.0:
		accel = 20.0
	elif stagger > 0.0:
		accel = 9.0
	elif low_crawl() or type == "crawler":
		accel *= 0.70
	var motion := planar.move_toward(target, accel * delta)
	velocity.x = motion.x
	velocity.z = motion.y
	if face.length_squared() > 0.05:
		var yaw := atan2(-face.x, -face.z)
		var moving := smoothstep(0.15, speed, motion.length())
		var turn_rate := lerpf(5.5, 3.0 if heavy else 4.4, moving)
		rotation.y = rotate_toward(rotation.y, yaw, turn_rate * delta)

func _update_support(delta: float, distance: float) -> void:
	if distance>54.0:
		motion_floor_normal = Vector3.UP
		support_world = Vector3.UP
		support_poll = 0.0
		return
	support_poll -= delta
	if motion_water or not grounded():
		support_world = Vector3.UP
	elif ground_step:
		if support_poll<=0.0:
			support_world = session.stream.ground_normal_at(global_position)
			support_poll = 0.13
	else:
		support_world = get_floor_normal()
	var normal := global_basis.inverse()*support_world
	motion_floor_normal = motion_floor_normal.lerp(normal,1.0-exp(-15.0*delta)).normalized()

func _walk_surface(from: Vector3, next: Vector3) -> bool:
	if velocity.y > 0.05 or velocity.y < -1.1 or brain.charge_left > 0.0:
		return false
	var surface: float = session.stream.ground_at(from)
	var feet := from.y - surface
	if feet < -0.045 or feet > 0.17:
		return false
	var height: float = session.stream.ground_at(next)
	var stride := WastelandCreatureRoute.planar(next - from).length()
	if absf(height - surface) > 0.02 + stride * tan(floor_max_angle):
		return false
	next.y = height + safe_margin
	var motion := next - from
	if motion.length_squared() > 0.000001:
		# The terrain sampler interpolates the same four vertices used by the collider.
		# Cast the full body against structures, cave ceilings, vehicles and other infected.
		ground_cast.transform = Transform3D(Basis.IDENTITY, from + collider.position)
		ground_cast.motion = motion
		var result := get_world_3d().direct_space_state.cast_motion(ground_cast)
		if result.size() != 2 or result[0] < 1.0:
			return false
		global_position = next
	velocity.y = 0.0
	return true

func _prime_rupture(remaining: float) -> void:
	hp = 0.0
	hurtboxes.enable(false)
	fuse_left = clampf(remaining, 0.01, float(spec.ai.fuse))
	velocity = Vector3.ZERO
	collision_layer = 0
	attack_kind = WastelandCreatureBrain.Action.RUPTURE
	windup = 1.0 - fuse_left / float(spec.ai.fuse)
	_show_blast_ring()

func _show_blast_ring() -> void:
	if not is_instance_valid(blast_ring):
		blast_ring = MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.outer_radius = float(spec.ai.blast_radius)
		ring.inner_radius = ring.outer_radius - 0.11
		ring.rings = 40
		ring.ring_segments = 4
		blast_ring.mesh = ring
		blast_ring.material_override = WastelandLook.matte(Color("#ff914d"),0.82)
		blast_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(blast_ring)
		blast_ring.position.y = 0.09
	blast_ring.show()

func stride_length(speed: float) -> float:
	if type == "crawler" or low_crawl():
		return lerpf(0.62,0.96,smoothstep(0.2,1.8,speed))
	return lerpf(1.18,2.30,smoothstep(0.55,4.15,speed))*clampf(float(spec.height)/1.74,0.65,1.40)

func _pose(delta: float, distance: float, travel := -1.0) -> void:
	if ragdoll != null:
		_fade_hit_flash(delta)
		if cloth_motion and ragdoll_settled(): cloth_motion.tick_resting(delta)
		_update_downed_hitboxes()
		return
	# Preview actors walk in place. World actors supply the distance that physics actually allowed.
	motion_distance += travel if travel >= 0.0 else Vector2(velocity.x,velocity.z).length()*delta
	phase_clock += delta
	var tick := 0.15 if distance > 54.0 else 0.075 if distance > 27.0 else 0.031
	if phase_clock < tick:
		return
	var span := phase_clock
	phase_clock = 0.0
	var drive := not motion_preview and get_parent() == director and session is WastelandSession
	if active_motion != null:
		if drive:
			active_motion.restore_targets()
		else:
			_stop_active_motion()
	for i in rise_target.size():
		skeleton.set_bone_pose(i,rise_target[i])
	_fade_hit_flash(span)
	rig.rotation = Vector3(impact_tilt.x, 0.0, impact_tilt.y) * (hurt / 0.81)
	var grounded_pose: bool = grounded() or (session is WastelandSession and session.replica and absf(velocity.y) < 0.70)
	var supporting: bool = travel >= 0.0 and not motion_preview and distance <= 27.0 and grounded_pose and not motion_water and rise_from.is_empty() and motion_rest <= 0.01
	if supporting:
		foot_contacts.enabled = true
		foot_contacts.recovery_foot = -1
		if active_motion != null and active_motion.balance != null:
			foot_contacts.recovery_foot = active_motion.balance.stepping_foot
		# When pivoting in place the feet travel around the hips. A blocked
		# character with unchanged facing still stops its gait completely.
		var pivot := absf(angle_difference(motion_yaw, rotation.y)) * capsule.radius
		motion_distance = maxf(motion_distance, pivot)
	elif foot_contacts.enabled:
		foot_contacts.clear()
	var measured_speed := motion_distance/span
	var blend := 1.0-exp(-15.0*span)
	motion_speed = lerpf(motion_speed,measured_speed,blend)
	motion_turn = lerpf(motion_turn,clampf(angle_difference(motion_yaw,rotation.y)/span,-6.0,6.0),blend)
	motion_yaw = rotation.y
	motion_clock += span
	pose_phase += motion_distance*TAU/stride_length(measured_speed)
	motion_distance = 0.0
	var speed := motion_speed
	var amplitude := minf(0.61, speed * 0.21)
	var brace := smoothstep(0.0, 0.82, windup)
	if is_instance_valid(gland):
		var power := windup if attack_kind in [WastelandCreatureBrain.Action.SPIT,WastelandCreatureBrain.Action.RUPTURE,WastelandCreatureBrain.Action.MEND] else 0.0
		var pulse := power * (0.90 + 0.10 * sin(pose_phase * 6.0))
		if type == "spitter":
			gland.scale = gland_size * (Vector3.ONE + Vector3(0.55,0.55,0.65) * pulse)
		elif type == "bloater":
			gland.scale = gland_size * (Vector3.ONE + Vector3(0.25,0.25,0.55) * pulse)
		else:
			gland.scale = gland_size * (1.0 + power * (0.70 + 0.20 * sin(pose_phase * 6.0)))
	if spec.get("animal", false):
		if not motion_preview and director!=null and not session.replica:
			_wildlife_track(distance)
		_animal_pose(speed, brace, span)
	elif type=="crawler":
		var stride := sin(pose_phase)*amplitude
		rig.position = Vector3(0,-0.042+sin(motion_clock*2.1)*0.004-absf(stride)*0.018,0)
		_pose_bone("hips",Vector3(stride*0.11,-stride*0.13,stride*0.17))
		_pose_bone("torso",Vector3(-attack*0.22+brace*0.30,stride*0.24,stride*0.11))
		_pose_bone("head",Vector3(-attack*0.24+sin(motion_clock*2.1)*0.035,stride*0.16+motion_turn*0.035,0.06))
	else:
		var stride := sin(pose_phase) * amplitude
		var weight := 0.14 if morph=="armored" else -0.09 if morph=="swift" else 0.0
		rig.position.y = -absf(stride) * (0.045 + weight*0.10)
		_pose_bone("hips",Vector3(weight - absf(stride)*0.06, -stride*0.16, stride*0.09))
		# Arms hang along -Y in their rest pose. A positive X rotation swings them toward -Z.
		var raised := 0.36 if alerted else 0.07
		_pose_bone("arm_l",Vector3(raised - stride*0.42 + attack*0.72 - brace*0.45,0,-0.11-brace*0.29))
		_pose_bone("arm_r",Vector3(raised + stride*0.42 + attack*0.91 - brace*0.62,0,0.11+brace*0.24))
		_pose_bone("elbow_l",Vector3(0.18 + maxf(stride,0.0)*0.30 + brace*0.31 - attack*0.09,0.06,-0.05))
		_pose_bone("elbow_r",Vector3(0.27 + maxf(-stride,0.0)*0.36 + brace*0.38 - attack*0.14,-0.08,0.04))
		var hunch := -0.19 if type=="walker" else -0.25 if type=="radiant" else -0.10 if type=="brute" else -0.07
		var list := 0.075 if type=="walker" else -0.095 if type=="screamer" else 0.0
		_pose_bone("torso",Vector3(hunch*(1.0-attack)-stagger*0.45+attack*0.24-brace*0.16+sin(motion_clock*2.2)*0.016, stride*0.25+brace*0.31+motion_turn*0.025,list*(1.0-attack)+stride*0.13))
		_pose_bone("head",Vector3(sin(motion_clock*0.95)*0.07,sin(motion_clock*1.3)*0.12+motion_turn*0.052,float(clampi(spec.variant,0,5)-2)*0.039))
		if type=="brute":
			var left := limb_damage.y > 0 and limb_damage.x == 0
			var arm := "l" if left else "r"
			var side := -1.0 if left else 1.0
			_pose_bone("arm_"+arm,Vector3(0.48 + attack*0.87 + brace*1.65,stride*0.18*side,(0.24 + attack*0.12 + brace*0.20)*side))
			_pose_bone("elbow_"+arm,Vector3(0.40 - attack*0.22 + brace*0.72,-0.12*side,0.06*side))
			var wrist := skeleton.find_bone("hand_"+arm)
			var flex := Basis(Vector3.RIGHT, -brace * 0.45 - attack * 0.16)
			var grip := flex * skeleton.get_bone_rest(wrist).basis
			skeleton.set_bone_pose_rotation(wrist, grip.get_rotation_quaternion())
		elif type=="spitter":
			_pose_bone("torso",Vector3(-0.14-brace*0.36+attack*0.36,0.08,stride*0.07))
			_pose_bone("head",Vector3(0.14+brace*0.52-attack*0.60,0.0,stride*0.07))
			_pose_bone("arm_l",Vector3(0.36 + brace*0.52,0,-0.30))
		elif type=="bloater" and attack_kind == WastelandCreatureBrain.Action.RUPTURE:
			_show_blast_ring()
			_pose_bone("hips",Vector3(-0.64*brace,0,0))
			_pose_bone("torso",Vector3(0.38*brace,0,0))
			_pose_bone("arm_l",Vector3(0.18,0,-0.35-brace))
			_pose_bone("arm_r",Vector3(0.18,0,0.35+brace))
		elif type=="bloater" and attack_kind == WastelandCreatureBrain.Action.NONE:
			_pose_bone("torso",Vector3(-0.19-stagger*0.45,0.10+stride*0.16,-0.12+stride*0.05),1.0-attack)
			_pose_bone("arm_l",Vector3(0.38-stride*0.20,0.18,-0.30),1.0-attack)
			_pose_bone("elbow_l",Vector3(0.84,0.25,0.20),1.0-attack)
		elif type=="bulwark":
			var shoulder := 0.90 - brace*0.75 + attack*0.34
			var fold := 0.40 - brace*1.04 - attack*0.51
			_pose_bone("arm_l",Vector3(shoulder,0,fold))
			_pose_bone("arm_r",Vector3(shoulder,0,-fold))
		elif type=="rimecaller" and attack_kind == WastelandCreatureBrain.Action.MEND:
			_pose_bone("arm_l",Vector3(0.80+brace*1.3,0,-0.52))
			_pose_bone("arm_r",Vector3(0.80+brace*1.3,0,0.52))
		elif type=="rimecaller" and attack_kind == WastelandCreatureBrain.Action.NONE:
			_pose_bone("head",Vector3(-0.12+sin(motion_clock*0.95)*0.06,0.18+sin(motion_clock*1.3)*0.10,-0.22))
		elif type=="sandrunner" and attack_kind == WastelandCreatureBrain.Action.CHARGE:
			_pose_bone("torso",Vector3(-0.15-brace*0.52,0,0))
			_pose_bone("arm_l",Vector3(-0.30*brace,0,-0.26-brace*0.58))
			_pose_bone("arm_r",Vector3(-0.30*brace,0,0.26+brace*0.58))
		elif type=="sandrunner" and attack_kind == WastelandCreatureBrain.Action.NONE:
			rig.position.y -= amplitude*0.08
			_pose_bone("torso",Vector3(-0.36-amplitude*0.18-stagger*0.45,stride*0.30,0.09+stride*0.10),1.0-attack)
			_pose_bone("head",Vector3(0.19+sin(motion_clock*0.95)*0.06,-0.16+stride*0.15,-0.12),1.0-attack)
			_pose_bone("elbow_l",Vector3(0.95+stride*0.25,-0.12,-0.18),1.0-attack)
			_pose_bone("elbow_r",Vector3(0.42-stride*0.23,0.06,0.11),1.0-attack)
		elif type=="screamer":
			var inhale := brace if attack_kind == WastelandCreatureBrain.Action.SCREAM else 0.0
			_pose_bone("head",Vector3(attack*0.43+inhale*0.68,sin(motion_clock*1.2)*0.17,-0.15))
			_pose_bone("arm_l",Vector3(0.29 + attack*0.87 + inhale*0.98,0.04,-0.26-inhale*0.27))
			if inhale > 0.0:
				_pose_bone("arm_r",Vector3(0.29 + inhale*0.98,-0.04,0.26+inhale*0.27))

	if not spec.get("animal",false):
		if attack_kind != WastelandCreatureBrain.Action.NONE:
			motion_action = attack_kind
		# Wrists have a rotated rest basis, particularly the hammer grip.
		if type!="brute" or limb_damage.y == 0 or limb_damage.x > 0:
			_wrist("hand_l",Vector3(-brace*0.34+attack*0.28+hurt*0.21,0,-0.15))
		if type!="brute":
			_wrist("hand_r",Vector3(-brace*0.52+attack*0.37-hurt*0.28,attack*0.26,0.11))
		if type=="radiant":
			_pose_bone("head",Vector3(0.13+brace*0.22-attack*0.32,0.13*sin(motion_clock*1.35),-0.16))
			_pose_bone("arm_l",Vector3(0.51+brace*0.77+attack*0.49,brace*0.38,-0.24))
		elif type=="walker":
			_pose_bone("head",Vector3(-0.11-brace*0.12+attack*0.29,0.19*sin(motion_clock*1.1)-brace*0.31+motion_turn*0.05,0.12))
		InfectedLimbs.pose(self, amplitude)
		InfectedMotion.special(self)
		InfectedMotion.melee(self)
		if hurt>0.0:
			var neck := skeleton.find_bone("head")
			var recoil := Quaternion.from_euler(Vector3(-hurt*0.21,impact_tilt.y*hurt*1.8,impact_tilt.x*hurt))
			skeleton.set_bone_pose_rotation(neck,skeleton.get_bone_pose_rotation(neck)*recoil)
		InfectedMotion.support(self)
		_posture(span)

	if not rise_from.is_empty():
		rise_time += span
		var weight := smoothstep(0.0,0.38,rise_time)
		for i in rise_from.size():
			rise_target[i] = skeleton.get_bone_pose(i)
			skeleton.set_bone_pose(i,rise_from[i].interpolate_with(rise_target[i],weight))
		if weight >= 1.0:
			rise_from.clear()
			rise_target.clear()
	if drive:
		if active_motion == null:
			_ensure_active_motion()
		else:
			active_motion.capture_targets()
		if active_motion != null:
			active_motion.balance.support_enabled = grounded_pose and not motion_water and motion_rest <= 0.01
	if cloth_motion and active_motion == null:
		cloth_motion.tick(span,distance)
	hurtboxes.pose(self)

func _fade_hit_flash(delta: float) -> void:
	if hurt == 0.0 and visible_hurt == 0.0: return
	hurt = maxf(0.0,hurt-delta*4.4)
	if absf(visible_hurt-hurt) > 0.02 or hurt == 0.0:
		visible_hurt = hurt
		for paint in render_colors.values():
			paint.set_shader_parameter("hurt",hurt)

func _posture(span := 0.0) -> void:
	var tilt := 0.0
	match brain.state:
		WastelandCreatureBrain.State.SLEEPING: tilt = 1.0
		WastelandCreatureBrain.State.WAKING: tilt = smoothstep(0.0, 1.0, brain.state_left / brain.wake_span)
		WastelandCreatureBrain.State.DEAD: tilt = maxf(motion_rest,smoothstep(0.0, 0.48, 3.0 - brain.state_left))
		WastelandCreatureBrain.State.KNOCKDOWN: tilt = smoothstep(0.0, 0.23, 2.0 - brain.state_left) * smoothstep(0.0, 0.7, brain.state_left)
		WastelandCreatureBrain.State.STAGGER: rig.rotation.x += sin(clampf(brain.state_left / 0.6, 0.0, 1.0) * PI) * 0.29
	if brain.state != WastelandCreatureBrain.State.DEAD and tilt < motion_rest and span > 0.0:
		tilt = maxf(tilt,motion_rest-span*2.5)
	motion_rest = tilt
	if tilt > 0.0:
		InfectedMotion.grounded_pose(self,tilt)
	if type == "screamer" and (attack_kind == WastelandCreatureBrain.Action.SCREAM or (screamed and attack > 0.05)):
		if not is_instance_valid(scream_ring):
			scream_ring = MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.outer_radius = 1.0
			ring.inner_radius = 0.96
			ring.rings = 40
			ring.ring_segments = 4
			scream_ring.mesh = ring
			scream_ring.material_override = WastelandLook.matte(Color("#e3bdcc"), 0.72)
			scream_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(scream_ring)
		scream_ring.visible = true
		scream_ring.position.y = body_height() * 0.62
		scream_ring.scale = Vector3.ONE * (0.3 + 3.1 * (windup if attack_kind == WastelandCreatureBrain.Action.SCREAM else 1.0 - attack))
	elif is_instance_valid(scream_ring):
		scream_ring.hide()

func _wrist(label: String, angles: Vector3) -> void:
	var i := skeleton.find_bone(label)
	if i>=0:
		skeleton.set_bone_pose_rotation(i,(Basis.from_euler(angles)*skeleton.get_bone_rest(i).basis).get_rotation_quaternion())

func _animal_pose(speed: float, brace: float, span: float) -> void:
	wildlife_motion.pose(self, speed, brace, span)

func _wildlife_track(distance: float) -> void:
	var traveled := Vector2(global_position.x-print_position.x,global_position.z-print_position.z)
	print_position = global_position
	if distance > 43.0 or traveled.length_squared() > 4.0:
		print_distance = 0.0
		return
	print_distance += traveled.length()
	if print_distance < (0.66 if type=="boar" else 0.86):
		return
	print_distance = 0.0
	_stamp_ground(Vector3(traveled.x,0,traveled.y))

func forage_sign()->void:
	if director and session and not session.replica: _stamp_ground(-global_basis.z)

func _stamp_ground(forward:Vector3)->void:
	var touch := global_position + global_basis.x * print_side * 0.14
	print_side = -print_side
	if session.stream.water_at(touch):
		return
	var ray := PhysicsRayQueryParameters3D.create(touch+Vector3.UP*0.35,touch+Vector3.DOWN*0.35,1|2|8)
	var surface := get_world_3d().direct_space_state.intersect_ray(ray)
	if surface.is_empty() or surface.collider.get_meta("kind","") != "terrain" or surface.normal.y < 0.69:
		return
	var tracks := director.get_node_or_null("Hoofprints") as Hoofprints
	if tracks == null:
		tracks = Hoofprints.new()
		tracks.name = "Hoofprints"
		director.add_child(tracks)
	tracks.stamp(surface.position,surface.normal,forward,type=="boar",self)

func _pose_bone(label: String, angles: Vector3, weight := 1.0) -> void:
	var index := skeleton.find_bone(label)
	if index >= 0:
		var rotation_target := Quaternion.from_euler(angles)
		if weight < 1.0:
			rotation_target = skeleton.get_bone_pose_rotation(index).slerp(rotation_target, weight)
		skeleton.set_bone_pose_rotation(index, rotation_target)
