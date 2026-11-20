class_name WastelandHands
extends Node3D

var model := Node3D.new()
var color_materials: Dictionary = {}
var model_id := "?"
var pose_time := 0.0
var breath_phase := 0.0
var stroke_phase := 0.0
var swing_serial := 0
var shot_serial := 0
var swing_force := 1.0
var search_ratio := 0.0
var swing := 0.0
var kick := 0.0
var reload_ratio := 0.0
var charge := 0.0
var flash := 0.0
var hurt_dip := 0.0
var landing := 0.0
var equip_lower := 0.0
var swimming := false
var swim_blend := 0.0
var brightness := 1.0
var crossbow_bolt:MeshInstance3D
var bolt_loaded:=false
var muzzle: MeshInstance3D
var resting_left: MeshInstance3D
var right_hand: MeshInstance3D
var swimming_fingers := false
var empty_grip := ""
var guard_left := 0.0
var guard_blend := 0.0
var item_material := ShaderMaterial.new()
var skin_material := ShaderMaterial.new()
var gloves_worn := false
var paw_gloves := false

const Offhand:=preload("res://game/art/offhand_art.gd")
const GrippingHand:=preload("res://game/art/gripping_hand.gd")
const RangedGrip:=preload("res://game/art/ranged_grip.gd")
var offhand_id:=""
var offhand_style:=""
var offhand_shield:=false
var offhand_block:=false
var offhand_lit:=false
var offhand_pose:=0.0
var offhand_root:=Node3D.new()
var offhand_prop:MeshInstance3D
var support_arm:MeshInstance3D

func set_offhand(id:String,blocking:=false,lit:=true)->void:
	offhand_shield=Offhand.item(id).get("shield",false)
	offhand_block=blocking and offhand_shield
	if offhand_id!=id or offhand_style!=outfit:
		offhand_id=id
		offhand_style=outfit
		for child in offhand_root.get_children():
			offhand_root.remove_child(child)
			child.queue_free()
		offhand_prop=null
		if not id.is_empty():
			var arm:=_bare_arm("handle")
			arm.reparent(offhand_root,false)
			arm.scale.x=-1
			offhand_prop=Offhand.prop(id,true,item_material)
			if offhand_prop:
				var socket:=Node3D.new()
				socket.position=Vector3(-0.125,-0.012,-0.295)
				if offhand_shield: socket.position=Vector3(-0.102,-0.010,-0.285)
				offhand_root.add_child(socket)
				socket.add_child(offhand_prop)
				var item:=Offhand.item(id)
				if GrippingHand.handle_radius(id,item)>0.0:
					socket.position=GrippingHand.CENTER*Vector3(-1,1,1)
					offhand_prop.position=-(offhand_prop.basis*GrippingHand.socket(id,item))
					_fit_fingers(arm,id,item,offhand_prop,true)
		offhand_root.visible=offhand_prop!=null
	if is_instance_valid(resting_left): resting_left.visible=id.is_empty()
	if is_instance_valid(support_arm): support_arm.visible=id.is_empty()
	if id=="torch" and is_instance_valid(offhand_prop): offhand_prop.get_node("LitGlass").visible=lit
	offhand_lit=lit

func set_gloves(worn: bool, paws := false) -> void:
	if paw_gloves != paws:
		paw_gloves = paws
		skin_material.set_shader_parameter("paw_gloves",paws)
	if gloves_worn != worn:
		gloves_worn = worn
		skin_material.set_shader_parameter("work_gloves",worn)

var outfit := "ranger"
static var arm_meshes: Dictionary = {}

func _ready() -> void:
	add_child(model)
	add_child(offhand_root)
	offhand_root.hide()
	item_material.shader=preload("res://shaders/hands.gdshader")
	item_material.render_priority=79
	item_material.set_shader_parameter("vertex_paint",true)
	skin_material.shader=item_material.shader
	skin_material.render_priority=79
	skin_material.set_shader_parameter("vertex_paint",true)
	skin_material.set_shader_parameter("skin_shading",true)

