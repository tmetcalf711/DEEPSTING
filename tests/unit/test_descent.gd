extends GutTest
## Milestone 4: floor plan + alternates, difficulty curve, champions, bosses per chapter, ending.

const RC := preload("res://scripts/run/run_controller.gd")


func test_floor_plan_shape() -> void:
	var plan: Array = RC.floor_plan()
	assert_eq(plan.size(), 8, "chapters 1-4, two floors each")
	assert_eq(plan[0]["main"], "hive", "floor 1 is always the Abandoned Hive")
	assert_false(plan[0].has("alt"))
	for i in plan.size():
		assert_eq(int(plan[i]["chapter"]), i / 2 + 1)
		assert_true(Content.has_entry("strata", plan[i]["main"]))
		if plan[i].has("alt"):
			assert_true(Content.has_entry("strata", plan[i]["alt"]))
	assert_true(RC.is_last_floor(7))
	assert_eq(plan[7]["final_boss"], "gilded_idol")
	assert_eq(plan[7]["ending"], "ending_1")
	assert_ne(tr("ENDING_1_TEXT"), "ENDING_1_TEXT")


func test_alt_strata_are_seeded_and_both_appear() -> void:
	var seen := {}
	for s in 120:
		for f in range(1, 8):
			var a: String = RC.stratum_for_floor(f, s)
			assert_eq(a, RC.stratum_for_floor(f, s), "same seed, same stratum")
			seen[a] = true
		assert_eq(RC.stratum_for_floor(0, s), "hive")
	for st in ["topsoil", "flooded_burrows", "landfill", "sewer_pipes", "bedrock", "collapsed_mine", "buried_ruins", "catacombs"]:
		assert_true(seen.has(st), st + " appears")


func test_difficulty_curve() -> void:
	assert_eq(Difficulty.hp_mult(1, false), 1.0)
	assert_gt(Difficulty.hp_mult(8, false), Difficulty.hp_mult(4, false))
	assert_lt(Difficulty.hp_mult(8, true), Difficulty.hp_mult(8, false), "bosses scale gentler")
	assert_eq(Difficulty.hit_damage(1), 1)
	assert_eq(Difficulty.hit_damage(6), 1)
	assert_eq(Difficulty.hit_damage(7), 2, "full hearts from chapter 4")
	assert_gt(Difficulty.champion_chance(8), Difficulty.champion_chance(1))
	assert_gt(Difficulty.champion_chance(1, "champions"), Difficulty.champion_chance(1), "Spore Bloom adds champions")
	assert_lte(Difficulty.champion_chance(99, "champions"), 0.4, "capped")
	assert_eq(Difficulty.max_template_difficulty(1), 1)
	assert_eq(Difficulty.max_template_difficulty(8), 3)


func test_champion_types_are_valid() -> void:
	var types: Dictionary = Content.get_entry("config", "champions")["types"]
	assert_gte(types.size(), 6)
	for k in types:
		assert_ne(Color.from_string(str(types[k]["tint"]), Color(0, 0, 0, 0)).a, 0.0, k + " tint parses")
		assert_gt(float(types[k]["weight"]), 0.0)


func test_three_bosses_per_chapter_and_every_stratum_has_one() -> void:
	var by_chapter := {}
	for b in Content.all("bosses"):
		assert_true(Content.has_entry("enemies", b.get("split_into", {}).get("enemy", "twin_grub")) or not b.has("split_into"))
		if b.get("final", false):
			continue
		by_chapter[int(b["chapter"])] = int(by_chapter.get(int(b["chapter"]), 0)) + 1
	for ch in [1, 2, 3, 4]:
		assert_gte(int(by_chapter.get(ch, 0)), 3, "chapter %d has 3+ bosses" % ch)
	for st in Content.ids("strata"):
		var n := Content.all("bosses").filter(func(b: Dictionary) -> bool: return st in b["strata"] and not b.get("final", false)).size()
		assert_gt(n, 0, st + " has a boss")
	assert_true(Content.get_entry("bosses", "gilded_idol").get("final", false))


func test_every_stratum_has_templates_for_every_room_kind_and_shape() -> void:
	for st in Content.ids("strata"):
		var ts := Content.all("rooms").filter(func(t: Dictionary) -> bool: return st in t["stratum"])
		for kind in ["start", "treasure", "boss", "secret", "normal"]:
			assert_true(ts.any(func(t: Dictionary) -> bool: return kind in t.get("room_types", ["normal"])), "%s has a %s room" % [st, kind])
		for shape in ["1x1", "2x1", "1x2", "2x2"]:
			assert_true(ts.any(func(t: Dictionary) -> bool: return t["shape"] == shape and "normal" in t.get("room_types", ["normal"])), "%s has a %s normal room" % [st, shape])
		var en: Array = Content.get_entry("strata", st)["enemies"]
		for e in en:
			assert_true(Content.has_entry("enemies", e), "%s lists real enemy %s" % [st, e])


func test_full_descent_generates_deterministically() -> void:
	var cfg: Dictionary = Content.get_entry("config", "floorgen")
	for f in 8:
		var st: String = RC.stratum_for_floor(f, 777)
		var hashes: Array = []
		for k in 2:
			var rng: Node = load("res://scripts/autoload/rng.gd").new()
			rng.set_run_seed(777)
			rng.set_floor(f)
			var l := FloorGen.generate(f + 1, rng.stream("map"), cfg, {"required_specials": ["treasure", "shop"]})
			var ts := Content.all("rooms").filter(func(t: Dictionary) -> bool: return st in t["stratum"] or "*" in t["stratum"])
			FloorGen.assign_templates(l, ts, rng.stream("rooms"), Difficulty.max_template_difficulty(f + 1))
			FloorContents.fill(l, {"floor_index": f, "stratum": Content.get_entry("strata", st), "pool": ItemPool.from_content(),
				"items_rng": rng.stream("items"), "rooms_rng": rng.stream("rooms"), "cfg": cfg,
				"final_boss": str(RC.floor_plan()[f].get("final_boss", ""))})
			hashes.append(var_to_str(l["rooms"]))
			rng.free()
			if f == 7:
				assert_eq(l["rooms"][l["boss"]]["boss_id"], "gilded_idol", "last floor's boss is the ending boss")
		assert_eq(hashes[0], hashes[1], "floor %d (%s) reproduces" % [f + 1, st])


func test_save_migrates_to_v3() -> void:
	var m: Dictionary = load("res://scripts/autoload/meta_save.gd").migrate_meta({"version": 2, "pulp": 5})
	assert_eq(m["version"], 3)
	assert_eq(m["endings"], {})
	assert_eq(m["pulp"], 5)


func test_boss_pick_avoids_bosses_already_met() -> void:
	var cfg: Dictionary = Content.get_entry("config", "floorgen")
	for s in 20:
		var r := RandomNumberGenerator.new()
		r.seed = s
		var l := FloorGen.generate(5, r, cfg, {"required_specials": ["treasure", "shop"]})
		FloorContents.fill(l, {"floor_index": 4, "stratum": Content.get_entry("strata", "bedrock"), "pool": ItemPool.from_content(),
			"items_rng": RandomNumberGenerator.new(), "rooms_rng": r, "cfg": cfg, "bosses_met": ["geode_golem", "crystal_mantis"]})
		assert_eq(l["rooms"][l["boss"]]["boss_id"], "old_drill", "the one bedrock boss not met yet")
