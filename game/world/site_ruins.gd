extends RefCounted

# Keep the eastern stairwell and the centre of every floor clear in every condition.
var condition := 0
var end := 1
var entrance_bay := 3
var span := 0.0
var heights := 1
var wood := false
var tower_mast:=""
var roof_bearings:Array=[]
var base_y:=0.0
var exposure:=0.5
var scatter:=0.5

func plan(chunk:WastelandChunk, width:float, storeys:int, timber:bool)->void:
	span=width
	heights=storeys
	wood=timber
	if chunk.stream.generator.site_revision==0: return
	var rng:=RandomNumberGenerator.new()
	rng.seed=chunk.stream.generator.seed_at(chunk.cell,5937)
	var roll:=rng.randf()
	condition=1 if roll<0.35 else 2 if roll<0.76 else 3
	end=1 if rng.randi()%2==0 else -1
	exposure=rng.randf()
	scatter=rng.randf()
	entrance_bay=2+end
	# The buried bunker has a cutaway ground profile. Its upper storey can crumble;
	# retain the buried retaining walls to avoid exposing solid terrain.
	if chunk.site=="bunker": end=-1; entrance_bay=1

func damaged(floor:int,side:int,part:int,site:String)->bool:
	if condition==0 or (site=="bunker" and floor==0): return false
	if side==3:
		if part==entrance_bay: return true
		if condition>=2 and part==2+end*2: return true
		if condition>=2 and part==2 and (heights==1 or floor>0): return true
		if condition==3 and floor==heights-1: return true
	return condition>=2 and side==(0 if end>0 else 2) and part==(0 if end>0 else 4)

func broken_wall(chunk:WastelandChunk,point:Vector3,basis:Basis,floor:int,side:int,part:int,id:String,hp:int,tint:Color)->void:
	var width:=span/5.0
	# Leave a full standing-height path through the opening. Short masonry courses
	# and splintered weatherboards terminate on the surviving side of the breach.
	if side==3 and part==entrance_bay and condition>=2: return
	var edge:=float(-end) if side==3 else (1.0 if end>0 else -1.0)
	if side==3 and part==2: edge=-float(end)
	if side==3 and part==2+2*end: edge=float(end)
	var rows:=5 if wood else 4
	rows+=posmod(floor+part+int(scatter*7),3)-1
	var courses: Array = []
	var broken_faces: Array = []
	for i in rows:
		var reach:=width*(0.34+exposure*0.10-0.052*i)
		var rise:=0.24 if wood else 0.32
		var local:=Vector3(edge*(width-reach)*0.5,rise*(i+0.5),0)
		var tilt:=Basis(Vector3.BACK,edge*(0.055+0.014*i)) if wood else Basis.IDENTITY
		var rotation := basis * tilt
		var at := point + basis * local
		courses.append([at,Vector3(reach,rise-0.014,0.3),tint.darkened(i*0.038),rotation])
		# Flaked render reveals aggregate; timber shears into pale uneven fibres.
		var tip := at + rotation * Vector3(-edge * (reach * 0.5 - 0.03),0,0)
		if wood:
			broken_faces.append([tip + rotation * Vector3(-edge * 0.06,rise * 0.25,0.045),
				Vector3(0.18 + (i % 2) * 0.08,0.056,0.14),Color("#b89770"),rotation * Basis(Vector3.BACK,edge * 0.11),0.42])
		else:
			var masonry := Color("#986f59") if chunk.site in ["hospital","post"] else Color("#817e72")
			broken_faces.append([tip + rotation * Vector3(edge * reach * 0.12,0,0.147),
				Vector3(reach * 0.34,rise * 0.72,0.035),masonry.darkened(i % 2 * 0.11),rotation,0.76])
	if not wood and floor<heights-1 and side==3 and part==2+2*end:
		# Exposed reinforcement stops below the lost slab.
		var column:=Vector3(edge*width*0.42,1.39,0)
		courses.append([point+basis*column,Vector3(0.21,2.78,0.23),tint.darkened(0.20),basis])
		for lateral:float in [-0.075,0.075]:
			courses.append([point+basis*(column+Vector3(lateral,1.52,0)),Vector3(0.035,0.32,0.035),Color("#876447"),basis*Basis(Vector3.BACK,lateral*2.1)])
	var solid_count := courses.size()
	courses.append_array(broken_faces)
	WastelandSite._cluster(chunk,id,courses,hp,solid_count)

