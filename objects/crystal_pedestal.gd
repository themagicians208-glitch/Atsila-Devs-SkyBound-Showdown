class_name CrystalPedestal
extends Node3D

## The grove's ancient pedestal. Carrying the crystal up to it and pressing
## interact sets the crystal in place: the pedestal lights up and the island's
## bridge to the vanishing crossing rises out of the mist.

signal filled

@export var solved_name := "hidden_crystal"
@export var use_range := 2.6
@export var empty_hint := "The pedestal is empty. Something shaped like a sky-blue crystal fits here."
@export var filled_message := "The crystal settles into the pedestal - a bridge rises from the clouds!"

var island: ForgottenIsland = null
var done := false

var _crystal_mesh: Node3D
var _rune: MeshInstance3D
var _base_material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#9a95a6")
	stone.roughness = 0.95
	_base_material = stone
	var stone_dark := StandardMaterial3D.new()
	stone_dark.albedo_color = Color("#6b6579")
	stone_dark.roughness = 0.95

	for radius in [0.62, 0.44]:
		var step := MeshInstance3D.new()
		var step_mesh := CylinderMesh.new()
		step_mesh.top_radius = float(radius)
		step_mesh.bottom_radius = float(radius) + 0.08
		step_mesh.height = 0.25
		step_mesh.radial_segments = 16
		step.mesh = step_mesh
		step.material_override = stone_dark if radius > 0.5 else stone
		step.position.y = 0.12 if radius > 0.5 else 0.36
		add_child(step)

	var bowl := MeshInstance3D.new()
	var bowl_mesh := TorusMesh.new()
	bowl_mesh.inner_radius = 0.3
	bowl_mesh.outer_radius = 0.46
	bowl_mesh.rings = 20
	bowl_mesh.ring_segments = 10
	bowl.mesh = bowl_mesh
	bowl.material_override = stone
	bowl.position.y = 0.85
	add_child(bowl)

	_rune = MeshInstance3D.new()
	var rune_mesh := TorusMesh.new()
	rune_mesh.inner_radius = 0.18
	rune_mesh.outer_radius = 0.24
	rune_mesh.rings = 14
	rune_mesh.ring_segments = 8
	_rune.mesh = rune_mesh
	_rune.material_override = _glow_material(Color("#b06bff"), 1.1)
	_rune.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_rune.position = Vector3(0.0, 0.6, 0.58)
	add_child(_rune)

	# The crystal the pedestal expects, hidden until it is actually placed.
	_crystal_mesh = Node3D.new()
	_crystal_mesh.name = "PlacedCrystal"
	_crystal_mesh.position.y = 1.05
	_crystal_mesh.visible = false
	add_child(_crystal_mesh)
	var gem_material := _glow_material(Color("#7ce8ff"), 1.8)
	for i in 2:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.34, 0.34, 0.34)
		piece.mesh = box
		piece.material_override = gem_material
		piece.rotation_degrees = Vector3(45.0, 45.0, 0.0)
		piece.position.y = 0.17 * (1.0 if i == 0 else -1.0)
		piece.scale = Vector3(1.0, 1.5, 1.0)
		_crystal_mesh.add_child(piece)


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.2
	return material


func _process(delta: float) -> void:
	if _rune != null:
		_rune.rotation.z += delta * (1.4 if done else 0.5)
	if done and _crystal_mesh != null:
		_crystal_mesh.rotate_y(delta * 1.2)
		_time += delta
		_crystal_mesh.position.y = 1.05 + sin(_time * 1.6) * 0.08


func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if _nearest_player() != null:
				_try_place()
				get_viewport().set_input_as_handled()
			return


func _try_place() -> void:
	if island == null:
		return
	var crystal := island.find_crystal()
	if crystal == null or not crystal.carried:
		if island != null:
			island.message.emit(empty_hint)
		return
	crystal.queue_free()
	fill()


## Place the crystal without needing someone to carry it. The island uses this
## when a test asks for every puzzle to be solved.
func fill() -> void:
	if done:
		return
	done = true
	if _crystal_mesh != null:
		_crystal_mesh.visible = true
	if _base_material != null:
		_base_material.emission_enabled = true
		_base_material.emission = Color("#8ce7ff")
		_base_material.emission_energy_multiplier = 0.5
	Audio.play("res://sounds/coin.ogg")
	filled.emit()
	if island != null:
		island.solve_puzzle(solved_name, filled_message)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := use_range
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or bool(candidate.get("is_dead")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best