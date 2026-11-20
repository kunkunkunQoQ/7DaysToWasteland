extends "res://tools/verify_combat.gd"

const TILE:=Vector2i(538,315)
const FOOT:=42
var view:=SubViewport.new()
var lens:=Camera3D.new()
var caption:=Label.new()
var sheet:=Image.create_empty(TILE.x*3,(TILE.y+FOOT)*4,false,Image.FORMAT_RGB8)
var taken:=0
var center:Vector3

func _run()->void:
	if DisplayServer.get_name()=="headless":
		quit(1)
		return
	WastelandSave.root_override="user://verification/combat-photo-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	var config:Dictionary=app._default_config()
	config.seed=2817
	config.start_id="shore"
	app._enter_world(config,{},0,false)
	session=app.session
	player=session.player
	session.simulation_paused=true
	session.set_physics_process(false)
	var cell:=Vector2i(3,-1)
	center=Vector3(cell.x*32+16,0,cell.y*32+16)
	session.stream.refresh(center,2)
	for dx in range(-1,2):
		for dz in range(-1,2): session.stream.ensure_landing(center+Vector3(dx*32,0,dz*32))
	center.y=session.stream.ground_at(center)
	await session.stream.quiesce()
	view.size=Vector2i(TILE.x,TILE.y+FOOT)
	view.world_3d=session.get_world_3d()
	view.msaa_3d=Viewport.MSAA_4X
	root.add_child(view)
	view.add_child(lens)
	lens.make_current()
	lens.fov=37
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	app.world_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	app.hands_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var footer:=ColorRect.new()
	footer.color=Color("#233332")
	footer.position.y=TILE.y
	footer.size=Vector2(TILE.x,FOOT)
	view.add_child(footer)
	caption.position=Vector2(15,5)
	var label_font:=SystemFont.new()
	label_font.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
	caption.add_theme_font_override("font",label_font)
	caption.add_theme_font_size_override("font_size",21)
	caption.add_theme_color_override("font_color",Color("#f2e7ce"))
	footer.add_child(caption)
	player.hide()
	await _ticks(3)
	await shoot_brute(session.stream.active[cell])
	await shoot_spitter()
	await shoot_bloater()
	center=Vector3(112,0,-112)
	session.stream.refresh(center,2)
	for dx in range(-1,2):
		for dz in range(-1,2): session.stream.ensure_landing(center+Vector3(dx*32,0,dz*32))
	center.y=session.stream.ground_at(center)
	await _ticks(4)
	await shoot_healer()
	if failures.is_empty() and taken==12:
		check(sheet.save_png("res://build/qa/infected-combat-field.png")==OK,"write twelve live combat frames")
	else:
		printerr("Combat capture incomplete ",taken," ",failures)
	view.queue_free()
	await session.audio.finish_playback()
	app._remove_session()
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() and taken==12 else 1)

func ground(offset:Vector3)->Vector3:
	var p:=center+offset
	p.y=session.stream.ground_at(p)+0.03
	return p

func individual(kind:String,at:Vector3,to:Vector3,look:=0)->WastelandCreature:
	return _spawn(kind,at,to,{"look_index":look,"limb_index":0,"wardrobe_index":0,"morph":""})

func frame(target:Vector3,eye:Vector3,words:String,fov:=37.0)->void:
	lens.global_position=eye
	lens.fov=fov
	lens.look_at(target)
	session.clock.hours=12.6
	session.atmosphere.sync(session.clock,0,lens.global_position,-lens.global_basis.z)
	caption.text=words
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	sheet.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i((taken%3)*TILE.x,(taken/3)*(TILE.y+FOOT)))
	taken+=1
	print("FIELD ",words)

func wait_for_state(a:WastelandCreature,action:int,phase:float)->bool:
	for step in 140:
		await _ticks(1,[a],true)
		if a.brain.action==action and a.windup>=phase: return true
	return false

func shoot_brute(chunk:WastelandChunk)->void:
	var wall:StaticBody3D=chunk.structures["wall/0/2/2"][0]
	var mid:=wall.global_position
	mid.y=center.y+0.18
	player.global_position=mid+Vector3.BACK*2.1
	var a:=individual("brute",mid+Vector3.FORWARD*1.30,player.global_position,1)
	session.hit_wall(wall,session.wall_health(wall)-21)
	session.hordes.add_noise(player.global_position,36)
	await _ticks(3)
	a.brain.route._find_breach(a.global_position+Vector3.UP*0.84,player.global_position,a.brain.reach)
	var ready:=await wait_for_state(a,BRAIN.Action.SMASH,0.16)
	check(ready,"brute AI targets actual police wall")
	if ready:
		var target:=a.global_position+Vector3(0,1.15,0.55)
		var eye:=a.global_position+Vector3(3.95,1.72,-1.15)
		await frame(target,eye,"破障工兵　｜　对准受损墙段")
		await wait_for_state(a,BRAIN.Action.SMASH,0.83)
		await frame(target,eye,"蓄力　｜　举臂准备砸墙")
		for step in 30:
			await _ticks(1,[a])
			if not chunk.structures.has("wall/0/2/2"): break
		check(not chunk.structures.has("wall/0/2/2"),"hammer destroys tracked wall section")
		await create_timer(4.1,false,true).timeout
		await _ticks(34,[a])
		await frame(mid+Vector3.UP*1.00,mid+Vector3(2.15,1.61,-4.15),"破墙　｜　墙段脱落形成缺口",43)
	session.hordes.release(a)

