extends RefCounted

const SPAN := 352.0
const NAMES := ["meadow","taiga","alpine","desert","mesa","marsh","canyon"]
const TITLES := ["长风草甸","北针林海","霜脊雪山","流金沙海","丹霞台地","苇泽湿原","红岩峡谷"]
const ZONES := [0,1,2,3,3,0,2]
const TEMPERATURE := [0.0,-3.5,-13.0,12.0,4.5,1.5,3.0]
const TONES := [Color("#a2ab69"),Color("#637f65"),Color("#8c9596"),Color("#dfb56d"),Color("#bd7958"),Color("#69846a"),Color("#ab765f")]
const REGIONAL_SITES := [
	["granary","granary","post","cabin"],
	["post","garage","cabin","cabin"],
	["garage","post","bunker","tower"],
	["garage","granary","fuel","fuel"],
	["garage","post","bunker","tower"],
	["granary","post","granary","cabin"],
	["garage","post","bunker","tower"]
]
var seed_value: int
var folds := FastNoiseLite.new()
var uplands := FastNoiseLite.new()
var water := FastNoiseLite.new()
var local_noise := FastNoiseLite.new()
var districts := {}
var starts := {}

func _init(seed_number: int) -> void:
	seed_value = seed_number
	folds.seed = seed_number ^ 89173
	folds.frequency = 0.0064
	folds.fractal_octaves = 3
	uplands.seed = seed_number ^ 105953
	uplands.frequency = 0.0023
	uplands.fractal_octaves = 1
	water.seed = seed_number ^ 61747
	water.frequency = 0.0016
	water.fractal_octaves = 2
	local_noise.seed = seed_number ^ 24001
	local_noise.frequency = 0.024
	local_noise.fractal_octaves = 2

func _hash(cell: Vector2i, salt: int) -> int:
	return hash(Vector4i(seed_value,cell.x,cell.y,salt))

# Each seven-district band contains all seven climates in a seeded order. Offset
# centres make the borders irregular; nearby districts contribute to the same height.
func _district(cell: Vector2i) -> Vector3:
	if districts.has(cell): return districts[cell]
	var band := Vector2i(floori(float(cell.x)/7.0),cell.y)
	var kind := posmod(posmod(cell.x,7)*(1+_hash(band,31)%6)+_hash(band,71),7)
	var dx := 0.29 + 0.42*(_hash(cell,13)%10007)/10006.0
	var dz := 0.29 + 0.42*(_hash(cell,47)%10007)/10006.0
	var site := Vector3((cell.x+dx)*SPAN,kind,(cell.y+dz)*SPAN)
	if districts.size()>1024: districts.clear()
	districts[cell] = site
	return site

func _nearest(p: Vector2) -> Vector3:
	var cell := Vector2i((p/SPAN).floor())
	var nearest := Vector3.ZERO
	var best := INF
	for z in range(-1,2):
		for x in range(-1,2):
			var site := _district(cell+Vector2i(x,z))
			var d := p.distance_squared_to(Vector2(site.x,site.z))
			if d < best:
				nearest = site
				best = d
	return nearest

func kind(p: Vector2) -> int:
	return int(_nearest(p).y)

func _outpost(site: Vector3) -> Vector2i:
	return Vector2i(floori(site.x/32.0),floori(site.z/32.0))

func beacon_cell(outpost: Vector2i) -> Vector2i:
	var direction := 1 if _hash(outpost,101)%2==0 else -1
	return outpost + Vector2i(3*direction,1)

func nearby_outposts(p: Vector2) -> Array[Vector2i]:
	var origin := Vector2i((p/SPAN).floor())
	var result: Array[Vector2i] = []
	for z in range(-3,4):
		for x in range(-3,4):
			var site := _district(origin+Vector2i(x,z))
			if int(site.y) in [0,1]: result.append(_outpost(site))
	return result

func starting_outpost(start_id: String) -> Vector2i:
	if start_id=="seeded" or start_id.is_empty():
		start_id = "grassland" if _hash(Vector2i.ZERO,173)%2==0 else "foothills"
	if starts.has(start_id): return starts[start_id]
	var target := 1 if start_id=="foothills" else 0
	var best := INF
	var chosen := Vector2i.ZERO
	for z in range(-4,5):
		for x in range(-4,5):
			var site := _district(Vector2i(x,z))
			if int(site.y)!=target: continue
			var at := Vector2(site.x,site.z)
			if at.length_squared() < 365.0*365.0: continue
			var score := at.length() + absf(water.get_noise_2d(at.x,at.y))*20.0
			if score < best:
				best=score
				chosen=_outpost(site)
	starts[start_id]=chosen
	return chosen

