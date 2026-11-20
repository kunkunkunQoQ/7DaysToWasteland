extends RefCounted

const Sculpt := WastelandBestiary.Sculpture

static func helmet() -> Sculpt:
	var mesh := Sculpt.new(501)
	var shell := Color("#d5a442")
	mesh.oval(Vector3(0,1.735,-0.001),Vector3(0.156,0.023,0.168),shell.darkened(0.12))
	mesh.oval(Vector3(0,1.755,0.001),Vector3(0.145,0.087,0.147),shell)
	for side: int in [-1,1]:
		mesh.twig([Vector3(side*0.053,1.796,-0.096),Vector3(side*0.043,1.835,-0.035),Vector3(side*0.043,1.835,0.035),Vector3(side*0.05,1.804,0.09)],
			[0.007,0.008,0.008,0.006],shell.lightened(0.10),7)
	mesh.oval(Vector3(0,1.752,-0.144), Vector3(0.035,0.013,0.005), Color("#cfd1bb"))
	return mesh

static func glove(side: int) -> Sculpt:
	var mesh := Sculpt.new(502)
	var leather := Color("#a57546")
	mesh.loft([Vector4(-0.071,0.050,0.065,-0.012),Vector4(-0.040,0.052,0.061,-0.008),
		Vector4(-0.010,0.037,0.043,0.002),Vector4(0.033,0.041,0.045,0.005)],leather)
	mesh.loft([Vector4(-0.001,0.039,0.045,0.003),Vector4(0.030,0.044,0.047,0.005)],Color("#5e5946"))
	mesh.oval(Vector3(side*0.037,-0.049,-0.009),Vector3(0.016,0.030,0.053),leather.darkened(0.22))
	return mesh

static func boot() -> Sculpt:
	var mesh := Sculpt.new(503)
	var leather := Color("#795542")
	mesh.oval(Vector3(0,-0.065,-0.058),Vector3(0.071,0.046,0.136),leather)
	mesh.oval(Vector3(0,-0.091,-0.067),Vector3(0.081,0.028,0.155),Color("#393c39"))
	mesh.loft([Vector4(-0.070,0.063,0.073,0.004),Vector4(0.012,0.055,0.056,0.008),
		Vector4(0.074,0.061,0.058,0.006),Vector4(0.091,0.063,0.06,0.005)],leather)
	for i in 3:
		var y := -0.045+i*0.027
		var z := -0.072+i*0.007
		mesh.twig([Vector3(-0.030,y,z),Vector3(0,y+0.008,z-0.008),Vector3(0.030,y,z)],[0.0035,0.0042,0.0035],Color("#b29c7b"),6)
	return mesh


static func cap()->Sculpt:
	var m:=Sculpt.new(504)
	var wool:=Color("#776b84",0.50)
	var band:=Color("#514960",0.25)
	# The raised crown slouches behind the head, above the fitted ribbed cuff.
	m.loft([Vector4(1.698,0.142,0.143,0.005),Vector4(1.736,0.150,0.150,0.008),
		Vector4(1.778,0.137,0.137,0.018),Vector4(1.807,0.100,0.110,0.030),Vector4(1.812,0.050,0.071,0.050),
		Vector4(1.800,0.014,0.020,0.082)],wool)
	m.loft([Vector4(1.685,0.143,0.144,0.004),Vector4(1.694,0.148,0.150,0.005),
		Vector4(1.717,0.151,0.152,0.007),Vector4(1.723,0.147,0.148,0.008)],band)
	for i in 28:
		var a:=TAU*i/28
		var n:=Vector3(sin(a),0,cos(a))
		m.twig([n*0.146+Vector3(0,1.690,0.005),n*0.151+Vector3(0,1.716,0.007)],
			[0.0025,0.0026],wool.lightened(0.10),4)
	for side:float in [-1,1]:
		m.oval(Vector3(side*0.129,1.673,0.015),Vector3(0.021,0.041,0.047),band)
	return m

static func cape(w:Vector3)->Sculpt:
	var m:=Sculpt.new(505)
	var sand:=Color("#c4a67c",0.5)
	var hem:=Color("#836c50",0.25)
	const SIDES:=32
	var rows:Array[PackedVector3Array]=[]
	for j in 7:
		var row:=PackedVector3Array()
		for i in SIDES+1:
			var a:=lerpf(0.10,TAU-0.10,i/float(SIDES))
			var front:=cos(a)
			var fold:=cos(9*a+0.25)
			var shoulder:float=[0.088,w.x*0.79,w.x+0.062,w.x+0.084,w.x+0.096,w.x+0.104,w.x+0.104][j]
			var depth:float=[0.081,0.124,0.163,0.180,0.192,0.202,0.204][j]
			var bottom:=0.84+0.22*maxf(front,0.0)+0.032*sin(3*a+0.21)
			var y:float=[1.470,1.448,1.397,1.295,1.14,bottom+0.024,bottom][j]
			var ripple:=fold*(0.002+j*0.002)
			row.append(Vector3(sin(a)*(shoulder+ripple),y,-front*(depth+ripple)))
		rows.append(row)
	for j in rows.size()-1:
		for i in SIDES:
			var a:=rows[j][i]
			var b:=rows[j][i+1]
			var c:=rows[j+1][i]
			var d:=rows[j+1][i+1]
			var outward:=Vector3(a.x,0.10,a.z).normalized()
			var tint:=hem if j==5 or i in [0,SIDES-1] else sand.lightened(0.035*(i%3))
			m.triangle(a,b,c,outward,tint)
			m.triangle(c,b,d,outward,tint)
			m.triangle(a,c,b,-outward,tint.darkened(0.22))
			m.triangle(c,d,b,-outward,tint.darkened(0.22))
	m.twig([Vector3(-0.065,1.423,-0.102),Vector3(-0.025,1.390,-0.145),Vector3(0.036,1.405,-0.137)],
		[0.008,0.007,0.007],Color("#66503d"),7)
	m.oval(Vector3(0.037,1.405,-0.139),Vector3(0.014,0.014,0.008),Color("#ad865b"))
	return m
