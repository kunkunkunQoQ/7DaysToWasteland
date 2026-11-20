class_name WastelandBestiary
extends RefCounted

const IRON := Color("#574e62")
const AMBER := Color("#d29a61")
const TARP := Color("#5c5666")
const ASH := Color("#91878f")
const TEAL := Color("#6e9888")
const InfectedLooks := preload("res://game/art/infected_looks.gd")
const SLEDGE_GRIP_POINT := Vector3(0.0, -0.139, 0.0)

static var hand_meshes: Dictionary = {}

static func hand_mesh(side: int, gripping: bool) -> ArrayMesh:
	var key := Vector2i(side, int(gripping))
	if not hand_meshes.has(key):
		hand_meshes[key] = _build_hand(-float(side), gripping)
	return hand_meshes[key]

static func _build_hand(thumb_side: float, gripping: bool) -> ArrayMesh:
	# Fingers point toward -Z, with the palm on -Y and the thumb facing the midline.
	var parts: Array = [
		[Vector3(0, 0, -0.008), Vector3(0.090, 0.062, 0.064), Color(0.90, 0.90, 0.90)],
		[Vector3(0, 0, -0.064), Vector3(0.133, 0.063, 0.100), Color.WHITE],
	]
	var widths := [0.029, 0.030, 0.027, 0.023]
	var lengths := [0.077, 0.087, 0.073, 0.061]
	var offsets := [0.044, 0.014, -0.016, -0.044]
	for finger in range(4):
		var x: float = thumb_side * offsets[finger]
		var width: float = widths[finger]
		var length: float = lengths[finger]
		if gripping:
			parts.append([Vector3(x, -0.048, -0.115), Vector3(width, 0.049, 0.064), Color.WHITE,
				Basis(Vector3.RIGHT, -0.92)])
			parts.append([Vector3(x, -0.087, -0.078), Vector3(width, 0.034, 0.066), Color(0.91, 0.91, 0.91)])
		else:
			var fan := Basis.from_euler(Vector3(-0.18 - finger * 0.049, -x * 1.85, 0.0))
			parts.append([Vector3(x, -0.009 - finger * 0.003, -0.099 - length * 0.43),
				Vector3(width, 0.041, length), Color(0.97, 0.97, 0.97), fan])
	var thumb_bend := Basis.from_euler(Vector3(-0.33, -thumb_side * 0.64, 0.0))
	var thumb := Vector3(thumb_side * 0.072, -0.020, -0.063)
	if gripping:
		thumb.y = -0.048
		thumb.z = -0.057
	parts.append([thumb, Vector3(0.042, 0.046, 0.077), Color(0.88, 0.88, 0.88), thumb_bend])
	return WastelandLook.mesh_parts(parts, 0.14)

# A section stores its height, half-width, half-depth and forward/back offset.
# Successive elliptical sections define the silhouette and anatomical landmarks.
class Sculpture extends WastelandScenery:
	var cached := false
	# Only head meshes carry this vertex flag. Skin and fur accept native
	# facial pigment while hair, helmets, horns, tusks and ears retain theirs.
	var face_surface := -1
	func triangle(a:Vector3,b:Vector3,c:Vector3,outside:Vector3,color:Color) -> void:
		if face_surface>=0:
			buffer.set_uv2(Vector2(float(face_surface),0))
		super.triangle(a,b,c,outside,color)
	func loft(sections: Array, color: Color, offset := Vector3.ZERO, rotation := Basis.IDENTITY, sides := 12, fur_pattern := 0) -> void:
		if cached:
			return
		buffer.set_smooth_group(0)
		var previous := PackedVector3Array()
		var last_center := Vector3.ZERO
		for row: Vector4 in sections:
			var center := offset + rotation * Vector3(0, row.x, row.w)
			var ring := PackedVector3Array()
			for i in sides:
				var theta := TAU * (i + 0.5) / sides
				ring.append(center + rotation * Vector3(cos(theta) * row.y, 0, sin(theta) * row.z))
			for i in sides:
				var j := (i + 1) % sides
				if previous.is_empty():
					triangle(center, ring[i], ring[j], rotation * Vector3.DOWN, color)
				else:
					var outside := (ring[i] + ring[j] + previous[i] + previous[j]) * 0.25 - (last_center + center) * 0.5
					var surface_color := color
					if fur_pattern != 0:
						var radial:=Vector3(cos(TAU*(i+1)/sides),0,sin(TAU*(i+1)/sides))
						var across:=rotation*radial
						if fur_pattern==1 and across.y>0.15 and across.y<0.83:
							surface_color = Color("#413d40")
						elif fur_pattern==2 and across.y>0.80:
							surface_color = color.darkened(0.22)
					triangle(previous[i], ring[i], previous[j], outside, surface_color)
					triangle(previous[j], ring[i], ring[j], outside, surface_color)
				if row == sections.back():
					triangle(center, ring[j], ring[i], rotation * Vector3.UP, color)
			previous = ring
			last_center = center
		buffer.set_smooth_group(-1)

	func oval(center: Vector3, size: Vector3, pigment: Color, tilt := 0.0, fur_pattern := 0) -> void:
		if cached:
			return
		loft([Vector4(-0.96*size.y,0.22*size.x,0.20*size.z,0),
			Vector4(-0.65*size.y,0.78*size.x,0.77*size.z,0),Vector4(0,size.x,size.z,0),
			Vector4(0.68*size.y,0.74*size.x,0.74*size.z,0),Vector4(size.y,0.16*size.x,0.17*size.z,0)],
			pigment,center,Basis(Vector3.BACK,tilt),10,fur_pattern)

	func twig(points: Array, radii: Array, pigment: Color, sides := 7) -> void:
		if cached:
			return
		tube(PackedVector3Array(points),PackedFloat32Array(radii),sides,pigment)

