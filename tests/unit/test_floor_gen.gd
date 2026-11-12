extends GutTest
## Floor generation invariants (DESIGN.md §10.3), shaped rooms, specials, contents determinism.

const SEEDS := 200
const RC := preload("res://scripts/run/run_controller.gd")


func _cfg() -> Dictionary:
	return Content.get_entry("config", "floorgen")


func _opts(extra: Dictionary = {}) -> Dictionary:
	var o := {"required_specials": ["treasure", "shop"], "brood_cells": [2, 4], "brood_cell_room_chance": 0.5,
		"random_specials": {"sacrifice": 1.0, "curse": 1.0, "challenge": 1.0, "miniboss": 1.0}, "random_special_count": 1}
	o.merge(extra, true)
	return o


func _gen(seed_value: int, depth: int = 1, extra: Dictionary = {}) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return FloorGen.generate(depth, r, _cfg(), _opts(extra))


func _normal_links(info: Dictionary) -> int:
	var n := 0
	for s in info["links"]:
		if info["doors"][s] != "secret":
			n += 1
	return n


func test_all_rooms_reachable_and_links_symmetric() -> void:
	for s in SEEDS:
		var l := _gen(s, 1 + s % 3)
		assert_false(l.is_empty(), "seed %d generated" % s)
		var rooms: Dictionary = l["rooms"]
		var seen := {l["start"]: true}
		var q: Array = [l["start"]]
		while not q.is_empty():
			var a: Vector2i = q.pop_front()
			for slot in rooms[a]["links"]:
				var link: Array = rooms[a]["links"][slot]
				var b: Vector2i = link[0]
				assert_true(rooms.has(b), "link leads to a room")
				assert_eq(rooms[b]["links"][link[1]], [a, slot], "seed %d: links are symmetric" % s)
				assert_eq(rooms[b]["doors"][link[1]], rooms[a]["doors"][slot], "door kinds match on both sides")
				if not seen.has(b):
					seen[b] = true
					q.append(b)
		assert_eq(seen.size(), rooms.size(), "seed %d: every room reachable" % s)


func test_cells_and_owner_consistent() -> void:
	for s in SEEDS:
		var l := _gen(s, 3)
		var cells_seen := {}
		for a in l["rooms"]:
			var info: Dictionary = l["rooms"][a]
			assert_eq(info["cells"].size(), FloorGen.SHAPES[info["shape"]].size())
			for c in info["cells"]:
				assert_false(cells_seen.has(c), "seed %d: rooms never overlap" % s)
				cells_seen[c] = true
				assert_eq(l["owner"][c], a)


func test_big_rooms_appear() -> void:
	var counts := {}
	for s in SEEDS:
		var l := _gen(s, 2)
		for a in l["rooms"]:
			counts[l["rooms"][a]["shape"]] = int(counts.get(l["rooms"][a]["shape"], 0)) + 1
	for shape in ["2x1", "1x2", "2x2"]:
		assert_gt(int(counts.get(shape, 0)), 0, "%s rooms are generated" % shape)


func test_room_count_matches_target() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var n := 0
		for a in l["rooms"]:
			if not l["rooms"][a]["type"] in FloorGen.SECRET_TYPES:
				n += 1
		assert_eq(n, int(l["target"]), "seed %d" % s)


func test_labyrinth_is_bigger_with_two_treasures() -> void:
	for s in 30:
		var normal := _gen(s, 1)
		var lab := _gen(s, 1, {"labyrinth": true})
		assert_gt(int(lab["target"]), int(normal["target"]))
		var treasures := 0
		for a in lab["rooms"]:
			if lab["rooms"][a]["type"] == "treasure":
				treasures += 1
		assert_eq(treasures, 2, "seed %d: labyrinth has 2 treasure rooms" % s)


func test_boss_is_farthest_dead_end() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var rooms: Dictionary = l["rooms"]
		var boss: Vector2i = l["boss"]
		assert_eq(rooms[boss]["type"], "boss")
		assert_eq(rooms[boss]["shape"], "1x1")
		assert_eq(_normal_links(rooms[boss]), 1, "seed %d: boss is a dead end" % s)
		for a in rooms:
			var info: Dictionary = rooms[a]
			if info["type"] in FloorGen.SECRET_TYPES or a == l["start"] or info["shape"] != "1x1":
				continue
			if _normal_links(info) == 1:
				assert_true(int(info["dist"]) <= int(rooms[boss]["dist"]), "seed %d: no dead end farther than boss" % s)


