class_name ForgottenIsland
extends Node3D

## Level 1 - THE FORGOTTEN ISLAND.
##
## A hand-laid island built from the project's own platform scenes plus props made
## from primitives, so it needs no new art. The route runs along +Z and is split
## into eight areas:
##
##   A Start Glade         z   0 - 11   spawn, stone arch, flowers         4 coins
##   B Forest Path         z  13 - 33   stepping stones, cave, waterfall  10 coins
##   C Crystal Grove       z  35 - 61   trees, glowing mushrooms, upper route  9 coins
##   D Vanishing Crossing  z  63 - 84   stepping stones over the chasm     5 coins
##   E Seal Terraces       z  88 - 115  three side terraces, the long path 5 coins
##   F Ruins Approach      z 116 - 145  stone floor, broken pillars        3 coins
##   G Warden's Arena      z 145 - 167  circular arena floor               1 coin
##   H Portal Terrace      z 162 - 174  the coin-gated portal to level 2   1 coin
##
## 38 coins in total, [member coins_required] of them needed for the portal.
##
## Conventions used by every helper here:
##   * heights are the WALKABLE SURFACE, never a node origin - the project's
##     platform scenes put their surface 0.5 above their origin, and a coin or a
##     player is placed relative to the surface.
##   * gaps between ledges stay at or under 2.3 units and rises under 1.0, which
##     is what the player's double jump reliably clears.

signal message(text: String)         ## ask the HUD to show a line of text
signal portal_unlocked               ## the coin requirement was just met

const PLATFORM := preload("res://objects/platform.tscn")
const PLATFORM_MEDIUM := preload("res://objects/platform_medium.tscn")
const PLATFORM_GRASS := preload("res://objects/platform_grass_large_round.tscn")
const COIN := preload("res://objects/coin.tscn")
const CLOUD := preload("res://objects/cloud.tscn")
const GRASS_TUFT := preload("res://models/grass.glb")
const GRASS_TUFT_SMALL := preload("res://models/grass-small.glb")

## Coins needed to wake the portal. Editable in the Inspector, or in code.
@export var coins_required := 30
## Height a coin floats above the surface it was placed on.
@export var coin_lift := 0.8

# --- Palette -----------------------------------------------------------------
const GRASS := Color("#83d95c")
const GRASS_DEEP := Color("#4f9e49")
const ROCK := Color("#7b6a58")
const ROCK_DEEP := Color("#57493c")
const STONE := Color("#9a95a6")
const STONE_DEEP := Color("#6b6579")
const BARK := Color("#6b4a34")
const LEAF := Color("#5fbf6d")
const LEAF_DEEP := Color("#3f8f52")
const CAP := Color("#8a5cff")
const CAP_GLOW := Color("#c0a2ff")
const PETAL_PINK := Color("#ff8ec9")
const PETAL_GOLD := Color("#ffd35c")
const PETAL_BLUE := Color("#78d6ff")
const WATER := Color("#63c8ff")
const MAGIC := Color("#b06bff")
const PORTAL_BLUE := Color("#4fd8ff")
const PORTAL_VIOLET := Color("#b06bff")

# --- State -------------------------------------------------------------------
var spawn_point := Vector3(0.0, 0.55, -4.0)
var portal_position := Vector3(0.0, 8.55, 168.5)
## Points the starting camera is aimed along, in walking order.
var waypoints: Array = []
## Where the four checkpoints go, in the order the player meets them.
var checkpoint_points: Array = []
var coins_placed := 0
var coins_collected := 0

var _main: Node = null
var _materials: Dictionary = {}
## Every walkable surface on the island: {position (on the surface), radius}. The
## coin checks in tools/ use this to prove each coin can be reached on foot.
var _surfaces: Array[Dictionary] = []
var _bobbers: Array[Node3D] = []
var _symbols: Array[Node3D] = []
var _portal_disc: MeshInstance3D
var _portal_inner: MeshInstance3D
var _portal_material: StandardMaterial3D
var _inner_material: StandardMaterial3D
var _portal_energy := 0.0
var _unlocked := false
var _prompt_cooldown := 0.0
var _time := 0.0


func build(main: Node) -> void:
	_main = main
	spawn_point = Vector3(0.0, 0.55, -4.0)
	_build_start_glade()
	_build_forest_path()
	_build_crystal_grove()
	_build_crossing()
	_build_seal_terraces()
	_build_ruins_approach()
	_build_arena()
	_build_portal_terrace()
	_build_flanks()
	_build_backdrop()
	_place_coins()
	_setup_environment()
	print("[ForgottenIsland] built: %d coins placed, %d required, %d checkpoints" % [
		coins_placed, coins_required, checkpoint_points.size()])


## True once the coin requirement is met. The level can be finished through the
## portal only then.
func is_portal_ready() -> bool:
	return coins_collected >= coins_required


func coins_needed() -> int:
	return maxi(0, coins_required - coins_collected)


## Called by the level each time a coin is picked up.
func notify_coins(count: int) -> void:
	coins_collected = count
	if _unlocked or coins_collected < coins_required:
		main_objective()
		return
	_unlocked = true
	main_objective()
	message.emit("The path to the next island has opened!")
	portal_unlocked.emit()


## The line shown across the top of the screen. It follows the coin hunt until the
## portal is awake, then points at the portal.
func main_objective() -> void:
	if get_node_or_null("/root/Settings") == null:
		return
	var hud: Node = _hud()
	if hud == null:
		return
	if is_portal_ready():
		hud.call("set_objective", "The portal on the east terrace is awake - step through it!")
	else:
		hud.call("set_objective", "Explore the Forgotten Island  -  %d more coins wake the portal" % coins_needed())


