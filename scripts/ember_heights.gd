extends Node3D
class_name EmberHeights

## Level 4: EMBER HEIGHTS - Fourth Fragment of the Eternal Tree
## Huge floating volcanic island kingdom with 6 connected regions:
##   1. Volcanic Arrival
##   2. Ashen Plains
##   3. Molten River Crossing
##   4. Ancient Energy Mines
##   5. The Obsidian Fortress
##   6. Ember Dragon's Sanctuary

const PLATFORM := preload("res://objects/platform_medium.tscn")
const COIN := preload("res://objects/coin.tscn")
const VOLCANIC_ENEMY := preload("res://objects/volcanic_enemy.gd")
const EMBER_DRAGON := preload("res://objects/ember_dragon.gd")
const FRAGMENT_CHEST := preload("res://objects/ember_fragment_chest.gd")
const EMBER_PUZZLES := preload("res://objects/ember_puzzles.gd")
const PUZZLE_GATE := preload("res://objects/puzzle_gate.gd")

@export var coins_required: int = 60
@export var next_level_scene: String = "res://scenes/main.tscn"

var route: Array = []
var region_names: Array[String] = [
	"Volcanic Arrival",
	"Ashen Plains",
	"Molten River Crossing",
	"Ancient Energy Mines",
	"The Obsidian Fortress",
	"Ember Dragon's Sanctuary",
]
var checkpoint_indices: Array[int] = [0, 10, 20, 31, 41]

var coins_placed: int = 0
var boss_defeated: bool = false
var fragment_recovered: bool = false
var fortress_discovered: bool = false
var ember_seals_complete: bool = false
var environment_recovered: bool = false
var boss_arena_locked: bool = false
var arrival_cinematic_complete: bool = false

var portal_count: int = 0
var volcano_count: int = 0
var fire_waterfall_count: int = 0
var lava_river_count: int = 0
var cave_cluster_count: int = 0

var _main: Node
var _world: Node3D
var _dragon: EmberDragon
var _chest: EmberFragmentChest
var _energy_switch: Node3D
var _magma_crystals: Array[Node3D] = []
var _energy_machines: Array[Node3D] = []
var _rising_lava_chamber: Node3D
var _rotating_bridges: Array[Node3D] = []
var _falling_rocks: Array[Node3D] = []
var ember_seals: Array[Node3D] = []

var _switch_gate: StaticBody3D
var _crystal_gate: StaticBody3D
var _machine_gate: StaticBody3D
var _chamber_gate: StaticBody3D
var _fortress_gate: StaticBody3D
var _boss_gate: StaticBody3D

var _moving_platforms: Array[Node3D] = []
var _charred_tree_materials: Array[StandardMaterial3D] = []
var _ash_particles: GPUParticles3D
var _distant_fortress: Node3D
var _fortress_beam: MeshInstance3D

var _arrival_portal_ring: MeshInstance3D
var _arrival_portal_material: StandardMaterial3D
var _exit_portal_ring: MeshInstance3D
var _exit_portal_material: StandardMaterial3D
var _portal_energy: float = 0.0
var _arrival_time: float = 0.0
var _time: float = 0.0

func build(main: Node) -> Array:
	_main = main
	_world = main.get("world")
	route = _make_route()
	_build_islands()
	_build_environment_details()
	_build_puzzles_and_hazards()
	_build_boss_arena()
	_build_distant_malakar_fortress()
	_build_ash_and_embers()
	_place_coins()
	_place_enemies()
	var prog := get_node_or_null("/root/Progress")
	if prog != null and bool(prog.get("fourth_fragment_recovered")):
		recover_environment()
	return route

func region_name_for_checkpoint(checkpoint_index: int) -> String:
	var region_index := 0
	if checkpoint_index >= 41:
		region_index = 5
	elif checkpoint_index >= 31:
		region_index = 4
	elif checkpoint_index >= 20:
		region_index = 3
	elif checkpoint_index >= 10:
		region_index = 2
	elif checkpoint_index >= 4:
		region_index = 1
	return region_names[region_index]

func _make_route() -> Array:
	var points: Array = []
	var z_cursor := 0.0
	for index in 46:
		var region := int(floor(float(index) / 8.0))
		var local := index % 8
		if index > 0:
			# The Boss Arena (index 43, radius 12.8) is an island of its own: the
			# approach platform (42) and exit platform (44) sit just outside its
			# rim with a ~0.9 jump gap, and the Portal Terrace (45) clears the
			# platform behind it the same way.
			if index == 43:
				z_cursor += 12.6
			elif index == 44:
				z_cursor += 17.4
			elif index == 45:
				z_cursor += 5.2
			elif index in [10, 28]:
				z_cursor += 2.5
			else:
				z_cursor += 2.32
		var x := sin(float(index) * 0.72) * (1.15 + float(region) * 0.12)
		if index in [0, 10, 28, 41, 42, 43, 44, 45]:
			x = 0.0
		var y := float(region) * 0.45 + float(local % 3) * 0.12
		if index >= 41:
			y = 2.8
		points.append(Vector3(x, y, z_cursor))
	return points

func _build_islands() -> void:
	var slab_indices := {
		0: ["VolcanicArrivalIsland", 2.8, 0.75],
		10: ["MoltenRiverPauseSlab", 2.6, 0.72],
		28: ["RisingLavaSafeLedge", 2.8, 0.72],
		43: ["EmberDragonArenaFloor", 12.8, 0.90],
		45: ["Level5PortalTerrace", 3.0, 0.80],
	}

	for index in route.size():
		if slab_indices.has(index):
			var spec: Array = slab_indices[index]
			var offset_z := 2.4 if index == 43 else 0.0
			_add_volcanic_island_slab(str(spec[0]), route[index] + Vector3(0.0, 0.12, offset_z), float(spec[1]), float(spec[2]))
			continue

		var platform: Node3D = PLATFORM.instantiate()
		platform.name = "EmberPlatform_%02d" % index
		platform.position = route[index]
		platform.scale = Vector3(1.0, 0.72, 1.0)
		_world.add_child(platform)
		_add_volcanic_cap(route[index], index)

		# Place decorative crystals and charred trees on flanking solid volcanic ledges outside the tile
		if index % 4 == 0 and index > 0:
			_add_magma_crystals_decor(route[index], 0.58 + float(index % 3) * 0.14)
		if index % 6 == 0 and index > 0:
			var side_x := 4.8 if (index % 12 == 0) else -4.8
			_add_charred_tree(route[index] + Vector3(side_x, -0.2, 0.0))
		if index % 9 == 4:
			_add_obsidian_arch(route[index])

	# Place huge volcanoes far out on the flanks (|x| >= 19.5) so their cones never touch playing tiles
	for region in 6:
		var z_pos := float(region) * 34.0 + 8.0
		_add_volcano(Vector3(-20.0 - float(region % 3) * 3.5, 1.0 + float(region) * 0.6, z_pos))
		_add_volcano(Vector3(20.0 + float(region % 3) * 3.5, 1.6 + float(region) * 0.5, z_pos + 16.0))

	# Arrival portal (leads back to Level 3) & Exit portal (leads to Level 5)
	_add_portal(route[0] + Vector3(0.0, 0.0, -2.0), Color("#72dfff"), false)
	_add_portal(route[route.size() - 1] + Vector3(0.0, 0.0, 1.8), Color("#ff6a1f"), true)

