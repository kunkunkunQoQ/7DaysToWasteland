extends RefCounted

# All fittings share their host furniture's mesh, damage key and floor supports.
const STEEL := Color("#5a6868")
const ENAMEL := Color("#c4bfb1")
const RUBBER := Color("#353c3b")
const PAPER := Color("#bcaa86")

static func add_fittings(parts: Array, materials: Dictionary, site: String, kind: String, at: Vector3, side: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var start := parts.size()
	var source := "scrap"
	match kind:
		"cot":
			if site == "hospital":
				# Drip stand clamped to the steel bed frame and a partly emptied bag.
				var foot := at + Vector3(-side * 0.78, 0.47, 0.31)
				parts.append([foot + Vector3.UP * 0.59, Vector3(0.044, 1.21, 0.044), STEEL])
				parts.append([foot + Vector3(side * 0.10, 1.18, 0), Vector3(0.24, 0.04, 0.04), STEEL])
				parts.append([foot + Vector3(side * 0.18, 1.04, 0), Vector3(0.15, 0.25, 0.075), Color("#aeb7aa")])
				parts.append([foot + Vector3(side * 0.18, 0.96, -0.04), Vector3(0.11, 0.05, 0.014), ENAMEL])
			else:
				source = "cloth"
				var pack := at + Vector3(-side * 0.58, 0.72, 0.03)
				parts.append([pack, Vector3(0.29, 0.13, 0.53), Color("#637162")])
				for strap in [-0.16, 0.16]:
					parts.append([pack + Vector3(0, 0.004, strap), Vector3(0.30, 0.137, 0.043), RUBBER])
		"desk", "bench":
			# Existing notes and the vise occupy opposite ends of these two worktops.
			var p := at + Vector3(side * (0.39 if kind == "desk" else -0.34), 0.835, 0)
			match site:
				"tower", "bunker", "lodge":
					_radio(parts, p, rng)
				"fuel":
					var body := Color("#879287")
					parts.append([p + Vector3.UP * 0.077, Vector3(0.46, 0.15, 0.38), body])
					parts.append([p + Vector3(0, 0.145, -0.07), Vector3(0.40, 0.10, 0.15), RUBBER, Basis(Vector3.RIGHT, -0.18)])
					parts.append([p + Vector3(0, 0.234, 0.10), Vector3(0.36, 0.17, 0.075), body])
					parts.append([p + Vector3(0, 0.247, 0.056), Vector3(0.24, 0.081, 0.014), Color("#364d45")])
				"police", "cabin":
					source = "wood"
					var crate := p + Vector3.UP * 0.095
					parts.append([crate, Vector3(0.46, 0.19, 0.32), Color("#80694b")])
					var count := rng.randi_range(3, 5)
					for i in count:
						parts.append([crate + Vector3(-0.16 + 0.075*i, 0.13, 0), Vector3(0.040, 0.16+0.026*(i%2), 0.26), PAPER.darkened(0.04*i), Basis(Vector3.BACK, 0.13)])
				"hospital":
					parts.append([p + Vector3.UP * 0.024, Vector3(0.49, 0.048, 0.28), STEEL])
					for i in rng.randi_range(2, 3):
						var tin := p + Vector3(-0.13 + 0.13*i, 0.10, 0)
						parts.append([tin, Vector3(0.085, 0.11, 0.092), ENAMEL])
						parts.append([tin + Vector3.UP * 0.063, Vector3(0.09, 0.022, 0.095), Color("#7a8880")])
		"shelves":
			# The old boxes use the first three shelves. The fittings rest on the top.
			var surface := at + Vector3(side * 0.20, 1.635, 0)
			if site in ["police", "tower", "bunker", "lodge"]:
				source = "wood"
				for i in rng.randi_range(2, 4):
					var file := surface + Vector3((i-1)*0.108, 0.155, 0)
					parts.append([file, Vector3(0.092, 0.31, 0.285), Color("#70624d").lightened(i*0.09)])
					parts.append([file + Vector3(0, 0.033, -0.146), Vector3(0.058, 0.071, 0.014), PAPER])
			else:
				for i in rng.randi_range(2, 3):
					var can := surface + Vector3((i-1)*0.22, 0.10, 0)
					parts.append([can, Vector3(0.16, 0.20, 0.17), Color("#879387") if site=="hospital" else Color("#a4815e")])
					parts.append([can + Vector3.UP * 0.103, Vector3(0.17, 0.023, 0.18), STEEL])
		"lockers":
			var mark := Color("#a87657") if site == "fuel" else Color("#8a9ba5")
			for door in [-1, 1]:
				var p := at + Vector3(door*0.31, 1.01, -0.273)
				parts.append([p, Vector3(0.26, 0.13, 0.022), mark])
				parts.append([p + Vector3(0, 0, -0.013), Vector3(0.17, 0.052, 0.012), PAPER])
	# Only count structural stock, scaled for hollow metal cases or thin file boards.
	for i in range(start, parts.size()):
		var size: Vector3 = parts[i][1]
		var volume := size.x * size.y * size.z
		materials[source] = float(materials.get(source, 0.0)) + volume * (0.11 if source != "cloth" else 0.45)

static func _radio(parts: Array, p: Vector3, rng: RandomNumberGenerator) -> void:
	var case_color := Color("#5b6858").lightened(rng.randf_range(0.0, 0.10))
	parts.append([p + Vector3.UP * 0.125, Vector3(0.43, 0.25, 0.24), case_color])
	parts.append([p + Vector3(-0.052, 0.17, -0.123), Vector3(0.24, 0.052, 0.014), PAPER])
	for i in 3:
		parts.append([p + Vector3(-0.048, 0.053+i*0.026, -0.125), Vector3(0.24, 0.014, 0.018), RUBBER])
	parts.append([p + Vector3(0.14, 0.14, -0.135), Vector3(0.067, 0.067, 0.044), STEEL])
	var axis := Basis(Vector3.BACK, rng.randf_range(0.10, 0.31))
	parts.append([p + Vector3(0.15, 0.25, 0.07) + axis.y * 0.17, Vector3(0.018, 0.34, 0.018), STEEL, axis])

# A second pass adds paint, repairs and attached equipment to the render mesh.
# Its RNG is local so these details cannot change furniture or cache rolls.
const RUST := Color("#945c44")
const OCHRE := Color("#c69c58")
const CANVAS := Color("#748075")

static func add_wear(parts: Array, site: String, kind: String, at: Vector3, side: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		"cot":
			_cot_frame(parts, at, side, site, rng)
		"desk", "bench":
			_worktop(parts, at, side, site, rng)
		"shelves":
			_shelf_stock(parts, at, side, site, rng)
		"lockers":
			_locker_kit(parts, at, side, site, rng)

static func _cot_frame(parts: Array, at: Vector3, side: int, site: String, rng: RandomNumberGenerator) -> void:
	# Repaired feet and a horizontal rail tie the cot legs together.
	var finish := ENAMEL if site == "hospital" else STEEL
	parts.append([at + Vector3(0, 0.39, -0.205), Vector3(1.60, 0.08, 0.085), finish])
	for x: float in [-0.77, 0.77]:
		parts.append([at + Vector3(x, 0.06, -0.20), Vector3(0.085, 0.12, 0.095), RUBBER])
	# The board faces across the pillow and is fixed to the two end posts.
	var end := at + Vector3(side * 0.82, 0, 0)
	for z: float in [-0.29, 0.29]:
		parts.append([end + Vector3(0, 0.67, z), Vector3(0.047, 0.47, 0.05), finish])
	parts.append([end + Vector3.UP * 0.87, Vector3(0.055, 0.076, 0.63), finish])
	var blanket := at + Vector3(-side * 0.32, 0.66, -0.343)
	var color := Color("#879c97") if site == "hospital" else Color("#957850") if site == "cabin" else CANVAS
	# The folded end of the blanket hangs over the visible bed edge.
	parts.append([blanket + Vector3(0, -0.107, -0.013), Vector3(0.46, 0.214, 0.042), color])
	parts.append([blanket + Vector3(0, -0.166, -0.036), Vector3(0.46, 0.037, 0.015), color.lightened(0.27)])
	if site == "hospital":
		parts.append([at + Vector3(-side * 0.78, 0.53, 0.31), Vector3(0.10, 0.065, 0.12), RUBBER])
		parts.append([at + Vector3(-side * 0.60, 1.30, 0.31), Vector3(0.021, 0.27, 0.022), ENAMEL])
	else:
		var patch := blanket + Vector3(rng.randf_range(-0.11, 0.11), -0.075, -0.039)
		parts.append([patch, Vector3(0.145, 0.088, 0.013), color.darkened(0.28), Basis(Vector3.BACK, 0.08)])

static func _worktop(parts: Array, at: Vector3, side: int, site: String, rng: RandomNumberGenerator) -> void:
	# A metal edge protects the frequently used front of the bench.
	parts.append([at + Vector3(-side * 0.56, 0.786, -0.281), Vector3(0.58, 0.06, 0.025), STEEL])
	for x: float in [-0.79, -0.34]:
		parts.append([at + Vector3(side * x, 0.786, -0.298), Vector3(0.027, 0.027, 0.014), ENAMEL])
	if site == "fuel":
		# The service hose is hung from a saddle on the front apron.
		var hub := at + Vector3(side * 0.42, 0.51, -0.30)
		parts.append([hub + Vector3(0, 0.196, 0.018), Vector3(0.22, 0.095, 0.13), RUST])
		_loop(parts, hub, 0.195, 0.207, 0.046, RUBBER)
		parts.append([hub + Vector3(-0.184, -0.162, -0.022), Vector3(0.046, 0.29, 0.046), RUBBER])
		parts.append([hub + Vector3(-0.184, -0.314, -0.022), Vector3(0.066, 0.09, 0.059), STEEL])
		return
	# A short board is screwed to the rear edge, above the notes and instruments.
	var board := at + Vector3(0, 1.08, 0.235)
	for x: float in [-0.44, 0.44]:
		parts.append([board + Vector3(x, -0.10, 0.015), Vector3(0.055, 0.43, 0.048), STEEL])
	var finish := Color("#795d49") if site in ["police", "cabin"] else Color("#596b65")
	parts.append([board, Vector3(1.02, 0.36, 0.042), finish])
	if site == "cabin":
		# Bunches of dried seed heads hang upside down from a rack.
		for i in 3:
			var peg := board + Vector3(-0.30 + i * 0.29, 0.08, -0.056)
			parts.append([peg, Vector3(0.055, 0.055, 0.104), STEEL])
			parts.append([peg + Vector3(0, -0.11, -0.025), Vector3(0.04, 0.22, 0.045), CANVAS])
			parts.append([peg + Vector3(0, -0.21, -0.025), Vector3(0.14, 0.17, 0.09), OCHRE.darkened(0.09*i), Basis.IDENTITY, 0.30])
		return
	var chart := board + Vector3(-side * 0.14, 0, -0.032)
	var ink := Color("#728f95") if site in ["tower", "lodge"] else Color("#9f6358")
	parts.append([chart, Vector3(0.48, 0.28, 0.018), PAPER])
	parts.append([chart + Vector3(0, 0.126, -0.012), Vector3(0.13, 0.045, 0.018), STEEL])
	if site in ["tower", "lodge"]:
		# A shore survey has a continuous two-segment waterline and a marked station.
		parts.append([chart + Vector3(-0.077, 0, -0.012), Vector3(0.23, 0.04, 0.014), ink, Basis(Vector3.BACK, 0.32)])
		parts.append([chart + Vector3(0.102, 0.016, -0.013), Vector3(0.15, 0.04, 0.014), ink, Basis(Vector3.BACK, -0.27)])
		parts.append([chart + Vector3(-0.16, -0.04, -0.023), Vector3(0.045, 0.045, 0.018), RUST])
	else:
		# Patient charts have a colored header. Police notices have a clipped photo.
		parts.append([chart + Vector3(-0.035, 0.06, -0.014), Vector3(0.31, 0.028, 0.014), ink])
		var note := chart + Vector3(side * 0.34, rng.randf_range(-0.03, 0.03), -0.005)
		parts.append([note, Vector3(0.134, 0.172, 0.018), ENAMEL, Basis(Vector3.BACK, -0.10)])
		parts.append([note + Vector3(0, 0.01, -0.012), Vector3(0.09, 0.10, 0.015), ink.darkened(0.2)])

static func _shelf_stock(parts: Array, at: Vector3, side: int, site: String, rng: RandomNumberGenerator) -> void:
	var brace := Basis(Vector3.BACK, -side * 0.73)
	parts.append([at + Vector3(0, 0.88, 0.215), Vector3(0.064, 2.05, 0.038), STEEL, brace])
	# Edge cards and a bent replacement strip identify two separate shelf bays.
	for level in [1, 2]:
		var p := at + Vector3(side * 0.40, 0.16 + level * 0.48, -0.264)
		parts.append([p, Vector3(0.31, 0.082, 0.027), STEEL])
		parts.append([p + Vector3(0, 0, -0.018), Vector3(0.24, 0.052, 0.014), PAPER])
	# Previous tins and files occupy the opposite end of the upper board.
	var stock := at + Vector3(-side * 0.48, 1.635, 0)
	match site:
		"hospital", "bunker", "police":
			var color := ENAMEL if site == "hospital" else Color("#61776a") if site == "bunker" else Color("#7f6e59")
			parts.append([stock + Vector3.UP * 0.115, Vector3(0.32, 0.23, 0.35), color])
			parts.append([stock + Vector3.UP * 0.232, Vector3(0.33, 0.043, 0.36), color.darkened(0.20)])
			if site == "hospital":
				var mark := stock + Vector3(0, 0.122, -0.182)
				parts.append([mark, Vector3(0.135, 0.038, 0.014), RUST])
				parts.append([mark + Vector3.FORWARD * 0.004, Vector3(0.043, 0.131, 0.015), RUST])
			elif site == "bunker":
				for x: float in [-0.09, 0.09]:
					parts.append([stock + Vector3(x, 0.269, 0), Vector3(0.061, 0.063, 0.075), RUST if x > 0 else RUBBER])
			else:
				parts.append([stock + Vector3(0.055, 0.126, 0), Vector3(0.053, 0.26, 0.366), PAPER])
		"lodge", "fuel":
			# A ring or coiled hose is suspended from a bracket on the rack front.
			var hub := at + Vector3(-side * 0.42, 1.32, -0.31)
			parts.append([hub + Vector3(0, 0.218, 0.06), Vector3(0.10, 0.09, 0.15), STEEL])
			_loop(parts, hub, 0.208, 0.226, 0.078 if site == "lodge" else 0.044, RUST if site == "lodge" else RUBBER, site == "lodge")
		"tower":
			parts.append([stock + Vector3.UP * 0.067, Vector3(0.29, 0.134, 0.28), RUBBER])
			for x: float in [-0.084, 0.084]:
				parts.append([stock + Vector3(x, 0.172, -0.018), Vector3(0.128, 0.128, 0.31), STEEL])
				parts.append([stock + Vector3(x, 0.172, -0.179), Vector3(0.092, 0.092, 0.020), Color("#374950")])
		"cabin":
			parts.append([stock + Vector3.UP * 0.063, Vector3(0.37, 0.126, 0.31), Color("#88694a")])
			for i in 3:
				var packet := stock + Vector3(-0.11 + 0.10*i, 0.155, 0)
				parts.append([packet, Vector3(0.069, 0.19, 0.18), PAPER.darkened(0.065*i), Basis(Vector3.BACK, rng.randf_range(0.05, 0.18))])

static func _locker_kit(parts: Array, at: Vector3, side: int, site: String, rng: RandomNumberGenerator) -> void:
	var door := at + Vector3(side * 0.31, 0, 0)
	for h: float in [0.26, 1.30]:
		parts.append([door + Vector3(-0.22, h, -0.282), Vector3(0.075, 0.116, 0.026), RUST])
	# A folded apron, duty satchel or filter bag hangs below the door label.
	var color := Color("#96734f") if site == "fuel" else Color("#506473") if site == "police" else CANVAS
	var bag := door + Vector3(-0.03, 0.49, -0.32)
	var height := 0.52 if site == "fuel" else 0.28
	for x: float in [-0.093, 0.093]:
		parts.append([bag + Vector3(x, 0.23, 0.012), Vector3(0.039, 0.33, 0.036), color.darkened(0.22), Basis(Vector3.BACK, signf(x)*0.43)])
	parts.append([bag + Vector3(0, 0.38, 0.015), Vector3(0.10, 0.043, 0.11), STEEL])
	parts.append([bag, Vector3(0.32, height, 0.13), color, Basis.IDENTITY, 0.91])
	parts.append([bag + Vector3(0, 0.044, -0.061), Vector3(0.32, 0.13, 0.039), color.lightened(0.13)])
	parts.append([bag + Vector3(0.052, 0.028, -0.085), Vector3(0.044, 0.074, 0.019), STEEL])
	var chip := at + Vector3(-side * 0.32, 0.17, -0.275)
	parts.append([chip, Vector3(rng.randf_range(0.16, 0.24), 0.049, 0.014), RUST, Basis(Vector3.BACK, 0.061)])

# Eight joined strips leave a real opening through the loop.
static func _loop(parts: Array, hub: Vector3, rx: float, ry: float, width: float, color: Color, banded := false) -> void:
	for i in 8:
		var a := TAU * i / 8.0
		var b := TAU * (i + 1) / 8.0
		var start := Vector2(cos(a)*rx, sin(a)*ry)
		var finish := Vector2(cos(b)*rx, sin(b)*ry)
		var mid := (start + finish)*0.5
		var axis := Basis(Vector3.BACK, (finish-start).angle())
		var tint := ENAMEL if banded and i % 2 == 1 else color
		parts.append([hub + Vector3(mid.x, mid.y, 0), Vector3(start.distance_to(finish) + width*0.40, width, width), tint, axis])

static func add_trade_fittings(parts: Array, kind: String, at: Vector3, side: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		"grain_bin":
			# The surviving front boards carry a batch ticket and two riveted straps.
			for x: float in [-0.72, 0.72]:
				parts.append([at + Vector3(x, 0.32, 0.777), Vector3(0.097, 0.52, 0.035), STEEL])
				for h: float in [0.15, 0.46]:
					parts.append([at + Vector3(x, h, 0.798), Vector3(0.049, 0.049, 0.023), RUST])
			var label := at + Vector3(side * 0.32, 0.44, 0.781)
			parts.append([label, Vector3(0.49, 0.195, 0.027), RUBBER])
			parts.append([label + Vector3.BACK * 0.02, Vector3(0.42, 0.149, 0.022), PAPER])
			parts.append([label + Vector3(-0.136, 0, 0.035), Vector3(0.047, 0.120, 0.014), OCHRE])
			# A strip of coarse sacking is trapped under a plank at the splintered lip.
			var flap := at + Vector3(-side * 0.36, 0.49, 0.80)
			parts.append([flap, Vector3(0.32, 0.19, 0.045), CANVAS, Basis(Vector3.BACK, -0.09)])
		"repair_stand":
			# The shallow drain pan has a recessed oil surface between raised rims.
			var pan := at + Vector3(0, 0.04, rng.randf_range(-0.48, 0.24))
			parts.append([pan, Vector3(0.71, 0.073, 0.81), STEEL])
			parts.append([pan + Vector3.UP * 0.04, Vector3(0.61, 0.018, 0.70), RUBBER])
			for x: float in [-0.33, 0.33]:
				parts.append([pan + Vector3(x, 0.067, 0), Vector3(0.052, 0.096, 0.81), STEEL])
			for z: float in [-0.38, 0.38]:
				parts.append([pan + Vector3(0, 0.067, z), Vector3(0.61, 0.096, 0.052), STEEL])
			for x: float in [-0.64, 0.64]:
				for i in 3:
					parts.append([at + Vector3(x, 0.992, 0.80 + i*0.183), Vector3(0.25, 0.015, 0.096), OCHRE, Basis(Vector3.UP, 0.15)])
		"tool_rack":
			# A folded tray with socket heads in size order occupies one end.
			var tray := at + Vector3(-0.48*side, 0.838, -0.07)
			parts.append([tray, Vector3(0.70, 0.056, 0.34), RUST])
			for i in 4:
				var socket := tray + Vector3(-0.23 + i*0.15, 0.027, 0)
				var width := 0.075 + 0.013*i
				parts.append([socket + Vector3.UP*0.057, Vector3(width, 0.114, width), STEEL.lightened(0.2)])
				parts.append([socket + Vector3.UP*0.119, Vector3(width*0.48, 0.012, width*0.48), RUBBER])
			parts.append([at + Vector3(side * 0.66, 1.15, 0.116), Vector3(0.31, 0.107, 0.034), PAPER])
		"parcel_counter":
			# A stamp with a tapered handle sits beside its ink pad at the clerk's end.
			var pad := at + Vector3(-side*0.66, 1.106, -0.03)
			parts.append([pad, Vector3(0.30, 0.053, 0.22), STEEL])
			parts.append([pad + Vector3.UP*0.031, Vector3(0.25, 0.022, 0.174), RUBBER])
			var stamp := pad + Vector3(side*0.25, -0.004, 0)
			parts.append([stamp, Vector3(0.14, 0.045, 0.14), RUBBER])
			parts.append([stamp + Vector3.UP*0.093, Vector3(0.108, 0.15, 0.108), RUST, Basis.IDENTITY, 0.55])
			parts.append([stamp + Vector3.UP*0.19, Vector3(0.136, 0.056, 0.136), RUST])
			for i in 2:
				var slip := at + Vector3(side*(0.05 + 0.05*i), 1.088 + 0.014*i, 0.08)
				parts.append([slip, Vector3(0.34, 0.017, 0.22), PAPER.lightened(0.10*i), Basis(Vector3.UP, 0.09*i)])
			# A worn kickplate follows the counter front below the wood beading.
			parts.append([at + Vector3(0, 0.10, 0.106), Vector3(2.44, 0.16, 0.028), STEEL])
		"sorting_case":
			# Metal ticket holders sit on the shelf lips facing the sorting clerk.
			for shelf in 3:
				for x: float in [-0.61, 0, 0.61]:
					var label := at + Vector3(x, 0.17 + shelf*0.53, 0.267)
					parts.append([label, Vector3(0.25, 0.077, 0.028), STEEL])
					if shelf != 2 or x != 0:
						parts.append([label + Vector3.BACK*0.018, Vector3(0.19, 0.044, 0.014), PAPER.darkened(0.07*shelf)])
			var mail := at + Vector3(side*0.39, 1.855, 0)
			parts.append([mail, Vector3(0.53, 0.109, 0.33), PAPER, Basis.IDENTITY, 0.94])
			parts.append([mail, Vector3(0.046, 0.124, 0.345), Color("#945c44")])