func _hud() -> Node:
	if _main == null:
		return null
	return _main.get("hud") as Node


func _process(delta: float) -> void:
	_time += delta
	if _prompt_cooldown > 0.0:
		_prompt_cooldown -= delta
	# Floating rocks and the portal keep moving so the island never looks still.
	for i in _bobbers.size():
		var rock := _bobbers[i]
		if is_instance_valid(rock):
			rock.position.y = rock.get_meta("bob_base", rock.position.y) + sin(_time * 0.6 + float(i)) * 0.18
	# The portal wakes up gradually: a dim, dull surface while it is locked, a
	# bright swirling one once the coins are in.
	var target := 1.0 if is_portal_ready() else 0.0
	_portal_energy = move_toward(_portal_energy, target, delta * 0.6)
	if _portal_disc != null and is_instance_valid(_portal_disc):
		_portal_disc.rotate_y(delta * (0.35 + 1.5 * _portal_energy))
		_portal_material.emission_energy_multiplier = 0.25 + 1.15 * _portal_energy
		_inner_material.emission_energy_multiplier = 0.4 + 1.6 * _portal_energy
		_portal_inner.rotate_y(-delta * (0.5 + 1.2 * _portal_energy))
	for i in _symbols.size():
		var symbol := _symbols[i]
		if not is_instance_valid(symbol):
			continue
		var angle := _time * (0.5 + _portal_energy) + TAU * float(i) / float(maxi(1, _symbols.size()))
		var radius := 1.75
		symbol.position = portal_position + Vector3(
			cos(angle) * radius, sin(angle * 1.3) * 0.55, sin(angle) * radius * 0.35)
		symbol.rotation.y += delta * 1.4
		symbol.rotation.x += delta * 0.9


# --- A: the start glade -------------------------------------------------------

func _build_start_glade() -> void:
	_grass_slab(0.0, 0.0, 2.0, 9.0, 3.4)
	waypoints = [
		Vector3(0.0, 0.55, -4.0),
		Vector3(0.0, 0.55, 2.0),
		Vector3(2.0, 0.75, 15.2),
	]
	checkpoint_points = [
		Vector3(0.0, 0.0, -6.6),
		Vector3(3.5, 2.8, 84.5),
		Vector3(0.0, 5.6, 122.0),
		Vector3(0.0, 8.0, 145.5),
	]
	# The broken arch the island is named for, and the props around it.
	_arch(0.0, 5.5, 0.0, 5.0, 3.8, 0.0)
	_scatter_tufts(0.0, 0.0, 2.0, 8.0, 14)
	_tree(0.0, -5.5, 1.0, 4.2, LEAF)
	_tree(0.0, 5.8, -1.0, 3.4, LEAF_DEEP)
	for spot in [Vector3(-3.2, 0.0, 3.4), Vector3(3.4, 0.0, 4.6), Vector3(-6.4, 0.0, -2.0)]:
		_flower(spot, 1.9, PETAL_PINK)
	for spot in [Vector3(-6.2, 0.0, 5.0), Vector3(6.4, 0.0, 3.0)]:
		_mushroom(spot, 1.5, true)
	_motes(0.9, 0.0, 2.0, 30, MAGIC, 5.0)
	_rock(-0.5, 7.4, 6.4, 1.3, 0.7, false)
	_rock(-1.2, -7.6, 6.0, 1.6, 2.1, false)


# --- B: the forest path -------------------------------------------------------

func _build_forest_path() -> void:
	var route := [
		[0.2, 0.0, 13.0, "medium"],
		[0.4, 2.0, 15.2, "small"],
		[0.6, 4.0, 17.4, "small"],
		[0.7, 2.2, 19.6, "medium"],
		[0.8, 0.2, 21.8, "small"],
		[1.0, -1.8, 24.0, "small"],
		[1.1, 0.2, 26.2, "grass"],
		[1.3, 2.4, 28.4, "small"],
		[1.4, 4.4, 30.6, "small"],
		[1.5, 2.6, 32.8, "medium"],
		[1.6, 0.6, 35.0, "small"],
	]
	for point in route:
		_platform(float(point[0]), float(point[1]), float(point[2]), str(point[3]), float(point[1]) * 0.2)

	# The cave: a rock shell you drop into, with a way back out.
	_grass_slab(1.2, -3.6, 20.5, 2.6, 2.2)
	_cave_shell(Vector3(-3.6, 1.2, 20.5), 2.6)
	_platform(1.7, -1.2, 18.8, "small")
	_rock(1.6, -3.4, 22.6, 1.4, 0.4, false)

	# The waterfall on the east edge. The ledge with the coins is on the far side
	# of the falling water, so the player has to hop through it to find them.
	_platform(-1.6, 3.2, 25.2, "small")
	_platform(-1.4, 5.2, 26.6, "small")
	_platform(-1.3, 6.0, 28.6, "small")
	_waterfall(Vector3(6.4, 6.2, 30.0), 3.2, 20.0)
	_platform(-1.25, 6.4, 30.0, "small")
	_platform(-1.2, 6.6, 31.4, "small")
	_cliff(-1.2, 6.6, 34.4, 3.0)
	_mushroom(Vector3(1.6, 0.2, 26.2), 1.3, true)

	# Optional floating rocks above the path.
	_rock(1.2, 2.4, 15.6, 1.3, 0.5, true)
	_rock(2.0, -1.4, 22.0, 1.4, 1.2, true)
	_rock(2.6, 2.6, 31.5, 1.3, 2.4, true)
	_tree(0.4, -5.0, 16.4, 3.8, LEAF)
	_tree(1.1, 5.4, 26.0, 4.6, LEAF_DEEP)
	_flower(Vector3(2.2, 1.1, 26.2), 1.7, PETAL_BLUE)


