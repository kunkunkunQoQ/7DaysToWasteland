extends "res://tools/verify_equipment.gd"

# Recipe keys are kept separate from output item IDs, e.g. smelt_ore -> ingot.
const ROUTES:={
	"coal":["heat_station"],"stick":["harvest_skewer"],"wood":["iron_axe"],"stone":["cobble","forge"],
	"fiber":["canvas_pack"],"medicinal_herb":["herbal_tea"],"reed_stem":["filter_pump"],
	"iron_ore":["smelt_ore","iron_axe"],"spring":["field_service_kit","service_vehicle"],
	"clay":["brick","concrete","raise_wall"],"sand":["concrete","raise_wall"],
	"scrap":["ingot","floodlight"],"brass":["wire","floodlight"],"lead":["battery"],
	"cloth":["expedition_pack"],"leather":["bicycle"],"parts":["field_glasses"],"wire":["floodlight"],
	"electronics":["solar"],"oil":["fuel","steel","steel_axe"],"mineral":["antibiotic","medkit"],
	"ingot":["steel","steel_axe"],"steel":["steel_axe"],"brick":["concrete","raise_wall"],
	"cobble":["forge"],"concrete":["raise_wall"],"casing":["round"],"powder":["heavy_round"],
	"tape":["taped_service_kit","service_vehicle"],"fuel":["steel","steel_axe"],"packed_snow":["melt_snow"],"field_service_kit":["service_vehicle"]
}
var stations:Dictionary
var executed:Dictionary={}

func craft_batch(key:String,supply_missing:=true)->bool:
	var recipe:Dictionary=session.catalog.recipes[key]
	var bounds:Dictionary={}
	for input:String in recipe.inputs:
		var n:int=recipe.inputs[input]
		if supply_missing and session.bag.count(input)<n: session.bag.add(input,n-session.bag.count(input))
	var cell:Variant=stations[recipe.station]
	heat_station(cell,recipe.inputs)
	var record:Dictionary={} if cell==null else session.construction.blocks[cell]
	for input:String in recipe.inputs: bounds[input]=WastelandSession.Fire.available(session.bag,record,input)-int(recipe.inputs[input])
	var previous:=session.bag.count(recipe.id)
	session.ui_command("craft",[key,1,cell])
	var q:Array=session.hand_queue if cell==null else session.construction.blocks[cell].queue
	if q.is_empty() or q[0].id!=recipe.id: return false
	for input:String in bounds:
		if WastelandSession.Fire.available(session.bag,record,input)!=bounds[input]: return false
	session.clock.elapsed=float(q[0].done)+0.01
	if cell==null: session._finish_crafting()
	else:
		session.construction.simulate(float(recipe.seconds)+0.1)
		session.ui_command("collect",[cell])
	return session.bag.count(recipe.id)==previous+int(recipe.amount)-int(recipe.inputs.get(recipe.id,0))

func run()->void:
	WastelandSave.root_override="user://verification/materials-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/settings.cfg"
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.terrain_revision=2
	app._enter_world(cfg,{},1,false)
	session=app.session
	session.simulation_paused=true
	stations={"hand":null}
	for station:String in ["campfire","bench","forge","chemistry"]: stations[station]=place_station(station)
	for id:String in session.catalog.skills: session.progress.skills[id]=3
	var report:Dictionary={}
	executed["tape"]=craft_batch("tape")
	check(executed.tape,"weave and bind tape at a real workbench")
	executed["taped_service_kit"]=craft_batch("taped_service_kit")
	check(executed.taped_service_kit,"newly crafted tape produces a usable field service kit")
	for id:String in session.catalog.items:
		if not session.catalog.is_material(id): continue
		if not ROUTES.has(id):
			check(false,"missing playable route for "+id)
			continue
		var direct_recipes:Array=[]
		for key:String in session.catalog.recipes:
			var recipe:Dictionary=session.catalog.recipes[key]
			if recipe.inputs.has(id): direct_recipes.append(key)
		var current:=id
		var valid:=true
		for step:String in ROUTES[id]:
			if step=="heat_station":
				var furnace:Dictionary=session.construction.blocks[stations.forge]
				session.bag.add("coal",1)
				var before:=float(furnace.fuel)
				session.ui_command("feed_fire",[stations.forge,"coal"])
				valid=is_equal_approx(float(furnace.fuel)-before,100.0)
				continue
			if step in ["raise_wall","service_vehicle"]:
				valid=valid and current==("concrete" if step=="raise_wall" else "field_service_kit")
				continue
			var recipe:Dictionary=session.catalog.recipes.get(step,{})
			if recipe.is_empty() or not recipe.inputs.has(current):
				valid=false
				break
			if not executed.has(step):
				session.bag.counts.clear()
				executed[step]=craft_batch(step)
			valid=valid and executed[step]
			current=recipe.id
		report[id]={"name":session.catalog.title(id),"direct_recipes":direct_recipes,"tested_route":ROUTES[id],"valid":valid}
		check(valid,"reachable crafted or interactive use for "+id)
	check(report.size()==ROUTES.size(),"coverage matches live catalog")
	test_terminals()
	test_harvest_meal()
	var path:="res://build/qa/material-routes.json"
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(report,"\t",true)+"\n")
	check(f!=null,"write machine-readable usage and route coverage")
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.free()
	print("MATERIAL ROUTES ",report.size()," materials, ",executed.size()," recipes, passed=",passed," failed=",failed)
	quit(1 if failed else 0)

func test_terminals()->void:
	var c:=session.construction
	var cell:Variant=place_station("frame")
	if cell!=null:
		for tier in 3:
			for item:String in c.UPGRADE[tier]: session.bag.add(item,c.UPGRADE[tier][item])
			var before:=session.bag.count("concrete")
			c.upgrade(cell)
			if tier==2: check(c.blocks[cell].tier==3 and session.bag.count("concrete")==before-10,"wall upgrade spends concrete")
	else: check(false,"frame available for concrete upgrade")
	session.vehicle_records["audit_bike"]={"type":"bicycle","point":session.player.position+Vector3.RIGHT*2,"yaw":0.0,"fuel":0.0}
	session._mount_vehicle("audit_bike")
	var bike:WastelandVehicle=session.vehicles.audit_bike
	session._damage_vehicle(bike,30)
	var health:=float(bike.record.hp)
	session.bag.add("field_service_kit",1)
	var prior:=session.bag.count("field_service_kit")
	session.ui_command("repair_vehicle",["audit_bike"])
	check(bike.record.hp>health and session.bag.count("field_service_kit")==prior-1,"maintenance consumes kit and restores vehicle condition")

func test_harvest_meal()->void:
	session.bag.counts.clear()
	var con:=session.construction
	var at:=session.player.position+Vector3(2,0,1)
	at.y=session.stream.ground_at(at)
	for seed:String in ["seed_potato","seed_corn"]:
		at.x+=1
		var cell:=WastelandConstruction.cell_at(at+Vector3.UP*0.13)
		while con.blocks.has(cell) or con.crops.has(cell):
			at.x+=1
			cell=WastelandConstruction.cell_at(at+Vector3.UP*0.13)
		con.till(at)
		session.bag.add(seed,1)
		con.farm(cell,seed)
		session.clock.hours+=36
		con.farm(cell,"")
	check(session.bag.count("corn")>=3 and session.bag.count("potato")>=3,"corn and potatoes from real harvested plots")
	session.bag.add("stick",2)
	for batch in 2:
		check(craft_batch("harvest_skewer",false),"successive campfire skewer from actual crop and stick")
		session.player.hunger=40
		session.player.warm_drink_left=0
		session.ui_command("consume",["harvest_skewer"])
		check(session.player.hunger==73 and session.player.warm_drink_left>=60,"skewer restores hunger and provides warmth")
