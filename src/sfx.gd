class_name Sfx
extends Node
## Tiny synthesized sound effects, so the game needs no audio files.

const RATE := 22050

static var inst: Sfx
var players: Array[AudioStreamPlayer] = []
var streams := {}
var next := 0
var enabled := true


func _ready() -> void:
	inst = self
	enabled = Storage.get_setting("sound", true)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		players.append(p)
	streams["tap"] = _make(_tone([[1046.0, 0.035]], 0.25, 0.0))
	streams["move"] = _make(_steps())
	streams["attack"] = _make(_clash())
	streams["kill"] = _make(_tone([[392.0, 0.08], [294.0, 0.08], [196.0, 0.22]], 0.35, 0.3))
	streams["build"] = _make(_knock())
	streams["coin"] = _make(_tone([[988.0, 0.06], [1319.0, 0.16]], 0.3, 0.0))
	streams["capture"] = _make(_tone([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.3]], 0.35, 0.25))
	streams["turn"] = _make(_horn())
	streams["victory"] = _make(_tone([[523.0, 0.15], [523.0, 0.08], [659.0, 0.15], [784.0, 0.15], [659.0, 0.1], [784.0, 0.1], [1047.0, 0.6]], 0.35, 0.3))
	streams["error"] = _make(_tone([[220.0, 0.08], [185.0, 0.12]], 0.3, 0.4))


static func play(name: String) -> void:
	if inst == null or not inst.enabled or not inst.streams.has(name):
		return
	var p := inst.players[inst.next]
	inst.next = (inst.next + 1) % inst.players.size()
	p.stream = inst.streams[name]
	p.play()


static func set_enabled(on: bool) -> void:
	Storage.set_setting("sound", on)
	if inst:
		inst.enabled = on


static func is_enabled() -> bool:
	return inst == null or inst.enabled


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## A sequence of notes: [[freq, seconds], ...]. "buzz" adds odd harmonics.
func _tone(notes: Array, vol: float, buzz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var f: float = n[0]
		var count := int(RATE * float(n[1]))
		for i in count:
			var t := float(i) / RATE
			var env := minf(1.0, i / 120.0) * exp(-3.5 * t / float(n[1]))
			var s := sin(TAU * f * t) + buzz * sin(TAU * f * 3.0 * t) / 3.0 + buzz * 0.5 * sin(TAU * f * 5.0 * t) / 5.0
			out.append(s * env * vol)
	return out


func _noise_burst(count: int, decay: float, smooth: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var prev := 0.0
	for i in count:
		var t := float(i) / RATE
		prev = lerpf(prev, rng.randf_range(-1.0, 1.0), smooth)
		out.append(prev * exp(-decay * t))
	return out


func _steps() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in 3:
		var b := _noise_burst(int(RATE * 0.05), 60.0, 0.12)
		for i in b.size():
			out.append(b[i] * 0.5)
		for i in int(RATE * 0.045):
			out.append(0.0)
	return out


func _clash() -> PackedFloat32Array:
	var out := _noise_burst(int(RATE * 0.18), 22.0, 0.6)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = out[i] * 0.35 + 0.5 * sin(TAU * 110.0 * t) * exp(-18.0 * t) + 0.18 * sin(TAU * 1780.0 * t) * exp(-30.0 * t)
	return out


func _knock() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in 2:
		for i in int(RATE * 0.07):
			var t := float(i) / RATE
			out.append(0.55 * sin(TAU * (320.0 - k * 40.0) * t) * exp(-45.0 * t))
		for i in int(RATE * 0.05):
			out.append(0.0)
	return out


func _horn() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(RATE * 0.55)
	for i in count:
		var t := float(i) / RATE
		var f := 196.0 * (1.0 + 0.006 * sin(TAU * 5.5 * t))
		var env := minf(1.0, t / 0.06) * minf(1.0, (0.55 - t) / 0.2)
		var s := sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t) + 0.25 * sin(TAU * f * 3.0 * t)
		out.append(s * env * 0.22)
	return out
