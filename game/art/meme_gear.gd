extends RefCounted

const Sculpt := WastelandBestiary.Sculpture
const INK := Color("#282633")
const PINK := Color("#ed94af")
const CREAM := Color("#f9d9aa")
const GOLD := Color("#ffcf35")
const AQUA := Color("#65ded9")
static var cache := {}

static func mesh(id: String) -> ArrayMesh:
	if cache.has(id): return cache[id]
	var m:=Sculpt.new(87)
	match id:
		"meme_clock":
			m.oval(Vector3.ZERO,Vector3(0.146,0.155,0.049),GOLD)
			m.oval(Vector3(0,0,0.039),Vector3(0.127,0.135,0.024),CREAM)
			for i in 12:
				var tick:=Vector3(sin(i*TAU/12),cos(i*TAU/12),0)
				m.twig([tick*0.098+Vector3.BACK*0.064,tick*0.113+Vector3.BACK*0.064],[0.003,0.003],INK,5)
			m.twig([Vector3(-0.070,0.038,0.067),Vector3(0,0,0.068),Vector3(0.04,0.092,0.068)],[0.007,0.008,0.005],INK,7)
			for side:int in [-1,1]:
				m.oval(Vector3(side*0.107,0.144,0),Vector3(0.048,0.032,0.043),PINK,side*0.35)
				m.twig([Vector3(side*0.08,-0.106,0),Vector3(side*0.095,-0.163,0)],[0.01,0.014],INK,6)
		"meme_shades":
			for side in [-1,1]:
				var at:=Vector3(side*0.051,0,0)
				m.oval(at,Vector3(0.055,0.032,0.014),INK,side*0.08)
				m.oval(at+Vector3.FORWARD*0.009,Vector3(0.047,0.025,0.011),Color("#3a7690"),side*0.08)
				m.twig([at+Vector3(side*0.04,0,0),Vector3(side*0.122,0,0.045),Vector3(side*0.12,-0.012,0.13)],[0.005,0.005,0.004],INK)
			m.twig([Vector3(-0.017,0.006,0),Vector3(0,0.012,0),Vector3(0.017,0.006,0)],[0.006,0.005,0.006],INK)
		"meme_whiskers":
			m.oval(Vector3.ZERO,Vector3(0.019,0.011,0.011),PINK)
			for side in [-1,1]:
				for i in 3:
					m.twig([Vector3(side*0.023,-0.012,0.002),Vector3(side*0.064,-0.008+(i-1)*0.012,-0.005),Vector3(side*(0.11+i*0.008),(i-1)*0.024,0.001)],[0.0028,0.0023,0.0008],CREAM,5)
		"meme_ears":
			m.twig([Vector3(-0.127,-0.04,0),Vector3(-0.09,0.035,0),Vector3(0,0.058,0),Vector3(0.09,0.035,0),Vector3(0.127,-0.04,0)],[0.009,0.011,0.011,0.011,0.009],INK)
			for side in [-1,1]:
				var base:=Vector3(side*0.079,0.035,0)
				var tip:=Vector3(side*0.126,0.133,0.012)
				m.twig([base,base.lerp(tip,0.52),tip],[0.054,0.036,0.002],Color("#65475e"),5)
				m.triangle(base+Vector3(-0.033,0.01,-0.039),base+Vector3(0.033,0.01,-0.039),tip+Vector3(0,-0.019,-0.017),Vector3.FORWARD,PINK)
		"meme_tail":
			var path:=[Vector3.ZERO,Vector3(0.04,-0.13,0.18),Vector3(0.12,-0.24,0.29),Vector3(0.23,-0.20,0.35),Vector3(0.27,-0.08,0.34),Vector3(0.24,-0.018,0.31)]
			m.twig(path,[0.048,0.045,0.040,0.034,0.027,0.004],Color("#bd8453"),10)
			for i in range(1,5):
				m.twig([path[i].lerp(path[i-1],0.16),path[i],path[i].lerp(path[i+1],0.18)],[0.053-i*0.005,0.052-i*0.005,0.05-i*0.005],Color("#704f40"),10)
		"meme_traffic":
			m.loft([Vector4(0,0.18,0.17,0),Vector4(0.018,0.18,0.17,0)],Color("#bc4f29"),Vector3.ZERO,Basis.IDENTITY,8)
			for row in [[0.016,0.133,0.093,0.10],[0.093,0.10,0.135,0.079],[0.135,0.079,0.195,0.052],[0.195,0.052,0.225,0.039],[0.225,0.039,0.26,0.020]]:
				m.loft([Vector4(row[0],row[1],row[1],0),Vector4(row[2],row[3],row[3],0)],CREAM if row[0] in [0.093,0.195] else Color("#ed7537"))
		"meme_pot":
			m.loft([Vector4(0,0.17,0.17,0),Vector4(0.013,0.18,0.18,0),Vector4(0.035,0.15,0.15,0),Vector4(0.061,0.048,0.048,0)],Color("#93a6a9"))
			m.oval(Vector3(0,0.075,0),Vector3(0.03,0.02,0.03),INK)
			m.twig([Vector3(0.11,0,0),Vector3(0.23,0.014,0),Vector3(0.28,0.022,0)],[0.017,0.014,0.021],INK)
		"meme_antenna":
			m.loft([Vector4(-0.014,0.155,0.17,0.004),Vector4(0.012,0.16,0.174,0.006),Vector4(0.061,0.144,0.155,0.01),Vector4(0.095,0.094,0.10,0.012),Vector4(0.11,0.03,0.035,0.012)],Color("#4d676c"))
			for side in [-1,1]:
				var tip:=Vector3(side*0.118,0.207+(side+1)*0.025,0.028)
				m.twig([Vector3(side*0.058,0.035,0),tip],[0.011,0.003],Color("#afc7bb"))
				m.oval(tip,Vector3.ONE*0.018,AQUA if side<0 else PINK)
		"meme_duck":
			for i in 28:
				for j in 12:
					var a:=_ring(i,j)
					var b:=_ring(i+1,j)
					var c:=_ring(i,j+1)
					var d:=_ring(i+1,j+1)
					var theta:=TAU*(i+0.5)/28
					var phi:=TAU*(j+0.5)/12
					var normal:=Vector3(cos(theta)*cos(phi),sin(phi),sin(theta)*cos(phi))
					m.triangle(a,b,c,normal,GOLD)
					m.triangle(b,d,c,normal,GOLD)
			m.oval(Vector3(0,0.085,-0.245),Vector3(0.081,0.105,0.073),GOLD)
			m.oval(Vector3(0,0.072,-0.317),Vector3(0.057,0.025,0.056),Color("#ee7a3e"))
			for side in [-1,1]: m.oval(Vector3(side*0.049,0.119,-0.292),Vector3.ONE*0.012,INK)
		"meme_alien":
			m.loft([Vector4(-0.31,0.18,0.167,0),Vector4(-0.17,0.23,0.174,0),Vector4(0.03,0.282,0.184,0),Vector4(0.19,0.24,0.169,0),Vector4(0.23,0.10,0.116,0)],Color("#7dbbb2"))
			m.oval(Vector3(0,0.035,-0.167),Vector3(0.118,0.129,0.047),Color("#b3e881"))
			for side in [-1,1]:
				m.oval(Vector3(side*0.051,0.06,-0.206),Vector3(0.039,0.020,0.01),INK,side*0.45)
				m.oval(Vector3(side*0.233,0.17,0),Vector3(0.103,0.076,0.17),Color("#665b86"))
		"meme_fins":
			m.oval(Vector3(0,-0.052,-0.088),Vector3(0.085,0.049,0.171),Color("#70a6a7"))
			for side in [-1,1]:
				m.twig([Vector3(0,-0.053,-0.18),Vector3(side*0.064,-0.052,-0.25),Vector3(side*0.088,-0.038,-0.28)],[0.035,0.028,0.002],Color("#d98e79"),5)
				m.oval(Vector3(side*0.068,-0.04,-0.05),Vector3.ONE*0.012,INK)
		"meme_claws":
			m.oval(Vector3(0,-0.035,-0.018),Vector3(0.061,0.079,0.064),CREAM)
			m.oval(Vector3(0,-0.044,-0.076),Vector3(0.032,0.032,0.013),PINK)
			for i in 4:
				var at:=Vector3((i-1.5)*0.024,-0.093-0.006*sin(i),-0.040)
				m.oval(at,Vector3(0.018,0.026,0.022),CREAM)
				m.oval(at+Vector3(0,-0.005,-0.018),Vector3(0.010,0.014,0.007),PINK)
		"meme_hammer":
			m.twig([Vector3(0,-0.15,0),Vector3.ZERO,Vector3(0,0.38,0)],[0.037,0.032,0.047],AQUA,12)
			m.twig([Vector3(-0.21,0.39,0),Vector3(-0.17,0.39,0),Vector3(0.17,0.39,0),Vector3(0.21,0.39,0)],[0.10,0.13,0.13,0.10],PINK,14)
			for side in [-1,1]:
				m.twig([Vector3(side*0.165,0.39,0),Vector3(side*0.202,0.39,0)],[0.138,0.129],GOLD,14)
	cache[id]=m.commit()
	return cache[id]

static func _ring(i:int,j:int)->Vector3:
	var a:=TAU*i/28
	var b:=TAU*j/12
	return Vector3(cos(a)*(0.263+0.083*cos(b)),0.083*sin(b),sin(a)*(0.219+0.083*cos(b)))
