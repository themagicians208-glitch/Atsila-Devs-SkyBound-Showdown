extends Node

func _ready() -> void:
	print("--- Running Consecutive Dash Verification ---")
	var problems: Array[String] = []

	var player_scene: PackedScene = load("res://objects/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	add_child(player)
	await get_tree().process_frame

	# Initial stamina should be 100
	if player.stamina != 100.0:
		problems.append("Initial stamina is %f, expected 100.0" % player.stamina)

	# 1st dash
	player._start_dash()
	if not player.is_dashing:
		problems.append("Player failed to start 1st dash")
	if player.stamina > 75.0:
		problems.append("1st dash did not consume stamina (stamina=%f)" % player.stamina)

	# Immediately trigger 2nd dash in a row
	player._start_dash()
	if not player.is_dashing:
		problems.append("Player failed to start 2nd dash in a row")
	if player.stamina > 50.0:
		problems.append("2nd dash did not consume stamina (stamina=%f)" % player.stamina)

	# 3rd dash in a row (stamina now down to 25.0)
	player._start_dash()
	if not player.is_dashing:
		problems.append("Player failed to start 3rd dash in a row")

	# Drain stamina to below 25% (e.g. 20.0)
	player.stamina = 20.0
	player.is_dashing = false
	player.dash_cooldown_left = 0.0

	# Attempt dash below 25% - should be blocked!
	player._start_dash()
	if player.is_dashing:
		problems.append("Player was able to dash while stamina was %f (below 25%%!)" % player.stamina)
	else:
		print("DASH BLOCKED OK: dash correctly refused at %f stamina (< 25%%)" % player.stamina)

	# Set stamina to 26% - should succeed
	player.stamina = 26.0
	player._start_dash()
	if not player.is_dashing:
		problems.append("Player failed to dash at 26% stamina")
	else:
		print("DASH OK: dash succeeded at 26% stamina")

	if problems.is_empty():
		print("\n*** ALL DASH CHECKS PASSED ***\n")
	else:
		print("\n*** DASH PROBLEMS FOUND (%d): ***" % problems.size())
		for prob in problems:
			print("  - " + prob)

	player.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)
