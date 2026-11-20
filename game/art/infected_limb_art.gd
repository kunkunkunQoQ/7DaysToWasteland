extends RefCounted

const Looks:=preload("res://game/art/infected_looks.gd")
static var meshes:Dictionary={}

# The caller replaces a single elbow or knee attachment. Vertices
# stay in that joint's rest space so the remaining length still follows the bone.
static func remnant(actor:Node3D,state:int,side:int)->Mesh:
	if state<3 or state>8: return null
	var key:="%s/%d/%d/%d"%[actor.type,actor.look_index,state,side]
	if meshes.has(key): return meshes[key]
	var sculpt:=WastelandBestiary.Sculpture.new(241)
	var coat:=Color.html(actor.spec.cloth)
	var skin:=Looks.skin_for(actor.type,Color.html(actor.spec.skin))
	var civilian:bool=actor.type in ["spitter","bloater"]
	if civilian: coat=Looks.coat_for(actor.type,actor.look_index)
	var crawler:bool=actor.type=="crawler"
	var girth:float=1.30 if actor.type=="brute" else 0.81 if int(actor.spec.get("rig",actor.spec.variant))==5 else 1.0
	var end:Vector3
	var direction:Vector3
	var radius:float
	var fabric:=coat.darkened(0.30)
	var sleeve_or_trousers:=state>4
	if state<=4:
		end=Vector3(side*0.008,-0.075,-0.127) if crawler else Vector3(0,-0.128,-0.037)
		direction=end.normalized()
		radius=0.064*girth
		var clothed:bool=civilian and actor.look_index!=0
		sleeve_or_trousers=clothed
		if actor.type=="bloater" and actor.look_index==2: coat=Color("#79726b")
		fabric=coat if clothed else skin
		sculpt.twig([Vector3(0,0.013,0),end*0.35,end*0.74,end],
			[0.066*girth,0.078*girth,radius*1.07,radius],fabric,12)
		if civilian and actor.look_index==0 and not crawler:
			sculpt.loft([Vector4(-0.084,0.080,0.083,-0.024),Vector4(-0.059,0.082,0.084,-0.023),
				Vector4(-0.01,0.076,0.077,-0.007)],coat.lightened(0.08))
	elif crawler:
		var knee:=Vector3(side*0.09,-0.28,-0.143)
		var ankle:=Vector3(side*0.071,-0.34,0.206)
		end=(ankle-knee)*(0.87 if state<=6 else 0.52)
		direction=(ankle-knee).normalized()
		radius=0.049 if state<=6 else 0.063
		sculpt.twig([Vector3.ZERO,end*0.42,end],[0.080,radius*1.18,radius],fabric,12)
	else:
		end=Vector3(0,-0.30,0.024) if state<=6 else Vector3(0,-0.174,0.031)
		direction=Vector3.DOWN
		radius=(0.060 if state<=6 else 0.072)*girth
		sculpt.twig([Vector3(0,0.026,0),Vector3(0,-0.060,0.022),end*0.67,end],
			[0.067*girth,0.082*girth,radius*1.13,radius],fabric,12)
	var axis:=Basis(Quaternion(Vector3.UP,direction))
	var scar:=skin.lerp(Color("#77605a"),0.51)
	sculpt.loft([Vector4(-0.021,radius*1.02,radius*0.97,0),Vector4(-0.006,radius*1.04,radius,0),
		Vector4(0.004,radius*0.94,radius*0.88,0)],fabric.darkened(0.23),end,axis,12)
	sculpt.loft([Vector4(-0.001,radius*0.90,radius*0.86,0),Vector4(0.010,radius*0.79,radius*0.76,0),
		Vector4(0.018,radius*0.46,radius*0.44,0.002),Vector4(0.020,radius*0.15,radius*0.17,0.003)],scar,end,axis,12)
	if sleeve_or_trousers:
		for index in 3:
			var angle:=index*1.98+0.41*side
			var normal:=axis*Vector3(cos(angle),0,sin(angle))
			var across:=normal.cross(direction)
			var rim:=end+normal*radius
			sculpt.triangle(rim-across*0.016-direction*0.018,rim+across*0.011-direction*0.022,
				rim+direction*(0.014+index*0.005),normal,fabric.lightened(0.10))
	meshes[key]=sculpt.commit()
	return meshes[key]
