extends CharacterBody3D
## SAFE MODE — a parasite. The malware sheds these: fast, jittering red husks
## that hunt whoever is nearest and try to latch on. If one drains you to zero
## you end up in the "Parasite" ending. Weak — an armed laser pops them — but
## they come in a rising tide, so ignoring them is how you die.
##
## Host/solo authority runs the AI; clients get replicated transform + death.

signal killed

const HOSTILE_LAYER := 8     # 1<<3 — the laser can hit it once armed
const SPEED := 5.4
const DMG := 12.0
const CD := 0.7

var max_health: float = 22.0
var health: float = 22.0
var _dead: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)
var _attack_timer: float = 0.0
var _t: float = 0.0
var _death_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _core: MeshInstance3D
var _glow: OmniLight3D
var _bar_root: Node3D
var _bar_fill: MeshInstance3D

func _enter_tree() -> void:
	set_multiplayer_authority(1)
	_build_synchronizer()

func _ready() -> void:
	_rng.randomize()
	add_to_group("hostile")
	add_to_group("parasite")
	collision_layer = 1 | HOSTILE_LAYER
	collision_mask = 1
	_build_body()

func _build_body() -> void:
	var cap := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.1
	shape.radius = 0.3
	cap.shape = shape
	cap.position = Vector3(0, 0.55, 0)
	add_child(cap)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.0, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.05, 0.08)
	mat.emission_energy_multiplier = 1.8

	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	_core.mesh = sm
	_core.material_override = mat
	_core.position = Vector3(0, 0.6, 0)
	add_child(_core)

	for i in 4:
		var spike := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.5, 0.09)
		spike.mesh = bm
		spike.material_override = mat
		var ang := TAU * float(i) / 4.0
		spike.position = Vector3(cos(ang) * 0.3, 0.6, sin(ang) * 0.3)
		spike.rotation = Vector3(ang, ang, 0)
		add_child(spike)

	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.1, 0.12)
	_glow.omni_range = 4.0
	_glow.light_energy = 1.2
	_glow.position = Vector3(0, 0.6, 0)
	add_child(_glow)

	_build_bar()

## A floating DELETION bar so you can see it whittle down as you burn it.
func _build_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0, 1.45, 0)
	add_child(_bar_root)
	var bg := _bar_quad(1.0, 0.14, Color(0.04, 0.0, 0.0))
	_bar_root.add_child(bg)
	_bar_fill = _bar_quad(0.94, 0.09, Color(1.0, 0.15, 0.15))
	_bar_fill.position = Vector3(0, 0, 0.01)
	_bar_root.add_child(_bar_fill)
	var lbl := Label3D.new()
	lbl.text = "DELETION"
	lbl.font_size = 40
	lbl.pixel_size = 0.0035
	lbl.position = Vector3(0, 0.18, 0)
	lbl.modulate = Color(1.0, 0.35, 0.35)
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	_bar_root.add_child(lbl)

func _bar_quad(w: float, h: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.2
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED   # always faces the camera
	mi.material_override = m
	return mi

func _build_synchronizer() -> void:
	var sync := MultiplayerSynchronizer.new()
	var cfg := SceneReplicationConfig.new()
	for prop in [".:position", ".:rotation", ".:health", ".:_dead"]:
		cfg.add_property(NodePath(prop))
		cfg.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	add_child(sync)   # inherits authority 1 from this node

func _process(delta: float) -> void:
	_t += delta
	if _dead:
		_death_t += delta
		var s := clampf(1.0 - _death_t * 3.0, 0.0, 1.0)
		_core.scale = Vector3.ONE * s
		_glow.light_energy = maxf(0.0, 3.0 * (1.0 - _death_t * 2.0))
		if _bar_root:
			_bar_root.visible = false
		return
	_core.scale = Vector3.ONE * (1.0 + sin(_t * 12.0) * 0.12)
	_glow.light_energy = 1.0 + sin(_t * 10.0) * 0.4
	if _bar_fill:
		var frac := clampf(health / max_health, 0.0, 1.0)
		_bar_fill.scale.x = maxf(0.001, frac)
		# fade from red toward white as it nears deletion, for feedback
		_bar_fill.material_override.emission = Color(1.0, 0.15, 0.15).lerp(Color(1.0, 0.9, 0.9), 1.0 - frac)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or _dead:
		if _dead:
			velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var target := _nearest_player()
	if target == null:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		move_and_slide()
		return

	var to: Vector3 = target.global_position - global_position
	var dist := to.length()
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() > 0.01:
		flat = flat.normalized()
	# jitter so they read as unstable, twitching things
	var side := Vector3(-flat.z, 0, flat.x)
	var move := (flat + side * sin(_t * 9.0 + float(get_instance_id() % 100)) * 0.5).normalized()
	velocity.x = move.x * SPEED
	velocity.z = move.z * SPEED
	move_and_slide()

	_attack_timer -= delta
	if dist <= 1.4 and _attack_timer <= 0.0:
		_attack_timer = CD
		if target.has_method("hit"):
			target.hit(DMG, "PARASITE")
		if Sound:
			Sound.hit()

func damage(amount: float) -> void:
	if _dead or not is_multiplayer_authority():
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector3.ZERO
	killed.emit()
	if Sound:
		Sound.purge()
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(self):
		queue_free()

func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("downed") == true:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
