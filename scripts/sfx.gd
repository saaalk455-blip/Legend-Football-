class_name Sfx
extends Node
## Procedural sound effects (no audio files): kick, bounce, whistle, goal
## cheer and a looping crowd murmur. Everything is synthesised at start-up.

const RATE := 22050

var _streams := {}
var _players := {}


func _ready() -> void:
	_streams["kick"] = _make(0.14, func(t: float, i: int) -> float:
		return sin(TAU * (140.0 - 600.0 * t) * t) * exp(-t * 30.0) + (randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.5)
	_streams["bounce"] = _make(0.10, func(t: float, i: int) -> float:
		return sin(TAU * 90.0 * t) * exp(-t * 40.0))
	_streams["whistle"] = _make(0.55, func(t: float, i: int) -> float:
		var f := 2800.0 + 120.0 * sin(TAU * 28.0 * t)
		var env := minf(t * 40.0, 1.0) * clampf((0.55 - t) * 12.0, 0.0, 1.0)
		return sin(TAU * f * t) * env * 0.6)
	_streams["cheer"] = _make(2.2, func(t: float, i: int) -> float:
		var env := minf(t * 4.0, 1.0) * clampf((2.2 - t) * 1.5, 0.0, 1.0)
		return (randf() * 2.0 - 1.0) * env * 0.5)
	var crowd := _make(2.0, func(t: float, i: int) -> float:
		return (randf() * 2.0 - 1.0) * 0.18 + sin(TAU * 110.0 * t) * 0.05)
	crowd.loop_mode = AudioStreamWAV.LOOP_FORWARD
	crowd.loop_end = int(2.0 * RATE)
	_streams["crowd"] = crowd
	for k in _streams:
		var p := AudioStreamPlayer.new()
		p.stream = _streams[k]
		add_child(p)
		_players[k] = p
	if Global.sound_on:
		var c: AudioStreamPlayer = _players["crowd"]
		c.volume_db = -22.0
		c.play()


func play(name: String, volume_db: float = 0.0) -> void:
	if not Global.sound_on or not _players.has(name):
		return
	var p: AudioStreamPlayer = _players[name]
	p.volume_db = volume_db
	p.play()


func _make(secs: float, fn: Callable) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var v := clampf(float(fn.call(float(i) / RATE, i)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
