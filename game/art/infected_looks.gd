extends RefCounted

const FORMS := {
	"bloater": [
		["旧工衫", "鬓发稀疏，褪蓝工衫的口袋歪在胸前，一侧下摆被肚腹顶起。"],
		["旧开衫", "松垮的灰红开衫露出内衣，头发在后颈扎成一个小髻。"],
		["棉背心", "针织帽垂在脑后，橄榄色棉背心下露出灰褐的长袖。"]],
	"bulwark": [
		["铆门盾", "两片带铆钉的蓝钢护板扣在前臂上，边角露出亮色底钢。"],
		["道钉盾", "黄黑条纹的长护轨压过手背，中间的钢脊首先迎向撞击。"],
		["龟背盾", "铜绿甲片叠成两面短圆盾，肩头和帽顶也鼓起同样的硬壳。"]],
	"rimecaller": [
		["双叉晶", "肩上的霜枝分出成对的晶叉，青白尖端之间留着空隙。"],
		["霜羽扇", "薄冰从一侧肩胛向上铺成扇面，披肩边缘也凝着白霜。"],
		["垂冰冠", "弯曲的晶枝从两肩拱起，末端垂下长短不一的冰锥。"]],
	"spitter": [
		["短檐帽", "软帽檐压着一侧眉梢，灰绿色巡防衬衫的袖子卷到肘下。"],
		["翻领夹克", "两鬓剃短，褪蓝夹克敞着领口，左胸还留着磨白的口袋翻盖。"],
		["旧雨衣", "泥褐色雨帽垂到耳际，肩后的挡雨布有一边开了线。"]],
	"sandrunner": [
		["风尾巾", "两条靛青巾尾从琥珀头巾后方甩出，一直垂到肩后。"],
		["沙帆兜", "兜帽两侧垂下宽布护耳，摩旧的红边露在沙色外层下面。"],
		["驿路客", "行囊上横捆着布卷，斜过胸口的肩带勒住了后扬的红披巾。"]]}

# Surface finish is encoded in the alpha channel of opaque vertex colors.
const LEATHER := Color("#6d463523")
const CANVAS := Color("#c9a47108")
const INDIGO := Color("#435e6808")
const VERMILION := Color("#ab503408")
const IRON := Color("#435662bc")
const STEEL := Color("#a4b6b9e6")
const BRASS := Color("#d5a357c9")
const RUBBER := Color("#383e4224")
const CIVILIAN_COATS := {
	"spitter": [Color("#6e7762"),Color("#64747c"),Color("#807765")],
	"bloater": [Color("#70818a"),Color("#846d69"),Color("#70735b")]
}

const FROST := Color("#a9e4eaf1")
const BLUE_ICE := Color("#639faedb")

static func coat_for(kind:String,look:int)->Color:
	return CIVILIAN_COATS[kind][look]

static func count_for(kind: String) -> int:
	return FORMS[kind].size() if FORMS.has(kind) else 0

static func title(kind: String, index: int) -> String:
	return FORMS[kind][posmod(index, count_for(kind))][0] if FORMS.has(kind) else ""

static func description(kind: String, index: int) -> String:
	return FORMS[kind][posmod(index, count_for(kind))][1] if FORMS.has(kind) else ""

static func joints_for(kind: String) -> Array:
	if kind in ["spitter","bloater"]: return ["torso","head","elbow_l","elbow_r"]
	if kind == "rimecaller": return ["torso","elbow_l"]
	if kind == "sandrunner":
		return ["torso","head","arm_l","elbow_r","knee_l","knee_r"]
	return ["torso","head","elbow_l","elbow_r"] if kind == "bulwark" else ["torso","head","elbow_l"]

static func skin_for(kind: String, skin: Color) -> Color:
	match kind:
		"sandrunner": return Color("#a3a184")
		"bloater": return Color("#9b8672")
		"bulwark": return Color("#9f958c")
		"spitter": return Color("#b1ad90")
		"rimecaller": return Color("#a4b9bd")
	return skin

static func sculpt(s, kind: String, look: int, joint: String) -> void:
	if kind in ["spitter","bloater"]:
		_civilian(s,kind,look,joint)
		return
	if joint == "torso":
		_torn_uniform(s, kind, look)
	elif joint != "head" and kind != "bulwark":
		_infected_limb(s, kind, look, joint)
		return
	match kind:
		"bulwark": _bulwark(s, look, joint)
		"rimecaller": _rimecaller(s, look)
		"sandrunner": _sandrunner(s, look, joint)

