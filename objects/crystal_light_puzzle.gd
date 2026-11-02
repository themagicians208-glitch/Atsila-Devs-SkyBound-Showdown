extends Node3D
class_name CrystalLightPuzzle

## Puzzle 3 - THE THREE CRYSTAL PUZZLE (Frozen Crystal Caves).
##
## Initial rules: three crystals, each controlling one section of the cave's energy
## grid. Turn each one (interact / E) until the light in its beam lines up with the
## gate's focus ring. The crystals start at 0/1/2/3 quarter-turns and the targets
## are 1, 2, 3.
##
## Mid-puzzle rule change: as soon as TWO crystals line up, the cave re-routes its
## energy. The warning pulses (beacon, alarm, ice cracking), then the whole grid
## turns a quarter-turn together: every target shifts on by one, so the two
## crystals the player just aligned now point the wrong way, and the third crystal
## is sealed inside a shell until the energy conduit beside the gate is activated
## (Crystal Activation). Only then can the final crystal be turned to finish the
## new path. Failing only wastes turns - nothing can strand the player.

signal solved
signal notice(text: String, tone: String)

## Set by Frozen Skies before the node enters the tree.
@export var rule_shift_enabled := false

var _crystals: Array[MeshInstance3D] = []
var _rotations: Array[int] = [0, 0, 0]
var _targets: Array[int] = [1, 2, 3]
var _beams: Array[MeshInstance3D] = []
var _beam_materials: Array[StandardMaterial3D] = []
var _shell: Node3D
var _conduit: Node3D
var _conduit_material: StandardMaterial3D
var _conduit_ready := false
var _gate_marker: Node3D
## Stage two of the puzzle: one crystal turns on its own, and the last crystal can
## only be redirected through the reflection surface the cave reveals.
var _spinning := -1
var _mirror: Node3D
var _mirror_material: StandardMaterial3D
var _mirror_live := false
var is_solved := false
var rule_shift: RuleShift
var _time := 0.0

const SPIN_SPEED := 0.9
const QUARTER := PI * 0.5

func _ready() -> void:
	_build()
	if rule_shift_enabled:
		_build_rule_shift()
	if Progress.crystal_light_solved:
		is_solved = true
		_rotations = _targets.duplicate()
		_conduit_ready = true
		_shell.visible = false
	_update_energy()

func _build_rule_shift() -> void:
	rule_shift = RuleShift.new()
	rule_shift.name = "RuleShift"
	rule_shift.position = Vector3(0.0, 0.5, 0.0)
	add_child(rule_shift)
	rule_shift.configure(
		"three_crystals",
		"THE THREE CRYSTAL PUZZLE",
		4,
		1,
		_apply_rules,
		"CRYSTAL ENERGY DESTABILIZED!",
		"ONE CRYSTAL IS SPINNING - THE LAST IS FROZEN IN PLACE",
		2.8)
	rule_shift.initial_objective = "turn all three crystals to face the gate's focus ring"
	rule_shift.new_objective = "lock the spinning crystal, power the conduit and use the reflection surface"
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	_apply_rules(0)
	rule_shift.restore()

func _apply_rules(stage: int) -> void:
	if stage <= 0:
		_targets = [1, 2, 3]
		_conduit_ready = false
		_spinning = -1
		_mirror_live = false
		if _shell != null:
			_shell.visible = true
		if _mirror != null:
			_mirror.visible = false
		is_solved = false
	else:
		# Every crystal now points somewhere new, one of them turns by itself and
		# the far one is frozen in place: the reflection surface is the only way to
		# send its beam anywhere. Never already solved.
		_targets = [2, 0, 3]
		if _targets == _rotations:
			_targets = [3, 1, 2]
		_conduit_ready = Progress.frozen_rule_done("three_crystals_conduit")
		_spinning = 1
		_mirror_live = _conduit_ready
		if _shell != null:
			_shell.visible = not _conduit_ready
		if _mirror != null:
			_mirror.visible = true
		is_solved = false
	_update_energy()

func _process(delta: float) -> void:
	_time += delta
	for index in _crystals.size():
		var crystal := _crystals[index]
		crystal.position.y = 0.8 + sin(_time * 2.0 + float(index)) * 0.08
		if index == _spinning:
			# The destabilised crystal turns on its own until the player locks it.
			crystal.rotation.y += delta * SPIN_SPEED
			_rotations[index] = int(roundf(crystal.rotation.y / QUARTER)) % 4
			_rotations[index] = (_rotations[index] + 4) % 4
		else:
			crystal.rotation.y += delta * (0.35 if is_solved else 0.12)
	if _shell != null and _shell.visible:
		_shell.rotate_y(delta * 0.4)
	if _conduit != null:
		_conduit.rotate_y(delta * (0.9 if _conduit_ready else 0.2))
	if _mirror != null and _mirror.visible:
		_mirror.rotate_y(delta * (0.5 if _mirror_live else 0.12))
	_update_energy()

