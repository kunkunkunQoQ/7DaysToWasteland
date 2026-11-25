class_name WastelandSurvivorRagdoll
extends Node3D

const PhysicsRagdoll := preload("res://game/actors/physical_ragdoll.gd")
const CORPSE_SECONDS := PhysicsRagdoll.CORPSE_SECONDS

var physics := PhysicsRagdoll.new()
var avatar := WastelandPartyAvatar.new()
var appearance := {}
var remaining := -1.0
var outside_stream := false
var resume_on_load := false

static func spawn(world: Node3D, pose: Transform3D, outfit: String, gear: Dictionary, held: String,
		offhand: String, loaded: bool, crouch: float, swimming: bool, velocity: Vector3,
		impact: Vector3, at := Vector3.INF, bone: StringName = &"",
		source: WastelandPartyAvatar = null) -> WastelandSurvivorRagdoll:
	var body := new()
	body.appearance = {"at": pose, "profile": outfit, "gear": gear.duplicate(), "held": held,
		"offhand": offhand, "loaded": loaded, "crouch": crouch, "swim": swimming, "velocity": velocity,
		"impact_at": at, "impact_bone": bone}
	world.add_child(body)
	body.global_transform = pose
	body.set_physics_process(false)
	body.avatar.show_tag = false
	body.avatar.apply_outfit(outfit)
	body.avatar.wear_loadout(gear)
	body.avatar.set_mainhand(held, loaded)
	body.avatar.set_offhand(offhand, false, false)
	body.add_child(body.avatar)
	body.avatar.pose(0.0, Vector2(velocity.x, velocity.z).length(), crouch, swimming)
	body.add_child(body.physics)
	var donor = source.active_motion if is_instance_valid(source) else null
	if is_instance_valid(donor) and donor.center().distance_squared_to(body.avatar.to_global(Vector3.UP * 0.85)) > 2.25:
		# An authoritative teleport can happen before the active rig receives its next motor targets.
		donor = null
	if not body.physics.begin(body.avatar, Vector3.ZERO if is_instance_valid(donor) else impact, at, bone):
		body.queue_free()
		return null
	if world is WastelandSession: body.physics.set_water_source(world.stream)
	if is_instance_valid(donor):
		body.physics.inherit_motion(donor)
		body.push(impact, at, bone)
	return body

func center() -> Vector3:
	return physics.center()

func push(impact: Vector3, at := Vector3.INF, bone: StringName = &"") -> void:
	appearance.impact_at = at
	appearance.impact_bone = bone
	if at.is_finite() or bone != &"": physics.kick_at(impact, at, bone)
	elif not impact.is_zero_approx(): physics.kick(impact)

func become_corpse() -> void:
	if remaining >= 0.0: return
	remaining = CORPSE_SECONDS
	preload("res://game/actors/ragdoll_hits.gd").enable(physics, true, "survivor", get_instance_id())
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		dismiss()
		return
	var world := get_parent() as WastelandSession
	if world == null: return
	var unloaded := not world.stream.at_surface(center())
	if unloaded == outside_stream: return
	outside_stream = unloaded
	if unloaded:
		resume_on_load = not world.replica or not physics.is_settled()
		physics.settle()
	elif resume_on_load:
		physics.kick(Vector3.ZERO)

func dismiss() -> void:
	if is_queued_for_deletion(): return
	hide()
	if physics.is_inside_tree(): physics.release()
	queue_free()
