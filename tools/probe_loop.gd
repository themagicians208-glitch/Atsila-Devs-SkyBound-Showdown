extends Node

## Checks that a model's walk clip keeps looping instead of stopping after one pass,
## and that the bone arms are actually rotating while it walks.

func _ready() -> void:
	var character: Node3D = load("res://objects/characters/nattie.tscn").instantiate()
	add_child(character)
	await get_tree().process_frame
	var player: AnimationPlayer = character.find_children("*", "AnimationPlayer", true, false)[0]
	var clip := player.get_animation("walk")
	print("clip length %.2fs  loop_mode %d (0 = none, 1 = linear)" % [clip.length, clip.loop_mode])
	player.play("walk")
	for step in 5:
		await get_tree().create_timer(0.6).timeout
		print("   t=%.1fs  playing %s  position %.2f" % [
			(step + 1) * 0.6, player.is_playing(), player.current_animation_position])

	# Bone arms respond to the walk channel.
	var skeleton: Skeleton3D = character.find_children("*", "Skeleton3D", true, false)[0]
	var left := skeleton.find_bone("arm.L_08")
	for amount in [0.0, 0.5, -0.5]:
		character.call("set_pose", 0.0, amount, 0.0, 0.0, 0.0, 0.0)
		await get_tree().process_frame
		var euler := skeleton.get_bone_pose_rotation(left).get_euler()
		print("   arm_swing %+.2f -> bone rotation (%.2f, %.2f, %.2f) degrees (%.1f, %.1f, %.1f)" % [
			amount, euler.x, euler.y, euler.z, rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)])
	get_tree().quit()