func site_for(cell: Vector2i, varied: bool = false) -> String:
	var p := Vector2(cell*32)+Vector2(16,16)
	var district := Vector2i((p/SPAN).floor())
	# The outpost stays at least three chunks inside its district; its satellite
	# can cross the edge by one chunk.
	for x in range(-1,2):
		var site := _district(district + Vector2i(x,0))
		if int(site.y) not in [0,1]: continue
		var hub := _outpost(site)
		if cell==hub: return "lodge"
		if cell==beacon_cell(hub): return "police" if int(site.y)==0 else "tower"
	var tag := _hash(cell,397)
	if tag%31!=0: return ""
	var id := kind(p)
	if height(p)<2.2: return ""
	if varied: return REGIONAL_SITES[id][_hash(cell,1823)%REGIONAL_SITES[id].size()]
	if id==1 or id==0: return "cabin"
	if id in [2,4,6]: return "bunker" if tag%2==0 else "tower"
	return "fuel" if id==3 else "cabin"

func _channel(p: Vector2) -> float:
	return absf(water.get_noise_2d(p.x,p.y)-0.045)*280.0

func _surface(id: int,p: Vector2,center: Vector2,fold: float,wide: float,fine: float,drain: float) -> float:
	var d := p-center
	match id:
		0: return 7.0+fold*7.0+fine*1.2
		1: return 17.0+wide*10.0+fold*4.0+fine*0.9
		2:
			var summit := 1.0-smoothstep(0.0,SPAN*0.79,(d*Vector2(0.88,1.08)).length())
			var pass_line := absf(d.y-d.x*0.30-78.0-15.0*sin(p.x*0.008))
			var saddle := (1.0-smoothstep(0.0,104.0,pass_line))*summit
			return 19.0+66.0*summit-13.0*saddle+wide*8.0+fold*1.9+fine*0.55
		3:
			var wind := (d.x*0.067+d.y*0.033)+fold*2.5+sin(p.y*0.024)*0.92
			var dune := 0.5+0.5*cos(wind+0.65*sin(wind+0.6))
			var sand := 6.5+11.0*dune+fold*5.0+fine
			var oasis := Vector2(d.x-64.0,d.y+33.0)*Vector2(0.75,1.22)
			return lerpf(-2.1+fine*0.25,sand,smoothstep(10.0,34.0,oasis.length()))
		4:
			var terrace := clampf(0.50+wide*0.54+0.18*cos(p.x*0.012+wide),0,1)
			var benches := smoothstep(0.13,0.37,terrace)*8+smoothstep(0.39,0.64,terrace)*10+smoothstep(0.66,0.89,terrace)*11
			return 8.0+benches+terrace*6.0+fold*1.4+fine*0.7
		5: return 0.75+fold*5.5+fine*1.35
		_:
			var wall := smoothstep(8.0,109.0,drain)
			return 3.0+wall*(24.0+wide*5.0)+smoothstep(76.0,162.0,drain)*11.0+fine*0.85

func height(p: Vector2) -> float:
	var cell := Vector2i((p/SPAN).floor())
	var fold := folds.get_noise_2d(p.x,p.y)
	var wide := uplands.get_noise_2d(p.x,p.y)
	var fine := local_noise.get_noise_2d(p.x,p.y)
	var drain := _channel(p)
	var total := 0.0
	var weights := 0.0
	var river_strength := 0.0
	var closest_hub := INF
	for z in range(-1,2):
		for x in range(-1,2):
			var site := _district(cell+Vector2i(x,z))
			var center := Vector2(site.x,site.z)
			var d2 := center.distance_squared_to(p)
			var w := maxf(0,1.0-d2/(SPAN*SPAN*0.89))
			if w<=0.0: continue
			w = w*w*w*w
			var id := int(site.y)
			if id in [0,1]:
				var hub := Vector2(_outpost(site)*32)+Vector2(16,16)
				closest_hub=minf(closest_hub,p.distance_squared_to(hub))
			total += w*_surface(id,p,center,fold,wide,fine,drain)
			weights += w
			if id not in [2,3,4]: river_strength += w
	var land := total/maxf(weights,0.0000001)
	var bank_width := 28.0+maxf(land,0.0)*1.35
	var banks := (1.0-smoothstep(2.9,bank_width,drain))*river_strength/maxf(weights,0.0000001)
	banks *= smoothstep(22.0,84.0,sqrt(closest_hub))
	var ford := smoothstep(0.58,0.92,sin(p.x*0.021+p.y*0.017))
	return lerpf(land,-2.7+ford*2.4+fine*0.24,banks)

func road(p: Vector2) -> float:
	var cell := Vector2i((p/SPAN).floor())
	var site := _district(cell)
	var start := Vector2(_outpost(site)*32)+Vector2(16,16)
	var distance := INF
	for dir: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var neighbor := _district(cell+dir)
		var end := Vector2(_outpost(neighbor)*32)+Vector2(16,16)
		var line := end-start
		var t := clampf((p-start).dot(line)/line.length_squared(),0,1)
		var bend := sin(t*PI)*10.0*sin((start.x+end.x+start.y+end.y)*0.012)
		var tangent := line.normalized().orthogonal()
		if dir.x<0 or dir.y<0: tangent = -tangent
		distance=minf(distance,p.distance_to(start+line*t+tangent*bend))
	return 1.0-smoothstep(1.2,3.4,distance)
