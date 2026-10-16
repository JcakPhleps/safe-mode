extends Node3D
## SAFE MODE — entry point + session director.
##
## THE GOAL: the machine is infected by a red sphere of malware that boots into a
## random room the instant you drop in. You start unarmed. Recover all seven
## system components by completing a task in each component room (hold your laser
## on its console) — that ARMS the laser. Then delete the malware before the
## six-minute timer runs out.
##
## If the timer expires with the malware still alive, the machine gives up on
## itself: the lights die and it begins DELETING itself room by room. Your only
## out is the USB jacked into the motherboard's ports — reach it to escape.
##
## Four endings:
##   MALWARE DELETION   — you killed the malware in time (win).
##   SUCCESSFULLY FAILED — you escaped to the USB after time ran out (win).
##   PARASITE           — a parasite drained you (lose).
##   FILE DELETION      — you were in a room when it was deleted (lose).
##
## Solo is the fully-wired path. In co-op the host is authoritative: clients only
## *request* task completion / laser hits / escape over RPC; the host owns tasks,
## the timer, the deletion schedule, and win/lose, and mirrors them to everyone.

const PlayerScene := preload("res://src/player/Player.tscn")
const MalwareScene := preload("res://src/enemies/Malware.tscn")
const ParasiteScene := preload("res://src/enemies/Parasite.tscn")
const WorldBuilderScript := preload("res://src/world/WorldBuilder.gd")
const DeletionVoidScript := preload("res://src/world/DeletionVoid.gd")
const HUDScript := preload("res://src/ui/HUD.gd")

const TIME_LIMIT := 360.0          # six minutes to delete the malware
const PARASITE_FIRST := 40.0       # first parasite emerges this many seconds in
const PARASITE_INTERVAL := 38.0
const MAX_PARASITES := 6
const DELETE_INTERVAL := 6.0       # a room is erased this often during the purge

enum Phase { RECOVER, PURGE }

const ENDINGS := {
	"MALWARE": {
		"title": "MALWARE DELETION",
		"sub": "the red thing is gone. the machine is yours again.",
		"color": Color(0.4, 1.0, 0.6), "win": true},
	"ESCAPE": {
		"title": "SUCCESSFULLY FAILED",
		"sub": "you reached :/USB as the drive went dark.\nyou survived. the machine did not.",
		"color": Color(1.0, 0.8, 0.3), "win": true},
	"PARASITE": {
		"title": "PARASITE",
		"sub": "one of them latched on, and did not let go.",
		"color": Color(1.0, 0.3, 0.35), "win": false},
	"DELETION": {
		"title": "FILE DELETION",
		"sub": "you were standing in a sector that no longer exists.",
		"color": Color(0.9, 0.2, 0.2), "win": false},
}

var _menu: Control
var _world: Node3D
var _entities: Node3D
var _spawner: MultiplayerSpawner
var _hud

var _task_ids: Array = []
var _tasks: Dictionary = {}         # id -> Task node
var _done: Dictionary = {}          # id -> true (mirrored on every peer)
var _armed: bool = false

var _spawns: Array = []
var _room_centers: Dictionary = {}
var _room_containers: Dictionary = {}
var _room_half: float = 7.0
var _room_height: float = 5.5
var _malware_spawns: Array = []
var _malware_spawn: Vector3 = Vector3.ZERO
var _malware: Node = null
var _usb: Area3D = null

var _phase: int = Phase.RECOVER
var _time_left: float = TIME_LIMIT
var _parasite_timer: float = PARASITE_FIRST
var _parasite_count: int = 0
var _purge_started: bool = false
var _delete_order: Array = []
var _delete_timer: float = 0.0

var _game_over: bool = false
var _last_cause: String = "PARASITE"
var _end_ui: CanvasLayer = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("game")
	_rng.randomize()
	get_tree().paused = false
	var intent := Net.next_boot
	Net.next_boot = ""
	if intent == "menu":
		_build_menu()
		return
	if intent == "solo" or "--solo" in OS.get_cmdline_user_args():
		_start_solo()
		return
	_build_menu()

func is_armed() -> bool:
	return _armed

func _is_authority() -> bool:
	return Net.mode == Net.Mode.SOLO or Net.mode == Net.Mode.HOST

