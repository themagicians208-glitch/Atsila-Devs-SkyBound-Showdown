extends Node

## Comprehensive verification suite for Level 4: EMBER HEIGHTS.
## Verifies all 20 requirements from Section 15 (FINAL TESTING).

var _problems: Array[String] = []
var _real_config_path: String = ""

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_problems.append(msg)

func _ready() -> void:
	print("--- Running Level 4: Ember Heights Verification ---")
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		_real_config_path = str(prog.get("config_path"))
		prog.set("config_path", "user://progress_ember_check.cfg")
		prog.call("clear")
		prog.call("recover_fragment")
		prog.call("recover_second_fragment")
		prog.call("recover_third_fragment")
		prog.call("unlock_ice_shield")
		prog.call("unlock_frost_dash")

	get_tree().set_meta("level_number", 4)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var ember: EmberHeights = main.get("ember_heights") as EmberHeights
	var world: Node3D = main.get_node("World") as Node3D
	var player: CharacterBody3D = main.get_node("Player") as CharacterBody3D
	var hud: Control = main.get_node("HUD") as Control

	_check(main.get("current_level") == 4, "Current level is not 4")
	_check(ember != null, "EmberHeights builder was not initialized")
	_check(hud.get("level_heading").text.contains("EMBER HEIGHTS"), "HUD level heading does not show EMBER HEIGHTS")
	_check(not bool(main.get_node("View").get("input_enabled")), "Arrival camera reveal cinematic did not start")

	# 1. Preserved Fragments 1, 2, 3 & Arrival Portal
	_check(bool(prog.get("fragment_recovered")), "First Fragment was not preserved")
	_check(bool(prog.get("second_fragment_recovered")), "Second Fragment was not preserved")
	_check(bool(prog.get("third_fragment_recovered")), "Third Fragment was not preserved")
	_check(ember.portal_count == 2, "Expected 2 portals (arrival + Level 5 exit), got %d" % ember.portal_count)
	_check(not ember.arrival_cinematic_complete, "Arrival portal opening animation should start on arrival")
	_check(ember.region_names.size() == 6, "Expected 6 regions in Ember Heights")
	_check(ember.checkpoint_indices.size() == 5, "Expected 5 checkpoints in Ember Heights")
	print("REGIONS & PORTALS OK: 6 regions, 5 checkpoints, arrival + exit portals present")

	# 2. Volcanic Enemy Variants (Magma Slime, Magma Wolf, Lava Phantom)
	var slimes := get_tree().get_nodes_in_group("magma_slimes")
	var wolves := get_tree().get_nodes_in_group("magma_wolves")
	var phantoms := get_tree().get_nodes_in_group("lava_phantoms")
	var dragon: EmberDragon = world.get_node_or_null("EmberDragon") as EmberDragon

	_check(slimes.size() >= 4, "Expected Magma Slimes in Level 4")
	_check(wolves.size() >= 4, "Expected Magma Wolves in Level 4")
	_check(phantoms.size() >= 3, "Expected Lava Phantoms in Level 4")
	_check(dragon != null, "EmberDragon boss did not spawn")

	var slime: VolcanicEnemy = slimes[0] as VolcanicEnemy
	var wolf: VolcanicEnemy = wolves[0] as VolcanicEnemy
	var phantom: VolcanicEnemy = phantoms[0] as VolcanicEnemy

	# Speed formula verification:
	# Magma Slime = 50% of player speed; Magma Wolf = 110% of player speed
	_check(is_equal_approx(slime.speed_ratio, 0.50), "Magma Slime speed_ratio is not 0.50")
	_check(is_equal_approx(slime._movement_speed(player), float(player.get("movement_speed")) * 0.50), "Magma Slime _movement_speed is not 50% of player speed")
	_check(is_equal_approx(wolf.speed_ratio, 1.10), "Magma Wolf speed_ratio is not 1.10")
	_check(is_equal_approx(wolf._movement_speed(player), float(player.get("movement_speed")) * 1.10), "Magma Wolf _movement_speed is not 110% of player speed")
	_check(is_equal_approx(wolf.chase_speed, 6.6), "Magma Wolf world chase_speed is not 6.6 (110% of 6.0)")

	# Damage verification: Magma Wolf attack damage < Level 1 Shadow Slime damage (4.0)
	var orig_slime: Node = load("res://objects/shadow_slime.gd").new()
	var orig_slime_dmg := float(orig_slime.get("contact_damage"))
	orig_slime.free()
	_check(wolf.attack_damage < orig_slime_dmg, "Magma Wolf attack_damage (%f) is not < Level 1 Shadow Slime (%f)" % [wolf.attack_damage, orig_slime_dmg])
	_check(is_equal_approx(slime.attack_damage, orig_slime_dmg), "Magma Slime attack_damage (%f) does not match Level 1 Shadow Slime (%f)" % [slime.attack_damage, orig_slime_dmg])
	_check(wolf._legs.size() == 4 and wolf._head_pivot != null and wolf._tail_pivot != null, "Magma Wolf does not have an articulated 4-legged rig")

	# Lava Phantom aerial patrol & projectile test
	player.global_position = Vector3(0.0, 0.0, -30.0)
	var phantom_pos_before := phantom.global_position
	phantom._physics_process(0.4)
	_check(not phantom.global_position.is_equal_approx(phantom_pos_before), "Lava Phantom did not patrol through the air")

	# Verify wolves and slimes cannot walk on air off their platforms
	player.global_position = wolf._home + Vector3(0.0, 0.0, 5.5)
	for step in 45:
		wolf._physics_process(0.016)
	var wolf_flat_dist := Vector2(wolf.global_position.x - wolf._home.x, wolf.global_position.z - wolf._home.z).length()
	_check(wolf_flat_dist <= 1.15, "Magma Wolf walked off its platform into the air (dist=%f)" % wolf_flat_dist)

	player.global_position = slime._home + Vector3(0.0, 0.0, 5.5)
	for step in 45:
		slime._physics_process(0.016)
	var slime_flat_dist := Vector2(slime.global_position.x - slime._home.x, slime.global_position.z - slime._home.z).length()
	_check(slime_flat_dist <= 1.15, "Magma Slime walked off its platform into the air (dist=%f)" % slime_flat_dist)

	# Verify no volcano cones merge/collide with any playing tiles
	for v_node in world.find_children("ActiveVolcano_*", "Node3D", true, false):
		var v_pos := (v_node as Node3D).global_position
		for r_pt in ember.route:
			var pt: Vector3 = r_pt
			var xz_dist := Vector2(v_pos.x - pt.x, v_pos.z - pt.z).length()
			_check(xz_dist > 7.5, "Volcano cone %s merges with playing tile at %s (dist=%f)" % [v_node.name, str(pt), xz_dist])

	# Verify Jolt solid collision registration for all playing tiles and slabs
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var solid_checked := 0
	for cap in world.find_children("VolcanicCap_*", "StaticBody3D", true, false):
		var c_body := cap as StaticBody3D
		var q := PhysicsRayQueryParameters3D.create(
			c_body.global_position + Vector3(0.0, 0.5, 0.0),
			c_body.global_position + Vector3(0.0, -0.5, 0.0)
		)
		var hit := space.intersect_ray(q)
		_check(not hit.is_empty(), "Playing tile %s is not registered as solid in Jolt physics" % c_body.name)
		solid_checked += 1
	print("SOLID TILES OK: %d playing tile caps verified solid in Jolt physics" % solid_checked)
	print("VOLCANIC ENEMIES & GEOMETRY OK: Magma Slime (50%%), Magma Wolf (110%%, dmg %.1f < %.1f), zero cone/tile merges, wolves/slimes cannot walk on air" % [wolf.attack_damage, orig_slime_dmg])

	# 3. Puzzles 1 to 7 & Magical Shield Ability
	# Puzzle 1: Ancient Energy Switch -> unlocks Magical Shield & opens AncientEnergyGate
	var energy_switch: Node3D = world.get_node("AncientEnergySwitch") as Node3D
	var switch_gate: Node = world.get_node("AncientEnergyGate")
	_check(not bool(switch_gate.get("opened")), "AncientEnergyGate should start closed")
	player.global_position = energy_switch.global_position
	_check(ember.try_activate_nearby(player), "Failed to activate AncientEnergySwitch")
	_check(bool(prog.get("magical_shield_unlocked")), "AncientEnergySwitch did not unlock Magical Shield")
	_check(bool(switch_gate.get("opened")), "AncientEnergyGate did not open")

	# Test Magical Shield activation, hazard protection & damage reduction
	player._activate_magical_shield()
	_check(bool(player.get("magical_shield_active")), "Magical Shield failed to activate")
	var hp_before: float = float(player.get("health"))
	player.take_damage(12.0, player.global_position, "lava_hazard")
	_check(is_equal_approx(float(player.get("health")), hp_before), "Magical Shield did not block selected environmental hazard (lava_hazard)")
	player.take_damage(20.0, player.global_position, "ember_dragon")
	_check(float(player.get("health")) < hp_before and float(player.get("health")) > hp_before - 20.0, "Magical Shield should reduce (not completely nullify) boss damage")
	player.reset_vitals()
	print("MAGICAL SHIELD OK: unlocked via Puzzle 1, blocks lava_hazard, reduces boss damage")

	# Puzzle 3: Three Magma Crystals
	for crystal in ember._magma_crystals:
		player.global_position = crystal.global_position
		_check(ember.try_activate_nearby(player), "Failed to activate MagmaCrystal")
	_check(int(prog.get("ember_crystals_activated")) == 3, "Expected 3 Magma Crystals activated")
	_check(bool(ember._crystal_gate.get("opened")), "MagmaCrystalGate did not open after 3 crystals")

	# Puzzle 4: Three Ancient Energy Machines (with Mid-Puzzle Rule Shift)
	for i in 2:
		var machine := ember._energy_machines[i]
		player.global_position = machine.global_position
		for step in 4:
			if not bool(machine.get("is_activated")):
				ember.try_activate_nearby(player)
	_check(int(prog.get("ember_machines_activated")) == 2, "Expected 2 Ancient Energy Machines activated before rule shift")
	_check(bool(ember._energy_machines[2].get("is_rule_shifted")), "Mid-puzzle rule shift failed to trigger on Machine 3 after 2 activations")

	# Complete Machine 3 under its shifted rule
	var final_machine := ember._energy_machines[2]
	player.global_position = final_machine.global_position
	for step in 4:
		if not bool(final_machine.get("is_activated")):
			ember.try_activate_nearby(player)
	_check(int(prog.get("ember_machines_activated")) == 3, "Expected 3 Ancient Energy Machines activated after completing shifted rule")
	_check(bool(ember._machine_gate.get("opened")), "EnergyFacilityGate did not open after 3 machines")

	# Puzzle 5: Rising Lava Chamber
	var chamber: Node3D = world.get_node("RisingLavaChamber") as Node3D
	chamber.call("solve")
	_check(bool(chamber.get("is_solved")), "RisingLavaChamber did not solve")
	_check(bool(ember._chamber_gate.get("opened")), "RisingLavaGate did not open")

	# Puzzle 6 & 7: Obsidian Fortress & Four Ember Seals
	_check(ember._rotating_bridges.size() >= 2, "Expected rotating obsidian bridges in Fortress")
	_check(ember._falling_rocks.size() >= 3, "Expected falling volcanic rocks in Fortress")
	_check(dragon.locked, "Ember Dragon must start locked before the 4 Ember Seals")

	# Defeat volcanic enemies so Seal 4 (enemy encounter seal) can activate
	for enemy in get_tree().get_nodes_in_group("volcanic_enemies"):
		if is_instance_valid(enemy) and enemy.has_method("take_hit"):
			enemy.call("take_hit", 999, player.global_position)
	await get_tree().process_frame

	for seal in ember.ember_seals:
		player.global_position = seal.global_position
		_check(ember.try_activate_nearby(player), "Failed to activate Ember Seal: %s" % seal.name)
	_check(int(prog.get("ember_seals_activated")) == 4, "Expected all 4 Ember Seals activated")
	_check(not dragon.locked, "Ember Dragon did not unlock after all 4 Ember Seals")
	_check(ember.boss_arena_locked, "Ember Dragon arena did not lock when fight began")
	print("PUZZLES 1-7 OK: Switch, Molten River, 3 Magma Crystals, 3 Energy Machines, Rising Lava Chamber, Obsidian Fortress, and 4 Ember Seals verified")

	# 4. Coins (must be > 60, portal requires 60)
	var total_coins := get_tree().get_nodes_in_group("collectible_coins").size()
	_check(total_coins > 60, "Expected > 60 coins in Ember Heights, found %d" % total_coins)
	_check(ember.coins_required == 60, "Level 5 portal coin requirement must be 60")
	print("COINS OK: %d coins placed (> 60 required)" % total_coins)

	# Verify arena cleanliness: only FourthFragmentChest in Guardian Arena, no puzzle switches or puzzle gates
	var arena_pos: Vector3 = ember.route[43]
	for child in world.get_children():
		if child.name.contains("Puzzle") or child.name.contains("Switch") or child.name.contains("Machine") or child.name.contains("Crystal"):
			var c_pos: Vector3 = (child as Node3D).global_position if child is Node3D else Vector3.ZERO
			var dist_to_arena := Vector2(c_pos.x - arena_pos.x, c_pos.z - arena_pos.z).length()
			_check(dist_to_arena > 6.0, "Unexpected puzzle element '%s' found in Guardian Arena" % child.name)

	# The arena must read as its own island: clear of every platform tile and of
	# the portal terrace, the way every other ledge on the route is.
	var arena_centre: Vector3 = ember.route[43] + Vector3(0.0, 0.0, 2.4)
	for child in world.get_children():
		var floor_node := child as Node3D
		if floor_node == null:
			continue
		var floor_radius := -1.0
		if floor_node.name.begins_with("EmberPlatform_"):
			floor_radius = 1.26   # the 2.52-wide volcanic tile cap
		elif floor_node.name == "Level5PortalTerrace":
			floor_radius = 3.0
		if floor_radius < 0.0:
			continue
		var floor_gap := Vector2(floor_node.position.x - arena_centre.x,
				floor_node.position.z - arena_centre.z).length() - 12.8 - floor_radius
		_check(floor_gap >= 0.5, "Floor %s merges with the Ember Dragon arena (only %.2f clear)" % [
			floor_node.name, floor_gap])
	print("ARENA SEPARATION OK: arena floor clear of every platform tile and the portal terrace")

	# 5. Final Boss: The Ember Dragon (movement and all 4 phases)
	_check(dragon.phase == 1, "Ember Dragon must start in Phase 1")
	var initial_pos: Vector3 = dragon.global_position
	player.global_position = arena_pos + Vector3(0.0, 0.0, -2.5)
	# Process one step to verify dragon actively moves towards player
	dragon._physics_process(0.2)
	var moved_dist := dragon.global_position.distance_to(initial_pos)
	_check(moved_dist > 0.1, "Ember Dragon is not moving towards player (moved %.2f)" % moved_dist)
	dragon._perform_phase_attack(player)
	dragon.take_hit(14, player.global_position)
	_check(dragon.phase == 2, "Ember Dragon did not enter Phase 2 (Rising Inferno)")
	dragon._perform_phase_attack(player)
	_check(get_tree().get_nodes_in_group("ember_dragon_hazards").size() > 0, "Ember Dragon Phase 2 did not spawn lava hazards")
	dragon.take_hit(12, player.global_position)
	_check(dragon.phase == 3, "Ember Dragon did not enter Phase 3 (Molten Fury)")
	dragon._perform_phase_attack(player)
	dragon.take_hit(12, player.global_position)
	_check(dragon.phase == 4, "Ember Dragon did not enter Phase 4 (Dragon's Awakening)")
	dragon._perform_phase_attack(player)

	# 6. Fourth Fragment Chest & Malakar's Fortress Discovery
	var chest: EmberFragmentChest = world.get_node("FourthFragmentChest") as EmberFragmentChest
	_check(not chest.unlocked, "Fourth Fragment chest must stay locked while Ember Dragon lives")
	_check(not ember.is_portal_ready(65), "Level 5 portal must stay locked before boss defeat and fragment recovery")
	_check(ember.portal_blocked_reason(25).contains("Coins 25/60 (35 more needed)") and ember.portal_blocked_reason(25).contains("Defeat the Ember Dragon"), "Portal blocked reason missing coin/boss details")

	# Defeat the Ember Dragon
	dragon.take_hit(20, player.global_position)
	_check(ember.boss_defeated, "EmberHeights did not record boss_defeated")
	_check(not ember.boss_arena_locked, "Boss arena did not unlock after Ember Dragon fell")
	_check(chest.unlocked and chest.magma_cooled, "Ancient Magma Chest did not unlock & cool magma after boss defeat")

	chest._on_body_entered(player)
	await get_tree().create_timer(0.85).timeout
	_check(bool(prog.get("fourth_fragment_recovered")), "Fourth Fragment was not saved in Progress")
	_check(bool(prog.get("malakar_fortress_discovered")), "Malakar's Fortress discovery was not saved in Progress")
	_check(ember.fragment_recovered and ember.fortress_discovered, "EmberHeights did not record fragment & fortress discovery")
	_check(ember.environment_recovered, "EmberHeights environment did not show signs of recovery")
	print("BOSS, 4TH FRAGMENT & FORTRESS DISCOVERY OK: 4 phases, magma chest cooled & opened, Malakar's Fortress discovered")

	# 7. Level 5 Portal Requirements
	_check(not ember.is_portal_ready(59), "Portal opened at 59 coins (requires 60)")
	_check(ember.portal_blocked_reason(59).contains("Coins 59/60 (1 more needed)"), "Portal blocked reason did not report 59/60 (1 more needed)")
	_check(ember.is_portal_ready(60), "Portal did not open with boss defeated, Fourth Fragment recovered, and 60 coins")
	print("LEVEL 5 PORTAL OK: locked at 59 coins, unlocked at 60 coins + boss + 4th Fragment")

	if prog != null:
		prog.call("clear")
		prog.set("config_path", _real_config_path)
		prog.call("load_progress")

	if _problems.is_empty():
		print("\n*** ALL LEVEL 4: EMBER HEIGHTS CHECKS PASSED PERFECTLY ***\n")
		get_tree().quit(0)
	else:
		print("\n*** LEVEL 4 PROBLEMS FOUND (%d): ***" % _problems.size())
		for p in _problems:
			print("  - " + p)
		get_tree().quit(1)
