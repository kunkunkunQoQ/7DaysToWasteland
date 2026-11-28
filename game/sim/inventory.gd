class_name WastelandBag
extends RefCounted

signal acquired(id: String)
signal changed

const STACK_SLOTS := 27
const ROW_SIZE := 9
const HOTBAR_SIZE := 8
const PACK := -1
const ANY := -2
const SLOTS := {"head":"头部","body":"身体","legs":"腿部","feet":"双脚","hands":"双手","eyes":"眼饰","muzzle":"脸饰","back":"背饰","pack":"背包"}
const EXTRA_SLOTS := ["legs","eyes","muzzle","back","pack"]

var catalog: WastelandCatalog
# Total ownership includes the stacks allocated to the eight quick slots.
var counts: Dictionary = {}
var bar: Array = ["", "", "", "", "", "", "", ""]
var bar_amounts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var active := 0:
	set(value):
		if active != value:
			active = value
			changed.emit()
var gear := {"head":"","body":"","hands":"","feet":""}
var offhand: String:
	get: return str(gear.get("offhand",""))
# Older saves and callers store the torso slot as "armor".
var armor: String:
	get: return gear.body
	set(value):
		if gear.body != value:
			gear.body = value
			changed.emit()
var magazine: Dictionary = {}

func _init(data: WastelandCatalog, snapshot: Dictionary = {}) -> void:
	catalog = data
	if not snapshot.is_empty():
		restore(snapshot)

func restore(saved: Dictionary, restore_active := true) -> void:
	counts = saved.get("counts", {}).duplicate()
	bar.fill("")
	bar_amounts.fill(0)
	var saved_bar: Array = saved.get("bar", [])
	var amounts: Array = saved.get("bar_amounts", [])
	for index in mini(saved_bar.size(), HOTBAR_SIZE):
		var id := str(saved_bar[index])
		if not catalog.items.has(id): continue
		# Legacy shortcuts referred to a shared total. Allocate at most one actual stack.
		var requested := stack_size(id)
		if saved.has("bar_amounts"):
			requested = int(amounts[index]) if index<amounts.size() else 0
		_set_slot(index, id, clampi(requested, 0, mini(stack_size(id), pack_count(id))))
	if restore_active: active = clampi(int(saved.get("active", 0)), 0, HOTBAR_SIZE - 1)
	restore_gear(saved)
	magazine = saved.get("magazine", {}).duplicate()

func snapshot() -> Dictionary:
	return {"counts": counts.duplicate(), "bar": bar.duplicate(), "bar_amounts": bar_amounts.duplicate(), "active": active, "armor": armor, "gear":gear.duplicate(), "magazine": magazine.duplicate()}

func restore_gear(saved: Dictionary) -> void:
	var equipped: Dictionary = saved.get("gear", {"body":saved.get("armor","")})
	for slot in SLOTS:
		var id := str(equipped.get(slot,""))
		var item: Dictionary = catalog.items.get(id,{})
		if slot in EXTRA_SLOTS and (id.is_empty() or count(id)==0 or item.get("slot","")!=slot):
			gear.erase(slot)
			continue
		gear[slot] = id if count(id)>0 and item.get("kind","")=="armor" and item.get("slot","body")==slot else ""
	var held:=str(equipped.get("offhand",""))
	gear.erase("offhand")
	if catalog.items.has(held) and available_count(held)>int(is_worn(held)): gear.offhand=held

func is_worn(id:String)->bool:
	if id.is_empty(): return false
	for slot:String in SLOTS:
		if gear.get(slot,"")==id: return true
	return false

func set_offhand(id:String)->void:
	if id==offhand: return
	if id=="":
		gear.erase("offhand")
		changed.emit()
		return
	if available_count(id)<=0 or not catalog.items.has(id): return
	if is_worn(id) and available_count(id)==1: toggle_gear(id)
	gear.offhand=id
	changed.emit()

func swap_hands()->void:
	var main:=current()
	var other:=offhand
	if other==main: return
	if assign(other,active): set_offhand(main)

func is_shield(id:String)->bool:
	return bool(catalog.items.get(id,{}).get("shield",false))

func wear_shield()->void:
	var previous:=offhand
	if not is_shield(previous):return
	var next:String=catalog.items[previous].get("worn_form","")
	var source := PACK if pack_count(previous)>0 else bar.find(previous)
	if not spend({previous:1},source):return
	if next!="":
		# This unit changes condition in place, even if a smaller pack is now overfull.
		counts[next]=count(next)+1
		if source>=0: _set_slot(source,next,1)
		if count(next)==1: acquired.emit(next)
		set_offhand(next)
	else:
		set_offhand("")

