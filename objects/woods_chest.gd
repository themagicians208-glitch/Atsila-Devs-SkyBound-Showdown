class_name WoodsChest
extends Node3D

## The Ancient Chest in the Guardian's Grove of The Whispering Woods, holding the
## Second Fragment of the Eternal Tree.
##
## Guarded by ancient roots that retract when the Shadow Wolf Boss is defeated.
## Opening it plays the Second Fragment reveal (golden, blue and green energy,
## rescued creatures gathering in the grove, and the required message) and saves
## the Second Fragment in Progress.

signal opened
signal fragment_taken

const WOOD_COLOR := Color("#69462b")
const GOLD_TRIM := Color("#f5c84c")
const ROOT_COLOR := Color("#3e2759")
const FRAGMENT_GREEN := Color("#5ef2a8")
const FRAGMENT_GOLD := Color("#ffe678")
const FRAGMENT_BLUE := Color("#5cdbff")

@export var interact_range := 3.0
@export var fragment_lift := 1.75

var woods: Node = null
var is_open := false
var fragment_out := false

var _lid_pivot: Node3D
var _guard_roots: Node3D
var _fragment: Node3D
var _light: OmniLight3D
var _time := 0.0
var _refuse_cooldown := 0.0


func _ready() -> void:
	_build()
	var prog := get_node_or_null("/root/Progress")
	if prog != null and bool(prog.get("second_fragment_recovered")):
		_set_open_immediately()


func _build() -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = WOOD_COLOR
	wood_mat.roughness = 0.8

	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = GOLD_TRIM
	gold_mat.metallic = 0.4
	gold_mat.roughness = 0.35
	gold_mat.emission_enabled = true
	gold_mat.emission = GOLD_TRIM
	gold_mat.emission_energy_multiplier = 0.4

	var plinth := MeshInstance3D.new()
	var plinth_box := BoxMesh.new()
	plinth_box.size = Vector3(1.85, 0.2, 1.3)
	plinth.mesh = plinth_box
	plinth.material_override = gold_mat
	plinth.position.y = 0.1
	add_child(plinth)

	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(1.55, 0.76, 1.05)
	body.mesh = body_box
	body.material_override = wood_mat
	body.position.y = 0.4
	add_child(body)

	var collider := StaticBody3D.new()
	collider.name = "ChestBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.0, 1.1)
	shape.shape = box
	shape.position.y = 0.5
	collider.add_child(shape)
	add_child(collider)

	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidPivot"
	_lid_pivot.position = Vector3(0.0, 0.78, -0.52)
	add_child(_lid_pivot)

	var lid := MeshInstance3D.new()
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(1.55, 0.28, 1.05)
	lid.mesh = lid_box
	lid.material_override = gold_mat
	lid.position = Vector3(0.0, 0.14, 0.52)
	_lid_pivot.add_child(lid)

	# Roots wrapping the chest until the Shadow Wolf Boss is defeated
	_guard_roots = Node3D.new()
	_guard_roots.name = "GuardRoots"
	add_child(_guard_roots)
	var root_mat := StandardMaterial3D.new()
	root_mat.albedo_color = ROOT_COLOR
	for side in [-1.0, 1.0]:
		var root_arch := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.09
		cyl.bottom_radius = 0.14
		cyl.height = 1.4
		root_arch.mesh = cyl
		root_arch.material_override = root_mat
		root_arch.position = Vector3(0.55 * side, 0.65, 0.0)
		root_arch.rotation.z = 0.48 * side
		_guard_roots.add_child(root_arch)

	# The Second Fragment of the Eternal Tree
	_fragment = Node3D.new()
	_fragment.name = "SecondFragment"
	_fragment.position = Vector3(0.0, 0.55, 0.0)
	_fragment.visible = false
	add_child(_fragment)

	for pair in [[FRAGMENT_GOLD, 0.0], [FRAGMENT_GREEN, 1.05], [FRAGMENT_BLUE, 2.1]]:
		var shard := MeshInstance3D.new()
		var shard_box := BoxMesh.new()
		shard_box.size = Vector3(0.32, 0.52, 0.16)
		shard.mesh = shard_box
		var f_mat := StandardMaterial3D.new()
		var col: Color = pair[0]
		f_mat.albedo_color = col
		f_mat.emission_enabled = true
		f_mat.emission = col
		f_mat.emission_energy_multiplier = 2.2
		shard.material_override = f_mat
		shard.rotation = Vector3(0.3, float(pair[1]), 0.4)
		_fragment.add_child(shard)

	_light = OmniLight3D.new()
	_light.light_color = FRAGMENT_GREEN
	_light.light_energy = 0.0
	_light.omni_range = 8.0
	_fragment.add_child(_light)


func retract_roots() -> void:
	if _guard_roots == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_guard_roots, "position:y", -1.4, 0.8)
	tween.tween_callback(func(): _guard_roots.visible = false)


func blocking_reason() -> String:
	if is_open:
		return ""
	if woods != null and woods.has_method("is_boss_defeated") and not bool(woods.call("is_boss_defeated")):
		return "The ancient chest is bound by corrupted roots - defeat the Shadow Wolf Guardian first!"
	return ""


func _process(delta: float) -> void:
	_time += delta
	_refuse_cooldown = maxf(_refuse_cooldown - delta, 0.0)
	if _fragment != null and _fragment.visible:
		_fragment.rotation.y = _time * 1.9
	if not is_open and woods != null and woods.has_method("is_boss_defeated") and bool(woods.call("is_boss_defeated")):
		if _guard_roots != null and _guard_roots.visible and _guard_roots.position.y > -0.1:
			retract_roots()


func _unhandled_input(event: InputEvent) -> void:
	if is_open:
		return
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
			if _player_in_range():
				try_open()
				return


func _player_in_range() -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Node3D
		if p != null and p.global_position.distance_to(global_position) <= interact_range:
			return true
	return false


func try_open() -> bool:
	if is_open:
		return false
	var reason := blocking_reason()
	if not reason.is_empty():
		if _refuse_cooldown <= 0.0:
			_refuse_cooldown = 2.0
			if woods != null and woods.has_signal("message"):
				woods.emit_signal("message", reason)
		return false
	open()
	return true


func open() -> void:
	if is_open:
		return
	is_open = true
	if _guard_roots != null:
		_guard_roots.visible = false
	_fragment.visible = true
	Audio.play("res://sounds/coin.ogg")
	opened.emit()

	var prog := get_node_or_null("/root/Progress")
	if prog != null and prog.has_method("recover_second_fragment"):
		prog.call("recover_second_fragment")
	fragment_out = true

	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_lid_pivot, "rotation_degrees:x", -112.0, 0.65)
	tween.parallel().tween_property(_fragment, "position:y", fragment_lift, 0.95)
	tween.parallel().tween_property(_light, "light_energy", 2.6, 0.95)

	if woods != null and woods.has_signal("message"):
		woods.emit_signal("message", "You have recovered the Second Fragment of the Eternal Tree!")
	if woods != null and woods.has_method("fragment_recovered"):
		woods.call("fragment_recovered")
	fragment_taken.emit()


func _set_open_immediately() -> void:
	is_open = true
	fragment_out = true
	if _guard_roots != null:
		_guard_roots.visible = false
	if _lid_pivot != null:
		_lid_pivot.rotation_degrees.x = -112.0
	if _fragment != null:
		_fragment.visible = true
		_fragment.position.y = fragment_lift
	if _light != null:
		_light.light_energy = 2.2
