class_name WastelandAtmosphere
extends Node3D

var sky_mat := ShaderMaterial.new()
var water_mat := ShaderMaterial.new()
var terrain_mat := ShaderMaterial.new()
var env := Environment.new()
var light := DirectionalLight3D.new()
var rain_fx: GPUParticles3D
var weather_kind := 0
var lightning := 0.0
var next_flash := 4.0
var tick := 0.0
var view_position := Vector3.ZERO
var rain_strength := 0.0
var sun_strength := 0.0
var snowing := false
var distant_basin := MeshInstance3D.new()
var terrain: WastelandTerrainGen
var horizon_task := -1
var horizon_center := Vector2i.MAX
var horizon_job: HorizonJob
var horizon_edits := {}
var horizon_revision := 0
var baked_horizon_revision := 0

class HorizonJob:
	extends RefCounted
	var seed_value: int
	var center: Vector2i
	var arrays: Array
	var edits: Dictionary
	var revision: int
	func run() -> void:
		var gen := WastelandTerrainGen.new(seed_value,3)
		arrays = WastelandAtmosphere._horizon_arrays(gen,Vector2(center),16.0,true,edits)

static var cached_distant_mesh: ArrayMesh
static var cached_distant_seed := 0
static var cached_distant_revision := 0

func set_distant_basin(generator: WastelandTerrainGen) -> void:
	terrain = generator
	if distant_basin.get_parent() == null:
		add_child(distant_basin)
		distant_basin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/distant_basin.gdshader")
		material.render_priority = -110
		distant_basin.material_override = material
	if generator.revision>=3:
		distant_basin.material_override.set_shader_parameter("regional_color",true)
		return
	if cached_distant_mesh == null or cached_distant_seed != generator.seed_value or cached_distant_revision != generator.revision:
		cached_distant_mesh = ArrayMesh.new()
		cached_distant_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_horizon_arrays(generator,Vector2(8,-46),8.0,false))
		cached_distant_seed = generator.seed_value
		cached_distant_revision = generator.revision
	distant_basin.mesh = cached_distant_mesh

func _stream_horizon(eye: Vector3) -> void:
	if horizon_task>=0:
		if not WorkerThreadPool.is_task_completed(horizon_task): return
		WorkerThreadPool.wait_for_task_completion(horizon_task)
		horizon_task = -1
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,horizon_job.arrays)
		distant_basin.mesh = mesh
		horizon_center = horizon_job.center
		baked_horizon_revision = horizon_job.revision
		horizon_job = null
	var at := Vector2i(roundi(eye.x/128.0)*128,roundi(eye.z/128.0)*128)
	if horizon_center==at and baked_horizon_revision==horizon_revision: return
	horizon_job = HorizonJob.new()
	horizon_job.seed_value = terrain.seed_value
	horizon_job.center = at
	horizon_job.revision = horizon_revision
	horizon_job.edits = horizon_edits.duplicate()
	horizon_task = WorkerThreadPool.add_task(horizon_job.run)

func _exit_tree() -> void:
	if horizon_task>=0:
		WorkerThreadPool.wait_for_task_completion(horizon_task)
		horizon_task = -1

func set_horizon_sample(point: Vector2i, depth: float) -> void:
	var spacing := 16 if terrain.revision>=3 else 8
	var origin := Vector2i.ZERO if terrain.revision>=3 else Vector2i(8,-46)
	var offset := point-origin
	if offset.x%spacing!=0 or offset.y%spacing!=0: return
	if depth==0: horizon_edits.erase(point)
	else: horizon_edits[point]=depth
	horizon_revision += 1

static func _horizon_arrays(generator: WastelandTerrainGen,origin: Vector2,spacing: float,regional: bool,edits: Dictionary = {}) -> Array:
	const SAMPLES := 53
	var points := PackedVector3Array()
	var index := PackedInt32Array()
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for row in SAMPLES:
		for col in SAMPLES:
			var x := (col - 26) * spacing + origin.x
			var z := (row - 26) * spacing + origin.y
			var height := generator.raw_height(x, z) + float(edits.get(Vector2i(int(x),int(z)),0.0))
			var flooded := height < 0.0 and generator.water_basin(x, z)
			points.append(Vector3(x, maxf(height, 0.0) if flooded else height, z))
			uv.append(Vector2(float(flooded), smoothstep(4.0, 34.0, height)))
			if regional: colors.append(generator.ground_color(x,z,height))
			if row > 0 and col > 0:
				var last := points.size() - 1
				index.append_array(PackedInt32Array([last - SAMPLES - 1, last - SAMPLES, last - 1, last - SAMPLES, last, last - 1]))
	for row in SAMPLES:
		for col in SAMPLES:
			var dx := points[row * SAMPLES + mini(col + 1, SAMPLES - 1)] - points[row * SAMPLES + maxi(col - 1, 0)]
			var dz := points[mini(row + 1, SAMPLES - 1) * SAMPLES + col] - points[maxi(row - 1, 0) * SAMPLES + col]
			normals.append(dz.cross(dx).normalized())
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	arrays[Mesh.ARRAY_TEX_UV] = uv
	if regional: arrays[Mesh.ARRAY_COLOR]=colors
	return arrays