func _add_volcanic_island_slab(slab_name: String, centre: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = slab_name
	body.position = centre
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius
	cyl_shape.height = height
	shape.shape = cyl_shape
	body.add_child(shape)

	var visual := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius * 0.90
	cyl_mesh.height = height
	visual.mesh = cyl_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#1b1621")
	mat.roughness = 0.82
	visual.material_override = mat
	body.add_child(visual)

	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.18
	torus.outer_radius = radius
	rim.mesh = torus
	rim.position.y = height * 0.5
	rim.material_override = _material(Color("#ff5218"), 1.5)
	body.add_child(rim)

	_world.add_child(body)

func _add_volcanic_cap(point: Vector3, index: int) -> void:
	var body := StaticBody3D.new()
	body.name = "VolcanicCap_%02d" % index
	body.position = point + Vector3(0.0, 0.43, 0.0)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2.52, 0.14, 2.52)
	shape.shape = box_shape
	body.add_child(shape)

	var cap := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.52, 0.14, 2.52)
	cap.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#1b171f") if index % 2 == 0 else Color("#241d26")
	mat.roughness = 0.82
	cap.material_override = mat
	body.add_child(cap)

	# Glowing magma crack veins on the volcanic rock surface
	var crack := MeshInstance3D.new()
	var crack_mesh := BoxMesh.new()
	crack_mesh.size = Vector3(1.75, 0.03, 0.14)
	crack.mesh = crack_mesh
	crack.position = Vector3(0.0, 0.08, 0.0)
	crack.rotation.y = float(index) * 0.55
	crack.material_override = _material(Color("#ff5218"), 1.65)
	body.add_child(crack)
	_world.add_child(body)

func _add_magma_crystals_decor(point: Vector3, scale_factor: float) -> void:
	# Placed on flanking outcroppings well clear of the playing tile surface
	for side in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.name = "MagmaCrystalOutcrop"
		body.position = point + Vector3(side * 4.4, 0.0, 0.0)
		var shape := CollisionShape3D.new()
		var cyl_s := CylinderShape3D.new()
		cyl_s.radius = 0.55 * scale_factor
		cyl_s.height = 1.2 * scale_factor
		shape.shape = cyl_s
		shape.position.y = 0.6 * scale_factor
		body.add_child(shape)

		var rock_base := MeshInstance3D.new()
		var base_cyl := CylinderMesh.new()
		base_cyl.top_radius = 0.65 * scale_factor
		base_cyl.bottom_radius = 0.85 * scale_factor
		base_cyl.height = 0.5 * scale_factor
		rock_base.mesh = base_cyl
		rock_base.material_override = _material(Color("#1f1924"), 0.15)
		body.add_child(rock_base)

		var crystal := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06 * scale_factor
		mesh.bottom_radius = 0.22 * scale_factor
		mesh.height = 1.15 * scale_factor
		crystal.mesh = mesh
		crystal.position = Vector3(0.0, 0.65 * scale_factor, 0.0)
		crystal.rotation.z = side * 0.18
		crystal.material_override = _material(Color("#ff5b1f" if side < 0.0 else "#9b52ff"), 1.35)
		body.add_child(crystal)
		_world.add_child(body)

func _add_charred_tree(point: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "CharredTree"
	body.position = point
	var shape := CollisionShape3D.new()
	var cyl_s := CylinderShape3D.new()
	cyl_s.radius = 0.35
	cyl_s.height = 2.4
	shape.shape = cyl_s
	shape.position.y = 1.2
	body.add_child(shape)

	var pedestal := MeshInstance3D.new()
	var p_cyl := CylinderMesh.new()
	p_cyl.top_radius = 1.1
	p_cyl.bottom_radius = 0.85
	p_cyl.height = 0.6
	pedestal.mesh = p_cyl
	pedestal.position.y = -0.3
	pedestal.material_override = _material(Color("#1b1621"), 0.15)
	body.add_child(pedestal)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.20
	trunk_mesh.bottom_radius = 0.34
	trunk_mesh.height = 2.4
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, 1.2, 0.0)
	trunk.material_override = _material(Color("#1f191d"), 0.15)
	body.add_child(trunk)

	for h in [2.05, 2.6, 3.05]:
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 0.88 - (h - 2.05) * 0.18
		crown_mesh.height = crown_mesh.radius * 1.8
		crown.mesh = crown_mesh
		crown.position = Vector3(0.0, h, 0.0)
		var crown_mat := _material(Color("#ff4e18"), 0.95)
		crown.material_override = crown_mat
		_charred_tree_materials.append(crown_mat)
		body.add_child(crown)
	_world.add_child(body)