# --- C: the crystal grove -----------------------------------------------------

func _build_crystal_grove() -> void:
	var route := [
		[1.6, 0.6, 37.2, "medium"],
		[1.7, -1.4, 39.4, "small"],
		[1.8, 0.6, 41.6, "grass"],
		[1.9, 2.6, 43.8, "small"],
		[2.0, 0.8, 46.0, "medium"],
		[2.1, -1.2, 48.2, "small"],
		[2.2, 0.8, 50.4, "grass"],
		[2.3, 2.8, 52.6, "small"],
		[2.4, 4.8, 54.8, "small"],
		[2.5, 2.8, 57.0, "medium"],
		[2.6, 0.8, 59.2, "small"],
		[2.6, -1.2, 61.4, "medium"],
	]
	for point in route:
		_platform(float(point[0]), float(point[1]), float(point[2]), str(point[3]), float(point[1]) * 0.3)

	# The pedestal that will hold the hidden crystal (wired up in a later stage).
	_pedestal(Vector3(0.6, 1.8, 41.6))
	_tree(1.8, -4.4, 40.0, 4.4, LEAF)
	_tree(1.8, 4.6, 42.6, 4.0, LEAF_DEEP)
	_tree(2.2, -4.8, 50.0, 4.8, LEAF)
	_tree(2.6, 4.2, 58.0, 4.2, LEAF_DEEP)
	for spot in [Vector3(1.0, 1.8, 44.6), Vector3(-1.0, 1.8, 49.8), Vector3(3.6, 1.8, 52.0)]:
		_mushroom(spot, 1.6, true)
	_flower(Vector3(-0.4, 1.8, 41.6), 2.0, PETAL_GOLD)
	_flower(Vector3(1.4, 1.8, 50.4), 1.8, PETAL_PINK)
	_motes(1.8, 0.0, 46.0, 24, MAGIC, 6.0)

	# The optional upper route: two coins up there for anyone who looks.
	_platform(2.2, 3.0, 41.0, "small")
	_platform(3.0, 4.4, 42.6, "small")
	_platform(3.8, 5.4, 44.4, "small")
	_rock(1.2, 3.0, 37.4, 1.3, 0.9, true)
	_rock(3.2, 4.0, 44.5, 1.4, 1.7, true)
	_rock(2.0, 0.2, 50.9, 1.3, 2.6, true)


# --- D: the vanishing crossing ------------------------------------------------

func _build_crossing() -> void:
	# Built as one row of stepping stones for now; the disappearing pattern is
	# added on top of them in the puzzle stage.
	var route := [
		[2.7, -3.2, 63.6],
		[2.8, -5.2, 65.8],
		[2.9, -3.2, 68.0],
		[3.0, -1.2, 70.2],
		[3.0, -3.2, 72.4],
		[3.1, -5.2, 74.6],
		[3.2, -3.2, 76.8],
		[3.3, -1.2, 79.0],
		[3.4, 0.8, 81.2],
		[3.5, 2.8, 83.4],
	]
	for point in route:
		_platform(float(point[0]), float(point[1]), float(point[2]), "small", float(point[1]) * 0.5)
	_platform(3.5, 2.8, 83.4, "grass", 0.4)
	# The rope bridge look: two low posts either side of the crossing.
	_post(3.6, -3.2, 62.6, 1.2)
	_post(3.7, 1.6, 84.6, 1.2)
	# A ledge tucked under the far end, and a rock above the middle.
	_grass_slab(0.6, 2.6, 86.4, 2.4, 2.0)
	_platform(1.6, 5.4, 85.0, "small")
	_rock(1.6, 0.5, 71.2, 1.4, 1.1, true)
	_rock(-0.6, -6.6, 68.0, 1.6, 0.6, false)
	_flower(Vector3(4.4, 3.3, 83.4), 1.7, PETAL_BLUE)


# --- E: the seal terraces -----------------------------------------------------

func _build_seal_terraces() -> void:
	_grass_slab(3.6, 0.6, 90.0, 2.6, 3.0)
	_post(3.7, 0.6, 86.8, 1.2)
	# The long path east, wandering a little.
	for i in 12:
		var surface := 3.6 + float(i) * 0.14
		var z := 92.4 + float(i) * 2.2
		var x := sin(float(i) * 0.7) * 0.6
		var kind := "small" if i % 3 != 1 else "medium"
		_platform(surface, x, z, kind, float(i) * 0.4)
		waypoints.append(Vector3(x, surface + 0.55, z))
	# West terrace.
	_platform(3.6, -2.4, 90.6, "small")
	_platform(3.8, -4.4, 91.4, "small")
	_platform(4.0, -6.2, 92.4, "grass", 0.3)
	_pedestal(Vector3(-6.2, 4.0, 92.4))
	# East terrace.
	_platform(3.7, 3.8, 90.0, "small")
	_platform(3.9, 5.8, 91.0, "small")
	_platform(4.2, 7.6, 94.0, "grass", 0.2)
	_pedestal(Vector3(7.6, 4.2, 94.0))
	# Upper terrace, reached by a short climb off the long path.
	_platform(4.6, 2.0, 100.0, "small")
	_platform(5.2, 4.0, 101.0, "small")
	_platform(5.8, 5.6, 102.6, "grass", 0.1)
	_pedestal(Vector3(5.6, 5.8, 102.6))
	_tree(4.0, -8.4, 94.2, 3.8, LEAF)
	_tree(4.2, 9.6, 95.6, 3.6, LEAF_DEEP)
	for spot in [Vector3(-6.0, 4.0, 90.8), Vector3(7.4, 4.2, 91.6), Vector3(5.0, 5.8, 103.8)]:
		_mushroom(spot, 1.4, true)
	_motes(4.0, -6.2, 92.4, 18, MAGIC, 5.0)
	_motes(4.2, 7.6, 94.0, 18, MAGIC, 5.0)


