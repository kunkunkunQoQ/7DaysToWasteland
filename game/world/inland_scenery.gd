extends RefCounted

static func build(kind:String,variant:int,detail:bool)->ArrayMesh:
	var mesh:=WastelandScenery.new(92311+variant*87+kind.hash())
	match kind:
		"birch","snag": _trunk(mesh,kind=="birch",variant,detail)
		"frost_fir","snow_fir": _fir(mesh,variant,detail,kind=="snow_fir")
		"strata","snowstone": _rock(mesh,kind=="snowstone",variant,detail)
		"cactus": _cactus(mesh,variant,detail)
		"dry_scrub": _scrub(mesh,variant,detail)
		_:
			var wet:=kind=="sedge"
			for i in (14 if detail else 6):
				var a:=i*2.39996
				var foot:=Vector3(cos(a),0,sin(a))*mesh.rng.randf_range(0.0,0.29)
				var length:=mesh.rng.randf_range(0.60,1.36) if wet else mesh.rng.randf_range(0.29,0.76)
				var color:=Color("#81925c") if wet else Color("#b4a768")
				mesh.foliage_blade(foot,a,length,0.046,0.16,color.lightened((i%3)*0.065))
				if detail and i%4==0:
					var tip:=foot+Vector3(cos(a)*0.18,length,sin(a)*0.18)
					mesh.tube([foot,tip],[0.010,0.006],4,color,0)
					mesh.lobe(tip,Vector3(0.028,0.119,0.026),Color("#795e42") if wet else Color("#ccaf74"),a,false)
	return mesh.commit()

static func _trunk(m:WastelandScenery,birch:bool,v:int,detail:bool)->void:
	var h:=6.4+v*0.45 if birch else 4.2+v*0.39
	var bark:=Color("#c3bba5") if birch else Color("#726650")
	var crown:=Vector3(0.42,h,0.25)
	m.tube([Vector3.DOWN*0.18,Vector3.UP*0.35,Vector3(0.05,h*0.44,-0.06),crown],[0.23,0.18,0.115,0.027 if birch else 0.105],9 if detail else 5,bark,0)
	var leaves:Color=[Color("#baad50"),Color("#adb15b"),Color("#d5b45a"),Color("#a3a85e")][v]
	if birch and detail:
		for i in 14:
			var a:=i*2.4
			var level:=i/16.0
			var c:=Vector3(0.10*level,h*level+0.14,-0.035*level)
			var radial:=Vector3(cos(a),0,sin(a))
			var crosswise:=Vector3(-radial.z,0,radial.x)
			var p:=c+radial*lerpf(0.181,0.078,level)
			m.triangle(p-crosswise*0.082,p+crosswise*0.095,p+Vector3.UP*0.055,radial,Color("#514e43"))
	for i in (10 if birch else 5):
		var t:=float(i)/(10 if birch else 5)
		var a:=v+i*2.40
		var dir:=Vector3(cos(a),0,sin(a))
		var at:=Vector3(0.06+t*0.24,h*(0.39+0.49*t),0)
		var spread:=(1.57-0.72*t) if birch else 1.41-0.39*t
		var fork:=at+dir*spread*0.62+Vector3.UP*(0.41+t*0.2)
		var end:=at+dir*spread+Vector3.UP*(0.92+t*0.23)
		m.tube([at,fork,end],[0.098,0.054,0.012 if birch else 0.023],6 if detail else 4,bark,a)
		if birch:
			m.leafy_bough(end,1.15-0.42*t,a,leaves,detail)
			if detail: m.leafy_bough(fork+Vector3.UP*0.3,0.92,a+1.15,leaves.darkened(0.12),false)
		elif detail:
			var twig:=fork+dir.rotated(Vector3.UP,0.78)*0.60+Vector3.UP*0.85
			m.tube([fork,twig],[0.052,0.006],5,bark.lightened(0.16),a)
	if birch: m.leafy_bough(crown,1.13,v,leaves.lightened(0.12),detail)

