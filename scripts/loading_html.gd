extends CanvasLayer

func _ready():
	# Try to open the HTML loading screen
	var path = "file://" + ProjectSettings.globalize_path("res://loading.html")
	OS.shell_open(ProjectSettings.globalize_path("res://loading.html"))
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/home.tscn")
	queue_free()
