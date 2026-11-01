extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Smoke tests must start from a known progression state, not a developer save.
	get_root().get_node("Progress").clear()
	get_root().get_node("Progress").recover_second_fragment()
	set_meta("level_number", 3)
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "main scene must load")
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	assert(instance.get("current_level") == 3, "level 3 must be selected")
	assert(get_root().get_node("Progress").second_fragment_recovered, "Level 3 must preserve the Second Fragment")
	assert(get_root().get_node("Progress").frozen_checkpoint_index == 0, "Frozen Skies must start at its arrival checkpoint")
	assert(instance.get("frozen_skies") != null, "Frozen Skies builder must be active")
	var world: Node = instance.get_node("World")
	assert(world.get_node_or_null("FrostTitan") != null, "Frost Titan must spawn")
	assert(world.get_node_or_null("ThirdFragmentChest") != null, "Third Fragment chest must spawn")
	assert(instance.get("frozen_skies").mechanisms.size() == 3, "three frozen mechanisms must spawn")
	assert(instance.get("frozen_skies").region_names.size() == 6, "Frozen Skies needs six named regions")
	assert(instance.get("frozen_skies").region_name_for_checkpoint(38) == "Frost Titan's Sanctuary", "boss region must be named")
	assert(instance.get("mirror_dimension") == false, "Frozen Skies must preserve the material dimension on arrival")
	var first_bridge: Node = instance.get("frozen_skies")._ice_bridges[0]
	var first_bridge_shape: CollisionShape3D = first_bridge.find_children("*", "CollisionShape3D", true, false)[0]
	assert(first_bridge_shape.disabled, "Frozen Switch bridge must start closed")
	var crystal_puzzle: Node = world.get_node("CrystalLightPuzzle")
	assert(not crystal_puzzle.is_solved, "crystal light puzzle starts unsolved")
	var crystal_gate: Node = world.get_node("CrystalLightGate")
	assert(not crystal_gate.opened, "crystal gate starts closed")
	assert(world.find_children("FrostSlime", "Node3D", true, false).size() > 0, "Frost Slimes must spawn")
	assert(world.find_children("FrostWolf", "Node3D", true, false).size() > 0, "Frost Wolves must spawn")
	assert(world.find_children("CrystalPhantom", "Node3D", true, false).size() > 0, "Crystal Phantoms must spawn")
	for frozen_enemy in world.get_tree().get_nodes_in_group("enemies"):
		if frozen_enemy is FrozenEnemy:
			assert(frozen_enemy.get_node_or_null("FrostParticles") != null, "Frozen enemies need frost particles")
	assert(world.find_children("MovingIcePlatform*", "Node3D", true, false).size() >= 5, "Frozen Skies needs moving ice platforms")
	assert(world.find_children("UnstableIce_*", "Node3D", true, false).size() == 4, "Frozen Lake needs unstable ice")
	assert(get_nodes_in_group("collectible_coins").size() >= 50, "Frozen Skies needs at least 50 coins")
	assert(instance.get("frozen_skies").portal_count == 2, "Frozen Skies needs arrival and exit portals")
	assert(instance.get_node("HUD").frozen_progress_hint != null, "Frozen Skies needs progression HUD")
	assert(not instance.get("frozen_skies").arrival_cinematic_complete, "arrival portal must begin opening")
	assert(instance.get("frozen_skies").waterfall_count == 6, "Frozen Skies needs frozen waterfalls")
	assert(instance.get("frozen_skies").cave_cluster_count == 4, "Frozen Crystal Caves need crystal clusters")
	var player: Node = instance.get_node("Player")
	var crystals: Array = crystal_puzzle.get("_crystals")
	for index in crystals.size():
		player.global_position = crystals[index].global_position
		for turn in range(index + 1):
			assert(crystal_puzzle.try_interact(player), "crystal interaction must be usable")
	assert(crystal_puzzle.is_solved, "crystal light puzzle must solve")
	assert(crystal_gate.opened, "crystal light puzzle must open its gate")
	var wolf: Node = world.find_children("FrostWolf", "Node3D", true, false)[0]
	assert(is_equal_approx(wolf._movement_speed(player), float(player.movement_speed) * 1.10), "Frost Wolf must be 110% of player speed")
	wolf.global_position = player.global_position + Vector3(0.0, 0.0, 1.8)
	wolf._physics_process(0.016)
	assert(wolf._lunge_time > 0.0, "Frost Wolf must have an icy lunge attack")
	var shadow_slime_script: GDScript = load("res://objects/shadow_slime.gd")
	var original_slime: Node = shadow_slime_script.new()
	assert(wolf.attack_damage < original_slime.contact_damage, "Frost Wolf attack must be lower than the original Shadow Slime")
	original_slime.free()
	var slime: Node = world.find_children("FrostSlime", "Node3D", true, false)[0]
	assert(is_equal_approx(slime._movement_speed(player), float(player.movement_speed) * 0.50), "Frost Slime must be 50% of player speed")
	var phantom: Node = world.find_children("CrystalPhantom", "Node3D", true, false)[0]
	player.global_position = Vector3(0.0, 0.0, -20.0)
	var phantom_before: Vector3 = phantom.global_position
	phantom._physics_process(0.5)
	assert(not phantom.global_position.is_equal_approx(phantom_before), "Crystal Phantom must patrol when not chasing")
	var titan: Node = world.get_node("FrostTitan")
	assert(titan.locked, "Frost Titan must be locked behind the frozen seals")
	var seal_list: Array = instance.get("frozen_skies").mechanisms
	player.global_position = seal_list[1].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "blocked seal interaction must be handled")
	player.global_position = seal_list[0].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "first seal must activate")
	assert(not first_bridge_shape.disabled, "Frozen Switch must open the ice bridge")
	player.global_position = seal_list[1].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "crystal-generator seal must activate after its challenge")
	player.global_position = seal_list[2].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "final seal must activate after the previous seal")
	assert(not titan.locked, "Frost Titan must unlock after all frozen seals")
	assert(instance.get("frozen_skies").boss_arena_locked, "Frost Titan arena must lock during the fight")
	assert(get_root().get_node("Progress").ice_shield_unlocked, "Ice Shield must unlock at the first seal")
	assert(get_root().get_node("Progress").frost_dash_unlocked, "Frost Dash must unlock at the second seal")
	assert(get_root().get_node("Progress").crystal_activation_unlocked, "Crystal Activation must unlock at the third seal")
	player._activate_ice_shield()
	assert(player.ice_shield_active, "Ice Shield must activate")
	var health_before_shield: float = player.health
	player.take_damage(100.0, player.global_position, "test")
	assert(is_equal_approx(player.health, health_before_shield), "Ice Shield must block damage")
	player._start_frost_dash()
	assert(player.is_dashing, "Frost Dash must activate")
	titan.take_hit(10, player.global_position)
	assert(titan.phase == 2, "Frost Titan must enter phase 2")
	titan._perform_phase_attack(player)
	assert(get_nodes_in_group("frost_hazards").size() > 0, "Titan phase 2 must create ice hazards")
	titan.take_hit(12, player.global_position)
	assert(titan.phase == 3, "Frost Titan must enter phase 3")
	titan.take_hit(8, player.global_position)
	assert(titan.phase == 4, "Frost Titan must enter the final phase")
	var frozen: Node = instance.get("frozen_skies")
	var chest: Node = world.get_node("ThirdFragmentChest")
	assert(not chest.unlocked, "fragment chest must stay locked before the boss")
	chest.unlock()
	chest._on_body_entered(player)
	await create_timer(1.0).timeout
	assert(get_root().get_node("Progress").third_fragment_recovered, "chest must recover the Third Fragment")
	assert(frozen.fragment_recovered, "Frozen Skies must record the recovered Fragment")
	frozen.thaw_environment()
	assert(frozen.environment_thawed, "fragment recovery must thaw Frozen Skies")
	assert(not frozen.is_portal_ready(52), "Level 4 portal must stay locked before boss and fragment")
	frozen._on_boss_defeated()
	assert(not frozen.boss_arena_locked, "Frost Titan arena must reopen after victory")
	assert(not frozen.is_portal_ready(49), "Level 4 portal must require 50 coins")
	assert(frozen.is_portal_ready(50), "Level 4 portal must open at 50 coins after boss and fragment")
	assert(frozen.boss_defeated, "Frozen Skies must retain the defeated Titan state")
	assert(frozen.fragment_recovered, "Frozen Skies must retain the recovered fragment state")
	get_root().get_node("Progress").clear()
	print("LEVEL3 Frozen Skies smoke passed: coins=", get_nodes_in_group("collectible_coins").size())
	quit()

