extends RefCounted

const H:=3.05
const TIMBER:=Color("#8c7051")
const STEEL:=Color("#6f6460")

static func bind(c:WastelandChunk,id:String,groups:Array)->void:
	c.support_graph[id]=groups

static func key(body:StaticBody3D)->String:
	return str(body.get_meta("site_id"))

static func footing(c:WastelandChunk,id:String,point:Vector3)->void:
	c.footings[id]=[Vector2(c.position.x+point.x,c.position.z+point.z)]

static func slab_id(floor:int,column:int,bay:int)->String:
	if column==1 and bay==2:return "slab/"+str(floor)
	return "slab/%d/%d/%d"%[floor,column,bay]

static func bay_at(span:float,z:float)->int:
	return clampi(floori((z+span*0.5)/(span*0.2)),0,4)

static func floor_id(span:float,floor:int,x:float,z:float)->String:
	var column:=0 if x< -span*0.5+2.4 else 2 if x>span*0.5-2.4 else 1
	return slab_id(floor,column,bay_at(span,z))

static func roof_id(span:float,x:float,z:float)->String:
	var column:=0 if x< -span*0.5+2.4 else 2 if x>span*0.5-2.4 else 1
	return "roof/plate/%d/%d"%[column,bay_at(span,z)]

static func attach_roof(c:WastelandChunk,body:StaticBody3D,span:float,x:float,z:float)->void:
	bind(c,key(body),[[roof_id(span,x,z)]])

static func fittings(c:WastelandChunk,parts:Array,center:Vector3,span:float,id:String)->void:
	var by_bearing:={}
	for i in parts.size():
		var p:Vector3=parts[i][0]-center
		var bearing:=""
		if id=="roof/fittings":
			bearing=c.ruin.tower_mast if c.site=="tower" and i>=10 else roof_id(span,p.x,p.z)
		else:
			match c.site:
				"hospital": bearing=roof_id(span,0,span*0.39)
				"fuel": bearing="canopy" if p.z>10.0 else "pump/-1" if p.x<0.0 else "pump/1"
				"tower": bearing=c.ruin.tower_mast
				"police","bunker":
					if i<(7 if c.site=="police" else 15):
						bearing=wall(0,0,0)
						if c.ruin.damaged(0,0,0,c.site): continue
					else:
						bearing=roof_id(span,p.x,p.z)
				"cabin","lodge":
					if c.site=="lodge" and c.cell!=WastelandSite.SHORE_CELL:
						if i>=4: bearing="logpile"
						else: bearing="roof/timber/1/%d"%bay_at(span,-3.2)
					else:
						if c.ruin.damaged(0,0,0,c.site): continue
						bearing=wall(0,0,0)
		if bearing.is_empty(): continue
		if not by_bearing.has(bearing): by_bearing[bearing]=[]
		by_bearing[bearing].append(parts[i])
	for bearing:String in by_bearing:
		var group_id:=id+"/"+bearing
		WastelandSite._cluster(c,group_id,by_bearing[bearing],140)
		if bearing=="logpile":
			footing(c,group_id,by_bearing[bearing][0][0])
		else:
			bind(c,group_id,[[bearing]])

static func wall(floor:int,side:int,bay:int)->String:
	return "wall/%d/%d/%d"%[floor,side,bay]

# Legacy saves identify a floor or a roof slope as one indivisible object.
# Require bearings spaced along the wall and allow either opposite wall pair.
static func wall_spans(level:int,side:int)->Array:
	var spans:Array=[]
	for a:int in [0,1,2]:
		for b in range(a+2,5):
			spans.append([wall(level,side,a),wall(level,side,b)])
	return spans

static func perimeter_spans(level:int)->Array:
	var spans:Array=[]
	for side in 2:
		for a:Array in wall_spans(level,side):
			for b:Array in wall_spans(level,side+2):
				spans.append(a+b)
	return spans

static func fit(c:WastelandChunk,id:String,at:Vector3,size:Vector3,orientation:Basis,tone:Color,groups:Array,hp:=180.0)->void:
	WastelandSite._feature(c,at,size,orientation,tone,id,hp)
	bind(c,id,groups)

static func foundation(c:WastelandChunk,base:Vector3,span:float,tone:Color)->void:
	var width:=span/5
	for bay in 5:
		for col in 3:
			var at:=base+Vector3((col-1)*(span*0.5-1.2),0.015,(bay-2)*width)
			var width_x:=span-4.8 if col==1 else 2.4
			var id:=slab_id(0,col,bay)
			WastelandSite._feature(c,at,Vector3(width_x,0.21,width),Basis.IDENTITY,tone,id,320)
			var samples:Array[Vector2]=[]
			for dx:int in [-1,1]:
				for dz:int in [-1,1]:
					samples.append(Vector2(c.position.x+at.x+dx*width_x*0.34,c.position.z+at.z+dz*width*0.35))
			c.footings[id]=samples