func _add_obsidian_arch(point: Vector3) -> void:
	var arch := Node3D.new()
	arch.name = "ObsidianArch"
	arch.position = point
	var obs_mat := _material(Color("#16131c"), 0.2)
	for side in [-1.0, 1.0]:
		var pillar_body := StaticBody3D.new()
		pillar_body.position = Vector3(side * 1.12, 1.4, 0.0)
		var p_shape := CollisionShape3D.new()
		var p_box := BoxShape3D.new()
		p_box.size = Vector3(0.32, 2.8, 0.32)
		p_shape.shape = p_box
		pillar_body.add_child(p_shape)
		var col := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.32, 2.8, 0.32)
		col.mesh = box
		col.material_override = obs_mat
		pillar_body.add_child(col)
		arch.add_child(pillar_body)
	var beam := MeshInstance3D.new()
	var b_box := BoxMesh.new()
	b_box.size = Vector3(2.6, 0.34, 0.38)
	beam.mesh = b_box
	beam.position = Vector3(0.0, 2.85, 0.0)
	beam.material_override = _material(Color("#ff5b1f"), 1.2)
	arch.add_child(beam)
	_world.add_child(arch)

func _add_volcano(point: Vector3) -> void:
	volcano_count += 1
	var volcano := Node3D.new()
	volcano.name = "ActiveVolcano_%02d" % volcano_count
	volcano.position = point

	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.15
	mesh.bottom_radius = 5.2
	mesh.height = 7.8
	cone.mesh = mesh
	cone.material_override = _material(Color("#1e1821"), 0.18)
	volcano.add_child(cone)

	var crater := MeshInstance3D.new()
	var c_mesh := CylinderMesh.new()
	c_mesh.top_radius = 1.05
	c_mesh.bottom_radius = 0.95
	c_mesh.height = 0.35
	crater.mesh = c_mesh
	crater.position.y = 3.85
	crater.material_override = _material(Color("#ff5318"), 2.4)
	volcano.add_child(crater)

	_world.add_child(volcano)

func _build_environment_details() -> void:
	# Fire waterfalls cascading on the side cliffs well clear of playing tiles
	for index in [3, 9, 15, 22, 30, 38]:
		_add_fire_waterfall(route[index] + Vector3(-4.4, -0.4, 0.0))
	# Flowing lava rivers beneath key crossings
	for index in [8, 12, 26, 35, 42]:
		_add_lava_river(route[index] + Vector3(0.0, -1.65, 0.0))
	# Volcanic cave crystal clusters placed on flanking solid rock pedestals outside the tiles
	for index in [14, 17, 23, 27, 34]:
		_add_volcanic_cave_cluster(route[index] + Vector3(4.5, 0.0, 0.0))
	# Solid floating volcanic rocks off to the sides for optional exploration
	for index in [5, 13, 19, 28, 36, 40]:
		_add_floating_volcanic_rock(route[index] + Vector3(4.6 if index % 2 == 0 else -4.6, 0.6, 0.0))

func _add_fire_waterfall(point: Vector3) -> void:
	fire_waterfall_count += 1
	var waterfall := Node3D.new()
	waterfall.name = "FireWaterfall_%02d" % fire_waterfall_count
	waterfall.position = point
	for col in 3:
		var stream := MeshInstance3D.new()
		var s_mesh := BoxMesh.new()
		s_mesh.size = Vector3(0.24, 2.4 + float(col % 2) * 0.5, 0.18)
		stream.mesh = s_mesh
		stream.position = Vector3(float(col - 1) * 0.32, 1.1, 0.0)
		stream.material_override = _material(Color("#ff6218" if col != 1 else "#ffae24"), 2.0)
		waterfall.add_child(stream)
	_world.add_child(waterfall)

func _add_lava_river(point: Vector3) -> void:
	lava_river_count += 1
	var river := MeshInstance3D.new()
	river.name = "LavaRiver_%02d" % lava_river_count
	var box := BoxMesh.new()
	box.size = Vector3(9.5, 0.22, 4.2)
	river.mesh = box
	river.position = point
	river.material_override = _material(Color("#ff4314"), 2.2)
	_world.add_child(river)

func _add_volcanic_cave_cluster(point: Vector3) -> void:
	cave_cluster_count += 1
	var cluster := StaticBody3D.new()
	cluster.name = "VolcanicCaveCluster_%02d" % cave_cluster_count
	cluster.position = point
	var shape := CollisionShape3D.new()
	var c_shape := CylinderShape3D.new()
	c_shape.radius = 0.75
	c_shape.height = 1.4
	shape.shape = c_shape
	shape.position.y = 0.7
	cluster.add_child(shape)

	var base := MeshInstance3D.new()
	var b_cyl := CylinderMesh.new()
	b_cyl.top_radius = 0.85
	b_cyl.bottom_radius = 1.05
	b_cyl.height = 0.55
	base.mesh = b_cyl
	base.material_override = _material(Color("#1d1823"), 0.15)
	cluster.add_child(base)

	for i in 4:
		var shard := MeshInstance3D.new()
		var s_mesh := CylinderMesh.new()
		s_mesh.top_radius = 0.04
		s_mesh.bottom_radius = 0.16 + float(i % 2) * 0.05
		s_mesh.height = 0.85 + float(i) * 0.16
		shard.mesh = s_mesh
		shard.position = Vector3(float(i - 1) * 0.22, 0.25 + s_mesh.height * 0.5, 0.0)
		shard.rotation.z = float(i - 1) * 0.16
		shard.material_override = _material(Color("#ff6a1f"), 1.8)
		cluster.add_child(shard)
	_world.add_child(cluster)

func _add_floating_volcanic_rock(point: Vector3) -> void:
	var rock := StaticBody3D.new()
	rock.name = "FloatingVolcanicRock"
	rock.position = point
	var shape := CollisionShape3D.new()
	var c_shape := CylinderShape3D.new()
	c_shape.radius = 0.95
	c_shape.height = 0.55
	shape.shape = c_shape
	rock.add_child(shape)

	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 0.72
	cyl.height = 0.55
	mesh_inst.mesh = cyl
	mesh_inst.material_override = _material(Color("#221b26"), 0.35)
	rock.add_child(mesh_inst)
	_world.add_child(rock)

