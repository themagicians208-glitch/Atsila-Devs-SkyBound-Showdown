extends Node

## Opens the character select with two slots, exactly as the local split-screen
## flow does, to check the layout and previews fit.

func _ready() -> void:
	var home: Node = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	await get_tree().process_frame
	home.call("_show_character_select", 2, func() -> void: pass, Callable())