## Interact: the conduit first, then the reflection surface, then the crystals.
func try_interact(player: Node3D) -> bool:
	if is_solved:
		return false
	if _conduit != null and not _conduit_ready and global_position.distance_to(player.global_position) <= 4.2 \
			and _conduit.global_position.distance_to(player.global_position) <= 2.6:
		activate_conduit()
		return true
	if _mirror != null and _mirror.visible and _mirror.global_position.distance_to(player.global_position) <= 2.4:
		use_reflection_surface()
		return true
	if global_position.distance_to(player.global_position) > 3.2:
		return false
	var nearest := 0
	var distance := INF
	for index in _crystals.size():
		var current := _crystals[index].global_position.distance_to(player.global_position)
		if current < distance:
			distance = current
			nearest = index
	if nearest == 2 and _far_crystal_locked():
		notice.emit("The far crystal is frozen in place - redirect it with the reflection surface.", "fail")
		return true
	if nearest == _spinning:
		return _lock_crystal(nearest)
	_rotations[nearest] = (_rotations[nearest] + 1) % 4
	_crystals[nearest].rotation.y = float(_rotations[nearest]) * QUARTER
	Audio.play("res://sounds/coin.ogg")
	_update_energy()
	if _matches_targets():
		_finish()
	elif rule_shift != null and not rule_shift.shifted and _aligned_count() >= 2:
		rule_shift.note_progress("two_crystals")
	return true


## Stop the crystal that has been turning on its own, on whatever quarter it is
## nearest to. Timing the lock is the whole challenge of the second set of rules.
func _lock_crystal(index: int) -> bool:
	_spinning = -1
	_rotations[index] = int(roundf(_crystals[index].rotation.y / QUARTER)) % 4
	_crystals[index].rotation.y = float(_rotations[index]) * QUARTER
	Audio.play("res://sounds/land.ogg")
	notice.emit("Crystal locked on quarter %d." % _rotations[index], "objective")
	_update_energy()
	if _matches_targets():
		_finish()
	return true


## The surface the cave reveals: the only way to turn the frozen far crystal.
func use_reflection_surface() -> bool:
	if not _mirror_live:
		notice.emit("The reflection surface is dark - power the energy conduit.", "fail")
		return true
	if _rotations[2] == _targets[2]:
		notice.emit("The surface has nowhere left to send that beam.", "objective")
		return true
	_rotations[2] = (_rotations[2] + 1) % 4
	_crystals[2].rotation.y = float(_rotations[2]) * QUARTER
	Audio.play("res://sounds/coin.ogg")
	FrozenAudio.cue(self, "shift", 0.6, -18.0)
	_update_energy()
	if _matches_targets():
		_finish()
	return true

func activate_conduit() -> bool:
	if _conduit_ready:
		return false
	_conduit_ready = true
	_mirror_live = true
	_shell.visible = false
	Progress.set_frozen_rule_state("three_crystals_conduit", {"done": true, "shifted": true, "stage": 1, "steps": 1, "fails": 0})
	_update_energy()
	Audio.play("res://sounds/coin.ogg")
	FrozenAudio.cue(self, "shift", 1.0, -14.0)
	notice.emit("ENERGY CONDUIT POWERED - the reflection surface is live.", "changed")
	if _matches_targets():
		_finish()
	return true

## The far crystal is frozen from the moment the cave starts destabilising: a turn
## spent during the warning would be wasted, so it refuses them out loud.
func _far_crystal_locked() -> bool:
	if rule_shift == null:
		return false
	return rule_shift.shifted or rule_shift.state == RuleShift.State.RULE_CHANGE_WARNING


func _matches_targets() -> bool:
	if _spinning >= 0:
		return false
	if rule_shift != null and rule_shift.shifted and not _conduit_ready:
		return false
	return _rotations == _targets

func _aligned_count() -> int:
	var count := 0
	for index in _rotations.size():
		if _rotations[index] == _targets[index]:
			count += 1
	return count

func _finish() -> void:
	is_solved = true
	Progress.mark_crystal_light_solved()
	if rule_shift != null and not rule_shift.finished:
		rule_shift.complete()
	solved.emit()

func _update_energy() -> void:
	for index in _beams.size():
		var material := _beam_materials[index]
		var aligned := _rotations[index] == _targets[index] \
				and (rule_shift == null or not rule_shift.shifted or _conduit_ready)
		material.albedo_color = Color("#8ff6ff") if aligned else Color("#8d7bd8")
		material.emission = Color("#b7f7ff") if aligned else Color("#6f5fc0")
		material.emission_energy_multiplier = 2.0 if aligned else 0.6
		var beam := _beams[index]
		beam.scale = Vector3(1.0, 1.0, 1.0 + (0.25 if aligned else 0.0))
		beam.rotation.y = float(_rotations[index]) * PI * 0.5
	if _conduit_material != null:
		_conduit_material.albedo_color = Color("#eaffff") if _conduit_ready else Color("#4f6f9c")
		_conduit_material.emission = Color("#9ff3ff") if _conduit_ready else Color("#3b5c86")
		_conduit_material.emission_energy_multiplier = 2.2 if _conduit_ready else 0.7
	if _gate_marker != null:
		_gate_marker.rotation.y = float(_targets[0]) * PI * 0.5
	if _mirror_material != null:
		_mirror_material.albedo_color = Color("#eaffff") if _mirror_live else Color("#7fb6d8")
		_mirror_material.emission = Color("#9ff3ff") if _mirror_live else Color("#3b5c86")
		_mirror_material.emission_energy_multiplier = 2.0 if _mirror_live else 0.5

