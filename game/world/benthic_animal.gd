class_name WastelandBenthicAnimal
extends "res://game/art/water_skeleton.gd"

const NAMES := {"pond_turtle":["青甲泽龟","金纹泽龟"],"crayfish":["赤褐溪螯虾","青壳溪螯虾"]}
const TURTLE_NECK := Vector3(0,0.055,-0.31)
const TURTLE_HEAD := Vector3(0,0.14,-0.58)
const CRAY_SKULL := Vector3(0,0.099,-0.078)
var species: String
var morph: String
var face_variant := 0
var anchor := Vector3.ZERO
var phase := 0.0
var stroke := 0.0
var alert := 0.0
var evade := Vector2.ZERO
var active_pose := false

func build(id: String, form: String, face := 0, preview := false) -> void:
	species = id
	morph = form
	face_variant = face
	previewing = preview
	if species == "pond_turtle":
		build_skin(id+form,_turtle)
		attach_head("Skull",id,form,face,TURTLE_HEAD,Vector3(0.114,0.089,0.139),Vector3(0,0.15,-0.709),Vector2(0.21,0.20))
	else:
		build_skin(id+form,_crayfish)
		attach_head("Carapace",id,form,face,CRAY_SKULL,Vector3(0.103,0.081,0.178),Vector3(0,0.12,-0.246),Vector2(0.15,0.16))

func _turtle() -> void:
	var golden := morph=="local"
	var skin := Color("#819563") if golden else Color("#708c77")
	var scute := Color("#977943") if golden else Color("#53776a")
	var seam := Color("#d0ae69") if golden else Color("#8eaa83")
	var b := joint("Shell","",Vector3.ZERO)
	b.oval(Vector3(0,0.02,0.03),Vector3(0.35,0.117,0.47),Color("#b3a36f"))
	var shell := Vector3(0,0.054,0.035)
	for ring in 3:
		var inner := ring/3.0
		var outer := (ring+1)/3.0
		for i in 12:
			var az := TAU*i/12.0
			var az2 := TAU*(i+1)/12.0
			var cell: Array[Vector3] = []
			for edge in [[az,inner],[az2,inner],[az2,outer],[az,outer]]:
				var f := float(edge[1])
				var a := float(edge[0]) + 0.19 * (1.0-f)
				cell.append(shell + Vector3(sin(a)*0.36*f,sqrt(maxf(0,1.0-f*f))*0.198,cos(a)*0.49*f))
			var middle := (cell[0]+cell[1]+cell[2]+cell[3])*0.25
			for k in 4:
				var next := (k+1)%4
				var inset := cell[k].lerp(middle,0.075)
				var inset2 := cell[next].lerp(middle,0.075)
				var normal := Vector3(middle.x,0.24,middle.z)
				b.triangle(cell[k],cell[next],inset,normal,seam)
				b.triangle(inset,cell[next],inset2,normal,seam)
				b.triangle(inset,inset2,middle+Vector3.UP*0.007,normal,scute.lightened(0.045*((ring+i)%4)))
	var neck := joint("Neck","Shell",TURTLE_NECK)
	neck.twig([Vector3.ZERO,Vector3(0,0.02,-0.14),TURTLE_HEAD-TURTLE_NECK],[0.12,0.092,0.080],skin,10)
	joint("Skull","Neck",TURTLE_HEAD).oval(Vector3.ZERO,Vector3(0.112,0.087,0.136),skin)
	joint("Tail","Shell",Vector3(0,0.018,0.38)).twig([Vector3.ZERO,Vector3(0,-0.012,0.22),Vector3(0.022,0,0.29)],[0.068,0.029,0.005],skin,8)
	for side: int in [-1,1]:
		for rear in 2:
			var suffix := ("L" if side<0 else "R")+str(rear)
			var shoulder := Vector3(side*(0.23 if rear==0 else 0.20),0.015,-0.235 if rear==0 else 0.28)
			var elbow := Vector3(side*0.13,-0.035,0.02)
			joint("Arm"+suffix,"Shell",shoulder).twig([Vector3.ZERO,elbow],[0.071,0.058],skin,8)
			var foot := joint("Paddle"+suffix,"Arm"+suffix,shoulder+elbow)
			var base := Vector3(side*0.10,0,0.057)
			foot.twig([Vector3.ZERO,base],[0.059,0.036],skin,8)
			foot.oval(base,Vector3(0.102,0.028,0.083),skin,side*0.23)
			for toe in 3:
				var heel := base+Vector3(side*0.05,0,(toe-1)*0.043)
				foot.twig([heel,heel+Vector3(side*0.062,-0.008,0.028)],[0.019,0.004],skin.lightened(0.15),5)

