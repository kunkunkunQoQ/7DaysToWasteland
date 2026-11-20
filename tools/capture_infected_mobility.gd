extends "res://tools/verify_combat.gd"

const ROWS := [
	[0,0,"四肢完整","双脚交替承重","旧衬衣"],
	[1,13,"缺左手","保留双腿步幅","短外套 · 腰包"],
	[18,25,"左小腿残缺","右腿承担主要支撑","短外套 · 斜挎包"],
	[74,35,"双小腿及左前臂残缺","伏低身体，用右臂拖行","缺袖上衣 · 水壶"]]
const PAPER := Color("#e7e2cf")
const MUTED := Color("#a5b4a8")
const ART_SIZE := Vector2i(418,288)
var studio := SubViewport.new()
var poster := SubViewport.new()
var camera := Camera3D.new()
var ink := SystemFont.new()
var title_font := SystemFont.new()
var photos := 0

func _run() -> void:
	WastelandSave.root_override="user://verification/mobility-photo-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	var config: Dictionary=app._default_config()
	config.seed=2817
	app._enter_world(config,{},0,false)
	session=app.session
	player=session.player
	await _ticks(28)
	session.simulation_paused=true
	_make_arena()
	await _ticks(3)
	_setup_studio()
	_setup_poster()
	for i in ROWS.size():
		await _photograph(i)
	if photos != ROWS.size():
		printerr("Incomplete mobility capture: ",photos," subjects")
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://build/qa/infected-mobility.png")
	var err := poster.get_texture().get_image().save_png(out)
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	studio.queue_free()
	poster.queue_free()
	ink = null
	title_font = null
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	print("Mobility capture: ",out," result=",err)
	quit(err)

func _setup_studio() -> void:
	studio.size=ART_SIZE*2
	studio.own_world_3d=true
	studio.msaa_3d=Viewport.MSAA_4X
	studio.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(studio)
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("#6c7773")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("#e1ebe4")
	env.ambient_light_energy=0.67
	camera.environment=env
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	studio.add_child(camera)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-48,-38,0)
	key.light_color=Color("#fff1d9")
	key.light_energy=0.99
	key.shadow_enabled=true
	key.shadow_bias=0.018
	key.shadow_normal_bias=0.24
	key.directional_shadow_max_distance=9.0
	studio.add_child(key)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size=Vector2(40,40)
	var floor_node:=MeshInstance3D.new()
	floor_node.mesh=floor_mesh
	floor_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ground:=ShaderMaterial.new()
	ground.shader=Shader.new()
	ground.shader.code="""
shader_type spatial;
varying vec2 meters;
void vertex() { meters = VERTEX.xz; }
void fragment() {
	vec2 grid = abs(fract(meters * 2.0 + 0.5) - 0.5) / max(fwidth(meters * 2.0), vec2(0.001));
	float line = 1.0 - smoothstep(0.0,1.05,min(grid.x,grid.y));
	ALBEDO = mix(vec3(0.20,0.245,0.225),vec3(0.167,0.212,0.199),line);
	ROUGHNESS = 1.0;
}
"""
	floor_node.material_override=ground
	studio.add_child(floor_node)

func _setup_poster() -> void:
	ink.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
	title_font.font_names=ink.font_names
	title_font.font_weight=700
	poster.size=Vector2i(1510,842)
	poster.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(poster)
	_block(Vector2.ZERO,Vector2(poster.size),Color("#243432"))
	_label("七日荒原   /   感染者图鉴",Vector2(36,20),20,MUTED)
	_label("肢体缺损与移动",Vector2(34,45),43,PAPER,true)
	_label("游荡者   ·   标准难度   ·   平地直线追逐",Vector2(1051,70),20,MUTED)
	_block(Vector2(36,114),Vector2(1438,2),Color("#738a7b"))
	_label("速度取追逐稳定后 3 秒内的平均水平速度。生命取拍摄时的实际数值。",Vector2(36,795),18,MUTED)

