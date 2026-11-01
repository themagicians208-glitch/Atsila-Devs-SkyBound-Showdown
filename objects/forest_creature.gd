class_name ForestCreature
extends Node3D

## Friendly Forest Creature (Puzzle 3 of The Whispering Woods).
##
## Charming Animal-Crossing-inspired forest sprite trapped by corrupted shadow
## roots or a dormant nature switch. Never harms the player. When rescued, its
## cage shatters, it rewards a coin, saves its rescue in Progress, updates the
## HUD counter, and hops happily to a safe clearing.

signal rescued(creature: ForestCreature)

const COIN_SCENE := preload("res://objects/coin.tscn")

@export var creature_id := "sprout_01"
@export var creature_name := "Pip"
@export var required_puzzle := ""
@export var interact_range := 2.8
@export var safe_spot := Vector3.ZERO
@export var body_color := Color("#7bf2b5")

var woods: Node = null
var is_rescued := false

var _visual: Node3D
var _head_pivot: Node3D
var _leaf_l: Node3D
var _leaf_r: Node3D
var _cage: Node3D
var _cage_body: StaticBody3D
var _time := 0.0
var _hint_cooldown := 0.0


func _ready() -> void:
	add_to_group("forest_creatures")
	_build()
	var prog := get_node_or_null("/root/Progress")
	if prog != null and bool(prog.call("is_creature_rescued", creature_id)):
		_complete_rescue_quietly()


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "CreatureVisual"
	add_child(_visual)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body_mat.roughness = 0.45

	var cheek_mat := StandardMaterial3D.new()
	cheek_mat.albedo_color = Color("#ff94b8")
	cheek_mat.emission_enabled = true
	cheek_mat.emission = Color("#ff94b8")
	cheek_mat.emission_energy_multiplier = 0.5

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color("#46c96b")
	leaf_mat.roughness = 0.5

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color("#1b1626")

	var torso := MeshInstance3D.new()
	var torso_sphere := SphereMesh.new()
	torso_sphere.radius = 0.28
	torso_sphere.height = 0.52
	torso.mesh = torso_sphere
	torso.material_override = body_mat
	torso.position.y = 0.26
	_visual.add_child(torso)

	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.52, 0.0)
	_visual.add_child(_head_pivot)

	var head := MeshInstance3D.new()
	var head_sphere := SphereMesh.new()
	head_sphere.radius = 0.26
	head_sphere.height = 0.48
	head.mesh = head_sphere
	head.material_override = body_mat
	_head_pivot.add_child(head)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_sphere := SphereMesh.new()
		eye_sphere.radius = 0.045
		eye_sphere.height = 0.09
		eye.mesh = eye_sphere
		eye.material_override = eye_mat
		eye.position = Vector3(0.1 * side, 0.03, 0.23)
		_head_pivot.add_child(eye)

		var cheek := MeshInstance3D.new()
		var cheek_sphere := SphereMesh.new()
		cheek_sphere.radius = 0.045
		cheek_sphere.height = 0.06
		cheek.mesh = cheek_sphere
		cheek.material_override = cheek_mat
		cheek.position = Vector3(0.16 * side, -0.04, 0.21)
		_head_pivot.add_child(cheek)

	_leaf_l = _build_leaf(-1.0, leaf_mat)
	_leaf_r = _build_leaf(1.0, leaf_mat)
	_head_pivot.add_child(_leaf_l)
	_head_pivot.add_child(_leaf_r)

	# Corrupted shadow-root cage around the creature until rescued
	_cage = Node3D.new()
	_cage.name = "CorruptedCage"
	add_child(_cage)
	var root_mat := StandardMaterial3D.new()
	root_mat.albedo_color = Color("#3b1d5e")
	root_mat.emission_enabled = true
	root_mat.emission = Color("#8b46ff")
	root_mat.emission_energy_multiplier = 0.65
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var bar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045
		cyl.bottom_radius = 0.075
		cyl.height = 0.95
		bar.mesh = cyl
		bar.material_override = root_mat
		bar.position = Vector3(cos(angle) * 0.48, 0.46, sin(angle) * 0.48)
		bar.rotation.z = -cos(angle) * 0.22
		bar.rotation.x = sin(angle) * 0.22
		_cage.add_child(bar)

	_cage_body = StaticBody3D.new()
	_cage_body.name = "CageBody"
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 0.52
	cyl_shape.height = 0.95
	shape.shape = cyl_shape
	shape.position.y = 0.48
	_cage_body.add_child(shape)
	add_child(_cage_body)


