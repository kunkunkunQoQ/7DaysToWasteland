extends "res://game/ui/item_slot.gd"

const NAMES := {"head":"头盔","body":"上身","legs":"裤装","feet":"靴子","hands":"手套","eyes":"眼饰","muzzle":"脸饰","back":"背饰","pack":"背包","offhand":"副手"}
const PINE := Color("#1f3530")
const INK := Color("#243c35")
const WASH := Color("#3d5447")
const IVORY := Color("#d6d3ae")
const BRASS := Color("#c6a16a")
const RUST := Color("#cd895e")
var slot: String

func setup(key:String)->void:
	slot=key
	name="Slot_"+key
	set_meta("slot",key)
	custom_minimum_size=Vector2(45,45)
	size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state:String in ["normal","hover","pressed","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func update_item(id:String,catalog:WastelandCatalog)->void:
	item=id
	image=WastelandItemArt.icon(id,catalog.items[id]) if id!="" and catalog.items.has(id) else null
	tooltip_text=NAMES[slot]+" · "+(catalog.title(id) if image else "空")
	queue_redraw()

func _notification(what:int)->void:
	if what in [NOTIFICATION_DRAG_BEGIN,NOTIFICATION_DRAG_END]: queue_redraw()

# The field sketches share a 32-unit square so their line weights stay legible on phones.
func _points(coords:PackedFloat32Array)->PackedVector2Array:
	var result:=PackedVector2Array()
	for i in range(0,coords.size(),2): result.append(Vector2(coords[i],coords[i+1]))
	return result

func _line(coords:PackedFloat32Array,color:=IVORY,width:=1.2)->void:
	draw_polyline(_points(coords),color,width,true)

func _cloth(coords:PackedFloat32Array)->void:
	var outline:=_points(coords)
	draw_colored_polygon(outline,WASH)
	outline.append(outline[0])
	draw_polyline(outline,IVORY,1.2,true)

func _sketch()->void:
	match slot:
		"head":
			_cloth([4,19,6,13,10,9,16,7,21,8,25,12,26,17,22,18,18,21,9,22,4,21])
			_line([6,17,13,15,21,14],BRASS,2)
			_cloth([21,11,26,10,29,12,28,16,23,17,21,15])
			_line([25,12,27,12,26,15],BRASS)
			_line([8,22,10,25,17,24,20,21],BRASS)
		"body":
			_cloth([7,8,11,6,14,10,18,11,21,7,25,9,23,15,25,25,20,27,7,25,9,16])
			_line([10,8,13,14,22,21,23,25],BRASS,1.8)
			_line([22,10,19,15,10,21,9,24],BRASS,1.8)
			_line([8,22,14,23,23,23])
			draw_circle(Vector2(16,17),1.6,RUST,true,-1,true)
		"legs":
			_cloth([9,5,23,7,24,12,23,18,24,26,19,27,16,18,14,14,13,19,10,27,5,25,8,17])
			_line([9,8,16,10,23,10],BRASS,1.7)
			_line([16,10,15,14],BRASS)
			_line([18,15,23,15,22,18,19,18,18,15],BRASS)
			_line([6,23,10,25,12,24],BRASS)
		"feet":
			_cloth([9,6,19,7,18,11,19,15,23,18,27,19,29,22,28,24,22,25,14,24,9,22,5,22,5,17,8,14])
			_line([6,20,11,21,16,22,24,23,28,22],BRASS,1.8)
			_line([12,9,17,10,13,12,17,13,14,15,19,16],BRASS)
			_line([20,18,21,20,26,21])
		"hands":
			_cloth([9,21,7,17,5,13,6,11,8,12,11,16,10,8,11,6,13,7,14,13,14,5,16,4,17,6,17,12,19,6,21,6,21,9,20,14,23,9,25,10,24,14,22,20,18,24,17,27,9,25])
			_line([9,21,14,23,19,23],BRASS,1.7)
			_line([12,16,16,17,18,20],BRASS)
		"eyes":
			_line([3,16,5,12,11,10,17,11,24,8,28,10,29,13],BRASS,1.7)
			_cloth([4,15,10,12,15,13,14,18,11,21,6,20])
			_cloth([18,12,24,10,28,11,27,16,24,18,20,18])
			_line([14,15,16,13,19,14],BRASS,1.7)
			_line([6,17,9,15],BRASS)
			_line([21,15,24,13],BRASS)
		"muzzle":
			_line([9,13,5,10,3,12,4,16,9,19],BRASS)
			_line([23,10,26,7,29,9,28,13,24,17],BRASS)
			_cloth([7,13,13,12,18,9,24,10,23,17,19,22,16,26,12,23,9,19])
			_line([9,15,15,16,22,12],BRASS)
			_line([11,18,16,19,21,16],BRASS)
		"back":
			# Bedroll sling, with its rolled end turned towards the viewer.
			_cloth([4,18,5,15,21,7,25,7,28,10,28,14,26,17,10,25,7,25,4,22])
			_line([5,16,8,15,12,17,13,21,10,24])
			_line([7,18,9,18,10,20,9,22,7,21],BRASS)
			_line([15,11,18,12,20,16,19,20],BRASS,2)
			_line([10,25,14,27,22,24,26,18],BRASS)
		"pack":
			_line([12,9,13,5,17,4,20,7,20,9],BRASS,1.7)
			_cloth([8,11,12,8,21,8,24,12,25,23,22,26,10,27,7,24])
			_line([8,12,11,15,20,16,24,12],BRASS)
			_line([12,12,13,18,15,18,15,14],BRASS,1.5)
			_line([10,20,20,19,22,23,19,25,11,25,10,20])
			_line([8,13,5,17,5,22,8,23],BRASS)
		"offhand":
			_line([7,7,12,5,17,7,18,10],RUST,2.0)
			_line([14,9,11,8,8,9,5,15,5,18,7,20,10,20,16,13,16,10],IVORY,2)
			_line([16,11,11,17],BRASS,2)
			_line([23,12,20,11,17,13,13,20,13,23,15,25,18,25,23,20,26,15,25,13,23,12],BRASS,2)
			_line([24,15,20,20],IVORY,1.8)

func _draw()->void:
	var hover:=is_hovered()
	var focused:=has_focus()
	var drag_data:Variant=get_viewport().gui_get_drag_data()
	var receiving:=drag_data!=null and _can_drop_data(Vector2.ZERO,drag_data)
	var border:=BRASS if focused or receiving else Color("#799383") if hover else Color("#536c5e")
	var sheet:=WastelandUIStyle.flat(PINE.lightened(0.12) if hover or receiving else PINE,border)
	sheet.set_corner_radius_all(5)
	draw_style_box(sheet,Rect2(Vector2(1,1),size-Vector2(2,2)))
	var accent:=RUST if image else BRASS
	draw_line(Vector2(6,4),Vector2(13,4),accent,1.5,true)
	if image:
		draw_texture_rect(image,Rect2(Vector2(5,5),size-Vector2(10,10)),false)
	else:
		var scale_factor:=minf(size.x,size.y)/41
		draw_set_transform((size-Vector2.ONE*32*scale_factor)*0.5,0,Vector2.ONE*scale_factor)
		_sketch()
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	if focused or receiving:
		var rim:=WastelandUIStyle.flat(Color.TRANSPARENT,BRASS,2)
		rim.set_corner_radius_all(5)
		draw_style_box(rim,Rect2(Vector2.ONE,size-Vector2.ONE*2))
	if receiving:
		draw_circle(size-Vector2(8,8),3.5,INK,true,-1,true)
		draw_line(size-Vector2(10,8),size-Vector2(6,8),BRASS,1.4,true)
		draw_line(size-Vector2(8,10),size-Vector2(8,6),BRASS,1.4,true)
