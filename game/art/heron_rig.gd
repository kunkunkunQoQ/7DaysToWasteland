extends "res://game/art/water_skeleton.gd"

const SKULL := Vector3(0,1.60,-0.25)
const RADII := Vector3(0.11,0.106,0.166)
const MASK_AT := Vector3(0,1.65,-0.402)
const MASK_SIZE := Vector2(0.27,0.31)
const NECK := Vector3(0,1.02,-0.22)
const NECK_BEND := Vector3(0,1.27,-0.25)
const HIP := Vector3(0,0.93,0.03)
const BILL := Color("#bd995f")
var juvenile := false
var planted_feet: Array[StringName] = []

func build(young: bool, face: int, preview := false) -> void:
	juvenile = young
	previewing = preview
	build_skin("heron_young" if young else "heron_adult",_sculpt)
	attach_head("Skull","heron","young" if young else "",face,SKULL,RADII,MASK_AT,MASK_SIZE)
	pose(0.0,0.0,0.0,0.0)

func _sculpt() -> void:
	var pearl := Color("#bead8b") if juvenile else Color("#dbdfce")
	var slate := Color("#928470") if juvenile else Color("#617c82")
	var body := joint("Breast","",HIP)
	body.lobe(Vector3(0,0.03,0.02),Vector3(0.21,0.25,0.49),slate,0,true)
	body.lobe(Vector3(0,0.06,-0.24),Vector3(0.18,0.23,0.24),pearl,0,false)
	for i in 5:
		var plume := float(i-2)/2.0
		body.twig([Vector3(plume*0.062,0.066,0.28),Vector3(plume*0.083,0.033,0.44),Vector3(plume*0.102,-0.015,0.61-absf(plume)*0.07)],[0.055,0.045,0.006],slate.darkened(0.22),6)
	var neck := joint("NeckBase","Breast",NECK)
	neck.twig([Vector3.ZERO,Vector3(0,0.17,-0.07),NECK_BEND-NECK],[0.134,0.105,0.092],pearl,9)
	var throat := joint("NeckTip","NeckBase",NECK_BEND)
	throat.oval(Vector3.ZERO,Vector3(0.095,0.085,0.093),pearl)
	throat.twig([Vector3.ZERO,Vector3(0,0.15,0.12),SKULL-NECK_BEND],[0.094,0.082,0.082],pearl,9)
	var skull := joint("Skull","NeckTip",SKULL)
	skull.lobe(Vector3.ZERO,Vector3(0.105,0.10,0.16),pearl,0,true)
	skull.twig([Vector3(0,0,-0.11),Vector3(0,-0.03,-0.40)],[0.055,0.004],BILL,6)
	if not juvenile:
		skull.twig([Vector3(0,0.05,0.03),Vector3(0,0.06,0.14),Vector3(0,-0.06,0.30)],[0.063,0.045,0.005],Color("#35444e"),6)
	for side: int in [-1,1]:
		var suffix := "L" if side < 0 else "R"
		var hip := HIP+Vector3(side*0.091,0,side*0.035)
		var hock := Vector3(0,-0.45,0.087)
		var shin := Vector3(0,-0.45,-0.087)
		var thigh := joint("Thigh"+suffix,"Breast",hip)
		thigh.twig([Vector3.ZERO,hock],[0.039,0.029],BILL,7)
		var leg := joint("Shin"+suffix,"Thigh"+suffix,hip+hock)
		leg.twig([Vector3.ZERO,shin],[0.031,0.020],BILL,7)
		var toes := joint("Foot"+suffix,"Shin"+suffix,hip+hock+shin)
		for i in [-1,0,1]:
			toes.twig([Vector3.ZERO,Vector3(i*0.064,-0.012,-0.15+absf(i)*0.024)],[0.015,0.004],BILL,5)
		toes.twig([Vector3.ZERO,Vector3(0,-0.008,0.08)],[0.014,0.003],BILL,5)
		var shoulder := Vector3(side*0.14,0.99,-0.08)
		var wrist := Vector3(side*0.48,0.07,-0.08)
		var wing := joint("Wing"+suffix,"Breast",shoulder)
		_wing_panel(wing,side,[Vector4(-0.055,-0.04,0.25,0),Vector4(0.19,-0.105,0.34,0.046),Vector4(0.38,-0.13,0.32,0.072),Vector4(0.53,-0.073,0.24,0.067)],slate)
		var primaries := joint("Wrist"+suffix,"Wing"+suffix,shoulder+wrist)
		_wing_panel(primaries,side,[Vector4(-0.075,-0.022,0.28,0),Vector4(0.10,-0.023,0.34,0),Vector4(0.31,0.028,0.32,-0.017),Vector4(0.51,0.107,0.26,-0.036),Vector4(0.65,0.167,0.196,-0.058)],slate.darkened(0.12))
		for normal in [Vector3.UP,Vector3.DOWN]:
			for i in 6:
				var base := Vector3(side*i*0.087,-0.005*i,0.10+i*0.010)
				var blade := Vector3(side*(0.15+i*0.018),-0.061,0.34-i*0.039)
				primaries.triangle(base,base+Vector3(side*0.14,0,-0.02),base+blade,normal,slate.darkened(0.24+i*0.035))

