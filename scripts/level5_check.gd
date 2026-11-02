extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	set_meta("level_number", 5)
	set_meta("resume_save", false)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	print("LEVEL5 current_level=", instance.get("current_level"), " player=", instance.get_node("Player").global_position)
	var world: Node = instance.get_node("World")
	print("boss=", world.has_node("Malakar"), " approach=", world.find_children("GateApproach_*", "Node3D", true, false).size(), " loop=", world.find_children("IslandLoopPlatform_*", "Node3D", true, false).size(), " raccoons=", world.find_children("IslandRaccoon_*", "Node3D", true, false).size())
	quit()
