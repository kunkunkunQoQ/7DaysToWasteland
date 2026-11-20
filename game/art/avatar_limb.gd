extends RefCounted

# Rings are specified from proximal to distal. Their radii follow the underlying
# bone landmarks; neighbouring bones share the same vertices through each joint.
const SIDES := 28

static func build(parent: Node3D, arm: bool, side: int, mass: float, skin: Color, lower: Vector3, distal: Vector3, material: Material, hem:float=-0.147) -> Skeleton3D:
	var skeleton:=Skeleton3D.new()
	parent.add_child(skeleton)
	for i in 3:
		skeleton.add_bone(["Root","Lower","Distal"][i])
		if i>0: skeleton.set_bone_parent(i,i-1)
		var anchor:=Vector3.ZERO if i==0 else lower if i==1 else distal
		skeleton.set_bone_rest(i,Transform3D(Basis.IDENTITY,anchor))
	skeleton.reset_bone_poses()
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var profile:=_arm_sections() if arm else _leg_sections()
	if not arm:
		while profile.size()>1 and profile[0].x>hem-0.008: profile.pop_front()
		profile.push_front(Vector4(hem+0.008,0.077,0.088,0.003))
	var ring_count:=(profile.size()-1)*3+1
	for i in ring_count:
		var index:=mini(i/3,profile.size()-2)
		var t:=(float(i)/3.0)-index
		var p:Vector4=profile[index]
		var q:Vector4=profile[index+1]
		# Cubic Hermite interpolation with derivatives measured in metres.
		var a:Vector4=profile[maxi(0,index-1)]
		var b:Vector4=profile[mini(profile.size()-1,index+2)]
		var span:=q.x-p.x
		var m:Vector4=(q-a)*(span/(q.x-a.x))
		var n:Vector4=(b-p)*(span/(b.x-p.x))
		var row:=p*(2*t*t*t-3*t*t+1)+m*(t*t*t-2*t*t+t)+q*(-2*t*t*t+3*t*t)+n*(t*t*t-t*t)
		for sector in SIDES:
			var angle:=TAU*sector/SIDES
			var across:=sin(angle)
			var front:=cos(angle)
			var pt:=_arm_point(row,across,front,side,mass) if arm else _leg_point(row,across,front,side,mass)
			var low_weight:=1.0-smoothstep(lower.y-0.075,lower.y+0.07,row.x)
			var end_y:=lower.y+distal.y
			var end_weight:=1.0-smoothstep(end_y-0.040,end_y+0.033,row.x)
			surface.set_bones(PackedInt32Array([0,1,2,0]))
			surface.set_weights(PackedFloat32Array([1.0-low_weight,low_weight-end_weight,end_weight,0.0]))
			# Soft occlusion in the cubital/popliteal fossa and inner thigh.
			var hollow:=_bump(row.x,lower.y,0.042)*maxf(0,front if arm else -front)*0.063
			if not arm:
				hollow+=_bump(row.x,-0.120,0.19)*maxf(0,-across*side)*0.060
			surface.set_color(skin.darkened(hollow))
			surface.set_uv(Vector2(float(sector)/SIDES,float(i)/(ring_count-1)))
			surface.add_vertex(pt)
	for i in ring_count-1:
		for j in SIDES:
			var a:=i*SIDES+j
			var b:=i*SIDES+(j+1)%SIDES
			for vertex in [a,a+SIDES,b,b,a+SIDES,b+SIDES]:
				surface.add_index(vertex)
	for j in range(1,SIDES-1):
		surface.add_index(0)
		surface.add_index(j)
		surface.add_index(j+1)
		var base:=(ring_count-1)*SIDES
		surface.add_index(base)
		surface.add_index(base+j+1)
		surface.add_index(base+j)
	surface.generate_normals()
	var visual:=MeshInstance3D.new()
	visual.mesh=surface.commit()
	visual.material_override=material
	skeleton.add_child(visual)
	visual.skeleton=NodePath("..")
	visual.skin=skeleton.create_skin_from_rest_transforms()
	return skeleton

static func _bump(point:float,center:float,radius:float)->float:
	var d:=(point-center)/radius
	return exp(-d*d)

