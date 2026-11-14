extends SceneTree
## Headless smoke test (run by tools/run_tests.sh). Plays a seeded run with scripted input:
## walks through a real door, visits every room of both chapter-1 floors, descends via the
## trapdoor, exercises every special room type (buying, sacrificing, gambling, choosing), deals,
## curses and big rooms, then benchmarks 600+ bullets. Fails on script errors (grepped by the
## runner) or on any explicit check below.
##   godot --headless -s res://tools/smoke_run.gd

const SPECIALS := ["shop", "sacrifice", "curse", "challenge", "miniboss", "vault", "arcade", "library", "royal", "den"]

var frames := 0
var started := false
var rc: Node = null
var steps: Array = []      # [frames_to_wait, Callable]
var wait := 0
var walk_action := ""
var start_anchor := Vector2i.ZERO
var failures: PackedStringArray = []
var prev_trinket := ""
var expecting_picker := false
var descended := false  # the M3 section checks the picker itself


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("smoke: FAIL ", what)


func _rs() -> Node:
	return root.get_node("RunState")


func _console(cmd: String) -> String:
	var out: String = root.get_node("DebugConsole").execute(cmd)
	print("smoke: > %s  =>  %s" % [cmd, out.split("\n")[0]])
	return out


func _process(_d: float) -> bool:
	frames += 1
	if not started:
		started = true
		root.get_node("MetaSave").save_dir = "user://smoke_save"
		root.get_node("MetaSave").data["runs"]["started"] = 0
		_rs().start_new(0x5EED1234)
		change_scene_to_file("res://scenes/run/run.tscn")
		return false
	if rc == null:
		rc = current_scene
		_build_steps()
		return false
	# Keep the wasp busy: shoot in a slow circle (walking is driven by the steps).
	_press("shoot_right", frames % 120 < 60)
	_press("shoot_down", frames % 120 >= 60)
	if wait > 0:
		wait -= 1
		return false
	var picker: Node = rc.get_node_or_null("MutationPicker")
	if picker and not picker.is_queued_for_deletion() and not expecting_picker:
		print("smoke: auto-picked mutation %s" % picker.options[0])
		picker._pick(picker.options[0])  # it pauses the game (and any transition) until chosen
	if rc._transitioning:
		return false  # tweens run on real time; headless frames are faster than that
	if steps.is_empty():
		_finish()
		return false
	var step: Array = steps.pop_front()
	wait = int(step[0])
	step[1].call()
	return false


func _then(frames_after: int, fn: Callable) -> void:
	steps.append([frames_after, fn])


func _build_steps() -> void:
	# 1. Walk out of the start room through a real door.
	_then(75, func() -> void:
		start_anchor = rc.current_anchor
		var slot: String = rc.room.info["doors"].keys()[0]
		walk_action = {"N": "move_up", "S": "move_down", "E": "move_right", "W": "move_left"}[rc.room.slot_dir(slot)]
		_press(walk_action, true))
	_then(2, func() -> void:
		_press(walk_action, false)
		_check(rc.current_anchor != start_anchor, "door transition")
		print("smoke: door transition -> %s" % rc.current_anchor)
		_console("god")
		for id in ["raw_geode", "bottle_cap", "obsidian_shard", "quartz_lens", "toy_soldier", "sun_disk", "acid_gland", "salt_lick"]:
			_console("give " + id))
	# 2. Visit and clear every room on floor 1 and floor 2.
	for floor_i in 2:
		_then(1, func() -> void: _queue_floor_tour())
	# 3. Every special room type through the room-test path.
	_then(1, func() -> void:
		for t in SPECIALS:
			_queue_special(t))
	# 4. Milestone 3 systems in real play.
	_then(1, func() -> void: _queue_m3())
	# 5. Every enemy (each as a champion) and every boss fights for a moment.
	_then(1, func() -> void: _queue_bestiary())
	# 6. Curses regenerate the floor.
	for c in ["cave_in", "tremor", "toxic_fog", "labyrinth", "silt"]:
		_then(20, func() -> void:
			_console("curse " + c)
			_check(rc.curse_id == c, "curse " + c)
			if c == "labyrinth":
				print("smoke: labyrinth floor has %d rooms" % rc.layout["order"].size()))
	_then(1, func() -> void: _console("curse none"))


