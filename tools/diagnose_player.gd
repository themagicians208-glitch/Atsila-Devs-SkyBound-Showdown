extends Node

## Diagnostic: load the level, then report where the player, its character and the
## camera actually are.


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.6).timeout
	_report(main)
	_mark(main)


## Force the character to draw over everything, so we can tell "it is drawn but
## hidden" apart from "it is not drawn at all".
func _mark(main: Node) -> void:
	var player: Node3D = main.get_node_or_null("Player")
	var view: Node3D = main.get_node_or_null("View")
	if player == null or view == null:
		return
	var camera: Camera3D = view.get_node_or_null("Camera")
	if camera == null:
		print("no camera")
		return

	var target := player.global_position + Vector3(0, 0.8, 0)
	var space := (main as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		print("nothing between the camera and the player")
	else:
		var occluder := hit["collider"] as Node
		print("physics hit between camera and player: ", occluder.name, " at ", hit["position"])
		var walk: Node = occluder
		while walk != null:
			if walk is VisualInstance3D:
				print("   ancestor %s (%s) visible=%s" % [
					walk.name, walk.get_class(), (walk as VisualInstance3D).visible])
			walk = walk.get_parent()

	# Draw the character regardless of depth.
	var character: Node = player.get_node("Character")
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = Color(1.0, 0.1, 0.9)
	flat.no_depth_test = true
	for node in character.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = flat
	print("character forced to draw on top (magenta)")


func _report(main: Node) -> void:
	var player: Node3D = main.get_node_or_null("Player")
	if player == null:
		print("NO PLAYER NODE")
		return
	print("player.global_position = ", player.global_position)
	print("player.visible = ", player.visible, "  player.scale = ", player.scale)
	print("player.rotation = ", player.rotation)

	var character: Node3D = player.get_node_or_null("Character")
	if character == null:
		print("NO Character CHILD")
		return
	print("character.visible = ", character.visible)
	print("character.global_position = ", character.global_position)
	print("character global scale = ", character.global_transform.basis.get_scale())

	var combined := AABB()
	var first := true
	for node in character.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var world: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		print("  %-10s visible=%s world_aabb pos=%s size=%s" % [
			mesh_instance.name, mesh_instance.visible, world.position, world.size])
		if first:
			combined = world
			first = false
		else:
			combined = combined.merge(world)
	print("combined world aabb = ", combined)

	var view: Node3D = main.get_node_or_null("View")
	if view == null:
		print("NO View NODE")
		return
	var camera: Camera3D = view.get_node_or_null("Camera")
	if camera == null:
		print("NO Camera")
		return
	print("camera.global_position = ", camera.global_position)
	print("distance camera->player = ", camera.global_position.distance_to(player.global_position))
	var inside := true
	for plane in camera.get_frustum():
		if plane.is_point_over(player.global_position):
			inside = false
	print("player inside camera frustum = ", inside)