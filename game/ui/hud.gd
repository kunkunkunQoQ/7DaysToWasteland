class_name WastelandHUD
extends Control

const S := preload("res://game/ui/style.gd")
const DIRECTIONS := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
const CREAM := Color("#fff0d6")
const VITALS := ["生命","耐力","饱食","水分"]
const BAR_COLORS := [Color("#d97582"), Color("#e2b171"), Color("#a9ac73"), Color("#83b6c3")]
var game: Node
var session: WastelandSession
var toast := ""
var toast_left := 0.0
var blink := 0.0
var draw_tick := 0.0
var scale_height := 340
var last_frame_ms := 0.0
var tracked_marker_id := -1
var tracked_expedition := ""
var touch_layout := preload("res://game/ui/touch_controls.gd").supported()
var area_label := ""
var weather_label := ""
var area_until := 0.0
var objective_state := []
var objective_until := 0.0
var axe_state := []
var axe_until := 0.0
var held_id := ""
var held_until := 0.0

func enter_world(world: WastelandSession) -> void:
	session=world
	area_label=""
	weather_label=""
	objective_state=[]
	axe_state=[]
	held_id=""
	held_until=0.0
	draw_tick=0.0
	update_notices()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	if not visible:
		return
	toast_left = maxf(0.0, toast_left - delta)
	blink += delta
	if is_instance_valid(session) and is_instance_valid(session.player):
		draw_tick-=delta
		if draw_tick<=0:
			draw_tick=0.20
			update_notices()
	queue_redraw()

func update_notices() -> void:
	var at:=session.player.global_position
	var area:=session.stream.generator.landform(at.x,at.z)
	var weather:String=WastelandCatalog.WEATHER[session.atmosphere.weather_kind]
	if session.atmosphere.rain_strength>0.12 and session.atmosphere.snowing: weather="高地飞雪"
	if area!=area_label or weather!=weather_label:
		area_label=area
		weather_label=weather
		area_until=blink+4.0
	var progress:=session.progress
	var job:=progress.active_job(session.catalog.quests)
	var count:=0
	if not job.is_empty() and progress.accepted:
		count=mini(1,session.bag.count("beacon_log")) if job.record=="beacon" else mini(progress.job_count(job),int(job.amount))
	var patrol:=progress.patrol
	var objective:=[progress.job,progress.accepted,count,patrol.get("serial",-1),patrol.get("index",-1),tracked_expedition]
	if objective!=objective_state:
		objective_state=objective
		objective_until=blink+4.5
	if progress.records.has("first_axe_guide"):
		var materials: Array = []
		var inputs:Dictionary=session.catalog.recipes.stone_axe.inputs
		for id:String in inputs: materials.append(mini(session.bag.count(id),inputs[id]))
		materials.append(session.bag.count("stone_axe")>0)
		materials.append(session.hand_queue.any(func(job): return job.id=="stone_axe"))
		if materials!=axe_state:
			axe_state=materials
			axe_until=blink+6.0
	var held:=session.bag.current()
	if held!=held_id:
		held_id=held
		held_until=blink+2.0

func say(words: String, duration: float) -> void:
	toast = words
	toast_left = duration

