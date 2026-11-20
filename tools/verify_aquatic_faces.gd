extends "res://tools/verify_avatar_ui.gd"

const Faces:=preload("res://game/art/species_faces.gd")
const FaceSelector:=preload("res://game/ui/face_selector.gd")
const Stage:=preload("res://game/ui/model_study.gd")
const April:=preload("res://game/art/april_face.gd")
const PHOTO_SIZE:=208
var portraits:Dictionary={}

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	WastelandSave.root_override="user://verification/water-faces-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await frames()
	app.front.atlas()
	var atlas=app.front.shell.find_child("TitleAtlas",true,false)
	atlas.choose_category("creatures")
	await frames()
	var hashes:={}
	for id:String in Faces.AQUATIC:
		var sheet:=load("res://assets/creature_faces/%s.png"%id) as Texture2D
		var pixels:=sheet.get_image()
		check(pixels.get_size()==Vector2i(320,320),id+" has four imported faces")
		for form in 2:
			var morph: String=("" if form==0 else ("young" if id=="heron" else "local"))
			var key:=id+("_"+morph if form else "")
			var entry:int=atlas.entries.find_custom(func(row):return row.id==key)
			atlas.list_scroll.ensure_control_visible(atlas.buttons[entry])
			await frames()
			await click(atlas.buttons[entry])
			var picker:=atlas.detail.get_node("FaceSelector") as FaceSelector
			var head:=picker.model.get_node("SpeciesFace") as MeshInstance3D
			var stage:=picker.model.get_parent().get_parent() as Stage
			var camera:=stage.camera
			var target:=head.global_position
			camera.size=maxf(0.17,head.global_basis.get_scale().y*3.1)
			camera.position=target+Vector3(0.07,0.025,-0.7)
			camera.look_at(target)
			var photos:Array[Image]=[]
			for n in 2:
				var face:=picker.variant
				var hash_key:=hash(pixels.get_region(Rect2i(face*160,form*160,160,160)).get_data())
				hashes[hash_key]=true
				var material:=head.material_override as ShaderMaterial
				check(material.get_shader_parameter("face_atlas")==sheet and material.get_shader_parameter("face_rect").is_equal_approx(Vector4(face*0.5,form*0.5,0.5,0.5)),key+" face %d uses its own tile"%face)
				if DisplayServer.get_name()!="headless":
					if form==0 and "--capture" in OS.get_cmdline_user_args():
						var closeup:=camera.transform
						var closeup_size:=camera.size
						var basis:=picker.model.global_basis.orthonormalized()
						var focus:=target
						match id:
							"heron": focus+=basis*Vector3(0,-0.015,-0.105)
							"crayfish": focus+=basis*Vector3(0,0,-0.17)
						camera.size={"lake_fish":0.31,"heron":0.43,"pond_turtle":0.34,"crayfish":0.57}[id]*picker.model.global_basis.get_scale().y
						var angle:=Vector3(-0.19,0.12,-0.90) if id!="heron" else Vector3(-0.44,0.115,-0.90)
						if id=="crayfish": angle=Vector3(-0.06,0.43,-0.90)
						camera.position=focus+basis*angle
						camera.look_at(focus)
						await frames(3)
						await RenderingServer.frame_post_draw
						var frame:=stage.scene.get_texture().get_image()
						var side:=mini(frame.get_width(),frame.get_height())
						var square:=frame.get_region(Rect2i((frame.get_width()-side)/2,(frame.get_height()-side)/2,side,side))
						square.resize(PHOTO_SIZE,PHOTO_SIZE,Image.INTERPOLATE_LANCZOS)
						portraits[id+str(face)]=square
						camera.transform=closeup
						camera.size=closeup_size
					await frames()
					await RenderingServer.frame_post_draw
					var photo:=stage.scene.get_texture().get_image()
					var extent:=mini(photo.get_width(),photo.get_height())
					var tile:=photo.get_region(Rect2i((photo.get_width()-extent)/2,(photo.get_height()-extent)/2,extent,extent))
					tile.resize(132,132,Image.INTERPOLATE_BILINEAR)
					photos.append(tile)
				atlas.detail_scroll.ensure_control_visible(picker)
				await frames()
				await click(picker)
			if photos.size()==2:
				var changed:=0
				for y in 132:
					for x in 132:
						var a:=photos[0].get_pixel(x,y)
						var b:=photos[1].get_pixel(x,y)
						if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>0.025: changed+=1
				check(changed>132*132*0.035,key+" changes visible facial pixels in the live camera (%d)"%changed)
			April.set_enabled(true)
			check(picker.model.get_node("AprilFace").visible and not head.material_override.get_shader_parameter("face_enabled"),key+" switches to the April face")
			April.set_enabled(false)
			check(not picker.model.get_node("AprilFace").visible and head.material_override.get_shader_parameter("face_enabled"),key+" restores its own face")
	check(hashes.size()==16,"all sixteen generated aquatic tiles are different")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		check(portraits.size()==8,"both views of all four adult models captured")
		if portraits.size()==8: await save_comparison()
	app._enter_world(app._default_config(),{},1,false)
	var lake:WastelandLakeWildlife=app.session.stream.lake_wildlife
	var shown:=0
	for habitat in lake.habitats:
		check(habitat.face_slots.size()==lake.SCHOOL_SIZE and habitat.upper.has_node("SpeciesFace"),"shore bird and every school member have a face")
		for i in lake.SCHOOL_SIZE:
			var slot:Vector2i=habitat.face_slots[i]
			var batch:MultiMeshInstance3D=habitat.natural_faces[slot.x]
			var fish:=Transform3D(Basis(Vector3.UP,0.7),Vector3(i,2,1))
			lake._fish_pose(habitat,i,fish)
			if DisplayServer.get_name()!="headless":
				check(batch.multimesh.get_instance_transform(slot.y).origin.distance_to(fish*lake.FISH_SKULL)<0.002,"swimming fish and face align")
			check(slot.x==lake._face_at(habitat.fishes,"lake_fish",i),"school face is stable for the seed and member")
			shown+=1
	check(shown>0 and lake.bottom_life.all(func(animal):return animal.has_node("SpeciesFace")),"populated underwater habitats have generated faces")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.queue_free()
	await frames(5)
	print("AQUATIC FACES failures=",fails)
	quit(1 if fails else 0)

