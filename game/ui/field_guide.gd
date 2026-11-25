extends VBoxContainer

signal materials_requested
signal sources_requested

const S := preload("res://game/ui/style.gd")
const Stage := preload("res://game/ui/model_study.gd")
const LookPicker := preload("res://game/ui/infected_look_picker.gd")
const FaceSelector := preload("res://game/ui/face_selector.gd")
const AQUATIC := {
	"heron":{"name":"灰鹭","hint":"在南岸浅水里等候小鱼。放慢脚步，看它伸颈或起飞。"},
	"lake_fish":{"name":"湖鱼群","hint":"寻找浅滩边的同心涟漪。船靠近时，鱼群会收紧队形并避开船头。"},
	"pond_turtle":{"name":"泽龟","hint":"沿遗址外侧的水草床缓缓下潜，泽龟在湖床上方划水。金纹种常在泵站附近活动。"},
	"crayfish":{"name":"溪螯虾","hint":"贴着沉船与桥墩边的砂砾观察步足。青壳种栖于断桥附近，潜水者靠近时会举螯退开。"}
}
const GATHERING := {
	"herb_patch":["近湖草地和黑杉林下，寻找成簇的花叶。","药草可制敷贴、暖饮，也可用芦秆和皮革编成止血夹板。"],
	"reed_bed":["沿湖滩的水陆交界处走，留意浅水中的高秆。","芦秆可作长矛的矛杆，也可编入油布背心。"],
	"iron_vein":["在灰脊高地和盐烬焦土寻找红棕色露头，地堡附近也有矿脉。","把铁矿石带到熔炉，可炼成铁锭。"],
	"fallen_stick":["留意草地、林缘和起步点附近分叉的落枝。伐树时也会折下木棍，有树冠的树还会掉落阔叶或针叶。","一根木棍、两块石头、两份草纤维可制石斧。一根木棍和三份落叶可扎成引火束。木料也能加工成木棍。"],
	"pebble":["低头寻找散落的小石。","小石是石斧的斧头。"],
	"grass":["打破脚边的草簇，再拾取掉到地上的植物纤维。","用草纤维把斧头绑紧。"],
	"machine_wreck":["沿公路边缘寻找锈蚀的泵机，旧镇、加油站和警署附近尤其常见。","弹簧可组装折弩。远行前用弹簧、废铁、皮革和油备好行车维修包。"]
}
const WRECKS := {"ferry":"沉没渡船","pump":"淹没泵站","bridge":"断桥遗址"}
const FORMS := {"":"常见型","young":"幼年","local":"地方色","armored":"披甲","swift":"迅行"}
var session: WastelandSession
var list: VBoxContainer
var details: VBoxContainer
var category := "野生动物"
var preview_actor: WastelandCreature
var face_selector: FaceSelector
var selected_gathering := ""
var gathering_count := 0

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tabs := S.line(self)
	for entry: String in ["野生动物","感染者","地点与航线","采集手记"]:
		var button := S.button(entry, func(): _populate(entry))
		tabs.add_child(button)
	tabs.add_child(S.button("材料用途",func(): materials_requested.emit()))
	tabs.add_child(S.button("获取方式",func(): sources_requested.emit()))
	var cols := S.line(self)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail := S.column(cols,3)
	rail.custom_minimum_size.x = 212
	list = S.scroller(rail)
	details = S.scroller(cols)
	details.add_theme_constant_override("separation",5)
	_populate(category)

func _clear(panel: Control) -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()

