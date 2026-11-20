extends RefCounted

const Art := preload("res://game/art/bestiary.gd")

static func animal(a:Node3D,kind:String,coat:Color,skin:Color)->void:
	var anatomy_rig = preload("res://game/art/wildlife_rig.gd")
	var ram:=kind=="argali"
	var mouse:=kind=="jerboa"
	var y:=0.69 if ram else 0.17 if mouse else 0.21
	var length:=0.46 if ram else 0.11 if mouse else 0.33
	var w:=0.23 if ram else 0.085 if mouse else 0.12
	var depth:=w*(1.13 if ram else 0.92)
	a._joint("torso",-1,Vector3.UP*y,[])
	var torso:=Art._sculpt(a,"torso",701)
	torso.loft([Vector4(-length,0.45*w,0.56*depth,0),Vector4(-length*0.66,w,depth,0),Vector4(-length*0.14,w*1.05,depth*1.12,0),Vector4(length*0.6,w,depth,0),Vector4(length,w*0.54,depth*0.63,0)],coat,Vector3.ZERO,Basis(Vector3.RIGHT,PI*0.5),16)
	if ram: torso.oval(Vector3(0,0.12,-0.31),Vector3(0.237,0.27,0.22),skin)
	Art._finish(a,"torso",torso)
	var head_height:=0.29 if ram else 0.108 if mouse else 0.08
	anatomy_rig.neck(a,Vector3(0,head_height,-length*0.84))
	var head:=Art._sculpt(a,"head",702)
	head.face_surface=1
	var h:=0.142 if ram else 0.060 if mouse else 0.109
	head.oval(Vector3(0,0,-h*0.46),Vector3(h,h*0.86,h*1.15),coat)
	head.oval(Vector3(0,-h*0.28,-h*1.35),Vector3(h*0.77,h*0.56,h*0.80),skin)
	head.oval(Vector3(0,-h*0.18,-h*2.04),Vector3(h*0.31,h*0.19,h*0.18),Color("#403935"))
	for side:float in [-1,1]:
		head.face_surface=0
		if ram:
			var helix:Array=[]
			var widths:Array=[]
			for i in 15:
				var q:=float(i)/14
				var theta:=q*TAU*(0.29 if a.morph=="young" else 0.88)
				helix.append(Vector3(side*(0.095+q*0.16),0.07+cos(theta)*0.16*(1-0.45*q),sin(theta)*0.15))
				widths.append(lerpf(0.062,0.006,q))
			head.twig(helix,widths,Color("#b5a386"),9)
		elif not mouse:
			for n in 3:
				head.twig([Vector3(side*0.057,-0.019,-0.15),Vector3(side*(0.109+0.012*n),n*0.012-0.029,-0.162)],[0.0026,0.0007],Color("#dac9aa"),4)
	Art._finish(a,"head",head)
	anatomy_rig.ears(a,coat,skin)
	var t:=0.15 if ram else 0.45 if mouse else 0.49
	var widths:=Vector3(0.012,0.009,0.004) if mouse else Vector3(w*0.62,w*0.33,0.006)
	anatomy_rig.tail(a,Vector3(0,0,length*0.84),Vector3(t*0.06,-t*0.19,t*0.53),Vector3(t*0.15,t*(0.14 if mouse else -0.16),t),widths,coat,coat)
	anatomy_rig.legs(a,y,0.0,w*0.69,length*0.58,-length*0.64,w*(0.53 if mouse else 0.43),coat,skin)

static func infected(a:Node3D,head:Art.Sculpture,body:Art.Sculpture)->void:
	var mud:bool=a.type=="mudwalker"
	if mud:
		for i in 19:
			var x:=sin(i*2.4)*0.23
			var z:=cos(i*2.4)*0.13
			body.twig([Vector3(x,0.36,z),Vector3(x*1.05,0.23,z*1.2),Vector3(x*1.16,0.06+0.09*sin(i),z*1.5)],[0.035,0.023,0.004],Color("#687543").darkened((i%4)*0.085),6)
	else:
		head.loft([Vector4(0.039,0.150,0.139,0.037),Vector4(0.102,0.162,0.152,0.041),Vector4(0.136,0.150,0.134,0.033)],Color("#d59a58"))
		for side:float in [-1,1]:
			for j in 3:
				body.twig([Vector3(side*0.195,0.31,j*0.058-0.08),Vector3(side*(0.27+0.023*j),0.44,j*0.061-0.06),Vector3(side*(0.31+0.024*j),0.48,j*0.062-0.03)],[0.051,0.021,0.002],Color("#dcc19a"),5)
