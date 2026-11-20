extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var session:=WastelandSession.new()
	root.add_child(session)
	var cfg:=WastelandSave.default_world()
	cfg.terrain_revision=2
	cfg.seed=WastelandSave.seed_number(cfg.seed_label)
	session.configure(cfg,{},0,WastelandCatalog.new(),WastelandSettings.new())
	session.simulation_paused=true
	var cell:=Vector2i(-2,5)
	var neighbor:=cell+Vector2i.LEFT
	session.stream.ensure_landing(Vector3(cell.x*32+16,0,cell.y*32+16))
	session.stream.ensure_landing(Vector3(neighbor.x*32+16,0,neighbor.y*32+16))
	await session.stream.quiesce()
	var chunk:WastelandChunk=session.stream.active[cell]
	var adjacent:WastelandChunk=session.stream.active[neighbor]
	var map:=chunk.get_world_3d().navigation_map
	var deadline:=Time.get_ticks_msec()+7000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		# Regions first register a temporary mesh, then publish the bake. The
		# first region iteration can still precede the map's edge connection pass.
		if chunk.baked_revision==chunk.nav_revision and adjacent.region.navigation_mesh!=null and NavigationServer3D.region_get_connections_count(chunk.region.get_rid())>0 and NavigationServer3D.region_get_connections_count(adjacent.region.get_rid())>0:
			break
	var nav:=chunk.region.navigation_mesh
	var incidence:={}
	for i in nav.get_polygon_count():
		var face:=nav.get_polygon(i)
		for j in face.size():
			var a:=face[j]
			var b:=face[(j+1)%face.size()]
			var edge:=Vector2i(mini(a,b),maxi(a,b))
			incidence[edge]=int(incidence.get(edge,0))+1
	var manifold:=chunk.baked_revision>0 and incidence.size()>50 and incidence.values().all(func(count):return count<=2)
	var connected:=false
	NavigationServer3D.map_force_update(map)
	for offset in range(3,30):
		var start:=chunk.global_position+Vector3(3,0,offset)
		var end:=start+Vector3.LEFT*7
		start.y=session.stream.ground_at(start)
		end.y=session.stream.ground_at(end)
		var path:=NavigationServer3D.map_get_path(map,start,end,true)
		if path.size()>1 and path[0].distance_to(start)<1.4 and path[-1].distance_to(end)<1.4:
			connected=true
			break
	await session.audio.finish_playback()
	session.queue_free()
	await process_frame
	print("NAVIGATION QA fuel station has manifold baked edges=",manifold," cross-chunk route=",connected)
	quit(0 if manifold and connected else 1)