func debris(chunk:WastelandChunk,center:Vector3,tone:Color)->void:
	if condition==0 or chunk.site=="bunker": return
	var corner:=center+Vector3(-span*0.5-1.0,0,end*(span*0.5-0.48))
	for i in (5 if condition==1 else 9):
		var t:=float(i)
		var offset:=Vector3(-0.19*t,0.10+0.04*(i%2),end*(sin(t*2.0+scatter*TAU)*0.75+0.14*t))
		var size:=Vector3(0.19,0.18,1.38-0.06*t) if wood else Vector3(0.46+0.12*(i%3),0.19+0.07*(i%2),0.39)
		var p:=corner+offset
		p.y=chunk.stream.generator.ground(chunk.position.x+p.x,chunk.position.z+p.z)+size.y*0.41
		var id:="ruin/debris/"+str(i)
		WastelandSite._feature(chunk,p,size,Basis.from_euler(Vector3(0.07*sin(t),0.71*t,0.07*cos(t))),tone.darkened(0.22+0.04*(i%3)),id,45)
		preload("res://game/world/site_support.gd").footing(chunk,id,p)

const FURNISHINGS := {
	"hospital":["cot","desk","shelves","cot"],
	"police":["desk","lockers","shelves"],
	"tower":["desk","shelves","cot"],
	"bunker":["lockers","cot","shelves"],
	"fuel":["bench","shelves","lockers"],
	"lodge":["desk","bench","cot","shelves"],
	"cabin":["cot","bench","shelves"]
}
var furniture_bounds:Array[AABB]=[]

func furniture_clear(point:Vector3,radius:=0.85)->bool:
	for bounds in furniture_bounds:
		if bounds.grow(radius).has_point(point): return false
	return true

func furnish(chunk:WastelandChunk,base:Vector3,storey:int)->void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=chunk.stream.generator.seed_at(chunk.cell,9071+storey)
	if chunk.site in ["granary","garage","post"]:
		preload("res://game/world/trade_ruins.gd").furnish(chunk,base,storey,rng)
		return
	var choices:Array=FURNISHINGS[chunk.site].duplicate()
	var side:=-1 if rng.randi()%2==0 else 1
	var count:=2 if rng.randf()<0.68 else 1
	if side<0 and not west_floor(chunk,storey,4): side=1
	for bay in count:
		if side<0 and not west_floor(chunk,storey,4): break
		var index:=rng.randi_range(0,choices.size()-1)
		var kind:String=choices[index]
		choices.erase(kind)
		var at:=base+Vector3(side*(span*0.5-1.94),0.13,span*0.5-0.91)
		var bounds:=AABB(at-Vector3(1.06,0.12,0.73),Vector3(2.12,2.05,1.46))
		furniture_bounds.append(bounds)
		var parts:Array=[]
		var metal:=Color("#49595b").lightened(rng.randf_range(0.0,0.13))
		var timber:=Color("#805f47").lightened(rng.randf_range(0.0,0.16))
		var fabric:=Color("#878b75").lerp(Color("#aaa095"),rng.randf())
		match kind:
			"desk","bench","cot":
				var top:=0.47 if kind=="cot" else 0.79
				var depth:=0.74 if kind=="cot" else 0.55
				for x:float in [-0.77,0.77]:
					for z:float in [-0.20,0.20]:
						parts.append([at+Vector3(x,top*0.5,z),Vector3(0.07,top,0.08),metal if kind=="cot" else timber.darkened(0.32)])
				parts.append([at+Vector3.UP*top,Vector3(1.79,0.09,depth),timber])
				if kind=="cot":
					parts.append([at+Vector3.UP*(top+0.10),Vector3(1.69,0.13,0.69),fabric])
					parts.append([at+Vector3(side*0.61,top+0.20,0),Vector3(0.37,0.11,0.55),fabric.lightened(0.21)])
					parts.append([at+Vector3(-side*0.44,top+0.18,0),Vector3(0.70,0.05,0.73),Color("#5e7068")])
				elif kind=="desk":
					parts.append([at+Vector3(side*0.49,top-0.16,0),Vector3(0.55,0.23,0.47),timber.darkened(0.18)])
					parts.append([at+Vector3(side*0.49,top-0.15,-0.25),Vector3(0.13,0.034,0.04),metal.lightened(0.27)])
					parts.append([at+Vector3(-side*0.32,top+0.07,0),Vector3(0.36,0.044,0.245),Color("#b8ac91"),Basis(Vector3.UP,rng.randf_range(-0.28,0.28))])
				else:
					for x:float in [-0.72,0.72]:
						parts.append([at+Vector3(x,0.32,0),Vector3(0.08,0.09,0.50),metal])
					parts.append([at+Vector3(0,0.27,0),Vector3(1.62,0.11,0.13),timber.darkened(0.21)])
					parts.append([at+Vector3(side*0.50,0.91,0.1),Vector3(0.31,0.17,0.17),metal])
			"shelves":
				for x:float in [-0.70,0.70]:
					for z:float in [-0.21,0.21]:
						parts.append([at+Vector3(x,0.88,z),Vector3(0.06,1.76,0.06),metal])
				for shelf in 4:
					parts.append([at+Vector3.UP*(0.16+shelf*0.48),Vector3(1.48,0.07,0.51),timber])
					if shelf<3 and rng.randf()<0.82:
						parts.append([at+Vector3(rng.randf_range(-0.40,0.40),0.33+shelf*0.48,0.02),Vector3(0.43,0.27,0.34),fabric.darkened(0.17*shelf)])
			"lockers":
				for x:float in [-0.31,0.31]:
					var p:=at+Vector3.RIGHT*x
					parts.append([p+Vector3.UP*0.78,Vector3(0.57,1.56,0.48),metal])
					parts.append([p+Vector3(0,0.8,-0.25),Vector3(0.51,1.40,0.035),metal.lightened(0.10)])
					for vent in 3:
						parts.append([p+Vector3(0,1.22+vent*0.055,-0.273),Vector3(0.26,0.018,0.015),metal.darkened(0.30)])
					parts.append([p+Vector3(0.18,0.73,-0.28),Vector3(0.03,0.15,0.037),fabric])
		var id:="furniture/%d/%s/%d"%[storey,kind,bay]
		var materials:=furniture_materials(kind,parts,metal,timber)
		var detail_seed:int=chunk.stream.generator.seed_at(chunk.cell,13621+5*storey+bay)
		var details:=preload("res://game/world/site_room_details.gd")
		details.add_fittings(parts,materials,chunk.site,kind,at,side,detail_seed)
		var solid_count:=parts.size()
		details.add_wear(parts,chunk.site,kind,at,side,detail_seed)
		var furnishing:=WastelandSite._cluster(chunk,id,parts,95,solid_count)
		furnishing.set_meta("salvage_components",materials)
		var support:=preload("res://game/world/site_support.gd")
		var z:=at.z-base.z
		var x:=at.x-base.x
		support.bind(chunk,id,[[support.floor_id(span,storey,x-0.7,z),support.floor_id(span,storey,x+0.7,z)]])
		side=-side