func _ready() -> void:
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	water_mat.shader = preload("res://shaders/water.gdshader")
	terrain_mat.shader = preload("res://shaders/terrain.gdshader")
	var backdrop := Sky.new()
	backdrop.radiance_size = Sky.RADIANCE_SIZE_64
	backdrop.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	backdrop.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = backdrop
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var environment := WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = 74.0
	light.directional_shadow_split_1 = 0.16
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 1.25
	add_child(light)
	add_outline(self)

static func add_outline(parent: Node) -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/outline.gdshader")
	material.render_priority = -50
	var fullscreen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	fullscreen.mesh = quad
	fullscreen.material_override = material
	fullscreen.extra_cull_margin = 30000.0
	fullscreen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fullscreen)

func _add_rain() -> void:
	rain_fx = GPUParticles3D.new()
	rain_fx.amount = 460
	rain_fx.lifetime = 0.92
	rain_fx.local_coords = false
	rain_fx.visibility_aabb = AABB(Vector3(-16, -14, -16), Vector3(32, 28, 32))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(12, 0.2, 12)
	motion.direction = Vector3(0.17, -1.0, 0.10)
	motion.spread = 5.0
	motion.initial_velocity_min = 12.0
	motion.initial_velocity_max = 16.0
	motion.gravity = Vector3(0.0, -9.0, 0.0)
	rain_fx.process_material = motion
	var geom := BoxMesh.new()
	geom.size = Vector3(0.015, 0.29, 0.015)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.albedo_color = Color(0.68, 0.74, 0.83, 0.52)
	geom.material = rain_mat
	rain_fx.draw_pass_1 = geom
	rain_fx.emitting = false
	add_child(rain_fx)

