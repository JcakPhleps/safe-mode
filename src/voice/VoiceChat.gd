extends Node
## SAFE MODE — proximity voice chat (autoload singleton "VoiceChat").
##
## PROTOTYPE. Push-to-talk mic capture -> streamed to peers -> played back on
## each remote player's AudioStreamPlayer3D. Because playback is positional,
## 3D falloff gives you proximity chat for free: closer teammates are louder.
##
## Real shipping voice wants Opus compression + jitter buffering; here we send
## lightly-downsampled mono PCM over unreliable RPC, which is fine on a LAN and
## good enough to feel the design. Inert in solo mode or when no mic exists.

const RECORD_BUS := "Record"
const DOWNSAMPLE := 3            # send every Nth frame to cut bandwidth
const MIC_ENABLED_DEFAULT := true

var enabled: bool = MIC_ENABLED_DEFAULT
var _capture: AudioEffectCapture = null
var _mic_player: AudioStreamPlayer = null
var _mix_rate: float = 44100.0
## peer_id -> AudioStreamGeneratorPlayback  (playback handles of remote voices)
var _playbacks: Dictionary = {}
var _active: bool = false        # currently transmitting (push-to-talk held)

func _ready() -> void:
	_mix_rate = AudioServer.get_mix_rate()
	set_process(false) # enabled once a session with voice starts

## Call when a networked session begins. Safe to call when no mic is present.
func begin_session() -> void:
	if not enabled or not Net.is_networked():
		return
	_setup_record_bus()
	_start_mic()
	set_process(true)

func end_session() -> void:
	set_process(false)
	_active = false
	_playbacks.clear()
	if _mic_player:
		_mic_player.stop()

## A remote player registers its positional voice sink (created in Player.gd).
func register_voice_sink(peer_id: int, gen_player: AudioStreamPlayer3D) -> void:
	if gen_player.stream is AudioStreamGenerator:
		gen_player.play()
		var pb := gen_player.get_stream_playback()
		if pb:
			_playbacks[peer_id] = pb

func unregister_voice_sink(peer_id: int) -> void:
	_playbacks.erase(peer_id)

func _process(_delta: float) -> void:
	_active = Input.is_action_pressed("push_to_talk")
	if not _active or _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	var stereo := _capture.get_buffer(available)   # PackedVector2Array
	# downsample to mono to keep the packet small
	var mono := PackedFloat32Array()
	var i := 0
	while i < stereo.size():
		mono.append((stereo[i].x + stereo[i].y) * 0.5)
		i += DOWNSAMPLE
	if mono.size() > 0:
		_send_voice.rpc(mono)

@rpc("any_peer", "call_remote", "unreliable")
func _send_voice(mono: PackedFloat32Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	var pb: AudioStreamGeneratorPlayback = _playbacks.get(from)
	if pb == null:
		return
	# re-expand the downsampled stream by holding each sample
	for s in mono:
		var frame := Vector2(s, s)
		for _r in DOWNSAMPLE:
			if pb.can_push_buffer(1):
				pb.push_frame(frame)

## --- audio plumbing -------------------------------------------------------

func _setup_record_bus() -> void:
	var idx := AudioServer.get_bus_index(RECORD_BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, RECORD_BUS)
	AudioServer.set_bus_mute(idx, true) # never hear your own mic locally
	# ensure a capture effect exists on the record bus
	_capture = null
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(idx, e)
			break
	if _capture == null:
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(idx, _capture)

func _start_mic() -> void:
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		add_child(_mic_player)
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = RECORD_BUS
	_mic_player.play()

## Build a positional sink stream for a remote peer (used by Player.gd).
static func make_generator_stream(mix_rate: float) -> AudioStreamGenerator:
	var g := AudioStreamGenerator.new()
	g.mix_rate = mix_rate
	g.buffer_length = 0.2
	return g