static func _fir(m:WastelandScenery,v:int,detail:bool,snow:bool)->void:
	var h:=6.8+0.65*v
	m.tube([Vector3.DOWN*0.12,Vector3.UP*h*0.5,Vector3.UP*h],[0.24,0.115,0.017],7 if detail else 5,Color("#62594b"),0)
	var steps:=7 if detail else 5
	for i in steps:
		var t:=float(i)/(steps-1)
		var at:=Vector3.UP*(1.08+t*(h-1.7))
		var width:=(1.92-1.45*t)*(1.0+0.07*sin(i*5.0+v))
		var count:=8 if detail else 6
		for j in count:
			var ang:=j*TAU/count+i*0.69+v
			var dir:=Vector3(cos(ang),0,sin(ang))
			var side:=Vector3(-dir.z,0,dir.x)*width*0.32
			var tip:=at+dir*width+Vector3.UP*0.09
			var bend:=at+dir*width*0.61-Vector3.UP*0.19
			var ridge:=at+Vector3.UP*(0.72+width*0.12)
			var tone:=Color("#38594d").lightened(t*0.12)
			for signum:float in [-1,1]:
				var skirt:=bend+side*signum
				m.triangle(ridge,skirt,tip,dir+Vector3.UP,tone)
				if snow:
					m.triangle(ridge+Vector3.UP*0.035,skirt.lerp(ridge,0.25)+Vector3.UP*0.032,tip.lerp(ridge,0.30)+Vector3.UP*0.035,dir+Vector3.UP,Color("#d3dedb").darkened(0.028*(j%3)))
				m.triangle(at,skirt,tip,Vector3.DOWN,tone.darkened(0.17))
				if detail:
					var inner:=ridge.lerp(tip,0.52)
					m.triangle(inner,skirt,tip+dir*0.19,Vector3.UP,tone.lightened(0.10))
	m.tube([Vector3.UP*(h-0.9),Vector3.UP*(h+0.20)],[0.31,0.012],6,Color("#567364"),0)

static func _rock(m:WastelandScenery,snow:bool,v:int,detail:bool)->void:
	var sides:=9 if detail else 6
	var heights:=[-0.15,0.25,0.48,0.55,0.89,1.05,1.34]
	var radii:=[0.83,1.03,0.93,0.98,0.85,0.91,0.67]
	var hues:=[Color("#a26445"),Color("#c1845c"),Color("#764e47"),Color("#bc7650"),Color("#e0b07a"),Color("#8d5e4a")]
	for i in heights.size()-1:
		for j in sides:
			var corners:=PackedVector3Array()
			for pair in [[i,j],[i,(j+1)%sides],[i+1,j],[i+1,(j+1)%sides]]:
				var layer:int=pair[0]
				var a:=TAU*float(pair[1])/sides
				var radius:float=radii[layer]*(1.1+0.21*sin(a*3+v))
				corners.append(Vector3(cos(a)*radius+0.11*layer/6.0,float(heights[layer])*(0.68+0.085*v)+0.071*sin(a+v),sin(a)*radius*0.75))
			var n:=(corners[0]+corners[1])*0.5
			n.y=0
			var tone:Color=hues[i] if not snow else Color("#706f78").lightened(0.04*(i%3))
			if snow and i>=4: tone=Color("#d5dfdf").darkened(0.07*(5-i))
			m.triangle(corners[0],corners[1],corners[2],n,tone)
			m.triangle(corners[1],corners[3],corners[2],n,tone)
			if i==5:
				m.triangle(corners[2],corners[3],Vector3(0.12,1.39*(0.68+0.085*v),0),Vector3.UP,Color("#e8eeee") if snow else hues[4])

static func _cactus(m:WastelandScenery,v:int,detail:bool)->void:
	var h:=1.43+0.19*v
	var green:=Color("#69835a")
	m.tube([Vector3.DOWN*0.10,Vector3.UP*h*0.78,Vector3.UP*h],[0.17,0.19,0.082],10 if detail else 6,green,0)
	for i in 2:
		var side:float=-1 if i==0 else 1
		var base:=Vector3.UP*h*(0.36+i*0.13)
		var arm:=base+Vector3(side*(0.35+i*0.08),0.14,0.09*i)
		m.tube([base,arm,arm+Vector3.UP*0.50,arm+Vector3.UP*0.62],[0.10,0.12,0.094,0.04],8 if detail else 5,green,0)
		var tip:=arm+Vector3.UP*0.68
		m.lobe(tip,Vector3(0.084,0.117,0.078),Color("#b84c67"),i,detail)
		if detail: m.lobe(tip+Vector3.UP*0.09,Vector3(0.038,0.024,0.036),Color("#d79d67"),i,false)
	if detail:
		for j in 10:
			var a:=j*TAU/10
			var d:=Vector3(cos(a),0,sin(a))
			m.tube([d*0.173+Vector3.UP*0.10,d*0.188+Vector3.UP*h*0.76,d*0.115+Vector3.UP*h*0.94],[0.008,0.009,0.004],4,green.lightened(0.24),0)

static func _scrub(m:WastelandScenery,v:int,detail:bool)->void:
	for i in (9 if detail else 5):
		var a:=i*2.4+v
		var dir:=Vector3(cos(a),0,sin(a))
		var k:=dir*0.32+Vector3.UP*0.28
		var tip:=dir*0.57+Vector3.UP*(0.48+0.09*sin(i))
		m.tube([Vector3.ZERO,k,tip],[0.033,0.021,0.005],4,Color("#8e7857"),0)
		if i%2==0: m.leafy_bough(k,0.25,a,Color("#a5a378"),false)