## --- menu -----------------------------------------------------------------

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.015)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.add_theme_constant_override("separation", 12)
	_menu.add_child(vb)

	var title := Label.new()
	title.text = "S A F E   M O D E"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "recover the components. arm the laser. delete the malware\nbefore the drive deletes itself."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.4, 0.5, 0.45))
	vb.add_child(sub)

	vb.add_child(_spacer(16))

	var solo := _mk_button("SOLO  (nobody has to come with you)")
	solo.pressed.connect(_start_solo)
	vb.add_child(solo)

	var host := _mk_button("HOST  (up to 5)")
	host.pressed.connect(_start_host)
	vb.add_child(host)

	var ip := LineEdit.new()
	ip.placeholder_text = "host address (blank = 127.0.0.1)"
	ip.custom_minimum_size = Vector2(320, 0)
	vb.add_child(ip)

	var join := _mk_button("JOIN")
	join.pressed.connect(func(): _start_client(ip.text))
	vb.add_child(join)

	var quit := _mk_button("QUIT")
	quit.pressed.connect(func(): get_tree().quit())
	vb.add_child(quit)

	add_child(_menu)

func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 40)
	return b

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

## --- session start --------------------------------------------------------

func _start_solo() -> void:
	Net.start_solo()
	_begin()
	_spawn_world_entities_local()

func _start_host() -> void:
	if Net.start_host() != OK:
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_begin()
	_setup_spawner()
	VoiceChat.begin_session()
	_spawner.spawn({"type": "malware", "pos": _malware_spawn})
	_spawner.spawn({"type": "player", "peer": 1, "pos": _pick_spawn(0)})

func _start_client(ip: String) -> void:
	if Net.start_client(ip) != OK:
		return
	Net.client_connected.connect(func():
		VoiceChat.begin_session()
		, CONNECT_ONE_SHOT)
	_begin()
	_setup_spawner()

func _begin() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	Horror.reset()
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var data := WorldBuilderScript.new().build(_world)
	_spawns = data.spawns
	_room_centers = data.room_centers
	_room_containers = data.room_containers
	_room_half = data.room_half
	_room_height = data.room_height
	_malware_spawns = data.malware_spawns
	_task_ids = data.task_ids
	_usb = data.usb
	for t in data.tasks:
		_tasks[t.id] = t
		t.completed.connect(_on_task_completed)
	if is_instance_valid(_usb):
		_usb.body_entered.connect(_on_usb_body)
	_malware_spawn = _malware_spawns[_rng.randi() % _malware_spawns.size()] if not _malware_spawns.is_empty() else Vector3(0, 1.4, 0)

	_entities = Node3D.new()
	_entities.name = "Entities"
	add_child(_entities)

	_hud = HUDScript.new()
	add_child(_hud)
	_hud.set_components(0, _task_ids.size())
	_hud.set_time(_time_left)

## --- spawning -------------------------------------------------------------

func _setup_spawner() -> void:
	_spawner = MultiplayerSpawner.new()
	add_child(_spawner)
	_spawner.spawn_path = _entities.get_path()
	_spawner.spawn_function = Callable(self, "_spawn_entity")

func _spawn_entity(data: Dictionary) -> Node:
	var t: String = data.get("type", "player")
	if t == "malware":
		var m := MalwareScene.instantiate()
		m.position = data.get("pos", Vector3.ZERO)
		_register_malware(m)
		return m
	if t == "parasite":
		var pa := ParasiteScene.instantiate()
		pa.position = data.get("pos", Vector3.ZERO)
		return pa
	var p := PlayerScene.instantiate()
	p.name = str(data.get("peer", 1))
	p.position = data.get("pos", Vector3.ZERO)
	if str(data.get("peer", 1)) == str(Net.local_id()):
		p.died.connect(_on_local_died)
	return p

func _spawn_world_entities_local() -> void:
	var m := MalwareScene.instantiate()
	m.position = _malware_spawn
	_entities.add_child(m)
	_register_malware(m)

	var p := PlayerScene.instantiate()
	p.name = "1"
	p.position = _pick_spawn(0)
	_entities.add_child(p)
	p.died.connect(_on_local_died)
	_hud.player = p

func _register_malware(m: Node) -> void:
	_malware = m
	if m.has_signal("killed"):
		m.killed.connect(_on_malware_killed)

func _spawn_parasite() -> void:
	if _parasite_count >= MAX_PARASITES or _malware_spawns.is_empty():
		return
	_parasite_count += 1
	var pos: Vector3 = _malware_spawns[_rng.randi() % _malware_spawns.size()]
	if Net.mode == Net.Mode.SOLO:
		var pa := ParasiteScene.instantiate()
		pa.position = pos
		_entities.add_child(pa)
	elif Net.mode == Net.Mode.HOST:
		_spawner.spawn({"type": "parasite", "pos": pos})
	Horror.announce("SOMETHING SPLIT OFF FROM THE INFECTION.")
	if Sound:
		Sound.sting()