static var anatomy: Dictionary = {}

static func _base_key(actor:Node3D,joint:String)->String:
	if actor.type in ["bloater","spitter"]:
		return "%s/%s/base%d/%s"%[actor.type,actor.morph,actor.look_index,joint]
	return actor.type+"/"+actor.morph+"/"+joint

static func _sculpt(actor: Node3D, joint: String, seed_value: int) -> Sculpture:
	var sculpt:=Sculpture.new(seed_value)
	sculpt.cached=anatomy.has(_base_key(actor,joint))
	return sculpt

static func _finish(actor: Node3D, joint: String, sculpt: Sculpture) -> void:
	var key:=_base_key(actor,joint)
	if not anatomy.has(key):
		anatomy[key] = sculpt.commit()
	var surface := MeshInstance3D.new()
	surface.mesh = anatomy[key]
	surface.material_override = actor._toon_material(Color.WHITE)
	actor.body_parts[joint].add_child(surface)

# Head-local mask center and size. Long muzzles slope from the brow down toward the nose.
static func attach_april_face(actor: Node3D) -> void:
	preload("res://game/art/species_faces.gd").attach_land(actor)
	var at:=Vector3(0,0.132,-0.216)
	var dimensions:=Vector2(0.289,0.301)
	var tilt:=0.05
	match actor.type:
		"brute":
			at=Vector3(0,0.105,-0.227)
			dimensions=Vector2(0.323,0.271)
		"screamer":
			at=Vector3(0,0.131,-0.223)
			dimensions=Vector2(0.244,0.293)
		"stag":
			at=Vector3(0,0.509,-0.546)
			dimensions=Vector2(0.262,0.325)
			tilt=0.75
		"boar":
			at=Vector3(0,-0.052,-0.672)
			dimensions=Vector2(0.337,0.335)
			tilt=0.65
		"fox":
			at=Vector3(0,0.027,-0.302)
			dimensions=Vector2(0.214,0.214)
			tilt=0.62
		"hare":
			at=Vector3(0,0.023,-0.149)
			dimensions=Vector2(0.164,0.160)
			tilt=0.26
		"wolf":
			at=Vector3(0,0.040,-0.399)
			dimensions=Vector2(0.303,0.300)
			tilt=0.71
		"badger":
			at=Vector3(0,0.017,-0.311)
			dimensions=Vector2(0.217,0.220)
			tilt=0.63
	if actor.type in ["argali","jerboa","otter"]:
		var h:=0.142 if actor.type=="argali" else 0.060 if actor.type=="jerboa" else 0.109
		at=Vector3(0,0,-2.21*h)
		dimensions=Vector2(2.1*h,1.7*h)
	var head_scale:=1.15 if actor.morph=="young" else 1.0
	preload("res://game/art/april_face.gd").attach(actor.body_parts.head,at*head_scale,dimensions*head_scale,Vector3(tilt,0,0))

