class_name IslandCrystal
extends Node3D

## The hidden crystal of the Forgotten Island. It waits where it was hidden -
## inside the cave above the forest path - until a player walks into it, then
## rides above their head until it is placed in the grove's pedestal.

signal picked_up

@export var solved_name := "hidden_crystal"
@export var pick_range := 1.3
@export var ride_height := 1.5

var island: ForgottenIsland = null
var carried := false

var _gem: Node3D
var _carrier: Node3D = null
var _time := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	_gem = Node3D.new()
	_gem.name = "Gem"
	_gem.position.y = 0.7
	add_child(_gem)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#7ce8ff")
	material.emission_enabled = true
	material.emission = Color("#4fd8ff")
	material.emission_energy_multiplier = 1.6
	material.roughness = 0.15

	# A faceted gem: two boxes turned 45 degrees, so it has a waist and points.
	for i in 2:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.34, 0.34, 0.34)
		piece.mesh = box
		piece.material_override = material
		piece.rotation_degrees = Vector3(45.0, 45.0, 0.0)
		piece.position.y = 0.17 * (1.0 if i == 0 else -1.0)
		piece.scale = Vector3(1.0, 1.5, 1.0)
		_gem.add_child(piece)

	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.42
	glow_mesh.height = 0.84
	glow_mesh.radial_segments = 14
	glow_mesh.rings = 8
	glow.mesh = glow_mesh
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = Color(0.5, 0.85, 1.0, 0.22)
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.emission_enabled = true
	glow_material.emission = Color("#4fd8ff")
	glow_material.emission_energy_multiplier = 0.6
	glow.material_override = glow_material
	_gem.add_child(glow)

	# A soft light so it is findable in the dark of the cave without a map.
	var light := OmniLight3D.new()
	light.light_color = Color("#8ce7ff")
	light.light_energy = 1.1
	light.omni_range = 4.5
	_gem.add_child(light)


func _process(delta: float) -> void:
	_time += delta
	if _gem != null:
		_gem.rotate_y(delta * 1.4)
		if not carried:
			_gem.position.y = 0.7 + sin(_time * 1.8) * 0.12
	if carried:
		_follow_carrier()


func _follow_carrier() -> void:
	if _carrier == null or not is_instance_valid(_carrier):
		return
	global_position = _carrier.global_position + Vector3(0.0, ride_height, 0.0)


func _physics_process(_delta: float) -> void:
	if carried:
		return
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or bool(candidate.get("is_dead")):
			continue
		if global_position.distance_to(candidate.global_position) < pick_range:
			pick_up(candidate)
			return


func pick_up(who: Node3D) -> void:
	if carried:
		return
	carried = true
	_carrier = who
	Audio.play("res://sounds/coin.ogg")
	if island != null:
		island.message.emit("You found the hidden crystal! Carry it to the pedestal in the crystal grove.")
	picked_up.emit()