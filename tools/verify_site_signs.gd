extends SceneTree

const Sites:=preload("res://game/world/expedition_sites.gd")
var app:Node
var session:WastelandSession
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,description:String)->void:
	checks+=1
	if ok: print("PASS ",description)
	else:
		failures+=1
		printerr("FAIL ",description)

func verify_letters(owner:Node,expected:String,area:Vector2,node_name:="PaintedLetters")->Label3D:
	var label:=owner.find_child(node_name,true,false) as Label3D
	check(label!=null,expected+" has a painted surface")
	if not label: return null
	var variant:=label.font as FontVariation
	var source:Font=variant.base_font if variant else label.font
	check(label.text.contains(expected) and source==WastelandUIStyle.FONT,expected+" uses the bundled typeface")
	var font_rid:RID=label.font.get_rids()[0]
	var glyphs:=true
	for i in label.text.length():
		var code:=label.text.unicode_at(i)
		if code!=10 and (code<32 or code>126 or not TextServerManager.get_primary_interface().font_has_char(font_rid,code)):
			glyphs=false
			printerr("Missing glyph ",label.text[i])
	check(glyphs,expected+" uses supported English lettering")
	check(label.get_meta("print_area",Vector2.ZERO).is_equal_approx(area),expected+" fits the actual sign panel design")
	var mesh:=label.generate_triangle_mesh()
	if not mesh:
		check(false,expected+" has a shaped glyph mesh")
		return label
	var inside:=true
	for v:Vector3 in mesh.get_faces():
		if absf(v.x)>area.x*0.5+0.001 or absf(v.y)>area.y*0.5+0.001: inside=false
	check(inside,expected+" rendered glyph geometry fits the inscription area")
	return label

func remove_sign(body:StaticBody3D,text:Label3D)->void:
	if not is_instance_valid(text):return
	session.hit_wall(body,10000)
	await process_frame
	if is_instance_valid(text) and text.is_inside_tree() and text.is_visible_in_tree():
		var piece:=text.get_parent() as RigidBody3D
		check(piece!=null and piece.is_in_group("falling_structure"),"inscription falls with the broken sign")
		await create_timer(4.3,false,true).timeout
	check(not is_instance_valid(text) or not text.is_inside_tree() or not text.is_visible_in_tree(),"destroyed sign clears its inscription")

func capture(label:Label3D,wide:bool,collapsed:=false)->void:
	if not "--capture" in OS.get_cmdline_user_args() or not is_instance_valid(label):return
	var cam:=session.player.camera
	var center:=label.global_position
	var facing:=label.global_basis.orthonormalized()
	var where:=center+facing*(Vector3(4.8,0.5,7.8) if wide else Vector3(0.65,0.03,3.0))
	var target:=center+facing*(Vector3(0,-0.72,-0.85) if wide else Vector3.ZERO)
	cam.top_level=true
	cam.fov=55 if wide else 48
	cam.global_position=where
	cam.look_at(target)
	session.clock.hours=14
	session.atmosphere.sync(session.clock,0,where,-cam.global_basis.z)
	app.hud.hide()
	app.pixel_paint.set_shader_parameter("hands_visible",false)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://build/qa/site-sign-"+("collapse" if collapsed else "ruins" if wide else "detail")+".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))==OK,"capture "+path)

