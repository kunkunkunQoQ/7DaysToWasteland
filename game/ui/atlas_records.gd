extends RefCounted

const S := preload("res://game/ui/style.gd")
const Stage := preload("res://game/ui/model_study.gd")
const LookPicker := preload("res://game/ui/infected_look_picker.gd")
const Guide := preload("res://game/ui/field_guide.gd")
const Profiles := preload("res://game/core/survivor_profiles.gd")
const Frontier := WastelandTerrainGen.Frontier
const LAND_TEXT := [
	"缓坡上铺着长草，桦树分散在草地与林缘。","冷杉与落叶桦围成密林，林下有成片阴影和灌丛。",
	"山脚散生冷杉，缓坡沿积雪山肩伸向宽阔山口。雪线以上的冰岩间植被稀少。","风向在沙丘上留下长脊。耐旱灌木、仙人掌和零星绿洲分隔沙海。",
	"深浅相间的砂岩在台缘露出层理，岩壁间散生矮灌木。","低洼水塘由苔草和枯木围绕，沿浅水可找到茂密芦苇。",
	"河道切入红岩，两岸岩层阶梯式下降，谷底地势狭长。"]
const BAY_TEXT := [
	"湖岸低地与水草床相连，浅水逐渐向深处倾斜。","黑杉夹着林下灌木，树干之间常有药草和落枝。",
	"灰色岩坡起伏，风化岩块与矿石在较高坡面露头。","焦土上的岩层裸露，坡地间散布矿石。",
	"旧路连接低矮的废弃聚落，沿路能找到金属残骸。"]
const COAST := [
	["creek","回湾溪谷","南岸河道弯入湖湾，近水的低坡沿河向上游延伸。"],
	["ridge","北岸折脊","湖面以北的山脊断续起伏，坡面陡而狭窄。"],
	["steps","西岸岩阶","西岸的岩坡呈现连续台阶，岩石间散生树木。"],
	["sandbar","白沙浅滩","浅滩从岸边平缓伸进湖里，水线外露出沙砾。"]]
const WATER_FORMS := {"heron":["冠羽成鸟","褐羽幼鸟"],"lake_fish":["银鳞","斑纹"],"pond_turtle":["青甲","金纹"],"crayfish":["赤褐","青壳"]}
class PreviewContext extends Node3D:
	var catalog: WastelandCatalog
	var clock := WastelandClock.new()
	var world_settings := {"difficulty":1.0,"zombie_speed":1.0}

static var terrain := WastelandTerrainGen.new(2817,3)
static var centers := {}

static func rows(category:String,catalog:WastelandCatalog)->Array[Dictionary]:
	var list:Array[Dictionary]=[]
	match category:
		"terrain":
			for i in Frontier.NAMES.size():
				list.append(_row(Frontier.NAMES[i],Frontier.TITLES[i],"内陆地貌",LAND_TEXT[i]))
			list.append(_row("oasis","沙漠绿洲","内陆 · 流金沙海","风沙在低处让出一池水面，绿洲水下也能遇到小型动物。"))
			list.append(_row("basin","灰湾湖盆","灰湾 · 全景","北岸山脊、西岸岩阶、南岸河谷围住暮色湖。湖区向林地、高地与旧镇过渡。"))
			for i in WastelandCatalog.BIOMES.size():
				list.append(_row("bay_"+str(i),WastelandCatalog.BIOMES[i],"灰湾 · 生态区",BAY_TEXT[i]))
			for place in COAST: list.append(_row(place[0],place[1],"灰湾 · 沿岸地貌",place[2]))
		"characters":
			for id:String in WastelandPartyAvatar.OUTFITS:
				list.append(_row(id,WastelandPartyAvatar.NAMES[id],WastelandPartyAvatar.ORIGINS[id]+" · "+WastelandPartyAvatar.OUTFITS[id],WastelandPartyAvatar.STORIES[id]))
		"creatures":
			for id:String in catalog.enemies:
				var spec:Dictionary=catalog.enemies[id]
				var animal:bool=spec.get("animal",false)
				var forms:=["","young","local"] if animal else ["","armored","swift"]
				for form:String in forms:
					var row:=_row(id if form=="" else id+"_"+form,spec.name if form=="" else Guide.FORMS[form]+spec.name,("陆生动物" if animal else "感染者")+" · "+Guide.FORMS[form],spec.ecology.hint)
					row.merge({"species":id,"form":form})
					list.append(row)
			for id:String in Guide.AQUATIC:
				var forms:=["","young" if id=="heron" else "local"]
				for i in forms.size():
					var row:=_row(id if i==0 else id+"_"+forms[i],Guide.AQUATIC[id].name+" · "+WATER_FORMS[id][i],"水域动物",Guide.AQUATIC[id].hint)
					row.merge({"species":id,"form":forms[i]})
					list.append(row)
	return list

