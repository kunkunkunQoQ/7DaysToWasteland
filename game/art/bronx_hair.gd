extends RefCounted

const HAIR := preload("res://shaders/survivor_hair.gdshader")
const Sculpt := WastelandBestiary.Sculpture
static var hair_mesh:ArrayMesh
static var ear_material:ShaderMaterial

static func attach(parent:Node3D,skin:Color)->void:
	if hair_mesh==null:
		hair_mesh=_build()
	var hair:=MeshInstance3D.new()
	hair.name="CroppedTwists"
	hair.mesh=hair_mesh
	parent.add_child(hair)
	var ears:=Sculpt.new(7521)
	for side:int in [-1,1]:
		ears.oval(Vector3(side*0.115,1.628,0.004),Vector3(0.019,0.030,0.017),skin.darkened(0.06))
		ears.oval(Vector3(side*0.128,1.631,-0.002),Vector3(0.005,0.014,0.009),skin.darkened(0.24))
	var lobes:=MeshInstance3D.new()
	lobes.mesh=ears.commit()
	if ear_material==null:
		ear_material=ShaderMaterial.new()
		ear_material.shader=preload("res://shaders/survivor_surface.gdshader")
	lobes.material_override=ear_material
	parent.add_child(lobes)

static func _point(a:float,t:float)->Vector3:
	var front:=smoothstep(-0.30,0.88,cos(a))
	var temple:=exp(-pow((absf(sin(a))-0.91)/0.13,2))
	var line:=1.624+0.093*front+0.008*temple
	var y:=lerpf(line,1.783,sin(t*PI*0.5))
	var h:=clampf((y-1.687)/0.096,0,1)
	var r:=sqrt(maxf(0,1-h*h))*(0.91+0.09*smoothstep(1.556,1.661,y))
	var level:=clampf((y-1.51)/0.231,0,1)
	var jaw:=clampf((level-0.53)/0.53,-1,1)
	var edge:=0.118*(0.35+0.65*sqrt(1.0-jaw*jaw))*(1.0-0.15*smoothstep(0.80,1,level))
	var blend:=smoothstep(0,0.25,t)
	var rx:=lerpf(edge+0.0025,0.133*r,blend)
	var rz:=lerpf(0.118,(0.130+0.014*smoothstep(1.719,1.739,y))*r,blend)
	return Vector3(sin(a)*rx,y,0.001-cos(a)*rz)

static func _normal(p:Vector3)->Vector3:
	return Vector3(p.x,(p.y-1.68)*1.18,p.z-0.005).normalized()

static func _build()->ArrayMesh:
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const AROUND:=72
	const ROWS:=24
	var top:=Color("#211a19")
	var stubble:=Color("#604538")
	for j in ROWS+1:
		var t:=float(j)/ROWS
		for k in AROUND+1:
			var a:=TAU*k/AROUND
			var pt:=_point(a,t)
			var fade:=smoothstep(0.015,0.59,t+0.21*maxf(cos(a),0))
			var tint:=stubble.lerp(top,fade)
			surface.set_normal(_normal(pt))
			surface.set_color(tint)
			surface.set_uv(Vector2(float(k)/AROUND,t))
			surface.add_vertex(pt)
	for j in ROWS:
		for k in AROUND:
			var a:=j*(AROUND+1)+k
			for idx:int in [a,a+1,a+AROUND+1,a+1,a+AROUND+2,a+AROUND+1]:
				surface.add_index(idx)
	var mesh:=surface.commit()
	var shader:=ShaderMaterial.new()
	shader.shader=preload("res://shaders/bronx_fade.gdshader")
	mesh.surface_set_material(0,shader)
	# Each short twist rises, coils and folds back onto the crown.
	surface=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SAMPLES:=10
	const SIDES:=7
	var count:=0
	const TWISTS:=284
	for i in TWISTS:
		var a:=i*2.39996323+0.028*sin(i*6.13)
		var t:=1.0-0.72*sqrt((i+0.4)/TWISTS)
		var base:=_point(a,t)
		var n:=_normal(base)
		var tangent:=Vector3(cos(a),0,sin(a))
		var cross_axis:=n.cross(tangent).normalized()
		var size:=0.0043+0.0024*(0.5+0.5*sin(i*1.73))
		size*=smoothstep(0.23,0.52,t)+0.18
		var path:=PackedVector3Array()
		for j in SAMPLES:
			var f:=float(j)/(SAMPLES-1)
			var theta:=a+1.19*sin(i*5.72)+f*TAU*(0.89+0.19*sin(i*4.81))
			path.append(base+n*(0.001+size*sin(PI*f)*1.25)+size*(tangent*cos(theta)+cross_axis*sin(theta)))
		for j in SAMPLES:
			var f:=float(j)/(SAMPLES-1)
			var travel:=(path[mini(j+1,SAMPLES-1)]-path[maxi(j-1,0)]).normalized()
			var r:=travel.cross(n).normalized()
			var up:=r.cross(travel)
			for k in SIDES+1:
				var ang:=TAU*k/SIDES
				var normal:=r*cos(ang)+up*sin(ang)
				surface.set_normal(normal)
				surface.set_color(top.lightened(0.014+0.040*(i%5)/4.0))
				surface.set_uv(Vector2(float(k)/SIDES,f))
				surface.add_vertex(path[j]+size*(0.22+0.39*sin(PI*f))*normal)
		for j in SAMPLES-1:
			for k in SIDES:
				var start:=count+j*(SIDES+1)+k
				for idx:int in [start,start+1,start+SIDES+1,start+1,start+SIDES+2,start+SIDES+1]:
					surface.add_index(idx)
		count+=SAMPLES*(SIDES+1)
	mesh=surface.commit(mesh)
	var curls:=ShaderMaterial.new()
	curls.shader=HAIR
	curls.set_shader_parameter("strand_count",6.0)
	mesh.surface_set_material(1,curls)
	return mesh