func hold(id: String, item: Dictionary) -> void:
	if id == model_id:
		return
	equip_lower = 0.0 if model_id == "?" else 1.0
	model_id = id
	for part in model.get_children():
		model.remove_child(part)
		part.queue_free()
	support_arm=null
	resting_left = null
	var kind: String = item.get("kind","")
	var grip := "handle" if kind in ["weapon","tool","light","field_gear"] or id=="bow" else "trigger" if kind=="ranged" else "open"
	if id.is_empty():
		grip = "relaxed"
	right_hand = _bare_arm(grip)
	swimming_fingers = false
	if id.is_empty():
		empty_grip = grip
		guard_left = 0.0
		guard_blend = 0.0
		resting_left = _bare_arm(grip)
		resting_left.position=Vector3(-0.63,-0.032,0.07)
		resting_left.scale=Vector3(-0.95,0.95,0.95)
	muzzle = null
	crossbow_bolt=null
	bolt_loaded=false
	if id != "":
		_attach_item(id,item)
	set_offhand(offhand_id,offhand_block,offhand_lit)
	_apply_light()

func _bare_arm(grip: String, support := false) -> MeshInstance3D:
	var key := outfit+"/"+grip
	if not arm_meshes.has(key):
		arm_meshes[key] = _arm_mesh(grip,outfit)
	var arm:=MeshInstance3D.new()
	arm.mesh=arm_meshes[key]
	arm.material_override=skin_material
	arm.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(arm)
	if support:
		arm.position=Vector3(0.183,0.031,-0.236)
		arm.rotation=Vector3(-0.13,-0.25,0.17)
		arm.scale=Vector3(-0.89,0.89,0.95)

	return arm

func _fit_fingers(arm:MeshInstance3D, id:String, item:Dictionary, asset:MeshInstance3D, left:bool) -> void:
	var key:=outfit+("/left-grip/" if left else "/right-grip/")+id
	if not arm_meshes.has(key):
		var axis:=asset.basis.y
		if left: axis.x=-axis.x
		var grip:=GrippingHand.frame(axis)
		var sculpt:=HandSculpture.new(1907)
		var skin:Color=WastelandPartyAvatar.SKIN_TONES.get(outfit,WastelandPartyAvatar.SKIN_TONES.ranger)
		var breadth:float=WastelandPartyAvatar.LIMB_GIRTH.get(outfit,1.0)
		GrippingHand.sculpt(sculpt,grip,GrippingHand.handle_radius(id,item)*asset.scale.x,skin,breadth)
		arm_meshes[key]=sculpt.commit()
	arm.mesh=arm_meshes[key]

class HandSculpture extends WastelandBestiary.Sculpture:
	func triangle(a: Vector3, b: Vector3, c: Vector3, outside: Vector3, color: Color) -> void:
		# The scene sculptor normally works in metres. Its area test must also
		# preserve millimetre-sized facets on the curled fingers and nail beds.
		super.triangle(a,b,c,outside.normalized(),color)

static func _arm_mesh(grip: String, style: String) -> ArrayMesh:
	var mesh:=HandSculpture.new(1907)
	var skin:Color=WastelandPartyAvatar.SKIN_TONES.get(style,WastelandPartyAvatar.SKIN_TONES.ranger)
	var breadth:float=WastelandPartyAvatar.LIMB_GIRTH.get(style,1.0)
	var axial:=Basis(Vector3.RIGHT,PI*0.5)
	var hand_origin:=Vector3(0.129,-0.035,0)
	# Forearm, wrist and palm share one continuous surface. The narrow wrist has
	# an ulnar ridge, and the knuckles widen before the fingers separate.
	mesh.loft([Vector4(-0.275,0.058,0.037,-0.003),Vector4(-0.252,0.065,0.044,-0.003),
		Vector4(-0.222,0.064,0.043,-0.001),Vector4(-0.193,0.056,0.040,0.002),
		Vector4(-0.161,0.047,0.034,0.009),Vector4(-0.132,0.045,0.036,0.015),
		Vector4(-0.075,0.049,0.042,0.024),Vector4(0.022,0.062,0.055,0.034),
		Vector4(0.110,0.075*breadth,0.066*breadth,0.049),Vector4(0.213,0.082*breadth,0.073*breadth,0.069),
		Vector4(0.35,0.076*breadth,0.073*breadth,0.089),Vector4(0.50,0.074*breadth,0.074*breadth,0.15),
		Vector4(0.76,0.093*breadth,0.086*breadth,0.26)],skin,hand_origin,axial,20)
	mesh.oval(Vector3(0.168,-0.027,-0.151),Vector3(0.012,0.010,0.020),skin.darkened(0.016))
	for index in 4:
		_finger(mesh,grip,index,skin)
	var base:=Vector3(0.160,-0.021,-0.213)
	var mid:=Vector3(0.171,0.022,-0.251)
	var bend:=Vector3(0.148,0.046,-0.285)
	var tip:=Vector3(0.110,0.054,-0.305)
	if grip=="relaxed" or grip=="open":
		base=Vector3(0.092,-0.047,-0.175)
		mid=Vector3(0.061,-0.045,-0.206)
		bend=Vector3(0.040,-0.056,-0.237)
		tip=Vector3(0.041,-0.066,-0.263)
	if grip=="open":
		mid=Vector3(0.057,-0.039,-0.206)
		bend=Vector3(0.021,-0.041,-0.239)
		tip=Vector3(0.011,-0.043,-0.268)
	elif grip=="fist":
		# The thumb wraps outside the index and middle fingers, across the folded fist.
		base=Vector3(0.088,-0.044,-0.177)
		mid=Vector3(0.057,-0.052,-0.218)
		bend=Vector3(0.059,-0.068,-0.259)
		tip=Vector3(0.101,-0.070,-0.279)
	var thumb_root:=Vector3(0.123,-0.042,-0.180) if grip in ["fist","open","relaxed"] else base.lerp(hand_origin+Vector3(0,0,-0.20),0.6)
	_digit(mesh,[thumb_root,base,base.lerp(mid,0.55),mid,bend,tip,tip+(tip-bend).normalized()*0.010],
		[0.014,0.027,0.029,0.025,0.019,0.014,0.006],skin)
	var nail:=skin.lerp(Color("#e6b8a7"),0.33)
	if grip=="fist":
		mesh.oval(tip+Vector3(-0.001,-0.010,-0.008),Vector3(0.012,0.005,0.009),nail,0.22)
	else:
		mesh.oval(tip+Vector3(0.001,0.011,0.002),Vector3(0.011,0.0036,0.013),nail)
	return mesh.commit()

