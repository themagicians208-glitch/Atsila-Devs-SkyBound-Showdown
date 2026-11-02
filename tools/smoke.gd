extends Node

## Boots the menu and a level and reports anything the engine complains about.

func _ready() -> void:
	var home: Node = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await get_tree().create_timer(0.8).timeout
	for screen in ["_show_settings", "_show_key_binds", "_show_controls"]:
		home.call(screen)
		await get_tree().create_timer(0.25).timeout
	print("menu screens built ok")
	home.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for level in [1, 4]:
		get_tree().set_meta("level_number", level)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		add_child(main)
		await get_tree().create_timer(1.0).timeout
		var player: CharacterBody3D = main.get_node("Player")
		# Walk, jump and slash for a moment.
		Input.action_press("move_forward")
		await get_tree().create_timer(0.4).timeout
		Input.action_press("jump")
		await get_tree().create_timer(0.15).timeout
		Input.action_release("jump")
		Input.action_press("attack")
		await get_tree().create_timer(0.2).timeout
		Input.action_release("attack")
		Input.action_press("inventory")
		await get_tree().create_timer(0.1).timeout
		Input.action_release("inventory")
		await get_tree().create_timer(0.2).timeout
		main.get_node("HUD").call("close_inventory")
		await get_tree().create_timer(0.3).timeout
		Input.action_release("move_forward")
		print("level %d ran: player at (%.1f, %.1f, %.1f), coins %d, dead %s" % [
			level, player.global_position.x, player.global_position.y, player.global_position.z,
			int(main.get("coins_collected")), player.get("is_dead")])
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
