extends Node

func _ready() -> void:
	for path in ["res://objects/characters/nattie.tscn"]:
		var node: Node = load(path).instantiate()
		add_child(node)
		await get_tree().process_frame
		print("%s:" % path.get_file())
		for player in _players(node):
			var names: Array[String] = []
			for clip in player.get_animation_list():
				names.append("%s (%.2fs)" % [clip, player.get_animation(clip).length])
			print("   %s -> %s" % [player.get_path(), ", ".join(names)])
		node.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _players(node: Node) -> Array[AnimationPlayer]:
	var found: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		found.append(node)
	for child in node.get_children():
		found.append_array(_players(child))
	return found
