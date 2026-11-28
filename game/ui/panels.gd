class_name WastelandPanels
extends Control

const S := preload("res://game/ui/style.gd")
const ItemSlot := preload("res://game/ui/item_slot.gd")
const ModelStudy := preload("res://game/ui/model_study.gd")
const TABS := {"bag":"背包与装备","craft":"制作","skills":"技能专长","journal":"委托","field":"探索手记","achievements":"成就","survivor":"人物"}
const GROUPS := {"weapon":"武器","tool":"工具","ranged":"远程","food":"食水","med":"药品","ammo":"弹药","material":"材料",
	"armor":"装备","build":"建材","device":"设备","light":"照明","seed":"种子","sapling":"树苗","wire":"工具","field_gear":"野外器材","vehicle":"载具","quest":"任务物品","supply":"补给"}
var game: Node
var session: WastelandSession
var active := ""
var current_context: Variant
var content: Control
var shade := ColorRect.new()
var body: VBoxContainer
var status_line: Label
var timer_status: Label
var progress_line: ProgressBar
var bag_list: VBoxContainer
var item_grid: GridContainer
var item_detail: TextureRect
var quick_slots: HBoxContainer
var inventory_buttons: Array[Button] = []
var bag_taps:=ItemSlot.TapPair.new()
var assign_button:Button
var use_item_button:Button
var discard_button:Button
var warned_item:=""
var warning_until:=0
var craft_quantity:=1
var craft_materials:GridContainer
var craft_outputs:HBoxContainer
var fire_status:Label
var fire_button:Button
var job_buttons:HBoxContainer
var craft_icon:TextureRect
var craft_minus:Button
var craft_plus:Button
var craft_max:Button
var craft_submit:Button
var craft_cancel:Button
var craft_collect:Button
var craft_quantity_label:Label
var recipe_list: VBoxContainer
var recipe_view := "全部"
var recipe_query := ""
var recipe_fingerprint := 0
var favorite_button: Button
var detail_title: Label
var material_link: Button
var source_link: Button
var detail_description: Label
var selection := ""
var selection_slot := WastelandBag.PACK
var selection_amount := 0
var good_counts := -1
var last_bag_fingerprint := 0
var queue_label: Label
var queue_button: Button
var scroll_target: Button
var station := "hand"
var map_canvas: WastelandMap
var marker_title: LineEdit
var marker_info: Label
var marker_delete: Button
var refresh_tick := 0.0
var status_left := 0.0
var journal_state := 0
var portrait: WastelandPartyAvatar
var bag_avatar: WastelandPartyAvatar
var bag_studio: ModelStudy
var fitted_outfit := 0
var portrait_action := 0
var portrait_time := 0.0
var survivor_vitals: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = S.theme()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.046,0.035,0.075,0.45)
	add_child(shade)
	hide()

func show_panel(id: String, session_node: WastelandSession, context: Variant = null) -> void:
	session = session_node
	active = id
	current_context = context
	queue_label = null
	progress_line = null
	status_line = null
	bag_list = null
	item_grid = null
	quick_slots = null
	item_detail = null
	material_link = null
	source_link = null
	inventory_buttons.clear()
	recipe_list = null
	favorite_button = null
	scroll_target = null
	selection = ""
	good_counts = -1
	last_bag_fingerprint = 0
	map_canvas = null
	portrait = null
	bag_avatar = null
	bag_studio = null
	fitted_outfit = 0
	survivor_vitals = null
	portrait_action = 0
	portrait_time = 0.0
	if is_instance_valid(content):
		content.hide()
		content.queue_free()
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -497.0
	frame.offset_top = -296.0
	frame.offset_right = 497.0
	frame.offset_bottom = 296.0
	content = frame
	add_child(frame)
	body = VBoxContainer.new()
	frame.add_child(body)
	var top := S.line(body)
	var page_title := str(TABS.get(id,{"map":"灰湾地图","trade":"湖务站公告板","device":"设备控制","vehicle":"载具维护","note":"撤离记录","ending":"灰湾收到回信"}.get(id,"")))
	if id=="trade": page_title=session.board_destination().name
	if id=="chest": page_title="容器"
	if id=="materials": page_title="材料用途"
	if id=="sources": page_title="物品获取方式"
	if session.stream.generator.revision>=3:
		if id=="map": page_title="荒原地图"
		if id=="ending": page_title="荒原收到回信"
	top.add_child(S.label(page_title,33,S.TEXT))
	S.fill(top)
	top.add_child(S.label("第 %02d 日  %s" % [session.clock.day(),session.clock.time_text()],17,S.MUTED))
	var close := S.button("关闭",func(): game.close_overlay())
	close.custom_minimum_size.x = 88.0
	top.add_child(close)
	S.rule(body,Color("#846358"))
	if id in TABS:
		var nav := S.line(body)
		for key in TABS:
			var tab := S.button(TABS[key],func(): game.open_panel(key),key==id)
			tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nav.add_child(tab)
	match id:
		"bag": _bag()
		"chest":
			var cache:=preload("res://game/ui/chest_panel.gd").new()
			body.add_child(cache)
			cache.out_of_reach.connect(func():
				if visible and active=="chest" and current_context==context: game.close_overlay())
			cache.setup(session,str(context))
		"craft":
			if context is Dictionary:
				current_context = context.cell
				_craft(current_context,context)
			else: _craft(context)
		"skills": _skills()
		"journal": _journal(false)
		"field": _field_notes()
		"sources":
			var guide := preload("res://game/ui/material_guide.gd").new()
			body.add_child(guide)
			var labels := {"bag":"返回背包","field":"返回探索手记","craft":"返回配方"}
			guide.setup(session.catalog,context.item,labels[context.origin],true)
			guide.returned.connect(return_from_sources)
		"materials":
			var guide := preload("res://game/ui/material_guide.gd").new()
			var from_bag := context is String and session.catalog.items.has(context)
			body.add_child(guide)
			guide.setup(session.catalog,str(context) if from_bag else "fiber","返回背包" if from_bag else "返回探索手记")
			guide.returned.connect(func():
				if from_bag: game.open_panel("bag",context)
				else: game.open_panel("field"))
		"achievements":
			var tree := preload("res://game/ui/achievement_tree.gd").new()
			body.add_child(tree)
			tree.setup(session)
			scroll_target=tree.tabs.get_child(0)
		"survivor": _survivor()
		"trade": _journal(true)
		"ending": _ending(context)
		"map": _map()
		"device": _device(context)
		"vehicle": _vehicle(str(context))
		"note":
			var quote := S.label(str(context),24,S.TEXT,true)
			body.add_child(quote)
			S.fill(body)
	if not is_instance_valid(status_line):
		status_line = S.label("",16,S.GOLD,true)
		status_line.custom_minimum_size.y = 21
		body.add_child(status_line)
	show()
	var target := scroll_target if is_instance_valid(scroll_target) else close
	target.grab_focus()

func _open_item_sources(id: String) -> void:
	if not session.catalog.items.has(id): return
	var from := {"item":id,"origin":active}
	if active=="craft":
		from.recipe = {"cell":current_context,"selection":selection,"quantity":craft_quantity,
			"view":recipe_view,"query":recipe_query}
	game.open_panel("sources",from)

func return_from_sources() -> void:
	var from: Dictionary = current_context
	match from.origin:
		"bag": game.open_panel("bag",from.item)
		"craft":
			var resume: Dictionary = from.recipe
			if resume.cell != null and not session.construction.blocks.has(resume.cell):
				game.open_panel("craft")
			else: game.open_panel("craft",resume)
		_: game.open_panel("field")

func update_status(words: String, duration: float) -> void:
	if is_instance_valid(status_line):
		status_left = duration
		status_line.text = words