static func _row(id:String,title:String,subtitle:String,description:String)->Dictionary:
	return {"id":id,"name":title,"subtitle":subtitle,"description":description}

static func detail(category:String,row:Dictionary,catalog:WastelandCatalog,parent:VBoxContainer,appearance:=Vector4i.ZERO)->void:
	var stage:=Stage.new()
	stage.custom_minimum_size=Vector2(0,250)
	parent.add_child(stage)
	parent.add_child(S.label(row.description,17,S.TEXT,true))
	if not stage.is_node_ready():
		stage.ready.connect(_preview.bind(stage,category,row,catalog,parent,appearance),CONNECT_ONE_SHOT)
	else:
		_preview(stage,category,row,catalog,parent,appearance)

static func _preview(stage:Stage,category:String,row:Dictionary,catalog:WastelandCatalog,parent:VBoxContainer,appearance:Vector4i)->void:
	match category:
		"terrain":
			_landscape(stage,row)
			var idx:=Frontier.NAMES.find(row.id)
			if idx>=0: parent.add_child(S.label("地区气温修正  %+.0f°C" % Frontier.TEMPERATURE[idx],16,S.MINT))
		"characters":
			var avatar:=WastelandPartyAvatar.new()
			avatar.show_tag=false
			avatar.apply_outfit(row.id)
			stage.scene.add_child(avatar)
			avatar.rotation.y=-0.20
			stage.follow_pointer(avatar)
			stage.frame_survivor(avatar,"半身")
			var buttons:=S.line(parent)
			for view:String in ["面部","半身","全身"]:
				buttons.add_child(S.button(view,func(): stage.frame_survivor(avatar,view)))
			var stats:Dictionary=Profiles.STATS[row.id]
			parent.add_child(S.label("生命 %d    体力 %d    闭气 %.0f 秒"%[stats.health,stats.stamina,stats.breath],17,S.MINT,true))
			parent.add_child(S.label(WastelandPartyAvatar.DESCRIPTIONS[row.id],16,S.MUTED,true))
		"creatures":
			var id:String=row.species
			var form:String=row.form
			if Guide.AQUATIC.has(id):
				var wildlife:=WastelandLakeWildlife.new()
				var model:=wildlife.preview_model(stage.scene,id,form,appearance.w)
				wildlife.free()
				model.rotation=Vector3(-0.22 if id!="heron" else 0.0,-0.73,0)
				match id:
					"heron": stage.frame(1.68 if form=="young" else 2.08,0.70 if form=="young" else 0.89)
					"lake_fish": stage.frame(0.67,0)
					_: stage.frame(1.25 if id=="pond_turtle" else 0.82,0.08)
				var faces:=preload("res://game/ui/face_selector.gd").new()
				parent.add_child(faces)
				faces.setup(model,id,form,appearance.w)
				return
			var spec:Dictionary=catalog.enemies[id]
			var actor:=WastelandCreature.new()
			stage.scene.add_child(actor)
			var context:=PreviewContext.new()
			context.catalog=catalog
			actor.add_child(context)
			actor.session=context
			actor.type=id
			actor.spec=spec
			actor.morph=form
			actor.look_index=appearance.x
			actor.wardrobe_index=appearance.y
			actor.limb_index=appearance.z
			actor.face_variant=appearance.w
			actor.collider=CollisionShape3D.new()
			actor.collider.shape=actor.capsule
			actor.add_child(actor.collider)
			actor.add_child(actor.rig)
			actor.rig.add_child(actor.skeleton)
			actor._rebuild_model()
			actor.collision_layer=0
			actor.collision_mask=0
			actor.rotation.y=-0.92 if spec.get("animal",false) or id=="crawler" else -0.39
			actor.brain.animal = bool(spec.get("animal",false))
			stage.study_creature(actor)
			actor._pose(0.12,35)
			stage.frame(maxf(0.95,float(spec.height)*1.34),float(spec.height)*(0.35 if form=="young" else 0.49))
			if not spec.get("animal",false):
				var picker:=LookPicker.new()
				picker.name="LookPicker"
				parent.add_child(picker)
				parent.move_child(picker,stage.get_index()+1)
				picker.setup(actor,stage)
			else:
				var faces:=preload("res://game/ui/face_selector.gd").new()
				parent.add_child(faces)
				faces.setup(actor,id,form,appearance.w)
			parent.add_child(S.label("物种基础值    生命 %d    移速 %.1f 米/秒    攻击 %d"%[spec.hp,spec.speed,spec.hit],16,S.MINT,true))
			var note:String={"young":"幼体四肢较短，体型小于成年同类。","local":"地方型具有不同的毛色，体形比常见型略宽。","armored":"披甲型耐久更高，移动较慢。","swift":"迅行型身形瘦长，速度较快，耐久较低。"}.get(form,"")
			if note!="": parent.add_child(S.label(note,16,S.MUTED,true))

