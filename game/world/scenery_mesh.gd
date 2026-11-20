class_name WastelandScenery
extends RefCounted

const H := 1.618034
const ICOSA := [
	Vector3(-1,H,0), Vector3(1,H,0), Vector3(-1,-H,0), Vector3(1,-H,0),
	Vector3(0,-1,H), Vector3(0,1,H), Vector3(0,-1,-H), Vector3(0,1,-H),
	Vector3(H,0,-1), Vector3(H,0,1), Vector3(-H,0,-1), Vector3(-H,0,1),
]
const FACES := [
	[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],
	[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
	[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
	[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1],
]
const AUTUMN := ["689476", "83a578", "c79253", "488377"]
const FIR := ["4e6e61", "587768", "465f5a", "6d7954"]
var buffer := SurfaceTool.new()
var rng := RandomNumberGenerator.new()
var triangle_count := 0

func _init(seed_value: int) -> void:
	rng.seed = seed_value
	buffer.begin(Mesh.PRIMITIVE_TRIANGLES)
	buffer.set_smooth_group(-1)

func commit() -> ArrayMesh:
	buffer.generate_normals()
	return buffer.commit()

func triangle(a: Vector3, b: Vector3, c: Vector3, external: Vector3, tint: Color) -> void:
	var facing := (c - a).cross(b - a).dot(external)
	if absf(facing) < 0.0000001:
		return
	triangle_count += 1
	var vertices: Array = [a, b, c] if facing > 0.0 else [a, c, b]
	for index in range(3):
		buffer.set_color(tint)
		buffer.set_uv([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN][index])
		buffer.add_vertex(vertices[index])

func tube(axis: PackedVector3Array, widths: PackedFloat32Array, sides: int, tint: Color, twist: float = 0.0) -> void:
	var rings: Array[PackedVector3Array] = []
	for index in axis.size():
		var tangent := (axis[mini(index+1,axis.size()-1)] - axis[maxi(0,index-1)]).normalized()
		var reference := Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.89 else Vector3.RIGHT
		var u := tangent.cross(reference).normalized()
		var v := tangent.cross(u)
		var ring := PackedVector3Array()
		for n in sides:
			var angle := float(n)*TAU/sides+twist+index*0.10
			var irregular := 1.0+0.08*sin(n*2.3+twist)
			ring.append(axis[index]+(u*cos(angle)+v*sin(angle))*widths[index]*irregular)
		rings.append(ring)
	for index in range(rings.size()-1):
		for n in sides:
			var next := (n+1)%sides
			var a := rings[index][n]
			var b := rings[index][next]
			var c := rings[index+1][n]
			var d := rings[index+1][next]
			var outside := (a+b+c+d)*0.25-(axis[index]+axis[index+1])*0.5
			var warmed := tint.lerp(Color("#b28163"),maxf(0,sin(n*5.3+twist))*0.28)
			triangle(a,b,c,outside,warmed)
			triangle(b,d,c,outside,warmed.darkened(maxf(0.0,sin(n*2.7+index))*0.11))
	for n in range(1,sides-1):
		triangle(rings[0][0],rings[0][n],rings[0][n+1],axis[0]-axis[1],tint.darkened(0.2))
		var end := rings.size()-1
		triangle(rings[end][0],rings[end][n+1],rings[end][n],axis[end]-axis[end-1],tint.lightened(0.12))

func lobe(center: Vector3, extent: Vector3, tint: Color, turning: float, detailed: bool, kind: float = 0.13) -> void:
	var spin := Basis(Vector3.UP, turning) * Basis(Vector3.FORWARD, sin(turning*1.43)*0.14)
	for face in FACES:
		var a: Vector3 = ICOSA[face[0]].normalized()
		var b: Vector3 = ICOSA[face[1]].normalized()
		var c: Vector3 = ICOSA[face[2]].normalized()
		if detailed:
			var ab := (a+b).normalized()
			var bc := (b+c).normalized()
			var ca := (c+a).normalized()
			_lobe_face(a,ab,ca,center,extent,spin,tint,turning,kind)
			_lobe_face(b,bc,ab,center,extent,spin,tint,turning,kind)
			_lobe_face(c,ca,bc,center,extent,spin,tint,turning,kind)
			_lobe_face(ab,bc,ca,center,extent,spin,tint,turning,kind)
		else:
			_lobe_face(a,b,c,center,extent,spin,tint,turning,kind)

func _lobe_face(a: Vector3,b: Vector3,c: Vector3,center: Vector3,extent: Vector3,spin: Basis,tint: Color,salt: float,rough: float) -> void:
	var pa := center + spin * (_undulate(a,salt,rough) * extent)
	var pb := center + spin * (_undulate(b,salt,rough) * extent)
	var pc := center + spin * (_undulate(c,salt,rough) * extent)
	var outward := (pa+pb+pc)/3.0-center
	var edge := ((a+b+c)/3.0).y
	var pattern := sin(a.x*14.8+b.z*8.7+c.y*11.1+salt)
	var tint_step := clampf(roundf((edge*0.16+pattern*0.125)*9.0)/9.0,-0.22,0.26)
	var color := tint.lightened(tint_step) if tint_step >= 0.0 else tint.darkened(-tint_step)
	triangle(pa,pb,pc,outward,color)

func _undulate(unit: Vector3, offset: float, rough: float) -> Vector3:
	return unit * (1.0 + sin(unit.x*14.7+unit.y*8.3+unit.z*11.9+offset*3.31)*rough)

func foliage_blade(foot: Vector3, facing: float, length: float, width: float, curl: float, tint: Color) -> void:
	var direction := Vector3(cos(facing),0,sin(facing))
	var across := Vector3(-direction.z,0,direction.x)
	var a := foot - across*width*0.44
	var b := foot + across*width*0.44
	var middle := foot + Vector3.UP*length*0.63 + direction*curl*0.28
	var end := foot + Vector3.UP*length + direction*curl
	var left := middle - across*width*0.51
	var right := middle + across*width*0.51
	var raised := middle + direction*width*0.28
	triangle(a,raised,b,direction,tint.darkened(0.20))
	triangle(a,left,raised,direction,tint)
	triangle(b,raised,right,direction,tint.darkened(0.10))
	triangle(left,end,raised,direction,tint.lightened(0.17))
	triangle(right,raised,end,direction,tint.lightened(0.11))

func leafy_bough(at: Vector3, span: float, facing: float, tint: Color, detailed: bool) -> void:
	# Overlapping folded sprays leave sky gaps between the forks.
	var forks := 5 if detailed else 4
	for fork in forks:
		var angle := facing + (float(fork) / (forks - 1) - 0.5) * 3.25
		var along := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-along.z, 0, along.x)
		var length := span * rng.randf_range(0.78, 1.23)
		var width := length * rng.randf_range(0.22, 0.38)
		var heel := at + along * 0.05
		var ridge := heel + along * length * 0.50 + Vector3.UP * length * 0.31
		var tip := heel + along * length + Vector3.UP * length * rng.randf_range(0.03, 0.26)
		var pigment := tint.lightened(rng.randf_range(0.0, 0.13))
		for side in [-1.0, 1.0]:
			var shoulder: Vector3 = ridge + across * width * side - Vector3.UP * width * 0.68
			triangle(heel, shoulder, ridge, Vector3.UP, pigment.darkened(0.12))
			triangle(shoulder, tip, ridge, Vector3.UP, pigment)
			if detailed:
				for pair in range(3):
					var t := 0.28 + pair * 0.23
					var stem := heel.lerp(ridge, t * 2.0) if t < 0.5 else ridge.lerp(tip, t * 2.0 - 1.0)
					var end: Vector3 = stem + along * length * 0.25 + across * side * width * (1.54 - t * 0.4) - Vector3.UP * width * 0.8
					triangle(stem, stem + along * length * 0.26, end, Vector3.UP, pigment.lightened(0.08 * pair))

func broadleaf(variant: int, detailed: bool) -> void:
	var bark := Color.html(["664635","6d4b3c","755340","684b42"][variant])
	var leaf := Color.html(AUTUMN[variant])
	var height: float = [6.68, 7.88, 6.86, 7.12][variant]
	var bend := Vector3(rng.randf_range(-0.67,0.66),0,rng.randf_range(-0.40,0.41))
	var stem := PackedVector3Array([
		Vector3(0,-0.22,0),Vector3(0,0.40,0), Vector3(0.08,height*0.27,0.05),
		bend*0.58+Vector3(0,height*0.51,0),bend+Vector3(0,height*0.74,0),bend*1.14+Vector3(0,height*0.96,0)])
	tube(stem,PackedFloat32Array([0.42,0.29,0.23,0.18,0.10,0.017]),9 if detailed else 6,bark,variant*0.3)
	if detailed:
		for root in range(5):
			var a := TAU*float(root)/5.0+variant*0.83
			var direction := Vector3(cos(a),0,sin(a))
			tube(PackedVector3Array([Vector3(0,0.62,0),direction*0.40+Vector3.UP*0.16,direction*0.93-Vector3.UP*0.05]),
				PackedFloat32Array([0.15,0.12,0.025]),5,bark.darkened(0.1),a)
	var branch_count := 7 if detailed else 5
	for branch in range(branch_count):
		var angle := branch * 2.399963 + variant * 0.83
		var direction := Vector3(cos(angle),0,sin(angle))
		var sideways := Vector3(-direction.z,0,direction.x)
		var level := float(branch)/maxi(1,branch_count-1)
		var origin := bend*level + Vector3.UP*height*(0.44+level*0.26)
		var lean := rng.randf_range(1.46,2.37) * (1.0-level*0.30)
		var elbow := origin + direction*lean*0.63 + sideways*0.16 + Vector3.UP*(0.48+level*0.4)
		var top := origin + direction*lean + sideways*rng.randf_range(-0.24,0.27) + Vector3.UP*(0.94+level*0.29)
		tube(PackedVector3Array([origin,elbow,top]),PackedFloat32Array([0.153-level*0.07,0.081,0.018]),6 if detailed else 4,bark,angle)
		var size := rng.randf_range(0.91,1.33)
		leafy_bough(top, size * 1.49, angle, leaf, detailed)
		leafy_bough(elbow + Vector3.UP * 0.29, size, angle - 1.7, leaf.darkened(0.08), detailed)
		if detailed:
			for branchlet in range(2):
				var side := -1.0 if branchlet == 0 else 1.0
				var tip := elbow+sideways*side*rng.randf_range(0.62,1.02)+direction*0.57+Vector3.UP*0.92
				tube(PackedVector3Array([elbow,elbow.lerp(tip,0.59)+Vector3.UP*0.10,tip]),
					PackedFloat32Array([0.065,0.039,0.013]),5,bark,angle+side)
				leafy_bough(tip, size * 1.12, angle + side * 1.19, leaf.lightened(0.07), true)
			for spray in range(5):
				var dist := 1.14+rng.randf()*0.29
				var p := top + sideways*rng.randf_range(-0.82,0.81)+direction*dist+Vector3.UP*rng.randf_range(0.07,0.76)
				foliage_blade(p,angle+spray*1.8,rng.randf_range(0.19,0.29),0.13,0.22,leaf.lightened(0.15))
	for i in range(3 if detailed else 1):
		var a := i*2.06+variant
		var tip := bend + Vector3(cos(a)*0.54,height*0.83+i*0.44,sin(a)*0.60)
		leafy_bough(tip, 1.70 - i * 0.15, a, leaf.lightened(0.08+i*0.06), detailed)

func conifer(variant: int, detailed: bool) -> void:
	var bark := Color("#68534b")
	var needles := Color.html(FIR[variant])
	var height := 8.4+variant*0.52
	var lean := Vector3(rng.randf_range(-0.38,0.40),0,rng.randf_range(-0.29,0.32))
	tube(PackedVector3Array([Vector3.DOWN*0.2,Vector3.UP*0.66,Vector3.UP*3.0,lean+Vector3.UP*5.5,lean+Vector3.UP*height]),
		PackedFloat32Array([0.40,0.26,0.17,0.11,0.021]),8 if detailed else 5,bark)
	var steps := 7 if detailed else 5
	for tier in range(steps):
		var slide := float(tier)/(steps-1)
		var y := lerpf(2.25,height-0.70,slide)
		var extent := lerpf(2.04,0.35,slide)
		var root := lean*slide+Vector3.UP*y
		var whorl := 6 if detailed else 4
		for branch in range(whorl):
			var a := branch*TAU/whorl+tier*0.61+variant*0.27
			var d := Vector3(cos(a),0,sin(a))
			var tip := root+d*extent+Vector3.UP*(0.16+slide*0.29)
			if detailed and tier < 5:
				tube(PackedVector3Array([root,root.lerp(tip,0.52)-Vector3.UP*0.14,tip]),
					PackedFloat32Array([0.087*(1.0-slide),0.041,0.012]),5,bark,a)
			var side := Vector3(-d.z, 0, d.x)
			var crown := root + Vector3.UP * (0.6 + extent * 0.20)
			var crease := root.lerp(tip, 0.62) + Vector3.UP * 0.13
			var tone := needles.lightened(slide * 0.21)
			for sign_value in [-1.0, 1.0]:
				var skirt: Vector3 = root.lerp(tip, 0.69) + side * sign_value * extent * 0.31 - Vector3.UP * 0.14
				triangle(crown, skirt, crease, Vector3.UP, tone)
				triangle(crease, skirt, tip, Vector3.UP, tone.lightened(0.11))
				if detailed:
					var spike: Vector3 = skirt + d * extent * 0.34 - Vector3.UP * 0.08
					triangle(skirt, crease, spike, Vector3.UP, tone.darkened(0.08))
			if detailed and tier<5:
				var edge := root.lerp(tip,0.78)
				for flair in range(3):
					var direction := a+lerpf(-0.64,0.70,float(flair)/2.0)
					foliage_blade(edge,direction,0.36,0.17,extent*0.27,needles.lightened(0.20))
	for sprig in range(5):
		var angle := sprig * TAU / 5.0
		var along := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-along.z, 0, along.x)
		var peak := lean + Vector3.UP * (height + 0.44)
		var foot := peak + along * 0.42 - Vector3.UP * 1.16
		triangle(peak, foot - side * 0.21, foot + side * 0.21, along, needles.lightened(0.18))

