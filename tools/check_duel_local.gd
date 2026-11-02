extends Node

## Local split-screen duel: two duelists on one machine and no network at all.
## Checks the setup (both cages, both duelists, their own devices and cameras),
## the countdown, the doors, real swings landing on the other duelist, the round
## ladder, the victory screen naming both players, and a one-press rematch.
##
## Run headless:
##   godot --headless res://tools/check_duel_local.tscn

const ARENA := preload("res://scenes/battle_arena.tscn")

var _problems: Array[String] = []
# Cached: nothing here changes the scene, but the arena's own return-to-menu
# would; keep the tree pointer safe either way.
var _tree: SceneTree


func _check(condition: bool, message: String) -> void:
	if not condition:
		_problems.append(message)


func _ready() -> void:
	print("--- Local split-screen duel check ---")
	_tree = get_tree()
	_tree.set_meta("arena_local_duel", true)
	_tree.set_meta("local_p1_device", "keyboard")
	_tree.set_meta("local_p2_device", "keyboard")
	_tree.set_meta("local_p1_name", "Duelist One")
	_tree.set_meta("local_p2_name", "Duelist Two")
	_tree.set_meta("p1_character", "Jamal")
	_tree.set_meta("p2_character", "Nattie")

	var arena: BattleArena = ARENA.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame

	# The countdown the player actually meets: 8 seconds, running by itself.
	_check(is_equal_approx(arena.round_countdown, 8.0),
			"the pre-fight countdown is not 8 seconds (%.1f)" % arena.round_countdown)
	_check(int(ceili(arena.countdown)) == 8,
			"the first countdown did not start at 8 (%d)" % int(ceili(arena.countdown)))

	arena.round_countdown = 2.0
	arena.round_freeze = 0.6
	arena.spawn_protection = 0.5
	if arena.phase == BattleArena.Phase.COUNTDOWN and arena.countdown > 5.0:
		arena._begin_round()

	# --- Both duelists, in their own cage, with their own half of the screen. ---
	_check(arena.local_duel, "the arena did not switch to the local duel")
	_check(arena.player != null and arena.player_two != null and is_instance_valid(arena.player_two),
			"player two did not appear")
	if arena.player_two == null:
		_report()
		return
	_check(arena.player.global_position.distance_to(BattleArena.CAGE_SPAWNS[1]) < 2.0,
			"player 1 is not in cage one")
	_check(arena.player_two.global_position.distance_to(BattleArena.CAGE_SPAWNS[2]) < 2.0,
			"player 2 is not in cage two")
	_check(str(arena.player.get("action_attack")) == "p1_attack",
			"player 1 does not have its own attack action (%s)" % str(arena.player.get("action_attack")))
	_check(str(arena.player_two.get("action_attack")) == "p2_attack",
			"player 2 does not have its own attack action (%s)" % str(arena.player_two.get("action_attack")))
	_check(InputMap.has_action("p2_attack") and InputMap.has_action("p2_jump") and InputMap.has_action("p2_magical_shield"),
			"player 2's actions were never defined")
	_check(int(arena.player.get("player_index")) == 0 and int(arena.player_two.get("player_index")) == 1,
			"the two duelists do not have different player colours")
	_check(arena.player_two.get("view") != null, "player 2 has no camera following it")
	var split := arena.get_node_or_null("SplitScreen")
	_check(split != null, "the split-screen layer was not built")
	if split != null:
		var columns := split.get_child(0) if split.get_child_count() > 0 else null
		_check(columns != null and columns.get_child_count() == 2,
				"the screen does not have two halves")
	_check(arena.hud.p2_name_label.text.contains("Duelist Two"),
			"player 2's name is not on the HUD (%s)" % arena.hud.p2_name_label.text)
	_check(arena.hud.hint_label.text.contains("P1") and arena.hud.hint_label.text.contains("P2"),
			"the hint line does not show both players' controls (%s)" % arena.hud.hint_label.text)

	# --- The duel starts by itself: nobody has to connect. ---
	_check(arena.phase == BattleArena.Phase.COUNTDOWN, "the duel did not start by itself")
	_check(bool(arena.player.get("controls_locked")) and bool(arena.player_two.get("controls_locked")),
			"a duelist is not held still during the countdown")
	_check(arena.cage_doors[1]["shape"].disabled == false and arena.cage_doors[2]["shape"].disabled == false,
			"the cages are not sealed during the countdown")
	_check(arena.hud.banner_label.text == "GET READY FOR BATTLE!",
			"the countdown banner is missing (%s)" % arena.hud.banner_label.text)

	var ticks: Array[int] = []
	var guard := 0
	while arena.phase == BattleArena.Phase.COUNTDOWN and guard < 400:
		guard += 1
		var seconds := int(ceili(arena.countdown))
		if ticks.is_empty() or ticks[ticks.size() - 1] != seconds:
			ticks.append(seconds)
		await get_tree().physics_frame
	_check(ticks.has(2) and ticks.has(1), "the countdown did not tick through the seconds (%s)" % str(ticks))
	_check(arena.phase == BattleArena.Phase.FIGHT, "the countdown did not open the arena")
	_check(arena.cage_doors[1]["shape"].disabled and arena.cage_doors[2]["shape"].disabled,
			"the cage doors did not open at zero")
	_check(not bool(arena.player.get("controls_locked")) and not bool(arena.player_two.get("controls_locked")),
			"a duelist is still held still after the doors opened")

	# --- Real swings, both ways, through the whole chain: input -> swing ->
	# groups -> take_hit claim -> local validation -> the other duelist's body. ---
	await _square_up(arena)
	_check(arena._grace_left > 0.0, "there is no spawn protection at the start of the fight")
	arena._grace_left = 0.0
	var hp_two := float(arena.hp[2])
	await _swing_with("p1_attack")
	_check(float(arena.hp[2]) < hp_two,
			"player 1's real swing did not reach player 2 (%s -> %s)" % [hp_two, arena.hp[2]])
	_check(float(arena.player_two.get("health")) < float(arena.player_two.get("max_health")),
			"player 2's body did not lose health")
	_check(arena.hud.p2_health.value < BattleArena.MAX_DUEL_HEALTH,
			"player 2's health bar did not follow")
	var hp_one := float(arena.hp[1])
	await _square_up(arena)
	arena._grace_left = 0.0
	await _swing_with("p2_attack")
	_check(float(arena.hp[1]) < hp_one,
			"player 2's real swing did not reach player 1 (%s -> %s)" % [hp_one, arena.hp[1]])
	_check(float(arena.player.get("health")) < float(arena.player.get("max_health")),
			"player 1's body did not lose health")

	# --- The round ladder, best of three. ---
	arena._host_on_death(2)
	await _wait(arena, BattleArena.Phase.ROUND_END, 3.0)
	_check(arena.phase == BattleArena.Phase.ROUND_END, "round one did not end")
	_check(int(arena.wins[1]) == 1 and int(arena.wins[2]) == 0, "the round was not scored (%s)" % str(arena.wins))
	await _wait(arena, BattleArena.Phase.COUNTDOWN, 4.0)
	_check(arena.round_number == 2, "the next round did not start (round %d)" % arena.round_number)
	_check(arena.player.global_position.distance_to(BattleArena.CAGE_SPAWNS[1]) < 2.0
			and arena.player_two.global_position.distance_to(BattleArena.CAGE_SPAWNS[2]) < 2.0,
			"the duelists were not returned to their cages")
	_check(float(arena.hp[1]) == BattleArena.MAX_DUEL_HEALTH and float(arena.hp[2]) == BattleArena.MAX_DUEL_HEALTH,
			"health was not restored between rounds")
	_check(bool(arena.player_two.get("controls_locked")), "player 2 is not held still between rounds")
	await _wait(arena, BattleArena.Phase.FIGHT, 6.0)

	arena._host_on_death(1)
	await _wait(arena, BattleArena.Phase.ROUND_END, 3.0)
	_check(int(arena.wins[1]) == 1 and int(arena.wins[2]) == 1, "the score did not reach 1-1 (%s)" % str(arena.wins))
	await _wait(arena, BattleArena.Phase.FIGHT, 8.0)
	_check(arena.round_number == 3, "1-1 did not start the deciding round (round %d)" % arena.round_number)

	arena._host_on_death(1)
	await _wait(arena, BattleArena.Phase.MATCH_OVER, 4.0)
	_check(arena.phase == BattleArena.Phase.MATCH_OVER, "the match did not end after two round wins")
	_check(int(arena.wins[2]) == 2, "the match did not end at exactly two wins (%s)" % str(arena.wins))
	_check(arena.hud.victory_overlay.visible, "the victory screen did not appear")
	_check(arena.hud.victory_heading.text.contains("DUELIST TWO"),
			"the victory screen does not name player 2 (%s)" % arena.hud.victory_heading.text)
	_check(arena.hud.p1_name_label.text.contains("Duelist One"),
			"player 1's name is not on the HUD (%s)" % arena.hud.p1_name_label.text)
	_check(arena.hud.rematch_status.text.contains("restarts"),
			"a local duel should restart from one press (%s)" % arena.hud.rematch_status.text)

	# --- One press is enough to start a fresh match on a shared screen. ---
	arena._vote_rematch()
	await get_tree().process_frame
	_check(arena.phase == BattleArena.Phase.COUNTDOWN, "the rematch did not start from one press")
	_check(int(arena.wins[1]) == 0 and int(arena.wins[2]) == 0 and arena.round_number == 1,
			"the rematch did not reset the score (%s, round %d)" % [str(arena.wins), arena.round_number])
	_check(arena.player.global_position.distance_to(BattleArena.CAGE_SPAWNS[1]) < 2.0
			and arena.player_two.global_position.distance_to(BattleArena.CAGE_SPAWNS[2]) < 2.0,
			"the duelists were not put back in their cages for the rematch")

	_tree.set_meta("arena_local_duel", false)
	_report()


func _report() -> void:
	if _problems.is_empty():
		print("LOCAL DUEL OK")
		_tree.quit(0)
	else:
		for problem in _problems:
			print("PROBLEM: ", problem)
		print("LOCAL DUEL FAILED (%d problems)" % _problems.size())
		_tree.quit(1)


# --- Helpers -------------------------------------------------------------------


## Both duelists squared up in the middle, facing each other, like a real fight.
func _square_up(arena: BattleArena) -> void:
	arena.player.global_position = Vector3(0.0, 0.6, -1.2)
	arena.player.rotation.y = 0.0
	arena.player_two.global_position = Vector3(0.0, 0.6, 1.2)
	arena.player_two.rotation.y = PI
	await get_tree().physics_frame
	await get_tree().physics_frame


## Press one duelist's own attack action for a couple of frames and let the
## swing play out through the normal combat path.
func _swing_with(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().create_timer(0.2).timeout


func _wait(arena: BattleArena, target: int, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if arena.phase == target:
			return true
		waited += 0.05
		await get_tree().create_timer(0.05).timeout
	return arena.phase == target