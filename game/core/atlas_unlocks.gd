extends RefCounted

# A marker per achievement makes two running games safe to update independently.
# Save slots still own their rewards and their in-world achievement progress.
static func remember(save_root: String, ids: Array) -> void:
	if ids.is_empty(): return
	var folder := save_root.path_join("atlas")
	for key in ids:
		if not key is String or not key.is_valid_ascii_identifier() or key.length()>64: continue
		var path := folder.path_join(key+".seen")
		if FileAccess.file_exists(path): continue
		if DirAccess.make_dir_recursive_absolute(folder)!=OK:
			push_warning("图鉴记录目录无法写入")
			return
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file==null:
			push_warning("无法写入图鉴记录 "+key)
			return
		file.close()

static func rows(catalog: WastelandCatalog) -> Array[Dictionary]:
	var root := WastelandSave.save_root()
	var folder := root.path_join("atlas")
	var known := {}
	if DirAccess.dir_exists_absolute(folder):
		for filename in DirAccess.get_files_at(folder):
			if filename.ends_with(".seen"): known[filename.get_basename()]=true
	# Import awarded entries from earlier releases, including a recovered backup.
	var imported: Array = []
	for slot in range(1,WastelandSave.MAX_SLOTS+1):
		var world := WastelandSave.read(slot)
		var awarded: Variant=world.get("progress",{}).get("achieved",{})
		if awarded is Dictionary:
			for key in awarded:
				if not known.has(key):
					known[key]=true
					imported.append(key)
	remember(root,imported)
	var result: Array[Dictionary] = []
	for entry: Dictionary in catalog.achievements:
		if known.has(entry.id):
			result.append({"unlocked":true,"category":entry.category,"id":entry.id,"name":entry.name,"desc":entry.desc,"reward":entry.reward})
		else:
			result.append({"unlocked":false,"category":entry.category,"id":"","name":"未解锁"})
	return result