static func _digit(mesh: WastelandBestiary.Sculpture, points: Array, radii: Array, skin: Color) -> void:
	const SIDES:=12
	mesh.buffer.set_smooth_group(0)
	var previous:=PackedVector3Array()
	for i in points.size():
		var center:Vector3=points[i]
		var tangent:Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
		var x_axis:=tangent.cross(Vector3.UP).normalized()
		var y_axis:=tangent.cross(x_axis).normalized()
		var ring:=PackedVector3Array()
		for j in SIDES:
			var angle:=TAU*j/SIDES
			ring.append(center+(x_axis*cos(angle)+y_axis*sin(angle)*0.87)*float(radii[i]))
		if i>0:
			for j in SIDES:
				var k:=(j+1)%SIDES
				var normal:Vector3=(ring[j]+ring[k])*0.5-center
				mesh.triangle(previous[j],ring[j],previous[k],normal,skin)
				mesh.triangle(previous[k],ring[j],ring[k],normal,skin)
				if i==points.size()-1:
					mesh.triangle(center,ring[j],ring[k],tangent,skin)
		previous=ring
	mesh.buffer.set_smooth_group(-1)

static func _finger(mesh: WastelandBestiary.Sculpture, grip:String, index:int, skin:Color) -> void:
	var radius:=0.018-index*0.0012
	var root:=Vector3(0.117+index*0.003,0.020-index*0.024,-0.257+index*0.012)
	var knuckle:=Vector3(0.076-index*0.006,0.026-index*0.027,-0.277+index*0.019)
	var joint:=knuckle+Vector3(-0.022,-0.001,-0.027)
	var tip:=joint+Vector3(0.010,-0.008,-0.026+index*0.002)
	if grip=="open" or grip=="fist" or (grip=="trigger" and index==0):
		root=Vector3(0.081+index*0.03,-0.014,-0.249+maxf(index-1,0)*0.004)
		knuckle=root+Vector3(-0.005,0.021,-0.034)
		var reach:float=[0.038,0.043,0.038,0.029][index]
		if grip=="fist":
			joint=knuckle+Vector3(-0.006,-0.022,-reach*0.66)
			tip=joint+Vector3(0.004,-0.023,0.019)
		else:
			joint=knuckle+Vector3(-0.005,-0.012,-reach)
			tip=joint+Vector3(0,-0.016,-reach*0.54)
	if grip in ["fist","relaxed","open"]:
		var finger_x:=0.080+index*0.031
		var length:float=[0.047,0.051,0.046,0.035][index]
		root=Vector3(finger_x,-0.023,-0.239+index*0.002)
		knuckle=root+Vector3((index-1.5)*0.002,0.014,-length*0.88)
		joint=knuckle+Vector3(-0.002,-length*0.79,-0.020)
		tip=joint+Vector3(-0.003,-0.014,length*0.77)
		if grip!="fist":
			var curl:=0.09 if grip=="open" else 0.39+0.14*index
			var spread:=(index-1.3)*(0.006 if grip=="open" else 0.002)
			joint=knuckle+Vector3(spread,-length*sin(curl),-length*cos(curl))
			tip=joint+Vector3(spread*0.5,-length*0.72*sin(curl*1.85),-length*0.72*cos(curl*1.85))
		mesh.oval(knuckle+Vector3.UP*0.002,Vector3(radius*1.04,radius*0.87,radius),skin.lerp(Color("#d48d76"),0.16))
	_digit(mesh,[root,knuckle,joint,tip,tip+(tip-joint).normalized()*radius*0.55],
		[radius*1.22,radius*1.05,radius*0.89,radius*0.76,radius*0.26],skin)
	var direction:=(tip-joint).normalized()
	var across:=direction.cross(Vector3.UP).normalized()
	var dorsal:=across.cross(direction).normalized() * (-1.0 if grip=="fist" else 1.0)
	var nail_frame:=Basis(dorsal.cross(direction),dorsal,direction)
	var nail_at:=tip-direction*radius*0.24+dorsal*radius*0.64
	mesh.loft([Vector4(-0.002,radius*0.46,radius*0.60,0),Vector4(0,radius*0.54,radius*0.70,0),
		Vector4(0.002,radius*0.43,radius*0.57,0)],skin.lerp(Color("#e4bdad"),0.54),nail_at,nail_frame,10)
