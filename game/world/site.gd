class_name WastelandSite
extends RefCounted

const STOREY_HEIGHT := 3.05
const FLOOR_TOP := 0.12
const DOOR_HEAD := FLOOR_TOP + 2.46
const ROOF_PITCH := 0.37
const ROOF_THICKNESS := 0.28
const ROOF_OVERHANG := 0.55
const Facades := preload("res://game/world/site_facades.gd")
const Support:=preload("res://game/world/site_support.gd")
const Signs := preload("res://game/world/painted_sign.gd")
const BOARD_POSITION := Vector2(-18.6, 50.5)
const SHORE_CELL := Vector2i(-1,1)
const STARTS := {"seeded":"随种子","grassland":"草原驿站","foothills":"山麓林场"}
const OUTPOST_SIGNS := {"grassland":"PRAIRIE STATION","foothills":"FOOTHILL TIMBER CO.","outpost":"FRONTIER OUTPOST"}
# Legacy fixed layouts parked these container IDs outside the building.
const VEHICLE_CACHE_SLOT := {"fuel":0, "tower":0, "garage":2}

static func board_at(cell: Vector2i) -> Vector2:
	return BOARD_POSITION+Vector2((cell-SHORE_CELL)*WastelandTerrainGen.SIZE)

static func _outpost_id(gen: WastelandTerrainGen, cell: Vector2i) -> String:
	for id: String in ["grassland","foothills"]:
		if cell==gen.starting_outpost(id): return id
	return "outpost"

static func station_name(gen: WastelandTerrainGen, cell: Vector2i) -> String:
	if cell==SHORE_CELL: return "湖务站"
	return STARTS.get(_outpost_id(gen,cell),"荒原前哨")

static func starter_dressing(chunk: WastelandChunk, rows: Array) -> Array:
	var additions := rows.duplicate()
	var gen:WastelandTerrainGen=chunk.stream.generator
	var center:=gen.wild_start
	if chunk.site=="lodge" and (not center.is_finite() or WastelandTerrainGen.chunk_at(center).distance_to(chunk.cell)>1.5):
		center=Vector2(chunk.cell*WastelandTerrainGen.SIZE)+Vector2(13,25)
	if center.is_finite():
		var origin:=Vector2(chunk.cell*WastelandTerrainGen.SIZE)
		for i in 6:
			var spot:=center+Vector2.from_angle(i*TAU/6.0+0.27)*(3.8+0.35*(i%2))
			if WastelandTerrainGen.chunk_at(spot)!=chunk.cell: continue
			var local:=spot-origin
			if gen.revision>=4 and center==gen.wild_start:
				# Keep the hand-sized pickup visible and reachable through nearby grass and trunks.
				additions=additions.filter(func(entry: Dictionary):
					var p: Vector3=entry.point
					return Vector2(p.x,p.z).distance_squared_to(local)>1.5*1.5)
			additions.append({"index":4700+i,"id":["fallen_stick","grass","pebble"][i%3],"point":Vector3(local.x,gen.ground(spot.x,spot.y),local.y),"scale":1.12,"angle":i*0.92,"variant":i%3,"pickup":true})
	if chunk.site!="lodge": return additions
	var positions := [Vector2(6,25),Vector2(24,26),Vector2(10,29),Vector2(10,24),Vector2(12,24)]
	var species := ["oak","boulder","brush","reed_bed","brush"]
	for i in positions.size():
		var p: Vector2 = positions[i]
		var y: float = chunk.stream.generator.ground(chunk.position.x+p.x,chunk.position.z+p.y)
		additions.append({"index":4600+i,"id":species[i],"point":Vector3(p.x,y-0.02,p.y),
			"scale":0.92,"angle":float(i)*1.71,"variant":i%2})
	return additions

