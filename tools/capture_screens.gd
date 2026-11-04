extends SceneTree
## Renders gameplay screenshots for review (needs a display, e.g. xvfb-run).
##   xvfb-run -a godot --rendering-driver opengl3 -s res://tools/capture_screens.gd -- <out_dir>

var frames := 0
var rc: Node = null
var out_dir := "user://shots"
var shots := []
var started := false


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("capture: ", name)


func _first(type: String) -> Vector2i:
	for c in rc.layout["order"]:
		if rc.layout["rooms"][c]["type"] == type:
			return c
	return Vector2i(-1, -1)


func _process(_d: float) -> bool:
	frames += 1
	if not started:
		started = true
		var args := OS.get_cmdline_user_args()
		if not args.is_empty():
			out_dir = args[0]
		root.get_node("MetaSave").save_dir = "user://capture_save"
		root.get_node("RunState").start_new(0x5EED1234)
		change_scene_to_file("res://scenes/run/run.tscn")
		return false
	if rc == null:
		rc = current_scene
		return false
	var console: Node = root.get_node("DebugConsole")
	match frames:
		40:
			_shot("01_start_room")
			console.execute("god")
		45:
			# First normal room with a brood cell, fighting.
			for c in rc.layout["order"]:
				if rc.layout["rooms"][c]["brood_cell"]:
					rc.enter_room(c, "S")
					break
		110:
			_press("shoot_up", true)
			_press("move_left", true)
		150:
			_shot("02_combat")
			_press("move_left", false)
		200:
			for e in get_nodes_in_group("enemies"):
				e.take_hit(9999.0, Vector2.UP, [])
		235:
			_press("shoot_up", false)
			_shot("03_cleared_workers_hauling")
		260:
			for b in get_nodes_in_group("brood_cells"):
				b.take_hit(1.0, Vector2.UP, ["blast"])
		285:
			_shot("04_brood_rescued")
		300:
			for id in ["raw_geode", "bottle_cap", "obsidian_shard", "quartz_lens", "toy_soldier", "gnome_hat", "dead_phone"]:
				console.execute("give " + id)
			rc.enter_room(_first("boss"), "W")
		420:
			_press("shoot_right", true)
		470:
			_shot("05_boss_fight")
		520:
			_press("shoot_right", false)
			for e in get_nodes_in_group("enemies"):
				if e.is_boss:
					e.take_hit(9999.0, Vector2.UP, [])
		600:
			_shot("06_boss_shaft_haul")
		760:
			_shot("07_banked_trapdoor")
		770:
			rc.enter_room(_first("treasure"), "S")
		800:
			_shot("08_treasure_room")
		810:
			rc.enter_room(_first("secret"), "S")
		840:
			_shot("09_secret_room")
			var ev := InputEventAction.new()
			ev.action = "pause"
			ev.pressed = true
			Input.parse_input_event(ev)
		860:
			_shot("10_pause")
			quit(0)
	return false
