class_name WastelandPartyAvatar
extends Node3D

const Sculpt := WastelandBestiary.Sculpture
const HEAD := preload("res://game/art/ranger_head.gd")
const LIMB := preload("res://game/art/avatar_limb.gd")
const GEAR_ART := preload("res://game/art/survivor_equipment.gd")
const SURFACE := preload("res://shaders/survivor_surface.gdshader")
static var body_material: ShaderMaterial
const OUTFITS := {"ranger":"巡护员","ferryman":"渡工","surveyor":"测绘员","mechanic":"机修工","medic":"急救员","climber":"攀岩者","bronx":"街头混混"}
const NAMES := {"ranger":"白冻梨","ferryman":"江过早","surveyor":"莫问几楼","mechanic":"鲁把串","medic":"艾微辣","climber":"蔡爱拼","bronx":"杰伦·六码"}
const ORIGINS := {"ranger":"哈尔滨","ferryman":"武汉","surveyor":"重庆","mechanic":"淄博","medic":"长沙","climber":"泉州","bronx":"纽约布朗克斯"}
const STORIES := {
	"ranger":"巡山前往窗台搁个冻梨，回来敲一声就知道夜里有多冷。",
	"ferryman":"头班船开得再早，过早的热干面也得拌匀了吃。",
	"surveyor":"在重庆长大，在西雅图测绘十五年。她的地图总标着哪层楼能走上街。",
	"mechanic":"能听声修柴油机，也能把漏风的烤炉修到一把串刚好熟。",
	"medic":"点粉只说微辣。头回跟她拼桌的人，后来都学会了自己点。",
	"climber":"岩壁上还差最后一个落脚点，她就哼起家乡那句“三分天注定”。",
	"bronx":"六号线桥下长大的非裔纽约客。朋友寄信爱打趣：邮编填个「六」就能找到他。"
}
const DESCRIPTIONS := {
	"ranger":"黑色短发，身形修长，青灰色窄领背心。",
	"ferryman":"鬓角花白，肩背宽厚，米色罗纹汗衫。",
	"surveyor":"深色束发，身形轻盈，靛蓝色运动内衣。",
	"mechanic":"棕肤卷发，身形结实，砖红色宽肩背心。",
	"medic":"深棕肤色，紧密短卷，矮壮身形配桑葚色运动背心。",
	"climber":"铜棕编发，高挑长臂，雾蓝色细肩运动背心。",
	"bronx":"两鬓渐短的黑色扭卷，肩宽腿长，穿灰白罗纹背心和墨绿平角内裤。"
}
const DYES := {
	"ranger":[Color("#496f65"),Color("#38454a"),Color("#849e91")],
	"ferryman":[Color("#c4b699"),Color("#505b60"),Color("#a99a7f")],
	"surveyor":[Color("#556c90"),Color("#454f6a"),Color("#a7b9c6")],
	"mechanic":[Color("#975c52"),Color("#50545a"),Color("#ba8973")],
	"medic":[Color("#875669"),Color("#4f4053"),Color("#c39a9d")],
	"climber":[Color("#748d99"),Color("#545969"),Color("#c2c3af")],
	"bronx":[Color("#a9afa8"),Color("#394d48"),Color("#cbd0c6")]
}
const SKIN_TONES := {"ranger":Color("#bf8c70"),"ferryman":Color("#b5876b"),"surveyor":Color("#d4a286"),"mechanic":Color("#a77758"),
	"medic":Color("#98684d"),"climber":Color("#dcb194"),"bronx":Color("#936750")}
# Shoulder, waist and hip half-widths in metres.
const WIDTHS := {"ranger":Vector3(0.217,0.154,0.172),"ferryman":Vector3(0.239,0.194,0.199),
	"surveyor":Vector3(0.184,0.142,0.181),"mechanic":Vector3(0.246,0.168,0.181),
	"medic":Vector3(0.215,0.170,0.198),"climber":Vector3(0.205,0.141,0.166),"bronx":Vector3(0.232,0.156,0.175)}
const STATURE := {"ranger":1.02,"ferryman":0.97,"surveyor":0.94,"mechanic":1.00,"medic":0.89,"climber":1.055,"bronx":1.034}
const LIMB_GIRTH := {"ranger":0.94,"ferryman":1.09,"surveyor":0.84,"mechanic":1.15,"medic":1.09,"climber":0.89,"bronx":1.03}
const LEG_LENGTH := {"ranger":1.045,"ferryman":0.94,"surveyor":1.012,"mechanic":0.99,"medic":0.95,"climber":1.09,"bronx":1.067}
const ARM_LENGTH := {"ranger":1.0,"ferryman":0.94,"surveyor":1.0,"mechanic":1.04,"medic":0.95,"climber":1.14,"bronx":1.079}
const HEAD_WIDTH := {"ranger":1.0,"ferryman":1.045,"surveyor":0.935,"mechanic":1.055,"medic":1.02,"climber":0.95,"bronx":1.018}
const SIDES := 48

static func skin_color(id: String) -> Color:
	var tone: Color = SKIN_TONES.get(id, SKIN_TONES.ranger)
	# The face atlas contains its own lighting. Bring the procedural skin into its midtone range.
	var light := Vector3(0.78,0.73,0.71)
	if id=="mechanic" or id=="medic":
		light = Vector3(0.74,0.70,0.66)
	return Color(tone.r*light.x,tone.g*light.y,tone.b*light.z)

