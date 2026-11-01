class_name IslandSwitch
extends Node3D

## A glowing ancient switch: an emissive lamp on a stone plinth that the player
## activates with the interact key when they are close enough.
##
## It explains itself the first time the player comes near, then turns from violet
## to green and tells the island its puzzle is solved.

signal activated

@export var solved_name := "ancient_switch"
@export var use_range := 2.6
@export var tutorial_range := 7.0
@export var tutorial := "A glowing switch. Walk up to it and press E to activate it."
@export var success := "The ancient switch hums - a stone gate grinds open to the north!"
@export var done := false

var island: ForgottenIsland = null

var _lamp: MeshInstance3D
var _lamp_material: StandardMaterial3D
var _ring: MeshInstance3D
var _hinted := false
var _time := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#6b6579")
	stone.roughness = 0.9
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.62
	base_mesh.bottom_radius = 0.78
	base_mesh.height = 0.55
	base_mesh.radial_segments = 18
	base.mesh = base_mesh
	base.material_override = stone
	base.position.y = 0.27
	add_child(base)

	var column := MeshInstance3D.new()
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.3
	column_mesh.bottom_radius = 0.4
	column_mesh.height = 0.9
	column_mesh.radial_segments = 16
	column.mesh = column_mesh
	column.material_override = stone
	column.position.y = 0.85
	add_child(column)

	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = Color("#b06bff")
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color("#b06bff")
	_lamp_material.emission_energy_multiplier = 1.5
	_lamp = MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.34
	lamp_mesh.height = 0.68
	lamp_mesh.radial_segments = 18
	lamp_mesh.rings = 10
	_lamp.mesh = lamp_mesh
	_lamp.material_override = _lamp_material
	_lamp.position.y = 1.62
	_lamp.scale = Vector3(1.0, 1.25, 1.0)
	add_child(_lamp)

	_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.44
	ring_mesh.outer_radius = 0.52
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 10
	_ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("#8a5cff")
	ring_material.emission_enabled = true
	ring_material.emission = Color("#8a5cff")
	ring_material.emission_energy_multiplier = 0.8
	_ring.material_override = ring_material
	_ring.position.y = 1.62
	add_child(_ring)


func _process(delta: float) -> void:
	_time += delta
	if _lamp != null:
		_lamp.position.y = 1.62 + sin(_time * 1.6) * 0.06
	if _ring != null:
		_ring.rotate_y(delta * (1.6 if done else 0.7))
	if not _hinted:
		var near := _nearest_player(tutorial_range)
		if near != null:
			_hinted = true
			_report(tutorial)


## Interact key handling, the same way the levels' levers work.
func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if _nearest_player(use_range) != null:
				activate()
				get_viewport().set_input_as_handled()
			return


func activate() -> void:
	if done:
		return
	done = true
	if _lamp_material != null:
		_lamp_material.albedo_color = Color("#65f6ad")
		_lamp_material.emission = Color("#25ff95")
		_lamp_material.emission_energy_multiplier = 2.2
	Audio.play("res://sounds/coin.ogg")
	activated.emit()
	if island != null:
		island.solve_puzzle(solved_name, success)
	else:
		_report(success)


func _report(text: String) -> void:
	if island != null:
		island.message.emit(text)


func _nearest_player(range_limit: float) -> Node3D:
	var best: Node3D = null
	var best_distance := range_limit
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or bool(candidate.get("is_dead")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best