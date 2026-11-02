extends RefCounted
class_name EmberPuzzles

## Volcanic puzzle components, ancient energy machines, rotating obsidian bridges,
## rising lava chambers, falling volcanic rocks, magma crystals, and ember seals
## for Level 4: Ember Heights.


class AncientEnergySwitch extends Node3D:
	## Puzzle 1: Powers an ancient energy machine with glowing orange energy lines,
	## unlocks the Magical Shield ability, and opens a stone gate.
	signal activated

	@export var switch_title: String = "Ancient Energy Switch"
	@export var unlocks_magical_shield: bool = true
	var is_activated: bool = false
	var _core: MeshInstance3D
	var _line: MeshInstance3D
	var _core_mat: StandardMaterial3D
	var _line_mat: StandardMaterial3D
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("ember_switches")
		var base := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.56
		cyl.bottom_radius = 0.68
		cyl.height = 0.36
		base.mesh = cyl
		base.position.y = 0.18
		var stone_mat := StandardMaterial3D.new()
		stone_mat.albedo_color = Color("#1e1a22")
		stone_mat.roughness = 0.85
		base.material_override = stone_mat
		add_child(base)

		_core = MeshInstance3D.new()
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = 0.22
		core_mesh.bottom_radius = 0.32
		core_mesh.height = 1.15
		_core.mesh = core_mesh
		_core.position.y = 0.85
		_core_mat = StandardMaterial3D.new()
		_core_mat.albedo_color = Color("#ff5e1f")
		_core_mat.emission_enabled = true
		_core_mat.emission = Color("#ff5e1f")
		_core_mat.emission_energy_multiplier = 0.85
		_core.material_override = _core_mat
		add_child(_core)

		# Glowing orange energy line leading forward toward the gate/machine
		_line = MeshInstance3D.new()
		_line.name = "EnergyLine"
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.18, 0.06, 2.6)
		_line.mesh = line_mesh
		_line.position = Vector3(0.0, 0.05, 1.35)
		_line_mat = StandardMaterial3D.new()
		_line_mat.albedo_color = Color("#4a2414")
		_line_mat.emission_enabled = true
		_line_mat.emission = Color("#ff6a18")
		_line_mat.emission_energy_multiplier = 0.3
		_line.material_override = _line_mat
		add_child(_line)

		var trigger := Area3D.new()
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.7
		shape.shape = sphere
		shape.position.y = 0.8
		trigger.add_child(shape)
		add_child(trigger)
		trigger.body_entered.connect(func(body: Node3D):
			if body.is_in_group("player"):
				activate()
		)

	func _process(delta: float) -> void:
		_time += delta
		if _core != null:
			_core.rotation.y += delta * (2.2 if is_activated else 0.65)
			_core.position.y = 0.85 + sin(_time * 2.5) * 0.06

	func activate() -> bool:
		if is_activated:
			return false
		is_activated = true
		if _core_mat != null:
			_core_mat.albedo_color = Color("#ffd84d")
			_core_mat.emission = Color("#ff941f")
			_core_mat.emission_energy_multiplier = 2.6
		if _line_mat != null:
			_line_mat.albedo_color = Color("#ffae24")
			_line_mat.emission = Color("#ff7a18")
			_line_mat.emission_energy_multiplier = 2.4
		var prog := get_node_or_null("/root/Progress")
		if prog != null:
			if unlocks_magical_shield:
				prog.call("unlock_magical_shield")
			prog.call("mark_ember_switch_solved")
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/coin.ogg")
		activated.emit()
		return true