func _build_puzzles_and_hazards() -> void:
	var prog := get_node_or_null("/root/Progress")

	# --- Puzzle 1: The Ancient Energy Switch (unlocks Magical Shield & opens SwitchGate) ---
	_energy_switch = EMBER_PUZZLES.AncientEnergySwitch.new()
	_energy_switch.name = "AncientEnergySwitch"
	_energy_switch.position = route[4] + Vector3(0.0, 0.55, 0.9)
	_world.add_child(_energy_switch)
	_switch_gate = _build_gate("AncientEnergyGate", route[4], route[5], Color("#ff6e1f"))
	_energy_switch.activated.connect(func():
		if _switch_gate != null:
			_switch_gate.open()
		if _main != null and _main.has_method("_on_ember_switch_solved"):
			_main.call("_on_ember_switch_solved")
	)
	if prog != null and bool(prog.get("ember_switch_solved")):
		_energy_switch.activate()
		if _switch_gate != null:
			_switch_gate.open()

	# --- Puzzle 2: The Molten River Crossing (horizontal & vertical moving stone platforms) ---
	for entry in [
		[7, -3.6, "horizontal"],
		[9, 3.6, "vertical"],
		[15, -3.6, "horizontal"],
		[25, 3.6, "vertical"],
		[34, -3.6, "horizontal"],
		[39, 3.6, "vertical"],
	]:
		var idx := int(entry[0])
		var x_off := float(entry[1])
		var mode := str(entry[2])
		var platform: Node3D = PLATFORM.instantiate()
		platform.name = "MovingVolcanicPlatform_%02d" % idx
		var origin: Vector3 = route[idx] + Vector3(x_off, 0.45, 2.0)
		platform.position = origin
		platform.scale = Vector3(0.76, 0.45, 0.76)
		platform.set_meta("origin", origin)
		platform.set_meta("phase", float(idx) * 0.65)
		platform.set_meta("mode", mode)
		var m_cap := MeshInstance3D.new()
		var m_box := BoxMesh.new()
		m_box.size = Vector3(2.4, 0.12, 2.4)
		m_cap.mesh = m_box
		m_cap.position.y = 0.48
		m_cap.material_override = _material(Color("#241b28"), 0.35)
		platform.add_child(m_cap)
		_world.add_child(platform)
		_moving_platforms.append(platform)

	# --- Puzzle 3: The Three Magma Crystals (Cave, Moving Platform, Slime-Guarded) ---
	var crystal_specs := [
		[12, Vector3(-1.1, 0.55, 0.6), "Volcanic Cave"],
		[15, Vector3(1.1, 0.55, 0.6), "Moving Platform"],
		[18, Vector3(0.0, 0.55, 0.9), "Magma Slime Guard"],
	]
	for i in crystal_specs.size():
		var spec: Array = crystal_specs[i]
		var crystal: Node3D = EMBER_PUZZLES.MagmaCrystalNode.new()
		crystal.name = "MagmaCrystal_%02d" % int(spec[0])
		crystal.set("crystal_index", i)
		crystal.set("location_hint", str(spec[2]))
		crystal.position = route[int(spec[0])] + (spec[1] as Vector3)
		_world.add_child(crystal)
		_magma_crystals.append(crystal)
		crystal.activated.connect(_on_magma_crystal_activated)
	_crystal_gate = _build_gate("MagmaCrystalGate", route[18], route[19], Color("#ff8a1f"))
	var saved_crystals := int(prog.get("ember_crystals_activated")) if prog != null else 0
	for i in range(mini(saved_crystals, _magma_crystals.size())):
		_magma_crystals[i].activate()
	if saved_crystals >= 3 and _crystal_gate != null:
		_crystal_gate.open()

	# --- Puzzle 4: The Ancient Energy Machines (3 machines in Ancient Energy Mines) ---
	for i in 3:
		var r_idx := 21 + i * 2
		var machine: Node3D = EMBER_PUZZLES.AncientEnergyMachine.new()
		machine.name = "AncientEnergyMachine_%02d" % r_idx
		machine.set("machine_index", i)
		machine.set("target_rotation_step", (i + 1) % 4)
		machine.position = route[r_idx] + Vector3(1.15 if i % 2 == 0 else -1.15, 0.55, 0.65)
		_world.add_child(machine)
		_energy_machines.append(machine)
		machine.activated.connect(_on_energy_machine_activated)
	_machine_gate = _build_gate("EnergyFacilityGate", route[25], route[26], Color("#ffae24"))
	var saved_machines := int(prog.get("ember_machines_activated")) if prog != null else 0
	for i in range(mini(saved_machines, _energy_machines.size())):
		_energy_machines[i].activate()
	if saved_machines >= 3 and _machine_gate != null:
		_machine_gate.open()

	# --- Puzzle 5: The Rising Lava Chamber ---
	_rising_lava_chamber = EMBER_PUZZLES.RisingLavaChamber.new()
	_rising_lava_chamber.name = "RisingLavaChamber"
	_rising_lava_chamber.position = route[28]
	_world.add_child(_rising_lava_chamber)
	_chamber_gate = _build_gate("RisingLavaGate", route[29], route[30], Color("#ff5218"))
	_rising_lava_chamber.solved.connect(func():
		if _chamber_gate != null:
			_chamber_gate.open()
		if _main != null and _main.has_method("_on_ember_rising_lava_solved"):
			_main.call("_on_ember_rising_lava_solved")
	)
	if prog != null and bool(prog.get("ember_rising_lava_solved")) and _chamber_gate != null:
		_chamber_gate.open()

	# --- Puzzle 6: The Obsidian Fortress (Rotating Bridges, Falling Rocks, Fortress Gate) ---
	for r_idx in [32, 35]:
		var bridge: Node3D = EMBER_PUZZLES.RotatingObsidianBridge.new()
		bridge.name = "RotatingObsidianBridge_%02d" % r_idx
		bridge.position = (route[r_idx] + route[r_idx + 1]) * 0.5 + Vector3(0.0, 0.45, 0.0)
		_world.add_child(bridge)
		_rotating_bridges.append(bridge)
	for r_idx in [33, 36, 38]:
		var rock: Node3D = EMBER_PUZZLES.FallingVolcanicRock.new()
		rock.name = "FallingVolcanicRock_%02d" % r_idx
		rock.set("phase_offset", float(r_idx) * 0.5)
		rock.position = route[r_idx] + Vector3(0.65, 0.5, 0.0)
		_world.add_child(rock)
		_falling_rocks.append(rock)
	_fortress_gate = _build_gate("ObsidianFortressGate", route[36], route[37], Color("#b04dff"))
	if prog != null and bool(prog.get("ember_fortress_solved")) and _fortress_gate != null:
		_fortress_gate.open()

	# --- Puzzle 7: The Four Ember Seals before the Ember Dragon's Sanctuary ---
	var seal_specs := [
		["Lava Platform Seal", 37, "lava_platforms"],
		["Energy Machine Seal", 38, "energy_machine"],
		["Magma Crystal Seal", 39, "crystal_sequence"],
		["Volcanic Pack Seal", 40, "enemy_encounter"],
	]
	for i in seal_specs.size():
		var sp: Array = seal_specs[i]
		var seal: Node3D = EMBER_PUZZLES.AncientEmberSeal.new()
		seal.name = "EmberSeal_%d" % i
		seal.set("seal_index", i)
		seal.set("seal_name", str(sp[0]))
		seal.set("challenge_type", str(sp[2]))
		seal.position = route[int(sp[1])] + Vector3(0.0, 0.55, 1.15)
		_world.add_child(seal)
		ember_seals.append(seal)
		seal.activated.connect(_on_ember_seal_activated)

	var saved_seals := int(prog.get("ember_seals_activated")) if prog != null else 0
	for i in range(mini(saved_seals, ember_seals.size())):
		ember_seals[i].activate()
	ember_seals_complete = saved_seals >= ember_seals.size()

