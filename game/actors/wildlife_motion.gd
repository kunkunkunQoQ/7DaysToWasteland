extends RefCounted

# Travel during stance in leg lengths, top cadence (Hz), running duty factor,
# and height of the suspended body in leg lengths.
const GAITS := {
	"stag": Vector4(1.13, 3.3, 0.34, 0.12),
	"argali": Vector4(1.01, 3.6, 0.37, 0.18),
	"boar": Vector4(0.89, 3.8, 0.44, 0.045),
	"fox": Vector4(1.16, 4.0, 0.32, 0.15),
	"wolf": Vector4(1.23, 3.45, 0.37, 0.09),
	"hare": Vector4(1.34, 4.2, 0.22, 0.78),
	"jerboa": Vector4(1.38, 4.5, 0.20, 1.10),
	"badger": Vector4(0.91, 4.1, 0.42, 0.035),
	"otter": Vector4(1.12, 3.9, 0.34, 0.12),
}

class Limb:
	var upper: int
	var knee: int
	var hock: int
	var paw: int
	var socket: Vector3
	var thigh: Vector3
	var shin: Vector3
	var heel: Vector3
	var rest_paw: Vector3
	var thigh_length: float
	var shin_length: float
	var thigh_angle: float
	var shin_angle: float

var limbs: Array[Limb] = []
var forage := 0.0
var swim := 0.0
var torso_id := -1
var torso_rest := Vector3.ZERO
var leg_length := 0.0
var profile := Vector4.ZERO

func reset(actor: Node3D) -> void:
	forage = 0.0
	swim = 0.0
	var skeleton: Skeleton3D = actor.skeleton
	torso_id = skeleton.find_bone("torso")
	torso_rest = skeleton.get_bone_rest(torso_id).origin
	profile = GAITS[actor.type]
	limbs.clear()
	for i in 4:
		var limb := Limb.new()
		limb.upper = skeleton.find_bone("leg%d" % i)
		limb.knee = skeleton.find_bone("ankle%d" % i)
		limb.hock = skeleton.find_bone("hock%d" % i)
		limb.paw = skeleton.find_bone("paw%d" % i)
		limb.socket = skeleton.get_bone_rest(limb.upper).origin
		limb.thigh = skeleton.get_bone_rest(limb.knee).origin
		limb.shin = skeleton.get_bone_rest(limb.hock).origin
		limb.heel = skeleton.get_bone_rest(limb.paw).origin
		limb.rest_paw = torso_rest + limb.socket + limb.thigh + limb.shin + limb.heel
		limb.thigh_length = limb.thigh.length()
		limb.shin_length = limb.shin.length()
		limb.thigh_angle = atan2(-limb.thigh.z,-limb.thigh.y)
		limb.shin_angle = atan2(-limb.shin.z,-limb.shin.y)
		limbs.append(limb)
	leg_length = torso_rest.y + limbs[0].socket.y - limbs[0].rest_paw.y