func _process(delta: float) -> void:
	if not visible or session == null:
		return
	refresh_tick -= delta
	if is_instance_valid(portrait):
		portrait_time -= delta
		if portrait_action == 5 and portrait_time <= 0.0:
			portrait.act("punch")
			portrait_time = 1.35
		var pace := 5.5 if portrait_action == 2 else 2.5 if portrait_action in [1,4] else 0.0
		portrait.pose(delta,pace,1.0 if portrait_action == 3 else 0.0,portrait_action == 4)
	status_left = maxf(0.0,status_left-delta)
	if status_left == 0.0 and is_instance_valid(status_line):
		status_line.text = ""
	if refresh_tick > 0.0:
		return
	refresh_tick = 0.18
	if active == "survivor" and is_instance_valid(survivor_vitals):
		_refresh_survivor()
	if active in ["trade","journal"] and journal_state != _journal_state():
		var words := status_line.text if is_instance_valid(status_line) else ""
		var left := status_left
		show_panel(active,session)
		if left > 0:
			update_status(words,left)
	if is_instance_valid(queue_label):
		_refresh_queue()
		if is_instance_valid(favorite_button):
			var fingerprint := hash([session.bag.counts,session.progress.skills,_station_record().get("molten",{})])
			if fingerprint != recipe_fingerprint:
				recipe_fingerprint = fingerprint
				_filter_recipes(recipe_query)
		_refresh_recipe()
	if is_instance_valid(bag_list):
		var fingerprint := _bag_fingerprint()
		if fingerprint != last_bag_fingerprint:
			_refresh_bag()
		elif warned_item!="" and Time.get_ticks_msec()>warning_until:
			warned_item=""
			_bag_details()
	if is_instance_valid(map_canvas):
		map_canvas.queue_redraw()

func _columns() -> Array[VBoxContainer]:
	var row := S.line(body)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := S.column(row)
	var right := S.column(row)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 292
	return [left,right]

func _bag() -> void:
	bag_taps.key=""
	warned_item=""
	selection=session.bag.current()
	selection_slot=session.bag.active
	if current_context is String and session.bag.count(current_context)>0:
		selection=current_context
		selection_slot=WastelandBag.PACK if session.bag.pack_count(selection)>0 else session.bag.bar.find(selection)
	selection_amount=session.bag.stack_size(selection)
	var columns := _columns()
	var left := columns[0]
	var right := columns[1]
	right.custom_minimum_size.x = 346
	left.add_theme_constant_override("separation",5)
	var heading := S.line(left)
	var meter := S.label("",16,S.MUTED)
	heading.add_child(meter)
	status_line = S.label("",15,S.GOLD)
	status_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(status_line)
	bag_list = S.scroller(left)
	bag_list.set_meta("count_label",meter)
	item_grid=GridContainer.new()
	item_grid.columns=9
	item_grid.name="InventoryGrid"
	item_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item_grid.add_theme_constant_override("h_separation",2)
	item_grid.add_theme_constant_override("v_separation",2)
	bag_list.add_child(item_grid)
	var stage:=preload("res://game/ui/equipment_stage.gd").new()
	stage.name="AvatarEquipmentStage"
	stage.size_flags_vertical=Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel",S.flat(Color("#263830"),Color("#566651"),1,6))
	right.add_child(stage)
	var dressing:=S.line(stage)
	dressing.add_theme_constant_override("separation",4)
	var left_tags:=S.column(dressing,2)
	var left_gear:=S.column(dressing,4)
	left_gear.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var armor:=S.column(left_gear,2)
	armor.name="EquipmentSlots"
	armor.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var slot_nodes:Dictionary={}
	for key:String in ["head","body","legs","feet"]:
		slot_nodes[key]=_equipment_slot(armor,key)
	var studio := ModelStudy.new()
	bag_studio = studio
	studio.name = "BagSurvivor"
	studio.custom_minimum_size = Vector2(122,218)
	studio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dressing.add_child(studio)
	bag_avatar = studio.preview(session.player.profile,session.bag.gear,true)
	studio.resized.connect(studio.frame_equipment.bind(bag_avatar))
	bag_avatar.neck.rotation.x = clampf(session.player.pitch,-0.58,0.65)
	var auxiliary:=S.column(dressing,4)
	auxiliary.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var extras:=S.column(auxiliary,2)
	extras.name="AccessorySlots"
	extras.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	extras.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	for key:String in ["hands","eyes","muzzle","back"]:
		slot_nodes[key]=_equipment_slot(extras,key)
	slot_nodes["pack"]=_equipment_slot(auxiliary,"pack")
	slot_nodes["offhand"]=_equipment_slot(left_gear,"offhand")
	_slot_names(left_tags,slot_nodes,["head","body","legs","feet","offhand"],true)
	_slot_names(S.column(dressing,2),slot_nodes,["hands","eyes","muzzle","back","pack"],false)
	bag_list.set_meta("gear_slots",slot_nodes)
	var held_items := S.line(right)
	for hand: String in ["main","offhand"]:
		var held := S.label("",16,S.MUTED)
		held.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		held.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		held_items.add_child(held)
		bag_list.set_meta(hand+"_label",held)
	var hands:=S.line(right)
	var swap:=S.button("交换双手",func(): session.ui_command("swap_hands",[]))
	swap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hands.add_child(swap)
	var clear:=S.button("移出副手",func(): session.ui_command("offhand",[""]))
	clear.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hands.add_child(clear)
	bag_list.set_meta("clear_offhand",clear)
	var summary:=S.line(left)
	summary.add_theme_constant_override("separation",7)
	item_detail=TextureRect.new()
	item_detail.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	item_detail.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	item_detail.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_detail.custom_minimum_size=Vector2(42,42)
	summary.add_child(item_detail)
	detail_title = S.label("选择一个物品",19,S.GOLD,true)
	detail_title.custom_minimum_size.x=115
	detail_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	summary.add_child(detail_title)
	material_link = S.button("材料用途",func(): game.open_panel("materials",selection))
	detail_description = S.label("",16,S.MUTED,true)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=54
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(detail_description)
	detail_description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	summary.add_child(scroll)
	var links:=S.column(summary,2)
	source_link=S.button("获取方式",func(): _open_item_sources(selection))
	for link:Button in [source_link,material_link]:
		link.custom_minimum_size.y=27
		link.add_theme_font_size_override("font_size",16)
		links.add_child(link)
	var actions:=S.line(left)
	assign_button=S.button("放入当前快捷格",_transfer_selected)
	use_item_button=S.button("使用／装备所选",_consume_selected)
	discard_button=S.button("丢弃 1 件",discard_selected)
	for control in [assign_button,use_item_button,discard_button]: actions.add_child(control)
	for action: Button in actions.get_children(): action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var hotbar_row:=S.line(left)
	var hotbar_label:=S.label("快捷栏",16,S.MUTED)
	hotbar_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	hotbar_row.add_child(hotbar_label)
	quick_slots=S.line(hotbar_row)
	quick_slots.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	quick_slots.add_theme_constant_override("separation",2)
	bag_list.get_parent().resized.connect(_fit_inventory_rows)
	_refresh_bag()
	_bag_details()

func _fit_inventory_rows() -> void:
	if not is_instance_valid(item_grid) or not is_instance_valid(bag_list): return
	var rows := ceili(session.bag.capacity()/9.0)
	var height := (bag_list.get_parent() as ScrollContainer).size.y
	var pitch := clampf(floorf((height-2*(rows-1))/rows),42,49)
	for cell: Control in item_grid.get_children():
		cell.custom_minimum_size.y=pitch

func _slot_names(rail: VBoxContainer, slots: Dictionary, keys: Array, on_left: bool) -> void:
	rail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for key: String in keys:
		var tile: Button = slots[key]
		if key == "offhand" or key == "pack":
			var gap := Control.new()
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rail.add_child(gap)
		var tag := Button.new()
		tag.text = tile.NAMES[key]
		tag.flat = true
		tag.focus_mode = Control.FOCUS_NONE
		tag.alignment = HORIZONTAL_ALIGNMENT_RIGHT if on_left else HORIZONTAL_ALIGNMENT_LEFT
		tag.custom_minimum_size = Vector2(38,tile.custom_minimum_size.y)
		tag.add_theme_font_size_override("font_size",16)
		tag.add_theme_color_override("font_color",S.GOLD if key=="offhand" or key=="pack" else S.MUTED)
		for state: String in ["normal","hover","pressed","focus"]:
			tag.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tag.pressed.connect(tile.pressed.emit)
		rail.add_child(tag)

func _equipment_slot(parent:Control,key:String)->Control:
	var tile:=preload("res://game/ui/equipment_slot.gd").new()
	tile.setup(key)
	parent.add_child(tile)
	tile.accepts=func(data): return data.source in ["bag","hotbar"] and _fits_slot(key,data.item)
	tile.transfer=func(data): _equip_from_bag(key,data.item)
	tile.pressed.connect(func():
		if _fits_slot(key,selection):
			_equip_from_bag(key,selection)
		elif tile.item!="":
			selection=tile.item
			selection_slot=WastelandBag.PACK if session.bag.pack_count(selection)>0 else session.bag.bar.find(selection)
			selection_amount=session.bag.stack_size(selection)
			_bag_details())
	return tile

