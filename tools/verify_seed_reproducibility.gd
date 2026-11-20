extends SceneTree

const CELLS:=[Vector2i(-1,1),Vector2i(2,1),Vector2i(3,-4),Vector2i(-7,11)]
var app:Node
var failed:=0
var checks:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,msg:String)->void:
	checks+=1
	if ok: print("PASS ",msg)
	else:
		failed+=1
		printerr("FAIL ",msg)

func new_world(title:String,phrase:String,style:String)->WastelandSession:
	app.set_appearance(style)
	app.front.creation()
	var edits:Array=app.front.shell.find_children("*","LineEdit",true,false)
	edits[0].text=title
	edits[1].text=phrase
	for control:Button in app.front.shell.find_children("*","Button",true,false):
		if control.text=="进入荒原":
			control.pressed.emit()
			break
	for i in 90:
		await process_frame
		if app.session and not app.session.preview_only and app.session.world_settings.name==title: break
	var s:WastelandSession=app.session
	s.simulation_paused=true
	check(s.world_settings.name==title and s.world_settings.seed_label==phrase and s.player.profile==style,"creation form applies "+title+" seed and survivor")
	return s

func capture(s:WastelandSession,reverse:bool,day:int)->Dictionary:
	var result:={"spawn":WastelandSave.read(s.slot).player.point,"terrain":{},"resources":{},"structure":{},"furniture":{},"chests":{},"loot":{}}
	var cells:=CELLS.duplicate()
	cells.append(WastelandTerrainGen.chunk_at(s.stream.generator.wild_start))
	if reverse: cells.reverse()
	s.clock.hours=(day-1)*24+13.5
	for cell:Vector2i in cells:
		var p:=Vector2(cell*32)+Vector2(16,16)
		s.stream.ensure_landing(Vector3(p.x,0,p.y))
		var chunk:WastelandChunk=s.stream.active[cell]
		var arrays:=chunk.ground_visual.mesh.surface_get_arrays(0)
		result.terrain[cell]=[arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_NORMAL],arrays[Mesh.ARRAY_COLOR]]
		var resources:Dictionary=chunk.small_nature.duplicate(true)
		for node in chunk.decoration_root.get_children():
			if node.get_meta("kind","")=="resource":
				resources[node.get_meta("index")]=[node.get_meta("resource"),node.global_transform,node.get_meta("group")]
		result.resources[cell]=resources
		for id:String in chunk.structures:
			var geometries:Array=[]
			for part:StaticBody3D in chunk.structures[id]:
				var geometry:Array=[part.global_transform]
				for child in part.get_children():
					if child is MeshInstance3D and child.mesh:
						geometry.append([child.transform,hash(child.mesh.get_faces())])
				geometries.append(geometry)
			var key:=chunk.object_key(id)
			result.structure[key]=geometries
			if id.begins_with("furniture/"): result.furniture[key]=geometries
		var ids:=chunk.supply_caches.keys()
		ids.sort()
		if reverse: ids.reverse()
		for id:String in ids:
			var visual:Node3D=chunk.supply_caches[id]
			var body:StaticBody3D=visual.get_parent()
			result.chests[id]=[body.global_transform,visual.global_transform,body.get_meta("type"),body.get_meta("cache_profile"),body.get_meta("finish_variant")]
			s.player.global_position=body.global_position+Vector3.BACK
			s._open_loot(body)
			var contents:=s.chest_view(id)
			if contents.is_empty(): check(false,"open generated chest "+id)
			else: result.loot[id]=contents.items.duplicate()
			app.close_overlay()
			s.simulation_paused=true
	check(result.structure.size()>60 and result.furniture.size()>5 and result.chests.size()>3 and result.loot.size()==result.chests.size(),"nonempty stage and real first stock on day %d: %d structural keys / %d furniture / %d chests"%[s.clock.day(),result.structure.size(),result.furniture.size(),result.chests.size()])
	await s.stream.quiesce()
	await s.audio.finish_playback()
	return result

func run()->void:
	WastelandSave.root_override="user://verification/seed-worlds-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var phrase:="秋霜越过乌桕桥"
	var first:=await capture(await new_world("北行手记",phrase,"ranger"),false,1)
	app._show_title()
	var second:=await capture(await new_world("暖灯小屋",phrase,"medic"),true,23)
	for key in first:
		check(first[key]==second[key],"same seed reproduces "+str(key)+" across character, name, chunk order and opening date")
	app._show_title()
	var other:=await capture(await new_world("第二条河","晚舟落在群山间","surveyor"),false,23)
	for key in ["structure","furniture","chests","loot"]:
		var a:Dictionary={}
		var b:Dictionary={}
		for cell:Vector2i in CELLS:
			var prefix:=WastelandTerrainGen.grid_key(cell)+":"
			for id:String in first[key]:
				if id.begins_with(prefix): a[id]=first[key][id]
			for id:String in other[key]:
				if id.begins_with(prefix): b[id]=other[key][id]
		check(not a.is_empty() and not b.is_empty() and a!=b,"identical site coordinates vary by seed: "+key)
	for key in ["spawn","resources"]:
		check(first[key]!=other[key],"different seed changes "+str(key))
	check(first.terrain[CELLS[3]]!=other.terrain[CELLS[3]],"different seed changes terrain at identical wilderness coordinates")
	app.queue_free()
	for i in 5: await process_frame
	print("SEED REPRODUCIBILITY checks=",checks," failures=",failed)
	quit(1 if failed else 0)
