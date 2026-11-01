class_name WhisperingWoods
extends Node3D

## Level 2 - THE WHISPERING WOODS (Second Fragment of the Eternal Tree).
##
## Connects directly to Level 1 (The Forgotten Island) and reuses the existing
## player controller, camera, combat, health/stamina, coin collection, checkpoint,
## Progress and HUD systems.
##
## Regions along +Z:
##   1. The Forgotten Entrance      z  -8 ..  16  Arrival portal, Checkpoint 1
##   2. The Whispering Meadow       z  18 ..  52  Puzzle 1 (Sleeping Tree), Slime & Wolf
##   3. The Twisted Tree Path       z  54 ..  94  Puzzle 2 (Moving Trees), Checkpoint 2, Creatures
##   4. The Crystal Caves           z  96 .. 134  Checkpoint 3, Puzzle 4 (Crystal Cave)
##   5. The Corrupted Forest & Maze z 136 .. 204  Puzzle 5 (Root Maze), Checkpoint 4, Puzzle 6 (4 Seals)
##   6. The Ancient Guardian's Grove z 205 .. 238 Checkpoint 5, Shadow Wolf Boss, 2nd Fragment, Lvl 3 Portal

signal message(text: String)
signal portal_unlocked
signal puzzle_solved(puzzle_name: String, text: String)
signal boss_fell
signal fragment_taken
signal creature_saved(rescued_count: int, total_count: int)
signal seal_lit_changed(lit_count: int, total_count: int)

const PLATFORM := preload("res://objects/platform.tscn")
const PLATFORM_MEDIUM := preload("res://objects/platform_medium.tscn")
const PLATFORM_GRASS := preload("res://objects/platform_grass_large_round.tscn")
const COIN := preload("res://objects/coin.tscn")
const CLOUD := preload("res://objects/cloud.tscn")
const GRASS_TUFT := preload("res://models/grass.glb")
const GRASS_TUFT_SMALL := preload("res://models/grass-small.glb")

const SLIME_SCRIPT := preload("res://objects/shadow_slime.gd")
const WOLF_SCRIPT := preload("res://objects/shadow_wolf.gd")
const PHANTOM_SCRIPT := preload("res://objects/sky_phantom.gd")
const CREATURE_SCRIPT := preload("res://objects/forest_creature.gd")
const PUZZLES := preload("res://objects/woods_puzzles.gd")

@export var coins_required := 40
@export var total_creatures := 5
@export var total_seals := 4
@export var level_3_scene_path := "res://scenes/level_3.tscn"

const GRASS := Color("#6fd468")
const GRASS_CORRUPT := Color("#4c3c78")
const ROCK := Color("#6f6256")
const ROCK_CAVE := Color("#3d3552")
const STONE := Color("#918da1")
const STONE_DEEP := Color("#5f5a70")
const BARK := Color("#69462d")
const BARK_DARK := Color("#3d2838")
const LEAF_BRIGHT := Color("#57cc6e")
const LEAF_GOLD := Color("#8be060")
const LEAF_CORRUPT := Color("#5b3882")
const VINE_GREEN := Color("#49eb8c")
const CRYSTAL_CYAN := Color("#5ceeff")
const MAGIC_VIOLET := Color("#b06bff")

var spawn_point := Vector3(0.0, 0.55, -2.0)
var arrival_portal_position := Vector3(0.0, 0.55, -6.2)
var portal_position := Vector3(0.0, 8.55, 233.5)
var waypoints: Array = []
var checkpoint_points: Array = []
var coins_placed := 0
var coins_collected := 0
var slimes_placed := 0
var wolves_placed := 0
var phantoms_placed := 0
var creatures_rescued_count := 0

var _main: Node = null
var _surfaces: Array[Dictionary] = []
var _solved: Dictionary = {}
var _gates: Dictionary = {}
var _raisers: Dictionary = {}

var _seeds_planted := 0
var _moving_tree_step := 0
var _switches_123: Array = []
var _mirrors: Array = []
var _seals: Array = []
var _creatures: Array[ForestCreature] = []
var _boss: ShadowWolfBoss = null
var _chest: WoodsChest = null
var _ancient_tree_crown: MeshInstance3D = null
var _portal_disc: MeshInstance3D = null
var _portal_material: StandardMaterial3D = null
var _unlocked := false
var _prompt_cooldown := 0.0
var _time := 0.0


func build(main: Node) -> void:
	_main = main
	spawn_point = Vector3(0.0, 0.55, 1.2)
	_build_region_1_entrance()
	_build_region_2_meadow()
	_build_region_3_twisted_path()
	_build_region_4_crystal_caves()
	_build_region_5_corrupted_maze()
	_build_region_6_guardian_grove()
	_build_flanks_and_backdrop()
	_build_all_puzzles()
	_spawn_all_enemies()
	_place_coins()
	_setup_environment()
	print("[WhisperingWoods] built: %d coins placed (%d required), %d checkpoints, %d slimes, %d wolves, %d phantoms, %d creatures" % [
		coins_placed, coins_required, checkpoint_points.size(),
		slimes_placed, wolves_placed, phantoms_placed, _creatures.size()
	])


func _process(delta: float) -> void:
	_time += delta
	_prompt_cooldown = maxf(_prompt_cooldown - delta, 0.0)
	if _portal_disc != null:
		_portal_disc.rotation.z = _time * (2.4 if is_portal_ready() else 0.5)
	if _portal_material != null:
		var target_energy := 2.4 if is_portal_ready() else 0.35
		_portal_material.emission_energy_multiplier = lerpf(
			_portal_material.emission_energy_multiplier, target_energy, delta * 3.0)


# --- Portal & Progression Queries --------------------------------------------

func is_boss_defeated() -> bool:
	return _boss == null or not is_instance_valid(_boss) or _boss.is_defeated


func has_second_fragment() -> bool:
	var prog := get_node_or_null("/root/Progress")
	return prog != null and bool(prog.get("second_fragment_recovered"))


func has_first_fragment() -> bool:
	var prog := get_node_or_null("/root/Progress")
	return prog != null and bool(prog.get("fragment_recovered"))


