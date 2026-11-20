extends SceneTree

const Art:=preload("res://game/art/offhand_art.gd")
var failures:=0
var windows:Array[SubViewport]=[]

func _initialize()->void: run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1

func view()->Camera3D:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(640,390)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera:=Camera3D.new()
	camera.fov=68
	camera.environment=Environment.new()
	camera.environment.background_mode=Environment.BG_COLOR
	camera.environment.background_color=Color("#38444c")
	camera.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	camera.environment.ambient_light_color=Color.WHITE
	camera.environment.ambient_light_energy=1.1
	viewport.add_child(camera)
	var lamp:=DirectionalLight3D.new()
	viewport.add_child(lamp)
	lamp.rotation=Vector3(-0.7,-0.5,0)
	camera.make_current()
	windows.append(viewport)
	return camera

func run()->void:
	var catalog:=WastelandCatalog.new()
	var last_shield_icon:=PackedByteArray()
	for id:String in ["torch","improvised_shield","dented_shield","cracked_shield","stone"]:
		var camera:=view()
		var hand:=WastelandHands.new()
		camera.add_child(hand)
		hand.hold("stone_axe",catalog.items.get("stone_axe",{}))
		hand.set_offhand(id,false,true)
		if not check_prop(hand,id): continue
		hand.animate(0.3,0,0,1,0)
		var lowered:=hand.offhand_root.position.y
		hand.set_offhand(id,true,true)
		hand.animate(0.3,0,0,1,0)
		if id.ends_with("shield"):
			var bounds:=hand.offhand_prop.mesh.get_aabb().size
			check(bounds.x>0.69 and bounds.y>0.94 and bounds.z<0.21,"torso-sized shield geometry "+id)
			check(hand.offhand_root.position.y>lowered+0.12,"guard raises "+id)
			var left_arm:=hand.offhand_root.get_child(0) as MeshInstance3D
			var grip_center:=left_arm.to_global(Vector3(0.102,-0.010,-0.285))
			check(hand.offhand_prop.global_position.distance_to(grip_center)<0.003,"wrapped grip centered in curled fingers "+id)
			var icon:=WastelandItemArt.icon(id,catalog.items[id]).get_image()
			check(icon.get_used_rect().size.x>=20 and icon.get_data()!=last_shield_icon,"readable and distinct shield wear icon "+id)
			last_shield_icon=icon.get_data()
		if id=="torch":
			Art.sync_world_light(camera,id,true)
			Art.sync_world_light(camera,id,false)
			check(not camera.get_node("OffhandLanternLight").visible,"world lighting follows lantern switch")
		var portrait_camera:=view()
		var avatar:=WastelandPartyAvatar.new()
		avatar.show_tag=false
		portrait_camera.get_parent().add_child(avatar)
		avatar.set_mainhand("stone_axe")
		avatar.set_offhand(id,true,true)
		avatar.pose(0.4,0,0)
		check(avatar.offhand_prop.mesh==hand.offhand_prop.mesh and avatar.left_curled.visible,"same actual item mesh follows avatar's curled left grip: "+id)
		avatar.apply_outfit("bronx")
		avatar.pose(0.4,2,0)
		check(avatar.offhand_prop.get_parent()==avatar.left_grip,"changing appearance recreates left grip: "+id)
		if id.ends_with("shield"):
			check(avatar.offhand_prop.global_position.distance_to(avatar.left_grip.global_position)<0.003,"third person grip meets the wrist socket "+id)
			var guarded:=avatar.offhand_prop.global_transform*avatar.offhand_prop.mesh.get_aabb()
			check(guarded.position.y<0.90 and guarded.end.y>1.50 and guarded.end.y<1.83,"raised shield covers hips and chest "+id)
		portrait_camera.fov=45
		portrait_camera.position=Vector3(-0.73,1.32,-2.48)
		portrait_camera.look_at(Vector3(0,1.0,0))
		if id=="torch":
			check(avatar.left_grip.get_node("OffhandLanternLight").visible,"remote lantern emits warm light")
		hand.hold("rifle",catalog.items.rifle)
		check(not hand.support_arm.visible,"two-handed weapon releases occupied supporting hand")
		hand.hold("stone_axe",catalog.items.get("stone_axe",{}))
		hand.animate(0.3,0,0,1,0)
	if DisplayServer.get_name()!="headless" and windows.size()==10:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var sheet:=Image.create(1280,1560,false,Image.FORMAT_RGB8)
		for i in 8:
			var img:=windows[i].get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),Vector2i(i%2,int(i/2))*img.get_size())
		check(sheet.save_png("res://build/qa/offhand-poses.png")==OK,"capture first and third person offhand models")
	print("OFFHAND ART failures=",failures)
	quit(1 if failures else 0)

func check_prop(hand:WastelandHands,id:String)->bool:
	var present:=is_instance_valid(hand.offhand_prop) and hand.offhand_prop.mesh!=null
	check(present,"main tool and offhand "+id+" coexist")
	return present
