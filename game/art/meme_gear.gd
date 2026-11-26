extends RefCounted

const Sculpt := preload("res://game/art/equipment_sculpture.gd")
const INK := Color("#282633")
const PINK := Color("#ed94af")
const CREAM := Color("#f9d9aa")
const GOLD := Color("#ffcf35")
const AQUA := Color("#65ded9")
const RING_ARCS := 20
const RING_SIDES := 8
static var cache := {}

static func mesh(id: String) -> ArrayMesh:
	if cache.has(id): return cache[id]
	var m:=Sculpt.new(87)
	match id:
		"meme_shawl":
			_shawl(m)
		"meme_clock":
			m.bead(Vector3.ZERO,Vector3(0.146,0.155,0.049),GOLD)
			m.bead(Vector3(0,0,0.039),Vector3(0.127,0.135,0.024),CREAM)
			for i in 12:
				var tick:=Vector3(sin(i*TAU/12),cos(i*TAU/12),0)
				m.twig([tick*0.098+Vector3.BACK*0.064,tick*0.113+Vector3.BACK*0.064],[0.003,0.003],INK,4)
			m.twig([Vector3(-0.070,0.038,0.067),Vector3(0,0,0.068),Vector3(0.04,0.092,0.068)],[0.007,0.008,0.005],INK,7)
			for side:int in [-1,1]:
				m.bead(Vector3(side*0.107,0.144,0),Vector3(0.048,0.032,0.043),PINK,side*0.35)
				m.twig([Vector3(side*0.08,-0.106,0),Vector3(side*0.095,-0.163,0)],[0.01,0.014],INK,6)
		"meme_shades":
			for side in [-1,1]:
				var at:=Vector3(side*0.051,0,0)
				m.bead(at,Vector3(0.055,0.032,0.014),INK,side*0.08)
				m.bead(at+Vector3.FORWARD*0.009,Vector3(0.047,0.025,0.011),Color("#3a7690"),side*0.08)
				m.twig([at+Vector3(side*0.04,0,0),Vector3(side*0.122,0,0.045),Vector3(side*0.12,-0.012,0.13)],[0.005,0.005,0.004],INK)
			m.twig([Vector3(-0.017,0.006,0),Vector3(0,0.012,0),Vector3(0.017,0.006,0)],[0.006,0.005,0.006],INK)
		"meme_whiskers":
			m.bead(Vector3.ZERO,Vector3(0.019,0.011,0.011),PINK)
			for side in [-1,1]:
				for i in 3:
					m.twig([Vector3(side*0.023,-0.012,0.002),Vector3(side*0.064,-0.008+(i-1)*0.012,-0.005),Vector3(side*(0.11+i*0.008),(i-1)*0.024,0.001)],[0.0028,0.0023,0.0008],CREAM,5)
		"meme_ears":
			m.twig([Vector3(-0.127,-0.04,0),Vector3(-0.09,0.035,0),Vector3(0,0.058,0),Vector3(0.09,0.035,0),Vector3(0.127,-0.04,0)],[0.009,0.011,0.011,0.011,0.009],INK,5)
			for side in [-1,1]:
				var base:=Vector3(side*0.079,0.035,0)
				var tip:=Vector3(side*0.126,0.133,0.012)
				m.twig([base,base.lerp(tip,0.52),tip],[0.054,0.036,0.002],Color("#65475e"),5)
				m.triangle(base+Vector3(-0.033,0.01,-0.039),base+Vector3(0.033,0.01,-0.039),tip+Vector3(0,-0.019,-0.017),Vector3.FORWARD,PINK)
		"meme_tail":
			var path:=[Vector3.ZERO,Vector3(0.04,-0.13,0.18),Vector3(0.12,-0.24,0.29),Vector3(0.23,-0.20,0.35),Vector3(0.27,-0.08,0.34),Vector3(0.24,-0.018,0.31)]
			m.twig(path,[0.048,0.045,0.040,0.034,0.027,0.004],Color("#bd8453"),8)
			for i in range(1,5):
				m.twig([path[i].lerp(path[i-1],0.16),path[i],path[i].lerp(path[i+1],0.18)],[0.053-i*0.005,0.052-i*0.005,0.05-i*0.005],Color("#704f40"),8)
		"meme_traffic":
			m.loft([Vector4(0,0.18,0.17,0),Vector4(0.018,0.18,0.17,0)],Color("#bc4f29"),Vector3.ZERO,Basis.IDENTITY,8)
			var bands := [Vector2(0.016,0.133),Vector2(0.093,0.10),Vector2(0.135,0.079),Vector2(0.195,0.052),Vector2(0.225,0.039),Vector2(0.26,0.020)]
			for i in 12:
				var normal := Vector3(cos(TAU*(i+0.5)/12),0,sin(TAU*(i+0.5)/12))
				var next := normal.rotated(Vector3.UP,-TAU/12)
				for j in bands.size()-1:
					var low: Vector2 = bands[j]
					var high: Vector2 = bands[j+1]
					var a := Vector3.UP*low.x + normal*low.y
					var b := Vector3.UP*low.x + next*low.y
					var c := Vector3.UP*high.x + normal*high.y
					var d := Vector3.UP*high.x + next*high.y
					var tint := CREAM if j % 2 else Color("#ed7537")
					m.triangle(a,b,c,normal,tint)
					m.triangle(c,b,d,normal,tint)
					if j == bands.size()-2:
						m.triangle(Vector3.UP*high.x,c,d,Vector3.UP,tint)
		"meme_pot":
			m.loft([Vector4(0,0.17,0.17,0),Vector4(0.013,0.18,0.18,0),Vector4(0.035,0.15,0.15,0),Vector4(0.061,0.048,0.048,0)],Color("#93a6a9"))
			m.bead(Vector3(0,0.075,0),Vector3(0.03,0.02,0.03),INK)
			m.twig([Vector3(0.11,0,0),Vector3(0.23,0.014,0),Vector3(0.28,0.022,0)],[0.017,0.014,0.021],INK)
		"meme_antenna":
			m.loft([Vector4(-0.014,0.155,0.17,0.004),Vector4(0.012,0.16,0.174,0.006),Vector4(0.061,0.144,0.155,0.01),Vector4(0.095,0.094,0.10,0.012),Vector4(0.11,0.03,0.035,0.012)],Color("#4d676c"))
			for side in [-1,1]:
				var tip:=Vector3(side*0.118,0.207+(side+1)*0.025,0.028)
				m.twig([Vector3(side*0.058,0.035,0),tip],[0.011,0.003],Color("#afc7bb"))
				m.bead(tip,Vector3.ONE*0.018,AQUA if side<0 else PINK)
		"meme_duck":
			for i in RING_ARCS:
				for j in RING_SIDES:
					var a:=_ring(i,j)
					var b:=_ring(i+1,j)
					var c:=_ring(i,j+1)
					var d:=_ring(i+1,j+1)
					var theta:=TAU*(i+0.5)/RING_ARCS
					var phi:=TAU*(j+0.5)/RING_SIDES
					var normal:=Vector3(cos(theta)*cos(phi),sin(phi),sin(theta)*cos(phi))
					m.triangle(a,b,c,normal,GOLD)
					m.triangle(b,d,c,normal,GOLD)
			m.bead(Vector3(0,0.085,-0.245),Vector3(0.081,0.105,0.073),GOLD)
			m.bead(Vector3(0,0.072,-0.317),Vector3(0.057,0.025,0.056),Color("#ee7a3e"))
			for side in [-1,1]: m.bead(Vector3(side*0.049,0.119,-0.292),Vector3.ONE*0.012,INK)
		"meme_alien":
			m.loft([Vector4(-0.31,0.18,0.167,0),Vector4(-0.17,0.23,0.174,0),Vector4(0.03,0.282,0.184,0),Vector4(0.19,0.24,0.169,0),Vector4(0.23,0.10,0.116,0)],Color("#7dbbb2"))
			m.bead(Vector3(0,0.035,-0.167),Vector3(0.118,0.129,0.047),Color("#b3e881"))
			for side in [-1,1]:
				m.bead(Vector3(side*0.051,0.06,-0.206),Vector3(0.039,0.020,0.01),INK,side*0.45)
				m.bead(Vector3(side*0.233,0.17,0),Vector3(0.103,0.076,0.17),Color("#665b86"))
		"meme_fins":
			m.bead(Vector3(0,-0.052,-0.088),Vector3(0.085,0.049,0.171),Color("#70a6a7"))
			for side in [-1,1]:
				m.twig([Vector3(0,-0.053,-0.18),Vector3(side*0.064,-0.052,-0.25),Vector3(side*0.088,-0.038,-0.28)],[0.035,0.028,0.002],Color("#d98e79"),5)
				m.bead(Vector3(side*0.068,-0.04,-0.05),Vector3.ONE*0.012,INK)
		"meme_claws":
			m.bead(Vector3(0,-0.035,-0.018),Vector3(0.061,0.079,0.064),CREAM)
			m.bead(Vector3(0,-0.044,-0.076),Vector3(0.032,0.032,0.013),PINK)
			for i in 4:
				var at:=Vector3((i-1.5)*0.024,-0.093-0.006*sin(i),-0.040)
				m.bead(at,Vector3(0.018,0.026,0.022),CREAM)
				m.bead(at+Vector3(0,-0.005,-0.018),Vector3(0.010,0.014,0.007),PINK)
		"meme_hammer":
			m.twig([Vector3(0,-0.15,0),Vector3.ZERO,Vector3(0,0.38,0)],[0.037,0.032,0.047],AQUA,8)
			m.twig([Vector3(-0.21,0.39,0),Vector3(-0.17,0.39,0),Vector3(0.17,0.39,0),Vector3(0.21,0.39,0)],[0.10,0.13,0.13,0.10],PINK,12)
			for side in [-1,1]:
				m.twig([Vector3(side*0.165,0.39,0),Vector3(side*0.202,0.39,0)],[0.138,0.129],GOLD,12)
	cache[id]=m.commit()
	return cache[id]

