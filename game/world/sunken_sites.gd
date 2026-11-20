class_name WastelandSunkenSites
extends RefCounted

const OAK := Color("#835f43")
const TIMBER := Color("#ad8862")
const IRON := Color("#486461")
const RUST := Color("#a46548")
const STONE := Color("#778a7c")
const LICHEN := Color("#b5b39a")
static var beds: Dictionary = {}
static var cache_seed := 0
static var locations: Dictionary = {}

static func landmarks(generator: WastelandTerrainGen) -> Dictionary:
	if generator.revision < 2:
		return {}
	if not locations.is_empty() and cache_seed == generator.seed_value:
		return locations
	locations = {}
	cache_seed = generator.seed_value
	for row in [["ferry", -8.0, -3.5], ["pump", 24.0, -4.7], ["bridge", -20.0, -7.4]]:
		for z in range(31, -68, -1):
			var x := float(row[1])
			var y := generator.ground(x, z)
			if y <= float(row[2]) and generator.water_basin(x, z):
				locations[row[0]] = Vector3(x, y, z)
				break
	return locations

static func populate(chunk: WastelandChunk) -> void:
	var sites := landmarks(chunk.stream.generator)
	_bed(chunk, sites)
	for key in sites:
		var point: Vector3 = sites[key]
		if WastelandTerrainGen.chunk_at(Vector2(point.x, point.z)) != chunk.cell:
			continue
		var ruin := Node3D.new()
		ruin.name = "Sunken_" + str(key)
		ruin.position = point - chunk.position
		chunk.poi_root.add_child(ruin)
		var frame := WreckFrame.new(chunk, ruin, key)
		var crate := Vector3.ZERO
		var tether := Vector3.ZERO
		match key:
			"ferry":
				ruin.rotation.y = 1.33
				_ferry(chunk,ruin,frame)
				crate = Vector3(-1.95, 0.72, -1.65)
				tether = Vector3(1.05, 1.18, 2.8)
			"pump":
				ruin.rotation.y = -0.27
				_pump(chunk,ruin,frame)
				crate = Vector3(-2.95, 1.06, 1.35)
				tether = Vector3(1.45, 1.23, -1.42)
			"bridge":
				ruin.rotation.y = 0.28
				_bridge(chunk,ruin,frame)
				crate = Vector3(-2.05, 0.74, 1.79)
				tether = Vector3(3.0, 2.24, 0)
		var yaw:=0.0
		if chunk.stream.generator.site_revision>0:
			var rng:=RandomNumberGenerator.new()
			rng.seed=chunk.stream.generator.seed_at(chunk.cell,0x48d7)^str(key).hash()
			# Move outwards from the proven salvage position, along the open side
			# of the wreck; reject shallow water and steep or out-of-chunk ledges.
			var outward:=Vector3(crate.x,0,crate.z).normalized()
			var crosswise:=Vector3(outward.z,0,-outward.x)
			for attempt in 6:
				var alternative:=crate+outward*rng.randf_range(0.25,1.9)+crosswise*rng.randf_range(-0.62,0.62)
				var world:=ruin.to_global(alternative)
				var height:float=chunk.stream.ground_at(world)
				if WastelandTerrainGen.chunk_at(Vector2(world.x,world.z))!=chunk.cell or height> -1.0: continue
				if absf(chunk.stream.ground_at(world+Vector3.RIGHT*0.65)-height)>0.50 or absf(chunk.stream.ground_at(world+Vector3.BACK*0.65)-height)>0.50: continue
				crate=alternative
				break
			yaw=ruin.rotation.y+atan2(outward.x,outward.z)+rng.randf_range(-0.23,0.23)
		_cache(chunk, str(key), ruin.transform * crate,yaw)
		if frame.bearing_enabled:
			match key:
				"ferry": tether = _hull_point(0.95,0.96,1)
				"pump": tether = Vector3(1.13,2.24,-1.42)
				"bridge": tether = Vector3(3.17,2.19,0.60)
		_marker(chunk,ruin,tether,-point.y,key)

