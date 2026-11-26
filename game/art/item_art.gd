class_name WastelandItemArt
extends RefCounted

const SAND := Color("#be936d")
const WOOD := Color("#9e694c")
const LEATHER := Color("#714d47")
const INK := Color("#383143")
const METAL := Color("#79838e")
const BRASS := Color("#bd9868")
const LINEN := Color("#d7c3ac")
const WATER := Color("#81bdcc")
const SIZE := 36

static var meshes: Dictionary = {}
static var icons: Dictionary = {}

static func mesh(id: String, definition: Dictionary) -> ArrayMesh:
	if meshes.has(id):
		return meshes[id]
	if definition.get("kind","")=="sapling":
		meshes[id]=preload("res://game/art/sapling_art.gd").item_mesh(definition.tree_model)
		return meshes[id]
	if id in ["canvas_pants","quilted_pants"]:
		meshes[id]=preload("res://game/art/trousers.gd").packed_mesh(id)
		return meshes[id]
	if id in ["canvas_pack","expedition_pack"]:
		meshes[id]=preload("res://game/art/travel_packs.gd").mesh(id)
		return meshes[id]
	if id.begins_with("meme_"):
		meshes[id]=preload("res://game/art/meme_gear.gd").mesh(id)
		return meshes[id]
	if id in ["alpine_cap","sun_cape"]:
		var gear:=preload("res://game/art/survivor_equipment.gd")
		var worn:=gear.cap().commit() if id=="alpine_cap" else gear.cape(Vector3(0.22,0.16,0.18)).commit()
		var centered:=SurfaceTool.new()
		centered.append_from(worn,0,Transform3D(Basis.IDENTITY,-worn.get_aabb().get_center()))
		meshes[id]=centered.commit()
		return meshes[id]
	var shape := WastelandScenery.new(id.hash())
	var parts: Array = []
	var tint := Color.from_string(definition.get("color",""), SAND)
	var kind: String = definition.get("kind","material")
	if not _field_item(id,parts,shape):
		match kind:
			"weapon","tool": _tool(id, tint, definition, parts, shape)
			"ranged": _ranged(id, tint, parts, shape)
			"food","med","seed": _provision(id, tint, kind, parts, shape)
			"build","device","wire": _equipment(id, tint, parts, shape)
			"vehicle": _kit(id, tint, parts)
			"ammo": _ammo(id, tint, parts, shape)
			"light": _light(parts,shape)
			"armor": _garment(id,tint,parts)
			"quest": _journal(parts)
			_: _material(id,tint,parts,shape)
	var result: ArrayMesh
	if kind == "armor":
		result = _garment_parts(parts, shape)
	elif not parts.is_empty():
		result = WastelandLook.mesh_parts(parts, 0.12)
	if shape.triangle_count>0:
		var sculpture:=shape.commit()
		if result==null:
			result=sculpture
		else:
			var assembled:=SurfaceTool.new()
			assembled.begin(Mesh.PRIMITIVE_TRIANGLES)
			assembled.append_from(result,0,Transform3D.IDENTITY)
			assembled.append_from(sculpture,0,Transform3D.IDENTITY)
			result=assembled.commit()
	meshes[id]=result
	return result

static func _box(parts: Array, at:Vector3, dimensions:Vector3, tone:Color, axis:Vector3 = Vector3.UP, yaw:float = 0.0, tip:float = 1.0) -> void:
	parts.append([at,dimensions,tone,Basis(axis,yaw),tip])

static func _shaft(shape: WastelandScenery, a:Vector3, b:Vector3, lo:float, hi:float, color:Color, sides: int = 10) -> void:
	shape.tube(PackedVector3Array([a,a.lerp(b,0.34),b]),PackedFloat32Array([lo,lerpf(lo,hi,0.34),hi]),sides,color,0.24)

static func _band(shape:WastelandScenery,at:Vector3,axis:Vector3,radius:float,thickness:float,color:Color) -> void:
	var half:=axis.normalized()*thickness*0.5
	_shaft(shape,at-half,at+half,radius,radius,color,8)

static func _tool(id:String,tint:Color,definition:Dictionary,parts:Array,shape:WastelandScenery) -> void:
	var long := id in ["sledge","shovel","hoe","steel_axe"]
	var haft := 0.60 if long else 0.48
	var bottom := Vector3(0,-0.32,0.012)
	var cap := Vector3(-0.037,haft,0.012)
	var bow := Vector3(0.022,haft*0.41,0.0)
	shape.tube(PackedVector3Array([bottom,Vector3(0,-0.17,0),Vector3(0,0.01,0.001),bow,cap]),
		PackedFloat32Array([0.035,0.044,0.047,0.042,0.045]),12,WOOD.lightened(0.06 if id=="club" else 0.0),0.14)
	for wrap in range(5):
		_band(shape,Vector3(0,-0.231+wrap*0.046,0),Vector3(0.07,1,0),0.050,0.025,LEATHER.lightened(wrap*0.026))
	if id=="club":
		shape.tube(PackedVector3Array([Vector3(0.014,0.103,0),Vector3(0.018,0.29,0),cap+Vector3(0,0.036,-0.011),cap+Vector3(0,0.10,-0.014)]),
			PackedFloat32Array([0.045,0.082,0.100,0.071]),12,tint.darkened(0.24),0.13)
		var stub := Vector3(-0.147,0.45,0.053)
		_shaft(shape, Vector3(-0.02,0.33,0.015), stub, 0.069, 0.034, WOOD.darkened(0.29), 7)
		_band(shape, stub, Vector3(-0.8,0.8,0.25), 0.034, 0.009, SAND.lightened(0.17))
		shape.triangle(Vector3(0.018,0.20,0.075), Vector3(-0.004,0.44,0.098),
			Vector3(0.047,0.38,0.091), Vector3.BACK, SAND.lightened(0.20))
		shape.triangle(Vector3(-0.004,0.44,0.098), Vector3(-0.042,0.55,0.079),
			Vector3(0.047,0.38,0.091), Vector3.BACK, WOOD.lightened(0.30))
		_band(shape, cap + Vector3(0,0.10,-0.014), Vector3.UP, 0.067, 0.008, SAND)
	elif id=="stone_axe":
		var rim := PackedVector3Array([Vector3(0.098,0.049,0),Vector3(-0.02,0.101,-0.007),
			Vector3(-0.22,0.073,0),Vector3(-0.284,-0.024,0.007),Vector3(-0.239,-0.115,0),
			Vector3(-0.067,-0.076,-0.006),Vector3(0.08,-0.053,0)])
		for i in rim.size():
			var next := (i + 1) % rim.size()
			var facet := tint.lightened(0.27) if i in [2,3] else tint.darkened(0.10 + i * 0.032)
			shape.triangle(cap + rim[i], cap + rim[next], cap + Vector3(-0.073,0.017,0.083), Vector3.BACK, facet)
			shape.triangle(cap + rim[i], cap + rim[next], cap + Vector3(-0.089,-0.007,-0.075), Vector3.FORWARD, facet.darkened(0.08))
		for tie in range(4):
			var strap := Basis(Vector3.FORWARD,lerpf(-0.64,0.61,float(tie)/3.0))
			parts.append([cap+Vector3(0.022,-0.017,0.067),Vector3(0.031,0.198,0.029),LEATHER.lightened(0.10+0.029*tie),strap])
	elif id=="iron_hammer":
		_box(parts,cap,Vector3(0.22,0.105,0.106),METAL.darkened(0.16))
		_box(parts,cap+Vector3(-0.13,0,0),Vector3(0.07,0.13,0.13),tint)
		_box(parts,cap+Vector3(0.14,-0.023,0),Vector3(0.12,0.055,0.064),METAL,Vector3.BACK,-0.34)
	elif id=="sledge":
		_box(parts,cap+Vector3(-0.039,0,0.01),Vector3(0.385,0.133,0.15),METAL.darkened(0.25),Vector3.BACK,-0.11)
		for tip in [-1,1]:
			_box(parts,cap+Vector3(tip*0.195,0,0),Vector3(0.112,0.143,0.173),tint,Vector3.BACK,-0.11)
		_band(shape,cap-Vector3.UP*0.12,Vector3.UP,0.063,0.088,BRASS.darkened(0.20))
	elif id in ["shovel","hoe"]:
		var center:=cap+Vector3(-0.063,0.065,0)
		var width:=0.171 if id=="shovel" else 0.235
		_box(parts,center,Vector3(width,0.237 if id=="shovel" else 0.115,0.065),tint,Vector3.BACK,-0.23,0.62)
		_box(parts,center+Vector3(0,0.10,0.012),Vector3(width*0.65,0.060,0.049),tint.lightened(0.31),Vector3.BACK,-0.21,0.68)
	else:
		var head:=cap+Vector3(-0.08,-0.035,0)
		var iron:=tint.darkened(0.27 if int(definition.get("power",0))<3 else 0.11)
		_box(parts,head,Vector3(0.251,0.106,0.080),iron,Vector3.BACK,-0.15)
		_box(parts,head+Vector3(-0.149,-0.016,0),Vector3(0.123,0.202,0.057),tint,Vector3.BACK,-0.054,0.71)
		_box(parts,head+Vector3(-0.207,-0.011,0),Vector3(0.032,0.177,0.027),tint.lightened(0.32),Vector3.BACK,-0.06,0.79)
		_band(shape,cap+Vector3(0.006,-0.137,0.0),Vector3.UP,0.059,0.058,INK)

