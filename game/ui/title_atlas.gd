extends VBoxContainer

const S := preload("res://game/ui/style.gd")
const LookPicker := preload("res://game/ui/infected_look_picker.gd")
const FaceSelector := preload("res://game/ui/face_selector.gd")
const TITLES := {"achievements":"成就","terrain":"地形","creatures":"生物","characters":"角色"}
const GROUPS := {"camp":"扎营","craft":"手艺","travel":"远行","wild":"众生","siege":"守夜","odd":"荒诞"}
var catalog: WastelandCatalog
var category := ""
var entries: Array = []
var page_rows := {}
var selection := -1
var tabs := HBoxContainer.new()
var sidebar: VBoxContainer
var list_scroll := ScrollContainer.new()
var list := VBoxContainer.new()
var detail_scroll := ScrollContainer.new()
var detail := VBoxContainer.new()
var page_label := Label.new()
var buttons: Array[Button] = []

func setup(data:WastelandCatalog, back:Callable) -> void:
	catalog=data
	name="TitleAtlas"
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	var heading:=S.line(self)
	heading.add_child(S.label("荒原图鉴",36,S.TEXT))
	S.fill(heading)
	heading.add_child(S.button("返回主菜单",back))
	add_child(tabs)
	for key:String in TITLES:
		var button:=S.button(TITLES[key],choose_category.bind(key))
		button.name=key
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
	var row:=S.line(self)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sidebar=S.column(row,6)
	sidebar.add_child(page_label)
	page_label.add_theme_font_size_override("font_size",16)
	page_label.add_theme_color_override("font_color",S.MUTED)
	sidebar.add_child(list_scroll)
	list_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	list_scroll.follow_focus=true
	list_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.add_child(list)
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var panel:=PanelContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",S.flat(Color("#182726"),S.BORDER,1,14))
	row.add_child(panel)
	panel.add_child(detail_scroll)
	detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus=true
	detail_scroll.focus_mode=Control.FOCUS_ALL
	detail_scroll.gui_input.connect(_detail_input)
	detail_scroll.add_child(detail)
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",9)
	choose_category("terrain")
	tabs.get_node("terrain").grab_focus()

func _detail_input(event:InputEvent) -> void:
	if not detail_scroll.has_focus(): return
	for action in ["ui_down","ui_up"]:
		if event.is_action_pressed(action,true):
			detail_scroll.scroll_vertical+=52 if action=="ui_down" else -52
			detail_scroll.accept_event()
			return

func _clear(box:Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func choose_category(key:String) -> void:
	category=key
	sidebar.custom_minimum_size.x=242 if key=="terrain" else 318
	_clear(list)
	buttons.clear()
	selection=-1
	list_scroll.scroll_vertical=0
	for tab:Button in tabs.get_children():
		tab.add_theme_stylebox_override("normal",S.flat(Color("#3a4336") if tab.name==key else S.PANEL,S.GOLD if tab.name==key else S.BORDER,1,8))
	if not page_rows.has(key):
		page_rows[key]=preload("res://game/core/atlas_unlocks.gd").rows(catalog) if key=="achievements" else preload("res://game/ui/atlas_records.gd").rows(key,catalog)
	entries=page_rows[key]
	var unlocked:=0
	var group:=""
	var grid:GridContainer
	for i in entries.size():
		var item:Dictionary=entries[i]
		var locked:bool=key=="achievements" and not item.get("unlocked",false)
		var at_group:=str(item.get("category",""))
		if key=="achievements" and (i==0 or at_group!=group):
			group=at_group
			list.add_child(S.label(str(GROUPS.get(group,group)),16,S.GOLD))
			grid=GridContainer.new()
			grid.columns=5
			list.add_child(grid)
		var button:=S.button(str(item.get("name","")),select_entry.bind(i))
		button.name="Entry_"+str(i)
		button.set_meta("index",i)
		if key=="achievements":
			button.custom_minimum_size=Vector2(54,41)
			button.text="◆" if not locked else "●"
			button.add_theme_color_override("font_color",S.GOLD if not locked else Color("#26302d"))
			button.add_theme_color_override("font_focus_color",S.GOLD if not locked else Color("#434b43"))
			button.add_theme_stylebox_override("normal",S.flat(Color("#0c1110") if locked else S.PANEL,S.BORDER,1,4))
			grid.add_child(button)
			if not locked: unlocked+=1
		else:
			button.alignment=HORIZONTAL_ALIGNMENT_LEFT
			list.add_child(button)
		buttons.append(button)
	page_label.text=("已解锁 %d / %d"%[unlocked,entries.size()]) if key=="achievements" else "%s  ·  %d 条记录"%[TITLES[key],entries.size()]
	if not entries.is_empty():
		var first:=0
		if key=="achievements":
			var found:=entries.find_custom(func(row:Dictionary):return row.get("unlocked",false))
			if found>=0: first=found
		select_entry(first)
		_reveal_after_layout.call_deferred(key,first)

func _reveal_after_layout(key:String,index:int) -> void:
	await get_tree().process_frame
	if is_inside_tree() and category==key and index==selection:
		list_scroll.ensure_control_visible(buttons[index])

func select_entry(index:int) -> void:
	if index<0 or index>=entries.size(): return
	if category=="terrain" and index==selection: return
	var old:=selection
	selection=index
	for i in [old,index]:
		if i<0: continue
		var locked:bool=category=="achievements" and not entries[i].get("unlocked",false)
		buttons[i].add_theme_stylebox_override("normal",S.flat(Color("#0c1110") if locked else S.PANEL,S.GOLD if i==index else S.BORDER,2 if i==index else 1,4))
	var picker:=detail.get_node_or_null("LookPicker") as LookPicker
	var appearance:=Vector4i.ZERO
	if category=="creatures" and picker!=null and picker.actor.type==entries[index].species:
		appearance=picker.appearance()
	elif category=="creatures":
		var faces:=detail.get_node_or_null("FaceSelector") as FaceSelector
		if faces!=null and faces.species==entries[index].species: appearance.w=faces.variant
	_clear(detail)
	detail_scroll.scroll_vertical=0
	var item:Dictionary=entries[index]
	list_scroll.ensure_control_visible(buttons[index])
	if category!="achievements":
		if category=="terrain":
			var heading:=S.line(detail)
			heading.add_child(S.label(item.name,29,S.TEXT))
			S.fill(heading)
			heading.add_child(S.label(item.subtitle,16,S.GOLD))
		else:
			detail.add_child(S.label(str(item.name),29,S.TEXT,true))
			if item.get("subtitle","")!="": detail.add_child(S.label(str(item.subtitle),16,S.GOLD,true))
		preload("res://game/ui/atlas_records.gd").detail(category,item,catalog,detail,appearance)
		return
	detail.add_child(S.label(str(GROUPS.get(item.get("category",""),"成就")),16,S.GOLD))
	if not item.get("unlocked",false):
		detail.add_child(S.label("未解锁",31,S.MUTED))
		detail.add_child(S.label("在游戏中达成后，这里会收录你的记录。",18,S.FAINT,true))
		return
	detail.add_child(S.label(str(item.name),31,S.TEXT,true))
	detail.add_child(S.label(str(item.desc),19,S.MUTED,true))
	var reward:=str(item.get("reward",""))
	if reward!="" and catalog.items.has(reward):
		S.rule(detail)
		var row:=S.line(detail)
		var icon:=TextureRect.new()
		icon.texture=WastelandItemArt.icon(reward,catalog.items[reward])
		icon.custom_minimum_size=Vector2(51,51)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		row.add_child(S.label("奖励  ·  "+catalog.title(reward),18,S.GOLD))
