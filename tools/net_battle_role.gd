extends Node

## The host and challenger halves of the two-process battle arena test. The
## role node lives on the tree root so it survives the scene change into the
## arena, then drives a full duel and prints HOST_/CLIENT_ lines that the test
## runner reads back.

const TEST_PORT := 27092


func _ready() -> void:
	_watchdog()
	var args := OS.get_cmdline_user_args()
	if args.has("host"):
		_run_host()
	else:
		_run_client()


## A test that stalls must fail loudly and exit, never sit in the background.
func _watchdog() -> void:
	await _sleep(140.0)
	print("ROLE_WATCHDOG the test did not finish in time")
	get_tree().quit(1)


# ==============================================================================
#  HOST
# ==============================================================================


func _run_host() -> void:
	var network: Node = get_node_or_null("/root/Network")
	network.set("local_name", "ArenaHost")
	network.set("local_character", "Jamal")
	if not bool(network.call("host", TEST_PORT, 1)):
		print("HOST_FAIL could not open the room")
		get_tree().quit(1)
		return
	network.call("start_battle")
	get_tree().set_meta("online", true)
	get_tree().change_scene_to_file.call_deferred("res://scenes/battle_arena.tscn")
	var arena := await _wait_for_arena(10.0)
	if arena == null:
		print("HOST_FAIL the arena did not load")
		get_tree().quit(1)
		return
	arena.round_countdown = 3.0
	arena.round_freeze = 1.0
	arena.spawn_protection = 0.3
	if arena.phase == BattleArena.Phase.COUNTDOWN and arena.countdown > 5.0:
		arena._begin_round()
	print("HOST arena loaded; waiting for the challenger…")

	await _wait_phase(arena, BattleArena.Phase.COUNTDOWN, 30.0)
	print("HOST_CHECK countdown_started=", arena.phase == BattleArena.Phase.COUNTDOWN,
			" cages_sealed=", not arena.cage_doors[1]["shape"].disabled and not arena.cage_doors[2]["shape"].disabled)

	await _wait_phase(arena, BattleArena.Phase.FIGHT, 12.0)
	print("HOST_CHECK round1_fight=", arena.phase == BattleArena.Phase.FIGHT,
			" doors_open=", arena.cage_doors[1]["shape"].disabled and arena.cage_doors[2]["shape"].disabled)

	# Meet the challenger at the sigil so both sides can trade real hits.
	_move_local(arena, Vector3(0.9, 0.6, 0.0))
	await _sleep(1.2)
	print("HOST_CHECK challenger_damage_received=", float(arena.hp[1]) < BattleArena.MAX_DUEL_HEALTH,
			" hp1=", arena.hp[1])

	await _host_win_round(arena)
	await _wait_phase(arena, BattleArena.Phase.ROUND_END, 4.0)
	print("HOST_CHECK round1_host_wins=", int(arena.wins[1]) == 1 and int(arena.wins[2]) == 0, " wins=", arena.wins)

	# Round two: the challenger hits the host, who then falls — 1-1. The host
	# waits for that hit before it goes down, so the claim is really exercised.
	await _wait_phase(arena, BattleArena.Phase.FIGHT, 12.0)
	_move_local(arena, Vector3(0.9, 0.6, 0.0))
	var hit_waited := 0.0
	while hit_waited < 4.0 and float(arena.hp[1]) >= BattleArena.MAX_DUEL_HEALTH:
		hit_waited += 0.1
		await _sleep(0.1)
	print("HOST_CHECK round2_challenger_hit=", float(arena.hp[1]) < BattleArena.MAX_DUEL_HEALTH, " hp1=", arena.hp[1])
	arena._host_on_death(1)
	await _wait_phase(arena, BattleArena.Phase.ROUND_END, 4.0)
	print("HOST_CHECK 1_1=", int(arena.wins[1]) == 1 and int(arena.wins[2]) == 1, " wins=", arena.wins)

	# Round three decides the match, and the host takes it 2-1.
	await _wait_phase(arena, BattleArena.Phase.FIGHT, 12.0)
	_move_local(arena, Vector3(0.9, 0.6, 0.0))
	await _sleep(1.0)
	await _host_win_round(arena)
	await _wait_phase(arena, BattleArena.Phase.MATCH_OVER, 8.0)
	print("HOST_CHECK match_over=", arena.phase == BattleArena.Phase.MATCH_OVER,
			" wins=", arena.wins, " victory_screen=", arena.hud.victory_overlay.visible)

	# The challenger votes from its own victory screen; the host agrees and a
	# fresh match begins at round one, 0-0.
	arena._host_vote(1)
	var restarted := await _wait_phase(arena, BattleArena.Phase.COUNTDOWN, 15.0)
	print("HOST_CHECK rematch=", restarted, " wins=", arena.wins, " round=", arena.round_number)
	print("HOST_ALL_DONE")

	# Leave the room: the remaining duelist should see its disconnect screen.
	await _sleep(5.0)
	arena._return_to_menu()
	await _sleep(1.0)
	get_tree().quit(0)


