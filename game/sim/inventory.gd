class_name WastelandBag
extends RefCounted

signal acquired(id: String)

const STACK_SLOTS := 27
const ROW_SIZE := 9
const HOTBAR_SIZE := 8
const SLOTS := {"head":"头部","body":"身体","legs":"腿部","feet":"双脚","hands":"双手","eyes":"眼饰","muzzle":"脸饰","back":"背饰","pack":"背包"}
const EXTRA_SLOTS := ["legs","eyes","muzzle","back","pack"]

var catalog: WastelandCatalog
var counts: Dictionary = {}
var bar: Array = ["", "", "", "", "", "", "", ""]
# Automatic bindings expire with the last unit. Player-assigned bindings survive until replaced.
var automatic_shortcuts: Dictionary = {}
var active := 0
var gear := {"head":"","body":"","hands":"","feet":""}
var offhand: String:
	get: return str(gear.get("offhand",""))
# One reservation per other player. Equal item IDs represent distinct units.
var partner_offhands: Array[String] = []
# Older saves and callers store the torso slot as "armor".
var armor: String:
	get: return gear.body
	set(value): gear.body = value
var magazine: Dictionary = {}

func _init(data: WastelandCatalog, snapshot: Dictionary = {}) -> void:
	catalog = data
	if not snapshot.is_empty():
		counts = snapshot.get("counts", {}).duplicate()
		var saved_bar: Array = snapshot.get("bar", [])
		for index in mini(saved_bar.size(), HOTBAR_SIZE):
			bar[index] = str(saved_bar[index])
		automatic_shortcuts = snapshot.get("automatic_shortcuts", {}).duplicate()
		active = clampi(int(snapshot.get("active", 0)), 0, HOTBAR_SIZE - 1)
		partner_offhands.assign(snapshot.get("partner_offhands",[]))
		restore_gear(snapshot)
		magazine = snapshot.get("magazine", {}).duplicate()

func snapshot() -> Dictionary:
	return {"counts": counts.duplicate(), "bar": bar.duplicate(), "automatic_shortcuts": automatic_shortcuts.duplicate(), "active": active, "armor": armor, "gear":gear.duplicate(), "magazine": magazine.duplicate()}

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
	if id=="":
		gear.erase("offhand")
		return
	if available_count(id)<=0 or not catalog.items.has(id): return
	if is_worn(id) and available_count(id)==1: toggle_gear(id)
	gear.offhand=id

func swap_hands()->void:
	var main:=current()
	var other:=offhand
	if other==main: return
	set_offhand(main)
	assign(other,active)

func is_shield(id:String)->bool:
	return bool(catalog.items.get(id,{}).get("shield",false))

func wear_shield()->void:
	var previous:=offhand
	if not is_shield(previous):return
	var next:String=catalog.items[previous].get("worn_form","")
	if not spend({previous:1}):return
	if next!="":
		# This unit changes condition in place, even if a smaller pack is now overfull.
		counts[next]=count(next)+1
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

func gear_bonus(stat: String) -> float:
	var total := 0.0
	for slot:String in SLOTS:
		total += float(catalog.items.get(gear.get(slot,""),{}).get(stat,0))
	return total

func count(id: String) -> int:
	return int(counts.get(id, 0))

func available_count(id:String)->int:
	return maxi(0,count(id)-partner_offhands.count(id))

func current() -> String:
	var id: String = bar[active]
	return id if _mainhand_units(id,offhand)>0 else ""

func partner_needs_last_mainhand(id:String,partner_slot:int,partner_hand:String)->bool:
	return id==bar[partner_slot] and _mainhand_units(id,partner_hand)==1

func _mainhand_units(id:String,secondary:String)->int:
	return count(id)-partner_offhands.count(id)-int(offhand==id)-int(secondary==id and is_worn(id))

func stack_size(id: String) -> int:
	return maxi(1, int(catalog.items.get(id, {}).get("stack", 99)))

func capacity() -> int:
	var id:String=gear.get("pack","")
	var rows:=clampi(int(catalog.items.get(id,{}).get("pack_rows",0)),0,2) if count(id)>0 else 0
	return STACK_SLOTS+rows*ROW_SIZE

func occupied() -> int:
	var used := 0
	for id in counts:
		used += ceili(float(counts[id]) / stack_size(id))
	return used

func room_for(id:String)->int:
	if not catalog.items.has(id): return 0
	var stack:=stack_size(id)
	return maxi(0,capacity()-occupied())*stack+posmod(-count(id),stack)

func add(id: String, amount: int) -> int:
	if amount <= 0 or not catalog.items.has(id):
		return 0
	var existing := count(id)
	var moved := mini(amount,room_for(id))
	if moved > 0:
		counts[id] = existing + moved
		if not bar.has(id):
			var slot := bar.find("")
			if slot >= 0:
				bar[slot] = id
				automatic_shortcuts[id] = true
		if existing==0: acquired.emit(id)
	return moved

func has_all(items: Dictionary) -> bool:
	for id in items:
		if int(items[id]) < 0 or available_count(id) < int(items[id]):
			return false
	return true

func spend(items: Dictionary) -> bool:
	if not has_all(items):
		return false
	for id in items:
		var left := count(id) - int(items[id])
		if left > 0:
			counts[id] = left
			if offhand==id and available_count(id)<=int(is_worn(id)):gear.erase("offhand")
		else:
			counts.erase(id)
			if automatic_shortcuts.erase(id):
				var shortcut := bar.find(id)
				if shortcut >= 0: bar[shortcut] = ""
			for slot in gear.keys():
				if gear[slot]!=id: continue
				if slot=="offhand" or slot in EXTRA_SLOTS: gear.erase(slot)
				else: gear[slot]=""
	return true

func transfer(source: Dictionary) -> int:
	var total := 0
	for id in source.keys():
		var moved := add(id, int(source[id]))
		total += moved
		source[id] = int(source[id]) - moved
		if source[id] <= 0:
			source.erase(id)
	return total

func assign(id: String, index: int) -> void:
	if index < 0 or index >= HOTBAR_SIZE or (id != "" and count(id) == 0):
		return
	var old := bar.find(id) if id != "" else -1
	automatic_shortcuts.erase(id)
	automatic_shortcuts.erase(bar[index])
	if old >= 0:
		bar[old] = bar[index]
	bar[index] = id

func rating() -> int:
	var weapon := 0
	for id in counts:
		weapon = maxi(weapon, int(catalog.items.get(id, {}).get("rating", 0)))
	return weapon + int(gear_bonus("rating"))
