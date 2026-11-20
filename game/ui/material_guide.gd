extends VBoxContainer

signal returned

const S := preload("res://game/ui/style.gd")
const ItemSources := preload("res://game/ui/item_sources.gd")
# Order breaks ties between equally short routes, favouring repeatable uses.
const USES := {
	"coal":["冶炼供热","在熔炉或营火点击加煤块，然后点火。一块可以燃烧 100 秒。"],
	"reinforcement_kit":["工事维护","手持加固包，对受损的圆石及以上构件或自建设施交互。"],
	"composite_filter":["水源补给","用手压泵过滤 4 份净水，或到修好的驼站井泵换取 6 份。"],
	"field_service_kit":["载具维护","在受损车辆旁打开维护，每包恢复最多 120 点耐久。"],
	"harvest_skewer":["远征口粮","把自家田里的玉米和土豆串起来烤，远行时食用可以充饥保暖。"],
	"reed_trauma_wrap":["野外救护","远行时处理骨折和出血。"],
	"improvised_shield":["守夜整备","副手持盾抵挡正面攻击，盾面受损后可以重新绑扎。"],
	"heavy_round":["弹药补给","在工作台装填重型弹，为步枪备弹。"],
	"round":["弹药补给","在工作台装填训练弹，为手枪备弹。"],
	"fuel":["动力补给","给发电机或机动载具加油。"],
	"clean_water":["水源补给","装进背包带上路，口渴时饮用。"],
	"herbal_tea":["防寒补给","在营火煮成暖饮，探索雪地时饮用可以补水保暖。"],
	"medkit":["野外救护","消耗一份医疗包，恢复生命、止血并减轻感染。"],
	"antibiotic":["野外救护","外出受感染后可以服用抗生素。"],
	"concrete":["据点扩建","用混凝土混合料把圆石构件升级为钢筋混凝土。"],
	"steel":["据点扩建","用锻钢把钢筋混凝土构件升级为锻钢装甲。"],
	"cobble":["据点扩建","用圆石料把实心木构件升级为圆石构件。"],
	"solar":["据点供电","搭建太阳能板，向驻地电网供电。"],
	"battery":["据点供电","将蓄电池组接入电网，储存电力。"],
	"floodlight":["驻地照明","把聚光灯接入电网，照亮驻地。"],
	"expedition_pack":["远征整备","穿上远行背囊，可用背包格扩展至五行。"],
	"leaf_kindling":["生火取暖","在营火或熔炉选「加引火束」，再点火。每束燃烧 24 秒。"],
	"sun_cape":["防暑装备","穿在上身可削减 60% 热暴露，降低炎热时的额外水耗。"]
}

var catalog: WastelandCatalog
var recipes_by_input: Dictionary = {}
var entries: Dictionary = {}
var details: VBoxContainer
var selected := ""
var sources: ItemSources

func setup(data: WastelandCatalog, initial: String, back_label: String, show_sources := false) -> void:
	catalog = data
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if show_sources:
		sources = ItemSources.new(catalog)
	else:
		for key: String in catalog.recipes:
			for ingredient: String in catalog.recipes[key].inputs:
				if not recipes_by_input.has(ingredient):
					recipes_by_input[ingredient] = []
				recipes_by_input[ingredient].append(key)
	var bar := S.line(self)
	if show_sources:
		var search := LineEdit.new()
		search.name = "ItemSourceSearch"
		search.placeholder_text = "搜索物品名称"
		search.clear_button_enabled = true
		search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search.text_changed.connect(_filter_sources)
		bar.add_child(search)
	else:
		bar.add_child(S.label("材料索引",20,S.MINT))
	S.fill(bar)
	bar.add_child(S.button(back_label,func(): returned.emit()))
	var columns := S.line(self)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail := S.column(columns,4)
	rail.custom_minimum_size.x = 218
	var list := S.scroller(rail)
	var group := ButtonGroup.new()
	for id: String in catalog.items:
		if not show_sources and not catalog.is_material(id): continue
		var button := S.button(catalog.title(id),select_material.bind(id))
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entries[id] = button
		list.add_child(button)
	var article := S.column(columns,6)
	article.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details = S.scroller(article)
	details.add_theme_constant_override("separation",8)
	select_material(initial if entries.has(initial) else "fiber")
	# A link from the bag may target a material beyond the first visible row.
	(list.get_parent() as ScrollContainer).ensure_control_visible.call_deferred(entries[selected])

func _filter_sources(query: String) -> void:
	var text := query.strip_edges().to_lower()
	var first := ""
	for id: String in entries:
		var button: Button = entries[id]
		button.visible = text.is_empty() or catalog.title(id).to_lower().contains(text) or id.contains(text)
		if button.visible and first == "": first = id
	if first == "":
		selected = ""
		_clear_details()
		details.add_child(S.label("没有匹配的物品",18,S.MUTED))
	elif selected == "" or not entries[selected].visible:
		select_material(first)

func use_paths(id: String) -> Array:
	var paths := {id: [id]}
	var pending: Array[String] = [id]
	var cursor := 0
	while cursor < pending.size():
		var current := pending[cursor]
		cursor += 1
		for key: String in recipes_by_input.get(current,[]):
			var product: String = catalog.recipes[key].id
			if paths.has(product): continue
			paths[product] = paths[current] + [product]
			pending.append(product)
	var options: Array = []
	for product: String in USES:
		if paths.has(product): options.append(paths[product])
	# Keep curated order for paths of the same length.
	var routes: Array = []
	var seen := {}
	for length in range(1,pending.size()+1):
		for path: Array in options:
			var group: String = USES[path.back()][0]
			if path.size() == length and not seen.has(group):
				routes.append(path)
				seen[group] = true
		if routes.size() >= 3: break
	return routes.slice(0,3)

func _clear_details() -> void:
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	(details.get_parent() as ScrollContainer).scroll_vertical = 0

func select_material(id: String) -> void:
	selected = id
	entries[id].set_pressed_no_signal(true)
	_clear_details()
	details.add_child(S.label(catalog.title(id),26,S.TEXT))
	if sources != null:
		_show_sources("稳定获取",sources.stable[id],S.MINT)
		_show_sources("随机获取",sources.random[id],S.GOLD)
		return
	for path: Array in use_paths(id):
		var use: Array = USES[path.back()]
		var names := PackedStringArray()
		for step: String in path: names.append(catalog.title(step))
		details.add_child(S.label("%s　%s" % [use[0]," → ".join(names)],18,S.GOLD,true))
		details.add_child(S.label(use[1],17,S.MUTED,true))
	var recipes: Array = recipes_by_input.get(id,[])
	if recipes.is_empty(): return
	S.rule(details)
	details.add_child(S.label("直接使用这种材料的配方",19,S.TEXT))
	for key: String in recipes:
		var recipe: Dictionary = catalog.recipes[key]
		var requirement: String = catalog.STATIONS[recipe.station]
		if not recipe.skill.is_empty():
			requirement += " · %s %d" % [catalog.skills[recipe.skill[0]].name,int(recipe.skill[1])]
		var product := catalog.title(recipe.id)
		var name: String = recipe.get("name",product)
		if not name.contains(product): name += " → " + product
		details.add_child(S.label("%s ×%d　·　%s" % [name,int(recipe.amount),requirement],17,S.MINT,true))
		details.add_child(S.label(catalog.requirements(recipe.inputs),16,S.MUTED,true))

func _show_sources(title: String, rows: PackedStringArray, tint: Color) -> void:
	if rows.is_empty(): return
	details.add_child(S.label(title,19,tint))
	for words in rows:
		details.add_child(S.label(words,17,S.TEXT,true))
