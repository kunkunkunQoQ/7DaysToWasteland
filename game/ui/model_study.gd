extends SubViewportContainer

var scene := SubViewport.new()
var camera := Camera3D.new()
var portrait_zoom := "半身"
var subject: WastelandPartyAvatar
var creature: WastelandCreature
var movement_time := 0.0
var animate_idle := true
var touch_finger := -1
var pointer_at := Vector2.ZERO
var has_pointer := false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene.own_world_3d = true
	scene.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("android") else Viewport.MSAA_2X
	scene.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	set_process(false)
	set_process_input(false)
	add_child(scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#263830")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#dfdfcf")
	env.ambient_light_energy = 0.56
	camera.environment = env
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(camera)
	var key := DirectionalLight3D.new()
	scene.add_child(key)
	key.rotation_degrees = Vector3(-32,145,0)
	key.light_color = Color("#ffe5c1")
	key.light_energy = 1.08
	var rim := DirectionalLight3D.new()
	scene.add_child(rim)
	rim.rotation_degrees = Vector3(-26,-40,0)
	rim.light_color = Color("#a1d5c6")
	rim.light_energy = 0.47

func preview(id: String, gear: Dictionary = {}, transparent := false) -> WastelandPartyAvatar:
	var avatar := WastelandPartyAvatar.new()
	avatar.show_tag = false
	avatar.outfit = id
	scene.add_child(avatar)
	avatar.wear_loadout(gear)
	scene.transparent_bg = transparent
	frame_survivor(avatar,"全身")
	follow_pointer(avatar)
	return avatar

func follow_pointer(avatar: WastelandPartyAvatar, idle := true) -> void:
	subject = avatar
	animate_idle = idle
	set_process(true)
	set_process_input(true)

func study_creature(actor: WastelandCreature) -> void:
	creature = actor
	creature.motion_preview = true
	creature.motion_yaw = creature.rotation.y
	movement_time = 0.0
	set_process(true)

func _advance_creature(delta: float) -> void:
	movement_time = fmod(movement_time+delta,8.0)
	var pace := smoothstep(0.55,1.45,movement_time)*(1.0-smoothstep(4.4,5.15,movement_time))
	var burst := smoothstep(2.25,3.20,movement_time)
	creature.velocity = Vector3.FORWARD*creature.max_move_speed()*pace*lerpf(0.38,0.93,burst)
	if creature.spec.get("animal",false):
		creature.brain.forage_left = maxf(0.0,7.65-movement_time) if movement_time > 5.4 else 0.0
		creature.brain.mode = WastelandCreatureBrain.Mode.FLEE if burst*pace>0.8 else WastelandCreatureBrain.Mode.ROAM
	else:
		creature.windup = smoothstep(5.3,5.95,movement_time)*(1.0-smoothstep(5.95,6.08,movement_time))
		creature.attack = smoothstep(5.94,6.12,movement_time)*(1.0-smoothstep(6.13,6.67,movement_time))
		var action := WastelandCreatureBrain.Action.NONE
		if creature.windup>0.0 or creature.attack>0.0:
			match creature.type:
				"spitter": action = WastelandCreatureBrain.Action.SPIT
				"bloater": action = WastelandCreatureBrain.Action.RUPTURE
				"sandrunner": action = WastelandCreatureBrain.Action.CHARGE if creature.can_rush() else WastelandCreatureBrain.Action.MELEE
				"rimecaller": action = WastelandCreatureBrain.Action.MEND
				"screamer": action = WastelandCreatureBrain.Action.SCREAM
				"brute": action = WastelandCreatureBrain.Action.SMASH
				_: action = WastelandCreatureBrain.Action.MELEE
		creature.attack_kind = action
		if action != WastelandCreatureBrain.Action.RUPTURE and is_instance_valid(creature.blast_ring):
			creature.blast_ring.hide()
	creature._pose(delta,5.0)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and touch_finger < 0:
			touch_finger = event.index
		if event.index == touch_finger:
			pointer_at = event.position
			has_pointer = not event.canceled
			if not event.pressed or event.canceled: touch_finger = -1
	elif event is InputEventScreenDrag and event.index == touch_finger:
		pointer_at = event.position
		has_pointer = true
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and touch_finger < 0:
		pointer_at = event.position
		has_pointer = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		touch_finger = -1
		has_pointer = false

func _process(delta: float) -> void:
	if is_visible_in_tree() and is_instance_valid(creature):
		_advance_creature(delta)
		return
	if not is_visible_in_tree() or not is_instance_valid(subject) or not is_instance_valid(subject.neck):
		return
	if animate_idle: subject.pose(delta,0,0)
	var touch_device := preload("res://game/ui/touch_layout.gd").active
	var target := Vector2.ZERO
	if has_pointer or not touch_device:
		var at := pointer_at if has_pointer else get_viewport().get_mouse_position()
		var eye := subject.neck.to_global(Vector3(0,0.115,-0.075))
		var projected := camera.unproject_position(eye) * size / Vector2(scene.size).max(Vector2.ONE)
		var offset := get_global_transform_with_canvas().affine_inverse() * at - projected
		var reach := maxf(56.0,size.y*0.36)
		target.x = clampf(atan2(-offset.y,reach),-0.58,0.65)
		target.y = clampf(atan2(offset.x,reach)-subject.rotation.y,-1.18,1.18)
	var blend := 1.0-exp(-12.0*delta)
	subject.neck.rotation.x = lerp_angle(subject.neck.rotation.x,target.x,blend)
	subject.neck.rotation.y = lerp_angle(subject.neck.rotation.y,target.y,blend)

func frame(span: float, center_y: float) -> void:
	camera.size = span
	camera.position = Vector3(0,center_y+0.06,-3.4)
	camera.look_at(Vector3(0,center_y,0))

func frame_equipment(avatar: WastelandPartyAvatar) -> void:
	# Fit the actual survivor, including headwear, when the two equipment rails change width.
	var bottom := INF
	var top := -INF
	var side := 0.0
	for node: MeshInstance3D in avatar.find_children("*","MeshInstance3D",true,false):
		if not node.mesh or not node.is_visible_in_tree(): continue
		var bounds: AABB = node.global_transform * node.get_aabb()
		bottom = minf(bottom,bounds.position.y)
		top = maxf(top,bounds.end.y)
		side = maxf(side,maxf(absf(bounds.position.x),absf(bounds.end.x)))
	if top > bottom:
		var span := (top-bottom)*1.10
		if size.x>0 and size.y>0:
			span = maxf(span,2.12*side*size.y/size.x)
		frame(span,(top+bottom)*0.5)

func frame_survivor(avatar: WastelandPartyAvatar, zoom: String) -> void:
	portrait_zoom = zoom
	var face := avatar.find_child("SculptedFace",true,false) as MeshInstance3D
	if face == null: return
	var eye_level := face.to_global(face.get_aabb().get_center()).y
	match zoom:
		"全身": frame(2.10,0.93)
		"面部": frame(0.40,eye_level)
		_: frame(1.13,eye_level-0.30)
