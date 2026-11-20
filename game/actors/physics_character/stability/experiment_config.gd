extends RefCounted
## Single-factor tests use baseline, or the explicitly named parent in the report.

const Config := preload("../config/physics_character_config.gd")
const RoundedPalms := preload("../config/rounded_palms.gd")
const PASSIVE_CONTACT := preload("../config/passive_contact.tres")
const RoundedFeet := preload("../config/rounded_feet.gd")
const ROUNDED_FEET_60 := preload("../config/rounded_feet60.tres")
const ROUNDED_FEET_120 := preload("../config/rounded_feet120.tres")
const PROFILES := [
	"baseline", "iterations32", "iterations64", "priority2", "priority4", "mass", "inertia",
	"capsule_tensor", "damping", "bias15", "bias35", "friction", "visc4", "visc8", "visc16",
	"erp20", "axial", "body_drag3", "tensor_iter32", "tensor_iter64", "palms", "slop2mm",
	"persistence12mm", "rolling5mm", "rolling15mm", "speculative", "palms_iter32",
	"palms_iter64", "palms_rolling", "hip_adduction", "articulated", "articulated_palms",
	"spec_no_ccd", "coupled_no_ccd", "contact_iter32", "contact_iter48", "contact_iter64",
	"contact_spec", "contact_visc8", "contact_damping", "contact_bias35", "contact_slop",
	"contact_persistence", "contact_drag", "contact_friction",
	"contact_roll18", "contact_roll22", "contact_roll25", "contact_roll30",
	"contact_load10", "contact_load30", "contact_load60", "contact_load100",
	"contact_bearing015", "contact_bearing035", "contact_bearing070", "contact_bearing140",
	"rounded_feet60", "rounded_feet120", "foot_bearing015", "foot_bearing035", "foot_bearing070", "foot_bearing140",
	"contact_stop10", "contact_stop30", "contact_stop90", "contact_stop180",
	"foot_stop10", "foot_stop30", "foot_stop90", "foot_stop180",
	"shoulder_stop45", "shoulder_stop90", "shoulder_stop150",
	"bearing35", "bearing38", "bearing40", "bearing42", "bearing45", "bearing50",
	"bearing40_iter32", "bearing40_iter48", "bearing40_iter64",
	"contact_slow1", "contact_slow2", "contact_slow4", "contact_slow8",
	"ankle_stop30", "ankle_stop180", "ankle_stop300",
	"bearing40_drag05", "bearing40_drag2", "bearing40_drag4", "bearing40_iter12", "bearing40_iter24",
	"bearing40_iter14", "bearing40_iter18", "bearing40_iter20",
]

class AnkleStops extends RoundedPalms:
	var torque_nm := 30.0

	func build_joints() -> Array[Dictionary]:
		var rows := super.build_joints()
		for row: Dictionary in rows:
			if row.child in [&"foot_l", &"foot_r"]:
				row.limit_torque_nm = torque_nm
		return rows

class ShoulderStops extends RoundedFeet:
	var torque_nm := 90.0

	func build_joints() -> Array[Dictionary]:
		var rows := super.build_joints()
		for row: Dictionary in rows:
			if row.child in [&"upper_arm_l", &"upper_arm_r"]:
				row.limit_torque_nm = torque_nm
		return rows

class HipEnvelope extends Config:
	func build_joints() -> Array[Dictionary]:
		var rows := super.build_joints()
		for row: Dictionary in rows:
			if row.child not in [&"thigh_l", &"thigh_r"]:
				continue
			var high := Vector3(row.twist, row.swing, row.swing)
			var low := -high
			if row.child == &"thigh_l":
				low.z = deg_to_rad(-20.0)
			else:
				high.z = deg_to_rad(20.0)
			row.lower_angles = low
			row.upper_angles = high
		return rows

class MassPropertiesExperiment extends Config:
	var variation: String

	func build_segments() -> Array[Dictionary]:
		var rows := super.build_segments()
		for row: Dictionary in rows:
			var size: Vector3 = row.size
			var squared := size * size
			# In 4.6.3 GodotPhysics uses the enclosing box for capsule inertia;
			# all shapes here are centered, single and axis-aligned in body space.
			var nominal := Vector3(squared.y + squared.z, squared.x + squared.z, squared.x + squared.y) * (float(row.mass) / 12.0)
			if variation == "mass":
				# Keep the original tensor, collider and total mass when moving
				# 0.25 kg from the chest to each foot and each forearm.
				if row.id == &"chest":
					row.mass -= 1.0
					row.inertia = nominal
				elif row.id in [&"foot_l", &"foot_r", &"lower_arm_l", &"lower_arm_r"]:
					row.mass += 0.25
					row.inertia = nominal
			elif variation == "inertia":
				row.inertia = nominal * 1.25
			elif row.shape == &"capsule":
				var r := size.x * 0.5
				var h := size.y - 2.0 * r
				var sphere_mass := float(row.mass) * (4.0 * r / 3.0) / (h + 4.0 * r / 3.0)
				var cylinder_mass := float(row.mass) - sphere_mass
				var transverse := cylinder_mass * (3.0*r*r + h*h) / 12.0 + sphere_mass * (0.4*r*r + 0.25*h*h + 0.375*h*r)
				var axial := r*r * (0.5*cylinder_mass + 0.4*sphere_mass)
				row.inertia = Vector3(transverse, axial, transverse)
		return rows

