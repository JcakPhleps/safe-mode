extends CanvasLayer
class_name HUD
## SAFE MODE — in-game overlay. Owns the full-screen VHS shader rect (registered
## with the Horror director) plus vitals, objective count, push-to-talk state,
## the liminal flash-message line, and the win/lose card.

var _vhs: ColorRect
var _crosshair: Label
var _health: Label
var _objective: Label
var _timer: Label
var _ptt: Label
var _flash: Label
var _card: Label
var _threat_label: Label
var _threat_bar_bg: ColorRect
var _threat_bar: ColorRect
var _flash_timer: float = 0.0

var player: Node = null
var total_components: int = 0
var collected_count: int = 0
var armed: bool = false
var purging: bool = false
var _malware_frac: float = 1.0
var _time_left: float = 360.0

func _ready() -> void:
	layer = 1
	_build()
	Horror.flash_message.connect(_on_flash)

func _build() -> void:
	# VHS / analog-horror full-screen shader
	_vhs = ColorRect.new()
	_vhs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vhs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/fx/vhs.gdshader")
	_vhs.material = mat
	add_child(_vhs)
	Horror.register_material(mat)

	_crosshair = _mk_label("+", 0.5, 0.5, HORIZONTAL_ALIGNMENT_CENTER)
	_crosshair.add_theme_font_size_override("font_size", 22)

	_health = _mk_label("INTEGRITY 100%", 0.02, 0.94, HORIZONTAL_ALIGNMENT_LEFT)
	_objective = _mk_label("COMPONENTS 0 / 0", 0.02, 0.90, HORIZONTAL_ALIGNMENT_LEFT)
	_ptt = _mk_label("", 0.02, 0.86, HORIZONTAL_ALIGNMENT_LEFT)
	_ptt.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))

	# countdown to self-deletion, top center
	_timer = _mk_label("6:00", 0.5, 0.03, HORIZONTAL_ALIGNMENT_CENTER)
	_timer.add_theme_font_size_override("font_size", 30)
	_timer.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))

	# malware vitals — hidden until the laser can actually hurt it
	_threat_label = _mk_label("MALWARE", 0.5, 0.10, HORIZONTAL_ALIGNMENT_CENTER)
	_threat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.35))
	_threat_label.visible = false
	_threat_bar_bg = ColorRect.new()
	_threat_bar_bg.color = Color(0.15, 0.02, 0.04, 0.7)
	_threat_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_threat_bar_bg.anchor_left = 0.5
	_threat_bar_bg.anchor_right = 0.5
	_threat_bar_bg.offset_left = -180
	_threat_bar_bg.offset_right = 180
	_threat_bar_bg.offset_top = 84
	_threat_bar_bg.offset_bottom = 94
	_threat_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_bar_bg.visible = false
	add_child(_threat_bar_bg)
	_threat_bar = ColorRect.new()
	_threat_bar.color = Color(1.0, 0.15, 0.2)
	_threat_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_threat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_bar_bg.add_child(_threat_bar)

	_flash = _mk_label("", 0.5, 0.2, HORIZONTAL_ALIGNMENT_CENTER)
	_flash.add_theme_font_size_override("font_size", 20)
	_flash.add_theme_color_override("font_color", Color(0.85, 0.95, 0.88))
	_flash.modulate.a = 0.0

	_card = _mk_label("", 0.5, 0.5, HORIZONTAL_ALIGNMENT_CENTER)
	_card.add_theme_font_size_override("font_size", 36)
	_card.visible = false

func _mk_label(text: String, ax: float, ay: float, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_left = ax
	l.anchor_top = ay
	l.anchor_right = ax
	l.anchor_bottom = ay
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _process(delta: float) -> void:
	if is_instance_valid(player):
		_health.text = "INTEGRITY %d%%" % int(maxf(0.0, player.health))
	if purging:
		_objective.text = "ESCAPE TO  :/USB  IN THE MOTHERBOARD"
		_objective.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	elif armed:
		_objective.text = "LASER ARMED — DELETE THE MALWARE"
		_objective.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	else:
		_objective.text = "COMPONENTS  %d / %d RECOVERED" % [collected_count, total_components]
	if armed and not purging:
		_threat_bar.anchor_right = clampf(_malware_frac, 0.0, 1.0)
	_ptt.text = "◉ TRANSMITTING" if (Net.is_networked() and Input.is_action_pressed("push_to_talk")) else ""

	if _flash_timer > 0.0:
		_flash_timer -= delta
		_flash.modulate.a = clampf(_flash_timer, 0.0, 1.0)

func _on_flash(text: String, hold: float) -> void:
	_flash.text = text
	_flash_timer = hold
	_flash.modulate.a = 1.0

func set_components(collected: int, total: int) -> void:
	collected_count = collected
	total_components = total

func set_armed(on: bool) -> void:
	armed = on
	_threat_label.visible = on and not purging
	_threat_bar_bg.visible = on and not purging

func set_malware_health(frac: float) -> void:
	_malware_frac = frac

func set_time(seconds: float) -> void:
	_time_left = seconds
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	_timer.text = "%d:%02d" % [m, s]
	# redden and pulse as the clock runs down
	var urgency := clampf(1.0 - seconds / 360.0, 0.0, 1.0)
	_timer.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5).lerp(Color(1.0, 0.2, 0.2), urgency))

func set_purge() -> void:
	purging = true
	_timer.text = "D E L E T I N G"
	_timer.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	_threat_label.visible = false
	_threat_bar_bg.visible = false

func show_card(text: String, color: Color) -> void:
	_card.text = text
	_card.add_theme_color_override("font_color", color)
	_card.visible = true
