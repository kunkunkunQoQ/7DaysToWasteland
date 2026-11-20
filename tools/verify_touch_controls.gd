extends SceneTree
var game: Node
var pad: Control
var failures:=0
var passed:=0
func _initialize()->void: run.call_deferred()
func check(result:bool,title:String)->void:
	if result: passed+=1
	else: failures+=1
	print("PASS " if result else "FAIL ",title)
func tap(index:int,pos:Vector2,pressed:bool,canceled:=false)->void:
	var e:=InputEventScreenTouch.new()
	e.index=index
	e.position=pos
	e.pressed=pressed
	e.canceled=canceled
	root.push_input(e,true)
func drag(index:int,a:Vector2,b:Vector2)->void:
	var e:=InputEventScreenDrag.new()
	e.index=index
	e.position=b
	e.relative=b-a
	root.push_input(e,true)
func button(id:String)->Vector2:return pad.layout[id].get_center()
func toggle_more()->void:
	var at:=button("more")
	tap(7,at,true)
	tap(7,at,false)
func hold_more(at:Vector2,action:String)->bool:
	tap(1,at,true)
	var deadline:=Time.get_ticks_msec()+4000
	while not pad.wheel_open and Time.get_ticks_msec()<deadline:
		await process_frame
	if pad.wheel_open and pad.wheel_targets.has(action): return true
	check(false,"long press expected "+action+"; got "+str(pad.wheel_targets.keys())+" in "+str(pad.wheel_title))
	tap(1,at,false,true)
	await finish()
	return false

func finish()->void:
	game.session.simulation_paused=true
	await game.session.stream.quiesce()
	await game.session.audio.finish_playback()
	print("TOUCH QA passed=",passed," failed=",failures)
	quit(1 if failures else 0)