static func _torn_uniform(s, kind: String, look: int) -> void:
	var cloth := INDIGO if kind in ["bulwark","rimecaller"] else CANVAS if kind == "sandrunner" else LEATHER
	var side := -1.0 if look == 1 else 1.0
	var x := side*(0.184 if kind != "rimecaller" else 0.159)
	var lining := Color("#57434540") if kind != "rimecaller" else Color("#50697535")
	# A broken side seam exposes three ribs, with the shirt still hanging from its upper edge.
	_plate(s,Vector3(x,0.186,-0.127),Vector3(0.061,0.107,0.027),lining,cloth,side*0.22)
	for i in 3:
		var root := Vector3(x-side*0.032,0.135+i*0.041,-0.164)
		s.twig([root,root+Vector3(side*0.051,0.016,0.011),root+Vector3(side*0.074,0.038,0.035)],[0.007,0.011,0.005],Color("#b39f8664"),5)
	for i in 3:
		var root := Vector3(side*(0.095+i*0.061),0.041,-0.134+i*0.025)
		_ribbon(s,[root,root+Vector3(side*0.018,-0.119,0.006),
			root+Vector3(side*(0.023+i*0.011),-0.237-(i%2)*0.092,0.047)],[0.046,0.037,0.005],Vector3.RIGHT,cloth.darkened(0.11*i))

static func _infected_limb(s, kind: String, look: int, joint: String) -> void:
	var sand := kind == "sandrunner"
	var bone := Color("#d1c29d79") if not kind == "rimecaller" else BLUE_ICE
	if joint.begins_with("knee"):
		var side := -1.0 if joint == "knee_l" else 1.0
		# Long swept splints make the lean shin and forward-facing kneecap read together.
		_plate(s,Vector3(0,-0.016,-0.072),Vector3(0.084,0.108,0.037),Color("#99896672"),bone,side*0.21)
		s.twig([Vector3(side*0.044,-0.175,-0.046),Vector3(side*0.083,-0.136,0.042),
			Vector3(side*0.104,-0.053,0.154)],[0.038,0.027,0.003],bone,5)
		for h: float in [-0.243,-0.177]:
			s.loft([Vector4(h,0.077,0.099,0.025),Vector4(h+0.027,0.078,0.099,0.025)],LEATHER)
		return
	if joint == "arm_l":
		var cloth: Color = [INDIGO,CANVAS,VERMILION][look]
		s.oval(Vector3(-0.054,0.003,0.011),Vector3(0.129,0.103,0.135),cloth,-0.36)
		for i in 3:
			var at := Vector3(-0.09,i*0.025-0.054,0.035+i*0.025)
			s.twig([at,at+Vector3(-0.072,0.054,0.038),at+Vector3(-0.111,0.118,0.105+i*0.016)],[0.035,0.026,0.002],bone,5)
		return
	var side := 1.0 if joint == "elbow_r" else -1.0
	var at := Vector3(side*0.04,-0.12,-0.061)
	s.oval(at,Vector3(0.053,0.112,0.039),Color("#78595950"),side*-0.23)
	for i in 2:
		var root := at+Vector3(side*0.022,i*0.071-0.039,0.03)
		var tip := root+Vector3(side*(0.096 if sand else 0.066),0.107+i*0.018,0.111)
		s.twig([root,root.lerp(tip,0.51)+Vector3(side*0.017,0,0),tip],[0.031,0.023,0.002],bone,5)

