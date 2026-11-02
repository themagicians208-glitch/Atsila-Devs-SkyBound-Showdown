extends Node3D
class_name FrozenLakeCycle

## Puzzle 4 - THE FROZEN LAKE.
##
## Initial rules: the lake is frozen over and the six floes are solid, so crossing
## is a simple run. A shore switch opens the exit on the far bank.
##
## Mid-puzzle rule change: pressing the shore switch starts the lake breathing.
## From then on the floes freeze and thaw in a wave - solid for a while, then a
## 1.2 s warning (the floe shakes, cracks and flashes), then it sinks under the
## water for two seconds and comes back. Neighbours are always half a cycle apart,
## so there is always a route; the player just has to read the wave and take it.
##
## Frost geysers between the floes spray on a timer. They are survivable without
## any ability, but the Ice Shield (K) eats the spray completely - the puzzle's
## own hint says so the first time one erupts.

const FLOE_COUNT := 6
const SOLID_TIME := 4.2
const WARNING_TIME := 1.2
const SUBMERGED_TIME := 2.0
const CYCLE := SOLID_TIME + WARNING_TIME + SUBMERGED_TIME
const FLOE_SPACING := 2.9
const ISLAND_DISTANCE := 19.0
const GEYSER_PERIOD := 4.0
const SLIPPERY_SCRIPT := preload("res://scripts/slippery_zone.gd")

signal completed
signal notice(text: String, tone: String)

var rule_shift: RuleShift
var floes: Array[Node3D] = []
var cycle_switch: Node3D
var geysers: Array[Area3D] = []
var _floe_shapes: Array[CollisionShape3D] = []
var _floe_visuals: Array[MeshInstance3D] = []
var _floe_materials: Array[StandardMaterial3D] = []
var _floe_phases: Array[float] = []
var _floe_state: Array[int] = []   # 0 solid, 1 warned, 2 submerged
var _shore := Vector3.ZERO
var _lane := Vector3.FORWARD
var _across := Vector3.RIGHT
var _far_shore: Node3D
var _switch_material: StandardMaterial3D
var _time := 0.0
var _player: Node3D
var _hint_shown := false
var _reached_far := false
## Stage one drifts two blocks and slows nothing; stage two fixes them, slicks two
## others and slows the freezing wave so the re-frozen route can be read.
var _drift: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _wave_speed := 1.0
var _energy_mechanism: Node3D
var _mechanism_material: StandardMaterial3D
var _slick_zones: Array[Area3D] = []


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
		"frozen_lake",
		"THE FROZEN LAKE",
		3,
		[1, 2],
		_apply_rules,
		"THE FROZEN LAKE IS MELTING!",
		"ICE BLOCKS ARE DRIFTING - THE WAVE LEAVES A ROUTE",
		2.6)
	rule_shift.initial_objective = "cross the frozen lake; press the shore switch to open the far gate"
	rule_shift.new_objective = "time the freezing wave; the Ice Shield (K) wakes the frozen energy mechanism"
	rule_shift.add_stage_text(1,
		"THE LAKE IS FREEZING AGAIN!",
		"TWO BLOCKS ARE FIXED, TWO ARE SLICK - BUILD THE NEW ROUTE",
		"cross on the re-frozen blocks and reach the far shore")
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	rule_shift.completed.connect(func(_name: String):
		notice.emit("THE FROZEN LAKE CROSSED.", "complete")
		completed.emit()
	)
	_apply_rules(0)
	rule_shift.restore()


func _apply_rules(stage: int) -> void:
	if stage <= 0:
		for index in floes.size():
			_floe_state[index] = 0
			_set_floe_submerged(index, false)
			_floe_phases[index] = 0.0
			_drift[index] = 0.0
		_wave_speed = 1.0
		_switch_material.albedo_color = Color("#8fd0ff")
		_switch_material.emission = Color("#8fd0ff")
		_switch_material.emission_energy_multiplier = 0.8
		_set_slick(false)
		if _energy_mechanism != null:
			_energy_mechanism.visible = false
		return
	# Stage 1 and on: the lake breathes in a wave and two blocks come loose.
	for index in floes.size():
		_floe_phases[index] = fmod(float(index) * (CYCLE * 0.5) + float(index) / 2.0 * 0.35, CYCLE)
	_drift = [0.0, 0.0, 1.7, 0.0, -1.5, 0.0]
	_wave_speed = 1.0
	_switch_material.albedo_color = Color("#eaffff")
	_switch_material.emission = Color("#9ff3ff")
	_switch_material.emission_energy_multiplier = 2.2
	_set_slick(false)
	if _energy_mechanism != null:
		_energy_mechanism.visible = true
	if stage >= 2:
		# Stage 2: the drifting blocks lock in place, two others go slick and the
		# wave slows right down, so the new route is about footing, not timing.
		_drift = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		_wave_speed = 0.55
		_set_slick(true)


