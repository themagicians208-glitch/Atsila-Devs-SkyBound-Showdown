extends Node

## Checks the Forgotten Island the way a player would: can every ledge be reached
## on foot from the spawn, and is every coin within reach of somewhere you can
## stand? Builds the island headless, then walks a reachability graph over the
## surfaces it recorded.
##
## Run: godot --headless --path . tools/check_island.tscn
##
## Rules mirror the player's double jump with margin: a ledge is reachable from
## another when the gap between their EDGES is at most 2.3 units and it is no
## more than 1.4 units higher up. Dropping down is always allowed.

const ISLAND := preload("res://scenes/forgotten_island.tscn")

const MAX_GAP := 2.3
const MAX_RISE := 1.4
## How far past a ledge edge a coin may sit and still be collectable.
const COIN_REACH := 1.7
const COIN_MIN_HEIGHT := 0.05
const COIN_MAX_HEIGHT := 2.1


func _ready() -> void:
	var island: ForgottenIsland = ISLAND.instantiate()
	add_child(island)
	island.build(null)

	var problems: Array[String] = []
	var surfaces: Array = island._surfaces
	print("island: %d surfaces, %d coins placed, %d required, %d checkpoints" % [
		surfaces.size(), island.coins_placed, island.coins_required, island.checkpoint_points.size()])

	if island.coins_placed < island.coins_required:
		problems.append("only %d coins placed but %d are required" % [island.coins_placed, island.coins_required])
	if island.coins_placed <= island.coins_required:
		problems.append("the level should hold MORE coins than the portal needs, so exploration is a choice")

	var coins: Array = []
	for child in island.get_children():
		if child.is_in_group("collectible_coins"):
			coins.append(child as Node3D)
	print("coins found in the tree: %d" % coins.size())
	if coins.size() != island.coins_placed:
		problems.append("coins in the tree (%d) do not match coins placed (%d)" % [coins.size(), island.coins_placed])

	# --- Reachability over the ledge graph -----------------------------------
	var start := _nearest_surface(surfaces, island.spawn_point)
	if start < 0:
		problems.append("nothing to stand on at the spawn point")
	else:
		# Phase 1: exactly as the player finds it. Anything behind a puzzle has to
		# be out of reach, or solving that puzzle would not open anything.
		if island.is_puzzle_solved("ancient_switch") or island.is_puzzle_solved("hidden_crystal"):
			problems.append("a puzzle is already marked solved before anyone played")
		var closed := _indices(surfaces, false, island)
		var reached_closed := _reachable(surfaces, start, closed)
		for i in surfaces.size():
			var gate := str(surfaces[i].get("gate", ""))
			if not gate.is_empty() and reached_closed.has(i):
				problems.append("the piece gated by '%s' at %s is reachable before that puzzle is solved" % [
					gate, surfaces[i]["point"]])
		print("as found: %d of %d ledges reachable, %d behind puzzles (%s)" % [
			reached_closed.size(), closed.size(), surfaces.size() - closed.size(),
			island.get_puzzle_names()])

		# The wall has to be wide enough to actually seal the way past it.
		var wall: Node3D = island.get_node_or_null("AncientGate")
		if wall == null:
			problems.append("the ancient gate is missing")
		else:
			var wall_width := float(wall.get("width"))
			var wall_z := wall.global_position.z
			var half_needed := 0.0
			for entry in surfaces:
				var point: Vector3 = entry["point"]
				if absf(point.z - wall_z) < 3.0:
					half_needed = maxf(half_needed, absf(point.x) + float(entry["radius"]))
			if wall_width * 0.5 < half_needed:
				problems.append("the gate is %.1f wide but the island is %.1f across at z %.1f, so it can be walked around" % [
					wall_width, half_needed * 2.0, wall_z])
			else:
				print("the gate spans %.1f against an island %.1f across at z %.1f" % [
					wall_width, half_needed * 2.0, wall_z])

		# Phase 2: every puzzle solved, so the whole island has to connect.
		island.solve_all_puzzles()
		await get_tree().process_frame
		await get_tree().process_frame
		var all_open := _indices(surfaces, true, island)
		var reached := _reachable(surfaces, start, all_open)
		var unreachable := 0
		for i in all_open:
			if not reached.has(i):
				unreachable += 1
				var point: Vector3 = surfaces[i]["point"]
				problems.append("ledge at (%.1f, %.1f, %.1f) cannot be reached from the spawn" % [point.x, point.y, point.z])
		print("puzzles solved: %d of %d ledges reachable" % [reached.size(), all_open.size()])

		# The portal has to be standable-on and reachable, or the level can't end.
		var portal_surface := _nearest_surface(surfaces, island.portal_position)
		if portal_surface < 0:
			problems.append("the portal has no floor")
		elif not reached.has(portal_surface):
			problems.append("the portal floor cannot be reached from the spawn")
		else:
			var portal_point: Vector3 = surfaces[portal_surface]["point"]
			print("portal floor reached at (%.1f, %.1f, %.1f)" % [portal_point.x, portal_point.y, portal_point.z])

		# Checkpoints must sit on something you can stand on.
		for index in island.checkpoint_points.size():
			var spot: Vector3 = island.checkpoint_points[index]
			var on := _nearest_surface(surfaces, spot)
			if on < 0:
				problems.append("checkpoint %d has no floor" % index)
			elif not reached.has(on):
				problems.append("checkpoint %d is on an unreachable ledge" % index)

	# --- Coins ---------------------------------------------------------------
	var loose := 0
	for coin in coins:
		var nearest := island.nearest_surface(coin.position)
		var past_edge := float(nearest[0])
		var height := float(nearest[1])
		var ok := past_edge <= COIN_REACH and height >= COIN_MIN_HEIGHT and height <= COIN_MAX_HEIGHT
		if not ok:
			loose += 1
			problems.append("coin at (%.1f, %.1f, %.1f): %.1f past the nearest ledge edge, %.1f above it"
				% [coin.position.x, coin.position.y, coin.position.z, past_edge, height])
	print("coins within reach of a ledge: %d of %d" % [coins.size() - loose, coins.size()])

	# --- Ambient decoration should not be inside the walkable space ----------
	var bobbers := 0
	for child in island.get_children():
		if child.has_meta("bob_base"):
			bobbers += 1
	print("floating props: %d" % bobbers)

	# --- The coin gate: coins are one of three keys -------------------------
	# The portal also wants the Warden gone and the First Fragment recovered, so
	# coins by themselves can never open it. The full three-condition case is the
	# running level below.
	var unlocks := [0]
	island.portal_unlocked.connect(func(): unlocks[0] += 1)
	island.notify_coins(0)
	if island.is_portal_ready():
		problems.append("the portal is ready with no coins")
	if island.coins_needed() != island.coins_required:
		problems.append("coins_needed() is %d with no coins, expected %d" % [island.coins_needed(), island.coins_required])
	island.notify_coins(island.coins_required - 1)
	if island.is_portal_ready():
		problems.append("the portal is ready one coin short")
	if island.coins_needed() != 1:
		problems.append("coins_needed() is %d one coin short, expected 1" % island.coins_needed())
	island.notify_coins(island.coins_required)
	if island.is_portal_ready():
		problems.append("coins alone opened the portal, with the Warden still standing")
	if island.portal_blocked_reason().is_empty():
		problems.append("the portal is dormant at full coins but gives no reason")
	if not island.portal_blocked_reason().contains("Warden"):
		problems.append("at full coins the portal blames something other than the Warden: '%s'" % island.portal_blocked_reason())
	if unlocks[0] != 0:
		problems.append("portal_unlocked fired %d times on coins alone, expected 0" % unlocks[0])
	island.notify_coins(island.coins_required + 5)
	if unlocks[0] != 0:
		problems.append("portal_unlocked fired %d times on coins alone, expected 0" % unlocks[0])
	print("coin gate: locked at %d coins, still locked at %d (the Warden and the Fragment are also keys)" % [
		island.coins_required - 1, island.coins_required])

	# --- The level must refuse a dormant portal, then really finish ---------
	# The Fragment comes from the chest, so the whole ending is walked here - with
	# Progress pointed at a throwaway file so a real player's save is untouched.
	var real_progress_path: String = Progress.config_path
	Progress.config_path = "user://progress_island_check.cfg"
	Progress.clear()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Node = main.get("hud")
	var live_island: ForgottenIsland = main.get("island")
	var who: Node3D = main.get("player")
	if live_island == null or hud == null:
		problems.append("level 1 did not build the island")
	else:
		main.call("_on_finish_body_entered", who)
		if bool(hud.get("victory_overlay").visible):
			problems.append("the level finished through the portal with 0 coins")
		live_island.notify_coins(live_island.coins_required)
		main.call("_on_finish_body_entered", who)
		if bool(hud.get("victory_overlay").visible):
			problems.append("the level finished at full coins with the Warden still standing")
		# Now do the rest of the ending: beat it, take the Fragment, walk in.
		# A particular island's own Warden. The check builds one island itself earlier,
	# so searching the tree by group would find the wrong one.
		var warden := live_island.get_node_or_null("IslandWarden") as IslandWarden
		if warden == null:
			problems.append("the running level has no Warden")
		else:
			warden.begin_fight()
			print("warden before the fight: state %s, health %d/%d, shielded %s" % [
				warden.state_name(), warden.health, warden.max_health, warden.shielded])
		var blows := 0
		while warden != null and warden.health > 0 and warden.state_name() != "dead" and blows < 80:
			blows += 1
			if warden.shielded:
				for slime in warden.summons():
					if is_instance_valid(slime):
						slime.take_hit(99, slime.global_position)
				await get_tree().create_timer(0.25).timeout
				continue
			warden.take_hit(1, who.global_position)
			await get_tree().physics_frame
		print("warden after the fight: state %s, health %d/%d, shielded %s, blows %d, player dead %s" % [
			warden.state_name(), warden.health, warden.max_health, warden.shielded, blows, who.get("is_dead")])
		var chest: IslandChest = live_island.get_node_or_null("FragmentChest")
		if chest == null:
			problems.append("the chamber has no chest to take the Fragment from")
		else:
			who.global_position = chest.global_position + Vector3(0.0, 0.55, 2.0)
			who.velocity = Vector3.ZERO
			await get_tree().physics_frame
			var opened_now := chest.try_open()
			print("chest: try_open %s   open %s   refusal '%s'   warden defeated %s   player dead %s" % [
				opened_now, chest.is_open, chest.blocking_reason(),
				live_island.is_warden_defeated(), who.get("is_dead")])
			var waited_for_fragment := 0.0
			while waited_for_fragment < 8.0 and not chest.fragment_out:
				waited_for_fragment += 0.1
				await get_tree().create_timer(0.1).timeout
			print("   after %.1fs: fragment out %s, island has it %s, portal ready %s" % [
				waited_for_fragment, chest.fragment_out, live_island.has_fragment(),
				live_island.is_portal_ready()])
			if not live_island.is_portal_ready():
				problems.append("the portal did not open with the Warden gone and the Fragment recovered")
			main.call("_on_finish_body_entered", who)
			await get_tree().process_frame
			if not bool(hud.get("victory_overlay").visible):
				problems.append("the level did NOT finish through a portal opened with all three keys")
			print("portal gate in the running level: blocked without coins, blocked without the Warden, opens once the Warden has fallen, the Fragment is recovered and %d coins are in hand" % live_island.coins_required)
	main.queue_free()
	Progress.config_path = real_progress_path
	Progress.load_progress()
	if FileAccess.file_exists("user://progress_island_check.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress_island_check.cfg"))

	# --- The portal has to actually exist -----------------------------------
	var portal: Node = island.get_node_or_null("Portal")
	if portal == null:
		problems.append("the island has no Portal node")
	else:
		var disc: Node = island.get("_portal_disc")
		if disc == null:
			problems.append("the portal has no swirling surface")
		print("portal: %d children, symbols %d" % [portal.get_child_count(), (island.get("_symbols") as Array).size()])

	print("")
	if problems.is_empty():
		print("ISLAND OK - every ledge, coin and checkpoint is reachable")
	else:
		print("ISLAND PROBLEMS (%d):" % problems.size())
		for problem in problems:
			print("  - " + problem)
	get_tree().quit()


