class_name InputPrompts

## Chooses on-screen button names for the connected gamepad, so the on-screen
## hints match the pad the player actually holds. Xbox names are the default;
## a PlayStation pad (DualSense / DualShock / PS4 / PS5) gets Sony names.
## Keyboard and mouse hints are unaffected.

static func is_playstation() -> bool:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return false
	var pad_name := Input.get_joy_name(int(pads[0])).to_lower()
	return pad_name.contains("playstation") \
		or pad_name.contains("dualsense") \
		or pad_name.contains("dualshock") \
		or pad_name.contains("ps4") \
		or pad_name.contains("ps5") \
		or pad_name.contains("wireless controller")


static func glyph(action: String) -> String:
	var ps := is_playstation()
	match action:
		"jump": return "CROSS" if ps else "A"
		"interact": return "SQUARE" if ps else "X"
		"time_freeze": return "TRIANGLE" if ps else "Y"
		"shift_dimension": return "L1" if ps else "LB"
		"dash": return "R1" if ps else "RB"
		"back": return "CIRCLE" if ps else "B"
	return action