class_name WastelandVehicle
extends CharacterBody3D

var session: Node3D
var record: Dictionary
var id: String
var occupied := false
var drive_speed := 0.0
var splash_time := 0.0
var sound_time := 0.0
var wheel_nodes: Array[Node3D] = []
var wake: WastelandBoatWake
var repair_marker: Node3D

func max_hp() -> float:
	return float({"bicycle":65,"bike":130,"boat":155,"pickup":245}.get(record.type,100))

func configure(owner_session: Node3D, key: String, data: Dictionary) -> void:
	session = owner_session
	id = key
	record = data
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.52
	floor_max_angle = deg_to_rad(49.0)
	var type: String = record.type
	var wide := type in ["boat","pickup"]
	var width := 1.70 if wide else 0.53
	var length := 2.87 if wide else 1.70
	var paint := session.catalog.color(type).darkened(0.21) as Color
	var chassis := WastelandLook.form(self, Vector3(width,0.25 if type != "pickup" else 0.55,length),
		Vector3(0,0.33,0), paint, 0.16)
	chassis.rotation.x = -0.05 if type == "boat" else 0.0
	WastelandLook.collider(self, Vector3(width,0.69,length), Vector3(0,0.42,0))
	WastelandLook.form(self, Vector3(width*0.64,0.17,0.46), Vector3(0,0.65,0.21), Color("#504752"),0.18)
	if type == "boat":
		wake = WastelandBoatWake.new()
		add_child(wake)
		var hull := WastelandScenery.new(24381)
		hull.tube(PackedVector3Array([Vector3(0,0.32,-1.77),Vector3(0,0.32,-1.33),Vector3(0,0.28,-0.71),Vector3(0,0.25,0.19),Vector3(0,0.25,1.19),Vector3(0,0.28,1.43)]),
			PackedFloat32Array([0.13,0.59,0.92,0.91,0.78,0.71]),12,paint.darkened(0.15))
		var canoe := MeshInstance3D.new()
		canoe.mesh=hull.commit()
		canoe.scale.y=0.27
		canoe.position.y=0.25
		canoe.material_override=WastelandLook.colored_material()
		add_child(canoe)
		for side in [-1,1]:
			WastelandLook.form(self, Vector3(0.16,0.27,length*0.78), Vector3(side*width*0.48,0.43,0.22), paint.lightened(0.20))
			WastelandLook.form(self, Vector3(0.23,0.16,0.84), Vector3(side*width*0.32,0.49,-length*0.43), paint.lightened(0.32)).rotation.y = side * -0.55
			WastelandLook.form(self, Vector3(0.073,0.085,0.91), Vector3(side*width*0.52,0.48,0.31), Color("#c8a179"))
		WastelandLook.form(self, Vector3(0.46,0.37,0.42), Vector3(0,0.47,1.53), Color("#706378"),0.17)
		WastelandLook.form(self, Vector3(0.32,0.11,0.49), Vector3(0,0.70,1.54), Color("#896961"),0.2)
		for rung in range(5):
			WastelandLook.form(self,Vector3(0.86,0.039,0.073),Vector3(0,0.49,-0.42+rung*0.15),Color("#9c7f6e"))
	else:
		for side in ([-1, 1] if wide else [0]):
			for z in [-length*0.40, length*0.40]:
				_wheel(Vector3(side*width*0.48,0.25,z),wide,0.32 if type!="bike" else 0.35)
		if type == "pickup":
			WastelandLook.form(self, Vector3(width*0.92,0.74,1.29), Vector3(0,0.87,-0.52), paint,0.14)
			var windscreen := WastelandLook.form(self, Vector3(width*0.82,0.37,0.095), Vector3(0,1.00,-1.148), Color("#514a64"),0.11)
			windscreen.rotation.x=-0.22
			WastelandLook.form(self,Vector3(width*0.98,0.15,0.33),Vector3(0,0.36,-1.43),Color("#706978"))
			WastelandLook.form(self,Vector3(width*0.95,0.12,0.70),Vector3(0,0.54,-1.07),paint.lightened(0.12))
			for side in [-1,1]:
				for z in [-0.59,0.40]:
					WastelandLook.form(self,Vector3(0.065,0.16,0.53),Vector3(side*0.80,0.67,z),paint.lightened(0.10))
				WastelandLook.form(self,Vector3(0.24,0.15,0.079),Vector3(side*0.61,0.49,-1.51),Color("#e1c895"),0.14)
				WastelandLook.form(self,Vector3(0.08,0.34,0.77),Vector3(side*0.76,0.70,0.84),paint.darkened(0.18))
				WastelandLook.form(self,Vector3(0.092,0.22,0.36),Vector3(side*0.77,1.036,-0.54),Color("#565769"))
			for slot in range(7):
				WastelandLook.form(self,Vector3(0.059,0.071,0.031),Vector3((slot-3)*0.084,0.472,-1.53),Color("#514b57"),0.04)
		else:
			var handlebars := Color("#a38f8a")
			WastelandLook.form(self, Vector3(0.67,0.059,0.085), Vector3(0,0.89,-0.54), handlebars,0.17)
			var brace := WastelandLook.form(self,Vector3(0.12,0.61,0.13),Vector3(0,0.55,-0.53),paint,0.2)
			brace.rotation.x=-0.22
			WastelandLook.form(self,Vector3(0.11,0.48,0.11),Vector3(0,0.43,0.36),paint.darkened(0.2),0.16).rotation.x=0.52
			WastelandLook.form(self,Vector3(0.14,0.14,0.83),Vector3(0,0.5,-0.04),paint.lightened(0.12),0.21).rotation.x=-0.49
			for grip in [-1,1]:
				WastelandLook.form(self,Vector3(0.145,0.072,0.084),Vector3(grip*0.30,0.89,-0.55),Color("#574854"),0.20)
			if type=="bike":
				WastelandLook.form(self,Vector3(0.42,0.31,0.53),Vector3(0,0.61,-0.10),paint.lightened(0.11),0.23)
				WastelandLook.form(self,Vector3(0.27,0.15,0.081),Vector3(0,0.70,-0.79),Color("#eac485"),0.14)
	set_meta("kind", "vehicle")
	set_meta("vehicle_id", id)
	global_position = record.point
	rotation.y = float(record.get("yaw",0.0))
	update_repair_marker()

