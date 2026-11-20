extends RefCounted

const Timber := preload("res://game/sim/timber.gd")
const Orders := preload("res://game/sim/outpost_orders.gd")
const Patrol := preload("res://game/sim/relay_patrol.gd")
const Expeditions := preload("res://game/sim/expeditions.gd")
const Nest := preload("res://game/world/nest_caves.gd")
const GATHER_AREAS := {
	"herb_patch":"近湖草地或黑杉林下", "reed_bed":"湖岸浅滩", "cactus":"流金沙海",
	"iron_vein":"灰脊高地、盐烬焦土或地堡附近", "machine_wreck":"公路沿线，尤其是旧镇、加油站和警署附近"
}
const CACHE_AREAS := {
	"shore_cache":"湖岸", "forest_cache":"林场", "ridge_cache":"山脊", "ash_cache":"焦土",
	"town_cache":"旧镇", "alpine_cache":"霜脊雪山", "desert_cache":"流金沙海",
	"ferry_salvage":"沉没渡船", "pump_salvage":"淹没泵站", "bridge_salvage":"断桥遗址"
}

var stable: Dictionary = {}
var random: Dictionary = {}

func _init(catalog: WastelandCatalog) -> void:
	for id: String in catalog.items:
		stable[id] = PackedStringArray()
		random[id] = PackedStringArray()
	_gathering(catalog)
	_interactions(catalog)
	_rewards(catalog)
	for recipe: Dictionary in catalog.recipes.values():
		var station: String = catalog.STATIONS[recipe.station]
		if recipe.station in ["forge","campfire"]: station += "（点火）"
		if not recipe.skill.is_empty():
			station += " · %s %d 级" % [catalog.skills[recipe.skill[0]].name,recipe.skill[1]]
		stable[recipe.id].append("%s · %s → %s ×%d" % [station,catalog.requirements(recipe.inputs),catalog.title(recipe.id),recipe.amount])
	_creatures(catalog)
	_caches(catalog)

func _gathering(catalog: WastelandCatalog) -> void:
	for kind: String in WastelandSession.RESOURCES:
		var resource: Array = WastelandSession.RESOURCES[kind]
		var location: String = GATHER_AREAS.get(kind,"")
		var action := "拾取" if kind in ["fallen_stick","pebble"] else "采收"
		var tool: String = WastelandSession.HARVEST_TOOLS.get(kind,"")
		for id: String in resource[2]:
			var words := "%s%s · 基础 ×%d" % [action,resource[0],resource[2][id]]
			if location != "": words += " · " + location
			if tool != "": words += "，用%s可提高产量" % catalog.title(tool)
			stable[id].append(words)
	for model: String in Timber.SAPLING_PERCENT:
		random["sapling_"+model].append("%s被风吹、受斧击或倒下时，每片可拾取落叶有 %d%% 机会伴生一株。" % [Timber.NAMES[model],Timber.SAPLING_PERCENT[model]])
		stable["sapling_"+model].append("已栽种的%s尚未成熟时，用工兵铲挖起可收回树苗 ×1。" % Timber.NAMES[model])
	for id: String in catalog.items:
		var item: Dictionary = catalog.items[id]
		if item.has("worn_form") and item.worn_form != "":
			stable[item.worn_form].append("副手装备%s，有效格挡一次。" % item.name)
		if item.has("crop"):
			stable[item.crop].append("用锄开垦，播下%s，35 个游戏小时后收获 3 份，每级荒野采集再加 1 份。" % item.name)
			stable[id].append("收获成熟的%s时返还 1 份种子。" % catalog.title(item.crop))

func _record_reward(items: Dictionary, activity: String) -> void:
	for id: String in items:
		stable[id].append("%s · ×%d" % [activity,items[id]])

func _interactions(catalog: WastelandCatalog) -> void:
	stable.tree_leaf.append("风吹、斧击或伐倒活树后，在树冠下拾取落叶。")
	stable.stick.append("树倒下后拾取折落的枝条。")
	stable.packed_snow.append("用工兵铲或铁镐挖雪山的新雪表层 · ×2")
	stable.stone.append("徒手敲风化岩块或露头矿石，每处可先取松石 ×3。")
	stable.sand.append("用工兵铲或铁镐挖沙层 ×3，普通泥土 ×2。")
	stable.clay.append("用工兵铲或铁镐挖普通泥土 · ×2")
	stable.dirty_water.append("在湖岸水边或驻地蓄水槽取生水 · ×1")
	stable.clean_water.append("手持手压净水泵在水边或蓄水槽取水。优先消耗 1 个复合滤芯产 4 份，否则消耗 1 份植物纤维产 1 份。修好的驼站井泵用 1 个滤芯可取 6 份。")
	stable.beacon_log.append("在回声医院、西岭观测塔或灰湾警务站的任务保险柜取出信标记录。")
	stable.dispatch_parcel.append("登记远行运单，当天到指定中继寄存柜签收。")
	stable.boat.append("在南岸码头修复遗留摩托艇后打包。")
	stable.parts.append("拆地标废车底盘，或公路机修车间的绞车。")
	_record_reward(WastelandSession.LANDING_CARGO.shore_float,"南岸近岸浮标，靠近后交互打捞")
	_record_reward(WastelandSession.LANDING_CARGO.survey_float,"南岸调查浮标，靠近后交互打捞")
	_record_reward(WastelandSession.TRADE_REWARD,"驻地公告板用%s兑换，每日一次" % catalog.requirements(WastelandSession.TRADE_COST))
	_record_reward(Expeditions.BRIDGE_REWARD,"完成灰湾潜调的断桥调查")
	_record_reward(Expeditions.WATCH_SUPPLIES.well,"修复驼站井泵后，血月开始时领取远征守夜补给")
	_record_reward(Expeditions.WATCH_SUPPLIES.bridge,"完成断桥调查后，血月开始时领取远征守夜补给")
	_record_reward(WastelandSession.VEHICLE_SALVAGE,"载具损毁后拾取")

