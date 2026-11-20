class_name WastelandSave
extends RefCounted

const ROOT := "user://worlds"
const MAGIC := 0x574C5331
const SCHEMA := 1
const MAX_SLOTS := 8
const MAX_BYTES := 64 * 1024 * 1024
static var root_override := ""

static func save_root() -> String:
	return ROOT if root_override.is_empty() else root_override

static func default_world() -> Dictionary:
	return {
		"name": "七日荒原", "seed_label": "荒原·第七日", "seed": 17236227, "start_id":"random",
		"terrain_revision": WastelandTerrainGen.CURRENT_REVISION,
		"site_revision": 1,
		"minutes": 32.0, "horde_days": 7, "loot": 1.0, "loot_days": 4,
		"zombie_speed": 1.0, "difficulty": 1.0,
	}

static func seed_number(value: String) -> int:
	var clean := value.strip_edges()
	if clean.is_valid_int():
		return clean.to_int() % 2147483629
	return int(clean.sha256_text().substr(0, 7).hex_to_int())

static func path_for(slot: int) -> String:
	return "%s/world_%02d.wls" % [save_root(), slot]

static func read(slot: int) -> Dictionary:
	if slot < 1 or slot > MAX_SLOTS:
		return {}
	var path := path_for(slot)
	var primary := _read_file(path)
	return primary if not primary.is_empty() else _read_file(path + ".bak")

static func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(1, MAX_SLOTS + 1):
		var data := read(slot)
		if not data.is_empty():
			result.append({
				"slot": slot, "name": data.settings.name, "seed": data.settings.seed_label,
				"time": data.get("time", 17.0), "saved_at": data.get("saved_at", 0),
			})
	result.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return result

static func next_slot() -> int:
	for slot in range(1, MAX_SLOTS + 1):
		var path := path_for(slot)
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
			return slot
	return 0

static func write(slot: int, snapshot: Dictionary) -> Error:
	if slot < 1 or slot > MAX_SLOTS:
		return ERR_INVALID_PARAMETER
	var error := DirAccess.make_dir_recursive_absolute(save_root())
	if error != OK and error != ERR_ALREADY_EXISTS:
		return error
	var path := path_for(slot)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	snapshot.schema = SCHEMA
	snapshot.saved_at = int(Time.get_unix_time_from_system())
	var bytes := var_to_bytes(snapshot)
	if bytes.size() > MAX_BYTES:
		file.close()
		DirAccess.remove_absolute(temporary)
		return ERR_OUT_OF_MEMORY
	var compression := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	file.store_32(MAGIC)
	file.store_32(bytes.size())
	file.store_buffer(hash.finish())
	file.store_buffer(compression)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK or _read_file(temporary).is_empty():
		DirAccess.remove_absolute(temporary)
		return ERR_FILE_CANT_WRITE
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if _read_file(path).is_empty():
			error = DirAccess.remove_absolute(path)
		else:
			error = DirAccess.rename_absolute(path, backup)
		if error != OK:
			return error
	error = DirAccess.rename_absolute(temporary, path)
	return error

static func delete_slot(slot: int) -> Error:
	if slot < 1 or slot > MAX_SLOTS:
		return ERR_INVALID_PARAMETER
	var path := path_for(slot)
	var awards: Dictionary = read(slot).get("progress",{}).get("achieved",{})
	preload("res://game/core/atlas_unlocks.gd").remember(save_root(),awards.keys())
	for suffix in [".tmp", ".bak", ""]:
		if FileAccess.file_exists(path + suffix):
			var error := DirAccess.remove_absolute(path + suffix)
			if error != OK:
				return error
	return OK

static func _read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 42 or file.get_length() > MAX_BYTES + 1024:
		return {}
	if file.get_32() != MAGIC:
		return {}
	var size := file.get_32()
	if size <= 0 or size > MAX_BYTES:
		return {}
	var expected := file.get_buffer(32)
	var compressed := file.get_buffer(file.get_length() - file.get_position())
	var bytes := compressed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != size:
		return {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish() != expected:
		return {}
	var result = bytes_to_var(bytes)
	if not result is Dictionary or result.get("schema") != SCHEMA or not result.get("settings") is Dictionary:
		return {}
	var settings := default_world()
	# A saved camp, excavation or vehicle relies on the heightfield it was placed on.
	settings.terrain_revision = 1
	settings.site_revision = 0
	settings.start_id = "seeded"
	settings.merge(result.settings, true)
	result.settings = settings
	return result