func toggle_gear(id: String) -> void:
	var item: Dictionary = catalog.items.get(id,{})
	if available_count(id)>0 and item.get("kind","")=="armor":
		var slot: String = item.get("slot","body")
		if slot in EXTRA_SLOTS and gear.get(slot,"")==id: gear.erase(slot)
		else:
			if gear.get(slot,"")!=id and offhand==id and available_count(id)==1: gear.erase("offhand")
			gear[slot] = "" if gear.get(slot,"")==id else id
		changed.emit()

func gear_bonus(stat: String) -> float:
	var total := 0.0
	for slot:String in SLOTS:
		total += float(catalog.items.get(gear.get(slot,""),{}).get(stat,0))
	return total

func count(id: String) -> int:
	return int(counts.get(id, 0))

func pack_count(id: String) -> int:
	var remaining := count(id)
	for i in HOTBAR_SIZE:
		if bar[i]==id: remaining -= bar_amounts[i]
	return remaining

func source_count(id: String, source: int) -> int:
	if source==ANY: return count(id)
	if source==PACK: return pack_count(id)
	return bar_amounts[source] if source>=0 and source<HOTBAR_SIZE and bar[source]==id else 0

func _set_slot(index: int, id: String, amount: int) -> void:
	bar[index] = id if amount>0 else ""
	bar_amounts[index] = amount

func set_loaded_rounds(id: String, rounds: int) -> void:
	if magazine.get(id,0) != rounds:
		magazine[id] = rounds
		changed.emit()

func available_count(id:String)->int:
	return count(id)

func current() -> String:
	var id: String = bar[active]
	var reserved := 1 + int(is_worn(id)) if offhand == id else 0
	return id if bar_amounts[active]>0 and count(id) > reserved else ""

func stack_size(id: String) -> int:
	return maxi(1, int(catalog.items.get(id, {}).get("stack", 99)))

func capacity() -> int:
	var id:String=gear.get("pack","")
	var rows:=clampi(int(catalog.items.get(id,{}).get("pack_rows",0)),0,2) if count(id)>0 else 0
	return STACK_SLOTS+rows*ROW_SIZE

func occupied() -> int:
	var used := 0
	for id in counts:
		used += ceili(float(pack_count(id)) / stack_size(id))
	return used

func pack_room_for(id: String) -> int:
	var stack := stack_size(id)
	return maxi(0, capacity()-occupied())*stack + posmod(-pack_count(id), stack)

func room_for(id:String,destination:=ANY)->int:
	if not catalog.items.has(id): return 0
	if destination==PACK: return pack_room_for(id)
	if destination!=ANY:
		if destination<0 or destination>=HOTBAR_SIZE or bar[destination] not in ["",id]: return 0
		return stack_size(id)-bar_amounts[destination]
	var room := pack_room_for(id)
	for i in HOTBAR_SIZE:
		if bar[i]=="" or bar[i]==id: room += stack_size(id)-bar_amounts[i]
	return room

func add(id: String, amount: int, destination:=ANY) -> int:
	if amount <= 0 or not catalog.items.has(id):
		return 0
	var existing := count(id)
	var moved := 0
	if destination==ANY:
		moved=_store_pickup(id,amount)
	else:
		moved=mini(amount,room_for(id,destination))
		if destination>=0 and moved>0: _set_slot(destination,id,bar_amounts[destination]+moved)
	if moved>0:
		counts[id]=existing+moved
		if existing==0: acquired.emit(id)
		changed.emit()
	return moved

func _store_pickup(id: String, amount: int) -> int:
	var stack := stack_size(id)
	var remaining := amount
	var pack_room := pack_room_for(id)
	# Top up ready-to-use stacks; keep items deliberately returned to the pack there.
	for i in HOTBAR_SIZE:
		if bar[i]!=id: continue
		var fill := mini(remaining, stack-bar_amounts[i])
		bar_amounts[i] += fill
		remaining -= fill
	if count(id)==0 and remaining>0 and bar.has(""):
		var fill := mini(remaining, stack)
		_set_slot(bar.find(""), id, fill)
		remaining -= fill
	var packed := mini(remaining, pack_room)
	remaining -= packed
	# Overflow can still occupy unused quick slots when the backpack is full.
	for i in HOTBAR_SIZE:
		if remaining==0: break
		if bar[i]!="": continue
		var fill := mini(remaining, stack)
		_set_slot(i, id, fill)
		remaining -= fill
	return amount-remaining

