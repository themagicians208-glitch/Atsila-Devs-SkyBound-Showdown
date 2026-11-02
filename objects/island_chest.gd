class_name IslandChest
extends Node3D

## The sealed chest at the back of the Warden's chamber, holding the First
## Fragment. It will not open while the guardian still stands: the chest says so
## when a player tries, so nobody is left guessing.
##
## Opening it plays the fragment's short scene - the lid swings, the light pours
## out, the Fragment rises and the island's three lines land one after another -
## and then the recovery is written to saved progression.

signal opened
signal fragment_taken

const STONE := Color("#8f8aa0")
const STONE_DEEP := Color("#565064")
const LOCK_COLOR := Color("#ff7a5c")
const RUNE_COLOR := Color("#b06bff")
const FRAGMENT_COLOR := Color("#ffe9a8")

@export var interact_range := 3.0
@export var fragment_lift := 1.7

var island: ForgottenIsland = null
var is_open := false
var fragment_out := false

var _lid_pivot: Node3D
var _lock_material: StandardMaterial3D
var _fragment: Node3D
var _fragment_light: OmniLight3D
var _beam: MeshInstance3D
var _time := 0.0
var _refuse_cooldown := 0.0
var _already_recovered := false


func _ready() -> void:
	_already_recovered = Progress.fragment_recovered
	_build()
	if _already_recovered:
		# A player who has done this before finds it open and the Fragment shown.
		_set_open(false)
		fragment_out = true
		if _fragment != null:
			_fragment.visible = true
			_fragment.position.y = fragment_lift


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.9
	var deep := StandardMaterial3D.new()
	deep.albedo_color = STONE_DEEP
	deep.roughness = 0.95

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.5, 0.75, 1.0)
	body.mesh = body_mesh
	body.material_override = stone
	body.position.y = 0.38
	add_child(body)

	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(1.8, 0.18, 1.25)
	plinth.mesh = plinth_mesh
	plinth.material_override = deep
	plinth.position.y = 0.09
	add_child(plinth)

	var collider := StaticBody3D.new()
	collider.name = "ChestBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.0, 1.1)
	shape.shape = box
	shape.position.y = 0.5
	collider.add_child(shape)
	add_child(collider)

	# The lid rides a pivot along its back edge, so it swings open the way a real
	# chest does rather than sliding off.
	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidPivot"
	_lid_pivot.position = Vector3(0.0, 0.76, -0.5)
	add_child(_lid_pivot)

	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.5, 0.26, 1.0)
	lid.mesh = lid_mesh
	lid.material_override = stone
	lid.position = Vector3(0.0, 0.13, 0.5)
	_lid_pivot.add_child(lid)

	# The seal across the front, in the corruption's colour while it is locked.
	_lock_material = StandardMaterial3D.new()
	_lock_material.albedo_color = LOCK_COLOR
	_lock_material.emission_enabled = true
	_lock_material.emission = LOCK_COLOR
	_lock_material.emission_energy_multiplier = 1.6
	var seal := MeshInstance3D.new()
	var seal_mesh := BoxMesh.new()
	seal_mesh.size = Vector3(0.36, 0.9, 0.16)
	seal.mesh = seal_mesh
	seal.material_override = _lock_material
	seal.position = Vector3(0.0, 0.5, 0.52)
	add_child(seal)

	var rune := StandardMaterial3D.new()
	rune.albedo_color = RUNE_COLOR
	rune.emission_enabled = true
	rune.emission = RUNE_COLOR
	rune.emission_energy_multiplier = 1.2
	for side in [-1.0, 1.0]:
		var stud := MeshInstance3D.new()
		var stud_mesh := BoxMesh.new()
		stud_mesh.size = Vector3(0.14, 0.5, 0.1)
		stud.mesh = stud_mesh
		stud.material_override = rune
		stud.position = Vector3(0.55 * side, 0.42, 0.52)
		add_child(stud)

	# The First Fragment, hidden inside until the chest opens.
	_fragment = Node3D.new()
	_fragment.name = "FirstFragment"
	_fragment.position = Vector3(0.0, 0.5, 0.0)
	add_child(_fragment)
	var shard_material := StandardMaterial3D.new()
	shard_material.albedo_color = FRAGMENT_COLOR
	shard_material.emission_enabled = true
	shard_material.emission = FRAGMENT_COLOR
	shard_material.emission_energy_multiplier = 2.2
	var shard := MeshInstance3D.new()
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(0.3, 0.62, 0.3)
	shard.mesh = shard_mesh
	shard.material_override = shard_material
	_fragment.add_child(shard)
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.22
	tip_mesh.height = 0.4
	tip_mesh.radial_segments = 4
	tip.mesh = tip_mesh
	tip.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	tip.material_override = shard_material
	tip.position.y = 0.5
	_fragment.add_child(tip)
	_fragment.visible = false

	_fragment_light = OmniLight3D.new()
	_fragment_light.light_color = FRAGMENT_COLOR
	_fragment_light.light_energy = 0.0
	_fragment_light.omni_range = 9.0
	_fragment.add_child(_fragment_light)

	# The beam of light that stands over the chest while the Fragment is out.
	_beam = MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.5
	beam_mesh.bottom_radius = 0.8
	beam_mesh.height = 6.0
	beam_mesh.radial_segments = 20
	_beam.mesh = beam_mesh
	var beam_material := StandardMaterial3D.new()
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.albedo_color = Color(FRAGMENT_COLOR.r, FRAGMENT_COLOR.g, FRAGMENT_COLOR.b, 0.16)
	beam_material.emission_enabled = true
	beam_material.emission = FRAGMENT_COLOR
	beam_material.emission_energy_multiplier = 0.7
	beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.mesh.material = beam_material
	_beam.material_override = beam_material
	_beam.position.y = 3.2
	_beam.visible = false
	add_child(_beam)