## Visits every room of the current floor (killing what's there), then takes the trapdoor.
func _queue_floor_tour() -> void:
	var order: Array = rc.layout["order"].duplicate()
	print("smoke: floor %d (%s) has %d rooms, curse '%s'" % [_rs().floor_index + 1, rc.stratum["id"], order.size(), rc.curse_id])
	var shapes := {}
	for a in order:
		shapes[rc.layout["rooms"][a]["shape"]] = true
	print("smoke: shapes on floor: %s" % [shapes.keys()])
	var front: Array = []
	for a in order:
		front.append([1, func() -> void:
			rc.enter_room(a, "")
			var info: Dictionary = rc.layout["rooms"][a]
			print("smoke: entered %s %s room %s (%s)" % [info["shape"], info["type"], a, info["template"]])])
		front.append([40, func() -> void:
			_kill_all()])
		front.append([70, func() -> void:
			_kill_all()])
	front.append([1, func() -> void:
		# The boss shaft banks the stash; then descend through the trapdoor.
		rc.enter_room(rc.layout["boss"], "")])
	front.append([30, func() -> void:
		_kill_all()])
	front.append([300, func() -> void:
		_check(rc.room.info.get("shaft_done", false), "boss shaft completed")
		_check(_rs().stash_total() == 0, "stash banked")
		var before: int = _rs().floor_index
		rc.on_trapdoor()
		print("smoke: trapdoor from floor %d" % (before + 1))])
	front.append([60, func() -> void:
		if rc._ended:
			# Chapter 1 complete: dismiss the victory screen and keep testing.
			print("smoke: chapter complete screen shown")
			paused = false
			rc._ended = false
			for n in rc.get_children():
				if n.has_method("setup") and n is CanvasLayer and n.get("victory") != null:
					n.queue_free()])
	steps = front + steps


## Builds a single special room via the room-test path and interacts with it.
func _queue_special(type: String) -> void:
	var front: Array = []
	front.append([1, func() -> void:
		var tid := ""
		for t in root.get_node("Content").all("rooms"):
			if type in t.get("room_types", []):
				tid = t["id"]
		root.get_node("GameState").room_test_template = tid
		rc._start_room_test(tid)
		root.get_node("GameState").room_test_template = ""
		_rs().add_mana(60)
		_rs().hearts_max = 12
		_rs().hearts = 12
		print("smoke: special %s (%s)" % [type, tid])])
	for phase in 4:
		front.append([60, func() -> void: _special_phase(type, phase)])
	steps = front + steps


func _queue_m3() -> void:
	var front: Array = []
	front.append([1, func() -> void:
		rc._start_room_test("hive_n02")
		for id in ["static_wire", "tin_can_phone", "darning_needle", "clay_idol", "amber_gnat", "dead_lighter", "jawbreaker", "glass_eye"]:
			_console("give " + id)
		rc.player.effects.add_mutation("glow_glands")
		print("smoke: m3 build: multishot=%d boomerang=%s procs=%d familiars=%d auras=%d" % [
			rc.player.spec["multishot"], rc.player.spec["boomerang"], rc.player.spec["procs"].size(), rc.player.effects.familiars.size(), _rs().auras.size()])
		_check(rc.player.spec["multishot"] == 2 and rc.player.spec["boomerang"], "m3 build composed")
		_press("shoot_right", true)])
	front.append([150, func() -> void:
		print("smoke: m3 fight: %d enemies left, kills %d, radiation %.1f" % [rc.room.enemies_alive, int(_rs().stats["kills"]), _rs().radiation])])
	front.append([1, func() -> void:
		# Knick-knack: walk onto one, then swap it for another.
		rc.room.spawn_pickup("trinket", rc.player.position)])
	front.append([20, func() -> void:
		_check(_rs().trinket != "", "picked up a knick-knack")
		print("smoke: knick-knack %s" % _rs().trinket)
		prev_trinket = _rs().trinket
		rc.room.spawn_pickup("trinket", rc.player.position)])
	front.append([20, func() -> void:
		var dropped: Array = get_nodes_in_group("pickups").filter(func(n: Node) -> bool:
			return n.data["kind"] == "trinket" and not n.collected and n.payload == prev_trinket)
		_check(dropped.size() == 1 and _rs().trinket != prev_trinket, "swapped knick-knack was dropped (and not re-picked)")
		rc.room.spawn_pickup("fossil", rc.player.position)])
	front.append([20, func() -> void:
		_check(_rs().consumable.get("kind", "") == "fossil", "holding a fossil")
		print("smoke: fossil %s" % _rs().consumable.get("id", ""))
		_press("use_consumable", true)])
	front.append([2, func() -> void:
		_press("use_consumable", false)
		_check(_rs().consumable.is_empty(), "fossil used")
		rc.room.spawn_pickup("fluid", rc.player.position)])
	front.append([20, func() -> void:
		var color: String = _rs().consumable.get("id", "")
		_press("use_consumable", true)
		print("smoke: drank %s fluid = %s" % [color, load("res://scripts/player/effect_host.gd").fluid_for_color(color)])])
	front.append([2, func() -> void:
		_press("use_consumable", false)
		_check(_rs().fluids_identified.size() >= 1, "fluid identified")
		_rs().add_radiation(200.0)
		expecting_picker = true
		_kill_all()])
	front.append([30, func() -> void:
		var picker: Node = rc.get_node_or_null("MutationPicker")
		_check(picker != null, "mutation offered at room clear")
		if picker:
			print("smoke: mutation options %s" % [picker.options])
			picker._pick(picker.options[0])])
	front.append([10, func() -> void:
		_press("shoot_right", false)
		print("smoke: mutations %s, next threshold %d" % [_rs().mutations, _rs().radiation_threshold])
		_check(_rs().mutations.size() >= 2, "mutation added")
		expecting_picker = false
		var picker: Node = rc.get_node_or_null("MutationPicker")
		if picker:
			picker._pick(picker.options[0])])
	steps = front + steps