static func upright(actor: Node3D, v: int, coat: Color, skin: Color) -> void:
	var civilian:bool=actor.type in ["bloater","spitter"]
	if civilian: coat=InfectedLooks.coat_for(actor.type,actor.look_index)
	if InfectedLooks.count_for(actor.type) > 0:
		skin = InfectedLooks.skin_for(actor.type, skin)
	var wide: float = [0.235,0.24,0.23,0.27,0.33,0.199][v]
	var pelvis_y := 0.80 if v!=5 else 0.82
	var fabric := Color("#55465a") if v==2 else Color("#665d6b") if v==5 else coat.darkened(0.30)
	var neck := -0.076 if v in [0,2,5] else -0.035
	actor._joint("hips",-1,Vector3(0,pelvis_y,0),[])
	var hips := _sculpt(actor,"hips",10)
	hips.loft([Vector4(-0.13,wide*0.64,0.108,0.026),Vector4(-0.055,wide*0.88,0.156,0.022),Vector4(0.095,wide*0.79,0.134,0)],fabric)
	hips.loft([Vector4(0.052,wide*0.83,0.141,0.005),Vector4(0.091,wide*0.81,0.140,0.002)],Color("#534444"))
	_finish(actor,"hips",hips)
	actor._joint("torso",0,Vector3(0,0.20,0.010),[])
	var torso := _sculpt(actor,"torso",11)
	torso.loft([Vector4(-0.123,wide*0.74,0.133,0.015),Vector4(0.012,wide*0.79,0.147,0.014),
		Vector4(0.164,wide*0.94,0.172,0.011),Vector4(0.30,wide*1.10,0.181,-0.005),
		Vector4(0.370,wide,0.154,-0.017),Vector4(0.422,wide*0.48,0.092,neck*0.55)],coat)
	torso.loft([Vector4(0.37,0.100,0.091,-0.024),Vector4(0.48,0.073,0.079,neck)],skin.darkened(0.23))
	actor._joint("head",1,Vector3(0,0.46,neck),[])
	var head := _sculpt(actor,"head",12)
	head.face_surface=1
	InfectedLooks.skull(head,skin,1.10 if v==4 else 0.91 if v==5 else 1.0)
	head.face_surface=0
	if not civilian: _identity(head,torso,v,wide,coat,skin)
	if actor.type in ["mudwalker","sandrunner"]: load("res://game/art/frontier_animals.gd").infected(actor,head,torso)
	if v in [0,5] and not civilian:
		# Split coat tails overlap at the waist and expose the moving legs below.
		for i in 15:
			var a := TAU * i / 15.0
			var b := TAU * (i+1) / 15.0
			if v==0 and i in [8,9,10]:
				continue
			var lower := -0.31 if v==5 else -0.16
			var tail_a:=Vector3(cos(a)*wide*1.10,lower-(i%3)*0.037,sin(a)*0.172+0.015)
			var tail_b:=Vector3(cos(b)*wide*1.10,lower-((i+1)%3)*0.037,sin(b)*0.172+0.015)
			var upper_a:=Vector3(cos(a)*wide*0.86,0.063,sin(a)*0.147+0.013)
			var upper_b:=Vector3(cos(b)*wide*0.86,0.063,sin(b)*0.147+0.013)
			var normal:=Vector3(cos(a),0,sin(a))
			var shade:=coat.darkened(0.09+(i%3)*0.048)
			torso.triangle(upper_a,tail_a,tail_b,normal,shade)
			torso.triangle(upper_a,tail_b,upper_b,normal,shade)
	_finish(actor,"torso",torso)
	_finish(actor,"head",head)
	var muscular := 1.30 if v == 4 else 0.81 if v == 5 else 1.0
	for side in [-1,1]:
		var suffix := "l" if side<0 else "r"
		var arm := "arm_"+suffix
		var elbow := "elbow_"+suffix
		var leg := "leg_"+suffix
		var knee := "knee_"+suffix
		actor._joint(arm,1,Vector3(side*(wide+0.053),0.30,-0.014),[])
		var sleeve := _sculpt(actor,arm,13)
		var radius := 0.109*muscular
		var sleeve_color:=skin if v==2 and side<0 else coat
		if actor.type=="bloater" and actor.look_index==2: sleeve_color=Color("#79726b")
		sleeve.loft([Vector4(-0.264,radius*0.57,0.069,-0.006),Vector4(-0.175,radius*0.77,0.093,-0.007),
			Vector4(-0.074,radius,0.107,0),Vector4(0.012,radius*1.04,0.110,0),Vector4(0.063,radius*0.51,0.060,0)],sleeve_color)
		if v in [3,4] and not civilian:
			sleeve.oval(Vector3(0,-0.016,0),Vector3(radius*1.18,0.093,0.127),coat.darkened(0.24))
		_finish(actor,arm,sleeve)
		actor._joint(elbow,actor.skeleton.find_bone(arm),Vector3(0,-0.253,-0.01),[])
		var forearm := _sculpt(actor,elbow,14)
		var forearm_color:=skin if v!=3 else coat.darkened(0.30)
		if civilian: forearm_color=skin if actor.look_index==0 else sleeve_color
		forearm.loft([Vector4(-0.242,0.045*muscular,0.045,-0.056),Vector4(-0.171,0.054*muscular,0.054,-0.043),
			Vector4(-0.073,0.077*muscular,0.080,-0.029),Vector4(-0.008,0.068*muscular,0.067,0),
			Vector4(0.033,0.050,0.049,0.004)],forearm_color)
		if civilian and actor.look_index==0:
			forearm.loft([Vector4(-0.079,0.083,0.084,-0.028),Vector4(-0.005,0.072,0.072,0.0)],sleeve_color)
		if v==2 and side<0:
			for i in 3:
				var start:=Vector3(-0.052,-0.10+i*0.054,0.027)
				forearm.twig([start,start+Vector3(-0.055,0.035,0.036),start+Vector3(-0.09,0.090,0.055)],[0.032,0.031,0.003],Color("#bed87e"),5)
		if v in [0,4,5] and side<0 and not civilian:
			for i in 3:
				forearm.loft([Vector4(-0.164+i*0.031,0.064*muscular+i*0.004,0.067+i*0.004,-0.037),
					Vector4(-0.14+i*0.031,0.067*muscular+i*0.004,0.07+i*0.004,-0.039)],
					Color("#a59981").darkened((i%2)*0.18))
		_finish(actor,elbow,forearm)
		actor._hand(side,Vector3(0,-0.229,-0.060),deg_to_rad(-75.0),skin,v==4 and side>0)
		actor._joint(leg,0,Vector3(side*wide*0.55,-0.055,0),[])
		var thigh := _sculpt(actor,leg,15)
		var trouser := fabric if v!=5 else coat.darkened(0.17)
		thigh.loft([Vector4(-0.347,0.064*muscular,0.081,-0.019),Vector4(-0.259,0.080*muscular,0.097,-0.014),
			Vector4(-0.112,0.105*muscular,0.129,0.012),Vector4(0.036,0.10*muscular,0.110,0.018)],trouser)
		_finish(actor,leg,thigh)
		actor._joint(knee,actor.skeleton.find_bone(leg),Vector3(0,-0.322,-0.021),[])
		var shin := _sculpt(actor,knee,16)
		shin.loft([Vector4(-0.326,0.054*muscular,0.069,0.019),Vector4(-0.151,0.076*muscular,0.091,0.033),
			Vector4(-0.063,0.081*muscular,0.092,0.021),Vector4(0.038,0.068*muscular,0.079,0)],trouser.darkened(0.09))
		_finish(actor,knee,shin)
		var ankle := "ankle_"+suffix
		var ankle_position := Vector3(0,-0.316,0.017)
		actor._joint(ankle,actor.skeleton.find_bone(knee),ankle_position,[])
		var boot := _sculpt(actor,ankle,17)
		var leather := Color("#4a4145")
		boot.loft([Vector4(-0.405,0.084*muscular,0.134,-0.046),Vector4(-0.380,0.089*muscular,0.142,-0.049),
			Vector4(-0.335,0.085*muscular,0.126,-0.044),Vector4(-0.277,0.068*muscular,0.082,0.009),
			Vector4(-0.228,0.068*muscular,0.080,0.017)],leather,-ankle_position)
		if v in [0,3,4]:
			for band in 2:
				boot.loft([Vector4(-0.279+band*0.035,0.071*muscular,0.085,0.015),Vector4(-0.268+band*0.035,0.072*muscular,0.085,0.015)],leather.lightened(0.10),-ankle_position)
		_finish(actor,ankle,boot)
	if v==4:
		_hammer(actor)
	if InfectedLooks.count_for(actor.type) > 0:
		_attach_look(actor)

