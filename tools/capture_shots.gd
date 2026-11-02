extends Node

## Windowed helper: renders scenes into PNGs in tools/, then quits.
## Run with:  godot --path . tools/capture_shots.tscn -- res://tools/preview_x.tscn [...]
## With no arguments it renders the key-binds clash message and the slash poses.

func _ready() -> void:
	var scenes := OS.get_cmdline_user_args()
	if scenes.is_empty():
		scenes = PackedStringArray([
			"res://tools/preview_anim.tscn",
			"res://tools/preview_swing.tscn",
		])
	for scene in scenes:
		var host: Node = load(str(scene)).instantiate()
		add_child(host)
		await get_tree().create_timer(1.4).timeout
		await _save(str(scene).get_file().get_basename().replace("preview_", ""))
		host.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://tools/shot_%s.png" % name
	image.save_png(path)
	print("saved %s" % path)
