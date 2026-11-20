extends RefCounted

# Grip coordinates use the wrapped section of the item as origin, with Y along its handle.
const CENTER := Vector3(0.102,-0.010,-0.285)

static func handle_radius(id: String, item: Dictionary) -> float:
	if item.get("shield",false): return 0.024
	if id in ["reed_spear","iron_pick","field_sickle","baton"]: return 0.043
	if id == "meme_hammer": return 0.035
	if id == "salvage_wrench": return 0.042
	if item.get("kind","") in ["tool","weapon"]: return 0.049
	return 0.0

static func socket(id: String, item: Dictionary) -> Vector3:
	if item.get("shield",false): return Vector3.ZERO
	if id == "salvage_wrench": return Vector3(0.008,-0.17,0)
	if id == "meme_hammer": return Vector3.DOWN*0.048
	return Vector3.DOWN*(0.12 if id in ["reed_spear","iron_pick","field_sickle","baton"] else 0.139)

static func frame(axis: Vector3) -> Transform3D:
	var up := axis.normalized()
	var across := Vector3.RIGHT.slide(up).normalized()
	return Transform3D(Basis(across,up,across.cross(up)),CENTER)

static func radial(angle: float, radius: float, height: float) -> Vector3:
	var a := deg_to_rad(angle)
	return Vector3(cos(a)*radius,height,sin(a)*radius)

# Joint centres trace the outside of the handle. Each fingertip turns back towards
# the palm. A little finger cannot reach as far around an axe as it can around a shield grip.
static func finger_path(grip: Transform3D, radius: float, i: int, size: float) -> PackedVector3Array:
	var level: float = [0.037,0.012,-0.012,-0.035][i]*size
	var pad: float = [0.012,0.013,0.012,0.010][i]*size
	var reach: float = [211.0,225.0,208.0,183.0][i]-clampf((radius-0.024)/0.022,0,1)*38.0
	var start: float = [26.0,18.0,9.0,3.0][i]
	var slope: float = [-0.014,-0.009,-0.004,0.003][i]*size
	var surface := radius+pad*0.79
	var path := PackedVector3Array()
	for sample: Vector3 in [
		radial(start-11,surface+0.010,level-0.004),
		radial(start+12,surface+0.004,level+0.003),
		radial(start+39,surface,level+0.005),
		radial(lerpf(start,reach,0.51),surface,level+slope*0.35),
		radial(lerpf(start,reach,0.75),surface-0.001,level+slope*0.70),
		radial(reach-12,surface-0.002,level+slope),
		radial(reach,surface-0.004,level+slope+0.001)]:
		path.append(grip*sample)
	return path

static func thumb_path(grip: Transform3D, radius: float, size: float) -> PackedVector3Array:
	var surface := radius+0.012*size
	var reach := 127.0+clampf((0.045-radius)/0.025,0,1)*19.0
	var path := PackedVector3Array()
	for sample: Vector3 in [
		Vector3(radius+0.022,-0.008,0.074),
		Vector3(radius+0.018,0.010,0.057),
		radial(45,surface+0.011,0.036*size),
		radial(65,surface+0.007,0.052*size),
		radial(87,surface+0.009,0.052*size),
		radial(109,surface+0.013,0.043*size),
		radial(reach,surface+0.013,0.030*size)]:
		path.append(grip*sample)
	return path

