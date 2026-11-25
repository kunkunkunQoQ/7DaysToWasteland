class_name WastelandFront
extends Control

const S := preload("res://game/ui/style.gd")
const WARDROBE := preload("res://game/ui/wardrobe.gd")
const Landscapes := preload("res://game/world/title_landscapes.gd")
var cover_rng := RandomNumberGenerator.new()
var landscape_index := -1
var game: Node
var screen := ""
var shade: ColorRect
var shell: Control
var menu_notice: Label
var binding_id := ""
var bind_button: Button
var return_screen := "title"
var nickname_input: LineEdit
var room_list: VBoxContainer

func _ready() -> void:
	cover_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = S.theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://shaders/menu_scrim.gdshader")
	shade.material = paint
	add_child(shade)
	game.network.discovery.changed.connect(_refresh_rooms)

func _reset(id: String, scenic: bool = false) -> void:
	if is_instance_valid(nickname_input):
		game.set_player_name(nickname_input.text)
		nickname_input = null
	screen = id
	room_list = null
	binding_id = ""
	if is_instance_valid(shell):
		shell.hide()
		shell.queue_free()
	shell = Control.new()
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	shade.material.set_shader_parameter("landscape", scenic)
	shade.material.set_shader_parameter("strength", 0.85 if id == "title" else 1.0)
	game.show_depth_of_field(1 if id == "title" else 2)
	show()

func title(keep_cover := true) -> void:
	_reset("title", true)
	if landscape_index<0 or not keep_cover:
		landscape_index = cover_rng.randi_range(0,Landscapes.TITLES.size()-1)
	game.session.frame_landscape(landscape_index)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	shell.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 66.0
	column.offset_right = 426.0
	column.offset_top = -252.0
	column.offset_bottom = 239.0
	var english := S.label("7 DAYS TO WASTELAND",20,S.GOLD)
	column.add_child(english)
	var game_title := S.label("七日荒原",86,S.TEXT)
	game_title.add_theme_color_override("font_shadow_color",Color("#1b251d"))
	game_title.add_theme_constant_override("shadow_offset_x",4)
	game_title.add_theme_constant_override("shadow_offset_y",5)
	column.add_child(game_title)
	column.add_child(S.label("在荒原扎营，守过第七夜。",19,Color("#cad1ba")))
	var downtime := Control.new()
	downtime.custom_minimum_size.y = 22
	column.add_child(downtime)
	var saves := WastelandSave.list_slots()
	var first := S.button("进入新世界   ›" if saves.is_empty() else "继续游戏   ›", creation if saves.is_empty() else func(): game.open_world(int(saves[0].slot)))
	_add_menu_button(column,first,true)
	if not saves.is_empty():
		_add_menu_button(column,S.button("新建世界",creation))
	_add_menu_button(column,S.button("局域网协作",lan_room))
	_add_menu_button(column,S.button("存档管理",slots))
	_add_menu_button(column,S.button("荒原图鉴",atlas))
	_add_menu_button(column,S.button("系统设置",func(): settings("title")))
	_add_menu_button(column,S.button("退出游戏",game.request_quit))
	menu_notice = S.label("",15,S.RED,true)
	column.add_child(menu_notice)
	if not saves.is_empty():
		var metadata := S.label("最近世界   %s  ·  第 %02d 日" % [saves[0].name, floori(float(saves[0].time)/24.0)+1],17,S.MUTED,true)
		column.add_child(metadata)
	var location := S.label(Landscapes.TITLES[landscape_index],17,Color("#f4e7cb"))
	shell.add_child(location)
	location.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	location.offset_left = 66
	location.offset_top = -38
	location.offset_right = 405
	var character := VBoxContainer.new()
	character.name = "TitleSurvivor"
	shell.add_child(character)
	character.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	character.offset_left = -300
	character.offset_top = -392
	character.offset_right = -58
	character.offset_bottom = -30
	character.add_theme_constant_override("separation",3)
	var studio := preload("res://game/ui/model_study.gd").new()
	character.add_child(studio)
	studio.preview(game.options.appearance,{},true)
	var person := S.label(game.options.player_name,18,S.TEXT)
	person.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	person.add_theme_color_override("font_shadow_color", Color("#14221e"))
	character.add_child(person)
	character.add_child(S.button("更衣库",dressing_room))
	first.grab_focus()