# --- F: the ruins approach ----------------------------------------------------

func _build_ruins_approach() -> void:
	_stone_slab(5.6, 0.0, 122.0, 7.0, 2.6)
	_stone_slab(8.0, 0.0, 147.0, 8.5, 3.0)
	# A climbing avenue of broken pillars between the two floors.
	var climb := [
		[6.0, -1.6, 132.5],
		[6.5, 1.2, 134.5],
		[7.0, -1.2, 136.5],
		[7.5, 1.6, 138.5],
	]
	for point in climb:
		_platform(float(point[0]), float(point[1]), float(point[2]), "medium", float(point[1]))
	for spot in [
		Vector3(-4.6, 5.6, 119.5), Vector3(4.6, 5.6, 119.5),
		Vector3(-5.4, 5.6, 125.0), Vector3(5.4, 5.6, 125.0),
		Vector3(-2.6, 8.0, 142.0), Vector3(2.6, 8.0, 142.0),
	]:
		_pillar(spot, 3.4, 0.35, true)
	_arch(8.0, 0.0, 131.0, 6.0, 4.0, 0.0)
	_rock(6.6, -3.6, 128.5, 1.5, 0.8, true)
	_mushroom(Vector3(2.4, 5.6, 123.4), 1.5, true)
	_flower(Vector3(-2.2, 5.6, 123.6), 1.8, PETAL_PINK)
	_motes(5.6, 0.0, 122.0, 20, MAGIC, 6.0)


# --- G: the arena -------------------------------------------------------------

func _build_arena() -> void:
	_stone_slab(8.0, 0.0, 156.0, 11.0, 3.2)
	# Broken pillars and violet braziers around the circle: the Shadow King's
	# corruption has reached this far.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var spot := Vector3(cos(angle) * 8.6, 8.0, 156.0 + sin(angle) * 8.6)
		_pillar(spot, 4.0, 0.28, i % 3 == 0)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + 0.4
		_brazier(Vector3(cos(angle) * 4.4, 8.0, 156.0 + sin(angle) * 4.4))
	_motes(8.0, 0.0, 156.0, 40, MAGIC, 7.0)


# --- H: the portal terrace ----------------------------------------------------

func _build_portal_terrace() -> void:
	_stone_slab(8.0, 0.0, 168.0, 6.2, 3.0)
	# Steps up to the terrace from the arena side.
	_platform(8.0, 0.0, 164.0, "medium", 0.0)
	portal_position = Vector3(0.0, 8.55, 168.5)
	_build_portal(portal_position)
	_pillar(Vector3(-4.4, 8.0, 166.0), 3.6, 0.2, true)
	_pillar(Vector3(4.4, 8.0, 166.0), 3.6, 0.24, true)
	_post(8.0, 0.0, 163.0, 1.4)
	_flower(Vector3(-2.6, 8.0, 165.0), 1.9, PETAL_GOLD)
	_flower(Vector3(2.6, 8.0, 165.0), 1.9, PETAL_BLUE)


func _build_portal(where: Vector3) -> void:
	var base := Node3D.new()
	base.name = "Portal"
	base.position = where
	add_child(base)

	# Stone frame: two jambs, a lintel and a ring.
	for side in [-1.0, 1.0]:
		_box(base, Vector3(0.7, 3.4, 0.9), _material(STONE_DEEP), Vector3(side * 2.1, 0.7, 0.0))
		_box(base, Vector3(0.9, 0.5, 1.1), _material(STONE), Vector3(side * 2.1, 2.5, 0.0))
	_box(base, Vector3(5.0, 0.7, 1.0), _material(STONE), Vector3(0.0, 2.9, 0.0))
	_torus(base, 1.95, 0.35, _material(STONE_DEEP), Vector3(0.0, 1.6, 0.0), Vector3(90.0, 0.0, 0.0))
	# Steps.
	_box(base, Vector3(4.6, 0.3, 1.6), _material(STONE), Vector3(0.0, -0.55, -0.6))
	_box(base, Vector3(3.6, 0.3, 1.2), _material(STONE_DEEP), Vector3(0.0, -0.85, -1.4))

	# The swirling surface: two counter-rotating discs, dim until the coins are in.
	_portal_material = _glow_material(PORTAL_BLUE, PORTAL_VIOLET, 1.0)
	_portal_disc = _cylinder_mesh(base, 1.7, 0.1, _portal_material, Vector3(0.0, 1.6, 0.0), Vector3(90.0, 0.0, 0.0))
	_inner_material = _glow_material(PORTAL_VIOLET, PORTAL_BLUE, 1.2)
	_portal_inner = _cylinder_mesh(base, 1.1, 0.14, _inner_material, Vector3(0.0, 1.6, 0.0), Vector3(90.0, 0.0, 0.0))

	# Floating glyphs orbiting the frame.
	for i in 5:
		var symbol := MeshInstance3D.new()
		var glyph := BoxMesh.new()
		glyph.size = Vector3(0.26, 0.26, 0.08)
		symbol.mesh = glyph
		symbol.material_override = _material(PORTAL_BLUE, PORTAL_BLUE)
		symbol.position = where
		base.add_child(symbol)
		_symbols.append(symbol)

	# Rising motes in front of the portal.
	_motes(where.y - 0.4, where.x, where.z - 1.0, 26, PORTAL_VIOLET, 4.0)

	# The prompt: walking up to a locked portal says what it still wants.
	var area := Area3D.new()
	area.name = "PortalPrompt"
	area.position = where + Vector3(0.0, 0.4, -0.5)
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 4.0
	shape.shape = sphere
	area.add_child(shape)
	area.body_entered.connect(_on_portal_prompt_entered)
	base.add_child(area)