func has_all(items: Dictionary) -> bool:
	for id in items:
		if int(items[id]) < 0 or available_count(id) < int(items[id]):
			return false
	return true

func spend(items: Dictionary, source := ANY) -> bool:
	for id in items:
		if int(items[id])<0 or source_count(id, source)<int(items[id]): return false
	var did_spend := false
	for id in items:
		if int(items[id]) == 0: continue
		did_spend = true
		var amount := int(items[id])
		if source>=0:
			_set_slot(source, id, bar_amounts[source]-amount)
		elif source==ANY:
			# Crafting and other shared costs draw from the pack before quick slots.
			var from_bar := maxi(0, amount-pack_count(id))
			for step in HOTBAR_SIZE:
				if from_bar==0: break
				var i := (active+step+1)%HOTBAR_SIZE
				if bar[i]!=id: continue
				var take := mini(from_bar,bar_amounts[i])
				_set_slot(i,id,bar_amounts[i]-take)
				from_bar -= take
		var left := count(id) - int(items[id])
		if left > 0:
			counts[id] = left
			if offhand==id and available_count(id)<=int(is_worn(id)):gear.erase("offhand")
		else:
			counts.erase(id)
			for slot in gear.keys():
				if gear[slot]!=id: continue
				if slot=="offhand" or slot in EXTRA_SLOTS: gear.erase(slot)
				else: gear[slot]=""
	if did_spend:
		changed.emit()
	return true

func transfer(source: Dictionary, received: Variant = null) -> int:
	var total := 0
	for id in source.keys():
		var moved := add(id, int(source[id]))
		total += moved
		if moved > 0 and received != null:
			received[id] = int(received.get(id, 0)) + moved
		source[id] = int(source[id]) - moved
		if source[id] <= 0:
			source.erase(id)
	return total

func put_from_pack(id: String, index: int, requested: int) -> bool:
	if index<0 or index>=HOTBAR_SIZE or requested<=0: return false
	var in_pack := pack_count(id)
	var stack := stack_size(id)
	var amount := mini(in_pack, mini(requested,stack))
	var old_id: String = bar[index]
	if old_id==id: amount = mini(amount, stack-bar_amounts[index])
	if amount<=0: return false
	if old_id!="" and old_id!=id:
		var freed := ceili(float(in_pack)/stack)-ceili(float(in_pack-amount)/stack)
		var old_stack := stack_size(old_id)
		var room := maxi(0,capacity()-occupied()+freed)*old_stack+posmod(-pack_count(old_id),old_stack)
		if room<bar_amounts[index]: return false
	_set_slot(index,id,amount+bar_amounts[index] if old_id==id else amount)
	changed.emit()
	return true

func put_in_pack(index: int) -> bool:
	if index<0 or index>=HOTBAR_SIZE or bar[index]=="": return false
	var id: String = bar[index]
	var amount := mini(bar_amounts[index],pack_room_for(id))
	if amount<=0: return false
	_set_slot(index,id,bar_amounts[index]-amount)
	changed.emit()
	return true

func move_slot(from: int, to: int) -> bool:
	if from<0 or from>=HOTBAR_SIZE or to<0 or to>=HOTBAR_SIZE or bar[from]=="": return false
	if from==to: return true
	var id: String = bar[from]
	var old_id: String = bar[to]
	var old_amount := bar_amounts[to]
	if old_id==id:
		var moved := mini(bar_amounts[from],stack_size(id)-old_amount)
		if moved==0: return false
		_set_slot(to,id,old_amount+moved)
		_set_slot(from,id,bar_amounts[from]-moved)
	else:
		_set_slot(to,id,bar_amounts[from])
		_set_slot(from,old_id,old_amount)
	changed.emit()
	return true

func assign(id: String, index: int) -> bool:
	if index<0 or index>=HOTBAR_SIZE: return false
	if bar[index]==id: return true
	if id=="": return pack_room_for(bar[index])>=bar_amounts[index] and put_in_pack(index)
	var existing := bar.find(id)
	if existing>=0: return move_slot(existing,index)
	return put_from_pack(id,index,stack_size(id))

func rating() -> int:
	var weapon := 0
	for id in counts:
		weapon = maxi(weapon, int(catalog.items.get(id, {}).get("rating", 0)))
	return weapon + int(gear_bonus("rating"))
