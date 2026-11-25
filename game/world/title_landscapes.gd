extends RefCounted

# Fixed survey points in a generated world keep the title fast to open. Gameplay worlds use their own seeds.
const SEED := 40917
const TITLES := ["灰湾水库   /   南岸码头","霜脊雪山   /   高山雪坡","流金沙海   /   沙丘绿洲","红岩峡谷   /   河谷浅湾"]

# World-space XZ ellipses on the surveyed shorelines and slopes.
const WILDLIFE := [
	[
		{"species":"heron", "center":Vector2(-2.3,18.85), "along":Vector2(1.27,-0.90), "across":Vector2(0.43,0.60), "height":4.3, "period":6.3, "phase":0.23},
		{"species":"heron", "center":Vector2(4.6,14.7), "along":Vector2(1.85,1.0), "across":Vector2(0.48,-0.89), "height":4.8, "period":8.0, "phase":0.68},
	],
	[
		{"species":"argali", "center":Vector2(-2320.0,2345.76), "along":Vector2(0.82,-0.30), "across":Vector2(-0.15,-0.41), "period":8.0, "phase":0.28},
		{"species":"argali", "center":Vector2(-2316.30,2344.95), "along":Vector2(0.43,0.79), "across":Vector2(0.35,-0.19), "period":9.5, "phase":0.67},
	],
	[
		{"species":"jerboa", "center":Vector2(-1865.92,900.47), "along":Vector2(0.35,-0.46), "across":Vector2(0.26,0.20), "period":3.5, "phase":0.06},
		{"species":"jerboa", "center":Vector2(-1865.10,901.50), "along":Vector2(0.37,-0.39), "across":Vector2(0.21,0.20), "period":4.1, "phase":0.53},
	],
	[
		{"species":"boar", "center":Vector2(227.2,-1035.0), "along":Vector2(-0.32,1.10), "across":Vector2(0.38,0.11), "period":9.0, "phase":0.48},
		{"species":"boar", "center":Vector2(231.2,-1029.8), "along":Vector2(-1.13,0.21), "across":Vector2(0.07,0.39), "period":10.8, "phase":0.19},
	],
]

static func frame(index: int, gen: WastelandTerrainGen) -> Dictionary:
	var eye: Vector2
	var target: Vector2
	var lift := 3.0
	var target_lift := 2.0
	var hour := 15.0
	var travel := 1.0
	var clearance := 1.4
	match index:
		0:
			eye = Vector2(-6,27)
			target = Vector2(2,10)
			lift = 2.5
			target_lift = 1.1
			hour = 17.5
			travel = 1.0
		1:
			eye = Vector2(-2322.95,2351.82)
			target = Vector2(-2296,2300.4)
			lift = 2.1
			target_lift = -9.4
			hour = 14.2
			travel = 0.64
			clearance = 1.1
		2:
			eye = Vector2(-1867.88,903.57)
			target = Vector2(-1857,888)
			lift = 0.65
			target_lift = 3.0
			hour = 17.8
			travel = 0.28
			clearance = 0.52
		3:
			eye = Vector2(229,-1042.6)
			target = Vector2(233,-1015)
			lift = 3.0
			target_lift = 2.0
			hour = 17.0
			travel = 1.2
	var at := Vector3(eye.x,maxf(0,gen.ground(eye.x,eye.y))+lift,eye.y)
	var aim := Vector3(target.x,maxf(0,gen.ground(target.x,target.y))+target_lift,target.y)
	return {"eye":at,"target":aim,"hour":hour,"wildlife":WILDLIFE[index],"travel":travel,"clearance":minf(clearance,lift)}
