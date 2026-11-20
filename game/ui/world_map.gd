class_name WastelandMap
extends Control

signal mark(at: Vector2)
signal marker_selected(id: int)
const S := preload("res://game/ui/style.gd")
const TILE_SIZE := WastelandTerrainGen.SIZE
var session: WastelandSession
var hud: WastelandHUD
var cache: Dictionary = {}
var center := Vector2.ZERO
var zoom := 2.85
var dragging := false
var drag_distance := 0.0
var selected := -1
var touch_navigation := false
var contacts := {}
var press_origin := Vector2.ZERO
var hold_until := 0
var gesture_moved := false

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	custom_minimum_size = Vector2(565,385)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	reset_center()

func reset_center() -> void:
	if session != null:
		center = Vector2(session.player.global_position.x, session.player.global_position.z)
	queue_redraw()

func _process(_delta:float) -> void:
	if hold_until>0 and Time.get_ticks_msec()>=hold_until and contacts.size()==1:
		hold_until=0
		gesture_moved=true
		if not _choose(press_origin): mark.emit(_to_world(press_origin))

func _touch(event:InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		contacts[event.index]=event.position
		if contacts.size()==1:
			press_origin=event.position
			gesture_moved=false
			hold_until=Time.get_ticks_msec()+520
		else:
			gesture_moved=true
			hold_until=0
	elif contacts.has(event.index):
		if not event.canceled and contacts.size()==1 and not gesture_moved:
			_choose(event.position)
		contacts.erase(event.index)
		hold_until=0

func _drag(event:InputEventScreenDrag) -> void:
	if not contacts.has(event.index): return
	var previous:Vector2=contacts[event.index]
	contacts[event.index]=event.position
	if contacts.size()==2:
		var fingers:=contacts.keys()
		var peer:Vector2=contacts[fingers[1] if fingers[0]==event.index else fingers[0]]
		var span:=previous.distance_to(peer)
		if span>1.0:
			var anchor:=_to_world((previous+peer)*0.5)
			zoom=clampf(zoom*event.position.distance_to(peer)/span,0.32,8.5)
			center+=anchor-_to_world((event.position+peer)*0.5)
	elif contacts.size()==1:
		if not gesture_moved and event.position.distance_to(press_origin)<8: return
		center-=(event.position-(previous if gesture_moved else press_origin))/zoom
	gesture_moved=true
	hold_until=0
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if touch_navigation:
		if event is InputEventScreenTouch:
			_touch(event)
			accept_event()
			return
		if event is InputEventScreenDrag:
			_drag(event)
			accept_event()
			return
		if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION:
			accept_event()
			return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom_at(event.position,1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.87)
			accept_event()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			mark.emit(_to_world(event.position))
			accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				drag_distance = 0.0
			elif drag_distance < 6.0:
				_choose(event.position)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		center -= event.relative / zoom
		drag_distance += event.relative.length()
		queue_redraw()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		mark.emit(center)
		accept_event()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		center.y += (-28.0 if event.is_action_pressed("ui_up") else 28.0) / zoom
		queue_redraw()
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		center.x += (-28.0 if event.is_action_pressed("ui_left") else 28.0) / zoom
		queue_redraw()
		accept_event()

func zoom_at(point: Vector2,factor: float) -> void:
	var target:=_to_world(point)
	zoom=clampf(zoom*factor,0.32,8.5)
	center+=target-_to_world(point)
	queue_redraw()

func _choose(point: Vector2) -> bool:
	for row in session.marker_records:
		if _on_screen(row.at).distance_to(point) < (22.0 if touch_navigation else 12.0):
			selected = int(row.id)
			marker_selected.emit(selected)
			queue_redraw()
			return true
	return false

func _on_screen(at: Vector2) -> Vector2:
	return (at-center)*zoom+size*0.5

func _to_world(at: Vector2) -> Vector2:
	return (at-size*0.5)/zoom+center

func _draw() -> void:
	if session == null:
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color("#202c29"))
	for stripe in range(-ceili(size.y), ceili(size.x), 19):
		draw_line(Vector2(stripe,0), Vector2(stripe+size.y,size.y), Color("#283530"),1)
	var start := WastelandTerrainGen.chunk_at(_to_world(Vector2.ZERO))
	var ending := WastelandTerrainGen.chunk_at(_to_world(size))
	var tile_budget := 4
	var pending := false
	for z in range(start.y,ending.y+1):
		for x in range(start.x,ending.x+1):
			var cell := Vector2i(x,z)
			var tile := Rect2(_on_screen(Vector2(cell*TILE_SIZE)),Vector2.ONE*TILE_SIZE*zoom+Vector2.ONE)
			if session.stream.discovered.has(WastelandTerrainGen.grid_key(cell)):
				if not cache.has(cell) and tile_budget>0:
					cache[cell] = _tile(cell)
					tile_budget -= 1
				if cache.has(cell):
					draw_texture_rect(cache[cell],tile,false)
				else:
					pending = true
				var id := session.stream.generator.site_for(cell)
				if id != "" and zoom > 0.72:
					var at := tile.get_center()
					draw_rect(Rect2(at-Vector2(4,4),Vector2(9,9)),S.INK)
					draw_rect(Rect2(at-Vector2(3,3),Vector2(7,7)),S.GOLD)
					if zoom > 2.0:
						var label: String = session._station_name(cell) if id=="lodge" else session.catalog.sites[id].name
						draw_string(S.FONT, at+Vector2(8,-8),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,S.TEXT)
			draw_rect(tile,Color(0.16,0.23,0.20,0.40),false,1.0)
	if pending:
		queue_redraw.call_deferred()
	var player := session.player
	var point := _on_screen(Vector2(player.global_position.x,player.global_position.z))
	var route := hud.destination() if hud != null else {}
	if not route.is_empty():
		var end := _on_screen(route.at)
		draw_dashed_line(point,end,Color("#e6c288"),1.5,6)
		draw_arc(end,9,0,TAU,16,S.GOLD,2)
	var heading := -player.global_basis.z
	var angle := atan2(heading.x,-heading.z)
	draw_circle(point,10.0,Color(0.08,0.065,0.11,0.91))
	draw_colored_polygon(PackedVector2Array([
		point+Vector2(0,-9).rotated(angle),point+Vector2(6,6).rotated(angle),point+Vector2(0,3).rotated(angle),point+Vector2(-6,6).rotated(angle)]),Color("#fff5dc"))
	for row in session.marker_records:
		var at := _on_screen(row.at)
		var tint := S.GOLD if selected == int(row.id) else S.MINT
		draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7),at+Vector2(7,0),at+Vector2(0,7),at+Vector2(-7,0)]),tint)
		if zoom > 1.15:
			draw_string(S.FONT,at+Vector2(10,6),str(row.name),HORIZONTAL_ALIGNMENT_LEFT,-1,14,S.TEXT)
	draw_rect(Rect2(Vector2.ZERO,size),S.BORDER,false,2)
	draw_rect(Rect2(Vector2(9,9),Vector2(32,29)),S.INK)
	draw_string(S.FONT,Vector2(17,30),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,16,S.GOLD)
	var middle_cell := WastelandTerrainGen.chunk_at(center)
	if session.stream.discovered.has(WastelandTerrainGen.grid_key(middle_cell)):
		var name_at_center := session.stream.generator.landform(center.x,center.y)
		var label_width := S.FONT.get_string_size(name_at_center,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_rect(Rect2(Vector2(47,9),Vector2(label_width+16,29)),S.INK)
		draw_string(S.FONT,Vector2(55,30),name_at_center,HORIZONTAL_ALIGNMENT_LEFT,-1,16,S.TEXT)
	var meters := maxi(10, roundi(68.0 / zoom / 10.0) * 10)
	var scale := meters * zoom
	var at := Vector2(16,size.y-17)
	draw_rect(Rect2(at-Vector2(8,23),Vector2(maxf(scale+16,85),29)),S.INK)
	draw_line(at,at+Vector2(scale,0),S.GOLD,2)
	draw_string(S.FONT,at+Vector2(0,-6),"%d 米" % meters,HORIZONTAL_ALIGNMENT_LEFT,-1,14,S.TEXT)

func _tile(cell: Vector2i) -> ImageTexture:
	var gen := session.stream.generator
	const SAMPLES := 20
	var image := Image.create_empty(SAMPLES,SAMPLES,false,Image.FORMAT_RGB8)
	var from := Vector2(cell*TILE_SIZE)
	var site := gen.site_for(cell)
	var site_center := from+Vector2.ONE*TILE_SIZE*0.5
	var spacing := float(TILE_SIZE) / SAMPLES
	var heights := PackedFloat32Array()
	for y in range(-1,SAMPLES):
		for x in range(-1,SAMPLES):
			var p := from + Vector2(x+0.5,y+0.5) * spacing
			heights.append(gen.ground(p.x,p.y,site,site_center))
	for y in SAMPLES:
		for x in SAMPLES:
			var i := (y+1)*(SAMPLES+1)+x+1
			var height := heights[i]
			var p := from + Vector2(x+0.5,y+0.5) * spacing
			var tint: Color
			if height < 0 and gen.water_basin(p.x,p.y):
				tint = Color("#85ae9c").lerp(Color("#376477"), smoothstep(0.1,8.0,-height))
			else:
				if gen.revision>=3:
					tint = gen.ground_color(p.x,p.y,height)
				else:
					tint = Color("#788b6a").lerp(Color("#d0bd93"),smoothstep(3,37,height))
				var slope := (height-heights[i-1]+height-heights[i-SAMPLES-1])/spacing
				tint *= clampf(1.0+slope*0.18,0.68,1.17)
				if floori(height/5) != floori(heights[i-1]/5) or floori(height/5) != floori(heights[i-SAMPLES-1]/5):
					tint = tint.darkened(0.18)
				if gen.revision<3:
					tint = tint.lerp(Color("#d4b382"),gen.road_strength(p.x,p.y)*0.85)
			image.set_pixel(x,y,tint)
	return ImageTexture.create_from_image(image)