func _fits_slot(key:String,id:String)->bool:
	if id.is_empty() or session.bag.count(id)<=0: return false
	if key=="offhand": return true
	var item:Dictionary=session.catalog.items.get(id,{})
	return item.get("kind","")=="armor" and item.get("slot","body")==key

func _equip_from_bag(key:String,id:String)->void:
	if not _fits_slot(key,id): return
	if key=="offhand": session.ui_command("offhand",[id])
	elif session.bag.gear.get(key,"")!=id: session.ui_command("quick_equip",[id])

func discard_selected()->void:
	if active!="bag" or not is_instance_valid(discard_button) or discard_button.disabled: return
	var confirm:=warned_item==selection and Time.get_ticks_msec()<=warning_until
	if session.discard_protected(selection):
		if confirm: warned_item=""
		else:
			warned_item=selection
			warning_until=Time.get_ticks_msec()+3200
	session.ui_command("discard",[selection,confirm,selection_slot])
	_refresh_bag()

func _refresh_bag() -> void:
	inventory_buttons.clear()
	for child in item_grid.get_children():
		item_grid.remove_child(child)
		child.queue_free()
	for child in quick_slots.get_children():
		quick_slots.remove_child(child)
		child.queue_free()
	var bag := session.bag
	if is_instance_valid(bag_avatar):
		bag_avatar.apply_outfit(session.player.profile)
		bag_avatar.wear_loadout(bag.gear)
	last_bag_fingerprint = _bag_fingerprint()
	var meter: Label = bag_list.get_meta("count_label")
	var capacity:int=bag.capacity()
	meter.text = "背包格 %02d / %02d    ·    减伤 %d%%" % [bag.occupied(),capacity,roundi(bag.gear_bonus("armor")*100)]
	if bag.occupied()>capacity: meter.text+="　超量物品可取出"
	var slots:Dictionary=bag_list.get_meta("gear_slots")
	for key:String in slots:
		slots[key].update_item(bag.gear.get(key,""),session.catalog)
	var secondary:String=bag.offhand
	bag_list.get_meta("clear_offhand").disabled=secondary.is_empty()
	bag_avatar.set_offhand(secondary,session.player.guarding,session.player.flashlight and not session.player.submerged)
	bag_avatar.set_mainhand(bag.current(),bag.magazine.get(bag.current(),0)>0)
	var main:String=bag.current()
	var updated_outfit := hash([session.player.profile,bag.gear,main])
	if fitted_outfit != updated_outfit:
		fitted_outfit = updated_outfit
		bag_studio.frame_equipment(bag_avatar)
	var main_label: Label = bag_list.get_meta("main_label")
	var other_label: Label = bag_list.get_meta("offhand_label")
	main_label.text="主手　"+(session.catalog.title(main) if main!="" else "空")
	other_label.text="副手　"+(session.catalog.title(secondary) if secondary!="" else "空")
	var ids := bag.counts.keys()
	ids.sort_custom(func(a,b): return str(session.catalog.items[a].kind)<str(session.catalog.items[b].kind) if session.catalog.items[a].kind!=session.catalog.items[b].kind else str(a)<str(b))
	for id in ids:
		var remaining:=bag.pack_count(id)
		while remaining>0:
			var amount:=mini(remaining,bag.stack_size(id))
			remaining-=amount
			var action:=func(): _select_stack(id,WastelandBag.PACK,amount)
			var item_button:=_inventory_tile(id,amount,false,action)
			item_button.taps=bag_taps
			item_button.tap_key=str(item_grid.get_child_count())+":"+str(id)
			item_button.quick_action=_quick_equip.bind(id,amount)
			item_grid.add_child(item_button)
			inventory_buttons.append(item_button)
	for index in range(maxi(0,capacity-inventory_buttons.size())):
		var empty:=_inventory_tile("",0,false,Callable())
		item_grid.add_child(empty)
	_fit_inventory_rows()
	for i in WastelandBag.HOTBAR_SIZE:
		var id:String=bag.bar[i]
		var tile:=_inventory_tile(id,bag.bar_amounts[i],true,func():
			session.ui_command("slot",[i])
			if id!="" or selection_slot>=0: _select_stack(id,i,bag.bar_amounts[i])
			else: _bag_details(),i+1)
		tile.slot_index=i
		tile.taps=bag_taps
		tile.tap_key="hotbar:"+str(i)+":"+id
		if id!="": tile.quick_action=func(): session.ui_command("pack_slot",[i,id])
		tile.accepts=func(data): return data.source in ["bag","hotbar"]
		tile.transfer=func(data):
			if data.source=="bag": session.ui_command("assign_slot",[data.item,i,data.quantity])
			else: session.ui_command("move_slot",[data.slot,i,data.item])
		tile.add_theme_stylebox_override("normal",S.flat(Color("#414233") if bag.active==i else S.PANEL,S.GOLD if bag.active==i else S.BORDER,1,0))
		quick_slots.add_child(tile)
	_bag_details()

func _inventory_tile(id:String,amount:int,quick:bool,action:Callable,number:int=0) -> ItemSlot:
	var tile:=ItemSlot.new()
	tile.item=id
	tile.quantity=amount
	tile.source="hotbar" if quick else "bag"
	if not quick:
		tile.accepts=func(data): return data.source=="hotbar"
		tile.transfer=func(data): session.ui_command("pack_slot",[data.slot,data.item])
	tile.custom_minimum_size=Vector2(42,46) if quick else Vector2(49,49)
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.set_meta("item",id)
	tile.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if action.is_valid() else Control.CURSOR_ARROW
	tile.add_theme_stylebox_override("normal",S.flat(S.PANEL,S.BORDER,1))
	tile.add_theme_stylebox_override("hover",S.flat(Color("#394d40"),S.MINT,1))
	tile.add_theme_stylebox_override("disabled",S.flat(Color("#192725"),Color("#35443e"),1))
	tile.add_theme_stylebox_override("focus",S.flat(Color.TRANSPARENT,S.GOLD,1))
	tile.add_theme_stylebox_override("pressed",S.flat(Color("#414233"),S.GOLD,1))
	if action.is_valid():
		tile.pressed.connect(action)
	else:
		tile.focus_mode=Control.FOCUS_NONE
	if id!="":
		var icon:=TextureRect.new()
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture=WastelandItemArt.icon(id,session.catalog.items[id])
		tile.image=icon.texture
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left=3
		icon.offset_right=-3
		icon.offset_top=3
		icon.offset_bottom=-3
		tile.tooltip_text=session.catalog.title(id)
	for is_number: bool in [false,true]:
		var value:=number if is_number else amount
		if value<=0: continue
		var counter:=S.label(str(value),14,S.GOLD if is_number else S.TEXT)
		counter.mouse_filter=Control.MOUSE_FILTER_IGNORE
		counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT if is_number else HORIZONTAL_ALIGNMENT_RIGHT
		tile.add_child(counter)
		counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if is_number else Control.PRESET_BOTTOM_WIDE)
		counter.offset_left=4
		counter.offset_right=-4
		counter.offset_top=0 if is_number else -19
		counter.offset_bottom=18 if is_number else -1
	return tile

func _select_stack(id:String,source:int,amount:int)->void:
	selection=id
	selection_slot=source
	selection_amount=amount
	_bag_details()

func _transfer_selected()->void:
	if selection_slot>=0:
		session.ui_command("pack_slot",[selection_slot,selection])
	else:
		session.ui_command("assign_slot",[selection,session.bag.active,selection_amount])
	_refresh_bag()

