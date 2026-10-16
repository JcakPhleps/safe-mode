extends RefCounted
## SAFE MODE — builds the interior of the machine from code (no external assets).
##
## 11 rooms on a wide grid, wired by an adjacency list so straight corridors line
## up. Each room is a distinct component and is DECORATED to look like the inside
## of that part — the motherboard room is a PCB with capacitors, a socket, RAM
## slots and the USB port header you escape through; the CPU room is a heatsink
## and pin grid; and so on. Every room's geometry lives under its own container
## Node3D so the deletion phase can erase a whole room at once.
## N = -Z, S = +Z, E = +X, W = -X. Units are meters.
##
## No class_name — Main preloads this and calls build() (headless-boot rule).

const ROOM_H := 5.5
const HALF := 7.0
const DOOR := 4.0
const WALL_T := 0.4
const PITCH := 34.0   # wide spacing → long data-bus corridors between rooms

# grid = (col, row); col -> +X, row -> +Z.  comp = "" means no recovery task here.
const ROOMS := {
	"BOOT":  {"grid": Vector2i(0, 0),   "comp": "",             "tint": Color(0.4, 1.0, 0.6)},
	"CPU":   {"grid": Vector2i(1, 0),   "comp": "CPU",          "tint": Color(1.0, 0.55, 0.15)},
	"MOBO":  {"grid": Vector2i(-1, 0),  "comp": "MOTHERBOARD",  "tint": Color(0.3, 1.0, 0.5)},
	"GPU":   {"grid": Vector2i(0, -1),  "comp": "GPU",          "tint": Color(0.35, 0.7, 1.0)},
	"PSU":   {"grid": Vector2i(0, 1),   "comp": "POWER SUPPLY", "tint": Color(1.0, 0.8, 0.2)},
	"RAM_A": {"grid": Vector2i(1, -1),  "comp": "RAM MODULE A", "tint": Color(0.7, 0.5, 1.0)},
	"RAM_B": {"grid": Vector2i(-1, -1), "comp": "RAM MODULE B", "tint": Color(0.75, 0.45, 1.0)},
	"SSD":   {"grid": Vector2i(1, 1),   "comp": "SSD",          "tint": Color(0.3, 0.95, 0.9)},
	"NIC":   {"grid": Vector2i(2, 0),   "comp": "",             "tint": Color(0.4, 0.9, 0.6)},
	"FAN":   {"grid": Vector2i(-2, 0),  "comp": "",             "tint": Color(0.6, 0.8, 0.9)},
	"CACHE": {"grid": Vector2i(-1, 1),  "comp": "",             "tint": Color(0.4, 0.7, 1.0)},
}

const LINKS := [
	["BOOT", "CPU"], ["BOOT", "MOBO"], ["BOOT", "GPU"], ["BOOT", "PSU"],
	["CPU", "RAM_A"], ["CPU", "SSD"], ["CPU", "NIC"],
	["MOBO", "RAM_B"], ["MOBO", "CACHE"], ["MOBO", "FAN"],
	["GPU", "RAM_A"], ["GPU", "RAM_B"],
	["PSU", "SSD"], ["PSU", "CACHE"],
]

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_trace: StandardMaterial3D

func _center(name: String) -> Vector3:
	var g: Vector2i = ROOMS[name].grid
	return Vector3(g.x * PITCH, 0, g.y * PITCH)

