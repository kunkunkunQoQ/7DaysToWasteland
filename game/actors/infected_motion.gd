extends RefCounted

const Action := WastelandCreatureBrain.Action
const State := WastelandCreatureBrain.State

# Keep terminal contacts in actor space. The torso may twist, flinch or lean while
# a planted foot or palm follows the distance travelled during its support phase.
static func support(a: WastelandCreature) -> void:
	var moving := smoothstep(0.015,0.55,a.motion_speed)
	var prone := a.type == "crawler" or a.low_crawl()
	var running := smoothstep(1.2,4.1,a.motion_speed)
	var stance := 0.58 if prone else lerpf(0.55,0.35,running)
	var step := a.stride_length(a.motion_speed)*stance*moving
	var scale_y := a.rig.scale.y
	var normal := a.motion_floor_normal
	var slope := Quaternion(Vector3.UP,normal)
	var stride_axis := a.stride_axis(a.global_basis)
	if prone:
		a.rig.quaternion = slope*a.rig.quaternion
		a.rig.position = slope*a.rig.position
	else:
		var load := maxf(a.windup,a.attack)
		a.rig.position.y -= (0.035+moving*(0.065+running*0.088)+load*0.045)*scale_y
		if a.limb_damage.z > 0 and a.limb_damage.w > 0:
			a.rig.position.y -= 0.08 * scale_y
		a.rig.position.y -= minf(0.15,Vector2(normal.x,normal.z).length()*0.27)*scale_y
		a.rig.position.x = (sin(a.pose_phase)*moving*0.022+signi(a.limb_damage.z-a.limb_damage.w)*0.034)*a.rig.scale.x
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var suffix := "_l" if i == 0 else "_r"
		var cycle := fposmod(a.pose_phase/TAU+0.5*i,1.0)
		var swing := clampf((cycle-stance)/(1.0-stance),0.0,1.0)
		var along := cycle/stance-0.5 if cycle<stance else 0.5-smoothstep(0.0,1.0,swing)
		var lift := sin(PI*swing)*moving
		if prone:
			var arm := a.skeleton.find_bone("arm"+suffix)
			var shoulder := a.rig.transform*a.skeleton.get_bone_global_pose(arm).origin
			var severity := a.limb_damage[i]
			var target := shoulder + Vector3(side*0.053*a.rig.scale.x,0,-0.055*a.rig.scale.z) + stride_axis*along*step
			target.y = (0.052+0.095*lift)*scale_y
			if severity > 0:
				target.y = (0.024+0.051*lift)*scale_y
				target.z += 0.043*a.rig.scale.z
			var grip := a.type == "brute" and not a.biting() and i == (0 if a.limb_damage.y > 0 else 1)
			if grip:
				target.y += 0.115*scale_y
			var striking := not a.biting() and (a.type == "crawler" or i == (0 if a.limb_damage.y > 0 else 1))
			if striking:
				target += Vector3(0,a.windup*0.15+a.attack*0.08,-a.attack*0.21)*scale_y
			var reaching := striking and (a.windup > 0.03 or a.attack > 0.03)
			var support_bone := StringName(("hand" if severity == 0 else "elbow")+suffix)
			target = a.foot_contacts.target(i, support_bone, a.global_transform, target, not reaching and (cycle < stance or moving < 0.01), 1.0 if reaching else swing, 0.24 * scale_y)
			target.y = _surface_y(target,normal)
			_reach(a,"arm"+suffix,"elbow"+suffix,"hand"+suffix,target,Vector3(side*0.82,0.30,0.95),0.55 if severity == 2 else 1.0)
			if severity == 0:
				_level_tip(a,"hand"+suffix,0.06 if grip else -0.21*lift)
			if a.type == "crawler":
				var damage := a.limb_damage[2+i]
				var remaining := 1.0 if damage == 0 else 0.87 if damage == 1 else 0.52
				var toe := Vector3(side*0.210,0.066 if damage == 0 else 0.025,0.525-(1.0-remaining)*0.349)*a.rig.scale
				toe -= stride_axis*along*step*0.72
				toe.y += maxf(0.0,sin(TAU*cycle))*0.065*moving*scale_y
				var heel := StringName(("ankle" if damage == 0 else "knee")+suffix)
				toe = a.foot_contacts.target(2+i, heel, a.global_transform, toe, cycle >= 0.5 or moving < 0.01, minf(1.0,cycle*2.0), 0.19*scale_y)
				toe.y = _surface_y(toe,normal)
				_reach(a,"leg"+suffix,"knee"+suffix,"ankle"+suffix,toe,Vector3(side*0.30,-0.48,-1.0),remaining)
				_level_tip(a,"ankle"+suffix,0.10*lift)
		elif a.limb_damage[2+i] == 0 or (a.limb_damage.z > 0 and a.limb_damage.w > 0):
			var stump := a.limb_damage[2+i] > 0
			var leg := a.skeleton.find_bone("leg"+suffix)
			var hip_x := a.skeleton.get_bone_rest(leg).origin.x
			var pitch := 0.0
			if cycle < stance:
				var contact := cycle/stance
				pitch = 0.25*(1.0-smoothstep(0.0,0.28,contact))-0.43*smoothstep(0.66,1.0,contact)
			else:
				pitch = lerpf(-0.43,0.25,smoothstep(0.0,0.9,swing))
			pitch *= moving
			var sole_y := 0.089*cos(pitch)+maxf(0.075*sin(pitch),-0.197*sin(pitch))
			if stump: sole_y = 0.019
			var height := 0.096+running*0.10+(0.07 if a.motion_water else 0.0)
			var target := Vector3(hip_x+side*0.013,sole_y+lift*height,side*0.016)*a.rig.scale
			target += stride_axis*along*step
			var support_bone := StringName(("knee" if stump else "ankle")+suffix)
			target = a.foot_contacts.target(i, support_bone, a.global_transform, target, cycle < stance or moving < 0.01, swing, 0.30 * scale_y)
			target.y = _surface_y(target,normal)
			_reach(a,"leg"+suffix,"knee"+suffix,"ankle"+suffix,target,Vector3(side*0.10,0,-1),0.95 if stump else 1.0)
			if not stump: _level_tip(a,"ankle"+suffix,pitch)

