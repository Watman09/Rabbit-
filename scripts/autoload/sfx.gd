## Procedural sound effects. Every sound is synthesised at startup (spread
## over several frames) so the prototype ships with zero audio assets.
## Replace entries in `_streams` with real .wav/.ogg files later.
extends Node

const SR := 22050
const VOICES := 24

var _streams := {}
var _queue: Array[String] = []
var _players: Array[AudioStreamPlayer] = []
var _last_play := {}
var _rng := RandomNumberGenerator.new()
var _music: AudioStreamPlayer
var muted := false

const SOUNDS := ["swing", "hit", "kill", "soul", "dash", "swing_big", "heavy", "hurt", "claw", "telegraph",
	"bolt", "slam", "portal", "charge", "charged", "denied", "roar_small", "boss_roar", "ability_whirl",
	"ability_crescent", "ability_harvest", "wave", "player_death", "step", "perfect", "parry", "execute", "upgrade", "drone"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	_queue.assign(SOUNDS)

func is_ready() -> bool:
	return _queue.is_empty()

func _process(_delta: float) -> void:
	# synthesise a couple of sounds per frame to avoid a long freeze
	var budget := 2
	while budget > 0 and not _queue.is_empty():
		var n: String = _queue.pop_front()
		_streams[n] = _make(n)
		budget -= 1

func start_music() -> void:
	if _streams.has("drone") and not _music.playing:
		_music.stream = _streams["drone"]
		_music.play()

func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if muted or not _streams.has(name):
		return
	var now := Time.get_ticks_msec()
	var min_gap := 35 if name in ["hit", "kill", "soul", "claw"] else 15
	if _last_play.has(name) and now - _last_play[name] < min_gap:
		return
	_last_play[name] = now
	var best: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			best = p
			break
	if best == null:
		return
	best.stream = _streams[name]
	best.pitch_scale = clampf(pitch, 0.3, 3.0)
	best.volume_db = volume_db
	best.play()

# ------------------------------------------------------------------ synthesis
func _make(n: String) -> AudioStreamWAV:
	var s: PackedFloat32Array
	var loop := false
	match n:
		"swing": s = _whoosh(0.22, 3200.0, 700.0, 0.7)
		"swing_big": s = _mix(_whoosh(0.34, 2400.0, 380.0, 0.9), _tone(0.3, 130.0, 55.0, 0.35, "sine"))
		"heavy": s = _mix(_whoosh(0.4, 1800.0, 260.0, 1.0), _boom(0.55, 80.0, 0.9))
		"hit": s = _mix(_tone(0.16, 160.0, 45.0, 0.9, "sine"), _noise_burst(0.05, 0.6, 5000.0))
		"kill": s = _mix(_noise_sweep(0.45, 2500.0, 200.0, 0.45), _tone(0.45, 620.0, 140.0, 0.18, "sine", 9.0))
		"soul": s = _mix(_tone(0.28, 1318.0, 1318.0, 0.35, "sine"), _tone(0.28, 1975.0, 1975.0, 0.15, "sine"))
		"dash": s = _whoosh(0.2, 600.0, 3500.0, 0.6)
		"hurt": s = _distort(_mix(_tone(0.3, 110.0, 50.0, 0.8, "saw"), _noise_burst(0.12, 0.5, 2000.0)), 2.5)
		"claw": s = _noise_sweep(0.14, 6000.0, 1500.0, 0.55)
		"telegraph": s = _tone(0.38, 380.0, 520.0, 0.3, "sine", 14.0)
		"bolt": s = _tone(0.25, 700.0, 180.0, 0.35, "square")
		"slam": s = _mix(_boom(0.7, 70.0, 1.0), _noise_sweep(0.5, 1500.0, 100.0, 0.6))
		"portal": s = _noise_sweep(0.55, 200.0, 2200.0, 0.35)
		"charge": s = _tone(0.55, 180.0, 700.0, 0.3, "sine", 18.0)
		"charged": s = _mix(_tone(0.35, 1046.0, 1046.0, 0.3, "sine"), _tone(0.35, 1568.0, 1568.0, 0.2, "sine"))
		"denied": s = _tone(0.12, 120.0, 100.0, 0.3, "square")
		"roar_small": s = _distort(_tone(0.6, 95.0, 70.0, 0.6, "saw", 6.0), 2.0)
		"boss_roar": s = _distort(_mix(_mix(_tone(1.4, 55.0, 42.0, 0.6, "saw", 5.0), _tone(1.4, 83.0, 60.0, 0.4, "saw", 7.0)), _noise_sweep(1.4, 900.0, 200.0, 0.4)), 2.2)
		"ability_whirl": s = _tremolo(_whoosh(0.85, 2000.0, 900.0, 0.8), 11.0)
		"ability_crescent": s = _mix(_whoosh(0.4, 3000.0, 600.0, 0.8), _tone(0.4, 880.0, 440.0, 0.2, "sine"))
		"ability_harvest": s = _mix(_mix(_tone(0.9, 220.0, 660.0, 0.25, "sine", 6.0), _tone(0.9, 277.0, 830.0, 0.2, "sine", 6.0)), _noise_sweep(0.9, 300.0, 3000.0, 0.3))
		"wave": s = _gong(1.8)
		"player_death": s = _mix(_tone(1.2, 440.0, 80.0, 0.4, "saw", 5.0), _noise_sweep(1.2, 2000.0, 100.0, 0.3))
		"step": s = _noise_sweep(0.09, 900.0, 200.0, 0.5, 0.002)
		"perfect": s = _mix(_mix(_tone(0.7, 1568.0, 1568.0, 0.25, "sine"), _tone(0.7, 2093.0, 2093.0, 0.18, "sine")), _noise_sweep(0.5, 4000.0, 800.0, 0.35))
		"parry": s = _mix(_tone(0.3, 2637.0, 1975.0, 0.3, "square"), _noise_burst(0.06, 0.6, 7000.0))
		"execute": s = _distort(_mix(_boom(0.9, 55.0, 1.0), _whoosh(0.5, 3000.0, 300.0, 1.0)), 1.6)
		"upgrade": s = _mix(_mix(_tone(0.6, 523.0, 523.0, 0.25, "sine"), _tone(0.6, 784.0, 784.0, 0.2, "sine")), _tone(0.6, 1046.0, 1046.0, 0.15, "sine"))
		"drone":
			s = _drone(8.0)
			loop = true
	return _to_wav(s, loop)

func _env(t: float, dur: float, attack := 0.01) -> float:
	if t < attack:
		return t / attack
	return pow(1.0 - (t - attack) / maxf(dur - attack, 0.001), 2.0)

func _whoosh(dur: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	return _noise_sweep(dur, f0, f1, amp, 0.08)

func _noise_sweep(dur: float, f0: float, f1: float, amp: float, attack := 0.005) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / SR
		var k := t / dur
		var fc := f0 * pow(f1 / f0, k)
		var f := 2.0 * sin(PI * minf(fc, SR * 0.2) / SR)
		var x := _rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - 0.6 * band
		band += f * high
		out[i] = band * amp * _env(t, dur, attack) * 0.8
	return out

func _noise_burst(dur: float, amp: float, fc: float) -> PackedFloat32Array:
	return _noise_sweep(dur, fc, fc * 0.5, amp, 0.001)

func _tone(dur: float, f0: float, f1: float, amp: float, wave: String, vib := 0.0) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var k := t / dur
		var f := f0 * pow(f1 / f0, k) * (1.0 + sin(t * TAU * vib) * 0.03 if vib > 0.0 else 1.0)
		ph = fmod(ph + f / SR, 1.0)
		var v := 0.0
		match wave:
			"sine": v = sin(ph * TAU)
			"saw": v = ph * 2.0 - 1.0
			"square": v = 1.0 if ph < 0.5 else -1.0
		out[i] = v * amp * _env(t, dur, 0.004)
	return out

func _boom(dur: float, f: float, amp: float) -> PackedFloat32Array:
	var a := _tone(dur, f, f * 0.4, amp, "sine")
	return _mix(a, _noise_sweep(dur * 0.6, 600.0, 60.0, amp * 0.6, 0.002))

func _gong(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[98.0, 0.5], [147.5, 0.3], [233.0, 0.22], [311.0, 0.15], [415.0, 0.1]]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for p in partials:
			v += sin(t * TAU * p[0]) * p[1] * exp(-t * (1.5 + p[0] / 200.0))
		out[i] = v * minf(1.0, t / 0.005) * 0.8
	return out

func _drone(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / SR
		var lfo := 0.5 + 0.5 * sin(t * TAU / dur)
		var v := sin(t * TAU * 55.0) * 0.35 + sin(t * TAU * 82.5) * 0.22 * lfo + sin(t * TAU * 110.0 + sin(t * TAU * 0.25) * 2.0) * 0.1
		low += 0.02 * (_rng.randf_range(-1.0, 1.0) - low)
		v += low * 0.6 * (0.6 + 0.4 * lfo)
		out[i] = v * 0.6
	# crossfade the ends for a seamless loop
	var fade := int(0.3 * SR)
	for i in fade:
		var k := float(i) / fade
		out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
	out.resize(n - fade)
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out

func _distort(a: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	for i in a.size():
		a[i] = tanh(a[i] * drive) * 0.7
	return a

func _tremolo(a: PackedFloat32Array, rate: float) -> PackedFloat32Array:
	for i in a.size():
		a[i] *= 0.55 + 0.45 * sin(float(i) / SR * TAU * rate)
	return a

func _to_wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w
