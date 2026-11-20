extends Node3D

const BIOME_KEYS := ["shore","forest","ridge","ash","town"]
const NAMES := {"alpine":"雪山救援箱","desert":"沙漠蓄水箱","shore":"湖岸浮箱","forest":"林场板条箱","ridge":"山脊远征匣","ash":"焦土密封桶","town":"旧镇调度柜",
	"ferry":"渡船救生匣","pump":"潜水备件筒","bridge":"桥检工具柜"}
# Shell, load-bearing frame and identification paint.
const FINISH := {
	"alpine":["b74c36","52626a","f1e4c6"], "desert":["648f91","615746","e4c07d"],
	"shore":["789a95","5e4d3c","eed9a4"], "forest":["956a43","443c34","60816a"],
	"ridge":["a5513f","46555c","d7c9a1"], "ash":["b78743","454745","383b38"],
	"town":["536c74","343b41","d7ad68"], "ferry":["cb8651","5e655d","e2d6ae"],
	"pump":["538079","424f52","cca46b"], "bridge":["6a7782","424848","c8894b"]
}
const DIMENSIONS := {"alpine":Vector3(1.37,0.60,0.80),"desert":Vector3(0.94,1.26,0.94),"shore":Vector3(1.18,0.68,0.72),"forest":Vector3(1.06,0.78,0.74),
	"ridge":Vector3(1.15,0.59,0.74),"ash":Vector3(0.80,0.90,0.80),"town":Vector3(0.84,0.93,0.65),
	"ferry":Vector3(1.15,0.64,0.74),"pump":Vector3(0.80,0.88,0.80),"bridge":Vector3(0.90,0.77,0.74)}
static var mesh_cache: Dictionary = {}
static var finishes: Dictionary = {}
var lid := MeshInstance3D.new()
var stores := MeshInstance3D.new()
var profile := ""
var last_state := -1
var opened:=false
var motion: Tween

static func state(record: Dictionary, day: int, refill_days: int, underwater: bool) -> int:
	if record.is_empty(): return 0
	if not record.get("items",{}).is_empty(): return 1
	var next := int(record.get("next",-1))
	return 0 if not underwater and refill_days > 0 and next >= 0 and day >= next else 2

static func kind_at(gen: WastelandTerrainGen, p: Vector3) -> String:
	var region:=gen.region_kind(p.x,p.z)
	if region in ["alpine","desert"]: return region
	return BIOME_KEYS[gen.biome(p.x,p.z)]

func configure(id: String, table: String, variant:=0) -> void:
	name = "SupplyChest"
	profile = id
	var key := id+"/"+table
	if not mesh_cache.has(key):
		mesh_cache[key] = _build(id,table)
	var pieces: Array = mesh_cache[key]
	scale = DIMENSIONS[id]
	var hull := MeshInstance3D.new()
	add_child(hull)
	hull.mesh = pieces[0]
	lid.name = "HingedLid"
	add_child(lid)
	lid.mesh = pieces[1]
	lid.position = pieces[3]
	add_child(stores)
	stores.mesh = pieces[2]
	if not finishes.has(id):
		var surface := ShaderMaterial.new()
		surface.shader = preload("res://shaders/supply_finish.gdshader")
		surface.set_shader_parameter("timber",id=="forest")
		surface.set_shader_parameter("submerged",id in ["ferry","bridge","pump"])
		finishes[id] = surface
	for part: MeshInstance3D in [hull,lid,stores]: part.material_override = finishes[id]
	stores.visible = false
	if variant>0:
		# Inspection stripes are attached to the door/lid and move with its hinge.
		var door:=profile in ["town","bridge"]
		var paint:=Color(["#deb66c","#bb7755","#bfcab4","#71969a"][(variant-1)/2])
		var count:=1+variant%2
		for i in count:
			var at:=Vector3(0.22+i*0.09,0.12,0.055) if door else Vector3(-0.20+i*0.10,0.174,0.40)
			var size:=Vector3(0.044,0.18,0.018) if door else Vector3(0.053,0.017,0.19)
			WastelandLook.box(lid,size,at,paint)

func show_state(value:int,animate:=true)->void:
	if last_state==value: return
	last_state=value
	_pose_lid(animate)

func set_opened(value:bool,animate:=true)->void:
	if opened==value: return
	opened=value
	_pose_lid(animate)

func _pose_lid(animate:bool)->void:
	stores.visible=(opened or last_state>0) and last_state==1
	if motion: motion.kill()
	var axis:="rotation:y" if profile in ["town","bridge"] else "rotation:x"
	var angle:=-1.58 if opened else -1.12 if last_state==2 else -0.38 if last_state==1 else 0.0
	if animate and is_inside_tree():
		motion=create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		motion.tween_property(lid,axis,angle,0.27)
	else: lid.set_indexed(NodePath(axis),angle)

