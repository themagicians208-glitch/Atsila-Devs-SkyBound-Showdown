class_name WoodsPuzzles
extends RefCounted

## Modular puzzle building blocks for Level 2: The Whispering Woods.
##
## Contains the interactive node classes for:
##   * Puzzle 1 - SleepingTreeSeed & SleepingTreeSocket (The Sleeping Tree)
##   * Puzzle 2 - SequenceTreeSwitch (The Moving Trees 1-2-3 leaf-clue sequence)
##   * Puzzle 4 - CrystalMirror (The Crystal Cave light-beam redirector)
##   * Puzzle 5 - MovingRootBridge (The Root Maze vertical/rotating/bridge roots)
##   * Puzzle 6 - AncientForestSeal (The Four Ancient Forest Seals)


class SleepingTreeSeed extends Node3D:
	signal picked_up(seed_node: SleepingTreeSeed)

	@export var pick_range := 1.45
	@export var ride_height := 1.55

	var woods: Node = null
	var carried := false
	var planted := false
	var carrier: Node3D = null
	var _time := 0.0
	var _visual: Node3D

	func _ready() -> void:
		add_to_group("sleeping_tree_seeds")
		_visual = Node3D.new()
		add_child(_visual)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#80ff9e")
		mat.emission_enabled = true
		mat.emission = Color("#46f27a")
		mat.emission_energy_multiplier = 1.8
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.24
		sphere.height = 0.54
		orb.mesh = sphere
		orb.material_override = mat
		orb.position.y = 0.45
		_visual.add_child(orb)

	func _process(delta: float) -> void:
		_time += delta
		if planted:
			return
		if _visual != null:
			_visual.rotation.y = _time * 2.2
			_visual.position.y = sin(_time * 3.5) * 0.1
		if carried and is_instance_valid(carrier):
			global_position = carrier.global_position + Vector3(0.0, ride_height, 0.0)
			return
		for node in get_tree().get_nodes_in_group("player"):
			var p := node as Node3D
			if p != null and p.global_position.distance_to(global_position) <= pick_range:
				_pick_up(p)
				return

	func _pick_up(who: Node3D) -> void:
		if carried or planted:
			return
		carried = true
		carrier = who
		Audio.play("res://sounds/coin.ogg")
		if woods != null and woods.has_signal("message"):
			woods.emit_signal("message", "Glowing Tree Seed picked up! Press E at a root socket by the Sleeping Tree to plant it.")
		picked_up.emit(self)


class SleepingTreeSocket extends Node3D:
	signal seed_planted(socket: SleepingTreeSocket)

	@export var use_range := 2.6
	var woods: Node = null
	var filled := false
	var _seed_visual: MeshInstance3D
	var _ring_mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("sleeping_tree_sockets")
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color("#593a25")
		var base := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.48
		cyl.bottom_radius = 0.62
		cyl.height = 0.28
		base.mesh = cyl
		base.material_override = bark
		base.position.y = 0.14
		add_child(base)

		var collider := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var c_shape := CylinderShape3D.new()
		c_shape.radius = 0.52
		c_shape.height = 0.35
		shape.shape = c_shape
		shape.position.y = 0.18
		collider.add_child(shape)
		add_child(collider)

		_ring_mat = StandardMaterial3D.new()
		_ring_mat.albedo_color = Color("#a882ff")
		_ring_mat.emission_enabled = true
		_ring_mat.emission = Color("#a882ff")
		_ring_mat.emission_energy_multiplier = 1.1
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.28
		torus.outer_radius = 0.42
		ring.mesh = torus
		ring.material_override = _ring_mat
		ring.position.y = 0.3
		add_child(ring)

		_seed_visual = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.24
		sphere.height = 0.48
		_seed_visual.mesh = sphere
		var seed_mat := StandardMaterial3D.new()
		seed_mat.albedo_color = Color("#65f6ad")
		seed_mat.emission_enabled = true
		seed_mat.emission = Color("#65f6ad")
		seed_mat.emission_energy_multiplier = 2.0
		_seed_visual.material_override = seed_mat
		_seed_visual.position.y = 0.55
		_seed_visual.visible = false
		add_child(_seed_visual)

	func _unhandled_input(event: InputEvent) -> void:
		if filled:
			return
		for action in ["interact", "p1_interact", "p2_interact"]:
			if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
				if _player_in_range():
					try_plant()
					return

	func _player_in_range() -> bool:
		for node in get_tree().get_nodes_in_group("player"):
			var p := node as Node3D
			if p != null and p.global_position.distance_to(global_position) <= use_range:
				return true
		return false

	func try_plant() -> bool:
		if filled:
			return true
		for node in get_tree().get_nodes_in_group("sleeping_tree_seeds"):
			var s := node as SleepingTreeSeed
			if s != null and s.carried and not s.planted:
				s.planted = true
				s.carried = false
				s.visible = false
				plant_immediately()
				return true
		if woods != null and woods.has_signal("message"):
			woods.emit_signal("message", "A root opening of the Sleeping Tree. Bring one of the glowing seeds nearby and press E.")
		return false

	func plant_immediately() -> void:
		if filled:
			return
		filled = true
		if _seed_visual != null:
			_seed_visual.visible = true
		if _ring_mat != null:
			_ring_mat.albedo_color = Color("#65f6ad")
			_ring_mat.emission = Color("#65f6ad")
		Audio.play("res://sounds/coin.ogg")
		if woods != null and woods.has_method("on_tree_seed_planted"):
			woods.call("on_tree_seed_planted")
		seed_planted.emit(self)


