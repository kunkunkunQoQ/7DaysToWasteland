extends "res://game/ui/model_study.gd"

const S := preload("res://game/ui/style.gd")
const Landscape := preload("res://game/ui/atlas_landscape.gd")
const DEFAULT_PITCH := PI / 6.0

var bounds := AABB()
var yaw := 0.0
var pitch := DEFAULT_PITCH
var orbiting := false
var finger := -1
var plan_button: Button

func _ready() -> void:
	super._ready()
	name = "TerrainView"
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = "拖动旋转地形"
	camera.environment.background_color = Color("#21312f")
	camera.environment.ambient_light_color = Color("#d0ddd7")
	key.rotation_degrees = Vector3(-40, 82, 0)
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.shadow_opacity = 0.64
	# The compatibility renderer lights vertex colors in sRGB; leave headroom on snow.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		key.light_energy = 0.48
		rim.light_energy = 0.24
		camera.environment.ambient_light_energy = 0.25
	resized.connect(_frame_sample)
	gui_input.connect(_orbit_input)

func show_sample(generator: WastelandTerrainGen, site: Dictionary) -> void:
	yaw = site.get("yaw", deg_to_rad(145.0))
	bounds = Landscape.build(self, generator, site.center, site.span)
	_frame_sample()

func add_controls(parent: Control, span: float, climate: String) -> void:
	var bar := S.line(parent)
	bar.add_child(S.label("取样范围  %d × %d 米" % [roundi(span), roundi(span)], 16, S.MUTED))
	if not climate.is_empty():
		bar.add_child(S.label(climate, 16, S.MINT))
	S.fill(bar)
	bar.add_child(S.button("左转", _turn.bind(-PI / 6.0)))
	bar.add_child(S.button("右转", _turn.bind(PI / 6.0)))
	plan_button = S.button("俯视", _toggle_plan)
	bar.add_child(plan_button)

func _toggle_plan() -> void:
	pitch = DEFAULT_PITCH if is_equal_approx(pitch, PI / 2.0) else PI / 2.0
	_frame_sample()

func _turn(angle: float) -> void:
	yaw = wrapf(yaw + angle, -PI, PI)
	_frame_sample()

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and finger < 0:
			finger = event.index
		elif event.index == finger:
			finger = -1
		accept_event()
	elif event is InputEventScreenDrag and event.index == finger:
		_drag(event.relative)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		orbiting = event.pressed and not event.canceled
		accept_event()
	elif event is InputEventMouseMotion and orbiting and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag(event.relative)
		else:
			orbiting = false

func _drag(delta: Vector2) -> void:
	yaw = wrapf(yaw - delta.x * 0.008, -PI, PI)
	pitch = clampf(pitch + delta.y * 0.006, deg_to_rad(14.0), PI / 2.0)
	_frame_sample()
	accept_event()

func _frame_sample() -> void:
	if not bounds.has_volume() or size.x < 1.0 or size.y < 1.0:
		return
	camera.rotation = Vector3(-pitch, yaw, 0.0)
	var axes := camera.basis
	var diameter := bounds.size.length()
	camera.position = bounds.get_center() + axes.z * diameter * 1.15
	camera.far = diameter * 2.0
	key.directional_shadow_max_distance = camera.far
	var width := axes.x.abs().dot(bounds.size)
	var height := axes.y.abs().dot(bounds.size)
	camera.size = maxf(height, width * size.y / size.x) * 1.06
	if is_instance_valid(plan_button):
		plan_button.text = "斜视" if is_equal_approx(pitch, PI / 2.0) else "俯视"
	scene.render_target_update_mode = SubViewport.UPDATE_ONCE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		finger = -1
		orbiting = false