func _populate(group: String) -> void:
	category = group
	_clear(list)
	var ids: Array = []
	match group:
		"野生动物":
			ids.assign(WastelandHordes.WILDLIFE)
			ids.append_array(AQUATIC.keys())
		"感染者":
			ids.assign(WastelandHordes.KINDS)
		"采集手记":
			ids.assign(GATHERING.keys())
			var basics:=S.button("入门 · 第一把石斧",_first_axe_note)
			list.add_child(basics)
		_:
			ids.assign(session.catalog.sites.keys())
			if session.stream.generator.revision >= 2: ids.append_array(WRECKS.keys())
	for key in ids:
		var id := str(key)
		var label := _name_of(id)
		if _recorded(id): label += "　✓"
		var button := S.button(label,func(): _select(id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 33
		list.add_child(button)
	if not ids.is_empty():
		_select(selected_gathering if group=="采集手记" and GATHERING.has(selected_gathering) else str(ids[0]))

func _first_axe_note()->void:
	_clear(details)
	preview_actor=null
	selected_gathering=""
	details.add_child(S.label("第一把石斧",23,S.GOLD))
	details.add_child(S.label("低头找枯枝和碎石，按 [%s] 捡起。按 [%s] 打破草丛，走近地上的纤维即可拾取。空拳打树干每拳损失 2 点生命，打岩块损失 3 点，打钢板损失 4 点。" % [session.options.action_name("use"),session.options.action_name("fire")],18,S.TEXT,true))
	details.add_child(S.label("随身制作材料 · "+session.catalog.requirements(session.catalog.recipes.stone_axe.inputs),17,S.MINT,true))
	details.add_child(S.label("打开 [%s] → 制作，选石斧。做好后选中快捷栏里的石斧就能伐木。若快捷栏已满，可在背包里为石斧指定一格。" % session.options.action_name("inventory"),17,S.TEXT,true))
	details.add_child(S.label("伐木后走近落枝和落叶即可收集。林地也能捡到零散落叶。阔叶和针叶都能扎成引火束、编遮阳斗篷，或在化学实验台制成燃料。",17,S.TEXT,true))
	details.add_child(S.button("查看树苗与种植",_sapling_note))

func _sapling_note()->void:
	_clear(details)
	preview_actor=null
	selected_gathering=""
	(details.get_parent() as ScrollContainer).scroll_vertical=0
	details.add_child(S.label("树苗与种植",23,S.GOLD))
	details.add_child(S.label("风吹落叶、砍伐时震落的叶片和撞地的树冠，都有机会带落同种树苗。走近掉下的树苗就能拾取。",18,S.TEXT,true))
	details.add_child(S.label("把树苗选入主手，在干燥的天然地面瞄准落点，按 [%s] 种下。选露天的平地或缓坡，和其他树木至少相隔 3 米。" % session.options.action_name("fire"),17,S.TEXT,true))
	details.add_child(S.label("瞄准幼树可查看长势。成熟前可以用工兵铲挖起移栽，成熟后可以砍伐。",17,S.MUTED,true))
	S.rule(details)
	details.add_child(S.label("每份落叶伴随树苗的概率 · 从种下到成树的游戏天数",16,S.MINT,true))
	for model:String in ["oak","birch","pine","frost_fir","snow_fir"]:
		var row:=S.line(details)
		_gather_item(row,"sapling_"+model)
		row.add_child(S.label("%d%%　·　%s 天" % [session.timber.SAPLING_PERCENT[model],str(preload("res://game/art/sapling_art.gd").duration_days(model)).trim_suffix(".0")],17,S.TEXT))

func _name_of(id: String) -> String:
	if GATHERING.has(id): return WastelandSession.RESOURCES[id][0]
	if WRECKS.has(id): return WRECKS[id]
	if AQUATIC.has(id): return AQUATIC[id].name
	if session.catalog.sites.has(id): return session.catalog.sites[id].name
	return session.catalog.enemies[id].name

func _recorded(id: String, morph: String = "") -> bool:
	if GATHERING.has(id): return session.progress.records.has("gather_"+id)
	var prefix := "recover_" if WRECKS.has(id) else "visit_" if session.catalog.sites.has(id) else "kill_" if category == "感染者" else "observe_"
	return session.progress.records.has(prefix+id+("_"+morph if morph != "" else ""))

func _select(id: String, morph: String = "") -> void:
	var appearance:=Vector4i.ZERO
	if is_instance_valid(preview_actor) and preview_actor.type==id:
		appearance=Vector4i(preview_actor.look_index,preview_actor.wardrobe_index,preview_actor.limb_index,preview_actor.face_variant)
	elif is_instance_valid(face_selector) and face_selector.species==id:
		appearance.w=face_selector.variant
	face_selector=null
	_clear(details)
	var scroll:=details.get_parent() as ScrollContainer
	scroll.scroll_vertical=0
	preview_actor = null
	var heading := S.line(details)
	heading.add_child(S.label(_name_of(id),23,S.GOLD))
	S.fill(heading)
	heading.add_child(S.label("已记录" if _recorded(id,morph) else "尚未记录",16,S.MINT if _recorded(id,morph) else S.FAINT))
	if category == "采集手记":
		_gathering(id)
		return
	if category == "地点与航线":
		var text: String
		if WRECKS.has(id):
			text = {"ferry":"从南岸码头出发，沿浮标绳寻找旧渡船。穿过破损船舷可以找到遗落的箱子。",
				"pump":"浅水泵站下方留着管线与罐体。下潜前先在水面补足氧气。",
				"bridge":"湖里的残存桥墩连成一线。沿桥跨搜索，留出返回水面的氧气。"}[id]
		else:
			text = str(session.catalog.sites[id].note) if _recorded(id) else "靠近这个地点即可完成踏查。探索过的地块会在地图上显现。"
		details.add_child(S.label(text,18,S.TEXT,true))
		if session.stream.generator.revision >= 2:
			S.rule(details)
			details.add_child(S.label("南岸航线",20,S.MINT))
			details.add_child(S.label("南岸码头的小艇需要修复。沿橙旗浮标航行可打捞物资，沉没遗址需要离船下潜。",17,S.MUTED,true))
		return
	var stage := Stage.new()
	stage.custom_minimum_size.y=clampf(get_viewport_rect().size.y*0.34,200,300)
	details.add_child(stage)
	var water_model: Node3D
	if AQUATIC.has(id):
		water_model=_water_model(stage,id,morph,appearance.w)
	else:
		var actor := WastelandCreature.new()
		stage.scene.add_child(actor)
		actor.configure(session.hordes)
		actor.revive(id,Vector3.ZERO,false,{"morph":morph,"look_index":appearance.x,"wardrobe_index":appearance.y,"limb_index":appearance.z,"face_variant":appearance.w})
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.rotation.y = -0.96 if category == "野生动物" else -0.42
		stage.study_creature(actor)
		actor._pose(0.05,35)
		preview_actor = actor
		var height := float(actor.spec.height)
		stage.frame(maxf(0.85,height*1.25),height*0.51)
	var forms: Array = ["","armored","swift"] if category == "感染者" else ["","young","local"]
	if id == "heron": forms = ["","young"]
	if id in ["lake_fish","pond_turtle","crayfish"]: forms = ["","local"]
	var controls := S.line(details)
	for form: String in forms:
		var label: String = FORMS[form]
		if id == "lake_fish": label = "银鳞" if form == "" else "斑纹"
		if id == "heron": label = "冠羽成鸟" if form == "" else "褐羽幼鸟"
		if id == "pond_turtle": label = "青甲" if form == "" else "金纹"
		if id == "crayfish": label = "赤褐" if form == "" else "青壳"
		controls.add_child(S.button(label,func(): _select.call_deferred(id,form),form == morph))
	if category=="感染者":
		var picker:=LookPicker.new()
		details.add_child(picker)
		picker.setup(preview_actor,stage)
	else:
		face_selector=FaceSelector.new()
		controls.add_child(face_selector)
		face_selector.setup(water_model if water_model!=null else preview_actor,id,morph,appearance.w)
	var clue: String = AQUATIC[id].hint if AQUATIC.has(id) else session.catalog.enemies[id].ecology.hint
	details.add_child(S.label(clue,16,S.TEXT,true))
	if category == "感染者" and session.catalog.enemies[id].has("salvage"):
		var material: String = session.catalog.enemies[id].salvage
		details.add_child(S.label("可回收 · %s ×1–2" % session.catalog.items[material].name,15,S.MINT,true))
	var how := "击败该形态可留下记录。" if category == "感染者" else "在野外对准目标，按 [%s] 记录观察。" % session.options.action_name("use")
	details.add_child(S.label(how,15,S.MUTED,true))
	if id in WastelandHordes.WILDLIFE:
		var notes:=preload("res://game/sim/nature_journal.gd").lines(session,id)
		details.add_child(S.label("野外日志",17,S.GOLD))
		if notes.is_empty():
			details.add_child(S.label("在野外观察动物，或对准它的足迹按交互，记录地点、时刻和行进方向。",15,S.MUTED,true))
		else:
			details.add_child(S.label("\n".join(notes),15,S.TEXT,true))

func _gathering(id: String) -> void:
	selected_gathering = id
	gathering_count = _gathering_count()
	details.add_child(S.label("已采集 %d / %d" % [gathering_count,GATHERING.size()],17,S.MINT))
	details.add_child(S.label(GATHERING[id][0],18,S.TEXT,true))
	S.rule(details)
	var tools := S.line(details)
	tools.add_child(S.label("推荐工具",17,S.MUTED))
	if WastelandSession.HARVEST_TOOLS.has(id): _gather_item(tools,WastelandSession.HARVEST_TOOLS[id])
	else: tools.add_child(S.label("徒手拾取",16,S.TEXT))
	var yields := S.line(details)
	yields.add_child(S.label("可获物资",17,S.MUTED))
	for product: String in WastelandSession.RESOURCES[id][2]:
		_gather_item(yields,product)
	details.add_child(S.label(GATHERING[id][1],17,S.TEXT,true))
	if id=="fallen_stick": details.add_child(S.button("查看树苗与种植",_sapling_note))
	if not _recorded(id):
		details.add_child(S.label("在野外采到第一份样本，即可记入本世界的手记。",15,S.MUTED,true))

func _gather_item(row: Control, id: String) -> void:
	var icon := TextureRect.new()
	icon.texture = WastelandItemArt.icon(id,session.catalog.items[id])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44,44)
	row.add_child(icon)
	row.add_child(S.label(session.catalog.title(id),17,S.TEXT))

func _gathering_count() -> int:
	var amount := 0
	for id: String in GATHERING:
		if _recorded(id): amount += 1
	return amount

func _process(delta: float) -> void:
	if category=="采集手记" and is_visible_in_tree() and _gathering_count()!=gathering_count:
		_populate(category)

func _water_model(stage: Stage, id: String, morph: String, face:int) -> Node3D:
	var wildlife: WastelandLakeWildlife = session.stream.lake_wildlife
	var model := wildlife.preview_model(stage.scene,id,morph,face)
	model.rotation.y = -0.62
	if id == "heron":
		stage.frame(1.68 if morph == "young" else 2.08,0.70 if morph == "young" else 0.89)
	elif id in ["pond_turtle","crayfish"]:
		model.rotation = Vector3(-0.30,-0.55,0)
		stage.frame(1.25 if id=="pond_turtle" else 0.82,0.08)
	else:
		stage.frame(0.65,0)
	return model