func shoot_spitter()->void:
	var at:=ground(Vector3(-3,0,7.25))
	player.global_position=ground(Vector3(3.6,0,7.25))
	var a:=individual("spitter",at,player.global_position,1)
	await _ticks(2)
	var ready:=await wait_for_state(a,BRAIN.Action.SPIT,0.71)
	check(ready,"spitter sees target and winds up")
	if ready:
		await frame(at+Vector3(0.15,1.08,0),at+Vector3(2.0,1.40,2.8),"巡防污染者　｜　仰头蓄酸")
		player.global_position+=Vector3.BACK*2.1
		for step in 34:
			await _ticks(1,[a],true)
			if not session.fx.acid_flights().is_empty(): break
		await _ticks(4,[],true)
		var shots:=session.fx.acid_flights()
		check(not shots.is_empty(),"AI fired live acid projectile")
		if not shots.is_empty():
			var shot:Vector3=shots.back().at
			var aim:=a.global_position.lerp(shot,0.60)
			aim.y=at.y+1.14
			await frame(aim,aim+Vector3(1.05,0.79,3.92),"喷射　｜　酸弹飞离口部")
		for step in 125:
			await _ticks(1,[],true)
			if not session.fx.acid_snapshot().is_empty(): break
		var pools:=session.fx.acid_snapshot()
		check(not pools.is_empty(),"shot actually hits world and leaves residue")
		if not pools.is_empty():
			var pool:Vector3=pools.back().at
			await frame(pool+Vector3.UP*0.34,pool+Vector3(1.15,2.52,3.75),"落地　｜　腐液留在地面")
	session.hordes.release(a)

func shoot_bloater()->void:
	var at:=ground(Vector3(-1.8,0,7.3))
	player.global_position=ground(Vector3(-0.70,0,9.1))
	_reset_player()
	var a:=individual("bloater",at,player.global_position,1)
	await _ticks(4,[a])
	var torso:=at+Vector3.UP*0.98
	var eye:=at+Vector3(2.3,1.43,2.80)
	await frame(torso,eye,"胀囊者　｜　接近幸存者")
	a.take_hit(a.max_health()+1,player.global_position)
	await _ticks(77,[a])
	check(a.fuse_left>0 and a.blast_ring.visible,"lethal hit starts live fuse and warning ring")
	await frame(torso,eye,"蓄压　｜　腹囊膨起、双臂张开")
	var old:=session.fx.particle_cursor
	for step in 42:
		await _ticks(1,[a])
		if not a.active: break
	check(not a.active and session.fx.particle_cursor!=old and player.health<100,"rupture fires particles and hits nearby survivor")
	await _ticks(5)
	await frame(torso,eye,"爆裂　｜　近处幸存者受到冲击")

func shoot_healer()->void:
	var at:=ground(Vector3(-2.60,0,7.42))
	var patient_at:=ground(Vector3(-0.28,0,8.02))
	player.global_position=ground(Vector3(4,0,8.2))
	var a:=individual("rimecaller",at,player.global_position,1)
	var patient:=individual("walker",patient_at,at+Vector3.BACK*6,0)
	patient.take_hit(32,player.global_position)
	var before:=patient.hp
	await _ticks(3)
	var ready:=await wait_for_state(a,BRAIN.Action.MEND,0.22)
	check(ready and a.brain.patient==patient,"caller selects actual injured ally")
	if ready:
		var focus:=at.lerp(patient_at,0.45)+Vector3.UP*1.05
		var eye:=focus+Vector3(0.28,0.77,4.33)
		await frame(focus,eye,"霜鸣者　｜　面向受伤同类")
		await wait_for_state(a,BRAIN.Action.MEND,0.83)
		await frame(at+Vector3.UP*1.20,at+Vector3(2.15,1.43,2.64),"鸣霜　｜　双手抬起蓄能")
		var cursor:=session.fx.particle_cursor
		for step in 28:
			await _ticks(1,[a])
			if patient.hp>before: break
		check(patient.hp>before and session.fx.particle_cursor!=cursor,"mend restores HP and emits particles on ally")
		for i in 8:
			await process_frame
			await RenderingServer.frame_post_draw
		await frame(focus,eye,"修复生效　｜　同类生命 %.0f → %.0f"%[before,patient.hp])
	session.hordes.release(a)
	session.hordes.release(patient)
