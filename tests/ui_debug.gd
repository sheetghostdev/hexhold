extends SceneTree
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 5:
		await process_frame
	_dump(root, 0)
	quit()

func _dump(n: Node, d: int) -> void:
	if d > 6:
		return
	var info := ""
	if n is Control:
		info = " size=%s pos=%s vis=%s" % [n.size, n.position, n.visible]
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", info)
	for c in n.get_children():
		_dump(c, d + 1)