## Two blocks turn slick in the re-frozen lake: the route is fixed but slippery.
func _set_slick(enabled: bool) -> void:
	for index in _slick_zones.size():
		var zone := _slick_zones[index]
		if not is_instance_valid(zone):
			continue
		var should_be_slick := enabled and (index == 1 or index == 4)
		zone.visible = should_be_slick
		for shape in zone.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).set_deferred("disabled", not should_be_slick)


func _process(delta: float) -> void:
	_time += delta
	if rule_shift != null and rule_shift.shifted:
		for index in floes.size():
			_advance_floe(index, delta * _wave_speed)
		if _energy_mechanism != null and _energy_mechanism.visible:
			_energy_mechanism.rotate_y(delta * (0.8 if rule_shift.stage >= 2 else 0.25))
	_drive_geysers()
	if rule_shift == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if not rule_shift.introduced and _shore.distance_to(_player.global_position) < 11.0:
		rule_shift.introduced = true
		rule_shift.introduce()
	if not rule_shift.finished and not _reached_far and _far_shore != null \
			and _player.global_position.distance_to(_far_shore.global_position) < 2.8:
		_reached_far = true
		if rule_shift.steps_done >= 2:
			rule_shift.note_progress("far_shore")
		else:
			# Shortcut across: count the steps the player skipped.
			while rule_shift.steps_done < 2 and not rule_shift.finished:
				rule_shift.note_progress("shortcut")
			if not rule_shift.finished:
				rule_shift.note_progress("far_shore")


func _advance_floe(index: int, delta: float) -> void:
	_floe_phases[index] = fmod(_floe_phases[index] + delta, CYCLE)
	var phase := _floe_phases[index]
	var state := 0
	if phase >= SOLID_TIME and phase < SOLID_TIME + WARNING_TIME:
		state = 1
	elif phase >= SOLID_TIME + WARNING_TIME:
		state = 2
	if state == _floe_state[index]:
		if state == 1:
			_shake_floe(index)
		return
	_floe_state[index] = state
	match state:
		0:
			_set_floe_submerged(index, false)
			FrozenAudio.cue(self, "crack", 0.5, -20.0)
		1:
			_shake_floe(index)
			Audio.play("res://sounds/break.ogg")
			FrozenAudio.cue(self, "crack", 0.7, -16.0)
		2:
			_set_floe_submerged(index, true)


func _shake_floe(index: int) -> void:
	var floe := floes[index]
	floe.position = _floe_home(index) + Vector3(sin(_time * 30.0 + float(index)) * 0.06, 0.0, cos(_time * 26.0) * 0.05)
	var material := _floe_materials[index]
	material.emission_energy_multiplier = 1.4 + sin(_time * 18.0) * 0.5


func _floe_home(index: int) -> Vector3:
	var drift := 0.0
	if index < _drift.size():
		drift = sin(_time * 0.6 + float(index) * 1.3) * _drift[index]
	return _shore + _lane * (2.4 + float(index) * FLOE_SPACING) + _across * drift + Vector3(0.0, 0.45, 0.0)


func _set_floe_submerged(index: int, submerged: bool) -> void:
	var floe := floes[index]
	floe.position = _floe_home(index) + (Vector3(0.0, -2.6, 0.0) if submerged else Vector3.ZERO)
	_floe_shapes[index].set_deferred("disabled", submerged)
	_floe_visuals[index].rotation.z += 0.22 if submerged else -0.22
	var material := _floe_materials[index]
	if submerged:
		material.albedo_color = Color(0.36, 0.55, 0.72, 0.35)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_energy_multiplier = 0.15
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.albedo_color = Color("#bfeaff")
		material.emission_energy_multiplier = 0.55


func _drive_geysers() -> void:
	for index in geysers.size():
		var geyser := geysers[index]
		if not is_instance_valid(geyser):
			continue
		var phase := fmod(_time + float(index) * 2.1, GEYSER_PERIOD)
		var erupting := phase > GEYSER_PERIOD - 1.4
		geyser.set_meta("erupting", erupting)
		var visual := geyser.get_node_or_null("GeyserSpray") as MeshInstance3D
		if visual != null:
			visual.visible = erupting
			if erupting:
				visual.scale = Vector3(1.0, 0.7 + (phase - (GEYSER_PERIOD - 1.4)) * 1.6, 1.0)
		var light := geyser.get_node_or_null("GeyserGlow") as OmniLight3D
		if light != null:
			light.light_energy = 2.4 if erupting else 0.5
		for shape in geyser.find_children("GeyserHit", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).set_deferred("disabled", not erupting)


