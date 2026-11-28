extends SceneTree

var app:Node
var mobile:=false
var fails:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,msg:String)->void:
	if ok: print("PASS ",msg)
	else:
		fails+=1
		printerr("FAIL ",msg)

func frames(n:=4)->void:
	for i in n: await process_frame

func input_at(event:InputEvent,at:Vector2)->void:
	if not mobile:
		event.position=at
		root.push_input(event,true)
		return
	event.position=root.get_final_transform()*at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func move(at:Vector2,delta:=Vector2.ZERO,held:=false)->void:
	if mobile and held:
		var e:=InputEventScreenDrag.new()
		e.index=0
		e.relative=root.get_final_transform().basis_xform(delta)
		input_at(e,at)
	else:
		var e:=InputEventMouseMotion.new()
		e.relative=root.get_final_transform().basis_xform(delta)
		e.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0
		input_at(e,at)

func press(at:Vector2,down:bool)->void:
	if mobile:
		var e:=InputEventScreenTouch.new()
		e.index=0
		e.pressed=down
		input_at(e,at)
	else:
		var e:=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		e.pressed=down
		input_at(e,at)

func click(button:Control)->void:
	var point:=button.get_global_rect().get_center()
	press(point,true)
	await frames(2)
	press(point,false)
	await frames()

func button(parent:Node,caption:String)->Button:
	for candidate:Button in parent.find_children("*","Button",true,false):
		if candidate.text==caption: return candidate
	return null

func gear_item(grid:Control,id:String)->Control:
	for tile in grid.get_children():
		if tile.item==id: return tile
	return null

func drag_item(src:Control,dest:Control)->void:
	var a:=src.get_global_rect().get_center()
	var b:=dest.get_global_rect().get_center()
	move(a)
	press(a,true)
	await frames(3)
	var old:=a
	for i in range(1,10):
		var p:=a.lerp(b,i/9.0)
		move(p,p-old,true)
		old=p
		await frames(2)
	press(b,false)
	await frames(18)

func look(studio:Control,within:=false)->void:
	var box:=studio.get_global_rect()
	var base:=box.get_center()
	var lo:=base+Vector2(-220,-175)
	var hi:=base+Vector2(80,175)
	if within:
		lo=base-box.size*Vector2(0.29,0.31)
		hi=base+box.size*Vector2(0.29,0.31)
	if mobile:
		press(lo,true)
		move(lo,Vector2.ZERO,true)
	else: move(lo)
	await frames(18)
	var first:Vector3=studio.subject.neck.rotation
	move(hi,hi-lo,mobile)
	await frames(18)
	var second:Vector3=studio.subject.neck.rotation
	if mobile: press(hi,false)
	check(second.y>first.y+0.32 and second.x<first.x-0.25,"head follows horizontal and vertical "+("native finger" if mobile else "mouse")+" motion")

func shot(name:String)->void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/qa/"+name+".png"))

