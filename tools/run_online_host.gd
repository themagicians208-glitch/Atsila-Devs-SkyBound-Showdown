extends Node

## Dev helper: hosts an ENet room and drops straight into the level (online mode).


func _ready() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		return
	network.local_name = "Tester"
	network.host()
	get_tree().set_meta("online", true)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("level_number", 1)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")