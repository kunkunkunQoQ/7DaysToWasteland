extends SceneTree

const Art := preload("res://game/art/sapling_art.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	if not condition: failures += 1

func bounds(tree: Node3D) -> AABB:
	var result := AABB()
	for part: MeshInstance3D in tree.get_children():
		if part.visible: result = result.merge(part.transform * part.mesh.get_aabb())
	return result

func run() -> void:
	var item_signatures := {}
	var durations := {}
	for model: String in Art.PROFILES:
		var item := Art.item_mesh(model)
		var facets := item.surface_get_arrays(0)
		var signature := hash([facets[Mesh.ARRAY_VERTEX], facets[Mesh.ARRAY_COLOR]])
		check(not item_signatures.has(signature) and item == Art.item_mesh(model), model + " has a distinctive cached pickup")
		item_signatures[signature] = true
		var days := Art.duration_days(model)
		check(days > 0.0 and not durations.has(days), model + " has its own maturation time")
		durations[days] = true
		for variant in 4:
			var mature := WastelandChunk._nature_mesh(model, variant, true)
			var tree := Art.build(model, variant, mature)
			var previous := bounds(tree).end.y
			var at_planting := previous
			var continuous := true
			var stages := {}
			for frame in range(101):
				var age := float(frame) / 100.0
				Art.update_visual(tree, age)
				var top := bounds(tree).end.y
				continuous = continuous and top >= previous - 0.0005 and top - previous < 0.26
				previous = top
				stages[Art.stage_name(model, age)] = true
			check(at_planting > 0.25 and at_planting < 0.70 and continuous and stages.size() == 5,
				"%s/%d grows continuously through five readable stages" % [model, variant])
			check(tree.adult.mesh == mature and tree.adult.transform.is_equal_approx(Transform3D.IDENTITY)
				and bounds(tree).is_equal_approx(mature.get_aabb()) and is_equal_approx(Art.height(tree), previous),
				"%s/%d joins its original wild-tree silhouette at maturity" % [model, variant])
			tree.free()
	check(Art.item_mesh("snag") == null and Art.duration_days("snag") == 0, "deadwood has no juvenile form")
	quit(1 if failures > 0 else 0)