static func interior_frame(c:WastelandChunk,base:Vector3,level:int,span:float)->void:
	var half:=span*0.5
	var bay_width:=span/5.0
	for bay in 5:
		var z:=(bay-2)*bay_width
		for side:int in [-1,1]:
			var x:=side*(half-2.40)
			var id:="column/%d/%d/%d"%[level,side,bay]
			var bearing:=slab_id(0,1,bay) if level==0 else "column/%d/%d/%d"%[level-1,side,bay]
			fit(c,id,base+Vector3(x,H*0.5,z),Vector3(0.20,H,0.22),Basis.IDENTITY,STEEL,[[bearing]],325)
		var left:="column/%d/-1/%d"%[level,bay]
		var right:="column/%d/1/%d"%[level,bay]
		fit(c,"girder/%d/%d"%[level,bay],base+Vector3(0,H-0.105,z),Vector3(span-4.58,0.24,0.23),Basis.IDENTITY,STEEL,[[left,right]],300)

static func decks(c:WastelandChunk,base:Vector3,level:int,span:float,tone:Color,roof:=false)->void:
	var half:=span*0.5
	var width:=span/5
	var previous:=level-1
	for bay in 5:
		var z:=(bay-2)*width
		for col in 3:
			if col==0 and not c.ruin.west_floor(c,level,bay): continue
			# Additional torn roof sheets never leave a cap over a missing west support.
			if roof and col==0 and c.ruin.damaged(previous,3,bay,c.site): continue
			var id:="roof/plate/%d/%d"%[col,bay] if roof else slab_id(level,col,bay)
			var x:=(col-1)*(half-1.2)
			var size_x:=span-4.8 if col==1 else 2.4
			var groups:Array=[]
			if col==1:
				groups=[["girder/%d/%d"%[previous,bay]]]
			elif col==2:
				groups=[["column/%d/1/%d"%[previous,bay],wall(previous,1,4-bay)]]
			else:
				var outer:=wall(previous,3,bay)
				if c.ruin.damaged(previous,3,bay,c.site):
					outer="lintel/%d/%d"%[previous,bay]
					var bridge_length:=width+0.36
					fit(c,outer,base+Vector3(-half,-0.16,z),Vector3(0.22,0.30,bridge_length),Basis.IDENTITY,STEEL,[[wall(previous,3,bay-1),wall(previous,3,bay+1)]],270)
				groups=[["column/%d/-1/%d"%[previous,bay],outer]]
			fit(c,id,base+Vector3(x,0.015,z),Vector3(size_x,0.24 if roof else 0.21,width),Basis.IDENTITY,tone,groups,320)

