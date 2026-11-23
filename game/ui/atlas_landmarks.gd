extends RefCounted

# Survey windows in the atlas's reference world. X/Z are world metres. The
# width includes the surroundings that distinguish a feature, such as both
# canyon walls, the snowline below a summit, or the dry rim of an oasis.
const SEED := 2817
# Each entry contains the window centre, its width, and the camera bearing in degrees.
const SAMPLES := {
	"meadow": [Vector2(-1056, 744), 72.0, 145.0],
	"taiga": [Vector2(720, -888), 60.0, 32.0],
	"alpine": [Vector2(264, 792), 180.0, 145.0],
	"desert": [Vector2(-576, 504), 108.0, -115.0],
	"mesa": [Vector2(-600, 1152), 132.0, -64.0],
	"marsh": [Vector2(-960, 744), 72.0, 112.0],
	"canyon": [Vector2(-1200, 1536), 120.0, 64.0],
	"oasis": [Vector2(284, 481), 76.0, 112.0],
	"basin": [Vector2(10, -54), 240.0, 28.0],
	"bay_0": [Vector2(72, -12), 60.0, -58.0],
	"bay_1": [Vector2(174, 84), 46.0, 22.0],
	"bay_2": [Vector2(-162, 102), 66.0, 142.0],
	"bay_3": [Vector2(-72, 84), 50.0, 128.0],
	"bay_4": [Vector2(108, -92), 44.0, -157.0],
	"ridge": [Vector2(-36, -144), 112.0, 30.0],
	"steps": [Vector2(-78, -36), 90.0, 70.0],
	"sandbar": [Vector2(18, 30), 50.0, 149.0],
}

static func site(terrain: WastelandTerrainGen, row: Dictionary) -> Dictionary:
	if row.id == "creek":
		const FORD_Z := 42.0
		return {"center": Vector2(terrain.river_x(FORD_Z), FORD_Z), "span": 66.0, "yaw": deg_to_rad(-142.0)}
	var sample: Array = SAMPLES[row.id]
	return {"center": sample[0], "span": sample[1], "yaw": deg_to_rad(sample[2])}
