extends Node3D
class_name SealApproach

## Puzzle 6 - THE FOUR FROZEN SEALS, the approach to the last one.
##
## Initial rules: the shrine that guards the fourth seal is dormant and the platform
## chain leading out to it is dark and intangible ("phase ghosts" of both
## dimensions). The player is told plainly that the seals come first.
##
## Mid-puzzle rule change (the corruption's last trick, once the third seal is lit):
## the shrine wakes. The chain powers up as pairs of twins - one platform of each
## pair exists in the Material Dimension, its twin somewhere else in the Mirror
## Dimension - so the player has to shift dimension mid-crossing to keep going.
## The dimension timer is kept topped up while the cross is in progress, so the
## shift can never expire under the player's feet inside the finale.

signal completed
signal notice(text: String, tone: String)

var rule_shift: RuleShift
var platform_pairs: Array[Dictionary] = []
var shrine: Node3D
var _shrine_material: StandardMaterial3D
var _anchor := Vector3.ZERO
var _lane := Vector3.FORWARD
var _across := Vector3.RIGHT
var _pedestal := Vector3.ZERO
var _main: Node
var _time := 0.0
var _player: Node3D
var _on_first_platform := false
var _reached_pedestal := false
var _powered := false
var _countdown := 0.0


func configure(anchor: Vector3, lane: Vector3, across: Vector3, main: Node) -> void:
	_anchor = anchor
	_lane = lane.normalized()
	_across = across.normalized()
	_main = main
	_pedestal = _anchor + _lane * 9.6
	# Laid out in world coordinates: the site node stays at the origin.
	position = Vector3.ZERO
	_build()
	rule_shift = RuleShift.new()
	rule_shift.name = "RuleShift"
	rule_shift.position = _anchor + Vector3(0.0, 0.2, 0.0)
	add_child(rule_shift)
	rule_shift.configure(
		"mirror_crossing",
		"THE MIRROR CROSSING",
		2,
		1,
		_apply_rules,
		"THE CROSSING HAS SPLIT BETWEEN DIMENSIONS!",
		"EACH PLATFORM NOW EXISTS IN ONLY ONE DIMENSION - SHIFT WITH Q",
		3.2)
	rule_shift.initial_objective = "a dormant shrine guards the crossing; only later will its path wake"
	rule_shift.new_objective = "ride the material platforms, shift dimension for their mirror twins"
	rule_shift.notice.connect(func(text: String, tone: String): notice.emit(text, tone))
	rule_shift.completed.connect(func(_name: String):
		notice.emit("THE MIRROR CROSSING IS CLEAR.", "complete")
		completed.emit()
	)
	_apply_rules(false)
	rule_shift.restore()


func _apply_rules(shifted: bool) -> void:
	_powered = shifted
	if not shifted:
		_set_pairs_in_group(false)
		for entry in platform_pairs:
			_dress_pair(entry, false)
		_shrine_material.albedo_color = Color("#4a5f86")
		_shrine_material.emission = Color("#2a3f60")
		_shrine_material.emission_energy_multiplier = 0.4
		return
	for entry in platform_pairs:
		_dress_pair(entry, true)
	_set_pairs_in_group(true)
	_shrine_material.albedo_color = Color("#eaffff")
	_shrine_material.emission = Color("#8fe8ff")
	_shrine_material.emission_energy_multiplier = 2.4
	Audio.play("res://sounds/coin.ogg")
	if _main != null and _main.has_method("grant_dimension_shifts"):
		_main.call("grant_dimension_shifts", 3)


## Only the pairs' platforms join the dimension groups; before the change they are
## plain, intangible scenery in both dimensions.
func _set_pairs_in_group(active: bool) -> void:
	for entry in platform_pairs:
		for platform in [entry["material"], entry["mirror"]]:
			var node := platform as AnimatableBody3D
			if not is_instance_valid(node):
				continue
			if not active:
				if node.is_in_group("material_dimension"):
					node.remove_from_group("material_dimension")
				if node.is_in_group("mirror_dimension"):
					node.remove_from_group("mirror_dimension")
				continue
			var group := "material_dimension" if entry["material"] == node else "mirror_dimension"
			if not node.is_in_group(group):
				node.add_to_group(group)
	if _main != null and _main.has_method("_apply_dimension_visibility"):
		_main.call("_apply_dimension_visibility")


## Dormant pairs are ghostly and have no collision; powered pairs are solid ice.
func _dress_pair(entry: Dictionary, powered: bool) -> void:
	for key in ["material", "mirror"]:
		var platform := entry[key] as AnimatableBody3D
		if not is_instance_valid(platform):
			continue
		for node in platform.find_children("*", "CollisionShape3D", true, false):
			(node as CollisionShape3D).set_deferred("disabled", not powered)
		var visual := platform.find_child("PlatformBody", true, false) as MeshInstance3D
		if visual != null:
			var material := visual.material_override as StandardMaterial3D
			if material != null:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if not powered else BaseMaterial3D.TRANSPARENCY_DISABLED
				material.albedo_color = Color(0.62, 0.72, 0.86, 0.35) if not powered \
						else (Color("#bff0ff") if key == "material" else Color(0.78, 0.62, 1.0))


func _process(delta: float) -> void:
	_time += delta
	for entry in platform_pairs:
		var material := entry["material"] as AnimatableBody3D
		var mirror := entry["mirror"] as AnimatableBody3D
		if is_instance_valid(material):
			material.position.y = material.get_meta("home_y", material.position.y) + sin(_time * 1.2) * 0.16
		if is_instance_valid(mirror):
			mirror.position.y = mirror.get_meta("home_y", mirror.position.y) + sin(_time * 1.2 + PI) * 0.16
	if shrine != null:
		shrine.rotate_y(delta * (0.7 if _powered else 0.15))
	if rule_shift == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if not rule_shift.introduced and _anchor.distance_to(_player.global_position) < 12.0:
		rule_shift.introduced = true
		rule_shift.introduce()
	_keep_shift_alive(delta)
	if rule_shift.finished or not _powered:
		return
	_track_crossing()