func _build_gate(gate_name: String, from_point: Vector3, to_point: Vector3, color: Color) -> StaticBody3D:
	var gate := StaticBody3D.new()
	gate.name = gate_name
	gate.set_script(PUZZLE_GATE)
	gate.position = (from_point + to_point) * 0.5 + Vector3(0.0, 1.5, 0.0)
	var dir := to_point - from_point
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		gate.rotation.y = atan2(dir.x, dir.z)
	var size := Vector3(3.6, 2.3, 0.32)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	gate.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color, 1.35)
	gate.add_child(visual)
	_world.add_child(gate)
	return gate

func _on_magma_crystal_activated(_crystal: Node3D) -> void:
	var count := 0
	for c in _magma_crystals:
		if bool(c.get("is_activated")):
			count += 1
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.call("set_ember_crystals_activated", count)
	if count >= _magma_crystals.size() and _crystal_gate != null:
		_crystal_gate.open()
	if _main != null and _main.has_method("_on_ember_crystal_progress"):
		_main.call("_on_ember_crystal_progress", count, _magma_crystals.size())

func _on_energy_machine_activated(_machine: Node3D) -> void:
	var count := 0
	for m in _energy_machines:
		if bool(m.get("is_activated")):
			count += 1
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.call("set_ember_machines_activated", count)

	# MID-PUZZLE RULE SHIFT:
	# Once 2 machines are activated, the circuit overloads and shifts rules!
	# The final machine reverses its polarity requirement to an inverted step.
	if count == 2 and _energy_machines.size() >= 3:
		var last_machine := _energy_machines[2]
		if not bool(last_machine.get("is_activated")):
			var orig_target: int = int(last_machine.get("target_rotation_step"))
			# Invert target rotation by 180 degrees (2 steps out of 4)
			var inverted_target := (orig_target + 2) % 4
			last_machine.call("apply_rule_shift", inverted_target)
			if _main != null and _main.has_method("_on_island_message"):
				_main.call("_on_island_message", "RULE SHIFT: Circuit Inversion! Align beam to the opposite node!")

	if count >= _energy_machines.size() and _machine_gate != null:
		_machine_gate.open()
	if _main != null and _main.has_method("_on_ember_machine_progress"):
		_main.call("_on_ember_machine_progress", count, _energy_machines.size())

func _on_ember_seal_activated(_seal: Node3D) -> void:
	var count := 0
	for s in ember_seals:
		if bool(s.get("is_activated")):
			count += 1
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.call("set_ember_seals_activated", count)
	if count == 1 and _fortress_gate != null:
		if prog != null:
			prog.call("mark_ember_fortress_solved")
		_fortress_gate.open()
	if count >= ember_seals.size():
		ember_seals_complete = true
		if _dragon != null:
			_dragon.unlock()
		_lock_boss_arena()
	if _main != null and _main.has_method("_on_ember_seal_progress"):
		_main.call("_on_ember_seal_progress", count, ember_seals.size())

func try_activate_nearby(player: Node3D) -> bool:
	if _energy_switch != null and not bool(_energy_switch.get("is_activated")) and _energy_switch.global_position.distance_to(player.global_position) <= 2.6:
		return bool(_energy_switch.call("activate"))
	for crystal in _magma_crystals:
		if not bool(crystal.get("is_activated")) and crystal.global_position.distance_to(player.global_position) <= 2.6:
			return bool(crystal.call("activate"))
	for machine in _energy_machines:
		if not bool(machine.get("is_activated")) and machine.global_position.distance_to(player.global_position) <= 2.8:
			return bool(machine.call("try_interact", player))
	if _rising_lava_chamber != null and bool(_rising_lava_chamber.call("try_interact", player)):
		return true
	for i in ember_seals.size():
		var seal := ember_seals[i]
		if not bool(seal.get("is_activated")) and seal.global_position.distance_to(player.global_position) <= 2.6:
			if i > 0 and not bool(ember_seals[i - 1].get("is_activated")):
				if _main != null and _main.has_method("_on_ember_mechanism_blocked"):
					_main.call("_on_ember_mechanism_blocked", "Activate the previous Ember Seal first.")
				return true
			if i == 1 and _active_machine_count() < 3:
				if _main != null and _main.has_method("_on_ember_mechanism_blocked"):
					_main.call("_on_ember_mechanism_blocked", "Activate all three Ancient Energy Machines first.")
				return true
			if i == 2 and _active_crystal_count() < 3:
				if _main != null and _main.has_method("_on_ember_mechanism_blocked"):
					_main.call("_on_ember_mechanism_blocked", "Find and activate all three Magma Crystals first.")
				return true
			if i == 3 and not _volcanic_enemy_encounter_cleared():
				if _main != null and _main.has_method("_on_ember_mechanism_blocked"):
					_main.call("_on_ember_mechanism_blocked", "Defeat the volcanic monsters before activating the final Ember Seal.")
				return true
			return bool(seal.call("activate"))
	return false

func _active_crystal_count() -> int:
	var c := 0
	for n in _magma_crystals:
		if bool(n.get("is_activated")):
			c += 1
	return c