# Unit-sized mesh in the tell's animated local space. Seams, roots and lobes
# expand together as the actor's existing attack pose scales this attachment.
static func sculpt_gland(s, kind: String, look: int) -> void:
	match kind:
		"bloater":
			# The lower shirt front closes against the torso at its hem, sides and chest.
			# Its long folds deform with the underlying abdomen during the fuse.
			var cloth:=coat_for(kind,look)
			s.loft([Vector4(-0.45,0.27,0.23,0.16),Vector4(-0.37,0.42,0.39,0.045),
				Vector4(-0.17,0.48,0.52,0.03),Vector4(0.04,0.48,0.55,0.048),
				Vector4(0.24,0.43,0.39,0.08),Vector4(0.46,0.32,0.25,0.15)],cloth,
				Vector3.ZERO,Basis(Vector3.BACK,-0.065+look*0.021),20)
			s.twig([Vector3(-0.34,-0.21,-0.30),Vector3(-0.19,-0.29,-0.412),
				Vector3(0.02,-0.33,-0.386)],[0.006,0.012,0.003],cloth.darkened(0.18),5)
			if look!=2:
				s.twig([Vector3(-0.065,0.374,-0.179),Vector3(-0.065,0.208,-0.342),
					Vector3(-0.060,0.046,-0.513),Vector3(-0.064,-0.16,-0.493),
					Vector3(-0.08,-0.362,-0.356)],[0.006,0.01,0.013,0.012,0.008],cloth.darkened(0.21),5)
		"spitter":
			var bruise:=Color(["#988e77","#928c7d","#9a907e"][look])
			s.loft([Vector4(-0.47,0.18,0.17,0.02),Vector4(-0.32,0.33,0.30,-0.035),
				Vector4(-0.07,0.45,0.42,-0.075),Vector4(0.22,0.43,0.40,-0.09),
				Vector4(0.44,0.26,0.31,-0.02)],bruise,Vector3.ZERO,Basis(Vector3.BACK,-0.18),14)
		"rimecaller":
			s.oval(Vector3.ZERO,Vector3(0.5,0.44,0.40),BLUE_ICE)
			for i in 5:
				var angle := TAU*i/5.0+0.23*look
				_crystal(s,Vector3(0,0,-0.15),Vector3(cos(angle)*0.47,sin(angle)*0.50,-0.41),0.147)
			_crystal(s,Vector3(0,0,-0.18),Vector3(0.027,0.12,-0.57),0.21)

# A pressed plate with a raised face and a continuous bevel around its rim.
static func _plate(s, at: Vector3, size: Vector3, surface: Color, rim: Color, twist := 0.0) -> void:
	var outline := [Vector2(-0.70,1),Vector2(0.70,1),Vector2(1,0.65),
		Vector2(0.90,-0.61),Vector2(0.24,-1),Vector2(-0.51,-0.94),Vector2(-1,-0.54),Vector2(-1,0.61)]
	var axis := Basis(Vector3.BACK, twist)
	var front := at + Vector3.FORWARD * size.z
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i+1)%outline.size()]
		var u := axis * Vector3(a.x*size.x, a.y*size.y, 0)
		var v := axis * Vector3(b.x*size.x, b.y*size.y, 0)
		var edge := ((u+v).normalized()+Vector3.FORWARD).normalized()
		s.triangle(front+u*0.82, front+v*0.82, front+Vector3.FORWARD*size.z*0.32, Vector3.FORWARD, surface)
		s.triangle(at+u, at+v, front+u*0.82, edge, rim)
		s.triangle(at+v, front+v*0.82, front+u*0.82, edge, rim)
		s.triangle(at, at+v, at+u, Vector3.BACK, rim.darkened(0.28))

# Double-faced cloth. A central fold and a taper keep loose ends readable from behind.
static func _ribbon(s, points: Array, widths: Array, across: Vector3, cloth: Color) -> void:
	for i in range(points.size()-1):
		var start: Vector3 = points[i]
		var end: Vector3 = points[i+1]
		var normal := across.cross(end-start).normalized()
		for sign_x: float in [-1,1]:
			var a: Vector3 = start + across*widths[i]*sign_x
			var b: Vector3 = end + across*widths[i+1]*sign_x
			var ridge_a: Vector3 = start + normal*widths[i]*0.22
			var ridge_b: Vector3 = end + normal*widths[i+1]*0.22
			var dye := cloth.darkened(0.13) if sign_x<0 else cloth
			for facing: float in [-1,1]:
				s.triangle(a,b,ridge_a,normal*facing,dye)
				s.triangle(b,ridge_b,ridge_a,normal*facing,dye)

static func _crystal(s, root: Vector3, tip: Vector3, radius: float) -> void:
	var axis := tip-root
	s.twig([root, root+axis*0.22, root+axis*0.70, tip],
		[radius*0.63,radius,radius*0.76,0.002],FROST,5)

static func _civilian(s, kind:String, look:int, joint:String)->void:
	var cloth:=coat_for(kind,look)
	var patrol:=kind=="spitter"
	if joint=="head":
		_civilian_head(s,patrol,look,cloth)
		return
	if joint.begins_with("elbow"):
		var side:float=-1 if joint=="elbow_l" else 1
		var hem:float=-0.077 if look==0 else -0.199 if patrol or look==1 else -0.182
		var radius:float=0.083 if look==0 else 0.060
		var cuff:=cloth.lightened(0.17) if look==0 else cloth.darkened(0.14)
		if not patrol and look==2: cuff=Color("#79726b")
		s.loft([Vector4(hem-0.021,radius*0.95,radius*0.94,-0.031),Vector4(hem-0.013,radius*1.04,radius,-0.031),
			Vector4(hem+0.024,radius,radius*0.98,-0.025)],cuff,Vector3.ZERO,Basis(Vector3.BACK,side*0.055))
		return
	var w:=0.27 if patrol else 0.235
	var hem:float=[-0.117,-0.18,-0.252][look] if patrol else [-0.135,-0.187,-0.116][look]
	s.loft([Vector4(hem,w*0.86,0.154,0.012),Vector4(hem+0.026,w*0.87,0.156,0.012),
		Vector4(0.035,w*0.84,0.151,0.012)],cloth.darkened(0.065))
	if look==0 or (patrol and look==1):
		for side:float in [-1,1]:
			s.triangle(Vector3(side*0.088,0.41,-0.095),Vector3(side*0.153,0.339,-0.150),
				Vector3(side*0.070,0.277,-0.188),Vector3.FORWARD,cloth.lightened(0.14))
		var pocket:=Vector3(-0.121,0.197,-0.152)
		_plate(s,pocket,Vector3(0.056,0.051,0.009),cloth.darkened(0.07),cloth.lightened(0.055),-0.14)
		_ribbon(s,[pocket+Vector3(0,0.049,-0.012),pocket+Vector3(-0.002,0.025,-0.013)],
			[0.055,0.050],Vector3.RIGHT,cloth.lightened(0.14))
		s.twig([Vector3(-0.19,0.289,0.124),Vector3(0,0.264,0.199),Vector3(0.19,0.289,0.124)],
			[0.002,0.006,0.003],cloth.darkened(0.16),5)
	elif patrol:
		# Rain yoke wraps the shoulders and drops further down the back.
		s.loft([Vector4(0.238,0.287,0.185,0.019),Vector4(0.292,0.306,0.197,0.010),
			Vector4(0.369,0.277,0.166,-0.008),Vector4(0.408,0.137,0.121,-0.018)],cloth.lightened(0.08))
	else:
		var undershirt:=Color("#ac9982") if look==1 else Color("#79726b")
		s.triangle(Vector3(-0.098,0.403,-0.099),Vector3(0.098,0.403,-0.099),
			Vector3(-0.009,0.200,-0.178),Vector3.FORWARD,undershirt)
		for side:float in [-1,1]:
			_ribbon(s,[Vector3(side*0.105,0.409,-0.099),Vector3(side*0.090,0.337,-0.174),
				Vector3(side*0.049,0.241,-0.174),Vector3(side*0.012,0.169,-0.171)],
				[0.016,0.018,0.015,0.01],Vector3.RIGHT,cloth.darkened(0.18))
		if look==2:
			for h:float in [0.095,0.205]:
				s.twig([Vector3(-0.18,h,0.10),Vector3(-0.093,h-0.013,0.165),Vector3(0,h-0.020,0.184),
					Vector3(0.11,h-0.009,0.154),Vector3(0.189,h,0.097)],[0.002,0.007,0.008,0.006,0.002],cloth.darkened(0.14),5)

static func _civilian_head(s, patrol:bool, look:int, cloth:Color)->void:
	var hair:=Color("#514c44") if look!=1 else Color("#4d4845")
	# The hairline sits higher over the temples and drops at the nape.
	var profile:=[Vector4(0.125,0.135,0.131,-0.026),Vector4(0.172,0.146,0.137,-0.024),
		Vector4(0.209,0.151,0.137,-0.014),Vector4(0.257,0.136,0.131,0.002),
		Vector4(0.294,0.103,0.102,0.012),Vector4(0.313,0.061,0.064,0.019),
		Vector4(0.325,0.008,0.009,0.019)]
	var previous:=PackedVector3Array()
	for level in 7:
		var ring:=PackedVector3Array()
		for i in 32:
			var angle:=TAU*i/32
			var front:=maxf(-sin(angle),0)
			var hairline:=0.128+front*0.113+0.047*absf(cos(angle))-0.017*sin(angle*3+0.35)
			if not patrol and look==1: hairline-=0.023
			var y:=lerpf(hairline,0.325,level/6.0)
			var section:=1
			while section<profile.size()-1 and y>profile[section].x: section+=1
			var lower:Vector4=profile[section-1]
			var upper:Vector4=profile[section]
			var row:=lower.lerp(upper,clampf(inverse_lerp(lower.x,upper.x,y),0,1))
			ring.append(Vector3(cos(angle)*row.y,y,row.w+sin(angle)*row.z))
		for i in 32:
			var j:=(i+1)%32
			var outward:=Vector3(cos(TAU*(i+0.5)/32),0.32,sin(TAU*(i+0.5)/32))
			if level>0:
				s.triangle(previous[i],ring[i],previous[j],outward,hair)
				s.triangle(previous[j],ring[i],ring[j],outward,hair)
			if level==6: s.triangle(Vector3(0,0.327,0.019),ring[i],ring[j],Vector3.UP,hair)
		previous=ring
	if patrol and look==0:
		var cap:=cloth.darkened(0.23)
		s.loft([Vector4(0.198,0.153,0.145,0.003),Vector4(0.224,0.160,0.151,-0.003),
			Vector4(0.293,0.138,0.132,0.009),Vector4(0.329,0.056,0.065,0.012)],cap,
			Vector3.ZERO,Basis(Vector3.BACK,0.058))
		s.oval(Vector3(0.003,0.214,-0.14),Vector3(0.139,0.014,0.12),cap,-0.055)
	elif patrol and look==2:
		var hood:=cloth.darkened(0.08)
		s.loft([Vector4(0.125,0.159,0.124,0.038),Vector4(0.207,0.171,0.157,0.015),
			Vector4(0.300,0.146,0.140,0.030),Vector4(0.357,0.038,0.048,0.065)],hood)
		for side:float in [-1,1]:
			_ribbon(s,[Vector3(side*0.141,0.23,-0.035),Vector3(side*0.154,0.118,0.00),
				Vector3(side*0.133,-0.014,0.046)],[0.091,0.104,0.097],Vector3.BACK,hood)
	elif not patrol and look==1:
		s.oval(Vector3(-0.095,0.102,0.129),Vector3(0.102,0.090,0.090),hair)
		for side:float in [-1,1]:
			s.oval(Vector3(side*0.125,0.134,0.059),Vector3(0.039,0.095,0.067),hair,-side*0.25)
			s.twig([Vector3(side*0.124,0.208,0),Vector3(side*0.132,0.139,0.063),Vector3(side*0.06,0.125,0.143)],
				[0.023,0.022,0.015],hair,6)
	elif not patrol and look==2:
		var knit:=Color("#625d58")
		s.loft([Vector4(0.183,0.154,0.142,0.013),Vector4(0.220,0.160,0.148,0.014),
			Vector4(0.29,0.144,0.139,0.032),Vector4(0.344,0.081,0.098,0.065),
			Vector4(0.357,0.031,0.046,0.089)],knit)
		s.loft([Vector4(0.189,0.159,0.147,0.011),Vector4(0.220,0.164,0.151,0.014)],knit.lightened(0.1))
	for side:float in [-1,1]:
		s.twig([Vector3(side*0.115,0.215,-0.045),Vector3(side*0.137,0.187,-0.019),
			Vector3(side*0.139,0.152,-0.015)],[0.014,0.016,0.005],hair,6)

static func skull(s,skin:Color,breadth:=1.0)->void:
	if s.cached: return
	# Model the nose bridge and cheekbones in the skull surface. The face atlas
	# supplies the markings and eyes directly on this surface.
	const SECTORS:=32
	var previous:=PackedVector3Array()
	s.buffer.set_smooth_group(0)
	for row:Vector4 in [Vector4(-0.018,0.053,0.066,-0.044),Vector4(0.012,0.080,0.091,-0.050),
		Vector4(0.043,0.103,0.109,-0.041),Vector4(0.075,0.118,0.122,-0.039),
		Vector4(0.099,0.125,0.127,-0.033),Vector4(0.122,0.133,0.129,-0.026),
		Vector4(0.148,0.138,0.131,-0.025),Vector4(0.171,0.141,0.133,-0.025),
		Vector4(0.210,0.146,0.132,-0.015),Vector4(0.257,0.130,0.124,0.002),
		Vector4(0.293,0.095,0.092,0.012),Vector4(0.309,0.052,0.055,0.019)]:
		var ring:=PackedVector3Array()
		var center:=Vector3(0,row.x,row.w)
		for i in SECTORS:
			var angle:=TAU*i/SECTORS
			var x:=cos(angle)*row.y*breadth
			var front:=maxf(0,-sin(angle))
			var nose:float=0.049*exp(-pow(x/0.025,2))*exp(-pow((row.x-0.107)/0.046,2))
			var cheek:float=0.019*exp(-pow((absf(x)-0.085)/0.031,2))*exp(-pow((row.x-0.118)/0.023,2))
			var hollow:float=0.011*exp(-pow((absf(x)-0.082)/0.03,2))*exp(-pow((row.x-0.077)/0.025,2))
			var ridge:float=0.011*exp(-pow((absf(x)-0.059)/0.032,2))*exp(-pow((row.x-0.17)/0.013,2))
			ring.append(center+Vector3(x,0,sin(angle)*row.z-front*(nose+cheek+ridge-hollow)))
		for i in SECTORS:
			var j:=(i+1)%SECTORS
			if previous.is_empty():
				s.triangle(center,ring[i],ring[j],Vector3.DOWN,skin)
			else:
				var outward:=Vector3(cos(TAU*(i+0.5)/SECTORS),0,sin(TAU*(i+0.5)/SECTORS))
				var at:Vector3=(previous[i]+previous[j]+ring[i]+ring[j])*0.25
				var eye_shadow:=exp(-pow((absf(at.x)-0.065)/0.045,2)-pow((at.y-0.145)/0.024,2))
				var bruise:=exp(-pow((at.x+0.089)/0.037,2)-pow((at.y-0.084)/0.038,2))
				var pigment:=skin.lerp(Color("#74666a"),maxf(0,-outward.z)*(eye_shadow*0.48+bruise*0.46))
				s.triangle(previous[i],ring[i],previous[j],outward,pigment)
				s.triangle(previous[j],ring[i],ring[j],outward,pigment)
			if row.x>0.30: s.triangle(center,ring[j],ring[i],Vector3.UP,skin)
		previous=ring
	s.buffer.set_smooth_group(-1)
	for side:float in [-1,1]:
		s.oval(Vector3(side*0.137*breadth,0.130,0.008),Vector3(0.017,0.034,0.023),skin.darkened(0.12))

static func civilian_morph(s,kind:String,look:int,joint:String,armored:bool)->void:
	var cloth:=coat_for(kind,look)
	var side:float=-1 if joint=="arm_l" else 1
	if armored:
		var canvas:=cloth.darkened(0.20)
		if joint=="torso":
			# Reinforced shoulder yoke leaves the throat, collar and belly exposed.
			for flank:float in [-1,1]:
				_ribbon(s,[Vector3(flank*0.137,0.311,-0.156),Vector3(flank*0.15,0.394,-0.063),
					Vector3(flank*0.147,0.391,0.051),Vector3(flank*0.139,0.231,0.153)],
					[0.038,0.045,0.053,0.041],Vector3.RIGHT,canvas)
		else:
			s.oval(Vector3(side*0.031,-0.028,0.007),Vector3(0.102,0.100,0.113),canvas,-side*0.16)
	else:
		if joint=="torso":
			_ribbon(s,[Vector3(0.153,0.021,0.126),Vector3(0.164,-0.081,0.138),
				Vector3(0.18,-0.159,0.159)],[0.047,0.035,0.008],Vector3.RIGHT,cloth.darkened(0.11))
		else:
			s.loft([Vector4(-0.177,0.091,0.094,-0.005),Vector4(-0.157,0.094,0.097,-0.006)],
				cloth.lightened(0.13),Vector3.ZERO,Basis(Vector3.BACK,0.09*side),12)

