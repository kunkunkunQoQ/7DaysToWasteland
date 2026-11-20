extends "res://tools/verify_expeditions.gd"

func traverse(s:WastelandSession,kind:String,hat:bool)->Vector2:
	if hat: s.bag.toggle_gear("alpine_cap")
	var p:=s.player
	p.hunger=100
	p.health=100
	p.hydration=100
	p.body_temp=37
	p.wet=0
	p.survival_tick=0
	p.warm_drink_left=0
	await walk_trail(s,kind)
	var result:=Vector2(37-p.body_temp,100-p.hunger)
	print("%s hat=%s: body temperature fell %.3f C, hunger fell %.3f"%[kind,hat,result.x,result.y])
	return result

func run()->void:
	WastelandSave.root_override="user://verification/pass-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/settings.cfg"
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	app._enter_world(cfg,{},1,false)
	var s:WastelandSession=app.session
	s.simulation_paused=true
	s.bag.add("alpine_cap",1)
	var paths:Dictionary=Sites.survey(s.stream.generator).trails
	var safe:Array=paths.alpine
	var short:Array=paths.alpine_short
	check(safe[0].distance_to(short[0])<0.01 and safe[-1].distance_to(short[-1])<0.01,"both routes connect the same shelter and weather station")
	check(Sites.pass_wind(s.stream.generator,safe[16])<0.1 and Sites.pass_wind(s.stream.generator,short[12])>17,"orange shoulder is sheltered and blue pass is exposed")
	var longer:=await traverse(s,"alpine",false)
	var colder:=await traverse(s,"alpine_short",false)
	var warmer:=await traverse(s,"alpine_short",true)
	check(colder.x>longer.x+0.2,"shorter pass costs more body heat overall")
	check(warmer.x<colder.x-0.1 and warmer.y<colder.y,"actual equipped wool cap reduces heat and hunger loss on shortcut")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.free()
	print("MOUNTAIN PASS failures=",fails)
	quit(1 if fails else 0)
