extends Node
## All sounds are synthesized at startup (no audio files): an underwater rumble loop plus
## bubble blips, a food "plop", a fish "nom", a fingertip "boop" and a call chime.

const RATE := 22050
var streams := {}
var pool: Array[AudioStreamPlayer3D] = []
var next := 0
var ambient: AudioStreamPlayer


func _ready() -> void:
	streams["bubble"] = _make(0.09, func(t: float, r: float) -> float:
		return sin(TAU * (500.0 * t + 6000.0 * t * t)) * 0.5 * exp(-t * 40.0))
	streams["plop"] = _make(0.12, func(t: float, r: float) -> float:
		return sin(TAU * (300.0 * t + 2500.0 * t * t)) * 0.6 * exp(-t * 30.0) + r * 0.05 * exp(-t * 80.0))
	streams["nom"] = _make(0.12, func(t: float, r: float) -> float:
		var f := 700.0 if t < 0.05 else 950.0
		return sin(TAU * f * t) * 0.35 * exp(-fmod(t, 0.06) * 50.0))
	streams["boop"] = _make(0.1, func(t: float, r: float) -> float:
		return sin(TAU * (1100.0 * t - 2000.0 * t * t)) * 0.4 * exp(-t * 35.0))
	streams["chime"] = _make(0.9, func(t: float, r: float) -> float:
		var v := 0.0
		var notes := [523.25, 659.25, 783.99, 1046.5]
		for k in 4:
			var t0 := k * 0.12
			if t > t0:
				v += sin(TAU * notes[k] * (t - t0)) * 0.2 * exp(-(t - t0) * 4.0)
		return v)
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 2.0
		add_child(p)
		pool.append(p)
	ambient = AudioStreamPlayer.new()
	ambient.stream = _ambient_loop()
	ambient.volume_db = -6.0
	add_child(ambient)
	ambient.play()


func _make(length: float, gen: Callable) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(length)
	for i in n:
		var v: float = gen.call(float(i) / RATE, rng.randf_range(-1.0, 1.0))
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


func _ambient_loop() -> AudioStreamWAV:
	## 8 s of low-passed noise with a slow swell; the ends are cross-faded so it loops cleanly.
	var secs := 8.0
	var n := int(secs * RATE)
	var fade := int(1.0 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n + fade:
		lp1 += (rng.randf_range(-1, 1) - lp1) * 0.02
		lp2 += (lp1 - lp2) * 0.05
		var t := float(i) / RATE
		buf[i] = lp2 * 6.0 * (0.75 + 0.25 * sin(TAU * t / secs * 2.0))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := buf[i]
		if i < fade:
			var k := float(i) / fade
			v = buf[i] * k + buf[n + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func play(sound: String, pos: Vector3, vol_db := 0.0) -> void:
	if not is_inside_tree() or not streams.has(sound):
		return
	var p := pool[next]
	next = (next + 1) % pool.size()
	p.stream = streams[sound]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = randf_range(0.85, 1.2)
	p.play()
