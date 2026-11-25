extends RefCounted

const LAND := {"alpine":["shelter","weather"],"desert":["canal","well"]}
const Signs := preload("res://game/world/painted_sign.gd")
const LABELS := {"shelter":"雪线避风棚","weather":"山口测候站","canal":"干渠进水闸","well":"驼站提水泵","ferry":"渡船航运铭牌","pump":"泵站水尺","bridge":"断桥界碑"}
const INSCRIPTIONS := {
	"shelter":"SNOWLINE SHELTER\nOrange ring: sheltered slope\nBlue pair: windy shortcut",
	"weather":"PASS WEATHER STATION", "canal":"CANAL INTAKE", "well":"CARAVAN WELL",
	"ferry":"GRAY BAY FERRY", "pump":"INTAKE WATER GAUGE", "bridge":"BRIDGE SURVEY MARK"
}
const WOOD := Color("#866046")
const STEEL := Color("#56716c")
const AMBER := Color("#d69152")
const STONE := Color("#927e69")

static func survey(gen:WastelandTerrainGen)->Dictionary:
	if not gen.expedition_layout.is_empty(): return gen.expedition_layout
	var result:={"points":{},"trails":{}}
	if gen.revision>=3:
		var origin:=Vector2(gen.starting_outpost("seeded")*32)+Vector2(16,16)
		var district:=Vector2i((origin/gen.Frontier.SPAN).floor())
		for kind:String in LAND:
			var target:=gen.Frontier.NAMES.find(kind)
			var best:=INF
			var hub:=Vector2.ZERO
			for z in range(-3,4):
				for x in range(-6,7):
					var site:=gen.frontier._district(district+Vector2i(x,z))
					var pos:=Vector2(site.x,site.z)
					if int(site.y)!=target or pos.length()<400 or origin.distance_squared_to(pos)>=best: continue
					hub=pos.round()
					best=origin.distance_squared_to(pos)
			var trail:=_walkable_trail(gen,hub,kind)
			if kind=="alpine":
				result.trails["alpine_short"]=trail
				trail=_sheltered_route(gen,trail)
			result.trails[kind]=trail
			result.points[LAND[kind][0]]=trail[0]
			result.points[LAND[kind][1]]=trail[-1]
	for id:String in WastelandSunkenSites.landmarks(gen):
		var base:Vector3=WastelandSunkenSites.landmarks(gen)[id]
		var offset:Vector2={"ferry":Vector2(-5.6,1.4),"pump":Vector2(1.0,3.1),"bridge":Vector2(0,4.6)}[id]
		var at:=Vector2(base.x,base.z)+offset
		result.points[id]=Vector3(at.x,gen.ground(at.x,at.y),at.y)
	gen.expedition_layout=result
	return result

static func _walkable_trail(gen:WastelandTerrainGen,hub:Vector2,kind:String)->Array[Vector3]:
	var best:Array[Vector3]=[]
	var lowest:=INF
	for i in 24:
		var axis:=Vector2.from_angle(i*TAU/24)
		var path:Array[Vector3]=[]
		var cost:=0.0
		var steepest:=0.0
		for j in 25:
			var p:Vector2=(hub+axis*(j-12)*3.0).round()
			var h:=gen.ground(p.x,p.y)
			if j>0:
				var grade:=absf(h-path[-1].y)/3.0
				steepest=maxf(steepest,grade)
				cost+=grade
			if j%4==0:
				if gen.region_kind(p.x,p.y)!=kind or h<1.0 or not gen.site_for(WastelandTerrainGen.chunk_at(p)).is_empty(): cost+=100
			path.append(Vector3(p.x,h,p.y))
		cost+=steepest*100
		if cost<lowest:
			lowest=cost
			best=path
	if best[0].y>best[-1].y: best.reverse()
	return best