func try_activate(player: Node3D) -> bool:
	if _energy_mechanism != null and _energy_mechanism.visible and rule_shift.stage == 1 \
			and _energy_mechanism.global_position.distance_to(player.global_position) <= 2.6:
		if not bool(player.get("ice_shield_active")):
			notice.emit("The frozen energy mechanism needs the Ice Shield (K).", "fail")
			return true
		Audio.play("res://sounds/coin.ogg")
		FrozenAudio.cue(self, "shift", 1.0, -14.0)
		rule_shift.note_progress("energy_mechanism")
		return true
	if cycle_switch == null:
		return false
	if cycle_switch.global_position.distance_to(player.global_position) > 2.4:
		return false
	if rule_shift.shifted or rule_shift.finished:
		notice.emit("The lake is already awake.", "objective")
		return true
	Audio.play("res://sounds/coin.ogg")
	rule_shift.note_progress("lake_switch")
	return true


func _on_geyser_body_entered(body: Node3D, index: int) -> void:
	if not body.is_in_group("player"):
		return
	if not bool(geysers[index].get_meta("erupting", false)):
		return
	if body.has_method("take_damage"):
		body.call("take_damage", 1.5, geysers[index].global_position, "frost_geyser")
	if not _hint_shown:
		_hint_shown = true
		notice.emit("Ice Shield (K) blocks the frost spray.", "objective")


func is_solved() -> bool:
	return rule_shift != null and rule_shift.finished


func state_name() -> String:
	return rule_shift.state_name() if rule_shift != null else "INITIAL_STATE"


func far_shore_position() -> Vector3:
	return _shore + _lane * ISLAND_DISTANCE


func submerged_count() -> int:
	var count := 0
	for index in _floe_state.size():
		if _floe_state[index] == 2:
			count += 1
	return count