static func _ranged(id:String,tint:Color,parts:Array,shape:WastelandScenery) -> void:
	if id=="bow":
		var ribs:=PackedVector3Array([
			Vector3(0,-0.537,0.127),Vector3(0,-0.46,0.044),Vector3(0,-0.31,-0.11),Vector3(0,-0.13,-0.19),
			Vector3(0,0,-0.225),Vector3(0,0.14,-0.18),Vector3(0,0.37,-0.082),Vector3(0,0.56,0.12)])
		shape.tube(ribs,PackedFloat32Array([0.016,0.024,0.035,0.044,0.051,0.047,0.030,0.014]),9,WOOD.lightened(0.15),0.12)
		_shaft(shape,ribs[0],ribs[ribs.size()-1],0.006,0.006,LINEN,5)
		for wrap in range(6):
			_band(shape,Vector3(0,-0.11+wrap*0.043,-0.215),Vector3.UP,0.051,0.027,LEATHER.lightened(wrap*0.038))
		_shaft(shape,Vector3(0,0.071,0.233),Vector3(0,0.071,-0.469),0.010,0.009,SAND,6)
		shape.lobe(Vector3(0,0.071,-0.457),Vector3(0.023,0.032,0.057),tint.lightened(0.32),0.3,false)
		return
	var rifle:=id=="rifle"
	var length:=0.651 if rifle else 0.353
	var receiver:=tint.darkened(0.46)
	var top_color:=tint.darkened(0.18)
	_box(parts,Vector3(0,0.064,-length*0.22),Vector3(0.141,0.113,length),receiver)
	_box(parts,Vector3(0,0.129,-length*0.25),Vector3(0.138,0.071,length*1.04),top_color)
	_box(parts,Vector3(0,-0.072,0.028),Vector3(0.106,0.235,0.130),INK,Vector3.RIGHT,-0.21,0.87)
	_box(parts,Vector3(0,-0.163,0.051),Vector3(0.119,0.043,0.136),receiver)
	_box(parts,Vector3(0,0.177,-length*0.64),Vector3(0.050,0.039,0.039),BRASS)
	_box(parts,Vector3(0,0.169,0.035),Vector3(0.093,0.035,0.041),INK)
	_shaft(shape,Vector3(0,0.104,-length*0.32),Vector3(0,0.105,-length*(1.05 if rifle else 0.86)),0.037,0.031,INK)
	_band(shape,Vector3(0,0.104,-length*(1.03 if rifle else 0.87)),Vector3.FORWARD,0.049,0.038,top_color)
	for face in [-1,1]:
		for groove in range(5):
			_box(parts,Vector3(face*0.071,0.136,-length*0.13-groove*0.025),Vector3(0.009,0.054,0.012),receiver,Vector3.RIGHT,0.28)
		_box(parts,Vector3(face*0.074,0.072,-0.117),Vector3(0.015,0.045,0.078),top_color.lightened(0.14))
	if rifle:
		_box(parts,Vector3(0,-0.087,-0.196),Vector3(0.087,0.205,0.120),receiver,Vector3.RIGHT,0.16)
		_box(parts,Vector3(0,0.045,-0.373),Vector3(0.171,0.118,0.296),WOOD.darkened(0.10))
		_box(parts,Vector3(0,0.046,0.278),Vector3(0.117,0.155,0.299),WOOD,Vector3.RIGHT,0.07)
		_box(parts,Vector3(0,0.042,0.414),Vector3(0.134,0.179,0.047),INK)
		for vent in range(8):
			_box(parts,Vector3(0,0.102,-0.292-vent*0.023),Vector3(0.179,0.032,0.011),WOOD.darkened(0.27))

static func _provision(id:String,tint:Color,kind:String,parts:Array,shape:WastelandScenery) -> void:
	if id in ["clean_water","dirty_water","fuel","oil","mineral"]:
		var paint:=WATER if id=="clean_water" else tint.darkened(0.07)
		shape.tube(PackedVector3Array([Vector3.DOWN*0.232,Vector3.DOWN*0.194,Vector3.DOWN*0.13,Vector3.UP*0.118,Vector3.UP*0.174,Vector3.UP*0.239]),
			PackedFloat32Array([0.112,0.143,0.148,0.147,0.088,0.061]),14,paint,0.07)
		_band(shape,Vector3.UP*0.254,Vector3.UP,0.071,0.059,LINEN if id=="clean_water" else INK)
		_band(shape,Vector3.DOWN*0.021,Vector3.UP,0.151,0.101,Color("#a6dbd6") if id=="clean_water" else Color("#c3a888"))
		_box(parts,Vector3(0,-0.013,-0.154),Vector3(0.069,0.061,0.009),Color("#406580") if id=="clean_water" else INK)
	elif id in ["canned","stew"]:
		_shaft(shape,Vector3.DOWN*0.175,Vector3.UP*0.148,0.163,0.173,BRASS,16)
		for y in [-0.167,0.146]:
			_band(shape,Vector3.UP*y,Vector3.UP,0.184,0.041,LINEN)
		_band(shape,Vector3.UP*0.004,Vector3.UP,0.176,0.154,tint.darkened(0.17))
		_box(parts,Vector3(0.02,0.174,-0.031),Vector3(0.055,0.026,0.102),BRASS.darkened(0.31),Vector3.UP,0.68)
		_box(parts,Vector3(0,0.021,-0.180),Vector3(0.113,0.080,0.014),Color("#b37d56"))
	elif id=="bandage":
		_shaft(shape,Vector3(-0.20,0,0),Vector3(0.19,0,0),0.144,0.142,LINEN,14)
		for y in [-0.14,-0.048,0.046,0.14]:
			_band(shape,Vector3(y,0,0),Vector3.RIGHT,0.148,0.031,tint.lightened(0.12))
		_band(shape,Vector3(0.201,0,0),Vector3.RIGHT,0.059,0.031,LEATHER)
		_box(parts,Vector3(0.023,-0.060,0.085),Vector3(0.268,0.043,0.241),LINEN.lightened(0.18),Vector3.RIGHT,-0.28,0.74)
	elif id in ["medkit","antibiotic","splint"]:
		_box(parts,Vector3.ZERO,Vector3(0.418,0.312,0.229),tint.darkened(0.22))
		_box(parts,Vector3(0,0,-0.12),Vector3(0.358,0.248,0.030),tint.lightened(0.17))
		_box(parts,Vector3(0,0.001,-0.146),Vector3(0.175,0.05,0.013),Color("#a84d58"))
		_box(parts,Vector3(0,0.001,-0.148),Vector3(0.048,0.172,0.013),Color("#a84d58"))
		_box(parts,Vector3(0,0.172,-0.008),Vector3(0.206,0.078,0.067),INK)
	elif kind=="seed":
		_box(parts,Vector3.ZERO,Vector3(0.313,0.382,0.139),Color("#bfa184"),Vector3.FORWARD,0.15,0.92)
		_box(parts,Vector3(0,0.134,-0.069),Vector3(0.320,0.047,0.036),LINEN,Vector3.FORWARD,0.15)
		for n in range(4):
			shape.lobe(Vector3((n%2)*0.10-0.063,0.047-n*0.046,-0.085),Vector3(0.048,0.033,0.012),tint,n,true,0.09)
	else:
		var pieces:=6 if id=="berries" else 3
		for n in range(pieces):
			var angle:=n*2.39996
			var small:=0.073 if id=="berries" else 0.127
			var point:=Vector3(cos(angle)*0.109,n*0.020-0.047,sin(angle)*0.103)
			shape.lobe(point,Vector3(small*1.11,small,small*1.12),tint.lightened((n%3)*0.12),angle,true,0.145)
		if id in ["corn","berries","potato"]:
			for n in range(4):
				shape.foliage_blade(Vector3(0,-0.105,0),n*1.54,0.267,0.104,0.18,Color("#8e9e68"))

