extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var progress := get_root().get_node("Progress")
	progress.config_path = "user://level_transition_%d.cfg" % OS.get_process_id()
	progress.clear()
	progress.recover_fragment()
	progress.recover_second_fragment()
	set_meta("level_number", 2)
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await process_frame
	var level2: Node = current_scene
	assert(level2.get("current_level") == 2, "handoff check must start on Level 2")
	await process_frame
	level2.set("coins_collected", level2.get("coin_goal"))
	level2.get("woods").notify_coins(level2.get("coin_goal"))
	var woods_boss: Node = level2.get("woods").get("_boss")
	woods_boss.set("is_defeated", true)
	level2.get("woods").boss_defeated()
	progress.recover_second_fragment()
	level2._on_finish_body_entered(level2.get("player"))
	assert(level2.get_node("HUD").victory_overlay.visible, "Level 2 portal must complete the level")
	level2._on_continue_pressed()
	await scene_changed
	await process_frame
	var level3: Node = current_scene
	assert(level3.get("current_level") == 3, "Level 2 portal must load Level 3")
	assert(level3.get("frozen_skies") != null, "Level 3 handoff must build Frozen Skies")
	assert(level3.get_node("HUD").level_heading.text.contains("FROZEN SKIES"), "Level 3 handoff must show the Frozen Skies title")
	progress.recover_third_fragment()
	level3.set("coins_collected", 50)
	level3.get("frozen_skies").boss_defeated = true
	level3.get("frozen_skies").fragment_recovered = true
	level3._on_finish_body_entered(level3.get("player"))
	assert(level3.get_node("HUD").victory_overlay.visible, "Frozen Skies portal must complete the level")
	level3._on_continue_pressed()
	await scene_changed
	await process_frame
	var level4: Node = current_scene
	assert(level4.get("current_level") == 4, "Frozen Skies portal must load Level 4")
	assert(level4.get("frozen_skies") == null, "Level 4 handoff must leave Frozen Skies")
	progress.clear()
	print("LEVEL TRANSITION smoke passed: Level 2 -> Frozen Skies -> Level 4")
	quit()
