extends Node

## Drives the Shadow Slime on the Forgotten Island and checks the rules the brief
## states explicitly:
##   * its speed is exactly half of the player's NORMAL walking speed (not the
##     dash), measured from the player rather than hard-coded;
##   * it never moves faster than that while chasing;
##   * it chases what comes near, loses interest when the player leaves, and
##     walks back to its patrol spot;
##   * hitting it flashes it and takes health, and the last hit dissolves it;
##   * touching it is fatal, the same as every other enemy here.
##
## Run: godot --headless --path . tools/check_slime.tscn

const SPEED_TOLERANCE := 0.02

var _problems: Array[String] = []


func _ready() -> void:
	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout

	var player: CharacterBody3D = main.get("player")
	var island: ForgottenIsland = main.get("island")
	var slimes := get_tree().get_nodes_in_group("shadow_slimes")
	var enemies := get_tree().get_nodes_in_group("enemies")
	print("slimes placed: %d   in the 'enemies' group: %d   island says %d" % [
		slimes.size(), enemies.size(), island.slimes_placed])
	if slimes.size() != island.slimes_placed:
		_problems.append("island placed %d slimes but %d exist" % [island.slimes_placed, slimes.size()])
	for slime in slimes:
		if not (slime as Node).is_in_group("enemies"):
			_problems.append("%s is not in the 'enemies' group, so slashes miss it" % (slime as Node).name)

	# --- 1. Half the player's normal walking speed --------------------------
	Input.action_press("move_forward")
	var peak := 0.0
	var frames := 0
	while frames < 120:
		frames += 1
		await get_tree().physics_frame
		if not bool(player.get("is_dashing")):
			peak = maxf(peak, Vector2(player.velocity.x, player.velocity.z).length())
	Input.action_release("move_forward")
	print("player normal walking speed: %.3f u/s" % peak)
	if peak < 1.0:
		_problems.append("the player never got walking (peak %.3f), so the speed rule cannot be judged" % peak)
	var expected := peak * 0.5
	for slime in slimes:
		var chase := float((slime as Node).get("chase_speed"))
		var ratio := float((slime as Node).get("speed_ratio"))
		if absf(chase - expected) > expected * SPEED_TOLERANCE:
			_problems.append("%s chases at %.3f, expected %.3f (half of %.3f)" % [
				(slime as Node).name, chase, expected, peak])
		if not is_equal_approx(ratio, 0.5):
			_problems.append("%s speed_ratio is %.2f, expected 0.5" % [(slime as Node).name, ratio])
	print("every slime chases at %.3f u/s (half of %.3f), ratio %.2f" % [expected, peak, 0.5])

	# --- 2. It really moves at that speed, and never faster -----------------
	# Placed 8 units away and sampled for one second: it covers about 2 units in
	# that time, so the test finishes before the slime reaches the player and ends
	# the run, which would pause everything downstream.
	var subject: ShadowSlime = slimes[0]
	var patrol_spot := Vector3(0.0, 0.05, 7.0)
	# Both of them on the start glade, which is solid ground: 7 units apart is
	# inside its detection range but outside its attack range, so the sample sees
	# a clean chase and is over before it can reach the player.
	player.global_position = Vector3(0.0, 0.6, 0.0)
	player.velocity = Vector3.ZERO
	subject.place_at(patrol_spot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fastest := 0.0
	var seen_chase := false
	frames = 0
	while frames < 60:
		frames += 1
		await get_tree().physics_frame
		fastest = maxf(fastest, Vector2(subject.velocity.x, subject.velocity.z).length())
		if subject.state_name() == "chase":
			seen_chase = true
	print("chase: state %s, fastest horizontal %.3f u/s (limit %.3f), player %.1f units away" % [
		subject.state_name(), fastest, expected, subject.global_position.distance_to(player.global_position)])
	if not seen_chase:
		_problems.append("a slime 8 units away never entered the chase state")
	if fastest > expected * (1.0 + SPEED_TOLERANCE):
		_problems.append("chasing slime moved at %.3f, faster than half the player's %.3f" % [fastest, expected])
	if fastest < expected * 0.85:
		_problems.append("chasing slime only reached %.3f, expected about %.3f" % [fastest, expected])

	# --- 3. It loses interest and goes home ---------------------------------
	# 26 units away, on a real platform of the forest path rather than in mid-air.
	player.global_position = Vector3(1.5, 3.2, 32.8)
	player.velocity = Vector3.ZERO
	# And put the slime a solid 6 units out from its patrol spot, on the same
	# ground, so "goes home" is a journey rather than a wobble inside the radius
	# its patrol wanders over anyway. Its home stays where it is: place_at()
	# re-homes a slime by design, so this moves it without moving the goalpost.
	subject.global_position = patrol_spot + Vector3(0.0, 0.35, -6.0)
	subject.velocity = Vector3(0.0, -1.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("player %.1f units away: state %s, paused %s" % [
		subject.global_position.distance_to(player.global_position), subject.state_name(), get_tree().paused])
	if subject.state_name() != "patrol":
		_problems.append("it kept chasing with the player 30 units away (state %s)" % subject.state_name())
	var before := subject.global_position.distance_to(patrol_spot)
	var elapsed := 0.0
	while elapsed < 3.0:
		elapsed += 0.1
		await get_tree().create_timer(0.1).timeout
	var after := subject.global_position.distance_to(patrol_spot)
	print("walking home: %.2f -> %.2f units from its patrol spot" % [before, after])
	if before < 4.0:
		_problems.append("the slime was only %.2f from home, too close to judge the return" % before)
	elif after > before - 0.5:
		_problems.append("it made no real progress home (%.2f -> %.2f)" % [before, after])

	# --- 4. They stay on their ledges ---------------------------------------
	# Six seconds of patrolling with the player far away: every slime should still
	# be near the spot it was placed on, rather than having hopped off the island.
	var strays := 0
	for node in slimes:
		(node as ShadowSlime).reset_to_home()
	await get_tree().create_timer(6.0).timeout
	for node in slimes:
		var slime := node as ShadowSlime
		var home: Vector3 = slime.get("_home")
		var drift := slime.global_position.distance_to(home)
		if drift > 3.0:
			strays += 1
			_problems.append("%s drifted %.1f units from its patrol spot at %s (now %s)" % [
				slime.name, drift, home, slime.global_position])
	print("after 6s of patrolling: %d of %d slimes within 3 units of their spot" % [
		slimes.size() - strays, slimes.size()])

	# --- 5. Hits, flashing, and dissolving ----------------------------------
	# Keep the player well clear so the fight cannot pause the game.
	player.global_position = Vector3(0.0, 0.6, -4.0)
	var health_before := int(subject.get("health"))
	var landed := bool(subject.call("take_hit", 1, subject.global_position + Vector3(0.0, 0.0, -1.0)))
	# Two physics frames: the flash is applied inside the slime's own physics step,
	# not at the moment take_hit is called.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var flashed: bool = (subject.get("_body_material") as StandardMaterial3D).albedo_color.r > 0.9
	print("hit landed %s, health %d -> %d, flashed white %s" % [
		landed, health_before, int(subject.get("health")), flashed])
	if not landed or int(subject.get("health")) != health_before - 1:
		_problems.append("a hit did not take exactly one health")
	if not flashed:
		_problems.append("a hit did not flash the slime")
	var died := [false]
	subject.defeated.connect(func(): died[0] = true)
	while int(subject.get("health")) > 0:
		subject.call("take_hit", 1, subject.global_position + Vector3(0.0, 0.0, -1.0))
		await get_tree().physics_frame
	await get_tree().create_timer(1.0).timeout
	print("defeated: signal %s, gone from the tree %s" % [died[0], not is_instance_valid(subject)])
	if not died[0]:
		_problems.append("its defeat never fired the defeated signal")
	if is_instance_valid(subject):
		_problems.append("it never dissolved away")

	# --- 6. Touching one is fatal -------------------------------------------
	var hunter: ShadowSlime = slimes[1]
	var died_player := [false]
	player.died.connect(func(): died_player[0] = true)
	player.global_position = Vector3(0.0, 0.6, 0.0)
	player.velocity = Vector3.ZERO
	hunter.place_at(Vector3(0.0, 0.05, 0.3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("touch: player dead %s, death screen %s" % [died_player[0], (main.get("hud") as Node).get("death_overlay").visible])
	if not died_player[0]:
		_problems.append("touching a Shadow Slime did not end the run")

	print("")
	if _problems.is_empty():
		print("SLIME OK - half-speed rule, chase, lose-interest, hits and fatal touch all hold")
	else:
		print("SLIME PROBLEMS (%d):" % _problems.size())
		for problem in _problems:
			print("  - " + problem)
	get_tree().quit()