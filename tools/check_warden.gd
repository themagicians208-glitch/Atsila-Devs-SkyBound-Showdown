extends Node3D

## Drives the Corrupted Island Warden: it must be dormant until a player walks
## into the arena, wake with the boss bar up, slam out shockwaves that a jumping
## player clears but a grounded one does not survive, escalate through three
## phases, raise the guard its slimes hold, and finally fall - resetting cleanly
## whenever the level respawns someone.

var _problems: Array = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_problems.append(message)


func _ready() -> void:
	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	var island: ForgottenIsland = main.get("island")
	var player: CharacterBody3D = main.get("player")
	var hud: Control = main.get("hud")
	var warden := get_tree().get_first_node_in_group("island_warden") as IslandWarden

	print("warden: %s   in 'enemies': %s   health %d" % [
		warden != null, warden != null and warden.is_in_group("enemies"),
		warden.max_health if warden != null else -1])
	if warden == null:
		print("WARDEN PROBLEMS: the island has no Warden at all")
		get_tree().quit(1)
		return
	_check(warden.is_in_group("enemies"), "the Warden is not in the 'enemies' group, so slashes miss it")
	_check(warden.max_health >= 8, "the Warden is too frail to be a boss (%d health)" % warden.max_health)
	print("starts %s at %s, home %s" % [
		warden.state_name(), warden.global_position.round(), warden.home.round()])
	_check(warden.global_position.distance_to(warden.home) < 1.0,
		"the Warden is not standing where it was placed (%s vs %s)" % [
			warden.global_position.round(), warden.home.round()])

	# --- 1. Dormant until the player arrives --------------------------------
	# Settle the player on the porch first, safely out of the Warden's reach (it
	# wakes within 11 units; this is 12.5). A wave sweeps out to 10.5, so the
	# porch is also the only ground in the chamber a standing player survives -
	# which is where a real jump gets measured.
	var woke := [false]
	warden.woke.connect(func(): woke[0] = true)
	player.global_position = Vector3(0.0, 8.55, 148.0)
	player.velocity = Vector3.ZERO
	for _frame in 40:
		await get_tree().physics_frame
	var floor_height := player.global_position.y
	print("player on the porch: rests at y %.2f, warden %s (%.1f units away)" % [
		floor_height, warden.state_name(), warden.global_position.distance_to(player.global_position)])

	# Measure a real jump: settle, press, and watch how high the player gets.
	Input.action_press("jump")
	var apex := 0.0
	var airborne_frames := 0
	while airborne_frames < 90:
		airborne_frames += 1
		await get_tree().physics_frame
		if airborne_frames == 16:
			Input.action_release("jump")
		apex = maxf(apex, player.global_position.y - floor_height)
	print("a real jump reaches %.2f above the floor" % apex)
	var jumps_clear := apex > IslandWarden.RING_CLEARANCE
	print("   the wave's clearance is %.2f, so a jump leaves %.2f of margin: %s" % [
		IslandWarden.RING_CLEARANCE, apex - IslandWarden.RING_CLEARANCE, jumps_clear])
	_check(jumps_clear, "a jump peaks at %.2f but the wave needs %.2f to clear" % [
		apex, IslandWarden.RING_CLEARANCE])

	# Now walk in, which is what wakes it - and stay airborne from the first frame,
	# because a wave reaches every standing spot in the chamber. Holding the player
	# at jump height for the whole observation is what a player has to do too.
	var hold := apex
	var died_in_hold := [false]
	var death_y := [0.0]
	player.died.connect(func(): death_y[0] = player.global_position.y; died_in_hold[0] = true)
	_hold(player, floor_height + hold, 152.0)
	var waited := 0.0
	var frames := 0
	while frames < 180 and warden.state_name() == "dormant":
		frames += 1
		_hold(player, floor_height + hold, 152.0)
		await get_tree().physics_frame
	waited = float(frames) / 60.0
	print("after the player walked in: state %s, woke %s, boss bar up %s (%.1fs)" % [
		warden.state_name(), woke[0], hud.boss_panel.visible, waited])
	_check(warden.state_name() != "dormant", "it stayed dormant with a player in the arena")
	_check(woke[0], "it never announced that it had woken")
	_check(hud.boss_panel.visible, "the boss bar did not appear when the Warden woke")

	# --- 2. Phase 1: slams and shockwaves -----------------------------------
	# Watch for a slam, held up at jump height the whole time.
	var saw_rings := false
	var lowest := 99.0
	frames = 0
	while frames < 360 and not saw_rings:
		frames += 1
		_hold(player, floor_height + hold, 158.0)
		await get_tree().physics_frame
		lowest = minf(lowest, player.global_position.y - floor_height)
		if warden.rings_out() > 0:
			saw_rings = true
	print("phase %d: rings out %d, phase text %s" % [
		warden.phase, warden.rings_out(), hud.boss_phase_label.text])
	_check(saw_rings, "it never slammed out a shockwave in six seconds")

	# Keep holding for a full sweep underneath, then read the verdict.
	for _frame in 90:
		_hold(player, floor_height + hold, 158.0)
		await get_tree().physics_frame
		lowest = minf(lowest, player.global_position.y - floor_height)
	print("player held %.2f up (lowest %.2f, wave clearance %.2f) while waves passed: dead %s%s" % [
		hold, lowest, IslandWarden.RING_CLEARANCE, player.get("is_dead"),
		" at height %.2f" % (death_y[0] - floor_height) if died_in_hold[0] else ""])
	_check(not bool(player.get("is_dead")), "a wave killed a player who was held up in the air")

	# And it does catch a player standing in it, which is the whole threat.
	player.global_position = Vector3(0.0, floor_height + 0.55, 158.5)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	warden.force_slam()
	waited = 0.0
	while waited < 2.0 and not bool(player.get("is_dead")):
		waited += 0.05
		await get_tree().create_timer(0.05).timeout
	print("grounded player when the next wave crossed: dead %s after %.2fs, death overlay %s" % [
		player.get("is_dead"), waited, hud.death_overlay.visible])
	_check(bool(player.get("is_dead")), "a grounded player survived a shockwave")
	_check(hud.death_overlay.visible, "dying to the Warden did not raise the death overlay")

	# --- 3. A respawn puts the fight back to the start ----------------------
	hud.retry_pressed.emit()
	waited = 0.0
	while waited < 4.0 and warden.state_name() == "dead":
		waited += 0.1
		await get_tree().create_timer(0.1).timeout
	print("after the retry: player dead %s at %s, warden %s with %d health, bar up %s" % [
		player.get("is_dead"), player.global_position.round(), warden.state_name(),
		warden.health, hud.boss_panel.visible])
	_check(not bool(player.get("is_dead")), "the retry did not bring the player back")
	_check(warden.health == warden.max_health, "the Warden did not heal when the player respawned")
	_check(warden.phase == 1 and not warden.shielded, "the Warden did not return to phase 1")
	_check(not hud.boss_panel.visible, "the boss bar stayed up after the reset")

	# Walk back in and wake it again for the phase work.
	player.global_position = Vector3(0.0, 8.55, 152.0)
	player.velocity = Vector3.ZERO
	warden.begin_fight()
	await get_tree().create_timer(1.6).timeout

	# --- 4. Phase 2 brings the charge --------------------------------------
	while warden.health > 8:
		warden.take_hit(1, player.global_position)
	await get_tree().physics_frame
	print("phase %d at %d/%d health, bar %d/%d, phase text %s" % [
		warden.phase, warden.health, warden.max_health,
		hud.boss_bar.value, hud.boss_bar.max_value, hud.boss_phase_label.text])
	_check(warden.phase == 2, "it did not reach phase 2 at two thirds health")
	_check(int(hud.boss_bar.value) == warden.health, "the boss bar is not following its health")

	var saw_charge := false
	waited = 0.0
	while waited < 12.0 and not saw_charge:
		waited += 0.05
		await get_tree().create_timer(0.05).timeout
		if warden.state_name() == "charge":
			saw_charge = true
	print("phase 2 charge seen: %s (after %.1fs), rings out %d" % [saw_charge, waited, warden.rings_out()])
	_check(saw_charge, "phase 2 never charged the player")

	# --- 5. Phase 3 raises the guard ----------------------------------------
	while warden.health > 4:
		warden.take_hit(1, player.global_position)
	await get_tree().physics_frame
	print("phase %d at %d/%d: shielded %s, summons %d" % [
		warden.phase, warden.health, warden.max_health, warden.shielded, warden.summons_alive()])
	_check(warden.phase == 3, "it did not reach phase 3 at a third of its health")
	_check(warden.shielded, "phase 3 did not raise its guard")
	_check(warden.summons_alive() >= 1, "phase 3 did not call any slimes")
	var refused := warden.take_hit(1, player.global_position)
	print("a slash while guarded: landed %s, health still %d" % [refused, warden.health])
	_check(not refused, "a slash got through the guard")
	_check(warden.health == 4, "the guarded Warden still lost health")

	# Break the guard by destroying what holds it.
	var kills := 0
	for slime in warden.summons():
		if is_instance_valid(slime):
			slime.take_hit(99, slime.global_position)
			kills += 1
	# They dissolve for a moment after dying, so give the guard time to notice.
	waited = 0.0
	while waited < 3.0 and warden.summons_alive() > 0:
		waited += 0.1
		await get_tree().create_timer(0.1).timeout
	print("summons destroyed %d, shielded now %s, summons alive %d (after %.1fs)" % [
		kills, warden.shielded, warden.summons_alive(), waited])
	_check(kills >= 1, "no summoned slime could be found to destroy")
	_check(not warden.shielded, "the guard stayed up after both slimes were destroyed")

	# --- 6. It falls --------------------------------------------------------
	var fell := [false]
	warden.defeated.connect(func(): fell[0] = true)
	var blows := 0
	while warden.health > 0 and warden.state_name() != "dead" and blows < 40:
		if not warden.shielded:
			warden.take_hit(1, player.global_position)
		blows += 1
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	print("warden: state %s, defeated %s, island says %s, bar up %s" % [
		warden.state_name(), fell[0], island.is_warden_defeated(), hud.boss_panel.visible])
	_check(fell[0], "the Warden never reported its defeat")
	_check(island.is_warden_defeated(), "the island does not know the Warden is gone")
	_check(not hud.boss_panel.visible, "the boss bar stayed up after the Warden fell")

	if _problems.is_empty():
		print("\nWARDEN OK - wakes, slams, charges, guards with slimes, and falls")
	else:
		print("\nWARDEN PROBLEMS (%d):" % _problems.size())
		for problem in _problems:
			print("  - %s" % problem)
	get_tree().quit(0 if _problems.is_empty() else 1)


## Hold a player at a height and place. Its own motion runs on applied_velocity,
## so that has to be stilled too, or it keeps sinking between the test putting it
## back - which is how a "held" player kept landing in a wave.
func _hold(player: CharacterBody3D, y: float, z: float) -> void:
	player.global_position = Vector3(0.0, y, z)
	player.velocity = Vector3.ZERO
	# Its fall speed is rebuilt inside its own _physics_process - which runs AFTER
	# this, because physics_frame fires first - so gravity has to be zeroed too.
	player.gravity = 0.0
	player.set("applied_velocity", Vector3.ZERO)


func _wait_for_rings(warden: IslandWarden, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		waited += 0.05
		await get_tree().create_timer(0.05).timeout
		if warden.rings_out() > 0:
			return true
	return false