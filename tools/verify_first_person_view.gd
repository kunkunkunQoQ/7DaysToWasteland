extends SceneTree

var failures := 0
var app: Node
const Grip:=preload("res://game/art/gripping_hand.gd")

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok: failures += 1

func capture_pose(label: String) -> void:
	for tick in 3: await process_frame
	await RenderingServer.frame_post_draw
	var hand: Image = app.hands_view.get_texture().get_image()
	var box := hand.get_used_rect()
	var center := hand.get_size() / 2
	if "shield" not in label:
		check(box.has_area() and box.position.y > hand.get_height()*0.40, label+" renders below the sight line")
	check(hand.get_pixelv(center).a < 0.05, label+" keeps the crosshair clear")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://build/qa")
		root.get_texture().get_image().save_png("res://build/qa/first-person-"+label+".png")

func check_shield_frame(h:WastelandHands, label:String) -> void:
	await capture_pose(label)
	# Isolate the mesh in the live hands viewport to measure its silhouette.
	var arm:=h.offhand_root.get_child(0) as MeshInstance3D
	arm.hide()
	h.model.hide()
	await RenderingServer.frame_post_draw
	var mask:Image=app.hands_view.get_texture().get_image()
	var rect:=mask.get_used_rect()
	var size:=Vector2(mask.get_size())
	var covered:=0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if mask.get_pixel(x,y).a>0.5: covered+=1
	arm.show()
	h.model.show()
	var extent:=Vector2(rect.size)/size
	var coverage:=covered/(size.x*size.y)
	print("SHIELD ",label," bounds=",rect," viewport=",size," extent=",extent," coverage=",coverage)
	var raised:=h.offhand_block
	check(extent.x>(0.24 if raised else 0.18) and extent.y>(0.53 if raised else 0.40),label+" has a torso-sized silhouette")
	check(coverage>(0.12 if raised else 0.065) and rect.end.x<size.x*0.49,label+" protects the left side and preserves the sight line")

func ray_hits(faces:PackedVector3Array,start:Vector3,direction:Vector3,cutoff:float)->PackedFloat32Array:
	var hits:=PackedFloat32Array()
	for i in range(0,faces.size(),3):
		var point=Geometry3D.ray_intersects_triangle(start,direction,faces[i],faces[i+1],faces[i+2])
		if point!=null and start.distance_to(point)<cutoff: hits.append(start.distance_to(point))
	hits.sort()
	return hits

func check_grip(arm:MeshInstance3D,asset:MeshInstance3D,id:String)->void:
	var item:Dictionary=app.catalog.items[id]
	var into_arm:=arm.global_transform.affine_inverse()*asset.global_transform
	var grip:=Grip.frame(into_arm.basis.y)
	var radius:=Grip.handle_radius(id,item)*asset.scale.x
	check((into_arm*Grip.socket(id,item)).distance_to(grip.origin)<0.001,id+" wraps the item's physical grip point")
	var object_faces:=into_arm*asset.mesh.get_faces()
	var skin_faces:=arm.mesh.get_faces()
	var breadth:float=WastelandPartyAvatar.LIMB_GIRTH[app.session.player.hand.outfit]
	var size:=lerpf(1,breadth,0.36)
	for i in 4:
		var sample:=Grip.finger_path(grip,radius,i,size)[4]
		var radial:Vector3=(sample-grip.origin).slide(grip.basis.y)
		var from:=sample-radial
		var outward:=radial.normalized()
		var object_hits:=ray_hits(object_faces,from,outward,radius+0.009)
		var skin_hits:=ray_hits(skin_faces,from,outward,radius+0.040)
		var touches:=not object_hits.is_empty() and skin_hits.size()>=2
		if touches:
			var surface:=object_hits[-1]
			touches=skin_hits[0]<surface+0.009 and skin_hits[-1]>surface+0.004
		check(touches,"%s finger %d curves into contact with the rendered handle"%[id,i+1])

