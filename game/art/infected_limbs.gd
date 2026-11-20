extends RefCounted

# Four ternary digits, ordered left arm, right arm, left leg, right leg.
const COUNT := 81
const LimbArt := preload("res://game/art/infected_limb_art.gd")

static func roll(world_seed: int, serial: int) -> int:
	var result := 0
	var place := 1
	for digit in 4:
		var ticket := posmod(hash(Vector4i(world_seed, serial, digit, 0x4c494d42)), 100)
		result += (2 if ticket < 6 else 1 if ticket < 15 else 0) * place
		place *= 3
	return result

@warning_ignore("integer_division")
static func decode(index: int) -> Vector4i:
	return Vector4i(index % 3, index / 3 % 3, index / 9 % 3, index / 27 % 3)

static func fit(actor: Node3D) -> void:
	if actor.limb_index == 0:
		return
	var limbs: Vector4i = actor.limb_damage
	if actor.type == "brute" and limbs.y > 0 and limbs.x == 0:
		var grip: Marker3D = actor.body_parts.hand_r.get_node("HammerGrip")
		grip.reparent(actor.body_parts.hand_l, false)
		grip.rotation.z *= -1.0
		var palm: MeshInstance3D = actor.body_parts.hand_l.get_node("HandMesh")
		palm.mesh = WastelandBestiary.hand_mesh(-1, true)
		var wrist: int = actor.skeleton.find_bone("hand_l")
		var rest: Transform3D = actor.skeleton.get_bone_rest(wrist)
		rest.basis *= Basis(Vector3.FORWARD, 0.96)
		actor.skeleton.set_bone_rest(wrist, rest)
	for i in 4:
		var severity := limbs[i]
		if severity == 0:
			continue
		var right := i % 2
		var suffix := "_r" if right else "_l"
		if i < 2:
			actor.body_parts["hand"+suffix].hide()
			if severity == 1:
				continue
		else:
			actor.body_parts["ankle"+suffix].hide()
		var joint := "elbow" if i < 2 else "knee"
		var attachment: BoneAttachment3D = actor.body_parts[joint+suffix]
		for old: Node3D in attachment.get_children():
			old.hide()
		var piece := MeshInstance3D.new()
		piece.name = "ShortenedLimb"
		var form := (3 if i < 2 else 5 if severity == 1 else 7) + right
		piece.mesh = LimbArt.remnant(actor, form, 1 if right else -1)
		piece.material_override = actor._toon_material(Color.WHITE)
		attachment.add_child(piece)
	if limbs.z + limbs.w > 0:
		var scale_y := 0.48 if actor.low_crawl() else 1.0 - 0.055 * (limbs.z + limbs.w)
		if actor.type == "crawler":
			scale_y = 0.80 if actor.low_crawl() else 0.97
		actor.capsule.height = maxf(actor.capsule.radius * 2.0, actor.capsule.height * scale_y)

static func pose(actor: Node3D, amplitude: float) -> void:
	if actor.limb_index == 0:
		return
	var limbs: Vector4i = actor.limb_damage
	var wave := sin(float(actor.pose_phase))
	var support := clampf(amplitude / 0.61, 0.0, 1.0)
	if actor.low_crawl():
		# Roll the former standing skeleton onto its belly. Its hips, shins and feet
		# now extend behind the chest, and the surviving arms pull from the floor.
		if actor.type != "crawler":
			actor.rig.rotation.x -= 1.29
			actor.rig.position = Vector3(0,-0.022+0.012*wave*support,0.92*actor.rig.scale.z)
			actor._pose_bone("torso", Vector3(-0.04,-wave*support*0.10,0))
			actor._pose_bone("head", Vector3(0.92+actor.attack*0.17,0.10*wave,0))
		for i in 2:
			var side := 1.0 if i else -1.0
			var suffix := "_r" if i else "_l"
			actor._pose_bone("leg"+suffix,Vector3(-0.10+side*wave*support*0.08,0,side*0.13))
			actor._pose_bone("knee"+suffix,Vector3(-0.31+side*wave*support*0.12,0,0))
		if limbs.x + limbs.y == 4:
			actor.rig.rotation.z += sin(float(actor.pose_phase)*0.5)*0.15*support
	elif limbs.z + limbs.w > 0:
		var injured_side := signi(limbs.w-limbs.z)
		var limp := 0.5+0.5*wave*(injured_side if injured_side else 1)
		actor.rig.rotation.z += (0.075+support*limp*0.095)*injured_side
		actor.rig.position.y += 0.004 - 0.008*limp*support
		for i in 2:
			if limbs[2+i] == 0:
				continue
			var side := 1.0 if i else -1.0
			var suffix := "_r" if i else "_l"
			actor._pose_bone("leg"+suffix,Vector3(0.15*limbs[2+i]+side*wave*amplitude*0.38,0,side*0.09))
			actor._pose_bone("knee"+suffix,Vector3(-0.29*limbs[2+i]-limp*amplitude*0.26,0,0))
	if limbs.x + limbs.y == 0:
		return
	if actor.biting() and (actor.attack_kind == WastelandCreatureBrain.Action.MELEE or actor.attack > 0):
		actor._pose_bone("head",Vector3((0.85 if actor.low_crawl() and actor.type != "crawler" else 0.0)-actor.attack*0.64+actor.windup*0.28,0,0.07))
	for i in 2:
		if limbs[i] == 0:
			continue
		var side := 1.0 if i else -1.0
		var suffix := "_r" if i else "_l"
		if not actor.low_crawl() and actor.attack_kind in [WastelandCreatureBrain.Action.NONE, WastelandCreatureBrain.Action.MELEE, WastelandCreatureBrain.Action.SMASH]:
			actor._pose_bone("arm"+suffix,Vector3(0.18+side*wave*amplitude*0.26,0,side*0.19))
			actor._pose_bone("elbow"+suffix,Vector3(0.45+0.18*limbs[i],0,0))