func furniture_materials(kind:String,parts:Array,metal:Color,timber:Color)->Dictionary:
	var result:={}
	for i in parts.size():
		var item:="wood"
		var fraction:=1.0
		match kind:
			"cot":
				if i<4: item="scrap"
				elif i>4: item="cloth"
			"desk":
				if i==6: item="scrap"
				if i==7: continue # Loose paper.
			"bench":
				if i in [5,6,8]: item="scrap"
			"shelves":
				if parts[i][2]==metal: item="scrap"
				elif parts[i][2]!=timber: continue # Boxes on the shelves.
			"lockers":
				item="scrap"
				fraction=0.055 # Thin folded panels around the empty cabinet.
		var size:Vector3=parts[i][1]
		result[item]=float(result.get(item,0.0))+size.x*size.y*size.z*fraction
	return result

# The centre and east aisles form the continuous route to the exterior stairs.
func has_floor(chunk:WastelandChunk,center:Vector3,point:Vector3)->bool:
	var floor:=floori((point.y-center.y+0.55)/WastelandSite.STOREY_HEIGHT)
	if floor<=0 or condition==0: return true
	var local:=point-center
	if local.x>=-span*0.5+2.40: return true
	var bay:=clampi(floori((local.z+span*0.5)/(span*0.2)),0,4)
	return west_floor(chunk,floor,bay)

func west_floor(chunk:WastelandChunk,floor:int,bay:int)->bool:
	if floor<=0: return true
	for level in floor:
		if not damaged(level,3,bay,chunk.site): continue
		# A single lost bay can be bridged by a lintel resting on two standing adjacent bays.
		if bay==0 or bay==4 or damaged(level,3,bay-1,chunk.site) or damaged(level,3,bay+1,chunk.site):
			return false
	return true
