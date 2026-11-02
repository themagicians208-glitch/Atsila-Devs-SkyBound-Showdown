extends Node3D
class_name FortressShift

## Puzzle 5 - THE SHATTERED ICE FORTRESS.
##
## Initial rules: two fortress mechanisms on either side of a side hall. Ride the
## two moving ice platforms to reach mechanism A, then the old stair to mechanism
## B, and the fortress gate opens. A rune-marked section in the middle of the hall
## is dead and dark.
##
## Mid-puzzle rule change: after mechanism A the fortress comes apart. The rune
## section wakes up as a bounded anti-gravity shaft (marked with four lit pillars -
## the only place gravity changes, so the rest of the level is untouched), the two
## moving platforms mirror their patrol, the old corridor is walled off by a slab,
## and a new route of mirror-dimension platforms phases in: the player shifts
## dimension (Q / LB) to ride them to mechanism B.

const GATE_OPEN_DROP := 2.6

signal completed
signal notice(text: String, tone: String)

var rule_shift: RuleShift
var mechanisms: Array[FrozenMechanism] = []
var mirror_platforms: Array[AnimatableBody3D] = []
var moving_platforms: Array[AnimatableBody3D] = []
var blocker: StaticBody3D
var fortress_gate: PuzzleGate
var gravity_zone: Area3D
var _moving_origins: Array[Vector3] = []
var _moving_offsets: Array[Vector3] = []
var _moving_phases: Array[float] = []
var _moving_speeds: Array[float] = []
var _blade: AnimatableBody3D
var _blade_damage_cooldown := 0.0
var _anchor := Vector3.ZERO
var _lane := Vector3.FORWARD
var _across := Vector3.RIGHT
var _time := 0.0
var _player: Node3D
var _main: Node
var _shift_clock := 0.0
## Stage two: the storm walk, and the gust that sweeps it.
var storm_platforms: Array[AnimatableBody3D] = []
var storm_timers: Array[float] = []
var storm_solid: Array[bool] = []
var gust: Area3D
var _gust_clock := 0.0
var _gust_damage_clock := 0.0


func configure(anchor: Vector3, lane: Vector3, across: Vector3, main: Node) -> void:
	_anchor = anchor
	_lane = lane.normalized()
	_across = across.normalized()
	_main = main
	# Laid out in world coordinates: the site node stays at the origin.
	position = Vector3.ZERO
	_build()
	rule_shift = RuleShift.new()
	rule_shift.name = "RuleShift"
	rule_shift.position = _anchor + Vector3(0.0, 0.2, 0.0)
	add_child(rule_shift)
	rule_shift.configure(
		"fortress_shift",
		"THE SHATTERED ICE FORTRESS",
		4,
		[2, 3],
		_apply_rules,
		"FORTRESS STRUCTURE ALTERED!",
		"PLATFORMS REVERSED, A GATE CLOSED - A MIRROR PATH OPENED",
		3.0)
	rule_shift.initial_objective = "ride the ice platforms to mechanisms A and B, then climb to C"
	rule_shift.new_objective = "the rune shaft lifts you; shift dimension (Q) to ride the mirror platforms"
	rule_shift.add_stage_text(1,
		"A FROST STORM SWEEPS THE FORTRESS!",
		"PLATFORMS FADE IN AND OUT - DASH AND SHIELD THROUGH IT",
		"reach the storm walk and activate mechanism C")
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	rule_shift.completed.connect(func(_name: String):
		if fortress_gate != null:
			fortress_gate.open()
		notice.emit("THE SHATTERED ICE FORTRESS IS STABLE - its gate stands open.", "complete")
		completed.emit()
	)
	_apply_rules(0)
	rule_shift.restore()