static func populate(chunk: WastelandChunk, definition: Dictionary, pad: float) -> void:
	var center := Vector3(16, pad, 16)
	var span := float(definition.span)
	var color := Color.html(definition.color)
	var site := chunk.site
	var inland := site=="lodge" and chunk.cell!=SHORE_CELL
	if inland: color=Color("#8b694e")
	var bunker := site == "bunker"
	if bunker:
		center.y -= 4.45
	var wood := site in ["lodge", "cabin"]
	var heights := int(definition.stories)
	chunk.ruin.plan(chunk,span,heights,wood)
	chunk.ruin.base_y=center.y
	var floor_tone := Color("#665359") if wood else Color("#716676")
	var trim := Color("#b68869") if wood else Color("#a797a2")
	var site_diff: Dictionary = chunk.stream.chunk_diff(chunk.cell).get("site_damage", {})
	for floor_index in heights:
		var base := center + Vector3.UP * floor_index * STOREY_HEIGHT
		_slab(chunk, floor_index, base, span, floor_tone)
		if chunk.ruin.condition and not wood: Support.interior_frame(chunk,base,floor_index,span)
		for side in range(4):
			var front: bool = side == 0
			var basis := Basis(Vector3.UP, side * PI * 0.5)
			var wall_at := base + basis * Vector3(0, 0, span * 0.5)
			var segments := 5
			var width := span / segments
			for part in segments:
				var local := (float(part) - 2.0) * width
				var id := "wall/%d/%d/%d" % [floor_index, side, part]
				var max_hp := 205 if wood else 480
				var point := wall_at + basis * Vector3(local, 0, 0)
				if chunk.ruin.condition:
					if not chunk.ruin.has_floor(chunk,center,point): continue
					Support.bind(chunk,id,[[Support.floor_id(span,floor_index,point.x-center.x,point.z-center.z)]])
				else: Support.bind(chunk,id,[["slab/"+str(floor_index)]])
				if chunk.ruin.damaged(floor_index,side,part,site):
					chunk.ruin.broken_wall(chunk,point,basis,floor_index,side,part,id,max_hp,color)
					continue
				var staircase_access := side == 1 and part in [0,4] and heights > 1
				var entry := (front and part == 2 and floor_index == 0) or staircase_access or (site == "fuel" and front and part == 1)
				var window := _has_window(site, floor_index, heights, part)
				if chunk.ruin.condition and (window or entry):
					for jamb_side:int in [-1,1]:
						_feature(chunk,point+basis*Vector3(jamb_side*(width*0.5-0.075),1.51,0),Vector3(0.15,3.02,0.29),basis,trim,id,max_hp)
				if entry:
					var header_height := STOREY_HEIGHT-DOOR_HEAD
					_panel(chunk, point + Vector3.UP * (DOOR_HEAD+header_height*0.5), Vector3(width, header_height, 0.29), basis, trim, id, max_hp, site_diff)
					if front and part==2 and not bunker:
						if site=="lodge":
							_feature(chunk,point+basis*Vector3(width*0.46,1.02,-0.78),Vector3(0.10,2.00,1.40),basis,trim.darkened(0.19),"door/entrance",95)
						else:
							board_door(chunk, point, width - 0.10, "door/entrance")
					elif bunker and front and part == 2:
						board_door(chunk, point, width - 0.10, "door/bunker")
				elif window:
					_panel(chunk, point + Vector3.UP * 0.52, Vector3(width, 1.05, 0.28), basis, color, id, max_hp, site_diff)
					_panel(chunk, point + Vector3.UP * 2.55, Vector3(width, 0.83, 0.30), basis, color,id,max_hp,site_diff)
					var beam := _feature(chunk,point+Vector3.UP*1.65,Vector3(0.12,1.13,0.08),basis,trim,id,max_hp)
					beam.rotation.y = side * PI / 2.0
				else:
					_panel(chunk, point + Vector3.UP * 1.53, Vector3(width, 3.05, 0.30), basis,
						color.lightened(0.035 * ((part + floor_index) % 3)), id, max_hp, site_diff)
		if floor_index < heights - 1:
			_stairs(chunk, base, span, floor_tone, 1 if floor_index % 2 == 0 else -1)
		if wood:
			for x:int in [-1, 1]:
				var bay:=0 if x<0 else 4
				if chunk.ruin.damaged(floor_index,0,bay,site): continue
				var corner:=_feature(chunk, base + Vector3(x * (span / 2.0 - 0.20), 1.53, span * 0.5 + 0.16), Vector3(0.20, 3.08, 0.27), Basis.IDENTITY, trim,Support.wall(floor_index,0,bay) if chunk.ruin.condition else "",205 if chunk.ruin.condition else 145)
				corner.set_meta("salvage_material","wood")
				if not chunk.ruin.condition: Support.bind(chunk,Support.key(corner),[[Support.wall(floor_index,0,bay)]])
		if chunk.ruin.condition:
			chunk.ruin.furnish(chunk,base,floor_index)
		else:
			var bed_size := Vector3(2.14, 0.55, 0.94) if site == "hospital" else Vector3(1.5, 0.72, 0.55)
			var furniture := base + Vector3(2.5, 0.35, -2.5)
			var bed:=_feature(chunk, furniture, bed_size, Basis.IDENTITY, Color("#91837f"))
			var pillow:=_fragment(chunk, Vector3(0.53, 0.23, 0.40), furniture + Vector3(-0.35, 0.35, 0), Color("#b9a4a6"))
			bed.set_meta("salvage_material","scrap" if site=="hospital" else "wood")
			pillow.set_meta("salvage_material","cloth")
			Support.bind(chunk,Support.key(bed),[["slab/"+str(floor_index)]])
			Support.bind(chunk,Support.key(pillow),[[Support.key(bed)]])
	if wood:
		_gabled_roof(chunk, center, span, color, trim)
		if chunk.ruin.condition:
			_chimney(chunk,center+Vector3(2.4,2.92,-2.02),Vector3(0.76,5.84,0.76),"chimney",235)
			Support.bind(chunk,"chimney",[[Support.floor_id(span,0,2.4,-2.02)]])
		else:
			var at := center + Vector3(2.4,4.85,-2.02)
			var stack_id := _fixture_key(at)
			_chimney(chunk,at,Vector3(0.86,2.03,0.83),stack_id,145)
			Support.bind(chunk,stack_id,[["roof/1"]])
			chunk.ruin.roof_bearings=[["roof/1"],["roof/-1"]]
	elif site != "tower":
		if chunk.ruin.condition:
			Support.decks(chunk,center+Vector3.UP*heights*STOREY_HEIGHT,heights,span,floor_tone,true)
		else:
			var roof:=_feature(chunk, center + Vector3.UP * heights * 3.05, Vector3(span + 0.63, 0.27, span + 0.63), Basis.IDENTITY, floor_tone)
			preload("res://game/art/site_floor.gd").apply(roof,site,Vector3(span+0.63,0.27,span+0.63),Vector2.ZERO,true,chunk.stream.generator.seed_at(chunk.cell,763+heights))
			roof.set_meta("salvage_material","stone")
			Support.bind(chunk,Support.key(roof),Support.perimeter_spans(heights-1))
			chunk.ruin.roof_bearings=[[Support.key(roof)]]
	else:
		if chunk.ruin.condition: Support.decks(chunk,center+Vector3.UP*heights*STOREY_HEIGHT,heights,span,floor_tone,true)
		else: chunk.ruin.roof_bearings=Support.perimeter_spans(heights-1)
		for side in [-1, 1]:
			var stand:=_feature(chunk, center + Vector3(side * 3, heights * 3.15, -1.40), Vector3(1.14, 1.65, 0.38), Basis.IDENTITY, color)
			if chunk.ruin.condition: Support.attach_roof(chunk,stand,span,side*3,-1.4)
			else: Support.bind(chunk,Support.key(stand),chunk.ruin.roof_bearings)
		var mast:=_fragment(chunk, Vector3(0.13, 3.3, 0.13), center + Vector3(2.9, heights * 3.05 + 1.5, -2.0), Color("#838296"))
		var lamp:=_fragment(chunk, Vector3(0.28, 0.17, 0.28), center + Vector3(2.9, heights * 3.05 + 3.1, -2.0), Color("#df8461"), 1.0)
		if chunk.ruin.condition:
			Support.attach_roof(chunk,mast,span,2.9,-2.0)
		else: Support.bind(chunk,Support.key(mast),chunk.ruin.roof_bearings)
		Support.bind(chunk,Support.key(lamp),[[Support.key(mast)]])
		chunk.ruin.tower_mast=Support.key(mast)
	var sign_at := Vector3(0,3.28 if inland else DOOR_HEAD+0.46,span*0.5+0.32)
	var sign := _feature(chunk,center+sign_at,Vector3(span*0.56,0.50,0.17),Basis.IDENTITY,trim.darkened(0.28) if inland else trim,"sign",75)
	if wood: sign.set_meta("salvage_components",{"wood":span*0.56*0.50*0.09,"scrap":span*0.56*0.46*0.006})
	Support.bind(chunk,"sign",[["wall/0/0/2"]])
	Support.bind(chunk,"door/entrance",[["wall/0/0/2"]])
	if bunker: Support.bind(chunk,"door/bunker",[["wall/0/0/2"]])
	if chunk.ruin.condition:
		for x:float in [-0.66,0.66]:
			_feature(chunk,center+Vector3(x,sign_at.y-0.16,span*0.5+0.18),Vector3(0.15,0.55,0.26),Basis.IDENTITY,trim,"sign",75)
	var station := _outpost_id(chunk.stream.generator,chunk.cell) if inland else ""
	var sign_name: String = OUTPOST_SIGNS[station] if inland else definition.sign
	Signs.facade(sign,sign_name,span*0.56,chunk.ruin.condition,chunk.stream.generator.seed_at(chunk.cell,385),site)
	var loot_rows: Array = definition.outpost_loots[station] if inland else definition.loots
	if chunk.stream.generator.site_revision>0:
		preload("res://game/world/site_caches.gd").populate(chunk,center,definition,loot_rows)
	else:
		for index in loot_rows.size():
			var level := mini(heights - 1, floori(float(index) / 2.0))
			var at := center + Vector3(-3.4 + 6.6 * (index % 2), 0.48 + 3.05 * level, -span * 0.24 + float(index % 3) * 1.4)
			if index == VEHICLE_CACHE_SLOT.get(site,-1):
				at = center + Vector3(-6.8, 0.65, 6.6)
			_loot(chunk, index, loot_rows[index], at)
	var note_text: String = "沿山路找邻近的中继站。柜里的日志要带回驻地，由公告板登记。" if inland else definition.note
	preload("res://game/sim/outpost_orders.gd").fixtures(chunk)
	for id:String in ["dispatch/locker","dispatch/cistern"]:
		if chunk.structures.has(id): Support.footing(chunk,id,chunk.structures[id][0].position)
	var note := chunk.object_body("note", "note", center + Vector3(-1.7, 1.03, 0.2), Vector3(0.38, 0.36, 0.43), {"text":note_text})
	if chunk.ruin.condition:
		var plinth:=center+Vector3(-1.7,0.53,0.2)
		Support.fit(chunk,"note/stand",plinth,Vector3(0.39,0.91,0.38),Basis.IDENTITY,trim.darkened(0.24),[[Support.floor_id(span,0,-1.7,0.2)]],70)
	WastelandLook.box(note, Vector3(0.34, 0.06, 0.24), Vector3.ZERO, Color("#d7c0a2"))
	WastelandLook.box(note, Vector3(0.18, 0.015, 0.022), Vector3(0, 0.036, 0.03), Color("#68535a"))
	if site == "lodge":
		var board := board_at(chunk.cell)
		_notice_board(chunk, Vector3(board.x-chunk.position.x,center.y+0.14,board.y-chunk.position.z))
		var step_at := center + Vector3(0, -0.08, span * 0.5 + 0.52)
		var step:=_feature(chunk, step_at, Vector3(3.16, 0.26, 1.2), Basis.IDENTITY, Color("#846556"))
		step.set_meta("salvage_material","wood")
		var lamp:=_fragment(chunk, Vector3(0.17, 0.28, 0.18), center + Vector3(1.9, 2.38, span * 0.5 + 0.37), Color("#f5ad58"), 0.82)
		Support.footing(chunk,Support.key(step),step_at)
		Support.bind(chunk,Support.key(lamp),[[Support.wall(0,0,3)]])
		if chunk.ruin.condition:
			_feature(chunk,lamp.position+Vector3.FORWARD*0.14,Vector3(0.13,0.11,0.24),Basis.IDENTITY,trim,Support.key(lamp))
	elif site == "fuel":
		var canopy_length:=8.4 if chunk.ruin.condition==0 else 8.4-0.77*chunk.ruin.condition
		var posts:Array=[]
		for i in [-1, 1]:
			var pump:=_feature(chunk, center + Vector3(i * 2., 0.85, 8.5), Vector3(0.62, 1.70, 0.61), Basis.IDENTITY, Color("#a55750"),"pump/"+str(i) if chunk.ruin.condition else "")
			_pump_jacket(pump,i)
			pump.set_meta("salvage_components",{"scrap":0.09,"parts":0.035})
			Support.footing(chunk,Support.key(pump),pump.position)
			var x:float=i*3.5 if i>0 else 4.9-canopy_length
			var post:=_feature(chunk, center + Vector3(x, 1.6, 8.5), Vector3(0.22, 3.2, 0.22), Basis.IDENTITY, trim,"canopy/post/"+str(i) if chunk.ruin.condition else "")
			Support.footing(chunk,Support.key(post),post.position)
			posts.append(Support.key(post))
		var canopy:=_feature(chunk, center + Vector3((8.4-canopy_length)*0.5, 3.34, 8.5), Vector3(canopy_length, 0.28, 4.3), Basis.IDENTITY, Color("#bf8a60"),"canopy" if chunk.ruin.condition else "")
		Support.bind(chunk,Support.key(canopy),[posts])
	if site in ["fuel", "police", "hospital"]:
		_car(chunk, center + Vector3(-8.0, 0.38, 6.3))
	if site in ["tower", "hospital"] or (site == "police" and (chunk.cell == Vector2i(3, -1) or chunk.stream.generator.revision>=3)):
		_loot(chunk, 99, definition.archive_loot, center + Vector3(0.4, 0.55 + (heights - 1) * 3.05, -3.8), true)
	_facade(chunk,center,span,color,trim,heights,wood)
	Facades.roof_plant(chunk,center,span,heights)
	if site != "lodge":
		for floor_index in mini(3, heights):
			for side: int in [-1,1]:
				var at := center + Vector3(side * span * 0.16, floor_index * STOREY_HEIGHT + FLOOR_TOP, -span * 0.17)
				if chunk.ruin.has_floor(chunk,center,at) and chunk.ruin.furniture_clear(at,0.6):
					chunk.sleeper_anchors.append(at)
	var front_edge:=center+Vector3(0,FLOOR_TOP,span*0.5+(1.20 if wood else 0.0))
	var entry_width:=2.88 if wood else span*0.2
	if site=="fuel":
		front_edge.x-=entry_width*0.5
		entry_width*=2.0
	_entrance_ramp(chunk,front_edge,Vector3.BACK,entry_width,floor_tone,"entrance/ramp",wood)
	if chunk.ruin.condition and not bunker:
		var breach:=center+Vector3(-span*0.5,FLOOR_TOP,(chunk.ruin.entrance_bay-2)*span*0.2)
		_entrance_ramp(chunk,breach,Vector3.LEFT,span*0.2,floor_tone,"entrance/breach",wood)
	chunk.ruin.debris(chunk,center,color)
	preload("res://game/art/site_weathering.gd").dress(chunk,center)

