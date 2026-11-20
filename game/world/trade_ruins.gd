extends RefCounted

const Support := preload("res://game/world/site_support.gd")
const STEEL := Color("#526367")
const RUST := Color("#9a6043")
const OAK := Color("#856348")
const SACK := Color("#b29c76")
const POST_RED := Color("#964c43")

static func furnish(c:WastelandChunk,base:Vector3,level:int,rng:RandomNumberGenerator)->void:
	var hand:=1 if rng.randf()<0.5 else -1
	match c.site:
		"granary":
			for i in 2:
				var at:=Vector3(hand*(4.72-i*6.80),0,-4.04+i*1.69)
				_grain_bin(c,base,at,i,rng)
			_silo(c,base,hand,rng)
		"garage":
			_repair_stand(c,base,Vector3(hand*1.70,0,-2.82),rng)
			_tool_rack(c,base,Vector3(-hand*3.64,0,3.10),rng)
			_hoist(c,base,hand)
		"post":
			if level==0:
				_counter(c,base,Vector3(hand*2.46,0,-1.73),hand)
				_sorter(c,base,Vector3(-hand*2.65,0,-3.68),level,rng)
				_postbox(c,base)
			else:
				for i in 2:
					var at:=Vector3(hand*(1.96-i*3.92),0,-2.04+i*4.10)
					_sorter(c,base,at,level,rng,i)

# Furniture and cache placement share the physical bounds, including tilted or
# projecting pieces. Tie the feet of each furnishing to its actual floor tiles.
static func _furniture(c:WastelandChunk,base:Vector3,at:Vector3,level:int,kind:String,index:int,
		parts:Array,feet:Array,materials:Dictionary)->void:
	var origin:=base+at+Vector3.UP*0.12
	var bounds:=AABB()
	for i in parts.size():
		var row:Array=parts[i]
		row[0]+=origin
		var size:Vector3=row[1]
		var pose:=Transform3D(row[3] if row.size()>3 else Basis.IDENTITY,row[0])
		var box:=pose*AABB(-size*0.5,size)
		bounds=box if i==0 else bounds.merge(box)
	c.ruin.furniture_bounds.append(bounds)
	var id:="furniture/%d/%s/%d"%[level,kind,index]
	var solid_count:=parts.size()
	var detail_seed:int=c.stream.generator.seed_at(c.cell,14821+level*17+index+int(kind.hash()%1000))
	preload("res://game/world/site_room_details.gd").add_trade_fittings(parts,kind,origin,signf(at.x),detail_seed)
	var body:=WastelandSite._cluster(c,id,parts,125,solid_count)
	body.set_meta("salvage_components",materials)
	var bearings:Array=[]
	for foot:Vector2 in feet:
		var tile:=Support.floor_id(c.ruin.span,level,at.x+foot.x,at.z+foot.y)
		if tile not in bearings: bearings.append(tile)
	Support.bind(c,id,[bearings])

static func _grain_bin(c:WastelandChunk,base:Vector3,at:Vector3,index:int,rng:RandomNumberGenerator)->void:
	var parts:Array=[]
	var broken:=rng.randi_range(0,2)
	for x:int in [-1,1]:
		for z:int in [-1,1]:
			parts.append([Vector3(x*0.94,0.67,z*0.72),Vector3(0.11,1.34,0.12),OAK.darkened(0.2)])
	for row in 4:
		var y:=0.16+row*0.30
		var tint:=OAK.lightened((row%2)*0.075)
		for side:int in [-1,1]:
			parts.append([Vector3(side*0.94,y,0),Vector3(0.10,0.26,1.49),tint])
		parts.append([Vector3(0,y,-0.72),Vector3(1.87,0.26,0.09),tint])
		if row<2 or (row==2 and broken==0):
			parts.append([Vector3(0,y,0.72),Vector3(1.86,0.25,0.09),tint])
	for bag in rng.randi_range(2,3):
		var p:=Vector3((bag-1)*0.49,0.22+(bag%2)*0.09,rng.randf_range(-0.24,0.24))
		var turn:=Basis(Vector3.UP,rng.randf_range(-0.18,0.18))
		parts.append([p,Vector3(0.61,0.42,0.72),SACK.darkened(0.08*bag),turn])
		parts.append([p+Vector3.UP*0.216,Vector3(0.14,0.028,0.71),OAK,turn])
	_furniture(c,base,at,0,"grain_bin",index,parts,[Vector2(-0.94,-0.72),Vector2(0.94,-0.72),Vector2(-0.94,0.72),Vector2(0.94,0.72)],{"wood":0.24,"fiber":0.04})