func stone(kind: String, variant: int, detailed: bool) -> void:
	var tint := Color.html(["807381","857483","938793","847c86"][variant])
	if kind == "clay_bank":
		tint = Color("#ab745f")
	elif kind == "ore":
		tint = Color("#736b86")
	elif kind == "salvage":
		tint = Color("#7d6663")
	var size := 0.23 if kind == "pebble" else rng.randf_range(0.83,1.29)
	lobe(Vector3(0,size*0.29,0),Vector3(size*0.56,size*0.39,size*0.55),tint,variant*1.17,detailed,0.25)
	for i in range(4 if detailed else 2):
		var theta := float(i)*TAU/4.0+variant*0.34
		var radial := Vector3(cos(theta),0,sin(theta))
		var bite := rng.randf_range(0.17,0.39)*size
		lobe(radial*size*0.39+Vector3.UP*bite*0.36,Vector3(bite*0.97,bite*0.65,bite*0.88),
			tint.lerp(Color("#b4a5ad"),i*0.11),theta,detailed and kind!="pebble",0.26)
	if kind in ["ore","salvage"] and detailed:
		for row in range(5):
			var theta := row*1.26
			var at := Vector3(cos(theta)*size*0.29,size*(0.48+row*0.018),sin(theta)*size*0.29)
			lobe(at,Vector3(size*0.14,size*0.072,size*0.15),Color("#bd9b70") if kind=="ore" else Color("#c99368"),theta,false,0.09)

