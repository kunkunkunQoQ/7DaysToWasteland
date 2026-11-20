extends RefCounted

const ORIGINAL := preload("res://assets/ranger_face.png")
# Each sheet is registered from hairline to chin. Keep UVs inside the selected face at the temples.
const SHEETS := {
	"ranger": ["",0,1], "ferryman": ["res://assets/survivor_faces.png",0,3],
	"surveyor": ["res://assets/surveyor_face.png",0,1], "mechanic": ["res://assets/survivor_faces.png",2,3],
	"medic": ["res://assets/survivor_faces_2.png",0,2], "climber": ["res://assets/survivor_faces_2.png",1,2],
	"bronx": ["res://assets/bronx_face.png",0,1]
}
# Jaw width, nose breadth, projection of nose bridge and cheekbone projection.
const SHAPES := {
	"ranger": Vector4(1,1,1,0), "ferryman": Vector4(1.19,1.15,1.07,0.005),
	"surveyor": Vector4(1.01,0.97,0.86,0.008), "mechanic": Vector4(1.10,1.32,0.97,0.005),
	"medic": Vector4(1.04,1.36,0.87,0.008), "climber": Vector4(0.96,0.84,1.14,0.007),
	"bronx": Vector4(1.14,1.38,0.91,0.008)
}
static var meshes: Dictionary = {}
static var materials: Dictionary = {}

static func attach(parent: Node3D, style: String = "ranger") -> MeshInstance3D:
	if not SHEETS.has(style):
		style = "ranger"
	if not meshes.has(style):
		var sheet: Array = SHEETS[style]
		meshes[style] = _sculpt(style, int(sheet[1]), int(sheet[2]))
		var material := StandardMaterial3D.new()
		material.albedo_texture = ORIGINAL if style == "ranger" else load(sheet[0]) as Texture2D
		material.roughness = 0.91
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.texture_repeat = false
		if style != "ranger":
			# UV2 fades the front photograph into the same skin used by the ears and neck.
			var skin := WastelandPartyAvatar.skin_color(style)
			var pigment := Gradient.new()
			pigment.colors = PackedColorArray([Color(skin,0.0),Color(skin,1.0)])
			var blend := GradientTexture1D.new()
			blend.width = 64
			blend.gradient = pigment
			material.detail_enabled = true
			material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			material.detail_albedo = blend
		materials[style] = material
	var head := MeshInstance3D.new()
	head.name = "SculptedFace"
	head.mesh = meshes[style]
	head.material_override = materials[style]
	parent.add_child(head)
	return head

static func _sculpt(style: String, column: int, columns: int) -> ArrayMesh:
	const SIDES := 40
	const ROWS := 25
	var surface := SurfaceTool.new()
	var stride := SIDES+1 if style=="ranger" else SIDES
	var shape: Vector4 = SHAPES[style]
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for row in ROWS + 1:
		var level := float(row)/ROWS
		var base_y := 1.51 + level*0.231
		var width := 0.121 * (0.42 + 0.58*smoothstep(0,0.43,level)) * (1.0-0.18*smoothstep(0.81,1,level))
		if style != "ranger":
			# The rounded chin broadens into the jaw below the cheekbones.
			var jaw_level := clampf((level-0.53)/0.53,-1,0)
			width = 0.118 * (0.35+0.65*sqrt(1.0-jaw_level*jaw_level))
			width *= 1.0-0.15*smoothstep(0.80,1,level)
		width *= lerpf(shape.x,1.0,smoothstep(0.02,0.52,level))
		var depth := 0.115 * (0.76+0.24*smoothstep(0,0.37,level))
		for i in stride:
			var angle := TAU*float(i)/SIDES
			var x := sin(angle)*width
			var front := cos(angle)
			var y := base_y
			if style != "ranger":
				# The jaw angles up towards the ear instead of ending in a level ring around the neck.
				y += 0.038*(1.0-smoothstep(0.0,0.44,level))*(1.0-maxf(0,front))
			# The nose bridge, nostrils, eye sockets and jaw carry the texture around the head in profile.
			var nose_y := 0.47 if style == "ranger" else 0.43
			var tip := exp(-pow(x/(0.026*shape.y),2)-pow((level-nose_y)/0.085,2))*0.037
			var bridge := exp(-pow(x/0.018,2)-pow((level-0.58)/0.18,2))*0.023*shape.z
			var eyes := exp(-pow((absf(x)-0.052)/0.027,2)-pow((level-0.70)/0.085,2))*0.015
			var jaw := exp(-pow(x/0.059,2)-pow((level-0.19)/0.18,2))*0.012
			var cheek := exp(-pow((absf(x)-0.074)/0.037,2)-pow((level-0.55)/0.13,2))*shape.w
			var z := -depth*front-(tip+bridge+jaw+cheek-eyes)*smoothstep(0.2,0.8,front)
			if style in ["surveyor","bronx"]:
				var brow := exp(-pow((absf(x)-0.046)/0.034,2)-pow((level-0.77)/0.055,2))
				var lips := exp(-pow(x/0.050,4)-pow((level-0.24)/0.052,2))
				var chin := exp(-pow(x/0.056,2)-pow((level-0.09)/0.13,2))
				var detail := 0.004*brow+0.005*lips+0.004*chin
				if style == "bronx":
					detail += 0.004*brow+0.006*lips+0.005*chin
				z -= detail*smoothstep(0.36,0.85,front)
			var u := 0.5 - sin(angle)*0.49
			if style != "ranger":
				# Project cheeks and lips to their anatomical width as the lower head tapers.
				var side_u := clampf(0.5-x/0.25,0.015,0.985)
				u = lerpf(side_u,0.03 if x > 0 else 0.97,smoothstep(0.0,0.68,-front))
			elif front < 0.0:
				# The back of the head samples the dark hair along the edge of the painting.
				u = 0.01 if x > 0 else 0.99
			var v := 1.0-level
			if style in ["surveyor","bronx"]:
				# Register the individual portrait to the eye socket, nose tip, mouth and chin.
				var eye_line := 0.273
				var nose_line := 0.552 if style=="surveyor" else 0.526
				var mouth_line := 0.751 if style=="surveyor" else 0.710
				if level >= 0.70:
					v = lerpf(eye_line,0.0,(level-0.70)/0.30)
				elif level >= 0.43:
					v = lerpf(nose_line,eye_line,(level-0.43)/0.27)
				elif level >= 0.24:
					v = lerpf(mouth_line,nose_line,(level-0.24)/0.19)
				else:
					v = lerpf(0.988,mouth_line,level/0.24)
			surface.set_uv(Vector2((column+u)/columns,v))
			if style != "ranger":
				surface.set_uv2(Vector2(1.0-smoothstep(0.30,0.83,front),0.5))
			surface.add_vertex(Vector3(x,y,z))
	for row in ROWS:
		for i in SIDES:
			var a := row*stride+i
			var c := a+stride
			# All three coordinate sets meet at the nose. Share vertices across this seam.
			var next := a+1 if i<SIDES-1 or style=="ranger" else row*stride
			for index in [a,next,c,c,next,next+stride]:
				surface.add_index(index)
	surface.generate_normals()
	return surface.commit()