func _process(delta: float) -> void:
	_time += delta
	_refuse_cooldown = maxf(_refuse_cooldown - delta, 0.0)
	if _lock_material != null and not is_open:
		_lock_material.emission_energy_multiplier = 1.2 + sin(_time * 2.4) * 0.5
	if _fragment != null and _fragment.visible:
		_fragment.rotation.y += delta * 0.9
		_fragment.position.y = fragment_lift + sin(_time * 1.3) * 0.12
	if _fragment_light != null and _fragment.visible:
		_fragment_light.light_energy = 1.6 + sin(_time * 2.0) * 0.3


## Why the chest will not open yet, or "" when it will.
func blocking_reason() -> String:
	if is_open:
		return ""
	if island != null and not island.is_warden_defeated():
		return "The chest is sealed by the Warden's corruption - the guardian still holds this chamber."
	return ""


func _unhandled_input(event: InputEvent) -> void:
	for action in ["interact", "p1_interact", "p2_interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if _nearest_player() != null:
				try_open()
				get_viewport().set_input_as_handled()
			return


## Called by the interact key, or directly by the dev checks.
func try_open() -> bool:
	if is_open:
		return true
	var reason := blocking_reason()
	if not reason.is_empty():
		if _refuse_cooldown <= 0.0:
			_refuse_cooldown = 2.5
			_report(reason)
		return false
	_open()
	return true


func _open() -> void:
	is_open = true
	_set_open(true)
	opened.emit()
	_report("The chest opens - the First Fragment is inside!")
	# The fragment's scene: the lid swings, the light comes up, the Fragment
	# rises over the chest, and the island's lines land one after another.
	var tween := create_tween()
	tween.tween_property(_lid_pivot, "rotation:x", -1.95, 1.1).set_trans(Tween.TRANS_CUBIC)
	await get_tree().create_timer(0.9).timeout
	if _fragment != null:
		_fragment.visible = true
	var rise := create_tween()
	rise.tween_property(_fragment, "position:y", fragment_lift, 2.0).set_trans(Tween.TRANS_SINE)
	_report("It rises: a shard of the sky itself, warm even from here.")
	await get_tree().create_timer(2.2).timeout
	fragment_out = true
	Progress.recover_fragment()
	fragment_taken.emit()
	_report("FIRST FRAGMENT RECOVERED.")
	if island != null:
		island.fragment_recovered()
	await get_tree().create_timer(2.4).timeout
	_report("The island's roots remember their own name.  The way home is open.")


## Put the chest in its open or closed state without the scene.
func _set_open(with_beam: bool) -> void:
	is_open = true
	if _lid_pivot != null:
		_lid_pivot.rotation.x = -1.95
	if _lock_material != null:
		_lock_material.albedo_color = Color("#8ef0c0")
		_lock_material.emission = Color("#8ef0c0")
		_lock_material.emission_energy_multiplier = 1.0
	if _beam != null:
		_beam.visible = with_beam


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