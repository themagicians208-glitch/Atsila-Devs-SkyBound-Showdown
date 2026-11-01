extends Node

func _ready() -> void:
	get_tree().set_meta("level_number", 2)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
