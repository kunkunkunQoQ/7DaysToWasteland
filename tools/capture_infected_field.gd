extends "res://tools/verify_frontier_ecology.gd"

const TILE:=Vector2i(464,496)
const CAPTION:=64
const LOOKS:=preload("res://game/art/infected_looks.gd")
const SHOTS:=[
	["sandrunner",0,WastelandCreatureBrain.Action.CHARGE,0.62,Vector3(1.85,1.22,-2.46),1.02,31.0,"沙丘 · 冲刺蓄势"],
	["rimecaller",1,WastelandCreatureBrain.Action.MEND,0.76,Vector3(-1.22,1.58,-2.96),1.18,33.0,"雪山 · 举臂鸣霜"],
	["bloater",1,WastelandCreatureBrain.Action.RUPTURE,0.48,Vector3(1.62,1.38,-2.58),1.12,36.0,"湿原 · 胀囊预警"]]
const CIVILIAN_SHOTS:=[
	["spitter",0,WastelandCreatureBrain.Action.NONE,0.0,Vector3(1.0,1.36,-2.8),1.29,33.0,"湿原 · 巡游"],
	["spitter",1,WastelandCreatureBrain.Action.SPIT,0.86,Vector3(1.35,1.36,-2.8),1.29,33.0,"湿原 · 吐射前仰头"],
	["spitter",2,WastelandCreatureBrain.Action.NONE,0.0,Vector3(-1.0,1.36,-2.8),1.29,33.0,"湿原 · 巡游"],
	["bloater",0,WastelandCreatureBrain.Action.NONE,0.0,Vector3(1.10,1.28,-2.8),1.10,32.0,"湿原 · 衬衫下摆隆起"],
	["bloater",1,WastelandCreatureBrain.Action.NONE,0.0,Vector3(-0.65,1.28,-2.8),1.10,32.0,"湿原 · 日常步态"],
	["bloater",2,WastelandCreatureBrain.Action.RUPTURE,0.84,Vector3(1.5,1.34,-2.9),1.10,36.0,"湿原 · 爆裂前张臂"]]
const LIMB_SHOTS:=[
	["spitter",0,WastelandCreatureBrain.Action.NONE,0.0,Vector3(-1.05,1.17,-3.0),1.11,37.0,"左前臂残缺 · 站立追击"],
	["bloater",1,WastelandCreatureBrain.Action.NONE,0.0,Vector3(-1.34,1.03,-3.35),0.82,36.0,"右手、左脚缺失 · 跛行"],
	["spitter",2,WastelandCreatureBrain.Action.NONE,0.0,Vector3(2.70,1.53,-2.52),0.38,38.0,"双侧小腿、左手残缺 · 伏地爬行"]]

