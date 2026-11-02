extends RefCounted

## The playable characters. Each display name is the name of the model file it was
## built from, as requested.

const CHARACTERS: Array = [
	{"id": "Jamal", "scene": "res://objects/character.tscn"},
	{"id": "Nattie", "scene": "res://objects/characters/nattie.tscn"},
]


static func count() -> int:
	return CHARACTERS.size()


static func id_at(index: int) -> String:
	if CHARACTERS.is_empty():
		return ""
	return str(CHARACTERS[posmod(index, CHARACTERS.size())]["id"])


static func index_of(id: String) -> int:
	for i in CHARACTERS.size():
		if str(CHARACTERS[i]["id"]) == id:
			return i
	return 0


static func has(id: String) -> bool:
	for entry in CHARACTERS:
		if str(entry["id"]) == id:
			return true
	return false


static func scene_for(id: String) -> String:
	for entry in CHARACTERS:
		if str(entry["id"]) == id:
			return str(entry["scene"])
	return ""


static func default_id() -> String:
	return id_at(0)