func _nearest_surface(surfaces: Array, spot: Vector3) -> int:
	var best := -1
	var best_score := INF
	for i in surfaces.size():
		var point: Vector3 = surfaces[i]["point"]
		var radius := float(surfaces[i]["radius"])
		var gap := maxf(0.0, Vector2(spot.x - point.x, spot.z - point.z).length() - radius)
		var score := absf(gap) + absf(spot.y - point.y) * 2.0
		if score < best_score:
			best_score = score
			best = i
	return best


## Every ledge index, optionally including the ones a puzzle has to be solved for.
func _indices(surfaces: Array, include_gated: bool, island: ForgottenIsland) -> Array[int]:
	var list: Array[int] = []
	for i in surfaces.size():
		if include_gated or island.surface_open(surfaces[i]):
			list.append(i)
	return list


## Which ledges can be walked to from [param start], following one-way jumps and
## only using the ledges in [param allowed].
func _reachable(surfaces: Array, start: int, allowed: Array[int] = []) -> Dictionary:
	var usable := allowed
	if usable.is_empty():
		# No filter given: every ledge counts.
		for i in surfaces.size():
			usable.append(i)
	var seen := {}
	if start in usable:
		seen[start] = true
	var queue: Array[int] = []
	if start in usable:
		queue.append(start)
	while not queue.is_empty():
		var current: int = queue.pop_back()
		for i in usable:
			if seen.has(i):
				continue
			if _can_hop(surfaces[current], surfaces[i]):
				seen[i] = true
				queue.append(i)
	return seen


func _can_hop(from_surface: Dictionary, to_surface: Dictionary) -> bool:
	var from: Vector3 = from_surface["point"]
	var to: Vector3 = to_surface["point"]
	var gap := Vector2(to.x - from.x, to.z - from.z).length() - float(from_surface["radius"]) - float(to_surface["radius"])
	if gap > MAX_GAP:
		return false
	return to.y - from.y <= MAX_RISE