func run()->void:
	WastelandSave.root_override="user://verification/touch-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	game=load("res://main.tscn").instantiate()
	game.options.storage_path=WastelandSave.root_override+"/test-options.cfg"
	root.add_child(game)
	await process_frame
	var cfg:Dictionary=game._default_config()
	cfg.seed=2817
	cfg.spawn_roll=8031
	game._enter_world(cfg,{},1,false)
	game.close_overlay()
	for child in game.hud.get_children():
		if child.get_script()==preload("res://game/ui/touch_controls.gd"): pad=child
	if not pad:
		pad=preload("res://game/ui/touch_controls.gd").new()
		pad.setup(game)
		game.hud.add_child(pad)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await process_frame
	check(game.options.action_name("fire")=="主动作" and game.options.action_name("reload")=="装填" and game.session.localized_prompt("[{action/use}]")=="[交互]","local and network prompts identify touch controls")
	await crafting_test()
	await first_axe_touch()
	# The rest of the control suite needs a safe, reproducible coastal fixture.
	cfg.terrain_revision=2
	game._enter_world(cfg,{},1,false)
	game.close_overlay()
	await physics_frame
	var joy:Vector2=pad._pad_center()
	await sprint_gestures()
	check(pad.layout.size()==7 and not pad.layout.has("discard") and not pad.layout.has("map"),"unarmed field layout has seven buttons before opening More")
	var look:=Vector2(750,320)
	var start:Vector3=game.session.player.position
	tap(0,joy,true)
	drag(0,joy,joy+Vector2(0,-58))
	tap(1,look,true)
	var yaw:float=game.session.player.rotation.y
	drag(1,look,look+Vector2(90,0))
	tap(2,button("fire"),true)
	for i in 48: await physics_frame
	check(game.session.player.position.distance_to(start)>0.3 and Input.is_action_pressed("up"),"actual player moves while fire and look are held")
	check(absf(game.session.player.rotation.y-yaw)>0.03 and game.session.player.hand.swing_serial>0,"camera drag and held attack reach player")
	tap(3,button("fire"),true)
	tap(2,button("fire"),false)
	check(Input.is_action_pressed("fire"),"lifting one of two fire fingers preserves other")
	tap(3,button("fire"),false,true)
	check(not Input.is_action_pressed("fire"),"canceled finger releases held attack")
	tap(0,joy,false)
	tap(1,look,false)
	var slot:=Vector2(pad.size.x*0.5+80,pad.size.y-55)
	tap(5,slot,true)
	tap(5,slot,false)
	await physics_frame
	await physics_frame
	check(game.session.bag.active==5,"tap actual HUD slot 6")
	tap(5,slot,false)
	await combat_buttons()
	tap(1,button("fire"),true)
	tap(1,button("fire"),false)
	tap(2,button("fire"),true)
	tap(2,button("fire"),false)
	for tick in 4: await physics_frame
	check(not Input.is_action_pressed("fire"),"rapid fingers leave no unreleased source")
	tap(4,button("use"),true)
	await physics_frame
	check(Input.is_action_pressed("use"),"interact remains held for loot search")
	tap(7,button("inventory"),true)
	check(game.panels.visible and game.panels.active=="bag" and not Input.is_action_pressed("use"),"opening inventory clears remaining fingers")
	game.close_overlay()
	toggle_more()
	check(not pad.layout.more.intersects(pad.layout.swap_hands),"expanded swap hands target is separate from more")
	for id:String in ["reload","rotate","shape","flashlight","swap_hands"]:
		tap(4,button(id),true)
		check(Input.is_action_pressed(id),"expanded "+id)
		tap(4,button(id),false)
	tap(9,button("alternate"),true)
	tap(6,button("jump"),true)
	tap(2,button("sprint"),true)
	check(Input.is_action_pressed("alternate") and Input.is_action_pressed("jump") and Input.is_action_pressed("sprint"),"three simultaneous extra actions")
	root.focus_exited.emit()
	check(not Input.is_action_pressed("jump") and not Input.is_action_pressed("sprint") and not Input.is_action_pressed("alternate") and pad.fingers.is_empty(),"focus loss releases all actions")
	await physics_frame
	await physics_frame
	game.session.bag.add("frame",1)
	game.session.bag.assign("frame",0)
	game.session.bag.active=0
	var more:=button("more")
	tap(0,joy,true)
	drag(0,joy,joy+Vector2.RIGHT*44)
	if not await hold_more(more,"rotate"): return
	check(pad.wheel_open and pad.wheel_title=="建造" and pad.wheel_targets.has("rotate") and Input.is_action_pressed("right"),"holding more opens contextual build wheel without releasing joystick")
	var rotate:Vector2=pad.wheel_targets.rotate.get_center()
	var turn:int=game.session.turn
	tap(8,rotate,true)
	tap(8,rotate,false)
	check(pad.wheel_selected=="" and pad.wheel_open,"second finger cannot select wheel")
	drag(1,more,rotate)
	check(pad.wheel_selected=="rotate","highlight tracks selecting finger")
	tap(1,rotate,false)
	for tick in 5: await physics_frame
	check(game.session.turn!=turn and not pad.wheel_open and not Input.is_action_pressed("rotate"),"slide and release rotates actual building once")
	tap(0,joy,false)
	game.session.bag.add("bow",1)
	game.session.bag.assign("bow",0)
	if not await hold_more(more,"reload"): return
	check(pad.wheel_title=="远程" and pad.wheel_targets.has("reload"),"ranged tool wheel includes reload")
	var reload:Vector2=pad.wheel_targets.reload.get_center()
	drag(1,more,reload)
	drag(1,reload,more)
	tap(1,more,false)
	check(not pad.wheel_open and not Input.is_action_pressed("reload"),"dragging to blank area cancels")
	game.session.bag.assign("",0)
	if not await hold_more(more,"field"): return
	var field:Vector2=pad.wheel_targets.field.get_center()
	drag(1,more,field)
	tap(1,field,false)
	check(game.panels.active=="field" and game.panels.visible,"exploration wheel opens illustrated field guide")
	game.close_overlay()
	if not await hold_more(more,"field"): return
	root.focus_exited.emit()
	check(not pad.wheel_open and pad.wheel_finger<0,"focus loss dismisses wheel")
	toggle_more()
	tap(5,button("map"),true)
	check(game.panels.active=="map","map opens")
	game.close_overlay()
	tap(5,button("pause_game"),true)
	check(game.front.visible and not game.session.controls_enabled,"pause routes to game menu")
	await restart_with_touch_preferences(cfg)
	await finish()