static func _surface_y(target: Vector3, normal: Vector3) -> float:
	return (target.y-normal.x*target.x-normal.z*target.z)/maxf(normal.y,0.35)

static func _reach(a: WastelandCreature, upper: String, lower: String, tip: String, target: Vector3, pole: Vector3, length_factor := 1.0) -> void:
	var sk := a.skeleton
	var upper_id := sk.find_bone(upper)
	var lower_id := sk.find_bone(lower)
	var parent := a.rig.transform*sk.get_bone_global_pose(sk.get_bone_parent(upper_id))
	var delta := parent.affine_inverse()*target-sk.get_bone_rest(upper_id).origin
	var upper_rest := sk.get_bone_rest(lower_id).origin
	var lower_rest := sk.get_bone_rest(sk.find_bone(tip)).origin*length_factor
	var l1 := upper_rest.length()
	var l2 := lower_rest.length()
	var d := clampf(delta.length(),absf(l1-l2)+0.001,l1+l2-0.0001)
	var direction := delta.normalized()
	var outward := (parent.basis.inverse()*pole).slide(direction).normalized()
	var along := (d*d+l1*l1-l2*l2)/(2.0*d)
	var bend := direction*along+outward*sqrt(maxf(0.0,l1*l1-along*along))
	var first := Quaternion(upper_rest.normalized(),bend.normalized())
	var second := Quaternion(lower_rest.normalized(),first.inverse()*(direction*d-bend).normalized())
	sk.set_bone_pose_rotation(upper_id,first)
	sk.set_bone_pose_rotation(lower_id,second)

static func _level_tip(a: WastelandCreature, label: String, pitch: float) -> void:
	var id := a.skeleton.find_bone(label)
	var parent := a.rig.transform*a.skeleton.get_bone_global_pose(a.skeleton.get_bone_parent(id))
	var surface := Basis(Quaternion(Vector3.UP,a.motion_floor_normal))
	var basis := parent.basis.orthonormalized().inverse()*surface*Basis(Vector3.RIGHT,pitch)
	a.skeleton.set_bone_pose_rotation(id,basis.get_rotation_quaternion())