func is_portal_ready() -> bool:
	return coins_collected >= coins_required and is_boss_defeated() and has_second_fragment()


func coins_needed() -> int:
	return maxi(0, coins_required - coins_collected)


func portal_blocked_reason() -> String:
	if coins_collected < coins_required and not is_boss_defeated():
		return "Portal locked (%d/%d coins, %d more needed) - and the Shadow Wolf Guardian still holds the grove." % [
			coins_collected, coins_required, coins_needed()]
	if not is_boss_defeated():
		return "Coins ready (%d/%d), but the Shadow Wolf Guardian must be defeated first!" % [
			coins_collected, coins_required]
	if not has_second_fragment():
		return "The Shadow Wolf is defeated - open the ancient chest and recover the Second Fragment!"
	if coins_collected < coins_required:
		var m := coins_needed()
		return "Portal inactive (%d/%d coins) - find %d more %s in the Whispering Woods." % [
			coins_collected, coins_required, m, "coin" if m == 1 else "coins"]
	return ""


func notify_coins(count: int) -> void:
	coins_collected = count
	var prog := get_node_or_null("/root/Progress")
	if prog != null and prog.has_method("record_woods_coins"):
		prog.call("record_woods_coins", coins_collected)
	main_objective()
	if not _unlocked and is_portal_ready():
		_unlocked = true
		message.emit("The path to the third island has opened!")
		portal_unlocked.emit()


func main_objective() -> void:
	var hud: Node = _main.get("hud") as Node if _main != null else null
	if hud == null:
		return
	if hud.has_method("set_woods_status"):
		hud.call("set_woods_status", creatures_rescued_count, total_creatures, seals_activated_count(), total_seals, has_second_fragment())
	if is_portal_ready():
		hud.call("set_objective", "The path to the third island has opened - step through the Level 3 portal!")
		return
	if not is_puzzle_solved("sleeping_tree"):
		hud.call("set_objective", "Wake the sleeping tree  •  Coins: %d/%d  •  Creatures: %d/%d" % [
			coins_collected, coins_required, creatures_rescued_count, total_creatures])
	elif not is_puzzle_solved("moving_trees"):
		hud.call("set_objective", "Align the Moving Trees (1-2-3 leaf clue)  •  Creatures: %d/%d" % [
			creatures_rescued_count, total_creatures])
	elif not is_puzzle_solved("crystal_cave"):
		hud.call("set_objective", "Open the Crystal Cave by aligning all 3 crystal mirrors")
	elif not is_puzzle_solved("root_maze"):
		hud.call("set_objective", "Escape the Root Maze and throw the root switch")
	elif not is_puzzle_solved("forest_seals"):
		hud.call("set_objective", "Activate all four Forest Seals (%d/%d) to open the Guardian's Grove" % [
			seals_activated_count(), total_seals])
	elif not is_boss_defeated():
		hud.call("set_objective", "Defeat the Shadow Wolf Guardian in the grove!")
	elif not has_second_fragment():
		hud.call("set_objective", "Recover the Second Fragment from the ancient chest!")
	else:
		hud.call("set_objective", "Find %d coins to unlock the portal (%d more needed)" % [
			coins_required, coins_needed()])


# --- Region 1: The Forgotten Entrance ----------------------------------------

func _build_region_1_entrance() -> void:
	_stone_slab(0.0, 0.0, 2.0, 8.5, 3.2)
	waypoints = [
		Vector3(0.0, 0.55, 1.2),
		Vector3(0.0, 0.55, 6.0),
		Vector3(0.0, 0.95, 13.0),
	]
	# Five checkpoints as required by Section 9:
	# 1. Arrival area, 2. After Moving Trees, 3. Crystal Cave entrance,
	# 4. After Root Maze, 5. Before Shadow Wolf boss arena.
	checkpoint_points = [
		Vector3(0.0, 0.0, -4.4),
		Vector3(0.0, 2.6, 82.0),
		Vector3(0.0, 3.4, 98.0),
		Vector3(0.0, 6.4, 170.0),
		Vector3(0.0, 8.0, 206.5),
	]
	# Arrival portal behind the player (opens on arrival and links back to Level 1)
	_build_arrival_portal(arrival_portal_position)
	_scatter_tufts(0.0, 0.0, 2.0, 7.2, 12)
	_rounded_tree(0.0, -5.8, 1.5, 4.4, LEAF_BRIGHT)
	_rounded_tree(0.0, 5.8, 2.2, 4.2, LEAF_GOLD)
	_flower(Vector3(-3.2, 0.0, 3.6), 1.7, Color("#ff8ec9"))
	_flower(Vector3(3.4, 0.0, 4.2), 1.7, Color("#ffd35c"))
	_motes(0.8, 0.0, 2.0, 28, Color("#9effb8"), 6.0)
	_platform(0.4, 0.0, 13.2, "medium")


func _build_arrival_portal(where: Vector3) -> void:
	var base := Node3D.new()
	base.name = "ArrivalPortal"
	base.position = where
	add_child(base)
	for side in [-1.0, 1.0]:
		_box_solid(base, Vector3(0.65, 3.2, 0.85), _mat(STONE_DEEP), Vector3(side * 1.9, 1.1, 0.0))
	_box_solid(base, Vector3(4.6, 0.65, 0.95), _mat(STONE), Vector3(0.0, 2.9, 0.0))
	var swirl_mat := _glow_mat(CRYSTAL_CYAN, VINE_GREEN, 1.8)
	var disc := _cylinder(base, 1.55, 0.1, swirl_mat, Vector3(0.0, 1.5, 0.0), Vector3(90.0, 0.0, 0.0))
	disc.name = "ArrivalPortalDisc"
	var area := Area3D.new()
	area.name = "ArrivalPortalArea"
	area.position = Vector3(0.0, 1.0, 1.2)
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	shape.shape = sphere
	area.add_child(shape)
	area.body_entered.connect(func(body: Node3D):
		if body != null and body.is_in_group("player") and _prompt_cooldown <= 0.0:
			_prompt_cooldown = 2.5
			message.emit("The arrival portal shimmers - leading back to the Forgotten Island.")
	)
	base.add_child(area)


