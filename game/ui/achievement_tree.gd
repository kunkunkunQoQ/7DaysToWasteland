extends VBoxContainer

const S := preload("res://game/ui/style.gd")
const ROUTES := {"camp":"扎营","craft":"手艺","travel":"远行","wild":"众生","siege":"守夜","odd":"荒诞"}
const COLORS := {"camp":Color("#a5c59a"),"craft":Color("#e1b283"),"travel":Color("#90c9d4"),"wild":Color("#b4c984"),"siege":Color("#da9a88"),"odd":Color("#bea3d4")}
var session: Node
var route := "camp"
var selected := ""
var tabs := HBoxContainer.new()
var scroll := ScrollContainer.new()
var graph: RoutesCanvas
var detail := VBoxContainer.new()

var signature := 0
var timer := 0.0
var buttons := {}

class RoutesCanvas extends Control:
	var edges: Array = []
	func _draw() -> void:
		for edge in edges:
			var a: Vector2=edge[0]
			var b: Vector2=edge[1]
			var middle:=Vector2((a.x+b.x)/2,a.y)
			draw_polyline(PackedVector2Array([a,middle,Vector2(middle.x,b.y),b]),edge[2],2.0,true)

func setup(owner_session: Node) -> void:
	session=owner_session
	name="AchievementTree"
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",9)
	add_child(tabs)
	for key: String in ROUTES:
		var action:=S.button(ROUTES[key],choose_route.bind(key))
		action.name=key
		action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tabs.add_child(action)
	var row:=S.line(self)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.follow_focus=true
	scroll.gui_input.connect(_scroll_route)
	row.add_child(scroll)
	graph=RoutesCanvas.new()
	graph.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(graph)
	var info:=PanelContainer.new()
	info.custom_minimum_size.x=243
	info.add_theme_stylebox_override("panel",S.flat(S.PANEL,S.BORDER,1,13))
	row.add_child(info)
	info.add_child(detail)
	detail.add_theme_constant_override("separation",10)
	choose_route(route)

func _scroll_route(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var direction:=1 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -1
		if scroll.get_v_scroll_bar().visible and not event.shift_pressed:
			return
		scroll.scroll_horizontal+=direction*70
		scroll.accept_event()

func choose_route(key: String) -> void:
	route=key
	selected=""
	scroll.scroll_vertical=0
	scroll.scroll_horizontal=0
	rebuild()

func _process(delta: float) -> void:
	timer-=delta
	if timer>0: return
	timer=0.4
	var next:=hash(session.progress.achieved)
	if next!=signature:
		signature=next
		rebuild()

func rebuild() -> void:
	var old_focus:=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_id: String=old_focus.get_meta("achievement","") if old_focus else ""
	for node in graph.get_children():
		graph.remove_child(node)
		node.queue_free()
	graph.edges=[]
	buttons.clear()
	var entries: Array=[]
	var levels:={}
	for entry: Dictionary in session.achievements.entries:
		if entry.category==route: entries.append(entry)
	for entry: Dictionary in entries:
		var depth:=0
		var parent:=str(entry.get("parent",""))
		var visited:={}
		while parent!="" and not visited.has(parent):
			var match_index:=entries.find_custom(func(other:Dictionary): return other.id==parent)
			if match_index<0: break
			visited[parent]=true
			depth+=1
			parent=str(entries[match_index].get("parent",""))
		if not levels.has(depth): levels[depth]=[]
		levels[depth].append(entry)
	var centers:={}
	var lanes:=1
	for siblings: Array in levels.values(): lanes=maxi(lanes,siblings.size())
	for depth in range(levels.size()):
		var group:Array=levels[depth]
		for i in group.size():
			var e:Dictionary=group[i]
			var unlocked:bool=session.achievements.unlocked(e.id)
			var button:=S.button("◆ "+str(e.name)+"\n已达成" if unlocked else "未解锁",select.bind(e.id))
			button.name="Node_"+str(e.id)
			button.mouse_filter=Control.MOUSE_FILTER_PASS
			button.set_meta("achievement",e.id)
			button.size=Vector2(162,66)
			button.position=Vector2(12+depth*195,12+((lanes-group.size())*0.5+i)*82)
			button.add_theme_font_size_override("font_size",17)
			button.add_theme_color_override("font_color",COLORS[route] if unlocked else Color("#989ba1"))
			if not unlocked:
				for state in ["hover","pressed","hover_pressed"]:
					button.add_theme_stylebox_override(state,S.flat(Color("#17191b"),Color("#63676a"),1,5))
			graph.add_child(button)
			buttons[e.id]=button
			centers[e.id]=button.position+Vector2(81,33)

	for e:Dictionary in entries:
		if centers.has(e.get("parent","")):
			var revealed:bool=session.achievements.unlocked(e.id) and session.achievements.unlocked(e.parent)
			graph.edges.append([centers[e.parent]+Vector2.RIGHT*81,centers[e.id]-Vector2.RIGHT*81,COLORS[route] if revealed else Color("#343639")])
	graph.custom_minimum_size=Vector2(12+levels.size()*195,24+lanes*82)
	graph.queue_redraw()
	for button:Button in tabs.get_children():
		button.modulate=COLORS[route] if button.name==route else Color.WHITE
	if entries.size()>0: select(selected if buttons.has(selected) else entries[0].id)
	if buttons.has(focus_id): buttons[focus_id].grab_focus()

func select(id:String) -> void:
	selected=id
	for node in detail.get_children():
		detail.remove_child(node)
		node.queue_free()
	for key: String in buttons:
		var earned: bool=session.achievements.unlocked(key)
		var border: Color=COLORS[route] if earned and key==id else S.BORDER
		if not earned: border=Color("#66696c") if key==id else Color("#303236")
		buttons[key].add_theme_stylebox_override("normal",S.flat(S.PANEL if earned else Color("#101113"),border,2 if key==id else 1,5))
	if not session.achievements.unlocked(id):
		detail.add_child(S.label("未解锁",24,S.MUTED))
		return
	var entry:Dictionary=session.achievements.by_id[id]
	detail.add_child(S.label(ROUTES[route]+"　已达成",16,COLORS[route]))
	detail.add_child(S.label(str(entry.name),24,S.TEXT,true))
	detail.add_child(S.label(str(entry.desc),17,S.MUTED,true))
	S.fill(detail)
	var reward:=str(entry.get("reward",""))
	if reward!="" and session.catalog.items.has(reward):
		var row:=S.line(detail)
		var icon:=TextureRect.new()
		icon.custom_minimum_size=Vector2(46,46)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture=WastelandItemArt.icon(reward,session.catalog.items[reward])
		row.add_child(icon)
		var title:=S.label(str(session.catalog.items[reward].name),17,S.TEXT,true)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(title)
		detail.add_child(S.label("奖励已发放" if session.achievements.rewarded(id) else "达成时自动发放",15,S.GOLD))
