extends Node3D
class_name FrozenSwitchPuzzle

## Puzzle 1 - THE FROZEN SWITCH (Frozen Arrival -> Crystal Snowfields).
##
## Initial rules: three ice switches lie along a frozen causeway. Activate them
## in order (I, II, III); each lights one section of the ice bridge and opens the
## way to the far ice island.
##
## Mid-puzzle rule change: after the second switch, Malakar's corruption cuts the
## first switch's lamp. A frozen crystal pushes up out of the snow nearby - taking
## it restores switch I - and the bridge swings to a new direction (a second
## island across the other axis). The remaining order becomes III, then I.
##
## Failing the order resets the lamps (the corrupted rules stay in force and the
## crystal, once taken, stays taken) so the puzzle can always be retried.

const SEGMENT_LENGTH := 3.0
const SEGMENT_GAP := 0.0
const SWITCH_SPACING := 2.1
const ISLAND_DISTANCE := 11.6

signal completed
signal notice(text: String, tone: String)

var rule_shift: RuleShift
var switches: Array[Node3D] = []
var sections: Array[StaticBody3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _switch_materials: Array[StandardMaterial3D] = []
var _lit: Array[bool] = [false, false, false]
var _carried_lit: Array[bool] = [false, false, false]
var _order: Array[int] = [0, 1, 2]
var _next_step := 0
var _crystal: Node3D
var _crystal_visual: Node3D
var _crystal_collected := false
var _dead_switch := false
var _origin := Vector3.ZERO
var _lane := Vector3.FORWARD
var _across := Vector3.RIGHT
var _reaim_pending := false
var _reaim_clock := 0.0
var _player: Node3D
var _time := 0.0

const PLAYER_GROUP := "player"


func configure(anchor: Vector3, lane: Vector3, across: Vector3) -> void:
	_origin = anchor
	_lane = lane.normalized()
	_across = across.normalized()
	# Children are laid out in world coordinates, so the site node stays at the
	# origin and only the beacon is offset to the site itself.
	position = Vector3.ZERO
	_build()
	rule_shift = RuleShift.new()
	rule_shift.name = "RuleShift"
	rule_shift.position = _origin + Vector3(0.0, 0.2, 0.0)
	add_child(rule_shift)
	rule_shift.configure(
		"frozen_switch",
		"THE FROZEN SWITCH",
		4,
		2,
		_apply_rules,
		"NEW RULE: SWITCH I IS DEAD!",
		"A CRYSTAL CAN RESTORE IT - THE ICE BRIDGE IS TURNING!",
		2.6)
	rule_shift.initial_objective = "activate the three ice switches in order: I, II, III"
	rule_shift.new_objective = "take the revealed crystal to restore switch I, then light III and I"
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	rule_shift.completed.connect(func(_name: String):
		_open_all_sections()
		notice.emit("THE FROZEN SWITCH: the causeway is open to the ice islands.", "complete")
		completed.emit()
	)
	_apply_rules(false)
	rule_shift.restore()


func _apply_rules(stage: int) -> void:
	if stage <= 0:
		_lit = [false, false, false]
		_carried_lit = [false, false, false]
		_order = [0, 1, 2]
		_next_step = 0
		_dead_switch = false
		_crystal_visual.visible = false
		_place_bridge(_lane)
		for index in sections.size():
			_set_section_open(index, false)
		for index in switches.size():
			_light_switch(index, false)
		return
	# Corrupted rules: switch I is dead until the crystal is taken, the bridge
	# swings to the second island, and the order continues III then I.
	_carried_lit = _lit.duplicate()
	_dead_switch = not _crystal_collected
	_carried_lit[0] = false
	_lit = _carried_lit.duplicate()
	_order = [2, 0]
	_next_step = 0
	_crystal_visual.visible = not _crystal_collected
	_reaim_pending = true
	_reaim_clock = 0.0
	for index in switches.size():
		_light_switch(index, _lit[index])


func _process(delta: float) -> void:
	_time += delta
	if _crystal_visual != null:
		_crystal_visual.position.y = 0.35 + sin(_time * 2.2) * 0.08
		_crystal_visual.rotate_y(delta * 0.9)
	if _reaim_pending:
		_reaim_clock += delta
		if _reaim_clock > 5.0 or _bridge_clear_of_player():
			_reaim_pending = false
			_place_bridge(_across)
			notice.emit("The ice bridge swings to the new island.", "changed")
	if rule_shift == null or rule_shift.finished:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node3D
	if _player != null and not rule_shift.introduced and _origin.distance_to(_player.global_position) < 9.0:
		rule_shift.introduced = true
		rule_shift.introduce()


## The player can interact with a nearby switch, or with the revealed crystal.
func try_activate(player: Node3D) -> bool:
	if rule_shift == null:
		return false
	if _crystal_visual != null and _crystal_visual.visible and not _crystal_collected:
		if _crystal.global_position.distance_to(player.global_position) <= 2.4:
			_collect_crystal()
			return true
	for index in switches.size():
		if switches[index].global_position.distance_to(player.global_position) > 2.4:
			continue
		return _press_switch(index)
	return false


func _press_switch(index: int) -> bool:
	if rule_shift.finished:
		return false
	if _lit[index]:
		notice.emit("Switch %s is already lit." % _roman(index), "objective")
		return true
	if index == 0 and _dead_switch:
		notice.emit("Switch I is dead. Take the revealed crystal to restore it.", "fail")
		return true
	var expected: int = _order[_next_step] if _next_step < _order.size() else -1
	if index != expected:
		rule_shift.fail("Wrong switch - the frozen causeway resets!")
		return true
	_lit[index] = true
	_light_switch(index, true)
	_set_section_open(index, true)
	_next_step += 1
	Audio.play("res://sounds/coin.ogg")
	notice.emit("Switch %s lit (%d/%d)." % [_roman(index), _next_step, _order.size()], "objective")
	rule_shift.note_progress("switch_%d" % index)
	return true


func _collect_crystal() -> void:
	_crystal_collected = true
	_crystal_visual.visible = false
	_dead_switch = false
	Audio.play("res://sounds/coin.ogg")
	FrozenAudio.cue(self, "shift", 0.9, -14.0)
	notice.emit("FROZEN CRYSTAL TAKEN - switch I is restored. Light III, then I.", "objective")


## Anything the player could be standing on: if they are, the swing waits.
func _bridge_clear_of_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return true
	for section in sections:
		if section.global_position.distance_to(_player.global_position) < 3.2:
			return false
	return true


func island_positions() -> Array[Vector3]:
	return [_origin + _lane * ISLAND_DISTANCE, _origin + _across * ISLAND_DISTANCE]


func _build() -> void:
	# The switches stand 2.6 apart along the shore, so each one is unambiguously
	# the switch the player is standing at.
	add_child(_make_pad("FrozenSwitchShore", _origin, Vector3(6.6, 0.16, 3.4)))
	var shelf := _origin + _across * -5.4 + _lane * 0.2
	add_child(_make_pad("FrozenCrystalShelf", shelf, Vector3(2.6, 0.16, 2.6)))
	for index in 3:
		var post := _make_switch(index, _origin + _lane * 1.4 + _across * (float(index) * 2.6 - 2.6))
		switches.append(post)
		add_child(post)
	for index in 3:
		var section := _make_section("IceBridgeSection_%d" % index, index)
		sections.append(section)
		add_child(section)
	_place_bridge(_lane)
	_crystal = Node3D.new()
	_crystal.name = "FrozenRevealCrystal"
	_crystal.position = shelf
	add_child(_crystal)
	_crystal_visual = Node3D.new()
	_crystal_visual.position.y = 0.35
	_crystal.add_child(_crystal_visual)
	for index in 3:
		var shard := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.24 - float(index) * 0.05
		cone.height = 1.0 - float(index) * 0.18
		shard.mesh = cone
		shard.position = Vector3(float(index - 1) * 0.22, 0.0, float(index % 2) * 0.12)
		shard.rotation.z = float(index - 1) * 0.22
		shard.material_override = _emissive(Color("#9fe8ff"), 1.5)
		_crystal_visual.add_child(shard)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#8fe0ff")
	glow.light_energy = 1.4
	glow.omni_range = 4.5
	glow.position.y = 1.0
	_crystal_visual.add_child(glow)
	_crystal_visual.visible = false
	add_child(_make_pad("FrozenBridgeIsland", _origin + _lane * ISLAND_DISTANCE))
	add_child(_make_pad("FrozenBridgeIslandTwo", _origin + _across * ISLAND_DISTANCE))


func _make_pad(pad_name: String, where: Vector3, size := Vector3(3.6, 0.16, 3.6)) -> StaticBody3D:
	var pad := StaticBody3D.new()
	pad.name = pad_name
	pad.position = where
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _emissive(Color("#cfeeff"), 0.3)
	pad.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	pad.add_child(shape)
	return pad


func _make_switch(index: int, where: Vector3) -> Node3D:
	var post := Node3D.new()
	post.name = "FrozenSwitch_%s" % _roman(index)
	post.position = where
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.36
	base_mesh.bottom_radius = 0.46
	base_mesh.height = 0.3
	base.mesh = base_mesh
	base.position.y = 0.15
	base.material_override = _emissive(Color("#1b3f74"), 0.15)
	post.add_child(base)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.13
	shaft_mesh.bottom_radius = 0.16
	shaft_mesh.height = 0.95
	shaft.mesh = shaft_mesh
	shaft.position.y = 0.72
	shaft.material_override = _emissive(Color("#9fd6ff"), 0.25)
	post.add_child(shaft)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := CylinderMesh.new()
	lamp_mesh.top_radius = 0.0
	lamp_mesh.bottom_radius = 0.26
	lamp_mesh.height = 0.7
	lamp.mesh = lamp_mesh
	lamp.position.y = 1.5
	var lamp_material := _emissive(Color("#2b6f96"), 0.5)
	lamp.material_override = lamp_material
	_lamps.append(lamp_material)
	post.add_child(lamp)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.6
	ring.mesh = ring_mesh
	ring.position.y = 0.32
	ring.rotation.x = PI / 2.0
	var ring_material := _emissive(Color("#4f8fd0"), 0.4)
	ring.material_override = ring_material
	_switch_materials.append(ring_material)
	post.add_child(ring)
	post.set_meta("index", index)
	return post


func _make_section(section_name: String, index: int) -> StaticBody3D:
	var section := StaticBody3D.new()
	section.name = section_name
	var size := Vector3(1.0, 0.14, SEGMENT_LENGTH)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _emissive(Color("#a9efff"), 1.0)
	section.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	section.add_child(shape)
	section.set_meta("index", index)
	return section


## Lay the three sections end to end along an axis, starting at the shore.
func _place_bridge(axis: Vector3) -> void:
	var yaw := atan2(axis.x, axis.z)
	for index in sections.size():
		var section := sections[index]
		var distance := 3.0 + float(index) * (SEGMENT_LENGTH + SEGMENT_GAP)
		var was_open := _lit[index] and rule_shift != null and rule_shift.shifted
		section.position = _origin + axis * distance + Vector3(0.0, 0.5, 0.0)
		section.rotation.y = yaw
		if not was_open:
			_set_section_open(index, false)


func _set_section_open(index: int, open: bool) -> void:
	var section := sections[index]
	for node in section.find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", not open)
	for node in section.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = open
	section.visible = open


func _open_all_sections() -> void:
	for index in sections.size():
		_set_section_open(index, true)


func _light_switch(index: int, lit: bool) -> void:
	var lamp := _lamps[index]
	lamp.albedo_color = Color("#eaffff") if lit else Color("#2b6f96")
	lamp.emission = Color("#b7f7ff") if lit else Color("#2b6f96")
	lamp.emission_energy_multiplier = 2.4 if lit else 0.5
	var ring: StandardMaterial3D = _switch_materials[index]
	ring.emission_energy_multiplier = 1.6 if lit else 0.4


func _roman(index: int) -> String:
	return "I" if index == 0 else ("II" if index == 1 else "III")


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.28
	material.emission_enabled = energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func is_solved() -> bool:
	return rule_shift != null and rule_shift.finished


func state_name() -> String:
	return rule_shift.state_name() if rule_shift != null else "INITIAL_STATE"