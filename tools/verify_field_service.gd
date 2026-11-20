extends SceneTree

var app:Node
var s:WastelandSession
var failed:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	if ok: print("PASS ",message)
	else:
		failed+=1
		printerr("FAIL ",message)

func craft(id:String)->void:
	s.ui_command("craft",[id,1,null])
	if not s.hand_queue.is_empty():
		s.clock.advance(s.hand_queue.back().done-s.clock.elapsed+0.1)
		s._finish_crafting()

func run()->void:
	WastelandSave.root_override="user://verification/field-service-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app._enter_world(app._default_config(),{},1,false)
	s=app.session
	s.simulation_paused=true
	for id:String in ["reed_stem","medicinal_herb","leather","spring","oil","scrap","wood","fiber"]:
		s.bag.add(id,5)
	s.bag.add("cracked_shield",1)
	craft("stick")
	craft("rebind_cracked_shield")
	check(s.bag.count("dented_shield")==1 and s.bag.count("cracked_shield")==0,"old timber can become real sticks to repair a cracked shield")
	craft("rebind_dented_shield")
	check(s.bag.count("improvised_shield")==1 and s.bag.count("dented_shield")==0 and s.bag.count("stick")==0,"second shield repair restores the last wear tier")
	craft("reed_trauma_wrap")
	s.player.health=50
	s.player.fracture=90
	s.player.bleed=37
	s.ui_command("consume",["reed_trauma_wrap"])
	check(s.player.fracture==0 and s.player.bleed==5 and s.player.health==57 and s.bag.count("reed_trauma_wrap")==0,"crafted reed wrap heals fracture and blood loss")
	craft("field_service_kit")
	s.vehicle_records["qa"]={"type":"pickup","point":s.player.position+Vector3.RIGHT*3,"yaw":0.0,"fuel":23}
	s._mount_vehicle("qa")
	s.ui_command("repair_vehicle",["qa"])
	check(s.bag.count("field_service_kit")==1,"full vehicle consumes no maintenance supplies")
	s._damage_vehicle(s.vehicles.qa,160)
	s.ui_command("repair_vehicle",["qa"])
	check(s.vehicle_records.qa.hp==205 and s.bag.count("field_service_kit")==0 and s.bag.count("spring")==3,"field parts repair 120 actual durability")
	check(s.save_now(false)==OK,"write repaired expedition equipment")
	var loaded:=WastelandSave.read(1)
	check(loaded.player.fracture==0 and loaded.player.bleed==5 and loaded.vehicles.qa.hp==205 and loaded.bag.counts.improvised_shield==1,"medical effects, repaired truck, and shield survive save roundtrip")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	await process_frame
	print("FIELD SERVICE QA failures=",failed)
	quit(1 if failed else 0)
