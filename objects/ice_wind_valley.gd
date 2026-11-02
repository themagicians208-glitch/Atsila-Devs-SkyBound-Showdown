extends Node3D
class_name IceWindValley

## Puzzle 2 - SLIPPERY ICE VALLEY.
##
## Initial rules: five ice platforms patrol gently across the valley and the wind
## blows straight down the crossing, so the platforms drift predictably. Ride them
## to the far island.
##
## Mid-puzzle rule change: halfway across (the third platform), the wind swings
## around. The vanes and the snow streaks flip first as the warning, then two
## platforms reverse their patrol, one freezes solid and stops dead, and one turns
## slick so the player skids on it. The route is the same line of platforms - but
## the timings are mirrored, so the crossing has to be re-read rather than redone.

const PLATFORM_COUNT := 5
const PLATFORM_SIZE := Vector3(2.0, 0.4, 2.0)
const LANE_SPACING := 2.6
const PATROL := 1.5
const ISLAND_DISTANCE := 14.0

signal completed
signal notice(text: String, tone: String)

var rule_shift: RuleShift
var platforms: Array[AnimatableBody3D] = []
var _offsets: Array[float] = []
var _speeds: Array[float] = []
var _phases: Array[float] = []
var _positions: Array[Vector3] = []
## Cracking platforms: a countdown that warns, then breaks, then reforms.
var _crumble_timers: Array[float] = []
var _solid: Array[bool] = []
var _slick_zones: Array[Area3D] = []
var _vanes: Array[Node3D] = []
var _shore := Vector3.ZERO
var _lane := Vector3.FORWARD
var _across := Vector3.RIGHT
var _streaks: GPUParticles3D
var _wind_arrow: Node3D
var _wind_reversed := false
var _time := 0.0
var _player: Node3D
var _highest_platform := -1
var _started_crossing := false
var _island: Node3D

const SLIPPERY_SCRIPT := preload("res://scripts/slippery_zone.gd")


func configure(anchor: Vector3, lane: Vector3, across: Vector3) -> void:
	_shore = anchor
	_lane = lane.normalized()
	_across = across.normalized()
	# Laid out in world coordinates: the site node stays at the origin.
	position = Vector3.ZERO
	_build()
	rule_shift = RuleShift.new()
	rule_shift.name = "RuleShift"
	rule_shift.position = _shore + Vector3(0.0, 0.2, 0.0)
	add_child(rule_shift)
	rule_shift.configure(
		"ice_wind_valley",
		"SLIPPERY ICE VALLEY",
		3,
		2,
		_apply_rules,
		"NEW RULE: PLATFORMS ARE REVERSING!",
		"THE WIND HAS TURNED - SOME ICE IS BREAKING AWAY",
		3.0)
	rule_shift.initial_objective = "ride the ice platforms across the valley; the wind is steady"
	rule_shift.new_objective = "two platforms drift the other way, one is frozen solid, one is slick and two break away"
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	rule_shift.completed.connect(func(_name: String):
		notice.emit("SLIPPERY ICE VALLEY CROSSED.", "complete")
		completed.emit()
	)
	_apply_rules(0)
	rule_shift.restore()


func _apply_rules(stage: int) -> void:
	if stage <= 0:
		_offsets = [PATROL, -PATROL, PATROL, -PATROL, PATROL]
		_speeds = [1.0, 0.9, 1.05, 0.95, 1.0]
		_wind_reversed = false
		_set_slick(false)
		_set_crumbling(false)
	else:
		# Two platforms mirror their patrol, one stops dead, two go slick and two
		# break away and reform on a warning timer (the ice is cracking).
		_offsets = [-PATROL, PATROL, 0.0, PATROL, -PATROL]
		_speeds = [1.25, 1.15, 0.0, 1.2, 1.3]
		_wind_reversed = true
		_set_slick(true)
		_set_crumbling(true)
	_apply_wind_visuals()


## The two outer platforms crumble away after a visible warning and come back.
func _set_crumbling(enabled: bool) -> void:
	if not enabled:
		for index in _crumble_timers.size():
			_crumble_timers[index] = -1.0
		for index in platforms.size():
			_set_platform_solid(index, true)
		return
	_crumble_timers = []
	for index in platforms.size():
		# Platforms 0 and 3 crack: not the ones the player is forced onto first.
		_crumble_timers.append(0.6 + float(index) * 0.9 if index in [0, 3] else -1.0)


func _set_platform_solid(index: int, solid: bool) -> void:
	var platform := platforms[index]
	for node in platform.find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", not solid)
	for node in platform.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		var material := visual.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = Color("#bfeaff") if solid else Color(0.9, 0.75, 0.8, 0.45)
			material.emission_energy_multiplier = 0.55 if solid else 1.6
	_solid[index] = solid


