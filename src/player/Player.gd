extends CharacterBody3D
## SAFE MODE — first-person player. Built entirely in code so the .tscn stays a
## one-liner and the same scene works for solo and for every networked peer.
##
## The authority peer runs input + physics; a MultiplayerSynchronizer replicates
## the resulting transform to everyone else. Remote players get a positional
## voice sink so teammates are heard in 3D (proximity chat).

const SPEED := 4.2
const SPRINT := 6.6
const JUMP := 6.0
const MOUSE_SENS := 0.0022
const SCAN_RANGE := 7.0
const BEAM_DPS := 34.0             # laser damage/sec against hostiles once armed
# scan ray hits the world (1) so walls block it, task consoles (1<<2) which the
# laser fills anytime, and hostiles (1<<3) which the armed laser burns.
const SCAN_MASK := 1 | 4 | 8

signal died(peer_id: int, cause: String)

var health: float = 100.0
var downed: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

var _head: Node3D
var _cam: Camera3D
var _flashlight: SpotLight3D
var _beam: MeshInstance3D
var _scan_ray: RayCast3D
var _beam_mat: StandardMaterial3D
var _pitch: float = 0.0
var head_pitch: float = 0.0   # replicated; remote peers apply it to the Head node
var _game: Node = null

func _enter_tree() -> void:
	# name is set to the owning peer id by the spawner; wire authority early.
	# Both this node's and the synchronizer's authority MUST be set here (not in
	# _ready) or Godot can't attach a network id to the synchronizer at spawn.
	var id := name.to_int()
	if id != 0:
		set_multiplayer_authority(id)
	_build_synchronizer()

func _ready() -> void:
	add_to_group("players")
	_game = get_tree().get_first_node_in_group("game")
	_build_body()

	if _is_local():
		_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_cam.current = false
		_add_voice_sink()

func _is_local() -> bool:
	# in solo there is no peer, so authority id 1 == local id 1
	return is_multiplayer_authority()

## --- construction ---------------------------------------------------------

func _build_body() -> void:
	var cap := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.8
	shape.radius = 0.35
	cap.shape = shape
	cap.position = Vector3(0, 0.9, 0)
	add_child(cap)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 1.6, 0)
	add_child(_head)

	_cam = Camera3D.new()
	_cam.fov = 78.0
	_head.add_child(_cam)

	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(0.8, 1.0, 0.9)
	_flashlight.light_energy = 4.0
	_flashlight.spot_range = 18.0
	_flashlight.spot_angle = 35.0
	_flashlight.rotation_degrees = Vector3(0, 0, 0)
	_cam.add_child(_flashlight)

	# scan beam (hidden until scanning)
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, SCAN_RANGE)
	_beam.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.3, 1.0, 0.6)
	bmat.emission_enabled = true
	bmat.emission = Color(0.4, 1.0, 0.7)
	bmat.emission_energy_multiplier = 3.0
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color.a = 0.5
	_beam_mat = bmat
	_beam.material_override = bmat
	_beam.position = Vector3(0.25, -0.2, -SCAN_RANGE * 0.5)
	_beam.visible = false
	_cam.add_child(_beam)

	_scan_ray = RayCast3D.new()
	_scan_ray.target_position = Vector3(0, 0, -SCAN_RANGE)
	_scan_ray.collision_mask = SCAN_MASK
	_scan_ray.add_exception(self)   # never scan your own capsule
	_scan_ray.enabled = true
	_cam.add_child(_scan_ray)

	# body mesh so other players can see you (a crude figure)
	var torso := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.height = 1.6
	caps.radius = 0.3
	torso.mesh = caps
	torso.position = Vector3(0, 0.9, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 0.25, 0.3)
	pmat.emission_enabled = true
	pmat.emission = Color(0.05, 0.2, 0.1)
	torso.material_override = pmat
	torso.visible = not _is_local()  # don't render your own body over the camera
	add_child(torso)