func _apply_rules(stage: int) -> void:
	# Each stage is the union of every rule change so far, so a puzzle restored at
	# stage 2 still gets the structural changes of stage 1.
	if stage >= 1:
		if gravity_zone != null:
			gravity_zone.set("monitoring", true)
		_set_pillars(true)
		_set_blocker(true)
		_set_powered(true)
		_moving_offsets = [Vector3(0.0, 0.0, -2.2), Vector3(0.0, 0.0, 2.2)]
		_moving_speeds = [1.25, 1.35]
		if _main != null and _main.has_method("reverse_frozen_bridges"):
			_main.call("reverse_frozen_bridges")
		if _main != null and _main.has_method("grant_dimension_shifts"):
			_main.call("grant_dimension_shifts", 3)
	else:
		if gravity_zone != null:
			gravity_zone.set("monitoring", false)
		_set_pillars(false)
		_set_blocker(false)
		_set_powered(false)
		_moving_offsets = [Vector3(0.0, 0.0, 2.2), Vector3(0.0, 0.0, -2.2)]
		_moving_speeds = [0.9, 1.0]
	_set_storm(stage >= 2)
	if stage >= 2 and _main != null and _main.has_method("grant_dimension_shifts"):
		_main.call("grant_dimension_shifts", 1)


## The storm walk: three platforms that warn, break away and reform.
func _set_storm(enabled: bool) -> void:
	for index in storm_platforms.size():
		if storm_timers.size() <= index:
			storm_timers.append(-1.0)
		storm_timers[index] = (1.2 + float(index) * 1.5) if enabled else -1.0
		if not enabled:
			_set_storm_platform_solid(index, true)
	if not enabled:
		for index in storm_timers.size():
			storm_timers[index] = -1.0


func _set_storm_platform_solid(index: int, solid: bool) -> void:
	var platform := storm_platforms[index]
	for node in platform.find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", not solid)
	for node in platform.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		var material := visual.material_override as StandardMaterial3D
		if material != null:
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color("#cfeaff") if solid else Color(0.75, 0.85, 0.95, 0.3)
			material.emission_energy_multiplier = 0.6 if solid else 1.8
	if storm_solid.size() <= index:
		storm_solid.append(solid)
	else:
		storm_solid[index] = solid


func _drive_storm(delta: float) -> void:
	for index in storm_timers.size():
		var timer: float = storm_timers[index]
		if timer < 0.0:
			continue
		timer -= delta
		if timer > 0.0 and timer <= 1.0 and index < storm_platforms.size():
			var home: Vector3 = storm_platforms[index].get_meta("home", storm_platforms[index].position)
			storm_platforms[index].position = home + Vector3(sin(_time * 34.0) * 0.05, 0.0, 0.0)
			FrozenAudio.cue(self, "crack", 0.35, -22.0)
		if timer <= 0.0:
			var solid: bool = storm_solid[index] if index < storm_solid.size() else true
			_set_storm_platform_solid(index, not solid)
			storm_timers[index] = 3.2 if not solid else 1.6
			Audio.play("res://sounds/break.ogg" if solid else "res://sounds/land.ogg")
		else:
			storm_timers[index] = timer
	_drive_storm_gust(delta)


## A frost gust sweeps the storm walk on a timer: the Ice Shield blocks it
## completely, and it is only ever 1 point of damage without one.
func _drive_storm_gust(delta: float) -> void:
	if gust == null or not is_instance_valid(gust):
		return
	_gust_clock += delta
	var cycle := fmod(_gust_clock, 5.0)
	var active := cycle > 3.6
	gust.visible = active
	var visual := gust.find_child("GustSpray", true, false) as MeshInstance3D
	if visual != null and active:
		visual.scale = Vector3(1.0, 0.6 + (cycle - 3.6) * 1.2, 1.0)
	if not active or _player == null or not is_instance_valid(_player):
		return
	if _player.global_position.distance_to(gust.global_position) > 2.2:
		return
	_gust_damage_clock -= delta
	if _gust_damage_clock > 0.0:
		return
	_gust_damage_clock = 1.2
	if _player.has_method("take_damage"):
		_player.call("take_damage", 1.0, gust.global_position, "frost_storm")


func _process(delta: float) -> void:
	_time += delta
	_drive_platforms(delta)
	_drive_blade(delta)
	_drive_storm(delta)
	if rule_shift == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if not rule_shift.introduced and _anchor.distance_to(_player.global_position) < 10.0:
		rule_shift.introduced = true
		rule_shift.introduce()
	if rule_shift.stage == 1 and rule_shift.steps_done == 2 and _player.global_position.distance_to(storm_walk_position()) < 4.0:
		rule_shift.note_progress("storm_walk")
	# While the player is inside the fortress puzzle, the mirror shift cannot time
	# out under them: the new route depends on it.
	if rule_shift.shifted and _anchor.distance_to(_player.global_position) < 16.0:
		_shift_clock -= delta
		if _shift_clock <= 0.0:
			_shift_clock = 0.5
			if _main != null and _main.has_method("extend_shift"):
				_main.call("extend_shift", 4.0)


