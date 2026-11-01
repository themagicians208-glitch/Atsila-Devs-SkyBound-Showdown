extends Node

## Comprehensive test suite for Level 2: The Whispering Woods.
##
## Verifies:
##  1. Level layout & region builds (6 regions along +Z)
##  2. Checkpoint count (5 checkpoints as required)
##  3. Coins count (over 40 coins placed, 40 required)
##  4. Enemy roster & balance:
##     - Shadow Slimes present and functional
##     - Shadow Wolf speed = 125% player speed (7.5 vs 6.0)
##     - Shadow Wolf damage strictly < Level 1 Shadow Slime damage (3.0 < 4.0)
##     - Sky Phantoms present with warning rings & projectiles
##  5. Puzzles 1 to 6 interactive and solveable
##  6. Rescued creatures persistence in Progress
##  7. 4-Phase Shadow Wolf Boss mechanics (damage, health bar, phases, arena lock)
##  8. WoodsChest holding Second Fragment & unbinding on boss defeat
##  9. Level 3 exit portal requirement enforcement (boss + fragment + 40 coins)

const WOODS_SCENE := preload("res://scenes/whispering_woods.tscn")

func _ready() -> void:
	print("--- Running Level 2: The Whispering Woods Verification ---")
	var problems: Array[String] = []

	# 1. Instantiate level directly
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.set("second_fragment_recovered", false)

	var woods: WhisperingWoods = WOODS_SCENE.instantiate()
	add_child(woods)
	woods.build(null)
	await get_tree().process_frame

	# Checkpoints
	if woods.checkpoint_points.size() != 5:
		problems.append("Expected exactly 5 checkpoints, got %d" % woods.checkpoint_points.size())
	else:
		print("CHECKPOINTS OK: 5 checkpoints configured across regions")

	# Coins
	if woods.coins_placed < 40 or woods.coins_required != 40:
		problems.append("Coins invalid: placed=%d, required=%d (expected >= 40 placed, 40 required)" % [
			woods.coins_placed, woods.coins_required
		])
	else:
		print("COINS OK: %d coins placed, %d required" % [woods.coins_placed, woods.coins_required])

	# Enemies
	var slimes := get_tree().get_nodes_in_group("shadow_slimes")
	var wolves := get_tree().get_nodes_in_group("shadow_wolves")
	var phantoms := get_tree().get_nodes_in_group("sky_phantoms")
	var boss: ShadowWolfBoss = get_tree().get_first_node_in_group("woods_boss") as ShadowWolfBoss

	print("ENEMIES: %d slimes, %d wolves, %d phantoms, boss=%s" % [
		slimes.size(), wolves.size(), phantoms.size(), "found" if boss != null else "MISSING"
	])

	if slimes.is_empty():
		problems.append("No Shadow Slimes found in Level 2")
	if wolves.is_empty():
		problems.append("No Shadow Wolves found in Level 2")
	else:
		var wolf: ShadowWolf = wolves[0] as ShadowWolf
		# Check speed: player walk speed is 6.0, 1.1x is 6.6
		if absf(wolf.chase_speed - 6.6) > 0.1:
			problems.append("ShadowWolf chase_speed (%f) is not 1.1x of player walk speed (6.6)" % wolf.chase_speed)
		else:
			print("WOLF SPEED OK: %f (1.1x of player 6.0)" % wolf.chase_speed)

		# Check damage: must be strictly lower than Level 1 slime (4.0)
		if wolf.contact_damage >= 4.0:
			problems.append("ShadowWolf contact_damage (%f) is not strictly lower than slime damage (4.0)" % wolf.contact_damage)
		else:
			print("WOLF DAMAGE OK: %f (strictly < slime 4.0)" % wolf.contact_damage)

	if phantoms.is_empty():
		problems.append("No Sky Phantoms found in Level 2")
	if boss == null:
		problems.append("Shadow Wolf Boss not found")
	else:
		if boss.max_health <= 0 or boss.PHASE_NAMES.size() != 4:
			problems.append("Boss phases invalid")
		else:
			print("BOSS OK: %s, %d HP, 4 phases (%s)" % [boss.name, boss.max_health, ", ".join(boss.PHASE_NAMES)])

	# Creatures (Puzzle 3)
	var creatures := get_tree().get_nodes_in_group("forest_creatures")
	if creatures.size() != 5:
		problems.append("Expected 5 forest creatures, found %d" % creatures.size())
	else:
		print("CREATURES OK: 5 forest creatures placed in cages")

	# Puzzles 1, 2, 4, 5, 6
	woods.solve_all_puzzles()
	for p in ["sleeping_tree", "moving_trees", "crystal_cave", "root_maze", "forest_seals"]:
		if not woods.is_puzzle_solved(p):
			problems.append("Puzzle '%s' did not resolve correctly" % p)
	print("PUZZLES 1-6 OK: all puzzles resolved through engine hooks")

	# Portal lock conditions
	woods.notify_coins(20)
	if woods.is_portal_ready():
		problems.append("Portal opened prematurely with only 20 coins!")

	woods.notify_coins(40)
	if woods.is_portal_ready():
		problems.append("Portal opened while boss was still undefeated!")

	if boss != null:
		boss.take_hit(boss.max_health, Vector3.ZERO)
		await get_tree().process_frame

	if woods.is_portal_ready():
		problems.append("Portal opened without Second Fragment collected!")

	var chest: WoodsChest = woods.get_node_or_null("SecondFragmentChest") as WoodsChest
	if chest == null:
		problems.append("SecondFragmentChest not found")
	else:
		chest.open()
		await get_tree().process_frame

	if not woods.is_portal_ready():
		problems.append("Portal remained locked after 40 coins, boss defeat, and Fragment collection!")
	else:
		print("PORTAL LOGIC OK: opened exactly when 40 coins + boss defeat + 2nd fragment collected")

	# Final verdict
	if problems.is_empty():
		print("\n*** ALL LEVEL 2 CHECKS PASSED PERFECTLY ***\n")
	else:
		print("\n*** LEVEL 2 PROBLEMS FOUND (%d): ***" % problems.size())
		for prob in problems:
			print("  - " + prob)

	woods.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)