func _on_portal_prompt_entered(body: Node3D) -> void:
	if _prompt_cooldown > 0.0:
		return
	if not body.is_in_group("player"):
		return
	_prompt_cooldown = 2.5
	if is_portal_ready():
		message.emit("The path to the next island has opened!")
	else:
		message.emit("The portal is dormant - %d more coins are needed." % coins_needed())


# --- Coins --------------------------------------------------------------------

## Every hidden coin on the island, in one place so the hunt can be judged at a
## glance. [surface, x, z, lift] - the lift is how far above the surface it floats.
func _place_coins() -> void:
	var spots: Array = [
		# A. easy pickings in the glade
		[0.0, 2.5, -1.5, 0.8],
		[0.0, -3.0, 1.5, 0.8],
		[0.0, -5.6, 4.6, 1.0],          # behind a mushroom
		[0.0, 0.0, 4.4, 1.9],           # on the stone arch
		# B. forest path
		[0.4, 2.0, 15.2, 0.8],          # on the path
		[1.4, 4.4, 30.6, 0.8],          # on the path
		[1.2, -3.6, 20.5, 0.8],         # inside the cave
		[1.2, -4.4, 20.9, 1.1],
		[1.2, -2.8, 21.4, 1.3],
		[-1.2, 6.6, 31.4, 0.8],         # behind the waterfall
		[-1.2, 6.8, 31.2, 1.0],
		[1.2, 2.4, 15.6, 0.8],          # floating rocks
		[2.0, -1.4, 22.0, 0.8],
		[2.6, 2.6, 31.5, 0.8],
		# C. crystal grove
		[1.6, 0.6, 37.2, 0.8],
		[2.2, 0.8, 50.4, 0.8],
		[1.8, -0.6, 41.6, 0.9],         # by the glowing plants
		[2.0, 1.4, 46.0, 0.9],
		[1.2, 3.0, 37.4, 0.8],          # floating rocks
		[3.2, 4.0, 44.5, 0.8],
		[2.0, 0.2, 50.9, 0.8],
		[2.2, 3.0, 41.0, 0.8],          # the upper route
		[3.8, 5.4, 44.4, 0.8],
		# D. vanishing crossing
		[3.0, -1.2, 70.2, 0.8],
		[3.3, -1.2, 79.0, 0.8],
		[1.6, 0.5, 71.2, 0.8],          # rock beside the middle
		[0.6, 2.6, 86.4, 0.8],          # under the far end
		[0.6, 3.6, 86.9, 1.0],
		# E. seal terraces
		[4.0, -6.2, 92.4, 0.8],
		[4.2, 7.6, 94.0, 0.8],
		[5.8, 5.6, 102.6, 0.8],
		[3.6, 0.6, 90.0, 0.8],
		[4.16, 0.2, 101.2, 0.8],
		# F. ruins approach
		[5.6, -4.6, 124.0, 0.8],        # behind a pillar
		[6.6, -3.6, 128.5, 0.8],        # on a floating rock
		[6.0, 0.0, 133.0, 0.8],         # under the arch
		# G. arena
		[8.0, 6.0, 158.0, 0.8],
		# H. portal terrace
		[8.0, -3.6, 166.5, 0.8],
	]
	for spot in spots:
		_coin(float(spot[0]), float(spot[1]), float(spot[2]), float(spot[3]))


# --- Environment --------------------------------------------------------------

## Atmosphere: a little fog so the far islands read as distance, and the sun set
## somewhere warm. Both are tuned on the shared environment resource at runtime,
## so nothing on disk changes for the other levels.
func _setup_environment() -> void:
	if _main == null:
		return
	var sun: DirectionalLight3D = _main.get("Sun")
	if sun != null:
		sun.rotation_degrees = Vector3(-46.0, -38.0, 0.0)
		sun.light_color = Color("#fff0cf")
		sun.light_energy = 1.12
		sun.shadow_enabled = true
	var world_environment: WorldEnvironment = _main.get("Environment")
	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	env.fog_enabled = true
	env.fog_light_color = Color("#cfe6ff")
	env.fog_light_energy = 1.0
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	env.ambient_light_energy = 1.05


## The land the route crosses. Wide grass shoulders with trees, mushrooms and
## flowers on them, so the island reads as land rather than as a trail of tiles.
## They are solid but are not part of the coin route, so they are not recorded as
## walkable ground and a player who lands on one is simply exploring.
func _build_flanks() -> void:
	var flanks: Array = [
		[0.2, 12.0, 18.0, 3.5],
		[1.2, -12.0, 32.0, 3.5],
		[2.6, 12.5, 44.0, 4.0],
		[2.6, -13.0, 58.0, 4.5],
		[3.6, 13.0, 72.0, 4.5],
		[4.4, -14.0, 92.0, 5.0],
		[5.6, 14.5, 108.0, 5.0],
		[8.0, -16.5, 152.0, 4.0],
		[8.0, 13.0, 165.0, 3.5],
	]
	for entry in flanks:
		var surface := float(entry[0])
		var x := float(entry[1])
		var z := float(entry[2])
		var radius := float(entry[3])
		var seed := int(absf(x) + absf(z))
		_grass_slab(surface, x, z, radius, radius * 0.9, false)
		_scatter_tufts(surface, x, z, radius * 0.85, 8)
		_tree(surface, x + radius * 0.35, z + radius * 0.25, 3.6 + float(seed % 3) * 0.5, LEAF)
		_tree(surface, x - radius * 0.4, z - radius * 0.35, 3.2 + float(seed % 2) * 0.6, LEAF_DEEP)
		_mushroom(Vector3(x + radius * 0.55, surface, z - radius * 0.5), 1.3, seed % 2 == 0)
		_flower(Vector3(x - radius * 0.6, surface, z + radius * 0.45), 1.8,
			PETAL_PINK if seed % 2 == 0 else PETAL_BLUE)
		_rock(surface - 0.2, x + radius * 0.85, z + radius * 0.7, radius * 0.35, float(seed), false)


