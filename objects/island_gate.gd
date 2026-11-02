class_name IslandGate
extends StaticBody3D

## An ancient stone gate: a wall of masonry that sinks into the ground when its
## puzzle is solved, taking its collision with it.
##
## The collision is a DIRECT child of this body, built before it can join the tree.
## That is not a style choice: with the Jolt backend a CollisionShape3D nested
## under an intermediate node - this gate used to hang its shape off the sinking
## Slab - never registers at all, and a shape added to a body already inside the
## tree does not register either. Either way the wall looks solid and is not, which
## is how every gate in the Forgotten Island could be walked straight through
## (tools/check_collision guards it now).
##
## The Slab carries only the masonry, and still sinks when the puzzle is solved;
## the collision is switched off at the same moment, so it does not need to follow.

@export var solved_name := "ancient_switch"
@export var width := 4.6
@export var height := 3.2
@export var sink := 3.6
## Decorative pillars either side of the opening, so the wall reads as built.
@export var side_pillars := true

var opened := false

var _slab: Node3D
var _collision: CollisionShape3D
var _rune: MeshInstance3D


func _init() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "WallCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.7)
	_collision.shape = box
	_collision.position.y = height * 0.5
	add_child(_collision)


func _ready() -> void:
	# The exports are only known now, so size the placeholder for real.
	(_collision.shape as BoxShape3D).size = Vector3(width, height, 0.7)
	_collision.position.y = height * 0.5
	_slab = Node3D.new()
	_slab.name = "Slab"
	add_child(_slab)
	_build()


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#8f8b96")
	stone.roughness = 0.95
	var stone_dark := StandardMaterial3D.new()
	stone_dark.albedo_color = Color("#5d5a66")
	stone_dark.roughness = 0.95

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, height, 0.7)
	mesh.mesh = box_mesh
	mesh.material_override = stone
	mesh.position.y = height * 0.5
	_slab.add_child(mesh)

	# Courses of blocks and a pair of carved runes, so it is not a plain slab.
	for row in 3:
		for column in 2:
			var block := MeshInstance3D.new()
			var block_mesh := BoxMesh.new()
			block_mesh.size = Vector3(width * 0.34, height * 0.16, 0.16)
			block.mesh = block_mesh
			block.material_override = stone_dark
			block.position = Vector3(
				(width * 0.5 - width * 0.17) * (1.0 if column == 0 else -1.0),
				height * 0.2 + float(row) * height * 0.27,
				0.42)
			_slab.add_child(block)

	_rune = MeshInstance3D.new()
	var rune_mesh := TorusMesh.new()
	rune_mesh.inner_radius = 0.34
	rune_mesh.outer_radius = 0.44
	rune_mesh.rings = 18
	rune_mesh.ring_segments = 8
	_rune.mesh = rune_mesh
	var rune_material := StandardMaterial3D.new()
	rune_material.albedo_color = Color("#b06bff")
	rune_material.emission_enabled = true
	rune_material.emission = Color("#b06bff")
	rune_material.emission_energy_multiplier = 1.2
	_rune.material_override = rune_material
	_rune.position = Vector3(0.0, height * 0.62, 0.45)
	_slab.add_child(_rune)

	if side_pillars:
		for side in [-1.0, 1.0]:
			var pillar := MeshInstance3D.new()
			var pillar_mesh := BoxMesh.new()
			pillar_mesh.size = Vector3(0.9, height + 1.1, 0.9)
			pillar.mesh = pillar_mesh
			pillar.material_override = stone_dark
			pillar.position = Vector3((width * 0.5 + 0.45) * side, (height + 1.1) * 0.5, 0.0)
			add_child(pillar)


func open() -> void:
	if opened:
		return
	opened = true
	for child in find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).set_deferred("disabled", true)
	if _rune != null:
		var material := _rune.material_override as StandardMaterial3D
		material.albedo_color = Color("#65f6ad")
		material.emission = Color("#25ff95")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_slab, "position:y", -sink, 1.1)
	Audio.play("res://sounds/break.ogg")