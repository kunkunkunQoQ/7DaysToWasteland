extends Control

const Style := preload("res://game/ui/style.gd")
const MENU := {"inventory":"bag","map":"map","journal":"journal"}
const Layout := preload("res://game/ui/touch_layout.gd")
const CAPTIONS := Layout.CAPTIONS
var game: Node
var fingers := {}
var action_sources := {}
var first_physics_frame := {}
var pending_release := {}
var pad_origin := Vector2.ZERO
var pad_offset := Vector2.ZERO
const PAD_REPEAT_MS := 325
var pad_down_ms := 0
var pad_release_ms := -1000
var pad_last_origin := Vector2.ZERO
var pad_second := false
var pad_wrong_way := false
var mirrored := false

const WHEEL_HOLD_MS := 390
const WHEEL_LABELS := {"field":"探索手记","craft":"制作","map":"地图","journal":"委托","flashlight":"提灯","shape":"切换形状","rotate":"旋转方块","reload":"装填","inventory":"背包","use":"交互","disembark":"下车 / 船"}
var wheel_finger := -1
var wheel_started := 0
var wheel_origin := Vector2.ZERO
var wheel_pointer := Vector2.ZERO
var wheel_open := false
var wheel_title := ""
var wheel_actions: Array[String] = []
var wheel_targets: Dictionary = {}
var wheel_selected := ""
var expanded := false
var layout := {}
var bounds := Rect2()
var scale_unit := 1.0
var verbs := {}
var verb_tick := 0.0

static func supported() -> bool:
	return Layout.active

func setup(main: Node) -> void:
	game=main

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	resized.connect(_layout)
	visibility_changed.connect(_visibility)
	get_window().focus_exited.connect(release_all)
	_layout()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_EXIT_TREE]:
		release_all()

func _visibility() -> void:
	if not is_visible_in_tree(): release_all()
	else: _layout()

func _layout() -> void:
	bounds=Rect2(Vector2.ZERO,size)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe:=DisplayServer.get_display_safe_area()
		if safe.has_area():
			var inverse:=get_screen_transform().affine_inverse()
			bounds=bounds.intersection(Rect2(inverse*Vector2(safe.position),inverse*Vector2(safe.end)-inverse*Vector2(safe.position)))
			if not bounds.has_area(): bounds=Rect2(Vector2.ZERO,size)
	bounds=bounds.grow(-8.0)
	mirrored=bool(game.options.get("touch_left_handed")) if is_instance_valid(game) else false
	var preference:Variant=game.options.get("touch_control_scale") if is_instance_valid(game) else null
	var fit:=minf(bounds.size.x/1160.0,bounds.size.y/680.0)
	scale_unit=clampf(fit,0.45,1.36)*clampf(float(preference) if preference!=null else 1.0,0.85,1.15)
	var right:=bounds.end.x
	var bottom:=bounds.end.y
	var top:=bounds.position.y
	var u:=scale_unit
	layout.clear()
	# The central view, crosshair and bottom-center HUD quickbar stay exposed.
	_rect("fire",Vector2(right-145*u,bottom-157*u),Vector2(126,74)*u)
	_rect("use",Vector2(right-101*u,bottom-255*u),Vector2(94,64)*u)
	_rect("jump",Vector2(right-228*u,bottom-251*u),Vector2(99,62)*u)
	_rect("crouch",Vector2(right-239*u,bottom-88*u),Vector2(95,60)*u)
	if expanded or verbs.has("alternate"):
		_rect("alternate",Vector2(right-89*u,bottom-76*u),Vector2(88,59)*u)
	if verbs.has("offhand_use"):
		_rect("offhand_use",Vector2(right-256*u,bottom-162*u),Vector2(82,59)*u)
	var secondary_slot:=WastelandHUD.offhand_rect(size).grow(5)
	var crouch:Rect2=layout.crouch
	if crouch.intersects(secondary_slot):
		crouch.position.x=secondary_slot.position.x-crouch.size.x
		layout.crouch=crouch
	var menu_row:=["inventory","pause_game","more"]
	for i in menu_row.size():
		_rect(menu_row[i],Vector2(right-(197-i*70)*u,top+109*u),Vector2(65,50)*u)
	if expanded:
		_rect("sprint",Vector2(bounds.position.x+225*u,bottom-254*u),Vector2(85,56)*u)
		for i in Layout.EXTRA.size():
			var id:String=Layout.EXTRA[i]
			_rect(id,Vector2(right-(282-(i%4)*75)*u,top+(170+floori(i/4.0)*54)*u),Vector2(71,49)*u)
	queue_redraw()