class SequenceTreeSwitch extends Node3D:
	signal pressed(order_index: int)

	@export var order_index := 1
	@export var use_range := 2.6

	var woods: Node = null
	var active := false
	var _orb_mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("moving_tree_switches")
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("#5d556b")
		var base := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.58
		cyl.height = 0.75
		base.mesh = cyl
		base.material_override = stone
		base.position.y = 0.38
		add_child(base)

		var collider := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var c_shape := CylinderShape3D.new()
		c_shape.radius = 0.52
		c_shape.height = 0.9
		shape.shape = c_shape
		shape.position.y = 0.45
		collider.add_child(shape)
		add_child(collider)

		_orb_mat = StandardMaterial3D.new()
		_orb_mat.albedo_color = Color("#b06bff")
		_orb_mat.emission_enabled = true
		_orb_mat.emission = Color("#b06bff")
		_orb_mat.emission_energy_multiplier = 1.4
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.56
		orb.mesh = sphere
		orb.material_override = _orb_mat
		orb.position.y = 0.98
		add_child(orb)

		# Glowing leaf-count clue pips above the switch (1, 2, or 3)
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = Color("#70ff9d")
		leaf_mat.emission_enabled = true
		leaf_mat.emission = Color("#70ff9d")
		leaf_mat.emission_energy_multiplier = 1.8
		for i in order_index:
			var pip := MeshInstance3D.new()
			var p_sphere := SphereMesh.new()
			p_sphere.radius = 0.1
			p_sphere.height = 0.2
			pip.mesh = p_sphere
			pip.material_override = leaf_mat
			var offset_x := (float(i) - float(order_index - 1) * 0.5) * 0.28
			pip.position = Vector3(offset_x, 1.48, 0.0)
			add_child(pip)

	func _unhandled_input(event: InputEvent) -> void:
		for action in ["interact", "p1_interact", "p2_interact"]:
			if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
				if _player_in_range():
					activate()
					return

	func _player_in_range() -> bool:
		for node in get_tree().get_nodes_in_group("player"):
			var p := node as Node3D
			if p != null and p.global_position.distance_to(global_position) <= use_range:
				return true
		return false

	func activate() -> void:
		if woods != null and woods.has_method("on_moving_tree_switch"):
			woods.call("on_moving_tree_switch", self)
		pressed.emit(order_index)

	func set_lit(lit: bool) -> void:
		active = lit
		if _orb_mat != null:
			var col := Color("#65f6ad") if lit else Color("#b06bff")
			_orb_mat.albedo_color = col
			_orb_mat.emission = col


