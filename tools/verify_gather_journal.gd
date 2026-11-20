extends SceneTree

const Guide := preload("res://game/ui/field_guide.gd")
var failed := 0
var app: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if ok: print("PASS ",message)
	else:
		printerr("FAIL ",message)
		failed += 1

func _open() -> Guide:
	app.open_panel("field")
	var guide: Guide = app.panels.body.get_children().filter(func(n): return n is Guide)[0]
	var tab: Button = guide.find_children("*","Button",true,false).filter(func(n): return n.text=="采集手记")[0]
	tab.pressed.emit()
	return guide

func _summary(guide: Guide, total: int) -> bool:
	var labels := guide.details.find_children("*","Label",true,false)
	return labels.any(func(l): return l.text=="已采集 %d / 7"%total)

func _run() -> void:
	WastelandSave.root_override = "user://verification/gather-journal-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app = load("res://main.tscn").instantiate()
	app.options.storage_path = WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg: Dictionary = app._default_config()
	cfg.terrain_revision=2 # Historic Gray Bay coastal fixture.
	app._enter_world(cfg,{},2,false)
	var session: WastelandSession = app.session
	var guide := _open()
	await process_frame
	_check(_summary(guide,0) and guide.list.get_child_count()==Guide.GATHERING.size()+1,"new world opens the axe guide and undiscovered field entries")
	var found := {}
	for radius in range(5):
		if found.size()==Guide.GATHERING.size(): break
		for z in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(z))!=radius: continue
				var cell := Vector2i(x,z)
				session.stream.ensure_landing(Vector3(x*32+16,0,z*32+16))
				var chunk: WastelandChunk = session.stream.active[cell]
				for body in chunk.decoration_root.get_children():
					var kind: String = body.get_meta("resource","")
					if not Guide.GATHERING.has(kind) or found.has(kind): continue
					var tool: String = WastelandSession.HARVEST_TOOLS.get(kind,"")
					if tool!="": session.bag.add(tool,1)
					session.bag.bar[session.bag.active] = tool
					var previous:=session.fx.drop_records.keys()
					var bag_before:=session.bag.counts.duplicate()
					session._harvest(body,1000.0,3,body.global_position)
					var released:=session.fx.drop_records.keys().filter(func(id):return not previous.has(id))
					_check(not released.is_empty() and session.bag.counts==bag_before,kind+" releases its materials before inventory changes")
					for drop_id:String in released: session.fx.take_drop(drop_id)
					guide._populate("采集手记")
					guide._select(kind)
					found[kind] = true
					var icons := guide.details.find_children("*","TextureRect",true,false)
					_check(guide._recorded(kind) and _summary(guide,found.size()) and icons.size()==(1 if tool=="" else 3) and icons.all(func(n): return n.texture!=null),kind+" collected from a generated node with illustrated products and tool")
				if found.size()==Guide.GATHERING.size(): break
			if found.size()==Guide.GATHERING.size(): break
	_check(found.size()==Guide.GATHERING.size(),"all seven gathering entries encountered")
	session.bag.counts.clear()
	_check(session.save_now(false)==OK,"saved world after spending collection")
	var saved := WastelandSave.read(2)
	app._enter_world(cfg,saved,2,false)
	guide = _open()
	_check(_summary(guide,Guide.GATHERING.size()) and guide.list.get_children().all(func(b): return b.text.ends_with("✓") or b.text.contains("第一把石斧")),"all entries and badges restored from disk with empty inventory")
	guide._populate("野生动物")
	_check(guide.list.get_child_count()>4,"wildlife guide remains accessible")
	await process_frame
	app.queue_free()
	await process_frame
	var finish := Time.get_ticks_msec()+450
	while Time.get_ticks_msec()<finish: await process_frame
	quit(1 if failed else 0)
