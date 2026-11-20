class_name WastelandBoatWake
extends MultiMeshInstance3D

const CAPACITY := 24
const LIFETIME := 2.35
var marks: Array[Dictionary] = []
var last_stern := Vector3.INF
var cursor := 0

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var points := [
			Vector3(side * 0.22, 0.0, -0.48), Vector3(side * 0.70, 0.0, 0.20),
			Vector3(side * 0.98, 0.0, 0.20), Vector3(side * 1.16, 0.0, 0.55),
		]
		for index in [0, 1, 2, 1, 3, 2]:
			ribbon.set_normal(Vector3.UP)
			ribbon.set_color(Color(1, 1, 1, 0.15 if index in [0, 3] else 1.0))
			ribbon.add_vertex(points[index])
	var paint := StandardMaterial3D.new()
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 1.0
	paint.render_priority = 2
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = ribbon.commit()
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	material_override = paint
	set_process(false)

func sample_surface(point: Vector3, stern_axis: Vector3, speed: float, in_water: bool) -> void:
	if not in_water or absf(speed) < 0.85:
		last_stern = Vector3.INF
		return
	var heading := stern_axis * signf(speed)
	var stern := point + heading * 1.30
	stern.y = WastelandTerrainGen.WATER_LEVEL + 0.046
	if stern.distance_squared_to(last_stern) < 0.88:
		return
	last_stern = stern
	var mark := {"point": stern, "angle": atan2(heading.x, heading.z), "age": 0.0, "power": clampf(absf(speed) / 7.0, 0.25, 1.0)}
	if marks.size() < CAPACITY:
		marks.append(mark)
	else:
		marks[cursor] = mark
		cursor = (cursor + 1) % CAPACITY
	set_process(true)

func _process(delta: float) -> void:
	var count := 0
	for index in range(marks.size() - 1, -1, -1):
		var mark := marks[index]
		mark.age += delta
		var age := float(mark.age) / LIFETIME
		if age >= 1.0:
			marks.remove_at(index)
			continue
		var power := float(mark.power)
		var spread := 0.68 + age * (1.8 + power)
		var axes := Basis(Vector3.UP, mark.angle).scaled_local(Vector3(spread, 1.0, 0.68 + power * 0.5))
		multimesh.set_instance_transform(count, Transform3D(axes, mark.point))
		multimesh.set_instance_color(count, Color(0.82, 0.96, 0.86, (1.0 - age) * (0.36 + power * 0.46)))
		count += 1
	multimesh.visible_instance_count = count
	if count == 0:
		set_process(false)
