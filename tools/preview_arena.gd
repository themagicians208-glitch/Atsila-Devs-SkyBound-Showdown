extends Node3D

## Visual check of the 1v1 battle arena: loads the real arena scene, then parks
## free cameras over the island and saves PNGs so the whole build can be judged
## at once (floating floor, energy barrier, crystals, cages, sigil, surroundings).
##
## Run: open this scene and play it, or
##   godot --path . res://tools/preview_arena.tscn

const ARENA := preload("res://scenes/battle_arena.tscn")

var _camera: Camera3D


func _ready() -> void:
	var arena: BattleArena = ARENA.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout

	var floor_body := arena.get_node_or_null("ArenaFloor") as Node3D
	var model := arena.player.get("model") as Node3D
	var view := arena.view
	var boom: float = view.get("camera").position.z if view != null and view.get("camera") != null else -1.0
	print("preview_arena: view at %s boom=%.2f clear(10)=%.2f hide_below=%.2f avoid_mask=%d" % [
			view.global_position if view != null else Vector3.ZERO,
			boom,
			view.call("clear_boom", 10.0) if view != null else -1.0,
			view.get("hide_target_when_close") if view != null else -1.0,
			view.get("avoid_mask") if view != null else -1])
	print("preview_arena: duelist layer=%d mask=%d" % [
			arena.player.collision_layer, arena.player.collision_mask])
	# What exactly the boom runs into: the view's own cast, reported by name.
	if view != null:
		var space := arena.get_world_3d().direct_space_state
		var origin: Vector3 = view.global_position + Vector3(0.0, 1.7, 0.0)
		var bz: Vector3 = view.global_transform.basis.z
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + bz * 10.0)
		ray.collision_mask = 1
		var hit := space.intersect_ray(ray)
		print("preview_arena: boom ray from %s along %s hit=%s at %s" % [
				origin, bz.snapped(Vector3.ONE * 0.01),
				str((hit.get("collider") as Node).name) if hit.has("collider") and hit["collider"] != null else "nothing",
				hit.get("position", Vector3.ZERO)])
	print("preview_arena: duelist visible=%s model=%s visible=%s scale=%s at %s meshes=%d" % [
			arena.player.visible,
			model != null,
			model.visible if model != null else false,
			model.scale if model != null else Vector3.ZERO,
			model.global_position if model != null else Vector3.ZERO,
			model.find_children("*", "MeshInstance3D", true, false).size() if model != null else -1])
	# A hard light of our own, so "the island is not rendering" and "the island
	# is not lit" cannot be confused in the shot.
	var lamp := DirectionalLight3D.new()
	lamp.light_energy = 2.2
	lamp.rotation_degrees = Vector3(-55.0, 40.0, 0.0)
	add_child(lamp)
	print("preview_arena: phase=%d waiting=%s" % [arena.phase, arena.hud.waiting_overlay.visible])
	print("preview_arena: sun energy=%s colour=%s visible=%s" % [
			arena.sun.light_energy if arena.sun != null else -1.0,
			arena.sun.light_color if arena.sun != null else Color.BLACK,
			arena.sun.visible if arena.sun != null else false])
	print("preview_arena: floor at %s  radius=%s" % [
			floor_body.position if floor_body != null else Vector3.ZERO,
			BattleArena.ARENA_RADIUS])
	print("preview_arena: local duelist at %s in slot %d" % [arena.player.global_position, arena.local_slot])
	for slot in arena.cage_doors.keys():
		var door: Dictionary = arena.cage_doors[slot]
		var body := door["body"] as Node3D
		var shape := door["shape"] as CollisionShape3D
		print("preview_arena: cage %d door y=%.2f sealed=%s" % [slot, body.position.y, not shape.disabled])
	print("preview_arena: barrier walls=%d  mirror steps=%d  crystals=%d" % [
			arena.get_tree().get_nodes_in_group("mirror_dimension").size(),
			arena.mirror_steps.size(),
			_count_meshes(arena)])

	# The waiting overlay is opaque and would cover the middle of every shot.
	arena.hud.waiting_overlay.visible = false
	arena.hud.visible = false

	# Shot 1: the whole island from outside and above.
	await _shoot("arena_wide", Vector3(30.0, 17.0, 34.0), Vector3(0.0, 3.0, 0.0), 55.0)
	# Shot 2: what a duelist sees at the start: from behind their cage, over the
	# sigil, to the opponent's cage on the far side.
	await _shoot("arena_player", Vector3(0.0, 4.0, -27.0), Vector3(0.0, 1.6, -6.0), 62.0)
	# Shot 2: the two cages and the sigil between them, from the south side.
	await _shoot("arena_cages", Vector3(0.0, 9.0, -30.0), Vector3(0.0, 1.5, 0.0), 60.0)
	# Shot 3: the duelist itself, inside its cage, seen from the side.
	var cage: Vector3 = BattleArena.CAGE_SPAWNS[1]
	await _shoot("arena_duelist", cage + Vector3(6.0, 2.0, 0.5), cage + Vector3(0.0, 0.75, 0.0), 60.0)
	# Shot 4: close to the near cage, next to the duelist, with a bright
	# unshaded control box so a pipeline problem cannot look like a dark arena.
	await _shoot("arena_close", Vector3(7.0, 3.5, -6.0), Vector3(0.0, 1.5, -13.0), 65.0)
	for i in 3:
		var probe := MeshInstance3D.new()
		var probe_mesh := BoxMesh.new()
		probe_mesh.size = Vector3(1.5, 1.5, 1.5)
		probe.mesh = probe_mesh
		var probe_mat := StandardMaterial3D.new()
		probe_mat.albedo_color = Color(1.0, 0.2, 0.3)
		probe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		probe.material_override = probe_mat
		probe.position = [Vector3(0.0, 2.0, 0.0), Vector3(0.0, 2.0, -13.0), Vector3(0.0, 6.0, 13.0)][i]
		add_child(probe)
	await _shoot("arena_probe", Vector3(30.0, 17.0, 34.0), Vector3(0.0, 3.0, 0.0), 55.0)


func _count_meshes(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()


func _shoot(shot_name: String, from: Vector3, target: Vector3, fov: float) -> void:
	_camera = _camera if _camera != null else _make_camera()
	_camera.fov = fov
	_camera.position = from
	_camera.look_at_from_position(from, target, Vector3.UP)
	_camera.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var active := get_viewport().get_camera_3d()
	print("preview_arena: viewport camera at %s (mine=%s)" % [
			active.global_position if active != null else Vector3.ZERO,
			active == _camera])
	var image := get_viewport().get_texture().get_image()
	var path := "res://tools/shot_%s.png" % shot_name
	image.save_png(path)
	print("preview_arena: saved %s (camera at %s)" % [path, _camera.global_position])


## One camera for every shot: freeing the last one leaves the viewport with no
## camera at all, which renders an empty frame.
func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	add_child(camera)
	return camera