func _draw() -> void:
	if session == null or not is_instance_valid(session.player):
		return
	var player := session.player
	var cx := size.x * 0.5
	var s := size
	var mirror_touch:=touch_layout and session.options.touch_left_handed
	var blood := session.clock.horde_active()
	if session.optics_active() and player.camera.fov<45.0:
		var center := s*0.5
		var lens := minf(s.x,s.y)*0.245
		for i in 4:
			var start_angle := PI*i*0.5+0.48
			draw_arc(center,lens,start_angle,start_angle+0.60,24,Color(0.06,0.10,0.10,0.68),3.0,true)
		for i in range(-3,4):
			if i==0: continue
			var notch := center+Vector2(i*12,0)
			draw_line(notch-Vector2(0,4),notch+Vector2(0,4),Color(0.09,0.13,0.12,0.83),2.0)
		_text(center+Vector2(lens*0.65,lens*0.7),"3×",17,CREAM,1)
	_day(Vector2(28,25), blood)
	var axe_guide:=session.progress.records.has("first_axe_guide") and axe_until>blink and not blood
	if axe_guide:
		_first_axe(Vector2(s.x-28 if mirror_touch else 28,70),mirror_touch)
	_compass(Vector2(cx,39))
	if area_until>blink: _area(Vector2(s.x - 29,34))
	_vitals(Vector2(s.x-216 if mirror_touch else 28,s.y - 140), player)
	if player.swimming or player.submerged or player.breath < player.max_breath() - 0.1:
		_water_readout(Vector2(cx,94), player)
	_hotbar(Vector2(cx,s.y - 18))
	_center(s / 2.0)
	if Time.get_ticks_msec()<session.achievements.caption_until:
		var words: String=session.achievements.caption
		var width:=_width(words,16)+32
		_box(Rect2(Vector2(cx-width*0.5,145),Vector2(width,32)),S.GOLD)
		_text(Vector2(cx,167),words,16,CREAM,1)
	_damage_direction(s / 2.0, player)
	if not axe_guide and (objective_until>blink or blood or session.progress.patrol.has("listen_until")):
		_status(Vector2(s.x-28 if mirror_touch else 28,100),mirror_touch)
	if toast_left > 0.0:
		var center := Vector2(cx,s.y-(190 if touch_layout else 150))
		var width := _width(toast, 18) + 32.0
		_box(Rect2(center - Vector2(width*0.5,17), Vector2(width,36)), Color("#a07964"), Color(0.08,0.065,0.11,0.92))
		_text(center + Vector2(0,6), toast, 18, S.GOLD, 1)
	if session.options.display.show_fps:
		_text(Vector2(s.x-28 if mirror_touch else 256,s.y-164) if touch_layout else Vector2(s.x-28,106), "%d FPS  ·  %.1f ms  ·  %dp" % [Engine.get_frames_per_second(),last_frame_ms,scale_height], 14,S.MINT,2)

func _day(p: Vector2, blood: bool) -> void:
	var words:="第 %d 日  %s" % [session.clock.day(),session.clock.time_text()]
	var warning := session.clock.warning_minutes()
	if warning > 0: words += "  血月倒计时 %d 分钟" % warning
	elif blood: words+="  血月"
	elif session.clock.next_horde()==session.clock.day(): words+="  今夜血月"
	var tint:=S.RED if blood or warning > 0 else CREAM
	_box(Rect2(p,Vector2(_width(words,18)+26,33)),S.RED.darkened(0.38) if blood else S.BORDER)
	_text(p+Vector2(13,23),words,18,tint)

func _first_axe(pos: Vector2, align_right:=false) -> void:
	var bag:=session.bag
	var inputs: Dictionary = session.catalog.recipes.stone_axe.inputs
	var totals: PackedStringArray = []
	var next := ""
	var actions := {"stick":"捡地上的枯枝","stone":"捡地上的碎石","fiber":"打破草丛，捡植物纤维"}
	for id:String in inputs:
		var need:=int(inputs[id])
		totals.append("%s %d/%d" % [session.catalog.title(id),mini(bag.count(id),need),need])
		if next.is_empty() and bag.count(id)<need:
			next="[%s] %s" % [session.options.action_name("use"),actions.get(id,"收集"+session.catalog.title(id))]
			if id=="fiber":
				next="[%s] 打破草丛，走近拾取纤维" % session.options.action_name("fire")
				for drop_id:String in session.fx.drop_live:
					var row:Dictionary=session.fx.drop_records[drop_id]
					if row.items.has("fiber") and session.player.global_position.distance_squared_to(row.point)<25:
						next="走近地上的植物纤维即可拾取"
						break
	var title:="第一把石斧"
	var counter:="   ".join(totals)
	if bag.count("stone_axe")>0:
		title+=" · 已获得"
		var slot:=bag.bar.find("stone_axe")
		if slot>=0:
			counter="石斧在快捷栏第 %d 格" % (slot+1)
			next="对准树干挥斧" if bag.current()=="stone_axe" else "选中这一格，即可挥斧砍树"
		else:
			counter="打开 [%s]，选中石斧" % session.options.action_name("inventory")
			next="点「放入当前快捷格」，再挥斧砍树"
	elif session.hand_queue.any(func(job): return job.id=="stone_axe"):
		title+=" · 制作中"
		counter="材料已投入制作"
		next="完成后从快捷栏或背包选用石斧"
	elif next.is_empty():
		next="[%s] 背包 → 制作 → 石斧" % session.options.action_name("inventory")
	var width:=maxf(_width(counter,14),_width(next,15))+24
	if align_right: pos.x-=width
	_box(Rect2(pos,Vector2(width,74)),Color("#665847"))
	_text(pos+Vector2(12,21),title,16,S.GOLD)
	_text(pos+Vector2(12,43),counter,14,S.MUTED)
	_text(pos+Vector2(12,64),next,15,CREAM)