func run()->void:
	mobile="--touch-controls" in OS.get_cmdline_user_args()
	WastelandSave.root_override="user://verification/avatar-ui-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.save_root()+"/options.cfg"
	root.add_child(app)
	await frames(8)
	var scenic:int=app.front.landscape_index
	var character:Control=app.front.shell.get_node("TitleSurvivor")
	check(character.get_global_rect().get_center().x>root.get_visible_rect().size.x*0.72,"title survivor resides on the right")
	await look(character.get_child(0))
	if not mobile:
		move(character.get_global_rect().get_center()+Vector2(-44,-160))
		await frames(12)
		await shot("avatar-title-16x9")
	await click(button(character,"更衣库"))
	check(app.front.screen=="wardrobe","wardrobe opens by real pointer")
	if app.front.screen!="wardrobe": quit(1);return
	var pick:OptionButton=app.front.shell.find_child("OutfitPicker",true,false)
	await click(pick)
	var popup:=pick.get_popup()
	check(popup.visible,"real outfit chooser opens")
	var target:=2
	var choice:=Vector2(popup.size.x*0.5,popup.size.y*(target+0.5)/pick.item_count)
	var physical:=Vector2(popup.position)+choice
	var local:=physical if popup.is_embedded() else root.get_final_transform().affine_inverse()*physical
	move(local)
	await frames(3)
	press(local,true)
	await frames(3)
	press(local,false)
	await frames()
	check(app.options.appearance=="surveyor","choosing a different survivor persists")
	app.front.nickname_input.text = "山海旅人"
	await click(button(app.front.shell,"返回开始页"))
	character=app.front.shell.get_node("TitleSurvivor")
	check(character.get_child(1).text=="山海旅人","title portrait shows the player's edited nickname after changing outfits")
	for open:String in ["荒原图鉴","系统设置","存档管理"]:
		await click(button(app.front.shell,open))
		if open=="荒原图鉴":
			var atlas:Control=app.front.shell.find_child("TitleAtlas",true,false)
			await click(atlas.tabs.get_node("characters"))
			await click(atlas.buttons[2])
			var stage:Control=atlas.detail.find_children("*","SubViewportContainer",true,false)[0]
			check(stage.subject.outfit==atlas.entries[2].id,"selected atlas character drives its own 3D portrait")
			for framing:String in ["面部","半身"]:
				var zoom:=button(atlas.detail,framing)
				zoom.grab_focus()
				await frames()
				await click(zoom)
				check(stage.portrait_zoom==framing,"character atlas framing "+framing)
				await look(stage,true)
		var back:Button=button(app.front.shell,"保存设置并返回" if open=="系统设置" else "返回主菜单")
		await click(back)
		check(app.front.screen=="title" and app.front.landscape_index==scenic,"return from "+open+" preserves title landscape")
	character=app.front.shell.get_node("TitleSurvivor")
	check(character.get_child(0).subject.outfit==app.options.appearance,"title actor uses chosen outfit")
	await click(button(app.front.shell,"进入新世界   ›"))
	await click(button(app.front.shell,"进入荒原"))
	for i in 100:
		if app.session and not app.session.preview_only: break
		await process_frame
	var session:WastelandSession=app.session
	for id:String in ["stone_axe","hardhat","canvas_pants","canvas_pack","expedition_pack","torch","clean_water","wood","fiber","stone","scrap","bandage","berries","spring","cloth"]:
		session.bag.add(id,1,WastelandBag.PACK)
	if mobile:
		var controls:Control=app.hud.get_node("TouchControls")
		var at:Vector2=controls.layout.inventory.get_center()
		press(at,true)
		await frames(2)
		press(at,false)
	else:
		var key:=InputEventKey.new()
		key.physical_keycode=KEY_TAB
		key.keycode=KEY_TAB
		key.pressed=true
		Input.parse_input_event(key)
		await frames(2)
		key=key.duplicate()
		key.pressed=false
		Input.parse_input_event(key)
	await frames(8)
	check(app.panels.active=="bag" and app.panels.visible,"normal gameplay inventory control opens backpack")
	var panels:WastelandPanels=app.panels
	var grid:=panels.item_grid
	var bar:=panels.quick_slots
	var studio:Control=panels.content.find_child("BagSurvivor",true,false)
	check(grid.columns==9 and grid.get_child_count()==27 and bar.get_child_count()==8,"baseline has 27 inventory cells in three rows and eight quick slots")
	check(studio.global_position.x>grid.get_global_rect().end.x and root.get_visible_rect().encloses(panels.content.get_global_rect()),"avatar is right of inventory and panel fits viewport")
	if not mobile: await shot("avatar-bag-16x9")
	var pack:Control=panels.content.find_child("Slot_pack",true,false)
	check(pack.item=="" and not session.bag.gear.has("pack"),"new survivor starts without backpack")
	for candidate:String in ["canvas_pack","expedition_pack"]:
		await click(gear_item(grid,candidate))
		await click(pack)
		await frames(18)
		var capacity:=36 if candidate=="canvas_pack" else 45
		check(pack.item==candidate and grid.get_child_count()==capacity and session.bag.capacity()==capacity,"equipped "+candidate+" exposes "+str(capacity)+" cells")
	await click(button(panels.content,"使用／装备所选"))
	await frames(18)
	check(pack.item=="" and grid.get_child_count()==27,"removing pack restores three rows")
	var axe:Control
	var hat:Control
	for tile in grid.get_children():
		if tile.item=="stone_axe": axe=tile
	await drag_item(axe,bar.get_child(5))
	check(session.bag.bar[5]=="stone_axe","drag tool onto quick slot six binds it")
	for tile in grid.get_children():
		if tile.item=="hardhat": hat=tile
	var head:Control=panels.content.find_child("Slot_head",true,false)
	await drag_item(hat,head)
	check(session.bag.gear.head=="hardhat","drag hardhat onto head equipment")
	var helmet:MeshInstance3D
	for piece in studio.subject.sleeves:
		if is_instance_valid(piece) and studio.subject.skull.is_ancestor_of(piece): helmet=piece
	var before:Basis
	if helmet: before=helmet.global_basis
	await look(studio)
	check(is_instance_valid(helmet) and not before.is_equal_approx(helmet.global_basis),"equipped helmet turns with articulated head")
	var armor:Control=panels.content.find_child("EquipmentSlots",true,false)
	var extras:Control=panels.content.find_child("AccessorySlots",true,false)
	var hand:Control=panels.content.find_child("Slot_offhand",true,false)
	check(armor.get_child_count()==4 and extras.get_child_count()==4 and armor.get_child(0).get_meta("slot")=="head" and armor.get_child(2).get_meta("slot")=="legs" and hand.item=="","four armor silhouettes, four accessories and empty independent offhand")
	var stage:Control=panels.content.find_child("AvatarEquipmentStage",true,false)
	check(stage.get_global_rect().encloses(armor.get_global_rect()) and stage.get_global_rect().encloses(hand.get_global_rect()) and armor.get_global_rect().end.x<=studio.global_position.x and extras.global_position.x>=studio.get_global_rect().end.x,"both slot columns frame the survivor inside the same portrait panel")
	check(absf(hand.global_position.x-armor.get_child(0).global_position.x)<1 and hand.global_position.y>armor.get_child(3).get_global_rect().end.y and pack.global_position.x>=studio.get_global_rect().end.x,"offhand is directly below boots, pack remains on the accessory side")
	for i in range(1,4): check(armor.get_child(i).global_position.y>=armor.get_child(i-1).get_global_rect().end.y,"armor row %d does not overlap"%i)
	await click(gear_item(grid,"canvas_pants"))
	await click(armor.get_child(2))
	await frames(16)
	check(session.bag.gear.get("legs","")=="canvas_pants","tap item then matching trousers slot equips")
	await click(gear_item(grid,"fiber"))
	await click(hand)
	await frames(16)
	check(session.bag.offhand=="fiber" and studio.subject.offhand_id=="fiber","ordinary material assigned to offhand via two taps")
	await click(button(panels.content,"移出副手"))
	await frames(16)
	check(session.bag.offhand=="" and hand.item=="","clear offhand restores empty shield illustration")
	await click(bar.get_child(5))
	await frames(16)
	await drag_item(gear_item(grid,"torch"),hand)
	check(session.bag.offhand=="torch" and studio.subject.preview_mainhand=="stone_axe","drag torch onto independent slot retains mainhand axe")
	await click(button(panels.content,"交换双手"))
	await frames(16)
	check(session.bag.offhand=="stone_axe" and session.bag.current()=="torch" and studio.subject.preview_mainhand=="torch" and studio.subject.offhand_id=="stone_axe","swap updates inventory and both hands of actual model")
	await click(button(panels.content,"交换双手"))
	await frames(16)
	check(root.get_visible_rect().encloses(panels.content.get_global_rect()) and not studio.get_global_rect().intersects(hand.get_global_rect()),"full equipment panel and standalone shield slot fit without overlap")
	if mobile:
		var at:=studio.get_global_rect().get_center()+Vector2(-48,-80)
		press(at,true)
		await frames(12)
		press(at,false)
		await shot("avatar-bag-20x9")
	var prior:=session.bag.snapshot()
	session.bag.restore({"counts":{"wood":session.bag.stack_size("wood")*31}})
	await frames(18)
	check(grid.get_child_count()==31 and session.bag.capacity()==27 and panels.bag_list.get_meta("count_label").text.contains("超量"),"legacy excess remains visible above current capacity")
	session.bag.spend({"wood":session.bag.stack_size("wood")*6})
	await frames(18)
	check(grid.get_child_count()==27,"three rows return after excess is removed")
	session.bag.restore(prior)
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.queue_free()
	await frames(2)
	quit(1 if fails else 0)