static func _attach_look(actor: Node3D) -> void:
	var look: int = actor.look_index
	for joint: String in InfectedLooks.joints_for(actor.type):
		var key := "%s/look%d/%s" % [actor.type, look, joint]
		if not anatomy.has(key):
			var accent := Sculpture.new(91)
			InfectedLooks.sculpt(accent, actor.type, look, joint)
			anatomy[key] = accent.commit()
		var part := MeshInstance3D.new()
		part.name = "LookDetail"
		part.mesh = anatomy[key]
		if not actor.render_colors.has("look_surface"):
			var paint := ShaderMaterial.new()
			paint.shader = preload("res://shaders/infected_surface.gdshader")
			actor.render_colors["look_surface"] = paint
		part.material_override = actor._toon_material(Color.WHITE) if actor.type in ["spitter","bloater"] else actor.render_colors["look_surface"]
		actor.body_parts[joint].add_child(part)

static func gland_mesh(kind: String, look: int) -> ArrayMesh:
	var key := "%s/look%d/gland" % [kind,look]
	if not anatomy.has(key):
		var organ := Sculpture.new(97)
		InfectedLooks.sculpt_gland(organ, kind, look)
		anatomy[key] = organ.commit()
	return anatomy[key]

static func gland_material(actor: Node3D) -> ShaderMaterial:
	if actor.type in ["bloater","spitter"]: return actor._toon_material(Color.WHITE)
	if not actor.render_colors.has("gland_membrane"):
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://shaders/infected_surface.gdshader")
		paint.set_shader_parameter("signal_glow", 0.55)
		actor.render_colors["gland_membrane"] = paint
	return actor.render_colors["gland_membrane"]

