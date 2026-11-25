extends SceneTree

var app:Node
var failed:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,what:String)->void:
	if ok: print("PASS ",what)
	else:
		failed+=1
		printerr("FAIL ",what)

func run()->void:
	WastelandSave.root_override="user://verification/chest-storage-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg:Dictionary=app._default_config()
	cfg.terrain_revision=2
	cfg.loot_days=2
	app._enter_world(cfg,{},1,false)
	var s:WastelandSession=app.session
	s.simulation_paused=true
	s.stream.ensure_landing(Vector3(-16,3,48))
	var c:WastelandChunk=s.stream.active[WastelandSite.SHORE_CELL]
	var key:String=c.object_key("container/0")
	var model:Node3D=c.supply_caches[key]
	var body:StaticBody3D=model.get_parent()
	for i in 3: await physics_frame
	for side in 8:
		var outward:=Vector2.from_angle(side*TAU/8)
		var hit_point:=body.global_position
		s.player.global_position=hit_point+Vector3(outward.x*1.3,-s.player.eyes.position.y+0.38,outward.y*1.3)
		s.player.rotation.y=atan2(outward.x,outward.y)
		s.player.pitch=-0.29
		s.player.eyes.rotation.x=s.player.pitch
		if s._interaction_trace().get("collider")==body: break
	check(s._interaction_trace().get("collider")==body,"camera can target actual unopened chest")
	s.progress.skills.scavenger=1
	Input.action_press("use")
	await physics_frame
	s._process_controls(0.01)
	Input.action_release("use")
	check(s.loot_target==body and is_equal_approx(s.loot_full,float(s.catalog.loot[body.get_meta("type")].time)*0.88),"tap arms investigation with scavenger speed bonus")
	s._tick_loot(s.loot_full*0.35)
	check(s.loot_ratio>0 and s.loot_target==body,"investigation advances after button release")
	var heading:=s.player.rotation.y
	s.player.rotation.y+=PI
	s.interaction=s._interaction_trace()
	s._tick_loot(0.05)
	check(not s.loot_target and not model.opened,"looking away cancels before opening")
	s.player.rotation.y=heading
	await physics_frame
	s._use()
	var slot:=s.bag.active
	s.bag.active=(slot+1)%WastelandBag.HOTBAR_SIZE
	s._tick_loot(1.0)
	check(s.loot_target==null and not model.opened,"changing shortcut cancels first search with no loot roll")
	s.bag.active=slot
	s._use()
	var point:=s.player.global_position
	s.player.global_position+=Vector3.RIGHT
	s._tick_loot(1.0)
	check(s.loot_target==null and not model.opened,"moving away cancels the progress even before the next trace")
	s.player.global_position=point
	await physics_frame
	if not preload("res://game/ui/touch_layout.gd").active:
		Input.action_press("alternate")
		await physics_frame
		s._process_controls(0.01)
		Input.action_release("alternate")
		check(s.loot_target==body,"empty-handed secondary click investigates ordinary chest")
	else:
		s._use()
	s._tick_loot(s.loot_full+0.1)
	check(model.opened and not s.bag.occupied(),"continued gaze opens chest without automatic transfer")
	app.close_overlay()
	s.simulation_paused=true
	s._use()
	check(model.opened and s.loot_target==null,"known chest opens immediately on next interaction")
	app.close_overlay()
	s.simulation_paused=true
	if not preload("res://game/ui/touch_layout.gd").active:
		s.bag.add("field_glasses",1)
		s.bag.assign("field_glasses",s.bag.active)
		await physics_frame
		Input.action_press("alternate")
		await physics_frame
		s._process_controls(0.01)
		Input.action_release("alternate")
		check(s.loot_target==null and not model.opened,"secondary input with optics preserves aiming")
		s.bag.spend({"field_glasses":1})
	var diff:=s.stream.edit_chunk(c.cell)
	diff.containers={key:{"items":{"wood":6,"stone":1},"next":3,"earned":false}}
	s.player.global_position=body.global_position+Vector3.BACK
	s._open_loot(body)
	check(model.opened and s.chest_view(key).items.wood==6 and s.bag.count("wood")==0,"opening chest exposes contents without taking them")
	await create_timer(0.35).timeout
	check(absf(model.lid.rotation.x)+absf(model.lid.rotation.y)>1.35,"physical hinge swings fully open")
	s.apply_ui_command("chest_take",[key,"wood",2])
	check(s.bag.count("wood")==2 and s.chest_view(key).items.wood==4,"explicit quantity takes two")
	s.apply_ui_command("chest_put",[key,"wood",1])
	check(s.bag.count("wood")==1 and s.chest_view(key).items.wood==5,"return one item to same stack")
	s.apply_ui_command("chest_take",[key,"wood",-1])
	s.apply_ui_command("chest_take",[key,"wood",0.5])
	s.apply_ui_command("chest_put",["wrong","wood",1])
	check(s.bag.count("wood")==1 and s.chest_view(key).items.wood==5,"reject invalid counts and forged container key")
	var host_bag:=s.bag
	s.bag=WastelandBag.new(s.catalog)
	s.actor_peer_id=2
	s._open_loot(body)
	s.apply_ui_command("chest_take",[key,"stone",1])
	check(s.bag.count("stone")==1 and s.chest_key(2)==key,"second actor sees and takes last stone")
	s.chest_close(key)
	s.actor_peer_id=1
	s.bag=host_bag
	check(model.opened and s.chest_move(key,"take","stone",1)==0,"one viewer leaves other viewer open and final item cannot duplicate")
	s.apply_ui_command("chest_all",[key])
	check(s.bag.count("wood")==6 and s.chest_view(key).items.is_empty(),"all takes remaining contents")
	s.chest_close(key)
	await create_timer(0.35).timeout
	check(not model.opened and absf(model.lid.rotation.length()-1.12)<0.05 and not model.stores.visible,"last viewer leaves the searched empty container visibly ajar")
	s._open_loot(body)
	check(s.chest_view(key).items.is_empty(),"empty container can reopen for storage")
	s.bag.add("bow",1)
	s.bag.magazine["bow"]=1
	s.chest_move(key,"put","bow",1)
	check(s.bag.count("arrow")==1 and not s.bag.magazine.has("bow"),"stowing the last equipped bow returns its nocked arrow")
	s.chest_move(key,"take","bow",1)
	s.bag.add("canvas_pack",1)
	s.ui_command("consume",["canvas_pack"])
	s.bag.add("sledge",26)
	var moved:=s.chest_move(key,"put","sledge",26)
	check(moved==24 and s.chest_view(key).used==24 and s.bag.count("sledge")==2,"24-slot chest leaves overflow in backpack")
	s.player.global_position+=Vector3(10,0,0)
	check(s.chest_move(key,"take","sledge",1)==0,"out-of-reach transfer denied")
	s.player.global_position=body.global_position+Vector3.BACK
	s.chest_move(key,"take","sledge",23)
	s.chest_close(key)
	s.clock.hours+=100
	s._open_loot(body)
	check(s.chest_view(key).items.get("sledge",0)>=1 and diff.containers[key].next==s.clock.day()+2 and s.chest_view(key).items.size()>1,"ordinary restock preserves player property and adds fresh supplies")
	var supplies: Dictionary = s.chest_view(key).items
	var table: Dictionary = s.catalog.loot[s.catalog.sites.lodge.loots[0]]
	var allowed := {"sledge":true}
	for row: Array in table.items:
		if s.hordes.stage() >= int(row[4]): allowed[row[0]] = true
	check(supplies.get("sledge",0) == 1 and allowed.has_all(supplies.keys()) and table.staples.any(func(item): return supplies.has(item)),
		"the retained sledge shares the refilled lake office chest with stage-eligible rescue supplies")
	s.chest_close(key)
	var snapshot:Dictionary=diff.containers[key].duplicate(true)
	s.save_now(false)
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	s.stream.ensure_landing(Vector3(-16,3,48))
	c=s.stream.active[WastelandSite.SHORE_CELL]
	check(s.stream.chunk_diff(c.cell).containers[key]==snapshot and s.chest_lids().is_empty(),"stored goods and stock survive disk reload with closed lid")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