class MagmaCrystalNode extends Node3D:
	## Puzzle 3: One of the Three Magma Crystals (cave, moving platform, slime-guarded).
	signal activated(crystal: MagmaCrystalNode)

	@export var crystal_index: int = 0
	@export var location_hint: String = "Volcanic Cave"
	var is_activated: bool = false
	var _shard: MeshInstance3D
	var _mat: StandardMaterial3D
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("magma_crystals")
		var pedestal := MeshInstance3D.new()
		var ped_mesh := CylinderMesh.new()
		ped_mesh.top_radius = 0.42
		ped_mesh.bottom_radius = 0.54
		ped_mesh.height = 0.34
		pedestal.mesh = ped_mesh
		pedestal.position.y = 0.17
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color("#1b1720")
		pedestal.material_override = dark
		add_child(pedestal)

		_shard = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.28
		cone.height = 1.35
		_shard.mesh = cone
		_shard.position.y = 0.96
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color("#ff471a")
		_mat.emission_enabled = true
		_mat.emission = Color("#ff5b1f")
		_mat.emission_energy_multiplier = 1.1
		_shard.material_override = _mat
		add_child(_shard)

		var trigger := Area3D.new()
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.65
		shape.shape = sphere
		shape.position.y = 0.85
		trigger.add_child(shape)
		add_child(trigger)
		trigger.body_entered.connect(func(body: Node3D):
			if body.is_in_group("player"):
				activate()
		)

	func _process(delta: float) -> void:
		_time += delta
		if _shard != null:
			_shard.rotation.y += delta * (2.4 if is_activated else 0.8)
			_shard.position.y = 0.96 + sin(_time * 2.4 + float(crystal_index)) * 0.08

	func activate() -> bool:
		if is_activated:
			return false
		is_activated = true
		if _mat != null:
			_mat.albedo_color = Color("#ffe052")
			_mat.emission = Color("#ff9d1f")
			_mat.emission_energy_multiplier = 2.8
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/coin.ogg")
		activated.emit(self)
		return true


class AncientEnergyMachine extends Node3D:
	## Puzzle 4: Ancient Energy Machine with rotating beam mechanism and energy crystal core.
	## MID-PUZZLE RULE SHIFT:
	## After activating the first 2 machines, an ancient thermal overload triggers
	## a Rule Shift: "RULE SHIFT: POLARITY INVERSION! Align beams to OPPOSITE energy nodes!"
	## Machine 3's target alignment changes dynamically, and machines emit inverted azure-cyan
	## harmonic resonance pulses until the inverted circuit is balanced.
	signal activated(machine: AncientEnergyMachine)
	signal rule_shifted(message: String)

	@export var machine_index: int = 0
	@export var target_rotation_step: int = 1
	var rotation_step: int = 0
	var is_activated: bool = false
	var is_rule_shifted: bool = false
	var _rotor: Node3D
	var _beam: MeshInstance3D
	var _core_mat: StandardMaterial3D
	var _beam_mat: StandardMaterial3D
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("ancient_energy_machines")
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = 0.62
		cyl_shape.height = 1.5
		shape.shape = cyl_shape
		shape.position.y = 0.75
		body.add_child(shape)
		add_child(body)

		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.52
		cyl.bottom_radius = 0.64
		cyl.height = 1.4
		pillar.mesh = cyl
		pillar.position.y = 0.7
		var obsidian := StandardMaterial3D.new()
		obsidian.albedo_color = Color("#18151e")
		obsidian.roughness = 0.45
		pillar.material_override = obsidian
		add_child(pillar)

		_rotor = Node3D.new()
		_rotor.name = "BeamRotor"
		_rotor.position.y = 1.48
		add_child(_rotor)

		var core := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.34
		sphere.height = 0.68
		core.mesh = sphere
		_core_mat = StandardMaterial3D.new()
		_core_mat.albedo_color = Color("#ff5b1f")
		_core_mat.emission_enabled = true
		_core_mat.emission = Color("#ff5b1f")
		_core_mat.emission_energy_multiplier = 1.1
		core.material_override = _core_mat
		_rotor.add_child(core)

		_beam = MeshInstance3D.new()
		_beam.name = "EnergyBeam"
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = 0.07
		beam_mesh.bottom_radius = 0.07
		beam_mesh.height = 3.2
		_beam.mesh = beam_mesh
		_beam.rotation.x = PI * 0.5
		_beam.position.z = 1.65
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.albedo_color = Color("#ff8a1f")
		_beam_mat.emission_enabled = true
		_beam_mat.emission = Color("#ff6e18")
		_beam_mat.emission_energy_multiplier = 1.6
		_beam.material_override = _beam_mat
		_rotor.add_child(_beam)

		var trigger := Area3D.new()
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		var t_shape := CollisionShape3D.new()
		var t_sphere := SphereShape3D.new()
		t_sphere.radius = 1.85
		t_shape.shape = t_sphere
		t_shape.position.y = 0.9
		trigger.add_child(t_shape)
		add_child(trigger)
		trigger.body_entered.connect(func(b: Node3D):
			if b.is_in_group("player"):
				activate()
		)

	func _process(delta: float) -> void:
		_time += delta
		if _rotor != null and is_activated:
			_rotor.position.y = 1.48 + sin(_time * 3.0) * 0.05

	func apply_rule_shift(inverted_target: int) -> void:
		is_rule_shifted = true
		target_rotation_step = inverted_target
		if not is_activated and _beam_mat != null and _core_mat != null:
			# Shift visual beam harmonics to telltale inverted cyan-gold hue
			_core_mat.emission = Color("#3de8ff")
			_core_mat.albedo_color = Color("#22c5e2")
			_beam_mat.emission = Color("#3de8ff")
			_beam_mat.albedo_color = Color("#22c5e2")
		rule_shifted.emit("Circuit Inversion")

	func try_interact(player: Node3D) -> bool:
		if is_activated or global_position.distance_to(player.global_position) > 2.8:
			return false
		rotation_step = (rotation_step + 1) % 4
		if _rotor != null:
			_rotor.rotation.y = float(rotation_step) * PI * 0.5
		if rotation_step == target_rotation_step:
			return activate()
		return true

	func activate() -> bool:
		if is_activated:
			return false
		is_activated = true
		rotation_step = target_rotation_step
		if _rotor != null:
			_rotor.rotation.y = float(rotation_step) * PI * 0.5
		if _core_mat != null:
			if is_rule_shifted:
				_core_mat.albedo_color = Color("#7af5ff")
				_core_mat.emission = Color("#28e5ff")
				_core_mat.emission_energy_multiplier = 3.2
			else:
				_core_mat.albedo_color = Color("#ffe259")
				_core_mat.emission = Color("#ffae24")
				_core_mat.emission_energy_multiplier = 2.8
		if _beam_mat != null:
			if is_rule_shifted:
				_beam_mat.albedo_color = Color("#7af5ff")
				_beam_mat.emission = Color("#28e5ff")
				_beam_mat.emission_energy_multiplier = 3.2
			else:
				_beam_mat.albedo_color = Color("#ffe86b")
				_beam_mat.emission = Color("#ffba24")
				_beam_mat.emission_energy_multiplier = 2.8
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/coin.ogg")
		activated.emit(self)
		return true


