extends SceneTree
## Headless smoke test: starts a seeded run and drives the player around with fake input,
## visiting every room via the console and clearing them. Fails on script errors (run via
## tools/run_tests.sh, which greps the log).
##   godot --headless -s res://tools/smoke_run.gd

var frames := 0
var phase := 0
var rc: Node = null
var rooms: Array = []
var room_i := 0


var started := false
var walk_dir := "S"
var start_cell := Vector2i.ZERO
var walked := false


func _initialize() -> void:
	pass


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _process(_d: float) -> bool:
	frames += 1
	if not started:
		started = true
		root.get_node("MetaSave").save_dir = "user://smoke_save"
		root.get_node("RunState").start_new(0x5EED1234)
		change_scene_to_file("res://scenes/run/run.tscn")
		return false
	if rc == null:
		rc = current_scene
		return false
	var console: Node = root.get_node("DebugConsole")
	# Phase 0 (frames 2-80): walk through a real door of the start room.
	if frames == 3:
		var doors: Dictionary = rc.room.info["doors"]
		walk_dir = doors.keys()[0]
		start_cell = rc._current
		print("smoke: walking %s out of the start room" % walk_dir)
		return false
	if frames > 3 and frames < 80:
		var act: String = {"N": "move_up", "S": "move_down", "E": "move_right", "W": "move_left"}[walk_dir]
		_press(act, true)
		if rc._current != start_cell and not walked:
			walked = true
			print("smoke: door transition OK -> %s" % rc._current)
		return false
	if frames == 80:
		for a in ["move_up", "move_down", "move_left", "move_right"]:
			_press(a, false)
		if not walked:
			print("smoke: FAIL door transition")
			quit(1)
	if frames == 85:
		rooms = rc.layout["order"].duplicate()
		print("smoke: floor has %d rooms" % rooms.size())
		console.execute("god")
		for id in ["raw_geode", "bottle_cap", "obsidian_shard", "quartz_lens", "toy_soldier", "sun_disk"]:
			print("smoke: ", console.execute("give " + id))
	# Walk + shoot in a circle the whole time.
	var a := frames * 0.05
	_press("move_right", sin(a) > 0.3)
	_press("move_left", sin(a) < -0.3)
	_press("move_down", cos(a) > 0.3)
	_press("move_up", cos(a) < -0.3)
	_press("shoot_right", frames % 120 < 60)
	_press("shoot_down", frames % 120 >= 60)
	if frames % 50 == 0:
		_press("dig_charge", true)
	if frames % 50 == 1:
		_press("dig_charge", false)
	if frames % 90 == 0:
		_press("use_active", true)
		_press("dash", true)
	if frames % 90 == 1:
		_press("use_active", false)
		_press("dash", false)
	# Every 150 frames: kill everything in the room and move to the next one.
	if frames > 90 and frames % 150 == 0:
		for e in get_nodes_in_group("enemies"):
			e.take_hit(9999.0, Vector2.RIGHT, [])
	if frames > 90 and frames % 150 == 120:
		if room_i < rooms.size():
			var c: Vector2i = rooms[room_i]
			room_i += 1
			rc.enter_room(c, "")
			print("smoke: entered %s room %s (%s)" % [rc.layout["rooms"][c]["type"], c, rc.layout["rooms"][c]["template"]])
	if frames > 10 and room_i >= rooms.size() and frames % 150 == 140:
		print("smoke: stash=%d pulp=%d brood=%d kills=%d bullets=%d" % [root.get_node("RunState").stash_total(), root.get_node("MetaSave").data["pulp"], root.get_node("RunState").stats["brood_rescued"], root.get_node("RunState").stats["kills"], rc.projectiles.bullets.size()])
		_bench()
		print("smoke: OK")
		quit(0)
	if frames > 6000:
		print("smoke: TIMEOUT")
		quit(1)
	return false


## 600 enemy bullets + 100 split/bouncing player shots, simulated for 120 physics steps.
func _bench() -> void:
	var ps: Node = rc.projectiles
	ps.clear()
	var r := RandomNumberGenerator.new()
	r.seed = 1
	for i in 600:
		ps.spawn_enemy_shot(Vector2(r.randf_range(10, 198), r.randf_range(10, 102)), Vector2.from_angle(r.randf() * TAU) * 6.0, Color.RED, 3.0, 99999.0)
	for i in 100:
		ps.spawn_player_shot(Vector2(104, 56), Vector2.from_angle(r.randf() * TAU), rc.player.spec)
	var t0 := Time.get_ticks_usec()
	var alive := 0
	for i in 60:
		ps._physics_process(1.0 / 60.0)
		alive += ps.bullets.size()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 60.0
	print("smoke: bench avg %d live bullets, %.2f ms per physics step (budget 8 ms)" % [alive / 60, ms])
	if ms > 8.0:
		print("smoke: FAIL bullet budget")
		quit(1)
