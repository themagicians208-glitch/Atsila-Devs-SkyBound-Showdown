extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
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
			assert(instance.get_node("World").get_node_or_null("ShadowWolf") != null, "Level 2 must spawn Shadow Wolf")
			assert(instance.get_node("World").get_node_or_null("SecondFragmentChest") != null, "Level 2 must spawn Second Fragment chest")
		instance.queue_free()
		await process_frame
	print("LEVEL REGRESSION smoke passed: 1, 2, 4, 5, 6")
	quit()
