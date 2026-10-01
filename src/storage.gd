class_name Storage
extends RefCounted
## Small local settings (sound, your name). On the web they live in the
## browser's storage.

const SETTINGS := "user://settings.json"


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