class CrystalMirror extends Node3D:
	signal aligned(mirror: CrystalMirror)

	@export var target_steps := 1
	@export var use_range := 2.8

	var woods: Node = null
	var current_step := 0
	var _mirror_head: Node3D
	var _beam_mesh: MeshInstance3D
	var _crystal_mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("crystal_mirrors")
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("#6b6579")
		var column := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.36
		cyl.bottom_radius = 0.5
		cyl.height = 1.0
		column.mesh = cyl
		column.material_override = stone
		column.position.y = 0.5
		add_child(column)

		var collider := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var c_shape := CylinderShape3D.new()
		c_shape.radius = 0.48
		c_shape.height = 1.4
		shape.shape = c_shape
		shape.position.y = 0.7
		collider.add_child(shape)
		add_child(collider)

		_mirror_head = Node3D.new()
		_mirror_head.position.y = 1.25
		add_child(_mirror_head)

		_crystal_mat = StandardMaterial3D.new()
		_crystal_mat.albedo_color = Color("#5ceeff")
		_crystal_mat.emission_enabled = true
		_crystal_mat.emission = Color("#5ceeff")
		_crystal_mat.emission_energy_multiplier = 1.6

		var pane := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.75, 0.75, 0.12)
		pane.mesh = box
		pane.material_override = _crystal_mat
		_mirror_head.add_child(pane)

		_beam_mesh = MeshInstance3D.new()
		var beam_cyl := CylinderMesh.new()
		beam_cyl.top_radius = 0.06
		beam_cyl.bottom_radius = 0.06
		beam_cyl.height = 4.5
		_beam_mesh.mesh = beam_cyl
		_beam_mesh.material_override = _crystal_mat
		_beam_mesh.rotation.x = PI * 0.5
		_beam_mesh.position = Vector3(0.0, 0.0, 2.3)
		_mirror_head.add_child(_beam_mesh)
		_update_visual()

	func is_aligned() -> bool:
		return current_step == target_steps

	func _unhandled_input(event: InputEvent) -> void:
		for action in ["interact", "p1_interact", "p2_interact"]:
			if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
				if _player_in_range():
					rotate_mirror()
					return

	func _player_in_range() -> bool:
		for node in get_tree().get_nodes_in_group("player"):
			var p := node as Node3D
			if p != null and p.global_position.distance_to(global_position) <= use_range:
				return true
		return false

	func rotate_mirror() -> void:
		current_step = (current_step + 1) % 3
		Audio.play("res://sounds/coin.ogg")
		_update_visual()
		if woods != null and woods.has_method("on_crystal_mirror_turned"):
			woods.call("on_crystal_mirror_turned", self)
		if is_aligned():
			aligned.emit(self)

	func align_immediately() -> void:
		current_step = target_steps
		_update_visual()
		if woods != null and woods.has_method("on_crystal_mirror_turned"):
			woods.call("on_crystal_mirror_turned", self)

	func _update_visual() -> void:
		if _mirror_head != null:
			_mirror_head.rotation_degrees.y = float(current_step - target_steps) * 60.0
		if _crystal_mat != null:
			var col := Color("#65f6ad") if is_aligned() else Color("#5ceeff")
			_crystal_mat.albedo_color = col
			_crystal_mat.emission = col


class MovingRootPlatform extends AnimatableBody3D:
	## Moving or rotating giant root platform used in Puzzle 5 (The Root Maze)
	## and Puzzle 6. Uses sync_to_physics = false when rotating so rotation works.
	@export var mode := "vertical" # "vertical", "horizontal", "rotate"
	@export var amplitude := 1.4
	@export var speed := 1.35
	@export var phase_offset := 0.0
	@export var length := 2.4

	var _collision: CollisionShape3D
	var _origin := Vector3.ZERO
	var _time := 0.0

	func _init() -> void:
		_collision = CollisionShape3D.new()
		_collision.name = "RootCollision"
		var box := BoxShape3D.new()
		box.size = Vector3(2.2, 0.5, 2.2)
		_collision.shape = box
		_collision.position = Vector3(0.0, -0.25, 0.0)
		add_child(_collision)

	func _ready() -> void:
		_origin = position
		if mode == "rotate":
			sync_to_physics = false
		(_collision.shape as BoxShape3D).size = Vector3(length, 0.5, 2.0)
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color("#5c3d28")
		bark.roughness = 0.85
		var moss := StandardMaterial3D.new()
		moss.albedo_color = Color("#57b85e")
		moss.roughness = 0.75

		var root_mesh := MeshInstance3D.new()
		var box_m := BoxMesh.new()
		box_m.size = Vector3(length, 0.36, 1.9)
		root_mesh.mesh = box_m
		root_mesh.material_override = bark
		root_mesh.position = Vector3(0.0, -0.28, 0.0)
		add_child(root_mesh)

		var top_mesh := MeshInstance3D.new()
		var top_box := BoxMesh.new()
		top_box.size = Vector3(length * 0.96, 0.16, 1.82)
		top_mesh.mesh = top_box
		top_mesh.material_override = moss
		top_mesh.position = Vector3(0.0, -0.08, 0.0)
		add_child(top_mesh)

	func _physics_process(delta: float) -> void:
		_time += delta * speed
		var wave := sin(_time + phase_offset)
		if mode == "vertical":
			position = _origin + Vector3(0.0, wave * amplitude, 0.0)
		elif mode == "horizontal":
			position = _origin + Vector3(wave * amplitude, 0.0, 0.0)
		elif mode == "rotate":
			rotation.y = wave * 0.55