func _attach_item(id:String,item:Dictionary) -> void:
	var asset:=MeshInstance3D.new()
	asset.mesh=WastelandItemArt.mesh("field_crossbow_empty" if id=="field_crossbow" else id,item)
	asset.material_override=item_material
	asset.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(asset)
	var kind: String = item.get("kind","")
	var item_scale:=0.81
	match kind:
		"weapon","tool":
			asset.position=Vector3(0.119,0.030,-0.363)
			asset.rotation=Vector3(-0.79,-0.16,-0.30)
			item_scale=0.92
			if id=="reed_spear": asset.rotation=Vector3(-1.19,-0.09,-0.19)
			if item.get("shield",false):
				asset.position=Vector3(0.102,-0.010,-0.285)
				asset.rotation=Vector3(0.05,-0.55,-0.16)
				item_scale=1.0
		"ranged":
			asset.position=Vector3(0.112,0.137,-0.321) if id!="bow" else Vector3(0.121,0.072,-0.258)
			asset.rotation=Vector3(0.033,0.04,0.15 if id=="bow" else 0.025)
			if id in ["bow","rifle","field_crossbow"]:
				support_arm=_bare_arm("handle",true)
			if id=="field_crossbow":
				crossbow_bolt=MeshInstance3D.new()
				crossbow_bolt.mesh=WastelandItemArt.mesh("field_crossbow_bolt",item)
				crossbow_bolt.material_override=item_material
				crossbow_bolt.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				asset.add_child(crossbow_bolt)
				crossbow_bolt.visible=bolt_loaded
			if id not in ["bow","field_crossbow"]:
				var front := -0.94 if id=="rifle" else -0.603
				muzzle=_piece(Vector3(0.14,0.12,0.19),Vector3(0.112,0.215,front),Color("#ffc27a"),Vector3(0.35,0,0.62))
				muzzle.hide()
		"field_gear":
			asset.position=Vector3(0.116,0.060,-0.33)
			asset.rotation=Vector3(-0.12,-0.18,-0.04)
		"food","med","light","seed":
			asset.position=Vector3(0.115,0.096,-0.362)
			asset.rotation=Vector3(-0.39,-0.28,0.14)
		_:
			asset.position=Vector3(0.099,0.102,-0.375)
			asset.rotation=Vector3(-0.34,-0.37,0.19)
	asset.scale=Vector3.ONE*item_scale
	if GrippingHand.handle_radius(id,item)>0.0:
		asset.position=GrippingHand.CENTER-asset.basis*GrippingHand.socket(id,item)
		_fit_fingers(right_hand,id,item,asset,false)
	elif kind=="ranged":
		RangedGrip.fit(id,asset,support_arm)
		if is_instance_valid(muzzle):
			muzzle.reparent(asset)
			muzzle.position=RangedGrip.flash_center(id)

