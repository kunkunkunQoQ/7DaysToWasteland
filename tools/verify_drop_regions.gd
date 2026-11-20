extends "res://tools/verify_frontier_economy.gd"

const SAMPLES := 21
const ORIGIN := Vector3(-31.5, 3.0, -32.5)

# This test can be copied unchanged into a pre-index checkout to collect the
# baseline. The timed network operation is region selection, not serialization.
func records(count: int) -> Dictionary:
	var result := {}
	for i in count:
		# The same camp has 192 scattered piles in both saves. Additional
		# stock stays in distant, previously explored areas.
		var point := ORIGIN + Vector3((i % 16 - 8) * 12, 0, (floori(i / 16.0) - 6) * 12)
		if i >= 192:
			point = ORIGIN + Vector3((i % 83 - 41) * 14, 0, 320 + floori(i / 83.0) * 14)
		result[str(i+1)] = {"point":point,"items":{"stone":1},"resting":true}
	return result

func run() -> void:
	WastelandSave.root_override="user://verification/drop-regions-%d"%OS.get_process_id()
	cfg = WastelandSave.default_world()
	cfg.seed = 2817
	for count in [1000, 10000]:
		enter({"drops":records(count)})
		await s.stream.quiesce()
		s.player.global_position = ORIGIN
		var lan := WastelandLan.new()
		s.network = lan
		profile(count, lan, [ORIGIN])
		lan.host = true
		lan.transport = ENetMultiplayerPeer.new()
		var guests: Array[Vector3] = []
		for i in 5:
			var at := ORIGIN + Vector3.RIGHT.rotated(Vector3.UP, TAU*i/5.0)*72.0
			var member := WastelandLan.MemberState.new(i+2)
			member.survivor = WastelandSurvivor.new()
			s.add_child(member.survivor)
			member.survivor.configure(s, {}, at, false)
			lan.members[member.peer_id] = member
			guests.append(at)
		profile(count, lan, guests)
		var nearest:=eligible(s.fx.drop_live)
		check(s.fx.drop_live.size()==s.fx.DROPS and nearest==s.fx.drop_live.keys().size(),"team-visible records keep 56 nearest physical pickups")
		lan.members.clear()
		s.network = null
		lan.free()
		await leave()
	var dense := {}
	for i in 1000:
		var point := ORIGIN + Vector3(i%20 *0.02,0, floori(i/20.0)*0.01)
		dense[str(i+1)]={"point":point,"items":{"stone":1},"resting":true,"loose_material":true}
	enter({"drops":dense})
	await s.stream.quiesce()
	s.stream.ensure_landing(ORIGIN)
	await physics_frame
	s.player.global_position=ORIGIN
	var single := WastelandLan.new()
	print("DENSE 1000 single-material piles within 0.8 m")
	profile(1000,single,[ORIGIN])
	var before:=s.fx.drop_records.size()
	var transfer_start:=Time.get_ticks_usec()
	s.fx.collect_nearby()
	print("DENSE piles_before_pickup=%d taken=%d pickup_us=%d" % [before,s.bag.count("stone"),Time.get_ticks_usec()-transfer_start])
	if s.fx.has_method("nearby_drops"):
		check(before==ceili(1000.0/s.bag.stack_size("stone")) and s.bag.count("stone")==1000 and s.fx.drop_records.is_empty(),
			"dense consolidation and pickup conserve all 1,000 units at the inventory stack limit")
		await lifecycle()
	single.free()
	await leave()
	print("DROP REGIONS checks=%d failures=%d" % [checks, failures])
	quit(int(failures>0))

func eligible(live: Dictionary) -> int:
	var distances: Array[float]=[]
	for id in s.fx.drop_records:
		var distance:=s.team_distance_squared(s.fx.drop_records[id].point)
		var radius:=72.0 if live.has(id) else 65.0
		if distance<=radius*radius: distances.append(distance)
	distances.sort()
	var result:=0
	for id in live:
		if s.team_distance_squared(s.fx.drop_records[id].point)<=distances[mini(distances.size(),s.fx.DROPS)-1]:
			result+=1
	return result

func region(at: Vector3, lan: WastelandLan) -> Dictionary:
	if s.fx.has_method("nearby_drops"):
		return s.fx.call("nearby_drops",at,142.0)
	return lan._near_records(s.fx.drop_records,at)

func candidate_count(at: Vector3, radius: float) -> int:
	if not s.fx.has_method("_near_buckets"): return s.fx.drop_records.size()
	var total:=0
	for bucket: Dictionary in s.fx.call("_near_buckets",at,radius): total+=bucket.size()
	return total

func profile(count: int, lan: WastelandLan, viewers: Array[Vector3]) -> void:
	s.fx._resync_drops()
	var sync: Array[int] = []
	var regions: Array[int] = []
	for i in SAMPLES+1:
		var start := Time.get_ticks_usec()
		s.fx._resync_drops()
		var split := Time.get_ticks_usec()
		for at in viewers: region(at,lan)
		var end := Time.get_ticks_usec()
		if i>0:
			sync.append(split-start)
			regions.append(end-split)
	sync.sort()
	regions.sort()
	var visits:=0
	for at in viewers: visits+=candidate_count(at,142.0)
	print("PROFILE drops=%d players=%d queries=%d resync_us=%d region_us=%d region_visits=%d" % [
		count,s.living_players().size(),viewers.size(),sync[SAMPLES/2],regions[SAMPLES/2],visits])
	if count!=s.fx.drop_records.size():
		var start:=Time.get_ticks_usec()
		for i in SAMPLES: s.fx._resync_drops()
		print("DENSE steady_resync_mean_us=%d" % ((Time.get_ticks_usec()-start)/SAMPLES))
	for at in viewers:
		check(region(at,lan)==lan._near_records(s.fx.drop_records,at),"regional query matches exact 3D radius")