static func _section(chunk:WastelandChunk,ruin:Node3D,mesh:ArrayMesh,id:String,hp:float,finish:WastelandScenery=null)->void:
	var center:=mesh.get_aabb().get_center()
	var body:=StaticBody3D.new()
	body.position=center
	body.collision_layer=2
	body.collision_mask=0
	ruin.add_child(body)
	var visual:=MeshInstance3D.new()
	visual.position=-center
	visual.mesh=mesh
	if finish!=null and finish.triangle_count>0:
		# Seams, dials and carving stay on the piece, without adding snag points for swimmers.
		var combined:=SurfaceTool.new()
		combined.begin(Mesh.PRIMITIVE_TRIANGLES)
		combined.append_from(mesh,0,Transform3D.IDENTITY)
		combined.append_from(finish.commit(),0,Transform3D.IDENTITY)
		visual.mesh=combined.commit()
		visual.set_meta("structural_mesh",mesh)
	visual.material_override=WastelandLook.colored_material()
	body.add_child(visual)
	if not chunk.stream.is_preview:
		var shape:=mesh.create_trimesh_shape()
		shape.backface_collision=true
		var collision:=CollisionShape3D.new()
		collision.shape=shape
		collision.position=-center
		body.add_child(collision)
	chunk.track_structure(body,id,hp)

# Keep the original member numbering while recording each joint beside its geometry.
class WreckFrame:
	var chunk: WastelandChunk
	var ruin: Node3D
	var prefix: String
	var bearing_enabled: bool
	var serial := 0

	func _init(owner_chunk: WastelandChunk, root: Node3D, key: String) -> void:
		chunk = owner_chunk
		ruin = root
		prefix = "wreck/" + key + "/"
		bearing_enabled = chunk.stream.generator.site_revision > 0

	func box(at: Vector3, size: Vector3, color: Color, supports := [], pose := Basis.IDENTITY, name := "", material := "") -> String:
		var id := prefix + name
		if name.is_empty():
			id = prefix + "member/" + str(serial)
			serial += 1
		var body := WastelandLook.solid(ruin,size,at,color)
		body.basis = pose
		if not material.is_empty(): body.set_meta("salvage_material",material)
		elif color==STONE or color==LICHEN: body.set_meta("salvage_material","stone")
		chunk.track_structure(body,id,125)
		joint(id,supports)
		return id

	func beam(start: Vector3, end: Vector3, width: float, depth: float, color: Color, supports: Array, material := "") -> String:
		var along := end - start
		var up := Vector3.RIGHT if absf(along.normalized().dot(Vector3.UP)) > 0.94 else Vector3.UP
		return box((start+end)*0.5,Vector3(width,depth,along.length()),color,supports,Basis.looking_at(along.normalized(),up),"",material)

	func joint(id: String, supports: Array) -> void:
		if bearing_enabled and not supports.is_empty():
			chunk.support_graph[id] = [supports]

	# Extend any exposed foundation down to the undisturbed bed. Excavation
	# affects the bearing check, never the generated length of the footing.
	func grounded(id: String, contacts: Array, width: float, color: Color) -> void:
		if not bearing_enabled: return
		var samples: Array[Vector2] = []
		for local: Vector3 in contacts:
			var world := ruin.to_global(local)
			samples.append(Vector2(world.x,world.z))
			var depth: float = world.y - chunk.stream.generator.ground(world.x,world.z) + 0.15
			if depth <= 0.16 or not chunk.structures.has(id): continue
			var body: StaticBody3D = chunk.structures[id][0]
			var center := body.to_local(world - Vector3.UP*depth*0.5)
			var size := Vector3(width,depth,width)
			var mesh := WastelandLook.box(body,size,center,color)
			mesh.basis = body.global_basis.inverse()*ruin.global_basis*Basis.from_scale(mesh.scale)
			if not chunk.stream.is_preview:
				var shape := WastelandLook.collider(body,size,center)
				shape.basis = body.global_basis.inverse()*ruin.global_basis
		chunk.footings[id] = samples

static func _quad(b: WastelandScenery, a: Vector3, c: Vector3, d: Vector3, e: Vector3, tint: Color) -> void:
	var normal := (c - a).cross(e - a).normalized()
	for face in [normal, -normal]:
		b.triangle(a, c, d, face, tint)
		b.triangle(a, d, e, face, tint)

