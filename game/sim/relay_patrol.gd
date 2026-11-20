extends RefCounted

const Depots := preload("res://game/sim/outpost_orders.gd")
const TASKS := ["audit", "listen", "repair"]
const TITLES := {"audit":"物资盘点", "listen":"无线电守听", "repair":"线路抢修"}
const CRATES := {"workshop":"工坊物资", "watch":"守夜物资", "travel":"远行物资"}
const LISTEN_SECONDS := 18

static func completed(s: Node) -> int:
	return int(s.progress.records.get("relay_patrol", 0))

static func stop(s: Node) -> Dictionary:
	var run: Dictionary = s.progress.patrol
	if run.is_empty() or int(run.index) >= run.stops.size(): return {}
	return run.stops[run.index]

static func destination(s: Node) -> Dictionary:
	if s.progress.patrol.is_empty(): return {}
	var leg := stop(s)
	if leg.is_empty():
		var board: Dictionary = s.board_destination()
		return {"at":board.at, "name":"巡线结算 · "+str(board.name)}
	return {"at":Vector2(leg.cell * WastelandTerrainGen.SIZE) + Depots.DEPOT,
		"name":str(s.catalog.sites[leg.site].name)+" · "+str(TITLES[leg.task])}

static func instructions(leg: Dictionary) -> String:
	match str(leg.task):
		"audit": return "进入标记的建筑，打开任意一只补给箱抄录库存。旧箱也有台账。若箱子已毁，可用两份废铁在中继柜重建台账。"
		"listen": return "启动黄边中继柜，队伍中至少一人在柜旁十米内守听十八秒。离开范围后需要重新启动。"
	return "将两份废铁和一份植物纤维带到黄边中继柜，接好断线。"

static func start(s: Node, serial: int) -> void:
	if s.replica or not s.near_board(false) or not s.progress.patrol.is_empty(): return
	if s.progress.job < 2 or serial != completed(s) + 1: return
	var origin := WastelandTerrainGen.chunk_at(Vector2(s.player.position.x, s.player.position.z))
	var gen: WastelandTerrainGen = s.stream.generator
	var candidates: Array[Vector2i] = []
	for radius in range(1, 22):
		for z in range(-radius, radius+1):
			for x in range(-radius, radius+1):
				if maxi(absi(x), absi(z)) != radius: continue
				var cell := origin + Vector2i(x,z)
				if gen.site_for(cell) in Depots.RELAYS: candidates.append(cell)
		if candidates.size() >= 7: break
	# Regional outposts provide backups for sparsely populated terrain.
	if candidates.size() < 3:
		var known: Array = s._nearby_sites().keys()
		known.sort_custom(func(a: Vector2i, b: Vector2i): return origin.distance_squared_to(a) < origin.distance_squared_to(b))
		for cell: Vector2i in known:
			if cell != origin and cell not in candidates and gen.site_for(cell) in Depots.RELAYS:
				candidates.append(cell)
				if candidates.size() >= 3: break
	var length := 3 if s.progress.job >= s.catalog.quests.size() else 2
	if candidates.size() < length: return
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_at(origin, serial)
	var first := posmod(gen.seed_at(origin, 19) + serial, candidates.size())
	var offset := posmod(gen.seed_at(origin, 31) + serial, TASKS.size())
	var stops: Array[Dictionary] = []
	for index in length:
		var cell: Vector2i = candidates.pop_at(first if index == 0 else rng.randi_range(0, candidates.size()-1))
		stops.append({"cell":cell, "site":gen.site_for(cell), "task":TASKS[(offset+index)%TASKS.size()]})
	s.progress.patrol = {"serial":serial, "index":0, "stops":stops}
	s.notify("已登记第 %d 趟巡线 · %s" % [serial, destination(s).name], 4)

static func advance(s: Node) -> void:
	var run: Dictionary = s.progress.patrol
	run.index = int(run.index) + 1
	run.erase("listen_until")
	var next := stop(s)
	s.notify("巡线记录齐全 · 到任一驻地公告板选领物资" if next.is_empty() else "已记入巡线簿 · 下一站 "+str(destination(s).name), 4)

static func opened_cache(s: Node, cell: Vector2i) -> void:
	var leg := stop(s)
	if leg.get("task") == "audit" and leg.cell == cell: advance(s)

static func locker_prompt(s: Node, cell: Vector2i) -> String:
	var leg := stop(s)
	if leg.get("cell") != cell: return ""
	match str(leg.task):
		"audit": return "巡线 · 重建台账（废铁 ×2）"
		"repair": return "巡线 · 接好断线（废铁 ×2、纤维 ×1）"
	var run: Dictionary = s.progress.patrol
	if run.has("listen_until"):
		return "巡线 · 守听剩余 %d 秒" % maxi(0, ceili(float(run.listen_until) - s.clock.elapsed))
	return "巡线 · 启动无线电守听"

static func use_locker(s: Node, cell: Vector2i) -> bool:
	var leg := stop(s)
	if s.replica or leg.get("cell") != cell: return false
	if leg.task == "listen":
		if not s.progress.patrol.has("listen_until"):
			s.progress.patrol.listen_until = s.clock.elapsed + LISTEN_SECONDS
			s.notify("守听已开始 · 至少一人留在柜旁十米内")
		return true
	var cost := {"scrap":2, "fiber":1} if leg.task == "repair" else {"scrap":2}
	if s.bag.spend(cost): advance(s)
	else: s.notify("缺少材料 · "+str(s.catalog.requirements(cost)))
	return true

static func tick(s: Node) -> void:
	var run: Dictionary = s.progress.patrol
	if not run.has("listen_until"): return
	var at: Vector2 = destination(s).at
	var center := Vector3(at.x, 0, at.y)
	center.y = s.stream.ground_at(center) + 0.5
	var nearby:bool=s.team_distance_squared(center)<=100.0
	if not nearby:
		run.erase("listen_until")
		s.notify("信号中断 · 回到中继柜重新启动守听")
	elif s.clock.elapsed >= float(run.listen_until):
		advance(s)

static func reward(run: Dictionary, crate: String) -> Dictionary:
	var count: int = run.stops.size()
	var items: Dictionary
	match crate:
		"workshop": items = {"steel":count+1, "electronics":count, "parts":count*2}
		"watch":
			items = {"bandage":count, "reinforcement_kit":1}
			items["round" if count==2 else "heavy_round"] = count*4
		"travel": items = {"trail_ration":count, "clean_water":count*2, "medkit":1}
	if int(run.serial)%3 == 0: items["spring"] = 4
	return items

static func claim(s: Node, serial: int, crate: String) -> void:
	var run: Dictionary = s.progress.patrol
	if s.replica or not s.near_board(false) or run.get("serial") != serial or not CRATES.has(crate): return
	if not stop(s).is_empty(): return
	var items := reward(run, crate)
	var xp: int = run.stops.size()*60
	s.progress.patrol = {}
	s.gain(xp, "relay_patrol")
	s.award(items, s.player.global_position)
	s.notify("第 %d 趟巡线已结清 · %s · +%d 经验" % [serial, CRATES[crate], xp], 4)