static func _chimney(chunk: WastelandChunk, at: Vector3, size: Vector3, id: String, hp: int) -> void:
	var brick := Color("#845d4d")
	var crown := at + Vector3.UP * size.y * 0.5
	var parts := [[at,size,brick]]
	# The corbel projects past the stack; one loose front brick has fallen from the flue rim.
	parts.append([crown + Vector3.UP * 0.025,Vector3(size.x + 0.11,0.12,size.z + 0.11),brick.darkened(0.16)])
	for edge: int in [-1,1]:
		parts.append([crown + Vector3(edge * (size.x * 0.5 - 0.05),0.19,0),Vector3(0.16,0.22,size.z + 0.06),brick.lerp(Color("#504b42"),0.44)])
	parts.append([crown + Vector3(0,0.19,-size.z * 0.5 + 0.04),Vector3(size.x - 0.25,0.22,0.15),brick.darkened(0.24)])
	parts.append([crown + Vector3(-size.x * 0.17,0.16,size.z * 0.5 - 0.04),Vector3(size.x * 0.32,0.16,0.15),brick])
	var solid_count := parts.size()
	parts.append([crown + Vector3.UP * 0.091,Vector3(size.x - 0.25,0.011,size.z - 0.17),Color("#393834")])
	var stack := _cluster(chunk,id,parts,hp,solid_count)
	stack.set_meta("salvage_material","brick")

static func board_door(chunk: WastelandChunk, at: Vector3, width: float, id: String) -> void:
	var parts := []
	for row in 5:
		var tilt := Basis(Vector3.BACK, 0.041 if row % 2 == 0 else -0.033)
		parts.append([at + Vector3.UP * (0.33 + row * 0.45), Vector3(width,0.33,0.15), Color("#896346").lightened(row%3 * 0.045), tilt])
	parts.append([at + Vector3(0,1.25,0.10),Vector3(0.16,2.34,0.10),Color("#594438"),Basis(Vector3.BACK,0.29)])
	var body := _cluster(chunk,id,parts,85.0)
	body.set_meta("salvage_material","wood")

static func _entrance_ramp(chunk:WastelandChunk,inner:Vector3,outward:Vector3,width:float,tone:Color,id:String,wood:bool)->void:
	# The high end meets the finished floor (or the outer edge of the timber porch).
	# Bury the toe in the original terrain so excavation can still undermine it.
	var outer := inner+outward*1.05
	outer.y=chunk.stream.generator.ground(chunk.position.x+outer.x,chunk.position.z+outer.z)-0.045
	var slope:=Basis.looking_at(outer-inner,Vector3.UP,true)
	var body:=_feature(chunk,(inner+outer)*0.5-slope.y*0.065,Vector3(width,0.13,inner.distance_to(outer)),slope,tone,id,160)
	body.set_meta("salvage_material","wood" if wood else "stone")
	Support.footing(chunk,id,outer)

