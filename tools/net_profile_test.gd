extends Node

## Two-process check for the online profile sync (name + chosen character), and
## for the host renaming a player whose name is already taken.
## Run as:  godot --headless --path . tools/net_profile_test.tscn -- host
##          godot --headless --path . tools/net_profile_test.tscn -- client [clash]


func _ready() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		print("NO NETWORK AUTOLOAD")
		get_tree().quit()
		return
	var args := OS.get_cmdline_user_args()
	if args.has("host"):
		network.local_name = "Hosty"
		network.local_character = "Nattie"
		print("HOST_START ok=", network.host())
		await get_tree().create_timer(4.5).timeout
		_report(network)
		get_tree().quit()
	else:
		# With "clash", the client asks for the name the host already has.
		network.local_name = "Hosty" if args.has("clash") else "Clienty"
		network.local_character = "Nattie"
		network.name_taken.connect(func(new_name: String) -> void:
			print("CLIENT told the name was taken; now called '%s'" % new_name))
		print("CLIENT_JOIN ok=", network.join("127.0.0.1"))
		await get_tree().create_timer(1.5).timeout
		print("CLIENT connected to host = ", network.players.has(1))
		# Change the pick after connecting, the way the character select can.
		network.local_character = "Nattie"
		network.announce_profile()
		await get_tree().create_timer(5.0).timeout
		print("CLIENT final local_name = '%s'" % network.local_name)
		get_tree().quit()


func _report(network: Node) -> void:
	print("HOST sees players: ", network.players.keys())
	for id in network.players.keys():
		print("   peer %d  name=%s  character=%s" % [
			id, network.get_player_name(id), network.get_player_character(id)])