func _bag_details() -> void:
	var bag := session.bag
	var item: Dictionary = session.catalog.items.get(selection,{})
	var active_id: String = bag.current()
	if warned_item!=selection: warned_item=""
	var owned:=selection!="" and bag.source_count(selection,selection_slot)>0
	assign_button.text="收回背包" if selection_slot>=0 else "放入当前快捷格"
	assign_button.disabled=not owned
	use_item_button.disabled=not owned or item.get("kind","") not in ["armor","food","med"]
	discard_button.text="确认丢弃" if warned_item==selection and selection!="" and Time.get_ticks_msec()<=warning_until else "丢弃 1 件"
	discard_button.disabled=not owned or item.get("kind","")=="quest"
	discard_button.tooltip_text="任务物品不能丢弃" if item.get("kind","")=="quest" else "%s · 正在使用的最后一件需要再次确认"%game.options.action_name("discard") if session.discard_protected(selection) else "%s · 丢弃所选物品一件"%game.options.action_name("discard")
	material_link.visible = session.catalog.is_material(selection) and bag.count(selection)>0
	source_link.visible = bag.count(selection)>0 and not item.is_empty()
	var details := "当前快捷格 %d / %s" % [bag.active+1,session.catalog.title(active_id) if active_id!="" else "空"]
	if item.is_empty() or not owned:
		detail_title.text = "选择一个物品"
		details="拖放物品可在背包和快捷栏之间转移。双击快捷格收回背包。\n"+details
		item_detail.texture=null
	else:
		detail_title.text = str(item.name)
		item_detail.texture=WastelandItemArt.icon(selection,item)
		var labels := {"damage":"伤害","food":"饱食","water":"水分","hp":"生命","warmth":"保暖","rating":"装备"}
		var location: String = "快捷格 %d"%(selection_slot+1) if selection_slot>=0 else "背包"
		var lines: Array[String] = ["%s   ·   %s ×%d" % [GROUPS.get(item.kind,item.kind),location,mini(selection_amount,bag.source_count(selection,selection_slot))]]
		var row: Array[String] = []
		for stat in labels:
			if item.has(stat):
				row.append("%s %d" % [labels[stat],int(item[stat])])
				if row.size()==2:
					lines.append("   ·   ".join(row))
					row.clear()
		if not row.is_empty(): lines.append("   ·   ".join(row))
		if item.kind=="armor":
			var slot: String = item.get("slot","body")
			lines.append("%s · 减伤 %d%% · %s" % [WastelandBag.SLOTS[slot],roundi(float(item.get("armor",0))*100),"已穿戴" if bag.gear.get(slot,"")==selection else "未穿戴"])
		if item.has("heat_resist"):
			lines.append("热暴露 −%d%%" % roundi(float(item.heat_resist)*100))
		if item.has("info"): lines.append(str(item.info))
		details = "\n".join(lines)+"\n"+details
	detail_description.text = details
	for tile in inventory_buttons:
		var chosen:bool=selection_slot==WastelandBag.PACK and tile.get_meta("item")==selection
		tile.add_theme_stylebox_override("normal",S.flat(Color("#414233") if chosen else S.PANEL,S.GOLD if chosen else S.BORDER,1))

func _quick_equip(id:String,amount:int)->void:
	if active!="bag" or not visible or session.bag.available_count(id)<=0: return
	session.ui_command("quick_equip",[id,amount])
	if _bag_fingerprint()!=last_bag_fingerprint: _refresh_bag()
	else: _bag_details()

func _consume_selected() -> void:
	var item: Dictionary = session.catalog.items.get(selection,{})
	if session.bag.count(selection)<=0:
		return
	if item.get("kind","") in ["armor","food","med"]:
		session.ui_command("consume",[selection,selection_slot])
	else:
		session.notify("将物品放入快捷栏即可使用")
	_refresh_bag()
	_bag_details()

func _bag_fingerprint() -> int:
	return hash([session.bag.counts,session.bag.active,session.bag.gear,session.bag.bar,session.bag.bar_amounts])

func _craft(context: Variant, resume: Dictionary = {}) -> void:
	recipe_view=resume.get("view","全部")
	recipe_query=resume.get("query","")
	craft_quantity=resume.get("quantity",1)
	craft_collect=null
	station="hand" if context==null else str(session.construction.blocks.get(context,{}).get("device","hand"))
	var columns:=_columns()
	var left:=columns[0]
	var right:=columns[1]
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio=1.08
	left.add_child(S.label(WastelandCatalog.STATIONS.get(station,"随身制作"),21,S.GOLD))
	if station in ["campfire","forge"]: _fire_controls(left,context)
	var filter:=LineEdit.new()
	filter.name="RecipeSearch"
	filter.placeholder_text="搜索配方、成品或材料"
	filter.text=recipe_query
	filter.clear_button_enabled=true
	filter.custom_minimum_size.y=38
	left.add_child(filter)
	var modes:=S.line(left)
	var group:=ButtonGroup.new()
	for mode:String in ["全部","材料齐全","已收藏"]:
		var mode_button:=S.button(mode,func(): recipe_view=mode; _filter_recipes(recipe_query))
		mode_button.toggle_mode=true
		mode_button.button_group=group
		mode_button.button_pressed=mode==recipe_view
		mode_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		modes.add_child(mode_button)
	recipe_list=S.scroller(left)
	filter.text_changed.connect(_filter_recipes)
	filter.text_submitted.connect(func(_query):
		if recipe_list.get_child_count()>0 and recipe_list.get_child(0) is Button:
			recipe_list.get_child(0).grab_focus())
	var product:=S.line(right)
	craft_icon=TextureRect.new()
	craft_icon.custom_minimum_size=Vector2(48,48)
	craft_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	craft_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	craft_icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	product.add_child(craft_icon)
	detail_title=S.label("",22,S.GOLD,true)
	detail_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	product.add_child(detail_title)
	favorite_button=S.button("收藏配方",_toggle_favorite_recipe)
	product.add_child(favorite_button)
	# Materials scroll separately; the craft and queue controls stay within reach.
	var material_scroll:=ScrollContainer.new()
	material_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	material_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	material_scroll.custom_minimum_size.y=68
	right.add_child(S.label("所需材料　·　持有 / 消耗　·　点选查看出处",16,S.MUTED))
	right.add_child(material_scroll)
	detail_description=S.label("",16,S.TEXT,true)
	detail_description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var ingredient_column:=S.column(material_scroll,2)
	ingredient_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ingredient_column.add_child(detail_description)
	craft_materials=GridContainer.new()
	craft_materials.columns=2
	craft_materials.add_theme_constant_override("h_separation",10)
	ingredient_column.add_child(craft_materials)
	var quantities:=S.line(right)
	craft_minus=S.button("−",func(): _set_craft_quantity(craft_quantity-1))
	craft_plus=S.button("＋",func(): _set_craft_quantity(craft_quantity+1))
	craft_max=S.button("最大",func(): _set_craft_quantity(8))
	craft_quantity_label=S.label("",17,S.TEXT)
	craft_quantity_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	craft_quantity_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for node in [craft_minus,craft_quantity_label,craft_plus,craft_max]: quantities.add_child(node)
	craft_submit=S.button("制作 1 次",func():
		var count:=mini(craft_quantity,_craft_limit(selection))
		if count>0: session.ui_command("craft",[selection,count,current_context])
		_refresh_queue()
		_refresh_recipe(),true)
	right.add_child(craft_submit)
	S.rule(right)
	queue_label=S.label("",16,S.MUTED,true)
	right.add_child(queue_label)
	var output_scroll:=ScrollContainer.new()
	output_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	output_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	output_scroll.custom_minimum_size.y=30
	right.add_child(output_scroll)
	craft_outputs=S.line(output_scroll)
	job_buttons=S.line(craft_outputs)
	progress_line=ProgressBar.new()
	progress_line.max_value=1.0
	progress_line.show_percentage=false
	progress_line.custom_minimum_size.y=8
	right.add_child(progress_line)
	var actions:=S.line(right)
	craft_cancel=S.button("取消队尾",func():
		session.ui_command("cancel",[current_context])
		_refresh_queue()
		_refresh_recipe())
	actions.add_child(craft_cancel)
	if context!=null:
		craft_collect=S.button("收取成品",func():
			session.ui_command("collect",[context])
			_refresh_queue()
			_refresh_recipe(),true)
		actions.add_child(craft_collect)
		if station=="campfire": actions.add_child(S.button("休息",func():session.ui_command("rest",[context])))
	if not resume.is_empty(): selection=resume.selection
	elif station=="hand" and session.progress.records.has("first_axe_guide"): selection="stone_axe"
	_filter_recipes(recipe_query)
	if not resume.is_empty(): _scroll_to_recipe.call_deferred()
	_refresh_queue()

func _craft_queue() -> Array:
	return session.hand_queue if current_context==null else session.construction.blocks.get(current_context,{}).get("queue",[])

func _station_record()->Dictionary:
	return session.construction.blocks.get(current_context,{}) if current_context!=null else {}

