class_name ProceduralAudio
extends RefCounted

## Procedural Cinematic Audio Synthesizer for Do Not Wake.
## Generates procedural, zero-dependency 16-bit PCM AudioStreamWAV resources
## for tactile physical interactions:
## - Ratchet clicks (4 variations with mechanical transient & tooth ringing)
## - Steam hiss and bursts (turbulent bandpass noise + thermal sizzle)
## - Metallic fallen bolt chime (multi-modal cylinder vibration with physics chatter bounces)
## - Screwdriver slip screech (high friction shear transient + spark pops)
## - Armored hatch removal thud (sub-bass 55 Hz body + hollow plate resonance)
## - Electrical surge impulse (high-voltage arc crackle + 100 Hz hum + capacitor discharge)
## - Scan sweep (400->1200 Hz linear chirp)
## - Relay clicks (two distinct contact snaps)
## - Paper rustle (3 variations of organic paper crinkle)
## - Stamp thud (rubber stamp body impact + surface slap)
## - Alarm ping (880 Hz ping with subtle flutter)
## - Wake silence (120 ms pure digital silence marker)

const SAMPLE_RATE: int = 44100

# Cached procedural streams for zero runtime allocation
static var _ratchet_variations: Array[AudioStreamWAV] = []
static var _bolt_variations: Array[AudioStreamWAV] = []
static var _steam_burst: AudioStreamWAV = null
static var _steam_loop: AudioStreamWAV = null
static var _tool_slip: AudioStreamWAV = null
static var _hatch_thud: AudioStreamWAV = null
static var _electric_impulse: AudioStreamWAV = null
static var _scan_sweep: AudioStreamWAV = null
static var _relay_click: AudioStreamWAV = null
static var _paper_rustle_variations: Array[AudioStreamWAV] = []
static var _stamp_thud: AudioStreamWAV = null
static var _alarm_ping: AudioStreamWAV = null
static var _wake_silence: AudioStreamWAV = null
static var _is_initialized: bool = false


static func initialize_all() -> void:
	if _is_initialized:
		return

	# Pre-synthesize all sounds once during startup
	_ratchet_variations.clear()
	for i in 4:
		_ratchet_variations.append(_synthesize_ratchet_click(i))

	_bolt_variations.clear()
	for i in 3:
		_bolt_variations.append(_synthesize_bolt_chime(i))

	_steam_burst = _synthesize_steam_burst(0.38)
	_steam_loop = _synthesize_steam_loop(0.85)
	_tool_slip = _synthesize_tool_slip(0.18)
	_hatch_thud = _synthesize_hatch_thud(0.35)
	_electric_impulse = _synthesize_electric_impulse(0.28)

	_scan_sweep = _synthesize_scan_sweep(0.60)
	_relay_click = _synthesize_relay_click(0.12)
	_paper_rustle_variations.clear()
	for i in 3:
		_paper_rustle_variations.append(_synthesize_paper_rustle(i, 0.20))
	_stamp_thud = _synthesize_stamp_thud(0.15)
	_alarm_ping = _synthesize_alarm_ping(0.15)
	_wake_silence = _synthesize_wake_silence(0.12)

	_is_initialized = true


static func get_ratchet_click(variation: int = -1) -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	if _ratchet_variations.is_empty():
		return null
	if variation < 0 or variation >= _ratchet_variations.size():
		return _ratchet_variations[randi() % _ratchet_variations.size()]
	return _ratchet_variations[variation]


static func get_bolt_chime(variation: int = -1) -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	if _bolt_variations.is_empty():
		return null
	if variation < 0 or variation >= _bolt_variations.size():
		return _bolt_variations[randi() % _bolt_variations.size()]
	return _bolt_variations[variation]


static func get_steam_burst() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _steam_burst


static func get_steam_loop() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _steam_loop


static func get_tool_slip() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _tool_slip


static func get_hatch_thud() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _hatch_thud


static func get_electric_impulse() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _electric_impulse


static func get_scan_sweep() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _scan_sweep


static func get_relay_click() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _relay_click


static func get_paper_rustle(variation: int = -1) -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	if _paper_rustle_variations.is_empty():
		return null
	if variation < 0 or variation >= _paper_rustle_variations.size():
		return _paper_rustle_variations[randi() % _paper_rustle_variations.size()]
	return _paper_rustle_variations[variation]


static func get_stamp_thud() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _stamp_thud


static func get_alarm_ping() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _alarm_ping


static func get_wake_silence() -> AudioStreamWAV:
	if not _is_initialized:
		initialize_all()
	return _wake_silence


# ==============================================================================
# PROCEDURAL SOUND SYNTHESIS ENGINES
# ==============================================================================