func _build_leaf(side: float, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.08 * side, 0.22, 0.0)
	var leaf := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.24
	leaf.mesh = sphere
	leaf.material_override = mat
	leaf.position = Vector3(0.06 * side, 0.08, 0.0)
	leaf.rotation.z = -0.45 * side
	pivot.add_child(leaf)
	return pivot


func _process(delta: float) -> void:
	_time += delta
	_hint_cooldown = maxf(_hint_cooldown - delta, 0.0)
	if _visual != null:
		var hop := absf(sin(_time * (6.5 if is_rescued else 2.8))) * (0.24 if is_rescued else 0.06)
		_visual.position.y = hop
	if _head_pivot != null:
		_head_pivot.rotation.y = sin(_time * 2.4) * 0.25
		_head_pivot.rotation.z = cos(_time * 3.1) * 0.08
	if _leaf_l != null and _leaf_r != null:
		var wiggle := sin(_time * 5.5) * 0.22
		_leaf_l.rotation.z = wiggle
		_leaf_r.rotation.z = -wiggle

	if not is_rescued and not required_puzzle.is_empty() and woods != null:
		if bool(woods.call("is_puzzle_solved", required_puzzle)):
			rescue()


func _unhandled_input(event: InputEvent) -> void:
	if is_rescued:
		return
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
			if _player_in_range():
				try_rescue()
				return


func _player_in_range() -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Node3D
		if p != null and p.global_position.distance_to(global_position) <= interact_range:
			return true
	return false


func try_rescue() -> bool:
	if is_rescued:
		return true
	if not required_puzzle.is_empty() and woods != null and not bool(woods.call("is_puzzle_solved", required_puzzle)):
		if _hint_cooldown <= 0.0:
			_hint_cooldown = 2.0
			if woods.has_signal("message"):
				woods.emit_signal("message", "%s is trapped by a dark root seal - activate the nearby nature switch first!" % creature_name)
		return false
	rescue()
	return true


func rescue() -> void:
	if is_rescued:
		return
	is_rescued = true
	var prog := get_node_or_null("/root/Progress")
	if prog != null and prog.has_method("record_creature_rescued"):
		prog.call("record_creature_rescued", creature_id)
	if _cage != null:
		_cage.visible = false
	if _cage_body != null:
		for child in _cage_body.find_children("*", "CollisionShape3D", true, false):
			(child as CollisionShape3D).set_deferred("disabled", true)
	Audio.play("res://sounds/coin.ogg")
	# Drop a bonus reward coin right beside the rescued creature
	if get_parent() != null:
		var bonus_coin: Area3D = COIN_SCENE.instantiate()
		bonus_coin.position = position + Vector3(0.0, 0.85, 0.8)
		get_parent().add_child(bonus_coin)
		if woods != null and woods.get("coins_placed") != null:
			woods.set("coins_placed", int(woods.get("coins_placed")) + 1)
	if safe_spot != Vector3.ZERO:
		var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "position", safe_spot, 1.1)
	if woods != null and woods.has_method("on_creature_rescued"):
		woods.call("on_creature_rescued", self)
	rescued.emit(self)


func _complete_rescue_quietly() -> void:
	is_rescued = true
	if _cage != null:
		_cage.visible = false
	if _cage_body != null:
		for child in _cage_body.find_children("*", "CollisionShape3D", true, false):
			(child as CollisionShape3D).disabled = true
	if safe_spot != Vector3.ZERO:
		position = safe_spot
