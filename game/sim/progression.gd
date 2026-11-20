class_name WastelandProgression
extends RefCounted

var level := 1
var xp := 0
var points := 0
var skills: Dictionary = {}
var records: Dictionary = {}
var job := 0
var baseline := 0
var accepted := false
var delivery_day := 0
var finish_day := 0
var finish_stats: Dictionary = {}
var achieved: Dictionary = {}
var legacy_water := false
var repair_base := 0
var dispatch: Dictionary = {}
var patrol: Dictionary = {}

func _init(snapshot: Dictionary = {}) -> void:
	level = maxi(1, int(snapshot.get("level", 1)))
	xp = int(snapshot.get("xp", 0))
	points = int(snapshot.get("points", 0))
	skills = snapshot.get("skills", {}).duplicate()
	records = snapshot.get("records", {}).duplicate()
	job = int(snapshot.get("job", 0))
	baseline = int(snapshot.get("baseline", 0))
	accepted = bool(snapshot.get("accepted", false))
	legacy_water = bool(snapshot.get("legacy_water",not snapshot.has("quest_revision") and job==1 and accepted))
	repair_base = int(snapshot.get("repair_base",0))
	dispatch = snapshot.get("dispatch",{}).duplicate(true)
	patrol = snapshot.get("patrol",{}).duplicate(true)
	delivery_day = int(snapshot.get("delivery_day", 0))
	finish_day = int(snapshot.get("finish_day",0))
	finish_stats = snapshot.get("finish_stats",{}).duplicate()
	achieved = snapshot.get("achieved",{}).duplicate()

func snapshot() -> Dictionary:
	return {
		"level": level, "xp": xp, "points": points, "skills": skills.duplicate(),
		"records": records.duplicate(), "job": job, "baseline": baseline, "accepted": accepted,
		"delivery_day": delivery_day, "finish_day":finish_day, "finish_stats":finish_stats.duplicate(),
		"achieved":achieved.duplicate(),"quest_revision":2,"legacy_water":legacy_water,"repair_base":repair_base,"dispatch":dispatch.duplicate(true),
		"patrol":patrol.duplicate(true),
	}

func goal() -> int:
	return 70 + level * 35

func gain(amount: int, record: String = "", count: int = 1) -> bool:
	if record != "":
		records[record] = int(records.get(record, 0)) + count
	xp += amount
	var leveled := xp >= goal()
	while xp >= goal():
		xp -= goal()
		level += 1
		points += 1
	return leveled

func rank(id: String) -> int:
	return int(skills.get(id, 0))

func can_learn(id: String, definition: Dictionary) -> bool:
	var next := rank(id) + 1
	var prereq: Array = definition.get("requires", [])
	if points < 1 or next > int(definition.max) or level < int(definition.unlock) + (next - 1) * 2:
		return false
	return prereq.is_empty() or rank(str(prereq[0])) >= int(prereq[1])

func learn(id: String, definition: Dictionary) -> bool:
	if not can_learn(id, definition):
		return false
	skills[id] = rank(id) + 1
	points -= 1
	return true

func active_job(quests: Array) -> Dictionary:
	if job<0 or job>=quests.size(): return {}
	var definition: Dictionary=quests[job]
	if legacy_water and job==1: return definition.legacy
	if definition.get("record")=="horde" and int(records.get("horde",0))==0 and records.has("failed_horde_day"):
		return definition.repair
	return definition

func job_count(definition: Dictionary) -> int:
	if definition.get("record")=="rebuild_watch": return maxi(0,int(records.get("build",0))-repair_base)
	if definition.get("record")=="horde": return int(records.get("horde",0))
	return maxi(0, int(records.get(definition.get("record", ""), 0)) - baseline)