static func _repair_stand(c:WastelandChunk,base:Vector3,at:Vector3,rng:RandomNumberGenerator)->void:
	var parts:Array=[]
	var worn:=rng.randi_range(0,1)
	for x:int in [-1,1]:
		for z:int in [-1,1]:
			var p:=Vector3(x*0.64,0,z*1.13)
			parts.append([p+Vector3.UP*0.08,Vector3(0.33,0.16,0.40),RUST])
			parts.append([p+Vector3.UP*0.49,Vector3(0.13,0.82,0.14),STEEL])
		parts.append([Vector3(x*0.64,0.92,0),Vector3(0.29,0.13,2.77),STEEL.lightened(0.16)])
	parts.append([Vector3(0,0.94,worn*0.56-0.58),Vector3(1.58,0.23,0.30),RUST])
	parts.append([Vector3(0,1.21,worn*0.56-0.58),Vector3(0.71,0.42,0.54),STEEL])
	for i in 4:
		parts.append([Vector3((i-1.5)*0.16,1.46,worn*0.56-0.58),Vector3(0.08,0.15,0.48),STEEL.lightened(0.17)])
	_furniture(c,base,at,0,"repair_stand",0,parts,[Vector2(-0.64,-1.13),Vector2(0.64,-1.13),Vector2(-0.64,1.13),Vector2(0.64,1.13)],{"scrap":0.26,"parts":0.12})

static func _tool_rack(c:WastelandChunk,base:Vector3,at:Vector3,rng:RandomNumberGenerator)->void:
	var parts:Array=[]
	for x:int in [-1,1]:
		parts.append([Vector3(x*0.90,0.07,0),Vector3(0.16,0.14,0.91),STEEL])
		parts.append([Vector3(x*0.90,0.94,0.17),Vector3(0.10,1.88,0.10),STEEL])
	parts.append([Vector3(0,0.76,0),Vector3(1.94,0.10,0.73),OAK])
	parts.append([Vector3(0,1.46,0.17),Vector3(1.78,0.75,0.08),OAK.darkened(0.26)])
	for col in 5:
		if rng.randf()<0.23: continue
		var tool:=Vector3((col-2)*0.31,1.54,0.088)
		parts.append([tool,Vector3(0.046,0.31,0.06),STEEL.lightened(0.27)])
		parts.append([tool+Vector3.UP*0.15,Vector3(0.13,0.09,0.07),STEEL.lightened(0.27)])
	_furniture(c,base,at,0,"tool_rack",0,parts,[Vector2(-0.90,0),Vector2(0.90,0)],{"wood":0.13,"scrap":0.08,"parts":0.035})

static func _counter(c:WastelandChunk,base:Vector3,at:Vector3,hand:int)->void:
	var parts:=[
		[Vector3(0,0.50,0),Vector3(2.53,1.0,0.18),OAK],
		[Vector3(0,1.02,0.04),Vector3(2.72,0.12,0.72),OAK.lightened(0.15)],
		[Vector3(hand*1.20,0.48,-0.60),Vector3(0.18,0.96,1.32),OAK],
		[Vector3(hand*1.20,1.01,-0.67),Vector3(0.55,0.10,1.30),OAK.lightened(0.13)],
		[Vector3(hand*0.68,1.15,0),Vector3(0.47,0.18,0.34),STEEL],
		[Vector3(hand*0.68,1.28,0),Vector3(0.64,0.065,0.49),STEEL.lightened(0.2)]
	]
	for i in 4:
		parts.append([Vector3((i-1.5)*0.6,0.49,0.105),Vector3(0.052,0.88,0.039),OAK.darkened(0.20)])
	_furniture(c,base,at,0,"parcel_counter",0,parts,[Vector2(-1.2,0),Vector2(1.2,0),Vector2(hand*1.2,-1.2)],{"wood":0.29,"parts":0.033})