static func _equipment(id:String,tint:Color,parts:Array,shape:WastelandScenery) -> void:
	if id=="frame":
		var r:=0.177
		for x in [-r,r]:
			for z in [-r,r]:
				_box(parts,Vector3(x,0,z),Vector3(0.040,0.375,0.040),WOOD.lightened(0.22))
		for y in [-r,r]:
			for edge in [-r,r]:
				_box(parts,Vector3(0,y,edge),Vector3(0.377,0.042,0.044),tint.darkened(0.12))
				_box(parts,Vector3(edge,y,0),Vector3(0.042,0.043,0.378),tint.darkened(0.08))
		_box(parts,Vector3(0,0,-r),Vector3(0.039,0.477,0.033),WOOD,Vector3.BACK,0.76)
	elif id in ["connector","wire","barbed","fence"]:
		for ring in range(3):
			var cord:=PackedVector3Array()
			var bounds:=PackedFloat32Array()
			for n in range(19):
				var a:=float(n)*TAU/18.0
				cord.append(Vector3(cos(a)*(0.144+ring*0.009),sin(a)*(0.144+ring*0.009),-0.059+ring*0.058))
				bounds.append(0.023)
			shape.tube(cord,bounds,6,BRASS.lightened(ring*0.08))
		_box(parts,Vector3(0,0.023,0.016),Vector3(0.105,0.41,0.092),INK,Vector3.FORWARD,-0.57)
		_box(parts,Vector3(-0.149,0.132,0.016),Vector3(0.091,0.119,0.101),tint,Vector3.FORWARD,-0.58,0.72)
	elif id in ["campfire","spikes","blade"]:
		for i in range(5):
			var twist:=i*TAU/5.0
			var radial:=Vector3(cos(twist),0,sin(twist))
			if id=="campfire":
				shape.lobe(radial*0.162+Vector3.DOWN*0.09,Vector3(0.091,0.064,0.086),METAL,twist,true)
				_shaft(shape,radial*0.16+Vector3.DOWN*0.02,radial*0.044+Vector3.UP*0.16,0.059,0.023,tint,6)
			else:
				_shaft(shape,radial*0.158+Vector3.DOWN*0.11,radial*0.11+Vector3.UP*0.17,0.054,0.008,tint,8)
		_box(parts,Vector3.DOWN*0.143,Vector3(0.37,0.081,0.34),WOOD)
	elif id in ["bench","chemistry","solar"]:
		for x in [-1,1]:
			for z in [-1,1]:
				_box(parts,Vector3(x*0.145,-0.087,z*0.111),Vector3(0.063,0.235,0.067),INK)
		_box(parts,Vector3.UP*0.050,Vector3(0.406,0.092,0.318),tint.darkened(0.20),Vector3.RIGHT,0.25 if id=="solar" else 0.0)
		for i in range(4):
			_box(parts,Vector3((i-1.5)*0.092,0.111,-0.053),Vector3(0.068,0.033 if id=="solar" else 0.102,0.128),tint.lightened(0.34))
	else:
		_box(parts,Vector3(0,-0.045,0),Vector3(0.392,0.312,0.328),tint.darkened(0.29))
		_box(parts,Vector3(0,0.143,0),Vector3(0.319,0.087,0.273),tint.lightened(0.13))
		for vent in range(4):
			_box(parts,Vector3((vent-1.5)*0.077,-0.091,-0.168),Vector3(0.027,0.129,0.027),INK)
		var spotlight:=id in ["turret","floodlight"]
		_box(parts,Vector3(0,0.041,-0.171),Vector3(0.215,0.084,0.094),LINEN if spotlight else BRASS)
		if spotlight:
			_shaft(shape,Vector3(0,0.120,-0.173),Vector3(0,0.12,-0.29),0.09,0.069,INK)

static func _kit(id:String,tint:Color,parts:Array) -> void:
	_box(parts,Vector3.ZERO,Vector3(0.458,0.302,0.310),INK)
	_box(parts,Vector3(0,0.130,0),Vector3(0.457,0.088,0.313),tint.darkened(0.28))
	for x in [-1,1]:
		for y in [-1,1]:
			_box(parts,Vector3(x*0.192,y*0.108,-0.149),Vector3(0.084,0.074,0.066),METAL)
		_box(parts,Vector3(x*0.115,0.169,0),Vector3(0.058,0.115,0.099),BRASS)
	_box(parts,Vector3(0,0.218,0),Vector3(0.278,0.051,0.099),tint)
	for mark in range(2 if id=="bicycle" else 3 if id=="boat" else 4 if id=="bike" else 5):
		_box(parts,Vector3((mark-2)*0.068,0.025,-0.159),Vector3(0.049,0.109,0.018),tint,Vector3.BACK,-0.34)

static func _ammo(id:String,tint:Color,parts:Array,shape:WastelandScenery) -> void:
	if id=="arrow":
		for n in range(3):
			var at:=Vector3((n-1)*0.077,-0.026,n*0.029)
			_shaft(shape,at-Vector3.UP*0.274,at+Vector3.UP*0.256,0.010,0.011,WOOD,6)
			shape.lobe(at+Vector3.UP*0.27,Vector3(0.035,0.057,0.017),METAL,n,false)
			_box(parts,at-Vector3.UP*0.203,Vector3(0.075,0.111,0.015),LINEN,Vector3.FORWARD,0.12+n*0.09,0.35)
	else:
		var length:=0.223 if id=="round" else 0.269
		for n in range(3):
			var x:float=(n-1)*0.106
			var at:=Vector3(x,(n%2)*0.075,0)
			_shaft(shape,at-Vector3.UP*length*0.58,at+Vector3.UP*length*0.35,0.052,0.046,BRASS,9)
			_band(shape,at-Vector3.UP*length*0.59,Vector3.UP,0.055,0.033,tint.lightened(0.14))
			_shaft(shape,at+Vector3.UP*length*0.28,at+Vector3.UP*length*0.75,0.043,0.013,METAL,9)

