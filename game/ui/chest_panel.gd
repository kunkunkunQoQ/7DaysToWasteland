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
var selected_slot := WastelandBag.PACK
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
		if side=="bag":
			list.add_child(S.label("快捷栏",16,S.MUTED))
			var quick:=GridContainer.new()
			quick.columns=WastelandBag.HOTBAR_SIZE
			quick.add_theme_constant_override("h_separation",2)
			list.add_child(quick)
			grids.quick=quick
	var actions:=S.line(self)
	choice.add_theme_font_size_override("font_size",16)
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(choice)
	single=S.button("取 1 件",func(): _move(selected_side,selected,1,selected_slot))
	stack=S.button("取这一组",func(): _move(selected_side,selected,selected_count,selected_slot))
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
	var bag:=session.bag
	var next_hash:=hash([view,bag.counts,bag.bar,bag.bar_amounts,bag.capacity(),selected,selected_side,selected_slot,selected_count])
	if next_hash==fingerprint: return
	fingerprint=next_hash
	var contents:Dictionary=view.get("items",{})
	var available:=int(contents.get(selected,0)) if selected_side=="chest" else bag.source_count(selected,selected_slot)
	selected_count=mini(selected_count,available)
	if available<=0: selected=""
	labels.chest.text="%s　%d / %d" % [view.get("title","箱子"),view.get("used",0),view.get("slots",24)]
	labels.bag.text="背包　%d / %d" % [session.bag.occupied(),session.bag.capacity()]
	_grid("chest",contents,int(view.get("slots",24)))
	var packed:Dictionary={}
	for id:String in bag.counts:
		var in_pack:=bag.pack_count(id)
		if in_pack>0: packed[id]=in_pack
	_grid("bag",packed,bag.capacity())
	var quick:GridContainer=grids.quick
	for child in quick.get_children():
		quick.remove_child(child)
		child.queue_free()
	for i in WastelandBag.HOTBAR_SIZE:
		quick.add_child(_slot("quick",bag.bar[i],bag.bar_amounts[i],i))
	var take:=selected_side=="chest"
	var transfer_hint:="双击或拖动整组转移" if preload("res://game/ui/touch_layout.gd").active else "Shift＋左键或双击可转移整组"
	choice.text=session.catalog.title(selected) if selected!="" else transfer_hint
	single.text="取 1 件" if take or selected=="" else "存 1 件"
	stack.text="取这一组" if take or selected=="" else "存这一组"
	var cap:=0
	if selected!="":
		cap=bag.room_for(selected) if take else mini(available,session.cache_inventory.room(session,contents,selected))
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

func _slot(side:String,id:String,count:int,index:=WastelandBag.PACK)->Slot:
	var tile:=Slot.new()
	tile.item=id
	tile.source="chest" if side=="chest" else "bag"
	tile.slot_index=index
	tile.quantity=count
	tile.custom_minimum_size=Vector2(53,48) if side=="chest" else Vector2(49,49)
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var chosen:=id!="" and id==selected and side==selected_side and index==selected_slot
	tile.add_theme_stylebox_override("normal",S.flat(Color("#343233"),S.GOLD if chosen else S.BORDER,1,0))
	tile.accepts=func(data):
		if data.source=="chest":
			return side!="chest" and session.bag.room_for(data.item,index)>0
		return data.source=="bag" and (side=="chest" or int(data.get("slot",WastelandBag.PACK))!=index)
	tile.transfer=func(data): _drop_stack(data,side,index)
	if side=="quick":
		var number:=S.label(str(index+1),12,S.MUTED)
		number.mouse_filter=Control.MOUSE_FILTER_IGNORE
		tile.add_child(number)
		number.position=Vector2(3,0)
	if id.is_empty():
		tile.focus_mode=Control.FOCUS_NONE
		return tile
	tile.taps=taps
	tile.tap_key=side+":"+str(grids[side].get_child_count())+":"+id
	tile.quick_action=_move.bind(side,id,count,index)
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
		selected_slot=index
		selected_count=count
		refresh.call_deferred())
	return tile

func _move(side:String,id:String,count:int,index:int)->void:
	if id.is_empty() or count<=0 or not is_visible_in_tree() or not is_instance_valid(session): return
	if side=="chest": session.ui_command("chest_take",[key,id,count])
	else: session.ui_command("chest_put",[key,id,count,index])
	refresh.call_deferred()

func _drop_stack(data:Dictionary,side:String,index:int)->void:
	var source:=int(data.get("slot",WastelandBag.PACK))
	if side=="chest":
		session.ui_command("chest_put",[key,data.item,data.quantity,source])
	elif data.source=="chest":
		session.ui_command("chest_take",[key,data.item,data.quantity,index])
	elif side=="bag":
		session.ui_command("pack_slot",[source,data.item])
	elif source==WastelandBag.PACK:
		session.ui_command("assign_slot",[data.item,index,data.quantity])
	else:
		session.ui_command("move_slot",[source,index,data.item])
	refresh.call_deferred()