var pivot := Node3D.new()
var jacket := Node3D.new()
var equipment := Node3D.new()
var undershirt: MeshInstance3D
var sleeves: Array[MeshInstance3D] = []
var equipped := ""
var accessories := {"head":"","legs":"","hands":"","feet":"","eyes":"","muzzle":"","back":"","pack":""}
var skull: Node3D
var neck: Node3D
var outfit := "ranger"
var arms: Array[Node3D] = []
var elbows: Array[Node3D] = []
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
const Offhand:=preload("res://game/art/offhand_art.gd")
var left_grip:Marker3D
var left_open:MeshInstance3D
var left_curled:MeshInstance3D
var offhand_id:=""
var offhand_shield:=false
var offhand_block:=false
var offhand_lit:=false
var offhand_prop:MeshInstance3D
var offhand_blend:=0.0

var preview_mainhand:=""
var preview_loaded:=false
var primary_shield:MeshInstance3D

func set_mainhand(id:String,loaded:=false)->void:
	preview_mainhand=id
	preview_loaded=loaded
	if not is_instance_valid(grip): return
	var model:="field_crossbow_empty" if id=="field_crossbow" and not loaded else id
	if grip.get_meta("preview_model","?")==model: return
	grip.set_meta("preview_model",model)
	primary_shield=null
	var prop:=grip.get_node_or_null("PreviewMainhand") as MeshInstance3D
	if prop:
		grip.remove_child(prop)
		prop.queue_free()
	if id.is_empty(): return
	var definition:=Offhand.item(id)
	if definition.is_empty(): return
	prop=MeshInstance3D.new()
	prop.name="PreviewMainhand"
	prop.mesh=WastelandItemArt.mesh(model,definition)
	prop.material_override=WastelandLook.colored_material()
	prop.scale=Vector3.ONE*(0.76 if definition.kind in ["weapon","tool","ranged"] else 0.42)
	prop.rotation.x=-1.25 if id=="reed_spear" else -0.93 if definition.kind in ["weapon","tool"] else 0.0
	if definition.get("shield",false):
		primary_shield=prop
		prop.scale=Vector3.ONE
		prop.rotation=Vector3.ZERO
	grip.add_child(prop)

func set_offhand(id:String,blocking:=false,lit:=true)->void:
	var changed:=id!=offhand_id
	offhand_id=id
	offhand_shield=Offhand.item(id).get("shield",false)
	offhand_block=blocking and offhand_shield
	offhand_lit=lit
	if not is_instance_valid(left_grip): return
	if changed and is_instance_valid(offhand_prop):
		left_grip.remove_child(offhand_prop)
		offhand_prop.queue_free()
		offhand_prop=null
	if not id.is_empty() and not is_instance_valid(offhand_prop):
		offhand_prop=Offhand.prop(id,false)
		if offhand_prop:
			left_grip.add_child(offhand_prop)
	if id=="torch" and is_instance_valid(offhand_prop): offhand_prop.get_node("LitGlass").visible=lit
	Offhand.sync_world_light(left_grip,id,lit)
	left_open.visible=id.is_empty()
	left_curled.visible=not id.is_empty()

var grip:Marker3D
var relaxed_digits:MeshInstance3D
var curled_digits:MeshInstance3D
var wrist_joints: Array[Node3D] = []
var ankle_joints: Array[Node3D] = []
var arm_rigs: Array[Skeleton3D] = []
var leg_rigs: Array[Skeleton3D] = []
var shorts_rig: Skeleton3D
var stride := 0.0
var show_tag := true
var player_name := WastelandSettings.DEFAULT_PLAYER_NAME
var name_tag: Label3D

func _ready() -> void:
	add_child(pivot)
	if show_tag:
		name_tag = Label3D.new()
		name_tag.font = WastelandUIStyle.FONT
		name_tag.font_size = 24
		name_tag.modulate = Color("#bde5d4")
		name_tag.outline_size = 4
		name_tag.pixel_size = 0.0038
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(name_tag)
		_update_name_tag()
	_build_body()

func set_player_name(value: String) -> void:
	player_name = WastelandSettings.clean_player_name(value)
	_update_name_tag()

func _update_name_tag() -> void:
	if is_instance_valid(name_tag):
		name_tag.text = "%s\n%s · %s" % [player_name,NAMES[outfit],OUTFITS[outfit]]
		name_tag.position.y = 1.81 * float(STATURE[outfit]) + 0.28

func apply_outfit(id: String) -> void:
	var next := id if OUTFITS.has(id) else "ranger"
	if outfit == next:
		return
	outfit = next
	_update_name_tag()
	if is_node_ready():
		_build_body()

func _reset_children(parent: Node3D) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _build_body() -> void:
	if jacket.get_parent() != null:
		_reset_children(pivot)
		jacket = Node3D.new()
		equipment = Node3D.new()
	offhand_prop=null
	for joints in [arms,elbows,legs,knees,sleeves,wrist_joints,ankle_joints,arm_rigs,leg_rigs]:
		joints.clear()
	pivot.add_child(jacket)
	pivot.scale = Vector3(1.0, STATURE[outfit], 1.0)
	var leg_ratio: float = LEG_LENGTH[outfit]
	jacket.scale.y = (1.80 - 0.85 * leg_ratio) / 0.95
	jacket.position.y = 0.85 * (leg_ratio - jacket.scale.y)
	jacket.add_child(equipment)
	var width: Vector3 = WIDTHS[outfit]
	var skin := Color(skin_color(outfit),0.75)
	if body_material==null:
		body_material=ShaderMaterial.new()
		body_material.shader=SURFACE
	var dyes:Array=DYES[outfit]
	var fabric: Array = [Color(dyes[0],0.5),Color(dyes[1],0.5),Color(dyes[2],0.25)]
	_shirt(width,fabric,skin)
	_boxers(width, fabric[1])
	# The head and its equipment meshes are authored at body height. Rotate them about the neck.
	neck = _joint(jacket,Vector3(0,1.505,0.004))
	skull = _joint(neck,-neck.position)
	skull.scale.x = float(HEAD_WIDTH[outfit])
	HEAD.attach(skull,outfit)
	_hair(skull,skin)
	for side: int in [-1,1]:
		_arm(width.x, side, skin)
		_leg(width.z, side, skin)
	_dress()
	set_offhand(offhand_id,offhand_block,offhand_lit)
	if not preview_mainhand.is_empty(): set_mainhand(preview_mainhand,preview_loaded)
	pose(0,0,0)

