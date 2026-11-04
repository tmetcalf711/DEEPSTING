extends GutTest
## Floor generation invariants (DESIGN.md §10.3).

const SEEDS := 200


func _cfg() -> Dictionary:
	return Content.get_entry("config", "floorgen")


func _gen(seed_value: int, depth: int = 1, opts: Dictionary = {}) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var o := {"required_specials": ["treasure"], "brood_cells": [2, 4], "brood_cell_room_chance": 0.5}
	o.merge(opts, true)
	return FloorGen.generate(depth, r, _cfg(), o)


func _reachable(layout: Dictionary) -> Dictionary:
	var rooms: Dictionary = layout["rooms"]
	var seen := {layout["start"]: true}
	var q: Array = [layout["start"]]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in rooms[c]["doors"]:
			var n: Vector2i = c + FloorGen.DIRS[d]
			assert_true(rooms.has(n), "door leads to a room")
			assert_true(rooms[n]["doors"].has(FloorGen.OPPOSITE[d]), "doors are symmetric")
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen


func test_all_rooms_reachable_and_doors_symmetric() -> void:
	for s in SEEDS:
		var l := _gen(s)
		assert_false(l.is_empty(), "seed %d generated" % s)
		assert_eq(_reachable(l).size(), l["rooms"].size(), "seed %d: every room reachable" % s)


func test_room_count_matches_target() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var normal := 0
		for c in l["rooms"]:
			if not l["rooms"][c]["type"] in ["secret", "super_secret"]:
				normal += 1
		assert_eq(normal, int(l["target"]), "seed %d" % s)


func test_boss_is_farthest_dead_end() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var rooms: Dictionary = l["rooms"]
		var boss: Vector2i = l["boss"]
		assert_eq(rooms[boss]["type"], "boss")
		var boss_doors := 0
		for d in rooms[boss]["doors"]:
			if rooms[boss]["doors"][d] == "normal":
				boss_doors += 1
		assert_eq(boss_doors, 1, "seed %d: boss is a dead end" % s)
		for c in rooms:
			var info: Dictionary = rooms[c]
			if info["type"] in ["secret", "super_secret"] or c == l["start"]:
				continue
			var n := 0
			for d in info["doors"]:
				if info["doors"][d] == "normal":
					n += 1
			if n == 1:
				assert_true(int(info["dist"]) <= int(rooms[boss]["dist"]), "seed %d: no dead end farther than boss" % s)


func test_specials_on_dead_ends() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var found_treasure := false
		for c in l["rooms"]:
			var info: Dictionary = l["rooms"][c]
			if info["type"] in ["treasure", "brood_cell"]:
				var n := 0
				for d in info["doors"]:
					if info["doors"][d] == "normal":
						n += 1
				assert_eq(n, 1, "seed %d: %s on a dead end" % [s, info["type"]])
				found_treasure = found_treasure or info["type"] == "treasure"
		assert_true(found_treasure, "seed %d has a treasure room" % s)


func test_secret_room_rules() -> void:
	var with_secret := 0
	for s in SEEDS:
		var l := _gen(s)
		var sc: Vector2i = l["secret"]
		if sc == FloorGen.NONE:
			continue
		with_secret += 1
		var nbrs: Array = []
		for d in FloorGen.DIR_ORDER:
			var n: Vector2i = sc + FloorGen.DIRS[d]
			if l["rooms"].has(n) and not l["rooms"][n]["type"] in ["secret", "super_secret"]:
				nbrs.append(n)
				assert_ne(l["rooms"][n]["type"], "boss", "seed %d: secret never borders boss" % s)
		assert_true(nbrs.size() >= 2, "seed %d: secret borders >= 2 (3 preferred)" % s)
		assert_eq(l["rooms"][sc]["doors"].size(), nbrs.size(), "secret has a cracked wall to each neighbor")
		for d in l["rooms"][sc]["doors"]:
			assert_eq(l["rooms"][sc]["doors"][d], "secret")
	assert_gt(with_secret, SEEDS * 0.9, "nearly every floor has a secret room")


func test_super_secret_rules() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var ss: Vector2i = l["super_secret"]
		if ss == FloorGen.NONE:
			continue
		var nbrs: Array = []
		for d in FloorGen.DIR_ORDER:
			var n: Vector2i = ss + FloorGen.DIRS[d]
			if l["rooms"].has(n) and not l["rooms"][n]["type"] in ["secret", "super_secret"]:
				nbrs.append(n)
		assert_eq(nbrs.size(), 1, "seed %d: super-secret borders exactly one room" % s)
		assert_ne(l["rooms"][nbrs[0]]["type"], "boss")
		if l["secret"] != FloorGen.NONE:
			var sc: Vector2i = l["secret"]
			assert_true(absi(ss.x - sc.x) + absi(ss.y - sc.y) > 1, "not adjacent to the secret room")


func test_brood_cells_placement() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var n := 0
		for c in l["rooms"]:
			var info: Dictionary = l["rooms"][c]
			if info["brood_cell"]:
				n += 1
				assert_eq(info["type"], "normal")
				assert_true(absi(c.x - l["boss"].x) + absi(c.y - l["boss"].y) > 1, "not boss-adjacent")
		assert_true(n <= 4, "seed %d: at most 4 brood cells" % s)


func test_same_seed_same_map() -> void:
	var templates := Content.all("rooms")
	for s in [1, 42, 9001, 0xCAFE]:
		var a := _gen(s)
		var b := _gen(s)
		var ra := RandomNumberGenerator.new()
		var rb := RandomNumberGenerator.new()
		ra.seed = s
		rb.seed = s
		FloorGen.assign_templates(a, templates, ra)
		FloorGen.assign_templates(b, templates, rb)
		assert_eq(FloorGen.structure_hash(a), FloorGen.structure_hash(b))
	assert_ne(FloorGen.structure_hash(_gen(1)), FloorGen.structure_hash(_gen(2)))


func test_every_room_gets_a_template() -> void:
	var templates := Content.all("rooms").filter(func(t: Dictionary) -> bool: return "hive" in t["stratum"])
	for s in 50:
		var l := _gen(s)
		var r := RandomNumberGenerator.new()
		r.seed = s
		FloorGen.assign_templates(l, templates, r)
		for c in l["rooms"]:
			var info: Dictionary = l["rooms"][c]
			assert_ne(info["template"], "", "seed %d: %s room has a template" % [s, info["type"]])
			var t: Dictionary = Content.get_entry("rooms", info["template"])
			assert_true(info["type"] in t.get("room_types", ["normal"]))
			if info["brood_cell"]:
				assert_true("brood_cell" in t["tags"])


func test_room_count_grows_with_depth() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	assert_true(FloorGen.target_room_count(6, r, _cfg()) > FloorGen.target_room_count(1, r, _cfg()))
	assert_true(FloorGen.target_room_count(50, r, _cfg()) <= 20, "capped")


func test_home_dir_points_toward_start() -> void:
	for s in 50:
		var l := _gen(s)
		for c in l["rooms"]:
			var info: Dictionary = l["rooms"][c]
			if c == l["start"]:
				assert_eq(info["home_dir"], "")
				continue
			var n: Vector2i = c + FloorGen.DIRS[info["home_dir"]]
			assert_eq(int(l["rooms"][n]["dist"]), int(info["dist"]) - 1, "seed %d" % s)