class Section extends WastelandScenery:
	func panel(a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3,pigment: Color) -> void:
		triangle(a,b,c,normal,pigment)
		triangle(a,c,d,normal,pigment)

	func bar(at: Vector3,size: Vector3,tint: Color,turn := Basis.IDENTITY) -> void:
		var v: Array[Vector3] = []
		for p: Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,-1,1),Vector3(-1,-1,1),Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(1,1,1),Vector3(-1,1,1)]:
			v.append(at+turn*(p*size*0.5))
		for q in [[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]]:
			var n := (v[q[0]]+v[q[2]])*0.5-at
			panel(v[q[0]],v[q[1]],v[q[2]],v[q[3]],n,tint)

	func ring(y: float,sx: float,sz: float,round_drum: bool) -> PackedVector3Array:
		var result := PackedVector3Array()
		if round_drum:
			for i in 20:
				var a := TAU*i/20.0
				result.append(Vector3(cos(a)*sx,y,sin(a)*sz))
		else:
			for p: Vector2 in [Vector2(-0.82,-1),Vector2(0.82,-1),Vector2(1,-0.8),Vector2(1,0.8),Vector2(0.82,1),Vector2(-0.82,1),Vector2(-1,0.8),Vector2(-1,-0.8)]:
				result.append(Vector3(p.x*sx,y,p.y*sz))
		return result

	func sides(a: PackedVector3Array,b: PackedVector3Array,tint: Color,inward := false) -> void:
		for i in a.size():
			var j := (i+1)%a.size()
			var n := Vector3(a[i].x+a[j].x,0,a[i].z+a[j].z)
			panel(a[i],a[j],b[j],b[i],-n if inward else n,tint)

	func cap(points: PackedVector3Array,up: bool,tint: Color) -> void:
		for i in range(1,points.size()-1):
			triangle(points[0],points[i],points[i+1],Vector3.UP if up else Vector3.DOWN,tint)

