extends WastelandScenery

static func harvest_mesh(kind: String, variant: int, detailed: bool) -> ArrayMesh:
	var model= new(641+variant*131)
	match kind:
		"herb_patch": model.herbs(detailed)
		"reed_bed": model.reeds(detailed)
		"iron_vein": model.iron(detailed)
		"machine_wreck": model.machine(detailed)
	return model.commit()

func herbs(detail: bool) -> void:
	for i in (9 if detail else 5):
		var a := i*2.4+rng.randf()*0.35
		var direction := Vector3(cos(a),0,sin(a))
		var base := direction*rng.randf_range(0.10,0.34)
		var crown := base+Vector3.UP*rng.randf_range(0.31,0.58)
		tube([base,crown],[0.016,0.009],4,Color("#789052"))
		foliage_blade(base,a,0.26,0.18,0.17,Color("#638d61"))
		for j in (4 if detail else 2):
			var offset := Vector3(cos(j*1.57),0,sin(j*1.57))*0.044
			lobe(crown+offset,Vector3(0.050,0.034,0.051),Color("#ccb1d4"),a,false)
		lobe(crown+Vector3.UP*0.025,Vector3(0.035,0.03,0.035),Color("#e3b668"),a,false)

func reeds(detail: bool) -> void:
	for i in (12 if detail else 6):
		var a := i*2.4
		var direction := Vector3(cos(a),0,sin(a))
		var base := direction*rng.randf_range(0.11,0.39)
		var neck := base+Vector3.UP*rng.randf_range(0.70,1.15)+direction*0.07
		tube([base,neck,neck+Vector3.UP*0.19],[0.018,0.013,0.006],4,Color("#c9a660"))
		tube([neck,neck+Vector3.UP*0.13,neck+Vector3.UP*0.17],[0.032,0.037,0.020],5,Color("#854e35"))
		foliage_blade(base,a+0.33,neck.y*0.75,0.083,0.21,Color("#a5a35f"))

func iron(detail: bool) -> void:
	lobe(Vector3(0,0.31,0),Vector3(0.70,0.54,0.57),Color("#59565c"),0,detail)
	for i in (9 if detail else 4):
		var a := i*2.4
		var p := Vector3(cos(a)*0.47,0.50+0.23*sin(i*2.13),sin(a)*0.39)
		lobe(p,Vector3(0.20,0.13,0.135),Color("#bc7150"),a,false)
		if detail:
			lobe(p+Vector3.UP*0.073,Vector3(0.12,0.07,0.09),Color("#a9b2b1"),a,false)

func machine(detail: bool) -> void:
	var teal := Color("#547970")
	var rust := Color("#aa6950")
	box(Vector3(0,0.13,0),Vector3(1.18,0.22,0.80),rust)
	box(Vector3(-0.18,0.47,0),Vector3(0.64,0.54,0.57),teal)
	tube([Vector3(0.1,0.38,0),Vector3(0.47,0.38,0)],[0.26,0.25],8,Color("#525861"))
	for i in (5 if detail else 3):
		var x := 0.14+i*0.072
		tube([Vector3(x,0.38,0),Vector3(x+0.024,0.38,0)],[0.28,0.28],8,rust)
	tube([Vector3(-0.41,0.71,0.10),Vector3(-0.41,0.98,0.10),Vector3(-0.22,0.98,0.10)],[0.056,0.056,0.046],6,Color("#817966"))
	if detail:
		for i in 5:
			box(Vector3(-0.18,0.38+i*0.056,-0.30),Vector3(0.36,0.023,0.035),Color("#394b4c"))

func box(center: Vector3, size: Vector3, tint: Color) -> void:
	for normal in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
		var u: Vector3=Vector3.RIGHT if absf(normal.y)>0.5 else Vector3.UP
		var v: Vector3=normal.cross(u)
		var c: Vector3=center+normal*size*0.5
		u=u*size*0.5
		v=v*size*0.5
		triangle(c-u-v,c+u-v,c+u+v,normal,tint)
		triangle(c-u-v,c+u+v,c-u+v,normal,tint)