static func _hull_point(t: float, height: float, side: float) -> Vector3:
	var taper := 0.26 + 0.74 * sin(t * PI)
	var x := side * lerpf(0.19, 1.47, pow(height, 0.59)) * taper
	var y := 0.16 + height * 1.62 + pow(absf(t * 2.0 - 1.0), 3.0) * 0.46
	return Basis(Vector3.BACK, 0.70) * Vector3(x, y, (t - 0.5) * 9.7) + Vector3(0.30, 0.05, 0)

static func _hull_iron(t: float, end: float, side: float, section: int, rim: float) -> WastelandScenery:
	var b:=WastelandScenery.new(241+section)
	var outside:=Basis(Vector3.BACK,0.70)*Vector3.RIGHT*side
	var seam:=lerpf(t,end,0.17)
	var lift:=outside*0.035
	# Wrought straps bind the board ends. The split port strakes retain only the lower rivets.
	var low:=0.16
	var top:=minf(rim-0.03,0.88)
	_quad(b,_hull_point(seam,low,side)+lift,_hull_point(seam+0.009,low,side)+lift,
		_hull_point(seam+0.009,top,side)+lift,_hull_point(seam,top,side)+lift,IRON.darkened(0.08))
	for height:float in [0.21,0.41,0.65,0.83]:
		if height>=top: continue
		var foot:=_hull_point(seam+0.0045,height,side)+lift
		b.tube(PackedVector3Array([foot,foot+outside*0.018]),PackedFloat32Array([0.042,0.033]),5,RUST)
	if section in [1,2,7,8]:
		var start:=_hull_point(t,0.56,side)+lift
		var finish:=_hull_point(end,0.56,side)+lift
		var shift:=Vector3.UP*0.071
		_quad(b,start,finish,finish+shift,start+shift,Color("#bcaa79") if section%2 else Color("#909b88"))
	return b

static func _ferry(chunk:WastelandChunk,ruin:Node3D,frame:WreckFrame) -> void:
	for section in range(10):
		var t := section / 10.0
		var t2 := (section + 1) / 10.0
		var keel := frame.prefix + "keel/" + str(section)
		if frame.bearing_enabled:
			var center := _hull_point((t+t2)*0.5,0,0)
			frame.box(center,Vector3(0.50,0.19,1.02),OAK.darkened(0.22),[],Basis.IDENTITY,"keel/"+str(section))
			frame.grounded(keel,[center+Vector3(0,-0.08,-0.33),center+Vector3(0,-0.08,0.33)],0.36,OAK.darkened(0.35))
		for side in [-1.0, 1.0]:
			var hull := frame.prefix+"hull/%d/%d"%[section,int(side)]
			var rim_height := 0.48 if frame.bearing_enabled and side<0 and section in [3,4,5] else 0.97
			var b:=WastelandScenery.new(738+section)
			for plank in 6:
				if side < 0 and section in [3,4,5] and plank >= 3:
					continue
				var h := plank / 6.0
				var h2 := (plank + 0.93) / 6.0
				_quad(b, _hull_point(t,h,side), _hull_point(t2,h,side), _hull_point(t2,h2,side), _hull_point(t,h2,side), OAK.lightened((section + plank * 2) % 4 * 0.09))
			if section>=6:
				_quad(b,_hull_point(t,0.78,side)+Vector3.RIGHT*side*0.023,_hull_point(t2,0.78,side)+Vector3.RIGHT*side*0.023,
					_hull_point(t2,0.82,side)+Vector3.RIGHT*side*0.023,_hull_point(t,0.82,side)+Vector3.RIGHT*side*0.023,Color("#83a8a0"))
			_section(chunk,ruin,b.commit(),hull,110,_hull_iron(t,t2,side,section,rim_height))
			frame.joint(hull,[keel])
			if section % 2 == 0:
				var knee := _hull_point(t, 0.29, side)
				var lower := frame.beam(_hull_point(t,0,side),knee,0.15,0.17,TIMBER,[hull])
				frame.beam(knee,_hull_point(t,rim_height+0.06,side),0.16,0.15,TIMBER,[lower])
			frame.beam(_hull_point(t,rim_height,side),_hull_point(t2,rim_height,side),0.16,0.12,TIMBER,[hull])
	for bench in [0.18,0.35,0.68,0.82]:
		var section := floori(bench*10)
		var left_height := 0.46 if frame.bearing_enabled and section in [3,4,5] else 0.71
		frame.beam(_hull_point(bench,left_height,-1),_hull_point(bench,0.71,1),0.42,0.12,OAK.lightened(0.23),
			[frame.prefix+"hull/%d/-1"%section,frame.prefix+"hull/%d/1"%section])
	var b:=WastelandScenery.new(738)
	var mast := _hull_point(0.67,0.16,1)
	var spar := frame.beam(mast,mast+Vector3(-2.82,2.75,0.72),0.22,0.23,TIMBER,[frame.prefix+"hull/6/1"])
	var yard := frame.beam(mast+Vector3(-2.23,2.24,0.58),mast+Vector3(-2.23,2.24,2.45),0.11,0.12,OAK,[spar])
	var boom := mast + Vector3(-2.23,2.24,2.45)
	var clew := _hull_point(0.91,0.68,1)
	b.tube(PackedVector3Array([boom,boom.lerp(clew,0.56)+Vector3(0,-0.24,0.11),clew]),PackedFloat32Array([0.033,0.030,0.038]),5,TIMBER)
	for strip in 3:
		var a := mast + Vector3(-2.23,2.21,0.66+strip*0.46)
		var hem := a + Vector3(0.24,-0.44 - strip * 0.13,0.08)
		_quad(b,a,a+Vector3(0,0,0.42),hem+Vector3(-0.06,0.08,0.28),hem,Color("#afb19a").darkened(strip*0.06))
	_section(chunk,ruin,b.commit(),"wreck/ferry/rigging",75)
	frame.joint(frame.prefix+"rigging",[yard])
	frame.joint(frame.prefix+"marker",[frame.prefix+"hull/9/1"])