func _photograph(i: int) -> void:
	var row: Array=ROWS[i]
	player.global_position=anchor+Vector3(8,0.045,5.0)
	var actor:=_spawn("walker",anchor+Vector3(-6,0.045,5.0),player.global_position,
		{"morph":"","wardrobe_index":row[1],"limb_index":row[0]})
	actor.pose_phase=0.75
	await _ticks(36,[actor])
	var start:=actor.global_position
	await _ticks(180,[actor])
	var delta:=WastelandCreatureRoute.planar(actor.global_position-start)
	var speed:=delta.length()/(180*STEP)
	var actual_health:=actor.hp
	# Capture the weight-bearing phase of the crawl after timing it. The wrist
	# rises during recovery; wait for the real moving hand to contact the floor.
	if actor.low_crawl():
		for tick in 100:
			var hand_y:=_lowest(actor,"hand_r")-actor.global_position.y
			if absf(hand_y)<0.023:
				break
			await _ticks(1,[actor])
	var owner_node:=actor.get_parent()
	actor.reparent(studio,false)
	actor.position=Vector3.ZERO
	actor.rotation=Vector3.ZERO
	var low:=actor.low_crawl()
	var aim:=Vector3(0,0.51 if low else 0.91,0.05 if low else 0.0)
	camera.size=1.60 if low else 2.13
	camera.position=aim+Vector3(-2.9,0.74,-1.60) if low else aim+Vector3(-2.0,0.56,-2.69)
	camera.look_at(aim)
	await process_frame
	await RenderingServer.frame_post_draw
	var contact := {}
	for joint: String in ["hand_r","hand_l","elbow_l","hips","knee_l","knee_r"]:
		contact[joint] = _lowest(actor,joint)
	print("CONTACT ",row[0]," ",contact)
	var tile:=studio.get_texture().get_image()
	tile.resize(ART_SIZE.x,ART_SIZE.y,Image.INTERPOLATE_LANCZOS)
	var at:=Vector2(36+(i%2)*728,138+floori(i/2.0)*320)
	_block(at,Vector2(710,298),Color("#344742"))
	var photo:=TextureRect.new()
	photo.texture=ImageTexture.create_from_image(tile)
	photo.position=at+Vector2(5,5)
	poster.add_child(photo)
	var x:=at.x+440
	_label(row[2],Vector2(x,at.y+22),24,PAPER,true)
	_label(row[3],Vector2(x,at.y+59),18,MUTED)
	_label(row[4],Vector2(x,at.y+89),17,MUTED)
	_block(Vector2(x,at.y+130),Vector2(239,1),Color("#688075"))
	_label("追逐速度",Vector2(x,at.y+146),17,MUTED)
	_label("%.2f 米/秒"%speed,Vector2(x,at.y+169),28,PAPER,true)
	_label("生命   %.1f"%actual_health,Vector2(x,at.y+239),21,PAPER)
	print("MOBILITY ",row[0]," measured=",speed," health=",actual_health)
	actor.reparent(owner_node,false)
	session.hordes.release(actor)
	photos += 1

func _lowest(actor: WastelandCreature, joint: String) -> float:
	var lowest := INF
	for part: MeshInstance3D in actor.body_parts[joint].find_children("*","MeshInstance3D",true,false):
		if part.is_visible_in_tree():
			for vertex in part.mesh.get_faces():
				lowest = minf(lowest,(part.global_transform*vertex).y)
	return lowest

func _block(at: Vector2, dimensions: Vector2, color: Color) -> void:
	var shape:=ColorRect.new()
	shape.color=color
	shape.position=at
	shape.size=dimensions
	poster.add_child(shape)

func _label(words: String, at: Vector2, font_size: int, color: Color, heavy:=false) -> void:
	var label:=Label.new()
	label.text=words
	label.position=at
	label.add_theme_font_override("font",title_font if heavy else ink)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	poster.add_child(label)
