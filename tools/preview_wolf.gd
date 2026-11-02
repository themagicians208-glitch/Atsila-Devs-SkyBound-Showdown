extends Node3D

## Close-up look at a Level 3 Frost Wolf, from the front, the side and three-quarter
## front, saved to res://preview_shots/. Builds the real level so the wolf is the
## wolf the game spawns, freezes it in place and frames the face.

const SHOT_DIR := "res://preview_shots"

var _main: Node
var _wolf: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup()
	if _wolf == null:
		push_error("WOLF PREVIEW: no Frost Wolf found in Level 3")
		_teardown()
		return
	_wolf.rotation.y = 0.0
	_wolf.process_mode = Node.PROCESS_MODE_DISABLED
	await _shoot("front", Vector3(0.0, 0.6, 3.9))
	await _shoot("three_quarter", Vector3(2.4, 0.85, 3.1))
	await _shoot("side", Vector3(4.1, 0.55, 0.0))
	print("WOLF PREVIEW: 3 screenshots written to %s" % SHOT_DIR)
	_teardown()


func _setup() -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.set("config_path", "user://progress_preview_wolf.cfg")
		prog.call("clear")
		prog.call("recover_fragment")
		prog.call("recover_second_fragment")
	get_tree().set_meta("level_number", 3)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	for frame in 4:
		await get_tree().process_frame
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("variant") == "Frost Wolf":
			_wolf = enemy as Node3D
			break
	var player: Node = _main.get("player")
	if player != null:
		player.set("controls_locked", true)
		player.global_position = Vector3(0.0, 0.5, -24.0)
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.name = "WolfCamera"
	cam.fov = 46.0
	add_child(cam)
	cam.current = true
	_camera = cam
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)


var _camera: Camera3D


func _shoot(tag: String, offset: Vector3) -> void:
	_camera.global_position = _wolf.global_position + offset
	_camera.look_at(_wolf.global_position + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	for frame in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/wolf_%s.png" % [SHOT_DIR, tag]
	var error := image.save_png(path)
	if error != OK:
		push_error("WOLF PREVIEW: could not write %s (error %d)" % [path, error])
	else:
		print("WOLF PREVIEW: wrote ", path)


func _teardown() -> void:
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()