func _fire_controls(parent:Container,cell:Vector3i)->void:
	var fuel_row:=S.line(parent)
	for id:String in WastelandSession.Fire.FUEL_SECONDS:
		fuel_row.add_child(S.button("加"+session.catalog.title(id),func():session.ui_command("feed_fire",[cell,id])))
	fire_button=S.button("点火",func():session.ui_command("enable",[cell]))
	fuel_row.add_child(fire_button)
	fire_status=S.label("",15,S.MUTED,true)
	parent.add_child(fire_status)
	if station!="forge": return
	var input_row:=S.line(parent)
	var ores:=OptionButton.new()
	ores.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for id:String in WastelandSession.Fire.MELTABLE: ores.add_item(session.catalog.title(id))
	input_row.add_child(ores)
	input_row.add_child(S.button("装入原料",func():session.ui_command("smelt_input",[cell,WastelandSession.Fire.MELTABLE[ores.selected]])))

func _craft_limit(id:String)->int:
	if not session.can_craft(id,station): return 0
	var limit:=maxi(0,8-_craft_queue().size())
	var inputs:Dictionary=session.catalog.recipes[id].inputs
	for material:String in inputs:
		limit=mini(limit,floori(float(WastelandSession.Fire.available(session.bag,_station_record(),material))/int(inputs[material])))
	return limit

func _set_craft_quantity(value:int)->void:
	craft_quantity=clampi(value,1,maxi(1,_craft_limit(selection)))
	_refresh_recipe()

func _filter_recipes(query:String)->void:
	var query_changed:=query!=recipe_query
	recipe_query=query
	var focused:String=""
	for child in recipe_list.get_children():
		if child.has_focus(): focused=child.get_meta("recipe","")
		recipe_list.remove_child(child)
		child.queue_free()
	var filter:=query.strip_edges().to_lower()
	var first_id:=""
	var kept:=false
	for id:String in session.catalog.recipes:
		var data:Dictionary=session.catalog.recipes[id]
		if data.station!=station: continue
		var title:=session.catalog.title(id)
		var haystack:=title+" "+session.catalog.title(data.id)+" "+session.catalog.requirements(data.inputs)
		if filter!="" and not haystack.to_lower().contains(filter): continue
		var unlocked:=session.can_craft(id,station)
		var ready:=unlocked and _craft_limit(id)>0
		if recipe_view=="材料齐全" and not ready: continue
		if recipe_view=="已收藏" and id not in game.options.favorite_recipes: continue
		if first_id=="": first_id=id
		kept=kept or selection==id
		var hint:="可制作" if ready else "缺材料" if unlocked else "需专长"
		var row:=S.button("%s ×%d    ·    %s"%[title,data.amount,hint],func():
			selection=id
			craft_quantity=1
			_refresh_recipe())
		row.icon=WastelandItemArt.icon(data.id,session.catalog.items[data.id])
		row.add_theme_constant_override("icon_max_width",32)
		row.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		row.set_meta("recipe",id)
		row.toggle_mode=true
		row.alignment=HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_color_override("font_color",S.MINT if ready else S.TEXT if unlocked else S.MUTED)
		recipe_list.add_child(row)
		if focused==id: row.grab_focus()
	if first_id=="":
		var empty:="没有匹配的配方。"
		if recipe_view=="材料齐全": empty="没有材料齐全的配方。"
		if recipe_view=="已收藏": empty="当前工作站没有匹配的收藏配方。"
		recipe_list.add_child(S.label(empty,16,S.MUTED,true))
	if not kept:
		selection=first_id
		craft_quantity=1
	_refresh_recipe()
	if query_changed: _scroll_to_recipe.call_deferred()

func _scroll_to_recipe()->void:
	if not is_instance_valid(recipe_list): return
	for child in recipe_list.get_children():
		if child is Button and child.get_meta("recipe","")==selection:
			recipe_list.get_parent().ensure_control_visible(child)
			break

func _toggle_favorite_recipe() -> void:
	if selection.is_empty():
		return
	var favorites: PackedStringArray = game.options.favorite_recipes
	if favorites.has(selection):
		favorites.remove_at(favorites.find(selection))
	else:
		favorites.append(selection)
	game.options.favorite_recipes = favorites
	game.options.save_options()
	_filter_recipes(recipe_query)
	_refresh_recipe()

func _refresh_recipe() -> void:
	var data:Dictionary=session.catalog.recipes.get(selection,{})
	var limit:=_craft_limit(selection)
	craft_quantity=clampi(craft_quantity,1,maxi(1,limit))
	for row in recipe_list.get_children():
		if row is Button: row.set_pressed_no_signal(row.get_meta("recipe","")==selection)
	favorite_button.disabled=data.is_empty()
	favorite_button.text="取消收藏" if selection in game.options.favorite_recipes else "收藏配方"
	craft_minus.disabled=craft_quantity<=1
	craft_plus.disabled=craft_quantity>=limit
	craft_max.disabled=craft_quantity>=limit
	craft_submit.disabled=limit<=0
	craft_submit.text="制作 %d 次"%craft_quantity
	craft_quantity_label.text="%d 次  /  可做 %d 次"%[craft_quantity,limit]
	if data.is_empty():
		detail_title.text="选择配方"
		_show_craft_items(craft_materials,[])
		detail_description.text=""
		craft_icon.texture=null
		return
	craft_icon.texture=WastelandItemArt.icon(data.id,session.catalog.items.get(data.id,{}))
	var total:=int(data.amount)*craft_quantity
	detail_title.text="%s ×%d"%[session.catalog.title(data.id),total]
	var lines:=PackedStringArray()
	var seconds:=float(data.seconds)*craft_quantity*(1.0-session.progress.rank("craft")*0.09)
	lines.append("%s　·　耗时 %.1f 秒"%[session.catalog.title(selection),seconds])
	if not data.skill.is_empty() and not session.can_craft(selection,station):
		lines.append("需要专长　%s %d"%[session.catalog.skills[data.skill[0]].name,data.skill[1]])
	if _craft_queue().size()>=8: lines.append("队列已满")
	var materials:Array=[]
	craft_materials.columns=2 if craft_materials.get_parent_control().size.x>=540 else 1
	for id:String in data.inputs:
		var available:=WastelandSession.Fire.available(session.bag,_station_record(),id)
		var need:=int(data.inputs[id])*craft_quantity
		var title:=session.catalog.title(id)+("（炉存）" if WastelandSession.Fire.uses_stock(_station_record(),id) else "")
		materials.append([id,"%s　%d / %d%s"%[title,available,need,"　缺 %d"%(need-available) if available<need else ""],available<need])
	_show_craft_items(craft_materials,materials)
	detail_description.text="\n".join(lines)

func _show_craft_items(container:Container,entries:Array)->void:
	if container.get_meta("entries",[])==entries: return
	container.set_meta("entries",entries)
	for node in container.get_children():
		container.remove_child(node)
		node.queue_free()
	for entry:Array in entries:
		if container==craft_materials:
			var link:=S.button(entry[1],_open_item_sources.bind(entry[0]))
			link.set_meta("item",entry[0])
			link.alignment=HORIZONTAL_ALIGNMENT_LEFT
			link.icon=WastelandItemArt.icon(entry[0],session.catalog.items[entry[0]])
			link.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			link.add_theme_constant_override("icon_max_width",26)
			link.add_theme_font_size_override("font_size",16)
			link.custom_minimum_size.y=36
			link.tooltip_text="查看%s的获取方式"%session.catalog.title(entry[0])
			if entry[2]: link.add_theme_color_override("font_color",S.RED)
			container.add_child(link)
			continue
		var row:=S.line(container)
		var image:=TextureRect.new()
		image.custom_minimum_size=Vector2(28,28)
		image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		image.texture=WastelandItemArt.icon(entry[0],session.catalog.items[entry[0]])
		row.set_meta("item",entry[0])
		row.tooltip_text=session.catalog.title(entry[0])
		row.add_child(image)
		row.add_child(S.label(entry[1],16,S.RED if entry[2] and container==craft_materials else S.GOLD if entry[2] else S.TEXT))