static func _gabled_roof(chunk: WastelandChunk, center: Vector3, span: float, wall_color: Color, trim: Color) -> void:
	var half_span := span * 0.5
	var run := half_span + ROOF_OVERHANG
	var length := span + 1.35
	var pitch_cosine := cos(ROOF_PITCH)
	var half_plate_height := ROOF_THICKNESS * 0.5 / pitch_cosine
	var slope := tan(ROOF_PITCH)
	var ridge_height := STOREY_HEIGHT + half_plate_height + half_span * slope - 0.03
	var eave_height := ridge_height - run * slope
	var panel_width := run / pitch_cosine
	var roof_color := Color("#566461") if chunk.cell == SHORE_CELL else Color("#68594a") if chunk.site == "cabin" else Color("#59565e")
	var rib_color := Color("#6f5c71")
	if chunk.ruin.condition:
		Support.timber_roof(chunk,center,span,roof_color)
		_close_gables(chunk,center,half_span,ridge_height-half_plate_height-STOREY_HEIGHT+0.025,wall_color)
		return
	for side in [-1, 1]:
		var ribs: Array = []
		var tilt := Basis(Vector3.BACK, -side * ROOF_PITCH)
		var midpoint := center + Vector3(side * run * 0.5, (ridge_height + eave_height) * 0.5, 0.0)
		var roof := _feature(chunk, midpoint, Vector3(panel_width, ROOF_THICKNESS, length), tilt, roof_color,"roof/"+str(side),220)
		roof.name = "RoofWest" if side < 0 else "RoofEast"
		var spans:Array=[]
		for pair:Array in Support.wall_spans(0,3 if side<0 else 1):
			spans.append(pair+["gable/-1"])
			spans.append(pair+["gable/1"])
		Support.bind(chunk,Support.key(roof),spans)
		var eave := center + Vector3(side * run, eave_height, 0.0)
		var trim_piece:=_feature(chunk, eave, Vector3(0.16, 0.24, length + 0.06), tilt, trim)
		trim_piece.set_meta("salvage_material","wood")
		Support.bind(chunk,Support.key(trim_piece),[[Support.key(roof)]])
		for index in range(14):
			var z := lerpf(-length * 0.47, length * 0.47, float(index) / 13.0)
			ribs.append([midpoint + tilt * Vector3(0, ROOF_THICKNESS * 0.5 + 0.018, z),
				Vector3(panel_width - 0.09, 0.045, 0.038), rib_color.lightened((index % 3) * 0.12), tilt])
		# The original one-piece roof used in older worlds still carries its bolted replacement sheet.
		var repair := midpoint + tilt * Vector3(side * panel_width * 0.23,ROOF_THICKNESS * 0.5 + 0.045,side * length * 0.27)
		ribs.append([repair,Vector3(panel_width * 0.37,0.029,length * 0.13),Color("#858475"),tilt])
		for corner: int in [-1,1]:
			ribs.append([repair + tilt * Vector3(corner * panel_width * 0.15,0.024,length * 0.05),Vector3(0.065,0.021,0.065),Color("#735748"),tilt])
		_cluster(chunk,"roof/"+str(side),ribs,220)
	var cap := _feature(chunk, center + Vector3.UP * (ridge_height + half_plate_height - 0.045),
		Vector3(0.30, 0.18, length + 0.08), Basis.IDENTITY, roof_color.lightened(0.18))
	cap.name = "RoofRidge"
	Support.bind(chunk,Support.key(cap),[["roof/-1"],["roof/1"]])
	_close_gables(chunk, center, half_span, ridge_height - half_plate_height - STOREY_HEIGHT + 0.025, wall_color)

static func _close_gables(chunk: WastelandChunk, center: Vector3, half_span: float, rise: float, color: Color) -> void:
	var builder := WastelandScenery.new(0)
	var south_left := Vector3(-half_span, 0, 0.14)
	var south_right := Vector3(half_span, 0, 0.14)
	var south_peak := Vector3(0, rise, 0.14)
	var depth := Vector3.FORWARD * 0.28
	var north_left := south_left + depth
	var north_right := south_right + depth
	var north_peak := south_peak + depth
	Facades.gable_face(builder,half_span,rise,color,1)
	Facades.gable_face(builder,half_span,rise,color,-1)
	var left_slope := Vector3(-rise, half_span, 0.0)
	builder.triangle(south_left, south_peak, north_left, left_slope, color)
	builder.triangle(north_left, south_peak, north_peak, left_slope, color)
	var right_slope := Vector3(rise, half_span, 0.0)
	builder.triangle(south_right, south_peak, north_right, right_slope, color)
	builder.triangle(north_right, south_peak, north_peak, right_slope, color)
	builder.triangle(south_left, south_right, north_left, Vector3.DOWN, color)
	builder.triangle(north_left, south_right, north_right, Vector3.DOWN, color)
	var gable := builder.commit()
	var shape := gable.create_convex_shape()
	for side in [-1, 1]:
		if chunk.ruin.condition>=2 and side==chunk.ruin.end: continue
		var body := StaticBody3D.new()
		body.name = "GableNorth" if side < 0 else "GableSouth"
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = center + Vector3(0.0, STOREY_HEIGHT - 0.035, side * half_span)
		chunk.poi_root.add_child(body)
		var visual := MeshInstance3D.new()
		visual.mesh = gable
		visual.material_override = WastelandLook.colored_material()
		body.add_child(visual)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		chunk.obstacles.append(body)
		chunk.track_structure(body,"gable/"+str(side),180)
		var wall_side:=0 if side>0 else 2
		if chunk.ruin.condition:
			Support.bind(chunk,"gable/"+str(side),[[Support.wall(0,wall_side,1),Support.wall(0,wall_side,2),Support.wall(0,wall_side,3)]])
		else: Support.bind(chunk,"gable/"+str(side),Support.wall_spans(0,wall_side))

static func _has_window(site: String, floor_index: int, floors: int, bay: int) -> bool:
	return site != "bunker" and (bay % 2 == 1 or (site == "tower" and floor_index == floors - 1 and bay == 2))

