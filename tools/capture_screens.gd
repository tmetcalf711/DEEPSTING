extends SceneTree
## Renders gameplay screenshots for review (needs a display, e.g. xvfb-run).
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s res://tools/capture_screens.gd -- <out_dir>

var frames := 0
var rc: Node = null
var out_dir := "user://shots"
var started := false
var built := false
var steps: Array = []
var wait := 0


func _shot(shot_name: String) -> void:
	root.get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	print("capture: ", shot_name)


func _console(cmd: String) -> void:
	root.get_node("DebugConsole").execute(cmd)


func _first(type: String, shape: String = "") -> Vector2i:
	for a in rc.layout["order"]:
		var info: Dictionary = rc.layout["rooms"][a]
		if (type == "" or info["type"] == type) and (shape == "" or info["shape"] == shape):
			return a
	return Vector2i(-1, -1)


func _special(tid: String) -> void:
	rc._start_room_test(tid)


func _kill_all() -> void:
	for e in get_nodes_in_group("enemies"):
		e.untargetable = false
		e.take_hit(9999.0, Vector2.UP, [])


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
	if not built:
		built = true
		rc = current_scene
		_build()
		return false
	if wait > 0:
		wait -= 1
		return false
	if steps.is_empty():
		quit(0)
		return false
	var s: Array = steps.pop_front()
	wait = int(s[0])
	s[1].call()
	return false


func _then(w: int, fn: Callable) -> void:
	steps.append([w, fn])


func _build() -> void:
	_then(30, func() -> void:
		_console("god")
		for id in ["raw_geode", "acid_gland", "toy_soldier", "wax_wings", "dead_phone"]:
			_console("give " + id))
	# Topsoil floor: a big room in combat, the minimap with big rooms.
	_then(40, func() -> void:
		_console("goto 2")
		var big := _first("normal", "2x1")
		if big.x < 0:
			big = _first("normal", "1x2")
		if big.x < 0:
			big = _first("normal", "2x2")
		if big.x >= 0:
			rc.enter_room(big, "")
		Input.action_press("shoot_right"))
	_then(50, func() -> void: _shot("01_topsoil_big_room"))
	_then(10, func() -> void:
		Input.action_release("shoot_right")
		_console("reveal"))
	_then(10, func() -> void: _shot("02_minimap_revealed"))
	# Tunnel Mole boss (rubble rain / burrow strike).
	_then(1, func() -> void:
		rc.enter_room(rc.layout["boss"], "")
		Input.action_press("shoot_up"))
	_then(200, func() -> void: _shot("03_boss_fight"))
	_then(1, func() -> void:
		Input.action_release("shoot_up")
		_kill_all())
	_then(200, func() -> void: _console("deal royal"))
	_then(30, func() -> void: _shot("04_boss_cleared_deal_door"))
	# Locked shop door on floor 2.
	_then(1, func() -> void:
		var shop := _first("shop")
		var info: Dictionary = rc.layout["rooms"][shop]
		var link: Array = info["links"].values()[0]
		rc.enter_room(link[0], link[1]))
	_then(30, func() -> void: _shot("05_locked_shop_door"))
	# Special rooms.
	for tid in ["special_shop", "special_den", "special_royal", "special_sacrifice", "special_arcade", "special_challenge"]:
		_then(1, func() -> void: _special(tid))
		_then(45, func() -> void: _shot("06_" + tid))
	# Curse of the Cave-in.
	_then(1, func() -> void: _console("curse cave_in"))
	_then(40, func() -> void: _shot("07_curse_cave_in"))
	_then(1, func() -> void: _console("curse none"))
	# Consumables, knick-knack, radiation, mutation picker.
	_then(1, func() -> void:
		var rs: Node = root.get_node("RunState")
		rc.player.effects.set_trinket("fishing_hook")
		rs.consumable = {"kind": "fluid", "id": "teal"}
		rs.add_radiation(70.0)
		rc._start_room_test("topsoil_t08")
		Input.action_press("shoot_left"))
	_then(40, func() -> void: _shot("09_hud_consumables_radiation"))
	_then(1, func() -> void:
		Input.action_release("shoot_left")
		rc._offer_mutation())
	_then(10, func() -> void: _shot("10_mutation_picker"))
	_then(1, func() -> void:
		var picker: Node = rc.get_node_or_null("MutationPicker")
		if picker:
			picker._pick(picker.options[0]))
	# Room editor.
	_then(1, func() -> void: change_scene_to_file("res://tools/room_editor.tscn"))
	_then(20, func() -> void:
		var ed: Node = current_scene
		ed._load("hive_x01"))
	_then(10, func() -> void: _shot("08_room_editor"))
	# Synergy Lab with a stacked build.
	_then(1, func() -> void:
		var gs: Node = root.get_node("GameState")
		gs.room_test_template = "lab_range"
		gs.lab_mode = true
		root.get_node("RunState").start_new(7)
		change_scene_to_file("res://scenes/run/run.tscn"))
	_then(20, func() -> void:
		rc = current_scene
		for e in [["items", "raw_geode"], ["items", "darning_needle"], ["items", "static_wire"], ["items", "acid_gland"], ["items", "snail_shell"], ["mutations", "glow_glands"]]:
			load("res://scripts/tools/synergy_lab.gd").toggle(e[0], e[1])
		rc.player.position = Vector2(60, 56)
		Input.action_press("shoot_right"))
	_then(70, func() -> void: _shot("11_synergy_lab"))
	_then(1, func() -> void: Input.action_release("shoot_right"))
