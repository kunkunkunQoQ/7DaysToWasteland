class_name WastelandHoofprints
extends MultiMeshInstance3D

const LIMIT := 80
const LIFETIME := 46.0
var ages := PackedFloat32Array()
var records: Array[Dictionary] = []
var alternate_meshes := {}
var serial := 0
var cursor := 0
var refresh_time := 0.0

func _ready() -> void:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		# Two tapered toes meet toward the animal's direction of travel (local -Z).
		var toe := PackedVector3Array([Vector3(side*0.012,0,-0.091),Vector3(side*0.043,0,-0.049),
			Vector3(side*0.061,0,0.012),Vector3(side*0.055,0,0.058),Vector3(side*0.032,0,0.073),
			Vector3(side*0.012,0,0.056),Vector3(side*0.008,0,-0.016)])
		for i in range(1,toe.size()-1):
			for point in [toe[0],toe[i],toe[i+1]]:
				builder.add_vertex(point)
	ages.resize(LIMIT)
	ages.fill(LIFETIME)
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo=true
	mat.albedo_color=Color("#514135")
	material_override=mat
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.use_colors=true
	multimesh.mesh=builder.commit()
	multimesh.instance_count=LIMIT
	multimesh.visible_instance_count=0
	for type:String in ["paw","hop","scrape"]:
		var form:=SurfaceTool.new()
		form.begin(Mesh.PRIMITIVE_TRIANGLES)
		if type=="paw":
			_disc(form,Vector2(0,0.022),Vector2(0.047,0.041))
			for i in 4: _disc(form,Vector2((i-1.5)*0.029,-0.029-0.019*sin(i*PI/3)),Vector2(0.013,0.022))
		elif type=="hop":
			for side in [-1,1]:
				_disc(form,Vector2(side*0.049,-0.037),Vector2(0.018,0.059))
				_disc(form,Vector2(side*0.024,0.061),Vector2(0.012,0.018))
		else:
			for i in 4: _disc(form,Vector2(i*0.038-0.059,sin(i)*0.034),Vector2(0.014,0.093-i*0.009))
		var layer:=MultiMeshInstance3D.new()
		layer.multimesh=MultiMesh.new()
		layer.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		layer.multimesh.use_colors=true
		layer.multimesh.mesh=form.commit()
		layer.multimesh.instance_count=LIMIT
		layer.multimesh.visible_instance_count=0
		layer.material_override=mat
		layer.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(layer)
		alternate_meshes[type]=layer.multimesh
	records.resize(LIMIT)
	set_process(false)

func _disc(builder:SurfaceTool,center:Vector2,radius:Vector2)->void:
	for i in 8:
		for at:Vector2 in [center,center+Vector2.from_angle(i*TAU/8)*radius,center+Vector2.from_angle((i+1)*TAU/8)*radius]:
			builder.add_vertex(Vector3(at.x,0,at.y))

func stamp(hit_point:Vector3,normal:Vector3,forward:Vector3,boar:bool,actor:Node3D=null)->void:
	var tangent:=forward.slide(normal).normalized()
	if tangent.length_squared()<0.5: return
	serial+=1
	var id:String=actor.type if actor else "boar" if boar else "stag"
	var state:="受惊疾行" if actor and actor.brain.mode==WastelandCreatureBrain.Mode.FLEE else "缓行觅食"
	var pattern:="hoof" if id in ["stag","boar","argali"] else "hop" if id in ["jerboa","hare"] else "paw"
	if actor and actor.brain.forage_left>0: pattern="scrape"; state="停步觅食"
	_write({"key":str(serial),"species":id,"name":actor.display_name() if actor else "野兽","pattern":pattern,
		"activity":state,"at":hit_point,"normal":normal,"direction":tangent,"age":0.0})

func _write(row:Dictionary)->void:
	var size:=Vector3(1.23,1,0.95) if row.species in ["boar","argali"] else Vector3(0.83,1,1.12)
	var basis:=Basis.looking_at(row.direction,row.normal).scaled_local(size)
	var xform:=global_transform.affine_inverse()*Transform3D(basis,row.at+row.normal*0.014)
	if not records[cursor].is_empty():
		var old:MultiMesh=alternate_meshes.get(records[cursor].pattern,multimesh)
		old.set_instance_color(cursor,Color(1,1,1,0))
	var layer:MultiMesh=alternate_meshes.get(row.pattern,multimesh)
	layer.set_instance_transform(cursor,xform)
	layer.set_instance_color(cursor,Color(1,1,1,0.76))
	layer.visible_instance_count=maxi(layer.visible_instance_count,cursor+1)
	records[cursor]=row
	ages[cursor]=row.age
	cursor=(cursor+1)%LIMIT
	set_process(true)

func clue(at:Vector3)->Dictionary:
	var closest:=1.30*1.30
	var best:Dictionary={}
	for i in LIMIT:
		if records[i].is_empty() or ages[i]>=LIFETIME: continue
		var row:=records[i]
		var dist:=at.distance_squared_to(row.at)
		if dist>=closest: continue
		closest=dist
		best=row.duplicate()
		var forward:Vector3=row.direction
		var direction:String=["北","东北","东","东南","南","西南","西","西北"][posmod(roundi(atan2(forward.x,-forward.z)*4/PI),8)]
		best.label="%s · %s · 向%s · %s"%[row.name,row.activity,direction,"刚留下" if ages[i]<14 else "正在变淡"]
	return best

func nearby(at:Vector3)->Array:
	var found:=[]
	for offset in LIMIT:
		var i:=posmod(cursor-1-offset,LIMIT)
		if records[i].is_empty() or ages[i]>=LIFETIME or at.distance_squared_to(records[i].at)>43*43: continue
		var row:=records[i].duplicate()
		row.age=ages[i]
		found.append(row)
		if found.size()==24: break
	found.reverse()
	return found

func mirror(rows:Array)->void:
	var existing:={}
	for record in records:
		if not record.is_empty(): existing[record.key]=true
	for row:Dictionary in rows:
		if not existing.has(row.key): _write(row)

func _process(delta: float) -> void:
	refresh_time+=delta
	if refresh_time<0.33:
		return
	var living:=false
	for i in LIMIT:
		if ages[i]>=LIFETIME:
			continue
		ages[i]=minf(LIFETIME,ages[i]+refresh_time)
		var alpha:=0.65*(1.0-smoothstep(LIFETIME*0.68,LIFETIME,ages[i]))
		var layer:MultiMesh=alternate_meshes.get(records[i].pattern,multimesh)
		layer.set_instance_color(i,Color(1,1,1,alpha))
		living=living or ages[i]<LIFETIME
	refresh_time=0.0
	if not living:
		set_process(false)