class RisingLavaChamber extends Node3D:
	## Puzzle 5: Underground volcanic chamber where lava gradually rises and falls
	## within safe bounds while the player activates switches to stabilize the chamber.
	signal solved

	@export var rise_amplitude: float = 0.65
	@export var rise_speed: float = 0.85
	var switches_activated: int = 0
	var switches_required: int = 2
	var is_solved: bool = false
	var _lava_surface: MeshInstance3D
	var _hazard_area: Area3D
	var _switches: Array[Node3D] = []
	var _base_lava_y: float = -0.65
	var _time: float = 0.0
	var _damage_cooldown: float = 0.0

	func _ready() -> void:
		add_to_group("rising_lava_chamber")
		_lava_surface = MeshInstance3D.new()
		_lava_surface.name = "RisingLavaSurface"
		var box := BoxMesh.new()
		box.size = Vector3(8.5, 0.28, 9.5)
		_lava_surface.mesh = box
		_lava_surface.position.y = _base_lava_y
		var lava_mat := StandardMaterial3D.new()
		lava_mat.albedo_color = Color("#ff3d14")
		lava_mat.emission_enabled = true
		lava_mat.emission = Color("#ff6818")
		lava_mat.emission_energy_multiplier = 2.1
		_lava_surface.material_override = lava_mat
		add_child(_lava_surface)

		_hazard_area = Area3D.new()
		_hazard_area.name = "RisingLavaHazard"
		_hazard_area.collision_layer = 0
		_hazard_area.collision_mask = 1
		var shape := CollisionShape3D.new()
		var h_box := BoxShape3D.new()
		h_box.size = Vector3(7.6, 0.35, 8.2)
		shape.shape = h_box
		_hazard_area.add_child(shape)
		_hazard_area.position.y = _base_lava_y
		add_child(_hazard_area)
		_hazard_area.body_entered.connect(_on_hazard_body_entered)

		for idx in 2:
			var sw := Node3D.new()
			sw.name = "ChamberSwitch_%d" % idx
			sw.position = Vector3(-1.4 if idx == 0 else 1.4, 0.55, -1.6 + float(idx) * 3.2)
			sw.set_meta("active", false)
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.25
			cyl.bottom_radius = 0.32
			cyl.height = 0.85
			post.mesh = cyl
			post.position.y = 0.42
			var sw_mat := StandardMaterial3D.new()
			sw_mat.albedo_color = Color("#ff5b1f")
			sw_mat.emission_enabled = true
			sw_mat.emission = Color("#ff5b1f")
			sw_mat.emission_energy_multiplier = 1.4
			post.material_override = sw_mat
			sw.set_meta("mat", sw_mat)
			sw.add_child(post)

			var area := Area3D.new()
			area.collision_layer = 0
			area.collision_mask = 1
			var s_shape := CollisionShape3D.new()
			var s_sphere := SphereShape3D.new()
			s_sphere.radius = 1.45
			s_shape.shape = s_sphere
			s_shape.position.y = 0.5
			area.add_child(s_shape)
			sw.add_child(area)
			area.body_entered.connect(func(b: Node3D):
				if b.is_in_group("player"):
					_activate_chamber_switch(sw)
			)
			add_child(sw)
			_switches.append(sw)

		var prog := get_node_or_null("/root/Progress")
		if prog != null and bool(prog.get("ember_rising_lava_solved")):
			solve()

	func _process(delta: float) -> void:
		_time += delta
		_damage_cooldown = maxf(0.0, _damage_cooldown - delta)
		if is_solved:
			if _lava_surface != null:
				_lava_surface.position.y = move_toward(_lava_surface.position.y, -1.4, delta * 0.8)
			if _hazard_area != null:
				_hazard_area.position.y = _lava_surface.position.y
			return
		# Lava rises and recedes in a fair, predictable cycle
		var wave := (sin(_time * rise_speed) * 0.5 + 0.5) * rise_amplitude
		if _lava_surface != null:
			_lava_surface.position.y = _base_lava_y + wave
		if _hazard_area != null:
			_hazard_area.position.y = _base_lava_y + wave

	func _on_hazard_body_entered(body: Node3D) -> void:
		if is_solved or _damage_cooldown > 0.0:
			return
		if body.is_in_group("player") and body.has_method("take_damage"):
			_damage_cooldown = 1.0
			body.call("take_damage", 8.0, global_position, "lava_hazard")

	func _activate_chamber_switch(sw: Node3D) -> void:
		if bool(sw.get_meta("active", false)):
			return
		sw.set_meta("active", true)
		var mat: StandardMaterial3D = sw.get_meta("mat")
		if mat != null:
			mat.albedo_color = Color("#ffe259")
			mat.emission = Color("#65f6ad")
		switches_activated += 1
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/coin.ogg")
		if switches_activated >= switches_required:
			solve()

	func try_interact(player: Node3D) -> bool:
		if is_solved:
			return false
		for sw in _switches:
			if not bool(sw.get_meta("active", false)) and sw.global_position.distance_to(player.global_position) <= 2.6:
				_activate_chamber_switch(sw)
				return true
		return false

	func solve() -> void:
		if is_solved:
			return
		is_solved = true
		switches_activated = switches_required
		for sw in _switches:
			sw.set_meta("active", true)
		var prog := get_node_or_null("/root/Progress")
		if prog != null:
			prog.call("mark_ember_rising_lava_solved")
		solved.emit()


