extends RefCounted

const Sculpt := preload("res://game/art/equipment_sculpture.gd")

static func mesh(id:String)->ArrayMesh:
	var large:=id=="expedition_pack"
	var s:=Sculpt.new(311 if large else 191)
	var fabric:=Color("#526e61") if large else Color("#ac8257")
	var trim:=Color("#69503d")
	var bottom:=-0.24 if large else -0.15
	var top:=0.23 if large else 0.12
	var width:=0.195 if large else 0.17
	s.loft([Vector4(bottom,width*0.82,0.068,0),Vector4(bottom+0.033,width,0.106,0.007),
		Vector4(top-0.033,width*0.95,0.108,0.009),Vector4(top,width*0.76,0.071,0)],fabric,Vector3.ZERO,Basis.IDENTITY,10)
	for sign_x:float in [-1,1]:
		var x:=sign_x*width*0.57
		s.twig([Vector3(x,top-0.028,-0.063),Vector3(x,top+0.045,-0.109),
			Vector3(x*1.36,top-0.07,-0.202),Vector3(x*1.43,bottom+0.085,-0.21),
			Vector3(x*1.25,bottom+0.042,-0.067)],[0.022,0.027,0.029,0.021,0.014],trim,5)
		s.twig([Vector3(x,top+0.004,0.064),Vector3(x,top-0.028,0.111),
			Vector3(x,top-0.115,0.124)],[0.014,0.017,0.016],trim,5)
		s.bead(Vector3(x,top-0.09,0.125),Vector3(0.018,0.014,0.006),Color("#b9a568"))
	var pocket:=Vector3(0,bottom+0.095,0.082)
	s.loft([Vector4(-0.060,width*0.64,0.024,0),Vector4(-0.045,width*0.80,0.057,0),
		Vector4(0.044,width*0.79,0.057,0),Vector4(0.071,width*0.64,0.034,0)],fabric.lightened(0.10),pocket,Basis.IDENTITY,8)
	if large:
		s.twig([Vector3(-0.226,top+0.046,0.015),Vector3(0,top+0.049,0.015),Vector3(0.226,top+0.046,0.015)],
			[0.067,0.070,0.065],Color("#aca077"),8)
		for sign_x:float in [-1,1]:
			s.bead(Vector3(sign_x*0.18,bottom+0.11,0.01),Vector3(0.064,0.105,0.085),fabric.darkened(0.09))
			s.twig([Vector3(sign_x*0.125,top+0.030,-0.052),Vector3(sign_x*0.125,top+0.114,0.016),
				Vector3(sign_x*0.125,top+0.045,0.083)],[0.010,0.012,0.010],trim,5)
	else:
		s.loft([Vector4(-0.06,width*0.72,0.010,0.012),Vector4(-0.039,width*0.92,0.020,0.009),
			Vector4(0.056,width*0.90,0.024,-0.012)],fabric.lightened(0.12),Vector3(0,top-0.036,0.090),Basis.IDENTITY,8)
	return s.commit()
