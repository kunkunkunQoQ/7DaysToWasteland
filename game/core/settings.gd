class_name WastelandSettings
extends RefCounted

const PATH := "user://options.cfg"
const PLAYER_NAME_LIMIT := 12
const DEFAULT_PLAYER_NAME := "幸存者"
const ACTIONS := {
	"up": ["向前", KEY_W], "down": ["向后", KEY_S],
	"left": ["向左", KEY_A], "right": ["向右", KEY_D],
	"jump": ["跳跃／上浮", KEY_SPACE], "sprint": ["冲刺", KEY_SHIFT],
	"crouch": ["蹲伏／下潜", KEY_CTRL], "use": ["交互", KEY_E],
	"fire": ["主动作", MOUSE_BUTTON_LEFT], "alternate": ["副动作", MOUSE_BUTTON_RIGHT],
	"reload": ["装填", KEY_R], "inventory": ["背包", KEY_TAB],
	"map": ["地图", KEY_M], "journal": ["任务", KEY_J], "chat": ["聊天", KEY_ENTER],
	"shape": ["切换建造形状", KEY_Q], "rotate": ["旋转方块", KEY_T],
	"pause_game": ["暂停／返回", KEY_ESCAPE], "flashlight": ["开关提灯", KEY_L],
	"swap_hands": ["主副手互换", KEY_F], "offhand_use": ["使用副手／持盾", KEY_V],
	"discard": ["丢弃所选物品", KEY_G], "slot_next": ["下个快捷栏", MOUSE_BUTTON_WHEEL_DOWN],
	"slot_prev": ["上个快捷栏", MOUSE_BUTTON_WHEEL_UP],
	"slot_1": ["快捷栏 1", KEY_1], "slot_2": ["快捷栏 2", KEY_2],
	"slot_3": ["快捷栏 3", KEY_3], "slot_4": ["快捷栏 4", KEY_4],
	"slot_5": ["快捷栏 5", KEY_5], "slot_6": ["快捷栏 6", KEY_6],
	"slot_7": ["快捷栏 7", KEY_7], "slot_8": ["快捷栏 8", KEY_8],
}
const MOUSE_ACTIONS := ["fire", "alternate", "slot_prev", "slot_next"]
const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A, "use": JOY_BUTTON_X, "crouch": JOY_BUTTON_B,
	"reload": JOY_BUTTON_Y, "sprint": JOY_BUTTON_LEFT_STICK,
	"flashlight": JOY_BUTTON_RIGHT_STICK, "inventory": JOY_BUTTON_BACK,
	"pause_game": JOY_BUTTON_START, "map": JOY_BUTTON_DPAD_UP,
	"journal": JOY_BUTTON_DPAD_DOWN, "shape": JOY_BUTTON_DPAD_LEFT,
	"rotate": JOY_BUTTON_DPAD_RIGHT, "slot_prev": JOY_BUTTON_LEFT_SHOULDER,
	"slot_next": JOY_BUTTON_RIGHT_SHOULDER,
}
const PAD_AXIS := {
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "alternate": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
const BUS := ["Master", "Effects", "Ambience", "Music"]
const BUS_LABEL := ["主音量", "音效", "环境", "音乐"]

var display := {"pixel_height": 510, "dynamic": true, "fps": 60, "radius": 4, "full": false, "show_fps": false,
	"sensitivity": 0.003, "invert_y": false, "auto_step": true, "ui_softness": 0.47, "impact_motion": 0.75}
var volumes := [0.84, 0.85, 0.62, 0.37]
var bindings: Dictionary = {}
var april_faces := false
var appearance := "ranger"
var player_name := DEFAULT_PLAYER_NAME
var favorite_recipes := PackedStringArray()
var touch_left_handed := false
var touch_control_scale := 1.0
var storage_path := PATH

static func clean_player_name(raw: String) -> String:
	var clean := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159) or (code >= 0x200B and code <= 0x200F) or (code >= 0x2028 and code <= 0x202E) or (code >= 0x2060 and code <= 0x206F) or code == 0xFEFF:
			continue
		clean += raw[index]
	clean = clean.replace("　"," ").strip_edges().left(PLAYER_NAME_LIMIT).strip_edges()
	return DEFAULT_PLAYER_NAME if clean.is_empty() else clean

