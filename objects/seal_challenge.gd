extends Node3D
class_name SealChallenge

## The mid-challenge rule changes behind Frozen Skies' three Frozen Seals.
##
##   "moving" - Seal I. Ride three ice platforms out to the timed switch and the
##              seal. Halfway across (standing on the middle platform) every
##              platform reverses its patrol, so the last two hops have to be
##              re-timed rather than repeated.
##
##   "arena"  - Seal III. The frozen guardians guard the last seal on three safe
##              platforms. When the first guardian falls, those platforms start
##              fading in and out on a warning timer, so the fight has to be
##              finished on moving ground.
##
## Seal II's challenge is the crystal puzzle itself (see crystal_light_puzzle.gd).

signal completed
signal notice(text: String, tone: String)

@export var mode := "moving"

var rule_shift: RuleShift
var platforms: Array[AnimatableBody3D] = []
var _origins: Array[Vector3] = []
var _offsets: Array[Vector3] = []
var _phases: Array[float] = []
var _solid: Array[bool] = []
var _timers: Array[float] = []
var _forward := Vector3.FORWARD
var _across := Vector3.RIGHT
var _anchor := Vector3.ZERO
var _far_pad: Node3D
var _player: Node3D
var _time := 0.0
var _enemies_at_start := -1
var _first_fallen := false
var _cleared := false


func configure(anchor: Vector3, lane: Vector3, across: Vector3, challenge_mode: String) -> void:
	_anchor = anchor
	_forward = lane.normalized()
	_across = across.normalized()
	mode = challenge_mode
	# The site lays its children out in world coordinates, so the node itself sits
	# at the origin and only the beacon is offset to the site.
	position = Vector3.ZERO
	_build()
	rule_shift = RuleShift.new()
	rule_shift.name = "RuleShift"
	rule_shift.position = _anchor + Vector3(0.0, 0.2, 0.0)
	add_child(rule_shift)
	if mode == "moving":
		rule_shift.configure(
			"seal_one",
			"SEAL I - THE MOVING ICE",
			2,
			1,
			_apply_rules,
			"PLATFORMS ARE REVERSING!",
			"THE ICE PATROLS SWAP DIRECTION - RE-TIME THE LAST TWO HOPS",
			2.6)
		rule_shift.initial_objective = "ride the moving ice platforms out to the timed switch and the first seal"
		rule_shift.new_objective = "every platform now patrols the other way"
	else:
		rule_shift.configure(
			"seal_three",
			"SEAL III - THE FROZEN GUARDIANS",
			3,
			2,
			_apply_rules,
			"THE SAFE PLATFORMS ARE SHIFTING!",
			"THE ARENA GROUND NOW FADES - KEEP MOVING AND KEEP FIGHTING",
			2.8)
		rule_shift.initial_objective = "defeat the frozen guardians and activate the last seal"
		rule_shift.new_objective = "the safe platforms fade in and out - fight from the solid ones"
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	rule_shift.completed.connect(func(_name: String):
		notice.emit(rule_shift.puzzle_name + " CLEARED.", "complete")
		completed.emit()
	)
	_apply_rules(0)
	rule_shift.restore()


func _apply_rules(stage: int) -> void:
	if stage <= 0:
		if mode == "moving":
			_offsets = [_across * 1.6, _across * -1.6, _across * 1.6]
		for index in platforms.size():
			_timers[index] = -1.0
			_set_solid(index, true)
		return
	if mode == "moving":
		# The same patrols, mirrored: the platforms now drift the other way.
		_offsets = [_across * -1.6, _across * 1.6, _across * -1.6]
	else:
		for index in platforms.size():
			_timers[index] = 1.4 + float(index) * 1.2


func _process(delta: float) -> void:
	_time += delta
	_drive_platforms(delta)
	_drive_timers(delta)
	if rule_shift == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if not rule_shift.introduced and _anchor.distance_to(_player.global_position) < 9.0:
		rule_shift.introduced = true
		rule_shift.introduce()
	if rule_shift.finished:
		return
	if mode == "moving":
		_track_crossing()
	else:
		_track_arena()


func _track_crossing() -> void:
	if rule_shift.steps_done == 0 and platforms.size() > 1:
		if _player.global_position.distance_to(platforms[1].global_position) < 1.8:
			rule_shift.note_progress("middle_platform")
	if _far_pad != null and _player.global_position.distance_to(_far_pad.global_position) < 2.4:
		if rule_shift.steps_done >= 1:
			rule_shift.note_progress("far_side")
		else:
			rule_shift.note_progress("shortcut")
			rule_shift.note_progress("far_side")


