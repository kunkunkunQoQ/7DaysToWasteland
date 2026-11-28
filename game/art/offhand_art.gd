class_name WastelandOffhandArt
extends RefCounted

static var definitions:Dictionary={}

static func item(id:String)->Dictionary:
	if definitions.is_empty():
		definitions=JSON.parse_string(FileAccess.get_file_as_string(WastelandCatalog.DATA_PATH+"items.json"))
	return definitions.get(id,{})

static func prop(id:String,first_person:bool,material:Material=null)->MeshInstance3D:
	var definition:=item(id)
	if definition.is_empty(): return null
	var mesh_node:=MeshInstance3D.new()
	mesh_node.name="OffhandItem"
	mesh_node.mesh=WastelandItemArt.mesh(id,definition)
	mesh_node.material_override=material if material!=null else WastelandLook.colored_material()
	var extent:=mesh_node.mesh.get_aabb().size
	var size:=minf(0.85,0.60/maxf(0.05,extent[extent.max_axis_index()])) if first_person else 0.90
	if definition.get("shield",false): size=1.0
	mesh_node.scale=Vector3.ONE*size
	if id=="torch":
		mesh_node.position.y=-0.269*size
		var glass:=BoxMesh.new()
		glass.size=Vector3(0.179,0.191,0.170)
		var glow:=MeshInstance3D.new()
		glow.name="LitGlass"
		glow.mesh=glass
		glow.position.y=0.03
		var amber:=StandardMaterial3D.new()
		amber.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		amber.albedo_color=Color("#ffe1a2")
		glow.material_override=amber
		mesh_node.add_child(glow)
	if first_person: mesh_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_node

static func sync_world_light(parent:Node3D,id:String,lit:bool,at_eyes:=false)->void:
	var light:=parent.get_node_or_null("OffhandLanternLight") as OmniLight3D
	var on:=id=="torch" and lit
	if light==null:
		if not on: return
		light=OmniLight3D.new()
		light.name="OffhandLanternLight"
		light.light_color=Color("#ffc687")
		light.light_energy=1.65
		light.omni_range=9
		light.omni_attenuation=1.25
		light.shadow_enabled=false
		parent.add_child(light)
		light.position=Vector3(-0.28,-0.20,-0.4) if at_eyes or parent is Camera3D else Vector3.DOWN*0.16
	light.visible=on
