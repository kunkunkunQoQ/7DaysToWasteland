extends SceneTree

const Lake := preload("res://game/world/lake_wildlife.gd")
const Stage := preload("res://game/ui/model_study.gd")
const TYPES := ["heron","lake_fish","pond_turtle","crayfish"]
const CELL := Vector2i(336,228)

var failures := 0
var lake := Lake.new()

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		print("PASS ",message)
	else:
		failures += 1
		printerr("FAIL ",message)

func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.size = CELL
	var capture := "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	var sheet := Image.create_empty(CELL.x*3,CELL.y*4,false,Image.FORMAT_RGBA8) if capture else null
	for row in TYPES.size():
		var id: String = TYPES[row]
		var actor = lake.preview_model(stage.scene,id,"")
		actor.set_process(false)
		var second = lake.preview_model(stage.scene,id,"")
		if id=="lake_fish":
			check(actor.spine.mesh==second.spine.mesh,"atlas and school can share posterior fish geometry")
		else:
			var body: MeshInstance3D = actor.get_node("Body")
			var bones: Skeleton3D = actor.bones
			check(body.mesh==second.get_node("Body").mesh and body.skin==second.get_node("Body").skin,id+" shares a single skinned surface and bind poses")
			check(body.mesh.get_surface_count()==1 and body.skin.get_bind_count()==bones.get_bone_count(),id+" has a bind pose for every joint")
		second.free()
		var focus := Vector3.UP*0.84 if id=="heron" else Vector3.ZERO
		stage.camera.size = {"heron":2.0,"lake_fish":0.66,"pond_turtle":1.22,"crayfish":0.92}[id]
		stage.camera.position = focus+Vector3(-2.7,0.55,-1.7) if id=="heron" else focus+Vector3(-2.5,1.18,-1.37)
		stage.camera.look_at(focus)
		var previous: Image
		var before: Transform3D
		for col in 3:
			match id:
				"heron":
					actor.pose([2.6,6.95,2.0][col],0.0,[0.0,0.0,1.0][col],-0.12)
					if col==2:
						stage.camera.position = focus+Vector3(-1.0,2.9,-2.8)
						stage.camera.look_at(focus)
				"lake_fish":
					actor.animate([0.15,1.85,4.55][col],0.8)
				_:
					actor.stroke = [0.25,2.55,4.88][col]
					actor.alert = [0.02,0.45,0.94][col]
					actor.animate(4.0,0.0)
			var current: Transform3D
			if id=="lake_fish":
				current = actor.spine.transform*actor.tail.transform
			else:
				var tip: String = {"heron":"Skull","pond_turtle":"PaddleL0","crayfish":"PincerL"}[id]
				current = actor.bones.get_bone_global_pose(actor.bone_ids[tip])
				var natural: MeshInstance3D = actor.get_node("SpeciesFace")
				var head: Transform3D = actor.bones.get_bone_global_pose(actor._head)
				check(natural.transform.is_equal_approx(head*actor._face_bind),id+" face follows skull in pose "+str(col+1))
			if col: check(not before.is_equal_approx(current),id+" moves its terminal joint in pose "+str(col+1))
			before = current
			if capture:
				for frame_index in 3:
					await process_frame
					await RenderingServer.frame_post_draw
				var frame := stage.scene.get_texture().get_image()
				frame.resize(CELL.x,CELL.y)
				frame.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(frame,Rect2i(Vector2i.ZERO,CELL),Vector2i(col*CELL.x,row*CELL.y))
				if col:
					check(previous.compute_image_metrics(frame,false).mean>0.001,id+" pose changes rendered pixels")
				previous = frame
		actor.free()
	var habitat := Lake.Habitat.new()
	stage.scene.add_child(habitat.bird)
	habitat.bird.add_child(habitat.upper)
	habitat.upper.build(false,0)
	habitat.perches = [Vector3.ZERO,Vector3(8,0,0)]
	lake._update_heron(habitat,[],1.0)
	var start := habitat.bird.position
	lake._update_heron(habitat,[],3.5)
	check(habitat.bird.position.distance_to(start)>0.25,"shore bird advances along the perch while stepping")
	var wading := habitat.bird.position
	lake._update_heron(habitat,[wading],3.5)
	check(habitat.flight_start.is_equal_approx(wading),"takeoff starts at the current foot position")
	lake._update_heron(habitat,[],5.15)
	check(habitat.bird.position.y>2.0,"bird clears the bank in flight")
	lake._update_heron(habitat,[],7.12)
	check(habitat.bird.position.distance_to(habitat.perches[1])<0.01,"bird lands at the second perch")
	if capture:
		var target := ProjectSettings.globalize_path("res://build/qa/aquatic-motion.png")
		check(sheet.save_png(target)==OK,"save "+target)
	stage.free()
	lake.free()
	print("AQUATIC MOTION failures=",failures)
	quit(1 if failures else 0)