func _rect(id:String,center:Vector2,extent:Vector2)->void:
	if mirrored: center.x=bounds.position.x+bounds.end.x-center.x
	layout[id]=Rect2(center-extent*0.5,extent)

func _pad_center()->Vector2:
	return Vector2(bounds.end.x-118*scale_unit if mirrored else bounds.position.x+118*scale_unit,bounds.end.y-241*scale_unit)

func _draw()->void:
	var u:=scale_unit
	var base:=pad_origin if "pad" in fingers.values() else _pad_center()
	var shadow:=Color(0.06,0.09,0.095,0.50)
	var ink:=Color(0.80,0.86,0.80,0.74)
	draw_circle(base,68*u,shadow,true,-1,true)
	draw_arc(base,68*u,0,TAU,64,ink,1.6*u,true)
	if action_sources.has("sprint"):
		_legend(base+Vector2(0,88)*u,"疾跑中",roundi(15*u),Style.GOLD)
	draw_circle(base+pad_offset,26*u,Color(0.78,0.82,0.75,0.48),true,-1,true)
	for id:String in layout:
		var box:Rect2=layout[id]
		var pressed:=action_sources.has(id) or (id=="more" and (expanded or wheel_finger>=0)) or (id=="discard" and "discard_tap" in fingers.values())
		draw_rect(box,Color(0.25,0.34,0.30,0.82) if pressed else shadow)
		draw_rect(box,Style.GOLD if pressed else ink,false,1.4*u,true)
		var caption:String=verbs.get(id,CAPTIONS[id])
		var h:=roundi(18*u)
		var baseline:=box.get_center().y+(Style.FONT.get_ascent(h)-Style.FONT.get_descent(h))*0.5
		draw_string(Style.FONT,Vector2(box.position.x,baseline),caption,HORIZONTAL_ALIGNMENT_CENTER,box.size.x,h,Color("#fff1d4"))

	if wheel_open: _draw_wheel()
	elif wheel_finger>=0:
		var rect:Rect2=layout.more
		var amount:=clampf(float(Time.get_ticks_msec()-wheel_started)/WHEEL_HOLD_MS,0,1)
		draw_line(Vector2(rect.position.x,rect.end.y),Vector2(rect.position.x+amount*rect.size.x,rect.end.y),Style.GOLD,3*scale_unit)

func _legend(center_baseline:Vector2,words:String,font_size:int,tint:Color)->void:
	var width:=Style.FONT.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var baseline:=center_baseline-Vector2(width*0.5,0)
	var top:=baseline-Vector2(5,Style.FONT.get_ascent(font_size))
	draw_rect(Rect2(top,Vector2(width+10,Style.FONT.get_height(font_size))),Color(0.055,0.085,0.085,0.85))
	draw_string(Style.FONT,baseline,words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,tint)

func _process(delta:float)->void:
	if not is_visible_in_tree(): return
	verb_tick-=delta
	if verb_tick<=0 and is_instance_valid(game) and is_instance_valid(game.session):
		verb_tick=0.10
		var updated:=_action_verbs(game.session)
		if updated!=verbs:
			verbs=updated
			_layout()
	if wheel_finger<0 or wheel_open: return
	if Time.get_ticks_msec()-wheel_started>=WHEEL_HOLD_MS: _open_wheel()
	queue_redraw()

