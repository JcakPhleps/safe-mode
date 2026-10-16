extends Node
## SAFE MODE — global networking + session state (autoload singleton "Net").
##
## Owns the multiplayer peer and the current session mode. Registers input
## actions at boot so project.godot stays tiny. Player spawning lives in
## Main.gd, which listens to the multiplayer signals directly.

enum Mode { NONE, SOLO, HOST, CLIENT }

const PORT := 24545
const MAX_PLAYERS := 5

var mode: int = Mode.NONE
var player_name: String = "USER"
# what Main should do on its next _ready (survives reload_current_scene, since Net
# is an autoload). "" = use the default (cmdline --solo, else the menu).
var next_boot: String = ""

signal server_started
signal client_connected
signal connection_failed
signal server_disconnected

func _ready() -> void:
	_register_input()
	multiplayer.connected_to_server.connect(func(): client_connected.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_disconnected.emit())

## --- session entry points -------------------------------------------------

func start_solo() -> void:
	mode = Mode.SOLO
	# No peer: everything runs locally. Multiplayer APIs still work as a
	# single "server" authority (id 1) which keeps spawn code path uniform.

func start_host() -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("SAFE MODE: could not host on port %d (err %d)" % [PORT, err])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	server_started.emit()
	return OK

func start_client(ip: String) -> int:
	if ip.strip_edges() == "":
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("SAFE MODE: could not connect to %s (err %d)" % [ip, err])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return OK

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.NONE

func is_networked() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT

func local_id() -> int:
	if is_networked():
		return multiplayer.get_unique_id()
	return 1 # solo authority

## --- input registration ---------------------------------------------------

func _register_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE])
	_bind("sprint", [KEY_SHIFT])
	_bind("interact", [KEY_E])
	_bind("flashlight", [KEY_F])
	_bind("menu", [KEY_ESCAPE])
	_bind("fullscreen", [KEY_F11])
	_bind("push_to_talk", [KEY_V])
	_bind_mouse("scan", MOUSE_BUTTON_LEFT)

func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _bind_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