func _queue_bestiary() -> void:
	var front: Array = []
	var champs: Array = root.get_node("Content").get_entry("config", "champions")["types"].keys()
	champs.sort()
	var i := 0
	for cat in ["enemies", "bosses"]:
		for id in root.get_node("Content").ids(cat):
			var champ: String = champs[i % champs.size()] if cat == "enemies" else ""
			i += 1
			front.append([1, func() -> void:
				rc._start_room_test("lab_range")
				_kill_all()
				var data: Dictionary = root.get_node("Content").get_entry(cat, id)
				var e: Node = rc.room.spawn_enemy(data, rc.room.center() + Vector2(40, 0), cat == "bosses", true, champ)
				e.untargetable = false])
			front.append([70, func() -> void:
				var alive: int = rc.room.room_enemies().size()
				if alive == 0:
					failures.append("bestiary: %s died on its own" % id)
				_kill_all()])
			front.append([15, func() -> void: _kill_all()])
	front.append([1, func() -> void: print("smoke: bestiary fought %d enemies and bosses" % i)])
	steps = front + steps


## Floors 3-8: boss, shaft, trapdoor; the last boss ends the run with Ending 1.
func _queue_descent() -> void:
	var front: Array = []
	for f in range(2, 8):
		front.append([1, func() -> void:
			rc.start_floor(f)
			print("smoke: descent floor %d = %s, boss %s" % [f + 1, rc.stratum["id"], rc.layout["rooms"][rc.layout["boss"]]["boss_id"]])
			rc.enter_room(rc.layout["boss"], "")])
		front.append([40, func() -> void: _kill_all()])
		front.append([20, func() -> void: _kill_all()])
		front.append([30, func() -> void: _await_shaft(f, 0)])
	front.append([30, func() -> void:
		_check(rc._ended, "the run ended after the last boss")
		var ends: Dictionary = root.get_node("MetaSave").data.get("endings", {})
		_check(ends.has("ending_1"), "ending 1 recorded")
		var screen: Array = rc.get_children().filter(func(n: Node) -> bool: return n.get("ending") == "ending_1")
		_check(not screen.is_empty(), "ending screen shown")
		print("smoke: reached %s" % ends.keys())
		paused = false
		rc._ended = false
		for n in screen:
			n.queue_free()])
	steps = front + steps


## Real-time animations (tweens, workers) don't advance per frame headless: poll with a deadline.
func _await_shaft(f: int, tries: int) -> void:
	if rc.room.info.get("shaft_done", false) or tries >= 60:
		_check(rc.room.info.get("shaft_done", false), "floor %d boss shaft" % (f + 1))
		rc.on_trapdoor()
		return
	_kill_all()
	steps.push_front([20, func() -> void: _await_shaft(f, tries + 1)])