func _sections(w: Vector3) -> Array:
	var full := 1.12 if outfit=="ferryman" else 1.05 if outfit in ["mechanic","medic"] else 0.96 if outfit in ["surveyor","climber"] else 1.0
	return [Vector4(0.835,w.z,0.124*full,0.020),Vector4(0.901,w.z*0.98,0.126*full,0.016),
		Vector4(0.965,w.y*1.045,0.113*full,0.007),Vector4(1.019,w.y,0.108*full,0.007),
		Vector4(1.076,w.y*1.014,0.109*full,0.006),Vector4(1.134,w.x*0.80,0.119*full,0.004),
		Vector4(1.204,w.x*0.887,0.132*full,0.000),Vector4(1.272,w.x*0.945,0.143*full,-0.004),
		Vector4(1.327,w.x*0.982,0.135*full,-0.002),Vector4(1.368,w.x*1.005,0.117*full,0.003),
		Vector4(1.394,w.x*0.923,0.106*full,0.005),Vector4(1.412,w.x*0.76,0.093*full,0.006),
		Vector4(1.439,w.x*0.48,0.078*full,0.006),Vector4(1.465,0.070,0.069,0.005),
		Vector4(1.507,0.063,0.066,0.002),Vector4(1.55,0.071,0.070,0.002)]

func _section_point(rings: Array, level: float, angle: float, ease: float) -> Vector3:
	var row: Vector4 = rings[0]
	for i in range(1,rings.size()):
		var next: Vector4 = rings[i]
		if level <= next.x:
			row = row.lerp(next, clampf((level-row.x)/(next.x-row.x),0,1))
			break
		row = next
	var across:=absf(sin(angle))
	var front:=cos(angle)
	var x:=sin(angle)*row.y
	var pec:=exp(-pow((across-0.49)/0.34,2)-pow((level-1.291)/0.073,2))
	var sternum:=exp(-pow(x/0.020,2)-pow((level-1.31)/0.09,2))
	var clavicle_y:=1.38+0.026*across-0.017*across*across
	var clavicle:=exp(-pow((level-clavicle_y)/0.012,2))*smoothstep(0.08,0.33,across)
	var rib_edge:=exp(-pow((level-(1.154+0.047*(1.0-across)))/0.022,2))
	var abdomen:=exp(-pow((level-1.071)/0.087,2)-pow(x/0.102,2))
	var neck_cord:=exp(-pow((across-(0.15+maxf(level-1.415,0)*3.2))/0.14,2))*smoothstep(1.38,1.46,level)
	var front_depth:=0.016*pec-0.009*sternum+0.008*clavicle+0.006*rib_edge+0.008*abdomen+0.004*neck_cord
	var scapula:=exp(-pow((across-0.57)/0.29,2)-pow((level-1.306+across*0.034)/0.088,2))
	var spine:=exp(-pow(x/0.019,2)-pow((level-1.249)/0.201,2))
	var lumbar:=exp(-pow((absf(x)-0.042)/0.029,2)-pow((level-1.13)/0.155,2))
	var dz:=front_depth if front>0 else 0.019*scapula-0.011*spine+0.008*lumbar
	return Vector3(sin(angle)*(row.y+ease),level,row.w-front*(row.z+ease+dz*absf(front)))
func _shirt_top(a: float) -> float:
	var x := absf(sin(a))
	var band_width := 0.25 if outfit in ["medic","mechanic"] else 0.14 if outfit=="climber" else 0.17 if outfit=="surveyor" else 0.21
	var crest := exp(-pow((x-0.70)/band_width,2.0))
	var front := maxf(0,cos(a))
	var side := smoothstep(0.87,1,x)
	var depth := 0.087 if outfit=="ferryman" else 0.024 if outfit in ["medic","mechanic"] else 0.06
	return 1.355 + crest * 0.084 - front * front * depth - side * 0.095

