extends SceneTree

const SEEDS := [40917,182,-9251]
const REGIONS := ["alpine","canyon","mesa","taiga"]
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, note: String) -> void:
	print(("PASS " if ok else "FAIL ")+note)
	if not ok: failures += 1

func _survey(terrain: Script) -> Dictionary:
	var all := {}
	for region: String in REGIONS: all[region] = []
	for seed_value: int in SEEDS:
		var gen = terrain.new(seed_value,3)
		for z in range(-1550,1551,43):
			for x in range(-1550,1551,43):
				var region: String = gen.region_kind(x,z)
				if not all.has(region): continue
				var cell := WastelandTerrainGen.chunk_at(Vector2(x,z))
				var site: String = gen.site_for(cell)
				var center := Vector2(cell*32)+Vector2(16,16)
				# These are the two actual collision triangles in a one-metre grid square.
				var a: float = gen.ground(x,z,site,center)
				var b: float = gen.ground(x+1,z,site,center)
				var c: float = gen.ground(x,z+1,site,center)
				var d: float = gen.ground(x+1,z+1,site,center)
				if minf(minf(a,b),minf(c,d))<0.15: continue
				all[region].append(rad_to_deg(atan(Vector2(b-a,c-a).length())))
				all[region].append(rad_to_deg(atan(Vector2(d-c,d-b).length())))
	for region: String in REGIONS:
		var samples: Array = all[region]
		samples.sort()
		var n := samples.size()
		var high := samples.bsearch(51.0)
		print("SLOPE %s n=%d median=%.2f p90=%.2f p95=%.2f p99=%.2f above51=%.2f%%" % [region,n,samples[n/2],samples[int(n*0.90)],samples[int(n*0.95)],samples[int(n*0.99)],100.0*(n-high)/n])
	return all

# Look for an ascending line without consulting generator district centres or authored passes.
func _routes(gen: WastelandTerrainGen, region: String) -> Array:
	var candidates := []
	for z in range(-1190,1191,52):
		for x in range(-1190,1191,52):
			var start := Vector2(x+0.3,z+0.6)
			if gen.region_kind(start.x,start.y)!=region: continue
			var start_y := gen.ground(start.x,start.y)
			for j in 12:
				var dir := Vector2.from_angle(j*TAU/12.0)
				var finish := start+dir*94.0
				if gen.region_kind(finish.x,finish.y)!=region: continue
				var gain := gen.ground(finish.x,finish.y)-start_y
				if gain<23.0 or gain>48.0: continue
				var worst := 0.0
				var prior := start_y
				for step in range(2,95,2):
					var at := start+dir*step
					var y := gen.ground(at.x,at.y)
					worst=maxf(worst,absf(y-prior)/2.0)
					if y<0.5 or worst>0.80 or gen.site_for(gen.chunk_at(at))!="":
						worst=10
						break
					prior=y
				if worst<1: candidates.append({"start":start,"finish":finish,"score":worst-0.002*gain})
	candidates.sort_custom(func(a,b): return a.score<b.score)
	return candidates

func _edge_clear(s:WastelandSession, space:PhysicsDirectSpaceState3D, first:Vector2, last:Vector2) -> bool:
	var side := first.direction_to(last).orthogonal()
	for offset in [-0.36,0.0,0.36]:
		var p := first+side*float(offset)
		var q := last+side*float(offset)
		var delta := q-p
		for segment in 2:
			var pa := p+delta*(segment*0.5)
			var pb := pa+delta*((segment+1)*0.5)
			var a := Vector3(pa.x,0,pa.y)
			var b := Vector3(pb.x,0,pb.y)
			a.y=s.stream.ground_at(a)+0.68
			b.y=s.stream.ground_at(b)+0.68
			if absf(a.y-b.y)>pa.distance_to(pb)*0.85: return false
			var ray := PhysicsRayQueryParameters3D.create(a,b,2,[s.player.get_rid()])
			if not space.intersect_ray(ray).is_empty(): return false
	return true

