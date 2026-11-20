extends RefCounted

const FUEL_SECONDS := {"wood":38.0,"coal":100.0,"leaf_kindling":24.0}
const MELTABLE := ["scrap","iron_ore","clay","lead","brass","ingot"]
const MELT_SECONDS := 2.0

static func thermal(row:Dictionary)->bool:
	return row.get("device","") in ["campfire","forge"]

static func lit(row:Dictionary)->bool:
	return row.get("enabled",false) and float(row.get("fuel",0))>0.0

static func restore(row:Dictionary,now:float)->void:
	if not thermal(row): return
	var fuel:=maxf(0,float(row.get("fuel",0)))
	row.fuel=fuel
	if fuel==0.0: row.enabled=false
	if not row.has("fuel_slots"):
		var whole:=floori(fuel/float(FUEL_SECONDS.wood))
		row.fuel_slots={"wood":whole} if whole>0 else {}
		row.ember=fuel-whole*float(FUEL_SECONDS.wood)
	var start:=now
	for job:Dictionary in row.get("queue",[]):
		if not job.has("left"):
			var remaining:=maxf(0.0,float(job.done)-start)
			job.left=minf(float(job.get("span",remaining)),remaining)
		start=maxf(start,float(job.done))

static func uses_stock(row:Dictionary,id:String)->bool:
	return row.get("device","")=="forge" and id in MELTABLE

static func available(bag:WastelandBag,row:Dictionary,id:String)->int:
	return int(row.get("molten",{}).get(id,0)) if uses_stock(row,id) else bag.available_count(id)

static func reserve(bag:WastelandBag,row:Dictionary,inputs:Dictionary)->Dictionary:
	var solid:={}
	var molten:={}
	for id:String in inputs:
		if available(bag,row,id)<int(inputs[id]): return {}
		if uses_stock(row,id): molten[id]=inputs[id]
		else: solid[id]=inputs[id]
	if not solid.is_empty() and not bag.spend(solid): return {}
	for id:String in molten: row.molten[id]-=int(molten[id])
	return {"inputs":solid,"molten":molten}

static func charge(row:Dictionary,bag:WastelandBag,id:String)->bool:
	if not thermal(row) or not FUEL_SECONDS.has(id) or float(row.fuel)>1200.0-FUEL_SECONDS[id]: return false
	if not bag.spend({id:1}): return false
	var fuel_slots:Dictionary=row.get("fuel_slots",{})
	fuel_slots[id]=int(fuel_slots.get(id,0))+1
	row.fuel_slots=fuel_slots
	row.fuel=float(row.fuel)+float(FUEL_SECONDS[id])
	return true

static func load_ore(row:Dictionary,bag:WastelandBag,id:String)->int:
	if row.get("device","")!="forge" or id not in MELTABLE: return 0
	var input:Dictionary=row.get("smelt_input",{})
	if int(input.get("count",0))>0 and input.id!=id: return 0
	var qty:=mini(10,mini(99-int(input.get("count",0)),bag.available_count(id)))
	if qty<=0 or not bag.spend({id:qty}): return 0
	row.smelt_input={"id":id,"count":int(input.get("count",0))+qty,"partial":float(input.get("partial",0.0))}
	return qty

static func _burn(row:Dictionary,dt:float)->float:
	var active:=minf(dt,float(row.fuel)) if lit(row) else 0.0
	if active<=0: return 0.0
	row.fuel=maxf(0.0,float(row.fuel)-active)
	var remaining:=active
	var ember:=float(row.get("ember",0.0))
	var slots:Dictionary=row.get("fuel_slots",{})
	while remaining>ember and not slots.is_empty():
		remaining-=ember
		var id:String=slots.keys()[0]
		ember=float(FUEL_SECONDS[id])
		slots[id]-=1
		if slots[id]==0: slots.erase(id)
	row.ember=maxf(0.0,ember-remaining)
	if row.fuel<=0: row.enabled=false
	return active

static func tick(row:Dictionary,dt:float,now:float)->float:
	var work:=_burn(row,dt)
	var input:Dictionary=row.get("smelt_input",{})
	if not input.is_empty() and work>0:
		input.partial+=work
		var qty:=mini(int(input.count),floori(float(input.partial)/MELT_SECONDS))
		if qty>0:
			var stock:Dictionary=row.get("molten",{})
			stock[input.id]=int(stock.get(input.id,0))+qty
			row.molten=stock
			input.partial-=qty*MELT_SECONDS
			input.count-=qty
			if input.count==0: row.erase("smelt_input")
	var budget:=work
	while not row.queue.is_empty():
		var job:Dictionary=row.queue[0]
		var span:=float(job.get("span",maxf(0.0,float(job.done)-(now-dt))))
		var left:=float(job.get("left",clampf(float(job.done)-(now-dt),0.0,span)))
		var advance:=minf(budget,left)
		budget-=advance
		job.left=left-advance
		if job.left>0: break
		row.queue.pop_front()
		row.out[job.id]=int(row.out.get(job.id,0))+int(job.amount)
	var deadline:=now
	for job:Dictionary in row.queue:
		deadline+=float(job.get("left",job.get("span",maxf(0.0,float(job.done)-deadline))))
		job.done=deadline
	return work

static func recover_store(row:Dictionary,items:Dictionary)->void:
	for source:Dictionary in [row.get("fuel_slots",{}),row.get("molten",{})]:
		for id:String in source: items[id]=int(items.get(id,0))+int(source[id])
	var input:Dictionary=row.get("smelt_input",{})
	if not input.is_empty(): items[input.id]=int(items.get(input.id,0))+int(input.count)
	for job:Dictionary in row.queue:
		for id:String in job.get("molten",{}): items[id]=int(items.get(id,0))+int(job.molten[id])