func try_activate(player: Node3D) -> bool:
	for index in mechanisms.size():
		var mechanism := mechanisms[index]
		if mechanism.is_activated or mechanism.global_position.distance_to(player.global_position) > 2.4:
			continue
		if index == 1 and not mechanisms[0].is_activated:
			notice.emit("Mechanism A has to go first - B is dead until it does.", "fail")
			return true
		mechanism.activate()
		rule_shift.note_progress("mechanism_%d" % index)
		return true
	return false


func is_solved() -> bool:
	return rule_shift != null and rule_shift.finished


func state_name() -> String:
	return rule_shift.state_name() if rule_shift != null else "INITIAL_STATE"


func storm_walk_position() -> Vector3:
	return _anchor + _lane * 6.4 + Vector3(0.0, 4.0, 0.0)


func mirror_route_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for platform in mirror_platforms:
		points.append(platform.global_position)
	return points


func _drive_platforms(delta: float) -> void:
	for index in moving_platforms.size():
		var platform := moving_platforms[index]
		if not is_instance_valid(platform):
			continue
		_moving_phases[index] = _moving_phases[index] + delta * _moving_speeds[index]
		var blend := (sin(_moving_phases[index]) + 1.0) * 0.5
		platform.position = _moving_origins[index] + _moving_offsets[index] * blend
	for index in mirror_platforms.size():
		var mirror := mirror_platforms[index]
		if not is_instance_valid(mirror):
			continue
		mirror.position.y = mirror.get_meta("home_y", mirror.position.y) \
				+ sin(_time * 1.4 + float(index)) * 0.18


func _drive_blade(delta: float) -> void:
	_blade_damage_cooldown = maxf(0.0, _blade_damage_cooldown - delta)
	if _blade == null or not is_instance_valid(_blade):
		return
	_blade.rotation.y += delta * 1.6
	if _player == null or not is_instance_valid(_player):
		return
	if _blade_damage_cooldown > 0.0:
		return
	if _blade.global_position.distance_to(_player.global_position) > 2.1:
		return
	_blade_damage_cooldown = 1.4
	if _player.has_method("take_damage"):
		_player.call("take_damage", 1.5, _blade.global_position, "fortress_blade")
	notice.emit("Mind the frost blade - it sweeps the hall.", "objective")