func _on_peer_connected(id: int) -> void:
	var idx := _entities.get_child_count()
	_spawner.spawn({"type": "player", "peer": id, "pos": _pick_spawn(idx)})

func _on_peer_disconnected(id: int) -> void:
	VoiceChat.unregister_voice_sink(id)
	var node := _entities.get_node_or_null(str(id))
	if node:
		node.queue_free()

func _pick_spawn(i: int) -> Vector3:
	if _spawns.is_empty():
		return Vector3(0, 1, 0)
	return _spawns[i % _spawns.size()]

## --- main loop ------------------------------------------------------------

func _process(delta: float) -> void:
	if _hud and not is_instance_valid(_hud.player) and _entities:
		var mine := _entities.get_node_or_null(str(Net.local_id()))
		if mine:
			_hud.player = mine
	if _hud and _armed and is_instance_valid(_malware):
		_hud.set_malware_health(_malware.health / _malware.max_health)
	if _game_over:
		return

	if _phase == Phase.RECOVER:
		_time_left = maxf(0.0, _time_left - delta)
		if _hud:
			_hud.set_time(_time_left)
		# authority spawns parasites and triggers the purge
		if _is_authority():
			_parasite_timer -= delta
			if _parasite_timer <= 0.0:
				_parasite_timer = PARASITE_INTERVAL
				_spawn_parasite()
			if _time_left <= 0.0 and not _purge_started:
				_trigger_purge()
	elif _phase == Phase.PURGE and _is_authority():
		_delete_timer -= delta
		if _delete_timer <= 0.0 and not _delete_order.is_empty():
			_delete_timer = DELETE_INTERVAL
			var room: String = _delete_order.pop_front()
			_do_delete_room(room)
			if Net.mode == Net.Mode.HOST:
				rpc("_rpc_delete_room", room)

	# co-op loss: host ends the run when every process is down
	if Net.mode == Net.Mode.HOST and not _game_over:
		var players := get_tree().get_nodes_in_group("players")
		if players.size() > 0:
			var all_down := true
			for p in players:
				if p.get("downed") != true:
					all_down = false
					break
			if all_down:
				_end(_last_cause)

## --- component tasks (host-authoritative) ----------------------------------

func _on_task_completed(id: String) -> void:
	if Net.mode == Net.Mode.CLIENT:
		rpc_id(1, "_srv_task_done", id)
	else:
		_authoritative_task(id)

@rpc("any_peer", "reliable")
func _srv_task_done(id: String) -> void:
	_authoritative_task(id)

func _authoritative_task(id: String) -> void:
	if _done.has(id):
		return
	_apply_task(id)
	if Net.mode == Net.Mode.HOST:
		rpc("_apply_task", id)

@rpc("authority", "call_remote", "reliable")
func _apply_task(id: String) -> void:
	if _done.has(id):
		return
	_done[id] = true
	var node = _tasks.get(id)
	if node and is_instance_valid(node):
		node.complete_visual()
	_hud.set_components(_done.size(), _task_ids.size())
	Horror.announce("COMPONENT RECOVERED  %d / %d" % [_done.size(), _task_ids.size()])
	Horror.raise_baseline(0.04)
	if _done.size() >= _task_ids.size() and not _armed:
		_arm()

func _arm() -> void:
	_armed = true
	_hud.set_armed(true)
	Horror.trigger_beat("STATIC_SURGE")
	if Sound:
		Sound.unlock()
	Horror.announce("LASER ARMED.  DELETE THE MALWARE.")

## --- damaging hostiles (host-authoritative) --------------------------------

func hit_hostile(node: Node, amount: float) -> void:
	if not is_instance_valid(node) or not node.has_method("damage"):
		return
	# the malware sphere is invulnerable until the laser is armed; parasites never are
	if node.is_in_group("malware") and not _armed:
		return
	if Net.mode == Net.Mode.CLIENT:
		rpc_id(1, "_srv_hit_hostile", node.get_path(), amount)
	else:
		node.damage(amount)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _srv_hit_hostile(path: NodePath, amount: float) -> void:
	var n := get_node_or_null(path)
	if not is_instance_valid(n) or not n.has_method("damage"):
		return
	if n.is_in_group("malware") and not _armed:
		return
	n.damage(amount)

func _on_malware_killed() -> void:
	if _phase == Phase.RECOVER:
		_end("MALWARE")

## --- the purge: blackout, self-deletion, escape ----------------------------

func _trigger_purge() -> void:
	_begin_purge()
	if Net.mode == Net.Mode.HOST:
		rpc("_rpc_begin_purge")

@rpc("authority", "call_remote", "reliable")
func _rpc_begin_purge() -> void:
	_begin_purge()