func save_comparison()->void:
	var sheet:=SubViewport.new()
	sheet.size=Vector2i(4*PHOTO_SIZE+5*10,2*PHOTO_SIZE+88)
	sheet.disable_3d=true
	root.add_child(sheet)
	var background:=ColorRect.new()
	background.color=Color("#202823")
	background.size=sheet.size
	sheet.add_child(background)
	for col in Faces.AQUATIC.size():
		var id:String=Faces.AQUATIC[col]
		var x:=10+col*(PHOTO_SIZE+10)
		var title:=WastelandUIStyle.label({"lake_fish":"湖鱼","heron":"灰鹭","pond_turtle":"泽龟","crayfish":"溪螯虾"}[id],20,Color("#e8dfce"))
		title.position=Vector2(x,5)
		background.add_child(title)
		for face in 2:
			var y:=37+face*(PHOTO_SIZE+28)
			var photo:=TextureRect.new()
			photo.texture=ImageTexture.create_from_image(portraits[id+str(face)])
			photo.position=Vector2(x,y)
			background.add_child(photo)
			var label:=WastelandUIStyle.label("面孔 A" if face==0 else "面孔 B",15,Color("#cbd2bd"))
			label.position=Vector2(x,y+PHOTO_SIZE+1)
			background.add_child(label)
	sheet.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	await frames(3)
	await RenderingServer.frame_post_draw
	check(sheet.get_texture().get_image().save_png("res://build/qa/aquatic-faces.png")==OK,"save aquatic face comparison")
	sheet.queue_free()