## 1. RATCHET CLICK: High-tension mechanical pawl snapping over hardened gear teeth
static func _synthesize_ratchet_click(variation: int) -> AudioStreamWAV:
	var duration: float = 0.040 # 40 ms
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var f_tooth: float = 2300.0 + float(variation) * 180.0
	var f_body: float = 1150.0 + float(variation) * 90.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + variation * 77

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var strike: float = sin(t * TAU * f_tooth) * exp(-t / 0.005) * 0.65
		var ring: float = sin(t * TAU * f_body) * exp(-t / 0.014) * 0.35
		var noise: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.0035) * 0.40

		var sample_f: float = strike + ring + noise
		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 2. METALLIC BOLT CHIME: Physics-based hardened steel bolt bouncing on stainless table
static func _synthesize_bolt_chime(variation: int) -> AudioStreamWAV:
	var duration: float = 0.32 # 320 ms
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var base_f: float = 1880.0 + float(variation) * 120.0
	var f0: float = base_f
	var f1: float = base_f * 2.72
	var f2: float = base_f * 4.65
	var f_table: float = 860.0 + float(variation) * 50.0

	var bounce_times := [0.0, 0.068 + float(variation) * 0.006, 0.122 + float(variation) * 0.008]
	var bounce_amps := [1.0, 0.42, 0.18]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + variation * 333

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var sample_f: float = 0.0

		for b in 3:
			var t_b: float = bounce_times[b]
			if t >= t_b:
				var dt: float = t - t_b
				var amp: float = bounce_amps[b]
				var pitch_mult: float = 1.0 + float(b) * 0.04

				var click: float = rng.randf_range(-1.0, 1.0) * exp(-dt / 0.002) * 0.5
				var m0: float = sin(dt * TAU * f0 * pitch_mult) * exp(-dt / 0.11) * 0.45
				var m1: float = sin(dt * TAU * f1 * pitch_mult) * exp(-dt / 0.06) * 0.22
				var m2: float = sin(dt * TAU * f2 * pitch_mult) * exp(-dt / 0.035) * 0.14
				var m_plate: float = sin(dt * TAU * f_table) * exp(-dt / 0.15) * 0.25

				sample_f += (click + m0 + m1 + m2 + m_plate) * amp

		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 3. STEAM BURST: Pressurized turbulent vapor release from overheated copper contacts
