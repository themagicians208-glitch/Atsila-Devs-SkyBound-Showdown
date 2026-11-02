extends Node

## Names the bones of a skinned character and dumps what its animation clips do,
## so the pose code can target real bones.

func _ready() -> void:
	var node: Node3D = load("res://objects/characters/nattie.tscn").instantiate()
	add_child(node)
	await get_tree().process_frame

	var skeleton := _skeleton(node)
	if skeleton == null:
		print("no skeleton")
		get_tree().quit()
		return
	print("bones (%d), with rest positions:" % skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		print("  %2d  %-28s parent=%-3d  head=%s" % [
			i, skeleton.get_bone_name(i), skeleton.get_bone_parent(i),
			rest.origin.snapped(Vector3.ONE * 0.01)])

	for player in _animations(node):
		print("\nanimation player %s: %s" % [player.get_path(), player.get_animation_list()])
		for clip in player.get_animation_list():
			var anim := player.get_animation(clip)
			print("  clip '%s': %.2fs, %d tracks, loop=%s" % [
				clip, anim.length, anim.get_track_count(), anim.loop_mode])
			for t in anim.get_track_count():
				var path := anim.track_get_path(t)
				var keys := anim.track_get_key_count(t)
				var values: Array[String] = []
				for k in mini(keys, 4):
					values.append(str(anim.track_get_key_value(t, k)).pad_decimals(2))
				print("     %-52s %s keys  %s" % [path, keys, ", ".join(values)])


func _animations(node: Node) -> Array[AnimationPlayer]:
	var found: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		found.append(node)
	for child in node.get_children():
		found.append_array(_animations(child))
	return found


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var s := _skeleton(child)
		if s != null:
			return s
	return null