func aim_ground(kinds:Array,origin:Vector3)->StaticBody3D:
	var s:WastelandSession=game.session
	var candidates:Array[StaticBody3D]=[]
	for chunk:WastelandChunk in s.stream.active.values():
		for body in chunk.decoration_root.get_children():
			if body is StaticBody3D and body.get_meta("resource","") in kinds and body.collision_layer!=0 and not body.is_queued_for_deletion():
				candidates.append(body)
	for id:String in s.fx.drop_live:
		for material:String in s.fx.drop_records[id].items:
			if material+"_drop" in kinds: candidates.append(s.fx.drop_live[id])
	candidates.sort_custom(func(a,b):return a.global_position.distance_squared_to(origin)<b.global_position.distance_squared_to(origin))
	for obj in candidates:
		if obj.global_position.distance_to(origin)>45: break
		var at:=obj.global_position
		for shape in obj.get_children():
			if shape is CollisionShape3D:
				at=shape.global_position
				break
		at.y=minf(at.y,s.stream.ground_at(at)+1.1)
		for side in 8:
			var p:=at+Vector3(sin(side*PI/4),0,cos(side*PI/4))*1.22
			p.y=s.stream.ground_at(p)+0.04
			s.player.global_position=p
			s.player.velocity=Vector3.ZERO
			var aim:=(at-s.player.camera.global_position).normalized()
			s.player.rotation.y=atan2(-aim.x,-aim.z)
			s.player.pitch=asin(aim.y)
			s.player.eyes.rotation.x=s.player.pitch
			if s._interaction_trace().get("collider")==obj and (obj.get_meta("kind","")=="drop" or s._trace(2.58,15,false,true).get("collider")==obj): return obj
	return null

func press_action(id:String,frames:=4)->void:
	var at:=button(id)
	tap(11,at,true)
	for i in frames: await physics_frame
	tap(11,at,false)
	for i in 3: await physics_frame

func tap_shortcut(index:int)->void:
	var bar:=WastelandHUD.quickbar_rect(pad.size)
	var point:=Vector2(bar.position.x+(index+0.5)*WastelandHUD.SLOT_STEP,bar.get_center().y)
	tap(5,point,true)
	for i in 2: await physics_frame
	tap(5,point,false)
	await physics_frame

func first_axe_touch()->void:
	var s:WastelandSession=game.session
	var origin:=s.player.global_position
	var initial:=s.player.health
	for pair:Array in [["fallen_stick","stick"],["pebble","stone"],["grass","fiber"]]:
		var required:=int(s.catalog.recipes.stone_axe.inputs.get(pair[1],0))
		for i in required:
			if not aim_ground([pair[0]],origin): break
			for tick in 2: await physics_frame
			if pair[0]=="grass":
				while s.action_lock>0: await physics_frame
				await press_action("fire",5)
				if s.bag.count("fiber")==i: aim_ground(["fiber_drop"],origin)
				for tick in 12: await physics_frame
				check(s.bag.count("fiber")>i,"nearby grass fiber is collected without tapping interact")
			else: await press_action("use")
		check(required>0 and s.bag.count(pair[1])>=required,"touch interaction gathers "+str(pair[1])+" near actual spawn")
	check(is_equal_approx(s.player.health,initial),"collecting all ground supplies preserves health")
	if s.bag.has_all(s.catalog.recipes.stone_axe.inputs):
		await press_action("inventory")
		click_button(game.panels,"制作")
		if click_button(game.panels,"制作 1 次"):
			game.close_overlay()
			for i in 180:
				if s.bag.count("stone_axe"): break
				await physics_frame
		game.close_overlay()
	check(s.bag.count("stone_axe")==1,"craft first axe through touchscreen-accessible bag panel")
	var axe_slot:=s.bag.bar.find("stone_axe")
	check(axe_slot>=0,"the crafted axe appears in the first available shortcut")
	await tap_shortcut(s.bag.bar.find(""))
	while s.action_lock>0: await physics_frame
	var trunk:=aim_ground(["oak","pine"],origin)
	if trunk:
		var attack:=button("fire")
		var facing:=s.player.rotation.y
		tap(11,attack,true)
		drag(11,attack,attack+Vector2(4,0))
		for i in 8: await physics_frame
		tap(11,attack,false)
		check(s.player.health<initial and absf(s.player.rotation.y-facing)>0.003,"bare fist hitting a tree costs health while attack finger can steer")
	else: check(false,"test world has a living tree for punching")
	if axe_slot>=0: await tap_shortcut(axe_slot)
	check(s.bag.current()=="stone_axe","touching its automatic shortcut equips the axe")
	var post_punch:=s.player.health
	var timber:=s.bag.count("wood")
	if trunk and s.bag.current()=="stone_axe":
		aim_ground(["oak","pine"],origin)
		for attempt in 7:
			if s.bag.count("wood")>timber: break
			while s.action_lock>0: await physics_frame
			if not aim_ground(["oak","pine"],origin): break
			await press_action("fire",6)
			for wait_frame in 420:
				if s.timber.active.is_empty(): break
				await physics_frame
			if s.bag.count("wood")==timber and aim_ground(["wood_drop"],s.player.global_position):
				for i in 12: await physics_frame
	check(s.bag.count("wood")>timber and s.player.health>=post_punch and not s.progress.records.has("first_axe_guide"),"new axe fells tree without further hand injury and finishes guidance")
	s.bag.assign("",s.bag.active)