static func _sheltered_route(gen:WastelandTerrainGen,direct:Array[Vector3])->Array[Vector3]:
	var start:=Vector2(direct[0].x,direct[0].z)
	var finish:=Vector2(direct[-1].x,direct[-1].z)
	var side:=(finish-start).orthogonal().normalized()
	var best:Array[Vector3]=[]
	var lowest:=INF
	for width:float in [24.0,-24.0,29.0,-29.0,32.0,-32.0]:
		var route:Array[Vector3]=[]
		var grade:=0.0
		var cost:=0.0
		for i in 33:
			var t:=i/32.0
			var at:=start.lerp(finish,t)+side*sin(PI*t)*width
			var point:=Vector3(at.x,gen.ground(at.x,at.y),at.y)
			if i>0:
				var prior:=route[-1]
				var slope:=absf(point.y-prior.y)/Vector2(point.x-prior.x,point.z-prior.z).length()
				grade=maxf(grade,slope)
				cost+=slope
			route.append(point)
		cost+=grade*150
		if cost<lowest:
			lowest=cost
			best=route
	return best

static func pass_wind(gen:WastelandTerrainGen,at:Vector3)->float:
	if gen.expedition_layout.is_empty(): return 0.0
	var trails:Dictionary=gen.expedition_layout.trails
	if not trails.has("alpine_short"): return 0.0
	var path:Array=trails.alpine_short
	var a:=Vector2(path[0].x,path[0].z)
	var b:=Vector2(path[-1].x,path[-1].z)
	var p:=Vector2(at.x,at.z)
	if not Rect2(a,Vector2.ZERO).expand(b).grow(6).has_point(p): return 0.0
	var dist:=Geometry2D.get_closest_point_to_segment(p,a,b).distance_to(p)
	return 18.0*(1.0-smoothstep(3,6,dist))*smoothstep(6,13,minf(p.distance_to(a),p.distance_to(b)))

static func _member(c:WastelandChunk,id:String,key:String,at:Vector3,size:Vector3,color:Color,tilt:=Vector3.ZERO)->StaticBody3D:
	var body:=WastelandLook.solid(c.poi_root,size,at-c.position,color)
	body.rotation=tilt
	preload("res://game/world/expedition_fittings.gd").fit(body,id,key,size,color,posmod(c.stream.generator.seed_at(c.cell,731),4))
	c.track_structure(body,"expedition/"+id+"/"+key,115)
	body.set_meta("expedition_id",id)
	return body

# Ground contacts use the original terrain so unloading after a dig cannot
# regrow a support. Long channel walls bear at both ends.
static func _grounded(c:WastelandChunk,id:String,key:String,at:Vector3,size:Vector3,color:Color,tilt:=Vector3.ZERO)->StaticBody3D:
	var body:=_member(c,id,key,at,size,color,tilt)
	if c.stream.generator.site_revision<=0: return body
	var contacts: Array[Vector3]=[Vector3(0,-size.y*0.5,0)]
	if size.z>2.0:
		contacts=[Vector3(0,-size.y*0.5,-size.z*0.38),Vector3(0,-size.y*0.5,size.z*0.38)]
	var samples: Array[Vector2]=[]
	for local:Vector3 in contacts:
		var point:=body.to_global(local)
		samples.append(Vector2(point.x,point.z))
		var depth:float=point.y-c.stream.generator.ground(point.x,point.z)+0.12
		if depth<=0.15: continue
		var center:=body.to_local(point-Vector3.UP*depth*0.5)
		var foot_size:=Vector3(size.x*0.90,depth,minf(size.z,0.45))
		var mesh:=WastelandLook.box(body,foot_size,center,color)
		mesh.basis=body.global_basis.inverse()*Basis.from_scale(mesh.scale)
		var shape:=WastelandLook.collider(body,foot_size,center)
		shape.basis=body.global_basis.inverse()
	c.footings["expedition/"+id+"/"+key]=samples
	return body

static func _joint(c:WastelandChunk,id:String,bearings:Array)->void:
	if c.stream.generator.site_revision>0: c.support_graph[id]=[bearings]