func _active_machine_count() -> int:
	var c := 0
	for n in _energy_machines:
		if bool(n.get("is_activated")):
			c += 1
	return c

func _volcanic_enemy_encounter_cleared() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is VolcanicEnemy and is_instance_valid(enemy):
			return false
	return true

func _place_coins() -> void:
	# Main route coins (44) + hidden exploration coins (28) = 72 coins (>= 60 required)
	for index in range(1, route.size() - 1):
		_add_coin(route[index] + Vector3(0.0, 1.08 + float(index % 3) * 0.24, 0.0), "ember_%02d" % index)
		coins_placed += 1
	var hidden_spots := [
		# Behind fire waterfalls
		[3, Vector3(-2.1, 1.4, 0.65)],
		[9, Vector3(-2.1, 1.4, 0.65)],
		[15, Vector3(-2.1, 1.4, 0.65)],
		[22, Vector3(-2.1, 1.4, 0.65)],
		[30, Vector3(-2.1, 1.4, 0.65)],
		[38, Vector3(-2.1, 1.4, 0.65)],
		# Inside volcanic caves & near glowing magma crystals
		[12, Vector3(-1.8, 1.5, 0.8)],
		[14, Vector3(1.9, 1.4, 0.6)],
		[17, Vector3(1.9, 1.4, 0.6)],
		[18, Vector3(1.6, 1.5, 0.8)],
		# On top of floating volcanic rocks
		[5, Vector3(-2.8, 2.2, 0.5)],
		[13, Vector3(-2.8, 2.2, 0.5)],
		[19, Vector3(-2.8, 2.2, 0.5)],
		[28, Vector3(2.8, 2.2, 0.5)],
		[36, Vector3(2.8, 2.2, 0.5)],
		[40, Vector3(2.8, 2.2, 0.5)],
		# Behind ancient energy machines & in mine tunnels
		[21, Vector3(2.0, 1.5, 0.9)],
		[23, Vector3(-2.0, 1.5, 0.9)],
		[24, Vector3(2.1, 1.6, 0.4)],
		[25, Vector3(2.0, 1.5, 0.9)],
		[27, Vector3(-2.1, 1.6, 0.5)],
		# Along optional moving-platform & Obsidian Fortress secret routes
		[7, Vector3(-1.4, 1.8, 1.45)],
		[10, Vector3(-2.2, 1.6, 0.5)],
		[29, Vector3(2.2, 1.7, -0.5)],
		[32, Vector3(-2.2, 1.7, 0.5)],
		[34, Vector3(-1.3, 1.8, 1.45)],
		[35, Vector3(2.2, 1.7, 0.5)],
		[42, Vector3(-2.4, 1.6, 0.8)],
	]
	for h_idx in hidden_spots.size():
		var entry: Array = hidden_spots[h_idx]
		var r_i := int(entry[0])
		var offset: Vector3 = entry[1]
		_add_coin(route[r_i] + offset, "ember_hidden_%02d" % h_idx)
		coins_placed += 1

func _add_coin(where: Vector3, persistent_id: String) -> void:
	var coin: Area3D = COIN.instantiate()
	coin.position = where
	coin.set_meta("persistent_coin_id", persistent_id)
	_world.add_child(coin)

func _place_enemies() -> void:
	# Magma Slimes (50% speed, Level 1 Shadow Slime damage) - spawned directly on the platform surface
	for index in [6, 14, 18, 27, 37]:
		_spawn_enemy("Magma Slime", route[index] + Vector3(0.0, 0.50, 0.0))
	# Magma Wolves (110% speed, articulated rig, damage < Shadow Slime) - spawned directly on the platform surface
	for index in [11, 22, 24, 33, 40]:
		_spawn_enemy("Magma Wolf", route[index] + Vector3(0.0, 0.50, 0.0))
	# Lava Phantoms (flying aerial movement, warning ring, fire projectiles)
	for index in [16, 26, 35, 40]:
		_spawn_enemy("Lava Phantom", route[index] + Vector3(0.0, 2.8, 0.0))

	# Final Boss: The Ember Dragon
	_dragon = EMBER_DRAGON.new()
	_dragon.name = "EmberDragon"
	_dragon.position = route[route.size() - 3] + Vector3(0.0, 0.5, 3.2)
	_world.add_child(_dragon)

	# Ancient Magma Chest (Fourth Fragment + Malakar's Fortress projection)
	_chest = FRAGMENT_CHEST.new()
	_chest.name = "FourthFragmentChest"
	_chest.position = route[route.size() - 3] + Vector3(4.8, 0.0, 4.8)
	_world.add_child(_chest)

	_dragon.defeated.connect(_on_boss_defeated)
	var prog := get_node_or_null("/root/Progress")
	if prog != null and bool(prog.get("ember_dragon_defeated")):
		boss_defeated = true
	if ember_seals_complete or boss_defeated:
		_dragon.unlock()
	if ember_seals_complete and not boss_defeated:
		_lock_boss_arena()
	if boss_defeated:
		_dragon.set_process(false)
		_dragon.set_physics_process(false)
		_chest.unlock()
		_unlock_boss_arena()

	_chest.fragment_recovered.connect(func():
		fragment_recovered = true
		recover_environment()
		if _main != null and _main.has_method("_on_ember_fragment_recovered"):
			_main.call("_on_ember_fragment_recovered")
	)
	_chest.fortress_discovered.connect(func():
		fortress_discovered = true
		if _fortress_beam != null:
			_fortress_beam.visible = true
		if _main != null and _main.has_method("_on_malakar_fortress_discovered"):
			_main.call("_on_malakar_fortress_discovered")
	)
	if prog != null:
		fragment_recovered = bool(prog.get("fourth_fragment_recovered"))
		fortress_discovered = bool(prog.get("malakar_fortress_discovered"))
		if fortress_discovered and _fortress_beam != null:
			_fortress_beam.visible = true

	if _main != null and _main.has_method("_bind_ember_boss"):
		_main.call("_bind_ember_boss", _dragon)

func _spawn_enemy(kind: String, where: Vector3) -> void:
	var enemy: VolcanicEnemy = VOLCANIC_ENEMY.new()
	enemy.variant = kind
	enemy.name = kind.replace(" ", "")
	enemy.position = where
	_world.add_child(enemy)