func _trail(s:WastelandSession, start:Vector2,finish:Vector2) -> PackedVector2Array:
	var dir:=start.direction_to(finish)
	var side:=dir.orthogonal()
	var space:=s.player.get_world_3d().direct_space_state
	var choices:Dictionary = {0:PackedVector2Array([start])}
	for step in range(1,20):
		var next := {}
		for lane in [0,-1,1,-2,2,-3,3]:
			var target:=start+dir*minf(94.0,step*5.0)+side*float(lane)*2.7
			for prior_lane in [lane,0,lane-1,lane+1]:
				if not choices.has(prior_lane) or absi(lane-prior_lane)>1: continue
				var path:PackedVector2Array=choices[prior_lane]
				if not _edge_clear(s,space,path[-1],target): continue
				path=path.duplicate()
				path.append(target)
				next[lane]=path
				break
		choices=next
		if choices.is_empty(): return PackedVector2Array()
	return choices.values()[0]

func _walk(s: WastelandSession, region: String) -> void:
	var candidates := _routes(s.stream.generator,region)
	print("ROUTES ",region," ",candidates.size())
	var player := s.player
	for route: Dictionary in candidates.slice(0,20):
		var start: Vector2 = route.start
		var finish: Vector2 = route.finish
		var dir := start.direction_to(finish)
		for distance in range(0,100,6):
			var p := start+dir*distance
			s.stream.ensure_landing(Vector3(p.x,0,p.y))
		await physics_frame
		var trail:=_trail(s,start,finish)
		if trail.is_empty(): continue
		var origin := Vector3(start.x,0,start.y)
		origin.y=s.stream.ground_at(origin)+0.18
		player.position=origin
		player.velocity=Vector3.ZERO
		player.rotation.y=atan2(-dir.x,-dir.y)
		for frame in 12:
			await physics_frame
			player.simulate(1.0/60.0,false)
		var foot := player.position
		Input.action_press("up")
		var grounded := 0
		var steps := 0
		var waypoint := 1
		for frame in 1900:
			await physics_frame
			var here:=Vector2(player.position.x,player.position.z)
			if here.distance_to(trail[waypoint])<0.48 and waypoint<trail.size()-1: waypoint+=1
			var heading:=here.direction_to(trail[waypoint])
			player.rotation.y=atan2(-heading.x,-heading.y)
			player.simulate(1.0/60.0,true)
			steps+=1
			if player.is_on_floor(): grounded+=1
			var now := Vector2(player.position.x,player.position.z)
			if start.distance_to(now)>90.5: break
			if frame>360 and frame%240==0 and start.distance_to(now)<frame*0.028: break
		Input.action_release("up")
		var horizontal := Vector2(player.position.x-foot.x,player.position.z-foot.z).length()
		var rise := player.position.y-foot.y
		print("WALK %s from %s to %s actual horizontal=%.1fm rise=%.1fm floor=%.1f%%" % [region,start,finish,horizontal,rise,100.0*grounded/steps])
		if horizontal>=80.0 and rise>=20.0 and grounded>steps*0.85:
			_check(true,region+" uphill using forward input and original collisions")
			return
	_check(false,region+" available uphill path traversable without jumping")

func _run() -> void:
	var survey := _survey(WastelandTerrainGen)
	for region: String in ["alpine","canyon"]:
		var grades: Array=survey[region]
		_check(grades[int(grades.size()*0.95)]<=41.0,region+" 95th percentile of dry ground slope stays under 41 degrees")
	WastelandSave.root_override="user://verification/mountain-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	var app: Node=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	await process_frame
	var cfg: Dictionary=app._default_config()
	cfg.seed=SEEDS[0]
	app._enter_world(cfg,{},0,false)
	var session: WastelandSession=app.session
	# Advance only the actual character while surveying. Scheduling hostile patrols would mix combat into the slope measurement.
	session.set_physics_process(false)
	session.stream.set_process(false)
	for region: String in ["alpine","canyon"]:
		await _walk(session,region)
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
