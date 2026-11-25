extends RefCounted

# Coordinates are shared across adjoining pieces. The same UVs travel with a falling slab.
const FINISHES := {
	"lodge":[0,"886e54","a89270"], "cabin":[0,"81674f","9d7c57"],
	"hospital":[1,"a9a497","739083"], "police":[1,"989b97","637989"],
	"post":[1,"ac9b83","8c7563"], "fuel":[1,"9b8b75","a47763"],
	"garage":[2,"827e76","c79b54"], "bunker":[2,"7d847e","b8ac77"],
	"tower":[2,"85838a","8b9da1"], "granary":[2,"918575","bdab83"]
}
const ROOF := [3,"746e70","837e7c"]
static var meshes := {}
static var finishes := {}

static func apply(body: StaticBody3D, site: String, size: Vector3, center: Vector2, roof: bool, seed_value: int) -> void:
	var visual := body.get_child(0) as MeshInstance3D
	var key := Vector4i(roundi(size.x*100),roundi(size.z*100),roundi(center.x*100),roundi(center.y*100))
	if not meshes.has(key):
		var arrays := visual.mesh.surface_get_arrays(0)
		var uv := PackedVector2Array()
		var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		uv.resize(points.size())
		for i in points.size():
			uv[i]=center+Vector2(points[i].x*size.x,points[i].z*size.z)
		arrays[Mesh.ARRAY_TEX_UV2]=uv
		var deck := ArrayMesh.new()
		deck.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		meshes[key]=deck
	var style: Array = ROOF if roof else FINISHES[site]
	var variation:=posmod(seed_value,8)
	var finish_key:=( "roof" if roof else site )+str(variation)
	if not finishes.has(finish_key):
		var mat:=ShaderMaterial.new()
		mat.shader=preload("res://shaders/site_floor.gdshader")
		mat.set_shader_parameter("finish",style[0])
		mat.set_shader_parameter("tone",Color(style[1]))
		mat.set_shader_parameter("accent",Color(style[2]))
		mat.set_shader_parameter("weathering",float(variation))
		mat.set_shader_parameter("patina",preload("res://game/art/weather_noise.tres"))
		finishes[finish_key]=mat
	visual.mesh=meshes[key]
	visual.material_override=finishes[finish_key]
	visual.set_meta("structural_volume",size.x*size.y*size.z)
