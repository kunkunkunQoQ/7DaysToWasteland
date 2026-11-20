extends VBoxContainer

const Looks := preload("res://game/art/infected_looks.gd")
const S := preload("res://game/ui/style.gd")
const Stage := preload("res://game/ui/model_study.gd")

var actor: WastelandCreature
var description: Label
var zoom: Button
var condition: Label
var preview_rng := RandomNumberGenerator.new()
var faces:=preload("res://game/ui/face_selector.gd").new()

func setup(subject: WastelandCreature, stage: Stage) -> void:
	actor = subject
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation",6)
	add_child(row)
	if Looks.count_for(actor.type)>0: row.add_child(S.label("外观",16,S.MUTED))
	var choices := ButtonGroup.new()
	for index in Looks.count_for(actor.type):
		var option := S.button(Looks.title(actor.type,index),select_look.bind(index))
		option.toggle_mode = true
		option.button_group = choices
		option.set_pressed_no_signal(index==actor.look_index)
		row.add_child(option)
	row.add_child(S.button("转身",func(): actor.rotate_y(PI*0.5)))
	zoom = S.button("近看",func():
		zoom.text = "看全身" if zoom.button_pressed else "近看"
		frame_actor(stage, zoom.button_pressed))
	zoom.toggle_mode = true
	row.add_child(zoom)
	row.add_child(faces)
	faces.setup(actor,actor.type,actor.morph,actor.face_variant)
	row.add_child(S.button("换个体",func(): sample_individual(stage)))
	frame_actor(stage, false)
	if Looks.count_for(actor.type)>0:
		description = S.label(Looks.description(actor.type,actor.look_index),16,S.MUTED,true)
		add_child(description)
	condition=S.label("",16,S.MINT,true)
	add_child(condition)
	describe_condition()

func frame_actor(stage: Stage, close: bool) -> void:
	var height := float(actor.spec.height)
	if actor.low_crawl() or actor.type=="crawler":
		var level:=height*(0.46 if actor.type=="crawler" else 0.28)
		stage.frame(maxf(0.66,height*(0.64 if close else 1.18)),level)
	else:
		stage.frame(height*(0.68 if close else 1.22),height*(0.72 if close else 0.50))

func appearance() -> Vector4i:
	return Vector4i(actor.look_index,actor.wardrobe_index,actor.limb_index,actor.face_variant)

func sample_individual(stage: Stage) -> void:
	# Browsing the journal never draws from the world's encounter generator.
	actor.wardrobe_index=(actor.wardrobe_index+preview_rng.randi_range(1,actor.WARDROBE_COUNT-1))%actor.WARDROBE_COUNT
	actor.limb_index=actor.InfectedLimbs.roll(preview_rng.randi(),preview_rng.randi())
	actor.face_variant=preview_rng.randi_range(0,1)
	actor._rebuild_model()
	faces.refresh()
	actor.hp=actor.max_health()
	actor._pose(0.08,5)
	frame_actor(stage,zoom.button_pressed)
	describe_condition()

func describe_condition() -> void:
	var labels: Array[String]=[]
	var sections:=[["左手缺失","左前臂残缺"],["右手缺失","右前臂残缺"],["左脚缺失","左小腿残缺"],["右脚缺失","右小腿残缺"]]
	for i in 4:
		var damage:=actor.limb_damage[i]
		if damage>0: labels.append(sections[i][damage-1])
	var movement:="贴地移动" if actor.low_crawl() else "跛行" if actor.limb_damage.z+actor.limb_damage.w>0 else "步行"
	if actor.type=="crawler": movement="爬行"
	var limbs:="四肢完整" if labels.is_empty() else "、".join(labels)
	condition.text="%s  ·  %s  ·  生命上限 %d  ·  移速 %.1f 米/秒"%[limbs,movement,roundi(actor.max_health()),actor.max_move_speed()]

func select_look(index: int) -> void:
	if actor.look_index == index: return
	actor.look_index = index
	actor._rebuild_model()
	actor._pose(0.08,5.0)
	description.text = Looks.description(actor.type,index)