func build(parent: Node3D) -> Dictionary:
	_make_materials()
	_add_environment(parent)

	var open := {}
	for name in ROOMS:
		open[name] = []
	for link in LINKS:
		var d: Vector2i = ROOMS[link[1]].grid - ROOMS[link[0]].grid
		open[link[0]].append(_side_for(d))
		open[link[1]].append(_side_for(-d))

	var containers := {}
	var centers := {}
	for name in ROOMS:
		var c := _center(name)
		var room := Node3D.new()
		room.name = "room_" + name
		parent.add_child(room)
		_build_shell(room, c, open[name])
		_decorate(room, name, c)
		containers[name] = room
		centers[name] = c

	for link in LINKS:
		var d: Vector2i = ROOMS[link[1]].grid - ROOMS[link[0]].grid
		var dir := Vector3(d.x, 0, d.y)
		_build_corridor(parent, _center(link[0]) + dir * HALF, _center(link[1]) - dir * HALF)

	var tasks := _place_tasks(containers)
	var usb := _build_usb(parent, _center("MOBO"))

	var malware_spawns := []
	for name in ROOMS:
		if name != "BOOT":
			malware_spawns.append(_center(name) + Vector3(0, 1.4, 0))

	var bc := _center("BOOT")
	var spawns := [
		bc + Vector3(-2.5, 1, -2.5), bc + Vector3(2.5, 1, -2.5),
		bc + Vector3(-2.5, 1, 2.5), bc + Vector3(2.5, 1, 2.5), bc + Vector3(0, 1, 0),
	]

	return {
		"spawns": spawns,
		"room_names": ROOMS.keys(),
		"room_centers": centers,
		"room_containers": containers,
		"room_half": HALF,
		"room_height": ROOM_H,
		"tasks": tasks.nodes,
		"task_ids": tasks.ids,
		"malware_spawns": malware_spawns,
		"usb": usb,
		"usb_room": "MOBO",
	}

func _side_for(d: Vector2i) -> String:
	if d == Vector2i(1, 0): return "E"
	if d == Vector2i(-1, 0): return "W"
	if d == Vector2i(0, 1): return "S"
	return "N"

## --- environment ----------------------------------------------------------

func _add_environment(parent: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.14, 0.12)
	env.ambient_light_energy = 0.22
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.06)
	env.fog_density = 0.05
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	we.name = "WorldEnvironment"
	parent.add_child(we)

func _make_materials() -> void:
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.06, 0.07, 0.07)
	_mat_floor.roughness = 0.9
	_mat_floor.metallic = 0.2

	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.03, 0.09, 0.05)
	_mat_wall.roughness = 0.85

	_mat_trace = StandardMaterial3D.new()
	_mat_trace.albedo_color = Color(0.1, 0.5, 0.25)
	_mat_trace.emission_enabled = true
	_mat_trace.emission = Color(0.2, 0.9, 0.45)
	_mat_trace.emission_energy_multiplier = 1.5