func _rewards(catalog: WastelandCatalog) -> void:
	for job: Dictionary in catalog.quests:
		_record_reward(job.reward,"交付主线「%s」" % job.name)
		if job.has("repair"): _record_reward(job.repair.reward,"守夜失利后完成「%s」" % job.repair.name)
	_record_reward(Orders.LOCAL_REWARD,"驻地公告板完成当天的本地交付")
	for day in Orders.DISPATCH_REWARDS.size():
		_record_reward(Orders.DISPATCH_REWARDS[day],"四日轮换第 %d 天完成驻地远行运单" % (day+1))
	for count in [2,3]:
		for crate: String in Patrol.CRATES:
			var when := "通关后" if count==3 else "完成「储水计划」后"
			_record_reward(Patrol.crate_supplies(count,1,crate),"%s完成 %d 站巡线，回公告板选「%s」" % [when,count,Patrol.CRATES[crate]])
	_record_reward(Patrol.BONUS_SUPPLIES,"每完成第 %d 趟中继巡线，任一档额外获得" % Patrol.BONUS_INTERVAL)
	for row: Dictionary in catalog.achievements:
		if row.reward != "": stable[row.reward].append("成就「%s」 · %s" % [row.name,row.desc])

func _creatures(catalog: WastelandCatalog) -> void:
	for enemy: Dictionary in catalog.enemies.values():
		if enemy.has("salvage"): stable[enemy.salvage].append("击败%s · ×1–2" % enemy.name)
		var harvest: Dictionary = enemy.ecology.get("harvest",{})
		for id: String in harvest:
			var amounts: Array = harvest[id]
			var sources := stable if int(amounts[0])>0 else random
			sources[id].append("狩猎%s · ×%d–%d" % [enemy.name,amounts[0],amounts[1]])
	for id: String in WastelandHordes.COMMON_LOOT:
		random[id].append("普通感染者有 %d%%（尸潮波次 %d%%）机会从 %d 种补给中掉一种 · ×1–%d" % [
			roundi(WastelandHordes.ROAM_DROP_CHANCE*100),roundi(WastelandHordes.WAVE_DROP_CHANCE*100),
			WastelandHordes.COMMON_LOOT.size(),WastelandHordes.MAX_COMMON_YIELD])
	var trophy_pools := {}
	for species: String in WastelandHordes.TROPHIES:
		for id: String in WastelandHordes.TROPHIES[species]:
			if not trophy_pools.has(id): trophy_pools[id] = PackedStringArray()
			trophy_pools[id].append(catalog.enemies[species].name)
	trophy_pools[WastelandHordes.LOCAL_FOX_TROPHY] = PackedStringArray(["地方色赤狐"])
	for morph: String in WastelandHordes.MORPH_TROPHIES:
		var reward: String = WastelandHordes.MORPH_TROPHIES[morph]
		if not trophy_pools.has(reward): trophy_pools[reward] = PackedStringArray()
		trophy_pools[reward].append("有稀有池的%s感染者" % {"armored":"披甲","swift":"迅行"}[morph])
	for id: String in trophy_pools:
		random[id].append("%s。每只以 1/%d 的机会进入稀有池，再从该物种的奖品中抽一件。" % ["、".join(trophy_pools[id]),WastelandHordes.RARE_ODDS])

func _caches(catalog: WastelandCatalog) -> void:
	for table: String in catalog.loot:
		var places := PackedStringArray()
		if CACHE_AREAS.has(table): places.append(CACHE_AREAS[table])
		if table in Nest.CHEST_TABLES: places.append("感染者巢穴")
		for site: Dictionary in catalog.sites.values():
			if table in site.loots: places.append(site.name)
		var chest: Dictionary = catalog.loot[table]
		for row: Array in chest.items:
			var words := "%s · 每次抽中 ×%d–%d" % [chest.name,row[2],row[3]]
			if int(row[4])>0: words += " · 箱内物资阶段 ≥%d" % row[4]
			if not places.is_empty(): words += " · " + "、".join(places)
			random[row[0]].append(words)