## How many quarter-turns are still needed (tools read this). The far crystal's
## turns come from the reflection surface, so they still count here.
func remaining_turns() -> int:
	var turns := 0
	for index in _rotations.size():
		turns += (_targets[index] - _rotations[index] + 4) % 4
	return turns


func mirror_position() -> Vector3:
	return _mirror.global_position if _mirror != null else global_position


func is_spinning() -> bool:
	return _spinning >= 0

func _build() -> void:
	for index in 3:
		var crystal := MeshInstance3D.new()
		crystal.name = "LightCrystal_%d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.32
		mesh.height = 1.5
		crystal.mesh = mesh
		crystal.position = Vector3(float(index - 1) * 1.35, 0.8, 0.0)
		crystal.material_override = _material(Color("#6ce7ff" if index == 0 else "#a58cff" if index == 1 else "#d8ffff"))
		add_child(crystal)
		_crystals.append(crystal)
		# The beam shows which way this crystal is sending its energy.
		var beam := MeshInstance3D.new()
		beam.name = "EnergyBeam_%d" % index
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(0.1, 0.1, 2.4)
		beam.mesh = beam_mesh
		beam.position = Vector3(float(index - 1) * 1.35, 0.8, 1.3)
		var beam_material := _material(Color("#8ff6ff"))
		beam.material_override = beam_material
		_beams.append(beam)
		_beam_materials.append(beam_material)
		add_child(beam)
	# Focus ring at the gate end: the crystals point this way.
	_gate_marker = Node3D.new()
	_gate_marker.name = "FocusRing"
	_gate_marker.position = Vector3(0.0, 0.9, 3.1)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.66
	ring.mesh = ring_mesh
	ring.rotation.x = PI / 2.0
	ring.material_override = _material(Color("#bff4ff"))
	_gate_marker.add_child(ring)
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.14, 0.14, 0.8)
	marker.mesh = marker_mesh
	marker.position.z = 0.6
	marker.material_override = _material(Color("#eaffff"))
	_gate_marker.add_child(marker)
	add_child(_gate_marker)
	# Shell over the third crystal; the conduit's energy dissolves it.
	_shell = Node3D.new()
	_shell.name = "ThirdCrystalShell"
	_shell.position = Vector3(1.35, 0.8, 0.0)
	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.62
	shell_mesh.height = 1.24
	shell.mesh = shell_mesh
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color(0.72, 0.86, 1.0, 0.42)
	shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_material.emission_enabled = true
	shell_material.emission = Color("#9fe8ff")
	shell_material.emission_energy_multiplier = 0.9
	shell.material_override = shell_material
	_shell.add_child(shell)
	add_child(_shell)
	# Energy conduit: a short tower by the gate.
	_conduit = Node3D.new()
	_conduit.name = "EnergyConduit"
	_conduit.position = Vector3(-2.4, 0.0, 2.4)
	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 0.2
	tower_mesh.bottom_radius = 0.42
	tower_mesh.height = 1.3
	tower.mesh = tower_mesh
	tower.position.y = 0.65
	_conduit_material = _material(Color("#4f6f9c"))
	tower.material_override = _conduit_material
	_conduit.add_child(tower)
	var crown := MeshInstance3D.new()
	var crown_mesh := TorusMesh.new()
	crown_mesh.inner_radius = 0.28
	crown_mesh.outer_radius = 0.4
	crown.mesh = crown_mesh
	crown.position.y = 1.45
	crown.rotation.x = PI / 2.0
	crown.material_override = _conduit_material
	_conduit.add_child(crown)
	add_child(_conduit)
	# Reflection surface: hidden while the energy is stable, revealed by the rule
	# change, and the only way to send the far crystal's beam anywhere new.
	_mirror = Node3D.new()
	_mirror.name = "ReflectionSurface"
	_mirror.position = Vector3(2.7, 0.0, 2.5)
	_mirror_material = _material(Color("#7fb6d8"))
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(1.2, 1.5, 0.14)
	panel.mesh = panel_mesh
	panel.position.y = 1.3
	panel.rotation.y = -0.6
	panel.material_override = _mirror_material
	_mirror.add_child(panel)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.09
	post_mesh.bottom_radius = 0.14
	post_mesh.height = 0.6
	post.mesh = post_mesh
	post.position.y = 0.3
	post.material_override = _mirror_material
	_mirror.add_child(post)
	_mirror.visible = false
	add_child(_mirror)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.3
	return material