func run()->void:
	if DisplayServer.get_name()=="headless":
		printerr("Field capture requires a rendering device.")
		quit(1)
		return
	WastelandSave.root_override="user://verification/infected-field-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.seed=2817
	open_world({})
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(TILE.x,TILE.y+CAPTION)
	viewport.world_3d=root.world_3d
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera:=Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	var footer:=ColorRect.new()
	footer.color=Color("#26272c")
	footer.position.y=TILE.y
	footer.size=Vector2(TILE.x,CAPTION)
	viewport.add_child(footer)
	var title:=caption(footer,Vector2(14,2),24,Color("#e9dbc5"))
	var action:=caption(footer,Vector2(14,34),16,Color("#aabdb8"))
	session.player.hide()
	var civilian:bool="--civilian" in OS.get_cmdline_user_args()
	var limbs:bool="--limbs" in OS.get_cmdline_user_args()
	var shots:=LIMB_SHOTS if limbs else CIVILIAN_SHOTS if civilian else SHOTS
	var strip:=Image.create_empty(TILE.x*3,(TILE.y+CAPTION)*ceili(shots.size()/3.0),false,Image.FORMAT_RGB8)
	for index in shots.size():
		var shot:Array=shots[index]
		var kind:String=shot[0]
		var at:=field_position(kind)
		if not at.is_finite():
			check(false,"find terrain for "+kind)
			break
		if kind=="sandrunner": at+=Vector3(4.8,0,-3.0)
		session.stream.refresh(at,2)
		for dx in range(-1,2):
			for dz in range(-1,2):
				session.stream.ensure_landing(at+Vector3(dx,0,dz)*WastelandTerrainGen.SIZE)
		at.y=session.stream.ground_at(at)
		var appearance:={"look_index":shot[1],"limb_index":0,"wardrobe_index":0}
		if limbs:
			# Use the ordinary per-individual wear and injury draw for these examples.
			var desired:int=[2,12,73][index]
			var serial:=1
			while WastelandCreature.InfectedLimbs.roll(int(config.seed),serial)!=desired: serial+=1
			appearance={"look_index":shot[1],"serial":serial}
		if not session.hordes._spawn(kind,at,false,appearance):
			check(false,"spawn "+kind)
			break
		var actor:WastelandCreature=session.hordes.alive.back()
		actor.rotation.y=0.15 if civilian or limbs else [1.32,-1.10,0.23][index]
		actor.pose_phase=0.65
		actor.alerted=true
		actor.windup=shot[3]
		actor.attack_kind=shot[2]
		actor.velocity=Vector3.FORWARD*(1.5 if limbs else 2.5 if kind=="sandrunner" else 0.16)
		actor._pose(0.12,3.0)
		camera.position=at+actor.basis*Vector3(shot[4])
		camera.fov=shot[6]
		camera.look_at(at+Vector3.UP*float(shot[5]))
		if kind=="bloater":
			camera.look_at(at+Vector3.UP*float(shot[5])+camera.basis.x*0.075)
		session.clock.hours=12.5 if civilian or limbs else [15.7,15.0,12.0][index]
		session.atmosphere.sync(session.clock,0,camera.position,-camera.basis.z)
		title.text="%s　%s"%[actor.spec.name,LOOKS.title(kind,actor.look_index)]
		action.text=shot[7]
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var tile:=viewport.get_texture().get_image()
		tile.convert(Image.FORMAT_RGB8)
		strip.blit_rect(tile,Rect2i(Vector2i.ZERO,tile.get_size()),Vector2i(TILE.x*(index%3),tile.get_height()*floori(index/3.0)))
		print(kind," look=",actor.look_index," serial=",actor.spawn_serial," limbs=",actor.limb_index,
			" at=",at," region=",session.stream.generator.region_kind(at.x,at.z))
		session.hordes.release(actor)
	if failures==0:
		DirAccess.make_dir_recursive_absolute("res://build/qa")
		var file:="infected-field-limbs.png" if limbs else "infected-field-civilians.png" if civilian else "infected-field-looks.png"
		check(strip.save_png("res://build/qa/"+file)==OK,"save field portraits")
	viewport.queue_free()
	await close_world()
	quit(1 if failures else 0)

func caption(parent:Control,at:Vector2,font_size:int,color:Color)->Label:
	var label:=Label.new()
	label.position=at
	label.add_theme_font_override("font",WastelandUIStyle.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func field_position(kind:String)->Vector3:
	if kind in ["bloater","spitter"]:
		return session.player.global_position+Vector3(4,0,-4)
	var origin:=habitat(kind)
	if not origin.is_finite(): return Vector3.INF
	var gen:=session.stream.generator
	var region:String=session.catalog.enemies[kind].ecology.region
	for z in range(-72,73,4):
		for x in range(-72,73,4):
			var at:=origin+Vector3(x,0,z)
			at.y=gen.ground(at.x,at.z)
			if at.y<1 or gen.region_kind(at.x,at.z)!=region: continue
			if kind=="rimecaller" and gen.snow_cover(at.x,at.z,at.y)<0.55: continue
			if absf(gen.ground(at.x+1,at.z)-at.y)>0.18 or absf(gen.ground(at.x,at.z+1)-at.y)>0.18: continue
			return at
	return origin
