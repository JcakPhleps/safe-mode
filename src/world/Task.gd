extends StaticBody3D
## SAFE MODE — a repair/recovery task bolted to a component. Hold your laser on
## its console until the bar fills to recover that component. Recovering all of
## them arms the laser so it can delete the malware.
##
## Completion is host-authoritative in co-op: the local beam fills the bar, and
## the instant it's full the task *requests* completion; Main confirms it and
## calls complete_visual() on every peer. No class_name (duck-typed by Main).

signal completed(id: String)

@export var id: String = ""
@export var label: String = ""
@export var tint: Color = Color(0.3, 0.9, 1.0)

const LAYER_TASK := 4        # 1<<2 — the scan ray includes this bit
const RATE := 0.30           # progress/sec while the beam is on it
const DECAY := 0.10          # progress lost/sec when the beam is off it

var progress: float = 0.0
var done: bool = false
var _emitted: bool = false
var _scanned_this_frame: bool = false
var _t: float = 0.0
var _bar: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _panel_mat: StandardMaterial3D
var _light: OmniLight3D

func _ready() -> void:
	add_to_group("task")
	collision_layer = LAYER_TASK
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.2, 0.6)
	cs.shape = box
	cs.position = Vector3(0, 1.1, 0)
	add_child(cs)
	_build()

func _build() -> void:
	# a stand
	var stand := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.5, 1.0, 0.5)
	stand.mesh = sm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.05, 0.06)
	dark.metallic = 0.4
	stand.material_override = dark
	stand.position = Vector3(0, 0.5, 0)
	add_child(stand)

	# a tilted console panel
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.5, 1.0, 0.12)
	panel.mesh = pm
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.albedo_color = tint * 0.2
	_panel_mat.emission_enabled = true
	_panel_mat.emission = tint * 0.5
	_panel_mat.emission_energy_multiplier = 1.2
	panel.material_override = _panel_mat
	panel.position = Vector3(0, 1.25, 0)
	panel.rotation_degrees = Vector3(-18, 0, 0)
	add_child(panel)

	# progress bar that fills across the panel
	var track := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.2, 0.14, 0.04)
	track.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.02, 0.02, 0.02)
	track.material_override = tmat
	track.position = Vector3(0, 0, 0.07)
	panel.add_child(track)

	_bar = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.14, 0.05)
	_bar.mesh = bm
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.albedo_color = tint
	_bar_mat.emission_enabled = true
	_bar_mat.emission = tint
	_bar_mat.emission_energy_multiplier = 2.5
	_bar.material_override = _bar_mat
	_bar.position = Vector3(0, 0, 0.02)
	_bar.scale.x = 0.001
	track.add_child(_bar)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.omni_range = 4.5
	_light.light_energy = 1.0
	_light.position = Vector3(0, 1.4, 0.3)
	add_child(_light)

	var lbl := Label3D.new()
	lbl.text = label + "\n[ hold laser to recover ]"
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.position = Vector3(0, 2.0, 0)
	lbl.modulate = tint
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

func _process(delta: float) -> void:
	if done:
		return
	_t += delta
	if not _scanned_this_frame:
		progress = maxf(0.0, progress - DECAY * delta)
	_scanned_this_frame = false
	_bar.scale.x = maxf(0.001, progress)
	_bar.position.x = -0.6 * (1.0 - progress)   # keep it left-anchored
	_light.light_energy = 0.8 + progress * 1.6 + sin(_t * 4.0) * 0.15

## Called each frame the laser is on this console.
func apply_scan(delta: float) -> void:
	if done:
		return
	_scanned_this_frame = true
	progress = minf(1.0, progress + RATE * delta)
	_bar_mat.emission = tint * 3.0
	if progress >= 1.0 and not _emitted:
		_emitted = true      # request once; Main confirms authoritatively
		completed.emit(id)

func complete_visual() -> void:
	done = true
	progress = 1.0
	_bar.scale.x = 1.0
	_bar.position.x = 0.0
	_bar_mat.albedo_color = Color(0.2, 1.0, 0.4)
	_bar_mat.emission = Color(0.2, 1.0, 0.4)
	_panel_mat.emission = Color(0.1, 0.8, 0.3)
	_light.light_color = Color(0.2, 1.0, 0.4)
	if Sound:
		Sound.unlock()