func _action_verbs(s:WastelandSession)->Dictionary:
	var held:=s.bag.current()
	var kind:String=s.catalog.items.get(held,{}).get("kind","")
	var result:Dictionary={}
	match kind:
		"", "material": result.fire="挥拳"
		"tool","weapon":
			result.fire="挥击"
			result.alternate="蓄力"
		"ranged":
			result.fire="射击"
			result.alternate="装填"
		"food","med":
			result.fire="使用"
		"build","device","vehicle": result.fire="放置"
		"sapling": result.fire="种树"
	if held=="field_glasses": result.alternate="观察"
	if s.player.swimming or s.player.submerged:
		result.jump="上浮"
		result.crouch="下潜"
	if is_instance_valid(s.player.mount_vehicle):
		result.use="离开载具"
	var target:Variant=s.interaction.get("collider")
	if is_instance_valid(target):
		match str(target.get_meta("kind","")):
			"sapling":
				if held=="shovel" and s.player.action_origin().distance_to(s.interaction.position)<=float(s.catalog.items.shovel.reach):
					result.fire="挖起树苗"
			"resource":
				if kind in ["","material","tool","weapon"]: result.fire="采集"
				var resource:String=target.get_meta("resource","")
				if resource!="grass" and resource in s.PICKUPS: result.use="拾取"
			"vehicle":
				result.use="驾驶"
				result.alternate="维护"
			"loot": result.use="开箱"
			"drop": result.use="拾取"
			"block":
				var info: Dictionary = s.construction.blocks.get(target.get_meta("block"), {})
				if held=="connector": result.alternate="接线"
				elif not info.is_empty() and info.device == "":
					if int(info.tier) == 0: result.use = "回收"
					elif int(info.shape) == 4: result.use = "开关"
					if s.construction.maintenance_tool(held):
						if float(info.hp) < s.construction._max_hp(info): result.alternate = "维修"
						elif int(info.tier) < 4: result.alternate = "升级"
						else: result.erase("alternate")
	if s.bag.is_shield(s.bag.offhand): result.offhand_use="举盾"
	elif s.bag.offhand=="torch": result.offhand_use="开关灯"
	elif s.bag.offhand=="field_glasses": result.offhand_use="观察"
	elif not s.bag.offhand.is_empty(): result.offhand_use="用副手"
	return result

func _open_wheel()->void:
	wheel_open=true
	expanded=false
	_layout()
	var session:WastelandSession=game.session
	var item:Dictionary=session.catalog.items.get(session.bag.current(),{})
	var kind:String=item.get("kind","")
	if is_instance_valid(session.player.mount_vehicle):
		wheel_title="驾驶"
		wheel_actions.assign(["map","journal","disembark","field"])
	elif kind in ["build","device","wire"]:
		wheel_title="建造"
		wheel_actions.assign(["shape","rotate","craft","inventory"])
	elif kind=="ranged":
		wheel_title="远程"
		wheel_actions.assign(["reload","inventory","flashlight","map"])
	elif kind in ["weapon","tool"]:
		wheel_title="野外作业" if kind=="tool" else "近战"
		wheel_actions.assign(["use","inventory","craft","field"])
	else:
		wheel_title="探索"
		wheel_actions.assign(["field","craft","journal","flashlight"])
	# A quarter fan opens inwards from the anchored button, keeping every target on screen.
	for i in wheel_actions.size():
		var angle:=deg_to_rad(174.0-i*28.0)
		var vector:=Vector2.from_angle(angle)
		if mirrored: vector.x *= -1
		var center:=wheel_origin+vector*202*scale_unit
		wheel_targets[wheel_actions[i]]=Rect2(center-Vector2(46,28)*scale_unit,Vector2(92,56)*scale_unit)
	_update_wheel(wheel_pointer)

func _update_wheel(at:Vector2)->void:
	wheel_pointer=at
	wheel_selected=""
	for id:String in wheel_targets:
		if wheel_targets[id].has_point(at):
			wheel_selected=id
			break
	queue_redraw()

func _draw_wheel()->void:
	var tint:=Color(0.08,0.13,0.13,0.96)
	for id:String in wheel_targets:
		var box:Rect2=wheel_targets[id]
		draw_line(wheel_origin,box.get_center(),Color(0.72,0.77,0.66,0.48),2*scale_unit)
	for id:String in wheel_targets:
		var box:Rect2=wheel_targets[id]
		var selected:=wheel_selected==id
		draw_rect(box,Color("#425d4f") if selected else tint)
		draw_rect(box,Style.GOLD if selected else Style.MUTED,false,2.0*scale_unit)
		var font_size:=roundi(19*scale_unit)
		var y:=box.get_center().y+(Style.FONT.get_ascent(font_size)-Style.FONT.get_descent(font_size))*0.5
		draw_string(Style.FONT,Vector2(box.position.x,y),WHEEL_LABELS[id],HORIZONTAL_ALIGNMENT_CENTER,box.size.x,font_size,Style.GOLD if selected else Style.TEXT)
	var legend:=Rect2(wheel_origin+Vector2(-7 if mirrored else -330,-73)*scale_unit,Vector2(337,42)*scale_unit)
	draw_rect(legend,tint)
	var label:=wheel_title+"  ·  "+("滑到动作松手，空白处取消" if wheel_selected=="" else "松手选择「"+str(WHEEL_LABELS[wheel_selected])+"」")
	draw_string(Style.FONT,legend.position+Vector2(0,28)*scale_unit,label,HORIZONTAL_ALIGNMENT_CENTER,legend.size.x,roundi(16*scale_unit),Style.TEXT)

