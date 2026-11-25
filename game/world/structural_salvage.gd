extends RefCounted

# Effective component volumes (m³) per inventory bundle. Large sections break
# into mostly unrecoverable debris; the player can carry only a few sound pieces.
const BUNDLE_VOLUME:={"wood":0.075,"stone":0.21,"scrap":0.070,"cloth":0.034,"fiber":0.012,"wire":0.009,"parts":0.050,"brick":0.018}
const MAX_UNITS:=6

static func material_hand_damage(material: String) -> int:
	match material:
		"cloth", "fiber": return 0
		"brick", "stone", "cobble", "concrete": return 3
		"iron", "steel", "metal", "scrap", "wire", "parts": return 4
		_: return 2

static func hand_impact_damage(body: StaticBody3D, site: String) -> int:
	var components: Dictionary = body.get_meta("salvage_components", {})
	if not components.is_empty():
		var volumes: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
		for material: String in components:
			volumes[material_hand_damage(material)] += maxf(0.0, float(components[material]))
		# Choose the main rigid material in a shared collider, such as a wooden frame with padding and screws.
		var largest_volume := 0.0
		var damage := 0
		for grade in range(2, volumes.size()):
			if volumes[grade] > largest_volume:
				largest_volume = volumes[grade]
				damage = grade
		if largest_volume > 0.0 or volumes[0] > 0.0: return damage
	var material := str(body.get_meta("salvage_material", ""))
	if material.is_empty():
		material = _material(site, str(body.get_meta("site_id", "")))
	return material_hand_damage(material)

static func origin(chunk:WastelandChunk,id:String)->Vector3:
	for body:StaticBody3D in chunk.structures.get(id,[]):
		if is_instance_valid(body) and not body.is_queued_for_deletion(): return body.global_position
	return Vector3.INF

# Read each still-attached body once before the caller removes the structural
# key. Applying health from a save or a peer must never call the award path.
static func materials(chunk:WastelandChunk,id:String)->Dictionary:
	var amounts:={}
	var seen:={}
	for body:StaticBody3D in chunk.structures.get(id,[]):
		if not is_instance_valid(body) or body.is_queued_for_deletion() or seen.has(body): continue
		seen[body]=true
		if body.has_meta("salvage_components"):
			var components:Dictionary=body.get_meta("salvage_components")
			for item:String in components:
				amounts[item]=float(amounts.get(item,0.0))+float(components[item])
			continue
		var item:=str(body.get_meta("salvage_material",""))
		if item.is_empty(): item=_material(chunk.site,id)
		if item.is_empty(): continue
		amounts[item]=float(amounts.get(item,0.0))+_volume(body,id)
	var result:={}
	# Give each substantial constituent its first piece, then fill the remaining
	# allowance in proportion to recoverable volume.
	var weights:={}
	var count:=0
	for item:String in amounts:
		if not BUNDLE_VOLUME.has(item) or float(amounts[item])<0.0005: continue
		weights[item]=clampf(sqrt(float(amounts[item])/float(BUNDLE_VOLUME[item])),1.0,MAX_UNITS)
	while count<MAX_UNITS:
		var next:=""
		var remainder:=0.5
		for item:String in weights:
			var extra:=float(weights[item])-int(result.get(item,0))
			if not result.has(item): extra+=MAX_UNITS
			if extra>remainder:
				next=item
				remainder=extra
		if next.is_empty(): break
		result[next]=int(result.get(next,0))+1
		count+=1
	return result

static func _volume(body:StaticBody3D,id:String)->float:
	if body.has_meta("salvage_volume"): return float(body.get_meta("salvage_volume"))
	var total:=0.0
	for child in body.get_children():
		if not child is MeshInstance3D or child.mesh==null: continue
		if child.has_meta("structural_volume"):
			total+=float(child.get_meta("structural_volume"))
			continue
		var mesh:Mesh=child.get_meta("structural_mesh",child.mesh)
		var envelope:=mesh.get_aabb().get_volume()
		var scale_factor:=absf(child.global_basis.determinant())
		if mesh is BoxMesh:
			total+=envelope*scale_factor
			continue
		# Wreck hulls and torn sails are drawn as two-sided surfaces. Measure
		# their area and board/cloth thickness instead of enclosing empty water.
		if id.contains("/hull/") or id.ends_with("/rigging") or id.ends_with("/marker") or id.contains("/intake/") or id.ends_with("/tank"):
			var vertices:=mesh.get_faces()
			var area:=0.0
			for i in range(0,vertices.size(),3):
				area+=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()*0.5
			var thickness:=0.032 if id.contains("/hull/") else 0.004 if id.ends_with("/rigging") else 0.018
			total+=area*thickness*0.5*scale_factor
		else:
			total+=envelope*scale_factor*(0.5 if id.begins_with("gable/") else 0.72)
	return total

static func _material(site:String,id:String)->String:
	var family:=id.get_slice("/",0)
	var part:=id.get_slice("/",2)
	var timber:=site in ["lodge","cabin"]
	match family:
		"wreck":
			if part=="marker": return "fiber"
			match id.get_slice("/",1):
				"ferry": return "cloth" if part=="rigging" else "wood"
				"bridge": return "stone"
				"pump": return "scrap"
		"expedition":
			if part=="plate": return "scrap"
			if part=="post": return "wood"
			match id.get_slice("/",1):
				"shelter": return "wood"
				"weather": return "scrap"
				"canal": return "wood" if part=="gate" else "stone"
				"well": return "stone" if part.begins_with("rim") else "scrap"
				"trail": return "stone" if part.begins_with("desert") else "wood"
				"channel": return "stone"
		"wall","slab","ruin": return "wood" if timber else "stone"
		"door": return "wood" if timber else "scrap"
		"gable","eave","ridge","porch","dock": return "wood"
		"girder","lintel","column","canopy","dispatch","pump","sign": return "scrap"
		"note": return "wood"
		"chimney": return "brick"
		"roof":
			match id.get_slice("/",1):
				"rafter": return "wood"
				"plate": return "stone"
				_: return "scrap"
		"landmark":
			if id.ends_with("/logpile") or site=="cabin": return "wood"
			if site=="lodge" and id.contains("/wall/"): return "fiber"
			return "scrap"
		"fixture": return "scrap"
	return ""
