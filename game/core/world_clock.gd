class_name WastelandClock
extends RefCounted

const START := 17.5

var hours := START
var elapsed := 0.0
var minutes := 32.0
var period := 7
var seed_value := 0

func configure(settings: Dictionary, snapshot: Dictionary) -> void:
	seed_value = int(settings.seed)
	period = maxi(1, int(settings.horde_days))
	minutes = maxf(5.0, float(settings.minutes))
	hours = float(snapshot.get("time", START))
	elapsed = float(snapshot.get("elapsed", 0.0))

func advance(delta: float) -> void:
	elapsed += delta
	hours += delta / (minutes * 2.5)

func day() -> int:
	return floori(hours / 24.0) + 1

func hour() -> float:
	return fposmod(hours, 24.0)

func time_text() -> String:
	var total := floori(hour() * 60.0)
	return "%02d:%02d" % [total / 60, total % 60]

func event_day() -> int:
	return day() - int(hour() < 4.0)

func horde_active() -> bool:
	return event_day() > 0 and event_day() % period == 0 and (hour() >= 22.0 or hour() < 4.0)

func blood() -> float:
	var ev_day := day() - int(hour() < 5.3)
	if ev_day <= 0 or ev_day % period != 0:
		return 0.0
	var evening_hour := hour() + (24.0 if hour() < 5.3 else 0.0)
	return smoothstep(21.5, 22.0, evening_hour) * (1.0 - smoothstep(28.0, 29.3, evening_hour))

func warning_minutes() -> int:
	if day() % period == 0 and hour() >= 21.5 and hour() < 22.0:
		return ceili((22.0 - hour()) * 60.0)
	return 0

func next_horde() -> int:
	if horde_active():
		return event_day()
	return (floori((day() - int(hour() < 4.0) - 1) / float(period)) + 1) * period

func weather_at(block: int) -> int:
	if block < 2:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + block * 193939
	var roll := rng.randf()
	var start_hour := posmod(block * 9, 24)
	if roll < 0.33 and start_hour < 12:
		return 1
	if roll > 0.87:
		return 3
	if roll > 0.62:
		return 2
	return 0

func weather() -> Vector4:
	var block := floori(hours / 9.0)
	var source := Vector4.ZERO
	var target := Vector4.ZERO
	source[weather_at(block - 1)] = 1.0
	target[weather_at(block)] = 1.0
	return source.lerp(target, smoothstep(0.0, 2.3, fposmod(hours, 9.0)))

func temperature() -> float:
	var weights := weather()
	return 11.5 + 7.5 * cos((hour() - 14.0) * TAU / 24.0) - weights.y * 2.0 - weights.z * 4.0 - weights.w * 6.0
