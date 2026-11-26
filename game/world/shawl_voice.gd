extends RefCounted

const RATE := 16000
# Pitch and the first two vowel formants, in Hz.
const SYLLABLES := [
	Vector3(149, 690, 1240), Vector3(202, 335, 1990),
	Vector3(169, 430, 870), Vector3(218, 555, 1670)
]

var syllable_pcm: Array[PackedByteArray] = []
var gap := PackedByteArray()
var rng := RandomNumberGenerator.new()

func _syllable(voice: Vector3) -> PackedByteArray:
	var pcm := PackedByteArray()
	var frames := roundi(RATE * 0.113)
	pcm.resize(frames * 2)
	var phase := 0.0
	for i in frames:
		var t := float(i) / RATE
		var onset := smoothstep(0.008, 0.041, t)
		var pitch := voice.x * (1.15 - 2.0 * t + 0.017 * sin(TAU * 22.0 * t))
		phase = fmod(phase + pitch / RATE, 1.0)
		# A pair of damped resonances after each pulse makes a pitched, buzzy vowel.
		var pulse_time := phase / pitch
		var f1 := lerpf(245.0, voice.y, onset)
		var f2 := lerpf(1180.0, voice.z, onset)
		var vowel := sin(TAU * f1 * pulse_time) * exp(-540.0 * pulse_time)
		vowel += 0.48 * sin(TAU * f2 * pulse_time) * exp(-780.0 * pulse_time)
		var envelope := smoothstep(0.0, 0.010, t) * (1.0 - smoothstep(0.072, 0.112, t))
		pcm.encode_s16(i * 2, roundi(vowel * envelope * 15600.0))
	return pcm

func phrase() -> AudioStreamWAV:
	if syllable_pcm.is_empty():
		for voice: Vector3 in SYLLABLES:
			syllable_pcm.append(_syllable(voice))
		gap.resize(roundi(RATE * 0.030) * 2)
		gap.fill(0)
	var pcm := PackedByteArray()
	var index := rng.randi_range(0, syllable_pcm.size() - 1)
	for group in rng.randi_range(2, 3):
		if group > 0:
			pcm.append_array(gap)
			index = (index + rng.randi_range(1, syllable_pcm.size() - 1)) % syllable_pcm.size()
		for repeat in rng.randi_range(2, 3):
			pcm.append_array(syllable_pcm[index])
			pcm.append_array(gap)
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	clip.data = pcm
	return clip