static func _shawl(m: Sculpt) -> void:
	const PANELS := 16
	var wool := Color("#9d879e")
	var lining := Color("#533f5d")
	var trim := Color("#e6aa69")
	var rows: Array[PackedVector3Array] = []
	for drop: float in [0.0, 0.18, 0.58, 0.68, 0.86, 0.93, 1.0]:
		var row := PackedVector3Array()
		for i in PANELS + 1:
			var angle := lerpf(-2.52, 2.52, float(i) / PANELS)
			var drape := clampf(drop / 0.22, 0.0, 1.0)
			var back := (1.0 + cos(angle)) * 0.5
			var pleat := cos(angle * 10.0) * drop * 0.009
			var width := lerpf(0.14, 0.293, drape) - 0.032 * drop
			var depth := lerpf(0.123, 0.201, drape) + 0.035 * drop
			var length := 0.125 + 0.33 * pow(back, 1.8)
			var y := -drop * length
			if drop == 0.58 or drop == 0.68:
				y += 0.024 if i % 2 == 0 else -0.008
			row.append(Vector3(sin(angle) * (width + pleat), y, cos(angle) * (depth + pleat)))
		if not rows.is_empty():
			var previous: PackedVector3Array = rows.back()
			var dye := trim if drop == 0.68 or drop == 0.93 else wool
			for i in PANELS:
				var outside := Vector3(row[i].x, 0.04, row[i].z).normalized()
				m.triangle(previous[i], row[i], row[i+1], outside, dye)
				m.triangle(previous[i], row[i+1], previous[i+1], outside, dye)
				var inset := outside * 0.003
				m.triangle(previous[i]-inset, row[i]-inset, row[i+1]-inset, -outside, lining)
				m.triangle(previous[i]-inset, row[i+1]-inset, previous[i+1]-inset, -outside, lining)
		rows.append(row)
	var hem: PackedVector3Array = rows.back()
	for i in range(1, PANELS):
		var at := hem[i]
		var tip := at + Vector3(sin(i * 1.6) * 0.008, -0.031 - 0.008 * (i % 3), 0.004)
		m.twig([at, tip], [0.006, 0.002], trim, 4)
	var collar := rows[0]
	var collar_path := PackedVector3Array()
	for i in range(0, PANELS + 1, 2):
		collar_path.append(collar[i])
	var collar_widths := PackedFloat32Array()
	collar_widths.resize(collar_path.size())
	collar_widths.fill(0.011)
	m.tube(collar_path, collar_widths, 5, trim)
	var clasp := Vector3(0, -0.083, -0.176)
	for end: Vector3 in [collar[0], collar[PANELS]]:
		m.twig([end, end.lerp(clasp, 0.5) + Vector3.FORWARD * 0.014, clasp], [0.008, 0.007, 0.006], trim, 6)
	m.bead(clasp, Vector3(0.022, 0.020, 0.010), GOLD)

static func _ring(i:int,j:int)->Vector3:
	var a:=TAU*i/RING_ARCS
	var b:=TAU*j/RING_SIDES
	return Vector3(cos(a)*(0.263+0.083*cos(b)),0.083*sin(b),sin(a)*(0.219+0.083*cos(b)))
