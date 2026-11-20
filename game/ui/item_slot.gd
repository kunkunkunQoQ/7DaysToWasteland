extends Button

var item := ""
var source := ""
var quantity := 0
var image: Texture2D
var accepts: Callable
var transfer: Callable
var taps: TapPair
var tap_key := ""
var quick_action: Callable
var press_point:=Vector2.ZERO
var tap_down:=false
var pressed_at:=0

class TapPair:
	var key:=""
	var at:=Vector2.ZERO
	var time:=0

	func released(id:String,point:Vector2)->bool:
		var now:=Time.get_ticks_msec()
		var twice:=key==id and now-time<=440 and point.distance_squared_to(at)<=100
		key="" if twice else id
		time=now
		at=point
		return twice

func _gui_input(event:InputEvent)->void:
	if taps==null or not quick_action.is_valid(): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.canceled:
			tap_down=false
			taps.key=""
		elif event.pressed and event.shift_pressed and source in ["bag","chest"] and transfer.is_valid():
			tap_down=false
			taps.key=""
			quick_action.call_deferred()
			accept_event()
		elif event.pressed:
			press_point=event.position
			pressed_at=Time.get_ticks_msec()
			tap_down=true
		else:
			var tapped:=tap_down and Time.get_ticks_msec()-pressed_at<=440 and Rect2(Vector2.ZERO,size).has_point(event.position)
			if not tapped: taps.key=""
			elif taps.released(tap_key,get_global_transform()*event.position):
				quick_action.call_deferred()
			tap_down=false
	elif event is InputEventMouseMotion and tap_down and event.position.distance_squared_to(press_point)>64:
		tap_down=false
		taps.key=""

func _get_drag_data(_position: Vector2) -> Variant:
	if item.is_empty() or source.is_empty(): return null
	tap_down=false
	if taps: taps.key=""
	var ghost := TextureRect.new()
	ghost.texture = image
	ghost.custom_minimum_size=Vector2(48,48)
	ghost.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(ghost)
	return {"item":item,"source":source,"quantity":quantity}

func _can_drop_data(_position:Vector2,data:Variant)->bool:
	return data is Dictionary and data.has_all(["item","source","quantity"]) and accepts.is_valid() and accepts.call(data)

func _drop_data(position:Vector2,data:Variant)->void:
	if transfer.is_valid() and _can_drop_data(position,data): transfer.call(data)
