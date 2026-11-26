class_name WastelandAudio
extends Node3D

const EFFECTS := ["step_soil","step_grass","step_leaves","step_wood","step_stone","splash","chop","stone","hit","place","search","reload","bow","shot","boom","thunder","collapse","growl","scream","alarm","generator",
	"attack_tell","spit_tell","scream_tell","hurt_impact","hurt_heavy","hurt_acid","heartbeat","hammer","tree_split","tree_rustle","tree_land"]
const VOICES := 24
var samples: Dictionary = {}
var voices: Array[AudioStreamPlayer3D] = []
var voice_cursor := 0
var lake: AudioStreamPlayer
var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var music: AudioStreamPlayer
var listener: Node3D
var relay := Callable()
var local_impact := AudioStreamPlayer.new()
var heartbeat := AudioStreamPlayer.new()
var underwater_filter := AudioEffectLowPassFilter.new()
var ambience_bus := -1
var shawl_speech := preload("res://game/world/shawl_voice.gd").new()

func _ready() -> void:
	ambience_bus = AudioServer.get_bus_index("Ambience")
	if ambience_bus >= 0:
		underwater_filter.cutoff_hz = 640.0
		AudioServer.add_bus_effect(ambience_bus, underwater_filter)
		set_underwater(false)
	for key in EFFECTS:
		samples[key] = load("res://assets/audio/" + key + ".wav")
	for voice in [local_impact, heartbeat]:
		voice.bus = &"Effects"
		add_child(voice)
	for i in VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = &"Effects"
		voice.unit_size = 6.0
		voice.max_distance = 78.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.attenuation_filter_cutoff_hz = 5100.0
		add_child(voice)
		voices.append(voice)
	lake = _ambient("lake", "Ambience", -10.0)
	wind = _ambient("blood_wind", "Ambience", -70.0)
	rain = _ambient("rain", "Ambience", -70.0)
	music = _ambient("dusk", "Music", -9.0)

func _ambient(id: String, bus_name: String, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var clip: AudioStreamWAV = load("res://assets/audio/" + id + ".wav").duplicate()
	clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
	clip.loop_begin = 0
	clip.loop_end = roundi(clip.get_length() * clip.mix_rate)
	player.stream = clip
	player.bus = bus_name
	player.volume_db = volume
	add_child(player)
	player.play()
	return player

func set_underwater(enabled: bool) -> void:
	if ambience_bus < 0:
		return
	for index in AudioServer.get_bus_effect_count(ambience_bus):
		if AudioServer.get_bus_effect(ambience_bus, index) == underwater_filter:
			AudioServer.set_bus_effect_enabled(ambience_bus, index, enabled)
			return

func finish_playback() -> void:
	# AudioServer releases retired playback objects on its mixing thread. Keep the
	# tree ticking until it has acknowledged the final active voices.
	var retiring: Array[WeakRef] = []
	for player in get_children():
		if player.playing:
			var playback: AudioStreamPlayback = player.get_stream_playback()
			if playback != null:
				retiring.append(weakref(playback))
		player.stop()
	var deadline := Time.get_ticks_msec()+1000
	while not retiring.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		retiring=retiring.filter(func(voice: WeakRef): return voice.get_ref()!=null)

func _exit_tree() -> void:
	if ambience_bus >= 0:
		for index in AudioServer.get_bus_effect_count(ambience_bus):
			if AudioServer.get_bus_effect(ambience_bus, index) == underwater_filter:
				AudioServer.remove_bus_effect(ambience_bus, index)
				break

func sync(wet: float, blood: float, near_water: float) -> void:
	wind.volume_db = linear_to_db(0.0003 + blood * 0.90)
	rain.volume_db = linear_to_db(0.0003 + wet * 0.58)
	lake.volume_db = linear_to_db(0.09 + near_water * 0.42)
	music.volume_db = -10.0 - blood * 8.0
	music.pitch_scale = 1.0 - blood * 0.10

func play_local(id: String, loudness: float) -> void:
	var voice := heartbeat if id == "heartbeat" else local_impact
	voice.stream = samples[id]
	voice.volume_db = linear_to_db(loudness)
	voice.play()

func play_at(id: String, at: Vector3, loudness: float = 1.0, occlusion: bool = true) -> void:
	if not samples.has(id):
		return
	if relay.is_valid():
		relay.call(id,at,loudness)
	if is_instance_valid(listener) and listener.global_position.distance_squared_to(at) > 88.0 * 88.0:
		return
	var pitch := randf_range(0.87, 1.12) if id not in ["alarm", "thunder"] else 1.0
	_play_clip(samples[id], at, loudness, pitch, occlusion)

func play_shawl_voice(at: Vector3) -> void:
	# Each speaker's caption is already rate-limited and delivered by the host.
	_play_clip(shawl_speech.phrase(), at + Vector3.UP * 1.38, 0.58, randf_range(0.95, 1.08), true)

func _play_clip(clip: AudioStream, at: Vector3, loudness: float, pitch: float, occlusion: bool) -> void:
	voice_cursor = (voice_cursor + 1) % VOICES
	var slot := voice_cursor
	for index in VOICES:
		var candidate := (voice_cursor + index) % VOICES
		if not voices[candidate].playing:
			slot = candidate
			break
	var voice := voices[slot]
	voice.stop()
	voice.global_position = at
	voice.stream = clip
	voice.pitch_scale = pitch
	voice.volume_db = linear_to_db(maxf(0.001, loudness)) + (-6.5 if occlusion and _blocked(at) else 0.0)
	voice.play()

func _blocked(at: Vector3) -> bool:
	if not is_instance_valid(listener) or at.distance_squared_to(listener.global_position) < 5.0:
		return false
	var from := at.move_toward(listener.global_position, 0.29)
	var query := PhysicsRayQueryParameters3D.create(from, listener.global_position, 3)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