func update_repair_marker() -> void:
	var damaged := bool(record.get("needs_repair", false))
	if damaged and not is_instance_valid(repair_marker):
		repair_marker = Node3D.new()
		add_child(repair_marker)
		WastelandLook.box(repair_marker, Vector3(0.16, 0.07, 1.15), Vector3(-0.10, 0.77, 0.33), Color("#976444")).rotation.y = -0.78
		WastelandLook.box(repair_marker, Vector3(0.13, 0.06, 1.03), Vector3(0.10, 0.85, 0.36), Color("#c29b63")).rotation.y = 0.72
		WastelandLook.box(repair_marker, Vector3(0.43, 0.30, 0.05), Vector3(0.38, 0.77, 0.74), Color("#de893f")).rotation.z = 0.32
	if is_instance_valid(repair_marker):
		repair_marker.visible = damaged

func _wheel(at: Vector3, broad: bool, radius: float) -> void:
	var tire := Node3D.new()
	tire.position=at
	add_child(tire)
	wheel_nodes.append(tire)
	var size := 0.25 if broad else 0.113
	for layer in range(3):
		var mesh := CylinderMesh.new()
		mesh.radial_segments=18
		mesh.rings=1
		mesh.top_radius=radius * (1.0 if layer==0 else 0.49 if layer==1 else 0.23)
		mesh.bottom_radius=mesh.top_radius
		mesh.height=size+float(layer)*0.036
		var wheel := MeshInstance3D.new()
		wheel.mesh=mesh
		wheel.material_override=WastelandLook.matte(Color.html(["3c3542","8d7778","585060"][layer]))
		wheel.rotation.z=PI*0.5
		tire.add_child(wheel)
	for i in range(10):
		var angle := i*TAU/10.0
		var rim := WastelandLook.form(tire,Vector3(size*0.9,0.063,0.080),Vector3(0,cos(angle)*radius,sin(angle)*radius),Color("#4f414d"),0.07)
		rim.rotation.x=angle

func seat_height() -> float:
	return 0.61 if record.type == "pickup" else 0.30

func drive(delta: float, input: Vector2, boost: bool) -> void:
	var type: String = record.type
	var is_boat := type == "boat"
	var surface: float = session.stream.ground_at(global_position)
	var in_water: bool = surface < -0.14 and global_position.y < 0.72 and session.stream.water_at(global_position)
	var def: Dictionary = session.catalog.items[type]
	var throttle := -input.y
	if def.get("powered", false) and float(record.fuel) <= 0.0:
		throttle = 0.0
	var maximum := float(def.speed) * (0.20 if is_boat != in_water else 1.0)
	var target_speed := throttle * maximum * (0.37 if throttle < 0.0 else 1.0)
	if boost and type == "bicycle":
		target_speed *= 1.18
	var acceleration := 7.2 if input.length_squared() > 0.04 else 9.0
	if is_boat and in_water:
		acceleration = 1.65 if is_zero_approx(throttle) else 5.0
	drive_speed = move_toward(drive_speed, target_speed, delta * acceleration)
	var steering := 0.38 + minf(1.25, absf(drive_speed) * 0.17)
	if is_boat and in_water:
		steering = 0.85 + minf(0.65, absf(drive_speed) * 0.10)
	rotation.y -= input.x * delta * steering * (1.0 if drive_speed >= 0 else -1.0)
	var guide := -basis.z * drive_speed
	velocity.x = guide.x
	velocity.z = guide.z
	if in_water:
		var float_target := -0.23 if is_boat else maxf(surface + 0.12, -1.48)
		velocity.y = move_toward(velocity.y, (float_target-global_position.y)*4.3, delta*14.0)
	else:
		velocity.y -= 18.0 * delta
	if session.stream.at_surface(global_position + guide * delta):
		move_and_slide()
	if wake != null:
		wake.sample_surface(global_position, global_basis.z, drive_speed, in_water)
	if def.get("powered", false) and (not is_boat or not is_zero_approx(throttle)):
		record.fuel = maxf(0.0, float(record.fuel) - delta * absf(drive_speed) * 0.062)
	record.point = global_position
	record.yaw = rotation.y
	for wheel in wheel_nodes:
		wheel.rotate_x(delta*drive_speed*2.90)
	splash_time -= delta
	sound_time -= delta
	if in_water and absf(drive_speed) > 1.0 and splash_time <= 0.0:
		splash_time = 0.22
		var stern := global_position + basis.z * (1.20 if drive_speed > 0.0 else -1.24)
		stern.y = 0.05
		var wash := clampf(absf(drive_speed) / maximum, 0.0, 1.0)
		if not is_boat:
			for side in [-1, 1]:
				session.fx.burst(stern + basis.x * side * 0.56, Color("#9acdd0"), 0.33 + wash * 0.33)
		if sound_time <= 0:
			sound_time = 1.02
			session.audio.play_at("splash", global_position, 0.57)
	if not in_water and def.get("powered", false) and absf(drive_speed) > 0.85 and sound_time <= 0.0:
		sound_time = 1.27
		session.audio.play_at("generator", global_position, 0.63)
		session.hordes.add_heat(global_position, 0.49)