func _compass(center: Vector2) -> void:
	var width := 382.0
	var box := Rect2(center-Vector2(width*0.5,14),Vector2(width,42))
	draw_rect(box,Color(0.07,0.055,0.10,0.74))
	draw_line(box.position+Vector2(0,41),box.end-Vector2(0,1),Color("#6a5363"))
	var forward := -session.player.global_basis.z
	var heading := fposmod(rad_to_deg(atan2(forward.x,-forward.z)),360.0)
	var origin := floori((heading-65.0)/15.0)*15
	for index in range(11):
		var bearing := origin+index*15
		var x := center.x+(bearing-heading)*2.95
		if x < box.position.x+10.0 or x > box.end.x-10.0:
			continue
		var major := bearing % 45 == 0
		draw_line(Vector2(x,center.y+11),Vector2(x,center.y+(17 if major else 15)),S.GOLD if major else S.MUTED)
		if major:
			_text(Vector2(x,center.y+6),DIRECTIONS[posmod(bearing/45,8)],16,CREAM,1)
	draw_colored_polygon(PackedVector2Array([center+Vector2(-4,-14),center+Vector2(4,-14),center+Vector2(0,-7)]),S.GOLD)
	var at := session.player.global_position
	var route := destination()
	if not route.is_empty():
		var delta_xz: Vector2 = route.at - Vector2(at.x,at.z)
		var bearing := wrapf(rad_to_deg(atan2(delta_xz.x, -delta_xz.y)) - heading, -180, 180)
		var x := clampf(bearing, -62, 62) * 2.95
		var direction := "‹ " if bearing < -62 else (" ›" if bearing > 62 else "")
		var label_x := clampf(x,-126,126)
		draw_circle(center+Vector2(x,21),4,S.GOLD)
		if objective_until>blink or tracked_marker_id>=0 or tracked_expedition!="" or session.progress.accepted or not session.progress.patrol.is_empty():
			_text(center+Vector2(label_x,44),direction + str(route.name) + "  %d m" % roundi(delta_xz.length()),14,S.GOLD,1)
	for entry in session.marker_records:
		if entry.id == tracked_marker_id:
			continue
		var toward: Vector2 = entry.at - Vector2(at.x,at.z)
		if toward.length_squared() < 0.8:
			continue
		var a := rad_to_deg(atan2(toward.x,-toward.y))
		var off := wrapf(a-heading,-180.0,180.0)
		if absf(off)>62:
			continue
		var p := center+Vector2(off*2.95,20)
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(4,0),p+Vector2(0,4),p+Vector2(-4,0)]),S.MINT)

func _area(p: Vector2) -> void:
	var words:=area_label+"  ·  "+weather_label
	var width:=_width(words,16)+24
	_box(Rect2(p+Vector2(-width,-9),Vector2(width,33)),S.BORDER)
	_text(p+Vector2(-12,14),words,16,CREAM,2)