func _shirt(width: Vector3, hues: Array, skin: Color, outer := false) -> void:
	var rings := _sections(width)
	var hem := 1.115 if outfit=="surveyor" else 1.088 if outfit=="climber" else 1.061 if outfit=="medic" else 0.962
	if outer: hem = 0.933
	const AROUND := 44
	const ROWS := 35
	for cloth:bool in [false,true]:
		if outer and not cloth: continue
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in ROWS:
			var f:=float(j)/(ROWS-1)
			for i in AROUND:
				var angle:=TAU*i/AROUND
				var y:=lerpf(hem,_shirt_top(angle),f) if cloth else lerpf(0.892,1.55,f)
				var ease:=0.006 if cloth else -0.016*(1.0-smoothstep(0.892,0.97,y))
				if outer:
					y += f*0.009
					ease = 0.015+0.026*(1.0-smoothstep(0.945,1.03,y))
				var point:=_section_point(rings,y,angle,ease)
				var across:=_section_point(rings,y,angle+0.013,ease)-_section_point(rings,y,angle-0.013,ease)
				var up:=_section_point(rings,y+0.0015,angle,ease)-_section_point(rings,y-0.0015,angle,ease)
				up.y=0.003
				var tint:=skin.darkened(smoothstep(1.385,1.54,y)*(0.14+0.12*maxf(cos(angle),0)))
				if cloth: tint=hues[2] if j<2 or j>=ROWS-2 else hues[0]
				if outer:
					var seam := absf(wrapf(angle,-PI,PI))
					if seam < 0.035: tint = hues[0].darkened(0.27)
					if seam > 0.30 and seam < 0.85 and j in [7,8,9]: tint = hues[2]
				surface.set_color(tint)
				surface.set_normal(up.cross(across).normalized())
				surface.add_vertex(point)
		for j in ROWS-1:
			for i in AROUND:
				var a:=j*AROUND+i
				var b:=j*AROUND+(i+1)%AROUND
				for index:int in [a,b,a+AROUND,b,b+AROUND,a+AROUND]:
					surface.add_index(index)
		var mesh:=MeshInstance3D.new()
		mesh.mesh=surface.commit()
		mesh.material_override=body_material
		if outer: equipment.add_child(mesh)
		else:
			jacket.add_child(mesh)
			if cloth: undershirt = mesh

func _hair_point(angle: float, f: float, height: float) -> Vector3:
	var front := smoothstep(-0.50,0.83,cos(angle))
	var lower := 1.565 + front*(0.149 + 0.004*sin(angle*3.0) + 0.006*absf(sin(angle*2.0)))
	if outfit=="ferryman":
		lower += 0.018*front*absf(sin(angle*2.0))
	elif outfit=="surveyor":
		lower += 0.016*front*sin(angle*2.0-0.25)
	elif outfit=="climber":
		lower += 0.011*front*sin(angle*2.0+0.32)
	lower += front*0.0034*sin(angle*11.0+0.35)
	if outfit=="surveyor":
		lower -= 0.033*(1.0-smoothstep(-0.20,0.75,cos(angle)))
	var radius := cos(f*PI*0.5)*0.134
	var y:=lerpf(lower,1.74+height,sin(f*PI*0.5))
	radius=maxf(radius,0.123*(1.0-smoothstep(1.744,1.774,y))*(1.0-smoothstep(-0.15,0.7,cos(angle))))
	return Vector3(sin(angle)*radius,y,-cos(angle)*radius+0.003+0.007*f)

func _hair(parent: Node3D, skin: Color) -> void:
	if outfit=="bronx":
		preload("res://game/art/bronx_hair.gd").attach(parent,skin)
		return
	if outfit in ["surveyor","climber"]:
		preload("res://game/art/survivor_hair.gd").attach(parent,outfit)
		var ears:=Sculpt.new(1202)
		for side:int in [-1,1]:
			ears.oval(Vector3(side*0.114,1.633,-0.004),Vector3(0.021,0.033,0.020),skin.darkened(0.10))
			ears.oval(Vector3(side*0.126,1.633,-0.01),Vector3(0.008,0.016,0.009),skin.darkened(0.26))
		_skin(parent,ears)
		return
	var mesh := Sculpt.new(1202)
	var dark := Color("#29251f")
	if outfit=="ferryman": dark=Color("#625f55")
	if outfit=="mechanic": dark=Color("#392b25")
	if outfit=="medic": dark=Color("#2b221f")
	if outfit=="climber": dark=Color("#8b5235")
	var height := 0.042 if outfit in ["ferryman","medic","mechanic"] else 0.067
	mesh.buffer.set_smooth_group(0)
	for i in 28:
		var a := TAU*i/28.0
		var b := TAU*(i+1)/28.0
		var front := cos((a+b)*0.5)
		var normal := Vector3(sin((a+b)*0.5),0,-front)
		var tone := dark
		if outfit=="ferryman":
			tone = dark.lerp(Color("#baaea1"),smoothstep(0.40,0.98,absf(normal.x))*0.82)
		for layer in 6:
			var points: Array[Vector3] = []
			for sample in [[a,layer],[b,layer],[a,layer+1],[b,layer+1]]:
				var angle := float(sample[0])
				var f := float(sample[1])/6.0
				points.append(_hair_point(angle,f,height))
			var highlight := (0.5+0.5*sin(i*1.85+layer*0.32))*0.035
			mesh.triangle(points[0],points[1],points[2],normal+Vector3.UP*layer*0.20,tone.lightened(highlight))
			mesh.triangle(points[2],points[1],points[3],normal+Vector3.UP*layer*0.20,tone.lightened(highlight))
		if i%2==0 and outfit in ["surveyor","climber","ferryman"]:
			for row in 5:
				var v := (row+0.2)/6.0
				var bend := -0.67 if outfit=="climber" else 0.45
				var u := a+bend*v
				var p := _hair_point(u,v,height)
				var q := _hair_point(u+0.048,v,height)
				var tip := _hair_point(u+bend/6.0,v+1.0/6.0,height)
				var outward := Vector3(sin(u),v,-cos(u)).normalized()
				mesh.triangle(p+outward*0.002,q+outward*0.002,tip+outward*0.002,outward,tone.lightened(0.047))
	mesh.buffer.set_smooth_group(-1)
	for side: int in [-1,1]:
		mesh.oval(Vector3(side*0.114,1.633,-0.004),Vector3(0.021,0.033,0.020),skin.darkened(0.10))
		mesh.oval(Vector3(side*0.126,1.633,-0.01),Vector3(0.008,0.016,0.009),skin.darkened(0.26))
	if outfit in ["mechanic","medic"]:
		var curls := 67 if outfit=="medic" else 52
		var volume := 0.73 if outfit=="medic" else 1.0
		for strand in curls:
			var a := strand*2.39996+0.09*sin(strand*0.75)
			var f := 1.0 - 0.84*sqrt((strand+0.4)/curls)
			var root := _hair_point(a,f,height)
			var outward := Vector3(sin(a),0.20+f,-cos(a)).normalized()
			var across := Vector3(cos(a),0,sin(a))
			var up := outward.cross(across).normalized()
			var pigment := dark.lightened((strand%4)*0.024)
			var radius := (0.007+0.004*absf(sin(strand*1.9)))*volume
			var axis: Array = []
			for k in 5:
				var arc := k*1.12+a
				axis.append(root+outward*(0.003+sin(k*PI/4)*radius*0.45)+across*radius*cos(arc)+up*radius*sin(arc))
			mesh.twig(axis,[0.003,0.0055*volume,0.006*volume,0.005*volume,0.002],pigment,5)
	elif outfit=="ranger":
		for i in 6:
			var x := -0.080+i*0.029
			mesh.twig([Vector3(x+0.021,1.761,-0.062),Vector3(x,1.735,-0.109),Vector3(x-0.016,1.708+0.003*i,-0.123)],
				[0.012,0.011,0.002],dark.lightened(0.018*(i%3)),7)
	_skin(parent,mesh)

