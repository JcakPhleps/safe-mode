extends OmniLight3D
## A sick, unreliable light. Mostly steady, then it isn't. The gaps are the point.

var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _base_energy: float = 1.1
var _next_glitch: float = 0.0
var _dark_for: float = 0.0

func _ready() -> void:
	add_to_group("lights")
	_rng.randomize()
	light_color = Color(0.55, 1.0, 0.7)
	omni_range = 14.0
	_base_energy = _rng.randf_range(0.9, 1.3)
	light_energy = _base_energy
	shadow_enabled = true
	_next_glitch = _rng.randf_range(2.0, 7.0)

func _process(delta: float) -> void:
	_t += delta
	# forced blackout (dread beat) overrides everything
	if _dark_for > 0.0:
		_dark_for -= delta
		light_energy = 0.0
		return
	# gentle mains hum flicker
	var hum := 1.0 + sin(_t * 40.0) * 0.02
	light_energy = _base_energy * hum
	# occasional dropout
	_next_glitch -= delta
	if _next_glitch <= 0.0:
		light_energy = _rng.randf_range(0.0, 0.3)
		_next_glitch = _rng.randf_range(1.5, 8.0)

## Called by the Horror director's BLACKOUT beat.
func force_dark(duration: float) -> void:
	_dark_for = maxf(_dark_for, duration)