func understory(kind: String, variant: int, detailed: bool) -> void:
	var gold := Color.html(["87a27d","83996d","76998a","bdab76"][variant])
	if kind == "brush":
		for graze in range(7 if detailed else 4):
			var angle := graze*2.39996+variant
			var extent := rng.randf_range(0.15,0.36)
			var at := Vector3(cos(angle)*extent,0.31+0.05*graze,sin(angle)*extent)
			tube(PackedVector3Array([Vector3.ZERO,at*0.54,at]),PackedFloat32Array([0.031,0.024,0.009]),4,Color("#756052"),angle)
			lobe(at,Vector3(0.29,0.18,0.26),Color("#767646").lightened(graze*0.045),angle,detailed and graze<4,0.24)
			if graze%2==0:
				lobe(at+Vector3(cos(angle)*0.15,0.09,sin(angle)*0.14),Vector3.ONE*0.061,Color("#b15b64"),angle,false)
		return
	var reeds := kind=="reeds"
	for index in range(15 if detailed else 7):
		var angle := index*2.39996+variant*0.31
		var at := Vector3(rng.randf_range(-0.51,0.51),0.006,rng.randf_range(-0.39,0.41))
		var tall := rng.randf_range(0.43,0.89) if reeds else rng.randf_range(0.22,0.50)
		var curl := rng.randf_range(0.07,0.28)
		foliage_blade(at,angle,tall,0.092 if reeds else 0.086,curl * 1.6,gold.lightened((index%4)*0.07))
		if reeds and index%3==0:
			lobe(at+Vector3(cos(angle)*curl,tall,sin(angle)*curl),Vector3(0.041,0.090,0.051),Color("#926742"),angle,false)

static func build(kind: String, variant: int, detail: bool) -> ArrayMesh:
	var model := WastelandScenery.new(810252+variant*79)
	match kind:
		"pondweed":
			for i in (11 if detail else 5):
				var a := i*2.39996 + variant
				var foot := Vector3(cos(a)*0.32,0,sin(a)*0.32)
				model.foliage_blade(foot,a,model.rng.randf_range(0.43,1.19),0.11,0.26,Color("#568c70").darkened(0.08*(i%3)))
		"bedrock": model.stone("boulder",variant,detail)
		"oak": model.broadleaf(variant,detail)
		"pine": model.conifer(variant,detail)
		"fallen_stick":
			model.tube([Vector3(-0.45,0.06,-0.12),Vector3(0.05,0.10,0.09),Vector3(0.49,0.13,0.04)],[0.047,0.036,0.019],6,Color("#ad835b"))
			model.tube([Vector3(0.05,0.1,0.09),Vector3(0.23,0.17,0.31)],[0.028,0.011],5,Color("#bb916b"))
		"boulder", "ore", "salvage", "clay_bank", "pebble": model.stone(kind,variant,detail)
		_: model.understory(kind,variant,detail)
	return model.commit()