func sync(clock: WastelandClock, delta: float, eye: Vector3, look: Vector3, audio: Node = null) -> void:
	tick -= delta
	if tick > 0.0 and delta > 0.0:
		return
	var step := 0.091
	tick = step
	view_position = eye
	var offset := 0.0
	if terrain!=null and terrain.revision>=3:
		_stream_horizon(eye)
		offset = terrain.temperature_offset(eye.x,eye.z)
	elif terrain!=null and baked_horizon_revision!=horizon_revision:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_horizon_arrays(terrain,Vector2(8,-46),8.0,false,horizon_edits))
		distant_basin.mesh = mesh
		baked_horizon_revision = horizon_revision
	var hour := clock.hour()
	var phase := (hour - 6.0) * TAU / 24.0
	var sun_height := sin(phase)
	var azimuth := lerpf(1.85, -0.35, 0.5 - 0.5 * cos(phase))
	var dusk := 1.0 - smoothstep(0.035, 0.54, absf(sun_height))
	var daylight := smoothstep(-0.10, 0.76, sun_height)
	var moonlight := 1.0 - smoothstep(-0.18, 0.18, sun_height)
	var blood := clock.blood()
	var weights := clock.weather()
	rain_strength = weights.z * 0.62 + weights.w
	if offset>7.0: rain_strength *= 0.24
	weather_kind = 0
	for k in range(1, 4):
		if weights[k] > weights[weather_kind]:
			weather_kind = k
	var body_height := maxf(sun_height, -0.54 * sun_height)
	var light_dir := Vector3(sin(azimuth), body_height, -cos(azimuth)).normalized()
	# Power generation and creature sight use the original evening blood-moon bonus.
	var gameplay_dusk := maxf(dusk, 0.48 * blood) if hour >= 18.0 else dusk
	sun_strength = maxf(daylight, 0.32 * gameplay_dusk)
	light.look_at_from_position(light_dir * 30.0, Vector3.ZERO, Vector3.UP)
	var cloud_wet := clampf(rain_strength * 0.9 + weights.y * 0.38, 0.0, 1.0)
	var light_color := Color("#ffeacb").lerp(Color("#acbde5"), moonlight)
	light_color = light_color.lerp(Color("#ffc18b"), dusk * (1.0 - moonlight))
	light_color = light_color.lerp(Color("#ced7e0"), cloud_wet * 0.48).lerp(Color("#f47789"), blood)
	lightning = move_toward(lightning, 0.0, step * 3.5)
	next_flash -= step
	if weights.w > 0.65 and next_flash < 0.0:
		lightning = 1.0
		next_flash = 6.0 + fposmod(clock.hours * 321.0, 11.0)
		if audio != null:
			audio.play_at("thunder", eye + Vector3(0, 16, -22), 1.0, false)
	light.light_color = light_color.lerp(Color("#e4efff"), lightning * 0.82)
	light.light_energy = lerpf(0.31 + 0.36 * dusk, 1.2, daylight) * (1.0 - cloud_wet * 0.68) + lightning * 1.25
	var shadow_contrast := lerpf(0.94, 0.66, moonlight) * (1.0 - 0.65 * cloud_wet)
	light.shadow_opacity = shadow_contrast * smoothstep(0.015, 0.23, light_dir.y)
	var fill := Color("#8c9dbb").lerp(Color("#bfd1dd"), daylight).lerp(Color("#b0a5b3"), dusk * 0.44)
	env.ambient_light_color = fill.lerp(Color("#997594"), blood)
	env.ambient_light_energy = (0.43 + 0.25 * daylight + 0.10 * dusk + 0.10 * cloud_wet * daylight) * (1.0 - 0.18 * blood) + lightning * 0.22
	var face := maxf(0.0, look.dot(Vector3(light_dir.x, 0.0, light_dir.z).normalized()))
	var pastel := Color("#8b9fa5").lerp(Color("#d9ab8e"), pow(face, 2.4))
	var fog := Color("#332e4e").lerp(Color("#a2acb5"), daylight).lerp(pastel, dusk)
	fog = fog.lerp(Color("#44495c").lerp(Color("#929aa3"), daylight), cloud_wet * 0.45)
	env.fog_light_color = fog.lerp(Color("#643853").lerp(Color("#884457"), face), blood)
	env.fog_light_energy = 1.0 + lightning * 0.20
	env.fog_density = 0.0058 + weights.y * 0.023 + rain_strength * 0.012 + blood * 0.004
	for material in [sky_mat, water_mat]:
		material.set_shader_parameter("sun_dir", light_dir)
		material.set_shader_parameter("daylight", daylight)
		material.set_shader_parameter("moonlight", moonlight)
		material.set_shader_parameter("twilight", dusk)
		material.set_shader_parameter("blood", blood)
	sky_mat.set_shader_parameter("wet", cloud_wet)
	sky_mat.set_shader_parameter("clock_seconds", clock.elapsed)
	water_mat.set_shader_parameter("rain", rain_strength)
	water_mat.set_shader_parameter("seconds", clock.elapsed)
	terrain_mat.set_shader_parameter("wind_time", clock.elapsed)
	terrain_mat.set_shader_parameter("rain", rain_strength)
	terrain_mat.set_shader_parameter("sunlight", daylight * (1.0 - cloud_wet))
	if rain_strength > 0.12 and rain_fx == null:
		_add_rain()
	if rain_fx != null:
		var temperature := clock.temperature()+offset-maxf(0.0,eye.y-10.0)*0.16
		var frozen := temperature < (0.8 if snowing else 0.25)
		if frozen!=snowing:
			snowing=frozen
			_style_precipitation(frozen)
		rain_fx.global_position = eye + Vector3(0, 8, 0)
		rain_fx.amount_ratio = rain_strength
		rain_fx.emitting = rain_strength > 0.12

func _style_precipitation(frozen: bool) -> void:
	var flakes: BoxMesh=rain_fx.draw_pass_1
	var paint: StandardMaterial3D=flakes.material
	var wind: ParticleProcessMaterial=rain_fx.process_material
	if frozen:
		flakes.size=Vector3(0.056,0.048,0.052)
		paint.albedo_color=Color(0.81,0.79,0.89,0.80)
		wind.direction=Vector3(0.58,-1,0.20)
		wind.initial_velocity_min=1.2
		wind.initial_velocity_max=3.0
		wind.gravity=Vector3(0,-2.8,0)
		rain_fx.lifetime=2.5
	else:
		flakes.size=Vector3(0.015,0.29,0.015)
		paint.albedo_color=Color(0.68,0.74,0.83,0.52)
		wind.direction=Vector3(0.17,-1,0.10)
		wind.initial_velocity_min=12.0
		wind.initial_velocity_max=16.0
		wind.gravity=Vector3(0,-9.0,0)
		rain_fx.lifetime=0.92