func _arm(shoulder_width: float, side: int, skin: Color) -> void:
	var shoulder := _joint(jacket,Vector3(side*(shoulder_width-0.017),1.361,0))
	shoulder.scale.y=ARM_LENGTH[outfit]
	var elbow:=_joint(shoulder,Vector3(side*0.045,-0.263,0.012))
	var wrist:=_joint(elbow,Vector3(-side*0.016,-0.217,-0.027))
	arms.append(shoulder)
	elbows.append(elbow)
	wrist_joints.append(wrist)
	if side==1:
		grip=Marker3D.new()
		grip.name="RightGrip"
		grip.position=Vector3(-0.016,-0.083,-0.012)
		wrist.add_child(grip)
	else:
		left_grip=Marker3D.new()
		left_grip.name="LeftGrip"
		left_grip.position=Vector3(0.016,-0.083,-0.012)
		wrist.add_child(left_grip)
	var mass:float=LIMB_GIRTH[outfit]
	arm_rigs.append(LIMB.build(shoulder,true,side,mass,skin,elbow.position,wrist.position,body_material))
	var hand:=Sculpt.new(1221)
	var nails:=Color(skin.lerp(Color("#cda78d"),0.17),0.75)
	var lengths:=[0.064,0.080,0.076,0.060]
	for i in 4:
		var z:float=-0.047+i*0.022
		var base:=Vector3(0,-0.073,z)
		var m:float=lengths[i]
		var end:=Vector3(-side*0.014,-0.075-m,z+0.008)
		var radius:=0.0125-i*0.00065
		hand.twig([base,base+Vector3(0,-m*0.33,0),base+Vector3(-side*0.004,-m*0.68,0.003),end],
			[radius*1.13,radius,radius*0.90,radius*0.65],skin,10)
		hand.oval(end,Vector3(radius*0.72,radius*0.81,radius*0.76),skin)
		hand.oval(end+Vector3(side*radius*0.58,0.003,0),Vector3(0.002,0.007,0.005),nails)
	var thumb:=Vector3(-side*0.016,-0.018,-0.029)
	hand.twig([thumb,thumb+Vector3(-side*0.005,-0.019,-0.017),thumb+Vector3(-side*0.011,-0.041,-0.025),
		thumb+Vector3(-side*0.018,-0.060,-0.022)],[0.020,0.017,0.014,0.010],skin,10)
	var fingers:=_skin(wrist,hand)
	var fist:=Sculpt.new(1223)
	for i in 4:
		var z:float=-0.047+i*0.022
		var base:=Vector3(0,-0.073,z)
		var knuckle:=base+Vector3(0.001,-0.021,0)
		var curl:=knuckle+Vector3(-0.018,-0.010,0.001)
		var tip:=curl+Vector3(-0.018,0.018,0.002)
		var radius:=0.013-i*0.0006
		fist.twig([base,knuckle,curl,tip],[radius*1.10,radius,radius*0.96,radius*0.70],skin,10)
		fist.oval(knuckle,Vector3(radius,radius,radius),skin)
	fist.twig([thumb,thumb+Vector3(-0.015,-0.023,-0.008),thumb+Vector3(-0.022,-0.045,0.005),thumb+Vector3(-0.022,-0.055,0.023)],[0.019,0.017,0.014,0.010],skin,10)
	var curled:=_skin(wrist,fist)
	curled.visible=false
	if side==1:
		relaxed_digits=fingers
		curled_digits=curled
	else:
		curled.scale.x=-1
		left_open=fingers
		left_curled=curled

