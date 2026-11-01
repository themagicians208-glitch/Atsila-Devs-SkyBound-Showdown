extends Node

## Boots straight into a level so a person (or a dev tool) can play it without
## clicking through the home menu, and reports where the player, the camera, the
## checkpoints and the gates are as they go. That is how a live run says "that
## walk went the wrong way", "that wall is not solid" or "that checkpoint never
## fired" without anyone having to guess from a screenshot.
##
## Level number from the command line: `tools/play_level.tscn -- 3` (default 1).
## A development scene, not part of the game.

var _player: Node3D = null
var _view: Node3D = null
var _camera: Camera3D = null
var _main: Node = null
var _island: Node = null
var _clock := 0.0
var _was_dead := false


func _ready() -> void:
	var level := 1
	for arg in OS.get_cmdline_user_args():
		if str(arg).is_valid_int():
			level = int(arg)
			break
	get_tree().set_meta("level_number", level)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	print("[play_level] starting level %d" % level)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(0.6).timeout
	_player = _main.get("player") as Node3D
	_view = _main.get_node_or_null("View") as Node3D
	if _view != null:
		_camera = _view.get_node_or_null("Camera") as Camera3D
	_island = _main.get("island") as Node


func _process(delta: float) -> void:
	if _player == null or _main == null:
		return
	_clock += delta
	if _clock < 0.6:
		return
	_clock = 0.0
	var spot := _player.global_position
	var dead := bool(_player.get("is_dead"))
	var camera_spot := _camera.global_position if _camera != null else Vector3.ZERO
	print("  t %.1fs  player (%.2f, %.2f, %.2f)  speed %.1f  cam %.1f away  dead %s  checkpoint %s" % [
		Time.get_ticks_msec() / 1000.0, spot.x, spot.y, spot.z,
		Vector2(_player.velocity.x, _player.velocity.z).length(),
		camera_spot.distance_to(spot), dead, _main.get("active_checkpoint")])
	_report_gate()
	if Vector2(_player.velocity.x, _player.velocity.z).length() < 0.1:
		_report_blocker()
	if dead and not _was_dead:
		print("  -> DIED at (%.2f, %.2f, %.2f)" % [spot.x, spot.y, spot.z])
	_was_dead = dead


## What the level's gates are doing right now.
func _report_gate() -> void:
	if _island == null:
		return
	for gate_name in ["AncientGate", "RuinsGate", "ChamberGate"]:
		var gate := _island.get_node_or_null(gate_name) as Node3D
		if gate == null:
			continue
		var disabled := []
		for shape in gate.find_children("*", "CollisionShape3D", true, false):
			disabled.append("%s:%s" % [(shape as CollisionShape3D).name, (shape as CollisionShape3D).disabled])
		print("     %s opened %s, shapes %s" % [gate_name, gate.get("opened"), disabled])


## What is directly around the player, so a live run can name what stopped them.
func _report_blocker() -> void:
	if _player == null:
		return
	var space := get_viewport().world_3d.direct_space_state
	var from := _player.global_position + Vector3(0.0, 0.6, 0.0)
	for direction in [Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * 4.0)
		query.collide_with_areas = false
		query.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(query)
		var way := "north" if direction.z > 0.0 else "south"
		if hit.is_empty():
			print("     %s of the player: clear for 4 units" % way)
		else:
			var what := hit["collider"] as Node3D
			print("     %s of the player: %s (a %s) at %s, %.2f away" % [
				way, what.name, what.get_class(), what.global_position.round(),
				from.distance_to(hit["position"])])
