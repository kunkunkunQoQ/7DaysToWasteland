extends SceneTree
## Geometric checks include full containment, where overlap interval length
## alone underestimates the translation needed to separate the shapes.
const Probe := preload("penetration_probe.gd")

var _failures := 0

func _initialize() -> void:
	var unit := _box(Vector3.ZERO, Vector3.ONE * 0.5)
	_expect(unit, _box(Vector3(0.8, 0, 0), Vector3.ONE * 0.5), 0.2)
	_expect(unit, _box(Vector3.ZERO, Vector3.ONE * 0.1), 0.6)
	_expect(unit, _box(Vector3(1.1, 0, 0), Vector3.ONE * 0.5), 0.0)
	_expect(unit, _capsule(Vector3.ZERO, 0.1, 0.2), 0.6)
	_expect(unit, _capsule(Vector3(0.65, 0, 0), 0.2, 0.3), 0.05)
	_expect(unit, _capsule(Vector3(0.6, 0, 0.6), 0.2, 0.3), 0.2 - sqrt(0.02))
	var a := _capsule(Vector3.ZERO, 0.2, 0.4)
	_expect(a, _capsule(Vector3(0.3, 0, 0), 0.2, 0.4), 0.1)
	_expect(a, _capsule(Vector3(0, 1, 0), 0.2, 0.4), 0.2)
	print("PENETRATION selftest failed=", _failures)
	quit(1 if _failures else 0)

func _box(point: Vector3, half: Vector3) -> Probe.Segment:
	var s := Probe.Segment.new()
	s.pose = Transform3D(Basis.IDENTITY, point)
	s.half = half
	return s

func _capsule(point: Vector3, radius: float, shaft: float) -> Probe.Segment:
	var s := Probe.Segment.new()
	s.pose = Transform3D(Basis.IDENTITY, point)
	s.radius = radius
	s.shaft = shaft
	return s

func _expect(a: Probe.Segment, b: Probe.Segment, expected: float) -> void:
	var common := Transform3D(Basis.from_euler(Vector3(0.43, -0.21, 1.1)), Vector3(1.6, 2.3, -1.4))
	var pa := a.pose
	var pb := b.pose
	for transform: Transform3D in [Transform3D.IDENTITY, common]:
		a.pose = transform * pa
		b.pose = transform * pb
		for actual: float in [Probe._penetration(a, b), Probe._penetration(b, a)]:
			if absf(actual - expected) > 0.00001:
				printerr("Expected ", expected, ", observed ", actual)
				_failures += 1
	a.pose = pa
	b.pose = pb
