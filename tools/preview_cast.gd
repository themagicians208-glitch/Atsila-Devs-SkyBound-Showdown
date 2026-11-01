extends Node

## Screenshots each character in level 1 while walking, from the game's own camera.

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	for i in ROSTER.count():
		var id := ROSTER.id_at(i)
		get_tree().set_meta("level_number", 1)
		get_tree().set_meta("p1_character", id)
		get_tree().set_meta("local_coop", false)
		get_tree().set_meta("online", false)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		add_child(main)
		await get_tree().create_timer(1.3).timeout
		# Walk for a moment so the limbs are mid-step, then hold the pose.
		Input.action_press("move_forward")
		await get_tree().create_timer(0.55).timeout
		Input.action_release("move_forward")
		await get_tree().create_timer(0.12).timeout
		await _save("cast_%s" % id.to_lower())
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://tools/shot_%s.png" % name
	image.save_png(path)
	print("saved %s" % path)