## Scatter the project's own grass models over a patch of ground, so the island
## has ground cover instead of flat green.
func _scatter_tufts(surface_y: float, x: float, z: float, radius: float, count: int) -> void:
	for i in count:
		var angle := TAU * float(i) / float(count)
		var spread := radius * (0.35 + 0.5 * float((i * 7) % 5) / 5.0)
		var tuft: Node3D = (GRASS_TUFT if i % 2 == 0 else GRASS_TUFT_SMALL).instantiate()
		tuft.position = Vector3(x + cos(angle) * spread, surface_y, z + sin(angle) * spread)
		tuft.rotation.y = angle * 1.7
		add_child(tuft)


## Distant islands and clouds, far enough out that the island feels like one peak
## in a floating range.
func _build_backdrop() -> void:
	var far_islands: Array = [
		[Vector3(-62.0, -10.0, 66.0), 16.0],
		[Vector3(74.0, -6.0, 128.0), 20.0],
		[Vector3(-88.0, -16.0, 178.0), 24.0],
		[Vector3(46.0, -14.0, -40.0), 14.0],
		[Vector3(-40.0, -22.0, 240.0), 26.0],
	]
	for entry in far_islands:
		var spot: Vector3 = entry[0]
		var radius := float(entry[1])
		_grass_slab(spot.y, spot.x, spot.z, radius, radius * 0.75, false)
		_tree(spot.y, spot.x - radius * 0.3, spot.z + radius * 0.2, radius * 0.5, LEAF)
		_rock(spot.y + 0.6, spot.x + radius * 0.4, spot.z - radius * 0.3, radius * 0.28, 1.2, false)
	for spot in [
		Vector3(-14.0, -6.0, 20.0), Vector3(16.0, -7.5, 44.0), Vector3(-18.0, -9.0, 78.0),
		Vector3(20.0, -10.0, 110.0), Vector3(-16.0, -12.0, 140.0), Vector3(18.0, -13.0, 170.0),
		Vector3(0.0, -16.0, 190.0), Vector3(-24.0, -5.0, -8.0), Vector3(22.0, -8.0, 6.0),
	]:
		var cloud: Node3D = CLOUD.instantiate()
		cloud.position = spot
		cloud.scale = Vector3.ONE * 2.2
		add_child(cloud)


# --- Prop and mesh helpers ----------------------------------------------------

func _material(albedo: Color, emission: Color = Color(0.0, 0.0, 0.0, 0.0), rough := 0.95) -> StandardMaterial3D:
	var key := "%s|%s|%.2f" % [albedo.to_html(), emission.to_html(), rough]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = rough
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 1.5
	_materials[key] = mat
	return mat


func _glow_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(albedo.r, albedo.g, albedo.b, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.25
	return mat


func _water_material() -> StandardMaterial3D:
	if _materials.has("water"):
		return _materials["water"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(WATER.r, WATER.g, WATER.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = WATER
	mat.emission_energy_multiplier = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.15
	_materials["water"] = mat
	return mat


func _box(parent: Node3D, size: Vector3, mat: Material, spot: Vector3, rotation_degrees_vec := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = spot
	node.rotation_degrees = rotation_degrees_vec
	parent.add_child(node)
	return node


func _sphere(parent: Node3D, radius: float, mat: Material, spot: Vector3, flat := Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	node.mesh = mesh
	node.material_override = mat
	node.position = spot
	node.scale = flat
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, radius: float, height: float, mat: Material, spot: Vector3,
		rotation_degrees_vec := Vector3.ZERO, top_radius := -1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	node.mesh = mesh
	node.material_override = mat
	node.position = spot
	node.rotation_degrees = rotation_degrees_vec
	parent.add_child(node)
	return node


func _cylinder_mesh(parent: Node3D, radius: float, height: float, mat: Material, spot: Vector3,
		rotation_degrees_vec := Vector3.ZERO) -> MeshInstance3D:
	return _cylinder(parent, radius, height, mat, spot, rotation_degrees_vec)


func _torus(parent: Node3D, inner: float, outer: float, mat: Material, spot: Vector3,
		rotation_degrees_vec := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 12
	node.mesh = mesh
	node.material_override = mat
	node.position = spot
	node.rotation_degrees = rotation_degrees_vec
	parent.add_child(node)
	return node


## A round island slab: rock sides, a grass cap, and collision matching the grass.
## Scenery slabs (the distant islands) are not recorded as walkable ground.
func _grass_slab(surface_y: float, x: float, z: float, radius: float, depth: float, record := true) -> StaticBody3D:
	return _round_slab(surface_y, x, z, radius, depth, GRASS, ROCK, record)


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
	_cylinder(body, radius, depth, _material(side_color, Color(0, 0, 0, 0), 1.0), Vector3.ZERO, Vector3.ZERO, radius * 0.74)
	var cap := _cylinder(body, radius * 0.99, 0.45, _material(top_color), Vector3(0.0, depth * 0.5 - 0.2, 0.0))
	cap.name = "GrassCap"
	add_child(body)
	if record:
		_record_surface(Vector3(x, surface_y, z), radius * 0.95)
	return body


## One of the project's own platform scenes. [param surface_y] is where the player
## stands, not the node's origin.
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


## Remember a walkable spot so the coin check can prove it is reachable.
func _record_surface(spot: Vector3, radius: float) -> void:
	_surfaces.append({"point": spot, "radius": radius})


## Nearest walkable surface to a spot, as [distance past the ledge edge, height
## above its surface]. Used by the coin checks to prove a coin can be picked up.
func nearest_surface(spot: Vector3) -> Array:
	var best := [INF, 0.0]
	for entry in _surfaces:
		var point: Vector3 = entry["point"]
		var flat := maxf(0.0, Vector2(spot.x - point.x, spot.z - point.z).length() - float(entry["radius"]))
		var height := spot.y - point.y
		if flat < best[0]:
			best = [flat, height]
	return best


func _coin(surface_y: float, x: float, z: float, lift := 0.8) -> void:
	var coin: Area3D = COIN.instantiate()
	coin.position = Vector3(x, surface_y + lift, z)
	add_child(coin)
	coins_placed += 1


## A floating rock. Solid ones are landing spots (they never move); the loose ones
## drift up and down as decoration.
func _rock(surface_y: float, x: float, z: float, radius: float, yaw: float, solid: bool) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Rock_%d_%d" % [roundi(x), roundi(z)]
	body.position = Vector3(x, surface_y - 0.35, z)
	body.rotation.y = yaw
	var rock := _sphere(body, radius, _material(ROCK), Vector3.ZERO, Vector3(1.0, 0.55, 0.9))
	rock.name = "RockShell"
	if solid:
		_cylinder(body, radius * 0.82, 0.3, _material(GRASS), Vector3(0.0, 0.32, 0.0))
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius * 0.8
		cylinder.height = 0.7
		shape.shape = cylinder
		body.add_child(shape)
		body.set_meta("bob_base", body.position.y)
		_record_surface(Vector3(x, surface_y, z), radius * 0.8)
	add_child(body)
	if not solid:
		_bobbers.append(body)
		body.set_meta("bob_base", body.position.y)
	return body


func _post(surface_y: float, x: float, z: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(x, surface_y, z)
	_cylinder(body, 0.12, height, _material(BARK), Vector3(0.0, height * 0.5, 0.0))
	_sphere(body, 0.16, _material(CAP_GLOW, CAP_GLOW), Vector3(0.0, height, 0.0))
	add_child(body)


func _tree(surface_y: float, x: float, z: float, height: float, leaf_color: Color) -> void:
	var tree := Node3D.new()
	tree.name = "Tree_%d_%d" % [roundi(x), roundi(z)]
	tree.position = Vector3(x, surface_y, z)
	tree.rotation.y = float(x + z) * 0.7
	_cylinder(tree, 0.26, height, _material(BARK), Vector3(0.0, height * 0.5, 0.0), Vector3.ZERO, 0.2)
	var crown := height * 0.42
	_sphere(tree, crown, _material(leaf_color), Vector3(0.0, height * 0.92, 0.0), Vector3(1.0, 0.85, 1.0))
	_sphere(tree, crown * 0.72, _material(leaf_color), Vector3(crown * 0.55, height * 0.78, 0.2), Vector3(1.0, 0.8, 1.0))
	_sphere(tree, crown * 0.66, _material(LEAF_DEEP), Vector3(-crown * 0.5, height * 0.74, -0.3), Vector3(1.0, 0.8, 1.0))
	add_child(tree)


func _mushroom(spot: Vector3, bulk: float, glow: bool) -> void:
	var node := Node3D.new()
	node.position = spot
	node.rotation.y = spot.x * 0.9
	var stalk := bulk * 0.85
	_cylinder(node, bulk * 0.16, stalk, _material(Color("#efe6d4")), Vector3(0.0, stalk * 0.5, 0.0), Vector3.ZERO, bulk * 0.12)
	var cap_color := CAP if glow else Color("#8a6b9c")
	var cap := _sphere(node, bulk * 0.62, _material(cap_color, CAP_GLOW if glow else Color(0, 0, 0, 0)),
		Vector3(0.0, stalk, 0.0), Vector3(1.0, 0.55, 1.0))
	cap.name = "Cap"
	if glow:
		_sphere(node, bulk * 0.2, _material(CAP_GLOW, CAP_GLOW), Vector3(0.0, stalk + bulk * 0.3, 0.0))
	add_child(node)


func _flower(spot: Vector3, bulk: float, petal: Color) -> void:
	var node := Node3D.new()
	node.position = spot
	node.rotation.y = spot.z * 1.3
	var stem := bulk * 1.1
	_cylinder(node, bulk * 0.07, stem, _material(GRASS_DEEP), Vector3(0.0, stem * 0.5, 0.0))
	for i in 6:
		var angle := TAU * float(i) / 6.0
		_sphere(node, bulk * 0.22, _material(petal), Vector3(
			cos(angle) * bulk * 0.52, stem, sin(angle) * bulk * 0.52), Vector3(1.0, 0.35, 1.0))
	_sphere(node, bulk * 0.24, _material(PETAL_GOLD, PETAL_GOLD), Vector3(0.0, stem + bulk * 0.05, 0.0))
	add_child(node)


func _pillar(spot: Vector3, height: float, tilt: float, broken: bool) -> void:
	var node := Node3D.new()
	node.position = spot
	node.rotation = Vector3(tilt * 0.5, spot.x * 0.4, tilt)
	_box(node, Vector3(1.0, 0.35, 1.0), _material(STONE_DEEP), Vector3(0.0, 0.17, 0.0))
	var body_height := height if not broken else height * 0.62
	_cylinder(node, 0.42, body_height, _material(STONE), Vector3(0.0, body_height * 0.5 + 0.3, 0.0), Vector3.ZERO, 0.46)
	if broken:
		_box(node, Vector3(0.7, 0.4, 0.6), _material(STONE_DEEP),
			Vector3(0.2, body_height + 0.5, 0.1), Vector3(12.0, 24.0, 18.0))
	else:
		_box(node, Vector3(1.2, 0.4, 1.2), _material(STONE_DEEP), Vector3(0.0, body_height + 0.5, 0.0))
	add_child(node)


func _brazier(spot: Vector3) -> void:
	var node := Node3D.new()
	node.position = spot
	_cylinder(node, 0.3, 0.9, _material(STONE_DEEP), Vector3(0.0, 0.45, 0.0), Vector3.ZERO, 0.42)
	_sphere(node, 0.34, _material(MAGIC, MAGIC), Vector3(0.0, 1.05, 0.0), Vector3(1.0, 1.3, 1.0))
	add_child(node)
	_motes(spot.y + 1.0, spot.x, spot.z, 12, MAGIC, 3.0, 0.6)


func _arch(x: float, z: float, surface_y: float, width: float, height: float, yaw: float) -> void:
	var node := Node3D.new()
	node.position = Vector3(x, surface_y, z)
	node.rotation.y = yaw
	for side in [-1.0, 1.0]:
		_box(node, Vector3(0.8, height, 0.8), _material(STONE), Vector3(side * width * 0.5, height * 0.5, 0.0))
		_box(node, Vector3(1.0, 0.35, 1.0), _material(STONE_DEEP), Vector3(side * width * 0.5, 0.18, 0.0))
	_box(node, Vector3(width + 0.9, 0.75, 1.0), _material(STONE), Vector3(0.0, height + 0.2, 0.0))
	_box(node, Vector3(width * 0.5, 0.5, 0.9), _material(STONE_DEEP), Vector3(0.0, height + 0.7, 0.0), Vector3(0.0, 0.0, 6.0))
	add_child(node)


func _pedestal(spot: Vector3) -> void:
	var node := Node3D.new()
	node.name = "Pedestal"
	node.position = spot
	_cylinder(node, 0.6, 0.25, _material(STONE_DEEP), Vector3(0.0, 0.12, 0.0), Vector3.ZERO, 0.5)
	_cylinder(node, 0.42, 1.0, _material(STONE), Vector3(0.0, 0.75, 0.0), Vector3.ZERO, 0.34)
	_torus(node, 0.3, 0.44, _material(MAGIC, MAGIC), Vector3(0.0, 1.35, 0.0))
	add_child(node)


func _cave_shell(spot: Vector3, radius: float) -> void:
	var node := Node3D.new()
	node.name = "CaveShell"
	node.position = spot
	_sphere(node, radius * 1.15, _material(ROCK_DEEP), Vector3(0.0, radius * 0.55, 0.0), Vector3(1.0, 0.8, 1.0))
	_sphere(node, radius * 0.62, _material(ROCK), Vector3(radius * 0.9, radius * 0.35, radius * 0.5), Vector3(1.0, 0.7, 1.0))
	add_child(node)


func _cliff(surface_y: float, x: float, z: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Cliff"
	body.position = Vector3(x, surface_y, z)
	_cylinder(body, 2.6, height, _material(ROCK_DEEP), Vector3(0.0, height * 0.5, 0.0), Vector3.ZERO, 1.7)
	_sphere(body, 2.5, _material(GRASS), Vector3(0.0, height, 0.0), Vector3(1.0, 0.3, 1.0))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.6
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)
	_record_surface(Vector3(x, surface_y + height, z), 2.4)


func _waterfall(spot: Vector3, width: float, height: float) -> void:
	var node := Node3D.new()
	node.name = "Waterfall"
	node.position = spot
	_box(node, Vector3(width, height, 0.18), _water_material(), Vector3(0.0, -height * 0.5, 0.0))
	_box(node, Vector3(width * 1.05, 0.5, 0.6), _water_material(), Vector3(0.0, 0.2, 0.2))
	# Foam and spray at the bottom.
	_box(node, Vector3(width * 1.2, 0.35, 0.8), _material(Color("#e8f8ff"), Color("#dff4ff"), 0.4), Vector3(0.0, -height + 0.2, 0.1))
	add_child(node)
	_motes(spot.y - height + 0.6, spot.x, spot.z + 0.3, 40, Color("#eaf9ff"), 2.4, 1.4)


## Ambient magic motes. [param rise] is how gently they drift upward.
func _motes(surface_y: float, x: float, z: float, amount: int, color: Color, spread: float, rise := 0.35) -> void:
	var material := _glow_material(color, color, 1.4)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = spread * 0.5
	process.direction = Vector3(0, 1, 0)
	process.spread = 35.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3(0.0, rise, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.5
	process.damping_min = 0.05
	process.damping_max = 0.2
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 4.0
	particles.preprocess = 3.0
	particles.explosiveness = 0.0
	particles.draw_pass_1 = quad
	particles.material_override = material
	particles.process_material = process
	particles.position = Vector3(x, surface_y + spread * 0.4, z)
	particles.emitting = true
	add_child(particles)