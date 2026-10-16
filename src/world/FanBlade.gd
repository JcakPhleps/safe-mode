extends Node3D
## SAFE MODE — a spinning system-fan hub for the FAN room. Purely decorative.

@export var tint: Color = Color(0.6, 0.8, 0.9)

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.09, 0.11)
	mat.metallic = 0.5
	mat.emission_enabled = true
	mat.emission = tint * 0.4
	mat.emission_energy_multiplier = 0.6
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.5
	hm.bottom_radius = 0.5
	hm.height = 0.4
	hub.mesh = hm
	hub.material_override = mat
	add_child(hub)
	for i in 7:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 0.08, 0.7)
		blade.mesh = bm
		blade.material_override = mat
		var ang := TAU * float(i) / 7.0
		blade.position = Vector3(cos(ang) * 1.5, 0, sin(ang) * 1.5)
		blade.rotation = Vector3(0, -ang, 0.35)
		add_child(blade)

func _process(delta: float) -> void:
	rotation.y += delta * 3.0
