extends SceneTree

var failed := 0
var passed := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, words: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",words)

func run() -> void:
	WastelandSave.root_override="user://verification/loads-%d"%OS.get_process_id()
	var app: Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	app._enter_world(app._default_config(),{},1,false)
	var s: WastelandSession=app.session
	s.simulation_paused=true
	var near:=s.start_position()+Vector3.RIGHT*3
	var base:=Vector3i(floori(near.x),ceili(s.stream.ground_at(near))+4,floori(near.z))
	var coord:=WastelandTerrainGen.chunk_at(Vector2(near.x,near.z))
	var chunk: WastelandChunk=s.stream.active[coord]
	var top:=Vector3(base)+Vector3(0.5,0,0.5)-chunk.position
	for i in 4:
		var point:=top+Vector3(-0.8 if i%2==0 else 0.8,-2.15,-0.8 if i<2 else 0.8)
		WastelandSite._feature(chunk,point,Vector3(0.2,4.1,0.2),Basis.IDENTITY,Color.GRAY,"pier"+str(i),240)
	var deck:=WastelandSite._feature(chunk,top-Vector3.UP*0.05,Vector3(2,0.1,2),Basis.IDENTITY,Color.GRAY,"test-deck",280)
	chunk.support_graph["test-deck"]=[["pier0","pier1"],["pier2","pier3"]]
	for id: String in ["loop-A","loop-B"]:
		WastelandSite._feature(chunk,top+Vector3(3,2,0),Vector3.ONE,Basis.IDENTITY,Color.GRAY,id,90)
	chunk.support_graph["loop-A"]=[["loop-B"]]
	chunk.support_graph["loop-B"]=[["loop-A"]]
	var dropped:=chunk.settle_structures()
	check(dropped.size()==2 and "loop-A" in dropped and "loop-B" in dropped,"a floating loop cannot support itself")
	for i in 3: await physics_frame
	s.bag.add("frame",1)
	s.bag.add("bench",1)
	var construction:=s.construction
	check(construction.place(base,"frame",0,0,s.player.global_position),"a real floor supports a newly placed player block")
	check(construction.place(base+Vector3i.UP,"bench",0,0,s.player.global_position),"a workshop stands on the first block")
	var workshop: Dictionary=construction.blocks[base+Vector3i.UP]
	workshop.out={"brass":3}
	workshop.queue=[{"id":"wire","amount":1,"inputs":{"brass":2},"done":s.clock.elapsed+50}]
	var loot_before:=s.fx.drop_records.keys()
	s.hit_wall(chunk.structures.pier0[0],999)
	check(chunk.structures.has("test-deck") and construction.blocks.has(base+Vector3i.UP),"one intact pair carries the deck and player blocks")
	s.hit_wall(chunk.structures.pier2[0],999)
	check(not chunk.structures.has("test-deck") and deck.collision_layer==0,"loss of the remaining span immediately releases its collision")
	check(not construction.blocks.has(base) and not construction.blocks.has(base+Vector3i.UP),"both player blocks lose their actual floor and collapse")
	var salvaged:=0
	for drop in s.fx.drop_records:
		if drop not in loot_before: salvaged+=int(s.fx.drop_records[drop].items.get("brass",0))
	check(salvaged==5,"collapsed workshop releases finished goods and reserved materials exactly once")
	check(get_nodes_in_group("falling_structure").size()>0,"fallen site surfaces become moving debris")
	check(s.stream.chunk_diff(coord).site_damage.get("test-deck",1)==0,"the cascading damage is recorded on the authoritative map")
	var test_base:=top+Vector3(4,-4,3)
	var anchor:=WastelandSite._feature(chunk,test_base,Vector3(3,0.2,3),Basis.IDENTITY,Color.GRAY,"test-footing",350)
	var taps:Array[Vector2]=[]
	for dx:int in [-1,1]:
		for dz:int in [-1,1]:
			taps.append(Vector2(anchor.global_position.x+dx,anchor.global_position.z+dz))
	chunk.footings["test-footing"]=taps
	var first:=taps[0]
	s.stream.excavate(Vector3(first.x,0,first.y),2.0)
	check(not "test-footing" in chunk.settle_structures(),"one excavated corner leaves sufficient separated bearings")
	for p: Vector2 in taps: s.stream.excavate(Vector3(p.x,0,p.y),2.0)
	s.stream.record_settlement(chunk)
	check(not chunk.structures.has("test-footing") and s.stream.chunk_diff(coord).site_damage["test-footing"]==0,"digging out all bearing stations releases the foundation")
	check(s.save_now(false)==OK and WastelandSave.read(1).diffs[WastelandTerrainGen.grid_key(coord)].site_damage["test-deck"]==0,"cascade is present in the saved world")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.free()
	print("LOAD PATHS ",passed," passed / ",failed," failed")
	quit(1 if failed else 0)