static func _facade(chunk: WastelandChunk, center: Vector3, span: float, tint: Color, metal: Color, floors: int, wood: bool) -> void:
	var parts: Array = []
	var plank := tint.darkened(0.22)
	var width := span*0.2
	for side in range(4):
		var orientation := Basis(Vector3.UP,side*PI*0.5)
		var wall := center+orientation*Vector3(0,0,span*0.5+0.167)
		for floor_index in floors:
			var height := floor_index * STOREY_HEIGHT
			var edge := wall+Vector3.UP*height
			for n in range(5):
				if chunk.ruin.damaged(floor_index,side,n,chunk.site): continue
				var point := edge+orientation*Vector3((n-2)*width,0,0)
				if chunk.ruin.condition and not chunk.ruin.has_floor(chunk,center,point):continue
				var doorway := (side == 0 and n == 2 and floor_index == 0) or (side == 1 and n in [0,4] and floors > 1) or (chunk.site == "fuel" and side == 0 and n == 1)
				Facades.bay(chunk,point,orientation,width,floor_index,side,n,floors,tint,metal,doorway,_has_window(chunk.site,floor_index,floors,n))
	parts.clear()
	if wood:
		var porch := center+Vector3(0,0.025,span*0.5+0.60)
		for step in range(8):
			parts.append([porch+Vector3((step-3.5)*0.365,FLOOR_TOP-0.025-0.0475,0),Vector3(0.346,0.095,1.20),metal.lightened((step%4)*0.026)])
		if chunk.ruin.condition:
			_cluster(chunk,"porch/deck",parts,160)
			chunk.footings["porch/deck"]=[Vector2(chunk.position.x+porch.x-1.3,chunk.position.z+porch.z),Vector2(chunk.position.x+porch.x+1.3,chunk.position.z+porch.z)]
			parts.clear()
		for x in [-1,1]:
			var pillar := porch+Vector3(x*1.52,1.42,0.57)
			parts.append([pillar,Vector3(0.153,2.85,0.17),plank])
			parts.append([pillar+Vector3.UP*1.155,Vector3(0.226,0.18,0.226),metal])
			if chunk.ruin.condition:
				var id:="porch/post/"+str(x)
				_cluster(chunk,id,parts,150)
				Support.footing(chunk,id,pillar)
				parts.clear()
		parts.append([porch+Vector3(0,2.86,0.19),Vector3(3.65,0.16,1.43),metal])
		_cluster(chunk,"porch",parts,160)
		if chunk.ruin.condition: Support.bind(chunk,"porch",[["porch/post/-1","porch/post/1","wall/0/0/2"]])
		else:
			chunk.footings["porch"]=[Vector2(chunk.position.x+porch.x-1.52,chunk.position.z+porch.z+0.57),Vector2(chunk.position.x+porch.x+1.52,chunk.position.z+porch.z+0.57)]
	else:
		var roof := center+Vector3(0,floors*3.05+0.069,0)
		for vent in range(5):
			var point := roof+Vector3(-3.2+vent*0.55,0.14,-1.9)
			if chunk.ruin.condition and chunk.ruin.end<0: point.x+=4.2
			parts.append([point,Vector3(0.46,0.34,0.91),metal.darkened(0.25),Basis.IDENTITY,0.74])
			parts.append([point+Vector3.UP*0.20,Vector3(0.51,0.105,0.96),metal.darkened(0.07)])
		if chunk.site=="tower":
			for strip in range(8):
				var angle := strip*PI/8.0
				var rotor := Basis(Vector3.RIGHT,angle)*Basis(Vector3.UP,-0.40)
				parts.append([roof+Vector3(2.35,2.07,-2.03),Vector3(1.44,0.057,0.19),metal,rotor])
		if chunk.ruin.condition: Support.fittings(chunk,parts,center,span,"roof/fittings")
		else:
			_cluster(chunk,"roof/fittings",parts,140)
			Support.bind(chunk,"roof/fittings",chunk.ruin.roof_bearings)
	parts.clear()
	_landmark_details(parts, "outpost" if chunk.site=="lodge" and chunk.cell!=SHORE_CELL else chunk.site, center, span, floors,chunk.ruin.condition)
	if chunk.ruin.condition: Support.fittings(chunk,parts,center,span,"landmark/fittings")
	else:
		_cluster(chunk,"landmark/fittings",parts,150)
		match chunk.site:
			"lodge","cabin":
				Support.bind(chunk,"landmark/fittings",[[Support.wall(0,0,0)]] if chunk.cell==SHORE_CELL or chunk.site=="cabin" else chunk.ruin.roof_bearings)
			"hospital","tower","police","bunker":
				Support.bind(chunk,"landmark/fittings",chunk.ruin.roof_bearings)
			"fuel":
				var p:=center+Vector3(0,3.34,8.5)
				Support.bind(chunk,"landmark/fittings",[["fixture/%.3f/%.3f/%.3f"%[p.x,p.y,p.z]]])

static func _cluster(chunk: WastelandChunk,id: String,parts: Array,hp: float,solid_count: int = -1) -> StaticBody3D:
	if parts.is_empty(): return null
	var body := StaticBody3D.new()
	body.collision_layer=2
	body.collision_mask=0
	var origin: Vector3=parts[0][0]
	var local := []
	var solid_volume:=0.0
	for part: Array in parts:
		var row:=part.duplicate()
		row[0]=part[0]-origin
		local.append(row)
		if solid_count < 0 or local.size() <= solid_count:
			var size:Vector3=part[1]
			solid_volume+=size.x*size.y*size.z
	body.set_meta("salvage_volume",solid_volume)
	body.position=origin
	chunk.poi_root.add_child(body)
	var image:=MeshInstance3D.new()
	image.mesh=preload("res://game/world/building_mesh.gd").boxes(local)
	image.material_override=WastelandLook.colored_material()
	body.add_child(image)
	if not chunk.stream.is_preview:
		var collider:=CollisionShape3D.new()
		var shape:ConcavePolygonShape3D
		if solid_count >= 0 and solid_count < local.size():
			# Six indexed quads expand to 36 collision points per box, in part order.
			# Trim the visual fittings from the single render mesh for physics.
			shape=ConcavePolygonShape3D.new()
			shape.set_faces(image.mesh.get_faces().slice(0,solid_count*36))
		else:
			shape=image.mesh.create_trimesh_shape()
		shape.backface_collision=true
		collider.shape=shape
		body.add_child(collider)
		chunk.obstacles.append(body)
	chunk.track_structure(body,id,hp)
	return body

