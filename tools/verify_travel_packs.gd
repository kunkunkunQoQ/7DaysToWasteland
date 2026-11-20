extends "res://tools/verify_expeditions.gd"

func craft(s:WastelandSession,id:String)->void:
	var recipe:Dictionary=s.catalog.recipes[id]
	for item:String in recipe.inputs: s.bag.add(item,recipe.inputs[item])
	var before:=s.bag.counts.duplicate()
	s.ui_command("craft",[id,1,null])
	if s.hand_queue.is_empty():
		check(false,"craft started "+id)
		return
	s.clock.elapsed=float(s.hand_queue[0].done)+0.1
	s._finish_crafting()
	var consumed:=true
	for item:String in recipe.inputs: consumed=consumed and s.bag.count(item)==int(before[item])-int(recipe.inputs[item])
	check(consumed and s.bag.count(id)==1,"completed recipe consumes declared materials for "+id)

func dropped(s:WastelandSession,id:String)->int:
	var sum:=0
	for record:Dictionary in s.fx.drop_records.values(): sum+=int(record.items.get(id,0))
	return sum

func run()->void:
	WastelandSave.root_override="user://verification/backpacks-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.terrain_revision=2
	app._enter_world(cfg,{},1,false)
	var s:WastelandSession=app.session
	s.simulation_paused=true
	check(s.bag.capacity()==27 and s.bag.counts.is_empty(),"new character starts empty with exactly 27 slots")
	var legacy:=WastelandBag.new(s.catalog,{"counts":{"sledge":36}})
	check(legacy.count("sledge")==36 and legacy.capacity()==27 and legacy.add("stone",1)==0,"legacy 36 occupied stacks survive without making new slots")
	legacy.spend({"sledge":10})
	check(legacy.add("sledge",2)==1 and legacy.occupied()==27,"after withdrawal legacy storage contracts to 27")
	for id:String in ["canvas_pack","expedition_pack"]: craft(s,id)
	var bag:=s.bag
	s.ui_command("consume",["canvas_pack"])
	check(bag.capacity()==36 and bag.gear.pack=="canvas_pack","wearing small pack adds one row")
	bag.add("meme_tail",1)
	s.ui_command("consume",["meme_tail"])
	bag.add("torch",1)
	bag.set_offhand("torch")
	s.ui_command("consume",["expedition_pack"])
	check(bag.capacity()==45 and bag.gear.pack=="expedition_pack" and bag.gear.back=="meme_tail" and bag.offhand=="torch","large pack coexists with independent back accessory and offhand")
	var avatar:=WastelandPartyAvatar.new()
	root.add_child(avatar)
	avatar.wear_loadout(bag.gear)
	check(avatar.equipment.get_node("WornPack").mesh==WastelandItemArt.mesh("expedition_pack",{}) and avatar.equipment.has_node("meme_tail"),"worn pack model coexists with tail")
	check(WastelandItemArt.icon("expedition_pack",s.catalog.items.expedition_pack).get_image().get_data()!=WastelandItemArt.icon("canvas_pack",s.catalog.items.canvas_pack).get_image().get_data(),"two packs have different rendered inventory icons")
	var load_count:=45-bag.occupied()
	check(bag.add("sledge",80)==load_count and bag.occupied()==45,"only 45 stacks fit largest pack")
	s.ui_command("consume",["canvas_pack"])
	check(bag.capacity()==36 and bag.occupied()==45 and bag.add("stone",1)==0,"equipping a smaller pack preserves overfull contents")
	s.ui_command("consume",["expedition_pack"])
	check(s.save_now(false)==OK,"full large pack saved")
	var saved:=WastelandSave.read(1)
	app._enter_world(saved.settings,saved,1,false)
	s=app.session
	s.simulation_paused=true
	bag=s.bag
	check(bag.occupied()==45 and bag.capacity()==45 and bag.offhand=="torch","disk reload restores contents, pack and other slots")
	s.stream.ensure_landing(Vector3(-16,3,48))
	var chunk:WastelandChunk=s.stream.active[WastelandSite.SHORE_CELL]
	var key:String=chunk.supply_caches.keys()[0]
	var body:StaticBody3D=chunk.supply_caches[key].get_parent()
	s.player.global_position=body.global_position+Vector3.BACK
	s._open_loot(body)
	s.ui_command("chest_put",[key,"expedition_pack",1])
	check(bag.capacity()==27 and bag.count("sledge")==load_count and s.chest_view(key).items.expedition_pack==1,"stowing the worn pack preserves every other carried stack")
	s.ui_command("chest_take",[key,"expedition_pack",1])
	check(bag.count("expedition_pack")==0 and s.chest_view(key).items.expedition_pack==1,"rejected overfull chest withdrawal leaves item in storage")
	s.ui_command("chest_put",[key,"sledge",20])
	s.ui_command("chest_take",[key,"expedition_pack",1])
	check(bag.count("expedition_pack")==1 and not s.chest_view(key).items.has("expedition_pack"),"making room permits taking the same pack exactly once")
	s.ui_command("consume",["expedition_pack"])
	s.ui_command("discard",["expedition_pack"])
	check(bag.count("expedition_pack")==1,"first discard protects the worn pack")
	s.ui_command("discard",["expedition_pack"])
	check(bag.capacity()==27 and dropped(s,"expedition_pack")==1,"discarding worn pack drops one physical item and removes added rows")
	s.ui_command("consume",["canvas_pack"])
	s.player_died()
	check(bag.capacity()==27 and dropped(s,"canvas_pack")==1 and bag.count("sledge")+dropped(s,"sledge")+int(s.stream.chunk_diff(chunk.cell).containers[key].stored.sledge)==load_count,"death clears lost pack while preserving all cargo across bag, chest and drops")
	s.respawn()
	var prior_cans:=dropped(s,"canned")
	bag.add("scrap",8)
	bag.add("sledge",27)
	var before_trade:=bag.count("sledge")
	s.trader_exchange()
	check(bag.count("sledge")==before_trade and bag.count("canned")+dropped(s,"canned")==prior_cans+2 and bag.count("bandage")+dropped(s,"bandage")==1,"trade at capacity preserves existing cargo and any award overflow")
	avatar.free()
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.free()
	print("TRAVEL PACK failures=",fails)
	quit(1 if fails else 0)
