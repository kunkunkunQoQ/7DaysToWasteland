extends RefCounted

const Art := preload("res://game/art/bestiary.gd")

# Skull-local attachment point, tip relative to the attachment and half width.
const EARS := {
	"stag": [Vector3(0.073, 0.543, -0.14), Vector3(0.153, 0.105, 0), 0.055],
	"boar": [Vector3(0.126, 0.107, -0.103), Vector3(0.091, 0.16, 0.06), 0.058],
	"fox": [Vector3(0.074, 0.082, 0.019), Vector3(0.039, 0.124, 0.014), 0.051],
	"wolf": [Vector3(0.102, 0.114, 0.026), Vector3(0.053, 0.136, 0.019), 0.071],
	"hare": [Vector3(0.044, 0.068, 0.009), Vector3(0.036, 0.232, 0.013), 0.034],
	"badger": [Vector3(0.085, 0.071, 0.015), Vector3(0.016, 0.066, 0.004), 0.038],
	"argali": [Vector3(0.102, 0.059, -0.034), Vector3(0.076, 0.061, 0.02), 0.040],
	"jerboa": [Vector3(0.040, 0.035, -0.016), Vector3(0.020, 0.109, 0.003), 0.026],
	"otter": [Vector3(0.081, 0.038, -0.025), Vector3(0.016, 0.066, 0.003), 0.040],
}

# Preserve the skull-local coordinates used by the portrait and face shaders.
static func neck(actor: Node3D, mount: Vector3) -> void:
	var base := mount * 0.58
	actor._joint("neck", 0, base, [])
	actor._joint("head", actor.skeleton.find_bone("neck"), mount - base, [])

static func ears(actor: Node3D, coat: Color, lining: Color) -> void:
	var dimensions: Array = EARS[actor.type]
	var root: Vector3 = dimensions[0]
	var tip: Vector3 = dimensions[1]
	var width: float = dimensions[2]
	var growth := 1.15 if actor.morph == "young" else 1.0
	for side: float in [-1, 1]:
		var mirror := Vector3(side, 1, 1) * growth
		var label := "ear_r" if side > 0 else "ear_l"
		actor._joint(label, actor.skeleton.find_bone("head"), root * mirror, [])
		var ear := Art._sculpt(actor, label, 712)
		var end := tip * mirror
		var w := width * growth
		var angle := -atan2(end.x, end.y)
		if actor.type in ["boar", "fox", "wolf"]:
			ear.twig([Vector3.ZERO, end * 0.46, end], [w, w * 0.71, w * 0.065], coat, 7)
			ear.triangle(Vector3(-w * 0.58, 0, -w * 0.82), Vector3(w * 0.58, 0, -w * 0.82), end * 0.83 + Vector3.FORWARD * w * 0.29, Vector3.FORWARD, lining)
		else:
			var size := Vector3(w, end.length() * 0.58, w * 0.57)
			ear.oval(end * 0.50, size, coat, angle)
			ear.oval(end * 0.50 + Vector3.FORWARD * w * 0.40, size * Vector3(0.63,0.78,0.43), lining, angle)
		Art._finish(actor, label, ear)