static func _identity(head: Sculpture, body: Sculpture, v: int, w: float, coat: Color, skin: Color) -> void:
	match v:
		0:
			# A worker's receding hairline, split shirt collar and sagging canvas jacket.
			head.loft([Vector4(0.203,0.151,0.139,0.015),Vector4(0.265,0.142,0.141,0.007),
				Vector4(0.319,0.065,0.071,0.014)],Color("#554e43"),Vector3.ZERO,Basis.IDENTITY,24)
			for side in [-1,1]:
				body.triangle(Vector3(side*0.113,0.405,-0.124),Vector3(side*0.157,0.274,-0.164),
					Vector3(side*0.027,0.194,-0.183),Vector3.FORWARD,coat.lightened(0.24))
			var fold:=coat.darkened(0.27)
			for i in 3:
				var start:=Vector3(0.08,0.05+i*0.088,-0.147-i*0.006)
				body.twig([start,start+Vector3(0.052,0.014,0.006),start+Vector3(0.103,0.035,0.047)],[0.008,0.009,0.001],fold,5)
			body.twig([Vector3(-0.11,0.379,-0.126),Vector3(-0.052,0.19,-0.178),Vector3(0.092,-0.065,-0.13)],[0.023,0.022,0.020],Color("#765337"),6)
		2:
			# Asymmetric mineral fan grows from the back and continues through one arm.
			for i in 8:
				var root := Vector3(-0.22 + i*0.050,0.22+sin(i*1.8)*0.05,0.115)
				var extent := Vector3(-0.18+i*0.040,0.11+0.17*(1.0-float(i)/8.0),0.12+0.06*sin(i))
				body.twig([root,root+extent*0.39,root+extent*0.79,root+extent],
					[0.045,0.066,0.037,0.002],Color("#c4dc85").darkened((i%3)*0.10),5)
			for side in [-1,1]:
				for i in 3:
					body.twig([Vector3(side*0.169,0.16+i*0.051,-0.126),Vector3(side*0.095,0.13+i*0.053,-0.171),Vector3(side*0.027,0.112+i*0.052,-0.165)],
						[0.016,0.021,0.012],skin.darkened(i*0.08),5)
		4:
			head.loft([Vector4(0.188,0.205,0.201,-0.013),Vector4(0.206,0.205,0.197,-0.015),
				Vector4(0.224,0.178,0.165,0),Vector4(0.302,0.156,0.147,0.009),
				Vector4(0.335,0.095,0.089,0.009)],Color("#b98b48"))
			head.oval(Vector3(0,0.262,-0.146),Vector3(0.052,0.040,0.036),Color("#e7c887"))
			body.loft([Vector4(-0.065,w*0.85,0.153,0.01),Vector4(0.078,w,0.190,-0.009),
				Vector4(0.215,w*1.10,0.212,-0.007),Vector4(0.329,w*1.12,0.186,0),Vector4(0.389,w*0.82,0.159,0)],coat.darkened(0.09))
			for side in [-1,1]:
				body.twig([Vector3(side*w*0.65,-0.045,-0.114),Vector3(side*w*0.46,0.162,-0.199),Vector3(side*w*0.57,0.35,-0.145),Vector3(side*w*0.53,0.392,0.045)],
					[0.030,0.032,0.032,0.030],Color("#c09b61"),6)
		5:
			var veil:=Color("#645769")
			head.loft([Vector4(0.153,0.146,0.124,0.024),Vector4(0.241,0.160,0.145,0.013),
				Vector4(0.309,0.132,0.124,0.026),Vector4(0.354,0.036,0.046,0.053)],veil)
			for side in [-1,1]:
				head.oval(Vector3(side*0.122,0.124,0.008),Vector3(0.042,0.142,0.074),veil,-side*0.13)
				body.twig([Vector3(side*0.05,0.433,-0.075),Vector3(side*0.082,0.34,-0.16),Vector3(side*0.129,0.24,-0.152)],[0.018,0.025,0.012],skin)
			# The mantle opens over the chest; alternating hem lengths break its outline.
			for i in 10:
				var a := lerpf(-0.96,4.10,i/10.0)
				var b := lerpf(-0.96,4.10,(i+1)/10.0)
				var top_a:=Vector3(sin(a)*0.131,0.397,cos(a)*0.13)
				var top_b:=Vector3(sin(b)*0.131,0.397,cos(b)*0.13)
				var end_a:=Vector3(sin(a)*0.249,0.12+(i%2)*0.045,cos(a)*0.204)
				var end_b:=Vector3(sin(b)*0.249,0.12+((i+1)%2)*0.045,cos(b)*0.204)
				var normal:=Vector3(sin(a),0,cos(a))
				body.triangle(top_a,end_a,end_b,normal,coat.darkened(0.16+(i%3)*0.045))
				body.triangle(top_a,end_b,top_b,normal,coat.darkened(0.14+(i%3)*0.045))

static func _hammer(actor: Node3D) -> void:
	var grip := Marker3D.new()
	grip.name = "HammerGrip"
	grip.position = Vector3(0,-0.059,-0.077)
	grip.rotation.z = -PI*0.5
	actor.body_parts.hand_r.add_child(grip)
	var hammer := MeshInstance3D.new()
	hammer.name = "Hammer"
	hammer.mesh = WastelandItemArt.mesh("sledge",actor.session.catalog.items.sledge)
	hammer.material_override = WastelandLook.colored_material()
	hammer.scale = Vector3.ONE*0.92
	hammer.position = -SLEDGE_GRIP_POINT*hammer.scale.x
	grip.add_child(hammer)

