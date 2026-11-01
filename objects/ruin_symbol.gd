class_name RuinSymbol
extends Node3D

## One station of the ancient ruins puzzle: a stone pillar carrying a rotatable
## symbol, and a pressure plate set into the floor in front of it.
##
## The player turns the symbol by interacting with the pillar - it cycles square,
## circle, triangle - and then stands on the plate. The plate only holds a charge
## when the symbol matches the one carved on the ruins' broken pillars outside, so
## the puzzle is: read the clue, set all three, then step on the plates. A charged
## station glows and feeds the energy conduit running between them.

signal charged

const SHAPE_NAMES := ["square", "circle", "triangle"]

@export var required := 0
@export var required_hint := 0
@export var interact_range := 3.0
@export var plate_radius := 1.1

var island: ForgottenIsland = null
var symbol := 0
var is_charged := false

var _symbol_mesh: Node3D
var _plate_material: StandardMaterial3D
var _pillar_rune: MeshInstance3D
var _rune_material: StandardMaterial3D
var _plate_area: Area3D
var _on_plate := false
var _time := 0.0
var _spin := 0.0
var _refused := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#9a95a6")
	stone.roughness = 0.95
	var stone_dark := StandardMaterial3D.new()
	stone_dark.albedo_color = Color("#6b6579")
	stone_dark.roughness = 0.95

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.72
	base_mesh.bottom_radius = 0.86
	base_mesh.height = 0.3
	base_mesh.radial_segments = 18
	base.mesh = base_mesh
	base.material_override = stone_dark
	base.position.y = 0.15
	add_child(base)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.34
	shaft_mesh.bottom_radius = 0.46
	shaft_mesh.height = 1.5
	shaft_mesh.radial_segments = 16
	shaft.mesh = shaft_mesh
	shaft.material_override = stone
	shaft.position.y = 1.05
	add_child(shaft)

	# The symbol itself, floating above the pillar on a slowly turning ring.
	_symbol_mesh = Node3D.new()
	_symbol_mesh.name = "Symbol"
	_symbol_mesh.position.y = 2.15
	add_child(_symbol_mesh)
	_rebuild_symbol()

	_rune_material = StandardMaterial3D.new()
	_rune_material.albedo_color = Color("#b06bff")
	_rune_material.emission_enabled = true
	_rune_material.emission = Color("#b06bff")
	_rune_material.emission_energy_multiplier = 1.0
	_pillar_rune = MeshInstance3D.new()
	var rune_mesh := TorusMesh.new()
	rune_mesh.inner_radius = 0.5
	rune_mesh.outer_radius = 0.6
	rune_mesh.rings = 22
	rune_mesh.ring_segments = 10
	_pillar_rune.mesh = rune_mesh
	_pillar_rune.material_override = _rune_material
	_pillar_rune.position.y = 2.15
	add_child(_pillar_rune)

	# The pressure plate, out in front of the pillar (+Z, where the player stands).
	# Whether a player is standing on it is a plain distance test, the same
	# question the island's switches and seals ask - it cannot be missed the way an
	# Area3D overlap event can when something is teleported into place.
	_plate_material = StandardMaterial3D.new()
	_plate_material.albedo_color = Color("#7a7288")
	_plate_material.roughness = 0.8
	_plate_material.emission_enabled = true
	_plate_material.emission = Color("#b06bff")
	_plate_material.emission_energy_multiplier = 0.1
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = plate_radius * 0.85
	plate_mesh.bottom_radius = plate_radius * 0.95
	plate_mesh.height = 0.12
	plate_mesh.radial_segments = 20
	plate.mesh = plate_mesh
	plate.material_override = _plate_material
	plate.position = Vector3(0.0, 0.07, 1.9)
	add_child(plate)
	var lip := MeshInstance3D.new()
	var lip_mesh := TorusMesh.new()
	lip_mesh.inner_radius = plate_radius * 0.85
	lip_mesh.outer_radius = plate_radius * 0.98
	lip_mesh.rings = 22
	lip_mesh.ring_segments = 8
	lip.mesh = lip_mesh
	lip.material_override = stone_dark
	lip.position = Vector3(0.0, 0.06, 1.9)
	add_child(lip)

	_plate_area = null
	_on_plate = false