# --- Region 2: The Whispering Meadow (Puzzle 1: Sleeping Tree) ---------------

func _build_region_2_meadow() -> void:
	_grass_slab(0.8, 0.0, 22.0, 5.5, 2.8)
	_rounded_tree(0.8, -3.8, 21.0, 4.6, LEAF_BRIGHT)
	_rounded_tree(0.8, 4.0, 23.5, 4.2, LEAF_GOLD)
	_platform(1.0, -2.2, 30.2, "medium")
	_platform(1.1, 2.2, 30.2, "medium")
	_grass_slab(1.2, 0.0, 38.0, 6.2, 3.0)
	_waterfall(Vector3(8.5, 6.5, 36.0), 3.0, 18.0)
	_rock(1.4, 5.2, 35.0, 1.35, 0.4, true)
	_motes(1.4, 0.0, 38.0, 30, Color("#88ffaa"), 7.0)


# --- Region 3: The Twisted Tree Path (Puzzle 2: Moving Trees) ----------------

func _build_region_3_twisted_path() -> void:
	_grass_slab(2.0, 0.0, 57.0, 5.2, 2.8)
	_rounded_tree(2.0, -3.8, 56.5, 4.5, LEAF_BRIGHT)
	_platform(2.2, 0.0, 64.6, "medium")
	_grass_slab(2.4, 0.0, 70.0, 4.5, 2.6)
	# Puzzle 2 bridge spans z = 74.0 .. 78.8 when solved
	_grass_slab(2.6, 0.0, 84.0, 5.4, 2.8)
	_platform(3.0, 0.0, 91.8, "medium")
	_rock(2.8, -4.6, 86.0, 1.35, 1.1, true)


# --- Region 4: The Crystal Caves (Puzzle 4: Crystal Cave) --------------------

func _build_region_4_crystal_caves() -> void:
	_stone_slab(3.4, 0.0, 100.0, 6.0, 3.0)
	_platform(3.6, -2.4, 108.4, "medium")
	_platform(3.8, 2.4, 112.4, "medium")
	_stone_slab(4.0, 0.0, 122.0, 7.5, 3.2)
	for spot in [Vector3(-5.2, 4.0, 118.0), Vector3(5.2, 4.0, 118.0), Vector3(-5.5, 4.0, 126.0), Vector3(5.5, 4.0, 126.0)]:
		_crystal_cluster(spot, 1.8)
	_rock(4.6, 5.8, 114.0, 1.4, 0.6, true)
	_platform(4.4, 0.0, 132.4, "medium")


# --- Region 5: The Corrupted Forest & Root Maze (Puzzles 5 & 6) --------------

func _build_region_5_corrupted_maze() -> void:
	_grass_slab(4.8, 0.0, 140.0, 5.5, 2.8, true, GRASS_CORRUPT)
	_rounded_tree(4.8, -4.0, 139.0, 4.4, LEAF_CORRUPT)
	_rounded_tree(4.8, 4.0, 141.0, 4.4, LEAF_CORRUPT)

	# Root Maze platforms (z = 147 .. 163), including moving & rotating roots
	var root_a := PUZZLES.MovingRootPlatform.new()
	root_a.name = "RootMaze_Vertical"
	root_a.mode = "vertical"
	root_a.amplitude = 0.65
	root_a.position = Vector3(0.0, 5.2, 147.8)
	add_child(root_a)
	_record_surface(Vector3(0.0, 5.2, 147.8), 1.4)

	_platform(5.5, -3.2, 151.6, "medium")
	_platform(5.5, 3.2, 151.6, "medium")

	var root_b := PUZZLES.MovingRootPlatform.new()
	root_b.name = "RootMaze_Rotate"
	root_b.mode = "rotate"
	root_b.length = 3.2
	root_b.position = Vector3(0.0, 5.8, 155.8)
	add_child(root_b)
	_record_surface(Vector3(0.0, 5.8, 155.8), 1.6)

	var root_c := PUZZLES.MovingRootPlatform.new()
	root_c.name = "RootMaze_Horizontal"
	root_c.mode = "horizontal"
	root_c.amplitude = 1.2
	root_c.position = Vector3(0.0, 6.1, 160.2)
	add_child(root_c)
	_record_surface(Vector3(0.0, 6.1, 160.2), 1.4)

	# Checkpoint 4 & Seal Hub after the Root Maze
	_grass_slab(6.4, 0.0, 171.0, 6.5, 3.0, true, GRASS_CORRUPT)
	# West & East Seal Terraces + North Seal Approach
	_platform(6.6, -5.2, 179.0, "medium")
	_grass_slab(6.8, -8.8, 183.5, 3.4, 2.4, true, GRASS)
	_platform(6.6, 5.2, 179.0, "medium")
	_grass_slab(6.8, 8.8, 183.5, 3.4, 2.4, true, GRASS)

	_platform(6.7, 0.0, 180.0, "medium")
	_platform(7.0, 0.0, 185.0, "medium")
	_grass_slab(7.4, 0.0, 193.0, 5.2, 3.0, true, GRASS_CORRUPT)
	_platform(7.7, 0.0, 201.2, "medium")


# --- Region 6: The Ancient Guardian's Grove & Portal to Level 3 --------------