class RotatingObsidianBridge extends AnimatableBody3D:
	## Puzzle 6: Rotating black obsidian bridge over lava.
	## Uses sync_to_physics = false so rotation updates apply reliably in Jolt.
	@export var spin_speed: float = 0.75
	@export var bridge_size: Vector3 = Vector3(1.85, 0.26, 3.4)

	func _init() -> void:
		sync_to_physics = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bridge_size
		shape.shape = box
		add_child(shape)

	func _ready() -> void:
		add_to_group("rotating_obsidian_bridges")
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = bridge_size
		visual.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#191620")
		mat.roughness = 0.38
		mat.emission_enabled = true
		mat.emission = Color("#ff4c18")
		mat.emission_energy_multiplier = 0.35
		visual.material_override = mat
		add_child(visual)

	func _physics_process(delta: float) -> void:
		rotation.y += delta * spin_speed


class FallingVolcanicRock extends Node3D:
	## Puzzle 6: Periodic falling volcanic rock hazard with a glowing ground warning ring.
	@export var fall_cycle: float = 2.8
	@export var phase_offset: float = 0.0
	@export var damage: float = 9.0
	var _rock: MeshInstance3D
	var _warning: MeshInstance3D
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("falling_volcanic_rocks")
		_time = phase_offset

		_rock = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.36
		sphere.height = 0.72
		_rock.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#241818")
		mat.emission_enabled = true
		mat.emission = Color("#ff5218")
		mat.emission_energy_multiplier = 1.6
		_rock.material_override = mat
		_rock.position.y = 4.5
		add_child(_rock)

		_warning = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.68
		_warning.mesh = torus
		_warning.position.y = 0.08
		var w_mat := StandardMaterial3D.new()
		w_mat.albedo_color = Color("#ff6e1f")
		w_mat.emission_enabled = true
		w_mat.emission = Color("#ff3e14")
		w_mat.emission_energy_multiplier = 1.8
		_warning.material_override = w_mat
		add_child(_warning)

	func _physics_process(delta: float) -> void:
		_time += delta
		var t := fmod(_time, fall_cycle) / fall_cycle
		if _rock != null:
			_rock.position.y = lerpf(4.8, 0.25, t)
			_rock.rotation.x += delta * 3.5
		if _warning != null:
			_warning.scale = Vector3.ONE * lerpf(0.5, 1.15, t)
		if t > 0.92:
			for p in get_tree().get_nodes_in_group("player"):
				if p is Node3D and (p as Node3D).global_position.distance_to(global_position) < 0.85:
					if p.has_method("take_damage"):
						p.call("take_damage", damage, global_position, "falling_rock")