func lifecycle() -> void:
	var fx: Variant=s.fx
	var p:=Vector3(-32.15,s.stream.ground_at(ORIGIN)+15.0,-32.4)
	s.stream.ensure_landing(p)
	s.stream.ensure_landing(p+Vector3.RIGHT)
	s.player.global_position=p
	fx.add_items(p,{"scrap":3},Vector3.RIGHT*8)
	var moving:=str(fx.serial)
	await physics_frame
	fx._step_drop(fx.drop_live[moving],fx.drop_records[moving],0.08)
	var at: Vector3=fx.drop_records[moving].point
	check(at.x>-32 and fx.nearby_drops(at,0.1).has(moving) and fx.nearby_drops(p,0.1).is_empty(),
		"a moving pile crosses a negative map-cell boundary and leaves its old bucket")
	check(fx.take_drop(moving)==3 and not fx.nearby_drops(at,1.0).has(moving),
		"collection removes the pile from its new bucket")
	var wall:=WastelandLook.solid(s,Vector3(0.08,2,2),p,Color.GRAY)
	await physics_frame
	var separated: Dictionary={}
	for i in 2:
		var id:=str(i+1)
		separated[id]={"point":p+Vector3.RIGHT*(i*0.5-0.25),"items":{"stone":1},"resting":true,"loose_material":true}
	fx.apply_drop_snapshot(separated.duplicate(true))
	fx._resync_drops()
	check(fx.drop_records.size()==2,"a thin wall prevents merging adjacent stationary scrap piles")
	wall.queue_free()
	await physics_frame
	fx._resync_drops()
	check(fx.drop_records.size()==1 and fx.drop_records.values()[0].items.stone==2,"clear adjacent piles can merge across map cells")
	var snapshot: Dictionary=fx.drop_records.duplicate(true)
	var anchor: Dictionary=snapshot.values()[0]
	snapshot["buoy"]={"point":anchor.point,"items":{"stone":1},"buoy":true}
	snapshot["grave"]={"point":anchor.point,"items":{"stone":1},"resting":true}
	snapshot["quest"]={"point":anchor.point,"items":{"beacon_log":1},"resting":true}
	snapshot["discard"]={"point":anchor.point,"items":{"stone":1},"resting":true,"discarded_by":"host"}
	snapshot["leaf"]={"point":anchor.point,"items":{"tree_leaf":1},"resting":true}
	snapshot["log"]={"point":anchor.point,"items":{"wood":5},"resting":true,
		"log_section":{"model":"oak","variant":0,"axis":Vector3.RIGHT,"length":1.0,"radius":0.2}}
	var saved:=snapshot.duplicate(true)
	fx.apply_drop_snapshot(snapshot)
	fx._resync_drops()
	check(fx.nearby_drops(p,2)==saved,"loading preserves special piles, their separate IDs and their counts")
	s.replica=true
	fx.apply_drop_snapshot(separated.duplicate(true))
	fx._resync_drops()
	check(fx.nearby_drops(p,2)==separated and fx.drop_live.size()==2,"new guest snapshots replace missing IDs and never merge authority-owned stock")
	s.replica=false
	s.bag=WastelandBag.new(s.catalog)
	s.bag.add("sledge",s.bag.capacity()-1)
	var limit:=s.bag.stack_size("stone")
	s.bag.add("stone",limit-1)
	fx.apply_drop_snapshot({})
	# Generate through the real resource-drop entry, then check the stationary
	# phase directly; terrain motion is also covered in verify_drop_motion.
	for amount in [limit-3,9,4]:
		s.drop_materials(p,{"stone":amount})
		fx.drop_records[str(fx.serial)].resting=true
	fx._resync_drops()
	var total:=0
	var bounded:=true
	for row: Dictionary in fx.drop_records.values():
		total+=int(row.items.stone)
		bounded=bounded and int(row.items.stone)<=limit
	check(bounded and total==limit+10 and fx.drop_records.size()==2,"real resource drops consolidate without exceeding their stack limit")
	for id: String in fx.drop_records.keys():
		fx.take_drop(id)
		fx.take_drop(id)
	var remainder: Dictionary=fx.drop_records.duplicate(true)
	var left:=0
	for row: Dictionary in remainder.values(): left+=int(row.items.stone)
	check(s.bag.count("stone")==limit and left==total-1,"repeated pickups against a full shared bag leave exact quantities on the ground")
	check(s.save_now(false)==OK,"save after partial pickup")
	var disk:=WastelandSave.read(1)
	await leave()
	enter(disk)
	check(s.fx.drop_records==remainder and s.fx.call("nearby_drops",p,2.0)==remainder and s.bag.count("stone")==limit,
		"reloading rebuilds the spatial lookup with the same IDs and quantities")