func _refresh_queue() -> void:
	var record:Dictionary=session.construction.blocks.get(current_context,{}) if current_context!=null else {}
	var queue:=_craft_queue()
	if WastelandSession.Fire.thermal(record) and is_instance_valid(fire_status):
		var lit:=WastelandSession.Fire.lit(record)
		fire_button.text="熄火" if lit else "点火"
		fire_button.disabled=float(record.fuel)<=0
		fire_status.text=("燃烧中" if lit else "已熄火")+"　燃料 %.0f 秒"%float(record.fuel)
		if station=="forge":
			var input:Dictionary=record.get("smelt_input",{})
			var stock:Dictionary=record.get("molten",{})
			var available_stock:={}
			for id:String in stock:
				if int(stock[id])>0: available_stock[id]=stock[id]
			fire_status.text+="\n投料口　"+("空" if input.is_empty() else "%s ×%d"%[session.catalog.title(input.id),input.count])
			fire_status.text+="　炉存　"+("空" if available_stock.is_empty() else session.catalog.requirements(available_stock))
	var goods:Dictionary=record.get("out",{})
	var text:="制作队列　%d / 8"%queue.size()
	craft_cancel.disabled=queue.is_empty()
	if is_instance_valid(craft_collect): craft_collect.disabled=goods.is_empty()
	if queue.is_empty():
		progress_line.value=0.0
	else:
		var first:Dictionary=queue[0]
		var left:=float(first.get("left",maxf(0.0,float(first.done)-session.clock.elapsed)))
		text+="　·　%s ×%d　%.1f 秒"%[session.catalog.title(first.id),first.amount,left]
		progress_line.value=clampf(1.0-left/maxf(0.01,float(first.span)),0.0,1.0)
		craft_cancel.tooltip_text="取消 %s，返还预留材料"%session.catalog.title(queue.back().id)
	if not goods.is_empty(): text+="　·　待领取"
	elif current_context==null and not queue.is_empty(): text+="\n完成后自动收入背包"
	var entries:Array=[]
	var tickets:=queue.map(func(job):return job.get("ticket",-1))
	if job_buttons.get_meta("tickets",[])!=tickets:
		job_buttons.set_meta("tickets",tickets)
		for node in job_buttons.get_children():
			job_buttons.remove_child(node)
			node.queue_free()
		for job:Dictionary in queue:
			var ticket:int=job.get("ticket",-1)
			var cancel:=S.button("× "+session.catalog.title(job.id),func():session.ui_command("cancel",[current_context,ticket]))
			cancel.icon=WastelandItemArt.icon(job.id,session.catalog.items[job.id])
			cancel.add_theme_constant_override("icon_max_width",24)
			cancel.set_meta("job_id",job.id)
			cancel.tooltip_text="取消这项制作，返还预留材料"
			job_buttons.add_child(cancel)
	for id:String in goods:
		entries.append([id,"待领 ×%d"%int(goods[id]),true])
	var products:=craft_outputs.get_node_or_null("Products") as HBoxContainer
	if products==null:
		products=S.line(craft_outputs)
		products.name="Products"
	_show_craft_items(products,entries)
	craft_outputs.get_parent().visible=not entries.is_empty() or not queue.is_empty()
	craft_outputs.get_parent().custom_minimum_size.y=43 if craft_outputs.get_combined_minimum_size().x>craft_outputs.get_parent().size.x else 30
	queue_label.text=text

func _skills() -> void:
	var status := S.label("等级 %d   ·   经验 %d / %d   ·   可用专长点 %d" % [session.progress.level,session.progress.xp,session.progress.goal(),session.progress.points],19,S.GOLD)
	body.add_child(status)
	var list := S.scroller(body)
	var last := ""
	for id in session.catalog.skills:
		var def: Dictionary = session.catalog.skills[id]
		if def.branch != last:
			last = def.branch
			list.add_child(S.label(last,20,S.MINT))
		var row := S.line(list)
		var meta := S.column(row,1)
		meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var requirement := "等级 %d" % (int(def.unlock)+session.progress.rank(id)*2)
		if def.has("requires"):
			requirement += " · %s %d" % [session.catalog.skills[def.requires[0]].name, int(def.requires[1])]
		meta.add_child(S.label("%s    %d / %d    ·    %s" % [def.name,session.progress.rank(id),int(def.max),requirement],19,S.TEXT))
		meta.add_child(S.label(str(def.info),15,S.MUTED,true))
		var learn := S.button("学习",func():
			session.ui_command("learn",[id])
			if not session.replica: show_panel("skills",session),true)
		learn.custom_minimum_size.x = 83
		learn.disabled = not session.progress.can_learn(id,def)
		row.add_child(learn)
		S.rule(list)

func _journal_state() -> int:
	return hash([session.clock.day(), session.clock.horde_active(), session.hordes.wave_index, session.progress.job, session.progress.accepted, session.progress.records, session.progress.dispatch, session.progress.patrol, session.progress.delivery_day, session.bag.counts, session.near_board(true),session.near_ruined_archive()])

func _journal(at_board: bool) -> void:
	journal_state = _journal_state()
	var cols := _columns()
	var main := S.scroller(cols[0])
	var daily_col: VBoxContainer = cols[1]
	daily_col.custom_minimum_size.x = 392
	var daily := S.scroller(daily_col)
	var progress := session.progress
	var current := progress.active_job(session.catalog.quests)
	main.add_child(S.label("驻地联络线　%d / %d" % [progress.job,session.catalog.quests.size()],24,S.GOLD))
	if session.near_board(true):
		at_board=false
		main.add_child(S.button("重建此处公告板（木料 ×3、植物纤维 ×2）",func(): session.ui_command("rebuild_board"),true))
	if session.near_ruined_archive():
		main.add_child(S.button("在保险柜残骸中查找信标散页",func(): session.ui_command("recover_archive"),true))
	if current.is_empty():
		main.add_child(S.label("信标已恢复。各地驻地开放三站巡线，完成后可换取工坊、守夜或远行物资。",18,S.MUTED,true))
		main.add_child(S.button("回看结局",func(): game.open_panel("ending")))
	else:
		var count := progress.job_count(current) if current.record != "beacon" else session.bag.count("beacon_log")
		var ready := progress.accepted and count >= int(current.amount) and session.bag.has_all(current.get("inputs",{}))
		var state := "可以提交" if ready else ("%d / %d" % [mini(count,int(current.amount)),int(current.amount)] if progress.accepted else "待接取")
		main.add_child(S.label("%s   ·   %s" % [current.name,state],21,S.TEXT,true))
		var story := str(current.story)
		if session.stream.generator.revision>=3:
			story = story.replace("湖务站公告板","驻地公告板").replace("在南岸加固","在驻地周围加固").replace("带回湖务站","带回任一驻地公告板")
		main.add_child(S.label(story,17,S.MUTED,true))
		if current.has("inputs"):
			main.add_child(S.label("交付物资　"+session.catalog.requirements(current.inputs),16,S.MINT,true))
		if current.record=="beacon" and progress.accepted:
			var next := "把信标记录带回最近的%s。" % session.board_destination().name if ready else "跟随罗盘前往%s，搜到记录后返回公告板。" % session.beacon_destination().name
			main.add_child(S.label(next,17,S.MINT,true))
		elif current.record=="horde":
			main.add_child(S.label("第 %d 日 22:00 至次日 04:00 守夜。此前守过的血月也计入委托。候夜期间可从公告板登记巡线，换取守夜物资。" % session.clock.next_horde(),16,S.MINT,true))
		main.add_child(S.label("报酬　%s  ·  %d 经验" % [session.catalog.requirements(current.reward),current.xp],16,S.GOLD,true))
		if not progress.patrol.is_empty():
			main.add_child(S.button("追踪主线委托",func():
				game.hud.tracked_marker_id=-1
				game.hud.tracked_expedition="campaign"
				session.track_order("")
				update_status("已追踪主线委托",2.5)))
		if at_board:
			var job_button := S.button("提交委托" if progress.accepted else "揭下委托",func(): session.ui_command("job"),true)
			job_button.disabled = progress.accepted and not ready
			main.add_child(job_button)
			if not job_button.disabled: scroll_target = job_button
	S.rule(main)
	for i in session.catalog.quests.size():
		var state := "已完成" if i < progress.job else ("进行中" if i == progress.job and progress.accepted else ("已张贴" if i == progress.job else "待开放"))
		main.add_child(S.label("%s   ·   %s" % [session.catalog.quests[i].name,state],16,S.MINT if i == progress.job else S.FAINT))
	var settled := progress.delivery_day == session.clock.day()
	var night := session.clock.next_horde()
	var wave := session.hordes.wave_index+1 if session.clock.horde_active() else 1
	var group := session.hordes.formation(night,wave)
	if not group.is_empty():
		daily.add_child(S.label("血月侦报 · 第 %d 夜第 %d 波" % [night,wave],19,S.GOLD))
		daily.add_child(S.label("%s · %s" % [group.name,group.tip],16,S.MINT,true))
		S.rule(daily)
	if progress.job >= 2: _patrol_journal(daily, at_board)
	daily.add_child(S.label("今日交付   ·   %s" % ("已结清" if settled else "任选一份"),21,S.GOLD))
	for order in session.daily_orders():
		daily.add_child(S.label(("%s · " % ("本地" if order.tier=="local" else "远行"))+str(order.name),19,S.TEXT))
		daily.add_child(S.label(str(order.story),16,S.MUTED,true))
		daily.add_child(S.label(str(order.source),16,S.MINT,true))
		daily.add_child(S.button("追踪运单" if order.tier=="expedition" else "追踪材料来源",func():
			game.hud.tracked_marker_id=-1
			game.hud.tracked_expedition=""
			session.track_order(order.id)
			update_status("已在罗盘和地图上追踪",2.5)))
		if order.tier=="expedition" and at_board and not settled and session.progress.dispatch.get("day",0)!=session.clock.day():
			daily.add_child(S.button("登记远行运单",func():
				session.track_order(order.id)
				game.hud.tracked_marker_id=-1
				game.hud.tracked_expedition=""
				session.ui_command("dispatch",[order.id])))
		var need: PackedStringArray = []
		for id in order.inputs:
			need.append("%s %d/%d" % [session.catalog.title(id),session.bag.count(id),order.inputs[id]])
		daily.add_child(S.label("交付　" + "、".join(need),16,S.MINT,true))
		daily.add_child(S.label("领取　%s · %d 经验" % [session.catalog.requirements(order.reward),order.xp],15,S.GOLD,true))
		if at_board and not settled:
			var deliver := S.button("交付这份物资",func(): session.ui_command("deliver",[order.id]))
			deliver.disabled = not session.bag.has_all(order.inputs) or (order.tier=="expedition" and (session.progress.dispatch.get("id","")!=order.id or not session.progress.dispatch.get("signed",false)))
			daily.add_child(deliver)
		S.rule(daily)
	main.add_child(S.label("野外远征",22,S.GOLD))
	for route in preload("res://game/sim/expeditions.gd").journal(session):
		main.add_child(S.label(route.name,17,S.MINT,true))
		main.add_child(S.label(route.desc,16,S.MUTED,true))
		main.add_child(S.button("停止追踪" if game.hud.tracked_expedition==route.route else "在地图和罗盘上追踪",func():
			game.hud.tracked_marker_id=-1
			session.track_order("")
			game.hud.tracked_expedition="" if game.hud.tracked_expedition==route.route else route.route
			show_panel(active,session)))
	if at_board:
		body.add_child(S.button("从物资柜兑换每日储备（%s）" % session.catalog.requirements(WastelandSession.TRADE_COST),func(): session.ui_command("barter")))
	else:
		body.add_child(S.label("最近的%s可接取委托、交付物资或兑换储备。" % session.board_destination().name,16,S.MUTED))

