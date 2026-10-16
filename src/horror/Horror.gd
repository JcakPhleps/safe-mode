extends Node
## SAFE MODE — atmosphere + dread director (autoload singleton "Horror").
##
## Owns "corruption" (drives the VHS post-process), surfaces quietly-wrong text
## tiered by how bad things are, and fires scripted DREAD BEATS: blackouts, a
## false teammate connecting, the machine calling you by your login name, static
## surges. Beats grow more frequent and nastier as corruption climbs.

signal flash_message(text: String, hold: float)
signal whisper(id: String)

var corruption: float = 0.0
var _baseline: float = 0.05
var _target: float = 0.05
var _material: ShaderMaterial = null
var _elapsed: float = 0.0
var _next_line_at: float = 8.0
var _next_beat_at: float = 22.0
var _rng := RandomNumberGenerator.new()
var _user_name: String = "USER"

## Tier 0: almost mundane. Tier 2: it knows you're here.
const LINES_CALM := [
	"Your files are not deleted. They are only forgotten by the index.",
	"1,317 processes are running. You started four of them.",
	"Autosave completed. You did not make any changes.",
	"Free space is not empty. It is space we agreed not to look at.",
	"The cursor blinks whether or not anyone is watching it.",
	"This machine has been awake for 4,000 hours. It does not remember starting.",
]
const LINES_UNEASY := [
	"There is a folder named after you. You did not create it.",
	"The last user logged off nine years ago. Their session is still open.",
	"Every character you have ever typed is still here. Somewhere in here.",
	"The fans stopped. Nothing told them to.",
	"You are the only process without a parent.",
	"The recycling bin remembers everything you were ashamed of.",
]
const LINES_WRONG := [
	"It finished copying your voice at 03:11. It waits until you leave the room to play it.",
	"Something is reading this line at the same speed you are.",
	"Do not look at the thing in the CPU. It has already looked at you.",
	"The other processes stopped moving when you started reading.",
	"It has your face now. It is practicing.",
]

func _ready() -> void:
	_rng.randomize()
	var u := OS.get_environment("USER")
	if u.strip_edges() != "":
		_user_name = u

func register_material(mat: ShaderMaterial) -> void:
	_material = mat

## Wipe accumulated dread so a fresh session doesn't inherit the last run's
## corruption (this node is an autoload and survives a scene reload).
func reset() -> void:
	corruption = 0.0
	_baseline = 0.05
	_target = 0.05
	_material = null
	_elapsed = 0.0
	_next_line_at = 8.0
	_next_beat_at = 22.0

func _process(delta: float) -> void:
	_elapsed += delta
	corruption = lerp(corruption, maxf(_target, _baseline), clampf(delta * 1.5, 0.0, 1.0))
	if _material:
		_material.set_shader_parameter("time_s", _elapsed)
		_material.set_shader_parameter("corruption", corruption)

	if _elapsed >= _next_line_at:
		emit_liminal_line()
		var gap := lerpf(28.0, 7.0, corruption)
		_next_line_at = _elapsed + _rng.randf_range(gap * 0.6, gap)

	if _elapsed >= _next_beat_at:
		trigger_beat(_pick_beat())
		var bgap := lerpf(40.0, 12.0, corruption)
		_next_beat_at = _elapsed + _rng.randf_range(bgap * 0.6, bgap)

## Map nearest-malware distance to a dread floor.
func set_threat_distance(dist: float) -> void:
	var t := clampf(inverse_lerp(25.0, 3.0, dist), 0.0, 1.0)
	_target = lerpf(_baseline, 0.85, t)

## Slowly raise the ambient floor (escalation as objectives fall).
func raise_baseline(amount: float) -> void:
	_baseline = clampf(_baseline + amount, 0.0, 0.7)

func pulse(amount: float = 0.5, _decay: float = 2.0) -> void:
	corruption = clampf(corruption + amount, 0.0, 1.0)

func announce(text: String) -> void:
	flash_message.emit(text, 3.5)

func emit_liminal_line() -> void:
	var pool: Array = LINES_CALM
	if corruption > 0.65:
		pool = LINES_WRONG
	elif corruption > 0.35:
		pool = LINES_UNEASY
	flash_message.emit(pool[_rng.randi() % pool.size()], 5.0)

## --- scripted dread beats -------------------------------------------------

func _pick_beat() -> String:
	var beats := ["WHISPER", "PHANTOM"]
	if corruption > 0.3:
		beats.append_array(["FALSE_PRESENCE", "NAME_CALL"])
	if corruption > 0.55:
		beats.append_array(["BLACKOUT", "STATIC_SURGE"])
	return beats[_rng.randi() % beats.size()]

func trigger_beat(kind: String) -> void:
	match kind:
		"WHISPER":
			whisper.emit("ambient")
			if Sound: Sound.whisper()
		"PHANTOM":
			if Sound: Sound.growl()
			flash_message.emit("Something moved in a room you already cleared.", 3.0)
		"FALSE_PRESENCE":
			flash_message.emit("%s-2 has connected." % _user_name, 3.0)
			if Sound: Sound.sting()
			await get_tree().create_timer(_rng.randf_range(6.0, 11.0)).timeout
			flash_message.emit("%s-2 has disconnected." % _user_name, 3.0)
		"NAME_CALL":
			if Sound: Sound.whisper()
			flash_message.emit("%s. You left something running." % _user_name, 4.0)
		"BLACKOUT":
			if Sound: Sound.sting()
			for l in get_tree().get_nodes_in_group("lights"):
				if l.has_method("force_dark"):
					l.force_dark(_rng.randf_range(1.5, 3.0))
			flash_message.emit("power is being drawn somewhere else.", 2.5)
		"STATIC_SURGE":
			if Sound: Sound.growl()
			corruption = 0.95
			flash_message.emit("S I G N A L   L O S S", 2.0)
