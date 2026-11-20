class_name WastelandCatalog
extends RefCounted

const DATA_PATH := "res://data/"
const TIER_NAMES := ["木框架", "实心木块", "圆石块", "钢筋混凝土", "锻钢装甲"]
const SHAPE_NAMES := ["立方体", "斜坡", "半墙", "栅栏", "活板门"]
const BIOMES := ["暮色湖区", "黑杉林", "灰脊高地", "盐烬焦土", "旧镇"]
const WEATHER := ["晴朗", "湖面晨雾", "秋雨", "雷暴"]
const STATIONS := {
	"hand": "随身制作", "campfire": "营火", "bench": "工作台",
	"forge": "熔炉", "chemistry": "化学实验台"
}

var items: Dictionary
var recipes: Dictionary
var loot: Dictionary
var skills: Dictionary
var enemies: Dictionary
var quests: Array
var delivery_pairs: Array
var sites: Dictionary
var achievements: Array

func _init() -> void:
	items = _read("items")
	recipes = _read("recipes")
	loot = _read("loot")
	skills = _read("skills")
	enemies = _read("enemies")
	var quest_data := _read("quests")
	quests = quest_data.get("jobs", [])
	delivery_pairs = quest_data.get("deliveries", [])
	sites = _read("sites")
	achievements = _read("achievements").entries

func _read(id: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH + id + ".json"))
	if data is Dictionary:
		return data
	push_error("无法读取数据表 " + id)
	return {}

func title(id: String) -> String:
	return items.get(id, {}).get("name", recipes.get(id,{}).get("name",id))

func is_material(id: String) -> bool:
	return items.get(id,{}).get("kind","") in ["material","supply"]

func color(id: String) -> Color:
	return Color.from_string(items.get(id, {}).get("color", ""), Color("#d5c3a6"))

func requirements(need: Dictionary) -> String:
	var words: PackedStringArray = []
	for id in need:
		words.append("%s ×%d" % [title(id), int(need[id])])
	return "、".join(words)

func roll_loot(table: String, seed_value: int, abundance: float, stage: int, draw_limit: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var definition: Dictionary = loot.get(table, loot.get("cabin", {}))
	var rows: Array = definition.get("items", [])
	if rows.is_empty():
		return {}
	var result: Dictionary = {}
	var draws := maxi(1, int(round(int(definition.get("draws", 2)) * abundance)))
	if draw_limit >= 0: draws = mini(draws,draw_limit)
	for draw in draws:
		var total := 0.0
		for row in rows:
			if stage >= int(row[4]):
				total += float(row[1])
		if total <= 0.0:
			break
		var ticket := rng.randf() * total
		for row in rows:
			if stage < int(row[4]):
				continue
			ticket -= float(row[1])
			if ticket <= 0.0:
				var id := str(row[0])
				result[id] = int(result.get(id, 0)) + rng.randi_range(int(row[2]), int(row[3]))
				break
	return result
