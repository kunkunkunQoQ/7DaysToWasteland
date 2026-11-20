extends VBoxContainer

signal out_of_reach

const S := preload("res://game/ui/style.gd")
const Slot := preload("res://game/ui/item_slot.gd")
var session: WastelandSession
var key := ""
var grids := {}
var labels := {}
var selected := ""
var selected_side := ""
var selected_count := 0
var taps:=Slot.TapPair.new()
var choice := Label.new()
var single: Button
var stack: Button
var everything: Button
var fingerprint := -1
var poll_left := 0.0
var had_view := false

func setup(world:WastelandSession,cache_key:String) -> void:
	session=world
	key=cache_key
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	var row:=S.line(self)
	row.layout_direction=Control.LAYOUT_DIRECTION_LTR
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	for side:String in ["bag","chest"]:
		var column:=S.column(row,4)
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var heading:=S.label("",20,S.GOLD)
		column.add_child(heading)
		labels[side]=heading
		var list:=S.scroller(column)
		var grid:=GridContainer.new()
		grid.columns=WastelandBag.ROW_SIZE if side=="bag" else 6
		grid.add_theme_constant_override("h_separation",2)
		grid.add_theme_constant_override("v_separation",2)
		list.add_child(grid)
		grids[side]=grid
	var actions:=S.line(self)
	choice.add_theme_font_size_override("font_size",16)
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(choice)
	single=S.button("取 1 件",func(): _move(selected_side,selected,1))
	stack=S.button("取这一组",func(): _move(selected_side,selected,selected_count))
	everything=S.button("全部取出",func(): session.ui_command("chest_all",[key]))
	for entry in [single,stack,everything]: actions.add_child(entry)
	refresh()

func _process(dt:float)->void:
	poll_left-=dt
	if poll_left<=0.0 and is_visible_in_tree() and is_instance_valid(session):
		poll_left=0.12
		refresh()

func refresh()->void:
	if not is_instance_valid(session): return
	var view:=session.chest_view(key)
	if had_view and view.is_empty():
		had_view=false
		out_of_reach.emit()
		return
	had_view=not view.is_empty()
	var next_hash:=hash([view,session.bag.counts,session.bag.capacity(),selected,selected_side,selected_count])
	if next_hash==fingerprint: return
	fingerprint=next_hash
	var contents:Dictionary=view.get("items",{})
	var available:=int((contents if selected_side=="chest" else session.bag.counts).get(selected,0))
	selected_count=mini(selected_count,available)
	if available<=0: selected=""
	labels.chest.text="%s　%d / %d" % [view.get("title","箱子"),view.get("used",0),view.get("slots",24)]
	labels.bag.text="背包　%d / %d" % [session.bag.occupied(),session.bag.capacity()]
	_grid("chest",contents,int(view.get("slots",24)))
	_grid("bag",session.bag.counts,session.bag.capacity())
	var take:=selected_side=="chest"
	var transfer_hint:="双击或拖动整组转移" if preload("res://game/ui/touch_layout.gd").active else "Shift＋左键或双击可转移整组"
	choice.text=session.catalog.title(selected) if selected!="" else transfer_hint
	single.text="取 1 件" if take or selected=="" else "存 1 件"
	stack.text="取这一组" if take or selected=="" else "存这一组"
	var cap:=0
	if selected!="":
		cap=session.bag.room_for(selected) if take else mini(session.bag.available_count(selected),session.cache_inventory.room(session,contents,selected))
	single.disabled=selected.is_empty() or view.is_empty() or cap<=0
	stack.disabled=single.disabled
	if selected!="" and cap<=0:
		choice.text+="　·　"+("背包已满" if take else "箱子已满")
	everything.disabled=view.is_empty() or not contents.keys().any(func(id):return session.bag.room_for(id)>0)

func _grid(side:String,items:Dictionary,capacity:int)->void:
	var grid:GridContainer=grids[side]
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var ids:=items.keys()
	ids.sort()
	for id:String in ids:
		var left:=int(items[id])
		while left>0:
			var count:=mini(left,session.bag.stack_size(id))
			grid.add_child(_slot(side,id,count))
			left-=count
	while grid.get_child_count()<capacity: grid.add_child(_slot(side,"",0))

func _slot(side:String,id:String,count:int)->Slot:
	var tile:=Slot.new()
	tile.item=id
	tile.source=side
	tile.quantity=count
	tile.custom_minimum_size=Vector2(49,49) if side=="bag" else Vector2(53,48)
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("normal",S.flat(Color("#343233"),S.GOLD if id!="" and id==selected and side==selected_side else S.BORDER,1,0))
	tile.accepts=func(data): return data.source!=side and data.source in ["bag","chest"]
	tile.transfer=func(data): _move(data.source,data.item,data.quantity)
	if id.is_empty():
		tile.focus_mode=Control.FOCUS_NONE
		return tile
	tile.taps=taps
	tile.tap_key=side+":"+str(grids[side].get_child_count())+":"+id
	tile.quick_action=_move.bind(side,id,count)
	tile.image=WastelandItemArt.icon(id,session.catalog.items[id])
	tile.icon=tile.image
	tile.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	tile.add_theme_constant_override("icon_max_width",32)
	tile.tooltip_text=session.catalog.title(id)
	var counter:=S.label(str(count),14,S.TEXT)
	counter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	tile.add_child(counter)
	counter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	counter.offset_top=-18
	counter.offset_right=-3
	tile.pressed.connect(func():
		selected=id
		selected_side=side
		selected_count=count
		refresh.call_deferred())
	return tile

func _move(side:String,id:String,count:int)->void:
	if id.is_empty() or count<=0 or not is_visible_in_tree() or not is_instance_valid(session): return
	session.ui_command("chest_take" if side=="chest" else "chest_put",[key,id,count])
	refresh.call_deferred()