func _vitals(base: Vector2, player: WastelandSurvivor) -> void:
	var thermal:=player.ambient<12 or player.ambient>27 or player.body_temp<36 or player.body_temp>37.8 or player.wet>0.4
	if not thermal: base.y+=26
	var panel_rect := Rect2(base+Vector2(0,-15),Vector2(188,137 if thermal else 111))
	_box(panel_rect,Color("#5a4555"))
	var data := [player.health,player.stamina,player.hunger,player.hydration]
	var maximum := [player.max_health(),player.max_stamina(),100.0,100.0]
	for i in range(4):
		var p := base+Vector2(11,i*24)
		_text(p+Vector2(0,7),VITALS[i],15,CREAM)
		var rect := Rect2(p+Vector2(37,-4),Vector2(86,11))
		draw_rect(rect,Color("#383040"))
		if i == 0 and player.injury.trace_health > player.health:
			var trail := rect
			trail.size.x *= clampf(player.injury.trace_health / player.max_health(), 0.0, 1.0)
			draw_rect(trail, Color("#f1bc9e"))
		rect.size.x *= clampf(data[i]/maximum[i],0,1)
		draw_rect(rect,BAR_COLORS[i])
		_text(p+Vector2(165,6),str(roundi(data[i])),15,BAR_COLORS[i],2)
	if thermal: _text(base+Vector2(10,109),"环境 %+.0f°  体温 %.1f°" % [player.ambient,player.body_temp],15,S.MUTED)
	var ailments: Array[String] = []
	if player.bleed>0.15: ailments.append("流血")
	if player.infection>0.15: ailments.append("感染 %.0f%%" % player.infection)
	if player.fracture>0.15: ailments.append("骨折")
	elif player.sprain>0.0: ailments.append("扭伤")
	if player.wet>0.4: ailments.append("潮湿")
	if not ailments.is_empty():
		var info := "  ".join(ailments)
		_box(Rect2(base+Vector2(0,-46),Vector2(_width(info,15)+22,26)),Color("#744650"))
		_text(base+Vector2(11,-27),info,15,S.RED)
	if player.injury.label_left > 0.0:
		var source := player.injury.last_source
		var loss := player.injury.last_amount
		var cause: String = WastelandDamageFeedback.LABELS.get(source, "受伤")
		var words := cause + "  −" + (str(roundi(loss)) if loss >= 1.0 else "%.1f" % maxf(0.1, loss))
		var offset := -77.0 if not ailments.is_empty() else -46.0
		var alpha := minf(1.0, player.injury.label_left * 3.8)
		var tint: Color = WastelandDamageFeedback.COLORS.get(source, S.RED.lightened(0.16))
		var rect := Rect2(base + Vector2(0, offset), Vector2(_width(words, 16) + 27.0, 26.0))
		_box(rect, Color(tint.darkened(0.44), alpha), Color(0.09, 0.055, 0.085, 0.88 * alpha))
		_text(rect.position + Vector2(13, 19), words, 16, Color(tint, alpha))

func _damage_direction(center: Vector2, player: WastelandSurvivor) -> void:
	var radius := clampf(size.y * 0.19, 95.0, 156.0)
	var right := player.global_basis.x
	var forward := -player.global_basis.z
	for cue in player.injury.directions:
		var toward: Vector3 = cue.bearing
		var screen := Vector2(toward.dot(right), -toward.dot(forward))
		var angle := screen.angle()
		var alpha := clampf(float(cue.lifetime) * 2.0, 0.0, 1.0)
		var span := 0.14 + float(cue.power) * 0.07
		var tint: Color = cue.color
		var side := screen.orthogonal()
		var tip := center + screen * (radius + 10.0)
		var foot := center + screen * (radius - 2.0)
		draw_arc(center, radius, angle - span, angle + span, 14, Color(0.065, 0.022, 0.036, 0.87 * alpha), 7.0)
		draw_arc(center, radius, angle - span, angle + span, 14, Color(tint, 0.87 * alpha), 3.0)
		draw_colored_polygon(PackedVector2Array([tip, foot + side * 7.0, foot - side * 7.0]), Color(tint, alpha))

const SLOT_STEP:=66.0

static func quickbar_rect(view_size:Vector2)->Rect2:
	return Rect2(view_size.x*0.5-SLOT_STEP*4,view_size.y-84,SLOT_STEP*8.0,57)

static func offhand_rect(view_size:Vector2)->Rect2:
	return Rect2(quickbar_rect(view_size).position-Vector2(74,0),Vector2(61,57))

