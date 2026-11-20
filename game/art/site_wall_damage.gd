extends RefCounted

static func update(chunk: WastelandChunk, body: StaticBody3D, hp: float) -> void:
	var fraction:=hp/float(body.get_meta("hp_max"))
	var stage:=0 if hp<=0.0 or fraction>0.73 else 1 if fraction>0.36 else 2
	if stage==int(body.get_meta("wall_wear",0)): return
	body.set_meta("wall_wear",stage)
	var id:String=body.get_meta("site_id")
	var overlay: ShaderMaterial
	if stage>0:
		overlay=chunk.wall_finishes.get(id)
		if not overlay:
			overlay=ShaderMaterial.new()
			overlay.shader=preload("res://shaders/site_wall_damage.gdshader")
			overlay.set_shader_parameter("timber",bool(body.get_meta("timber_wall")))
			var marks:Dictionary=chunk.stream.chunk_diff(chunk.cell).get("wall_marks",{})
			overlay.set_shader_parameter("impact",marks.get(id,body.global_position))
			chunk.wall_finishes[id]=overlay
		overlay.set_shader_parameter("severe",stage==2)
	else:
		chunk.wall_finishes.erase(id)
	for child in body.get_children():
		if child is MeshInstance3D: child.material_overlay=overlay