static func _pump(chunk:WastelandChunk,ruin:Node3D,frame:WreckFrame) -> void:
	var slab := frame.box(Vector3(0,0.12,0),Vector3(5.6,0.44,4.1),STONE)
	var contacts := []
	for x: float in [-2.32,2.32]:
		for z: float in [-1.62,1.62]: contacts.append(Vector3(x,-0.08,z))
	frame.grounded(slab,contacts,0.70,STONE.darkened(0.18))
	var width := 2.55 if frame.bearing_enabled else 5.1
	var roof := frame.box(Vector3(-1.275 if frame.bearing_enabled else 0.0,2.83,-0.78),Vector3(width,0.28,2.17),LICHEN)
	var posts := {}
	for side: int in [-1,1]:
		var ends := []
		for z: float in [-1.63,0.19]:
			ends.append(frame.box(Vector3(side*2.32,1.51,z),Vector3(0.34,2.67,0.34),STONE,[slab]))
		posts[side] = ends
	if frame.bearing_enabled:
		var center_posts := []
		for i in 2:
			center_posts.append(frame.box(Vector3(0,1.51,-1.63+i*1.82),Vector3(0.24,2.67,0.24),STONE,[slab],Basis.IDENTITY,"middle_post/"+str(i)))
		var girder := frame.box(Vector3(0,2.64,-0.73),Vector3(0.30,0.22,2.23),IRON,center_posts,Basis.IDENTITY,"girder")
		frame.joint(roof,[girder]+posts[-1])
		frame.box(Vector3(1.275,2.83,-0.78),Vector3(width,0.28,2.17),LICHEN,[girder]+posts[1],Basis.IDENTITY,"roof/east")
	for x in [-1.13,1.13]:
		var b:=WastelandScenery.new(738)
		var mouth := Vector3(x,1.25,1.42)
		b.tube(PackedVector3Array([mouth + Vector3.FORWARD * 1.68,mouth - Vector3.BACK * 0.24,mouth]),PackedFloat32Array([0.72,0.80,0.89]),14,IRON)
		b.tube(PackedVector3Array([mouth,mouth + Vector3.BACK * 0.11]),PackedFloat32Array([0.79,0.74]),14, Color("#283e43"))
		var intake := frame.prefix+"intake/"+str(int(signf(x)))
		frame.joint(intake,[slab])
		for bar in range(-3,4):
			var dx := bar * 0.19
			var half := sqrt(0.53 - dx * dx)
			frame.box(mouth+Vector3(dx,0,0.14),Vector3(0.075,2.0*half,0.10),RUST.lightened(0.17),[intake])
		var bend := Vector3(x,1.24,-0.71)
		b.tube(PackedVector3Array([bend,bend+Vector3.UP * 0.68,bend+Vector3(0,1.0,-0.31),bend+Vector3(0,1.0,-1.65)]), PackedFloat32Array([0.34,0.34,0.36,0.33]),9,RUST)
		var fittings:=WastelandScenery.new(15)
		var flange:=mouth-Vector3.BACK*0.13
		# An open flange follows the pipe rim. Its fasteners remain outside the grille.
		for i in 14:
			var a:=TAU*i/14.0
			var next:=TAU*(i+1)/14.0
			var ray:=Vector3(cos(a),sin(a),0)
			var beside:=Vector3(cos(next),sin(next),0)
			var lip:=Vector3.BACK*0.25
			_quad(fittings,flange+ray*0.83+lip,flange+beside*0.83+lip,flange+beside*0.98+lip,flange+ray*0.98+lip,RUST.darkened(0.08))
			_quad(fittings,flange+ray*0.98,flange+ray*0.98+lip,flange+beside*0.98+lip,flange+beside*0.98,IRON)
			if i%2==0:
				var stud:=flange+lip+ray*0.91
				fittings.tube(PackedVector3Array([stud,stud+Vector3.BACK*0.054]),PackedFloat32Array([0.062,0.052]),6,LICHEN)
		_section(chunk,ruin,b.commit(),intake,160,fittings)
	var ladder := frame.prefix+"ladder/rail"
	if frame.bearing_enabled:
		frame.box(Vector3(2.54,1.64,-0.16),Vector3(0.09,2.72,0.12),IRON,[posts[1][1]],Basis.IDENTITY,"ladder/rail")
	for i in 7:
		frame.box(Vector3(2.55,0.57+i*0.36,-0.13),Vector3(0.44,0.06,0.60),IRON,[ladder])
	var b:=WastelandScenery.new(738)
	var tank := Vector3(-1.88,0.36,-1.58)
	b.tube(PackedVector3Array([tank,tank+Vector3.UP*0.18,tank+Vector3.UP*1.89,tank+Vector3.UP*2.03]),PackedFloat32Array([0.40,0.53,0.53,0.38]),12,Color("#667d76"))
	for h in [0.32,1.57]:
		b.tube(PackedVector3Array([tank+Vector3.UP*h,tank+Vector3.UP*(h+0.08)]),PackedFloat32Array([0.55,0.55]),12,RUST)
	var gauge:=WastelandScenery.new(16)
	var dial:=tank+Vector3(0,1.22,0.53)
	gauge.tube(PackedVector3Array([dial-Vector3.BACK*0.12,dial+Vector3.BACK*0.10]),PackedFloat32Array([0.27,0.30]),12,IRON)
	dial+=Vector3.BACK*0.12
	gauge.tube(PackedVector3Array([dial-Vector3.BACK*0.028,dial]),PackedFloat32Array([0.25,0.25]),12,Color("#c3b392"))
	var dial_face:=dial+Vector3.BACK*0.012
	for tick in 9:
		var angle:=PI*(0.16+tick*0.2125)
		var ray:=Vector3(-sin(angle),-cos(angle),0)
		var across:=Vector3(-ray.y,ray.x,0)*0.015
		var tip:=dial_face+ray*0.22
		_quad(gauge,tip+across,tip-across,tip-across-ray*0.051,tip+across-ray*0.051,IRON)
	gauge.triangle(dial_face+Vector3.LEFT*0.035,dial_face+Vector3(0.13,0.13,0.012),dial_face+Vector3.RIGHT*0.036,Vector3.BACK,RUST)
	_section(chunk,ruin,b.commit(),"wreck/pump/tank",170,gauge)
	frame.joint(frame.prefix+"tank",[slab])
	var hub := Vector3(0,1.23,1.72)
	var rings := []
	var spokes := []
	var housing := frame.prefix+"valve_stand"
	if frame.bearing_enabled:
		frame.box(Vector3(0,0.80,1.04),Vector3(0.37,0.99,0.42),IRON,[slab],Basis.IDENTITY,"valve_stand")
	for i in 12:
		var theta := i * TAU / 12.0
		var radial := Vector3(cos(theta),sin(theta),0)
		var next := Vector3(cos(theta+TAU/12.0),sin(theta+TAU/12.0),0)
		rings.append(frame.beam(hub+radial*0.35,hub+next*0.35,0.065,0.066,RUST.lightened(0.21),[]))
		if i%3==0:
			spokes.append(frame.beam(hub,hub+radial*0.35,0.055,0.053,RUST,[]))
	var axle := frame.box(hub+Vector3.FORWARD*0.40,Vector3(0.13,0.13,0.89),IRON,[housing])
	for i in spokes.size():
		frame.joint(spokes[i],[axle])
		frame.joint(rings[i*3],[spokes[i]])
		frame.joint(rings[i*3+2],[spokes[(i+1)%spokes.size()]])
		frame.joint(rings[i*3+1],[rings[i*3],rings[i*3+2]])
	for side in [-1.0,1.0]:
		frame.beam(Vector3(side*2.35,0.4,-1.58),Vector3(side*2.35,2.61,0.15),0.10,0.11,RUST,posts[int(side)])
	frame.joint(frame.prefix+"marker",[frame.prefix+"intake/1"])