func _boxers(w: Vector3, tint: Color) -> void:
	shorts_rig = Skeleton3D.new()
	pivot.add_child(shorts_rig)
	shorts_rig.add_bone("Waist")
	shorts_rig.set_bone_rest(0,Transform3D.IDENTITY)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var mass: float = LIMB_GIRTH[outfit]
	var ratio: float = LEG_LENGTH[outfit]
	const AROUND := 24
	const ROWS := 7
	for index in 2:
		var side := -1.0 if index==0 else 1.0
		var bone := index+1
		var joint := Vector3(side*w.z*0.58,0.85*ratio,0.004)
		shorts_rig.add_bone("ThighL" if index==0 else "ThighR")
		shorts_rig.set_bone_parent(bone,-1)
		shorts_rig.set_bone_rest(bone,Transform3D(Basis.IDENTITY,joint))
		var start := index*(AROUND+1)*ROWS
		for row in ROWS:
			for i in AROUND+1:
				var angle := TAU*i/AROUND
				var wave := sin(angle)
				var across := maxf(0,wave)
				var point: Vector3
				var influence := 0.0
				if row < 4:
					var waist: float = [w.y*1.098,w.y*1.10,w.z*1.10,w.z*1.11][row]
					var depth: float = [0.132,0.133,0.144,0.138][row]
					var y: float = [0.979,0.950,0.871,0.819][row]
					if row==3:
						y -= maxf(-wave,0.0)*0.046
						influence = 0.32*across
					point = Vector3(side*across*waist,jacket.position.y+y*jacket.scale.y,-cos(angle)*depth+0.005)
				else:
					var hem := -0.17 if outfit=="mechanic" else -0.147
					var y: float = [-0.078,hem+0.014,hem][row-4]
					var rx := (0.098 if row==4 else 0.092)*mass
					var rz := (0.112 if row==4 else 0.105)*mass
					point = joint + Vector3(side*wave*rx,y*ratio,-cos(angle)*rz+0.001)
					influence = 0.83 if row==4 else 1.0
				surface.set_bones(PackedInt32Array([0,bone,0,0]))
				surface.set_weights(PackedFloat32Array([1.0-influence,influence,0,0]))
				surface.set_color(tint.lightened(0.16 if row<2 else 0.055 if row==6 else 0.0))
				surface.add_vertex(point)
		for row in ROWS-1:
			for i in AROUND:
				var a := start+row*(AROUND+1)+i
				var down := a+AROUND+1
				var order := [a,down,a+1,a+1,down,down+1] if side>0 else [a,a+1,down,a+1,down+1,down]
				for item in order:
					surface.add_index(item)
	shorts_rig.reset_bone_poses()
	surface.generate_normals()
	var shorts := MeshInstance3D.new()
	shorts.mesh = surface.commit()
	shorts.material_override = body_material
	shorts_rig.add_child(shorts)
	shorts.skeleton = NodePath("..")
	shorts.skin = shorts_rig.create_skin_from_rest_transforms()

func _leg(hip_width: float, side: int, skin: Color) -> void:
	var hip := _joint(pivot,Vector3(side*hip_width*0.58,0.85*float(LEG_LENGTH[outfit]),0.004))
	hip.scale.y = LEG_LENGTH[outfit]
	var knee:=_joint(hip,Vector3(-side*0.011,-0.39,-0.006))
	var ankle:=_joint(knee,Vector3(side*0.012,-0.354,0.016))
	legs.append(hip)
	knees.append(knee)
	ankle_joints.append(ankle)
	var mass:float=LIMB_GIRTH[outfit]
	leg_rigs.append(LIMB.build(hip,false,side,mass,skin,knee.position,ankle.position,body_material,-0.17 if outfit=="mechanic" else -0.147))
	var foot:=Sculpt.new(1222)
	var nails:=Color(skin.lerp(Color("#d4af95"),0.22),0.75)
	for i in 5:
		var x:=side*(-0.030+0.017*i)*mass
		var z:float=-0.133+0.005*i
		var radius:float=[0.0135,0.0115,0.010,0.0091,0.0084][i]*mass
		var tip:=Vector3(x,-0.091,z-0.034+i*0.001)
		foot.twig([Vector3(x,-0.085,z+0.011),Vector3(x,-0.086,z-0.009),tip],
			[radius*1.13,radius,radius*0.78],skin,10)
		foot.oval(tip,Vector3(radius*0.82,radius*0.68,radius*0.88),skin)
		foot.oval(tip+Vector3(0,radius*0.62,0.004),Vector3(radius*0.52,0.0018,radius*0.62),nails)
	_skin(ankle,foot)
func _skin(parent: Node3D, shape: Sculpt) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = shape.commit()
	visual.material_override = body_material
	parent.add_child(visual)
	return visual