func _begin_purge() -> void:
	if _purge_started:
		return
	_purge_started = true
	_phase = Phase.PURGE
	# the lights die
	for l in get_tree().get_nodes_in_group("lights"):
		if l.has_method("force_dark"):
			l.force_dark(99999.0)
	Horror.trigger_beat("STATIC_SURGE")
	Horror.raise_baseline(0.4)
	if _hud:
		_hud.set_purge()
	Horror.announce("TIME OUT.  THE DRIVE IS DELETING ITSELF.")
	await get_tree().create_timer(2.0).timeout
	Horror.announce("GET TO THE USB IN THE MOTHERBOARD.")
	# authority plans the deletion order: farthest rooms from the USB first, so
	# the safe zone collapses toward the motherboard the player must reach
	if _is_authority():
		var mobo: Vector3 = _room_centers.get("MOBO", Vector3.ZERO)
		var order := []
		for name in _room_containers:
			if name != "MOBO":
				order.append(name)
		order.sort_custom(func(a, b):
			return _room_centers[a].distance_to(mobo) > _room_centers[b].distance_to(mobo))
		_delete_order = order
		_delete_timer = DELETE_INTERVAL

func _do_delete_room(name: String) -> void:
	var room = _room_containers.get(name)
	if room and is_instance_valid(room):
		room.queue_free()
	_room_containers.erase(name)
	# a void that deletes any process caught inside the erased sector
	var void_area = DeletionVoidScript.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_room_half * 2, _room_height + 6.0, _room_half * 2)
	cs.shape = box
	void_area.add_child(cs)
	void_area.position = _room_centers[name] + Vector3(0, _room_height * 0.5 - 1.0, 0)
	_world.add_child(void_area)
	Horror.announce("SECTOR %s DELETED." % name)
	if Sound:
		Sound.sting()

@rpc("authority", "call_remote", "reliable")
func _rpc_delete_room(name: String) -> void:
	_do_delete_room(name)

func _on_usb_body(body: Node) -> void:
	if _phase != Phase.PURGE or _game_over:
		return
	if not body.is_in_group("players") or not body.is_multiplayer_authority():
		return
	if body.get("downed") == true:
		return
	if Net.mode == Net.Mode.CLIENT:
		rpc_id(1, "_srv_escape")
	else:
		_end("ESCAPE")

@rpc("any_peer", "reliable")
func _srv_escape() -> void:
	_end("ESCAPE")

## --- win / lose -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		var m := DisplayServer.window_get_mode()
		if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_local_died(_peer: int, cause: String) -> void:
	if Net.mode == Net.Mode.SOLO:
		_end(cause)
	elif Net.mode == Net.Mode.CLIENT:
		rpc_id(1, "_srv_player_down", cause)
	else:
		_srv_player_down(cause)

@rpc("any_peer", "reliable")
func _srv_player_down(cause: String) -> void:
	_last_cause = cause   # host's all-down check in _process ends the run

func _end(key: String) -> void:
	if _game_over:
		return
	_game_over = true
	_show_end(key)
	if Net.mode == Net.Mode.HOST:
		rpc("_rpc_end", key)

@rpc("authority", "call_remote", "reliable")
func _rpc_end(key: String) -> void:
	if _game_over:
		return
	_game_over = true
	_show_end(key)

var _ending: String = ""

func _show_end(key: String) -> void:
	_ending = key
	var e: Dictionary = ENDINGS.get(key, ENDINGS["PARASITE"])
	Horror.announce(e.title)
	_hud.show_card("%s\n\n%s" % [e.title, e.sub], e.color)
	_build_end_menu()

func _build_end_menu() -> void:
	if is_instance_valid(_end_ui):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

	_end_ui = CanvasLayer.new()
	_end_ui.layer = 5
	_end_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_end_ui)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_ui.add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.add_theme_constant_override("separation", 12)
	vb.anchor_top = 0.66
	vb.anchor_bottom = 0.66
	_end_ui.add_child(vb)

	if not Net.is_networked():
		var retry := _mk_button("RESTART")
		retry.pressed.connect(func(): _reboot("solo"))
		vb.add_child(retry)

	var menu := _mk_button("MAIN MENU")
	menu.pressed.connect(func(): _reboot("menu"))
	vb.add_child(menu)

	var quit := _mk_button("QUIT")
	quit.pressed.connect(func(): get_tree().quit())
	vb.add_child(quit)

func _reboot(intent: String) -> void:
	if Net.is_networked():
		Net.leave()
	Net.next_boot = intent
	get_tree().paused = false
	get_tree().reload_current_scene()