func _patrol_journal(list: VBoxContainer, at_board: bool) -> void:
	var run := session.progress.patrol
	var serial := session.Patrol.completed(session) + 1
	list.add_child(S.label("中继巡线   ·   已完成 %d 趟" % (serial-1),21,S.GOLD))
	if run.is_empty():
		var count := 3 if session.progress.job >= session.catalog.quests.size() else 2
		list.add_child(S.label("本趟共 %d 站，可跨日。途中盘点物资、接修断线或守听电台。结算时任选补给，每三趟额外获得回弹簧 ×4。" % count,16,S.MUTED,true))
		if at_board:
			list.add_child(S.button("登记第 %d 趟巡线" % serial,func():
				_track_patrol()
				session.ui_command("patrol_start",[serial])))
		else: list.add_child(S.label("到任一驻地公告板登记。",16,S.MINT))
	else:
		for index in run.stops.size():
			var leg: Dictionary = run.stops[index]
			var state := "已完成" if index<int(run.index) else ("当前" if index==int(run.index) else "下一站")
			list.add_child(S.label("%s · %s · %s" % [state,session.catalog.sites[leg.site].name,session.Patrol.TITLES[leg.task]],16,S.MINT if index==int(run.index) else S.MUTED,true))
		var leg := session.Patrol.stop(session)
		if not leg.is_empty():
			list.add_child(S.label(session.Patrol.instructions(leg),16,S.TEXT,true))
		else:
			list.add_child(S.label("到任一公告板选领一份补给 · %d 经验" % (run.stops.size()*60),16,S.TEXT,true))
			for crate: String in session.Patrol.CRATES:
				var caption: String = session.Patrol.CRATES[crate]
				if at_board: list.add_child(S.button(caption,func():session.ui_command("patrol_claim",[serial,crate])))
				else: list.add_child(S.label(caption,16,S.MINT,true))
				list.add_child(S.label(session.catalog.requirements(session.Patrol.reward(run,crate)),15,S.GOLD,true))
		list.add_child(S.button("在地图和罗盘追踪巡线",func():
			_track_patrol()
			update_status("已追踪中继巡线",2.5)))
	S.rule(list)

func _track_patrol() -> void:
	game.hud.tracked_marker_id=-1
	session.track_order("")
	game.hud.tracked_expedition="relay_patrol"

func _field_notes() -> void:
	var guide := preload("res://game/ui/field_guide.gd").new()
	guide.session = session
	guide.materials_requested.connect(func(): game.open_panel("materials"))
	guide.sources_requested.connect(func(): _open_item_sources("fiber"))
	body.add_child(guide)

func _ending(receipt: Variant) -> void:
	var progress := session.progress
	if receipt is not Dictionary and progress.job<session.catalog.quests.size():
		body.add_child(S.label("信标尚未恢复。前往驻地公告板接取主线委托。",20,S.MUTED,true))
		return
	var record: Dictionary = receipt if receipt is Dictionary else progress.finish_stats
	var day := int(record.get("day",progress.finish_day))
	var letter := S.column(body,15)
	letter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var station := str(record.get("station","荒原驻地" if session.stream.generator.revision>=3 else "南岸湖务站"))
	letter.add_child(S.label(station+"收报簿",21,S.GOLD))
	letter.add_child(S.label("「%s，收到。这里是远方中继台。昨夜我们收到了你们的信号。请保持这个频率，明早再联络。」" % station,26,S.TEXT,true))
	S.rule(letter)
	letter.add_child(S.label("通关于第 %d 日" % day if day>0 else "这份旧档案没有记下回信日期。",21,S.MINT))
	letter.add_child(S.label("完成主线委托　%d / %d" % [int(record.get("jobs",progress.job)),session.catalog.quests.size()],20,S.TEXT))
	if record.has("nights"):
		letter.add_child(S.label("守过血月 %d 次　·　建造 %d 次　·　搜获物资 %d 次" % [record.nights,record.built,record.searches],17,S.MUTED,true))
	if record.has("save_error"):
		var status := "通关记录已写入主机存档。" if int(record.save_error)==OK else "自动保存失败（错误 %d）。进度仍在本次游戏中，请让主机手动保存。" % int(record.save_error)
		letter.add_child(S.label(status,16,S.MINT if int(record.save_error)==OK else S.RED,true))
	var resume := S.button("继续自由生存",func(): game.close_overlay(),true)
	body.add_child(resume)

func _survivor() -> void:
	var cols := _columns()
	var studio := preload("res://game/ui/model_study.gd").new()
	cols[0].add_child(studio)
	studio.frame(1.13,1.32)
	portrait = WastelandPartyAvatar.new()
	portrait.show_tag = false
	studio.scene.add_child(portrait)
	portrait.wear_loadout(session.bag.gear)
	studio.follow_pointer(portrait,false)
	portrait.rotation.y = -0.52
	var info: VBoxContainer = cols[1]
	info.custom_minimum_size.x = 342
	info.add_theme_constant_override("separation",5)
	info.add_child(S.label("幸存者   /   Lv.%02d" % session.progress.level,24,S.GOLD))
	preload("res://game/ui/wardrobe.gd").picker(info,game,portrait,func():
		studio.frame_survivor(portrait,studio.portrait_zoom)
		_refresh_survivor())
	info.add_child(S.label("经验　%d / %d" % [session.progress.xp, session.progress.goal()],17,S.MUTED))
	S.rule(info)
	survivor_vitals = S.label("",18,S.TEXT)
	info.add_child(survivor_vitals)
	_refresh_survivor()
	var worn: PackedStringArray = []
	for id: String in session.bag.gear.values():
		if not id.is_empty(): worn.append(session.catalog.title(id))
	info.add_child(S.label("防具　" + ("未装备" if worn.is_empty() else "、".join(worn)),16,S.MUTED,true))
	S.fill(info)
	var zoom := S.line(cols[0])
	for view: String in ["全身","半身","面部"]:
		zoom.add_child(S.button(view,func(): studio.frame_survivor(portrait,view)))
	var turn := zoom
	S.fill(turn)
	turn.add_child(S.button("向左转",func(): portrait.rotation.y -= PI/4))
	turn.add_child(S.button("向右转",func(): portrait.rotation.y += PI/4))
	var motion := OptionButton.new()
	motion.tooltip_text = "预览角色动作"
	for caption in ["站立","步行","奔跑","蹲伏","游泳","出拳"]: motion.add_item(caption)
	turn.add_child(motion)
	motion.item_selected.connect(func(index: int):
		portrait_action = index
		portrait_time = 0.0
		studio.frame_survivor(portrait,"全身"))