func _special_phase(type: String, phase: int) -> void:
	var p: Node2D = rc.player
	if phase == 0:
		match type:
			"shop", "den":
				var wares: Array = rc.room.entities.get_children().filter(func(n: Node) -> bool: return n.has_method("_try_buy"))
				_check(not wares.is_empty(), type + " has wares")
				var mana_before: int = _rs().mana
				var hearts_before: int = _rs().hearts_max
				for w in wares:
					w._try_buy(p)
				var sold: int = rc.room.info["wares"].filter(func(e: Dictionary) -> bool: return e["sold"]).size()
				print("smoke: %s sold %d/%d (mana %d->%d, hearts %d->%d)" % [type, sold, wares.size(), mana_before, _rs().mana, hearts_before, _rs().hearts_max])
				_check(sold > 0, type + " sold something")
			"sacrifice":
				p.position = rc.room.feature.position
			"vault", "library":
				# Stand near (not on) the pedestal: the HUD side panel should name the item.
				var ped: Array = get_nodes_in_group("pedestals").filter(func(n: Node) -> bool: return rc.room.is_ancestor_of(n))
				if not ped.is_empty():
					p.position = ped[0].position + Vector2(0, 20)
			"arcade":
				var machines: Array = rc.room.entities.get_children().filter(func(n: Node) -> bool: return n.has_method("_play"))
				_check(machines.size() == 3, "arcade machines")
				for m in machines:
					for i in 5:
						m._play()
			"royal":
				_check(rc.room.info.get("extra_pedestals", []).size() == 2, "royal has two choices")
				var peds: Array = get_nodes_in_group("pedestals").filter(func(n: Node) -> bool: return n.extra_index >= 0)
				p.position = peds[0].position
			"challenge", "miniboss":
				_check(rc.room.enemies_alive > 0, type + " spawned enemies")
				_kill_all()
	elif phase == 1:
		if type in ["vault", "library"]:
			var hud: Node = rc.hud
			_check(hud.inspected != null and hud._inspect_title.text != "", type + ": side panel names the nearby item")
			print("smoke: %s inspect -> %s / %s" % [type, hud._inspect_title.text, hud._inspect_kind.text])
		match type:
			"sacrifice":
				_check(int(rc.room.info.get("sac_uses", 0)) == 0, "god mode blocks sacrifice damage")
				_console("god")
				p._iframes = 0.0
				rc.room.feature._armed = true
			"royal":
				var left: Array = rc.room.info["extra_pedestals"].filter(func(e: Dictionary) -> bool: return e["id"] != "")
				_check(left.is_empty(), "royal: taking one choice removes the other")
			"challenge":
				_kill_all()
	elif phase == 2:
		match type:
			"sacrifice":
				print("smoke: sacrifices used: %d" % int(rc.room.info.get("sac_uses", 0)))
				_check(int(rc.room.info.get("sac_uses", 0)) == 1, "sacrifice used once")
				_console("god")
			"challenge":
				_kill_all()
	elif phase == 3 and type == "challenge":
		_check(rc.room.is_cleared, "challenge cleared after all waves")
		var locked: Array = get_nodes_in_group("pedestals").filter(func(n: Node) -> bool: return n.locked)
		_check(locked.is_empty(), "challenge pedestal unlocked")


## Test shortcut: kill everything outright (champion traits like shields or splitting stripped
## first; champions have their own checks).
func _kill_all() -> void:
	for e in get_nodes_in_group("enemies"):
		_strip(e)
		e.take_hit(9999.0, Vector2.RIGHT, [])


func _strip(e: Node) -> void:
	e.champion = ""
	e.champion_cfg = {}
	e.shield_hits = 0
	e.untargetable = false


func _finish() -> void:
	if not descended:
		descended = true
		_queue_descent()
		return
	# Deal rooms on a real floor, plus a locked door.
	_console("goto 2")
	_console("deal royal")
	_check(rc.layout["deal"] != FloorGen.NONE, "deal room added")
	var shop: Vector2i = FloorGen.NONE
	for a in rc.layout["order"]:
		if rc.layout["rooms"][a]["type"] == "shop":
			shop = a
	if shop != FloorGen.NONE:
		var info: Dictionary = rc.layout["rooms"][shop]
		var locked: bool = info["doors"].values().has("locked")
		print("smoke: floor 2 shop door locked: %s" % locked)
		_check(locked, "floor 2 shop is locked")
	rc._start_room_test("hive_start")
	_bench()
	if failures.is_empty():
		print("smoke: OK")
		quit(0)
	else:
		print("smoke: FAIL %d check(s): %s" % [failures.size(), ", ".join(failures)])
		quit(1)


## 600 enemy bullets + 100 split/bouncing player shots, simulated for 60 physics steps.
func _bench() -> void:
	var ps: Node = rc.projectiles
	ps.clear()
	var r := RandomNumberGenerator.new()
	r.seed = 1
	for i in 600:
		ps.spawn_enemy_shot(Vector2(r.randf_range(10, 198), r.randf_range(10, 102)), Vector2.from_angle(r.randf() * TAU) * 6.0, Color.RED, 3.0, 99999.0)
	for i in 100:
		ps.spawn_player_shot(Vector2(104, 56), Vector2.from_angle(r.randf() * TAU), rc.player.spec)
	print("smoke: bench spawned %d (room %s, %.0fx%.0f)" % [ps.bullets.size(), rc.room.info["template"], rc.room.room_w, rc.room.room_h])
	var t0 := Time.get_ticks_usec()
	var alive := 0
	for i in 60:
		ps._physics_process(1.0 / 60.0)
		alive += ps.bullets.size()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 60.0
	print("smoke: bench avg %d live bullets, %.2f ms per physics step (budget 8 ms)" % [alive / 60, ms])
	_check(ms <= 8.0, "bullet budget")
	_check(alive / 60 >= 500, "bench kept 500+ bullets alive")