func run()->void:
	WastelandSave.root_override="user://verification/signs-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(WastelandSave.root_override)
	app=load("res://main.tscn").instantiate()
	app.options.storage_path=WastelandSave.root_override+"/options.cfg"
	root.add_child(app)
	var cfg:Dictionary=app._default_config()
	cfg.seed=27491
	cfg.start_id="grassland"
	cfg.site_revision=1
	app._enter_world(cfg,{},1,false)
	session=app.session
	session.simulation_paused=true
	var gen:=session.stream.generator
	var cell:=gen.starting_outpost("grassland")
	var center:=Vector2(cell*32)+Vector2(16,16)
	session.stream.ensure_landing(Vector3(center.x,gen.ground(center.x,center.y),center.y))
	var lodge:WastelandChunk=session.stream.active[cell]
	var sign:StaticBody3D=lodge.structures.sign[0]
	var board:StaticBody3D
	for child in lodge.decoration_root.get_children():
		if child.get_meta("kind","")=="trader": board=child
	var shelter:Vector3=Sites.survey(gen).points.shelter
	await process_frame
	var lintel:=verify_letters(sign,"PRAIRIE STATION",Vector2(float(session.catalog.sites.lodge.span)*0.52,0.38))
	var notice:=verify_letters(board,"STATION NOTICES",Vector2(1.06,0.18))
	verify_letters(board,"MISSING",Vector2(0.25,0.25),"PaperNotice0")
	verify_letters(board,"RATIONS",Vector2(0.25,0.25),"PaperNotice1")
	verify_letters(board,"WANTED",Vector2(0.25,0.25),"PaperNotice2")
	check(WastelandSite.station_name(gen,cell)=="草原驿站","the player's map and dispatch screens retain the localised station name")
	await capture(lintel,true)
	await capture(lintel,false)
	if "--capture" in OS.get_cmdline_user_args():
		session.hit_wall(lodge.structures["ridge/post/4"][0],10000)
		check(not lodge.structures.has("ridge/beam/1") and not lodge.structures.has("roof/timber/1/4") and lodge.structures.has("roof/timber/1/0"),"the near roof span loses its ridge bearing")
		await create_timer(0.85,false,true).timeout
		await capture(lintel,true,true)
	await remove_sign(sign,lintel)
	await remove_sign(board,notice)
	session.stream.ensure_landing(shelter)
	var snow:WastelandChunk=session.stream.active[WastelandTerrainGen.chunk_at(Vector2(shelter.x,shelter.z))]
	var plate:StaticBody3D=snow.structures["expedition/shelter/plate"][0]
	var salvage:=preload("res://game/world/structural_salvage.gd")
	check(salvage.materials(snow,"expedition/shelter/plate").has("scrap") and salvage.materials(snow,"expedition/shelter/post").has("wood"),"expedition sign yields metal from its plate and wood from its post")
	await process_frame
	var route:=verify_letters(plate,"SNOWLINE SHELTER",Vector2(0.93,0.49))
	if route:
		check(route.text.count("\n")==2 and route.text.contains("Orange ring: sheltered slope") and route.text.contains("Blue pair: windy shortcut"),"three lines preserve both route choices")
		await physics_frame
		var eye:=plate.to_global(Vector3(0,0.39,1.6))
		for x:float in [-0.43,0.0,0.43]:
			var query:=PhysicsRayQueryParameters3D.create(eye,plate.to_global(Vector3(x,0,0)),3)
			check(plate.get_world_3d().direct_space_state.intersect_ray(query).get("collider")==plate,"shelter posts leave all of the directions visible from the trail")
	await remove_sign(plate,route)
	await check_other_sites(gen)
	await session.stream.quiesce()
	await session.audio.finish_playback()
	app.queue_free()
	for i in 6: await process_frame
	print("SITE SIGNS checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func check_other_sites(gen:WastelandTerrainGen)->void:
	var cells:Dictionary={}
	for cell:Vector2i in WastelandTerrainGen.FIXED:
		cells[gen.site_for(cell)]=cell
	for z in range(-20,21):
		for x in range(-20,21):
			var cell:=Vector2i(x,z)
			var site:=gen.site_for(cell)
			if not site.is_empty() and not cells.has(site): cells[site]=cell
		if cells.size()==session.catalog.sites.size(): break
	check(cells.size()==session.catalog.sites.size(),"sample covers every building in the catalog")
	cells["lodge"]=WastelandSite.SHORE_CELL
	cells["foothills"]=gen.starting_outpost("foothills")
	for cell:Vector2i in gen.nearby_outposts(Vector2.ZERO):
		if cell not in [gen.starting_outpost("grassland"),gen.starting_outpost("foothills"),WastelandSite.SHORE_CELL]:
			cells["outpost"]=cell
			break
	check(cells.has("outpost"),"sample includes an ordinary inland outpost")
	for site:String in cells:
		var cell:Vector2i=cells[site]
		var at:=Vector2(cell*32)+Vector2(16,16)
		session.stream.ensure_landing(Vector3(at.x,0,at.y))
		var chunk:WastelandChunk=session.stream.active[cell]
		var definition:Dictionary=session.catalog.sites[chunk.site]
		var expected:String={"foothills":"FOOTHILL TIMBER CO.","outpost":"FRONTIER OUTPOST"}.get(site,definition.sign)
		await process_frame
		verify_letters(chunk.structures.sign[0],expected,Vector2(float(definition.span)*0.52,0.38))
		if cell==WastelandSite.SHORE_CELL:
			var board:Node=chunk.fixtures[chunk.object_key("trader")]
			verify_letters(board,"HARBOR NOTICES",Vector2(1.06,0.18))
			verify_letters(board,"LAST FERRY",Vector2(0.25,0.25),"PaperNotice2")
	for id:String in Sites.INSCRIPTIONS:
		if id=="shelter": continue
		var at:Vector3=Sites.survey(gen).points[id]
		session.stream.ensure_landing(at)
		var chunk:WastelandChunk=session.stream.active[WastelandTerrainGen.chunk_at(Vector2(at.x,at.z))]
		await process_frame
		verify_letters(chunk.structures["expedition/"+id+"/plate"][0],Sites.INSCRIPTIONS[id],Vector2(0.93,0.49))