func _hotbar(foot: Vector2) -> void:
	var step := SLOT_STEP
	var start := quickbar_rect(size).position
	var bag := session.bag
	_box(Rect2(start-Vector2(5,4),Vector2(step*8.0+6,66)),Color("#5d4b5c"))
	var side:=offhand_rect(size)
	_box(side,Color("#786c5a"),Color(0.075,0.061,0.105,0.87))
	if bag.offhand!="":
		draw_texture_rect(WastelandItemArt.icon(bag.offhand,session.catalog.items[bag.offhand]),Rect2(side.position+Vector2(12,9),Vector2(36,36)),false)
	_text(side.position+Vector2(5,15),"副手",12,S.MUTED)
	for i in range(8):
		var selected := i == bag.active
		var p := start+Vector2(step*i,0)
		var slot := Rect2(p,Vector2(61,57))
		_box(slot,S.GOLD if selected else Color("#4b3c50"),Color(0.20,0.14,0.20,0.95) if selected else Color(0.075,0.061,0.105,0.87))
		if selected:
			draw_rect(Rect2(p,Vector2(61,2)),S.GOLD)
		_text(p+Vector2(6,15),str(i+1),13,S.GOLD if selected else S.FAINT)
		var id: String = bag.bar[i]
		if bag.count(id) > 0:
			var def: Dictionary = session.catalog.items[id]
			var icon := WastelandItemArt.icon(id,def)
			draw_texture_rect(icon,Rect2(p+Vector2(12,9),Vector2(36,36)),false)
			_text(p+Vector2(56,50),str(bag.count(id)) if def.kind != "ranged" else str(bag.magazine.get(id,0)),14,S.TEXT,2)
	var held := bag.current()
	var display := "空手"
	if held != "":
		var def: Dictionary = session.catalog.items[held]
		display = session.catalog.title(held)
		if def.kind == "ranged":
			display += "    %d / %d" % [int(bag.magazine.get(held,0)),bag.count(def.ammo)]
		if def.kind == "build":
			display += "  ·  " + WastelandCatalog.SHAPE_NAMES[session.shape]
	var hand:=session.player.hand
	var progress := -1.0
	if hand.reload_ratio>0.0:
		display += "  ·  装填中"
		progress=1.0-hand.reload_ratio
	elif hand.charge>0.0:
		display += "  ·  蓄力"
		progress=hand.charge
	if progress<0.0 and held_until<=blink and session.catalog.items.get(held,{}).get("kind","") not in ["ranged","build"]:
		return
	var width:=_width(display,16)+22
	var plate:=Rect2(foot.x-width*0.5,start.y-34,width,25)
	_box(plate,Color("#625448"))
	_text(Vector2(foot.x,plate.position.y+18),display,16,CREAM,1)
	if progress>=0.0:
		draw_rect(Rect2(plate.position+Vector2(0,23),Vector2(width*clampf(progress,0,1),2)),S.GOLD)


func _center(point: Vector2) -> void:
	var gap := 5.0 + session.player.shot_spread()*360.0 + session.player.hand.charge * 4.0
	draw_rect(Rect2(point-Vector2(1,1),Vector2(2,2)),CREAM)
	for dir in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		draw_line(point+dir*gap,point+dir*(gap+5),S.INK,3.0)
		draw_line(point+dir*gap,point+dir*(gap+5),CREAM,1.0)
	if session.player.confirmation_left>0:
		var ink:=Color("#ff554e") if session.player.confirmed_head else Color.WHITE
		for offset:Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			draw_line(point+offset*5,point+offset*11,S.INK,3.0)
			draw_line(point+offset*5,point+offset*11,ink,1.5)
	if session.player.crouch>0.5:
		var noise:=session.player.heard_radius()
		var rect:=Rect2(point+Vector2(-30,13),Vector2(60,4))
		draw_rect(rect,S.INK)
		rect.size.x*=clampf(noise/10.0,0.0,1.0)
		draw_rect(rect,S.GOLD)
		_text(point+Vector2(0,-14),"潜行　%.1f 米"%noise,13,S.MINT,1)
	if session.focus_damage >= 0.0:
		var hp := Rect2(point+Vector2(-33,-30),Vector2(66,4))
		draw_rect(hp,S.INK)
		hp.size.x *= clampf(session.focus_damage,0,1)
		draw_rect(hp,S.RED)
	if session.hint != "":
		var words := session.hint
		var w := _width(words,17)+26
		_box(Rect2(point+Vector2(-w*0.5,24),Vector2(w,30)), Color("#715967"))
		_text(point+Vector2(0,44),words,17,CREAM,1)
	if session.loot_ratio > 0.0:
		_box(Rect2(point+Vector2(-101,58),Vector2(202,10)),S.MUTED)
		draw_rect(Rect2(point+Vector2(-98,61),Vector2(196*session.loot_ratio,4)),S.GOLD)

