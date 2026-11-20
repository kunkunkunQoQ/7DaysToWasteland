extends SceneTree

const PALM := Vector3(0.100,-0.012,-0.290)
const MAIN_GRIPS := {"bow":Vector3(0,-0.003,-0.215),"pistol":Vector3(0,-0.072,0.028),
	"rifle":Vector3(0,-0.072,0.028),"field_crossbow":Vector3(0,-0.061,0.030)}
const SUPPORT_GRIPS := {"bow":Vector3(0,0.071,0.126),"rifle":Vector3(0,0.037,-0.38),
	"field_crossbow":Vector3(0,0.022,-0.231)}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var hands := WastelandHands.new()
	root.add_child(hands)
	var catalog := WastelandCatalog.new()
	var passed := true
	for id: String in MAIN_GRIPS:
		hands.hold(id,catalog.items[id])
		var asset: MeshInstance3D
		for child in hands.model.get_children():
			if child is MeshInstance3D and child != hands.right_hand and child != hands.support_arm and child != hands.muzzle:
				asset = child
				break
		var correct := is_instance_valid(asset)
		if correct:
			for t: float in [0.0,0.5]:
				hands.reload_ratio=t
				hands.animate(0.20,1.0,0.12,0.84,0.0)
				correct = correct and asset.to_global(MAIN_GRIPS[id]).distance_to(hands.right_hand.to_global(PALM)) < 0.003
				if SUPPORT_GRIPS.has(id):
					var contact := Vector3(0.086,0.020,-0.278) if id=="bow" else PALM
					correct = correct and is_instance_valid(hands.support_arm)
					if is_instance_valid(hands.support_arm):
						correct = correct and asset.to_global(SUPPORT_GRIPS[id]).distance_to(hands.support_arm.to_global(contact)) < 0.003
			if id in ["rifle","pistol"]:
				var barrel_tip := Vector3(0,0.104,-0.651*1.03 if id=="rifle" else -0.353*0.87)
				var flash_offset := asset.to_local(hands.muzzle.global_position)-barrel_tip
				correct = correct and absf(flash_offset.x)<0.002 and absf(flash_offset.y)<0.002 and flash_offset.z<0 and flash_offset.z > -0.095
			elif id=="field_crossbow":
				hands.set_loaded_arrow(true)
				correct = correct and hands.crossbow_bolt.get_parent()==asset and hands.crossbow_bolt.visible
		print("RANGED GRIP ",id,": ",correct)
		passed = passed and correct
	hands.queue_free()
	await process_frame
	quit(0 if passed else 1)
