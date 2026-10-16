extends Node
## SAFE MODE — asset-free procedural audio (autoload singleton "Sound").
##
## Every sound is synthesized into an AudioStreamWAV at boot, so the game ships
## with zero audio files. A low drone runs constantly and its level tracks the
## Horror director's corruption; a heartbeat quickens as dread rises; one-shot
## stingers fire on game events. Crude on purpose — it sits under the VHS look.

const RATE := 22050

var _drone: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _hb_timer := 0.0
var _rng := RandomNumberGenerator.new()

var _wav_heart: AudioStreamWAV
var _wav_sting: AudioStreamWAV
var _wav_purge: AudioStreamWAV
var _wav_unlock: AudioStreamWAV
var _wav_hit: AudioStreamWAV
var _wav_growl: AudioStreamWAV
var _wav_whisper: AudioStreamWAV

func _ready() -> void:
	_rng.randomize()
	_wav_heart = _build_thump()
	_wav_sting = _build_sting()
	_wav_purge = _build_purge()
	_wav_unlock = _build_unlock()
	_wav_hit = _build_hit()
	_wav_growl = _build_growl()
	_wav_whisper = _build_whisper()

	_drone = AudioStreamPlayer.new()
	_drone.stream = _build_drone()
	_drone.volume_db = -24.0
	add_child(_drone)
	_drone.play()

	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func _process(delta: float) -> void:
	var c: float = Horror.corruption if Horror else 0.0
	_drone.volume_db = lerpf(-26.0, -8.0, c)
	# heartbeat: silent when calm, frantic when the machine is close
	_hb_timer -= delta
	if _hb_timer <= 0.0 and c > 0.22:
		_play(_wav_heart, lerpf(-16.0, -3.0, c))
		var bpm := lerpf(58.0, 155.0, c)
		_hb_timer = 60.0 / bpm

## --- public one-shots -----------------------------------------------------

func sting() -> void: _play(_wav_sting, -6.0)
func purge() -> void: _play(_wav_purge, -4.0)
func unlock() -> void: _play(_wav_unlock, -2.0)
func hit() -> void: _play(_wav_hit, -3.0)
func growl() -> void: _play(_wav_growl, -8.0)
func whisper() -> void: _play(_wav_whisper, -10.0)

func _play(wav: AudioStreamWAV, db: float) -> void:
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = wav
	p.volume_db = db
	p.play()

## --- synthesis ------------------------------------------------------------

func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0

func _build_drone() -> AudioStreamWAV:
	# 2s seamless loop: detuned low sines (beating) + slow swell + hiss
	var n := RATE * 2
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 55.0 * t) * 0.4
		v += sin(TAU * 55.5 * t) * 0.30
		v += sin(TAU * 110.0 * t) * 0.12
		v += _noise() * 0.03
		v *= 0.6 + 0.4 * sin(TAU * 0.5 * t) # 1 full swell over the loop
		buf[i] = v * 0.55
	return _to_wav(buf, true)

func _build_thump() -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 16.0)
		buf[i] = (sin(TAU * 46.0 * t) * 0.9 + sin(TAU * 30.0 * t) * 0.5) * env
	return _to_wav(buf)

func _build_sting() -> AudioStreamWAV:
	# short dissonant metallic screech, descending
	var n := int(RATE * 0.45)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 7.0)
		var f := lerpf(900.0, 300.0, t / 0.45)
		var v := sin(TAU * f * t) * 0.5 + sin(TAU * f * 1.48 * t) * 0.4
		v += _noise() * 0.15
		buf[i] = v * env * 0.7
	return _to_wav(buf)

func _build_purge() -> AudioStreamWAV:
	# clean rising confirmation with a little sparkle
	var n := int(RATE * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 5.0)
		var f := lerpf(300.0, 760.0, t / 0.5)
		buf[i] = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.2) * env
	return _to_wav(buf)

func _build_unlock() -> AudioStreamWAV:
	# big ominous downward boom for the final gate
	var n := int(RATE * 1.1)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 2.2)
		var f := lerpf(140.0, 38.0, clampf(t / 0.6, 0.0, 1.0))
		var v := sin(TAU * f * t) * 0.8 + sin(TAU * f * 0.5 * t) * 0.4
		v += _noise() * 0.05 * env
		buf[i] = v * env
	return _to_wav(buf)

func _build_hit() -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 22.0)
		buf[i] = (_noise() * 0.8 + sin(TAU * 90.0 * t) * 0.4) * env
	return _to_wav(buf)

func _build_growl() -> AudioStreamWAV:
	# low, wet, modulated — the shape of something breathing wrong
	var n := int(RATE * 0.9)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / 0.9)                     # fade in/out
		var trem := 0.6 + 0.4 * sin(TAU * 7.0 * t)
		var v := sin(TAU * 58.0 * t) * 0.5 + _noise() * 0.4
		buf[i] = v * env * trem * 0.8
	return _to_wav(buf)

func _build_whisper() -> AudioStreamWAV:
	# breathy amplitude-shaped noise; reads as a voice with no words
	var n := int(RATE * 0.7)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / 0.7)
		var am := 0.5 + 0.5 * sin(TAU * 5.0 * t + sin(t * 30.0))
		buf[i] = _noise() * env * am * 0.5
	return _to_wav(buf)
