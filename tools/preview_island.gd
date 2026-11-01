extends Node3D

## Wide look at the Forgotten Island: loads level 1, then parks a free camera so the
## whole island can be judged at once.
##
## Run: godot --path . tools/capture_shots.tscn -- res://tools/preview_island.tscn [height]

const CAMERA_HEIGHT := 46.0
const CAMERA_SIDE := 78.0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	## Args come through after "--" along with the scene path, so only the numeric
## ones are read: [height] [target z] [camera side x] [look-at y].
	var numbers: Array[float] = []
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_float():
			numbers.append(arg.to_float())
	var height := numbers[0] if numbers.size() > 0 else CAMERA_HEIGHT
	var target_z := numbers[1] if numbers.size() > 1 else 92.0
	var side := numbers[2] if numbers.size() > 2 else CAMERA_SIDE
	var look_y := numbers[3] if numbers.size() > 3 else 2.0

	var camera := Camera3D.new()
	camera.fov = 62.0
	# A fifth number switches to a head-on view of the portal, and a sixth grants
	# that many coins so the awake state can be looked at too.
	if numbers.size() > 4 and numbers[4] > 0.5:
		camera.position = Vector3(side * 0.3, height + 2.0, target_z - 9.0)
		camera.look_at_from_position(camera.position, Vector3(0.0, look_y, target_z), Vector3.UP)
	else:
		camera.position = Vector3(side, height, target_z)
		camera.look_at_from_position(camera.position, Vector3(0.0, look_y, target_z), Vector3.UP)
	add_child(camera)
	camera.current = true
	await get_tree().process_frame
	var player: Node3D = main.get("player")
	if numbers.size() > 5:
		var island: ForgottenIsland = main.get("island")
		if island != null:
			island.notify_coins(int(numbers[5]))
			await get_tree().create_timer(1.6).timeout
	print("preview_island: player at %s, coins %d" % [player.global_position, get_tree().get_nodes_in_group("collectible_coins").size()])
	print("preview_island: camera at %s" % camera.global_position)