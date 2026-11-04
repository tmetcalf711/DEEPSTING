extends GutTest


func _pool(unlocked: Callable = func(_id: String) -> bool: return true) -> ItemPool:
	var pools := {
		"a": {"id": "a", "fallback": "b", "entries": [{"id": "x", "weight": 3.0}, {"id": "y", "weight": 1.0}]},
		"b": {"id": "b", "fallback": "", "entries": [{"id": "y", "weight": 1.0}, {"id": "z", "weight": 1.0}]},
	}
	var items := {"x": {"id": "x"}, "y": {"id": "y"}, "z": {"id": "z"}, "pocket_lint": {"id": "pocket_lint"}}
	return ItemPool.new(pools, items, unlocked)


func test_weighting() -> void:
	var counts := {"x": 0, "y": 0}
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for i in 4000:
		var p := _pool()
		counts[p.roll("a", r)] += 1
	assert_almost_eq(float(counts["x"]) / float(counts["y"]), 3.0, 0.4)


func test_seen_items_removed_from_all_pools() -> void:
	var p := _pool()
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var got := [p.roll("a", r), p.roll("a", r)]
	got.sort()
	assert_eq(got, ["x", "y"])
	# "y" is gone from pool b too, so b can only give z.
	assert_eq(p.roll("b", r), "z")


func test_fallback_chain_then_lint() -> void:
	var p := _pool()
	var r := RandomNumberGenerator.new()
	var all := []
	for i in 4:
		all.append(p.roll("a", r))
	assert_eq(all.slice(0, 3).duplicate().size(), 3)
	assert_true("z" in all, "a exhausted -> falls back to b")
	assert_eq(all[3], ItemPool.FALLBACK_ITEM)


func test_locked_items_excluded() -> void:
	var p := _pool(func(id: String) -> bool: return id != "x")
	var r := RandomNumberGenerator.new()
	for i in 20:
		var q := _pool(func(id: String) -> bool: return id != "x")
		assert_ne(q.roll("a", r), "x")
	assert_eq(p.candidates("a").size(), 1)


func test_real_pools_roll_valid_items() -> void:
	var p := ItemPool.from_content()
	var r := RandomNumberGenerator.new()
	for pid in ["dig_site", "boss", "secret"]:
		var id := p.roll(pid, r)
		assert_true(Content.has_entry("items", id), "%s gave %s" % [pid, id])
