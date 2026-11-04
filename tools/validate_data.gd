extends SceneTree
## CLI data validator. Usage:
##   godot --headless -s res://tools/validate_data.gd
## Exits 0 when all /data JSON is valid, 1 otherwise.

func _initialize() -> void:
	var content: Node = root.get_node_or_null("Content")
	if content == null:
		content = load("res://scripts/autoload/content.gd").new()
		root.add_child(content)
	else:
		content.reload()
	var total := 0
	for cat in content.SCHEMA:
		total += content.count(cat)
	if content.errors.is_empty():
		print("validate_data: OK (%d entries)" % total)
		quit(0)
	else:
		for e in content.errors:
			printerr("  " + e)
		printerr("validate_data: %d problem(s)" % content.errors.size())
		quit(1)