func _track_arena() -> void:
	var alive := _living_guardians()
	if _enemies_at_start < 0:
		if _anchor.distance_to(_player.global_position) < 11.0 and alive > 0:
			_enemies_at_start = alive
			rule_shift.note_progress("encounter_started")
		return
	if not _first_fallen and alive < _enemies_at_start:
		_first_fallen = true
		rule_shift.note_progress("first_guardian_fallen")
	if not _cleared and alive <= 0:
		_cleared = true
		if rule_shift.steps_done >= 2:
			rule_shift.note_progress("guardians_cleared")
		else:
			while rule_shift.steps_done < 2 and not rule_shift.finished:
				rule_shift.note_progress("guardians_cleared")
			if not rule_shift.finished:
				rule_shift.note_progress("guardians_cleared")


## Frozen enemies still standing anywhere in the level, by script (no class
## references, so this also works from the headless tools).
func _living_guardians() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var script: Script = enemy.get_script() as Script
		if script != null and str(script.resource_path).ends_with("frozen_enemy.gd"):
			count += 1
	return count


func _drive_platforms(delta: float) -> void:
	for index in platforms.size():
		var platform := platforms[index]
		if not is_instance_valid(platform):
			continue
		_phases[index] += delta * (1.0 + float(index) * 0.15)
		var blend := (sin(_phases[index]) + 1.0) * 0.5
		platform.position = _origins[index] + _offsets[index] * blend


func _drive_timers(delta: float) -> void:
	for index in _timers.size():
		var timer: float = _timers[index]
		if timer < 0.0:
			continue
		timer -= delta
		if timer > 0.0 and timer <= 1.0 and index < platforms.size():
			var home := _origins[index]
			platforms[index].position = home + Vector3(sin(_time * 32.0) * 0.05, 0.0, cos(_time * 28.0) * 0.05)
			FrozenAudio.cue(self, "crack", 0.35, -22.0)
		if timer <= 0.0:
			_set_solid(index, not _solid[index])
			_timers[index] = 3.0 if _solid[index] else 1.5
			Audio.play("res://sounds/land.ogg" if _solid[index] else "res://sounds/break.ogg")
		else:
			_timers[index] = timer


func _set_solid(index: int, solid: bool) -> void:
	var platform := platforms[index]
	for node in platform.find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", not solid)
	for node in platform.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		var material := visual.material_override as StandardMaterial3D
		if material != null:
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color("#cfeaff") if solid else Color(0.9, 0.75, 0.8, 0.35)
			material.emission_energy_multiplier = 0.6 if solid else 1.7
	_solid[index] = solid


func far_side_position() -> Vector3:
	return _far_pad.global_position if _far_pad != null else _anchor


func is_solved() -> bool:
	return rule_shift != null and rule_shift.finished


func state_name() -> String:
	return rule_shift.state_name() if rule_shift != null else "INITIAL_STATE"


func guardian_count() -> int:
	return _enemies_at_start


func _build() -> void:
	if mode == "moving":
		# Three platforms patrolling across the valley, out to the far pad.
		for index in 3:
			var origin := _anchor + _forward * (2.2 + float(index) * 2.6) + Vector3(0.0, 0.6, 0.0)
			var platform := _make_platform("SealMovingPlatform_%d" % index, origin, Vector3(2.0, 0.34, 2.0))
			platforms.append(platform)
			_origins.append(origin)
			_offsets.append(_across * (1.6 if index % 2 == 0 else -1.6))
			_phases.append(float(index) * 1.2)
			_timers.append(-1.0)
			_solid.append(true)
		_far_pad = _make_pad("SealMovingFarPad", _anchor + _forward * 9.4)
		add_child(_far_pad)
	else:
		# Three safe platforms around the seal's arena.
		for index in 3:
			var angle := TAU * float(index) / 3.0
			var origin := _anchor + Vector3(cos(angle) * 3.0, 0.6, sin(angle) * 3.0)
			var platform := _make_platform("SealArenaPlatform_%d" % index, origin, Vector3(2.4, 0.3, 2.4))
			platforms.append(platform)
			_origins.append(origin)
			_offsets.append(Vector3.ZERO)
			_phases.append(0.0)
			_timers.append(-1.0)
			_solid.append(true)


func _make_platform(platform_name: String, where: Vector3, size: Vector3) -> AnimatableBody3D:
	var platform := AnimatableBody3D.new()
	platform.name = platform_name
	platform.position = where
	platform.sync_to_physics = true
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position.y = size.y * 0.5
	visual.material_override = _emissive(Color("#cfeaff"), 0.6)
	platform.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	platform.add_child(shape)
	add_child(platform)
	return platform


func _make_pad(pad_name: String, where: Vector3) -> StaticBody3D:
	var pad := StaticBody3D.new()
	pad.name = pad_name
	pad.position = where
	var size := Vector3(3.0, 0.18, 3.0)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _emissive(Color("#d8f4ff"), 0.35)
	pad.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	pad.add_child(shape)
	return pad


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.emission_enabled = energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = energy
	return material