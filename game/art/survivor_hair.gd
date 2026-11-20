extends RefCounted

const HAIR := preload("res://shaders/survivor_hair.gdshader")
static var cache:Dictionary={}

static func attach(parent:Node3D, style:String) -> void:
	if not cache.has(style):
		var cap:=SurfaceTool.new()
		var locks:=SurfaceTool.new()
		cap.begin(Mesh.PRIMITIVE_TRIANGLES)
		locks.begin(Mesh.PRIMITIVE_TRIANGLES)
		var copper:=style=="climber"
		var color:=Color("#83462f") if copper else Color("#292324")
		for i in 72:
			for j in 12:
				var a:=TAU*i/72.0
				var b:=TAU*(i+1)/72.0
				var u:=float(j)/12
				var v:=float(j+1)/12
				var coords:=[Vector2(a,u),Vector2(b,u),Vector2(a,v),Vector2(b,v)]
				for k:int in [0,1,2,1,3,2]:
					var uv:Vector2=coords[k]
					var pt:=_scalp(uv.x,uv.y,copper)
					_vertex(cap,pt,_normal(pt),Vector2(uv.x/TAU,1-uv.y),color.darkened(0.18))
		var count:=78 if copper else 83
		for i in count:
			var a:=TAU*i/count
			var path:=PackedVector3Array()
			var ns:=PackedVector3Array()
			var sway:=0.66 if copper else -0.83
			for j in 17:
				var t:=j/16.0
				var f:=lerpf(0.985,0.0,t)
				var split:=tanh((sin(a)-(0.40 if copper else -0.47))*6.0)
				var angle:=a+(sway*0.66+split*0.34)*(0.6+0.4*cos(a))*sin(PI*t)+0.045*sin(a*9+3*t)*t
				var gather:=smoothstep(-0.03,0.95,-cos(a))*smoothstep(0.28,1,t)
				var anchor:=-2.49 if copper else PI
				angle+=angle_difference(angle,anchor)*gather*0.81
				var pt:=_scalp(angle,f,copper)
				var n:=_normal(pt)
				pt+=n*(0.002+0.0035*sin(PI*t))
				pt.y-=smoothstep(0.78,1.0,t)*(0.003+0.012*(0.5+0.5*sin(i*8.13)))
				path.append(pt)
				ns.append(n)
			_ribbon(locks,path,ns,0.009+0.0028*sin(i*2.4),0.0023,color.lightened(0.02+0.035*(0.5+0.5*cos(i*2.38))))
		# Narrow temple wisps leave the ears exposed and taper independently.
		for side:float in [-1,1]:
			for i in 4:
				var a:=side*(0.92+i*0.072)
				var start:=_scalp(a,0.32,copper)
				var mid:=_scalp(a+side*0.12,0.035,copper)
				var tip:=mid+Vector3(-side*0.002,-0.022-i*0.003,0.012)
				_lock(locks,[start,mid,tip],0.006-i*0.00065,0.002,color,Vector3(side,0,-0.35))
		if copper: _braid(locks,color)
		else: _pony(locks,color)
		var meshes:=[cap.commit(),locks.commit()]
		for i in 2:
			var mat:=ShaderMaterial.new()
			mat.shader=HAIR
			mat.set_shader_parameter("strand_count",110.0 if i==0 else 9.0)
			meshes[i].surface_set_material(0,mat)
		cache[style]=meshes
	for i in 2:
		var node:=MeshInstance3D.new()
		node.name="HairScalp" if i==0 else "StyledLocks"
		node.mesh=cache[style][i]
		parent.add_child(node)

static func _scalp(a:float,f:float,copper:bool)->Vector3:
	var c:=cos(a)
	var front:=smoothstep(-0.48,0.94,c)
	var part:=0.42 if copper else -0.54
	var line:=1.566-0.022*smoothstep(0.05,0.97,-c)+0.009*sin(4*a+0.6)*(1.0-front)+0.149*front+0.015*exp(-pow((sin(a)-part)/0.23,2))*front
	line+=0.011*sin(a*(2.0 if copper else 3.0)+0.5)*front+0.014*exp(-pow((absf(sin(a))-0.98)/0.07,2))
	var y:=lerpf(line,1.799 if copper else 1.794,sin(f*PI*0.5))
	var crown:=1.799 if copper else 1.794
	var altitude:=clampf((y-1.696)/(crown-1.696),0,1)
	var rad:=sqrt(maxf(0.0,1.0-altitude*altitude))
	rad*=0.87+0.13*smoothstep(1.562,1.677,y)
	var shift:=part*0.045*(1-rad)
	return Vector3(sin(a)*rad*0.126+shift,y,-cos(a)*rad*0.133+0.003+0.016*f)

static func _normal(p:Vector3)->Vector3:
	return Vector3(p.x,(p.y-1.696)*1.19,p.z-0.006).normalized()

static func _vertex(s:SurfaceTool,p:Vector3,n:Vector3,uv:Vector2,c:Color)->void:
	s.set_color(c)
	s.set_uv(uv)
	s.set_normal(n)
	s.add_vertex(p)