func find_button(container:Node,caption:String,prefix:=false)->Button:
	for candidate:Button in container.find_children("*","Button",true,false):
		if (candidate.text.begins_with(caption) if prefix else candidate.text==caption) and candidate.is_visible_in_tree():
			return candidate
	return null

func click_button(container:Node,caption:String,prefix:=false)->bool:
	var target:=find_button(container,caption,prefix)
	if target==null or target.disabled: return false
	target.pressed.emit()
	return true

func crafting_test()->void:
	var panels:Control=game.panels
	var session:WastelandSession=game.session
	game.open_panel("craft")
	await process_frame
	check(session.bag.counts.is_empty() and click_button(panels,"材料齐全") and panels.recipe_list.find_children("*","Button",false,false).is_empty() and panels.selection=="","empty start has no affordable hand recipes")
	check(click_button(panels,"已收藏") and panels.recipe_list.find_children("*","Button",false,false).is_empty() and panels.favorite_button.disabled,"empty favorites have no selected recipe")
	click_button(panels,"全部")
	var title:=session.catalog.title("stone_axe")
	check(click_button(panels.recipe_list,title+" ×",true) and click_button(panels,"收藏配方"),"favorite stone axe using recipe panel")
	click_button(panels,"已收藏")
	check(panels.recipe_list.get_child_count()==1 and find_button(panels.recipe_list,title+" ×",true)!=null,"favorites filter lists only saved axe")
	game.close_overlay()
	game.options.favorite_recipes.clear()
	game.options.load_options()
	game.open_panel("craft")
	await process_frame
	click_button(panels,"已收藏")
	check(click_button(panels.recipe_list,title+" ×",true) and panels.favorite_button.text=="取消收藏","reopening and reading isolated settings restores favorite")
	click_button(panels,"材料齐全")
	var inputs:Dictionary=session.catalog.recipes.stone_axe.inputs
	for id:String in inputs: session.bag.add(id,inputs[id])
	await create_timer(0.40).timeout
	check(click_button(panels.recipe_list,title+" ×",true) and click_button(panels,"制作 1 次"),"affordable filter updates in place; craft through real button")
	check(session.bag.counts.is_empty() and session.hand_queue.size()==1 and session.hand_queue[0].id=="stone_axe","craft immediately debits exact ingredients and queues one stone axe")
	await create_timer(0.32).timeout
	check(panels.recipe_list.find_children("*","Button",false,false).is_empty(),"spent ingredients remove axe from affordable list")
	click_button(panels,"已收藏")
	click_button(panels.recipe_list,title+" ×",true)
	check(click_button(panels,"取消收藏") and panels.recipe_list.find_children("*","Button",false,false).is_empty(),"unfavorite immediately clears saved recipe list")
	game.options.load_options()
	check(not game.options.favorite_recipes.has("stone_axe"),"unfavorite persists on fresh options read")
	click_button(panels,"取消队尾")
	check(session.hand_queue.is_empty() and session.bag.has_all(inputs),"cancel queued craft returns all ingredients")
	session.bag.spend(inputs)
	game.close_overlay()
	await process_frame
func combat_buttons()->void:
	var s:WastelandSession=game.session
	s.bag.add("pistol",1)
	s.bag.add(s.catalog.items.pistol.ammo,4)
	s.bag.assign("pistol",s.bag.active)
	s.bag.add("improvised_shield",1)
	s.bag.set_offhand("improvised_shield")
	s.player.pitch=0.95
	s.player.eyes.rotation.x=s.player.pitch
	await create_timer(0.22).timeout
	check(pad.verbs.get("alternate")=="装填" and pad.verbs.get("fire")=="射击" and pad.verbs.get("offhand_use")=="举盾","ranged loadout labels match the available actions")
	check(pad.layout.size()==9,"pistol and shield add just two context buttons")
	tap(7,button("alternate"),true)
	for frame in 3: await physics_frame
	check(s.reload_id=="pistol" and s.player.hand.reload_ratio>0,"thumb-side button reloads through normal input")
	tap(7,button("alternate"),false)
	var from_button:=button("offhand_use")
	tap(8,from_button,true)
	var previous_yaw:=s.player.rotation.y
	drag(8,from_button,from_button+Vector2(45,0))
	for frame in 3: await physics_frame
	check(s.player.guarding and absf(previous_yaw-s.player.rotation.y)>0.025,"shield thumb can turn to face an incoming hit while holding guard")
	tap(8,from_button,false)
	var side:=WastelandHUD.offhand_rect(pad.size).get_center()
	tap(8,side,true)
	for frame in 3: await physics_frame
	check(s.player.guarding,"offhand quick slot raises the equipped shield")
	tap(8,side,false)
	s.bag.set_offhand("")
	s.bag.assign("",s.bag.active)
	tap(8,side,true)
	check(game.panels.visible and game.panels.active=="bag","empty offhand quick slot opens equipment")
	tap(8,side,false)
	game.close_overlay()
	s.player.pitch=0.0
	s.player.eyes.rotation.x=0.0