static func create(profile: String) -> Config:
	if profile.begins_with("ankle_stop"):
		var ankle := AnkleStops.new()
		ankle.torque_nm = profile.trim_prefix("ankle_stop").to_float()
		ankle.multi_axis_limit_torque_nm = 90.0
		ankle.rolling_resistance_m = 0.015
		return ankle
	if profile.begins_with("shoulder_stop"):
		var shoulder := ShoulderStops.new()
		shoulder.torque_nm = profile.trim_prefix("shoulder_stop").to_float()
		shoulder.rolling_resistance_m = 0.015
		shoulder.dry_joint_friction_nm = 1.40
		return shoulder
	if profile == "hip_adduction":
		return HipEnvelope.new()
	if profile in ["mass", "inertia", "capsule_tensor", "tensor_iter32", "tensor_iter64"]:
		var experiment := MassPropertiesExperiment.new()
		experiment.variation = profile
		return experiment
	var config := Config.new()
	if profile == "rounded_feet60":
		config = ROUNDED_FEET_60.duplicate() as Config
	elif profile == "rounded_feet120":
		config = ROUNDED_FEET_120.duplicate() as Config
	elif profile.begins_with("foot_") or profile.begins_with("bearing"):
		config = RoundedFeet.new()
		config.rolling_resistance_m = 0.015
		if profile.begins_with("foot_stop"):
			config.dry_joint_friction_nm = 1.40
		if profile.begins_with("bearing"):
			config.dry_joint_friction_nm = 1.40
			config.bearing_reference_radius_m = profile.trim_prefix("bearing").get_slice("_", 0).to_float() * 0.001
	elif profile == "palms_rolling" or profile.begins_with("contact_"):
		config = PASSIVE_CONTACT.duplicate() as Config
	elif profile.begins_with("palms") or profile == "articulated_palms":
		config = RoundedPalms.new()
	match profile:
		"bearing40_drag05": config.passive_joint_drag = 0.50
		"bearing40_drag2": config.passive_joint_drag = 2.0
		"bearing40_drag4": config.passive_joint_drag = 4.0
		"contact_slow1", "contact_slow2", "contact_slow4", "contact_slow8":
			config.low_speed_extra_lever_m = 0.015
			config.rolling_transition_rad_s = profile.trim_prefix("contact_slow").to_float()
		"priority2": config.joint_solver_priority = 2
		"priority4": config.joint_solver_priority = 4
		"damping", "contact_damping": config.multi_axis_limit_damping = 0.70
		"bias15": config.shape_contact_bias = 0.15
		"bias35", "contact_bias35": config.shape_contact_bias = 0.35
		"friction", "contact_friction": config.surface_friction = 0.50
		"visc4": config.passive_joint_drag = 4.0
		"visc8", "contact_visc8": config.passive_joint_drag = 8.0
		"visc16": config.passive_joint_drag = 16.0
		"erp20": config.angular_limit_erp = 0.20
		"axial": config.use_multi_axis_hinges = true
		"body_drag3", "contact_drag": config.angular_damping = 3.0
		"rolling5mm": config.rolling_resistance_m = 0.005
		"rolling15mm": config.rolling_resistance_m = 0.015
		"contact_roll18": config.rolling_resistance_m = 0.018
		"contact_roll22": config.rolling_resistance_m = 0.022
		"contact_roll25": config.rolling_resistance_m = 0.025
		"contact_roll30": config.rolling_resistance_m = 0.030
		"contact_load10": config.contact_load_time_s = 0.010
		"contact_load30": config.contact_load_time_s = 0.030
		"contact_load60": config.contact_load_time_s = 0.060
		"contact_load100": config.contact_load_time_s = 0.100
		"contact_bearing015", "foot_bearing015": config.dry_joint_friction_nm = 0.15
		"contact_bearing035", "foot_bearing035": config.dry_joint_friction_nm = 0.35
		"contact_bearing070", "foot_bearing070": config.dry_joint_friction_nm = 0.70
		"contact_bearing140", "foot_bearing140": config.dry_joint_friction_nm = 1.40
		"contact_stop10", "foot_stop10": config.multi_axis_limit_torque_nm = 10.0
		"contact_stop30", "foot_stop30": config.multi_axis_limit_torque_nm = 30.0
		"contact_stop90", "foot_stop90": config.multi_axis_limit_torque_nm = 90.0
		"contact_stop180", "foot_stop180": config.multi_axis_limit_torque_nm = 180.0
		"speculative", "contact_spec": config.predict_contacts = true
		"articulated", "articulated_palms":
			config.predict_contacts = true
			config.articulated_contact_response = true
		"spec_no_ccd", "coupled_no_ccd":
			config.predict_contacts = true
			config.articulated_contact_response = profile == "coupled_no_ccd"
			config.continuous_collision_detection = false
	return config

static func iterations(profile: String) -> int:
	match profile:
		"bearing40_iter12": return 12
		"bearing40_iter14": return 14
		"bearing40_iter18": return 18
		"bearing40_iter20": return 20
		"bearing40_iter24": return 24
		"iterations32", "tensor_iter32", "palms_iter32", "contact_iter32", "bearing40_iter32": return 32
		"contact_iter48", "bearing40_iter48", "rounded_feet120": return 48
		"iterations64", "tensor_iter64", "palms_iter64", "contact_iter64", "bearing40_iter64": return 64
	return -1

## Intended only for a private benchmark world.
static func configure_space(profile: String, space: RID) -> void:
	var count := iterations(profile)
	if count > 0:
		PhysicsServer3D.space_set_param(space, PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS, count)
	if profile in ["slop2mm", "contact_slop"]:
		PhysicsServer3D.space_set_param(space, PhysicsServer3D.SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION, 0.002)
	if profile in ["persistence12mm", "contact_persistence"]:
		PhysicsServer3D.space_set_param(space, PhysicsServer3D.SPACE_PARAM_CONTACT_MAX_SEPARATION, 0.012)