func _build() -> void:
	add_child(_make_pad("FrozenLakeShore", _shore))
	var switch_post := Node3D.new()
	switch_post.name = "FrozenLakeSwitch"
	switch_post.position = _shore + _across * 1.9 + Vector3(0.0, 0.35, 0.0)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.44
	base_mesh.height = 0.3
	base.mesh = base_mesh
	base.position.y = 0.15
	base.material_override = _emissive(Color("#1b3f74"), 0.15)
	switch_post.add_child(base)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := CylinderMesh.new()
	lamp_mesh.top_radius = 0.0
	lamp_mesh.bottom_radius = 0.26
	lamp_mesh.height = 0.75
	lamp.mesh = lamp_mesh
	lamp.position.y = 0.75
	_switch_material = _emissive(Color("#8fd0ff"), 0.8)
	lamp.material_override = _switch_material
	switch_post.add_child(lamp)
	add_child(switch_post)
	cycle_switch = switch_post
	# The lake surface itself, for the floes to sink beneath.
	var surface := MeshInstance3D.new()
	surface.name = "FrozenLakeSurface"
	var surface_mesh := BoxMesh.new()
	surface_mesh.size = Vector3(7.0, 0.06, ISLAND_DISTANCE + 4.0)
	surface.mesh = surface_mesh
	surface.position = _shore + _lane * (ISLAND_DISTANCE * 0.5) + Vector3(0.0, -0.05, 0.0)
	surface.rotation.y = atan2(_lane.x, _lane.z)
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_color = Color(0.32, 0.62, 0.86, 0.55)
	surface_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface_material.emission_enabled = true
	surface_material.emission = Color("#2f7fb8")
	surface_material.emission_energy_multiplier = 0.35
	surface.material_override = surface_material
	add_child(surface)
	for index in FLOE_COUNT:
		var floe := Node3D.new()
		floe.name = "FrozenFloe_%d" % index
		floe.position = _floe_home(index)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.3, 0.18, 2.3)
		visual.mesh = mesh
		var material := _emissive(Color("#bfeaff"), 0.55)
		visual.material_override = material
		floe.add_child(visual)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		floe.add_child(shape)
		add_child(floe)
		floes.append(floe)
		_floe_visuals.append(visual)
		_floe_shapes.append(shape)
		_floe_materials.append(material)
		_floe_state.append(0)
		_floe_phases.append(0.0)
	# Geysers sit between the floes, offset to the sides so they never cover a
	# landing spot: they punish dawdling, they do not gate the crossing.
	for index in 2:
		var geyser := Area3D.new()
		geyser.name = "FrostGeyser_%d" % index
		geyser.collision_layer = 0
		geyser.collision_mask = 1
		var hit := CollisionShape3D.new()
		hit.name = "GeyserHit"
		var hit_shape := CylinderShape3D.new()
		hit_shape.radius = 0.9
		hit_shape.height = 2.0
		hit.shape = hit_shape
		hit.position.y = 1.0
		geyser.add_child(hit)
		var spray := MeshInstance3D.new()
		spray.name = "GeyserSpray"
		var spray_mesh := CylinderMesh.new()
		spray_mesh.top_radius = 0.12
		spray_mesh.bottom_radius = 0.7
		spray_mesh.height = 2.4
		spray.mesh = spray_mesh
		spray.position.y = 1.2
		var spray_material := StandardMaterial3D.new()
		spray_material.albedo_color = Color(0.85, 0.96, 1.0, 0.6)
		spray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spray_material.emission_enabled = true
		spray_material.emission = Color("#cdf3ff")
		spray_material.emission_energy_multiplier = 1.2
		spray.material_override = spray_material
		spray.visible = false
		geyser.add_child(spray)
		var light := OmniLight3D.new()
		light.name = "GeyserGlow"
		light.light_color = Color("#a9e8ff")
		light.light_energy = 0.5
		light.omni_range = 5.0
		light.position.y = 1.0
		geyser.add_child(light)
		geyser.position = _shore + _lane * (2.4 + float(index * 3) * FLOE_SPACING + FLOE_SPACING * 0.5) \
				+ _across * (2.0 if index % 2 == 0 else -2.0) + Vector3(0.0, 0.0, 0.0)
		geyser.body_entered.connect(_on_geyser_body_entered.bind(index))
		add_child(geyser)
		geysers.append(geyser)
	_far_shore = _make_pad("FrozenLakeFarShore", far_shore_position())
	add_child(_far_shore)
	# The frozen energy mechanism the melting lake reveals: out beside the fourth
	# block, and only wakeable with the Ice Shield up.
	var mech_pad := _make_pad("FrozenLakeMechanismPad", _shore + _lane * (2.4 + 3.0 * FLOE_SPACING) + _across * 3.1)
	add_child(mech_pad)
	_energy_mechanism = Node3D.new()
	_energy_mechanism.name = "FrozenEnergyMechanism"
	_energy_mechanism.position = mech_pad.position + Vector3(0.0, 0.4, 0.0)
	var mech_base := MeshInstance3D.new()
	var mech_base_mesh := CylinderMesh.new()
	mech_base_mesh.top_radius = 0.42
	mech_base_mesh.bottom_radius = 0.55
	mech_base_mesh.height = 0.4
	mech_base.mesh = mech_base_mesh
	mech_base.position.y = 0.2
	mech_base.material_override = _emissive(Color("#1b3f74"), 0.2)
	_energy_mechanism.add_child(mech_base)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.34
	core_mesh.height = 0.68
	core.mesh = core_mesh
	core.position.y = 1.0
	_mechanism_material = _emissive(Color("#8fe8ff"), 1.5)
	core.material_override = _mechanism_material
	_energy_mechanism.add_child(core)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.6
	ring.mesh = ring_mesh
	ring.position.y = 1.0
	ring.rotation.x = PI / 2.0
	ring.material_override = _mechanism_material
	_energy_mechanism.add_child(ring)
	_energy_mechanism.visible = false
	add_child(_energy_mechanism)
	# Slick coating for the blocks that turn slippery when the lake re-freezes.
	for index in FLOE_COUNT:
		var zone := SLIPPERY_SCRIPT.new() as Area3D
		zone.name = "FrozenLakeSlick_%d" % index
		zone.collision_layer = 0
		zone.collision_mask = 1
		var zone_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.3, 1.4, 2.3)
		zone_shape.shape = box
		zone.add_child(zone_shape)
		zone.position = _floe_home(index)
		zone.visible = false
		add_child(zone)
		_slick_zones.append(zone)


func _make_pad(pad_name: String, where: Vector3) -> StaticBody3D:
	var pad := StaticBody3D.new()
	pad.name = pad_name
	pad.position = where
	var size := Vector3(3.6, 0.16, 3.6)
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