class AncientEmberSeal extends Node3D:
	## Puzzle 7: One of the Four Ancient Ember Seals guarding the Ember Dragon's Sanctuary.
	##   0: Moving-platform challenge over lava ("lava_platforms")
	##   1: Ancient energy-machine puzzle ("energy_machine")
	##   2: Timed magma-crystal sequence ("crystal_sequence")
	##   3: Combined enemy encounter ("enemy_encounter")
	signal activated(seal: AncientEmberSeal)

	@export var seal_index: int = 0
	@export var seal_name: String = "Ember Seal"
	@export var challenge_type: String = "lava_platforms"
	var is_activated: bool = false
	var _orb: MeshInstance3D
	var _mat: StandardMaterial3D
	var _time: float = 0.0

	func _ready() -> void:
		add_to_group("ember_seals")
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.60
		cyl.height = 1.25
		pillar.mesh = cyl
		pillar.position.y = 0.62
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("#1b1722")
		stone.roughness = 0.7
		pillar.material_override = stone
		add_child(pillar)

		_orb = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.34
		sphere.height = 0.68
		_orb.mesh = sphere
		_orb.position.y = 1.52
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color("#ff471a")
		_mat.emission_enabled = true
		_mat.emission = Color("#ff5b1f")
		_mat.emission_energy_multiplier = 1.2
		_orb.material_override = _mat
		add_child(_orb)

	func _process(delta: float) -> void:
		_time += delta
		if _orb != null:
			_orb.position.y = 1.52 + sin(_time * 2.5 + float(seal_index)) * 0.07
			_orb.rotation.y += delta * (2.2 if is_activated else 0.7)

	func activate() -> bool:
		if is_activated:
			return false
		is_activated = true
		if _mat != null:
			_mat.albedo_color = Color("#ffe45c")
			_mat.emission = Color("#ffae24")
			_mat.emission_energy_multiplier = 2.8
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/coin.ogg")
		activated.emit(self)
		return true