static func legs(actor: Node3D, hip_height: float, hip_drop: float, half_width: float, rear_z: float, front_z: float, radius: float, coat: Color, skin: Color) -> void:
	var hoofed: bool = actor.type in ["stag", "argali", "boar"]
	var springer: bool = actor.type in ["hare", "jerboa"]
	for i in 4:
		var rear := i < 2
		var side := 1.0 if i % 2 == 0 else -1.0
		var upper_name := "leg%d" % i
		var knee_name := "ankle%d" % i
		var hock_name := "hock%d" % i
		var foot_name := "paw%d" % i
		var thick := radius * (1.22 if rear else 0.88)
		var paw_y := thick * (0.34 if hoofed else 0.40)
		var h := hip_height - hip_drop - paw_y
		if actor.type == "jerboa" and not rear:
			h *= 0.60
			thick *= 0.63
		var knee := Vector3(0, -h * 0.39, -h * (0.43 if springer else 0.31)) if rear else Vector3(0, -h * 0.40, h * 0.24)
		var hock := Vector3(0, -h * 0.32, h * (0.68 if springer else 0.51)) if rear else Vector3(0, -h * 0.41, -h * 0.34)
		var heel := Vector3(0, -h - knee.y - hock.y, -knee.z - hock.z)
		actor._joint(upper_name, 0, Vector3(side * half_width, -hip_drop, rear_z if rear else front_z), [])
		actor._joint(knee_name, actor.skeleton.find_bone(upper_name), knee, [])
		actor._joint(hock_name, actor.skeleton.find_bone(knee_name), hock, [])
		actor._joint(foot_name, actor.skeleton.find_bone(hock_name), heel, [])
		var thigh := Art._sculpt(actor, upper_name, 713)
		thigh.twig([-knee * 0.19, knee * 0.32, knee * 0.66, knee * 1.04], [thick * 0.86, thick, thick * 0.78, thick * 0.48], coat, 10)
		if springer and rear:
			thigh.oval(knee * 0.30, Vector3(thick, thick * 1.30, thick * 1.45), coat)
		Art._finish(actor, upper_name, thigh)
		var shank := Art._sculpt(actor, knee_name, 714)
		shank.oval(Vector3.ZERO, Vector3(thick * 0.50, thick * 0.48, thick * 0.50), coat)
		shank.twig([-hock * 0.08, hock * 0.32, hock], [thick * 0.50, thick * 0.56, thick * 0.32], coat, 9)
		Art._finish(actor, knee_name, shank)
		var lower := Art._sculpt(actor, hock_name, 715)
		var sock := skin.darkened(0.15) if actor.type == "stag" else coat.darkened(0.26 if actor.type == "fox" else 0.12)
		lower.oval(Vector3.ZERO, Vector3(thick * 0.34, thick * 0.37, thick * 0.36), sock)
		lower.twig([-heel * 0.10, heel * 0.49, heel], [thick * 0.35, thick * 0.27, thick * 0.32], sock, 8)
		Art._finish(actor, hock_name, lower)
		var paw := Art._sculpt(actor, foot_name, 716)
		if hoofed:
			for toe: float in [-1, 1]:
				paw.oval(Vector3(toe * thick * 0.18, 0, -thick * 0.16), Vector3(thick * 0.21, paw_y, thick * 0.48), Color("#483e39"))
		else:
			var reach := thick * (1.88 if springer and rear else 0.90)
			var spread := thick * (0.88 if actor.type == "otter" else 0.69)
			paw.oval(Vector3(0, 0, -reach * 0.47), Vector3(spread, paw_y, reach), sock)
			if actor.type in ["badger","otter"] and not rear:
				for toe in range(-1,2):
					var base := Vector3(spread * toe * 0.53, 0, -reach)
					var tip := base + Vector3(spread * toe * 0.12, -paw_y * 0.30, -reach * (0.85 if actor.type == "badger" else 0.52))
					paw.twig([base, tip], [spread * 0.21, spread * 0.041], skin.darkened(0.34) if actor.type == "badger" else sock, 5)
		Art._finish(actor, foot_name, paw)

static func tail(actor: Node3D, base: Vector3, middle: Vector3, tip: Vector3, widths: Vector3, coat: Color, end_color: Color) -> void:
	actor._joint("tail", 0, base, [])
	var first := Art._sculpt(actor, "tail", 717)
	if actor.type == "hare":
		first.oval(tip * 0.49, Vector3(0.056,0.064,0.070), coat)
		Art._finish(actor, "tail", first)
		return
	var tangent := tip.normalized()
	first.twig([Vector3.ZERO, middle * 0.42, middle - tangent * middle.length() * 0.24, middle],
		[widths.x, lerpf(widths.x, widths.y, 0.46), lerpf(widths.x, widths.y, 0.93), widths.y], coat, 10)
	Art._finish(actor, "tail", first)
	actor._joint("tail_tip", actor.skeleton.find_bone("tail"), middle, [])
	var last := Art._sculpt(actor, "tail_tip", 718)
	var end := tip - middle
	var blend := tangent * end.length() * 0.33
	var taper := lerpf(widths.y, widths.z, 0.23)
	last.twig([-tangent * widths.y * 0.42, blend], [widths.y * 0.96, taper], coat, 10)
	last.twig([blend, end * 0.70, end], [taper, lerpf(widths.y, widths.z, 0.57), widths.z], end_color, 10)
	if actor.type == "jerboa":
		last.oval(end, Vector3(0.020,0.029,0.037), Color("#54433c"))
	Art._finish(actor, "tail_tip", last)