## The three shapes, built from primitives. A square, a ring and a triangle (a
## narrow pyramid), sized to read from across the ruin floor.
func _rebuild_symbol() -> void:
	if _symbol_mesh == null:
		return
	for child in _symbol_mesh.get_children():
		child.queue_free()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#cbb6ff")
	material.emission_enabled = true
	material.emission = Color("#b06bff")
	material.emission_energy_multiplier = 1.3
	match symbol:
		0:
			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(0.7, 0.7, 0.16)
			box.mesh = box_mesh
			box.material_override = material
			_symbol_mesh.add_child(box)
		1:
			var ring := MeshInstance3D.new()
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = 0.24
			ring_mesh.outer_radius = 0.38
			ring_mesh.rings = 20
			ring_mesh.ring_segments = 10
			ring.mesh = ring_mesh
			ring.material_override = material
			ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			_symbol_mesh.add_child(ring)
		_:
			var pyramid := MeshInstance3D.new()
			var pyramid_mesh := CylinderMesh.new()
			pyramid_mesh.top_radius = 0.0
			pyramid_mesh.bottom_radius = 0.46
			pyramid_mesh.height = 0.72
			pyramid_mesh.radial_segments = 3
			pyramid.mesh = pyramid_mesh
			pyramid.material_override = material
			pyramid.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			_symbol_mesh.add_child(pyramid)
	_spin = 0.6


func shape_name() -> String:
	return SHAPE_NAMES[symbol % SHAPE_NAMES.size()]


func required_name() -> String:
	return SHAPE_NAMES[required % SHAPE_NAMES.size()]


func matches() -> bool:
	return symbol == required


func _process(delta: float) -> void:
	_time += delta
	if _refused > 0.0:
		_refused -= delta
	# Standing on the plate is polled rather than reported by an overlap event.
	var stood := _player_on_plate()
	if stood != _on_plate:
		_on_plate = stood
		if stood:
			_evaluate()
	if _pillar_rune != null:
		_pillar_rune.rotate_y(delta * (2.2 if is_charged else 0.5))
	if _symbol_mesh != null:
		if _spin > 0.0:
			# A quick turn when the symbol changes.
			_spin = maxf(_spin - delta * 3.0, 0.0)
			_symbol_mesh.rotate_y(delta * 9.0 * _spin)
		else:
			_symbol_mesh.rotate_y(delta * 0.35)
		_symbol_mesh.position.y = 2.15 + sin(_time * 1.4) * 0.07
	if _plate_material == null:
		return
	if is_charged:
		_plate_material.emission_energy_multiplier = 1.6
	elif _on_plate:
		_plate_material.emission_energy_multiplier = 0.5 + sin(_time * 6.0) * 0.25
	else:
		_plate_material.emission_energy_multiplier = 0.1


func _on_plate_entered(_body: Node3D) -> void:
	pass


## Is a player standing on the plate right now?
func _player_on_plate() -> bool:
	var spot := to_global(Vector3(0.0, 0.3, 1.9))
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or bool(candidate.get("is_dead")):
			continue
		var offset := candidate.global_position - spot
		if Vector2(offset.x, offset.z).length() <= plate_radius and absf(offset.y) <= 1.1:
			return true
	return false


## A station holds its charge for good once the symbol is right and someone has
## stood on its plate - the ruin does not ask the player to stand still.
func _evaluate() -> void:
	if is_charged or not _on_plate:
		return
	if not matches():
		if _refused <= 0.0:
			_refused = 2.0
			_report("The plate stays cold: this symbol is carved as a %s elsewhere in the ruins." % required_name())
		return
	is_charged = true
	if _pillar_rune != null:
		_rune_material.albedo_color = Color("#65f6ad")
		_rune_material.emission = Color("#65ff9d")
		_rune_material.emission_energy_multiplier = 2.0
	if _plate_material != null:
		_plate_material.albedo_color = Color("#8ef0c0")
	Audio.play("res://sounds/coin.ogg")
	charged.emit()
	if island != null:
		island.ruin_station_charged(self)


## Cycle to the next symbol.
func turn() -> void:
	if is_charged:
		return
	symbol = (symbol + 1) % SHAPE_NAMES.size()
	_rebuild_symbol()
	Audio.play("res://sounds/land.ogg")
	if island != null:
		island.message.emit("The ruin symbol turns: %s." % shape_name())
	_evaluate()


## Set it directly. The dev checks and solve_all_puzzles use this.
func set_symbol(value: int) -> void:
	if is_charged:
		return
	symbol = posmod(value, SHAPE_NAMES.size())
	_rebuild_symbol()


## Force a charge without standing on the plate (see solve_all_puzzles).
func force_charge() -> void:
	if is_charged:
		return
	set_symbol(required)
	is_charged = true
	if _pillar_rune != null:
		_rune_material.albedo_color = Color("#65f6ad")
		_rune_material.emission = Color("#65ff9d")
		_rune_material.emission_energy_multiplier = 2.0
	if _plate_material != null:
		_plate_material.albedo_color = Color("#8ef0c0")
		_plate_material.emission_energy_multiplier = 1.6
	charged.emit()
	if island != null:
		island.ruin_station_charged(self)


func _unhandled_input(event: InputEvent) -> void:
	if is_charged:
		return
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if _nearest_player() != null:
				turn()
				get_viewport().set_input_as_handled()
			return


func _report(text: String) -> void:
	if island != null:
		island.message.emit(text)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := interact_range
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or bool(candidate.get("is_dead")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best