static func crawler(actor: Node3D, coat: Color, skin: Color) -> void:
	var fabric:=coat.darkened(0.29)
	actor._joint("hips",-1,Vector3(0,0.477,0.239),[])
	var hips:=_sculpt(actor,"hips",28)
	hips.oval(Vector3.ZERO,Vector3(0.180,0.124,0.171),fabric)
	_finish(actor,"hips",hips)
	actor._joint("torso",0,Vector3(0,-0.073,-0.352),[])
	var chest:=_sculpt(actor,"torso",29)
	chest.loft([Vector4(-0.226,0.103,0.095,-0.018),Vector4(-0.124,0.188,0.131,-0.018),Vector4(0.068,0.200,0.149,0.011),
		Vector4(0.204,0.132,0.108,0.009),Vector4(0.29,0.12,0.103,0.004)],coat,Vector3.ZERO,Basis(Vector3.RIGHT,PI*0.5))
	for i in 6:
		chest.oval(Vector3(0,0.137-i*0.003,-0.095+i*0.056),Vector3(0.029,0.034,0.036),skin.darkened(0.23))
	_finish(actor,"torso",chest)
	actor._joint("head",1,Vector3(0,-0.05,-0.31),[])
	var head:=_sculpt(actor,"head",30)
	head.face_surface=1
	InfectedLooks.skull(head,skin)
	head.face_surface=0
	_finish(actor,"head",head)
	for side in [-1,1]:
		var suffix:="l" if side<0 else "r"
		var arm:="arm_"+suffix
		var elbow:="elbow_"+suffix
		var leg:="leg_"+suffix
		actor._joint(arm,1,Vector3(side*0.205,-0.005,-0.107),[])
		var upper:=_sculpt(actor,arm,31)
		upper.twig([Vector3.ZERO,Vector3(side*0.052,-0.065,0.046),Vector3(side*0.113,-0.158,0.110)],[0.082,0.105,0.062],coat)
		_finish(actor,arm,upper)
		actor._joint(elbow,actor.skeleton.find_bone(arm),Vector3(side*0.113,-0.158,0.11),[])
		var fore:=_sculpt(actor,elbow,32)
		fore.twig([Vector3.ZERO,Vector3(side*0.012,-0.036,-0.066),Vector3(side*0.014,-0.134,-0.231)],[0.067,0.084,0.044],skin)
		_finish(actor,elbow,fore)
		actor._hand(side,Vector3(side*0.014,-0.134,-0.231),-0.49,skin)
		actor._joint(leg,0,Vector3(side*0.139,-0.032,0.08),[])
		var knee_at := Vector3(side*0.09,-0.28,-0.143)
		var ankle_at := Vector3(side*0.071,-0.340,0.206)
		var knee := "knee_"+suffix
		var ankle := "ankle_"+suffix
		var rear:=_sculpt(actor,leg,33)
		rear.twig([Vector3.ZERO,Vector3(side*0.062,-0.147,-0.082),knee_at],[0.100,0.109,0.080],fabric)
		_finish(actor,leg,rear)
		actor._joint(knee,actor.skeleton.find_bone(leg),knee_at,[])
		var calf := _sculpt(actor,knee,34)
		calf.twig([Vector3.ZERO,Vector3(side*0.098,-0.319,0.036)-knee_at,ankle_at-knee_at],[0.080,0.067,0.041],fabric)
		_finish(actor,knee,calf)
		actor._joint(ankle,actor.skeleton.find_bone(knee),ankle_at-knee_at,[])
		var foot := _sculpt(actor,ankle,35)
		foot.oval(Vector3(-side*0.004,-0.013,-0.002),Vector3(0.058,0.053,0.109),Color("#574748"))
		_finish(actor,ankle,foot)
