extends Node3D

## The end of the Forgotten Island: the sealed chest, the First Fragment's scene,
## saved progression, and the three things the portal answers to.
##
## It points Progress at a throwaway path first, so a real player's save file is
## never touched, and restores it (and their real value) afterwards.

var _problems: Array = []
var _real_path := ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		_problems.append(message)


func _interact() -> void:
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = "interact"
	release.pressed = false
	Input.parse_input_event(release)


func _ready() -> void:
	# Never touch the player's own save file: point Progress at a throwaway one.
	_real_path = Progress.config_path
	Progress.config_path = "user://progress_check.cfg"
	Progress.clear()

	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	var island: ForgottenIsland = main.get("island")
	var player: CharacterBody3D = main.get("player")
	var warden := get_tree().get_first_node_in_group("island_warden") as IslandWarden
	var chest: IslandChest = island.get_node_or_null("FragmentChest")

	print("chest: %s   closed %s   warden alive %s   fragment held %s" % [
		chest != null, chest != null and not chest.is_open,
		not island.is_warden_defeated(), Progress.fragment_recovered])
	if chest == null:
		print("FINALE PROBLEMS: the chamber has no chest")
		_finish()
		return
	_check(not chest.is_open, "the chest starts open")
	_check(chest.blocking_reason() != "", "the chest has no reason to refuse while the Warden lives")

	# --- 1. Shut while the Warden holds the chamber -------------------------
	player.global_position = chest.global_position + Vector3(0.0, 0.55, 2.0)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	_interact()
	await get_tree().physics_frame
	print("interacting with the sealed chest: open %s   reason: '%s'" % [
		chest.is_open, chest.blocking_reason()])
	_check(not chest.is_open, "the chest opened while the Warden was still alive")

	# --- 2. The portal wants all three --------------------------------------
	island.coins_collected = island.coins_required
	print("all coins but the Warden alive: portal ready %s - '%s'" % [
		island.is_portal_ready(), island.portal_blocked_reason()])
	_check(not island.is_portal_ready(), "the portal opened while the Warden was alive")
	_check(island.portal_blocked_reason().contains("Warden"),
		"the refusal does not say the Warden is the problem")
	island.coins_collected = 0

	# --- 3. The Warden falls, the chest opens -------------------------------
	warden.begin_fight()
	await _kill_warden(warden, player)
	await get_tree().create_timer(0.4).timeout
	print("after the Warden fell: island says defeated %s, chest reason '%s'" % [
		island.is_warden_defeated(), chest.blocking_reason()])
	_check(island.is_warden_defeated(), "the island does not know the Warden is gone")
	_check(chest.blocking_reason() == "", "the chest still refuses after the Warden fell")

	var took := [false]
	chest.fragment_taken.connect(func(): took[0] = true)
	_interact()
	await get_tree().create_timer(1.2).timeout
	print("interacting again: open %s, fragment taken %s, saved %s" % [
		chest.is_open, took[0], Progress.fragment_recovered])
	_check(chest.is_open, "the chest did not open when interacted with")
	# The scene takes a few seconds; wait for the Fragment to actually rise.
	var waited := 0.0
	while waited < 8.0 and not took[0]:
		waited += 0.1
		await get_tree().create_timer(0.1).timeout
	print("after the scene (%.1fs): fragment taken %s, island has it %s, chest shows it %s" % [
		waited, took[0], island.has_fragment(), chest.fragment_out])
	_check(took[0], "the First Fragment's scene never completed")
	_check(island.has_fragment(), "the island does not know the Fragment is recovered")
	_check(chest.fragment_out, "the chest does not show the Fragment")

	# --- 4. Saved progression survives a reload -----------------------------
	var progress_script := load("res://scripts/progress.gd") as GDScript
	var probe: Node = progress_script.new()
	probe.set("config_path", Progress.config_path)
	probe.call("load_progress")
	var remembered: bool = probe.get("fragment_recovered")
	probe.free()
	print("a fresh load of the save file remembers the Fragment: %s" % remembered)
	_check(remembered, "the recovered Fragment was not written to saved progression")

	# --- 5. The portal, with everything in hand -----------------------------
	island.coins_collected = island.coins_required
	print("warden gone, fragment held, %d coins: portal ready %s" % [
		island.coins_collected, island.is_portal_ready()])
	_check(island.is_portal_ready(), "the portal did not open with all three conditions met")
	_check(island.portal_blocked_reason() == "", "the portal still refuses with everything done")
	island.coins_collected = island.coins_required - 1
	print("one coin short: ready %s - '%s'" % [
		island.is_portal_ready(), island.portal_blocked_reason()])
	_check(not island.is_portal_ready(), "the portal opened one coin short")
	_check(island.portal_blocked_reason().contains("coin"), "the refusal does not mention the coins")

	if _problems.is_empty():
		print("\nFINALE OK - chest sealed, Fragment recovered, saved, portal open")
	else:
		print("\nFINALE PROBLEMS (%d):" % _problems.size())
		for problem in _problems:
			print("  - %s" % problem)
	_finish()


## Beat the Warden the way a player has to: slash it while it is open, and when
## its guard is up, destroy the slimes holding it. Capped, so a guard that never
## drops shows up as a failure rather than a hang.
func _kill_warden(warden: IslandWarden, player: Node3D) -> void:
	var blows := 0
	while warden.health > 0 and warden.state_name() != "dead" and blows < 80:
		blows += 1
		if warden.shielded:
			for slime in warden.summons():
				if is_instance_valid(slime):
					slime.take_hit(99, slime.global_position)
			await get_tree().create_timer(0.25).timeout
			continue
		warden.take_hit(1, player.global_position)
		await get_tree().physics_frame


func _finish() -> void:
	# Put the real save back exactly as it was found.
	Progress.config_path = _real_path
	Progress.load_progress()
	if FileAccess.file_exists("user://progress_check.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress_check.cfg"))
	get_tree().quit(0 if _problems.is_empty() else 1)