func dressing_room() -> void:
	_reset("wardrobe",true)
	var body := _dialog("更衣库","",752,518)
	var row := S.line(body)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var studio := preload("res://game/ui/model_study.gd").new()
	studio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(studio)
	var avatar := studio.preview(game.options.appearance)
	var details := S.column(row,12)
	details.custom_minimum_size.x = 314
	WARDROBE.picker(details,game,avatar,func(): studio.frame_survivor(avatar,"全身"))
	S.fill(details)
	nickname_input = WARDROBE.player_name_input(details,game)
	var done := S.button("返回开始页",func(): title(true),true)
	body.add_child(done)
	done.grab_focus()

func atlas() -> void:
	_reset("atlas",true)
	var frame:=PanelContainer.new()
	shell.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left=-521
	frame.offset_right=521
	frame.offset_top=-309
	frame.offset_bottom=309
	var browser:=preload("res://game/ui/title_atlas.gd").new()
	frame.add_child(browser)
	browser.setup(game.catalog,func(): title(true))

func _add_menu_button(column: VBoxContainer, button: Button, primary: bool = false) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(260,49 if primary else (44 if preload("res://game/ui/touch_controls.gd").supported() else 32))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size",22 if primary else 19)
	var normal := S.flat(Color("#edaf75") if primary else Color(0.03,0.08,0.075,0.52), Color.TRANSPARENT,0,7)
	normal.content_margin_left = 14
	normal.content_margin_right = 16
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	button.add_theme_stylebox_override("normal",normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#ffd09a") if primary else Color("#364a40")
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)
	if primary:
		for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
			button.add_theme_color_override(key,Color("#172522"))
	column.add_child(button)

