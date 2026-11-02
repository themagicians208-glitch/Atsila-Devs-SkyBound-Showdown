extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var progress := get_root().get_node("Progress")
	progress.config_path = "user://level_regression_%d.cfg" % OS.get_process_id()
	progress.clear()
	create_timer(20.0, true, false, true).timeout.connect(func():
		push_error("LEVEL REGRESSION timed out")
		quit(1))
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "main scene must load")
	for level in [1, 2, 4, 5, 6]:
		set_meta("level_number", level)
		var instance: Node = packed.instantiate()
		root.add_child(instance)
		await process_frame
		assert(instance.get("current_level") == level, "level %d must load" % level)
		assert(instance.get("frozen_skies") == null, "level %d must not use Frozen Skies builder" % level)
		if level == 2:
			assert(instance.get("woods") != null, "Level 2 must use the Whispering Woods builder")
			assert(instance.get("woods").get_node_or_null("SecondFragmentChest") != null, "Level 2 must spawn Second Fragment chest")
			assert(get_first_node_in_group("woods_boss") != null, "Level 2 must spawn Shadow Wolf boss")
		instance.queue_free()
		await process_frame
	print("LEVEL REGRESSION smoke passed: 1, 2, 4, 5, 6")
	progress.clear()
	quit()