static func timber_roof(c:WastelandChunk,center:Vector3,span:float,roof_color:Color)->void:
	var half:=span*0.5
	var run:=half+WastelandSite.ROOF_OVERHANG
	var pitch:=WastelandSite.ROOF_PITCH
	var ridge_y:=H+0.14/cos(pitch)+half*tan(pitch)-0.03
	var width:=span/5.0
	var wall_height:=ridge_y-half*tan(pitch)
	for index:int in [0,2,4]:
		var z:=(index-2)*width
		var id:="ridge/post/"+str(index)
		if index==4:
			# Carry the front ridge on a timber portal above the entrance aisle.
			var cross_y:=H-0.14
			for side:int in [-1,1]:
				WastelandSite._feature(c,center+Vector3(side*width*0.57,cross_y*0.5,z),Vector3(0.19,cross_y,0.19),Basis.IDENTITY,TIMBER,id,190)
			WastelandSite._feature(c,center+Vector3(0,cross_y,z),Vector3(width*1.14+0.19,0.26,0.23),Basis.IDENTITY,TIMBER,id,190)
			fit(c,id,center+Vector3(0,(cross_y+ridge_y)*0.5,z),Vector3(0.19,ridge_y-cross_y,0.19),Basis.IDENTITY,TIMBER,[[slab_id(0,1,index)]],190)
		else:
			fit(c,id,center+Vector3(0,ridge_y*0.5,z),Vector3(0.19,ridge_y,0.19),Basis.IDENTITY,TIMBER,[[slab_id(0,1,index)]],190)
	for pair in 2:
		var direction:=-1 if pair==0 else 1
		var depth:=half+0.62
		fit(c,"ridge/beam/"+str(pair),center+Vector3(0,ridge_y-0.12,direction*depth*0.5),Vector3(0.23,0.25,depth),Basis.IDENTITY,TIMBER,[["ridge/post/"+str(pair*2),"ridge/post/"+str(pair*2+2)]],220)
	for bay in 5:
		var z:=(bay-2)*width
		var offset:=(-0.31 if bay==0 else 0.31 if bay==4 else 0.0)
		var depth:=width+(0.62 if bay in [0,4] else 0.0)
		for side:int in [-1,1]:
			var wall_side:=3 if side<0 else 1
			var wall_bay:=bay if side<0 else 4-bay
			if c.ruin.damaged(0,wall_side,wall_bay,c.site): continue
			var bearing:=wall(0,wall_side,wall_bay)
			var eave:="eave/%d/%d"%[side,bay]
			fit(c,eave,center+Vector3(side*half,wall_height-0.14,z+offset),Vector3(0.21,0.24,depth),Basis.IDENTITY,TIMBER,[[bearing]],170)
			var tilt:=Basis(Vector3.BACK,-side*pitch)
			var mid:=center+Vector3(side*run*0.5,ridge_y-run*0.5*tan(pitch),z+offset)
			var rafters:Array=[]
			for end:int in [-1,1]:
				var rafter:="roof/rafter/%d/%d/%d"%[side,bay,end]
				var ridge:="ridge/beam/"+str(0 if z+offset+end*depth*0.40<0 else 1)
				fit(c,rafter,mid+Vector3(0,-0.14,end*depth*0.40),Vector3(run/cos(pitch),0.16,0.15),tilt,TIMBER,[[ridge,eave]],135)
				rafters.append(rafter)
			var plate:="roof/timber/%d/%d"%[side,bay]
			_roof_sheets(c,plate,mid,tilt,run/cos(pitch),depth,side,bay,roof_color)
			bind(c,plate,[rafters])
	# A snapped rafter rests on the ground beside the opening.
	var x:=center.x-half-1.0
	var z0:=center.z+c.ruin.end*(half-1.02)
	var start:=Vector3(x,0,z0)
	var finish:=start+Vector3(-1.15,0,c.ruin.end*1.37)
	start.y=c.stream.generator.ground(c.position.x+start.x,c.position.z+start.z)+0.095
	finish.y=c.stream.generator.ground(c.position.x+finish.x,c.position.z+finish.z)+0.095
	var axis:=finish-start
	WastelandSite._feature(c,(start+finish)*0.5,Vector3(0.19,0.18,axis.length()),Basis.looking_at(axis,Vector3.UP),TIMBER.darkened(0.18),"ruin/fallen-rafter",60)
	footing(c,"ruin/fallen-rafter",(start+finish)*0.5)

# Three sheets meet at the ridge. Cutting them back individually exposes the rafter tails.
static func _roof_sheets(c: WastelandChunk, id: String, mid: Vector3, pitch: Basis, length: float, depth: float,
		side: int, bay: int, tone: Color) -> void:
	var sheets: Array = []
	var seams: Array = []
	var lane := depth / 3.0
	var repair_bay := 1 if c.ruin.end < 0 else 3
	var damaged: bool = bay == repair_bay or (side == c.ruin.end and bay in [0,4])
	for strip in 3:
		var z := (strip - 1) * lane
		var loss := 0.045 * posmod(strip + bay + side,3)
		if damaged and strip == 2: loss = 0.66 + c.ruin.exposure * 0.28
		elif damaged and strip == 1: loss = 0.32
		var replacement := bay == repair_bay and strip == 0
		var shade := tone.lerp(Color("#93674e"),0.12 + posmod(bay + strip + side,4) * 0.07)
		if replacement: shade = Color("#82877a")
		var sheet_center := mid + pitch * Vector3(-side * loss * 0.5,0,z)
		# Adjacent lanes share an edge but never overlap coplanar top faces.
		sheets.append([sheet_center,Vector3(length - loss,0.15,lane),shade,pitch])
		seams.append([sheet_center + pitch * Vector3(0,0.084,-lane * 0.43),Vector3(length - loss - 0.04,0.051,0.039),shade.lightened(0.12),pitch])
		if damaged and strip == 1:
			var crease := sheet_center + pitch * Vector3(side * (length - loss) * 0.5,0,0)
			var folded := pitch * Basis(Vector3.BACK,-side * 0.47)
			sheets.append([crease + folded * Vector3(side * 0.19,0,0),Vector3(0.38,0.085,lane * 0.90),Color("#885f48"),folded])
		if replacement:
			# The bright square washer and shorter lap show where the existing iron was patched.
			var mended := sheet_center + pitch * Vector3(side * length * 0.20,0.09,0)
			seams.append([mended,Vector3(length * 0.26,0.036,lane * 0.85),Color("#77776a"),pitch])
			for fastener: int in [-1,1]:
				seams.append([mended + pitch * Vector3(side * length * 0.094,0.026,fastener * lane * 0.31),Vector3(0.057,0.021,0.067),Color("#554d43"),pitch])
	var solid_count := sheets.size()
	sheets.append_array(seams)
	WastelandSite._cluster(c,id,sheets,210,solid_count)