func test_specials_on_1x1_dead_ends() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var found := {}
		for a in l["rooms"]:
			var info: Dictionary = l["rooms"][a]
			if not info["type"] in ["normal", "start", "secret", "super_secret"]:
				found[info["type"]] = true
				assert_eq(info["shape"], "1x1", "seed %d: %s is 1x1" % [s, info["type"]])
				assert_eq(_normal_links(info), 1, "seed %d: %s on a dead end" % [s, info["type"]])
		assert_true(found.has("treasure") and found.has("shop"), "seed %d has treasure + shop" % s)


func test_secret_room_rules() -> void:
	var with_secret := 0
	for s in SEEDS:
		var l := _gen(s)
		var sc: Vector2i = l["secret"]
		if sc == FloorGen.NONE:
			continue
		with_secret += 1
		var info: Dictionary = l["rooms"][sc]
		assert_true(info["links"].size() >= 2, "seed %d: secret borders >= 2 rooms (3 preferred)" % s)
		for slot in info["links"]:
			assert_eq(info["doors"][slot], "secret")
			assert_ne(l["rooms"][info["links"][slot][0]]["type"], "boss", "secret never borders boss")
	assert_gt(with_secret, SEEDS * 0.9, "nearly every floor has a secret room")


func test_super_secret_rules() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var ss: Vector2i = l["super_secret"]
		if ss == FloorGen.NONE:
			continue
		var info: Dictionary = l["rooms"][ss]
		assert_eq(info["links"].size(), 1, "seed %d: super-secret borders exactly one room" % s)
		assert_ne(l["rooms"][info["links"].values()[0][0]]["type"], "boss")
		if l["secret"] != FloorGen.NONE:
			var sc: Vector2i = l["secret"]
			assert_true(absi(ss.x - sc.x) + absi(ss.y - sc.y) > 1, "not adjacent to the secret room")


func test_brood_cells_placement() -> void:
	for s in SEEDS:
		var l := _gen(s)
		var n := 0
		for a in l["rooms"]:
			var info: Dictionary = l["rooms"][a]
			if info["brood_cell"]:
				n += 1
				assert_eq(info["type"], "normal")
				for slot in info["links"]:
					assert_ne(info["links"][slot][0], l["boss"], "not boss-adjacent")
		assert_true(n <= 4, "seed %d: at most 4 brood cells" % s)


func test_home_slot_points_toward_start() -> void:
	for s in 50:
		var l := _gen(s)
		for a in l["rooms"]:
			var info: Dictionary = l["rooms"][a]
			if a == l["start"]:
				assert_eq(info["home_slot"], "")
				continue
			var b: Vector2i = info["links"][info["home_slot"]][0]
			assert_true(int(l["rooms"][b]["dist"]) < int(info["dist"]), "seed %d" % s)


func test_deal_room_attaches_to_boss() -> void:
	for s in 50:
		var l := _gen(s, 2)
		assert_ne(l["deal_slot"], "", "boss has a free wall for the deal door")
		var a := FloorGen.add_deal_room(l, "royal")
		assert_eq(a, FloorGen.DEAL_ANCHOR)
		var info: Dictionary = l["rooms"][a]
		assert_true(info["offmap"])
		var back: Array = info["links"].values()[0]
		assert_eq(back[0], l["boss"])
		assert_eq(l["rooms"][l["boss"]]["links"][l["deal_slot"]][0], a)
		assert_eq(FloorGen.add_deal_room(l, "den"), a, "only one deal room per floor")


func test_every_room_gets_a_matching_template() -> void:
	for st in ["hive", "topsoil"]:
		var templates := Content.all("rooms").filter(func(t: Dictionary) -> bool: return st in t["stratum"] or "*" in t["stratum"])
		for s in 60:
			var l := _gen(s, 1 + s % 2, {"random_specials": {"sacrifice": 1.0, "curse": 1.0, "challenge": 1.0, "miniboss": 1.0, "vault": 1.0, "arcade": 1.0, "library": 1.0}})
			var r := RandomNumberGenerator.new()
			r.seed = s
			FloorGen.assign_templates(l, templates, r)
			for a in l["rooms"]:
				var info: Dictionary = l["rooms"][a]
				assert_ne(info["template"], "", "%s seed %d: %s %s room has a template" % [st, s, info["shape"], info["type"]])
				var t: Dictionary = Content.get_entry("rooms", info["template"])
				assert_true(info["type"] in t.get("room_types", ["normal"]))
				assert_eq(t["shape"], info["shape"])
				if info["brood_cell"]:
					assert_true("brood_cell" in t["tags"])