func _build_region_6_guardian_grove() -> void:
	# Approach platform with Checkpoint 5 (spaced cleanly between tile at 201.2 and arena at 213.5)
	_stone_slab(8.0, 0.0, 206.5, 2.8, 2.8)
	# Large circular Boss Arena (radius 8.4, edge at 209.6 to 226.4)
	_grass_slab(8.0, 0.0, 218.0, 8.4, 3.4, true, GRASS)
	# Perimeter trees framing only the sides and back of the arena (leaving the entire front/approach completely open)
	for i in [0, 1, 2, 3, 4]:
		var angle := TAU * float(i) / 8.0
		var spot := Vector3(cos(angle) * 7.5, 8.0, 218.0 + sin(angle) * 7.5)
		_rounded_tree(8.0, spot.x, spot.z, 4.8, LEAF_CORRUPT if i % 2 == 0 else LEAF_BRIGHT)

	# Central Ancient Tree on the back rim of the grove
	var ancient_tree := Node3D.new()
	ancient_tree.name = "CentralAncientTree"
	ancient_tree.position = Vector3(0.0, 8.0, 224.5)
	_cylinder(ancient_tree, 0.85, 5.6, _mat(BARK), Vector3(0.0, 2.8, 0.0), Vector3.ZERO, 0.55)
	_ancient_tree_crown = _sphere(ancient_tree, 3.2, _glow_mat(LEAF_CORRUPT, MAGIC_VIOLET, 0.45), Vector3(0.0, 5.8, 0.0), Vector3(1.2, 0.85, 1.2))
	add_child(ancient_tree)

	# Shadow Wolf Boss
	_boss = ShadowWolfBoss.new()
	_boss.name = "ShadowWolfBoss"
	_boss.home = Vector3(0.0, 8.0, 218.0)
	_boss.arena_radius = 7.2
	_boss.set_woods(self)
	add_child(_boss)
	_boss.global_position = _boss.home
	_boss.rotation.y = PI

	# Ancient Chest holding the Second Fragment
	_chest = WoodsChest.new()
	_chest.name = "SecondFragmentChest"
	_chest.woods = self
	_chest.position = Vector3(0.0, 8.0, 222.2)
	_chest.rotation.y = PI
	add_child(_chest)
	_record_surface(Vector3(0.0, 8.0, 222.2), 1.2)

	# Portal Terrace to Level 3 (placed cleanly behind arena, edge at 227.0 to 232.0)
	_stone_slab(8.0, 0.0, 229.5, 2.5, 3.0)
	portal_position = Vector3(0.0, 8.55, 229.5)
	_build_level_3_portal(portal_position)


func _build_level_3_portal(where: Vector3) -> void:
	var base := Node3D.new()
	base.name = "PortalToLevel3"
	base.position = where
	add_child(base)

	# Ancient wooden & stone frame with glowing green vines
	for side in [-1.0, 1.0]:
		_box_solid(base, Vector3(0.75, 3.5, 0.9), _mat(BARK), Vector3(side * 2.1, 1.2, 0.0))
		_cylinder(base, 0.16, 3.4, _glow_mat(VINE_GREEN, VINE_GREEN, 1.4), Vector3(side * 1.75, 1.2, 0.35))
	_box_solid(base, Vector3(5.2, 0.75, 1.05), _mat(STONE), Vector3(0.0, 3.0, 0.0))

	_portal_material = _glow_mat(CRYSTAL_CYAN, MAGIC_VIOLET, 0.6)
	_portal_disc = _cylinder(base, 1.7, 0.12, _portal_material, Vector3(0.0, 1.6, 0.0), Vector3(90.0, 0.0, 0.0))
	_motes(where.y, where.x, where.z - 0.8, 28, VINE_GREEN, 4.0)

	var area := Area3D.new()
	area.name = "PortalPrompt"
	area.position = Vector3(0.0, 0.6, -0.6)
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.8
	shape.shape = sphere
	area.add_child(shape)
	area.body_entered.connect(func(body: Node3D):
		if body != null and body.is_in_group("player") and _prompt_cooldown <= 0.0:
			_prompt_cooldown = 2.5
			if is_portal_ready():
				message.emit("The path to the third island has opened!")
			else:
				message.emit(portal_blocked_reason())
	)
	base.add_child(area)


# --- Puzzles 1 to 6 ----------------------------------------------------------

