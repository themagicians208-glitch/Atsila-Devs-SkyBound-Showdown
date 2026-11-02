class_name VanishingPlatform
extends Node3D

## One stone of the vanishing crossing. The project's PhasePlatform blinks in and
## out with no warning; this one is built for the brief's puzzle 3, where the
## player has to *read* the pattern and cross on the beat:
##
##   * stones take turns in a staggered wave, so the crossing pulses rather than
##     flashing all at once;
##   * a ghost outline stays behind whenever a stone is gone, showing exactly where
##     it will come back, so a mistimed jump is the player's mistake and not a
##     surprise;
##   * the rune above a stone pulses faster and faster as its solid window runs
##     out, which is the cue to jump now.
##
## `solid_time < period` is what makes it vanish at all; keep the solid window
## comfortably longer than one jump so the crossing is always fair.

@export var scene: PackedScene = null
@export var period := 3.8
@export var solid_time := 2.5
## Stagger along the wave. Neighbouring stones should differ by at least
## `period / 2` so they are never gone at the same moment.
@export var offset := 0.0
@export var warn_time := 0.7
@export var yaw := 0.0

var solid := true

var _stone: Node3D
var _ghost: Node3D
var _rune: MeshInstance3D
var _rune_material: StandardMaterial3D
var _shapes: Array[CollisionShape3D] = []
var _time := 0.0


func _ready() -> void:
	_build()
	# `offset` shifts this stone's place in the wave, so neighbours take turns.
	_time = 0.0
	_set_solid(true)


func _cycle_phase() -> float:
	var phase := fmod(_time + offset, period)
	if phase < 0.0:
		phase += period
	return phase


func _build() -> void:
	if scene != null:
		var node: Node3D = scene.instantiate()
		node.rotation.y = yaw
		add_child(node)
		_stone = node
		for child in node.find_children("*", "CollisionShape3D", true, false):
			_shapes.append(child as CollisionShape3D)

	# The ghost: a faint slab exactly where the stone sits, plus four motes at its
	# corners, so a missing stone still reads as "something belongs here".
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	_ghost.position.y = 0.5
	add_child(_ghost)
	var ghost_material := StandardMaterial3D.new()
	ghost_material.albedo_color = Color(0.62, 0.85, 1.0, 0.2)
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.emission_enabled = true
	ghost_material.emission = Color("#4fd8ff")
	ghost_material.emission_energy_multiplier = 0.5
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(1.85, 0.04, 1.7)
	slab.mesh = slab_mesh
	slab.material_override = ghost_material
	_ghost.add_child(slab)
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.09
	mote_mesh.height = 0.18
	mote_mesh.radial_segments = 10
	mote_mesh.rings = 5
	for corner in 4:
		var mote := MeshInstance3D.new()
		mote.mesh = mote_mesh
		mote.material_override = ghost_material
		mote.position = Vector3(
			0.78 if corner in [0, 3] else -0.78,
			0.14,
			0.72 if corner in [0, 1] else -0.72)
		_ghost.add_child(mote)

	_rune_material = StandardMaterial3D.new()
	_rune_material.albedo_color = Color("#7ce8ff")
	_rune_material.emission_enabled = true
	_rune_material.emission = Color("#4fd8ff")
	_rune_material.emission_energy_multiplier = 1.4
	_rune = MeshInstance3D.new()
	var rune_mesh := TorusMesh.new()
	rune_mesh.inner_radius = 0.34
	rune_mesh.outer_radius = 0.44
	rune_mesh.rings = 20
	rune_mesh.ring_segments = 10
	_rune.mesh = rune_mesh
	_rune.material_override = _rune_material
	_rune.position.y = 0.9
	add_child(_rune)


func _process(delta: float) -> void:
	_time += delta
	var phase := _cycle_phase()
	var wants_solid := phase < solid_time
	if wants_solid != solid:
		_set_solid(wants_solid)
	if _rune != null:
		_rune.rotate_y(delta * 1.1)
		_rune.position.y = 0.9 + sin(_time * 2.0) * 0.05
	if _ghost != null and not solid:
		_ghost.rotate_y(delta * 0.4)
	if _rune_material == null:
		return
	if not solid:
		_rune_material.emission_energy_multiplier = 0.35
	elif phase > solid_time - warn_time:
		# Time is nearly up: the rune throbs faster and faster.
		var left := solid_time - phase
		_rune_material.emission_energy_multiplier = 1.6 + sin(left * 34.0) * 0.9
	else:
		_rune_material.emission_energy_multiplier = 1.4


func _set_solid(state: bool) -> void:
	solid = state
	if _stone != null:
		_stone.visible = state
	if _ghost != null:
		_ghost.visible = not state
	for shape in _shapes:
		shape.set_deferred("disabled", not state)


## How much of one cycle this stone is standing. The checks use it to prove the
## crossing is fair before they time the pattern.
func solid_fraction() -> float:
	return clampf(solid_time / maxf(period, 0.01), 0.0, 1.0)