func _host_win_round(arena: BattleArena) -> void:
	var guard := 0
	while arena.phase == BattleArena.Phase.FIGHT and float(arena.hp[2]) > 0.0 and guard < 40:
		guard += 1
		arena._grace_left = 0.0
		var point: Vector3 = arena._last_pos.get(2, Vector3.ZERO)
		arena._last_pos[1] = point + Vector3(0.9, 0.0, 0.0)
		arena._host_try_hit(1, point)
		await _sleep(0.12)


func _move_local(arena: BattleArena, where: Vector3) -> void:
	if arena.player == null or not is_instance_valid(arena.player):
		return
	arena.player.global_position = where
	arena.player.velocity = Vector3.ZERO


# ==============================================================================
#  CHALLENGER
# ==============================================================================


func _run_client() -> void:
	var network: Node = get_node_or_null("/root/Network")
	network.set("local_name", "ArenaChallenger")
	network.set("local_character", "Nattie")
	print("CLIENT_JOIN ok=", bool(network.call("join", "127.0.0.1", TEST_PORT)))
	var arena := await _wait_for_arena(15.0)
	if arena == null:
		print("CLIENT_FAIL the host's arena did not load")
		get_tree().quit(1)
		return
	print("CLIENT arena loaded in slot ", arena.local_slot)

	# The duel starts a moment after this arena announced itself, so wait for the
	# countdown to begin before judging it.
	var ticks: Array[int] = []
	var sealed := true
	var waited := 0.0
	while arena.phase != BattleArena.Phase.COUNTDOWN and waited < 8.0:
		waited += 0.05
		await _sleep(0.05)
	while arena.phase == BattleArena.Phase.COUNTDOWN and waited < 16.0:
		# Only the host owns the countdown number; the client's copy arrives
		# through the HUD and the state broadcasts. Judge the seal only while
		# the countdown HUD is up: the doors-open packet hides it in the same
		# breath, one frame before the phase packet flips to FIGHT.
		if arena.hud.countdown_label.visible:
			# Sealed means the door collider is on: disabled == false.
			if arena.cage_doors[1]["shape"].disabled or arena.cage_doors[2]["shape"].disabled:
				sealed = false
			var shown := int(arena.hud.countdown_label.text)
			if ticks.is_empty() or ticks[ticks.size() - 1] != shown:
				ticks.append(shown)
		waited += 0.05
		await _sleep(0.05)
	print("CLIENT_CHECK cages_sealed=", sealed, " countdown_ticks=", ticks,
			" countdown_on_screen=", arena.hud.countdown_label.visible,
			" banner=", arena.hud.banner_label.text)

	await _wait_phase(arena, BattleArena.Phase.FIGHT, 8.0)
	print("CLIENT_CHECK fight_started=", arena.phase == BattleArena.Phase.FIGHT,
			" doors_open=", arena.cage_doors[1]["shape"].disabled and arena.cage_doors[2]["shape"].disabled,
			" unlocked=", not bool(arena.player.get("controls_locked")),
			" announced=", arena.hud.announce_label.text)

	# Round one: the challenger lands a hit the host validates.
	_move_local(arena, Vector3(0.0, 0.6, 0.0))
	await _sleep(1.0)
	var before := float(arena.hp[1])
	arena.request_hit(arena.player.global_position)
	await _sleep(0.6)
	print("CLIENT_CHECK hit_landed=", float(arena.hp[1]) < before,
			" hp1 ", before, " -> ", arena.hp[1], " bar=", arena.hud.p1_health.value)

	# The host takes the round: the challenger is knocked out, 1-0 to the host.
	await _wait_phase(arena, BattleArena.Phase.ROUND_END, 15.0)
	print("CLIENT_CHECK round1_host_wins=", int(arena.wins[1]) == 1 and int(arena.wins[2]) == 0, " wins=", arena.wins)
	await _wait_phase(arena, BattleArena.Phase.COUNTDOWN, 8.0)
	print("CLIENT_CHECK round2_reset=", arena.round_number == 2,
			" back_in_cage=", arena.player.global_position.distance_to(BattleArena.CAGE_SPAWNS[2]) < 2.5,
			" hp_restored=", float(arena.hp[2]) == BattleArena.MAX_DUEL_HEALTH)

	# Round two: the challenger hits the host, who then falls — 1-1.
	await _wait_phase(arena, BattleArena.Phase.FIGHT, 10.0)
	_move_local(arena, Vector3(0.0, 0.6, 0.0))
	await _sleep(1.0)
	var before2 := float(arena.hp[1])
	arena.request_hit(arena.player.global_position)
	await _sleep(0.6)
	print("CLIENT_CHECK second_hit_landed=", float(arena.hp[1]) < before2, " hp1=", arena.hp[1])
	await _wait_phase(arena, BattleArena.Phase.ROUND_END, 12.0)
	print("CLIENT_CHECK 1_1=", int(arena.wins[1]) == 1 and int(arena.wins[2]) == 1, " wins=", arena.wins)

	# Round three: the host wins the match 2-1 and the victory screen names it.
	await _wait_phase(arena, BattleArena.Phase.MATCH_OVER, 25.0)
	print("CLIENT_CHECK match_over=", arena.phase == BattleArena.Phase.MATCH_OVER,
			" victory_screen=", arena.hud.victory_overlay.visible,
			" heading=", arena.hud.victory_heading.text,
			" score=", arena.hud.victory_score.text)

	# Both duelists ask for another match.
	arena._vote_rematch()
	var restarted := await _wait_phase(arena, BattleArena.Phase.COUNTDOWN, 15.0)
	print("CLIENT_CHECK rematch=", restarted, " wins=", arena.wins, " round=", arena.round_number)

	# The host leaves the room: the challenger is told and returned safely.
	var waited2 := 0.0
	while waited2 < 15.0 and is_instance_valid(arena) and not arena.hud.disconnect_overlay.visible:
		waited2 += 0.1
		await _sleep(0.1)
	print("CLIENT_CHECK disconnect_notice=", is_instance_valid(arena) and arena.hud.disconnect_overlay.visible)
	print("CLIENT_ALL_DONE")
	get_tree().quit(0)


# ==============================================================================
#  SHARED
# ==============================================================================


func _wait_for_arena(limit: float) -> BattleArena:
	var waited := 0.0
	while waited < limit:
		var scene := get_tree().current_scene
		if scene is BattleArena:
			return scene
		waited += 0.1
		await _sleep(0.1)
	return null


func _wait_phase(arena: BattleArena, target: int, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if arena.phase == target:
			return true
		waited += 0.05
		await _sleep(0.05)
	return arena.phase == target


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout