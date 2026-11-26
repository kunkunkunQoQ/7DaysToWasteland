extends RefCounted

const Art := preload("res://game/art/bestiary.gd")
const Looks := preload("res://game/art/infected_looks.gd")
const ClothMotion := preload("res://game/actors/infected_cloth.gd")
const HIDE := Color("#735e4b")
const STITCH := Color("#ab9678")
const BUTTON := Color("#726f64")
static var meshes: Dictionary = {}

static func fabric_color(base: Color, wardrobe: int) -> Color:
	var cut := posmod(wardrobe,3)
	var wear := floori(wardrobe/3.0)%3
	var dye: Color = [base.darkened(0.12),base.lerp(Color("#58686a"),0.56),base.lerp(Color("#a08d71"),0.57)][cut]
	return dye.lerp(Color("#a69c87"),0.15*wear)

static func dress(actor: Node3D) -> ClothMotion:
	var motion := ClothMotion.new()
	motion.skeleton = actor.skeleton
	motion.torso = motion.skeleton.find_bone("torso")
	var index := posmod(int(actor.wardrobe_index),36)
	var cut := index%3
	var wear := floori(index/3.0)%3
	var kit := floori(index/9.0)
	var crawling: bool = actor.type == "crawler"
	var width: float = {"brute":0.33,"spitter":0.27,"screamer":0.199,"rimecaller":0.199,"crawler":0.20}.get(actor.type,0.235)
	var base := Looks.coat_for(actor.type,actor.look_index) if actor.type in ["spitter","bloater"] else Color.html(actor.spec.cloth)
	var cloth := fabric_color(base, index)
	var key := "%s/%s/%d/%d" % [actor.type,base.to_html(false),cut,wear]
	if not meshes.has(key):
		var shell := Art.Sculpture.new(113)
		_jacket(shell,cut,wear,width,cloth)
		meshes[key] = ClothMotion.flexible_mesh(shell.commit(),0.21,[-0.15,0.0,-0.08][cut]-0.03)
	var shell_node := _attach(actor,"torso","OuterShirt",meshes[key])
	motion.shirt = shell_node
	if crawling:
		_flatten_for_crawler(shell_node)
	var sleeve_key := key+"/sleeve"
	if not meshes.has(sleeve_key):
		var sleeve := Art.Sculpture.new(114)
		var skin := Color.html(actor.spec.skin)
		if actor.type in ["sandrunner","bloater","bulwark","spitter","rimecaller"]:
			skin = Looks.skin_for(actor.type,skin)
		_sleeve(sleeve,cut,wear,cloth,skin,crawling,1.30 if actor.type=="brute" else 0.81 if actor.type in ["screamer","rimecaller"] else 1.0)
		meshes[sleeve_key] = sleeve.commit()
	if cut == 2:
		# The existing left upper arm is painted as a continuous full sleeve.
		# Replace just that surface with the exposed arm and torn shoulder seam.
		actor.body_parts.arm_l.get_child(0).visible = false
	_attach(actor,"arm_l","ShirtSleeve",meshes[sleeve_key])
	if kit > 0:
		var kit_key := "gear/%d/%d" % [roundi(width*1000),kit]
		if not meshes.has(kit_key):
			var gear := Art.Sculpture.new(115)
			_accessory(gear,kit,width)
			meshes[kit_key] = ClothMotion.flexible_mesh(gear.commit(),0.20 if kit == 2 else 0.07,-0.10)
		var gear_node := _attach(actor,"torso","PersonalEffects",meshes[kit_key])
		motion.accessory = gear_node
		if crawling:
			_flatten_for_crawler(gear_node)
	return motion

static func _attach(actor: Node3D, joint: String, label: String, mesh: ArrayMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = actor._toon_material(Color.WHITE)
	actor.body_parts[joint].add_child(node)
	return node

static func _flatten_for_crawler(node: MeshInstance3D) -> void:
	node.basis = Basis(Vector3.RIGHT,-PI*0.5)*Basis.from_scale(Vector3(0.99,0.82,0.80))
	node.position = Vector3(0,0,0.086)

static func _jacket(s: Art.Sculpture, cut: int, wear: int, width: float, cloth: Color) -> void:
	for side: float in [-1,1]:
		var gap: float = [0.50,0.69,0.90][cut]
		var hem: float = [-0.15,0.00,-0.08][cut]
		var collar := 0.375 if cut != 2 else 0.320
		for j in 7:
			var a := lerpf(gap,PI,j/7.0)
			var b := lerpf(gap,PI,(j+1)/7.0)
			var bottom_a := hem-_fray(j,side,wear)
			var bottom_b := hem-_fray(j+1,side,wear)
			var lo := _seam(side,a,bottom_a,width)
			var next_lo := _seam(side,b,bottom_b,width)
			var mid := _seam(side,a,0.207,width)
			var next_mid := _seam(side,b,0.207,width)
			var hi := _seam(side,a,collar,width)
			var next_hi := _seam(side,b,collar,width)
			var normal := Vector3(side*sin((a+b)/2),0,-cos((a+b)/2))
			var shade := cloth.darkened(0.036*(j%3))
			s.triangle(hi,mid,next_mid,normal,shade)
			s.triangle(hi,next_mid,next_hi,normal,shade)
			s.triangle(mid,lo,next_mid,normal,shade.darkened(0.022))
			if not (wear == 2 and j == (3 if side>0 else 1)):
				s.triangle(lo,next_lo,next_mid,normal,shade)
			if cut == 1:
				var welt := _seam(side,a,bottom_a+0.035,width)*Vector3(1.009,1,1.009)
				var next_welt := _seam(side,b,bottom_b+0.035,width)*Vector3(1.009,1,1.009)
				s.triangle(welt,lo,next_lo,normal,shade.darkened(0.2))
				s.triangle(welt,next_lo,next_welt,normal,shade.darkened(0.2))
		var lapel := [_seam(side,gap,collar,width),_seam(side,gap-0.13,0.29,width),
			_seam(side,gap+0.10,0.17,width)]
		var normal := Vector3(side*0.36,0,-1)
		s.triangle(lapel[0],lapel[1]+Vector3.FORWARD*0.012,lapel[2],normal,cloth.lightened(0.20))
		if wear > 0:
			_patch(s,side,width,0.14 if side<0 else 0.055,cloth.lightened(0.12),wear)
		if cut == 0 and side>0:
			for h: float in [0.223,0.121,0.027]:
				_button(s,_seam(side,gap+0.045,h,width)+Vector3.FORWARD*0.009,normal.normalized(),0.009)

static func _button(s: Art.Sculpture, at: Vector3, normal: Vector3, radius: float) -> void:
	var tangent := Vector3.UP.cross(normal)
	for i in 5:
		var a := TAU*i/5.0
		var b := TAU*(i+1)/5.0
		s.triangle(at+(tangent*cos(a)+Vector3.UP*sin(a))*radius,
			at+(tangent*cos(b)+Vector3.UP*sin(b))*radius,at+normal*0.003,normal,BUTTON)

static func _fray(segment: int, side: float, wear: int) -> float:
	return (0.019+0.026*wear) * (absf(sin(segment*2.16+side*0.77)) if segment not in [0,7] else 0.15)

static func _seam(side: float, angle: float, y: float, width: float) -> Vector3:
	var upper := smoothstep(-0.11,0.275,y)
	var radius := width*lerpf(0.94,1.14,upper)
	var depth := lerpf(0.157,0.192,upper)
	if y>0.32:
		radius *= lerpf(1,0.86,(y-0.32)/0.08)
		depth *= lerpf(1,0.83,(y-0.32)/0.08)
	return Vector3(side*sin(angle)*radius,y,-cos(angle)*depth)

static func _patch(s: Art.Sculpture, side: float, width: float, y: float, cloth: Color, wear: int) -> void:
	var points := [_seam(side,0.89,y+0.055,width),_seam(side,1.36,y+0.04,width),
		_seam(side,1.31,y-0.059,width),_seam(side,0.93,y-0.035,width)]
	var normal := Vector3(side*0.75,0,-0.65)
	for i in points.size():
		points[i] += normal*0.009
	s.triangle(points[0],points[1],points[2],normal,cloth)
	s.triangle(points[0],points[2],points[3],normal,cloth.darkened(0.04))
	if wear==1:
		for i in 3:
			var at: Vector3 = points[0].lerp(points[3],(i+0.4)/3.0)
			var end := at+Vector3(side*0.014,-0.004,0.008)
			s.triangle(at+Vector3.UP*0.002,at-Vector3.UP*0.002,end,normal,STITCH)

static func _sleeve(s: Art.Sculpture, cut: int, wear: int, cloth: Color, skin: Color, crawl: bool, bulk: float) -> void:
	var path := [Vector3(-0.003,0.037,0),Vector3(-0.007,-0.035,0),Vector3(-0.008,-0.151,0),Vector3(0,-0.251,-0.007)]
	if crawl:
		path = [Vector3(0,0.023,-0.017),Vector3(-0.037,-0.04,0.035),Vector3(-0.088,-0.121,0.081),Vector3(-0.113,-0.158,0.110)]
	var muscle := [0.067*bulk,0.116*bulk,0.102*bulk,0.067*bulk]
	if cut==2:
		s.twig(path,muscle,skin.darkened(0.10),10)
		s.twig([path[0],path[1],path[1].lerp(path[2],0.27)],[0.072*bulk,0.121*bulk,0.113*bulk],cloth,8)
		var outer: Vector3 = path[1]+Vector3.LEFT*0.101*bulk
		s.triangle(outer+Vector3.BACK*0.03,outer+Vector3.FORWARD*0.04,outer+Vector3(-0.012,-0.113,0.025),Vector3.LEFT,cloth.darkened(0.15))
	else:
		var end: Vector3 = path[2].lerp(path[3],0.69 if cut==0 else 0.11)
		var at: Vector3 = path[2].lerp(end,0.69)
		s.twig([path[0],path[1],path[2],at],[0.073*bulk,0.121*bulk,0.114*bulk,0.107*bulk],cloth,8)
		s.twig([at,end],[0.108*bulk,0.099*bulk],cloth.lightened(0.10+0.07*wear),8)

static func _pouch(s: Art.Sculpture, at: Vector3, extent: Vector3, pigment: Color, tilt := 0.0) -> void:
	s.loft([Vector4(-extent.y,extent.x*0.67,extent.z*0.64,0),
		Vector4(-extent.y*0.32,extent.x,extent.z,0),Vector4(extent.y*0.78,extent.x*0.81,extent.z*0.84,0)],
		pigment,at,Basis(Vector3.BACK,tilt),7)

static func _accessory(s: Art.Sculpture, kit: int, width: float) -> void:
	match kit:
		1:
			var at := Vector3(width*0.81,-0.067,-0.099)
			_pouch(s,at,Vector3(0.084,0.088,0.051),HIDE,-0.08)
			_pouch(s,at+Vector3(0,0.029,-0.030),Vector3(0.084,0.051,0.028),HIDE.lightened(0.15),-0.08)
			_button(s,at+Vector3(0,0.004,-0.057),Vector3.FORWARD,0.012)
			s.twig([at+Vector3(-0.035,0.046,0.02),at+Vector3(-0.041,0.106,0.018),at+Vector3(-0.050,0.103,-0.003)],[0.013,0.014,0.013],HIDE,5)
		2:
			# The strap descends over the back, leaving the chest free for attack organs.
			var path := [Vector3(-width*0.52,0.319,-0.146),Vector3(-width*0.64,0.389,-0.064),
				Vector3(-width*0.59,0.381,0.105),Vector3(-width*0.26,0.242,0.19),
				Vector3(width*0.43,0.071,0.166),Vector3(width*0.88,-0.034,0.10)]
			s.twig(path,[0.023,0.027,0.028,0.028,0.031,0.026],HIDE.darkened(0.12),5)
			var at: Vector3 = path.back()
			_pouch(s,at,Vector3(0.103,0.095,0.078),Color("#747463"),-0.19)
			_pouch(s,at+Vector3(0,0.035,0.039),Vector3(0.101,0.049,0.043),Color("#96917a"),-0.16)
		3:
			var at := Vector3(-width*0.89,-0.092,0.051)
			s.twig([at+Vector3(0.024,0.053,0),at+Vector3(0.022,0.148,0),at+Vector3(0.056,0.160,0)],[0.012,0.015,0.01],HIDE,6)
			_pouch(s,at,Vector3(0.072,0.113,0.053),Color("#778b83"),-0.13)
			s.twig([at+Vector3(0.011,0.081,0),at+Vector3(0.016,0.119,0)],[0.026,0.024],BUTTON,8)
			s.twig([at+Vector3(-0.067,-0.022,0.013),at+Vector3(-0.002,-0.013,0.052),at+Vector3(0.065,0.007,0.013)],[0.01,0.012,0.01],HIDE,5)