func sprint_gestures()->void:
	for left_handed:bool in [false,true]:
		game.options.touch_left_handed=left_handed
		game.options.touch_control_scale=1.12 if left_handed else 1.0
		game.options.save_options()
		var restored:=WastelandSettings.new()
		restored.storage_path=game.options.storage_path
		restored.load_options()
		check(restored.touch_left_handed==left_handed and is_equal_approx(restored.touch_control_scale,game.options.touch_control_scale),"fresh settings instance restores touch scale and handedness")
		pad._layout()
		var p:Vector2=pad._pad_center()
		var front:=Vector2.UP*54*float(pad.scale_unit)
		tap(4,p,true)
		drag(4,p,p+front)
		check(not Input.is_action_pressed("sprint"),"single forward push walks")
		tap(4,p+front,false)
		tap(5,p,true)
		drag(5,p,p+Vector2.UP*3)
		check(not Input.is_action_pressed("sprint"),"second thumb contact in deadzone stays walking")
		drag(5,p+Vector2.UP*3,p+front)
		var look:Vector2=pad.bounds.get_center()+Vector2(-60 if left_handed else 60,10)
		tap(6,look,true)
		drag(6,look,look+Vector2.RIGHT*36)
		tap(7,button("jump"),true)
		tap(8,button("fire"),true)
		check(game.session.action_held("sprint") and Input.is_action_pressed("up") and Input.is_action_pressed("jump") and Input.is_action_pressed("fire"),"double push sprints with independent look jump and attack")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/qa")
			root.get_texture().get_image().save_png("res://build/qa/touch-sprint-%s.png"%("left" if left_handed else "right"))
		drag(5,p+front,p+Vector2.RIGHT*55)
		check(not Input.is_action_pressed("sprint"),"turning thumb sideways ends sprint")
		pad.release_all()
		tap(4,p,true)
		tap(4,p,false)
		tap(7,button("jump"),true)
		tap(7,button("jump"),false)
		tap(4,p,true)
		drag(4,p,p+front)
		check(not Input.is_action_pressed("sprint"),"intervening jump cannot complete joystick repeat")
		pad.release_all()
		# Use the input clock, independent of simulation speed.
		tap(4,p,true)
		tap(4,p,false)
		var deadline:int=Time.get_ticks_msec()+pad.PAD_REPEAT_MS+12
		while Time.get_ticks_msec()<deadline: await process_frame
		tap(4,p,true)
		drag(4,p,p+front)
		check(not Input.is_action_pressed("sprint"),"expired double-tap window requires two new contacts")
		pad.release_all()
	game.options.touch_left_handed=false
	game.options.touch_control_scale=1.0
	pad._layout()
func restart_with_touch_preferences(cfg:Dictionary)->void:
	var saved_path:String=game.options.storage_path
	game.options.touch_left_handed=true
	game.options.touch_control_scale=0.85
	game.options.save_options()
	game.session.simulation_paused=true
	await game.session.stream.quiesce()
	await game.session.audio.finish_playback()
	game.free()
	await process_frame
	game=load("res://main.tscn").instantiate()
	game.options.storage_path=saved_path
	root.add_child(game)
	game._enter_world(cfg,{},1,false)
	game.close_overlay()
	await process_frame
	for child in game.hud.get_children():
		if child.get_script()==preload("res://game/ui/touch_controls.gd"): pad=child
	check(is_instance_valid(pad) and pad.mirrored and pad._pad_center().x>pad.size.x*0.5 and is_equal_approx(game.options.touch_control_scale,0.85),"complete game restart reopens world with saved mirrored controls and 85 percent scale")