func _joint(parent: Node3D, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position=at
	parent.add_child(node)
	return node

func wear(id: String) -> void:
	var next := id if id in ["coat","armor","oilskin_vest","sun_cape"] else ""
	if equipped == next:
		return
	equipped = next
	if is_node_ready():
		_dress()

func wear_loadout(gear: Dictionary) -> void:
	var changed: bool = equipped!=gear.get("body","")
	equipped=gear.get("body","")
	for slot in accessories:
		var id: String=gear.get(slot,"")
		if accessories[slot]!=id:
			changed=true
			accessories[slot]=id
	if not changed: return
	if is_node_ready(): _dress()

func _costume(parent:Node3D, id:String, at:Vector3, size:=Vector3.ONE)->void:
	var piece:=MeshInstance3D.new()
	piece.mesh=preload("res://game/art/meme_gear.gd").mesh(id)
	piece.material_override=WastelandLook.colored_material()
	piece.name=id
	parent.add_child(piece)
	piece.position=at
	piece.scale=size
	if parent!=equipment: sleeves.append(piece)

func _dress() -> void:
	_reset_children(equipment)
	undershirt.visible = equipped.is_empty() or equipped in ["sun_cape","meme_duck"]
	for sleeve in sleeves:
		if is_instance_valid(sleeve):
			sleeve.get_parent().remove_child(sleeve)
			sleeve.queue_free()
	sleeves.clear()
	if accessories.pack in ["canvas_pack","expedition_pack"]:
		var pack:=MeshInstance3D.new()
		pack.name="WornPack"
		pack.mesh=WastelandItemArt.mesh(accessories.pack,{})
		pack.material_override=WastelandLook.colored_material()
		pack.position=Vector3(0,1.224,0.218 if equipped!="" else 0.20)
		equipment.add_child(pack)
	var trousers:String=accessories.legs
	var worn:=trousers in ["canvas_pants","quilted_pants"]
	var waistband:MeshInstance3D=shorts_rig.get_child(0)
	waistband.material_override=WastelandLook.matte(preload("res://game/art/trousers.gd").dye(trousers)) if worn else body_material
	if worn:
		for i in leg_rigs.size():
			var leg:=MeshInstance3D.new()
			leg.name="TrouserLeg"
			leg.mesh=preload("res://game/art/trousers.gd").leg(trousers,-1 if i==0 else 1,LIMB_GIRTH[outfit])
			leg.material_override=body_material
			leg_rigs[i].add_child(leg)
			leg.skeleton=NodePath("..")
			leg.skin=leg_rigs[i].create_skin_from_rest_transforms()
			sleeves.append(leg)
	if accessories.head=="hardhat":
		sleeves.append(_skin(skull,GEAR_ART.helmet()))
	elif accessories.head=="alpine_cap":
		sleeves.append(_skin(skull,GEAR_ART.cap()))
	for i in wrist_joints.size():
		if accessories.hands=="work_gloves":
			sleeves.append(_skin(wrist_joints[i],GEAR_ART.glove(-1 if i==0 else 1)))
		if accessories.feet=="trail_boots":
			sleeves.append(_skin(ankle_joints[i],GEAR_ART.boot()))
		if accessories.hands=="meme_claws": _costume(wrist_joints[i],"meme_claws",Vector3.ZERO)
		if accessories.feet=="meme_fins": _costume(ankle_joints[i],"meme_fins",Vector3.ZERO)
	if str(accessories.head).begins_with("meme_"):
		_costume(skull,accessories.head,Vector3(0,1.73,0))
	if accessories.eyes=="meme_shades": _costume(skull,accessories.eyes,Vector3(0,1.645,-0.115))
	if accessories.muzzle=="meme_whiskers": _costume(skull,accessories.muzzle,Vector3(0,1.605,-0.136))
	if accessories.back=="meme_tail": _costume(equipment,accessories.back,Vector3(0,0.92,0.125))
	if accessories.back=="meme_clock": _costume(equipment,accessories.back,Vector3(0,1.26,0.153))
	if equipped in ["meme_duck","meme_alien"]:
		_costume(equipment,equipped,Vector3(0,0.99 if equipped=="meme_duck" else 1.215,0))
		return
	if equipped.is_empty():
		return
	var w:Vector3 = WIDTHS[outfit]
	if equipped=="sun_cape":
		_skin(equipment,GEAR_ART.cape(w))
		return
	if equipped=="oilskin_vest":
		var wax := Color("#998442",0.5)
		_shirt(w,[wax,wax,wax.darkened(0.17)],Color.WHITE,true)
		return
	var gear := Sculpt.new(1207)
	if equipped=="armor":
		for i in 4:
			var radius := lerpf(w.y,w.x,0.24+i*0.23)
			gear.loft([Vector4(1.005+i*0.081,radius+0.015,0.158,0),Vector4(1.081+i*0.081,radius+0.026,0.165,-0.002)],
				Color("#59676b").lightened(i*0.038))
		for side in [-1,1]:
			gear.twig([Vector3(side*0.142,1.30,-0.116),Vector3(side*0.147,1.415,-0.057),Vector3(side*0.144,1.422,0.026),Vector3(side*0.147,1.30,0.125)],
				[0.028,0.029,0.03,0.03],Color("#685645"),7)
	else:
		gear.loft([Vector4(0.775,w.z+0.055,0.166,0.015),Vector4(0.96,w.y+0.03,0.153,0.004),Vector4(1.11,w.y+0.03,0.16,0.004),
			Vector4(1.30,w.x+0.01,0.168,0.002),Vector4(1.402,w.x,0.14,0),Vector4(1.445,0.095,0.096,0.006)],Color("#78654e"))
		for i in 2:
			var sleeve := Sculpt.new(1208)
			var side := -1 if i==0 else 1
			sleeve.twig([Vector3(-side*0.006,0.025,0),Vector3(side*0.015,-0.039,0),elbows[i].position],
				[0.094,0.108,0.079],Color("#78654e"),12)
			sleeves.append(_skin(arms[i],sleeve))
			var cuff := Sculpt.new(1209)
			cuff.loft([Vector4(-0.206,0.061,0.064,-0.008),Vector4(-0.082,0.077,0.077,0.008),Vector4(0.02,0.081,0.080,0.008)],Color("#76634e"))
			sleeves.append(_skin(elbows[i],cuff))
	_skin(equipment,gear)

var action_kind:=""
var action_time:=0.0

func act(kind:String) -> void:
	if kind in ["punch","tool","fire"]:
		action_kind=kind
		action_time=0.0

func pose(dt: float, foot_speed: float, duck: float, swimming:bool=false) -> void:
	if arms.size()!=2:
		return
	var speed:=clampf(foot_speed/4.9,0.0,1.5)
	var duck_amount:=clampf(duck,0.0,1.0)
	stride+=dt*(1.65+minf(foot_speed,7.4)*1.82)
	var strength:=smoothstep(0.02,1.04,speed)
	var cycle:=sin(stride)
	var crouch_hip:=0.83*duck_amount
	var crouch_knee:=1.62*duck_amount
	var leg_ratio:float=LEG_LENGTH[outfit]
	# Shorten the pelvis-to-floor distance as the thighs and shins fold.
	var sink:float=(0.39*(1.0-cos(crouch_hip))+0.354*(1.0-cos(crouch_knee-crouch_hip)))*leg_ratio
	pivot.position.y=(-sink+0.020*absf(cycle)*strength)*float(STATURE[outfit])
	var pitch:=-0.041-duck_amount*0.30-strength*0.055
	jacket.rotation=Vector3(pitch,cycle*strength*0.11,0.012+cos(stride)*strength*0.026)
	offhand_blend=move_toward(offhand_blend,float(offhand_block),dt*5.5)
	action_time+=dt
	var duration:=0.68 if action_kind=="tool" else 0.24 if action_kind=="fire" else 0.44
	if action_time>=duration: action_kind=""
	var closed:=not action_kind.is_empty() or (is_instance_valid(grip) and grip.get_child_count()>0)
	curled_digits.visible=closed
	relaxed_digits.visible=not closed
	var progress:=clampf(action_time/duration,0,1)
	var drive:=smoothstep(0.26,0.47,progress)*(1.0-smoothstep(0.52,1.0,progress))
	var windup:=sin(PI*clampf(progress/0.42,0,1))
	if swimming:
		pivot.rotation.x=-0.85-strength*0.31
		pivot.position.y=0.43+0.025*cos(stride)
	else:
		pivot.rotation.x=0
	if not action_kind.is_empty(): jacket.rotation.y+=0.26*windup-0.32*drive
	var torso_anchor:=Vector3(0,0.975*jacket.scale.y,0)
	jacket.position=Vector3(0,0.85*leg_ratio+0.125*jacket.scale.y,0)-jacket.basis.orthonormalized()*torso_anchor
	var waist_rotation:=jacket.basis.orthonormalized()
	var waist_y:=0.85*leg_ratio+0.125*jacket.scale.y
	shorts_rig.set_bone_pose_rotation(0,waist_rotation.get_rotation_quaternion())
	shorts_rig.set_bone_pose_position(0,Vector3.UP*waist_y-waist_rotation*(Vector3.UP*waist_y))
	for i in 2:
		var side:float=-1 if i==0 else 1
		var run:=smoothstep(4.3,7.2,foot_speed)
		var phase:=stride+(PI if i==1 else 0.0)
		var step:=sin(phase)*strength
		var lifted:=maxf(0.0,-cos(phase))*strength
		var thigh:=0.030+step*(0.53+0.21*run)+crouch_hip
		var knee_bend:=-0.059-lifted*(0.74+0.38*run)-crouch_knee
		legs[i].rotation=Vector3(thigh,side*(0.080+duck_amount*0.04),side*(0.021+duck_amount*0.095))
		knees[i].rotation.x=knee_bend
		ankle_joints[i].rotation.x=-(thigh+knee_bend)*(1.0-0.54*lifted)-lifted*0.19
		arms[i].rotation=Vector3(0.045-step*(0.44+0.25*run)+duck_amount*0.16,side*(0.050+step*0.058),side*(0.039+duck_amount*0.084))
		elbows[i].rotation=Vector3(0.14+0.27*strength+0.32*run+0.48*duck_amount+maxf(0,-step)*0.17,side*0.090,-side*0.11)
		wrist_joints[i].rotation=Vector3(-0.061,-side*0.070,-side*0.07)
		if swimming:
			var stroke:=sin(phase)
			arms[i].rotation=Vector3(0.92+stroke*1.02,side*0.16,side*(0.58+0.42*cos(phase)))
			elbows[i].rotation.x=0.55+0.34*cos(phase)
			legs[i].rotation.x=0.15+0.28*stroke
			knees[i].rotation.x=-0.20-0.28*maxf(0,-stroke)
			ankle_joints[i].rotation.x=-0.44
		if not action_kind.is_empty():
			if i==1:
				match action_kind:
					"tool":
						arms[i].rotation+=Vector3(1.65*windup+0.78*drive,-0.20*windup+0.32*drive,0.28*windup)
						elbows[i].rotation.x+=0.88*windup+0.20*drive
					"punch":
						arms[i].rotation+=Vector3(-0.29*windup+1.42*drive,0.23*drive,0.13*windup)
						elbows[i].rotation.x+=0.92*windup-0.10*drive
					"fire":
						arms[i].rotation.x+=0.92*windup+0.5*drive
						elbows[i].rotation.x+=0.48*windup
			else:
				elbows[i].rotation.x+=0.63*(drive+windup)
		if i==0 and not offhand_id.is_empty():
			arms[i].rotation=Vector3(0.27+offhand_blend*0.50+step*0.065,-0.08+offhand_blend*0.23,-0.19)
			elbows[i].rotation=Vector3(0.54+offhand_blend*0.33+0.30*float(offhand_id=="torch" and offhand_lit),0.06,0.09)
			if is_inside_tree():
				left_grip.global_transform.basis=global_transform.basis
				if offhand_shield and is_instance_valid(offhand_prop):
					offhand_prop.rotation.y=lerpf(0.68,0.08,offhand_blend)
		if i==1 and is_inside_tree() and is_instance_valid(primary_shield):
			primary_shield.global_basis=global_basis*Basis(Vector3.UP,-0.68)
		shorts_rig.set_bone_pose_rotation(i+1,legs[i].quaternion)
		arm_rigs[i].set_bone_pose_rotation(1,elbows[i].quaternion)
		arm_rigs[i].set_bone_pose_rotation(2,wrist_joints[i].quaternion)
		leg_rigs[i].set_bone_pose_rotation(1,knees[i].quaternion)
		leg_rigs[i].set_bone_pose_rotation(2,ankle_joints[i].quaternion)