static func _light(parts:Array,shape:WastelandScenery) -> void:
	_box(parts,Vector3(0,-0.134,0),Vector3(0.252,0.100,0.226),INK)
	_box(parts,Vector3(0,0.03,0),Vector3(0.174,0.215,0.164),Color("#f8c77d"))
	_box(parts,Vector3(0,0.161,0),Vector3(0.239,0.083,0.207),BRASS.darkened(0.24))
	for side in [-1,1]:
		_shaft(shape,Vector3(side*0.102,-0.113,-0.07),Vector3(side*0.108,0.154,-0.07),0.014,0.013,INK,7)
		_box(parts,Vector3(side*0.089,0.214,0),Vector3(0.033,0.102,0.041),METAL,Vector3.BACK,side*0.23)
	_box(parts,Vector3(0,0.269,0),Vector3(0.148,0.030,0.042),METAL)

static func _garment(id:String,tint:Color,parts:Array) -> void:
	_box(parts,Vector3.ZERO,Vector3(0.374,0.395,0.142),tint.darkened(0.14),Vector3.UP,0,0.90)
	_box(parts,Vector3(0,0.214,-0.009),Vector3(0.172,0.071,0.118),INK)
	for side in [-1,1]:
		_box(parts,Vector3(side*0.233,0.009,0.013),Vector3(0.122,0.278,0.129),tint,Vector3.BACK,side*0.30,0.90)
		_box(parts,Vector3(side*0.111,0.026,-0.075),Vector3(0.109,0.205,0.052),tint.lightened(0.21 if id=="armor" else 0.07))
	_box(parts,Vector3(0,0.003,-0.09),Vector3(0.014,0.315,0.022),BRASS)

static func _garment_parts(parts: Array, shape: WastelandScenery) -> ArrayMesh:
	const RIM := [Vector2(-0.38,-0.5), Vector2(0.38,-0.5), Vector2(0.5,-0.38), Vector2(0.5,0.38),
		Vector2(0.38,0.5), Vector2(-0.38,0.5), Vector2(-0.5,0.38), Vector2(-0.5,-0.38)]
	var boxes: Array = []
	for part: Array in parts:
		var size: Vector3 = part[1]
		var thin_axis := size.min_axis_index()
		# Laces and zip fasteners are only a few millimetres across. Tapered
		# garment blocks already have a complete twelve-triangle silhouette.
		if part[4] != 1.0 or size[thin_axis] <= 0.018:
			boxes.append(part)
			continue
		var center: Vector3 = part[0]
		var rotation: Basis = part[3]
		var color: Color = part[2]
		var previous := PackedVector3Array()
		for depth: float in [-0.5, 0.0, 0.5]:
			var ring := PackedVector3Array()
			var inset := 1.0 if depth == 0.0 else 0.96
			for corner: Vector2 in RIM:
				var point := Vector3.ZERO
				point[thin_axis] = depth
				point[(thin_axis+1)%3] = corner.x * inset
				point[(thin_axis+2)%3] = corner.y * inset
				ring.append(center + rotation * (point * size))
			if depth != 0.0:
				var cap_normal := rotation[thin_axis] * signf(depth)
				for i in range(1, ring.size()-1):
					shape.triangle(ring[0],ring[i],ring[i+1],cap_normal,color)
			if not previous.is_empty():
				for i in ring.size():
					var next := (i+1) % ring.size()
					var outward := ((ring[i]+ring[next]+previous[i]+previous[next])*0.25-center).normalized()
					shape.triangle(previous[i],previous[next],ring[i],outward,color)
					shape.triangle(ring[i],previous[next],ring[next],outward,color)
			previous = ring
	return WastelandLook.mesh_parts(boxes) if not boxes.is_empty() else null

static func _journal(parts:Array) -> void:
	_box(parts,Vector3.ZERO,Vector3(0.332,0.397,0.069),INK,Vector3.BACK,0.11)
	_box(parts,Vector3(0.025,0.002,-0.046),Vector3(0.28,0.366,0.045),LINEN,Vector3.BACK,0.11)
	for n in range(6):
		_box(parts,Vector3(0.021,0.134-n*0.041,-0.073),Vector3(0.174-(n%3)*0.023,0.014,0.009),WOOD,Vector3.BACK,0.11)
	_box(parts,Vector3(-0.119,0.026,-0.064),Vector3(0.056,0.347,0.025),Color("#8d5560"),Vector3.BACK,0.11)

static func _material(id:String,tint:Color,parts:Array,shape:WastelandScenery) -> void:
	match id:
		"stick":
			shape.tube([Vector3(-0.09,-0.23,0),Vector3(0.01,0.03,0.01),Vector3(0.05,0.24,0)],[0.035,0.03,0.016],7,tint)
			shape.tube([Vector3(0.01,0.03,0.01),Vector3(0.13,0.15,-0.01)],[0.024,0.01],6,tint.lightened(0.18))
		"tree_leaf":
			_dry_leaf(shape,Vector3(-0.03,-0.07,-0.02),0.27,0.054,0.62,Color("#9aab60"))
			_dry_leaf(shape,Vector3(0.007,-0.15,0),0.32,0.080,-0.43,tint)
			_dry_leaf(shape,Vector3(0.025,-0.10,0.02),0.20,0.051,0.44,Color("#bd7747"))
		"leaf_kindling":
			for i in 5:
				var angle:=i*TAU/5
				var offset:=Vector3(cos(angle)*0.041,0,sin(angle)*0.041)
				_shaft(shape,offset+Vector3(-0.042,-0.19,0),offset*1.4+Vector3(0.041,0.17+(i%3)*0.024,0),0.023,0.013,WOOD,6)
			_dry_leaf(shape,Vector3(-0.019,-0.12,0.043),0.25,0.058,-0.24,tint)
			_dry_leaf(shape,Vector3(-0.024,-0.11,-0.037),0.23,0.060,0.14,tint.darkened(0.14))
			for y:float in [-0.049,0.011]:
				_band(shape,Vector3(y*0.24,y,0),Vector3(0.23,1,0),0.076,0.022,LINEN.darkened(0.16))
		"wood":
			for n in range(3):
				var offset:=Vector3((n-1)*0.114,(n%2)*0.056,n*0.013)
				_box(parts,offset,Vector3(0.107,0.419,0.141),WOOD.lightened(n*0.10),Vector3.BACK,(n-1)*0.18,0.82)
				_box(parts,offset+Vector3.UP*0.188,Vector3(0.095,0.067,0.127),SAND,Vector3.BACK,(n-1)*0.18)
		"scrap","parts","electronics","brass","lead","ingot","steel","casing","wire":
			for n in range(4):
				var at:=Vector3((n%2)*0.14-0.078,(n%3)*0.07-0.07,(n-1.5)*0.055)
				_box(parts,at,Vector3(0.184,0.132,0.241),tint.darkened(n*0.11),Vector3.UP,n*0.63,0.76)
				_box(parts,at+Vector3.UP*0.064,Vector3(0.122,0.038,0.208),tint.lightened(0.15),Vector3.UP,n*0.63)
		"fiber":
			for n in 8:
				var x:=(n-3.5)*0.018
				shape.tube([Vector3(x*0.65,-0.15,0),Vector3(x,0.01,(n%3)*0.017),Vector3(x*1.9,0.17+(n%3)*0.029,0.04)],[0.017,0.016,0.004],5,Color("#bbac69").darkened((n%3)*0.10))
			_box(parts,Vector3(0,-0.04,0.011),Vector3(0.152,0.044,0.084),LEATHER)
		"cloth","leather","tape":
			for n in range(4):
				_box(parts,Vector3(n*0.015-0.022,n*0.065-0.093,n*0.018),Vector3(0.292,0.067,0.229),tint.darkened(n*0.074),Vector3.UP,n*0.153)
			_box(parts,Vector3(0,0.024,-0.008),Vector3(0.084,0.297,0.262),LEATHER,Vector3.UP,0.12)
		"fuel","oil","mineral":
			_provision(id,tint,"food",parts,shape)
		_:
			for n in range(4):
				var at:=Vector3(cos(n*2.11)*0.103,n*0.059-0.05,sin(n*2.13)*0.097)
				shape.lobe(at,Vector3(0.133,0.107,0.107),tint.darkened(n*0.065),n,true,0.22)

