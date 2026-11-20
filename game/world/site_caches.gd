extends RefCounted

const Chest:=preload("res://game/art/supply_chest.gd")
const Containers:=preload("res://game/world/regional_caches.gd")
const LOCAL_FORMS:={"lodge":"forest","cabin":"forest","fuel":"ash","hospital":"ridge","police":"ridge","tower":"ridge","bunker":"ridge","granary":"forest","garage":"ash","post":"town"}

static func populate(chunk:WastelandChunk,center:Vector3,definition:Dictionary)->void:
	var gen:WastelandTerrainGen=chunk.stream.generator
	var rng:=RandomNumberGenerator.new()
	rng.seed=gen.seed_at(chunk.cell,0x3109)^chunk.site.hash()
	var half:=float(definition.span)*0.5
	var stories:=int(definition.stories)
	var trade_ruin:=chunk.site in ["granary","garage","post"]
	var anchors:Array[Dictionary]=[]
	for story in stories:
		# Two rear-wall alcoves and the middle bay of each side wall keep the main
		# entrance, staircase landings and central quest cabinet approachable.
		for side in 4:
			var facing:=Vector3.BACK
			var sector:Vector3
			match side:
				0,1:
					# Leave room for a survivor between the box and the innermost column.
					var offset:=half-3.62 if trade_ruin else half*0.60
					sector=Vector3((-1 if side==0 else 1)*offset,0,-half+0.90)
				2:
					sector=Vector3(half-0.88,0,-half*0.16)
					facing=Vector3.LEFT
				_:
					if chunk.ruin.damaged(story,3,2,chunk.site): continue
					sector=Vector3(-half+0.88,0,half*(0.20 if trade_ruin else 0.03))
					facing=Vector3.RIGHT
			var tangent:=Vector3(facing.z,0,-facing.x)
			var at:=center+sector+Vector3.UP*(story*WastelandSite.STOREY_HEIGHT)+tangent*rng.randf_range(-0.28,0.28)
			var approach:=at+facing*1.36
			if not chunk.ruin.has_floor(chunk,center,at) or not chunk.ruin.has_floor(chunk,center,approach): continue
			if not chunk.ruin.furniture_clear(at,0.90) or not chunk.ruin.furniture_clear(approach,0.55): continue
			# Keep the original pool of eligible slots, its RNG and saved container
			# IDs. Within a concrete room move the chest and its visitor together
			# off the column line. The east corner also clears the quest safe.
			if not trade_ruin and chunk.ruin.condition>0 and not chunk.ruin.wood:
				if side<=1:
					var safe_storey:=side==1 and story==stories-1 and chunk.site in ["tower","hospital","police"]
					var clearance:=half-1.02 if safe_storey else half-3.62
					at.x+=signf(sector.x)*(clearance-absf(sector.x))
				elif side==3:
					at.z=center.z-chunk.ruin.end*half*0.16
				approach=at+facing*1.36
			anchors.append({"at":at,"approach":approach,"yaw":atan2(facing.x,facing.z)+rng.randf_range(-0.10,0.10),"story":story})
	var stock:Array=definition.loots
	if stock.is_empty(): return
	var count:=mini(anchors.size(),rng.randi_range(maxi(1,stock.size()-2),stock.size()+1))
	var biome:=Chest.kind_at(gen,chunk.position+center)
	var deep_stock := false
	for index in count:
		var candidate:Dictionary=anchors.pop_at(rng.randi_range(0,anchors.size()-1))
		var profile:String=biome if rng.randf()<0.58 else LOCAL_FORMS[chunk.site]
		var size:Vector3=Chest.DIMENSIONS[profile]
		var table:String=stock[rng.randi_range(0,stock.size()-1)]
		if index==0 and trade_ruin: table=stock[0]
		var meta:={"quest":false,"cache_floor":candidate.story,"cache_approach":candidate.approach+chunk.position,"cache_biome":biome}
		var body:=Containers.spawn(chunk,"container/"+str(index),table,candidate.at+Vector3.UP*(0.12+size.y*0.5),meta,profile)
		body.rotation.y=candidate.yaw
		if table in ["medical","weapons","safe","garage_spares"] and (candidate.story>0 or candidate.at.z<center.z-half*0.55): deep_stock=true
	if not deep_stock and chunk.site not in ["lodge","tower","police","hospital"]:
		anchors.sort_custom(func(a: Dictionary,b: Dictionary): return a.story>b.story if a.story!=b.story else a.at.z<b.at.z)
		for slot in anchors:
			if slot.story == 0 and slot.at.z > center.z-half*0.55: continue
			var cache_type: String = {"bunker":"weapons","post":"medical","cabin":"medical"}.get(chunk.site,"garage_spares")
			var size: Vector3 = Chest.DIMENSIONS[biome]
			var meta := {"cache_floor":slot.story,"cache_approach":slot.approach+chunk.position,"cache_biome":biome}
			var chest := Containers.spawn(chunk,"nest/deep",cache_type,slot.at+Vector3.UP*(0.12+size.y*0.5),meta,biome)
			chest.rotation.y=slot.yaw
			break
