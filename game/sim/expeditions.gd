extends RefCounted

const Sites:=preload("res://game/world/expedition_sites.gd")
const BRIDGE_REWARD := {"spring":2,"bandage":2}
const WATCH_SUPPLIES := {"well":{"clean_water":2},"bridge":{"bandage":2}}
const COST:={"shelter":{"wood":4,"fiber":3},"weather":{"scrap":3},"canal":{"stone":3},"well":{"scrap":2,"wood":2}}
const PREVIOUS:={"weather":"shelter","well":"canal","pump":"ferry","bridge":"pump"}
const INSTRUCTION:={"shelter":"用木料与纤维加固避风棚，在棚口选择路线。","weather":"橙环沿山肩绕行避风，蓝双环直穿风口较近。走近道前戴上保暖帽或先在棚下取暖，再到风杯塔，修复山口测候仪。","canal":"找到干渠石岸，砌好闸槽，再沿残存水渠前往驼站。","well":"沿干渠与石桩找到八角井圈，修好提水泵。","ferry":"从灰湾南岸入水，沿橙旗绳下潜，在倾覆渡船旁抄录航运铭牌。","pump":"上浮换气，再找青旗浮绳；潜到泵站进水格栅外侧，读取水尺。","bridge":"换气后前往砖红旗，沿绳潜至断桥桥墩旁，拓录界碑。"}
const RESULT:={"shelter":"避风棚已加固，可休息取暖。橙环缓坡避风；蓝双环近道迎风，出发前可在棚内取暖。","weather":"风杯仪已修好，可读取下一时段的天气。","canal":"清淤砌闸完成。沿干渠橙环路桩前往驼站提水泵。","well":"驼站提水泵已恢复，可在这里饮水。","ferry":"铭牌记下了青旗进水口。先上浮换气，下次从泵站继续。","pump":"水尺标着断桥墩号。先上浮换气，再循砖红旗寻找界碑。","bridge":"三份记录已合并为灰湾航运调查。已收到打捞补给。"}

static func _done(s:Node,id:String)->bool:
	return s.progress.records.has("exp_"+id)

static func journal(s:Node)->Array[Dictionary]:
	var points:Dictionary=Sites.survey(s.stream.generator).points
	var rows:Array[Dictionary]=[]
	for chain:Array in [["shelter","weather"],["canal","well"],["ferry","pump","bridge"]]:
		if not points.has(chain[-1]): continue
		var index:=0
		while index<chain.size()-1 and _done(s,chain[index]): index+=1
		var id:String=chain[index]
		var complete:=_done(s,id)
		var at:Vector3=points[id]
		var name:String={"shelter":"雪线远征","canal":"沙海水路","ferry":"灰湾潜调"}[chain[0]]
		rows.append({"id":id,"route":chain[0],"name":"%s  %d/%d · %s"%[name,index+int(complete),chain.size(),Sites.LABELS[id]],"desc":RESULT[id] if complete else INSTRUCTION[id],"at":Vector2(at.x,at.z),"complete":complete})
	return rows

static func ground_id(s:Node,point:Vector3)->String:
	var points:Dictionary=Sites.survey(s.stream.generator).points
	for id:String in points:
		var at:Vector3=points[id]
		if Vector2(at.x,at.z).distance_squared_to(Vector2(point.x,point.z))<=3.24:
			return id
	return ""

static func prompt(s:Node,id:String)->String:
	if not Sites.LABELS.has(id): return ""
	if PREVIOUS.has(id) and not _done(s,PREVIOUS[id]):
		return "先调查"+str(Sites.LABELS[PREVIOUS[id]])
	if not _done(s,id):
		if COST.has(id):
			var parts:=PackedStringArray()
			for item:String in COST[id]: parts.append("%s×%d"%[s.catalog.title(item),COST[id][item]])
			return "修复"+str(Sites.LABELS[id])+" · "+"、".join(parts)
		return "抄录"+str(Sites.LABELS[id])
	if id=="well" and s.bag.current()=="composite_filter": return "装入复合滤芯 · 净水 ×6"
	return {"shelter":"在避风棚休息取暖","weather":"读取下时段天气","well":"从提水泵饮水 · 手持复合滤芯可取六份净水"}.get(id,"重读"+str(Sites.LABELS[id]))

static func use(s:Node,id:String)->void:
	if s.replica or not Sites.LABELS.has(id): return
	var points:Dictionary=Sites.survey(s.stream.generator).points
	if not points.has(id) or s.player.global_position.distance_to(points[id])>8.0: return
	if PREVIOUS.has(id) and not _done(s,PREVIOUS[id]):
		s.notify(prompt(s,id))
		return
	if not _done(s,id):
		if COST.has(id) and not s.bag.spend(COST[id]):
			s.notify(prompt(s,id)+" · 材料不足")
			return
		s.progress.records["exp_"+id]=1
		s.gain(35)
		if id=="bridge": s.award(BRIDGE_REWARD,s.player.global_position)
		s.notify(RESULT[id],5)
		return
	match id:
		"shelter":
			s.player.warm_drink_left=maxf(s.player.warm_drink_left,100)
			s.player.body_temp=maxf(s.player.body_temp,36.5)
			s.notify("已在避风棚复温 · 出发后仍保暖 100 秒")
		"weather":
			var forecast:int=s.clock.weather_at(floori(s.clock.hours/9.0)+1)
			var next_hour:=posmod((floori(s.clock.hours/9.0)+1)*9,24)
			s.notify("山口预报 · 下一时段 %02d:00 起，%s"%[next_hour,WastelandCatalog.WEATHER[forecast]],5)
		"well":
			if s.bag.current()=="composite_filter":
				s.draw_filtered_batch(points[id],6,s.bag.active)
				return
			s.player.hydration=minf(100,s.player.hydration+34)
			s.notify("已饮用驼站井水 · 水分 %d"%roundi(s.player.hydration))
		_: s.notify(RESULT[id],4)