## The corruption keeps reality unstable here: while the player is on the cross,
## the mirror shift never times out under them.
func _keep_shift_alive(delta: float) -> void:
	if not _powered or _anchor.distance_to(_player.global_position) > 18.0:
		return
	_countdown -= delta
	if _countdown > 0.0:
		return
	_countdown = 0.5
	if _main != null and _main.has_method("extend_shift"):
		_main.call("extend_shift", 4.0)
	if _main != null and _main.has_method("grant_dimension_shifts"):
		_main.call("grant_dimension_shifts", 1)


func _track_crossing() -> void:
	if not _on_first_platform:
		for entry in platform_pairs:
			for key in ["material", "mirror"]:
				var platform := entry[key] as AnimatableBody3D
				if not is_instance_valid(platform):
					continue
				if _player.global_position.distance_to(platform.global_position) < 1.8:
					_on_first_platform = true
					rule_shift.note_progress("crossing_started")
					return
	if not _reached_pedestal and _player.global_position.distance_to(_pedestal) < 2.6:
		_reached_pedestal = true
		if rule_shift.steps_done >= 1:
			rule_shift.note_progress("pedestal_reached")
		else:
			rule_shift.note_progress("shortcut")
			rule_shift.note_progress("pedestal_reached")


func pedestal_position() -> Vector3:
	return _pedestal


func is_powered() -> bool:
	return _powered


func is_solved() -> bool:
	return rule_shift != null and rule_shift.finished


func state_name() -> String:
	return rule_shift.state_name() if rule_shift != null else "INITIAL_STATE"


func _build() -> void:
	add_child(_make_pad("SealApproachShore", _anchor))
	add_child(_make_pad("SealApproachPedestalPad", _pedestal + Vector3(0.0, 0.1, 0.0)))
	# The shrine: the corruption's own marker over the cross.
	var shrine_node := Node3D.new()
	shrine_node.name = "SealShrine"
	shrine_node.position = _anchor + _lane * 4.4 + _across * -3.4 + Vector3(0.0, 0.6, 0.0)
	var plinth := MeshInstance3D.new()
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 0.5
	plinth_mesh.bottom_radius = 0.66
	plinth_mesh.height = 1.0
	plinth.mesh = plinth_mesh
	plinth.position.y = 0.5
	plinth.material_override = _emissive(Color("#8fb6e0"), 0.3)
	shrine_node.add_child(plinth)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.42
	core_mesh.height = 0.84
	core.mesh = core_mesh
	core.position.y = 1.5
	_shrine_material = _emissive(Color("#4a5f86"), 0.4)
	core.material_override = _shrine_material
	shrine_node.add_child(core)
	for index in 3:
		var spike := MeshInstance3D.new()
		var spike_mesh := CylinderMesh.new()
		spike_mesh.top_radius = 0.0
		spike_mesh.bottom_radius = 0.1
		spike_mesh.height = 0.7 + float(index) * 0.16
		spike.mesh = spike_mesh
		spike.position = Vector3(cos(float(index) * TAU / 3.0) * 0.42, 1.9, sin(float(index) * TAU / 3.0) * 0.42)
		spike.rotation.z = cos(float(index) * TAU / 3.0) * 0.5
		spike.material_override = _shrine_material
		shrine_node.add_child(spike)
	shrine = shrine_node
	add_child(shrine_node)
	# Four pairs of dimension twins spanning the cross to the pedestal.
	for index in 4:
		var distance := 2.6 + float(index) * 1.75
		var material_point := _anchor + _lane * distance + _across * (1.1 if index % 2 == 0 else -1.1) + Vector3(0.0, 0.6, 0.0)
		var mirror_point := _anchor + _lane * (distance + 0.85) + _across * (-1.9 if index % 2 == 0 else 1.9) + Vector3(0.0, 1.5 + float(index) * 0.35, 0.0)
		var material_platform := _make_platform("SealPair_%d_Material" % index, material_point, Color("#bff0ff"))
		var mirror_platform := _make_platform("SealPair_%d_Mirror" % index, mirror_point, Color(0.78, 0.62, 1.0))
		add_child(material_platform)
		add_child(mirror_platform)
		platform_pairs.append({"material": material_platform, "mirror": mirror_platform})


func _make_platform(platform_name: String, where: Vector3, tint: Color) -> AnimatableBody3D:
	var platform := AnimatableBody3D.new()
	platform.name = platform_name
	platform.position = where
	platform.set_meta("home_y", where.y)
	platform.sync_to_physics = true
	var visual := MeshInstance3D.new()
	visual.name = "PlatformBody"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 0.3, 1.9)
	visual.mesh = mesh
	var material := _emissive(tint, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.35)
	visual.material_override = material
	platform.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.3, 1.9)
	shape.shape = box
	platform.add_child(shape)
	# A phase marker so the player can tell which dimension each twin belongs to.
	var marker := MeshInstance3D.new()
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.5
	marker_mesh.outer_radius = 0.58
	marker.mesh = marker_mesh
	marker.rotation.x = PI / 2.0
	marker.position.y = 0.24
	marker.material_override = _emissive(tint, 1.4)
	platform.add_child(marker)
	return platform


func _make_pad(pad_name: String, where: Vector3) -> StaticBody3D:
	var pad := StaticBody3D.new()
	pad.name = pad_name
	pad.position = where
	var size := Vector3(3.2, 0.18, 3.2)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _emissive(Color("#cfe4f6"), 0.35)
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