static func _dry_leaf(shape:WastelandScenery,base:Vector3,length:float,width:float,angle:float,tint:Color)->void:
	var turn:=Basis(Vector3.BACK,angle)
	var tip:=base+turn*Vector3(width*0.14,length,-0.004)
	var ridge:=base+turn*Vector3(0,length*0.48,0.014)
	for side:float in [-1,1]:
		var lower:=base+turn*Vector3(width*side*0.82,length*0.27,-0.003)
		var edge:=base+turn*Vector3(width*side,length*0.56,-0.006)
		var upper:=base+turn*Vector3(width*side*0.52,length*0.78,0)
		var rim:=[base,lower,edge,upper,tip]
		var tone:=tint.lightened(0.13) if side<0 else tint
		var underside:=Vector3.FORWARD*0.0015
		for i in rim.size()-1:
			shape.triangle(ridge,rim[i],rim[i+1],Vector3.BACK,tone)
			shape.triangle(ridge+underside,rim[i]+underside,rim[i+1]+underside,Vector3.FORWARD,tone.darkened(0.06))
	shape.tube([base-turn*Vector3.UP*0.036,base,ridge,tip],[0.005,0.005,0.0035,0.001],5,tint.lightened(0.35))

static func icon(id:String,definition:Dictionary) -> ImageTexture:
	if icons.has(id):
		return icons[id]
	var model:=mesh(id,definition)
	var arrays:=model.surface_get_arrays(0)
	var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var kind:String=definition.get("kind","")
	var rotate := Basis(Vector3.FORWARD,-0.37 if kind in ["tool","weapon","ammo"] else 0.12) * Basis(Vector3.RIGHT,0.32) * Basis(Vector3.UP,-0.82 if kind!="ranged" else -1.00)
	if id=="tree_leaf":
		rotate=Basis(Vector3.BACK,0.14)*Basis(Vector3.UP,-0.22)
	if definition.get("shield",false):
		rotate=Basis(Vector3.BACK,-0.12)*Basis(Vector3.RIGHT,0.15)*Basis(Vector3.UP,PI-0.30)
	var mapped:=PackedVector3Array()
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for vertex in points:
		var rotated:=rotate*vertex
		mapped.append(rotated)
		low=low.min(Vector2(rotated.x,-rotated.y))
		high=high.max(Vector2(rotated.x,-rotated.y))
	var center:Vector2=(low+high)*0.5
	var zoom:=float(SIZE-8)/maxf(0.01,maxf(high.x-low.x,high.y-low.y))
	var pixels:=Image.create_empty(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	var depth:=PackedFloat32Array()
	depth.resize(SIZE*SIZE)
	depth.fill(-INF)
	var light:=Vector3(-0.5,0.8,0.65).normalized()
	for i in range(0,mapped.size(),3):
		var a:=mapped[i]
		var b:=mapped[i+1]
		var c:=mapped[i+2]
		var u:Vector2=(Vector2(a.x,-a.y)-center)*zoom+Vector2.ONE*float(SIZE)*0.5
		var v:Vector2=(Vector2(b.x,-b.y)-center)*zoom+Vector2.ONE*float(SIZE)*0.5
		var w:Vector2=(Vector2(c.x,-c.y)-center)*zoom+Vector2.ONE*float(SIZE)*0.5
		var normal:=rotate*normals[i]
		var tint:=colors[i].darkened(0.43-maxf(0.0,normal.dot(light))*0.43)
		_fill_icon(pixels,depth,u,v,w,Vector3(a.z,b.z,c.z),tint)
	var outlined:=pixels.duplicate() as Image
	for x in range(1,SIZE-1):
		for y in range(1,SIZE-1):
			if pixels.get_pixel(x,y).a>0.5:
				continue
			for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if pixels.get_pixel(x+d.x,y+d.y).a>0.5:
					outlined.set_pixel(x,y,Color("#272131"))
					break
	var texture:=ImageTexture.create_from_image(outlined)
	icons[id]=texture
	return texture

static func _fill_icon(pixels:Image,depth:PackedFloat32Array,a:Vector2,b:Vector2,c:Vector2,dist:Vector3,tint:Color) -> void:
	var ab:=b-a
	var ac:=c-a
	var det:=ab.cross(ac)
	if absf(det)<0.00001:
		return
	var low:=a.min(b).min(c).floor()
	var high:=a.max(b).max(c).ceil()
	for y in range(clampi(int(low.y),0,SIZE-1),clampi(int(high.y)+1,0,SIZE)):
		for x in range(clampi(int(low.x),0,SIZE-1),clampi(int(high.x)+1,0,SIZE)):
			var p:=Vector2(x+0.5,y+0.5)-a
			var ratio_b:=p.cross(ac)/det
			var ratio_c:=ab.cross(p)/det
			if ratio_b<0.0 or ratio_c<0.0 or ratio_b+ratio_c>1.0:
				continue
			var z:=dist.x+(dist.y-dist.x)*ratio_b+(dist.z-dist.x)*ratio_c
			var index:=x+y*SIZE
			if z>depth[index]:
				depth[index]=z
				pixels.set_pixel(x,y,tint)

# Ridged metal and stamped hardware share a closed silhouette on both sides.
static func _plate(shape:WastelandScenery,rim:Array,center:Vector3,depth:float,tone:Color)->void:
	for i in rim.size():
		var a:Vector3=rim[i]
		var b:Vector3=rim[(i+1)%rim.size()]
		var shade:=tone.lightened(0.10*(i%3))
		shape.triangle(a,b,center+Vector3.BACK*depth,Vector3.BACK,shade)
		shape.triangle(a,b,center+Vector3.FORWARD*depth,Vector3.FORWARD,shade.darkened(0.08))

static func _field_item(id:String,parts:Array,shape:WastelandScenery)->bool:
	var steel:=Color("#85949a")
	var green:=Color("#74885c")
	match id:
		"field_service_kit":
			_box(parts,Vector3.ZERO,Vector3(0.39,0.24,0.16),LEATHER)
			for x in [-0.12,0.12]:
				_box(parts,Vector3(x,0,0),Vector3(0.042,0.26,0.18),BRASS)
			_box(parts,Vector3(0,0.12,-0.02),Vector3(0.23,0.035,0.039),METAL)
		"reed_trauma_wrap":
			for i in 5:
				_box(parts,Vector3((i-2)*0.053,0.0,0.0),Vector3(0.046,0.36-(i%2)*0.04,0.072),SAND.lightened(0.07*i))
			for y in [-0.09,0.09]:
				_box(parts,Vector3(0,y,0),Vector3(0.28,0.06,0.088),LEATHER)
		"improvised_shield","dented_shield","cracked_shield":
			_plank_shield(id,parts,shape)
		"field_glasses":
			for x: float in [-0.098,0.098]:
				var front := Vector3(x,0.065,-0.186)
				var eye := Vector3(x*0.78,0.075,0.146)
				_shaft(shape,front,eye,0.097,0.067,green,14)
				_band(shape,front,Vector3.FORWARD,0.100,0.029,INK)
				_band(shape,front+Vector3.FORWARD*0.018,Vector3.FORWARD,0.081,0.009,Color("#76b6bb"))
				_band(shape,eye,Vector3.BACK,0.068,0.053,INK)
				_band(shape,eye+Vector3.BACK*0.029,Vector3.BACK,0.046,0.008,Color("#557f91"))
			_box(parts,Vector3(0,0.06,-0.014),Vector3(0.166,0.064,0.096),METAL)
			_band(shape,Vector3(0,0.128,-0.002),Vector3.BACK,0.039,0.065,INK)
			shape.tube(PackedVector3Array([Vector3(-0.14,0.02,0.06),Vector3(-0.13,-0.14,0.10),Vector3(0.04,-0.18,0.13),Vector3(0.14,0.02,0.06)]),PackedFloat32Array([0.012,0.012,0.012,0.012]),5,LEATHER,0)
		"composite_filter":
			_shaft(shape,Vector3(0,-0.19,0),Vector3(0,0.19,0),0.082,0.082,Color("#ab8962"),16)
			for i in 12:
				var angle:=TAU*i/12.0
				var offset:=Vector3(cos(angle),0,sin(angle))*0.079
				_shaft(shape,offset-Vector3.UP*0.17,offset+Vector3.UP*0.17,0.015,0.015,Color("#e8d9a6"),5)
			for y:float in [-0.18,0.0,0.18]:
				_band(shape,Vector3(0,y,0),Vector3.UP,0.096,0.035,BRASS)
			_band(shape,Vector3(0,0.218,0),Vector3.UP,0.045,0.045,INK)
		"reinforcement_kit":
			for i in 4:
				var offset:=Vector3((i%2-0.5)*0.063,(floori(i/2.0)-0.5)*0.06,0)
				_shaft(shape,offset+Vector3.FORWARD*0.245,offset+Vector3.BACK*0.245,0.036,0.037,WOOD,7)
			_box(parts,Vector3(0,0.067,0),Vector3(0.18,0.05,0.32),steel)
			for z:float in [-0.107,0.107]:
				_box(parts,Vector3(0,0.016,z),Vector3(0.192,0.173,0.036),LEATHER)
		"filter_pump":
			_shaft(shape,Vector3(0,-0.22,0),Vector3(0,0.112,0),0.10,0.10,Color("#548b90"),12)
			for y: float in [-0.213,-0.028,0.107]:
				_band(shape,Vector3(0,y,0),Vector3.UP,0.104,0.027,BRASS)
			_shaft(shape,Vector3(0,0.117,0),Vector3(0,0.211,0),0.025,0.025,METAL)
			_shaft(shape,Vector3(-0.096,0.218,0),Vector3(0.096,0.218,0),0.032,0.032,INK)
			shape.tube(PackedVector3Array([Vector3(0.081,0.065,0),Vector3(0.17,0.08,0),Vector3(0.18,-0.21,0.02),Vector3(0.097,-0.29,0.035)]),PackedFloat32Array([0.024,0.024,0.020,0.020]),8,INK,0)
			_shaft(shape,Vector3(-0.085,0.065,0),Vector3(-0.155,0.103,0),0.023,0.018,BRASS)
		"iron_pick","field_sickle","reed_spear","baton":
			var top:float={"iron_pick":0.51,"field_sickle":0.24,"reed_spear":0.85,"baton":0.37}[id]
			var bottom:=-0.52 if id=="reed_spear" else -0.30
			var wood:=Color("#bfa474") if id=="reed_spear" else WOOD
			if id=="baton": wood=Color("#464c52")
			_shaft(shape,Vector3.UP*bottom,Vector3.UP*top,0.039,0.051 if id=="baton" else 0.032,wood,12)
			for i in 5:
				_band(shape,Vector3.UP*(-0.20+i*0.040),Vector3.UP,0.043,0.023,LEATHER)
			if id=="iron_pick":
				var path:=PackedVector3Array([Vector3(-0.37,0.33,0),Vector3(-0.24,0.47,0),Vector3(-0.09,0.51,0),Vector3(0.09,0.49,0),Vector3(0.22,0.41,0),Vector3(0.28,0.35,0)])
				shape.tube(path,PackedFloat32Array([0.005,0.026,0.046,0.044,0.031,0.012]),6,steel,0)
				_band(shape,Vector3.UP*0.478,Vector3.UP,0.060,0.080,METAL.darkened(0.22))
			elif id=="field_sickle":
				var arc:=PackedVector3Array()
				var widths:=PackedFloat32Array()
				for i in 13:
					var angle:=lerpf(-0.96,2.44,i/12.0)
					arc.append(Vector3(-0.134+0.224*cos(angle),0.34+0.159*sin(angle),0))
					widths.append(0.012+0.040*sin(PI*i/12.0))
				for i in 12:
					var a:=arc[i]
					var b:=arc[i+1]
					var ta:=arc[i+1]-arc[maxi(0,i-1)]
					var tb:=arc[mini(12,i+2)]-arc[i]
					var edge_a:=Vector3(-ta.y,ta.x,0).normalized()*widths[i]
					var edge_b:=Vector3(-tb.y,tb.x,0).normalized()*widths[i+1]
					for side:float in [-1,1]:
						var face:=Vector3.BACK*side
						var ridge_a:=a+face*0.011
						var ridge_b:=b+face*0.011
						for edge:float in [-1,1]:
							var tone:=steel.lightened(0.27) if edge<0 else steel
							shape.triangle(a+edge_a*edge,b+edge_b*edge,ridge_a,face,tone)
							shape.triangle(ridge_a,b+edge_b*edge,ridge_b,face,tone)
				_band(shape,Vector3.UP*0.232,Vector3.UP,0.045,0.045,BRASS)
			elif id=="reed_spear":
				_plate(shape,[Vector3(0,1.10,0),Vector3(0.078,0.865,0),Vector3(0.025,0.80,0),Vector3(-0.025,0.80,0),Vector3(-0.074,0.885,0)],Vector3(0,0.884,0),0.027,steel)
				for i in 4: _band(shape,Vector3.UP*(0.744+i*0.026),Vector3.UP,0.044,0.018,LINEN)
				for y:float in [-0.37,0.22,0.47,0.65]: _band(shape,Vector3.UP*y,Vector3.UP,0.038,0.012,WOOD)
			else:
				_band(shape,Vector3.UP*0.13,Vector3.UP,0.055,0.038,BRASS)
				_band(shape,Vector3.UP*0.36,Vector3.UP,0.050,0.035,METAL)
				_shaft(shape,Vector3(-0.014,0.07,0),Vector3(-0.13,-0.027,0),0.028,0.025,INK)
		"salvage_wrench":
			_box(parts,Vector3(0,-0.025,0),Vector3(0.092,0.52,0.043),Color("#8d999c"),Vector3.BACK,-0.07,0.83)
			_box(parts,Vector3(0.008,-0.17,0),Vector3(0.096,0.25,0.056),Color("#ad6951"),Vector3.BACK,-0.07,0.80)
			for side:float in [-1,1]:
				var arm:=PackedVector3Array([Vector3(0,0.19,0),Vector3(side*0.080,0.25,0),Vector3(side*0.112,0.333,0),Vector3(side*0.093+0.026,0.382,0)])
				shape.tube(arm,PackedFloat32Array([0.055,0.055,0.038,0.020]),6,steel,0)
			for i in 4: _band(shape,Vector3(-0.024+i*0.016,0.211,-0.033),Vector3.RIGHT,0.030,0.012,INK)
		"field_crossbow","field_crossbow_empty":
			_box(parts,Vector3(0,0.035,-0.06),Vector3(0.105,0.106,0.64),WOOD,Vector3.RIGHT,0.04,0.71)
			_box(parts,Vector3(0,-0.061,0.03),Vector3(0.081,0.22,0.105),LEATHER,Vector3.RIGHT,-0.28)
			_box(parts,Vector3(0,0.080,-0.15),Vector3(0.036,0.035,0.54),steel)
			for side:float in [-1,1]:
				var base:=Vector3(0,0.091,-0.33)
				var tip:=Vector3(side*0.39,0.093,-0.14)
				shape.tube(PackedVector3Array([base,Vector3(side*0.20,0.125,-0.31),tip]),PackedFloat32Array([0.038,0.031,0.012]),8,Color("#625a56"),0)
				_shaft(shape,tip,Vector3(0,0.109,0.080),0.006,0.006,LINEN,5)
				_band(shape,Vector3(side*0.11,0.101,-0.322),Vector3.UP,0.031,0.052,BRASS)
			if id=="field_crossbow":
				_field_bolt(shape,steel)
		"field_crossbow_bolt":
			_field_bolt(shape,steel)
		"hardhat":
			var amber:=Color("#dba042")
			const SHELL_SIDES := 16
			var profile:=[Vector3(-0.066,0.203,0.216),Vector3(-0.059,0.235,0.270),Vector3(-0.044,0.236,0.266),Vector3(-0.029,0.205,0.209),Vector3(0.035,0.200,0.208),Vector3(0.09,0.177,0.189),Vector3(0.135,0.131,0.142),Vector3(0.156,0.051,0.076),Vector3(0.161,0.003,0.003)]
			for j in profile.size()-1:
				var row:Vector3=profile[j]
				var next:Vector3=profile[j+1]
				for i in SHELL_SIDES:
					var a:=TAU*i/SHELL_SIDES
					var b:=TAU*(i+1)/SHELL_SIDES
					var p:=Vector3(cos(a)*row.y,row.x,sin(a)*row.z)
					var q:=Vector3(cos(b)*row.y,row.x,sin(b)*row.z)
					var r:=Vector3(cos(a)*next.y,next.x,sin(a)*next.z)
					var t:=Vector3(cos(b)*next.y,next.x,sin(b)*next.z)
					var normal:=Vector3(cos(a),0.1*j,sin(a))
					var dye:=amber.darkened(0.33) if j==0 else amber
					shape.triangle(p,q,r,normal,dye)
					shape.triangle(r,q,t,normal,dye)
			_box(parts,Vector3(0,0.157,0.025),Vector3(0.044,0.045,0.223),amber.lightened(0.15))
			_box(parts,Vector3(0,0.045,-0.197),Vector3(0.104,0.065,0.044),INK)
			_box(parts,Vector3(0,0.050,-0.219),Vector3(0.068,0.044,0.012),LINEN)
		"work_gloves","trail_boots":
			for side:float in [-1,1]:
				var x:=side*0.102
				if id=="work_gloves":
					shape.lobe(Vector3(x,-0.005,0),Vector3(0.086,0.108,0.040),LEATHER,0,true)
					_box(parts,Vector3(x,-0.105,0),Vector3(0.15,0.073,0.069),LINEN)
					for i in 4:
						shape.tube([Vector3(x-0.059+i*0.039,0.045,0),Vector3(x-0.064+i*0.041,0.155+0.037*sin(i*PI/3),-0.01)],[0.020,0.015],6,SAND,0.24)
					shape.tube([Vector3(x+side*0.056,0.004,0),Vector3(x+side*0.107,0.087,-0.014)],[0.030,0.015],6,SAND,0.24)
				else:
					var z:=side*0.062
					shape.lobe(Vector3(x,-0.058,z-0.05),Vector3(0.093,0.088,0.17),LEATHER,0,true)
					_box(parts,Vector3(x,-0.12,z-0.052),Vector3(0.18,0.035,0.308),INK)
					shape.tube([Vector3(x,-0.027,z+0.027),Vector3(x,0.152,z+0.027)],[0.083,0.084],8,WOOD,0.24)
					for j in 3: _box(parts,Vector3(x,0.019+0.035*j,z-0.052),Vector3(0.114,0.011,0.012),LINEN,Vector3.BACK,0.13*side)
		"oilskin_vest":
			var wax:=Color("#86905a")
			_box(parts,Vector3(0,-0.035,0),Vector3(0.34,0.26,0.11),wax,Vector3.UP,0,0.88)
			for side:float in [-1,1]:
				_box(parts,Vector3(side*0.106,0.127,0),Vector3(0.088,0.16,0.091),wax,Vector3.BACK,-side*0.13)
				_box(parts,Vector3(side*0.088,-0.072,-0.061),Vector3(0.118,0.082,0.025),wax.darkened(0.19))
			_box(parts,Vector3(0,-0.036,-0.060),Vector3(0.013,0.25,0.012),BRASS)
		"medicinal_herb","reed_stem":
			for i in 5:
				var a:=i*2.4
				var tip:=Vector3(0.094*cos(a),0.16+i*0.023,0.07*sin(a))
				var foot:=Vector3(-0.011*i,-0.18,0)
				_shaft(shape,foot,tip,0.011,0.007,green,7)
				if id=="reed_stem":
					_shaft(shape,tip,tip+Vector3(0.021*cos(a),0.096,0.016*sin(a)),0.024,0.017,WOOD,8)
				else:
					for j in 3: shape.foliage_blade(foot.lerp(tip,0.30+0.21*j),a+j*2.26,0.13,0.057,0.045,green.lightened(j*0.10))
		"herbal_tea":
			var cup:=Color("#769690")
			shape.tube([Vector3.DOWN*0.16,Vector3.UP*0.09,Vector3.UP*0.135],[0.123,0.15,0.153],12,cup)
			_band(shape,Vector3.UP*0.14,Vector3.UP,0.15,0.015,LINEN)
			shape.lobe(Vector3.UP*0.148,Vector3(0.139,0.012,0.137),Color("#905e36"),0,true)
			shape.tube([Vector3(0.119,-0.09,0),Vector3(0.235,-0.069,0),Vector3(0.23,0.066,0),Vector3(0.135,0.08,0)],[0.024,0.026,0.026,0.024],6,cup)
			shape.foliage_blade(Vector3(-0.055,0.15,0),0.5,0.042,0.055,0.075,green)
		"harvest_skewer":
			_shaft(shape,Vector3(-0.28,-0.19,0),Vector3(0.27,0.19,0),0.014,0.008,WOOD,7)
			for i in 4:
				var p:=Vector3(-0.12+0.095*i,-0.082+0.067*i,0)
				var corn:=i%2==0
				shape.lobe(p,Vector3(0.067,0.066,0.071),Color("#d89d46") if corn else Color("#9c6642"),i,true,0.10)
				for j in 3:
					_box(parts,p+Vector3(-0.024+j*0.022,0.019,-0.057),Vector3(0.011,0.044,0.011),Color("#82532f"),Vector3.BACK,-0.3)
		"trail_ration":
			_box(parts,Vector3(0,-0.059,0),Vector3(0.40,0.105,0.24),Color("#939063"),Vector3.UP,0.21)
			for i in 3:
				_box(parts,Vector3(0.018*i,0.014+i*0.039,0),Vector3(0.33-i*0.025,0.038,0.16),Color("#995842").lightened(i*0.07),Vector3.UP,-0.12+i*0.16)
			for x in [-0.09,0.13]:
				_box(parts,Vector3(x,0.018,0),Vector3(0.029,0.19,0.25),LINEN,Vector3.UP,0.08)
		"cactus_fruit":
			for i in 2:
				var at:=Vector3(-0.085+i*0.13,-0.036+i*0.046,i*0.043)
				shape.lobe(at,Vector3(0.118,0.18,0.105),Color("#af4967").lightened(0.10*i),i,true,0.07)
				_band(shape,at+Vector3.UP*0.146,Vector3.UP,0.045,0.034,Color("#d19c64"))
				for j in 5:
					var a:=j*2.4
					var dot:=at+Vector3(cos(a)*0.109,(j-2)*0.026,sin(a)*0.097)
					shape.lobe(dot,Vector3.ONE*0.012,Color("#e5b393"),a,false)
		"packed_snow":
			for i in 5:
				var a:=i*2.4
				var at:=Vector3(cos(a)*0.084,i*0.025-0.09,sin(a)*0.077)
				shape.lobe(at,Vector3(0.129,0.093,0.118),Color("#afcfdf").lightened(i*0.055),a,true,0.21)
		"iron_ore":
			shape.lobe(Vector3.ZERO,Vector3(0.23,0.16,0.16),Color("#575558"),0,true,0.32)
			for i in 11:
				var a:=i*2.4
				shape.lobe(Vector3(0.154*cos(a),0.065+0.058*sin(i),0.116*sin(a)),Vector3(0.087,0.055,0.066),Color("#a96b50").lightened(0.05*(i%3)),a,false,0.28)
		"spring":
			var axis:=PackedVector3Array()
			var radii:=PackedFloat32Array()
			for i in 89:
				var t:=i/88.0
				axis.append(Vector3(0.085*cos(t*TAU*5),lerpf(-0.18,0.18,t),0.085*sin(t*TAU*5)))
				radii.append(0.017)
			shape.tube(axis,radii,7,steel,0)
		_: return false
	return true

static func _plank_shield(id:String,parts:Array,shape:WastelandScenery)->void:
	# Both hands attach to the origin at the center of the wrapped grip.
	var top:=[0.365,0.429,0.458,0.472,0.457,0.426,0.359]
	var foot:=[-0.316,-0.398,-0.461,-0.496,-0.456,-0.397,-0.314]
	var plank_colors:=["976747","b48659","9f714c","b08054","966541","ae805a","a3744f"]
	for i in 7:
		var x:=(i-3)*0.103
		var high:float=top[i]
		var low:float=foot[i]
		var notch:=0.017
		var split_width:=0.004
		if id!="improvised_shield" and i==5:
			high-=0.067
			notch=0.075
		if id=="cracked_shield" and i==0:
			high-=0.13
			notch=0.095
			low+=0.11
		if id=="cracked_shield" and i==2:
			notch=0.247
			split_width=0.025
		var bevel_left:=0.086 if i==0 else 0.008
		var bevel_right:=0.086 if i==6 else 0.008
		var rim:=PackedVector2Array([Vector2(x-0.051,low+bevel_left),Vector2(x-0.030,low),
			Vector2(x+0.029,low+0.005),Vector2(x+0.051,low+bevel_right),Vector2(x+0.051,high-bevel_right),
			Vector2(x+0.028,high),Vector2(x+0.011,high-notch),Vector2(x+0.011-split_width,high-0.004),
			Vector2(x-0.026,high-0.005),Vector2(x-0.051,high-bevel_left)])
		var grain:=Color(plank_colors[i])
		var triangles:=Geometry2D.triangulate_polygon(rim)
		# Negative Z faces the incoming blow. The rear clears the curled fingers.
		for z:float in [-0.135,-0.096]:
			var normal:=Vector3.FORWARD if z < -0.12 else Vector3.BACK
			for j in range(0,triangles.size(),3):
				var a:=rim[triangles[j]]
				var b:=rim[triangles[j+1]]
				var c:=rim[triangles[j+2]]
				shape.triangle(Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(c.x,c.y,z),normal,grain)
			var surface_z:=z+normal.z*0.0008
			for stripe in 3:
				var gx:=x-0.030+stripe*0.023
				var gy:=lerpf(low,high,0.10+stripe*0.22+0.04*(i%2))
				var length:=(0.19+0.055*((i+stripe)%3))*(high-low)
				shape.triangle(Vector3(gx,gy,surface_z),Vector3(gx+0.009,gy+length*0.64,surface_z),
					Vector3(gx+0.003,gy+length,surface_z),normal,grain.darkened(0.23))
		# A chipped diagonal paint stripe on the salvaged boards identifies the outside.
		if i in [1,2,3,4,5]:
			var stripe_y:=0.003+x*0.45
			var paint:=Color("#baab82").lerp(grain,0.2+0.11*(i%3))
			var a:=Vector3(x-0.047,stripe_y-0.022,-0.137)
			var b:=Vector3(x+0.045,stripe_y+0.020,-0.137)
			var c:=Vector3(b.x-0.007,b.y+0.040,-0.137)
			var d:=Vector3(a.x+0.001,a.y+0.043,-0.137)
			shape.triangle(a,b,c,Vector3.FORWARD,paint)
			shape.triangle(a,c,d,Vector3.FORWARD,paint)
		for j in rim.size():
			var a:=rim[j]
			var b:=rim[(j+1)%rim.size()]
			var edge:=Vector3(b.y-a.y,a.x-b.x,0).normalized()
			var back_a:=Vector3(a.x,a.y,-0.096)
			var back_b:=Vector3(b.x,b.y,-0.096)
			var front_a:=Vector3(a.x,a.y,-0.135)
			var front_b:=Vector3(b.x,b.y,-0.135)
			shape.triangle(back_a,back_b,front_a,edge,grain.darkened(0.20))
			shape.triangle(back_b,front_a,front_b,edge,grain.darkened(0.20))
	var iron:=Color("#596770")
	for y:float in [-0.221,0.216]:
		_box(parts,Vector3(0,y,-0.084),Vector3(0.707,0.062,0.028),Color("#75513c"))
		_box(parts,Vector3(0,y,-0.144),Vector3(0.714,0.042,0.020),iron)
		for x:float in [-0.311,-0.103,0.103,0.311]:
			_band(shape,Vector3(x,y,-0.157),Vector3.BACK,0.014,0.013,BRASS)
			_band(shape,Vector3(x,y,-0.066),Vector3.BACK,0.012,0.011,iron)
	for y:float in [-0.123,0.123]:
		_box(parts,Vector3(0,y,-0.089),Vector3(0.082,0.055,0.024),iron)
		_shaft(shape,Vector3(0,y,-0.092),Vector3(0,y,0),0.021,0.017,iron)
	_shaft(shape,Vector3(0,-0.135,0),Vector3(0,0.135,0),0.022,0.022,LEATHER)
	for i in 8:
		_band(shape,Vector3(0,-0.101+i*0.029,0),Vector3(0.16,1,0),0.024,0.013,Color("#af835c"))

static func _field_bolt(shape:WastelandScenery,steel:Color)->void:
	_shaft(shape,Vector3(0,0.12,0.09),Vector3(0,0.12,-0.48),0.011,0.009,SAND,7)
	shape.lobe(Vector3(0,0.12,-0.485),Vector3(0.02,0.021,0.053),steel,0,false)
	for side:float in [-1,1]:
		shape.triangle(Vector3(0,0.12,0.09),Vector3(side*0.024,0.133,0.09),Vector3(0,0.12,0.018),Vector3.UP,LINEN)