static func wildlife(actor: Node3D, kind: String, coat: Color, skin: Color) -> void:
	if kind in ["argali","jerboa","otter"]:
		load("res://game/art/frontier_animals.gd").animal(actor,kind,coat,skin)
		return
	if kind in ["fox","hare","wolf","badger"]:
		_small_wildlife(actor,kind,coat,skin)
		return
	var anatomy_rig = load("res://game/art/wildlife_rig.gd")
	var tall:=kind=="stag"
	var y:=0.82 if tall else 0.54
	var pitch_axis:=Basis(Vector3.RIGHT,PI*0.5)
	var muzzle:=Color("#403b3b")
	actor._joint("torso",-1,Vector3(0,y,0),[])
	var body:=_sculpt(actor,"torso",41)
	if tall:
		body.loft([Vector4(-0.50,0.10,0.13,-0.03),Vector4(-0.36,0.193,0.253,0.0),Vector4(-0.19,0.221,0.291,0.011),
			Vector4(0.054,0.185,0.233,0.022),Vector4(0.26,0.21,0.246,0.003),Vector4(0.41,0.166,0.210,0),Vector4(0.49,0.073,0.104,0.023)],coat,Vector3.ZERO,pitch_axis,16,2 if actor.morph=="local" else 0)
	else:
		body.loft([Vector4(-0.55,0.128,0.180,-0.03),Vector4(-0.38,0.251,0.325,-0.055),
			Vector4(-0.18,0.278,0.316,-0.053),Vector4(0.095,0.261,0.272,-0.018),
			Vector4(0.27,0.216,0.21,0.019),Vector4(0.41,0.13,0.162,0.04),Vector4(0.46,0.070,0.099,0.052)],coat,Vector3.ZERO,pitch_axis,16,2 if actor.morph=="local" else 0)
		for i in 13:
			var z:=-0.46+i*0.055
			var height:=0.379-maxf(z+0.20,0)*0.31
			body.twig([Vector3(sin(i)*0.043,height-0.09,z),Vector3(sin(i)*0.041,height-0.01,z+0.023),
				Vector3(sin(i)*0.032,height+0.050+(i%3)*0.018,z+0.071)],[0.052,0.037,0.002],coat.darkened(0.24),5)
	_finish(actor,"torso",body)
	anatomy_rig.neck(actor,Vector3(0,0.051,-0.35))
	var head:=_sculpt(actor,"head",42)
	head.face_surface=1
	if tall:
		head.face_surface=0
		head.loft([Vector4(-0.055,0.147,0.159,0.048),Vector4(0.11,0.143,0.148,0.017),
			Vector4(0.272,0.109,0.130,-0.067),Vector4(0.422,0.087,0.112,-0.135),Vector4(0.507,0.082,0.096,-0.18)],coat)
		head.face_surface=1
		head.loft([Vector4(-0.52,0.051,0.048,0.075),Vector4(-0.447,0.067,0.069,0.050),
			Vector4(-0.35,0.085,0.084,0.025),Vector4(-0.246,0.123,0.134,0),Vector4(-0.155,0.096,0.115,-0.015),
			Vector4(-0.117,0.068,0.078,-0.016)],skin,Vector3(0,0.509,0),pitch_axis)
		head.oval(Vector3(0,0.445,-0.515),Vector3(0.060,0.044,0.040),muzzle)
		for side in [-1,1]:
			head.face_surface=0
			var path:=[Vector3(side*0.055,0.599,-0.19),Vector3(side*0.117,0.746,-0.174),
				Vector3(side*0.21,0.812,-0.102),Vector3(side*0.27,0.932,-0.010),Vector3(side*0.318,1.04,0.114)]
			if actor.morph=="young":
				head.twig([path[0],path[0]+Vector3(side*0.028,0.089,0.016)],[0.025,0.009],Color("#a59480"))
				continue
			head.twig(path,[0.031,0.029,0.024,0.015,0.003],Color("#b29a7e"))
			for t in range(1,4):
				var start:Vector3=path[t]
				head.twig([start,start+Vector3(side*0.013,0.057,-0.046),start+Vector3(side*0.041,0.125+(t%2)*0.03,-0.075)],
					[0.021,0.017,0.003],Color("#c2aa8e"),6)
	else:
		head.loft([Vector4(-0.616,0.094,0.069,0.109),Vector4(-0.51,0.095,0.095,0.086),
			Vector4(-0.36,0.144,0.145,0.047),Vector4(-0.23,0.183,0.194,-0.015),
			Vector4(-0.06,0.181,0.192,-0.040),Vector4(0.048,0.125,0.145,0)],coat,Vector3.ZERO,pitch_axis,16,2 if actor.morph=="local" else 0)
		head.oval(Vector3(0,-0.107,-0.601),Vector3(0.108,0.066,0.038),skin.darkened(0.13))
		for side in [-1,1]:
			head.face_surface=0
			head.twig([Vector3(side*0.105,-0.144,-0.434),Vector3(side*0.154,-0.153,-0.494),Vector3(side*0.188,-0.116,-0.532),
				Vector3(side*0.193,-0.050,-0.54)],[0.034,0.035,0.025,0.004],Color("#dfcba7"))
	_finish(actor,"head",head)
	anatomy_rig.ears(actor,coat,skin)
	if tall:
		anatomy_rig.tail(actor,Vector3(0,0.10,0.398),Vector3(0,-0.081,0.083),Vector3(0,-0.17,0.092),Vector3(0.048,0.059,0.014),Color("#b49a78"),Color("#d7b98b"))
	else:
		anatomy_rig.tail(actor,Vector3(0,0.098,0.41),Vector3(0.023,-0.097,0.062),Vector3(0.035,-0.21,0.071),Vector3(0.020,0.014,0.010),coat,coat.darkened(0.33))
	anatomy_rig.legs(actor,y,0.10,0.15 if tall else 0.173,0.285,-0.286,0.089 if tall else 0.091,coat,skin)