static func _bridge(chunk:WastelandChunk,ruin:Node3D,frame:WreckFrame) -> void:
	var crowns := {}
	for side: int in [-1,1]:
		var x := side*3.17
		var pier := frame.box(Vector3(x,0.32,0),Vector3(1.62,0.75,3.12),STONE.darkened(0.13))
		var contacts := []
		for dx: float in [-0.50,0.50]:
			for dz: float in [-1.12,1.12]: contacts.append(Vector3(x+dx,-0.02,dz))
		frame.grounded(pier,contacts,0.62,STONE.darkened(0.20))
		var previous := [pier,pier]
		for row in 3:
			for n in 2:
				var z := -0.61+n*1.22
				previous[n]=frame.box(Vector3(x,0.98+row*0.43,z),Vector3(1.02,0.41,1.17),STONE.lightened(0.08*((row+n)%3)),[previous[n]])
		crowns[side] = previous
	for i in 13:
		var b:=WastelandScenery.new(738+i)
		var a := PI * i / 13.0 + 0.008
		var end := PI * (i + 1) / 13.0 - 0.008
		var inner := 2.68
		var outer := 3.63
		var face: Array[Vector3] = []
		for v in [[a,inner],[a,outer],[end,outer],[end,inner]]:
			face.append(Vector3(cos(v[0])*v[1],1.97+sin(v[0])*v[1]*0.71,1.27))
		var depth := Vector3.FORWARD * (1.52 if i in [3,4] else 2.54)
		var stone := LICHEN.darkened(0.075*(i%4))
		_quad(b,face[0],face[1],face[2],face[3],stone)
		_quad(b,face[0]+depth,face[1]+depth,face[2]+depth,face[3]+depth,stone)
		for n in 4:
			var m := (n+1)%4
			_quad(b,face[n],face[m],face[m]+depth,face[n]+depth,stone.darkened(0.10))
		var stone_id := frame.prefix+"arch/"+str(i)
		var facing:=WastelandScenery.new(530+i)
		# A recessed joint surrounds each stone face. The projecting crown was dressed separately.
		var face_center:Vector3=(face[0]+face[1]+face[2]+face[3])*0.25
		for n in 4:
			var m:=(n+1)%4
			var projection:=Vector3.BACK*(0.15 if i==6 else 0.055)
			var inner_n:=face[n].lerp(face_center,0.20)+projection
			var inner_m:=face[m].lerp(face_center,0.20)+projection
			_quad(facing,face[n]+Vector3.BACK*0.004,face[m]+Vector3.BACK*0.004,inner_m,inner_n,stone.lightened(0.13) if n==2 else stone.darkened(0.13))
			facing.triangle(inner_n,inner_m,face_center+projection,Vector3.BACK,stone.lightened(0.19 if i==6 else 0.04))
		_section(chunk,ruin,b.commit(),stone_id,230,facing)
		if i==0 or i==12:
			frame.joint(stone_id,crowns[1 if i==0 else -1])
		elif i==6:
			frame.joint(stone_id,[frame.prefix+"arch/5",frame.prefix+"arch/7"])
		else:
			var previous := i-1 if i<6 else i+1
			var supports := [frame.prefix+"arch/"+str(previous)]
			if i>=2 and i<=10: supports.append(frame.prefix+"arch/"+("12" if i<6 else "0"))
			frame.joint(stone_id,supports)
	for side in [-1.0,1.0]:
		var at := Vector3(side*4.65,0.39,-0.45)
		var debris := frame.box(at,Vector3(1.49,0.84,2.14),STONE,[],Basis(Vector3.BACK,side*0.32))
		frame.grounded(debris,[at+Vector3(0,-0.4,-0.72),at+Vector3(0,-0.4,0.72)],0.65,STONE)
	for x in [-2.55,-1.65,-0.75,0.15,1.05]:
		var height := 1.97 + sqrt(maxf(0.0,3.63*3.63-x*x))*0.71
		var bay := clampi(floori(acos(x/3.63)*13.0/PI),0,12)
		frame.box(Vector3(x,height+0.14,-0.72),Vector3(0.86,0.28,0.57),LICHEN,[frame.prefix+"arch/"+str(bay)])
	var riser := ""
	for row in 3:
		riser=frame.box(Vector3(5.9,row*0.42+0.12,-1.72),Vector3(1.34-row*0.13,0.41,2.54),STONE,[] if row==0 else [riser])
		if row==0: frame.grounded(riser,[Vector3(5.9,-0.07,-2.57),Vector3(5.9,-0.07,-0.85)],0.70,STONE)
	frame.beam(Vector3(5.51,1.24,-2.3),Vector3(4.75,0.21,1.93),0.22,0.27,OAK.darkened(0.15),[riser],"wood")
	frame.joint(frame.prefix+"marker",[crowns[1][1]])