func _refresh_survivor() -> void:
	if not is_instance_valid(survivor_vitals): return
	var p := session.player
	survivor_vitals.text = "生命　%d / %d\n耐力　%d / %d\n饱食　%d　　水分　%d\n体温　%.1f°" % [roundi(p.health),roundi(p.max_health()),roundi(p.stamina),roundi(p.max_stamina()),roundi(p.hunger),roundi(p.hydration),p.body_temp]
	if p.warm_drink_left>0.0: survivor_vitals.text+="\n暖饮保暖　%d 秒"%ceili(p.warm_drink_left)
	if p.ration_left>0.0: survivor_vitals.text+="\n行军补给　%d 秒"%ceili(p.ration_left)

func _map() -> void:
	var columns := _columns()
	var left := columns[0]
	var right := columns[1]
	right.custom_minimum_size.x = 244
	map_canvas = WastelandMap.new()
	map_canvas.session = session
	map_canvas.hud = game.hud
	left.add_child(map_canvas)
	right.add_child(S.label("自定义标记",23,S.GOLD))
	marker_title = LineEdit.new()
	marker_title.placeholder_text = "标记名称"
	marker_title.max_length=20
	right.add_child(marker_title)
	marker_info = S.label("尚未选中标记",16,S.MUTED,true)
	right.add_child(marker_info)
	marker_delete = S.button("删除选中标记",func():
		session.ui_command("unmark",[map_canvas.selected])
		map_canvas.selected=-1
		marker_delete.disabled=true
		marker_info.text="尚未选中标记")
	marker_delete.disabled=true
	right.add_child(marker_delete)
	var navigate := S.button("在罗盘上追踪", func():
		game.hud.tracked_marker_id = map_canvas.selected
		game.hud.tracked_expedition=""
		session.track_order("")
		map_canvas.queue_redraw()
		update_status("已在罗盘上追踪标记",2.5))
	navigate.disabled = true
	right.add_child(navigate)
	right.add_child(S.button("探索手记",func(): game.open_panel("field")))
	right.add_child(S.button("回到当前位置",map_canvas.reset_center))
	if preload("res://game/ui/touch_controls.gd").supported():
		map_canvas.touch_navigation=true
		var zoom_row:=S.line(right)
		for multiplier:float in [0.8,1.25]:
			var zoom_button:=S.button("缩小" if multiplier<1 else "放大",func(): map_canvas.zoom_at(map_canvas.size*0.5,multiplier))
			zoom_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			zoom_row.add_child(zoom_button)
		right.add_child(S.label("单指拖动平移，双指开合缩放。长按空白处添加标记，轻点已有标记可追踪。",16,S.MUTED,true))
	else:
		right.add_child(S.label("滚轮缩放，拖动平移。右键打点，点选标记可追踪。\n手柄用方向键移动，A 打点。",16,S.MUTED,true))
	map_canvas.mark.connect(func(at: Vector2):
		session.ui_command("marker",[at,marker_title.text])
		marker_title.clear()
		map_canvas.queue_redraw())
	map_canvas.marker_selected.connect(func(id: int):
		for marker in session.marker_records:
			if int(marker.id)==id:
				marker_info.text=str(marker.name)+"\n%.0f，%.0f 米" % [marker.at.x,marker.at.y]
				marker_delete.disabled=false
				navigate.disabled=false
				break)

func _device(cell: Vector3i) -> void:
	var data: Dictionary = session.construction.blocks.get(cell,{})
	if data.is_empty(): return
	body.add_child(S.label(session.catalog.title(data.device),24,S.GOLD))
	var rating: Dictionary = session.catalog.items[data.device]
	var info := "耐久 %.0f   ·   %s" % [float(data.hp),"已通电" if session.construction.powered.has(cell) else "未通电"]
	if rating.has("capacity"): info+="\n电量 %.0f / %.0f" % [float(data.charge),float(rating.capacity)]
	if rating.has("draw"): info+="\n负载 %.0f" % float(rating.draw)
	if data.device=="generator": info+="\n燃料余时 %.0f 秒" % float(data.fuel)
	if data.device=="turret": info+="\n弹药 %d" % int(data.ammo)
	body.add_child(S.label(info,19,S.MUTED,true))
	S.fill(body)
	var row := S.line(body)
	row.add_child(S.button("停用" if data.enabled else "启用",func(): session.ui_command("enable",[cell]); show_panel("device",session,cell),true))
	if data.device in ["generator","turret"]:
		row.add_child(S.button("加注燃料" if data.device=="generator" else "装入重型弹 ×12",func():
			session.ui_command("fuel",[cell])
			show_panel("device",session,cell)))
	body.add_child(S.label("手持接线器，依次对准两台设备使用副动作即可接线。",16,S.MUTED,true))

func _vehicle(id: String) -> void:
	var data: Dictionary = session.vehicle_records.get(id,{})
	if data.is_empty(): return
	body.add_child(S.label(session.catalog.title(data.type),24,S.GOLD))
	var condition := S.label("",19,S.MUTED,true)
	body.add_child(condition)
	var materials := S.label("",18,S.TEXT,true)
	body.add_child(materials)
	S.fill(body)
	var row := S.line(body)
	var repair := S.button("修复摩托艇",func(): session.ui_command("repair_vehicle",[id]),true)
	var refuel := S.button("加注燃料 ×1",func(): session.ui_command("vehicle",[id,false]),true)
	var pack := S.button("收回为套件",func(): session.ui_command("vehicle",[id,true]))
	for button in [repair,refuel,pack]:
		row.add_child(button)
	var refresh := func():
		if not visible or active != "vehicle" or current_context != id:
			return
		var current: Dictionary = session.vehicle_records.get(id, {})
		if current.is_empty():
			game.close_overlay()
			return
		var damaged := bool(current.get("needs_repair", false))
		var bike: bool = current.type == "bicycle"
		var move_focus := repair.has_focus() and not damaged
		var vehicle:WastelandVehicle=session.vehicles.get(id)
		var maximum:=vehicle.max_hp() if is_instance_valid(vehicle) else 0.0
		var hp:=float(current.get("hp",maximum))
		repair.text="修复摩托艇" if damaged else "用维修包维护 +120"
		repair.visible = damaged or hp<maximum
		repair.disabled = not session.bag.has_all(WastelandSession.BOAT_REPAIR) if damaged else session.bag.available_count("field_service_kit")<1
		refuel.visible = not damaged and not bike
		refuel.disabled = session.bag.count("fuel") == 0
		pack.visible = not damaged
		materials.visible = damaged
		if damaged:
			condition.text = "船身漏水。用木料封住裂口，纤维与废铁用来固定补板。"
			var stock := PackedStringArray()
			for item_id in WastelandSession.BOAT_REPAIR:
				stock.append("%s　%d / %d" % [session.catalog.title(item_id),session.bag.count(item_id),WastelandSession.BOAT_REPAIR[item_id]])
			materials.text = "\n".join(stock)
		else:
			condition.text = "脚踏驱动" if bike else "剩余燃料 %.0f　·　背包燃料 ×%d" % [float(current.fuel),session.bag.count("fuel")]
		if not damaged: condition.text += "　·　耐久 %d / %d"%[ceili(hp),ceili(maximum)]
		if move_focus and not repair.visible:
			pack.grab_focus()
	# Remote repairs and the player's inventory arrive with the next world snapshot.
	var timer := Timer.new()
	timer.wait_time = 0.2
	body.add_child(timer)
	timer.timeout.connect(refresh)
	timer.start()
	refresh.call_deferred()
