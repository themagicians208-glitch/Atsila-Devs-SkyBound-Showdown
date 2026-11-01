extends Node

## Opens the inventory over a level so the panel can be seen.

func _ready() -> void:
	get_tree().set_meta("level_number", 3)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var hud: Control = main.get_node("HUD")
	hud.call("_on_coin_collected", 5)
	await get_tree().create_timer(0.3).timeout
	hud.call("open_inventory")