static func melee(a: WastelandCreature) -> void:
	var preparing := a.attack_kind in [Action.MELEE,Action.SMASH] and a.windup > 0.0
	if not preparing and (a.attack <= 0.0 or a.motion_action not in [Action.NONE,Action.MELEE,Action.SMASH]):
		return
	var sweep := smoothstep(0.70,0.99,a.windup) if preparing else smoothstep(0.0,0.76,a.attack)
	var load := smoothstep(0.02,0.65,a.windup)*(1.0-sweep) if preparing else 0.0
	var strength := maxf(sweep,load)
	if a.biting():
		var prone_pitch := 0.92 if a.low_crawl() and a.type != "crawler" else 0.0
		a._pose_bone("head",Vector3(prone_pitch+0.26*load-0.54*sweep,0,-0.06*sweep),strength)
		return
	if a.low_crawl() or a.type == "crawler":
		return
	var left := a.limb_damage.y > 0
	var suffix := "_l" if left else "_r"
	var side := -1.0 if left else 1.0
	var heavy := a.type == "brute"
	var shoulder := 2.36*load+1.25*sweep if heavy else -0.57*load+1.58*sweep
	a._pose_bone("arm"+suffix,Vector3(shoulder,side*(0.28*load-0.14*sweep),side*(0.49*load+0.13*sweep)),strength)
	a._pose_bone("elbow"+suffix,Vector3(0.95*load+0.16*sweep,-side*0.12,0),strength)
	if a.type == "spitter" and not left and a.limb_damage.x == 0:
		a._pose_bone("arm_l",Vector3(0.46+0.60*sweep,0.06,-0.20),strength)
	a._pose_bone("torso",Vector3(0.08*load-0.28*sweep,side*(-0.42*load+0.28*sweep),side*(0.08*load-0.09*sweep)),strength)
	a._pose_bone("head",Vector3(0.06+0.10*sweep,side*(0.22*load-0.23*sweep),0),strength)

static func special(a: WastelandCreature) -> void:
	var kind := a.attack_kind if a.attack_kind != Action.NONE else a.motion_action
	var inhale := smoothstep(0.0,0.87,a.windup)
	var release := smoothstep(0.0,0.85,a.attack)
	var weight := maxf(inhale,release)
	if weight <= 0.0: return
	var prone := a.low_crawl()
	var neck := 0.92 if prone and a.type != "crawler" else 0.0
	match kind:
		Action.SPIT:
			a._pose_bone("head",Vector3(neck+0.52*inhale-0.59*release,-0.06*inhale,0),weight)
			a._pose_bone("torso",Vector3(-0.25*inhale-0.05-0.23*release,0.10*inhale,0),weight)
		Action.SCREAM,Action.MEND:
			a._pose_bone("head",Vector3(neck+0.40*inhale+0.21*release,0,-0.09),weight)
			a._pose_bone("torso",Vector3(0.12*inhale-0.16*release,0,0),weight)
			if not prone:
				for i in 2:
					var side := -1.0 if i == 0 else 1.0
					var suffix := "_l" if i == 0 else "_r"
					var arch := 1.15 if kind == Action.MEND else 0.57
					a._pose_bone("arm"+suffix,Vector3(0.55+arch*inhale+0.36*release,side*0.09,side*(0.35+0.54*release)),weight)
					a._pose_bone("elbow"+suffix,Vector3(0.35+0.31*inhale,0,0),weight)
		Action.RUPTURE:
			if prone:
				a._pose_bone("torso",Vector3(0.23*inhale,0,0),weight)
				a._pose_bone("head",Vector3(neck+0.22*inhale,0,0),weight)