func _wing_panel(part: Sculpt, side: int, rows: Array, color: Color) -> void:
	# Spanwise sections retain wing depth and overlap at the wrist when it folds.
	var previous: Array[Vector3] = []
	for section: Vector4 in rows:
		var width := section.z-section.y
		var x := side*section.x
		var y := section.w
		var ring: Array[Vector3] = [Vector3(x,y,section.y), Vector3(x,y+width*0.14,section.y+width*0.29),
			Vector3(x,y-0.016,section.z), Vector3(x,y-width*0.066,section.y+width*0.37)]
		if not previous.is_empty():
			for i in 4:
				var j := (i+1)%4
				var normal := Vector3.UP if i<2 else Vector3.DOWN
				var tint := color if i==0 else color.darkened(0.10 if i==1 else 0.16)
				part.triangle(previous[i],previous[j],ring[i],normal,tint)
				part.triangle(ring[i],previous[j],ring[j],normal,tint)
		previous = ring

func pose(now: float, phase: float, airborne: float, flap_phase: float, leg_tuck := -1.0, crouch := 0.0, flare := 0.0) -> void:
	if leg_tuck < 0.0: leg_tuck = airborne
	var ground_action := 1.0-maxf(airborne,crouch)
	var strike := fposmod(now+phase+2.0,8.6)
	var reach := smoothstep(0.0,0.23,strike)*(1.0-smoothstep(0.39,1.38,strike))*ground_action
	var scan := sin(now*0.72+phase)*(1.0-reach)*ground_action
	var step := smoothstep(2.9,3.4,strike)*(1.0-smoothstep(5.7,6.3,strike))*ground_action
	var beat := lerpf(sin(flap_phase),0.36,flare)
	planted_feet.clear()
	var bend_angle := 0.49*crouch
	# Shorten the two shanks symmetrically around the planted foot as the breast lowers.
	var drop := 0.90*(1.0-cos(bend_angle))+0.174*sin(bend_angle)
	bones.set_bone_pose_position(bone_ids.Breast,HIP-Vector3.UP*drop)
	var breast_pitch := -0.17*reach+airborne*(-0.14+beat*0.055)+0.25*flare
	bend("Breast",breast_pitch,0,step*sin(now*3.0)*0.028)
	bend("NeckBase",-1.55*reach-0.61*airborne+0.05*scan,scan*0.16)
	bend("NeckTip",-0.43*reach+0.98*airborne)
	bend("Skull",0.88*reach-0.36*airborne,scan*0.23)
	for side: int in [-1,1]:
		var suffix := "L" if side < 0 else "R"
		var stride := now*3.0+phase+(PI if side==1 else 0.0)
		var swing := step*sin(stride)
		var lift := step*maxf(0,cos(stride))
		if lift<0.10: planted_feet.append(&"FootL" if side<0 else &"FootR")
		bend("Thigh"+suffix,-1.18*leg_tuck-bend_angle+0.37*swing-0.30*lift+0.14*reach+0.16*flare-breast_pitch*(1.0-leg_tuck))
		bend("Shin"+suffix,-0.32*leg_tuck+2.0*bend_angle+0.74*lift)
		bend("Foot"+suffix,-0.31*lift+0.88*leg_tuck-bend_angle-0.21*flare)
		bend("Wing"+suffix,0,side*lerpf(-1.26,0.06,airborne),side*lerpf(-0.62,0.08+beat*0.95,airborne))
		bend("Wrist"+suffix,0,side*lerpf(2.30,0.12+0.30*cos(flap_phase),airborne),side*airborne*(-0.13+0.48*sin(flap_phase-0.87)))
	sync_head()

func _process(delta: float) -> void:
	preview_time += delta
	var cycle := fposmod(preview_time,14.0)
	var spread := smoothstep(8.6,9.5,cycle)*(1.0-smoothstep(11.8,12.8,cycle))
	pose(preview_time,0,spread,preview_time*6.8)