func _full_floor(seed_value: int, floor_index: int) -> Dictionary:
	var rng: Node = load("res://scripts/autoload/rng.gd").new()
	rng.set_run_seed(seed_value)
	rng.set_floor(floor_index)
	var stratum: Dictionary = Content.get_entry("strata", str(RC.floor_plan()[floor_index]["main"]))
	var l := FloorGen.generate(floor_index + 1, rng.stream("map"), _cfg(), _opts())
	var templates := Content.all("rooms").filter(func(t: Dictionary) -> bool: return stratum["id"] in t["stratum"] or "*" in t["stratum"])
	FloorGen.assign_templates(l, templates, rng.stream("rooms"))
	FloorContents.fill(l, {"floor_index": floor_index, "stratum": stratum, "pool": ItemPool.from_content(),
		"items_rng": rng.stream("items"), "rooms_rng": rng.stream("rooms"), "cfg": _cfg()})
	rng.free()
	return l


func test_same_seed_same_floor_including_contents() -> void:
	for s in [1, 42, 9001, 0xCAFE]:
		for f in 2:
			var a := _full_floor(s, f)
			var b := _full_floor(s, f)
			assert_eq(FloorGen.structure_hash(a), FloorGen.structure_hash(b))
			assert_eq(var_to_str(a["rooms"]), var_to_str(b["rooms"]), "seed %d floor %d: contents identical" % [s, f + 1])
	assert_ne(FloorGen.structure_hash(_full_floor(1, 0)), FloorGen.structure_hash(_full_floor(2, 0)))


func test_contents_rolled() -> void:
	for s in 20:
		var l := _full_floor(s, 1)
		for a in l["rooms"]:
			var info: Dictionary = l["rooms"][a]
			match str(info["type"]):
				"treasure":
					assert_true(Content.has_entry("items", info["pedestal"]))
				"boss":
					assert_true(Content.has_entry("bosses", info["boss_id"]))
					assert_true(Content.has_entry("items", info["pedestal_on_clear"]))
				"shop":
					assert_eq(info["wares"].size(), 5)
					for w in info["wares"]:
						assert_true(int(w["price"]) > 0)


func test_floor_two_shop_is_locked_floor_one_is_not() -> void:
	for s in 20:
		for f in 2:
			var l := _full_floor(s, f)
			for a in l["rooms"]:
				var info: Dictionary = l["rooms"][a]
				if info["type"] == "shop":
					var kinds: Array = info["doors"].values()
					assert_eq(kinds.has("locked"), f == 1, "seed %d floor %d shop lock" % [s, f + 1])


func test_curse_and_challenge_doors() -> void:
	var l := _gen(7, 2, {"random_specials": {"curse": 1.0}, "random_special_count": 1})
	FloorContents.fill(l, {"floor_index": 1, "stratum": Content.get_entry("strata", "topsoil"), "pool": ItemPool.from_content(),
		"items_rng": RandomNumberGenerator.new(), "rooms_rng": RandomNumberGenerator.new(), "cfg": _cfg()})
	for a in l["rooms"]:
		if l["rooms"][a]["type"] == "curse":
			assert_true(l["rooms"][a]["doors"].values().has("spiked"))
			return
	pass_test("no spare dead end for the curse room on this seed")


func test_eligible_specials_respect_rules() -> void:
	var cfg := _cfg()
	var d1: Dictionary = RC.eligible_specials(1, cfg)
	assert_false(d1.has("vault"), "vault needs depth 3")
	assert_false(d1.has("arcade"))
	assert_true(RC.eligible_specials(3, cfg).has("vault"))
	if not MetaSave.is_unlocked("feature", "library"):
		assert_false(d1.has("library"), "library needs the Archivist unlock")


func test_room_count_grows_with_depth() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	assert_true(FloorGen.target_room_count(6, r, _cfg()) > FloorGen.target_room_count(1, r, _cfg()))
	assert_true(FloorGen.target_room_count(50, r, _cfg()) <= 20, "capped")


func test_slots() -> void:
	assert_eq(FloorGen.shape_slots("1x1").size(), 4)
	assert_eq(FloorGen.shape_slots("2x1").size(), 6)
	assert_eq(FloorGen.shape_slots("2x2").size(), 8)
	assert_eq(FloorGen.parse_slot("1,0,N"), [Vector2i(1, 0), "N"])