func _emat(color: Color, emit: float = 0.0, metallic: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.metallic = metallic
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m

## --- geometry helpers -----------------------------------------------------

func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = center
		parent.add_child(body)
	return mi

func _cyl(parent: Node3D, center: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi

func _accent(parent: Node3D, pos: Vector3, color: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	parent.add_child(l)

func _build_shell(room: Node3D, c: Vector3, open: Array) -> void:
	_box(room, c + Vector3(0, -0.1, 0), Vector3(HALF * 2, 0.2, HALF * 2), _mat_floor)
	_box(room, c + Vector3(0, ROOM_H, 0), Vector3(HALF * 2, 0.2, HALF * 2), _mat_wall)
	_box(room, c + Vector3(0, 0.02, 0), Vector3(HALF * 2 - 1.0, 0.03, 0.15), _mat_trace, false)
	_box(room, c + Vector3(0, 0.02, 0), Vector3(0.15, 0.03, HALF * 2 - 1.0), _mat_trace, false)
	for side in ["N", "S", "E", "W"]:
		_build_wall(room, c, side, open.has(side))
	var lamp := preload("res://src/world/FlickerLight.gd").new()
	lamp.position = c + Vector3(0, ROOM_H - 0.6, 0)
	room.add_child(lamp)

func _build_wall(parent: Node3D, c: Vector3, side: String, has_door: bool) -> void:
	var along_x := side == "N" or side == "S"
	var sign_z := -1.0 if side == "N" else 1.0
	var sign_x := 1.0 if side == "E" else -1.0
	var wall_center: Vector3
	var wall_size: Vector3
	if along_x:
		wall_center = c + Vector3(0, ROOM_H * 0.5, sign_z * HALF)
		wall_size = Vector3(HALF * 2, ROOM_H, WALL_T)
	else:
		wall_center = c + Vector3(sign_x * HALF, ROOM_H * 0.5, 0)
		wall_size = Vector3(WALL_T, ROOM_H, HALF * 2)

	if not has_door:
		_box(parent, wall_center, wall_size, _mat_wall)
		return

	var seg := (HALF * 2 - DOOR) * 0.5
	if along_x:
		var off := (DOOR * 0.5) + seg * 0.5
		_box(parent, wall_center + Vector3(-off, 0, 0), Vector3(seg, ROOM_H, WALL_T), _mat_wall)
		_box(parent, wall_center + Vector3(off, 0, 0), Vector3(seg, ROOM_H, WALL_T), _mat_wall)
	else:
		var off2 := (DOOR * 0.5) + seg * 0.5
		_box(parent, wall_center + Vector3(0, 0, -off2), Vector3(WALL_T, ROOM_H, seg), _mat_wall)
		_box(parent, wall_center + Vector3(0, 0, off2), Vector3(WALL_T, ROOM_H, seg), _mat_wall)

func _build_corridor(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var run := b - a
	var horizontal := absf(run.x) > absf(run.z)
	var length := run.length() + 0.2
	if horizontal:
		_box(parent, mid + Vector3(0, -0.1, 0), Vector3(length, 0.2, DOOR), _mat_floor)
		_box(parent, mid + Vector3(0, ROOM_H, 0), Vector3(length, 0.2, DOOR), _mat_wall)
		_box(parent, mid + Vector3(0, ROOM_H * 0.5, -DOOR * 0.5), Vector3(length, ROOM_H, WALL_T), _mat_wall)
		_box(parent, mid + Vector3(0, ROOM_H * 0.5, DOOR * 0.5), Vector3(length, ROOM_H, WALL_T), _mat_wall)
	else:
		_box(parent, mid + Vector3(0, -0.1, 0), Vector3(DOOR, 0.2, length), _mat_floor)
		_box(parent, mid + Vector3(0, ROOM_H, 0), Vector3(DOOR, 0.2, length), _mat_wall)
		_box(parent, mid + Vector3(-DOOR * 0.5, ROOM_H * 0.5, 0), Vector3(WALL_T, ROOM_H, length), _mat_wall)
		_box(parent, mid + Vector3(DOOR * 0.5, ROOM_H * 0.5, 0), Vector3(WALL_T, ROOM_H, length), _mat_wall)

## --- per-room theming -----------------------------------------------------

func _decorate(room: Node3D, name: String, c: Vector3) -> void:
	var tint: Color = ROOMS[name].tint
	match name:
		"BOOT": _theme_boot(room, c, tint)
		"CPU": _theme_cpu(room, c, tint)
		"MOBO": _theme_mobo(room, c, tint)
		"GPU": _theme_gpu(room, c, tint)
		"PSU": _theme_psu(room, c, tint)
		"RAM_A", "RAM_B": _theme_ram(room, c, tint)
		"SSD": _theme_ssd(room, c, tint)
		"NIC": _theme_nic(room, c, tint)
		"FAN": _theme_fan(room, c, tint)
		"CACHE": _theme_cache(room, c, tint)

func _theme_boot(room: Node3D, c: Vector3, tint: Color) -> void:
	# a bare boot sector: a central POST monolith and four corner pylons
	_box(room, c + Vector3(0, 1.0, 0), Vector3(1.4, 2.0, 1.4), _emat(Color(0.03, 0.06, 0.04), 0.0, 0.5))
	_box(room, c + Vector3(0, 2.1, 0), Vector3(1.5, 0.2, 1.5), _emat(tint, 2.0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(room, c + Vector3(sx * (HALF - 1.5), 1.2, sz * (HALF - 1.5)), Vector3(0.6, 2.4, 0.6), _emat(Color(0.04, 0.08, 0.05), 0.0, 0.6))
	_accent(room, c + Vector3(0, 2.5, 0), tint, 1.2, 8.0)

func _theme_cpu(room: Node3D, c: Vector3, tint: Color) -> void:
	# a socket platform with a pin grid and a tall finned heatsink over it
	_box(room, c + Vector3(0, 0.15, 0), Vector3(4.5, 0.3, 4.5), _emat(Color(0.05, 0.05, 0.06), 0.0, 0.6))
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			_box(room, c + Vector3(ix * 0.7, 0.35, iz * 0.7), Vector3(0.12, 0.2, 0.12), _emat(Color(0.8, 0.7, 0.2), 0.6, 0.8), false)
	# heatsink fins
	for i in 9:
		_box(room, c + Vector3(0, 1.6, -1.6 + i * 0.4), Vector3(3.0, 2.4, 0.12), _emat(Color(0.15, 0.15, 0.17), 0.0, 0.8), false)
	_box(room, c + Vector3(0, 0.7, 0), Vector3(3.2, 0.5, 3.2), _emat(tint * 0.5, 0.4))
	_accent(room, c + Vector3(0, 1.0, 0), tint, 1.6, 9.0)

func _theme_mobo(room: Node3D, c: Vector3, tint: Color) -> void:
	# the PCB: capacitors, a CPU socket outline, RAM slot rails, chips, traces —
	# and the USB port header (built separately) that you escape through.
	for i in 6:
		var ang := TAU * float(i) / 6.0
		_cyl(room, c + Vector3(cos(ang) * 3.5, 0.6, sin(ang) * 3.5), 0.3, 1.2, _emat(Color(0.1, 0.1, 0.12), 0.0, 0.7))
		_box(room, c + Vector3(cos(ang) * 3.5, 1.22, sin(ang) * 3.5), Vector3(0.62, 0.06, 0.62), _emat(Color(0.6, 0.5, 0.1), 0.3), false)
	# CPU socket outline
	for s in [-1, 1]:
		_box(room, c + Vector3(s * 1.3, 0.25, 0), Vector3(0.15, 0.4, 2.6), _emat(tint, 0.8), false)
		_box(room, c + Vector3(0, 0.25, s * 1.3), Vector3(2.6, 0.4, 0.15), _emat(tint, 0.8), false)
	# RAM slot rails
	for i in 3:
		_box(room, c + Vector3(-4.5 + i * 0.35, 0.3, -3.5), Vector3(0.12, 0.5, 3.0), _emat(Color(0.2, 0.15, 0.05), 0.2), false)
	# chip packages
	_box(room, c + Vector3(3.5, 0.3, -3.0), Vector3(1.2, 0.4, 1.2), _emat(Color(0.05, 0.05, 0.06), 0.0, 0.6), false)
	_box(room, c + Vector3(-3.5, 0.3, 3.2), Vector3(0.9, 0.35, 0.9), _emat(Color(0.05, 0.05, 0.06), 0.0, 0.6), false)
	# extra floor traces for a busy PCB look
	for i in 5:
		_box(room, c + Vector3(-HALF + 1 + i * 1.2, 0.03, 0), Vector3(0.08, 0.03, HALF * 1.6), _mat_trace, false)
	_accent(room, c + Vector3(0, 2.0, 0), tint, 1.4, 10.0)

func _theme_gpu(room: Node3D, c: Vector3, tint: Color) -> void:
	# a long graphics card slab with two big fans and a row of VRAM chips
	_box(room, c + Vector3(0, 0.8, 0), Vector3(6.0, 0.4, 2.4), _emat(Color(0.04, 0.05, 0.07), 0.0, 0.7))
	for sx in [-1.6, 1.6]:
		_cyl(room, c + Vector3(sx, 1.05, 0), 1.1, 0.2, _emat(Color(0.06, 0.07, 0.09), 0.0, 0.6))
		for b in 6:
			var ang := TAU * float(b) / 6.0
			_box(room, c + Vector3(sx + cos(ang) * 0.6, 1.12, sin(ang) * 0.6), Vector3(0.7, 0.04, 0.18), _emat(tint * 0.6, 0.3), false)
	for i in 5:
		_box(room, c + Vector3(-2.0 + i, 0.35, -1.8), Vector3(0.5, 0.3, 0.5), _emat(tint, 0.5), false)
	_accent(room, c + Vector3(0, 1.6, 1.5), tint, 1.6, 9.0)

func _theme_psu(room: Node3D, c: Vector3, tint: Color) -> void:
	# capacitors, a big fan and cable bundles arcing overhead
	for i in 5:
		var ang := TAU * float(i) / 5.0
		_cyl(room, c + Vector3(cos(ang) * 2.0, 0.9, sin(ang) * 2.0), 0.4, 1.8, _emat(Color(0.12, 0.1, 0.06), 0.0, 0.7))
	_cyl(room, c + Vector3(0, 0.2, -HALF + 1.2), 1.6, 0.3, _emat(Color(0.05, 0.05, 0.05), 0.0, 0.6))
	for i in 5:
		_box(room, c + Vector3(-2 + i, 3.2 + sin(i) * 0.3, 2.5), Vector3(0.14, 0.14, 3.0), _emat(Color(0.6, 0.5, 0.1), 0.3), false)
	_accent(room, c + Vector3(0, 1.5, 0), tint, 1.7, 9.0)

func _theme_ram(room: Node3D, c: Vector3, tint: Color) -> void:
	# a bank of tall RAM-stick monoliths with gold contact strips at the base
	for i in 5:
		var x := -4.0 + i * 2.0
		_box(room, c + Vector3(x, 1.8, 0), Vector3(0.5, 3.6, 2.4), _emat(Color(0.06, 0.05, 0.09), 0.0, 0.6))
		_box(room, c + Vector3(x, 0.25, 0), Vector3(0.55, 0.4, 2.5), _emat(Color(0.7, 0.6, 0.15), 0.4), false)
		for chip in 4:
			_box(room, c + Vector3(x + 0.28, 1.2 + chip * 0.7, 0.6), Vector3(0.06, 0.4, 0.5), _emat(tint, 0.6), false)
	_accent(room, c + Vector3(0, 3.0, 0), tint, 1.4, 9.0)

func _theme_ssd(room: Node3D, c: Vector3, tint: Color) -> void:
	# a low board covered in a grid of flat NAND chips plus a controller
	_box(room, c + Vector3(0, 0.2, 0), Vector3(5.0, 0.2, 5.0), _emat(Color(0.04, 0.06, 0.06), 0.0, 0.6))
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			_box(room, c + Vector3(ix * 1.1, 0.4, iz * 1.1), Vector3(0.8, 0.2, 0.8), _emat(Color(0.05, 0.08, 0.08), 0.0, 0.7), false)
	_box(room, c + Vector3(0, 0.5, 0), Vector3(1.0, 0.3, 1.0), _emat(tint, 0.7), false)
	_accent(room, c + Vector3(0, 1.5, 0), tint, 1.4, 8.0)

func _theme_nic(room: Node3D, c: Vector3, tint: Color) -> void:
	# an ethernet jack block on the wall with blinking activity LEDs
	_box(room, c + Vector3(0, 1.5, -HALF + 0.6), Vector3(2.4, 1.6, 0.6), _emat(Color(0.05, 0.06, 0.06), 0.0, 0.6))
	for i in 4:
		_box(room, c + Vector3(-0.9 + i * 0.6, 1.5, -HALF + 0.95), Vector3(0.4, 0.5, 0.2), _emat(Color(0.02, 0.02, 0.02), 0.0, 0.3), false)
		var led := preload("res://src/world/FlickerLight.gd").new()
		led.position = c + Vector3(-0.9 + i * 0.6, 2.1, -HALF + 1.0)
		room.add_child(led)
	_accent(room, c + Vector3(0, 2.5, 0), tint, 1.2, 8.0)

func _theme_fan(room: Node3D, c: Vector3, tint: Color) -> void:
	# a big system fan: a hub with radial blades (a FanBlade script spins it)
	var hub := preload("res://src/world/FanBlade.gd").new()
	hub.position = c + Vector3(0, 2.5, 0)
	hub.tint = tint
	room.add_child(hub)
	_cyl(room, c + Vector3(0, 2.5, 0), 3.0, 0.3, _emat(Color(0.05, 0.06, 0.07), 0.0, 0.5))
	_accent(room, c + Vector3(0, 1.5, 0), tint, 1.3, 9.0)

func _theme_cache(room: Node3D, c: Vector3, tint: Color) -> void:
	# cold shelves of tiny glowing memory cells
	for shelf in 4:
		var y := 0.6 + shelf * 1.1
		_box(room, c + Vector3(0, y - 0.1, -3.0), Vector3(HALF * 1.6, 0.1, 1.2), _emat(Color(0.04, 0.05, 0.07), 0.0, 0.5), false)
		for i in 7:
			_box(room, c + Vector3(-4.5 + i * 1.5, y, -3.0), Vector3(0.4, 0.4, 0.4), _emat(tint, 0.5 + float(shelf) * 0.1), false)
	_accent(room, c + Vector3(0, 2.5, 2.0), tint, 1.4, 9.0)

## --- tasks + USB ----------------------------------------------------------

func _place_tasks(containers: Dictionary) -> Dictionary:
	var TaskScript := preload("res://src/world/Task.gd")
	var nodes := []
	var ids := []
	for name in ROOMS:
		var label: String = ROOMS[name].comp
		if label == "":
			continue
		var t := TaskScript.new()
		t.id = name
		t.label = label
		t.tint = ROOMS[name].tint
		t.position = _center(name) + Vector3(HALF - 2.5, 0, HALF - 2.5)
		containers[name].add_child(t)
		nodes.append(t)
		ids.append(name)
	return {"nodes": nodes, "ids": ids}

## The escape hatch: a USB port header on the motherboard's north wall with a
## stick jacked in. Built on `parent` (not the MOBO container) so it survives
## even if— it never does; MOBO is never deleted, but this keeps it robust.
func _build_usb(parent: Node3D, c: Vector3) -> Area3D:
	var port_z := -HALF + 0.7
	# port header block
	_box(parent, c + Vector3(0, 0.9, port_z), Vector3(2.2, 1.0, 0.7), _emat(Color(0.5, 0.5, 0.55), 0.0, 0.8))
	for s in [-0.55, 0.55]:
		_box(parent, c + Vector3(s, 0.9, port_z + 0.1), Vector3(0.7, 0.5, 0.4), _emat(Color(0.02, 0.02, 0.03), 0.0, 0.4), false)
	# the USB stick jacked into the right port
	_box(parent, c + Vector3(0.55, 0.9, port_z + 0.9), Vector3(0.6, 0.5, 1.2), _emat(Color(0.1, 0.4, 0.9), 1.2))
	_box(parent, c + Vector3(0.55, 0.9, port_z + 1.7), Vector3(0.4, 0.35, 0.5), _emat(Color(0.7, 0.7, 0.7), 0.2), false)

	var lbl := Label3D.new()
	lbl.text = ":/USB  — ESCAPE HATCH"
	lbl.font_size = 42
	lbl.pixel_size = 0.005
	lbl.position = c + Vector3(0.55, 2.0, port_z + 1.2)
	lbl.modulate = Color(0.4, 0.7, 1.0)
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

	var usb := Area3D.new()
	usb.name = "USB"
	usb.monitoring = true
	usb.collision_layer = 0
	usb.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.5, 2.5)
	cs.shape = box
	usb.add_child(cs)
	usb.position = c + Vector3(0.55, 1.2, port_z + 1.3)
	parent.add_child(usb)
	return usb