func load_options(android_defaults := OS.has_feature("android")) -> void:
	if android_defaults:
		display.merge({"pixel_height":340,"fps":30,"radius":2,"ui_softness":0.0,"full":true},true)
	var file := ConfigFile.new()
	file.load(storage_path)
	april_faces = bool(file.get_value("appearance","april_faces",false))
	appearance = str(file.get_value("appearance","outfit","ranger"))
	player_name = clean_player_name(str(file.get_value("multiplayer","player_name",DEFAULT_PLAYER_NAME)))
	touch_left_handed = bool(file.get_value("touch","left_handed",false))
	touch_control_scale = clampf(float(file.get_value("touch","control_scale",1.0)),0.85,1.15)
	var saved_recipes = file.get_value("crafting","favorites",PackedStringArray())
	favorite_recipes = saved_recipes if saved_recipes is PackedStringArray else PackedStringArray()
	if not WastelandPartyAvatar.OUTFITS.has(appearance): appearance = "ranger"
	preload("res://game/art/april_face.gd").set_enabled(april_faces)
	for key in display:
		display[key] = file.get_value("display", key, display[key])
	for index in BUS.size():
		volumes[index] = clampf(float(file.get_value("audio", BUS[index], volumes[index])), 0.0, 1.0)
	for id in ACTIONS:
		var default := Vector2i(int(id in MOUSE_ACTIONS), int(ACTIONS[id][1]))
		var mapping = file.get_value("input", id, default)
		bindings[id] = mapping if mapping is Vector2i and mapping.y > 0 else default
	# Preserve custom bindings when adding the two new actions to a previous profile.
	if not file.has_section_key("input","swap_hands"):
		var taken := {}
		for action in bindings:
			if action not in ["swap_hands","offhand_use"]: taken[bindings[action]]=true
		if bindings.flashlight==Vector2i(0,KEY_F) and not taken.has(Vector2i(0,KEY_L)):
			bindings.flashlight=Vector2i(0,KEY_L)
			taken.erase(Vector2i(0,KEY_F))
			taken[bindings.flashlight]=true
		for action in ["swap_hands","offhand_use"]:
			var code: Vector2i=bindings[action]
			while taken.has(code): code.y+=1
			bindings[action]=code
			taken[code]=true
	for id in ACTIONS:
		_apply_binding(id)
	apply_audio()

func save_options() -> void:
	var file := ConfigFile.new()
	file.set_value("appearance","april_faces",april_faces)
	file.set_value("appearance","outfit",appearance)
	file.set_value("multiplayer","player_name",player_name)
	file.set_value("crafting","favorites",favorite_recipes)
	file.set_value("touch","left_handed",touch_left_handed)
	file.set_value("touch","control_scale",touch_control_scale)
	for key in display:
		file.set_value("display", key, display[key])
	for index in BUS.size():
		file.set_value("audio", BUS[index], volumes[index])
	for id in bindings:
		file.set_value("input", id, bindings[id])
	file.save(storage_path)

func apply_audio() -> void:
	for index in BUS.size():
		var bus_index := AudioServer.get_bus_index(BUS[index])
		if bus_index < 0:
			AudioServer.add_bus()
			bus_index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus_index, BUS[index])
			AudioServer.set_bus_send(bus_index, "Master")
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(0.0001, volumes[index])))
		AudioServer.set_bus_mute(bus_index, volumes[index] <= 0.0)

func apply_display() -> void:
	if not OS.has_feature("android"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if display.full else DisplayServer.WINDOW_MODE_WINDOWED)
	Engine.max_fps = int(display.fps)

func reset_bindings() -> void:
	for id in ACTIONS:
		bindings[id] = Vector2i(int(id in MOUSE_ACTIONS), int(ACTIONS[id][1]))
		_apply_binding(id)
	save_options()

func rebind(id: String, event: InputEvent) -> bool:
	var binding := Vector2i.ZERO
	if event is InputEventKey:
		binding.y = event.physical_keycode
	elif event is InputEventMouseButton:
		binding = Vector2i(1, event.button_index)
	if binding.y == 0:
		return false
	var previous: Vector2i = bindings[id]
	for other in bindings:
		if other != id and bindings[other] == binding:
			bindings[other] = previous
			_apply_binding(other)
	bindings[id] = binding
	_apply_binding(id)
	save_options()
	return true

func _apply_binding(id: String) -> void:
	if not InputMap.has_action(id):
		InputMap.add_action(id, 0.22)
	InputMap.action_erase_events(id)
	var binding: Vector2i = bindings[id]
	if binding.x == 1:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = binding.y
		InputMap.action_add_event(id, mouse)
	else:
		var key := InputEventKey.new()
		key.physical_keycode = binding.y
		InputMap.action_add_event(id, key)
	if PAD_BUTTONS.has(id):
		var joy := InputEventJoypadButton.new()
		joy.device = -1
		joy.button_index = PAD_BUTTONS[id]
		InputMap.action_add_event(id, joy)
	if PAD_AXIS.has(id):
		var axis := InputEventJoypadMotion.new()
		axis.device = -1
		axis.axis = PAD_AXIS[id][0]
		axis.axis_value = PAD_AXIS[id][1]
		InputMap.action_add_event(id, axis)

func action_name(id: String) -> String:
	const Touch := preload("res://game/ui/touch_layout.gd")
	return Touch.action_caption(id) if Touch.active else binding_name(id)

func binding_name(id: String) -> String:
	var binding: Vector2i = bindings.get(id, Vector2i.ZERO)
	if binding.x == 0:
		var name := OS.get_keycode_string(binding.y)
		return {"Space": "空格", "Escape": "Esc", "Control": "Ctrl"}.get(name, name)
	return {
		MOUSE_BUTTON_LEFT: "左键", MOUSE_BUTTON_RIGHT: "右键",
		MOUSE_BUTTON_MIDDLE: "中键", MOUSE_BUTTON_WHEEL_UP: "滚轮↑",
		MOUSE_BUTTON_WHEEL_DOWN: "滚轮↓",
	}.get(binding.y, "鼠标%d" % binding.y)