static func _landmark_details(parts: Array, site: String, center: Vector3, span: float, floors: int, weathered:=0) -> void:
	var steel := Color("#465461")
	var ivory := Color("#ead5a3")
	var amber := Color("#d5914f")
	var roof := center + Vector3(0, floors * STOREY_HEIGHT + 0.2, 0)
	var front := center + Vector3(-span * 0.40, 0, span * 0.5 + 0.25)
	match site:
		"outpost":
			# The antenna links inland boards to the regional relay network.
			var pole := roof+Vector3(3.7 if weathered else -3.7,1.9,-3.2)
			parts.append([pole,Vector3(0.09,4.4,0.09),steel])
			for i in 3:
				parts.append([pole+Vector3.UP*(1.2+i*0.35),Vector3(1.35-i*0.23,0.07,0.07),ivory])
			for i in 6:
				var row := 1 if i>=4 else 0
				var log_at := center+Vector3(4.0+row*0.25,0.26+row*0.46,6.2+(i%4)*0.48)
				parts.append([log_at,Vector3(2.3-i%3*0.11,0.41,0.41),Color("#795234"),Basis(Vector3.RIGHT,0.15)])
				parts.append([log_at+Vector3.LEFT*(1.15-i%3*0.055),Vector3(0.04,0.31,0.32),amber])
		"hospital":
			var sign_at := roof + Vector3(0, 1.03, span * 0.39)
			for side in [-1, 1]:
				parts.append([sign_at + Vector3(side * 0.74, -0.55, 0), Vector3(0.12, 1.05, 0.13), steel])
			parts.append([sign_at, Vector3(2.15, 1.62, 0.21), Color("#567e78")])
			for z in [-0.12, 0.12]:
				parts.append([sign_at + Vector3.BACK * z, Vector3(1.13, 0.34, 0.04), ivory])
				parts.append([sign_at + Vector3.BACK * z, Vector3(0.34, 1.13, 0.05), ivory])
		"fuel":
			var width:=8.42-0.77*weathered
			var fascia := center + Vector3((8.42-width)*0.5, 3.34, 10.67)
			# The original enamel band hangs on at the left; the right end has lost its skin.
			var seam := fascia + Vector3.RIGHT * width * 0.26
			parts.append([fascia + Vector3.LEFT * width * 0.12, Vector3(width * 0.76, 0.43, 0.13), Color("#914d41")])
			parts.append([fascia + Vector3(-width * 0.12,-0.145,0.071),Vector3(width * 0.76,0.055,0.023),Color("#c4b38b")])
			var bend := Basis(Vector3.BACK,-0.19)
			parts.append([seam + bend * Vector3(width * 0.069,-0.05,0.015),Vector3(width * 0.138,0.31,0.10),Color("#99654d"),bend])
			for y: float in [-0.10,0.16]:
				parts.append([seam + Vector3(width * 0.12,y,-0.015),Vector3(width * 0.24,0.054,0.12),steel])
			for bay in 3:
				var truss := Basis(Vector3.BACK,(-1 if bay % 2 == 0 else 1) * atan2(0.26,width * 0.08))
				parts.append([seam + Vector3(width * (0.04 + 0.08 * bay),0.03,0.03),Vector3(Vector2(0.26,width * 0.08).length(),0.043,0.059),Color("#775941"),truss])
			for i in range(3):
				parts.append([fascia + Vector3(-width*0.42 + i * 0.44, 0, 0.092), Vector3(0.18, 0.38, 0.04), ivory, Basis(Vector3.BACK, -0.42)])
			for side in [-1, 1]:
				var pump := center + Vector3(side * 2.0, 1.29, 8.83)
				parts.append([pump, Vector3(0.45, 0.31, 0.07), steel])
				parts.append([pump + Vector3.UP * 0.05 + Vector3.BACK * 0.05, Vector3(0.30, 0.06, 0.02), ivory])
		"police":
			var board := front + Vector3.UP * 1.60
			parts.append([board, Vector3(1.53, 1.04, 0.09), Color("#354960")])
			for row in range(3):
				for col in range(2):
					parts.append([board + Vector3(-0.41 + col * 0.76, 0.27 - row * 0.30, 0.065), Vector3(0.61, 0.16, 0.03), ivory.darkened(row * 0.10)])
			var mast := roof + Vector3(2.6 if weathered else -2.6, 1.7, 1.7)
			parts.append([mast, Vector3(0.10, 3.5, 0.10), steel])
			for row in range(3):
				parts.append([mast + Vector3.UP * (0.72 + row * 0.39), Vector3(1.76 - row * 0.34, 0.07, 0.08), ivory])
		"bunker":
			var gauge := front + Vector3.UP * 2.65
			parts.append([gauge, Vector3(0.64, 5.02, 0.11), ivory])
			for tick in range(14):
				var length := 0.46 if tick % 3 == 0 else 0.24
				parts.append([gauge + Vector3((length - 0.58) * 0.5, -2.3 + tick * 0.35, 0.08), Vector3(length, 0.09, 0.03), steel])
			for side in [-1, 1]:
				var duct := roof + Vector3(side * 2.9, 0.84, 2.6)
				parts.append([duct, Vector3(0.64, 1.75, 0.64), Color("#647f76")])
				parts.append([duct + Vector3.UP * 0.91, Vector3(0.97, 0.17, 0.97), amber])
		"lodge":
			var ring := front + Vector3.UP * 1.67
			for segment in range(8):
				var angle := segment * TAU / 8.0
				var radial := Vector3(cos(angle), sin(angle), 0)
				parts.append([ring + radial * 0.43, Vector3(0.19, 0.38, 0.17), amber if segment % 2 == 0 else ivory, Basis(Vector3.BACK, angle)])
		"cabin":
			for side in [-1, 1]:
				var paddle := front + Vector3(side * 0.19, 1.63, 0.03 * side)
				var tilt := Basis(Vector3.BACK, side * 0.33)
				parts.append([paddle, Vector3(0.08, 1.62, 0.07), ivory, tilt])
				parts.append([paddle + tilt * Vector3.DOWN * 0.66, Vector3(0.24, 0.54, 0.09), amber, tilt])
		"tower":
			var perch := roof + Vector3(2.9, 3.06, -2.0)
			for side in [-1, 1]:
				parts.append([perch + Vector3(side * 0.23, 0, 0), Vector3(0.06, 0.48, 0.07), steel])
			parts.append([perch + Vector3.UP * 0.25, Vector3(0.65, 0.10, 0.64), amber])

static func _slab(chunk: WastelandChunk, floor_index: int, base: Vector3, span: float, color: Color) -> void:
	if floor_index == 0:
		if chunk.ruin.condition: Support.foundation(chunk,base,span,color)
		else:
			_feature(chunk, base + Vector3(0, 0.015, 0), Vector3(span, 0.21, span), Basis.IDENTITY, color,"slab/0",320.0)
			var points:Array[Vector2]=[]
			for x:int in [-1,1]:
				for z:int in [-1,1]: points.append(Vector2(chunk.position.x+base.x+x*span*0.37,chunk.position.z+base.z+z*span*0.37))
			chunk.footings["slab/0"]=points
	else:
		if chunk.ruin.condition: Support.decks(chunk,base,floor_index,span,color)
		else:
			_feature(chunk, base + Vector3(0, 0.015, 0), Vector3(span, 0.21, span), Basis.IDENTITY, color,"slab/"+str(floor_index),320.0)
			Support.bind(chunk,"slab/"+str(floor_index),Support.perimeter_spans(floor_index-1))
		for side in [-1,1]:
			var old_center:=base+Vector3(span*0.5+0.33,0.015,side*(span*0.5-0.68))
			var landing_width:=3.22 if chunk.ruin.heights>2 else 1.72
			var landing_at:=base+Vector3(span*0.5+landing_width*0.5,0.015,side*(span*0.5-0.68))
			var landing:=_feature(chunk,landing_at,Vector3(landing_width,0.21,1.74),Basis.IDENTITY,color,_fixture_key(old_center))
			landing.set_meta("salvage_material","stone")
			if chunk.ruin.condition: Support.bind(chunk,Support.key(landing),[[Support.slab_id(floor_index,2,0 if side<0 else 4)]])
			else: Support.bind(chunk,Support.key(landing),[["slab/"+str(floor_index)]])