func _build_boss_arena() -> void:
	var centre: Vector3 = route[route.size() - 3] + Vector3(0.0, 0.0, 2.4)
	# Giant volcanic pillars & glowing magma crystals around the outer rim of the circular temple arena
	# Skip i = 6 (south entrance) so no pillar blocks the path into the arena
	for i in [0, 1, 2, 3, 4, 5, 7]:
		var angle := TAU * float(i) / 8.0
		var pillar_body := StaticBody3D.new()
		pillar_body.name = "VolcanicArenaPillar_%d" % i
		pillar_body.position = centre + Vector3(cos(angle) * 11.8, 2.4, sin(angle) * 11.8)
		var p_shape := CollisionShape3D.new()
		var p_cyl := CylinderShape3D.new()
		p_cyl.radius = 0.65
		p_cyl.height = 4.8
		p_shape.shape = p_cyl
		pillar_body.add_child(p_shape)

		var pillar := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.45
		mesh.bottom_radius = 0.72
		mesh.height = 4.8
		pillar.mesh = mesh
		pillar.material_override = _material(Color("#1b1622"), 0.25)
		pillar_body.add_child(pillar)

		var crystal := MeshInstance3D.new()
		var c_cone := CylinderMesh.new()
		c_cone.top_radius = 0.08
		c_cone.bottom_radius = 0.35
		c_cone.height = 1.35
		crystal.mesh = c_cone
		crystal.position = Vector3(0.0, 2.85, 0.0)
		crystal.material_override = _material(Color("#ff5b1f"), 1.9)
		pillar_body.add_child(crystal)
		_world.add_child(pillar_body)

	# Glowing volcanic temple sigil ring
	var sigil := MeshInstance3D.new()
	var s_torus := TorusMesh.new()
	s_torus.inner_radius = 5.2
	s_torus.outer_radius = 5.6
	sigil.mesh = s_torus
	sigil.position = centre + Vector3(0.0, 0.08, 0.0)
	sigil.material_override = _material(Color("#ff6a1f"), 1.6)
	_world.add_child(sigil)

	# Boss arena entrance gate (locks during boss fight)
	_boss_gate = StaticBody3D.new()
	_boss_gate.name = "EmberDragonArenaGate"
	_boss_gate.position = route[route.size() - 4] + Vector3(0.0, 1.35, 1.45)
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(4.8, 2.8, 0.35)
	gate_shape.shape = gate_box
	_boss_gate.add_child(gate_shape)
	var gate_visual := MeshInstance3D.new()
	var gate_mesh := BoxMesh.new()
	gate_mesh.size = gate_box.size
	gate_visual.mesh = gate_mesh
	gate_visual.material_override = _material(Color("#ff4718"), 1.35)
	_boss_gate.add_child(gate_visual)
	_world.add_child(_boss_gate)

func _build_distant_malakar_fortress() -> void:
	# Distant dark floating fortress with huge shadow towers, barrier, and connection beam
	var anchor: Vector3 = route[route.size() - 1] + Vector3(0.0, 9.5, 34.0)
	_distant_fortress = Node3D.new()
	_distant_fortress.name = "DistantMalakarFortress"
	_distant_fortress.position = anchor
	_world.add_child(_distant_fortress)

	var keep := MeshInstance3D.new()
	var k_cyl := CylinderMesh.new()
	k_cyl.top_radius = 2.4
	k_cyl.bottom_radius = 5.5
	k_cyl.height = 11.0
	keep.mesh = k_cyl
	keep.material_override = _material(Color("#1d0d36"), 0.85)
	_distant_fortress.add_child(keep)

	for i in 4:
		var angle := TAU * float(i) / 4.0 + 0.4
		var tower := MeshInstance3D.new()
		tower.name = "ShadowTower_%d" % i
		var t_cyl := CylinderMesh.new()
		t_cyl.top_radius = 0.55
		t_cyl.bottom_radius = 1.25
		t_cyl.height = 14.5
		tower.mesh = t_cyl
		tower.position = Vector3(cos(angle) * 5.8, 2.0, sin(angle) * 5.8)
		tower.material_override = _material(Color("#32145c"), 1.2)
		_distant_fortress.add_child(tower)

	var barrier := MeshInstance3D.new()
	var b_sphere := SphereMesh.new()
	b_sphere.radius = 9.2
	b_sphere.height = 18.4
	barrier.mesh = b_sphere
	var b_mat := _material(Color("#b04dff"), 1.4)
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.albedo_color = Color(0.62, 0.22, 0.95, 0.22)
	barrier.material_override = b_mat
	_distant_fortress.add_child(barrier)

	# Visual connection beam leading toward the next island
	_fortress_beam = MeshInstance3D.new()
	_fortress_beam.name = "FortressRouteBeam"
	var beam_box := BoxMesh.new()
	beam_box.size = Vector3(0.45, 0.25, 28.0)
	_fortress_beam.mesh = beam_box
	_fortress_beam.position = route[route.size() - 1] + Vector3(0.0, 2.5, 16.0)
	_fortress_beam.rotation.x = -0.24
	_fortress_beam.material_override = _material(Color("#c46bff"), 2.2)
	_fortress_beam.visible = false
	_world.add_child(_fortress_beam)