static func _sorter(c:WastelandChunk,base:Vector3,at:Vector3,level:int,rng:RandomNumberGenerator,index:=0)->void:
	var parts:Array=[]
	for x:int in [-1,1]:
		parts.append([Vector3(x*0.92,0.96,0),Vector3(0.095,1.92,0.53),OAK])
	parts.append([Vector3(0,0.98,-0.24),Vector3(1.84,1.78,0.062),OAK.darkened(0.36)])
	var missing:=rng.randi_range(0,2)
	for row in 4:
		parts.append([Vector3(0,0.17+row*0.53,0),Vector3(1.85,0.078,0.52),OAK.lightened(0.14)])
		if row==3: break
		for i in 2:
			if row==2 and i==missing: continue
			parts.append([Vector3((i-0.5)*0.61,0.43+row*0.53,0),Vector3(0.055,0.48,0.50),OAK])
		for i in 3:
			if rng.randf()<0.47:
				parts.append([Vector3((i-1)*0.61,0.285+row*0.53,0.035),Vector3(0.45,0.16,0.38),SACK.lightened(0.08*i)])
	_furniture(c,base,at,level,"sorting_case",index,parts,[Vector2(-0.92,0),Vector2(0.92,0)],{"wood":0.23})

static func _ground(c:WastelandChunk,p:Vector3)->Vector3:
	p.y=c.stream.generator.ground(c.position.x+p.x,c.position.z+p.z)
	return p

static func _silo(c:WastelandChunk,base:Vector3,hand:int,rng:RandomNumberGenerator)->void:
	var center:=base+Vector3(hand*3.2,0,-c.ruin.span*0.5-2.35)
	var deck_height:=_ground(c,center).y+1.53
	var legs:Array=[]
	for x:int in [-1,1]:
		for z:int in [-1,1]:
			var foot:=_ground(c,center+Vector3(x*0.78,0,z*0.78))
			deck_height=maxf(deck_height,foot.y+0.90)
	for x:int in [-1,1]:
		for z:int in [-1,1]:
			var foot:=_ground(c,center+Vector3(x*0.78,0,z*0.78))
			var height:=deck_height-foot.y
			var id:="silo/leg/%d/%d"%[x,z]
			var leg:=WastelandSite._feature(c,foot+Vector3.UP*height*0.5,Vector3(0.18,height,0.18),Basis.IDENTITY,STEEL,id,175)
			leg.set_meta("salvage_material","scrap")
			Support.footing(c,id,foot)
			legs.append(id)
	center.y=deck_height
	var deck:=WastelandSite._feature(c,center,Vector3(2.42,0.17,2.42),Basis.IDENTITY,STEEL,"silo/deck",210)
	deck.set_meta("salvage_material","scrap")
	Support.bind(c,"silo/deck",[legs])
	var gap:=rng.randi_range(0,7)
	var mouth:=Basis(Vector3.UP,gap*PI*0.25)
	var slope:=mouth*Basis(Vector3.RIGHT,0.44)
	var throat:=center+mouth*Vector3(0,0.03,1.04)
	var chute:=[[throat+slope*Vector3(0,0,0.57),Vector3(0.72,0.064,1.21),RUST,slope]]
	for side:int in [-1,1]:
		chute.append([throat+slope*Vector3(side*0.35,0.13,0.42),Vector3(0.06,0.25,0.92),STEEL,slope])
	var spout:=WastelandSite._cluster(c,"silo/chute",chute,90)
	spout.set_meta("salvage_material","scrap")
	Support.bind(c,"silo/chute",[["silo/deck"]])
	for panel in 8:
		var cut:=posmod(panel-gap,8)
		if cut==0: continue
		var height:=1.1+0.24*c.ruin.exposure if cut in [1,7] else 3.6
		var turn:=Basis(Vector3.UP,panel*PI*0.25)
		var face:=center+turn*Vector3(0,0,1.08)
		var parts:=[[face+Vector3.UP*(0.08+height*0.5),Vector3(0.92,height,0.071),STEEL.lightened((panel%3)*0.06),turn]]
		for y:float in [0.42,1.42,2.42,3.51]:
			if y>height: break
			parts.append([face+turn*Vector3(0,y,0.043),Vector3(0.94,0.085,0.065),RUST,turn])
		var id:="silo/sheet/%d"%panel
		var body:=WastelandSite._cluster(c,id,parts,100)
		body.set_meta("salvage_material","scrap")
		Support.bind(c,id,[["silo/deck"]])