class AncientForestSeal extends Node3D:
	## One of the four Ancient Forest Seals before the Guardian's Grove (Puzzle 6).
	signal activated(seal: AncientForestSeal)

	@export var seal_id := "tree_climb"
	@export var seal_title := "The Canopy Seal"
	@export var challenge_type := "climb" # "climb", "crystal", "timed", "enemies"
	@export var required_puzzle := ""
	@export var ward_range := 9.0
	@export var use_range := 2.8

	var woods: Node = null
	var is_active := false
	var _orb_mat: StandardMaterial3D
	var _refuse_cooldown := 0.0

	func _ready() -> void:
		add_to_group("forest_seals")
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("#6e677d")
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.58
		cyl.height = 1.25
		pillar.mesh = cyl
		pillar.material_override = stone
		pillar.position.y = 0.62
		add_child(pillar)

		var collider := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var c_shape := CylinderShape3D.new()
		c_shape.radius = 0.58
		c_shape.height = 1.35
		shape.shape = c_shape
		shape.position.y = 0.68
		collider.add_child(shape)
		add_child(collider)

		_orb_mat = StandardMaterial3D.new()
		_orb_mat.albedo_color = Color("#9b6bff")
		_orb_mat.emission_enabled = true
		_orb_mat.emission = Color("#9b6bff")
		_orb_mat.emission_energy_multiplier = 1.3
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		orb.mesh = sphere
		orb.material_override = _orb_mat
		orb.position.y = 1.48
		add_child(orb)

	func _process(delta: float) -> void:
		_refuse_cooldown = maxf(_refuse_cooldown - delta, 0.0)

	func blocking_reason() -> String:
		if is_active:
			return ""
		if challenge_type == "enemies":
			for node in get_tree().get_nodes_in_group("enemies"):
				var e := node as Node3D
				if e != null and not (e is ShadowWolfBoss) and e.global_position.distance_to(global_position) <= ward_range:
					return "%s is warded by corrupted creatures nearby - defeat them first!" % seal_title
		elif not required_puzzle.is_empty() and woods != null:
			if not bool(woods.call("is_puzzle_solved", required_puzzle)):
				return "%s is dormant - complete its forest challenge first!" % seal_title
		return ""

	func _unhandled_input(event: InputEvent) -> void:
		if is_active:
			return
		for action in ["interact", "p1_interact", "p2_interact"]:
			if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
				if _player_in_range():
					try_activate()
					return

	func _player_in_range() -> bool:
		for node in get_tree().get_nodes_in_group("player"):
			var p := node as Node3D
			if p != null and p.global_position.distance_to(global_position) <= use_range:
				return true
		return false

	func try_activate() -> bool:
		if is_active:
			return true
		var reason := blocking_reason()
		if not reason.is_empty():
			if _refuse_cooldown <= 0.0:
				_refuse_cooldown = 2.0
				if woods != null and woods.has_signal("message"):
					woods.emit_signal("message", reason)
			return false
		activate_immediately()
		return true

	func activate_immediately() -> void:
		if is_active:
			return
		is_active = true
		if _orb_mat != null:
			_orb_mat.albedo_color = Color("#65f6ad")
			_orb_mat.emission = Color("#65f6ad")
			_orb_mat.emission_energy_multiplier = 2.2
		Audio.play("res://sounds/coin.ogg")
		if woods != null and woods.has_method("on_forest_seal_activated"):
			woods.call("on_forest_seal_activated", self)
		activated.emit(self)
