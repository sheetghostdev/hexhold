extends SceneTree
## Loads every script so parse errors show up: godot --headless --script res://tests/check.gd
func _init() -> void:
	var files := []
	_collect("res://src", files)
	for f in files:
		var s = load(f)
		if s == null:
			printerr("FAILED: ", f)
	print("checked ", files.size(), " scripts")
	quit()

func _collect(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