func _add_portal(point: Vector3, color: Color, is_exit: bool = false) -> void:
	portal_count += 1
	var portal := Node3D.new()
	portal.name = "EmberExitPortal" if is_exit else "EmberArrivalPortal"
	portal.position = point + Vector3(0.0, 1.75, 0.0)

	# Volcanic black stone frame & top-mounted magma crystals
	var frame_mat := _material(Color("#18141f"), 0.25)
	for side in [-1.0, 1.0]:
		var pillar_body := StaticBody3D.new()
		pillar_body.position = Vector3(side * 1.25, 0.0, 0.0)
		var p_shape := CollisionShape3D.new()
		var p_box_shape := BoxShape3D.new()
		p_box_shape.size = Vector3(0.32, 2.5, 0.32)
		p_shape.shape = p_box_shape
		pillar_body.add_child(p_shape)

		var pillar := MeshInstance3D.new()
		var p_box := BoxMesh.new()
		p_box.size = Vector3(0.32, 2.5, 0.32)
		pillar.mesh = p_box
		pillar.material_override = frame_mat
		pillar_body.add_child(pillar)
		portal.add_child(pillar_body)

		var shard := MeshInstance3D.new()
		var s_cone := CylinderMesh.new()
		s_cone.top_radius = 0.04
		s_cone.bottom_radius = 0.12
		s_cone.height = 0.42
		shard.mesh = s_cone
		shard.position = Vector3(side * 1.25, 1.46, 0.0)
		shard.material_override = _material(color, 1.8)
		portal.add_child(shard)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.96
	ring_mesh.outer_radius = 1.15
	ring.mesh = ring_mesh
	ring.rotation.x = PI * 0.5
	var ring_mat := _material(color, 1.35)
	ring.material_override = ring_mat
	if is_exit:
		_exit_portal_ring = ring
		_exit_portal_material = ring_mat
	elif _arrival_portal_ring == null:
		_arrival_portal_ring = ring
		_arrival_portal_material = ring_mat
	portal.add_child(ring)

	var surface := MeshInstance3D.new()
	var s_mesh := QuadMesh.new()
	s_mesh.size = Vector2(1.9, 2.8)
	surface.mesh = s_mesh
	var s_mat := _material(Color(color, 0.28), 0.9)
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.material_override = s_mat
	portal.add_child(surface)

	_world.add_child(portal)

func _build_ash_and_embers() -> void:
	var particles := GPUParticles3D.new()
	_ash_particles = particles
	particles.name = "VolcanicAshAndEmbers"
	particles.amount = 200
	particles.lifetime = 5.0
	particles.visibility_aabb = AABB(Vector3(-22.0, -4.0, -6.0), Vector3(44.0, 20.0, 165.0))
	var flake := QuadMesh.new()
	flake.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ff7b24")
	mat.emission_enabled = true
	mat.emission = Color("#ff4e18")
	mat.emission_energy_multiplier = 1.8
	flake.material = mat
	particles.draw_pass_1 = flake
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.15, -0.8, 0.0)
	proc.spread = 22.0
	proc.initial_velocity_min = 0.8
	proc.initial_velocity_max = 2.2
	proc.gravity = Vector3(0.0, -0.15, 0.0)
	proc.scale_min = 0.5
	proc.scale_max = 1.5
	particles.process_material = proc
	particles.position = Vector3(0.0, 10.0, 65.0)
	_world.add_child(particles)

func _process(delta: float) -> void:
	_time += delta
	var prog := get_node_or_null("/root/Progress")
	if prog != null and bool(prog.get("fourth_fragment_recovered")):
		fragment_recovered = true
	if prog != null and bool(prog.get("malakar_fortress_discovered")):
		fortress_discovered = true
	if not arrival_cinematic_complete:
		_arrival_time += delta
		if _arrival_portal_ring != null:
			_arrival_portal_ring.scale = Vector3.ONE * (0.35 + clampf(_arrival_time / 1.4, 0.0, 1.0))
			_arrival_portal_material.emission_energy_multiplier = clampf(_arrival_time / 1.4, 0.0, 1.0) * 1.8
		if _arrival_time >= 1.4:
			arrival_cinematic_complete = true
	if _exit_portal_ring != null and _main != null:
		var current_coins := int(_main.get("coins_collected"))
		var target_energy := 1.0 if is_portal_ready(current_coins) else 0.0
		_portal_energy = move_toward(_portal_energy, target_energy, delta * 0.85)
		_exit_portal_ring.rotate_y(delta * (0.5 + _portal_energy * 1.5))
		_exit_portal_material.emission_energy_multiplier = 0.4 + _portal_energy * 2.0
	for platform in _moving_platforms:
		if not is_instance_valid(platform):
			continue
		var origin: Vector3 = platform.get_meta("origin")
		var phase: float = platform.get_meta("phase")
		var mode := str(platform.get_meta("mode", "horizontal"))
		if mode == "vertical":
			platform.position = origin + Vector3(0.0, sin(_time * 1.4 + phase) * 1.15, 0.0)
		else:
			platform.position = origin + Vector3(sin(_time * 1.15 + phase) * 1.85, sin(_time * 1.6 + phase) * 0.25, 0.0)

func _lock_boss_arena() -> void:
	if boss_arena_locked or _boss_gate == null:
		return
	boss_arena_locked = true
	for shape in _boss_gate.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).set_deferred("disabled", false)

func _unlock_boss_arena() -> void:
	if _boss_gate == null:
		return
	boss_arena_locked = false
	for shape in _boss_gate.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).set_deferred("disabled", true)
	var tween := _boss_gate.create_tween()
	tween.tween_property(_boss_gate, "position:y", _boss_gate.position.y - 2.6, 0.7)

func _on_boss_defeated() -> void:
	boss_defeated = true
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.call("mark_ember_dragon_defeated")
	_unlock_boss_arena()
	if _chest != null:
		_chest.unlock()

func recover_environment() -> void:
	if environment_recovered:
		return
	environment_recovered = true
	for mat in _charred_tree_materials:
		mat.albedo_color = Color("#6be89a")
		mat.emission = Color("#54f4e8")
		mat.emission_energy_multiplier = 0.9
	if _ash_particles != null:
		_ash_particles.amount = 50
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/coin.ogg")

func is_portal_ready(coins: int) -> bool:
	var prog := get_node_or_null("/root/Progress")
	var has_frag := fragment_recovered or (prog != null and bool(prog.get("fourth_fragment_recovered")))
	return boss_defeated and has_frag and coins >= coins_required

func portal_blocked_reason(coins: int) -> String:
	var missing: Array[String] = []
	var prog := get_node_or_null("/root/Progress")
	var has_frag := fragment_recovered or (prog != null and bool(prog.get("fourth_fragment_recovered")))
	if not boss_defeated:
		missing.append("Defeat the Ember Dragon")
	if not has_frag:
		missing.append("Recover the Fourth Fragment")
	if coins < coins_required:
		missing.append("Coins %d/%d (%d more needed)" % [coins, coins_required, coins_required - coins])
	return "Portal locked: " + " • ".join(missing)

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.34
	mat.emission_enabled = emission > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = emission
	return mat