func _status(pos: Vector2,align_right:bool) -> void:
	var horde := session.clock.horde_active()
	var goal := "下一次血月 · 第 %d 日" % session.clock.next_horde()
	if horde:
		var director := session.hordes
		if director.wave_index > 0 and director.wave_index < director.wave_total and session.clock.elapsed >= director.assault_until:
			goal = "补墙间隙 · 下一波 %d 秒" % maxi(0, ceili(director.next_wave - session.clock.elapsed))
		else:
			goal = "坚守至 04:00 · 第 %d / %d 波" % [director.wave_index, director.wave_total]
	var secondary := ""
	var job := session.progress.active_job(session.catalog.quests)
	if session.progress.accepted and not job.is_empty():
		secondary = "%s  %d / %d" % [job.name,mini(session.progress.job_count(job), int(job.amount)),int(job.amount)]
		if job.record == "beacon":
			secondary = "%s  %d / 1" % [job.name,mini(1,session.bag.count("beacon_log"))]
	elif not job.is_empty():
		secondary = "前往"+str(session.board_destination().name)
	if not job.is_empty():
		secondary = "主线 %d/%d · " % [session.progress.job+1,session.catalog.quests.size()]+secondary
	elif session.progress.finish_day!=0:
		secondary = "三站巡线已开放"
	var run := session.progress.patrol
	if not run.is_empty() and (job.is_empty() or tracked_expedition in ["","relay_patrol"]):
		secondary = "第 %d 趟巡线 · %d/%d 站" % [run.serial,run.index,run.stops.size()]
		if run.has("listen_until"): secondary += " · 守听 %d 秒" % maxi(0,ceili(float(run.listen_until)-session.clock.elapsed))
	var words:=goal if horde or secondary.is_empty() else secondary
	var width := _width(words,16)+24
	if align_right: pos.x-=width
	_box(Rect2(pos+Vector2(0,-32),Vector2(width,31)),Color("#5d4b5c"))
	_text(pos+Vector2(12,-11),words,16,S.RED if horde else S.GOLD)

func destination() -> Dictionary:
	for marker in session.marker_records:
		if int(marker.id) == tracked_marker_id:
			return marker
	if tracked_expedition not in ["","campaign","relay_patrol"]:
		for row in preload("res://game/sim/expeditions.gd").journal(session):
			if row.route==tracked_expedition: return row
	var order:=session.order_destination()
	if not order.is_empty(): return order
	if tracked_expedition!="campaign" and not session.progress.patrol.is_empty(): return session.Patrol.destination(session)
	var job := session.progress.active_job(session.catalog.quests)
	if not job.is_empty():
		var ready := session.bag.count("beacon_log") >= 1 if job.record == "beacon" else session.progress.job_count(job) >= int(job.amount)
		if not session.progress.accepted or ready:
			return session.board_destination()
		if job.record=="beacon": return session.beacon_destination()
	if job.is_empty(): return session.board_destination()
	return {}

func _water_readout(at: Vector2, player: WastelandSurvivor) -> void:
	var tint := S.RED if player.breath < 5.0 else S.MINT
	var rect := Rect2(at + Vector2(-143,0),Vector2(286,50))
	_box(rect, tint.darkened(0.35))
	var depth := maxf(0,-player.camera.global_position.y)
	_text(rect.position+Vector2(10,19), "水下 %.1f m" % depth if player.submerged else "水面换气",15,CREAM)
	_text(rect.position+Vector2(276,19), "氧气 %d s" % ceili(player.breath),15,tint,2)
	draw_rect(Rect2(rect.position+Vector2(10,25),Vector2(266,3)), S.BORDER)
	draw_rect(Rect2(rect.position+Vector2(10,25),Vector2(266*player.breath/player.max_breath(),3)),tint)
	_text(rect.position+Vector2(143,43),"[%s] 上浮    [%s] 下潜" % [session.options.action_name("jump"),session.options.action_name("crouch")],13,S.MUTED,1)

func _box(rect: Rect2, outline: Color, background: Color = Color(0.055,0.095,0.094,0.87)) -> void:
	draw_rect(rect,background)
	draw_rect(rect,outline,false,1.0)

func _width(words: String, font_size: int) -> float:
	return S.FONT.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x

func _text(pos: Vector2, words: String, font_size: int, tint: Color, anchor: int = 0) -> void:
	var adjusted := pos
	if anchor > 0: adjusted.x -= _width(words,font_size) * (0.5 if anchor == 1 else 1.0)
	draw_string(S.FONT,adjusted+Vector2(1,1),words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(0,0,0,0.75))
	draw_string(S.FONT,adjusted,words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,tint)