func _piece(size: Vector3, at: Vector3, color: Color, turn: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var piece := WastelandLook.form(model, size, at, color, 0.14 if size.x >= 0.13 else 0.075)
	piece.rotation = turn
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := color.to_html()
	if not color_materials.has(key):
		var shader := ShaderMaterial.new()
		shader.shader = preload("res://shaders/hands.gdshader")
		shader.render_priority = 80
		shader.set_shader_parameter("tint", color)
		color_materials[key] = shader
	piece.material_override = color_materials[key]
	return piece

func swing_attack(power: float) -> void:
	swing_serial += 1
	swing_force = power
	swing = 1.0
	if model_id.is_empty(): guard_left=1.35
	kick = maxf(kick, power * 0.55)

func set_loaded_arrow(loaded:bool)->void:
	bolt_loaded=loaded
	if is_instance_valid(crossbow_bolt):
		crossbow_bolt.visible=loaded

func recoil(show_flash: bool) -> void:
	shot_serial += 1
	kick = 0.45 if model_id=="field_crossbow" else 1.0
	if model_id=="field_crossbow": set_loaded_arrow(false)
	flash = 0.063 if show_flash else 0.0

func animate(delta: float, pace: float, duck: float, light: float, hit_stop: float) -> void:
	var f := maxf(0.0,delta-hit_stop)
	pose_time += f * (1.6 + pace * 2.15)
	breath_phase = fmod(breath_phase+f*(1.63+pace*0.20),TAU)
	stroke_phase = fmod(stroke_phase+f*(2.1+minf(pace,1.4)*1.5),TAU)
	kick = move_toward(kick, 0.0, f * 7.0)
	swing = move_toward(swing, 0.0, f * 2.9)
	flash = maxf(0.0, flash - delta)
	if muzzle != null:
		muzzle.visible = flash > 0.0
	equip_lower = move_toward(equip_lower, 0.0, delta * 5.0)
	landing = move_toward(landing, 0.0, delta * 3.8)
	swim_blend = move_toward(swim_blend, 1.0 if swimming else 0.0, delta * 3.2)
	guard_left=maxf(0.0,guard_left-f)
	guard_blend=move_toward(guard_blend,1.0 if guard_left>0.0 else 0.0,f*(10.0 if guard_left>0.0 else 3.0))
	if is_instance_valid(crossbow_bolt):
		crossbow_bolt.visible=bolt_loaded
		crossbow_bolt.position=Vector3(0.035,0.16,0.15)*smoothstep(0.0,0.40,reload_ratio)
	var settle := smoothstep(0.0, 1.0, equip_lower)
	var recovery := sin(swing * PI) if not model_id.is_empty() else 0.0
	var reload_pose := sin(PI * reload_ratio)
	var drift := Vector3(sin(pose_time) * pace * 0.012, cos(pose_time*2.0) * pace * 0.008, 0)
	model.position = Vector3(0.34, -0.322 - duck * 0.026, -0.58) + drift
	model.position.y += sin(breath_phase)*0.0065/(1.0+pace)
	model.position += Vector3(0.049 * charge, -reload_pose * 0.22, kick * 0.11 + charge * 0.10)
	model.position += Vector3(0.0, -hurt_dip * 0.068, hurt_dip * 0.036)
	model.rotation = Vector3(-kick * 0.21 - reload_pose * 0.60 + recovery * 0.65 - charge * 0.28,
		recovery * 0.86 + reload_pose * 0.30, -0.07 + recovery * 0.53 - reload_pose * 0.57 + charge * 0.17)
	if model_id=="reed_spear":
		model.position.z-=recovery*0.24
		model.rotation.y-=recovery*0.63
		model.rotation.x-=recovery*0.37
	if model_id=="field_crossbow":
		model.position+=Vector3(-0.14,0.052,-0.06)*(1.0-reload_pose)
	model.position.y -= settle * 0.13 + landing * 0.075
	var stroke := sin(pose_time) * minf(pace, 1.0)
	model.position += Vector3(stroke * 0.026, -0.060 + stroke * 0.016, 0.052) * swim_blend
	model.rotation.z += (-0.12 + stroke * 0.075) * swim_blend
	if offhand_root.visible:
		offhand_pose=move_toward(offhand_pose,float(offhand_block),delta*5.5)
		if offhand_shield:
			var guard:=smoothstep(0.0,1.0,offhand_pose)
			offhand_root.position=Vector3(-0.35,-0.44,-0.44).lerp(Vector3(-0.35,-0.16,-0.44),guard)
			offhand_root.rotation=Vector3(0.04,0.59,0.15).lerp(Vector3(0.04,0.04,-0.035),guard)
		else:
			var lantern:=float(offhand_id=="torch" and offhand_lit)
			offhand_root.position=Vector3(-0.28,-0.32,-0.53)+Vector3(0.055,0.205,-0.095)*lantern
			offhand_root.rotation=Vector3(-0.10,0.34,0.08)
		offhand_root.position+=Vector3(-0.08,-0.16,0.06)*swim_blend
		offhand_root.position.y+=sin(pose_time)*minf(pace,1.6)*0.010
	if is_instance_valid(resting_left):
		_pose_empty_hands(pace)
	elif search_ratio > 0.0:
		model.position.y -= sin(search_ratio*PI)*0.095
	model.rotation.x += hurt_dip * 0.22 - settle * 0.31 - landing * 0.13
	if absf(light - brightness) > 0.035:
		brightness = light
		_apply_light()

func _pose_empty_hands(pace: float) -> void:
	swimming_fingers = swim_blend > 0.40
	var grip := "open" if swimming_fingers else "fist" if guard_left>0.0 else "relaxed"
	if grip != empty_grip:
		empty_grip = grip
		var key := outfit+"/"+grip
		if not arm_meshes.has(key): arm_meshes[key] = _arm_mesh(grip,outfit)
		right_hand.mesh = arm_meshes[key]
		resting_left.mesh = arm_meshes[key]
	var t := 1.0-swing
	var extend := smoothstep(0.03,0.30,t)*(1.0-smoothstep(0.32,0.95,t))
	var windup := sin(clampf(t/0.20,0.0,1.0)*PI)
	var search := sin(search_ratio*PI)
	for left: bool in [false,true]:
		var side := -1.0 if left else 1.0
		var active := not left if not offhand_id.is_empty() else (swing_serial%2==0)==left
		var jab := extend if active else 0.0
		var guard := 0.0 if active else extend
		var cycle := stroke_phase+(PI if left else 0.0)
		var reach := (0.5+0.5*cos(cycle))*swim_blend
		var pull := sin(cycle)*swim_blend
		var gait := side*sin(pose_time)*minf(pace,2.5)*(1.0-swim_blend)
		# Pose each wrist about its own joint. At rest the elbows hang out of frame
		# and the thumbs face inward. Leading hands straighten on contact or on a swim stroke.
		var wrist := Vector3(-0.80,-0.16,-0.042) if left else Vector3(0.055,-0.045,0.021)
		var guard_wrist:=Vector3(-0.71,-0.056,-0.071) if left else Vector3(0.065,-0.010,0.018)
		wrist=wrist.lerp(guard_wrist,maxf(guard_blend,swim_blend))
		var land_angles:=Vector3(0.64 if left else 0.96,side*(0.67 if left else 0.73),side*0.47)
		land_angles=land_angles.lerp(Vector3(0.81,side*0.74,-side*0.37),guard_blend)
		var open_angles:=Vector3(0.06,side*0.30,side*0.05)
		var angles:=land_angles.lerp(open_angles,swim_blend)
		angles=angles.lerp(Vector3(0.12,side*0.19,-side*0.18),jab)
		angles+=Vector3(0.12*guard-gait*0.026,side*0.26*pull,-side*0.22*reach)
		wrist += Vector3(-side*0.25*jab,0.18*jab+0.024*guard,-(0.29+0.035*swing_force)*jab+0.038*guard)
		wrist.z += (windup*0.043 if active else 0.0)+gait*0.016
		wrist += Vector3(side*(0.093*pull-0.065*reach),0.076*reach-0.040*absf(pull),-0.23*reach+0.061*maxf(0,-pull))
		if left:
			wrist += Vector3(0.085,0.026,-0.16)*search
			angles.z -= search*0.21
		var arm := resting_left if left else right_hand
		var hand_scale := Vector3(-0.95,0.95,0.95) if left else Vector3.ONE
		var basis:=Basis.from_euler(angles).scaled_local(hand_scale)
		arm.transform = Transform3D(basis,wrist-basis*Vector3(0.129,-0.050,-0.133))

func _apply_light() -> void:
	item_material.set_shader_parameter("brightness",brightness)
	skin_material.set_shader_parameter("brightness",brightness)
	for material in color_materials.values():
		material.set_shader_parameter("brightness", brightness)