func _build_all_puzzles() -> void:
	# Puzzle 1: The Sleeping Tree (3 seeds + 3 sockets -> branch bridge across z = 45..52)
	var sleeping_tree := Node3D.new()
	sleeping_tree.name = "SleepingTree"
	sleeping_tree.position = Vector3(-4.2, 1.2, 41.5)
	_cylinder(sleeping_tree, 0.95, 4.8, _mat(BARK), Vector3(0.0, 2.4, 0.0), Vector3.ZERO, 0.65)
	_sphere(sleeping_tree, 2.8, _mat(LEAF_BRIGHT), Vector3(0.0, 5.0, 0.0), Vector3(1.15, 0.85, 1.15))
	add_child(sleeping_tree)

	for seed_spot in [Vector3(-2.6, 0.8, 22.0), Vector3(2.8, 1.2, 36.5), Vector3(-2.8, 1.2, 39.2)]:
		var seed_node := PUZZLES.SleepingTreeSeed.new()
		seed_node.woods = self
		seed_node.position = seed_spot
		add_child(seed_node)

	for sock_spot in [Vector3(-1.8, 1.2, 41.8), Vector3(0.0, 1.2, 42.2), Vector3(1.8, 1.2, 41.8)]:
		var sock := PUZZLES.SleepingTreeSocket.new()
		sock.woods = self
		sock.position = sock_spot
		add_child(sock)

	for plank in [[1.4, 0.0, 45.8], [1.6, 0.0, 48.6], [1.8, 0.0, 51.4]]:
		_build_gated_bridge("sleeping_tree", float(plank[0]), float(plank[1]), float(plank[2]), 1.1)

	# Puzzle 2: The Moving Trees (1-2-3 leaf-clue switches -> tree bridge across z = 75..80)
	var switch_specs := [
		[Vector3(-3.0, 2.0, 57.0), 1],
		[Vector3(3.0, 2.0, 57.0), 2],
		[Vector3(0.0, 2.4, 70.0), 3],
	]
	for spec in switch_specs:
		var sw := PUZZLES.SequenceTreeSwitch.new()
		sw.woods = self
		sw.position = spec[0]
		sw.order_index = int(spec[1])
		add_child(sw)
		_switches_123.append(sw)

	for plank in [[2.45, 0.0, 75.4], [2.5, 0.0, 78.2]]:
		_build_gated_bridge("moving_trees", float(plank[0]), float(plank[1]), float(plank[2]), 1.1)

	# Puzzle 3: Five Lost Forest Creatures
	var creature_plans := [
		["sprout_01", "Pip", Vector3(3.2, 0.8, 21.5), Vector3(-2.5, 0.0, 1.5), "", Color("#7bf2b5")],
		["sprout_02", "Lumi", Vector3(-3.2, 2.6, 84.0), Vector3(2.5, 0.0, 1.5), "moving_trees", Color("#80e5ff")],
		["sprout_03", "Bramble", Vector3(-4.5, 4.0, 121.0), Vector3(-3.5, 8.0, 224.0), "", Color("#ffe07d")],
		["sprout_04", "Fern", Vector3(4.2, 6.4, 171.0), Vector3(3.5, 8.0, 224.0), "root_maze", Color("#ff9de6")],
		["sprout_05", "Willow", Vector3(-8.8, 6.8, 184.5), Vector3(0.0, 8.0, 227.2), "", Color("#a5ff7d")],
	]
	for cp in creature_plans:
		var c := CREATURE_SCRIPT.new()
		c.creature_id = str(cp[0])
		c.creature_name = str(cp[1])
		c.position = cp[2]
		c.safe_spot = cp[3]
		c.required_puzzle = str(cp[4])
		c.body_color = cp[5]
		c.woods = self
		add_child(c)
		_creatures.append(c)
		if c.is_rescued:
			creatures_rescued_count += 1

	# Puzzle 4: The Crystal Cave (3 rotatable crystal mirrors + CaveGate at z = 128.0)
	for m_spot in [Vector3(-3.8, 4.0, 119.5), Vector3(0.0, 4.0, 122.0), Vector3(3.8, 4.0, 119.5)]:
		var mirror := PUZZLES.CrystalMirror.new()
		mirror.woods = self
		mirror.position = m_spot
		mirror.target_steps = 1
		add_child(mirror)
		_mirrors.append(mirror)

	var cave_gate := IslandGate.new()
	cave_gate.name = "CaveGate"
	cave_gate.solved_name = "crystal_cave"
	cave_gate.width = 12.0
	cave_gate.position = Vector3(0.0, 4.0, 127.8)
	add_child(cave_gate)
	_register_gate("crystal_cave", cave_gate)
	_gate_off("crystal_cave", 127.8)

	# Puzzle 5: The Root Maze switch & gate at z = 165.0
	var maze_switch := IslandSwitch.new()
	maze_switch.name = "RootMazeSwitch"
	maze_switch.island = self as Variant
	maze_switch.solved_name = "root_maze"
	maze_switch.tutorial = "A glowing root switch at the heart of the maze. Press E to clear the tangled barrier!"
	maze_switch.success = "The giant roots part - the way out of the Root Maze is open!"
	maze_switch.position = Vector3(3.2, 5.5, 151.6)
	add_child(maze_switch)

	var maze_gate := IslandGate.new()
	maze_gate.name = "RootMazeGate"
	maze_gate.solved_name = "root_maze"
	maze_gate.width = 11.0
	maze_gate.position = Vector3(0.0, 6.2, 165.0)
	add_child(maze_gate)
	_register_gate("root_maze", maze_gate)
	_gate_off("root_maze", 165.0)

	# Puzzle 6: The Four Ancient Forest Seals & GroveGate at z = 198.5
	var seal_crystal_sw := IslandSwitch.new()
	seal_crystal_sw.name = "SealCrystalSwitch"
	seal_crystal_sw.island = self as Variant
	seal_crystal_sw.solved_name = "seal_crystal"
	seal_crystal_sw.position = Vector3(-5.2, 6.6, 179.0)
	add_child(seal_crystal_sw)

	var seal_timed_sw := IslandSwitch.new()
	seal_timed_sw.name = "SealTimedSwitch"
	seal_timed_sw.island = self as Variant
	seal_timed_sw.solved_name = "seal_timed"
	seal_timed_sw.position = Vector3(5.2, 6.6, 179.0)
	add_child(seal_timed_sw)

	var seal_specs := [
		["tree_climb", "The Canopy Seal", "climb", "", Vector3(-8.8, 6.8, 182.5)],
		["crystal_beam", "The Prism Seal", "crystal", "seal_crystal", Vector3(-3.8, 7.4, 192.0)],
		["timed_roots", "The Root-Pulse Seal", "timed", "seal_timed", Vector3(8.8, 6.8, 182.5)],
		["pack_ward", "The Pack-Ward Seal", "enemies", "", Vector3(3.8, 7.4, 192.0)],
	]
	for sp in seal_specs:
		var seal := PUZZLES.AncientForestSeal.new()
		seal.name = "ForestSeal_%s" % sp[0]
		seal.seal_id = str(sp[0])
		seal.seal_title = str(sp[1])
		seal.challenge_type = str(sp[2])
		seal.required_puzzle = str(sp[3])
		seal.position = sp[4]
		seal.woods = self
		add_child(seal)
		_seals.append(seal)

	var grove_gate := IslandGate.new()
	grove_gate.name = "GroveGate"
	grove_gate.solved_name = "forest_seals"
	grove_gate.width = 12.0
	grove_gate.position = Vector3(0.0, 7.4, 198.5)
	add_child(grove_gate)
	_register_gate("forest_seals", grove_gate)
	_gate_off("forest_seals", 198.5)


# --- Puzzle Callbacks & Dev Hooks --------------------------------------------

func is_puzzle_solved(puzzle: String) -> bool:
	return bool(_solved.get(puzzle, false))


func solve_puzzle(puzzle: String, text := "") -> void:
	if is_puzzle_solved(puzzle):
		return
	_solved[puzzle] = true
	if _gates.has(puzzle):
		for gate in _gates[puzzle]:
			if is_instance_valid(gate):
				(gate as IslandGate).open()
	if _raisers.has(puzzle):
		for raiser in _raisers[puzzle]:
			(raiser as Callable).call()
	if not text.is_empty():
		message.emit(text)
	puzzle_solved.emit(puzzle, text)
	main_objective()


func solve_all_puzzles() -> void:
	for p in ["sleeping_tree", "moving_trees", "crystal_cave", "root_maze", "seal_crystal", "seal_timed", "forest_seals"]:
		solve_puzzle(p)