static func _bulwark(s, look: int, joint: String) -> void:
	var side := -1.0 if joint == "elbow_l" else 1.0
	if joint.begins_with("elbow"):
		match look:
			0:
				_plate(s,Vector3(side*0.028,-0.102,-0.074),Vector3(0.148,0.238,0.043),Color("#526d7ac8"),STEEL,side*0.1)
				for x: float in [-0.075,0.075]:
					for y: float in [-0.21,0.027]:
						s.oval(Vector3(side*0.028+x,y,-0.128),Vector3(0.014,0.014,0.012),BRASS)
				_plate(s,Vector3(side*0.026,-0.06,-0.13),Vector3(0.092,0.014,0.008),CANVAS,LEATHER)
			1:
				for i in 3:
					var at := Vector3(side*0.018+(i-1)*0.079,-0.125,-0.092+absf(i-1)*0.018)
					_plate(s,at,Vector3(0.048,0.275-absf(i-1)*0.052,0.045),IRON,STEEL,side*0.065)
					_plate(s,at+Vector3(0,0.043,-0.053),Vector3(0.039,0.032,0.007),BRASS,LEATHER,0.28)
			2:
				var at := Vector3(side*0.04,-0.118,-0.08)
				s.oval(at,Vector3(0.173,0.208,0.084),BRASS)
				for i in 3:
					_plate(s,at+Vector3(0,(i-1)*0.08,-0.059),Vector3(0.149-absf(i-1)*0.032,0.072,0.042),Color("#54857bbd").darkened(i*0.055),Color("#8fac93dc"),side*0.13)
		return
	if joint == "head":
		match look:
			0:
				s.loft([Vector4(0.177,0.187,0.179,-0.012),Vector4(0.202,0.188,0.177,-0.014),Vector4(0.286,0.144,0.147,0),Vector4(0.325,0.08,0.08,0)],IRON)
				_plate(s,Vector3(0,0.224,-0.149),Vector3(0.069,0.047,0.022),STEEL,IRON)
			1:
				_plate(s,Vector3(0,0.272,-0.120),Vector3(0.15,0.065,0.025),IRON,BRASS)
				_plate(s,Vector3(0,0.267,-0.159),Vector3(0.099,0.011,0.005),RUBBER,STEEL)
			2:
				s.oval(Vector3(0,0.233,0.036),Vector3(0.192,0.138,0.175),Color("#54857bbd"))
				for i in 3:
					s.oval(Vector3((i-1)*0.085,0.208,-0.116),Vector3(0.059,0.043,0.057),BRASS.darkened(0.12*i))
		return
	for flank: float in [-1,1]:
		s.twig([Vector3(flank*0.12,0.38,0.07),Vector3(flank*0.143,0.365,-0.108),Vector3(flank*0.18,0.19,-0.15),Vector3(flank*0.119,-0.04,-0.135)],[0.032,0.033,0.026,0.022],LEATHER)
		match look:
			0:
				_plate(s,Vector3(flank*0.138,0.29,-0.133),Vector3(0.098,0.095,0.035),IRON,STEEL,flank*0.19)
			1:
				s.twig([Vector3(flank*0.18,0.24,0.075),Vector3(flank*0.25,0.41,0.12),Vector3(flank*0.30,0.49,0.17)],[0.064,0.070,0.053],IRON,4)
			2:
				s.oval(Vector3(flank*0.206,0.34,0.045),Vector3(0.151,0.114,0.15),Color("#54857bbd"),flank*0.32)

static func _rimecaller(s, look: int) -> void:
	for side: float in [-1,1]:
		var root := Vector3(side*0.144,0.312,0.093)
		s.oval(root,Vector3(0.133,0.116,0.089),BLUE_ICE,side*0.25)
		match look:
			0:
				var fork := Vector3(side*0.297,0.502,0.139)
				s.twig([root,root.lerp(fork,0.52),fork],[0.073,0.050,0.041],BLUE_ICE,6)
				_crystal(s,fork,Vector3(side*0.266,0.777,0.151),0.042)
				_crystal(s,fork,Vector3(side*0.447,0.724,0.137),0.041)
				_crystal(s,root,Vector3(side*0.389,0.506,0.276),0.044)
			1:
				var length := 1.0 if side<0 else 0.52
				for i in 6:
					var base := root + Vector3(0,0,i*0.018-0.041)
					var angle := 0.14+i*0.244
					var reach := (0.42+sin(i*0.68)*0.085)*length
					var tip := base + Vector3(side*sin(angle)*reach,cos(angle)*reach,0.11)
					# Each blade has a raised spine and a blue underside.
					var spine := base.lerp(tip,0.52)
					var half_width := Vector3(cos(angle)*0.047,-side*sin(angle)*0.047,0)
					for edge: float in [-1,1]:
						var wing := spine+half_width*edge
						var ridge := spine + Vector3.FORWARD*0.026
						s.triangle(base,wing,ridge,Vector3.FORWARD,FROST)
						s.triangle(wing,tip,ridge,Vector3.FORWARD,FROST.darkened(0.08 if edge<0 else 0.0))
						s.triangle(base,wing,tip,Vector3.BACK,BLUE_ICE)
			2:
				var crook := Vector3(side*0.312,0.615,0.13)
				var end := Vector3(side*0.469,0.536,0.14)
				s.twig([root,Vector3(side*0.207,0.505,0.10),crook,end],[0.067,0.048,0.044,0.022],BLUE_ICE,5)
				for i in 3:
					var anchor := crook.lerp(end,(i+0.15)/2.6)
					_crystal(s,anchor,anchor+Vector3(side*0.038,-0.097-i*0.048,0.025),0.028+i*0.006)
		_ribbon(s,[Vector3(side*0.11,0.385,-0.095),Vector3(side*0.159,0.263,-0.133),
			Vector3(side*0.196,-0.023,-0.11)],[0.047,0.039,0.016],Vector3.RIGHT,INDIGO)