func _drive_crumbling(delta: float) -> void:
	if _crumble_timers.is_empty():
		return
	for index in _crumble_timers.size():
		var timer: float = _crumble_timers[index]
		if timer < 0.0:
			continue
		timer -= delta
		if timer > 0.0 and timer <= 1.0:
			# Warning window: the platform shakes and glows before it breaks.
			var platform := platforms[index]
			platform.position += Vector3(sin(_time * 40.0) * 0.03, 0.0, 0.0)
			FrozenAudio.cue(self, "crack", 0.4, -22.0)
		if timer <= 0.0:
			if _solid[index]:
				_set_platform_solid(index, false)
				_crumble_timers[index] = 1.6
				Audio.play("res://sounds/break.ogg")
			else:
				_set_platform_solid(index, true)
				_crumble_timers[index] = 3.4
		else:
			_crumble_timers[index] = timer


func _process(delta: float) -> void:
	_time += delta
	_drive_platforms(delta)
	_drive_crumbling(delta)
	_animate_vanes(delta)
	if rule_shift == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if not rule_shift.introduced and _shore.distance_to(_player.global_position) < 10.0:
		rule_shift.introduced = true
		rule_shift.introduce()
	if rule_shift.finished:
		return
	_track_crossing()


## The player's progress is the highest platform they have stood on, plus the
## far island: 1 platform = the crossing started, 3 = halfway (the rule change),
## the island = the crossing finished.
func _track_crossing() -> void:
	var landed := -1
	for index in platforms.size():
		if absf(platforms[index].global_position.y - _player.global_position.y) < 2.6 \
				and Vector2(platforms[index].global_position.x - _player.global_position.x,
						platforms[index].global_position.z - _player.global_position.z).length() < 1.6:
			landed = index
			break
	if landed >= 0 and landed > _highest_platform:
		_highest_platform = landed
		if not _started_crossing:
			_started_crossing = true
			rule_shift.note_progress("crossing_started")
		elif landed >= 2 and rule_shift.steps_done < 2:
			rule_shift.note_progress("halfway")
	if _island != null and _player.global_position.distance_to(_island.global_position) < 2.6:
		if rule_shift.steps_done >= 2:
			rule_shift.note_progress("far_island")
		elif not rule_shift.finished:
			# Reaching the island without the platform trail: count it all at once.
			rule_shift.note_progress("crossing_shortcut")
			rule_shift.note_progress("far_island")


func _drive_platforms(delta: float) -> void:
	for index in platforms.size():
		var platform := platforms[index]
		if not is_instance_valid(platform):
			continue
		var speed: float = _speeds[index]
		if speed <= 0.0:
			platform.position = _positions[index]
			continue
		_phases[index] = _phases[index] + delta * speed
		var blend := (sin(_phases[index]) + 1.0) * 0.5
		platform.position = _positions[index] + _across * (_offsets[index] * blend)
		if _slick_zones.size() > index:
			_slick_zones[index].global_position = platform.global_position


func _animate_vanes(delta: float) -> void:
	for vane in _vanes:
		if not is_instance_valid(vane):
			continue
		var shake := 0.0
		if rule_shift != null and rule_shift.state == RuleShift.State.RULE_CHANGE_WARNING:
			shake = sin(_time * 22.0) * 0.35
		var yaw := atan2(_across.x, _across.z) + (PI if _wind_reversed else 0.0) + shake
		vane.rotation.y = lerp_angle(vane.rotation.y, yaw, delta * 4.0)
	if _wind_arrow != null:
		var arrow_yaw := atan2(_across.x, _across.z) + (PI if _wind_reversed else 0.0)
		_wind_arrow.rotation.y = lerp_angle(_wind_arrow.rotation.y, arrow_yaw, delta * 3.0)
	if _streaks != null:
		var process := _streaks.process_material as ParticleProcessMaterial
		if process != null:
			var sign_axis := -1.0 if _wind_reversed else 1.0
			process.direction = Vector3(_across.x, 0.0, _across.z) * sign_axis


func _apply_wind_visuals() -> void:
	for vane in _vanes:
		if is_instance_valid(vane):
			vane.rotation.y = atan2(_across.x, _across.z) + (PI if _wind_reversed else 0.0)


func _set_slick(enabled: bool) -> void:
	for index in _slick_zones.size():
		var zone := _slick_zones[index]
		if not is_instance_valid(zone):
			continue
		# Only platforms 2 and 4 turn slick: the player should feel *which* ones.
		var should_be_slick := enabled and (index == 2 or index == 4)
		zone.visible = should_be_slick
		for shape in zone.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).set_deferred("disabled", not should_be_slick)


func is_solved() -> bool:
	return rule_shift != null and rule_shift.finished


