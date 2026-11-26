extends "res://tools/verify_harvest.gd"

func run() -> void:
	WastelandSave.root_override="user://verification/achievements-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.seed=2817
	config.terrain_revision=3
	open_world({"progress":{"records":{"wood":3}}})
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	session.options.storage_path=WastelandSave.root_override+"/bindings.cfg"
	session.options.reset_bindings()
	var book=session.achievements
	book.refresh()
	check(book.unlocked("twigs"),"old save with wood records receives regular achievement")
	var targets:={}
	var ids:={}
	var valid:=true
	for row:Dictionary in book.entries:
		valid=valid and not ids.has(row.id) and int(row.target)>0
		ids[row.id]=row
		if row.reward!="":
			valid=valid and row.hidden and session.catalog.items.has(row.reward) and not targets.has(row.reward)
			targets[row.reward]=true
	for id:String in ids:
		var seen:={}
		var cursor:=id
		while cursor!="":
			if not ids.has(cursor) or seen.has(cursor):
				valid=false
				break
			seen[cursor]=true
			cursor=ids[cursor].parent
	check(valid and ids.size()==62 and targets.size()==14,"62 distinct acyclic achievements, 14 unique existing secret rewards")
	await close_world()
	open_world({})
	session.options.storage_path=WastelandSave.root_override+"/bindings.cfg"
	session.options.reset_bindings()
	book=session.achievements
	await verify_barehand_wood()
	var recipe:Dictionary=session.catalog.recipes.stone_axe
	for id:String in recipe.inputs: session.bag.add(id,recipe.inputs[id])
	session.ui_command("craft",["stone_axe",1,null])
	session.clock.elapsed+=20
	session._finish_crafting()
	book.refresh()
	check(book.unlocked("first_tools") and session.bag.count("stone_axe")==1,"craft queue issues first-tool achievement")

	var desert:=land("desert")
	session.player.global_position=desert
	session.clock.hours=23
	hold("field_glasses")
	session.player.pitch=1.0
	Input.action_press("alternate")
	sample(3)
	Input.action_release("alternate")
	sample(1)
	Input.action_press("alternate")
	sample(4)
	book.refresh()
	check(not book.unlocked("off_duty"),"interrupted stargazing streak resets")
	sample(3)
	Input.action_release("alternate")
	reward("off_duty")

	var tower:=session.stream.generator.outpost_beacon_cell(session.stream.generator.starting_outpost("foothills"))
	session.player.global_position=Vector3(tower.x*32+16,session.stream.ground_at(Vector3(tower.x*32+16,0,tower.y*32+16)),tower.y*32+16)
	await squats(7)
	reward("contact")
	session.player.global_position=land("taiga")
	hold("wood")
	await squats(8)
	reward("ears")
	session.ui_command("consume",["meme_ears"])
	var track:=Vector3(22,session.stream.generator.ground(22,44)+0.14,44)
	session.stream.ensure_landing(track)
	session.player.position=track
	session.player.velocity=Vector3.ZERO
	await physics_frame
	Input.action_press("crouch")
	Input.action_press("up")
	for i in 2600:
		if i%55==0: session.player.rotation.y+=PI*0.5
		session.player.simulate(1.0/60.0,true)
		if session.progress.records.get("cat_stalk_m",0)>=30: break
	Input.action_release("up")
	Input.action_release("crouch")
	reward("tail")

	var coast:=Vector3(10,3,44)
	session.player.position=coast
	session.stream.ensure_landing(coast)
	var c:=place_nearby("frame",coast)
	if not session.construction.nodes.has(c):
		check(false,"construct frame for inspection")
		await close_world()
		quit(1)
		return
	var block:StaticBody3D=session.construction.nodes[c]
	session.bag.assign("",0)
	await physics_frame
	session.player.camera.global_position=block.global_position+Vector3(0,0,1.3)
	session.player.camera.look_at(block.global_position)
	for i in 7:
		session.player.stamina=session.player.max_stamina()
		session._melee({},1)
	book.refresh()
	check(book.amount("inspect")==7 and not book.unlocked("inspect") and session.construction.blocks.has(c),"seven bare-handed knocks on one frame leave the eighth outstanding")
	session._melee({},1)
	reward("inspect")
	hold("wood")
	session._melee({},1)
	check(session.progress.records.get("inspect_frame")==8,"a strike while holding material adds no inspection progress")
	var fireplace:=place_nearby("campfire",coast)
	hold("potato")
	if session.construction.blocks.has(fireplace):
		session.construction.blocks[fireplace].out={"clean_water":1}
		session.collect_station(fireplace)
	reward("cookhat")

	var fox_at:=coast+Vector3(0,2,0)
	session.hordes._spawn("fox",fox_at,false,{})
	await physics_frame
	session.player.camera.global_position=fox_at+Vector3(0,0.36,1.55)
	session.player.camera.look_at(fox_at+Vector3.UP*0.36)
	session.player.crouch=1
	session._use()
	reward("catvoice")
	hold("")
	for chunk:WastelandChunk in session.stream.active.values():
		for key:String in chunk.small_nature.keys():
			if not chunk.small_nature.has(key): continue
			var row:Dictionary=chunk.small_nature[key]
			if row.resource!="grass": continue
			var p:Vector3=chunk.position+row.bounds.get_center()
			var hit:=chunk.trace_nature(p+Vector3.UP,p-Vector3.UP)
			if not hit.is_empty() and hit.collider.get_meta("resource")=="grass":
				session._harvest(hit.collider,9,0,hit.position)
			if session.progress.records.get("weed_paws",0)>=5: break
		if session.progress.records.get("weed_paws",0)>=5: break
	reward("paws")
	for id in ["meme_whiskers","meme_tail","meme_claws"]: session.ui_command("consume",[id])
	book.refresh()
	check(book.unlocked("catwalk"),"actual four-slot cat outfit unlocks catwalk")

	var p:=session.player
	p.position=Vector3(-1,-1.05,-48)
	p.camera.transform=Transform3D.IDENTITY
	p.rotation.y=0.0
	p.velocity=Vector3.ZERO
	session.stream.ensure_landing(p.position)
	await physics_frame
	hold("filter_pump")
	Input.action_press("down")
	for i in 1800:
		if i%90==0: p.rotation.y+=PI*0.5
		p.simulate(1.0/60.0,true)
		if session.progress.records.get("reverse_swim_m",0)>=15 and session.progress.records.get("swim_pump_s",0)>=8: break
	Input.action_release("down")
	reward("floating")
	reward("reverse")

	session.clock.hours=12
	hold("")
	var road:=Vector3.INF
	for x in range(-70,72,2):
		for z in range(28,100,2):
			if session.stream.generator.road_strength(x,z)>0.80 and session.stream.generator.ground(x,z)>0.5:
				road=Vector3(x,session.stream.generator.ground(x,z)+0.16,z)
				break
		if road.is_finite(): break
	if road.is_finite():
		session.stream.ensure_landing(road)
		await physics_frame
		p.position=road
		p.velocity=Vector3.DOWN*3
		for i in 20:
			p._walk(1.0/60.0,Vector2.ZERO,true)
			if p.is_on_floor(): break
		sample(21)
	reward("signalcone")

	hold("torch")
	session.bag.add("wood",session.bag.stack_size("wood")*session.bag.capacity())
	check(session.bag.occupied()==session.bag.capacity(),"full inventory for final reward")
	p.pitch=1
	session.atmosphere.weather_kind=3
	sample(6)
	book.refresh()
	var drops:=0
	for row:Dictionary in session.fx.drop_records.values(): drops+=int(row.items.get("meme_antenna",0))
	check(book.unlocked("antenna") and book.rewarded("antenna") and drops==1 and session.bag.count("meme_antenna")==0,"storm lantern reward spills once when bag is full")
	check(session.save_now(false)==OK,"save award ledger")
	var snapshot:=WastelandSave.read(1)
	var ledger:Dictionary=session.progress.achieved.duplicate()
	await close_world()
	open_world(snapshot)
	session.achievements.refresh()
	session.achievements.refresh()
	drops=0
	for row:Dictionary in session.fx.drop_records.values(): drops+=int(row.items.get("meme_antenna",0))
	check(drops==1 and session.progress.achieved==ledger,"save reload and repeated refresh never duplicate rewards")
	await close_world()
	print("ACHIEVEMENTS QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)

func verify_barehand_wood()->void:
	await physics_frame
	var tree:StaticBody3D
	for chunk:WastelandChunk in session.stream.active.values():
		if not chunk.standing_trees.is_empty():
			tree=chunk.standing_trees.values()[0]
			break
	if not is_instance_valid(tree):
		check(false,"standing tree available for bare-hand harvest")
		return
	var id:String=tree.get_meta("key")
	var kind:String=tree.get_meta("resource")
	var camera:=session.player.camera
	var original:=camera.transform
	camera.global_position=tree.global_position+Vector3.BACK*1.9
	camera.look_at(tree.global_position)
	for i in 12:
		if tree.collision_layer==0: break
		session.player.stamina=session.player.max_stamina()
		session._melee({},1.0)
	camera.transform=original
	check(session.timber.active.has(id) and session.player.injury.last_source=="bark","bare-handed swings fell a live tree and scrape the player's hands")
	for i in 480:
		if session.timber.active.is_empty(): break
		session.timber.tick(1.0/60.0)
	var logs:Array[String]=[]
	var yield_count:=0
	for key:String in session.fx.drop_records:
		var row:Dictionary=session.fx.drop_records[key]
		if row.has("log_section"):
			logs.append(key)
			yield_count+=int(row.items.wood)
	var book=session.achievements
	book.refresh()
	check(yield_count==int(WastelandSession.RESOURCES[kind][2].wood) and session.bag.count("wood")==0 and book.amount("twigs")==0,"settled wood keeps the tree's full yield on the ground and has no pickup credit yet")
	if logs.is_empty(): return
	var bag:=session.bag
	var filler:=bag.add("sledge",bag.capacity()-1)
	bag.add("wood",bag.stack_size("wood")-2)
	var log_id:=logs[0]
	var first_stack:=int(session.fx.drop_records[log_id].items.wood)
	var moved:=session.fx.take_drop(log_id)
	book.refresh()
	check(moved==2 and session.fx.drop_records[log_id].items.wood==first_stack-2 and book.amount("twigs")==2 and not book.unlocked("twigs"),"a partially collected log credits only the two pieces that fit")
	check(session.fx.take_drop(log_id)==0 and book.amount("twigs")==2,"repeated pickup with a full bag adds no wood progress")
	bag.spend({"sledge":filler})
	for key in logs: session.fx.take_drop(key)
	book.refresh()
	check(book.unlocked("twigs") and session.progress.records.collected_wood==yield_count,"collecting the remaining wood unlocks the achievement and counts every piece once")
	var old_serial:=session.fx.serial
	session.discard("wood")
	if session.fx.serial>old_serial: session.fx.take_drop(str(session.fx.serial))
	check(session.fx.serial==old_serial+1 and session.progress.records.collected_wood==yield_count,"discarding and retrieving the same wood gives no extra credit")
	bag.spend({"wood":bag.count("wood")})

func hold(id:String)->void:
	if id!="" and session.bag.count(id)==0: session.bag.add(id,1)
	session.bag.assign(id,0)
	session.bag.active=0

func sample(seconds:int)->void:
	for i in seconds*4: session.achievements.sample(session.player,0.25,true,Vector2.ZERO)

func reward(id:String)->void:
	session.achievements.refresh()
	var book=session.achievements
	var row:Dictionary=book.by_id[id]
	check(book.unlocked(id) and book.rewarded(id) and book.amount(id)==row.target and session.bag.count(row.reward)==1,"real challenge awards "+id+" once; metric "+str(session.progress.records.get(row.metric,0)))
	book.refresh()

func land(id:String)->Vector3:
	var gen:=session.stream.generator
	for x in range(1,12):
		for z in range(-2,3):
			var center:=gen.frontier._district(Vector2i(x,z))
			if gen.region_kind(center.x,center.z)==id:
				return Vector3(center.x,gen.ground(center.x,center.z)+0.15,center.z)
	return Vector3.ZERO

func squats(count:int)->void:
	for i in count:
		Input.action_press("crouch")
		await physics_frame
		session.player._walk(1.0/60.0,Vector2.ZERO,true)
		Input.action_release("crouch")
		await physics_frame

func place_nearby(id:String,point:Vector3)->Vector3i:
	session.bag.add(id,1)
	for x in range(int(point.x)-3,int(point.x)+4):
		for z in range(int(point.z)-3,int(point.z)+4):
			var y:=session.stream.ground_at(Vector3(x+0.5,0,z+0.5))
			var cell:=Vector3i(x,ceili(y-0.42),z)
			if session.construction.place(cell,id,0,0,session.player.global_position):
				return cell
	return Vector3i(-999,0,-999)