static func _repair_detail(c:WastelandChunk,id:String,body:Node3D)->Node3D:
	var detail:=preload("res://game/world/expedition_repair.gd").new()
	detail.session=c.stream.get_parent()
	detail.id=id
	detail.visible=false
	body.add_child(detail)
	return detail

static func populate(c:WastelandChunk)->void:
	if c.stream.is_preview: return
	var plan:=survey(c.stream.generator)
	for id:String in plan.points:
		var at:Vector3=plan.points[id]
		if WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))!=c.cell: continue
		var yaw := 0.0
		if id=="shelter":
			var forward:Vector3=plan.points.weather-at
			yaw=atan2(forward.x,forward.z)
		# Keep a reading position clear at the plaque, including thick kelp bounds.
		var facing:=Transform3D(Basis(Vector3.UP,yaw),at-c.position)
		var clearing:=facing*AABB(Vector3(-1.7,-0.3,-1.0),Vector3(3.4,3.8,4.0))
		for key:String in c.small_nature.keys():
			if clearing.intersects(c.small_nature[key].bounds):
				c.erase_small_nature(key)
		var base_key:="expedition/"+id+"/"
		_joint(c,base_key+"plate",[base_key+"post"])
		var title:=_member(c,id,"plate",at+Vector3(0,0.83,0),Vector3(1.05,0.67,0.17),STEEL,Vector3(0,yaw,0))
		_grounded(c,id,"post",at+Vector3(0,0.32,0),Vector3(0.18,0.70,0.16),WOOD,Vector3(0,yaw,0))
		Signs.enamel(title.get_child(0),STEEL,1+posmod(c.stream.generator.seed_at(c.cell,383),3),id.hash())
		Signs.letter(title,INSCRIPTIONS[id],Vector3(0,0.02,0.105),Vector2(0.93,0.49))
		if id in ["shelter","weather","canal","well"]:
			var repaired:=_repair_detail(c,id,title)
			WastelandLook.box(repaired,Vector3(0.86,0.08,0.06),Vector3(0,-0.23,0.09),Color("#85d19e"),0.4)
			if c.stream.generator.site_revision==0 and id=="shelter":
				WastelandLook.box(repaired,Vector3(1.21,0.18,0.66),Vector3(0,-0.49,-1.95),Color("#d4ab73"))
			elif c.stream.generator.site_revision==0 and id in ["canal","well"]:
				WastelandLook.box(repaired,Vector3(1.36,0.06,2.6 if id=="canal" else 1.25),Vector3(0,-0.46,-1.72),Color("#578e91"))
		match id:
			"shelter":
				var weathered:bool=c.stream.generator.site_revision>0
				var torn_side:=1 if posmod(c.stream.generator.seed_at(c.cell,349),2)==0 else -1
				for side:int in [-1,1]:
					var torn:=weathered and side==torn_side
					var sill:="sill"+str(side)
					var post_pair:=[base_key+"post%d-1"%side,base_key+"post%d1"%side]
					if weathered:
						_member(c,id,sill,at+Vector3(side*2,1.38,-2).rotated(Vector3.UP,yaw),Vector3(0.21,0.20,3.65),WOOD,Vector3(0,yaw,0))
					_joint(c,base_key+sill,post_pair)
					_joint(c,base_key+"roof"+str(side),[base_key+sill,base_key+"ridge"])
					if torn: _joint(c,base_key+"rafters",[base_key+sill,base_key+"ridge"])
					_member(c,id,"roof"+str(side),at+Vector3(side*1.05,1.82,-2.74 if torn else -2.0).rotated(Vector3.UP,yaw),Vector3(2.53,0.13,2.32 if torn else 3.8),Color("#9a6449"),Vector3(0,yaw,-side*0.45))
					if torn:
						_member(c,id,"rafters",at+Vector3(side*1.05,1.72,-0.69).rotated(Vector3.UP,yaw),Vector3(2.34,0.14,0.14),WOOD,Vector3(0,yaw,-side*0.45))
					for end:int in [-1,1]:
						_ground_post(c,id,"post%d%d"%[side,end],at+Vector3(side*2,1.43,-2+end*1.6).rotated(Vector3.UP,yaw),0.17,WOOD)
				if weathered:
					for end:int in [-1,1]:
						_ground_post(c,id,"ridgepost"+str(end),at+Vector3(0,2.37,-2+end*1.60).rotated(Vector3.UP,yaw),0.20,WOOD)
					_member(c,id,"ridge",at+Vector3(0,2.30,-2).rotated(Vector3.UP,yaw),Vector3(0.23,0.20,3.78),WOOD,Vector3(0,yaw,0))
				_joint(c,base_key+"ridge",[base_key+"ridgepost-1",base_key+"ridgepost1"])
				_joint(c,base_key+"windbreak",[base_key+"post-1-1",base_key+"post1-1"])
				var screen:=_member(c,id,"windbreak",at+Vector3(0,0.66,-3.65).rotated(Vector3.UP,yaw),Vector3(3.9,1.5,0.17),WOOD,Vector3(0,yaw,0))
				if weathered:
					WastelandLook.box(_repair_detail(c,id,screen),Vector3(1.65,0.19,0.09),Vector3(0,-0.32,0.10),Color("#d4ab73"))
			"weather":
				_grounded(c,id,"mast",at+Vector3(0,2.7,-1),Vector3(0.21,5.7,0.21),STEEL)
				for n in 3:
					_joint(c,base_key+"rotor"+str(n),[base_key+"mast"])
					var angle:=n*TAU/3
					var dir:=Vector3(cos(angle),0,sin(angle))
					if c.stream.generator.site_revision>0 and n==posmod(c.stream.generator.seed_at(c.cell,93),3):
						_member(c,id,"rotor"+str(n),at+Vector3(0,5.20,-1)+dir*0.28,Vector3(0.60,0.12,0.15),AMBER,Vector3(0,-angle,0.18))
						continue
					_member(c,id,"rotor"+str(n),at+Vector3(0,5.24,-1)+dir*0.76,Vector3(1.6,0.13,0.17),AMBER,Vector3(0,-angle,0))
					_joint(c,base_key+"cup"+str(n),[base_key+"rotor"+str(n)])
					_member(c,id,"cup"+str(n),at+Vector3(0,5.36,-1)+dir*1.5,Vector3(0.37,0.32,0.38),STEEL)
			"canal":
				for side:int in [-1,1]:
					var split:bool=c.stream.generator.site_revision>0 and side==(1 if posmod(c.stream.generator.seed_at(c.cell,774),2)==0 else -1)
					_grounded(c,id,"bank"+str(side),at+Vector3(side*1.15,0.19,-2.36 if split else -1.5),Vector3(0.46,0.62,3.28 if split else 5.0),STONE)
					if split:
						_grounded(c,id,"bankfall",at+Vector3(side*1.35,-0.04,0.42),Vector3(0.45,0.45,0.77),STONE,Vector3(0.22,0.14,-side*0.51))
				_joint(c,base_key+"gate",[base_key+"bank-1",base_key+"bank1"])
				var gate:=_member(c,id,"gate",at+Vector3(0,0.72,-2.5),Vector3(2.12,1.46,0.19),WOOD)
				if c.stream.generator.site_revision>0:
					WastelandLook.box(_repair_detail(c,id,gate),Vector3(1.36,0.06,2.6),Vector3(0,-0.64,0.78),Color("#578e91"))
			"well":
				for n in 8:
					var angle:=n*TAU/8
					var cracked:bool=c.stream.generator.site_revision>0 and n==posmod(c.stream.generator.seed_at(c.cell,718),8)
					_grounded(c,id,"rim"+str(n),at+Vector3(sin(angle),0.10 if cracked else 0.38,-2+cos(angle)),Vector3(0.72 if cracked else 0.85,0.32 if cracked else 0.8,0.38),STONE,Vector3(0,angle,0.17 if cracked else 0.0))
				var pipe:=_grounded(c,id,"pipe",at+Vector3(0,0.95,-2),Vector3(0.24,2.0,0.24),STEEL)
				if c.stream.generator.site_revision>0:
					WastelandLook.box(_repair_detail(c,id,pipe),Vector3(1.24,0.06,1.25),Vector3(0,-0.73,0),Color("#578e91"))
				_joint(c,base_key+"lever",[base_key+"pipe"])
				_member(c,id,"lever",at+Vector3(0.59,1.78,-2),Vector3(1.4,0.14,0.19),AMBER,Vector3(0,0,-0.28))
	for kind:String in plan.trails:
		var trail:Array=plan.trails[kind]
		_clear_footpath(c,trail)
		for n in range(4,trail.size()-1,4):
			var at:Vector3=trail[n]
			if WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))!=c.cell: continue
			var direction:Vector3=trail[n+1]-at
			var right:=Vector3(direction.z,0,-direction.x).normalized()
			var pos:=at+right*1.6
			if c.stream.generator.site_revision>0: pos.y=c.stream.generator.ground(pos.x,pos.z)
			var stone:=WastelandLook.solid(c.poi_root,Vector3(0.38,1.3,0.40),pos-c.position+Vector3.UP*0.55,STONE if kind=="desert" else WOOD)
			c.track_structure(stone,"expedition/trail/"+kind+str(n),55)
			if c.stream.generator.site_revision>0: c.footings["expedition/trail/"+kind+str(n)]=[Vector2(pos.x,pos.z)]
			WastelandLook.box(stone,Vector3(0.41,0.16,0.43),Vector3.UP*0.4,Color("#79d6eb") if kind=="alpine_short" else AMBER)
			if kind=="alpine_short": WastelandLook.box(stone,Vector3(0.41,0.10,0.43),Vector3.UP*0.17,Color("#79d6eb"))
			if kind=="desert":
				for side:int in [-1,1]:
					var center:=at+right*(side*0.9)
					var angle:=atan2(direction.x,direction.z)
					var key:="%d/%d"%[n,side]
					var size:=Vector3(0.32,0.27,4.5)
					var basis:=Basis(Vector3.UP,angle)
					if c.stream.generator.site_revision>0:
						var axis:=basis.z*2.25
						var start:=center-axis
						var end:=center+axis
						start.y=c.stream.generator.ground(start.x,start.z)+0.06
						end.y=c.stream.generator.ground(end.x,end.z)+0.06
						center=start.lerp(end,0.5)
						basis=Basis.looking_at(start-end)
						size.z=start.distance_to(end)
						c.footings["expedition/channel/"+key]=[Vector2(start.x,start.z),Vector2(end.x,end.z)]
					var rail:=WastelandLook.solid(c.poi_root,size,center-c.position,STONE)
					rail.basis=basis
					c.track_structure(rail,"expedition/channel/"+key,70)

static func _ground_post(c:WastelandChunk,id:String,key:String,tip:Vector3,width:float,color:Color)->void:
	var foot:=minf(tip.y-0.35,c.stream.generator.ground(tip.x,tip.z)-0.18)
	_grounded(c,id,key,Vector3(tip.x,(tip.y+foot)*0.5,tip.z),Vector3(width,tip.y-foot,width),color)

static func _clear_footpath(c:WastelandChunk,trail:Array)->void:
	var local:=Rect2(Vector2(c.cell*32),Vector2(32,32)).grow(7)
	var bounds:=Rect2(Vector2(trail[0].x,trail[0].z),Vector2.ZERO)
	for point:Vector3 in trail: bounds=bounds.expand(Vector2(point.x,point.z))
	if not local.intersects(bounds.grow(5)): return
	for body:Node in c.decoration_root.get_children():
		if not body is StaticBody3D or body.get_meta("kind","")!="resource" or body.is_queued_for_deletion(): continue
		var p:=Vector2(body.global_position.x,body.global_position.z)
		for i in range(1,trail.size()):
			var a:=Vector2(trail[i-1].x,trail[i-1].z)
			var b:=Vector2(trail[i].x,trail[i].z)
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,a,b))<21:
				c.remove_resource(body)
				break