static func _ribbon(s:SurfaceTool,path:PackedVector3Array,ns:PackedVector3Array,width:float,depth:float,color:Color)->void:
	const ACROSS:=7
	var base:=int(s.get_meta("vertex_count",0))
	s.set_meta("vertex_count",base+path.size()*ACROSS)
	for j in path.size():
		var t:=float(j)/(path.size()-1)
		var along:=(path[mini(j+1,path.size()-1)]-path[maxi(j-1,0)]).normalized()
		var right:=ns[j].cross(along).normalized()
		var bulge:=pow(maxf(0,sin(PI*t)),0.38)
		var w:=width*(0.10+0.90*bulge)
		for k in ACROSS:
			var x:=2.0*k/(ACROSS-1)-1.0
			var p:=path[j]+right*x*w+ns[j]*depth*(1.0-x*x)*bulge
			var normal:=(ns[j]+right*x*0.50).normalized()
			_vertex(s,p,normal,Vector2((x+1)*0.5,t),color.darkened(0.13*(1-t)+0.08*absf(x)))
	for j in path.size()-1:
		for k in ACROSS-1:
			var a:=base+j*ACROSS+k
			for index:int in [a,a+1,a+ACROSS,a+1,a+ACROSS+1,a+ACROSS]: s.add_index(index)

static func _lock(s:SurfaceTool,points:Array,width:float,depth:float,color:Color,normal:Vector3)->void:
	var path:=PackedVector3Array()
	var ns:=PackedVector3Array()
	for j in (points.size()-1)*5+1:
		var idx:=mini(j/5,points.size()-2)
		var t:=j/5.0-idx
		var p:Vector3=points[idx]
		p=p.cubic_interpolate(points[idx+1],points[maxi(0,idx-1)],points[mini(idx+2,points.size()-1)],t)
		path.append(p)
		ns.append(normal.normalized())
	_ribbon(s,path,ns,width,depth,color)

static func _tube(s:SurfaceTool,path:PackedVector3Array,radii:PackedFloat32Array,color:Color)->void:
	const SIDES:=12
	var base:=int(s.get_meta("vertex_count",0))
	s.set_meta("vertex_count",base+path.size()*(SIDES+1))
	for i in path.size():
		var along:=(path[mini(i+1,path.size()-1)]-path[maxi(0,i-1)]).normalized()
		var x:=along.cross(Vector3.RIGHT).normalized()
		var y:=along.cross(x)
		for k in SIDES+1:
			var angle:=TAU*k/SIDES
			var n:=x*cos(angle)+y*sin(angle)
			_vertex(s,path[i]+n*radii[i],n,Vector2(float(k)/SIDES,float(i)/(path.size()-1)),color)
	for i in path.size()-1:
		for k in SIDES:
			var a:=base+i*(SIDES+1)+k
			for idx:int in [a,a+SIDES+1,a+1,a+1,a+SIDES+1,a+SIDES+2]: s.add_index(idx)

static func _braid(s:SurfaceTool,color:Color)->void:
	for strand in 3:
		var pts:=PackedVector3Array()
		var rs:=PackedFloat32Array()
		for i in 79:
			var t:=i/78.0
			var phase:=TAU*(3.35*t+strand/3.0)
			var center:=Vector3(-0.061-0.102*sin(t*PI*0.74),1.685-0.348*t,0.101-0.208*smoothstep(0,0.83,t))
			var rx:=lerpf(0.023,0.010,t)
			pts.append(center+Vector3(rx*sin(phase),0,rx*0.64*sin(2*phase)))
			rs.append(lerpf(0.0165,0.0065,t))
		_tube(s,pts,rs,color.lightened(strand*0.032))
		var tip:=pts[-1]
		_lock(s,[tip,tip+Vector3(-0.001,-0.020,0.005),tip+Vector3(0.012,-0.042,0.007)],0.009,0.004,color,Vector3(0,0,-1))

static func _pony(s:SurfaceTool,color:Color)->void:
	for strand in 19:
		var pts:=PackedVector3Array()
		var rs:=PackedFloat32Array()
		var a:=TAU*strand/19
		for i in 26:
			var t:=i/25.0
			var radius:=0.009+0.021*sin(PI*t)
			var center:=Vector3(0.015*t+0.018*sin(PI*t),1.677-0.164*t,0.112+0.067*sin(PI*t*0.7))
			pts.append(center+Vector3(cos(a+t*0.5)*radius,0.009*sin(a)-0.017*t*sin(2*a),sin(a+t*0.5)*radius))
			rs.append((0.007+0.006*sin(PI*t))*(1-smoothstep(0.8,1,t)*0.95))
		_tube(s,pts,rs,color.lightened(0.012+0.044*(strand%4)/3.0))

	# A narrow fabric tie compresses the locks below their common root.
	var tie:=PackedVector3Array()
	var sizes:=PackedFloat32Array()
	for i in 33:
		var angle:=TAU*i/32
		tie.append(Vector3(0.013+0.027*cos(angle),1.654+0.008*sin(angle),0.134+0.020*sin(angle)))
		sizes.append(0.0036)
	_tube(s,tie,sizes,Color("#4b403d"))