static func _stairs(chunk: WastelandChunk, base: Vector3, span: float, color: Color, direction: int) -> void:
	# Alternate parallel lanes so returning flights never close off the landing below them.
	var length:=span-3.10
	var x:=span*0.5+(0.90 if direction>0 else 2.44)
	var level:=roundi((base.y-chunk.ruin.base_y)/STOREY_HEIGHT)
	var low:=base+Vector3(x,FLOOR_TOP,-direction*length*0.5)
	var high:=base+Vector3(x,FLOOR_TOP+STOREY_HEIGHT,direction*length*0.5)
	if level==0: low.y=chunk.stream.generator.ground(chunk.position.x+low.x,chunk.position.z+low.z)-0.05
	var surface:=Basis(Vector3.RIGHT,-direction*atan2(high.y-low.y,length))
	var old_center:=base+Vector3(span*0.5+0.67,1.52,0)
	var flight:=_feature(chunk,(low+high)*0.5-surface.y*0.06,Vector3(1.45,0.12,low.distance_to(high)),surface,color,_fixture_key(old_center))
	var treads: Array = []
	for index in 11:
		var point:=low.lerp(high,(index+0.5)/11.0)-Vector3.UP*0.07
		treads.append([flight.transform.affine_inverse()*point,Vector3(1.45,0.17,length/11.0),color.lightened(0.12),flight.basis.inverse()])
	Facades.clad_box(flight,treads)
	flight.set_meta("salvage_volume", float(flight.get_meta("salvage_volume")) + 1.45 * 0.17 * length)
	var old_top:=base+Vector3(span*0.5+0.57,3.0,direction*(span*0.5-0.10))
	var beam_width:=x-span*0.5+0.72
	var beam_at:=base+Vector3(span*0.5+beam_width*0.5,STOREY_HEIGHT+FLOOR_TOP-0.30,direction*(length*0.5+0.10))
	var top:=_feature(chunk,beam_at,Vector3(beam_width,0.18,0.28),Basis.IDENTITY,color,_fixture_key(old_top))
	flight.set_meta("salvage_material","stone")
	top.set_meta("salvage_material","stone")
	if chunk.ruin.condition:
		var high_bay:=4 if direction>0 else 0
		Support.bind(chunk,Support.key(top),[[Support.slab_id(level+1,2,high_bay)]])
		Support.bind(chunk,Support.key(flight),[[Support.slab_id(level,2,4-high_bay),Support.key(top)]])
	else:
		Support.bind(chunk,Support.key(top),[["slab/"+str(level+1)]])
		Support.bind(chunk,Support.key(flight),[["slab/"+str(level),Support.key(top)]])

static func _fragment(chunk:WastelandChunk,size:Vector3,at:Vector3,color:Color,glow:float=0.0) -> StaticBody3D:
	var body:=_feature(chunk,at,size,Basis.IDENTITY,color)
	if glow>0:
		var mesh:MeshInstance3D=body.get_child(0)
		mesh.material_override=WastelandLook.matte(color,glow)
		body.set_meta("salvage_material","wire")
	return body

static func _feature(chunk: WastelandChunk, at: Vector3, size: Vector3, basis: Basis, color: Color, id: String="",hp: float=145.0) -> StaticBody3D:
	var body := WastelandLook.solid(chunk.poi_root, size, at, color)
	body.basis = basis
	if id=="": id=_fixture_key(at)
	if id.begins_with("slab/") or id.begins_with("roof/plate/"):
		var roof:=id.begins_with("roof/")
		var level:=int(chunk.ruin.heights) if roof else id.get_slice("/",1).to_int()
		preload("res://game/art/site_floor.gd").apply(body,chunk.site,size,Vector2(at.x-16,at.z-16),roof,chunk.stream.generator.seed_at(chunk.cell,763+level))
	chunk.track_structure(body,id,hp)
	chunk.obstacles.append(body)
	return body

static func _fixture_key(at:Vector3)->String:
	return "fixture/%.3f/%.3f/%.3f"%[at.x,at.y,at.z]

static func _pump_jacket(body: StaticBody3D, side: int) -> void:
	var enamel := Color("#bbad8a")
	var primer := Color("#80563f")
	var steel := Color("#586361")
	var parts := [
		[Vector3(0,0.81,0),Vector3(0.68,0.11,0.65),enamel,Basis.IDENTITY,0.91],
		[Vector3(0,-0.75,0),Vector3(0.65,0.17,0.63),primer],
		[Vector3(0,-0.18,0.311),Vector3(0.47,0.65,0.028),steel if side<0 else Color("#8e6152")],
		[Vector3(side*0.16,-0.05,0.337),Vector3(0.065,0.042,0.027),enamel],
	]
	for vent in 3:
		parts.append([Vector3(0,-0.39+vent*0.055,0.332),Vector3(0.26,0.023,0.018),Color("#403d37")])
	# The rubber line hangs from the head to the nozzle clipped to the casing.
	var line := PackedVector3Array([Vector3(0.303,0.49,-0.13),Vector3(0.44,0.39,-0.13),
		Vector3(0.51,-0.37,-0.10),Vector3(0.48,-0.57,0.02),Vector3(0.40,-0.53,0.14),Vector3(0.37,0.03,0.17)])
	for i in range(line.size()-1):
		var a := line[i] * Vector3(side,1,1)
		var b := line[i+1] * Vector3(side,1,1)
		var segment := b-a
		parts.append([(a+b)*0.5,Vector3(0.048,segment.length()+0.018,0.05),Color("#393934"),Basis(Quaternion(Vector3.UP,segment.normalized()))])
	parts.append([Vector3(side*0.35,0.13,0.17),Vector3(0.09,0.23,0.085),steel,Basis(Vector3.BACK,-side*0.17)])
	Facades.clad_box(body,parts)

static func _panel(chunk: WastelandChunk, at: Vector3, size: Vector3, basis: Basis, color: Color, id: String, hp: int, _diffs: Dictionary) -> void:
	_feature(chunk,at,size,basis,color,id,hp)

static func _loot(chunk: WastelandChunk, index: int, table: String, at: Vector3, quest: bool = false) -> void:
	var profile := preload("res://game/art/supply_chest.gd").kind_at(chunk.stream.generator,chunk.position+at)
	preload("res://game/world/regional_caches.gd").spawn(chunk,"container/"+str(index),table,at,{"quest":quest,"building_cache":true},profile)

static func _car(chunk: WastelandChunk, at: Vector3) -> void:
	var chassis:=_feature(chunk, at, Vector3(2.3, 0.61, 3.83), Basis.IDENTITY, Color("#6a5f6c"))
	chassis.set_meta("salvage_components",{"scrap":0.42,"parts":0.08})
	var cab:=_fragment(chunk, Vector3(1.89, 0.77, 1.56), at + Vector3(0, 0.59, -0.67), Color("#464551"))
	cab.set_meta("salvage_components",{"scrap":0.13,"cloth":0.041})
	var roof:=_fragment(chunk, Vector3(2.02, 0.12, 1.74), at + Vector3(0, 1.03, -0.67), Color("#9a786e"))
	var wheels:Array=[]
	for side in [-1, 1]:
		for z in [-1.20, 1.22]:
			var wheel:=_fragment(chunk, Vector3(0.25, 0.7, 0.72), at + Vector3(side * 1.12, -0.17, z), Color("#333041"))
			wheel.set_meta("salvage_volume",0.011) # Only the metal rim is recoverable.
			wheels.append(Support.key(wheel))
			Support.footing(chunk,Support.key(wheel),wheel.position)
	Support.bind(chunk,Support.key(chassis),[[wheels[0],wheels[3]],[wheels[1],wheels[2]]])
	Support.bind(chunk,Support.key(cab),[[Support.key(chassis)]])
	Support.bind(chunk,Support.key(roof),[[Support.key(cab)]])

