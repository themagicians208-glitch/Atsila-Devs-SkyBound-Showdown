class_name NatureSeal
extends Node3D

## One of the island's three nature seals. Each is a stone pedestal holding a
## dormant rune, and each answers to a different challenge - the brief's three:
##
##   "guardian"  a Shadow Slime patrols it; interact is refused while one lives
##   "switch"    dormant until a hidden switch elsewhere on the island is thrown
##   "climb"     simply hard to reach - the platforming is the puzzle
##
## A seal that is still waiting says what it wants, so the player is never left
## guessing why it will not open.

signal lit

const IDLE_COLOR := Color("#7a6f8f")
const LIVE_COLOR := Color("#65f6ad")

@export var seal_name := "Seal"
@export var solution := "climb"
## For "switch" seals: the puzzle name of the switch that feeds this seal.
@export var feed_puzzle := "seal_feed"
## For "guardian" seals: how close a living enemy has to be to ward the seal.
@export var ward_range := 7.0
@export var use_range := 2.8

var island: ForgottenIsland = null
var awakened := false

var _rune: MeshInstance3D
var _rune_material: StandardMaterial3D
var _orb: MeshInstance3D
var _orb_material: StandardMaterial3D
var _radiance: OmniLight3D
var _time := 0.0
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

	for radius in [0.78, 0.56]:
		var step := MeshInstance3D.new()
		var step_mesh := CylinderMesh.new()
		step_mesh.top_radius = float(radius)
		step_mesh.bottom_radius = float(radius) + 0.1
		step_mesh.height = 0.28
		step_mesh.radial_segments = 18
		step.mesh = step_mesh
		step.material_override = stone_dark if radius > 0.6 else stone
		step.position.y = 0.14 if radius > 0.6 else 0.42
		add_child(step)

	var column := MeshInstance3D.new()
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.34
	column_mesh.bottom_radius = 0.44
	column_mesh.height = 0.85
	column_mesh.radial_segments = 16
	column.mesh = column_mesh
	column.material_override = stone
	column.position.y = 1.0
	add_child(column)

	_rune_material = StandardMaterial3D.new()
	_rune_material.albedo_color = IDLE_COLOR
	_rune_material.emission_enabled = true
	_rune_material.emission = IDLE_COLOR
	_rune_material.emission_energy_multiplier = 0.4
	_rune = MeshInstance3D.new()
	var rune_mesh := TorusMesh.new()
	rune_mesh.inner_radius = 0.46
	rune_mesh.outer_radius = 0.58
	rune_mesh.rings = 22
	rune_mesh.ring_segments = 10
	_rune.mesh = rune_mesh
	_rune.material_override = _rune_material
	_rune.position.y = 1.7
	add_child(_rune)

	_orb_material = StandardMaterial3D.new()
	_orb_material.albedo_color = IDLE_COLOR
	_orb_material.emission_enabled = true
	_orb_material.emission = IDLE_COLOR
	_orb_material.emission_energy_multiplier = 0.5
	_orb = MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.3
	orb_mesh.height = 0.6
	orb_mesh.radial_segments = 18
	orb_mesh.rings = 10
	_orb.mesh = orb_mesh
	_orb.material_override = _orb_material
	_orb.position.y = 1.7
	_orb.scale = Vector3(1.0, 1.2, 1.0)
	add_child(_orb)

	# Which challenge this one wants, written on the plinth as a row of marks.
	var mark_material := StandardMaterial3D.new()
	mark_material.albedo_color = Color("#c9c2d8")
	var marks := 1 if solution == "guardian" else (2 if solution == "switch" else 3)
	for i in marks:
		var mark := MeshInstance3D.new()
		var mark_mesh := BoxMesh.new()
		mark_mesh.size = Vector3(0.12, 0.12, 0.06)
		mark.mesh = mark_mesh
		mark.material_override = mark_material
		mark.position = Vector3(-0.22 + 0.22 * float(i), 1.28, 0.44)
		add_child(mark)

	_radiance = OmniLight3D.new()
	_radiance.light_color = IDLE_COLOR
	_radiance.light_energy = 0.35
	_radiance.omni_range = 5.0
	_radiance.position.y = 1.7
	add_child(_radiance)


func _process(delta: float) -> void:
	_time += delta
	if _rune != null:
		_rune.rotate_y(delta * (1.8 if awakened else 0.45))
		_rune.position.y = 1.7 + sin(_time * 1.5) * 0.06
	if _orb != null:
		_orb.position.y = 1.7 + sin(_time * 1.5 + 1.0) * 0.06
		_orb.scale = Vector3(1.0, 1.2 + sin(_time * 2.2) * 0.08, 1.0)
	if _refused > 0.0:
		_refused -= delta


## Why this seal will not open yet, or "" when it is ready.
func blocking_reason() -> String:
	if awakened:
		return ""
	if solution == "guardian" and _guardian_alive():
		return "%s is warded - something dark still guards it." % seal_name
	if solution == "switch" and island != null and not island.is_puzzle_solved(feed_puzzle):
		return "%s is dormant - a hidden switch elsewhere feeds it." % seal_name
	return ""


func _guardian_alive() -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if int(enemy.get("health")) <= 0:
			continue
		if global_position.distance_to(enemy.global_position) <= ward_range:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if awakened:
		return
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if _nearest_player() != null:
				_try_awaken()
				get_viewport().set_input_as_handled()
			return


func _try_awaken() -> void:
	var reason := blocking_reason()
	if not reason.is_empty():
		if _refused <= 0.0:
			_refused = 2.0
			_report(reason)
		return
	awaken()


## Light the seal. The island calls this once its challenge is met.
func awaken() -> void:
	if awakened:
		return
	awakened = true
	if _rune_material != null:
		_rune_material.albedo_color = LIVE_COLOR
		_rune_material.emission = LIVE_COLOR
		_rune_material.emission_energy_multiplier = 1.8
	if _orb_material != null:
		_orb_material.albedo_color = LIVE_COLOR
		_orb_material.emission = LIVE_COLOR
		_orb_material.emission_energy_multiplier = 2.0
	if _radiance != null:
		_radiance.light_color = LIVE_COLOR
		_radiance.light_energy = 1.1
	Audio.play("res://sounds/coin.ogg")
	lit.emit()
	if island != null:
		island.seal_awakened(self)


func _report(text: String) -> void:
	if island != null:
		island.message.emit(text)


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