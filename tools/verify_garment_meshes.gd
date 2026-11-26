extends SceneTree

# Without --headless this also measures actual visible triangles on a 600×340
# viewport. Baselines are captures of the original garments on the same fixture.
const LOADOUTS := [
	{"name":"base", "gear":{}, "baseline":3568},
	{"name":"oilskin/quilt", "gear":{"body":"oilskin_vest", "legs":"quilted_pants"}, "baseline":5248},
	{"name":"coat/canvas", "gear":{"body":"coat", "legs":"canvas_pants"}, "baseline":2680},
	{"name":"armor", "gear":{"body":"armor"}, "baseline":0},
]
var passes := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passes += 1
	else:
		failures += 1
		printerr("FAIL ", label)

func skin_valid(piece: MeshInstance3D) -> bool:
	if not is_instance_valid(piece) or piece.skin == null: return false
	var rig := piece.get_node_or_null(piece.skeleton) as Skeleton3D
	if rig == null or rig.get_bone_count() != 3: return false
	var arrays := piece.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones.size() != arrays[Mesh.ARRAY_VERTEX].size()*4 or bones.size() != weights.size(): return false
	for i in range(0, bones.size(), 4):
		var sum_weights := 0.0
		for j in 4:
			if weights[i+j] > 0 and (bones[i+j]<0 or bones[i+j]>=rig.get_bone_count()): return false
			sum_weights += weights[i+j]
		if absf(sum_weights-1.0)>0.0001: return false
	return true

func lods_valid(mesh: ArrayMesh) -> bool:
	if mesh == null or mesh.get_surface_count() != 1: return false
	var data := RenderingServer.mesh_get_surface(mesh.get_rid(),0)
	var previous: int = data.index_count
	if previous <= 0 or data.get("lods",[]).is_empty(): return false
	var stride: int = data.index_data.size()/previous
	if stride not in [2,4]: return false
	for lod: Dictionary in data.lods:
		var packed: PackedByteArray = lod.index_data
		var count := packed.size()/stride
		if count<=0 or count%3!=0 or count>=previous: return false
		previous = count
		for pos in range(0, packed.size(), stride):
			var vertex := packed.decode_u16(pos) if stride==2 else packed.decode_u32(pos)
			if vertex >= int(data.vertex_count): return false
	return true

func drawn(view: SubViewport, camera: Camera3D, distance: float) -> int:
	camera.position = Vector3(0,1.0,distance)
	camera.look_at(Vector3.UP)
	for i in 3: await RenderingServer.frame_post_draw
	return view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)

func run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(600,340)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.current = true
	var visible_renderer := DisplayServer.get_name() != "headless"
	for id: String in WastelandPartyAvatar.OUTFITS:
		var actor := WastelandPartyAvatar.new()
		actor.show_tag = false
		actor.apply_outfit(id)
		view.add_child(actor)
		var shorts := actor.shorts_rig.get_node_or_null("BaseShorts") as MeshInstance3D
		check(skin_valid(shorts) and actor.shorts_rig.get_bone_parent(1)==-1 and actor.shorts_rig.get_bone_parent(2)==-1, id+" shorts bindings")
		for loadout: Dictionary in LOADOUTS:
			actor.wear_loadout(loadout.gear)
			var label := "%s %s" % [id,loadout.name]
			var clothes: Array = [shorts]
			if loadout.gear.is_empty(): clothes.append(actor.undershirt)
			clothes.append_array(actor.equipment.get_children())
			clothes.append_array(actor.sleeves)
			var close_triangles := 0
			for piece in clothes:
				if not is_instance_valid(piece) or not piece is MeshInstance3D:
					check(false,label+" missing garment")
					continue
				check(lods_valid(piece.mesh), label+" LOD indices "+str(piece.name))
				close_triangles += piece.mesh.surface_get_array_index_len(0)/3
			if loadout.gear.has("legs"):
				for rig in actor.leg_rigs:
					check(skin_valid(rig.get_node_or_null("TrouserLeg")),label+" knee weights")
			if loadout.gear.get("body")=="coat":
				for i in 2:
					check(actor.arms[i].has_node("CoatSleeve") and actor.elbows[i].has_node("CoatCuff"),label+" sleeve attachment")
			if loadout.baseline > 0: check(close_triangles < int(loadout.baseline),label+" full-detail triangle reduction")
			if visible_renderer:
				for piece in actor.find_children("*","MeshInstance3D",true,false):
					piece.visible = clothes.has(piece)
				var near := await drawn(view,camera,1.6)
				var middle := await drawn(view,camera,9.0)
				var far := await drawn(view,camera,28.0)
				check(near == close_triangles and far>0 and far<=middle and middle<near,label+" renderer selects coarser garment indices")
				print("%s  1.6m=%d  9m=%d  28m=%d" % [label,near,middle,far])
		actor.wear_loadout({})
		check(actor.undershirt.visible and actor.sleeves.is_empty() and not actor.leg_rigs[0].has_node("TrouserLeg"),id+" restored base outfit")
		view.remove_child(actor)
		actor.free()
	view.queue_free()
	await process_frame
	print("GARMENT MESH QA passed=%d failed=%d renderer_counts=%s" % [passes,failures,visible_renderer])
	quit(1 if failures else 0)
