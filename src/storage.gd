class_name Storage
extends RefCounted
## Local saves (one per game) and settings. On the web these live in the
## browser's storage, so each brother keeps his own copy of every game.

const DIR := "user://games"
const SETTINGS := "user://settings.json"


static func save_game(gs: GameState, local_player: int, waiting: bool) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"code": Codec.encode(gs),
		"local": local_player,
		"waiting": waiting,
		"time": int(Time.get_unix_time_from_system()),
		"turn": gs.turn,
		"seq": gs.seq,
		"cur": gs.cur,
		"cur_name": gs.players[gs.cur].name,
		"over": gs.winner >= 0,
		"title": title_for(gs),
	}
	var f := FileAccess.open("%s/%s.json" % [DIR, gs.game_id], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


static func title_for(gs: GameState) -> String:
	var names := PackedStringArray()
	for p in gs.players:
		names.append(p.name)
	return " vs ".join(names)


static func load_entry(game_id: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, game_id]
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


static func list_games() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var e := load_entry(f.get_basename())
		if e.is_empty():
			continue
		e["id"] = f.get_basename()
		out.append(e)
	out.sort_custom(func(a, b): return a.get("time", 0) > b.get("time", 0))
	return out


static func delete_game(game_id: String) -> void:
	DirAccess.remove_absolute("%s/%s.json" % [DIR, game_id])


static func _settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	return d if d is Dictionary else {}


static func get_setting(key: String, default: Variant = null) -> Variant:
	return _settings().get(key, default)


static func set_setting(key: String, value: Variant) -> void:
	var s := _settings()
	s[key] = value
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))
		f.close()
