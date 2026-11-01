extends Node

## Drives the fighting: spawns a level with a sentry in it (level 2 - level 1 is
## the Forgotten Island, which lays out its own enemies), slashes the sentry until
## it dies, pogos off it, and checks that the character's swing pose comes alive
## during a slash. There is no health system any more - being touched is fatal.

var player: CharacterBody3D
var hud: Control


func _ready() -> void:
	get_tree().set_meta("level_number", 2)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	player = main.get_node("Player")
	hud = main.get_node("HUD")
	var enemies := get_tree().get_nodes_in_group("enemies")
	print("level 2: %d enemy, %d health objects on the player" % [
		enemies.size(), player.get("masks") if player.get("masks") != null else 0])
	print("player has 'masks': %s   'soul': %s" % [
		player.get("masks") != null, player.get("soul") != null])
	print("hud inventory button: '%s'" % hud.get("inventory_button").text)

	# --- Slash it until it dies ---------------------------------------------
	var target: Node3D = enemies[0]
	var group := get_tree().get_nodes_in_group("enemies")
	var swings := 0
	while is_instance_valid(target) and swings < 6:
		swings += 1
		player.global_position = target.global_position + Vector3(0, 0, -1.4)
		player.rotation.y = 0.0
		var character: Node3D = player.get_node("Character")
		await _press("attack")
		# Sample the swing pose right after the press, while the slash plays.
		print("swing %d: enemy health %d   character swing %.2f (dir %d)  arm channel %.2f" % [
			swings, int(target.get("health")) if is_instance_valid(target) else -1,
			float(character.get("swing")), int(character.get("swing_dir")),
			_arm_channel(character)])
		await get_tree().create_timer(0.4).timeout
	print("enemy destroyed: %s   enemies left: %d" % [
		not is_instance_valid(target), get_tree().get_nodes_in_group("enemies").size()])
	print("after the swing ends: character swing %.2f (0 = back to walking)" % float(
		player.get_node("Character").get("swing")))

	# --- Pogo ---------------------------------------------------------------
	# Level 2 again: the island (level 1) has no sentry to pogo off. The first
	# level is torn down first, so only one game is running at a time.
	get_tree().set_meta("level_number", 2)
	main.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	Engine.time_scale = 1.0
	var main2: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main2)
	await get_tree().create_timer(0.9).timeout
	player = main2.get_node("Player")
	hud = main2.get_node("HUD")
	var victim: Node3D = get_tree().get_nodes_in_group("enemies")[0]
	player.global_position = victim.global_position + Vector3(0, 1.75, 0)
	player.gravity = 4.0
	# A bare teleport keeps the "on floor" flag from before the move, and the
	# player then refuses to fall. Give them a downward velocity so the next
	# physics step really is mid-air, the way a jump would be.
	player.velocity = Vector3(0.0, -0.2, 0.0)
	Input.action_press("move_back")
	# Two physics frames: the first signal arrives before nodes have run their own
	# _physics_process, so the floor flag only settles on the second.
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("\npogo: on floor %s, victim health %d" % [player.is_on_floor(), int(victim.get("health"))])
	print("   player %s  victim %s  velocity %s  airborne input ok: %s" % [
		player.global_position, victim.global_position, player.velocity, not player.is_on_floor()])
	await _press("attack")
	Input.action_release("move_back")
	await get_tree().physics_frame
	var character2: Node3D = player.get_node("Character")
	print("down-slash: gravity %.2f (negative = bounced)   swung %.2f dir %d" % [
		player.gravity, float(character2.get("swing")), int(character2.get("swing_dir"))])

	# --- Touching an enemy is fatal -----------------------------------------
	print("\ncontact: calling take_damage like an enemy would")
	var died := [false]
	player.died.connect(func(): died[0] = true)
	player.call("take_damage", 1, player.global_position + Vector3(0, 0, 1.5))
	await get_tree().physics_frame
	print("   player dead: %s   death overlay up: %s" % [
		died[0], hud.get("death_overlay").visible])

	# --- Inventory ----------------------------------------------------------
	hud.call("toggle_inventory")
	await get_tree().process_frame
	print("\ninventory open: %s   paused: %s" % [
		hud.get("inventory_overlay").visible, get_tree().paused])
	for child in (hud.get("inventory_rows") as VBoxContainer).get_children():
		if child is HBoxContainer:
			var parts: Array[String] = []
			for part in child.get_children():
				parts.append((part as Label).text)
			print("   %s = %s" % [parts[0], parts[1]])
		else:
			print("   %s" % (child as Label).text)
	get_tree().quit()


## The arm value the shader is actually using.
func _arm_channel(character: Node3D) -> float:
	var materials: Array = character.get("_limb_materials")
	if materials.is_empty():
		return -99.0
	return float((materials[0] as ShaderMaterial).get_shader_parameter("u_arm_swing"))


func _press(action: String) -> void:
	Input.action_press(action)
	for i in 3:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame
