extends SceneTree

const STOCK := {"granary":"seed_stock","garage":"garage_spares","post":"mailbag"}
const FAILURES := {
	"granary":["silo/leg/1/1","silo/deck"],
	"garage":["hoist/upright/0","hoist/winch"],
	"post":["post/bracket","post/blade"]
}
var errors:=0

func _initialize()->void: run.call_deferred()

func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: errors+=1

func nearest(gen:WastelandTerrainGen)->Dictionary:
	var result:={}
	for radius in range(6,60):
		for offset in range(-radius,radius+1):
			for cell:Vector2i in [Vector2i(offset,-radius),Vector2i(offset,radius),Vector2i(-radius,offset),Vector2i(radius,offset)]:
				var site:=gen.site_for(cell)
				if site in STOCK and not result.has(site): result[site]=cell
		if result.size()==STOCK.size(): break
	return result

func install(s:WastelandSession,cell:Vector2i)->WastelandChunk:
	var world:=Vector2(cell*32)+Vector2(16,16)
	s.stream.ensure_landing(Vector3(world.x,0,world.y))
	return s.stream.active[cell]

func layout(c:WastelandChunk)->Array:
	var rows:Array=[]
	for id:String in c.structures:
		if id.begins_with("furniture/"):
			var body:StaticBody3D=c.structures[id][0]
			var mesh:MeshInstance3D=body.get_child(0)
			rows.append([id,Vector2(body.position.x,body.position.z),hash(mesh.mesh.get_faces())])
	return rows

func reachable(s:WastelandSession,c:WastelandChunk)->bool:
	for chest:Node in c.supply_caches.values():
		var body:StaticBody3D=chest.get_parent()
		if not body.has_meta("cache_approach"): continue
		s.player.global_position=body.get_meta("cache_approach")+Vector3.UP*0.18
		s.player.camera.look_at(body.global_position)
		var clearance:=PhysicsShapeQueryParameters3D.new()
		clearance.shape=s.player.stand_shape
		clearance.transform=s.player.capsule.global_transform
		clearance.collision_mask=3
		var obstacles:=s.get_world_3d().direct_space_state.intersect_shape(clearance,1)
		var hit:Node3D=s._interaction_trace().get("collider")
		if hit!=body or not obstacles.is_empty():
			print("Box ",body.position," from ",s.player.global_position-c.position," ray ",hit," obstacles ",obstacles)
			return false
	return true

func run()->void:
	WastelandSave.root_override="user://verification/trade-ruins-%d"%OS.get_process_id()
	var app:Node=load("res://main.tscn").instantiate()
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.start_id="shore"
	var variants:={}
	for seed_value:int in [2817,7399,5112,8801]:
		cfg.seed=seed_value
		app._enter_world(cfg,{},1,false)
		var s:WastelandSession=app.session
		s.simulation_paused=true
		s.set_physics_process(false)
		var cells:=nearest(s.stream.generator)
		var old:=WastelandTerrainGen.new(seed_value,4)
		var stored:={}
		check(cells.size()==3,"three naturally generated trade ruins in the region for seed %d"%seed_value)
		for site:String in cells:
			var c:=install(s,cells[site])
			var rows:=layout(c)
			stored[site]=rows
			if not variants.has(site): variants[site]=[]
			variants[site].append(hash(rows))
			check(old.site_for(c.cell) not in STOCK and c.site==site and c.ruin.condition>0,"old world identity and damaged new "+site)
			check(rows.size()==c.ruin.furniture_bounds.size() and rows.size()>=2,site+" has supported interior work areas")
			var key:=c.object_key("container/0")
			if not c.supply_caches.has(key):
				check(false,site+" lacks its trade stock")
				continue
			var box:StaticBody3D=c.supply_caches[key].get_parent()
			await physics_frame
			await physics_frame
			check(reachable(s,c),site+" all boxes reachable from a clear standing position")
			s.player.global_position=box.get_meta("cache_approach")+Vector3.UP*0.18
			s.player.camera.look_at(box.global_position)
			var hit:Node3D=s._interaction_trace().get("collider")
			if hit!=box:
				print("Expected ",box.global_position," from ",s.player.global_position," hit ",hit.get_meta("site_id",hit.name) if hit else "nothing")
			check(hit==box,site+" stock reachable with survivor's interaction ray")
			s._use()
			if s.loot_target==box: s._tick_loot(s.loot_full+0.01)
			check(box.get_meta("type")==STOCK[site] and s.chest_key()==key and not s.chest_view(key).items.is_empty(),site+" opens specialty stock")
			s.chest_close(key)
			var pair:Array=FAILURES[site]
			check(c.structures.has_all(pair) and c.settle_structures().is_empty(),site+" exterior intact on real bearings")
			if c.structures.has(pair[0]):
				s.hit_wall(c.structures[pair[0]][0],9999)
				check(not c.structures.has(pair[1]),site+" supported exterior falls on demolition")
		check(s.save_now(false)==OK,"save demolished exteriors")
		var saved:=WastelandSave.read(1)
		app._enter_world(saved.settings,saved,1,false)
		s=app.session
		s.simulation_paused=true
		s.set_physics_process(false)
		for site:String in cells:
			var c:=install(s,cells[site])
			check(layout(c)==stored[site] and not c.structures.has(FAILURES[site][1]),site+" geometry and demolition reproduce from disk")
	for site:String in variants:
		check(variants[site][0]!=variants[site][1],site+" room contents vary across world seeds")
	await app.session.stream.quiesce()
	await app.session.audio.finish_playback()
	app.free()
	print("TRADE RUINS errors=",errors)
	quit(1 if errors else 0)
