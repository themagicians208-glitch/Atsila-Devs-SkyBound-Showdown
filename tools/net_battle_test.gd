extends Node

## Two-process check for the 1v1 battle arena over a real ENet connection.
##
##   godot --headless res://tools/net_battle_test.tscn -- host
##   godot --headless res://tools/net_battle_test.tscn -- client
##
## Run the host first and the challenger a few seconds later. The real work
## lives in net_battle_role.gd, which this scene adds to the tree ROOT so it
## survives the scene change into the arena (a node in the current scene would
## be freed by it).

const ROLE := preload("res://tools/net_battle_role.gd")


func _ready() -> void:
	var role := Node.new()
	role.name = "BattleTestRole"
	role.set_script(ROLE)
	# Deferred: the tree root is still setting up this scene while _ready runs.
	get_tree().root.add_child.call_deferred(role)