func _crayfish() -> void:
	var blue := morph=="local"
	var armor := Color("#547e85") if blue else Color("#a3573e")
	var rim := Color("#91b4aa") if blue else Color("#ce8a5c")
	var body := joint("Carapace","",Vector3.ZERO)
	body.oval(Vector3(0,0.098,-0.07),Vector3(0.103,0.080,0.179),armor)
	for i in 5:
		var falloff := 1.0-0.095*i
		var ring := joint("Abdomen"+str(i),"Carapace" if i==0 else "Abdomen"+str(i-1),Vector3(0,0.092-i*0.009,0.06+i*0.054))
		ring.oval(Vector3(0,0,0.03),Vector3(0.095*falloff,0.063*falloff,0.064),armor.lightened((i%2)*0.12))
	var fan := joint("Fan","Abdomen4",Vector3(0,0.045,0.304))
	for i in 3:
		fan.oval(Vector3((i-1)*0.057,-0.010,0.046-absf(i-1)*0.022),Vector3(0.044,0.017,0.085),rim.darkened(0.15))
	for side: int in [-1,1]:
		var suffix := "L" if side<0 else "R"
		var feeler := joint("Feeler"+suffix,"Carapace",Vector3(side*0.044,0.138,-0.21))
		feeler.twig([Vector3.ZERO,Vector3(side*0.045,0.035,-0.16),Vector3(side*0.166,-0.011,-0.43)],[0.010,0.006,0.002],rim,5)
		var shoulder := Vector3(side*0.064,0.074,-0.147)
		var elbow := Vector3(side*0.108,0.028,-0.058)
		joint("Arm"+suffix,"Carapace",shoulder).twig([Vector3.ZERO,elbow],[0.039,0.045],armor,7)
		var claw := joint("Claw"+suffix,"Arm"+suffix,shoulder+elbow)
		var knuckle := Vector3(side*0.039,0.045,-0.119)
		claw.twig([Vector3.ZERO,knuckle],[0.046,0.041],armor,7)
		claw.oval(knuckle,Vector3(0.075,0.048,0.118),armor.lightened(0.10))
		var hinge := knuckle+Vector3(-side*0.032,0,-0.066)
		claw.twig([knuckle+Vector3(side*0.032,0,-0.066),knuckle+Vector3(side*0.051,0.005,-0.138),knuckle+Vector3(side*0.020,0.015,-0.190)],[0.035,0.020,0.005],rim,6)
		joint("Pincer"+suffix,"Claw"+suffix,shoulder+elbow+hinge).twig([Vector3.ZERO,Vector3(-side*0.019,0.005,-0.072),Vector3(side*0.012,0.015,-0.124)],[0.035,0.020,0.005],rim,6)
		for i in 4:
			var hip := Vector3(side*0.074,0.065,-0.084+i*0.047)
			var knee := Vector3(side*0.092,0.022,0.024)
			var leg_id := suffix+str(i)
			joint("Leg"+leg_id,"Carapace",hip).twig([Vector3.ZERO,knee],[0.017,0.013],armor.lightened(0.13),6)
			joint("Shin"+leg_id,"Leg"+leg_id,hip+knee).twig([Vector3.ZERO,Vector3(side*(0.059+0.011*i),-0.083,0.038)],[0.014,0.005],armor.lightened(0.13),6)