func _set_pillars(lit: bool) -> void:
	for node in find_children("FortressRune*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		if material == null:
			continue
		material.albedo_color = Color("#eaffff") if lit else Color("#3d5f8c")
		material.emission = Color("#9ff3ff") if lit else Color("#26415f")
		material.emission_energy_multiplier = 2.0 if lit else 0.35


func _set_blocker(closed: bool) -> void:
	if blocker == null:
		return
	blocker.position.y = blocker.get_meta("home_y", blocker.position.y) + (0.0 if closed else -2.8)
	for node in blocker.find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", not closed)
	blocker.visible = closed
	if closed:
		Audio.play("res://sounds/land.ogg")


## Mirror platforms only exist in the mirror dimension, and only after the change.
func _set_powered(powered: bool) -> void:
	for platform in mirror_platforms:
		if powered:
			platform.add_to_group("mirror_dimension")
		elif platform.is_in_group("mirror_dimension"):
			platform.remove_from_group("mirror_dimension")
	if _main != null and _main.has_method("_apply_dimension_visibility"):
		_main.call("_apply_dimension_visibility")


func _build() -> void:
	add_child(_make_pad("FortressShiftShore", _anchor))
	# Two mechanisms: A on the near side, B up on the far ledge.
	var mechanism_a := FrozenMechanism.new()
	mechanism_a.name = "FortressMechanismA"
	mechanism_a.mechanism_name = "Fortress Mechanism A"
	mechanism_a.position = _anchor + _across * 2.4 + Vector3(0.0, 0.35, 0.0)
	add_child(mechanism_a)
	var mechanism_b := FrozenMechanism.new()
	mechanism_b.name = "FortressMechanismB"
	mechanism_b.mechanism_name = "Fortress Mechanism B"
	mechanism_b.position = _anchor + _lane * 9.0 + _across * -3.2 + Vector3(0.0, 3.15, 0.0)
	add_child(mechanism_b)
	mechanisms = [mechanism_a, mechanism_b]
	# The marked gravity section: a rune slab plus four pillars, walled to a box.
	gravity_zone = Area3D.new()
	gravity_zone.name = "FortressGravityRunes"
	gravity_zone.position = _anchor + _lane * 3.4 + Vector3(0.0, 1.1, 0.0)
	gravity_zone.collision_layer = 0
	gravity_zone.collision_mask = 1
	gravity_zone.set_script(preload("res://scripts/anti_gravity_zone.gd"))
	gravity_zone.set("monitoring", false)
	var zone_shape := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(2.4, 4.6, 2.4)
	zone_shape.shape = zone_box
	gravity_zone.add_child(zone_shape)
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var pillar := MeshInstance3D.new()
		pillar.name = "FortressRune"
		var pillar_mesh := BoxMesh.new()
		pillar_mesh.size = Vector3(0.18, 3.4, 0.18)
		pillar.mesh = pillar_mesh
		pillar.position = Vector3(corner.x * 1.2, 1.1, corner.y * 1.2)
		pillar.material_override = _emissive(Color("#3d5f8c"), 0.35)
		gravity_zone.add_child(pillar)
	add_child(gravity_zone)
	# Upper landing pad the rune shaft lifts the player to, reachable from B's ledge.
	add_child(_make_pad("FortressUpperLedge", _anchor + _lane * 6.4 + Vector3(0.0, 4.0, 0.0)))
	add_child(_make_pad("FortressFarLedge", _anchor + _lane * 9.0 + _across * -3.2 + Vector3(0.0, 3.0, 0.0)))
	# Moving platforms: the original route to A.
	for index in 2:
		var platform := AnimatableBody3D.new()
		platform.name = "FortressMovingPlatform_%d" % index
		platform.sync_to_physics = true
		var origin := _anchor + _lane * (1.6 + float(index) * 2.4) + Vector3(0.0, 0.55, 0.0)
		platform.position = origin
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.9, 0.36, 1.9)
		visual.mesh = mesh
		visual.position.y = 0.18
		visual.material_override = _emissive(Color("#a9efff"), 0.5)
		platform.add_child(visual)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.9, 0.36, 1.9)
		shape.shape = box
		shape.position.y = 0.18
		platform.add_child(shape)
		add_child(platform)
		moving_platforms.append(platform)
		_moving_origins.append(origin)
		_moving_phases.append(float(index) * 1.5)
	# Mirror-dimension route: four platforms that phase in after the change.
	for index in 4:
		var platform := AnimatableBody3D.new()
		platform.name = "FortressMirrorPlatform_%d" % index
		platform.sync_to_physics = true
		var origin := _anchor + _lane * (4.6 + float(index) * 1.5) + _across * (2.6 + float(index) * 0.3) + Vector3(0.0, 1.4 + float(index) * 0.55, 0.0)
		platform.position = origin
		platform.set_meta("home_y", origin.y)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.7, 0.3, 1.7)
		visual.mesh = mesh
		visual.position.y = 0.15
		var material := _emissive(Color("#c88bff"), 1.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.78, 0.6, 1.0, 0.72)
		visual.material_override = material
		platform.add_child(visual)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.7, 0.3, 1.7)
		shape.shape = box
		shape.position.y = 0.15
		platform.add_child(shape)
		add_child(platform)
		mirror_platforms.append(platform)
	# The slab that walls off the old corridor once the fortress breaks.
	blocker = StaticBody3D.new()
	blocker.name = "FortressBlocker"
	blocker.position = _anchor + _lane * 2.0 + _across * -2.6 + Vector3(0.0, 0.9, 0.0)
	blocker.set_meta("home_y", blocker.position.y)
	var blocker_visual := MeshInstance3D.new()
	var blocker_mesh := BoxMesh.new()
	blocker_mesh.size = Vector3(0.4, 3.6, 2.6)
	blocker_visual.mesh = blocker_mesh
	blocker_visual.material_override = _emissive(Color("#8cd6ff"), 0.5)
	blocker.add_child(blocker_visual)
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.4, 3.6, 2.6)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	add_child(blocker)
	# A frost blade sweeping the hall: the "moving obstacle" of the fortress.
	_blade = AnimatableBody3D.new()
	_blade.name = "FortressFrostBlade"
	_blade.sync_to_physics = false
	_blade.position = _anchor + _lane * 5.4 + Vector3(0.0, 0.95, 0.0)
	var blade_visual := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(4.4, 0.22, 0.3)
	blade_visual.mesh = blade_mesh
	blade_visual.material_override = _emissive(Color("#bff4ff"), 0.9)
	_blade.add_child(blade_visual)
	var blade_shape := CollisionShape3D.new()
	var blade_box := BoxShape3D.new()
	blade_box.size = Vector3(4.4, 0.22, 0.3)
	blade_shape.shape = blade_box
	_blade.add_child(blade_shape)
	add_child(_blade)
	# The fortress gate the two mechanisms open.
	fortress_gate = PuzzleGate.new()
	fortress_gate.name = "FortressGate"
	fortress_gate.position = _anchor + _lane * 9.0 + _across * -3.2 + Vector3(0.0, 1.5, 1.6)
	var gate_visual := MeshInstance3D.new()
	var gate_mesh := BoxMesh.new()
	gate_mesh.size = Vector3(3.2, 2.4, 0.3)
	gate_visual.mesh = gate_mesh
	gate_visual.material_override = _emissive(Color("#9fe8ff"), 1.0)
	fortress_gate.add_child(gate_visual)
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(3.2, 2.4, 0.3)
	gate_shape.shape = gate_box
	fortress_gate.add_child(gate_shape)
	add_child(fortress_gate)
	# Mechanism C sits at the top of the fortress, reached along the storm walk.
	var mechanism_c := FrozenMechanism.new()
	mechanism_c.name = "FortressMechanismC"
	mechanism_c.mechanism_name = "Fortress Mechanism C"
	mechanism_c.position = _anchor + _lane * 9.6 + _across * 1.2 + Vector3(0.0, 7.0, 0.0)
	add_child(mechanism_c)
	mechanisms.append(mechanism_c)
	add_child(_make_pad("FortressTopLedge", _anchor + _lane * 9.6 + _across * 1.2 + Vector3(0.0, 6.6, 0.0)))
	# The storm walk: three platforms that warn, break away and reform.
	for index in 3:
		var platform := AnimatableBody3D.new()
		platform.name = "FortressStormPlatform_%d" % index
		platform.sync_to_physics = true
		var home := _anchor + _lane * (6.6 + float(index) * 1.05) + _across * (0.5 + float(index) * 0.35) \
				+ Vector3(0.0, 4.9 + float(index) * 0.6, 0.0)
		platform.position = home
		platform.set_meta("home", home)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.8, 0.3, 1.8)
		visual.mesh = mesh
		visual.position.y = 0.15
		var material := _emissive(Color("#cfeaff"), 0.6)
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		visual.material_override = material
		platform.add_child(visual)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 0.3, 1.8)
		shape.shape = box
		shape.position.y = 0.15
		platform.add_child(shape)
		add_child(platform)
		storm_platforms.append(platform)
		storm_timers.append(-1.0)
		storm_solid.append(true)
	# The gust that sweeps the storm walk.
	gust = Area3D.new()
	gust.name = "FortressFrostGust"
	gust.collision_layer = 0
	gust.collision_mask = 1
	gust.position = _anchor + _lane * 8.2 + Vector3(0.0, 5.7, 0.0)
	var spray := MeshInstance3D.new()
	spray.name = "GustSpray"
	var spray_mesh := CylinderMesh.new()
	spray_mesh.top_radius = 0.2
	spray_mesh.bottom_radius = 1.5
	spray_mesh.height = 2.6
	spray.mesh = spray_mesh
	spray.position.y = 1.2
	var spray_material := StandardMaterial3D.new()
	spray_material.albedo_color = Color(0.86, 0.95, 1.0, 0.5)
	spray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray_material.emission_enabled = true
	spray_material.emission = Color("#cdf3ff")
	spray_material.emission_energy_multiplier = 1.1
	spray.material_override = spray_material
	gust.add_child(spray)
	gust.visible = false
	add_child(gust)


func _make_pad(pad_name: String, where: Vector3) -> StaticBody3D:
	var pad := StaticBody3D.new()
	pad.name = pad_name
	pad.position = where
	var size := Vector3(3.2, 0.18, 3.2)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _emissive(Color("#b9cde4"), 0.3)
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