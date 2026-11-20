extends RefCounted

const RELAYS := ["tower","police","hospital","lodge"]
const DEPOT := Vector2(23,20)
const VAT := Vector2(11,23)

static func fixtures(chunk: WastelandChunk) -> void:
	if chunk.site not in RELAYS: return
	var p:=DEPOT
	var y:float=chunk.stream.generator.ground(chunk.position.x+p.x,chunk.position.z+p.y)
	var body:=WastelandSite._feature(chunk,Vector3(p.x,y+0.5,p.y),Vector3(1.45,1.0,0.74),Basis.IDENTITY,Color("#47655a"),"dispatch/locker")
	body.set_meta("dispatch_locker",true)
	WastelandLook.box(body,Vector3(1.16,0.12,0.78),Vector3(0,0.24,0),Color("#e8b365"))
	if chunk.site!="lodge": return
	p=VAT
	y=chunk.stream.generator.ground(chunk.position.x+p.x,chunk.position.z+p.y)
	var vat:=WastelandSite._feature(chunk,Vector3(p.x,y+0.38,p.y),Vector3(1.5,0.76,0.94),Basis.IDENTITY,Color("#596e71"),"dispatch/cistern")
	vat.set_meta("cistern",true)
	WastelandLook.box(vat,Vector3(1.39,0.04,0.83),Vector3(0,0.40,0),Color("#6da9a5"))
	WastelandLook.box(vat,Vector3(0.12,0.58,0.12),Vector3(0.6,0.48,0.27),Color("#b59160"))

static func relay(s:Node,origin:Vector2i) -> Vector2i:
	var gen:WastelandTerrainGen=s.stream.generator
	var best:=origin
	var distance:=INF
	var rotation:=posmod(s.clock.day()-1,4)
	for z in range(-15,16):
		for x in range(-15,16):
			var offset:=Vector2i(x,z)
			for i in rotation: offset=Vector2i(-offset.y,offset.x)
			var d:=offset.length()
			if d<10.3 or d>=distance: continue
			if gen.site_for(origin+offset) in RELAYS:
				best=origin+offset
				distance=d
	if best==origin:
		for candidate:Vector2i in WastelandTerrainGen.FIXED:
			if candidate!=origin and WastelandTerrainGen.FIXED[candidate] in RELAYS:
				best=candidate
				break
	return best

static func _source(s:Node,origin:Vector2i,kind:String) -> Vector2:
	var gen:WastelandTerrainGen=s.stream.generator
	for radius in 3:
		for z in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(z))!=radius: continue
				var cell:=origin+Vector2i(x,z)
				var chunk:WastelandChunk=s.stream.active.get(cell)
				var removed:Dictionary=s.stream.chunk_diff(cell).get("removed",{})
				var start:=Vector2(cell*32)
				var rows:=gen._dressing(cell,start,start+Vector2(16,16),gen.site_for(cell))
				if chunk: rows=WastelandSite.starter_dressing(chunk,rows)
				for row:Dictionary in rows:
					if row.id==kind and not removed.has(str(row.index)):
						return start+Vector2(row.point.x,row.point.z)
	return Vector2.INF

static func orders(s:Node,origin:Vector2i) -> Array[Dictionary]:
	var day:int=s.clock.day()
	var board:=WastelandSite.board_at(origin)
	var i:=posmod(day-1,4)
	var material:String=["berries","wood","stone","fiber"][i]
	var kind:String=["brush","oak","boulder","brush"][i]
	var at:=_source(s,origin,kind)
	var well:=Vector2(origin*32)+VAT
	var source:=str(s.RESOURCES[kind][0])
	if not at.is_finite():
		material="dirty_water"
		at=well
		source="驻地蓄水槽"
	var destination:=relay(s,origin)
	var end:=Vector2(destination*32)+DEPOT
	var reward:Dictionary=[{"spring":2,"electronics":3,"clean_water":2},{"parts":5,"wire":4,"bandage":2},
		{"leather":4,"round":8,"clean_water":1},{"iron_ore":5,"electronics":2,"medkit":1}][i]
	return [{"id":"local_%s_%d"%[WastelandTerrainGen.grid_key(origin),day],"name":"驻地补给 · "+s.catalog.title(material),
		"story":"就近收集后带回发单公告板。","inputs":{material:3},"reward":{"clean_water":2,"bandage":1},"xp":38,
		"tier":"local","source":source,"at":at,"board":board,"origin":origin},
		{"id":"dispatch_%s_%d"%[WastelandTerrainGen.grid_key(origin),day],"name":"远行运单 · "+str(s.catalog.sites[s.stream.generator.site_for(destination)].name),
		"story":"先在本站登记，前往中继寄存柜签收一个货包，在今日结束前返回本站交货。","inputs":{"dispatch_parcel":1},"reward":reward,"xp":90,
		"tier":"expedition","source":str(s.catalog.sites[s.stream.generator.site_for(destination)].name)+"寄存柜","at":end,"board":board,"origin":origin,"relay":destination}]
