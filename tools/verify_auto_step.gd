extends "res://tools/verify_harvest.gd"

var remote_test:=false
var water_test:=false
var terrain_test:=false
var stage:Node3D
var start:=Vector3(10,24,44)

func solid(at:Vector3,extent:Vector3)->void:
	var body:=StaticBody3D.new()
	body.collision_layer=1 if terrain_test else 2
	if terrain_test: body.set_meta("kind","terrain")
	stage.add_child(body)
	body.position=at
	WastelandLook.collider(body,extent,Vector3.ZERO)

func trial(height:float,depth:float,ceiling:bool,enabled:bool,duck:bool,axis:Vector2)->bool:
	stage=Node3D.new()
	session.add_child(stage)
	solid(start+Vector3(0,-0.15,0),Vector3(8,0.30,9))
	solid(start+Vector3(0,height/2,-1.25-depth/2),Vector3(2,height,depth))
	if ceiling: solid(start+Vector3(0,2.02,-1.48),Vector3(2,0.12,1.63))
	session.options.display.auto_step=not enabled if remote_test else enabled
	if remote_test:
		session.remote_actor=true
		session.network.remote_input={"enabled":true,"auto_step":enabled,"drive":axis}
	var p:=session.player
	p.position=start+Vector3.UP*0.022
	p.rotation=Vector3.ZERO
	p.velocity=Vector3.ZERO
	p.crouch=0.0
	p.reset_water_state()
	await physics_frame
	for i in 6: p._walk(1.0/60,Vector2.ZERO,true)
	if duck: Input.action_press("crouch")
	var max_y:=p.position.y
	var swam:=false
	var max_rise:=0.0
	for i in 44:
		var before:=p.position.y
		p._walk(1.0/60,axis,true)
		max_y=maxf(max_y,p.position.y)
		max_rise=maxf(max_rise,p.position.y-before)
		swam=swam or p.swimming
	if duck: Input.action_release("crouch")
	var cleared:=max_y>start.y+height-0.06 and p.position.z<start.z-1.40
	if water_test: check(swam and max_rise<0.15,"submerged movement floats gradually without stepping onto the block")
	session.remote_actor=false
	stage.free()
	await physics_frame
	return cleared

func run()->void:
	WastelandSave.root_override="user://verification/auto-step-%d"%OS.get_process_id()
	config=WastelandSave.default_world()
	config.terrain_revision=2
	open_world({})
	session.options.storage_path=WastelandSave.root_override+"/step.cfg"
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	session.options.reset_bindings()
	check(await trial(0.5,1.5,false,true,false,Vector2.UP),"forward walk ascends half block")
	check(not await trial(1.0,1.5,false,true,false,Vector2.UP),"full-height wall requires manual jumping")
	check(not await trial(0.52,1.5,true,true,false,Vector2.UP),"low ceiling stops upward sweep")
	check(not await trial(0.52,1.5,false,false,false,Vector2.UP),"disabled option keeps original collision")
	check(not await trial(0.52,1.5,false,true,true,Vector2.UP),"crouching never auto climbs")
	check(not await trial(0.52,0.08,false,true,false,Vector2.UP),"thin rail has no landing footprint")
	check(not await trial(0.52,1.5,false,true,false,Vector2.ZERO),"stationary input never auto climbs")
	check(not await trial(0.52,1.5,false,true,false,Vector2.RIGHT),"lateral input never auto climbs")
	terrain_test=true
	check(await trial(0.39,1.6,false,true,false,Vector2.UP),"low natural-ground collision step also traverses")
	terrain_test=false
	var lan:=WastelandLan.new()
	root.add_child(lan)
	lan.set_process(false)
	lan.set_physics_process(false)
	session.network=lan
	remote_test=true
	check(await trial(0.50,1.5,false,true,false,Vector2.UP),"authority obeys enabled guest override while host setting is off")
	check(not await trial(0.50,1.5,false,false,false,Vector2.UP),"authority obeys disabled guest override while host setting is on")
	remote_test=false
	session.network=null
	lan.free()
	start=Vector3(14,-2.2,-48)
	session.stream.ensure_landing(start)
	water_test=true
	await trial(0.50,1.5,false,true,false,Vector2.UP)
	water_test=false
	await close_world()
	print("AUTO STEP QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)