func on_tree_seed_planted() -> void:
	_seeds_planted += 1
	if _seeds_planted >= 3:
		solve_puzzle("sleeping_tree", "The Sleeping Tree awakens and extends its branches into a bridge!")
	else:
		message.emit("Tree seed planted (%d of 3)!" % _seeds_planted)


func on_moving_tree_switch(sw: Node) -> void:
	var idx := int(sw.get("order_index"))
	if idx == _moving_tree_step + 1:
		_moving_tree_step = idx
		sw.call("set_lit", true)
		Audio.play("res://sounds/coin.ogg")
		if _moving_tree_step >= 3:
			solve_puzzle("moving_trees", "The Moving Trees align in sequence and form a path across the forest!")
		else:
			message.emit("Nature switch %d of 3 aligned!" % _moving_tree_step)
	else:
		_moving_tree_step = 0
		for node in _switches_123:
			node.call("set_lit", false)
		message.emit("The trees shift back - follow the glowing leaf-count clues (1, then 2, then 3)!")


func on_crystal_mirror_turned(_mirror: Node) -> void:
	var aligned_count := 0
	for m in _mirrors:
		if bool(m.call("is_aligned")):
			aligned_count += 1
	if aligned_count >= _mirrors.size():
		solve_puzzle("crystal_cave", "All three crystal mirrors focus the light beam - the Crystal Cave door opens!")
	else:
		message.emit("Crystal beams aligned: %d of %d" % [aligned_count, _mirrors.size()])


func on_creature_rescued(creature: ForestCreature) -> void:
	creatures_rescued_count = 0
	for c in _creatures:
		if is_instance_valid(c) and c.is_rescued:
			creatures_rescued_count += 1
	message.emit("%s rescued! (%d of %d forest creatures safe)" % [
		creature.creature_name, creatures_rescued_count, total_creatures])
	creature_saved.emit(creatures_rescued_count, total_creatures)
	main_objective()


func seals_activated_count() -> int:
	var count := 0
	for s in _seals:
		if is_instance_valid(s) and bool(s.get("is_active")):
			count += 1
	return count


func on_forest_seal_activated(seal: Node) -> void:
	var lit := seals_activated_count()
	seal_lit_changed.emit(lit, total_seals)
	if lit >= total_seals:
		solve_puzzle("forest_seals", "All four Ancient Forest Seals are lit - the Guardian's Grove opens!")
	else:
		message.emit("%s activated (%d of %d Forest Seals lit)!" % [
			str(seal.get("seal_title")), lit, total_seals])


func set_arena_locked(_locked: bool) -> void:
	# No entrance barrier
	pass


func boss_defeated() -> void:
	if _ancient_tree_crown != null:
		_ancient_tree_crown.material_override = _glow_mat(LEAF_BRIGHT, VINE_GREEN, 1.4)
	if _chest != null:
		_chest.retract_roots()
	message.emit("The Shadow Wolf Guardian dissolves into light - the Ancient Tree glows and unbinds the chest!")
	boss_fell.emit()
	main_objective()


func fragment_recovered() -> void:
	fragment_taken.emit()
	main_objective()
	if not _unlocked and is_portal_ready():
		_unlocked = true
		message.emit("The path to the third island has opened!")
		portal_unlocked.emit()


# --- Enemies: Slimes, Wolves, and Phantoms -----------------------------------

func _spawn_all_enemies() -> void:
	# Returning Level 1 Shadow Slimes (exact same script, 50% speed, 4% HP hit)
	var slime_spots := [
		Vector3(0.0, 0.85, 22.0),
		Vector3(-2.5, 4.05, 122.0),
		Vector3(2.5, 4.05, 122.0),
		Vector3(2.8, 7.45, 192.0),
	]
	for spot in slime_spots:
		var slime: ShadowSlime = SLIME_SCRIPT.new()
		slime.name = "WoodsSlime_%02d" % slimes_placed
		slime.position = spot
		add_child(slime)
		slimes_placed += 1

	# New Shadow Wolves (125% player speed, damage < Shadow Slime)
	var wolf_spots := [
		Vector3(0.0, 1.25, 37.5),
		Vector3(0.0, 2.05, 57.0),
		Vector3(0.0, 4.05, 124.5),
		Vector3(0.0, 6.45, 171.0),
		Vector3(4.2, 7.45, 193.0),
	]
	for spot in wolf_spots:
		var wolf: ShadowWolf = WOLF_SCRIPT.new()
		wolf.name = "ShadowWolf_%02d" % wolves_placed
		wolf.position = spot
		add_child(wolf)
		wolves_placed += 1

	# New Sky Phantoms (flying across gaps in the Root Maze & Seal Terraces)
	var phantom_spots := [
		Vector3(0.0, 7.2, 154.0),
		Vector3(-5.0, 8.2, 180.0),
		Vector3(4.5, 9.0, 192.5),
	]
	for spot in phantom_spots:
		var phantom: SkyPhantom = PHANTOM_SCRIPT.new()
		phantom.name = "SkyPhantom_%02d" % phantoms_placed
		phantom.position = spot
		add_child(phantom)
		phantoms_placed += 1


# --- 52 Hidden & Path Coins (40 required for the Level 3 Portal) -------------