static func _notice_board(chunk: WastelandChunk, at: Vector3) -> void:
	var board := chunk.object_body("trader", "trader", at + Vector3.UP * 1.05, Vector3(1.36, 1.86, 0.35))
	var timber := Color("#74523b")
	for side: int in [-1, 1]:
		WastelandLook.box(board, Vector3(0.10,1.90,0.13), Vector3(side*0.61,-0.13,0), timber)
	var panel := WastelandLook.box(board,Vector3(1.38,0.94,0.12),Vector3(0,0.33,0),Color("#435d53"))
	Signs.enamel(panel,Color("#435d53"),chunk.ruin.condition,chunk.stream.generator.seed_at(chunk.cell,389))
	WastelandLook.box(board, Vector3(1.54,0.09,0.42),Vector3(0,0.86,0),timber.lightened(0.16))
	WastelandLook.box(board, Vector3(1.05,0.47,0.36),Vector3(0,-0.46,0),Color("#48726e"))
	WastelandLook.box(board, Vector3(0.27,0.04,0.08),Vector3(0,-0.41,0.20),Color("#d7ab6c"))
	var shore := chunk.cell==SHORE_CELL
	var notices := [
		"MISSING\nDockhand\nBlue coat" if shore else "MISSING\nTrail crew\nNorth pass",
		"RATIONS\nOne tin\nper family",
		"LAST FERRY\nSouth pier\n17:30" if shore else "WANTED\nSeed grain\nfor trade"
	]
	for i in notices.size():
		var x := -0.39 + 0.37 * i
		var paper := WastelandLook.box(board, Vector3(0.29,0.39,0.017),Vector3(x,0.29+i%2*0.06,0.078),Color("#e0c69a").darkened(i*0.06))
		paper.rotation.z = (i-1)*0.085
		var tack := paper.position+Vector3(0,0.166,0.012).rotated(Vector3.BACK,paper.rotation.z)
		WastelandLook.box(board,Vector3(0.019,0.018,0.008),tack,Color("#655746"))
		var ink := Signs.letter(board,notices[i],paper.position+Vector3(0,0,0.014),Vector2(0.25,0.25))
		ink.name = "PaperNotice%d" % i
		ink.rotation.z = paper.rotation.z
		ink.modulate = timber.darkened(0.38)
		ink.outline_size = 0
		ink.visibility_range_end = 8
	var heading := "HARBOR NOTICES" if shore else "STATION NOTICES"
	var title := Signs.letter(board,heading,Vector3(0,0.655,0.103),Vector2(1.06,0.18))
	title.shaded = true

static func landing_shore(generator: WastelandTerrainGen) -> float:
	var shore := 12.0
	for step in range(28, 4, -1):
		if generator.ground(5.0, float(step)) < 0.65:
			shore = float(step)
			break
	return shore

static func landing(chunk: WastelandChunk) -> void:
	var first_member := chunk.poi_root.get_child_count()
	var modern:bool=chunk.stream.generator.site_revision>0
	var shore := landing_shore(chunk.stream.generator)
	var near := Vector3(5.0, maxf(0.43, chunk.stream.generator.ground(5.0, shore + 1.0) + 0.12), shore + 1.0)
	var far := Vector3(5.0, 0.45, maxf(2.0, shore - 11.0))
	var length := near.distance_to(far)
	var old_wood := Color("#a17f64")
	for index in range(21):
		var portion := (float(index) + 0.5) / 21.0
		var at := near.lerp(far, portion)
		var pitch := atan2(far.y-near.y,near.z-far.z)
		var chipped:bool=modern and index%7==posmod(chunk.stream.generator.seed_at(chunk.cell,832),7)
		if chipped: at.x+=0.42
		var plank := _feature(chunk,at,Vector3(2.04 if chipped else 2.88,0.19,length/21.0),Basis(Vector3.RIGHT,pitch),
			old_wood.lightened((index%5)*0.038),"dock/plank/"+str(index),90.0)
		Facades.dock_plank(plank,index)
	var piles:={}
	for index in [3, 10, 17, 20]:
		var at := near.lerp(far, float(index) / 21.0)
		for side in [-1, 1]:
			var p := at + Vector3(side * 1.31, 0.0, 0.0)
			var mud_depth := maxf(0.65, p.y - chunk.stream.generator.ground(p.x, p.z))
			var pile:=_fragment(chunk, Vector3(0.19, mud_depth + 0.69, 0.19),
				p + Vector3.UP * (0.33 - mud_depth * 0.5), old_wood.darkened(0.33))
			pile.set_meta("salvage_material","wood")
			Facades.dock_pile(pile,index in [3,20])
			var id:="fixture/%.3f/%.3f/%.3f"%[pile.position.x,pile.position.y,pile.position.z]
			piles[Vector2i(index,side)]=id
			if modern: chunk.footings[id]=[Vector2(p.x,p.z)]
	if modern:
		var runs:=[Vector2i(3,10),Vector2i(10,17),Vector2i(17,20)]
		for bay in runs.size():
			var endpoints:Vector2i=runs[bay]
			var start:=near.lerp(far,0 if bay==0 else endpoints.x/21.0)
			var finish:=near.lerp(far,1 if bay==2 else endpoints.y/21.0)
			for side:int in [-1,1]:
				var beam_id:="dock/stringer/%d/%d"%[bay,side]
				var beam_center:=start.lerp(finish,0.5)+Vector3(side*1.31,-0.16,0)
				_feature(chunk,beam_center,Vector3(0.19,0.26,start.distance_to(finish)+0.1),Basis(Vector3.RIGHT,atan2(finish.y-start.y,start.z-finish.z)),old_wood.darkened(0.23),beam_id)
				chunk.support_graph[beam_id]=[[piles[Vector2i(endpoints.x,side)],piles[Vector2i(endpoints.y,side)]]]
		for index in 21:
			var bay:=0 if index<10 else 1 if index<17 else 2
			var pair:=["dock/stringer/%d/-1"%bay,"dock/stringer/%d/1"%bay]
			var plank_id:="dock/plank/"+str(index)
			if index%7==posmod(chunk.stream.generator.seed_at(chunk.cell,832),7):
				var brace_id:="dock/batten/"+str(index)
				var at:=near.lerp(far,(index+0.5)/21.0)-Vector3.UP*0.105
				_feature(chunk,at,Vector3(2.80,0.13,0.12),Basis.IDENTITY,old_wood.darkened(0.31),brace_id,70)
				chunk.support_graph[brace_id]=[pair]
				chunk.support_graph[plank_id]=[[brace_id]]
			else:
				chunk.support_graph[plank_id]=[pair]
	var platform := far + Vector3(1.36,0,-0.50)
	if modern:
		var outer:=platform+Vector3(1.49,-0.05,0)
		var depth:=maxf(0.5,outer.y-chunk.stream.generator.ground(outer.x,outer.z)+0.18)
		_feature(chunk,outer-Vector3.UP*depth*0.5,Vector3(0.23,depth,0.23),Basis.IDENTITY,old_wood.darkened(0.3),"dock/platform_pile")
		chunk.support_graph["dock/platform"]=[["dock/platform_pile",piles[Vector2i(20,1)]]]
		chunk.footings["dock/platform_pile"]=[Vector2(outer.x,outer.z)]
	_feature(chunk, platform, Vector3(3.56,0.14,1.28), Basis.IDENTITY, old_wood,"dock/platform",180.0)
	var lamp_post:=_fragment(chunk, Vector3(0.12,1.34,0.12), platform + Vector3(1.57,0.60,0.44), Color("#736679"))
	var lamp:=_fragment(chunk, Vector3(0.24,0.16,0.20), platform + Vector3(1.57,1.32,0.44), Color("#e5b47a"), 0.78)
	lamp_post.set_meta("salvage_material","scrap")
	lamp.set_meta("salvage_material","wire")
	if modern:
		var post_id:="fixture/%.3f/%.3f/%.3f"%[lamp_post.position.x,lamp_post.position.y,lamp_post.position.z]
		var lamp_id:="fixture/%.3f/%.3f/%.3f"%[lamp.position.x,lamp.position.y,lamp.position.z]
		chunk.support_graph[post_id]=[["dock/platform"]]
		chunk.support_graph[lamp_id]=[[post_id]]
	preload("res://game/art/site_weathering.gd").dress_dock(chunk,first_member)
