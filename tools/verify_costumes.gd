extends SceneTree

var failures:=0
var passed:=0
const LOOKS := [
	{"head":"meme_ears","eyes":"meme_shades","muzzle":"meme_whiskers","hands":"meme_claws","back":"meme_tail"},
	{"head":"meme_traffic","body":"meme_duck","feet":"meme_fins"},
	{"head":"meme_pot","body":"meme_alien"},
	{"head":"meme_antenna","back":"meme_tail","hands":"meme_claws"}]
func _initialize()->void: run.call_deferred()

func check(ok:bool,msg:String)->void:
	if ok: passed+=1
	else:
		failures+=1
		printerr("FAIL ",msg)

func run()->void:
	var catalog:=WastelandCatalog.new()
	var bag:=WastelandBag.new(catalog)
	var unique:={}
	var hands:=WastelandHands.new()
	root.add_child(hands)
	for id:String in catalog.items:
		if not id.begins_with("meme_"): continue
		bag.add(id,1)
		var item:Dictionary=catalog.items[id]
		var mesh:=WastelandItemArt.mesh(id,item)
		check(mesh.get_aabb().size.length()>0.12 and not unique.has(mesh) and WastelandItemArt.icon(id,item).get_image().get_used_rect().has_area(),"unique mesh and icon "+id)
		unique[mesh]=true
		hands.hold(id,item)
		check(hands.model.get_child_count()>=2 and hands.model_id==id,"first person holds "+id)
	check(unique.size()==12,"twelve items")
	hands.hide()
	root.size=Vector2i(1620,930)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var studio:=preload("res://game/ui/model_study.gd").new()
	root.add_child(studio)
	studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in LOOKS.size():
		var gear:Dictionary=LOOKS[i]
		for id: String in gear.values(): bag.toggle_gear(id)
		var restored:=WastelandBag.new(catalog,bag.snapshot())
		for slot:String in gear: check(restored.gear.get(slot)==gear[slot],"save worn "+slot)
		var avatar:=WastelandPartyAvatar.new()
		avatar.show_tag=false
		avatar.apply_outfit(["climber","bronx","mechanic","surveyor"][i])
		studio.scene.add_child(avatar)
		avatar.position.x=(1.5-i)*0.90
		avatar.rotation.y=[-0.33,0.18,-0.27,2.51][i]
		avatar.wear_loadout(restored.gear)
		for slot:String in gear: check(avatar.find_child(gear[slot],true,false)!=null,"attached "+gear[slot])
		avatar.wear_loadout({})
		avatar.wear_loadout(restored.gear)
		if i==2:
			var hammer:=MeshInstance3D.new()
			hammer.mesh=WastelandItemArt.mesh("meme_hammer",catalog.items.meme_hammer)
			hammer.material_override=WastelandLook.colored_material()
			avatar.grip.add_child(hammer)
			hammer.rotation.x=1.12
			avatar.act("tool")
			avatar.pose(0.12,0,0)
		for id:String in gear.values(): bag.toggle_gear(id)
		check(bag.gear=={"head":"","body":"","hands":"","feet":""},"undress and retain legacy slots")
	studio.frame(2.25,0.98)
	for tick in 8: await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://build/qa/meme-wardrobe.png")==OK,"save wardrobe lineup")
	print("COSTUME QA passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)
