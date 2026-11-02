extends Node3D

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.set("config_path", "user://progress_preview_ember.cfg")
		prog.call("clear")
	get_tree().set_meta("level_number", 4)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