func _place_coins() -> void:
	var spots: Array = [
		# Region 1: Forgotten Entrance (5)
		[0.0, -2.5, 1.0, 0.8],
		[0.0, 2.5, 1.0, 0.8],
		[0.0, -4.5, 4.5, 0.8],
		[0.0, 4.5, 4.5, 0.8],
		[0.4, 0.0, 13.2, 0.8],
		# Region 2: Whispering Meadow & Waterfall (10)
		[0.8, -2.0, 20.5, 0.8],
		[0.8, 2.0, 20.5, 0.8],
		[0.8, 0.0, 24.5, 0.8],
		[1.0, -2.2, 30.2, 0.8],
		[1.1, 2.2, 30.2, 0.8],
		[1.2, -3.5, 36.5, 0.8],
		[1.2, 3.5, 36.5, 0.8],
		[1.2, 0.0, 40.0, 0.8],
		[1.4, 5.2, 35.0, 0.8],
		[1.4, 5.6, 35.4, 1.1],
		# Region 3: Twisted Tree Path (9)
		[2.0, -2.4, 55.5, 0.8],
		[2.0, 2.4, 55.5, 0.8],
		[2.0, 0.0, 59.0, 0.8],
		[2.2, 0.0, 64.6, 0.8],
		[2.4, -2.0, 69.5, 0.8],
		[2.4, 2.0, 69.5, 0.8],
		[2.6, -2.5, 83.5, 0.8],
		[2.6, 2.5, 83.5, 0.8],
		[2.8, -4.6, 86.0, 0.8],
		# Region 4: Crystal Caves (10)
		[3.0, 0.0, 91.8, 0.8],
		[3.4, -3.0, 99.5, 0.8],
		[3.4, 3.0, 99.5, 0.8],
		[3.6, -2.4, 108.4, 0.8],
		[3.8, 2.4, 112.4, 0.8],
		[4.6, 5.8, 114.0, 0.8],
		[4.0, -4.2, 120.0, 0.8],
		[4.0, 4.2, 120.0, 0.8],
		[4.0, 0.0, 125.0, 0.8],
		[4.4, 0.0, 132.4, 0.8],
		# Region 5: Corrupted Forest, Root Maze & Seals (12)
		[4.8, -2.5, 139.5, 0.8],
		[4.8, 2.5, 139.5, 0.8],
		[5.2, 0.0, 147.8, 0.8],
		[5.5, -3.2, 151.6, 0.8],
		[5.5, 3.2, 151.6, 0.8],
		[5.8, 0.0, 155.8, 0.8],
		[6.4, -3.0, 170.5, 0.8],
		[6.4, 3.0, 170.5, 0.8],
		[6.8, -8.8, 183.5, 0.8],
		[6.8, 8.8, 183.5, 0.8],
		[7.4, -2.8, 193.0, 0.8],
		[7.4, 2.8, 193.0, 0.8],
		# Region 6: Ancient Guardian's Grove & Portal Terrace (6)
		[7.7, 0.0, 201.2, 0.8],
		[8.0, -4.5, 214.0, 0.8],
		[8.0, 4.5, 214.0, 0.8],
		[8.0, -4.5, 222.0, 0.8],
		[8.0, 4.5, 222.0, 0.8],
		[8.0, -2.0, 229.0, 0.8],
	]
	for spot in spots:
		var coin: Area3D = COIN.instantiate()
		coin.position = Vector3(float(spot[1]), float(spot[0]) + float(spot[3]), float(spot[2]))
		add_child(coin)
		coins_placed += 1


# --- Geometry & Surface Helpers ----------------------------------------------

func _register_gate(puzzle: String, gate: IslandGate) -> void:
	if not _gates.has(puzzle):
		_gates[puzzle] = []
	_gates[puzzle].append(gate)


func _gate_off(puzzle: String, beyond_z: float) -> void:
	for entry in _surfaces:
		var pt: Vector3 = entry["point"]
		if pt.z > beyond_z:
			var prev := str(entry.get("gate", ""))
			entry["gate"] = puzzle if prev.is_empty() else prev + "|" + puzzle


func surface_open(entry: Dictionary) -> bool:
	var g := str(entry.get("gate", ""))
	if g.is_empty():
		return true
	for part in g.split("|"):
		if not is_puzzle_solved(part):
			return false
	return true


func _build_gated_bridge(puzzle: String, surface_y: float, x: float, z: float, radius: float) -> void:
	var plank: Node3D = PLATFORM.instantiate()
	plank.name = "Bridge_%s_%d" % [puzzle, roundi(z)]
	plank.position = Vector3(x, surface_y - 3.0, z)
	plank.visible = false
	add_child(plank)
	var shapes := plank.find_children("*", "CollisionShape3D", true, false)
	for s in shapes:
		(s as CollisionShape3D).disabled = true
	_record_surface(Vector3(x, surface_y, z), radius, puzzle)
	if not _raisers.has(puzzle):
		_raisers[puzzle] = []
	_raisers[puzzle].append(func():
		plank.visible = true
		for s in shapes:
			(s as CollisionShape3D).set_deferred("disabled", false)
		var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(plank, "position:y", surface_y - 0.5, 0.65)
	)


func _record_surface(spot: Vector3, radius: float, gate := "") -> void:
	_surfaces.append({"point": spot, "radius": radius, "gate": gate})


func nearest_surface(spot: Vector3) -> Array:
	var best := [INF, 0.0]
	for entry in _surfaces:
		var pt: Vector3 = entry["point"]
		var flat := maxf(0.0, Vector2(spot.x - pt.x, spot.z - pt.z).length() - float(entry["radius"]))
		var h := spot.y - pt.y
		if flat < best[0]:
			best = [flat, h]
	return best


func _platform(surface_y: float, x: float, z: float, kind := "medium", yaw := 0.0) -> Node3D:
	var scene: PackedScene = PLATFORM_MEDIUM
	var radius := 1.5
	if kind == "small":
		scene = PLATFORM
		radius = 0.9
	elif kind == "grass":
		scene = PLATFORM_GRASS
		radius = 2.5
	var node: Node3D = scene.instantiate()
	node.position = Vector3(x, surface_y - 0.5, z)
	node.rotation.y = yaw
	add_child(node)
	_record_surface(Vector3(x, surface_y, z), radius)
	return node


func _grass_slab(surface_y: float, x: float, z: float, radius: float, depth: float, record := true, top_col := GRASS) -> StaticBody3D:
	return _round_slab(surface_y, x, z, radius, depth, top_col, ROCK, record)


func _stone_slab(surface_y: float, x: float, z: float, radius: float, depth: float) -> StaticBody3D:
	return _round_slab(surface_y, x, z, radius, depth, STONE, STONE_DEEP, true)


