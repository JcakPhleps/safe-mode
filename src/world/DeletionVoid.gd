extends Area3D
## SAFE MODE — the empty space where a deleted room used to be. Any process still
## inside a sector when it is erased is deleted with it (the "File Deletion"
## ending). Kills only the local, authoritative player so death routes correctly
## in co-op; each peer's own void handles its own player.

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_try_kill)

func _physics_process(_delta: float) -> void:
	# catch anyone already standing here the instant the room is erased
	for b in get_overlapping_bodies():
		_try_kill(b)

func _try_kill(b: Node) -> void:
	if not b.is_in_group("players"):
		return
	if not b.is_multiplayer_authority():
		return
	if b.get("downed") == true:
		return
	if b.has_method("kill"):
		b.kill("DELETION")