static func _sandrunner(s, look: int, joint: String) -> void:
	if joint == "head":
		match look:
			0:
				for side: float in [-1,1]:
					_ribbon(s,[Vector3(side*0.095,0.14,0.104),Vector3(side*0.143,0.108,0.231),
						Vector3(side*0.156,0.062,0.347), Vector3(side*0.22,0.094,0.479-side*0.053)],
						[0.044,0.041,0.033,0.005],Vector3.UP,INDIGO)
			1:
				s.loft([Vector4(0.174,0.186,0.181,-0.011),Vector4(0.232,0.182,0.167,0.018),
					Vector4(0.31,0.142,0.134,0.037),Vector4(0.379,0.042,0.056,0.078)],CANVAS)
				for side: float in [-1,1]:
					var top := Vector3(side*0.145,0.223,0.016)
					var hem := Vector3(side*0.263,-0.12,0.141)
					_ribbon(s,[top,Vector3(side*0.176,0.083,0.062),hem],[0.09,0.112,0.052],Vector3.BACK,VERMILION)
					_ribbon(s,[top+Vector3.RIGHT*side*0.013,Vector3(side*0.195,0.096,0.063),
						hem+Vector3(0,0.041,0)],[0.096,0.107,0.056],Vector3.BACK,CANVAS)
			2:
				s.loft([Vector4(0.183,0.163,0.152,0),Vector4(0.211,0.166,0.158,0),
					Vector4(0.244,0.151,0.14,0.01)],VERMILION)
				s.oval(Vector3(-0.127,0.18,0.097),Vector3(0.063,0.046,0.065),VERMILION)
		return
	match look:
		0:
			_ribbon(s,[Vector3(-0.014,0.393,-0.098),Vector3(-0.168,0.314,-0.15),
				Vector3(-0.28,0.154,-0.104)],[0.063,0.101,0.047],Vector3.UP,INDIGO)
			_ribbon(s,[Vector3(0.138,0.386,-0.093),Vector3(0.047,0.264,-0.18),
				Vector3(-0.199,-0.045,-0.101)],[0.046,0.053,0.038],Vector3.RIGHT,INDIGO)
			for side: float in [-1,1]:
				s.oval(Vector3(side*0.154,0.016,0.117),Vector3(0.083,0.083,0.075),LEATHER)
		1:
			for side: float in [-1,1]:
				_ribbon(s,[Vector3(side*0.07,0.393,-0.11),Vector3(side*0.178,0.288,-0.149),
					Vector3(side*0.249,0.126,-0.087)], [0.073,0.09,0.029],Vector3.RIGHT,CANVAS)
				_ribbon(s,[Vector3(side*0.092,0.398,0.08),Vector3(side*0.205,0.269,0.14),
					Vector3(side*0.293,0.022,0.259)],[0.075,0.121,0.045],Vector3.BACK,CANVAS)
				s.twig([Vector3(side*0.224,0.329,-0.052),Vector3(side*0.135,0.276,-0.165),
					Vector3(side*0.02,0.251,-0.184)],[0.018,0.022,0.016],VERMILION)
		2:
			_ribbon(s,[Vector3(-0.20,0.391,-0.097),Vector3(-0.096,0.286,-0.183),
				Vector3(0.076,0.157,-0.17),Vector3(0.207,0.072,-0.1)],[0.104,0.121,0.098,0.051],Vector3.UP,VERMILION)
			s.oval(Vector3(0,0.224,0.214),Vector3(0.183,0.189,0.115),LEATHER)
			var axis := Basis(Vector3.BACK,-1.38)
			var at := Vector3(-0.26,0.383,0.188)
			s.loft([Vector4(0,0.076,0.076,0),Vector4(0.037,0.096,0.093,0),
				Vector4(0.49,0.099,0.094,0),Vector4(0.54,0.084,0.081,0)],CANVAS,at,axis,10)
			for h: float in [0.111,0.399]:
				s.loft([Vector4(h,0.10,0.097,0),Vector4(h+0.028,0.10,0.097,0)],LEATHER,at,axis,10)
			_ribbon(s,[Vector3(-0.161,0.383,-0.089),Vector3(0.036,0.238,-0.19),
				Vector3(0.185,-0.027,-0.107)],[0.046,0.048,0.041],Vector3.RIGHT,LEATHER)
			_ribbon(s,[Vector3(-0.099,0.39,0.115),Vector3(-0.217,0.25,0.27),
				Vector3(-0.26,0.01,0.396),Vector3(-0.326,-0.082,0.464)],[0.079,0.096,0.067,0.007],Vector3.RIGHT,VERMILION)
