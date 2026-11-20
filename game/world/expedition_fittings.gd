extends RefCounted

const WOOD := Color("#977652")
const IRON := Color("#425553")
const RUST := Color("#9f5e42")
const BONE := Color("#cec3a3")
const OCHRE := Color("#c3914c")

# Local metres on the member. Everything is baked into its original draw surface.
static func fit(body: StaticBody3D, site: String, member: String, size: Vector3, color: Color, wear: int) -> void:
	var parts := []
	match site:
		"shelter":
			if member.begins_with("roof"):
				var face := size.y * 0.5
				for seam in range(5):
					var z := size.z * (seam - 2) / 5.0
					parts.append([Vector3(0, face + 0.018, z), Vector3(size.x, 0.044, 0.056), color.darkened(0.23)])
				var edge := -1 if member.ends_with("-1") else 1
				parts.append([Vector3(edge*(size.x*0.5-0.04), face, 0), Vector3(0.10,0.105,size.z), Color("#6e6353")])
			elif member == "windbreak":
				for row in 6:
					var y := (row - 2.5)*0.244
					var split := -0.82 + 0.61 * posmod(row + wear, 4)
					for side: int in [-1, 1]:
						var end := size.x * side * 0.5
						parts.append([Vector3((end+split)*0.5,y,0), Vector3(absf(end-split)-0.018,0.221,size.z+0.045), WOOD.darkened(0.06*posmod(row+side+wear,4))])
				for x: float in [-1.38, 1.38]:
					parts.append([Vector3(x,0,0.137), Vector3(0.13,1.41,0.075), WOOD.darkened(0.34)])
			elif member.begins_with("ridgepost"):
				for y: float in [-0.11, 0.02]:
					parts.append([Vector3(0,size.y*0.5-0.25+y,0), Vector3(size.x+0.028,0.075,size.z+0.028),IRON])
		"weather":
			if member == "mast":
				for i in 3:
					parts.append([Vector3(0,size.y*(i*0.27-0.29),0),Vector3(0.28,0.092,0.28),RUST])
				var housing := Vector3(0.18,-1.22,0)
				parts.append([housing,Vector3(0.51,0.67,0.39),IRON])
				for i in 5:
					parts.append([housing+Vector3(0,0.23-i*0.104,0.012),Vector3(0.57,0.070,0.44),BONE.darkened(0.05*(i%2)),Basis(Vector3.RIGHT,-0.08)])
				parts.append([housing+Vector3.UP*0.385,Vector3(0.66,0.075,0.50),RUST,Basis(Vector3.RIGHT,-0.09)])
			elif member.begins_with("cup"):
				# The shadowed bowl and chipped rim read even when the station is silhouetted.
				parts.append([Vector3(0,size.y*0.49,0),Vector3(0.40,0.055,0.40),OCHRE])
				parts.append([Vector3(0,size.y*0.5+0.028,0),Vector3(0.28,0.018,0.28),IRON.darkened(0.40)])
		"canal":
			if member == "gate":
				for board in 8:
					var x := size.x*(board-3.5)/8.0
					parts.append([Vector3(x,-0.012,0),Vector3(size.x/8.0-0.017,size.y-0.035,size.z+0.034),WOOD.darkened(0.07*posmod(board+wear,4))])
				for x: float in [-0.75,0.75]:
					parts.append([Vector3(x,0,0.13),Vector3(0.13,1.47,0.063),IRON])
					for y: float in [-0.53,0.48]:
						parts.append([Vector3(x,y,0.167),Vector3(0.066,0.067,0.027),OCHRE.darkened(0.25)])
				parts.append([Vector3(0,0.65,0),Vector3(size.x+0.10,0.18,0.31),IRON])
				parts.append([Vector3(0,0.79,0),Vector3(0.17,0.25,0.16),RUST])
				# Front-mounted handwheel with its hub and four bearing spokes.
				var hub := Vector3(0,0.82,0.185)
				parts.append([hub-Vector3.BACK*0.085,Vector3(0.10,0.10,0.24),IRON])
				for sector in 8:
					var a := sector * TAU/8
					var mid := hub+Vector3(sin(a),cos(a),0)*0.218
					parts.append([mid,Vector3(0.191,0.044,0.044),RUST,Basis(Vector3.BACK,-a)])
					if sector%2==0:
						parts.append([hub.lerp(mid,0.5),Vector3(0.037,0.22,0.037),IRON,Basis(Vector3.BACK,-a)])
			elif member.begins_with("bank") and member != "bankfall":
				var stones := maxi(3,roundi(size.z/0.82))
				for i in stones:
					var z := size.z*((i+0.5)/stones-0.5)
					parts.append([Vector3(0,size.y*0.44,z),Vector3(size.x+0.052,0.13,size.z/stones-0.035),color.lightened(0.07*posmod(i+wear,3))])
		"well":
			if member == "pipe":
				for h: float in [-0.77,0.16,0.67]:
					parts.append([Vector3(0,h,0),Vector3(0.33,0.09,0.33),RUST])
				parts.append([Vector3(-0.17,0.35,0),Vector3(0.46,0.16,0.18),IRON])
				parts.append([Vector3(-0.36,0.28,0),Vector3(0.16,0.24,0.17),IRON])
				parts.append([Vector3(-0.36,0.148,0),Vector3(0.19,0.055,0.20),RUST])
			elif member == "lever":
				parts.append([Vector3(size.x*0.30,0,0),Vector3(0.44,0.175,0.20),WOOD])
				parts.append([Vector3(-size.x*0.40,0,0),Vector3(0.16,0.16,0.27),IRON])
			elif member.begins_with("rim"):
				parts.append([Vector3(0,size.y*0.42,0),Vector3(size.x*0.98,0.12,size.z+0.09),color.lightened(0.19)])
				if size.y>0.5:
					parts.append([Vector3(size.x*0.10,-0.06,size.z*0.5),Vector3(size.x*0.75,0.032,0.02),color.darkened(0.30)])
	if parts.is_empty(): return
	parts.push_front([Vector3.ZERO,size,color])
	var visual := body.get_child(0) as MeshInstance3D
	visual.set_meta("structural_volume",size.x*size.y*size.z)
	visual.scale=Vector3.ONE
	visual.mesh=preload("res://game/world/building_mesh.gd").boxes(parts)
	visual.material_override=WastelandLook.colored_material()
