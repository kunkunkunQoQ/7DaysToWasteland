extends RefCounted

const IRON := Color("#4d5058")
const DARK := Color("#343039")
const WORN := Color("#a7a59a")
const WOOD := Color("#9c6c46")
const OCHRE := Color("#bd8a4c")
const COPPER := Color("#b47251")
const CERAMIC := Color("#d2cab0")
const GREEN := Color("#719b86")
const LIVE := Color("#f7bd69")

static func mesh(id: String, accent: Color, active: bool) -> Mesh:
	var parts: Array = []
	match id:
		"campfire", "forge", "bench", "chemistry":
			_workshop(parts, id, accent, active)
		"generator", "battery", "solar", "floodlight":
			_power(parts, id, accent, active)
		"spikes", "barbed", "fence", "mine", "turret", "blade":
			_defense(parts, id, accent, active)
	return WastelandLook.mesh_parts(parts)

static func _part(parts: Array, center: Vector3, size: Vector3, color: Color, top := 1.0, basis := Basis.IDENTITY) -> void:
	parts.append([center, size, color, basis, top])

static func _bar(parts: Array, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var delta := b - a
	_part(parts, (a + b) * 0.5, Vector3(width, delta.length(), width), color, 1.0, Basis(Quaternion(Vector3.UP, delta.normalized())))

static func _workshop(p: Array, id: String, accent: Color, active: bool) -> void:
	match id:
		"campfire":
			for i in 8:
				var angle := i * TAU / 8
				_part(p, Vector3(cos(angle)*0.34,-0.41,sin(angle)*0.34), Vector3(0.23,0.17,0.21), IRON.lightened((i%3)*0.06), 0.69, Basis(Vector3.UP,angle))
			for k in [-1, 1]:
				_part(p, Vector3(k*0.075,-0.33,0),Vector3(0.12,0.12,0.52),DARK,0.82,Basis(Vector3.UP,k*0.74))
			if active:
				for i in 3:
					_part(p,Vector3((i-1)*0.10,-0.17,0.07*(i%2)),Vector3(0.16,0.29+0.12*(i%2),0.15),LIVE.lerp(Color("#e17845"),i*0.34),0.08,Basis(Vector3.FORWARD,(i-1)*0.23))
		"forge":
			_part(p,Vector3(0,-0.38,0),Vector3(0.89,0.23,0.82),IRON)
			_part(p,Vector3(0,-0.11,-0.08),Vector3(0.77,0.47,0.58),accent,0.84)
			for x in [-0.30,0.30]:
				_part(p,Vector3(x,-0.15,0.27),Vector3(0.16,0.32,0.19),COPPER)
			_part(p,Vector3(0,0.02,0.27),Vector3(0.74,0.10,0.19),WORN)
			_part(p,Vector3(0,-0.17,0.226),Vector3(0.44,0.20,0.04),LIVE if active else DARK)
			for x in [-0.13,0.0,0.13]:
				_part(p,Vector3(x,-0.20,0.25),Vector3(0.034,0.14,0.03),IRON)
			_part(p,Vector3(-0.17,0.20,-0.14),Vector3(0.22,0.40,0.22),IRON,0.84)
			_part(p,Vector3(-0.17,0.40,-0.14),Vector3(0.26,0.055,0.26),DARK)
		"bench", "chemistry":
			for x in [-0.37,0.37]:
				for z in [-0.32,0.32]:
					_part(p,Vector3(x,-0.15,z),Vector3(0.09,0.69,0.10),IRON if id=="chemistry" else WOOD)
			_part(p,Vector3(0,-0.32,0),Vector3(0.81,0.07,0.67),IRON)
			_part(p,Vector3(0,0.15,0),Vector3(0.95,0.11,0.83),accent)
			if id=="bench":
				_part(p,Vector3(0.18,-0.005,0.09),Vector3(0.43,0.19,0.48),WOOD)
				_part(p,Vector3(0.18,-0.025,0.34),Vector3(0.15,0.035,0.034),WORN)
				_part(p,Vector3(-0.25,0.245,0.18),Vector3(0.29,0.085,0.2),IRON)
				for x in [-0.34,-0.16]:
					_part(p,Vector3(x,0.32,0.18),Vector3(0.065,0.12,0.21),WORN)
				_bar(p,Vector3(0.01,0.223,-0.22),Vector3(0.37,0.223,-0.02),0.046,COPPER)
			else:
				for i in 3:
					var pos := Vector3((i-1)*0.22,0.283,0.13*(i%2))
					_part(p,pos,Vector3(0.15,0.15,0.15),GREEN.lightened(i*0.09),0.62)
					_part(p,pos+Vector3.UP*0.11,Vector3(0.052,0.094,0.052),CERAMIC)
				_part(p,Vector3(0,0.31,-0.30),Vector3(0.70,0.21,0.055),IRON)
				_part(p,Vector3(-0.1,0.33,-0.26),Vector3(0.33,0.075,0.032),CERAMIC)

static func _power(p: Array, id: String, accent: Color, active: bool) -> void:
	var signal_color := LIVE if active else DARK
	match id:
		"solar":
			_part(p,Vector3(0,-0.45,0),Vector3(0.57,0.09,0.47),IRON)
			_part(p,Vector3(0,-0.23,0),Vector3(0.15,0.42,0.14),WORN)
			var slope := Basis(Vector3.RIGHT,0.32)
			var origin := Vector3(0,0.04,0)
			_part(p,origin,Vector3(0.93,0.062,0.78),WORN,1.0,slope)
			for x in [-0.29,0.0,0.29]:
				for z in [-0.175,0.175]:
					_part(p,origin+slope*Vector3(x,0.040,z),Vector3(0.264,0.022,0.319),accent.darkened(0.22),1.0,slope)
		"generator":
			for x in [-0.32,0.32]:
				_part(p,Vector3(x,-0.45,0),Vector3(0.10,0.09,0.80),IRON)
			_part(p,Vector3(0,-0.29,0),Vector3(0.78,0.27,0.67),accent)
			_part(p,Vector3(-0.12,-0.045,0),Vector3(0.45,0.28,0.54),IRON)
			for z in [-0.15,-0.05,0.05,0.15]:
				_part(p,Vector3(-0.12,0.077,z),Vector3(0.49,0.077,0.043),WORN)
			_part(p,Vector3(0.24,0.03,0),Vector3(0.20,0.37,0.44),OCHRE,0.90)
			_part(p,Vector3(0.24,0.244,-0.09),Vector3(0.096,0.061,0.096),DARK)
			_part(p,Vector3(0.20,-0.24,0.35),Vector3(0.12,0.064,0.028),signal_color)
		"battery":
			_part(p,Vector3(0,-0.42,0),Vector3(0.90,0.13,0.69),IRON)
			for x in [-0.24,0.0,0.24]:
				_part(p,Vector3(x,-0.14,0),Vector3(0.218,0.45,0.57),accent)
				_part(p,Vector3(x,0.104,0),Vector3(0.23,0.084,0.59),DARK)
				for z in [-0.16,0.16]:
					_part(p,Vector3(x,0.17,z),Vector3(0.084,0.084,0.084),COPPER if z>0 else WORN)
			_part(p,Vector3(0,0.213,-0.16),Vector3(0.56,0.035,0.052),WORN)
			_part(p,Vector3(0,-0.13,0.294),Vector3(0.13,0.075,0.027),signal_color)
		"floodlight":
			_part(p,Vector3(0,-0.45,0),Vector3(0.66,0.10,0.61),IRON)
			_part(p,Vector3(0,-0.17,0),Vector3(0.105,0.50,0.105),WORN)
			_part(p,Vector3(0,0.07,0),Vector3(0.68,0.064,0.078),OCHRE)
			for x in [-0.21,0.21]:
				_part(p,Vector3(x,0.22,0),Vector3(0.35,0.28,0.18),IRON)
				_part(p,Vector3(x,0.22,-0.097),Vector3(0.29,0.212,0.032),Color("#fff3bd") if active else Color("#9e9f96"))
				_part(p,Vector3(x,0.377,-0.04),Vector3(0.38,0.033,0.24),accent)

static func _defense(p: Array, id: String, accent: Color, active: bool) -> void:
	match id:
		"spikes":
			for x in [-0.29,0.29]:
				_part(p,Vector3(x,-0.44,0),Vector3(0.15,0.11,0.80),WOOD)
			for i in 5:
				_part(p,Vector3((i-2)*0.16,-0.19,(i%2)*0.38-0.19),Vector3(0.15,0.59,0.17),accent.lightened(i%3*0.07),0.07,Basis(Vector3.RIGHT,(i%2-0.5)*0.40))
		"barbed", "fence":
			for x in [-0.37,0.37]:
				_part(p,Vector3(x,-0.46,0),Vector3(0.17,0.07,0.38),IRON)
				_part(p,Vector3(x,-0.18,0),Vector3(0.083,0.59,0.087),IRON)
				if id=="fence":
					for y in [-0.25,-0.04]:
						_part(p,Vector3(x,y,0),Vector3(0.12,0.083,0.12),CERAMIC)
			if id=="fence":
				for y in [-0.25,-0.04]:
					_part(p,Vector3(0,y,0),Vector3(0.75,0.026,0.032),LIVE if active else COPPER)
			else:
				var last := Vector3(-0.37,-0.18,0.115)
				for i in range(1,17):
					var angle := i*PI/2.0
					var point := Vector3(-0.37+0.74*i/16.0,-0.18+sin(angle)*0.16,cos(angle)*0.115)
					_bar(p,last,point,0.022,WORN)
					last=point
		"mine":
			_part(p,Vector3(0,-0.425,0),Vector3(0.55,0.14,0.55),IRON,0.79)
			_part(p,Vector3(0,-0.337,0),Vector3(0.36,0.062,0.36),accent,0.85)
			_part(p,Vector3(0,-0.298,0),Vector3(0.18,0.021,0.17),OCHRE)
		"blade", "turret":
			_part(p,Vector3(0,-0.43,0),Vector3(0.78,0.14,0.70),IRON,0.84)
			_part(p,Vector3(0,-0.14,0),Vector3(0.22,0.47,0.21),accent)
			_part(p,Vector3(0,-0.19,0.117),Vector3(0.086,0.06,0.028),LIVE if active else DARK)
			if id=="blade":
				for i in 3:
					var spin := Basis(Vector3.UP,TAU*i/3)
					_part(p,spin*Vector3(0.20,0.13,0.047),Vector3(0.37,0.042,0.13),WORN,0.73,spin)
				_part(p,Vector3(0,0.15,0),Vector3(0.195,0.11,0.19),OCHRE,0.78)
			else:
				_part(p,Vector3(0,0.16,0),Vector3(0.47,0.25,0.43),accent,0.80)
				_part(p,Vector3(0,0.17,-0.295),Vector3(0.13,0.122,0.36),IRON)
				_part(p,Vector3(0.14,0.205,-0.20),Vector3(0.075,0.069,0.044),GREEN)