func pose(actor: Node3D, speed: float, brace: float, delta: float) -> void:
	if limbs.is_empty():
		reset(actor)
	var kind: String = actor.type
	var clock: float = actor.motion_clock
	var turn := clampf(float(actor.motion_turn) * 0.25, -1.0, 1.0)
	var springer := kind in ["hare","jerboa"]
	var motion := smoothstep(0.03, minf(0.88, leg_length * 1.9), speed)
	var ratio := speed / float(actor.spec.speed)
	var run := smoothstep(0.33, 0.90, ratio)
	var gather := smoothstep(0.49 if kind == "wolf" else 0.34, 0.93, ratio)
	if springer:
		gather = motion
	elif kind == "badger":
		gather *= 0.32
	var travel := leg_length * lerpf(0.60, profile.x, run) * motion
	var duty := lerpf(0.66, profile.z, run)
	var scale_z: float = actor.rig.scale.z
	# Short-legged animals spend less of a fast stride in contact. This keeps
	# the stance velocity equal to travel speed without cycling their feet at 12 Hz.
	var frequency := 0.0
	if motion > 0.0:
		frequency = minf(profile.y, speed * duty / maxf(0.025, travel * scale_z))
		duty = clampf(frequency * travel * scale_z / speed, 0.065, duty)
	var stride_cycle := fposmod(float(actor.wildlife_cycle) + delta * frequency, 1.0)
	actor.wildlife_cycle = stride_cycle
	var phase := stride_cycle * TAU
	var wave := sin(phase)
	var breath := sin(clock * (3.7 if springer else 2.35) + float(actor.spawn_serial) * 0.71)
	var foraging: bool = actor.brain.forage_left > 0.0 and not actor.alerted
	forage = move_toward(forage, float(foraging), delta * (2.1 if foraging else 4.4))
	swim = move_toward(swim, float(kind == "otter" and actor.motion_water), delta * 3.4)
	var launch := sin(PI * clampf((stride_cycle - duty) / maxf(0.08, 0.71 - duty), 0.0, 1.0))
	var crouch := sin(PI * clampf(stride_cycle / duty, 0.0, 1.0))
	var suspension := launch * gather
	var bob := (-0.045 - 0.035 * cos(phase * 2.0)) * motion
	bob += (suspension * profile.w - crouch * 0.09 * gather) * (1.0 - swim)
	var pitch := (0.105 if springer else 0.051) * sin(phase - 0.76) * gather
	var roll := wave * motion * (0.074 if kind == "badger" else 0.025) + turn * motion * 0.095
	var yaw := wave * motion * (0.10 if kind in ["badger","otter"] else 0.033)
	if kind == "jerboa":
		pitch += 0.19 + 0.14 * suspension
	if kind == "boar":
		pitch += -brace * 0.16 + float(actor.attack) * 0.19
		bob -= brace * 0.11
	pitch += float(actor.stagger) * 0.14
	pitch = lerpf(pitch, 0.10 * sin(phase - 0.4), swim)
	# Transform the contact plane into skeleton space. The young and local
	# rigs have nonuniform scale, so directions and plane normals differ here.
	var support: Vector3 = actor.motion_floor_normal
	if support.y < 0.55 or actor.motion_water:
		support = Vector3.UP
	var floor_normal: Vector3 = (actor.rig.basis.transposed() * support).normalized()
	var tangent := Vector2(floor_normal.x, floor_normal.z) / maxf(0.55, floor_normal.y)
	var follow := (1.0 - swim) * (1.0 - suspension * 0.38)
	pitch += atan(tangent.y) * 0.84 * follow
	roll -= atan(tangent.x) * 0.62 * follow
	var torso_basis := Basis.from_euler(Vector3(pitch, yaw, roll))
	var torso_at := torso_rest + Vector3(0, leg_length * (bob + breath * 0.009 - swim * 0.25), 0)
	var skeleton: Skeleton3D = actor.skeleton
	skeleton.set_bone_pose_position(torso_id, torso_at)
	skeleton.set_bone_pose_rotation(torso_id, torso_basis.get_rotation_quaternion())
	var inverse := torso_basis.transposed()
	var slope_rotation := Quaternion(Vector3.UP, floor_normal)
	for i in 4:
		var rear := i < 2
		var right := i % 2 == 0
		var lead := 0.0 if right else 0.5
		var walk_offset := lead + (0.0 if rear else -0.23)
		var trot_offset := lead + (0.0 if rear else -0.50)
		var run_offset := (0.0 if rear else -0.54) + (0.0 if right else -0.085)
		if springer:
			run_offset = (0.0 if rear else -0.63) + (0.0 if right else -0.035)
		# Unwrap the left legs toward their next strike as the animal changes
		# from a diagonal trot to a gallop.
		if not right:
			run_offset += 1.0
		var offset := lerpf(walk_offset,trot_offset,smoothstep(0.18,0.54,ratio))
		var beat := fposmod(stride_cycle + lerpf(offset, run_offset, gather), 1.0)
		var stance := beat < duty
		var swing := clampf((beat - duty) / (1.0 - duty), 0.0, 1.0)
		var height := sin(PI * swing)
		height *= height
		var step := beat / duty - 0.5 if stance else 0.5 - smoothstep(0.0, 1.0, swing)
		var limb := limbs[i]
		var target := limb.rest_paw
		target.z += step * travel * (1.0 + turn * 0.14 * signf(limb.socket.x))
		target.y += leg_length * height * motion * (0.20 + gather * (0.58 if springer else 0.19))
		target.y += leg_length * suspension * profile.w * height
		var foot_support := (1.0 - height * 0.84) * (1.0 - swim)
		var floor_y := -tangent.dot(Vector2(target.x, target.z))
		target.y += (floor_y + limb.rest_paw.y * (1.0 / floor_normal.y - 1.0)) * (1.0 - swim)
		var curl := height * motion
		var foot_pitch := curl * (0.42 if rear else -0.34) - 0.13 * motion * sin(TAU * swing)
		if kind == "jerboa" and not rear:
			target = limb.rest_paw + Vector3(0, leg_length * (0.13 + 0.09 * suspension), leg_length * 0.15 * wave * motion)
			foot_pitch = 0.36 + wave * 0.12 * motion
			foot_support = 0.0
		if swim > 0.0:
			var offset_angle := PI if rear == right else 0.0
			var stroke := Vector2.from_angle(clock * 3.2 + offset_angle) * 0.55
			stroke = stroke.lerp(Vector2.from_angle(phase + offset_angle), motion)
			target = target.lerp(limb.rest_paw + leg_length * Vector3(stroke.y * signf(limb.socket.x) * 0.18, 0.24 + 0.15 * stroke.x, 0.51 * stroke.y), swim)
			foot_pitch = lerpf(foot_pitch, 0.55 * stroke.x, swim)
		var heel_pitch := (curl * (0.80 if springer else 0.52) if rear else -curl * 0.23) - pitch
		var ground := Basis(Quaternion.IDENTITY.slerp(slope_rotation, foot_support))
		_place(skeleton, limb, inverse * (target - torso_at) - limb.socket, heel_pitch, inverse * ground * Basis(Vector3.RIGHT, foot_pitch), rear)
	_head_and_tail(actor, clock, phase, motion, turn, pitch, roll, breath, brace)

