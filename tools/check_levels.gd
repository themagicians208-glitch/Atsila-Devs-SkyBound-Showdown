extends Node

## Levels 2-6 must place exactly one sky sentry, within reach of a jump (about
## 2 units with the double jump). Level 1 is the Forgotten Island, which lays out
## its own enemies per area instead.

func _ready() -> void:
	for level in range(1, 7):
		get_tree().set_meta("level_number", level)
		get_tree().set_meta("local_coop", false)
		get_tree().set_meta("online", false)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		add_child(main)
		await get_tree().create_timer(0.7).timeout
		var enemies := get_tree().get_nodes_in_group("enemies")
		var health := -1
		if enemies.size() > 0:
			health = int((enemies[0] as Node3D).get("health"))
		if level == 1:
			var island: Node = main.get("island")
			print("level 1 (Forgotten Island): %d enemies, %d coins (%d needed for the portal), %d checkpoints" % [
				enemies.size(),
				get_tree().get_nodes_in_group("collectible_coins").size(),
				int(island.get("coins_required")) if island != null else -1,
				int(island.get("checkpoint_points").size()) if island != null else -1])
		else:
			print("level %d: %d enemy (health %d), %d coins, %d shards" % [
				level, enemies.size(), health,
				get_tree().get_nodes_in_group("collectible_coins").size(),
				get_tree().get_nodes_in_group("mask_shards").size()])
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
