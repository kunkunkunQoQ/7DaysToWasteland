extends Node3D
## Markers and readouts consume only the public character snapshot.

const State := preload("../state/physics_character_state.gd")
const SUPPORT_LABELS := ["无", "左脚", "右脚", "双脚"]

@onready var _com: MeshInstance3D = $CenterOfMass
@onready var _feet: MeshInstance3D = $FootPoint
@onready var _timing: Label = %Timing
@onready var _contact: Label = %Contact
@onready var _measurements: Label = %Measurements

var _until_readout := 0.0

func sync_state(state: State) -> void:
	_com.global_position = state.center_of_mass
	_feet.global_position = state.foot_position
	_com.show()
	_feet.show()
	if state.step_seconds <= 0.0:
		return
	_until_readout -= state.step_seconds
	if _until_readout > 0.0:
		return
	_until_readout = 0.1
	_timing.text = "%d Hz   ·   固定步长 %.2f ms   ·   #%d" % [
		roundi(1.0 / state.step_seconds), state.step_seconds * 1000.0, state.tick_index]
	var ground_text := "身体接地" if state.body_grounded else "身体离地"
	var fall_text := "已跌倒" if state.fallen else "未跌倒"
	_contact.text = "%s   ·   支撑脚 %s   ·   %s" % [
		ground_text, SUPPORT_LABELS[state.support_feet], fall_text]
	_measurements.text = "\n".join(PackedStringArray([
		"重心  %s m" % _xyz(state.center_of_mass),
		"脚点  %s m" % _xyz(state.foot_position),
		"骨盆  %s m" % _xyz(state.pelvis_position),
		"眼点  %s m" % _xyz(state.eye_position),
		"质心速度  %s m/s" % _xyz(state.linear_velocity),
		"骨盆角速度  %s rad/s" % _xyz(state.angular_velocity),
	]))

func _xyz(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
