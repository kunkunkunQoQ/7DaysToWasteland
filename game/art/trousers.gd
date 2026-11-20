extends RefCounted

const Limb := preload("res://game/art/avatar_limb.gd")
const CANVAS := Color("#72795a",0.50)
const QUILT := Color("#4b6580",0.50)
const SIDES := 28
static var cache := {}

static func dye(id:String)->Color:
	return QUILT if id=="quilted_pants" else CANVAS

static func leg(id:String,side:int,mass:float)->ArrayMesh:
	var key:=[id,side,mass]
	if cache.has(key): return cache[key]
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var padded:=id=="quilted_pants"
	var rings:=Limb._leg_sections()
	var count:=0
	for row:Vector4 in rings:
		if row.x < -0.745: break
		var weight:=1.0-smoothstep(-0.465,-0.32,row.x)
		var cuff:=row.x < -0.69
		var bulge:=0.009 if padded and count%2==0 and not cuff else 0.0
		for j in SIDES:
			var angle:=TAU*j/SIDES
			var radial:=Vector2(sin(angle),cos(angle))
			var vertex:=Limb._leg_point(row,radial.x,radial.y,side,mass)
			var ease:=(0.023 if padded else 0.015)+bulge
			vertex+=Vector3(radial.x,0,-radial.y)*ease*mass
			var color:=dye(id)
			if cuff or (padded and count%2==1):
				color=color.darkened(0.22 if cuff else 0.12)
			elif not padded and row.x < -0.14 and row.x > -0.30 and radial.x*side>0.54:
				color=color.lightened(0.15)
			if absf(radial.x)>0.99:color=color.lightened(0.12)
			surface.set_color(color)
			surface.set_uv(Vector2(float(j)/SIDES,-row.x))
			surface.set_bones(PackedInt32Array([0,1,0,0]))
			surface.set_weights(PackedFloat32Array([1.0-weight,weight,0,0]))
			surface.add_vertex(vertex)
		count+=1
	for i in count-1:
		for j in SIDES:
			var a:=i*SIDES+j
			var b:=i*SIDES+(j+1)%SIDES
			for index in [a,a+SIDES,b,b,a+SIDES,b+SIDES]: surface.add_index(index)
	surface.generate_normals()
	cache[key]=surface.commit()
	return cache[key]

static func packed_mesh(id:String)->ArrayMesh:
	var mesh:=SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var waist:=WastelandBestiary.Sculpture.new(531)
	waist.loft([Vector4(0.01,0.195,0.135,0),Vector4(0.15,0.172,0.128,0),Vector4(0.176,0.171,0.124,0)],dye(id))
	waist.loft([Vector4(0.141,0.175,0.131,0),Vector4(0.171,0.175,0.129,0)],dye(id).darkened(0.30))
	_append_static(mesh,waist.commit(),Transform3D(Basis.IDENTITY,Vector3.UP*0.35))
	for side:int in [-1,1]:
		_append_static(mesh,leg(id,side,1.0),Transform3D(Basis(Vector3.BACK,side*0.09),Vector3(side*0.105,0.42,0)))
	return mesh.commit()

static func _append_static(output:SurfaceTool,source:ArrayMesh,pose:Transform3D)->void:
	var data:=source.surface_get_arrays(0)
	var indices:PackedInt32Array=data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	for i in (indices.size() if not indices.is_empty() else data[Mesh.ARRAY_VERTEX].size()):
		var vertex:int=indices[i] if not indices.is_empty() else i
		output.set_color(data[Mesh.ARRAY_COLOR][vertex])
		output.set_normal(pose.basis*data[Mesh.ARRAY_NORMAL][vertex])
		output.add_vertex(pose*data[Mesh.ARRAY_VERTEX][vertex])
