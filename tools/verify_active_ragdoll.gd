extends SceneTree

const Motion := preload("res://game/actors/active_ragdoll.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ",description)
	if not ok: failures += 1

func body_box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var surface := StaticBody3D.new()
	parent.add_child(surface)
	surface.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	surface.add_child(shape)
	return surface

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	body_box(world,Vector3.DOWN * 0.1,Vector3(20,0.2,20))
	var avatar := WastelandPartyAvatar.new()
	avatar.show_tag = false
	world.add_child(avatar)
	var rig := Motion.start(avatar,avatar,null,true)
	if not rig:
		check(false,"live driver starts")
		quit(1)
		return
	var hips := rig.body_for(&"hips")
	var hand := rig.body_for(&"hand_r")
	var baseline := hips.position
	var rest_hand := hand.position
	for i in 65:
		await physics_frame
		rig.restore_targets()
		avatar.pose(1.0/60,0.0,0.0)
		rig.capture_targets()
	check(hips.position.distance_to(baseline) < 0.15 and hand.position.distance_to(rest_hand) < 0.23,
		"motors support pelvis and hand against gravity")
	var before := hand.position
	rig.kick_at(Vector3.RIGHT * 7.0,hand.position,&"hand_r")
	var excursion := 0.0
	for i in 60:
		await physics_frame
		excursion = maxf(excursion,hand.position.distance_to(before))
	check(excursion > 0.015 and hand.position.distance_to(before) < excursion * 0.7,
		"localized impulse deflects the live wrist, then the muscles recover")
	var left_leg := rig.body_for(&"leg_l")
	var right_leg := rig.body_for(&"leg_r")
	var stride_gap := 0.0
	for i in 90:
		await physics_frame
		avatar.position.z -= 3.4/60.0
		rig.restore_targets()
		avatar.pose(1.0/60,3.4,0.0)
		rig.capture_targets()
		stride_gap = maxf(stride_gap,absf(left_leg.position.z - right_leg.position.z))
	check(absf(hips.position.z-avatar.position.z) < 0.35 and stride_gap > 0.055,
		"walking pelvis follows the route and physical legs alternate")
	var wall := body_box(world,Vector3(0.38,1.1,avatar.position.z),Vector3(0.12,2.2,3.0))
	for i in 40:
		await physics_frame
		avatar.position.x += 0.008
		rig.restore_targets()
		avatar.pose(1.0/60,0.0,0.0)
		rig.capture_targets()
	check(hand.position.x < wall.position.x-0.02,
		"wall contact stops the wrist even while its animation target moves through the wall")
	var hand_rid := hand.get_rid()
	var hand_pose := hand.global_transform
	var passive := rig.let_go(Vector3.ZERO) as Motion
	check(passive == rig and not passive.driving and hand.get_rid() == hand_rid and hand.global_transform.is_equal_approx(hand_pose),
		"fall releases the motors on the same bodies without a pose jump")
	for i in 85: await physics_frame
	check(hips.position.y < baseline.y - 0.30,"unpowered pelvis falls onto the floor")
	world.queue_free()
	await process_frame
	print("ACTIVE RAGDOLL failures=",failures)
	quit(int(failures > 0))