func advance(stream: WastelandStream, observer: Vector3, now: float, delta: float) -> void:
	var turtle := species=="pond_turtle"
	var separation := Vector2(global_position.x-observer.x,global_position.z-observer.z)
	var caution := 1.0-smoothstep(1.0,3.2,global_position.distance_to(observer))
	alert = move_toward(alert,caution,delta*1.7)
	evade = evade.move_toward(separation.normalized()*alert*(1.45 if turtle else 0.85),delta*(2.0 if turtle else 1.4))
	var cycle := now*(0.25 if turtle else 0.17)+phase
	var radius := 1.38 if turtle else 0.71
	var next := anchor+Vector3(sin(cycle)*radius+evade.x,0,cos(cycle)*radius*0.67+evade.y)
	var bed := stream.ground_at(next)
	next.y = clampf(bed+1.20+sin(cycle*1.7)*0.28-alert*0.49,bed+0.30,-0.38) if turtle else bed+0.024
	var heading := Vector2(cos(cycle),-sin(cycle)*0.67).normalized()
	if turtle:
		heading = (heading+evade*1.5).normalized()
	elif alert>0.35:
		heading = -separation.normalized()
	rotation.y = lerp_angle(rotation.y,atan2(-heading.x,-heading.y),1.0 if not active_pose else minf(1,delta*3.5))
	position = next
	active_pose = true
	animate(now,delta)

func _process(delta: float) -> void:
	preview_time += delta
	var cycle := fposmod(preview_time,10.0)
	alert = smoothstep(5.5,6.3,cycle)*(1.0-smoothstep(7.5,8.8,cycle))
	animate(preview_time,delta)

func animate(now: float, delta: float) -> void:
	stroke = fmod(stroke+delta*(2.8+alert*3.0),TAU)
	if species == "pond_turtle":
		var glide := maxf(alert,1.0-smoothstep(0.25,0.80,sin(now*0.90+phase)))
		bend("Shell",-0.12*alert,0,0.05*sin(stroke+phase)*glide)
		bones.set_bone_pose_position(bone_ids.Neck,TURTLE_NECK+Vector3(0,-0.018,0.085)*alert)
		bend("Neck",0.14*sin(now*0.85+phase)-0.22*alert,0.25*sin(now*0.47+phase))
		bend("Skull",0.06*sin(stroke+phase),0.10*sin(now*0.62))
		bend("Tail",0,0.20*sin(stroke+phase-1.2)*glide)
		for side: int in [-1,1]:
			for rear in 2:
				var beat := stroke+phase+PI*rear+(PI if side==1 else 0.0)
				var suffix := ("L" if side<0 else "R")+str(rear)
				bend("Arm"+suffix,0,side*lerpf(-0.38,sin(beat)*(0.72 if rear==0 else 0.56),glide),side*(0.05+glide*0.24*cos(beat)))
				bend("Paddle"+suffix,glide*cos(beat-0.4)*0.41,side*(0.16+glide*0.47*sin(beat-0.92)),side*glide*0.28*cos(beat-0.85))
	else:
		var tuck := alert*maxf(0.0,cos(stroke+phase))
		bones.set_bone_pose_position(bone_ids.Carapace,Vector3.UP*tuck*0.10)
		for i in 5:
			bend("Abdomen"+str(i),tuck*(0.13+0.02*i),0.024*sin(stroke+phase-i*0.36))
		bend("Fan",tuck*0.31)
		for side: int in [-1,1]:
			var suffix := "L" if side<0 else "R"
			var beat := stroke+phase+side*1.17
			bend("Feeler"+suffix,0.13*cos(now*1.8+side)+alert*0.18,side*(0.08+0.27*sin(now*2.3+side)))
			bend("Arm"+suffix,0.45*alert,side*(0.13*sin(beat)+0.16*alert))
			bend("Claw"+suffix,0.33*alert+0.08*cos(beat),side*(0.10+0.20*alert))
			bend("Pincer"+suffix,0,side*(0.10+0.16*sin(beat)+0.24*alert))
			for i in 4:
				var gait := stroke+phase+i*1.71+(PI if side<0 else 0.0)
				var lift := maxf(0.0,cos(gait))
				var leg_id := suffix+str(i)
				bend("Leg"+leg_id,0,side*0.38*sin(gait),side*(0.28*lift-0.04))
				bend("Shin"+leg_id,0,-side*0.12*sin(gait-0.62),side*(0.32*lift-0.08))
	sync_head()