static func _synthesize_steam_burst(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5555

	var y1: float = 0.0
	var y2: float = 0.0
	var omega: float = TAU * 3400.0 / float(SAMPLE_RATE)
	var sin_w: float = sin(omega)
	var cos_w: float = cos(omega)
	var alpha: float = sin_w / (2.0 * 1.4)
	var b0: float = alpha
	var b1: float = 0.0
	var b2: float = -alpha
	var a0: float = 1.0 + alpha
	var a1: float = -2.0 * cos_w
	var a2: float = 1.0 - alpha
	var x1: float = 0.0
	var x2: float = 0.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var white_noise: float = rng.randf_range(-1.0, 1.0)

		var y: float = (b0 * white_noise + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = white_noise
		y2 = y1
		y1 = y

		var flutter: float = 0.75 + 0.25 * sin(t * TAU * 19.0) * sin(t * TAU * 31.0)
		var env: float = 0.0
		if t < 0.015:
			env = t / 0.015
		else:
			env = exp(-(t - 0.015) / 0.12)

		var sample_f: float = y * flutter * env * 2.2
		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 4. STEAM LOOP: Continuous subtle fluid vapor hiss
static func _synthesize_steam_loop(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7777

	var filter_val: float = 0.0
	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var noise: float = rng.randf_range(-1.0, 1.0)
		filter_val = lerpf(filter_val, noise, 0.38)

		var flutter: float = 0.8 + 0.2 * sin(t * TAU * 12.0)
		var sample_f: float = filter_val * flutter * 0.45
		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = num_samples
	wav.data = bytes
	return wav


## 5. SCREWDRIVER SLIP: Violent steel shear screech and metallic grind
static func _synthesize_tool_slip(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 10101
	var phase: float = 0.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var current_f: float = lerpf(3800.0, 1100.0, clampf(t / 0.09, 0.0, 1.0))
		phase += current_f * TAU / float(SAMPLE_RATE)
		var shear_chirp: float = sin(phase) * exp(-t / 0.08) * 0.65
		var grind_noise: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.12) * 0.45

		var sample_f: float = tanh(2.2 * (shear_chirp + grind_noise))
		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 6. HATCH REMOVAL THUD: Heavy armored chest plate (15 kg) tearing out with deep sub-bass
static func _synthesize_hatch_thud(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20202
	var sub_phase: float = 0.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var sub_f: float = lerpf(120.0, 48.0, clampf(t / 0.08, 0.0, 1.0))
		sub_phase += sub_f * TAU / float(SAMPLE_RATE)
		var sub_bass: float = sin(sub_phase) * exp(-t / 0.14) * 0.70

		var cav1: float = sin(t * TAU * 220.0) * exp(-t / 0.18) * 0.35
		var cav2: float = sin(t * TAU * 460.0) * exp(-t / 0.09) * 0.20
		var latch_snap: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.004) * 0.50

		var sample_f: float = sub_bass + cav1 + cav2 + latch_snap
		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 7. ELECTRICAL SURGE IMPULSE: High-voltage arc discharge, 100 Hz hum, capacitor snap
static func _synthesize_electric_impulse(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 30303

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var arc_crack: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.012) * 0.75
		var hum: float = (
			sin(t * TAU * 100.0) * 0.35 +
			sin(t * TAU * 300.0) * 0.25 +
			sin(t * TAU * 500.0) * 0.18 +
			sin(t * TAU * 1200.0) * 0.12
		) * exp(-t / 0.18)
		var sizzle: float = sin(t * TAU * 3400.0) * rng.randf_range(0.5, 1.0) * exp(-t / 0.08) * 0.28

		var sample_f: float = arc_crack + hum + sizzle
		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 8. SCAN SWEEP: Linear frequency sweep 400 -> 1200 Hz for diagnostic beam
static func _synthesize_scan_sweep(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var f_start: float = 400.0
	var f_end: float = 1200.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var phase: float = TAU * (f_start * t + 0.5 * ((f_end - f_start) / duration) * t * t)
		var tone: float = sin(phase) * 0.70 + sin(phase * 2.0) * 0.15

		var env: float = 1.0
		if t < 0.02:
			env = t / 0.02
		elif t > duration - 0.06:
			env = (duration - t) / 0.06

		var sample_f: float = clampf(tone * env * 0.75, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 9. RELAY CLICK: Two distinct mechanical contact relay snaps in quick succession (0.12 s)
static func _synthesize_relay_click(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 40404

	var click_times := [0.0, 0.045]
	var click_freqs := [2600.0, 2100.0]

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var sample_f: float = 0.0

		for c in 2:
			var t_c: float = click_times[c]
			if t >= t_c:
				var dt: float = t - t_c
				var noise_snap: float = rng.randf_range(-1.0, 1.0) * exp(-dt / 0.003) * 0.60
				var ring: float = sin(dt * TAU * click_freqs[c]) * exp(-dt / 0.015) * 0.35
				sample_f += (noise_snap + ring) * (1.0 if c == 0 else 0.8)

		sample_f = clampf(sample_f, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 10. PAPER RUSTLE: Organic high-frequency paper crinkle and slide noise (3 variations)
static func _synthesize_paper_rustle(variation: int, duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 50505 + variation * 888

	var filter_val: float = 0.0
	var prev_noise: float = 0.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var white_noise: float = rng.randf_range(-1.0, 1.0)
		var diff: float = white_noise - prev_noise * 0.75
		prev_noise = white_noise
		filter_val = lerpf(filter_val, diff, 0.45)

		var burst1: float = exp(-absf(t - 0.04) / 0.025)
		var burst2: float = exp(-absf(t - 0.11 - float(variation) * 0.015) / 0.035) * 0.75
		var env: float = clampf(burst1 + burst2, 0.0, 1.2)

		var sample_f: float = clampf(filter_val * env * 0.70, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 11. STAMP THUD: Heavy mechanical rubber stamp body impact + paper slap
static func _synthesize_stamp_thud(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 60606
	var sub_phase: float = 0.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var sub_f: float = lerpf(85.0, 45.0, clampf(t / 0.06, 0.0, 1.0))
		sub_phase += sub_f * TAU / float(SAMPLE_RATE)
		var thud: float = sin(sub_phase) * exp(-t / 0.055) * 0.75

		var slap: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.005) * 0.50
		var ring: float = sin(t * TAU * 1250.0) * exp(-t / 0.018) * 0.25

		var sample_f: float = clampf(thud + slap + ring, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 12. ALARM PING: High-tension 880 Hz ping with subtle pitch vibrato (0.15 s)
static func _synthesize_alarm_ping(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var phase: float = 0.0

	for i in num_samples:
		var t: float = float(i) / float(SAMPLE_RATE)
		var current_f: float = 880.0 + sin(t * TAU * 18.0) * 16.0
		phase += current_f * TAU / float(SAMPLE_RATE)

		var tone: float = sin(phase) * 0.75 + sin(phase * 2.0) * 0.15
		var env: float = exp(-t / 0.045)

		var sample_f: float = clampf(tone * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32760.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 13. WAKE SILENCE: 120 ms pure digital silence marker
static func _synthesize_wake_silence(duration: float) -> AudioStreamWAV:
	var num_samples: int = int(float(SAMPLE_RATE) * duration)
	var bytes := PackedByteArray()
	bytes.resize(num_samples * 2)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