static func _hoist(c:WastelandChunk,base:Vector3,hand:int)->void:
	var near:=_ground(c,base+Vector3(hand*3.8,0,c.ruin.span*0.5+0.92))
	var far:=_ground(c,near+Vector3.BACK*3.10)
	var top:=maxf(near.y,far.y)+3.74
	var supports:Array=[]
	for foot:Vector3 in [near,far]:
		var id:="hoist/upright/"+str(supports.size())
		var h:=top-foot.y
		var parts:=[[foot+Vector3.UP*0.075,Vector3(0.84,0.15,0.72),STEEL],
			[foot+Vector3.UP*h*0.5,Vector3(0.21,h,0.22),RUST]]
		for i in 4:
			parts.append([foot+Vector3(0,0.42+i*0.27,0.12),Vector3(0.215,0.12,0.02),SACK])
		var pillar:=WastelandSite._cluster(c,id,parts,195)
		pillar.set_meta("salvage_material","scrap")
		Support.footing(c,id,foot)
		supports.append(id)
	var mid:=(near+far)*0.5
	mid.y=top
	var bridge:=[[mid,Vector3(0.16,0.26,3.60),RUST],[mid+Vector3.UP*0.15,Vector3(0.36,0.07,3.60),RUST]]
	var beam:=WastelandSite._cluster(c,"hoist/beam",bridge,190)
	beam.set_meta("salvage_material","scrap")
	Support.bind(c,"hoist/beam",[supports])
	var at:=mid+Vector3.BACK*(c.ruin.scatter-0.5)*1.65
	var winch:=WastelandSite._cluster(c,"hoist/winch",[
		[at+Vector3.DOWN*0.22,Vector3(0.52,0.34,0.44),STEEL],
		[at+Vector3.DOWN*0.97,Vector3(0.045,1.27,0.045),STEEL.darkened(0.3)],
		[at+Vector3(0.07,-1.63,0),Vector3(0.18,0.085,0.10),STEEL]],110)
	winch.set_meta("salvage_components",{"parts":0.06,"wire":0.02})
	Support.bind(c,"hoist/winch",[["hoist/beam"]])

static func _postbox(c:WastelandChunk,base:Vector3)->void:
	var at:=_ground(c,base+Vector3(c.ruin.span*0.36,0,c.ruin.span*0.5+0.80))
	var parts:=[[at+Vector3.UP*0.10,Vector3(0.79,0.20,0.70),STEEL],
		[at+Vector3.UP*0.72,Vector3(0.66,1.08,0.58),POST_RED],
		[at+Vector3.UP*1.31,Vector3(0.74,0.16,0.66),POST_RED.darkened(0.16)],
		[at+Vector3(0,1.08,0.303),Vector3(0.46,0.095,0.035),STEEL.darkened(0.55)],
		[at+Vector3(0,0.75,0.303),Vector3(0.29,0.16,0.039),SACK]]
	var box:=WastelandSite._cluster(c,"post/dropbox",parts,120)
	box.set_meta("salvage_material","scrap")
	Support.footing(c,"post/dropbox",at)
	var bracket:=base+Vector3(c.ruin.span*0.40,4.48,c.ruin.span*0.5+0.22)
	var arm:=WastelandSite._cluster(c,"post/bracket",[
		[bracket,Vector3(0.28,0.66,0.16),STEEL],
		[bracket+Vector3(0,0.21,0.69),Vector3(0.12,0.13,1.50),STEEL]],110)
	arm.set_meta("salvage_material","scrap")
	Support.bind(c,"post/bracket",[[Support.wall(1,0,4)]])
	var sign:=bracket+Vector3(0,-0.24,0.83)
	var blade:Array=[[sign,Vector3(0.15,0.80,1.20),POST_RED]]
	for x:int in [-1,1]:
		blade.append([sign+Vector3(x*0.083,0,0),Vector3(0.024,0.43,0.75),SACK])
		for side:int in [-1,1]:
			blade.append([sign+Vector3(x*0.10,0.08,side*0.18),Vector3(0.023,0.051,0.44),RUST,Basis(Vector3.RIGHT,-side*0.46)])
	var board:=WastelandSite._cluster(c,"post/blade",blade,85)
	board.set_meta("salvage_components",{"scrap":0.055,"wood":0.06})
	Support.bind(c,"post/blade",[["post/bracket"]])