static func sculpt(mesh, grip: Transform3D, radius: float, skin: Color, breadth: float) -> void:
	var size := lerpf(1,breadth,0.36)
	# Forearm to fingertips is one continuous set of palm sections. At the grip
	# the breadth of the palm runs up the handle, placing the knuckles in a sloping row.
	var centers := PackedVector3Array([Vector3(0.129,-0.295,0.76),Vector3(0.129,-0.184,0.5),
		Vector3(0.129,-0.104,0.22),Vector3(0.139,-0.066,0.012),Vector3(0.151,-0.052,-0.128),
		grip*Vector3(radius+0.028,-0.025,0.100),grip*Vector3(radius+0.025,-0.014,0.068),
		grip*Vector3(radius+0.020,-0.006,0.041),grip*radial(35,radius+0.021,0.001),
		grip*radial(22,radius+0.016,0.001)])
	var widths := [0.093*breadth,0.076*breadth,0.082*breadth,0.058,0.039,0.040,0.051,0.055,0.053,0.045]
	var depths := [0.086*breadth,0.074*breadth,0.071*breadth,0.049,0.030,0.029,0.027,0.024,0.021,0.014]
	var previous := PackedVector3Array()
	mesh.buffer.set_smooth_group(0)
	for i in centers.size():
		var tangent := (centers[mini(i+1,centers.size()-1)]-centers[maxi(0,i-1)]).normalized()
		var across := Vector3.RIGHT.lerp(grip.basis.y,smoothstep(2.0,7.0,float(i))).slide(tangent).normalized()
		var depth := tangent.cross(across).normalized()
		var ring := PackedVector3Array()
		for j in 20:
			var angle := TAU*j/20
			ring.append(centers[i]+across*cos(angle)*float(widths[i])+depth*sin(angle)*float(depths[i]))
		if i>0:
			for j in 20:
				var k := (j+1)%20
				var normal := (previous[j]+previous[k]+ring[j]+ring[k])*0.25-(centers[i-1]+centers[i])*0.5
				mesh.triangle(previous[j],ring[j],previous[k],normal,skin)
				mesh.triangle(previous[k],ring[j],ring[k],normal,skin)
				if i==centers.size()-1: mesh.triangle(ring[k],ring[j],centers[i],tangent,skin)
		previous=ring
	mesh.buffer.set_smooth_group(-1)
	for i in 4:
		var pad: float = [0.012,0.013,0.012,0.010][i]*size
		var path := finger_path(grip,radius,i,size)
		_digit(mesh,grip,path,[1.24,1.22,1.09,1.0,0.90,0.76,0.35],pad,skin)
	var thumb := thumb_path(grip,radius,size)
	_digit(mesh,grip,thumb,[1.15,1.40,1.32,1.15,0.97,0.83,0.45],0.015*size,skin)

static func _digit(mesh, grip: Transform3D, path: PackedVector3Array, widths: Array, pad: float, skin: Color) -> void:
	# Align the slightly flattened pads to the object, including on the far side.
	var previous := PackedVector3Array()
	mesh.buffer.set_smooth_group(0)
	for i in path.size():
		var tangent := (path[mini(i+1,path.size()-1)]-path[maxi(0,i-1)]).normalized()
		var radial_out := (path[i]-grip.origin).slide(grip.basis.y).slide(tangent).normalized()
		var sideways := tangent.cross(radial_out).normalized()
		var radius: float = pad*widths[i]
		var ring := PackedVector3Array()
		for j in 12:
			var angle := TAU*j/12
			ring.append(path[i]+(radial_out*cos(angle)*0.89+sideways*sin(angle))*radius)
		if i>0:
			for j in 12:
				var k := (j+1)%12
				var normal := (ring[j]+ring[k])*0.5-path[i]
				mesh.triangle(previous[j],ring[j],previous[k],normal,skin)
				mesh.triangle(previous[k],ring[j],ring[k],normal,skin)
				if i==path.size()-1: mesh.triangle(path[i],ring[j],ring[k],tangent,skin)
		previous=ring
	mesh.buffer.set_smooth_group(-1)
	var tip := path[-2].lerp(path[-1],0.15)
	var forward := (path[-1]-path[-3]).normalized()
	var dorsal := (tip-grip.origin).slide(grip.basis.y).slide(forward).normalized()
	var nail_frame := Basis(dorsal.cross(forward),dorsal,forward)
	mesh.loft([Vector4(-0.001,pad*0.43,pad*0.60,0),Vector4(0,pad*0.49,pad*0.68,0),
		Vector4(0.0018,pad*0.39,pad*0.50,0)],skin.lerp(Color("#d5aba2"),0.38),tip+dorsal*pad*0.63,nail_frame,10)