static func _build(id: String,table: String) -> Array:
	var base := Section.new(427)
	var top := Section.new(543)
	var cargo := Section.new(315)
	var shell := Color.html(FINISH[id][0])
	var frame := Color.html(FINISH[id][1])
	var accent := Color.html(FINISH[id][2])
	var metal := Color("#ada88a")
	var drum := id in ["pump","ash","desert"]
	var door := id in ["bridge","town"]
	var hinge := Vector3(-0.46,0,0.45) if door else Vector3(0,0.27,-0.44)
	if door:
		base.bar(Vector3(0,0,-0.40),Vector3(0.99,0.91,0.13),shell.darkened(0.26))
		for side: float in [-1.0,1.0]:
			base.bar(Vector3(side*0.46,0,0),Vector3(0.09,0.92,0.86),shell)
			base.bar(Vector3(0,side*0.43,0),Vector3(1,0.08,0.87),frame)
		base.bar(Vector3(0,-0.08,0),Vector3(0.91,0.045,0.81),frame)
		top.bar(Vector3(0.46,0,0),Vector3(0.91,0.79,0.09),shell)
		for i in 4:
			top.bar(Vector3(0.54,0.24-i*0.042,0.058),Vector3(0.40,0.018,0.038),frame)
		for side: float in [-1.0,1.0]:
			top.bar(Vector3(0.73,side*0.12-0.08,0.083),Vector3(0.068,0.048,0.11),metal)
		top.bar(Vector3(0.73,-0.08,0.132),Vector3(0.050,0.28,0.055),metal)
		top.bar(Vector3(0.27,-0.12,0.050),Vector3(0.30,0.15,0.015),accent)
		if id == "bridge":
			for side: float in [-1.0,1.0]:
				top.bar(Vector3(0.46,0.02,0.07),Vector3(0.045,0.91,0.04),accent,Basis(Vector3.BACK,side*0.81))
	else:
		var floor_ring := base.ring(-0.40,0.44,0.39,drum)
		var rim := base.ring(0.27,0.49,0.45,drum)
		var inside := base.ring(0.27,0.45,0.408,drum)
		var inner_floor := base.ring(-0.35,0.402,0.35,drum)
		base.sides(floor_ring,rim,shell)
		base.cap(floor_ring,false,frame)
		base.sides(inner_floor,inside,shell.darkened(0.52),true)
		base.cap(inner_floor,true,frame.darkened(0.30))
		for i in rim.size():
			var j := (i+1)%rim.size()
			base.panel(rim[i],rim[j],inside[j],inside[i],Vector3.UP,metal)
		var lower := top.ring(0,0.50,0.46,drum)
		var upper := top.ring(0.13 if drum else 0.16,0.455,0.414,drum)
		top.sides(lower,upper,shell.lightened(0.12))
		top.cap(lower,false,frame)
		top.cap(upper,true,shell.lightened(0.14))
		if drum:
			for y in [-0.31,0.12]:
				base.sides(base.ring(y,0.489,0.456,true),base.ring(y+0.048,0.492,0.459,true),frame)
			for i in 8:
				var a := TAU*i/8.0
				top.bar(Vector3(0.393*cos(a),0.139,0.357*sin(a)),Vector3(0.037,0.026,0.04),metal)
			for i in 3:
				base.bar(Vector3(-0.135+i*0.136,-0.08,0.441),Vector3(0.077,0.19,0.027),accent,Basis(Vector3.BACK,-0.41))
			var wheel := Color("#993f31") if id=="pump" else frame
			for i in 6:
				var a := TAU*i/6.0
				top.bar(Vector3(0.165*cos(a),0.196,0.165*sin(a)),Vector3(0.045,0.043,0.201),wheel,Basis(Vector3.UP,-a))
				if i%2==0: top.bar(Vector3(0.08*cos(a),0.194,0.08*sin(a)),Vector3(0.17,0.04,0.029),wheel,Basis(Vector3.UP,-a))
		else:
			for side: float in [-1.0,1.0]:
				var strap := accent if id in ["shore","ferry"] else frame
				base.bar(Vector3(side*0.31,-0.065,0.434),Vector3(0.065,0.64,0.045),strap)
				top.bar(Vector3(side*0.31,0.167,0),Vector3(0.067,0.024,0.81),strap)
				base.bar(Vector3(side*0.46,-0.419,0),Vector3(0.098,0.082,0.77),frame)
				base.bar(Vector3(side*0.31,0.205,0.46),Vector3(0.096,0.13,0.044),metal)
			if id=="forest":
				for i in 4:
					base.bar(Vector3(0,-0.304+i*0.144,0.436),Vector3(0.886,0.12,0.031),shell.lightened(0.035*(i%3)))
				base.bar(Vector3(0,-0.065,0.46),Vector3(0.80,0.074,0.040),frame,Basis(Vector3.BACK,0.58))
			elif id=="ridge":
				for side: float in [-1.0,1.0]:
					base.bar(Vector3(side*0.42,-0.22,0.383),Vector3(0.12,0.33,0.13),frame)
					top.bar(Vector3(side*0.023,0.177,0),Vector3(0.043,0.027,0.30),accent,Basis(Vector3.UP,side*0.42))
			else:
				for side: float in [-1.0,1.0]:
					base.bar(Vector3(side*0.49,-0.03,0),Vector3(0.064,0.10,0.75),accent)
				for i in 4:
					top.bar(Vector3(0,0.172,(i-1.5)*0.16),Vector3(0.52,0.024,0.034),shell.darkened(0.20))
	if id=="alpine":
		for side:float in [-1,1]:
			var x:=side*0.32
			base.tube([Vector3(x,-0.36,-0.55),Vector3(x,-0.47,-0.42),Vector3(x,-0.48,0.42),Vector3(x,-0.37,0.57)], [0.036,0.046,0.046,0.031],7,frame,0)
			base.tube([Vector3(side*0.49,0.14,-0.18),Vector3(side*0.57,0.14,-0.18),Vector3(side*0.57,0.14,0.16),Vector3(side*0.49,0.14,0.16)],[0.022,0.023,0.023,0.022],6,accent,0)
		top.bar(Vector3(0,0.177,0),Vector3(0.29,0.023,0.084),accent)
		top.bar(Vector3(0,0.180,0),Vector3(0.075,0.025,0.33),accent)
		base.bar(Vector3(0,-0.04,0.446),Vector3(0.29,0.067,0.023),accent)
		base.bar(Vector3(0,-0.04,0.448),Vector3(0.068,0.31,0.024),accent)
	elif id=="desert":
		var nozzle:=Vector3(0,-0.19,0.40)
		base.tube([nozzle,nozzle+Vector3.BACK*0.13,nozzle+Vector3(0,-0.08,0.15)],[0.047,0.051,0.038],8,accent,0)
		base.bar(nozzle+Vector3(0,0.067,0.095),Vector3(0.17,0.028,0.033),Color("#a55541"))
		for i in 2:
			var x:float=-0.25+i*0.50
			base.bar(Vector3(x,-0.41,0),Vector3(0.095,0.13,0.79),frame)
		base.bar(Vector3(0.30,-0.015,0.322),Vector3(0.091,0.38,0.10),frame)
		base.bar(Vector3(0.30,-0.038,0.377),Vector3(0.035,0.27,0.013),Color("#a6d7cf"))
		for i in 4: base.bar(Vector3(0.33,-0.16+i*0.081,0.38),Vector3(0.031,0.009,0.013),accent)
		top.tube([Vector3(-0.18,0.15,0),Vector3(-0.18,0.24,0),Vector3(0.15,0.24,0),Vector3(0.15,0.15,0)],[0.025,0.024,0.024,0.025],8,frame,0)
	elif id == "ferry":
		for i in 16:
			var a := TAU*i/16.0
			var rescue := Color("#c05437") if (i/2)%2==0 else Color("#e9dbc2")
			base.bar(Vector3(0.155*cos(a),-0.037+0.207*sin(a),0.475),Vector3(0.065,0.090,0.079),rescue,Basis(Vector3.BACK,a))
		for side: float in [-1.0,1.0]:
			var rope_x := side*0.515
			base.tube(PackedVector3Array([Vector3(rope_x,0.16,-0.34),Vector3(rope_x*1.055,-0.05,-0.16),Vector3(rope_x*1.06,-0.07,0.09),Vector3(rope_x,0.16,0.33)]),PackedFloat32Array([0.015,0.016,0.016,0.015]),6,Color("#bfaa7c"))
	elif id == "pump":
		var gauge := Vector3(0,0.035,0.46)
		base.tube(PackedVector3Array([gauge,gauge+Vector3.BACK*0.06]),PackedFloat32Array([0.138,0.134]),16,frame)
		base.tube(PackedVector3Array([gauge+Vector3.BACK*0.061,gauge+Vector3.BACK*0.073]),PackedFloat32Array([0.113,0.113]),16,accent.lightened(0.39))
		base.bar(gauge+Vector3(-0.025,0.025,0.077),Vector3(0.015,0.10,0.013),Color("#913a2c"),Basis(Vector3.BACK,0.69))
		for side: float in [-1.0,1.0]:
			var spout := Vector3(side*0.405,-0.19,0)
			base.tube(PackedVector3Array([spout,spout+Vector3(side*0.17,0,0),spout+Vector3(side*0.22,0.06,0),spout+Vector3(side*0.22,0.16,0)]),PackedFloat32Array([0.081,0.079,0.073,0.076]),10,accent)
			base.bar(spout+Vector3(side*0.22,0.163,0),Vector3(0.18,0.041,0.18),frame)
	# Small pictographs keep the location's medical, food and technical contents identifiable.
	var badge_colors := {"medical":"d39b84","kitchen":"a7ab73","weapons":"8b9a7d","safe":"c5aa69","salvage":"81ada9","trunk":"a29bae"}
	if badge_colors.has(table):
		var at := Vector3(0.22,-0.16,0.067) if door else Vector3(0.03,0.07,0.455)
		var board := top if door else base
		board.bar(at,Vector3(0.181,0.146,0.021),Color.html(badge_colors[table]))
		if table == "medical":
			board.bar(at+Vector3.BACK*0.019,Vector3(0.106,0.032,0.014),Color.WHITE)
			board.bar(at+Vector3.BACK*0.020,Vector3(0.030,0.104,0.014),Color.WHITE)
		else:
			for line in 2: board.bar(at+Vector3(0,0.025-line*0.047,0.014),Vector3(0.115-line*0.034,0.012,0.011),frame)
	if id=="desert":
		var bottles:Color=Color("#9bc8c2")
		for i in 3:
			var at:=Vector3(-0.18+0.18*i,-0.21,0)
			cargo.tube([at,at+Vector3.UP*0.19,at+Vector3.UP*0.25],[0.073,0.073,0.031],10,bottles,0)
	elif id=="alpine":
		cargo.bar(Vector3(-0.13,-0.13,0),Vector3(0.25,0.33,0.26),accent)
		cargo.tube([Vector3(0.09,-0.15,-0.17),Vector3(0.09,-0.15,0.17)],[0.107,0.107],11,Color("#698b7b"),0)
	else:
		for i in 3:
			cargo.bar(Vector3(-0.19+i*0.17,-0.22,0.07*(i%2)),Vector3(0.17,0.22+i*0.034,0.27),accent.darkened(0.12*i),Basis(Vector3.UP,i*0.33))
	var lid_mesh := top.commit()
	if not door:
		var offset := SurfaceTool.new()
		offset.append_from(lid_mesh,0,Transform3D(Basis.IDENTITY,Vector3(0,0,-hinge.z)))
		lid_mesh = offset.commit()
	return [base.commit(),lid_mesh,cargo.commit(),hinge]