func _dialog(name: String, note: String, width: float = 770.0, height: float = 555.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	shell.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	column.add_child(S.label(name,34,S.TEXT))
	if note != "":
		column.add_child(S.label(note,17,S.MUTED,true))
	S.rule(column,Color("#876257"))
	return column

func creation() -> void:
	_reset("create",true)
	var default := WastelandSave.default_world()
	var box := _dialog("新建世界","留空会生成一片新荒原。输入相同种子，可复现地形、废墟、宝箱和野外出生点。",1000,610)
	var rows := S.line(box)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := S.column(rows,8)
	var studio := preload("res://game/ui/model_study.gd").new()
	studio.custom_minimum_size.x = 228
	rows.add_child(studio)
	var avatar := WastelandPartyAvatar.new()
	avatar.show_tag = false
	studio.scene.add_child(avatar)
	studio.follow_pointer(avatar)
	avatar.rotation.y = -0.22
	var right := S.column(rows,10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var world_name := _edit(left,"世界名称",str(default.name),28)
	var seed_text := _edit(left,"世界种子","",72)
	seed_text.placeholder_text = "留空以随机生成"
	left.add_child(S.button("生成随机种子",func(): seed_text.text = str(randi())))
	left.add_child(S.label("幸存者",17,S.GOLD))
	WARDROBE.picker(left,game,avatar,func(): studio.frame_survivor(avatar,"半身"))
	var day := _range(right,"单日时长"," 分钟",8,90,float(default.minutes),1)
	var frequency := _range(right,"血月间隔"," 日",1,21,float(default.horde_days),1)
	var abundance := _range(right,"战利品丰度"," 倍",0.5,2.5,float(default.loot),0.1)
	var refill := _range(right,"容器刷新（0 为关闭）"," 日",0,14,float(default.loot_days),1)
	var speed := _range(right,"丧尸速度"," 倍",0.5,1.8,float(default.zombie_speed),0.1)
	var difficulty := _range(right,"难度"," 倍",0.65,1.8,float(default.difficulty),0.05)
	right.add_child(S.label("第一把石斧",17,S.GOLD))
	right.add_child(S.label("按 [%s] 捡枯枝和碎石，打草收集纤维。集齐木棍 ×1、石料 ×2、纤维 ×2 后，打开 [%s] 制作石斧。空拳打树每拳损失 2 点生命，打岩石或金属伤得更重。" % [game.options.action_name("use"),game.options.action_name("inventory")],16,S.TEXT,true))
	var bar := S.line(box)
	bar.add_child(S.button("返回", title))
	S.fill(bar)
	var status := S.label("",16,S.RED)
	bar.add_child(status)
	var enter := S.button("进入荒原",func():
		var free_slot := WastelandSave.next_slot()
		if free_slot == 0:
			status.text = "8 个存档位已满。可在存档管理中释放一个位置。"
			return
		var seed_label := seed_text.text.strip_edges()
		if seed_label == "": seed_label = str(randi())
		default.name = world_name.text.strip_edges() if world_name.text.strip_edges() != "" else "未命名世界"
		default.seed_label = seed_label
		default.seed = WastelandSave.seed_number(seed_label)
		default.minutes = day.value
		default.horde_days = roundi(frequency.value)
		default.loot = abundance.value
		default.loot_days = roundi(refill.value)
		default.zombie_speed = speed.value
		default.difficulty = difficulty.value
		game.create_world(default,free_slot),true)
	bar.add_child(enter)
	enter.grab_focus()

func _edit(parent: Control,label: String,default: String, limit: int) -> LineEdit:
	parent.add_child(S.label(label,17,S.MUTED))
	var value := LineEdit.new()
	value.text = default
	value.max_length = limit
	value.custom_minimum_size.y = 38
	parent.add_child(value)
	return value

func _range(parent: Control, title_text: String, unit: String, lo: float, hi: float, value: float, step: float) -> HSlider:
	var column := S.column(parent,1)
	var row := S.line(column)
	row.add_child(S.label(title_text,16,S.MUTED))
	S.fill(row)
	var format := "%.0f" if step >= 1 else "%.2f"
	var number := S.label((format % value)+unit,16,S.GOLD)
	row.add_child(number)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 17
	column.add_child(slider)
	slider.value_changed.connect(func(v: float): number.text = (format % v) + unit)
	return slider

func slots() -> void:
	_reset("slots",true)
	var box := _dialog("存档管理","最多 8 个世界。每个世界会自动保存所有玩家和世界进度。",780,510)
	var list := S.scroller(box)
	var saves := WastelandSave.list_slots()
	if saves.is_empty():
		list.add_child(S.label("暂无存档",22,S.MUTED))
	for save in saves:
		var row := S.line(list)
		var data := S.column(row,3)
		data.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		data.add_child(S.label(str(save.name),22,S.TEXT))
		data.add_child(S.label("槽位 %02d  ·  第 %02d 日  ·  种子 %s" % [save.slot,floori(float(save.time)/24.0)+1,save.seed],15,S.MUTED,true))
		row.add_child(S.button("载入",func(): game.open_world(int(save.slot)),true))
		row.add_child(S.button("删除",func(): _confirm_delete(int(save.slot),str(save.name))))
		S.rule(list)
	var back := S.button("返回主菜单", title)
	box.add_child(back)
	back.grab_focus()

func lan_room() -> void:
	_reset("lan",true)
	var body:=_dialog("局域网协作","选择一个单人存档开放，或加入附近的世界（含房主最多 %d 人）。"%WastelandLan.MAX_PLAYERS,870,605)
	nickname_input = WARDROBE.player_name_input(body,game)
	var row:=S.line(body)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var launch:=S.column(row,10)
	var join:=S.column(row,10)
	launch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	join.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	launch.add_child(S.label("主机",23,S.GOLD))
	var worlds:=OptionButton.new()
	for info in WastelandSave.list_slots():
		worlds.add_item("%s · 第 %d 日" % [info.name,floori(float(info.time)/24.0)+1],int(info.slot))
	launch.add_child(worlds)
	var port_in:=_edit(launch,"开放端口",str(WastelandLan.DEFAULT_PORT),5)
	var go:=S.button("开放选中世界",func():
		game.set_player_name(nickname_input.text)
		var target:=port_in.text.to_int()
		if target<1024 or target>65535:
			menu_notice.text="端口须在 1024 到 65535 之间。"
		else:
			game.host_world(worlds.get_selected_id(),target),true)
	go.disabled=worlds.item_count==0
	launch.add_child(go)
	if go.disabled:
		launch.add_child(S.label("创建并保存一个世界后可开放。",16,S.MUTED,true))
	else:
		var address:PackedStringArray=[]
		for ip in IP.get_local_addresses():
			if str(ip)!="127.0.0.1" and not str(ip).contains(":") and game.network._local_address(ip): address.append(ip)
		if not address.is_empty():
			launch.add_child(S.label("本机地址  "+address[0],15,S.MUTED,true))
	join.add_child(S.label("附近的世界",23,S.GOLD))
	room_list=S.scroller(join)
	room_list.name="NearbyWorlds"
	_refresh_rooms()
	var manual:=S.column(join,3)
	var address_in:=_edit(manual,"主机局域网地址","",45)
	address_in.placeholder_text="192.168.1.20"
	var join_port:=_edit(manual,"主机端口",str(WastelandLan.DEFAULT_PORT),5)
	manual.add_child(S.button("连接",func():
		game.set_player_name(nickname_input.text)
		var address_text:=address_in.text.strip_edges()
		var target:=join_port.text.to_int()
		var result:Error=game.network.connect_to(address_text,target) if target>=1024 and target<=65535 else ERR_INVALID_PARAMETER
		menu_notice.text="正在等候主机…" if result==OK else "请填写局域网 IP 地址和有效端口。",true))
	manual.hide()
	join.add_child(S.button("手动输入地址",func(): manual.visible=not manual.visible))
	menu_notice=S.label("",16,S.GOLD,true)
	body.add_child(menu_notice)
	body.add_child(S.button("返回",func(): game.network.stop(); title()))

func _refresh_rooms() -> void:
	if screen!="lan" or not is_instance_valid(room_list): return
	for old in room_list.get_children():
		old.hide()
		old.queue_free()
	var rooms: Dictionary = game.network.discovery.rooms
	if rooms.is_empty():
		room_list.add_child(S.label("正在搜索同一网络中的世界…",16,S.MUTED,true))
	for id in rooms:
		var room: Dictionary = rooms[id]
		var current := str(ProjectSettings.get_setting("application/config/version"))
		var caption := "%s  ·  %d/%d\n%s　 第 %d 日" % [room.name,room.players,WastelandLan.MAX_PLAYERS,room.owner,room.day]
		if room.version!=current: caption+="　版本 "+str(room.version)
		var button := S.button(caption,func():
			game.set_player_name(nickname_input.text)
			var result: Error=game.network.connect_to(room.address,room.port)
			menu_notice.text="正在加入世界…" if result==OK else "连接失败，请查看房间是否仍然开放。")
		button.disabled = room.players>=WastelandLan.MAX_PLAYERS or room.version!=current
		room_list.add_child(button)

func _confirm_delete(slot: int, label: String) -> void:
	_reset("delete",true)
	var body := _dialog("删除世界","「%s」及其备用存档将永久删除。" % label,566,266)
	S.fill(body)
	var row := S.line(body)
	var cancel := S.button("取消",slots,true)
	row.add_child(cancel)
	S.fill(row)
	row.add_child(S.button("确认删除",func():
		var error := WastelandSave.delete_slot(slot)
		if error == OK:
			slots()
		else:
			body.add_child(S.label("删除失败 · 错误 %d" % error,16,S.RED))))
	cancel.grab_focus()

func pause() -> void:
	_reset("pause")
	var box := _dialog("已暂停",game.session.world_settings.name + "  ·  第 %d 日  %s" % [game.session.clock.day(),game.session.clock.time_text()],450,470)
	var resume := S.button("返回游戏",func(): game.close_overlay(),true)
	box.add_child(resume)
	var save_button := S.button("保存世界",func():
		if game.session.replica:
			menu_notice.text = "正在保存世界…"
			game.network.send_request("save", [])
			return
		var result: Error = game.session.save_now(false)
		menu_notice.text = "世界已保存" if result == OK else "保存失败 · 错误 %d" % result)
	box.add_child(save_button)
	if not game.session.replica:
		var share := S.button("保存并关闭局域网" if game.network.server() else "将此世界开放到局域网",func():
			var was_host: bool=game.network.server()
			var result: Error=game.set_world_shared(not was_host)
			if result!=OK:
				menu_notice.text="操作失败 · 错误 %d" % result
			else:
				pause()
				menu_notice.text="已保存，可继续单人游玩" if was_host else "同一网络中的队友现在可以搜索到这个世界")
		box.add_child(share)
	box.add_child(S.button("系统设置",func(): settings("pause")))
	box.add_child(S.button("离开队伍" if game.session.replica else "保存并返回主菜单",func(): game.leave_world()))
	menu_notice = S.label("",15,S.MINT)
	box.add_child(menu_notice)
	resume.grab_focus()

func died() -> void:
	_reset("dead")
	shade.material.set_shader_parameter("strength", 0.36)
	game.show_depth_of_field(0)
	var note := "可以在队友附近重新加入。" if game.session.replica else "遗落物资的位置已记在地图上。"
	var box := _dialog("你倒在了荒原",note,398,265)
	var card := box.get_parent() as Control
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	card.offset_left = 26.0
	card.offset_right = 424.0
	S.fill(box)
	var revive := S.button("在队友附近复苏" if game.session.replica else "返回"+game.session.start_name(),func():
		if game.session.replica: game.session.ui_command("revive")
		else:
			game.session.respawn()
			game.close_overlay(),true)
	box.add_child(revive)
	box.add_child(S.button("返回主菜单",func(): game.leave_world()))
	revive.grab_focus()

func settings(origin: String) -> void:
	_reset("settings",origin == "title")
	return_screen = origin
	var opts: WastelandSettings = game.options
	var box := _dialog("系统设置","",840,580)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	var display_scroll:=ScrollContainer.new()
	display_scroll.name="画面"
	display_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	display_scroll.follow_focus=true
	tabs.add_child(display_scroll)
	var display:=S.column(display_scroll,3)
	display.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var reach := _range(display,"渲染高度上限","p",272,816,float(opts.display.pixel_height),34)
	reach.value_changed.connect(func(v): opts.display.pixel_height = int(v); game.resize_scene(true))
	var radius := _range(display,"视距"," 区块",2,6,float(opts.display.radius),1)
	radius.value_changed.connect(func(v): opts.display.radius = int(v))
	var ui_focus := _range(display,"界面柔焦"," %",0,80,float(opts.display.ui_softness)*100.0,1)
	ui_focus.value_changed.connect(func(v): opts.display.ui_softness=v/100.0; game.apply_ui_softness())
	var impact_motion := _range(display,"受击镜头晃动"," %",0,100,float(opts.display.impact_motion)*100.0,5)
	impact_motion.value_changed.connect(func(v): opts.display.impact_motion=v/100.0)
	var fps := _range(display,"帧率上限"," FPS",30,144,float(opts.display.fps),1)
	fps.value_changed.connect(func(v): opts.display.fps = int(v); Engine.max_fps = int(v))
	_toggle(display,"按帧率自动调节像素分辨率",bool(opts.display.dynamic),func(value): opts.display.dynamic = value; game.resize_scene(true))
	_toggle(display,"帧率／帧时监控",bool(opts.display.show_fps),func(value): opts.display.show_fps = value)
	if not OS.has_feature("android"):
		_toggle(display,"全屏",bool(opts.display.full),func(value): opts.display.full = value; opts.apply_display())
	var looks := HBoxContainer.new()
	looks.name = "外观与趣味"
	tabs.add_child(looks)
	var studio := preload("res://game/ui/model_study.gd").new()
	studio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	looks.add_child(studio)
	studio.frame(2.03,0.92)
	var avatar := WastelandPartyAvatar.new()
	avatar.show_tag = false
	studio.scene.add_child(avatar)
	avatar.rotation.y = -0.44
	var wardrobe := S.column(looks,7)
	wardrobe.custom_minimum_size.x = 310
	wardrobe.add_child(S.label("我的角色",23,S.GOLD))
	WARDROBE.picker(wardrobe,game,avatar)
	nickname_input = WARDROBE.player_name_input(wardrobe,game)
	S.rule(wardrobe)
	_toggle(wardrobe,"愚人节模式",opts.april_faces,func(value):
		opts.april_faces = value
		preload("res://game/art/april_face.gd").set_enabled(value))
	wardrobe.add_child(S.label("让荒原上的动物、鱼鸟和感染者都长出同一张人脸。联机时各自选择。",16,S.MUTED,true))
	var mix := VBoxContainer.new()
	mix.name = "声音"
	tabs.add_child(mix)
	for i in range(WastelandSettings.BUS.size()):
		var slider := _range(mix,WastelandSettings.BUS_LABEL[i]," %",0,100,opts.volumes[i]*100,1)
		slider.value_changed.connect(func(value): opts.volumes[i] = value/100.0; opts.apply_audio())
	var mouse := VBoxContainer.new()
	mouse.name = "操控"
	tabs.add_child(mouse)
	var touch_ui:=preload("res://game/ui/touch_controls.gd").supported()
	if touch_ui:
		mouse.add_child(S.label("连点摇杆，第二次向前推住即可疾跑。持盾时按住「举盾」，拖动可转身。点「更多」可打开地图、丢弃物品或换手；长按「更多」打开工具盘，滑到动作后松手。",17,S.TEXT,true))
		_toggle(mouse,"左手操作按钮（摇杆移到右侧）",opts.touch_left_handed,func(value): opts.touch_left_handed=value)
		var control_scale:=_range(mouse,"触控大小"," %",85,115,roundi(opts.touch_control_scale*100),5)
		control_scale.name="TouchControlScale"
		control_scale.custom_minimum_size.y=32
		control_scale.value_changed.connect(func(value): opts.touch_control_scale=value/100.0)
	var sensitivity := _range(mouse,"视角灵敏度","",0.35,3.0,float(opts.display.sensitivity)*500,0.05)
	sensitivity.value_changed.connect(func(value): opts.display.sensitivity = value/500.0)
	_toggle(mouse,"反转垂直视角",bool(opts.display.invert_y),func(value): opts.display.invert_y = value)
	_toggle(mouse,"向前移动时自动跨越低障碍",bool(opts.display.auto_step),func(value): opts.display.auto_step = value)
	if not touch_ui:
		mouse.add_child(S.label("连按两次前进，第二次按住即可疾跑。点选下方键位可重新绑定，重复键位会互换。",15,S.MUTED,true))
		var scroll := S.scroller(mouse)
		for id in WastelandSettings.ACTIONS:
			var line := S.line(scroll)
			line.add_child(S.label(WastelandSettings.ACTIONS[id][0],16,S.MUTED))
			S.fill(line)
			var button := Button.new()
			button.text = opts.action_name(id)
			button.custom_minimum_size = Vector2(161,34)
			button.pressed.connect(func():
				binding_id = id
				bind_button = button
				button.text = "等待输入…")
			line.add_child(button)
		mouse.add_child(S.button("恢复默认键位",func(): opts.reset_bindings(); settings(origin)))
	var pad := VBoxContainer.new()
	pad.name = "手柄"
	tabs.add_child(pad)
	for line in [
		"左／右摇杆   行走／视角", "左／右扳机   副动作／主动作", "A 跳跃   B 蹲伏   X 交互   Y 装填",
		"左／右肩键   循环切换快捷栏", "方向键 ↑ 地图  ↓ 委托  ← 方块形状  → 旋转",
		"左／右摇杆按下   冲刺／开关提灯", "视图键   背包      菜单键   暂停",
	]:
		pad.add_child(S.label(line,18,S.MUTED))
	var exit := S.button("保存设置并返回",_settings_back,true)
	box.add_child(exit)
	exit.grab_focus()

func _toggle(parent: Control, title_text: String, value: bool, action: Callable) -> void:
	var box := CheckButton.new()
	box.text = title_text
	box.button_pressed = value
	box.toggled.connect(action)
	parent.add_child(box)

func _settings_back() -> void:
	game.options.save_options()
	if return_screen == "pause": pause()
	else: title(true)

func handle_back() -> void:
	match screen:
		"title": pass
		"settings": _settings_back()
		"atlas": title(true)
		"pause": game.close_overlay()
		"dead": pass
		"delete": slots()
		"lan": game.network.stop(); title()
		_: title()

func try_binding(event: InputEvent) -> bool:
	if binding_id == "" or not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		bind_button.text = game.options.action_name(binding_id)
		binding_id = ""
		return true
	if game.options.rebind(binding_id,event):
		bind_button.text = game.options.action_name(binding_id)
		binding_id = ""
		_update_bind_labels()
		return true
	return false

func _update_bind_labels() -> void:
	if not is_instance_valid(bind_button):
		return
	var rows := bind_button.get_parent().get_parent()
	var index := 0
	var mapping: Array = WastelandSettings.ACTIONS.keys()
	for row in rows.get_children():
		if row.get_child_count() >= 3 and index < mapping.size():
			row.get_child(2).text = game.options.action_name(mapping[index])
			index += 1
