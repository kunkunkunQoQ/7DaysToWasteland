extends "res://tools/verify_avatar_ui.gd"

const Looks:=preload("res://game/art/infected_looks.gd")
const Picker:=preload("res://game/ui/infected_look_picker.gd")
const KINDS:=["spitter","bloater","bulwark","rimecaller","sandrunner"]
var pictures: Array[Image]=[]

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	WastelandSave.root_override="user://verification/infected-gallery-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await frames()
	app.front.atlas()
	var atlas=app.front.shell.find_child("TitleAtlas",true,false)
	atlas.choose_category("creatures")
	await frames()
	for id: String in KINDS:
		var entry:int=atlas.entries.find_custom(func(row): return row.id==id)
		var row_button:Button=atlas.buttons[entry]
		atlas.list_scroll.ensure_control_visible(row_button)
		await frames()
		await click(row_button)
		var picker:=atlas.detail.get_node_or_null("LookPicker") as Picker
		check(picker!=null and picker.actor.type==id,"open "+id+" from the title list")
		if picker==null: continue
		var stage:=picker.actor.get_parent() as SubViewport
		var full_span:=stage.get_camera_3d().size
		atlas.detail_scroll.ensure_control_visible(picker.zoom)
		await frames()
		await click(picker.zoom)
		check(stage.get_camera_3d().size<full_span*0.7,id+" can be inspected up close")
		var print_start:=pictures.size()
		for index in Looks.count_for(id):
			var choice:=button(picker,Looks.title(id,index))
			atlas.detail_scroll.ensure_control_visible(choice)
			await frames()
			await click(choice)
			check(picker.actor.look_index==index and choice.button_pressed and picker.description.text==Looks.description(id,index),id+" selects "+choice.text)
			if DisplayServer.get_name()!="headless":
				picker.actor.pose_phase=0
				picker.actor._pose(0.1,5)
				await frames(2)
				await RenderingServer.frame_post_draw
				var photo:=stage.get_texture().get_image()
				var extent:=mini(photo.get_height(),photo.get_width())
				var tile:=photo.get_region(Rect2i((photo.get_width()-extent)/2,(photo.get_height()-extent)/2,extent,extent))
				tile.resize(180,180,Image.INTERPOLATE_LANCZOS)
				for earlier in range(print_start,pictures.size()):
					check(different_outline(pictures[earlier],tile),id+" outline differs between %d and %d"%[earlier-print_start,index])
				pictures.append(tile)
		var turn:=button(picker,"转身")
		var yaw:=picker.actor.rotation.y
		await click(turn)
		check(absf(angle_difference(yaw,picker.actor.rotation.y))>1.4,id+" can be inspected from the side")
		await click(picker.zoom)
		check(is_equal_approx(stage.get_camera_3d().size,full_span),id+" restores full-body framing")
		var armor_index:int=atlas.entries.find_custom(func(row): return row.id==id+"_armored")
		atlas.list_scroll.ensure_control_visible(atlas.buttons[armor_index])
		await frames()
		await click(atlas.buttons[armor_index])
		picker=atlas.detail.get_node_or_null("LookPicker") as Picker
		check(picker!=null and picker.actor.morph=="armored" and picker.actor.look_index==2,id+" keeps its finish on armored form")
	if "--capture" in OS.get_cmdline_user_args() and pictures.size()==KINDS.size()*3:
		await save_sheet()
	for id: String in WastelandHordes.KINDS:
		var entry: int=atlas.entries.find_custom(func(row): return row.id==id)
		atlas.list_scroll.ensure_control_visible(atlas.buttons[entry])
		await frames()
		await click(atlas.buttons[entry])
		var picker:=atlas.detail.get_node("LookPicker") as Picker
		var shuffle:=button(picker,"换个体")
		atlas.detail_scroll.ensure_control_visible(shuffle)
		await frames()
		var original:=picker.appearance()
		await click(shuffle)
		var sample:=picker.appearance()
		check(sample.y!=original.y and picker.condition.text.contains("生命上限 %d"%roundi(picker.actor.max_health())),id+" rolls a dressed individual and shows its actual condition")
		var variant: int=atlas.entries.find_custom(func(row): return row.id==id+"_swift")
		atlas.list_scroll.ensure_control_visible(atlas.buttons[variant])
		await frames()
		await click(atlas.buttons[variant])
		picker=atlas.detail.get_node("LookPicker") as Picker
		check(picker.appearance()==sample,id+" preserves clothes and limbs when comparing forms")
	app._enter_world(app._default_config(),{},1,false)
	app.open_panel("field")
	await frames()
	var guide=app.panels.body.find_children("*","",false,false).filter(func(node): return node.get_script()==preload("res://game/ui/field_guide.gd")).front()
	await click(button(guide,"感染者"))
	var species:=button(guide.list,app.catalog.enemies.bloater.name)
	guide.list.get_parent().ensure_control_visible(species)
	await frames()
	await click(species)
	var field_choice:=button(guide.details,Looks.title("bloater",1))
	guide.details.get_parent().ensure_control_visible(field_choice)
	await frames()
	await click(field_choice)
	check(guide.preview_actor.look_index==1,"field journal swaps the live model")
	var swift:=button(guide.details,guide.FORMS.swift)
	guide.details.get_parent().ensure_control_visible(swift)
	await frames()
	await click(swift)
	check(guide.preview_actor.morph=="swift" and guide.preview_actor.look_index==1,"field journal retains appearance while changing morphology")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.queue_free()
	await frames(5)
	print("INFECTED GALLERY failures=",fails)
	quit(1 if fails else 0)

func different_outline(a:Image,b:Image)->bool:
	var first_bg:=a.get_pixel(0,0)
	var second_bg:=b.get_pixel(0,0)
	var either:=0
	var changed:=0
	for y in a.get_height():
		for x in a.get_width():
			var first:bool=a.get_pixel(x,y)!=first_bg
			var second:bool=b.get_pixel(x,y)!=second_bg
			if first or second: either+=1
			if first!=second: changed+=1
	return either>0 and changed>either*0.018

func save_sheet()->void:
	var sheet:=SubViewport.new()
	sheet.size=Vector2i(798,1062)
	sheet.disable_3d=true
	root.add_child(sheet)
	var canvas:=ColorRect.new()
	canvas.size=sheet.size
	canvas.color=Color("#182724")
	sheet.add_child(canvas)
	for row in KINDS.size():
		var id:String=KINDS[row]
		var species:=WastelandUIStyle.label(app.catalog.enemies[id].name,20,WastelandUIStyle.TEXT)
		species.position=Vector2(15,row*210+95)
		species.add_theme_font_override("font",WastelandUIStyle.FONT)
		canvas.add_child(species)
		for index in 3:
			var corner:=Vector2(163+index*210,6+row*210)
			var portrait:=TextureRect.new()
			portrait.texture=ImageTexture.create_from_image(pictures[row*3+index])
			portrait.position=corner
			canvas.add_child(portrait)
			var label:=WastelandUIStyle.label(Looks.title(id,index),16,WastelandUIStyle.GOLD)
			label.position=corner+Vector2(0,178)
			label.size.x=180
			label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_override("font",WastelandUIStyle.FONT)
			canvas.add_child(label)
	sheet.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	await frames(3)
	await RenderingServer.frame_post_draw
	var path:="res://build/qa/infected-looks.png"
	check(sheet.get_texture().get_image().save_png(path)==OK,"save fifteen in-engine model views")
	sheet.queue_free()