func run() -> void:
	WastelandSave.root_override="user://verification/hand-view-%d"%OS.get_process_id()
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	if "--touch-controls" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
		app.options.load_options(true)
		app.options.display.full=false
		app.options.save_options()
	root.add_child(app)
	for frame in 5: await process_frame
	var config: Dictionary = app._default_config()
	config.seed=2817
	app._enter_world(config,{},1,false)
	app.close_overlay()
	var s: WastelandSession=app.session
	for tick in 35: await physics_frame
	s.simulation_paused=true
	s.clock.hours=10.0
	s.player.rotation.y+=0.92
	s.atmosphere.sync(s.clock,1.0,s.player.camera.global_position,-s.player.camera.global_basis.z)
	var h:=s.player.hand
	h.hold("",{})
	h.animate(0.4,0,0,0.85,0)
	await capture_pose("idle")
	var wrist:=Vector3(0.129,-0.050,-0.133)
	var right_at:=h.right_hand.transform*wrist
	var left_at:=h.resting_left.transform*wrist
	h.swing_attack(1.0)
	h.animate(0.11,0,0,0.85,0)
	check((h.right_hand.transform*wrist).z<right_at.z-0.22 and (h.resting_left.transform*wrist).z>left_at.z-0.08,"leading fist extends while the other hand guards")
	var shoulder:=h.right_hand.to_global(Vector3(0.129,-0.295,0.76))
	check(app.hands_camera.is_position_behind(shoulder) or not app.hands_view.get_visible_rect().has_point(app.hands_camera.unproject_position(shoulder)),"striking forearm continues beyond the frame")
	await capture_pose("jab")
	h.animate(0.45,0,0,0.85,0)
	s.bag.add("improvised_shield",1)
	s.bag.set_offhand("improvised_shield")
	h.set_offhand("improvised_shield",true,false)
	h.swing_attack(1.0)
	h.animate(0.11,0,0,0.85,0)
	check(not h.resting_left.visible and (h.right_hand.transform*wrist).z<right_at.z-0.22,"left shield keeps the striking hand active on the second punch")
	h.animate(1.5,0,0,0.85,0)
	await check_shield_frame(h,"shield-guard")
	h.set_offhand("improvised_shield",false,false)
	h.animate(0.48,0,0,0.85,0)
	await check_shield_frame(h,"shield-lowered")
	s.bag.add("stone_axe",1)
	s.bag.assign("stone_axe",s.bag.active)
	s.progress.records.erase("first_axe_guide")
	h.hold("stone_axe",s.catalog.items.stone_axe)
	h.animate(0.48,0,0,0.85,0)
	await check_shield_frame(h,"axe-shield-lowered")
	h.set_offhand("improvised_shield",true,false)
	h.animate(0.48,0,0,0.85,0)
	check(h.offhand_root.visible and h.offhand_pose>0.98,"axe and raised shield occupy independent grips")
	var hud:=app.hud as WastelandHUD
	hud.update_notices()
	hud._process(8.0)
	check(hud.objective_until<=hud.blink and hud.area_until<=hud.blink and hud.held_until<=hud.blink,"unchanged trail HUD retires quest, area and item captions")
	await check_shield_frame(h,"axe-shield")
	check_grip(h.offhand_root.get_child(0),h.offhand_prop,"improvised_shield")
	for part in h.model.get_children():
		if part is MeshInstance3D and part.mesh==WastelandItemArt.mesh("stone_axe",s.catalog.items.stone_axe):
			check_grip(h.right_hand,part,"stone_axe")
	h.set_offhand("",false,false)
	h.hold("",{})
	h.swimming=true
	h.animate(0.45,0.7,0,0.85,0)
	check(h.swimming_fingers and h.right_hand.mesh!=WastelandHands.arm_meshes[h.outfit+"/fist"],"swimming opens both fists")
	await capture_pose("swim-stroke")
	await s.stream.quiesce()
	await s.audio.finish_playback()
	app.queue_free()
	for frame in 5: await process_frame
	quit(1 if failures else 0)