static func grounded_pose(a: WastelandCreature, tilt: float) -> void:
	var dead := a.brain.state == State.DEAD
	var asleep := a.brain.state in [State.SLEEPING,State.WAKING]
	var prone := a.type == "crawler" or a.low_crawl()
	var breath := sin(a.motion_clock*1.52)*0.022 if asleep else 0.0
	var pushing := sin(tilt*PI) if a.brain.state in [State.WAKING,State.KNOCKDOWN] else 0.0
	a.rig.rotation.z += tilt*(0.61 if prone else 1.49)
	a.rig.position.y += (0.17 if prone else 0.21)*tilt*a.rig.scale.y
	if not prone:
		var slope := Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP,a.motion_floor_normal),tilt)
		a.rig.quaternion = slope*a.rig.quaternion
	a._pose_bone("hips",Vector3(-0.06,-0.19,0.04),tilt)
	a._pose_bone("torso",Vector3(-0.18+breath,-0.20,0.07),tilt)
	a._pose_bone("head",Vector3(0.42 if a.low_crawl() and a.type != "crawler" else -0.11,-0.21,0.13+breath),tilt)
	for i in 2:
		var suffix := "_l" if i == 0 else "_r"
		var side := -1.0 if i == 0 else 1.0
		a._pose_bone("arm"+suffix,Vector3((0.99 if i == 0 else 0.41)+pushing*0.26,side*0.14,side*(0.25 if dead else 0.08)),tilt)
		a._pose_bone("elbow"+suffix,Vector3((0.30 if dead else 0.97)-pushing*0.26,side*0.10,0),tilt)
		var wrist := a.skeleton.find_bone("hand"+suffix)
		var rest := a.skeleton.get_bone_rest(wrist).basis.get_rotation_quaternion()
		a.skeleton.set_bone_pose_rotation(wrist,a.skeleton.get_bone_pose_rotation(wrist).slerp(rest,tilt))
		var fold := (0.38 if dead else 0.66) if i == 0 else (0.12 if dead else 0.39)
		if prone: fold *= 0.4
		a._pose_bone("leg"+suffix,Vector3(fold+pushing*0.21,side*0.07,side*0.04),tilt)
		a._pose_bone("knee"+suffix,Vector3(-fold*1.4-pushing*0.34,0,0),tilt)
		a._pose_bone("ankle"+suffix,Vector3(-0.15*side,0,0),tilt)
	_settle(a,tilt)

static func _settle(a: WastelandCreature, tilt: float) -> void:
	if a.rest_contacts.is_empty():
		for joint: String in a.body_parts:
			_collect(a,a.body_parts[joint],a.skeleton.find_bone(joint),Transform3D.IDENTITY)
	var floor_distance := INF
	var normal := a.motion_floor_normal
	for row in a.rest_contacts:
		var at: Transform3D = a.rig.transform*a.skeleton.get_bone_global_pose(row.bone)*row.local
		var mesh: Mesh = row.mesh
		var bounds: AABB = at*mesh.get_aabb()
		if normal.dot(bounds.get_support(-normal)) >= floor_distance:
			continue
		for point in _support_points(mesh):
			floor_distance = minf(floor_distance,normal.dot(at*point))
	if is_finite(floor_distance):
		a.rig.position.y -= floor_distance*tilt/maxf(normal.y,0.35)

static func _collect(a: WastelandCreature, node: Node3D, bone: int, at: Transform3D) -> void:
	if not node.visible: return
	if node is MeshInstance3D and node.mesh != null:
		a.rest_contacts.append({"bone":bone,"local":at,"mesh":node.mesh})
	for child in node.get_children():
		if child is Node3D: _collect(a,child,bone,at*child.transform)

# Select real surface vertices spread over the hull. All actors sharing a mesh
# reuse these points, and most bones are excluded by their bounds before sampling.
static func _support_points(mesh: Mesh) -> PackedVector3Array:
	if mesh.has_meta("infected_support"):
		return mesh.get_meta("infected_support")
	var points := PackedVector3Array()
	var bounds := mesh.get_aabb()
	var center := bounds.get_center()
	var size := bounds.size.max(Vector3.ONE*0.001)
	var extremes := {}
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var radial := (vertex-center)/size
			var cell := Vector3i((radial*3.0).round())
			if not extremes.has(cell) or radial.length_squared() > ((Vector3(extremes[cell])-center)/size).length_squared():
				extremes[cell] = vertex
	for point: Vector3 in extremes.values():
		points.append(point)
	mesh.set_meta("infected_support",points)
	return points
