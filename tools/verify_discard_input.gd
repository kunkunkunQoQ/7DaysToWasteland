extends "res://tools/verify_touch_controls.gd"

func frames(n:int)->void:
	for i in n: await physics_frame

func g_key(down:bool,echo:=false)->void:
	var event:=InputEventKey.new()
	event.keycode=KEY_G
	event.physical_keycode=KEY_G
	event.pressed=down
	event.echo=echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(3)

func drops_of(id:String)->int:
	var total:=0
	for row:Dictionary in game.session.fx.drop_records.values():
		total+=int(row.items.get(id,0))
	return total

func run()->void:
	WastelandSave.root_override="user://verification/discard-%d"%OS.get_process_id()
	game=load("res://main.tscn").instantiate()
	game.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(game)
	var cfg:Dictionary=game._default_config()
	cfg.seed=2817
	cfg.spawn_roll=17
	game._enter_world(cfg,{},1,false)
	game.close_overlay()
	for child in game.hud.get_children():
		if child.get_script()==preload("res://game/ui/touch_controls.gd"): pad=child
	if not pad:
		pad=preload("res://game/ui/touch_controls.gd").new()
		pad.setup(game)
		game.hud.add_child(pad)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(3)
	var s:WastelandSession=game.session
	var bag:=s.bag
	var start_count:=s.fx.serial
	await g_key(true)
	await g_key(false)
	check(s.fx.serial==start_count,"G with empty hands leaves the world empty")
	bag.add("stone",5)
	bag.add("wood",3)
	bag.assign("stone",0)
	bag.active=0
	await g_key(true)
	await g_key(true,true)
	await frames(8)
	await g_key(false)
	check(bag.count("stone")==4 and drops_of("stone")==1,"held G and keyboard repeat throw exactly one stone")
	var hand:=s.player.global_position
	var direction:Vector3=-s.player.eyes.global_basis.z
	if s.fx.serial>start_count:
		var row:Dictionary=s.fx.drop_records[str(s.fx.serial)]
		check((Vector3(row.point)-hand).dot(direction)>0.4,"discard moves forward from the survivor")
	game.open_panel("bag")
	game.panels.selection="wood"
	game.panels._bag_details()
	await g_key(true)
	await g_key(false)
	check(bag.count("wood")==2 and bag.count("stone")==4 and drops_of("wood")==1,"backpack G drops the highlighted item once")
	game.close_overlay()
	await frames(3)
	for left:bool in [false,true]:
		game.options.touch_left_handed=left
		game.options.touch_control_scale=1.15 if left else 0.85
		pad._layout()
		check(not pad.layout.has("discard"),"discard stays out of the normal combat layout")
		toggle_more()
		var box:Rect2=pad.layout.discard
		check(pad.expanded and pad.bounds.encloses(box) and not box.intersects(pad.layout.inventory),"More reveals an in-bounds discard target separate from inventory")
		var center:=box.get_center()
		var away:=center+Vector2.DOWN*(box.size.y+10)
		tap(3,center,true)
		drag(3,center,away)
		drag(3,away,center)
		tap(3,center,false)
		tap(4,center,true)
		tap(4,center,false,true)
		var before:=bag.count("stone")
		await frames(4)
		check(bag.count("stone")==before,"sliding out or canceling a touch preserves the stack")
		tap(5,center,true)
		await frames(5)
		check(bag.count("stone")==before,"holding discard waits for release")
		tap(5,center,false)
		await frames(5)
		check(bag.count("stone")==before-1 and bag.count("stone")+drops_of("stone")==5,"one deliberate release removes one held item")
		toggle_more()
	await g_key(true)
	await g_key(false)
	await g_key(true)
	await g_key(false)
	check(bag.count("stone")==1 and drops_of("stone")==4,"last held item waits for confirmation")
	await g_key(true)
	await g_key(false)
	check(bag.count("stone")==0 and drops_of("stone")==5,"confirmed last stone reaches the world")
	bag.add("beacon_log",1)
	bag.assign("beacon_log",0)
	await g_key(true)
	await g_key(false)
	check(bag.count("beacon_log")==1 and drops_of("beacon_log")==0,"G protects mission items")
	await finish()