func _build_synchronizer() -> void:
	# Only node-level properties here — no child paths — so the synchronizer can
	# register at spawn even though the body/Head are built later in _ready.
	# Head pitch rides along as a plain float (head_pitch) and is applied to the
	# Head node visually on remote peers.
	var sync := MultiplayerSynchronizer.new()
	var cfg := SceneReplicationConfig.new()
	for prop in [".:position", ".:rotation", ".:head_pitch", ".:downed"]:
		cfg.add_property(NodePath(prop))
		cfg.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	# authority is left to inherit from this node (set just above in _enter_tree);
	# setting it on the synchronizer after the fact trips Godot's spawn timing.
	add_child(sync)

func _add_voice_sink() -> void:
	var sink := AudioStreamPlayer3D.new()
	sink.name = "VoiceSink"
	sink.stream = VoiceChat.make_generator_stream(AudioServer.get_mix_rate())
	sink.unit_size = 4.0          # proximity falloff distance
	sink.max_distance = 22.0
	sink.position = Vector3(0, 1.4, 0)
	add_child(sink)
	VoiceChat.register_voice_sink(get_multiplayer_authority(), sink)

func _process(_delta: float) -> void:
	if not _is_local():
		# mirror the replicated head pitch so remote players look where they aim
		if _head:
			_head.rotation.x = head_pitch
		return
	# feed the atmosphere director with how close the nearest malware is
	var nearest := INF
	for m in get_tree().get_nodes_in_group("malware"):
		nearest = minf(nearest, global_position.distance_to(m.global_position))
	if nearest < INF:
		Horror.set_threat_distance(nearest)

## --- input / look ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local() or downed:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.4, 1.4)
		_head.rotation.x = _pitch
		head_pitch = _pitch
	if event.is_action_pressed("flashlight"):
		_flashlight.visible = not _flashlight.visible
	# Esc always frees the mouse; a click grabs it back (and doesn't scan that frame)
	if event.is_action_pressed("menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

## --- movement + scanning --------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _is_local():
		return
	if downed:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := SPRINT if Input.is_action_pressed("sprint") else SPEED
	if dir:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	_handle_scan(delta)

func _handle_scan(delta: float) -> void:
	var scanning := Input.is_action_pressed("scan") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_beam.visible = scanning
	var armed: bool = _game != null and _game.is_armed()
	# beam reads green while it's just a scanner, hot white-red once it can kill
	_beam_mat.emission = Color(1.0, 0.3, 0.2) if armed else Color(0.4, 1.0, 0.7)
	_beam_mat.albedo_color = Color(1.0, 0.35, 0.25, 0.5) if armed else Color(0.3, 1.0, 0.6, 0.5)
	if not scanning:
		return
	_scan_ray.force_raycast_update()
	if not _scan_ray.is_colliding():
		return
	var hit := _scan_ray.get_collider()
	if hit == null:
		return
	if hit.is_in_group("task") and hit.has_method("apply_scan"):
		hit.apply_scan(delta)                 # recover components anytime
	elif hit.is_in_group("hostile") and hit.has_method("damage"):
		# parasites can be deleted anytime; the malware sphere needs the armed laser
		if not hit.is_in_group("malware") or armed:
			_game.hit_hostile(hit, BEAM_DPS * delta)

## --- damage ---------------------------------------------------------------

func hit(amount: float, cause: String = "PARASITE") -> void:
	if downed:
		return
	health -= amount
	Horror.pulse(0.3)
	if Sound:
		Sound.hit()
	if health <= 0.0:
		_go_down(cause)

## Instant death with no chip damage — used by the deletion voids.
func kill(cause: String) -> void:
	if downed:
		return
	health = 0.0
	_go_down(cause)

func _go_down(cause: String) -> void:
	downed = true
	health = 0.0
	Horror.pulse(0.8)
	Horror.announce("CONNECTION TO %s LOST." % name)
	died.emit(name.to_int(), cause)
	# collapse the view
	if _is_local():
		_head.position.y = 0.4