func _close_wheel()->void:
	wheel_open=false
	wheel_finger=-1
	wheel_selected=""
	wheel_targets.clear()
	wheel_actions.clear()
	queue_redraw()

func _execute_wheel(id:String)->void:
	if id in ["field","map","journal","craft","inventory"]:
		release_all()
		game.open_panel("bag" if id=="inventory" else id)
	elif not id.is_empty():
		var action:="use" if id=="disembark" else id
		_set_source(action,-2,1.0)
		pending_release[action]=-2

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_instance_valid(game) or not is_instance_valid(game.session): return
	if not game.session.controls_enabled or game.session.simulation_paused or game.session.death_screen: return
	if event is InputEventScreenTouch:
		var finger:int=event.index
		if event.pressed and not event.canceled:
			_begin(finger,get_global_transform_with_canvas().affine_inverse()*event.position)
		else:
			if finger==wheel_finger and wheel_open: _update_wheel(get_global_transform_with_canvas().affine_inverse()*event.position)
			_end(finger,event.canceled,get_global_transform_with_canvas().affine_inverse()*event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var movement:=get_global_transform_with_canvas().affine_inverse()
		var pos:Vector2=movement*event.position
		var delta:Vector2=pos-movement*(event.position-event.relative)
		match str(fingers.get(event.index,"")):
			"discard_tap":
				if not layout.has("discard") or not layout.discard.has_point(pos):
					fingers[event.index]="discard_canceled"
					queue_redraw()
			"more": _update_wheel(pos)
			"pad": _move_pad(pos)
			"look","fire","alternate","offhand_use":
				game.session.mouse_look(delta)
		get_viewport().set_input_as_handled()

func _begin(finger:int,pos:Vector2)->void:
	_end(finger,true)
	if wheel_open and finger!=wheel_finger:
		for box:Rect2 in wheel_targets.values():
			if box.has_point(pos): return
	for id:String in layout:
		if not layout[id].has_point(pos): continue
		if not "pad" in fingers.values(): pad_release_ms=-1000
		if MENU.has(id) or id in ["pause_game","chat"]:
			release_all()
			if id=="pause_game": game._pause()
			elif id=="chat": game.open_chat()
			else: game.open_panel(MENU[id])
		elif id=="discard":
			fingers[finger]="discard_tap"
			queue_redraw()
		elif id=="more":
			if wheel_finger>=0: return
			wheel_finger=finger
			wheel_started=Time.get_ticks_msec()
			wheel_origin=layout.more.get_center()
			wheel_pointer=pos
			fingers[finger]="more"
			queue_redraw()
		else:
			fingers[finger]=id
			_set_source(id,finger,1.0)
		return
	var bar:=WastelandHUD.quickbar_rect(size).grow_individual(0,2,0,6)
	if not bounds.has_point(pos): return
	if WastelandHUD.offhand_rect(size).has_point(pos):
		if not "pad" in fingers.values(): pad_release_ms=-1000
		if game.session.bag.offhand.is_empty():
			release_all()
			game.open_panel("bag")
		else:
			fingers[finger]="offhand_use"
			_set_source("offhand_use",finger,1.0)
		return
	if bar.has_point(pos):
		if not "pad" in fingers.values(): pad_release_ms=-1000
		var id:="slot_%d"%(1+clampi(floori((pos.x-bar.position.x)/WastelandHUD.SLOT_STEP),0,7))
		fingers[finger]=id
		_set_source(id,finger,1.0)
		return
	var horizontal:=(bounds.end.x-pos.x if mirrored else pos.x-bounds.position.x)/bounds.size.x
	if horizontal<0.44 and pos.y>bounds.position.y+bounds.size.y*0.38:
		if "pad" in fingers.values(): return
		fingers[finger]="pad"
		pad_down_ms=Time.get_ticks_msec()
		pad_second=pad_down_ms-pad_release_ms<=PAD_REPEAT_MS and pos.distance_to(pad_last_origin)<=72*scale_unit
		pad_release_ms=-1000
		pad_wrong_way=false
		pad_origin=pos
		_move_pad(pos)
	elif horizontal>=0.44 and not "look" in fingers.values():
		if not "pad" in fingers.values(): pad_release_ms=-1000
		fingers[finger]="look"

func _move_pad(pos:Vector2)->void:
	var radius:=59*scale_unit
	pad_offset=(pos-pad_origin).limit_length(radius)
	var axial:=pad_offset/radius
	var magnitude:=axial.length()
	var forward:=-axial.y
	if magnitude>0.38 and forward<magnitude*0.55:
		pad_wrong_way=true
		pad_second=false
	var running:bool=action_sources.get("sprint",{}).has(-3)
	if running and forward<0.34: pad_second=false
	_set_source("sprint",-3,1.0 if pad_second and forward>=(0.34 if running else 0.68) and forward>=magnitude*0.74 else 0.0)
	var strength:=maxf(0.0,(magnitude-0.12)/0.88)
	axial=axial.normalized()*strength if strength>0 else Vector2.ZERO
	_set_source("left",-1,maxf(-axial.x,0))
	_set_source("right",-1,maxf(axial.x,0))
	_set_source("up",-1,maxf(-axial.y,0))
	_set_source("down",-1,maxf(axial.y,0))
	queue_redraw()

func _set_source(id:String,finger:int,strength:float)->void:
	if not InputMap.has_action(id): return
	var sources:Dictionary=action_sources.get(id,{})
	if strength>0.0:
		if pending_release.has(id):
			sources.erase(pending_release[id])
			pending_release.erase(id)
		if sources.is_empty(): first_physics_frame[id]=Engine.get_physics_frames()
		sources[finger]=strength
		action_sources[id]=sources
		Input.action_press(id,sources.values().max())
	elif sources.erase(finger):
		if sources.is_empty():
			Input.action_release(id)
			action_sources.erase(id)
		else: Input.action_press(id,sources.values().max())
	queue_redraw()

func _end(finger:int,canceled:=false,pos:=Vector2.INF)->void:
	var id:String=fingers.get(finger,"")
	fingers.erase(finger)
	if id in ["discard_tap","discard_canceled"]:
		if id=="discard_tap" and not canceled and layout.has("discard") and layout.discard.has_point(pos):
			_set_source("discard",finger,1.0)
			pending_release["discard"]=finger
		queue_redraw()
		return
	if id=="more":
		var choice:=wheel_selected
		var opened:=wheel_open
		var tapped:=wheel_pointer.distance_to(wheel_origin)<46*scale_unit
		_close_wheel()
		if canceled: return
		if opened: _execute_wheel(choice)
		elif tapped:
			expanded=not expanded
			_layout()
		return
	if id=="pad":
		var now:=Time.get_ticks_msec()
		if not canceled and not pad_second and not pad_wrong_way and now-pad_down_ms<=220:
			pad_release_ms=now
			pad_last_origin=pad_origin
		pad_second=false
		_set_source("sprint",-3,0)
		pad_offset=Vector2.ZERO
		for axis:String in ["left","right","up","down"]: _set_source(axis,-1,0)
	elif id!="" and id!="look":
		# Preserve a fast down/up pair until one gameplay physics sample sees the press.
		if not canceled and action_sources.get(id,{}).size()==1 and first_physics_frame.get(id,-1)==Engine.get_physics_frames():
			pending_release[id]=finger
		else: _set_source(id,finger,0)
	queue_redraw()

func _physics_process(_delta:float)->void:
	for id:String in pending_release.keys():
		if Engine.get_physics_frames()>int(first_physics_frame.get(id,-1))+1:
			_set_source(id,pending_release[id],0)
			pending_release.erase(id)

func release_all()->void:
	_close_wheel()
	for id:String in action_sources:
		if InputMap.has_action(id): Input.action_release(id)
	fingers.clear()
	action_sources.clear()
	first_physics_frame.clear()
	pending_release.clear()
	pad_offset=Vector2.ZERO
	pad_second=false
	pad_release_ms=-1000
	if expanded:
		expanded=false
		if is_inside_tree(): _layout()
	queue_redraw()
