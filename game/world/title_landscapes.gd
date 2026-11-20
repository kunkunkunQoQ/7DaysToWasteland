extends RefCounted

# Fixed survey points in a generated world keep the title fast to open. Gameplay worlds use their own seeds.
const SEED := 40917
const TITLES := ["灰湾水库   /   南岸码头","荒原内陆   /   山麓林场","霜脊雪山   /   高山雪坡","流金沙海   /   沙丘绿洲","红岩峡谷   /   河谷浅湾"]

static func frame(index: int, gen: WastelandTerrainGen) -> Dictionary:
	var eye: Vector2
	var target: Vector2
	var lift := 3.0
	var target_lift := 2.0
	var hour := 15.0
	match index:
		0:
			eye = Vector2(-6,27)
			target = Vector2(2,10)
			lift = 2.5
			target_lift = 1.1
			hour = 17.5
		1:
			var origin := Vector2(gen.starting_outpost("foothills")*WastelandTerrainGen.SIZE)
			eye = origin+Vector2(14,31)
			target = origin+Vector2(10,16)
			lift = 2.8
			hour = 16.9
		2:
			eye = Vector2(-2331,2361)
			target = Vector2(-2296,2300.4)
			lift = 4.2
			target_lift = -9.4
			hour = 14.2
		3:
			eye = Vector2(-1870,906)
			target = Vector2(-1835,876)
			lift = 2.0
			target_lift = 3.0
			hour = 15.7
		4:
			eye = Vector2(232.1,-1045.8)
			target = Vector2(249.7,-1011.6)
			lift = 4.0
			target_lift = 3.2
			hour = 16.1
	var at := Vector3(eye.x,maxf(0,gen.ground(eye.x,eye.y))+lift,eye.y)
	var aim := Vector3(target.x,maxf(0,gen.ground(target.x,target.y))+target_lift,target.y)
	return {"eye":at,"target":aim,"hour":hour}
