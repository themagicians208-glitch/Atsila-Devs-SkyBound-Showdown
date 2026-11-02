extends Node3D

## Visual check of the local split-screen duel: loads the real arena in its local
## two-player mode and saves a shot of the countdown and one of the fight, in both
## halves of the screen.
##
## Run: open this scene and play it.

const ARENA := preload("res://scenes/battle_arena.tscn")


func _ready() -> void:
	get_tree().set_meta("arena_local_duel", true)
	get_tree().set_meta("local_p1_device", "keyboard")
	get_tree().set_meta("local_p2_device", "keyboard")
	get_tree().set_meta("local_p1_name", "Player One")
	get_tree().set_meta("local_p2_name", "Player Two")
	get_tree().set_meta("p1_character", "Jamal")
	get_tree().set_meta("p2_character", "Nattie")

	var arena: BattleArena = ARENA.instantiate()
	add_child(arena)
	arena.round_freeze = 2.0
	var split := arena.get_node_or_null("SplitScreen")
	# Where each camera actually sits relative to its duelist, and which way the
	# duelists face: the arena puts every camera BEHIND its own duelist.
	var cam_one := arena.get("view").get("camera") as Camera3D
	var cam_two := arena.get("_view_two").get("camera") as Camera3D
	print("preview_duel: p1 at %s rot=%.0f  cam1 at z=%.1f  |  p2 at %s rot=%.0f  cam2 at z=%.1f" % [
			arena.player.global_position, rad_to_deg(arena.player.rotation.y),
			cam_one.global_position.z,
			arena.player_two.global_position, rad_to_deg(arena.player_two.rotation.y),
			cam_two.global_position.z])
	print("preview_duel: local=%s player_two=%s split=%s halves=%d countdown=%d" % [
			arena.local_duel,
			arena.player_two != null,
			split != null,
			split.get_child(0).get_child_count() if split != null and split.get_child_count() > 0 else -1,
			int(ceili(arena.countdown))])

	await get_tree().create_timer(1.8).timeout
	# Once the views have settled behind their duelists, both should be outside
	# the cages and both duelists should be facing the sigil between them.
	var model_one := arena.player.get("model") as Node3D
	var model_two := arena.player_two.get("model") as Node3D
	print("preview_duel: settled cam1 z=%.1f cam2 z=%.1f | facing: p1=%s p2=%s (0,0,+1 = toward the sigil)" % [
			cam_one.global_position.z, cam_two.global_position.z,
			(model_one.global_transform.basis * Vector3(0, 0, 1)).snapped(Vector3.ONE * 0.01),
			(model_two.global_transform.basis * Vector3(0, 0, 1)).snapped(Vector3.ONE * 0.01)])
	await _save("duel_countdown")

	# Wait for the doors, then bring both duelists to the middle so the fight is
	# visible in both halves.
	var waited := 0.0
	while arena.phase != BattleArena.Phase.FIGHT and waited < 12.0:
		waited += 0.05
		await get_tree().create_timer(0.05).timeout
	arena.player.global_position = Vector3(0.0, 0.6, -4.5)
	arena.player.rotation.y = 0.0
	arena.player_two.global_position = Vector3(0.0, 0.6, 4.5)
	arena.player_two.rotation.y = PI
	await get_tree().create_timer(1.0).timeout
	arena.player_two.call("take_hit", 0, arena.player.global_position)
	await get_tree().create_timer(0.5).timeout
	await _save("duel_fight")
	print("preview_duel: phase=%d hp={1: %s, 2: %s}" % [arena.phase, arena.hp[1], arena.hp[2]])


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://tools/shot_%s.png" % shot_name
	image.save_png(path)
	print("preview_duel: saved %s" % path)