static func _center(row:Dictionary)->Vector2:
	var id:String=row.id
	if centers.has(id): return centers[id]
	var at:=Vector2(12,-42)
	if id=="oasis" or id in Frontier.NAMES:
		for x in range(1,13):
			for z in range(-2,3):
				var spot:=terrain.frontier._district(Vector2i(x,z))
				var point:=Vector2(spot.x,spot.z)
				if terrain.region_kind(point.x,point.y)==("desert" if id=="oasis" else id):
					at=point+Vector2(64,-33) if id=="oasis" else point
					centers[id]=at
					return at
	elif id!="basin":
		var closest:=INF
		for x in range(-200,201,8):
			for z in range(-190,191,8):
				if terrain.landform(x,z)!=row.name: continue
				var score:=Vector2(x,z).distance_squared_to(Vector2(12,-42))
				if id.begins_with("bay_") and id!="bay_0" and terrain.ground(x,z)<1.0: continue
				if score<closest:
					closest=score
					at=Vector2(x,z)
	centers[id]=at
	return at

static func _landscape(stage:Stage,row:Dictionary)->void:
	var at:=_center(row)
	var span:=255.0 if row.id=="basin" else 115.0 if row.id in Frontier.NAMES else 68.0
	var patch:=WastelandScenery.new(2817)
	var peak:=-INF
	var low:=INF
	var step:=span/30.0
	var grid:=PackedVector3Array()
	for z in 31:
		for x in 31:
			var local:=Vector2(x*step-span*0.5,z*step-span*0.5)
			var world:=local+at
			var h:=terrain.ground(world.x,world.y)
			grid.append(Vector3(local.x,h,local.y))
			peak=maxf(peak,h)
			low=minf(low,h)
	var center_y:=(peak+low)*0.5
	for z in 30:
		for x in 30:
			var i:=z*31+x
			var a:=grid[i]
			var b:=grid[i+1]
			var c:=grid[i+31]
			var d:=grid[i+32]
			var tint:=terrain.ground_color(at.x+a.x,at.y+a.z,a.y)
			patch.triangle(a,c,b,Vector3.UP,tint)
			patch.triangle(b,c,d,Vector3.UP,tint)
			if minf(minf(a.y,b.y),minf(c.y,d.y))<0 and terrain.water_basin(at.x+a.x,at.y+a.z):
				var water:=Color("#598e98")
				a.y=0.02
				b.y=0.02
				c.y=0.02
				d.y=0.02
				patch.triangle(a,c,b,Vector3.UP,water)
				patch.triangle(b,c,d,Vector3.UP,water)
	var mesh:=MeshInstance3D.new()
	mesh.mesh=patch.commit()
	mesh.material_override=WastelandLook.colored_material()
	stage.scene.add_child(mesh)
	var first:=WastelandTerrainGen.chunk_at(at-Vector2.ONE*span*0.5)
	var last:=WastelandTerrainGen.chunk_at(at+Vector2.ONE*span*0.5)
	var species:={}
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			var cell:=Vector2i(x,z)
			var origin:=Vector2(cell*32)
			for entry:Dictionary in terrain._dressing(cell,origin,origin+Vector2(16,16),terrain.site_for(cell)):
				if entry.id not in ["oak","pine","boulder","brush","cactus"]: continue
				var p:Vector3=entry.point+Vector3(origin.x-at.x,0,origin.y-at.y)
				if maxf(absf(p.x),absf(p.z))>=span*0.50: continue
				var model:String=entry.get("model","")
				if model=="": model=entry.id
				if not species.has(model): species[model]=[]
				species[model].append(Transform3D(Basis(Vector3.UP,entry.angle).scaled(Vector3.ONE*float(entry.scale)),p))
	for model:String in species:
		var transforms:Array[Transform3D]=[]
		transforms.assign(species[model])
		var plants:=WastelandLook.instanced(mesh,WastelandChunk._nature_mesh(model,0,false),transforms)
		plants.material_override=WastelandLook.colored_material()
	stage.camera.size=span*1.46
	stage.camera.far=span*6.0
	stage.camera.position=Vector3(span*0.67,center_y+span*0.75,-span*1.1)
	stage.camera.look_at(Vector3(0,center_y,0))
