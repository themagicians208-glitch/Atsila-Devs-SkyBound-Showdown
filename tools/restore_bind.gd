extends Node

## One-shot helper: replaces the stored key binds. Args are action=keycode pairs;
## no args means "clear them all".

func _ready() -> void:
	var settings := get_node("/root/Settings")
	settings.call("clear_key_binds")
	for spec in OS.get_cmdline_user_args():
		var parts := str(spec).split("=")
		if parts.size() == 2:
			settings.call("set_key_bind", parts[0], int(parts[1]))
	print("binds now: %s" % settings.get("key_binds"))
	get_tree().quit()
