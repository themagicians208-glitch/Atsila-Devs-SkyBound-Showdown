extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Smoke tests must start from a known progression state, not a developer save.
	get_root().get_node("Progress").config_path = "user://level3_smoke_%d.cfg" % OS.get_process_id()
	create_timer(20.0, true, false, true).timeout.connect(func():
		push_error("LEVEL3 smoke timed out")
		quit(1))
	get_root().get_node("Progress").clear()
	get_root().get_node("Progress").recover_fragment()
	get_root().get_node("Progress").recover_second_fragment()
	set_meta("level_number", 3)
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "main scene must load")
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	assert(instance.get("current_level") == 3, "level 3 must be selected")
	assert(instance.get_node("HUD").level_heading.text.contains("FROZEN SKIES"), "Level 3 HUD must be titled Frozen Skies")
	instance.get_node("HUD").play_level_transition("LEVEL 3 – FROZEN SKIES", func(): pass)
	await process_frame
	assert(instance.get_node("HUD")._transition_overlay != null, "level transitions must create their fade overlay on first use")
	assert(not instance.get_node("View").input_enabled, "Frozen Skies arrival must begin with a camera reveal")
	assert(get_root().get_node("Progress").second_fragment_recovered, "Level 3 must preserve the Second Fragment")
	assert(get_root().get_node("Progress").fragment_recovered, "Level 3 must preserve the First Fragment")
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
	var moving_platform: Node3D = world.find_children("MovingIcePlatform*", "Node3D", true, false)[0]
	var moving_position := moving_platform.position
	instance.get("frozen_skies")._process(0.5)
	assert(not moving_platform.position.is_equal_approx(moving_position), "Frozen moving platforms must move over time")
	assert(world.find_children("UnstableIce_*", "Node3D", true, false).size() == 4, "Frozen Lake needs unstable ice")
	assert(get_nodes_in_group("collectible_coins").size() >= 50, "Frozen Skies needs at least 50 coins")
	assert(instance.get("frozen_skies").portal_count == 2, "Frozen Skies needs arrival and exit portals")
	assert(world.get_node_or_null("Level2ReturnPortalArea") != null, "Frozen arrival portal must provide a Level 2 return interaction")
	assert(instance.get_node("HUD").frozen_progress_hint != null, "Frozen Skies needs progression HUD")
	assert(instance.get_node("HUD").frozen_progress_hint.text.contains("GENERATORS 0/3"), "Frozen HUD must show generator progress")
	assert(not instance.get("frozen_skies").arrival_cinematic_complete, "arrival portal must begin opening")
	assert(instance.get("frozen_skies").waterfall_count == 6, "Frozen Skies needs frozen waterfalls")
	assert(instance.get("frozen_skies").cave_cluster_count == 4, "Frozen Crystal Caves need crystal clusters")
	assert(instance.get("frozen_skies").glowing_flower_count >= 8, "Frozen Skies needs glowing blue flowers")
	assert(instance.get("frozen_skies").frozen_ruin_count >= 3, "Frozen Skies needs ancient frozen ruins")
	assert(instance.get("frozen_skies")._crystal_generators.size() == 3, "Crystal Cave needs three generators")
	var player: Node = instance.get_node("Player")
	var slippery_zone: Node = load("res://scripts/slippery_zone.gd").new()
	slippery_zone._on_body_entered(player)
	assert(player.slippery, "Frozen ice zones must enable slippery movement")
	slippery_zone._on_body_exited(player)
	assert(not player.slippery, "Leaving Frozen ice zones must restore movement control")
	slippery_zone.free()
	var crystals: Array = crystal_puzzle.get("_crystals")
	for index in crystals.size():
		player.global_position = crystals[index].global_position
		for turn in range(index + 1):
			assert(crystal_puzzle.try_interact(player), "crystal interaction must be usable")
	assert(crystal_puzzle.is_solved, "crystal light puzzle must solve")
	assert(crystal_gate.opened, "crystal light puzzle must open its gate")
	assert(get_root().get_node("Progress").crystal_activation_unlocked, "solving crystal light must unlock Crystal Activation before the cave")
	var wolf: Node = world.find_children("FrostWolf", "Node3D", true, false)[0]
	assert(is_equal_approx(wolf._movement_speed(player), player.get_normal_movement_speed() * 1.10), "Frost Wolf must be 110% of actual player speed")
	wolf.global_position = player.global_position + Vector3(0.0, 0.0, 1.8)
	wolf._physics_process(0.016)
	assert(wolf._lunge_time > 0.0, "Frost Wolf must have an icy lunge attack")
	var shadow_slime_script: GDScript = load("res://objects/shadow_slime.gd")
	var original_slime: Node = shadow_slime_script.new()
	assert(wolf.attack_damage < original_slime.contact_damage, "Frost Wolf attack must be lower than the original Shadow Slime")
	var health_before_wolf: float = player.health
	player.take_damage(wolf.attack_damage, wolf.global_position, "frozen_enemy")
	assert(not player.is_dead and is_equal_approx(player.health, health_before_wolf - wolf.attack_damage), "Frost Wolf must deal ordinary nonfatal configured damage")
	player.reset_vitals()
	original_slime.free()
	var slime: Node = world.find_children("FrostSlime", "Node3D", true, false)[0]
	assert(is_equal_approx(slime._movement_speed(player), player.get_normal_movement_speed() * 0.50), "Frost Slime must be 50% of actual player speed")
	var phantom: Node = world.find_children("CrystalPhantom", "Node3D", true, false)[0]
	player.global_position = Vector3(0.0, 0.0, -20.0)
	var phantom_before: Vector3 = phantom.global_position
	phantom._physics_process(0.5)
	assert(not phantom.global_position.is_equal_approx(phantom_before), "Crystal Phantom must patrol when not chasing")
	player.global_position = phantom.global_position + Vector3(0.0, 0.0, 4.0)
	phantom._projectile_cooldown = 0.0
	phantom._physics_process(0.016)
	assert(phantom._attack_warning.visible, "Crystal Phantom must telegraph ice projectiles")
	var titan: Node = world.get_node("FrostTitan")
	assert(titan.locked, "Frost Titan must be locked behind the frozen seals")
	var seal_list: Array = instance.get("frozen_skies").mechanisms
	instance.set("active_checkpoint", 9)
	instance.set("checkpoint_position", instance.get("frozen_skies").route[9] + Vector3(0.0, 0.55, 0.0))
	get_root().get_node("Progress").set_frozen_checkpoint(9)
	player.die("checkpoint_test")
	await create_timer(0.7).timeout
	assert(not player.is_dead, "Frozen Skies defeat must respawn the player")
	assert(player.global_position.distance_to(instance.get("checkpoint_position")) < 0.6, "Frozen Skies defeat must use the latest checkpoint")
	player.global_position = instance.get("frozen_skies")._timed_seal_switch.global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "timed seal switch must start the first seal challenge")
	player.global_position = seal_list[1].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "blocked seal interaction must be handled")
	player.global_position = seal_list[0].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "first seal must activate")
	assert(not first_bridge_shape.disabled, "Frozen Switch must open the ice bridge")
	player.global_position = seal_list[1].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "crystal-generator seal must activate after its challenge")
	for enemy in get_nodes_in_group("enemies"):
		if enemy is FrozenEnemy:
			enemy.take_hit(999, player.global_position)
	await process_frame
	player.global_position = seal_list[2].global_position
	assert(instance.get("frozen_skies").try_activate_nearby(player), "final seal must activate after the previous seal")
	assert(not titan.locked, "Frost Titan must unlock after all frozen seals")
	assert(instance.get("frozen_skies").boss_arena_locked, "Frost Titan arena must lock during the fight")
	assert(get_root().get_node("Progress").ice_shield_unlocked, "Ice Shield must unlock at the first seal")
	assert(get_root().get_node("Progress").frost_dash_unlocked, "Frost Dash must unlock at the second seal")
	assert(get_root().get_node("Progress").crystal_activation_unlocked, "Crystal Activation must unlock at the third seal")
	var generators: Array = instance.get("frozen_skies")._crystal_generators
	for generator in generators:
		player.global_position = generator.global_position
		assert(instance.get("frozen_skies").try_activate_nearby(player), "Crystal Activation must activate cave generators")
	assert(get_root().get_node("Progress").frozen_generators_activated == 3, "all three cave generators must activate")
	assert(instance.get("frozen_skies")._cave_gate.opened, "three generators must open the cave door")
	player._activate_ice_shield()
	assert(player.ice_shield_active, "Ice Shield must activate")
	var health_before_shield: float = player.health
	player.take_damage(100.0, player.global_position, "test")
	assert(is_equal_approx(player.health, health_before_shield), "Ice Shield must block damage")
	player._start_frost_dash()
	assert(player.is_dashing, "Frost Dash must activate")
	assert(is_equal_approx(player.get_normal_movement_speed() * player.frost_dash_speed_multiplier, player.movement_speed * player.get_physics_process_delta_time() * 3.0), "Frost Dash must scale from normal movement speed")
	titan.take_hit(10, player.global_position)
	assert(titan.phase == 2, "Frost Titan must enter phase 2")
	titan._perform_phase_attack(player)
	assert(get_nodes_in_group("frost_hazards").size() > 0, "Titan phase 2 must create ice hazards")
	titan.take_hit(12, player.global_position)
	assert(titan.phase == 3, "Frost Titan must enter phase 3")
	titan._perform_phase_attack(player)
	assert(titan._warning.visible, "Frost Titan phase 3 must show a reappearance warning")
	assert(not titan._visual.visible, "Frost Titan phase 3 must disappear before reappearing")
	await create_timer(0.45).timeout
	assert(not titan._warning.visible, "Frost Titan phase 3 warning must clear after reappearance")
	assert(titan._visual.visible, "Frost Titan phase 3 must reappear after the warning")
	titan.take_hit(8, player.global_position)
	assert(titan.phase == 4, "Frost Titan must enter the final phase")
	var frozen: Node = instance.get("frozen_skies")
	var chest: Node = world.get_node("ThirdFragmentChest")
	assert(not chest.unlocked, "fragment chest must stay locked before the boss")
	assert(not frozen.is_portal_ready(52), "Level 4 portal must stay locked before the boss")
	assert(frozen.portal_blocked_reason(12).contains("Coins 12/50") and frozen.portal_blocked_reason(12).contains("Defeat the Frost Titan"), "portal must show coin and boss requirements")
	titan.take_hit(999, player.global_position)
	await process_frame
	assert(chest.unlocked, "defeating the Frost Titan must unlock the fragment chest")
	assert(not frozen.is_portal_ready(50), "Level 4 portal must stay locked before the fragment")
	assert(frozen.portal_blocked_reason(50).contains("Recover the Third Fragment"), "portal must show the missing fragment requirement")
	chest._on_body_entered(player)
	await create_timer(1.0).timeout
	assert(get_root().get_node("Progress").third_fragment_recovered, "chest must recover the Third Fragment")
	assert(frozen.fragment_recovered, "Frozen Skies must record the recovered Fragment")
	frozen.thaw_environment()
	assert(frozen.environment_thawed, "fragment recovery must thaw Frozen Skies")
	assert(not frozen.boss_arena_locked, "Frost Titan arena must reopen after victory")
	assert(not frozen.is_portal_ready(49), "Level 4 portal must require 50 coins")
	assert(frozen.portal_blocked_reason(49).contains("Coins 49/50"), "portal must show the current coin count")
	assert(frozen.is_portal_ready(50), "Level 4 portal must open at 50 coins after boss and fragment")
	assert(frozen.boss_defeated, "Frozen Skies must retain the defeated Titan state")
	assert(frozen.fragment_recovered, "Frozen Skies must retain the recovered fragment state")
	instance.queue_free()
	await process_frame
	var restored: Node = packed.instantiate()
	root.add_child(restored)
	await process_frame
	assert(restored.get("current_level") == 3, "Frozen Skies must reload from saved progression")
	assert(get_root().get_node("Progress").fragment_recovered and get_root().get_node("Progress").second_fragment_recovered, "saved fragments must survive a Frozen Skies reload")
	assert(get_root().get_node("Progress").third_fragment_recovered and get_root().get_node("Progress").frost_titan_defeated, "saved boss and Third Fragment state must survive a reload")
	assert(get_root().get_node("Progress").frozen_checkpoint_index == 9, "saved Frozen Skies checkpoint must survive a reload")
	assert(restored.get("frozen_skies").is_portal_ready(50), "saved Frozen Skies progression must reopen the Level 4 portal")
	restored.queue_free()
	await process_frame
	get_root().get_node("Progress").clear()
	print("LEVEL3 Frozen Skies smoke passed: coins=", get_nodes_in_group("collectible_coins").size())
	quit()

