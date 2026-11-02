extends Node

## Plays a whole 1v1 duel through the arena's host logic in one process:
## the matchmaking wait, the sealed countdown, the cage doors opening, validated
## damage, best-of-three rounds (including a replayed double knock-out), the
## victory screen, the mutual rematch vote and a disconnect.
##
## A second, two-process test (tools/net_battle_test.tscn) sends the same flow
## over a real ENet connection to a joining challenger.
##
## Run headless:
##   godot --headless res://tools/check_battle.tscn

const ARENA := preload("res://scenes/battle_arena.tscn")
const TEST_PORT := 27091

var _problems: Array[String] = []
# Cached: the final "return to menu" swaps the scene under this test's feet,
# which detaches it from the tree, so get_tree() cannot be used after that.
var _tree: SceneTree


func _check(condition: bool, message: String) -> void:
	if not condition:
		_problems.append(message)


func _ready() -> void:
	print("--- 1v1 Battle Arena check (match flow) ---")
	_tree = get_tree()
	var network: Node = get_node_or_null("/root/Network")
	if network == null:
		print("PROBLEM: no Network autoload")
		get_tree().quit(1)
		return
	network.set("local_name", "ArenaHost")
	network.set("local_character", "Jamal")
	_check(bool(network.call("host", TEST_PORT, 1)), "could not open the arena room on port %d" % TEST_PORT)
	get_tree().set_meta("online", true)

	var arena: BattleArena = ARENA.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.round_countdown = 2.0
	arena.round_freeze = 0.6
	arena.spawn_protection = 0.5

	# --- Matchmaking: one duelist waits, with an address to share. ---
	_check(arena.phase == BattleArena.Phase.WAITING, "the arena did not wait for an opponent")
	_check(arena.hud.waiting_overlay.visible, "the waiting screen is not shown to a lone duelist")
	_check(arena.hud.waiting_players.text.contains("PLAYER 1"), "the waiting screen does not list player 1")
	_check(arena.hud.waiting_players.text.contains("waiting for a challenger"),
			"the waiting screen does not say it is waiting for a challenger")
	_check(not arena.hud.waiting_address.text.is_empty(), "the waiting screen does not show an address to share")
	_check(arena.player != null, "the local duelist did not spawn")
	_check(arena.player.global_position.distance_to(BattleArena.CAGE_SPAWNS[1]) < 2.0,
			"the local duelist did not spawn in its cage")
	_check(arena.cage_doors[1]["shape"].disabled == false, "the near cage door is not sealed while waiting")

	# --- A challenger connects, but its arena is still loading. ---
	var players := network.get("players") as Dictionary
	var names := network.get("player_names") as Dictionary
	var characters := network.get("player_characters") as Dictionary
	players[777] = true
	names[777] = "Rival"
	characters[777] = "Nattie"
	network.emit_signal("peer_list_changed")
	await get_tree().process_frame
	_check(arena.phase == BattleArena.Phase.WAITING,
			"the duel started before the challenger's arena had loaded")
	_check(arena.hud.waiting_players.text.contains("loading"),
			"the waiting screen does not say the challenger is still loading (%s)" % arena.hud.waiting_players.text)

	# --- The challenger's arena announces itself: the countdown starts. ---
	var ready_peers := network.get("arena_ready_peers") as Dictionary
	ready_peers[777] = true
	network.emit_signal("arena_ready", 777)
	await get_tree().process_frame
	_check(arena.phase == BattleArena.Phase.COUNTDOWN,
			"the countdown did not start when the challenger arrived")
	_check(arena.opponent != null and is_instance_valid(arena.opponent), "the opponent did not appear")
	_check(arena.opponent.global_position.distance_to(BattleArena.CAGE_SPAWNS[2]) < 2.0,
			"the opponent did not spawn in the far cage")
	_check(not arena.hud.waiting_overlay.visible, "the waiting screen is still up after the challenger arrived")
	_check(arena.hud.p2_name_label.text.contains("Rival"),
			"the opponent's name is not on the HUD (got '%s')" % arena.hud.p2_name_label.text)
	_check(arena.cage_doors[1]["shape"].disabled == false and arena.cage_doors[2]["shape"].disabled == false,
			"the cages are not sealed during the countdown")
	_check(bool(arena.player.get("controls_locked")), "the duelist is not held still during the countdown")
	_check(arena.hud.banner_label.text == "GET READY FOR BATTLE!",
			"the countdown banner does not say GET READY FOR BATTLE! (got '%s')" % arena.hud.banner_label.text)
	_check(arena.hud.countdown_label.visible, "the countdown number is not on screen")
	var sealed_hp := float(arena.hp[2])
	arena._host_try_hit(1, arena.opponent.global_position)
	_check(float(arena.hp[2]) == sealed_hp, "damage landed while the cages were still sealed")

	# The countdown ticks through whole seconds, then the doors open together.
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
			"the cage doors did not open when the countdown reached zero")
	_check(not arena.hud.countdown_label.visible, "the countdown number is still on screen after the doors opened")
	_check(arena.hud.announce_label.text == "FIGHT!",
			"the fight announcement is missing (got '%s')" % arena.hud.announce_label.text)
	_check(not bool(arena.player.get("controls_locked")), "the duelist is still held still after the doors opened")

	# --- Host-validated damage. ---
	_check(arena._grace_left > 0.0, "there is no spawn protection at the start of the fight")
	var protected_hp := float(arena.hp[2])
	arena._host_try_hit(1, arena.opponent.global_position)
	_check(float(arena.hp[2]) == protected_hp, "a hit landed inside the spawn protection window")
	arena._grace_left = 0.0
	_hit(arena)
	_check(float(arena.hp[2]) < protected_hp, "a valid hit did not take the opponent's health")
	_check(absf(arena.hud.p2_health.value - float(arena.hp[2])) < 0.01,
			"the opponent's health bar does not follow the damage")
	var landed_hp := float(arena.hp[2])
	arena._host_try_hit(1, Vector3(500, 0, 500))
	_check(float(arena.hp[2]) == landed_hp, "a hit claimed from across the map was accepted")

	# --- Round one, and the best-of-three ladder. ---
	await _win_round(arena)
	await _wait(arena, BattleArena.Phase.ROUND_END, 3.0)
	_check(arena.phase == BattleArena.Phase.ROUND_END, "round one did not end when the opponent fell")
	_check(int(arena.wins[1]) == 1 and int(arena.wins[2]) == 0,
			"the round winner did not score exactly one point (%s)" % str(arena.wins))
	_check(bool(arena.player.get("controls_locked")), "the duelist is not frozen between rounds")
	_check(arena.hud.banner_label.text.contains("TAKES ROUND 1"),
			"the round banner does not name the round (%s)" % arena.hud.banner_label.text)
	_check(arena.hud.score_label.text.contains("1") and arena.hud.pips_label.text.contains("●"),
			"the score display did not update (%s / %s)" % [arena.hud.score_label.text, arena.hud.pips_label.text])

	await _wait(arena, BattleArena.Phase.FIGHT, 8.0)
	_check(arena.round_number == 2, "the next round did not start at round 2 (round %d)" % arena.round_number)
	_check(float(arena.hp[1]) == BattleArena.MAX_DUEL_HEALTH and float(arena.hp[2]) == BattleArena.MAX_DUEL_HEALTH,
			"health was not restored between rounds")
	_check(arena.player.global_position.distance_to(BattleArena.CAGE_SPAWNS[1]) < 2.0,
			"the duelist was not returned to its cage")
	_check(arena.opponent.global_position.distance_to(BattleArena.CAGE_SPAWNS[2]) < 3.5,
			"the opponent was not returned to its cage")
	_check(arena.hud.p1_health.value == BattleArena.MAX_DUEL_HEALTH, "the health bar was not reset for the new round")

	# Round two: the host falls; the challenger levels the match at 1-1.
	arena._host_on_death(1)
	await _wait(arena, BattleArena.Phase.ROUND_END, 2.0)
	_check(int(arena.wins[1]) == 1 and int(arena.wins[2]) == 1, "the score did not reach 1-1 (%s)" % str(arena.wins))
	await _wait(arena, BattleArena.Phase.FIGHT, 8.0)
	_check(arena.round_number == 3, "1-1 did not start the deciding round (round %d)" % arena.round_number)

	# A double knock-out replays the deciding round with no point for anyone.
	arena._host_on_death(1)
	arena._host_on_death(2)
	await _wait(arena, BattleArena.Phase.ROUND_END, 2.0)
	_check(int(arena.wins[1]) == 1 and int(arena.wins[2]) == 1,
			"a double knock-out awarded a point (%s)" % str(arena.wins))
	_check(arena.hud.banner_label.text.contains("DOUBLE KNOCK-OUT"),
			"the draw is not announced (%s)" % arena.hud.banner_label.text)
	await _wait(arena, BattleArena.Phase.FIGHT, 8.0)
	_check(arena.round_number == 3, "the replayed round changed its number (%d)" % arena.round_number)

	# The replayed round decides the match: two round wins take it.
	arena._host_on_death(2)
	await _wait(arena, BattleArena.Phase.MATCH_OVER, 4.0)
	_check(arena.phase == BattleArena.Phase.MATCH_OVER, "the match did not end after two round wins")
	_check(int(arena.wins[1]) == 2, "the match did not end at exactly two wins (%s)" % str(arena.wins))
	_check(arena.hud.victory_overlay.visible, "the victory screen did not appear")
	_check(arena.hud.victory_heading.text.contains("ARENAHOST"),
			"the victory screen does not name the winner (got '%s')" % arena.hud.victory_heading.text)
	_check(arena.hud.victory_score.text.contains("2"),
			"the victory screen does not show the match score (got '%s')" % arena.hud.victory_score.text)
	_check(bool(arena.player.get("controls_locked")), "the duelist is not frozen on the victory screen")
	_check(arena.hud.rematch_button != null and arena.hud.victory_menu_button != null,
			"the victory screen is missing its PLAY AGAIN / RETURN buttons")

	# PLAY AGAIN waits for both duelists to agree.
	arena._host_vote(1)
	await get_tree().process_frame
	_check(arena.phase == BattleArena.Phase.MATCH_OVER, "one vote restarted the match; it must wait for both")
	_check(arena.hud.rematch_status.text.contains("1/2"),
			"the rematch status does not show 1/2 (%s)" % arena.hud.rematch_status.text)
	arena._host_vote(2)
	await get_tree().process_frame
	_check(arena.phase == BattleArena.Phase.COUNTDOWN, "both votes did not start a fresh match")
	_check(int(arena.wins[1]) == 0 and int(arena.wins[2]) == 0 and arena.round_number == 1,
			"the rematch did not reset the score (%s, round %d)" % [str(arena.wins), arena.round_number])
	_check(not arena.hud.victory_overlay.visible, "the victory screen is still up after the rematch started")

	# A disconnect hands the remaining duelist back to the menu safely.
	arena._on_peer_left(777)
	await get_tree().process_frame
	_check(arena.hud.disconnect_overlay.visible, "no disconnect message was shown")
	_check(arena.hud.disconnect_body.text.contains("left the arena"),
			"the disconnect message does not explain what happened (%s)" % arena.hud.disconnect_body.text)
	arena._return_to_menu()
	_check(bool(_tree.get_meta("open_multiplayer_menu", false)),
			"returning did not ask the menu to reopen the multiplayer screen")
	_report()


func _report() -> void:
	if _problems.is_empty():
		print("BATTLE ARENA OK")
		_tree.quit(0)
	else:
		for problem in _problems:
			print("PROBLEM: ", problem)
		print("BATTLE ARENA FAILED (%d problems)" % _problems.size())
		_tree.quit(1)


# --- Helpers -------------------------------------------------------------------


## A swing both duelists could really make: the claimed point, the attacker's
## last synced position and the victim all line up inside the arena's
## validation triangle.
func _hit(arena: BattleArena) -> void:
	var point: Vector3 = arena.opponent.global_position
	arena._last_pos[2] = point
	arena._last_pos[1] = point + Vector3(0.9, 0.0, 0.0)
	arena._host_try_hit(1, point)


func _win_round(arena: BattleArena) -> void:
	var guard := 0
	while arena.phase == BattleArena.Phase.FIGHT and float(arena.hp[2]) > 0.0 and guard < 40:
		guard += 1
		arena._grace_left = 0.0
		_hit(arena)
		await get_tree().create_timer(0.05).timeout


func _wait(arena: BattleArena, target: int, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if arena.phase == target:
			return true
		waited += 0.05
		await get_tree().create_timer(0.05).timeout
	return arena.phase == target