static func _marker(chunk:WastelandChunk,ruin: Node3D, anchor: Vector3, water_y: float, key: String) -> void:
	var b := WastelandScenery.new(92)
	var top := Vector3(anchor.x + 0.31,water_y + 0.13,anchor.z - 0.23)
	var paint := Color("#c48649") if key == "ferry" else Color("#79a9a4") if key == "pump" else Color("#bb775e")
	b.tube(PackedVector3Array([anchor,anchor.lerp(top,0.47)+Vector3(-0.19,0,0.12),top]),PackedFloat32Array([0.038,0.033,0.038]),5,TIMBER)
	b.tube(PackedVector3Array([top-Vector3.UP*0.24,top,top+Vector3.UP*0.24]),PackedFloat32Array([0.18,0.35,0.19]),8,paint)
	b.tube(PackedVector3Array([top+Vector3.UP*0.18,top+Vector3.UP*0.78]),PackedFloat32Array([0.043,0.034]),5,IRON)
	var pennant := top + Vector3.UP * 0.77
	for face in [Vector3.FORWARD,Vector3.BACK]:
		b.triangle(pennant,pennant+Vector3(0.49,-0.11,0.04),pennant-Vector3.UP*0.27,face,paint.lightened(0.26))
	_section(chunk,ruin,b.commit(),"wreck/"+key+"/marker",50)

static func _cache(chunk: WastelandChunk, key: String, point: Vector3, yaw:float) -> void:
	var global_point := point + chunk.position
	point.y = chunk.stream.ground_at(global_point) + 0.37
	var chest:=preload("res://game/world/regional_caches.gd").spawn(chunk,"submerged/"+key,key+"_salvage",point,{"submerged_site":key},key)
	chest.rotation.y=yaw

static func _bed(chunk: WastelandChunk, sites: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk.stream.generator.seed_at(chunk.cell, 781)
	var groups := {}
	for i in 56:
		var x := rng.randf_range(0.35,31.65)
		var z := rng.randf_range(0.35,31.65)
		var world := Vector2(chunk.position.x+x, chunk.position.z+z)
		var y: float = chunk.stream.ground_at(Vector3(world.x,0,world.y))
		if y > -0.60 or not chunk.stream.generator.water_basin(world.x, world.y):
			continue
		var open := true
		for origin: Vector3 in sites.values():
			var clearance_sq:=49.0 if chunk.stream.generator.site_revision>0 else 23.0
			if world.distance_squared_to(Vector2(origin.x,origin.z)) < clearance_sq:
				open = false
		if not open:
			continue
		var band := sin(world.x*0.13+world.y*0.06)+cos(world.y*0.22)
		var kind := "grass" if band > -0.48 else "ledge"
		if i % 12 == 0 and y < -2.2:
			kind = "snag"
		elif i % 4 == 0:
			kind = "silt"
		if sites.has("pump") and world.distance_squared_to(Vector2(sites.pump.x,sites.pump.z)) < 210.0 and i%4==0:
			kind = "snag"
		elif sites.has("bridge") and world.distance_squared_to(Vector2(sites.bridge.x,sites.bridge.z)) < 256.0 and i%2==0:
			kind = "ledge"
		elif sites.has("ferry") and world.distance_squared_to(Vector2(sites.ferry.x,sites.ferry.z)) < 180.0 and i%3==0:
			kind = "silt"
		if not groups.has(kind):
			var list: Array[Transform3D] = []
			groups[kind] = list
		var s := rng.randf_range(0.67,1.42)
		if kind == "grass":
			s = minf(s, absf(y)*0.55)
		var basis := Basis(Vector3.UP,rng.randf() * TAU).scaled(Vector3.ONE * s)
		var key := "bed/%d" % i
		if chunk.stream.chunk_diff(chunk.cell).get("removed",{}).has(key): continue
		var pose := Transform3D(basis,Vector3(x,y-0.06,z))
		if not chunk.stream.is_preview:
			var id: String = {"grass":"pondweed","ledge":"bedrock","snag":"driftwood","silt":"silt"}[kind]
			chunk.index_nature(key,id,"bed/"+kind,groups[kind].size(),pose,_bed_mesh(kind))
		groups[kind].append(pose)
	for kind in groups:
		if groups[kind].is_empty(): continue
		var patch := WastelandLook.instanced(chunk.decoration_root,_bed_mesh(kind),groups[kind])
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.visibility_range_end = 53.0
		chunk.instances["bed/"+kind] = [patch]

static func _bed_mesh(kind: String) -> ArrayMesh:
	if beds.has(kind):
		return beds[kind]
	var b := WastelandScenery.new(387)
	match kind:
		"grass":
			for i in 23:
				var angle := i*2.40
				var radius := 0.21+i*0.059
				var foot := Vector3(cos(angle)*radius,0,sin(angle)*radius)
				b.foliage_blade(foot,angle+0.3,0.41+0.75*absf(sin(i*3.82)),0.13+0.12*absf(cos(i)),0.22+0.33*absf(sin(i)),Color("#638865").lightened((i%4)*0.07))
		"ledge":
			for i in 5:
				var at := Vector3((i-2)*0.55,0.17 + 0.04*i,0.18*sin(i))
				b.lobe(at,Vector3(0.70,0.33+0.1*(i%3),0.61),STONE.darkened(0.08*(i%3)),i,false,0.20)
		"snag":
			var tip := Vector3(0.55,2.45,0.28)
			b.tube(PackedVector3Array([Vector3.DOWN*0.2,Vector3(0.06,0.82,0),Vector3(0.37,1.71,0.15),tip]),PackedFloat32Array([0.22,0.14,0.086,0.012]),6,OAK.darkened(0.20))
			for i in 5:
				var a := i*2.4
				var root := tip*(0.19+i*0.11)
				var d := Vector3(cos(a),0,sin(a))
				b.tube(PackedVector3Array([root,root+d*0.49+Vector3.UP*0.19,root+d*0.77+Vector3.UP*0.70]),PackedFloat32Array([0.09,0.04,0.009]),5,OAK)
		"silt":
			for i in 5:
				var at := Vector3((i-2)*0.32,0.049,0.12*cos(i))
				b.lobe(at,Vector3(0.17,0.095,0.72),Color("#ab9b75").darkened((i%2)*0.08),0.12,false)
	beds[kind] = b.commit()
	return beds[kind]