static func _small_wildlife(actor: Node3D, kind: String, coat: Color, skin: Color) -> void:
	var anatomy_rig = load("res://game/art/wildlife_rig.gd")
	var fox:=kind=="fox"
	var hare:=kind=="hare"
	var wolf:=kind=="wolf"
	var badger:=kind=="badger"
	var dark:=Color("#403b40")
	var cream:=Color("#d7cdb7")
	var axial:=Basis(Vector3.RIGHT,PI*0.5)
	var hip_y:=0.44 if fox else 0.23 if hare else 0.65 if wolf else 0.25
	var length:=0.37 if fox else 0.235 if hare else 0.52 if wolf else 0.34
	var width:=0.112 if fox else 0.115 if hare else 0.166 if wolf else 0.164
	var depth:=0.146 if fox else 0.132 if hare else 0.208 if wolf else 0.147
	actor._joint("torso",-1,Vector3(0,hip_y,0),[])
	var torso:=_sculpt(actor,"torso",61)
	torso.loft([Vector4(-length,width*0.48,depth*0.66,-depth*0.21),Vector4(-length*0.63,width*1.06,depth*1.1,-depth*0.13),
		Vector4(-length*0.21,width,depth,0),Vector4(length*0.24,width*0.88,depth*0.82,0),
		Vector4(length*0.64,width*1.03,depth*1.05,-depth*0.05),Vector4(length,width*0.57,depth*0.63,0)],coat,Vector3.ZERO,axial,16,2 if actor.morph=="local" else 0)
	if hare:
		torso.oval(Vector3(0,0.01,0.065),Vector3(0.134,0.161,0.177),coat)
	elif wolf:
		for side in [-1,1]:
			torso.twig([Vector3(side*0.077,0.074,-length*0.58),Vector3(side*0.152,0.102,-length*0.63),
				Vector3(side*0.190,0.048,-length*0.39)],[0.102,0.075,0.004],coat.darkened(0.18),7)
	elif badger:
		torso.oval(Vector3(0,depth*0.51,0.057),Vector3(width*0.91,depth*0.58,length*0.70),coat.lightened(0.12))
	_finish(actor,"torso",torso)
	var head_y:=0.082 if fox else 0.103 if hare else 0.137 if wolf else 0.033
	anatomy_rig.neck(actor,Vector3(0,head_y,-length*0.80))
	var head:=_sculpt(actor,"head",62)
	head.face_surface=1
	var size:=0.85 if fox else 0.63 if hare else 1.17 if wolf else 0.81
	var skull:=Color("#d4d0bd") if badger else coat
	var nose_z:=-0.114 if hare else -0.36 if wolf else -0.274
	head.oval(Vector3(0,0.021*size,-0.025),Vector3(size*0.144,size*0.134,size*0.164),skull,0,1 if badger else 0)
	head.loft([Vector4(nose_z,0.041*size,0.034*size,0.017*size),Vector4(nose_z*0.74,0.061*size,0.052*size,0.014*size),
		Vector4(nose_z*0.40,0.112*size,0.094*size,-0.003*size),Vector4(-0.025,0.12*size,0.098*size,0)],skull,Vector3.ZERO,axial,20,1 if badger else 0)
	head.oval(Vector3(0,-0.019*size,nose_z),Vector3(0.045*size,0.031*size,0.031*size),dark)
	_finish(actor,"head",head)
	anatomy_rig.ears(actor,skull,skin)
	var tail_base := Vector3(0,0.046,length*0.83)
	if hare:
		anatomy_rig.tail(actor,tail_base,Vector3.ZERO,Vector3(0,0.040,0.090),Vector3.ZERO,cream,cream)
	elif fox:
		anatomy_rig.tail(actor,tail_base,Vector3(0.052,-0.080,0.32),Vector3(0.087,-0.026,0.536),Vector3(0.052,0.093,0.006),coat,cream)
	elif wolf:
		anatomy_rig.tail(actor,tail_base,Vector3(0,-0.152,0.203),Vector3(0.021,-0.227,0.401),Vector3(0.059,0.078,0.010),coat.darkened(0.18),coat.darkened(0.21))
	else:
		anatomy_rig.tail(actor,tail_base,Vector3(0,-0.037,0.113),Vector3(0,-0.076,0.206),Vector3(0.059,0.056,0.012),coat,coat)
	anatomy_rig.legs(actor,hip_y,0.04,width*0.66,length*0.63,-length*0.62,width*(0.53 if hare else 0.47),coat,skin)
static func mutation(actor: Node3D, armored: bool) -> void:
	var crawler_pose: bool=actor.type=="crawler"
	var shoulders: Array = ["arm_l","arm_r","torso"]
	for joint: String in shoulders:
		var accent:=Sculpture.new(83)
		var mid:=joint=="torso"
		var sign_x:=1.0 if joint=="arm_r" else -1.0
		if actor.type in ["spitter","bloater"]:
			InfectedLooks.civilian_morph(accent,actor.type,actor.look_index,joint,armored)
		elif armored and mid:
			var w:float=(0.33 if actor.type=="brute" else 0.27 if actor.type=="spitter" else 0.23)
			if crawler_pose:
				accent.oval(Vector3(0,0.128,0.04),Vector3(0.224,0.097,0.236),Color("#65676a"))
			else:
				accent.loft([Vector4(0.052,w*0.84,0.17,-0.020),Vector4(0.117,w*1.04,0.197,-0.016),
					Vector4(0.29,w*1.10,0.213,-0.018),Vector4(0.369,w*0.81,0.179,-0.023)],Color("#575d5e"))
				for i in 3:
					accent.twig([Vector3(-w*0.87,0.13+i*0.055,-0.138),Vector3(0,0.114+i*0.055,-0.218),
						Vector3(w*0.83,0.136+i*0.055,-0.141)],[0.012,0.018,0.011],Color("#a78d68"),5)
		elif armored:
			accent.oval(Vector3(sign_x*0.025,0.006,0.011),Vector3(0.157,0.116,0.162),Color("#777b73"))
			for i in 2:
				accent.oval(Vector3(sign_x*(0.067+i*0.022),-0.055-i*0.057,-0.010),Vector3(0.12-i*0.018,0.067,0.13-i*0.018),Color("#686b69"))
		else:
			for i in range(5 if mid else 2):
				var root:=Vector3((i%2-0.5)*0.082,0.13+i*0.056,0.12) if mid else Vector3(sign_x*0.073,-0.034-i*0.077,0.037)
				if crawler_pose and mid:
					root=Vector3(0,0.118,-0.11+i*0.072)
				var spur:=Vector3((i%2-0.5)*0.10,0.12+i*0.008,0.12) if mid else Vector3(sign_x*0.115,0.064,0.045)
				accent.twig([root,root+spur*0.51,root+spur],[0.043,0.029,0.003],Color("#b8a48c").darkened(i*0.042),5)
		var key:=_base_key(actor,joint)+"/mutation"
		if not anatomy.has(key):
			anatomy[key]=accent.commit()
		var feature:=MeshInstance3D.new()
		feature.mesh=anatomy[key]
		feature.material_override=actor._toon_material(Color.WHITE)
		actor.body_parts[joint].add_child(feature)