static func _arm_sections()->Array[Vector4]:
	return [Vector4(0.059,0.009,0.018,0.006),Vector4(0.048,0.049,0.053,0.005),Vector4(0.024,0.065,0.068,0.003),
		Vector4(-0.021,0.068,0.075,0.001),Vector4(-0.072,0.060,0.064,0),Vector4(-0.113,0.050,0.056,0.006),
		Vector4(-0.153,0.051,0.061,0.009),Vector4(-0.196,0.047,0.052,0.010),Vector4(-0.234,0.039,0.042,0.009),
		Vector4(-0.263,0.043,0.041,0.012),Vector4(-0.292,0.044,0.044,0.011),Vector4(-0.331,0.049,0.052,0.006),
		Vector4(-0.369,0.045,0.047,0.001),Vector4(-0.415,0.037,0.039,-0.008),Vector4(-0.461,0.029,0.032,-0.015),
		Vector4(-0.486,0.029,0.035,-0.016),Vector4(-0.510,0.025,0.041,-0.021),Vector4(-0.542,0.024,0.047,-0.026),
		Vector4(-0.565,0.018,0.042,-0.025),Vector4(-0.577,0.010,0.031,-0.025)]

static func _arm_point(row:Vector4,across:float,front:float,side:int,mass:float)->Vector3:
	var h:=row.x
	var outer:=across*side
	var axis_x:=0.045*(1.0-smoothstep(-0.26,0.015,h))-0.039*smoothstep(-0.018,0.06,h)
	axis_x-=0.017*(1.0-smoothstep(-0.52,-0.29,h))
	var rx:=row.y
	rx+=0.009*_bump(h,-0.032,0.060)*maxf(0,outer)
	rx+=0.006*_bump(h,-0.338,0.056)*maxf(0,-outer)
	var rz:=row.z
	rz+=maxf(front,0)*0.013*_bump(h,-0.145,0.061)
	rz+=maxf(-front,0)*(0.013*_bump(h,-0.164,0.096)+0.013*_bump(h,-0.265,0.025))
	return Vector3(side*axis_x+across*rx*mass,h,row.w-front*rz*mass)

static func _leg_sections()->Array[Vector4]:
	return [Vector4(-0.043,0.076,0.094,0.005),Vector4(-0.095,0.088,0.103,0.006),Vector4(-0.153,0.082,0.098,0.007),
		Vector4(-0.207,0.074,0.087,0.002),Vector4(-0.268,0.067,0.074,-0.002),Vector4(-0.325,0.056,0.062,-0.002),
		Vector4(-0.360,0.054,0.058,-0.003),Vector4(-0.390,0.052,0.055,-0.006),Vector4(-0.414,0.049,0.052,-0.005),
		Vector4(-0.445,0.047,0.050,0.005),Vector4(-0.489,0.052,0.058,0.013),Vector4(-0.537,0.056,0.063,0.020),
		Vector4(-0.588,0.049,0.056,0.021),Vector4(-0.648,0.036,0.043,0.016),Vector4(-0.695,0.030,0.036,0.011),
		Vector4(-0.741,0.030,0.036,0.008),Vector4(-0.764,0.032,0.043,0.010),Vector4(-0.790,0.038,0.061,0.002),
		Vector4(-0.811,0.047,0.087,-0.022),Vector4(-0.832,0.051,0.109,-0.037),Vector4(-0.846,0.043,0.102,-0.039)]

static func _leg_point(row:Vector4,across:float,front:float,side:int,mass:float)->Vector3:
	var h:=row.x
	var outer:=across*side
	var axis_x:=0.008*_bump(h,-0.16,0.14)-0.011*_bump(h,-0.386,0.11)+0.008*_bump(h,-0.585,0.18)
	var rx:=row.y
	rx+=0.010*maxf(0,-outer)*_bump(h,-0.32,0.063)
	rx+=0.011*maxf(0,-outer)*_bump(h,-0.555,0.080)
	rx+=0.008*maxf(0,outer)*_bump(h,-0.505,0.057)
	rx+=0.006*absf(outer)*_bump(h,-0.757-outer*0.009,0.014)
	var rz:=row.z
	rz+=maxf(0,front)*(0.012*_bump(h,-0.198,0.110)+0.011*_bump(h,-0.392,0.028))
	rz+=maxf(0,-front)*0.012*_bump(h,-0.527,0.085)
	if h < -0.798:
		rx*=0.76+0.24*smoothstep(-0.45,0.71,front)
		axis_x+=0.008*front
	return Vector3(side*axis_x+across*rx*mass,h,row.w-front*rz*mass)