func _round_slab(surface_y: float, x: float, z: float, radius: float, depth: float,
		top_color: Color, side_color: Color, record := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Slab_%d_%d" % [roundi(x), roundi(z)]
	body.position = Vector3(x, surface_y - depth * 0.5, z)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = depth
	shape.shape = cylinder
	body.add_child(shape)
	_cylinder(body, radius, depth, _mat(side_color), Vector3.ZERO, Vector3.ZERO, radius * 0.75)
	_cylinder(body, radius * 0.99, 0.42, _mat(top_color), Vector3(0.0, depth * 0.5 - 0.18, 0.0))
	add_child(body)
	if record:
		_record_surface(Vector3(x, surface_y, z), radius * 0.95)
	return body


func _rock(surface_y: float, x: float, z: float, radius: float, yaw: float, solid: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Rock_%d_%d" % [roundi(x), roundi(z)]
	body.position = Vector3(x, surface_y - 0.45, z)
	body.rotation.y = yaw
	_cylinder(body, radius * 0.95, 0.68, _mat(ROCK), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, radius * 0.72)
	_cylinder(body, radius * 0.96, 0.22, _mat(GRASS), Vector3(0.0, 0.34, 0.0))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius * 0.96
	cylinder.height = 0.82
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.04, 0.0)
	body.add_child(shape)
	add_child(body)
	if solid:
		_record_surface(Vector3(x, surface_y, z), radius * 0.95)
	return body


func _rounded_tree(surface_y: float, x: float, z: float, height: float, canopy_color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "WoodsTree_%d_%d" % [roundi(x), roundi(z)]
	body.position = Vector3(x, surface_y, z)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.32
	cyl.height = height * 0.75
	shape.shape = cyl
	shape.position = Vector3(0.0, height * 0.38, 0.0)
	body.add_child(shape)
	_cylinder(body, 0.3, height * 0.75, _mat(BARK), Vector3(0.0, height * 0.38, 0.0), Vector3.ZERO, 0.22)
	var crown := height * 0.46
	_sphere(body, crown, _mat(canopy_color), Vector3(0.0, height * 0.85, 0.0), Vector3(1.15, 0.85, 1.15))
	_sphere(body, crown * 0.72, _mat(canopy_color.lightened(0.08)), Vector3(crown * 0.5, height * 0.74, 0.2), Vector3(1.0, 0.8, 1.0))
	add_child(body)


func _crystal_cluster(spot: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "CrystalCluster_%d_%d" % [roundi(spot.x), roundi(spot.z)]
	body.position = spot
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = height
	shape.shape = cyl
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape)
	_cylinder(body, 0.08, height, _glow_mat(CRYSTAL_CYAN, CRYSTAL_CYAN, 1.6), Vector3(0.0, height * 0.5, 0.0), Vector3.ZERO, 0.32)
	add_child(body)


func _waterfall(spot: Vector3, width: float, height: float) -> void:
	var node := Node3D.new()
	node.name = "Waterfall"
	node.position = spot
	var w_mat := StandardMaterial3D.new()
	w_mat.albedo_color = Color(0.38, 0.82, 1.0, 0.72)
	w_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	w_mat.emission_enabled = true
	w_mat.emission = Color("#5ceeff")
	w_mat.emission_energy_multiplier = 0.45
	var box_inst := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(width, height, 0.2)
	box_inst.mesh = b_mesh
	box_inst.material_override = w_mat
	box_inst.position = Vector3(0.0, -height * 0.5, 0.0)
	node.add_child(box_inst)
	add_child(node)


func _flower(spot: Vector3, bulk: float, petal: Color) -> void:
	var node := Node3D.new()
	node.position = spot
	_sphere(node, bulk * 0.22, _glow_mat(petal, petal, 0.5), Vector3(0.0, 0.25, 0.0))
	add_child(node)


func _scatter_tufts(surface_y: float, x: float, z: float, radius: float, count: int) -> void:
	for i in count:
		var angle := TAU * float(i) / float(count)
		var spread := radius * (0.35 + 0.45 * float((i * 5) % 4) / 4.0)
		var tuft: Node3D = (GRASS_TUFT if i % 2 == 0 else GRASS_TUFT_SMALL).instantiate()
		tuft.position = Vector3(x + cos(angle) * spread, surface_y, z + sin(angle) * spread)
		add_child(tuft)


func _build_flanks_and_backdrop() -> void:
	for flank in [
		[0.5, -15.0, 28.0, 4.0],
		[1.8, 16.0, 62.0, 4.5],
		[3.5, -16.5, 112.0, 4.5],
		[5.8, 17.0, 158.0, 4.8],
		[7.8, -18.0, 214.0, 4.5],
	]:
		_grass_slab(float(flank[0]), float(flank[1]), float(flank[2]), float(flank[3]), 2.6, false)
		_rounded_tree(float(flank[0]), float(flank[1]), float(flank[2]), 4.2, LEAF_BRIGHT)
	for c_spot in [Vector3(-18.0, 4.0, 45.0), Vector3(19.0, 6.0, 105.0), Vector3(-19.0, 9.0, 185.0)]:
		var cloud: Node3D = CLOUD.instantiate()
		cloud.position = c_spot
		add_child(cloud)


func _setup_environment() -> void:
	if _main == null:
		return
	var sun := _main.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
		sun.light_color = Color("#e8ffe0")
		sun.light_energy = 1.08


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	return m


func _glow_mat(col: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = energy
	return m


func _box_solid(parent: Node3D, box_size: Vector3, mat: Material, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = box_size
	mesh_inst.mesh = b_mesh
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	parent.add_child(body)


func _cylinder(parent: Node3D, radius: float, height: float, mat: Material, pos: Vector3,
		rot_deg := Vector3.ZERO, top_r := -1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_r < 0.0 else top_r
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node


func _sphere(parent: Node3D, radius: float, mat: Material, pos: Vector3, scale_vec := Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.scale = scale_vec
	parent.add_child(node)
	return node


func _motes(surface_y: float, x: float, z: float, amount: int, color: Color, spread: float) -> void:
	var mat := _glow_mat(color, color, 1.4)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.13)
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = spread * 0.5
	proc.direction = Vector3(0, 1, 0)
	proc.gravity = Vector3(0.0, 0.3, 0.0)
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 3.5
	p.draw_pass_1 = quad
	p.material_override = mat
	p.process_material = proc
	p.position = Vector3(x, surface_y + 1.5, z)
	add_child(p)