func state_name() -> String:
	return rule_shift.state_name() if rule_shift != null else "INITIAL_STATE"


func island_position() -> Vector3:
	return _shore + _lane * ISLAND_DISTANCE


func platform_position(index: int) -> Vector3:
	return _positions[index] if index >= 0 and index < _positions.size() else Vector3.ZERO


func _build() -> void:
	_offsets = [PATROL, -PATROL, PATROL, -PATROL, PATROL]
	_speeds = [1.0, 0.9, 1.05, 0.95, 1.0]
	_phases = [0.0, 0.9, 1.8, 2.7, 3.6]
	add_child(_make_pad("IceWindShore", _shore))
	for index in PLATFORM_COUNT:
		var distance := 2.0 + float(index) * LANE_SPACING
		var origin := _shore + _lane * distance + Vector3(0.0, 0.55, 0.0)
		_positions.append(origin)
		var platform := _make_platform(index, origin)
		platforms.append(platform)
		add_child(platform)
		var zone := SLIPPERY_SCRIPT.new() as Area3D
		zone.name = "IceWindSlick_%d" % index
		zone.collision_layer = 0
		zone.collision_mask = 1
		var zone_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.1, 1.4, 2.1)
		zone_shape.shape = box
		zone.add_child(zone_shape)
		zone.position = origin
		zone.visible = false
		add_child(zone)
		_slick_zones.append(zone)
		_solid.append(true)
		_crumble_timers.append(-1.0)
	_island = _make_pad("IceWindFarIsland", island_position())
	add_child(_island)
	for index in 3:
		var vane := _make_vane(index)
		_vanes.append(vane)
		add_child(vane)
	_wind_arrow = _make_arrow()
	add_child(_wind_arrow)
	_streaks = _make_streaks()
	add_child(_streaks)
	_apply_wind_visuals()


func _make_platform(index: int, origin: Vector3) -> AnimatableBody3D:
	var platform := AnimatableBody3D.new()
	platform.name = "IceWindPlatform_%d" % index
	platform.position = origin
	platform.sync_to_physics = true
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = PLATFORM_SIZE
	visual.mesh = mesh
	visual.position.y = 0.2
	visual.material_override = _emissive(Color("#bfeaff"), 0.55)
	platform.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PLATFORM_SIZE
	shape.shape = box
	shape.position.y = 0.2
	platform.add_child(shape)
	return platform


func _make_pad(pad_name: String, where: Vector3) -> StaticBody3D:
	var pad := StaticBody3D.new()
	pad.name = pad_name
	pad.position = where
	var size := Vector3(3.4, 0.16, 3.4)
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


func _make_vane(index: int) -> Node3D:
	var vane := Node3D.new()
	vane.name = "IceWindVane_%d" % index
	vane.position = _shore + _lane * (1.0 + float(index) * 5.5) + _across * (2.6 if index % 2 == 0 else -2.6) + Vector3(0.0, 0.5, 0.0)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 1.5
	pole.mesh = pole_mesh
	pole.position.y = 0.75
	pole.material_override = _emissive(Color("#cfe7ff"), 0.2)
	vane.add_child(pole)
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.9, 0.16, 0.06)
	blade.mesh = blade_mesh
	blade.position = Vector3(0.35, 1.5, 0.0)
	blade.material_override = _emissive(Color("#8fe7ff"), 0.9)
	vane.add_child(blade)
	return vane


func _make_arrow() -> Node3D:
	var arrow := Node3D.new()
	arrow.name = "IceWindArrow"
	arrow.position = _shore + _lane * 0.6 + _across * -3.0 + Vector3(0.0, 0.6, 0.0)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.08, 0.08, 1.2)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 0.1, 0.0)
	shaft.material_override = _emissive(Color("#9fe8ff"), 1.1)
	arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.22
	head_mesh.height = 0.5
	head.mesh = head_mesh
	head.rotation.x = PI / 2.0
	head.position = Vector3(0.0, 0.1, 0.8)
	head.material_override = _emissive(Color("#c8f6ff"), 1.3)
	arrow.add_child(head)
	return arrow


func _make_streaks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "IceWindStreaks"
	particles.amount = 90
	particles.lifetime = 1.6
	particles.visibility_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 9.0, 24.0))
	var streak := BoxMesh.new()
	streak.size = Vector3(0.5, 0.04, 0.04)
	particles.draw_pass_1 = streak
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#e8fbff")
	material.emission_enabled = true
	material.emission = Color("#bff1ff")
	streak.material = material
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(_across.x, 0.0, _across.z)
	process.spread = 12.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 6.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.5
	particles.process_material = process
	particles.position = _shore + _lane * (ISLAND_DISTANCE * 0.5) + Vector3(0.0, 2.4, 0.0)
	return particles


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.emission_enabled = energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = energy
	return material