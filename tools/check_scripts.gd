extends SceneTree
## Loads every GDScript and scene in the project (outside addons/) so parse errors anywhere fail
## the build, then boots the main menu and checks it actually ran its script.
##   godot --headless -s res://tools/check_scripts.gd

var failures: PackedStringArray = []
var frames := 0
var menu: Node = null


func _initialize() -> void:
	for path in _files("res://", [".gd", ".tscn"]):
		var res: Resource = load(path)
		if res == null:
			failures.append("cannot load " + path)
		elif res is GDScript and not (res as GDScript).can_instantiate() and not path.begins_with("res://tests/"):
			# Abstract/static-only scripts can't instantiate; a broken one also can't reload.
			if (res as GDScript).reload() != OK:
				failures.append("parse error in " + path)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		menu = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(menu)
	elif frames == 5:
		var title: Label = menu.get_node("%Title")
		if title.text == "":
			failures.append("main menu did not initialize (script failed?)")
		if failures.is_empty():
			print("check_scripts: OK")
			quit(0)
		else:
			for f in failures:
				printerr("check_scripts: " + f)
			quit(1)
	return false


func _files(dir: String, exts: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var full := dir.path_join(n)
			if d.current_is_dir():
				if n != "addons":
					out.append_array(_files(full, exts))
			else:
				for e in exts:
					if n.ends_with(e):
						out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out
