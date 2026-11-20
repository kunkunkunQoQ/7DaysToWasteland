extends RefCounted

static func build(chunk:WastelandChunk)->Vector3:
	if posmod(chunk.stream.generator.seed_at(chunk.cell,9237),3)!=0: return Vector3.INF
	var center:=chunk.cave_origin+Vector3(5.1,0,2.2)
	var world:=chunk.position+center
	center.y=chunk.stream.ground_at(world)
	var rim:=PackedVector3Array()
	for i in 16:
		var a:=TAU*i/16.0
		var p:=center+Vector3(1.82*cos(a),0,1.3*sin(a))
		p.y=chunk.stream.ground_at(chunk.position+p)
		if absf(p.y-center.y)>0.32: return Vector3.INF
		rim.append(p)
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	center.y+=0.08
	for i in rim.size():
		surface.add_vertex(center)
		surface.add_vertex(rim[i]+Vector3.UP*0.08)
		surface.add_vertex(rim[(i+1)%rim.size()]+Vector3.UP*0.08)
		var stone:=WastelandLook.form(chunk.decoration_root,Vector3(0.55,0.15,0.32),rim[i]+Vector3.UP*0.035,Color("#bead89"),0.18)
		stone.rotation.y=-TAU*i/16.0+PI*0.5
	surface.generate_normals()
	var water:=MeshInstance3D.new()
	water.mesh=surface.commit()
	water.material_override=WastelandLook.matte(Color("#70ab9c"))
	chunk.decoration_root.add_child(water)
	var steam:=GPUParticles3D.new()
	var plume:=ParticleProcessMaterial.new()
	plume.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	plume.emission_sphere_radius=0.55
	plume.direction=Vector3.UP
	plume.gravity=Vector3(0,0.20,0)
	plume.initial_velocity_min=0.2
	plume.initial_velocity_max=0.42
	plume.scale_min=0.5
	plume.scale_max=1.2
	var fade:=Gradient.new()
	fade.colors=PackedColorArray([Color(0.84,0.91,0.88,0.32),Color(0.87,0.91,0.89,0.0)])
	var gradient:=GradientTexture1D.new()
	gradient.gradient=fade
	plume.color_ramp=gradient
	var puff:=QuadMesh.new()
	puff.size=Vector2(0.32,0.24)
	var mist:=StandardMaterial3D.new()
	mist.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	mist.vertex_color_use_as_albedo=true
	puff.material=mist
	steam.amount=10
	steam.lifetime=1.8
	steam.draw_pass_1=puff
	steam.process_material=plume
	chunk.decoration_root.add_child(steam)
	steam.position=center+Vector3.UP*0.25
	return chunk.position+center