func _place(skeleton: Skeleton3D, limb: Limb, target: Vector3, heel_pitch: float, paw_basis: Basis, rear: bool) -> void:
	var bank := Basis(Vector3.BACK, atan2(target.x, -target.y))
	var hock := bank.transposed() * target - limb.heel.rotated(Vector3.RIGHT, heel_pitch)
	var distance := clampf(Vector2(hock.y,hock.z).length(), absf(limb.thigh_length - limb.shin_length) + 0.0001, limb.thigh_length + limb.shin_length - 0.0001)
	var cosine := (limb.thigh_length ** 2 + distance ** 2 - limb.shin_length ** 2) / (2.0 * distance * limb.thigh_length)
	var aim := atan2(-hock.z, -hock.y)
	var thigh_angle := aim + (1.0 if rear else -1.0) * acos(clampf(cosine, -1.0, 1.0))
	var upper_pitch := thigh_angle - limb.thigh_angle
	var endpoint := Vector3(0, -cos(aim), -sin(aim)) * distance
	var shin := endpoint - limb.thigh.rotated(Vector3.RIGHT, upper_pitch)
	var shin_pitch := atan2(-shin.z,-shin.y) - limb.shin_angle
	skeleton.set_bone_pose_rotation(limb.upper, (bank * Basis(Vector3.RIGHT,upper_pitch)).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(limb.knee, Quaternion(Vector3.RIGHT, shin_pitch - upper_pitch))
	skeleton.set_bone_pose_rotation(limb.hock, Quaternion(Vector3.RIGHT, heel_pitch - shin_pitch))
	var heel_basis := bank * Basis(Vector3.RIGHT,heel_pitch)
	skeleton.set_bone_pose_rotation(limb.paw, (heel_basis.transposed() * paw_basis).get_rotation_quaternion())

func _head_and_tail(actor: Node3D, clock: float, phase: float, motion: float, turn: float, pitch: float, roll: float, breath: float, brace: float) -> void:
	var kind: String = actor.type
	var alert := float(actor.alerted)
	var idle := (1.0 - motion) * (1.0 - forage)
	var sniff := sin(clock * (8.0 if kind in ["boar","badger","otter"] else 4.6))
	var browse := (0.87 if kind in ["stag","argali"] else 0.52) * forage
	var head_pitch := -browse + sniff * forage * 0.10 + alert * 0.14 - pitch * 0.65 + breath * 0.025
	var look := turn * 0.32 + sin(clock * 0.84) * idle * (0.24 + alert * 0.13) + forage * sin(clock * 1.67) * 0.19
	if kind in ["boar","wolf"]:
		head_pitch += -brace * 0.45 + float(actor.attack) * 0.34
	actor._pose_bone("neck", Vector3(head_pitch * 0.54, look * 0.46, -roll * 0.34))
	actor._pose_bone("head", Vector3(head_pitch * 0.46, look * 0.54, -roll * 0.39))
	for side: float in [-1, 1]:
		var listen := pow(maxf(0.0, cos(clock * 1.56 + side * 1.73)), 14.0)
		var sweep := motion * (0.49 if kind in ["hare","jerboa"] else 0.16)
		actor._pose_bone("ear_r" if side > 0 else "ear_l", Vector3(sweep + motion * sin(phase - 0.7) * 0.095 - alert * 0.12, side * (listen * 0.48 + idle * 0.09) - look * 0.37, side * listen * 0.15))
	var balancing := 0.44 if kind in ["fox","jerboa","otter"] else 0.21
	actor._pose_bone("tail", Vector3(-pitch * 0.9 - alert * 0.12 + swim * sin(phase) * 0.24, -turn * 0.33 + motion * balancing * sin(phase - 0.35), 0))
	if kind != "hare":
		actor._pose_bone("tail_tip", Vector3(motion * 0.16 * sin(phase - 1.2) + 0.06 * breath, -turn * 0.23 + balancing * (motion * sin(phase - 1.35) + idle * 0.37 * sin(clock * 1.5)), 0))
