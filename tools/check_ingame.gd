extends Node

## Loads the first level with a chosen character, walks it, dashes it and stands
## still, printing how fast the limbs are cycling in each state. Used to check
## that every character animates and that sprinting speeds the arms up.

const CHARACTER := "Jamal"
const ROSTER := preload("res://scripts/roster.gd")

var player: CharacterBody3D
var character: Node3D
var spawn := Vector3.ZERO


func _ready() -> void:
	get_tree().set_meta("p1_character", CHARACTER)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.2).timeout

	player = main.get_node("Player")
	var tree := ""
	for child in player.get_children():
		tree += child.name + " "
	print("player children: %s" % tree)

	character = player.get_node_or_null("Character")
	if character == null:
		# Every character script answers to this, so it identifies one whatever
		# the node happens to be called.
		for child in player.get_children():
			if child.has_method("set_player_index"):
				character = child as Node3D
				break
	if character == null:
		print("no character node found - stopping")
		get_tree().quit()
		return
	spawn = player.global_position
	var script: Script = character.get_script()
	print("character node %s  script %s" % [
		character.name, script.resource_path if script != null else "none"])
	print("spawn %s  on floor %s" % [spawn, player.is_on_floor()])

	await _measure("walk", 1.4, true, false)
	await _measure("dash (sprint)", 1.4, true, true)
	await _measure("idle", 1.0, false, false)

	# Then every character in the roster, swapped in on the spot.
	for i in ROSTER.count():
		var character_id := ROSTER.id_at(i)
		print("\n--- %s ---" % character_id)
		player.set("character_id", character_id)
		player.call("_apply_character_choice")
		await get_tree().process_frame
		character = player.get_node_or_null("Character")
		var swapped: Script = character.get_script()
		print("  script %s   limb rig %s   drop %.2f" % [
			swapped.resource_path if swapped != null else "none",
			character.get("limb_rig"),
			character.get("arm_drop")])
		await _measure("walk", 1.2, true, false)
		await _measure("dash", 1.2, true, true)
	get_tree().quit()


func _measure(label: String, seconds: float, hold_forward: bool, dash: bool) -> void:
	# Hold the player at the spawn point while it "runs", so it cannot leave the
	# platform: physics stays on, so the controller - and any animation clip it
	# drives - behaves exactly as in play.
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.6).timeout
	var grounded := player.is_on_floor()
	if dash:
		# Held down for the whole window, so the just-pressed edge lands in a
		# physics frame and the dash actually covers the measurement.
		Input.action_press("dash")
	if hold_forward:
		Input.action_press("move_forward")

	var phase0: float = character.get("_phase")
	var elapsed := 0.0
	var speed_peak := 0.0
	var lowest := INF
	var highest := -INF
	while elapsed < seconds:
		player.global_position = spawn
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		speed_peak = maxf(speed_peak, Vector2(player.velocity.x, player.velocity.z).length())
		var swing := float(character.get("_leg_swing"))
		lowest = minf(lowest, swing)
		highest = maxf(highest, swing)
	Input.action_release("move_forward")
	Input.action_release("dash")

	var rate := (float(character.get("_phase")) - phase0) / elapsed
	var clip := ""
	var anim := player.get("animation") as AnimationPlayer
	if anim != null:
		clip = "   clip '%s' at x%.2f" % [
			anim.current_animation if not anim.current_animation.is_empty() else "none", anim.speed_scale]
	print("%-13s grounded %-5s speed %5.2f  limb rate %5.1f rad/s   leg swing %+.2f..%+.2f  arm %+.2f  splay %+.2f%s" % [
		label, grounded, speed_peak, rate, lowest, highest,
		character.get("_arm_swing"), character.get("_leg_splay"), clip])