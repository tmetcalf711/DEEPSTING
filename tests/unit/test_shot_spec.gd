extends GutTest
## Projectile-modifier stacking (DESIGN.md §6.5): generic, order-independent composition.

const STATS := {"damage": 3.5, "shot_speed": 1.0, "range": 150.0}


func _m(mod: String, params: Dictionary, src: String) -> Dictionary:
	return {"modifier": mod, "params": params, "source": src}


func test_base_spec() -> void:
	var s := ShotSpec.build(STATS, [])
	assert_eq(s["damage"], 3.5)
	assert_eq(s["pierce"], 0)
	assert_eq(s["speed"], ShotSpec.SPEED_UNIT)


func test_order_independent() -> void:
	var mods := [_m("split", {"count": 3, "damage_mult": 0.4}, "geode"), _m("pierce", {"count": -1}, "obsidian"),
		_m("bounce", {"count": 2}, "cap"), _m("homing", {"strength": 1.2}, "lens"), _m("size", {"mult": 1.5}, "big")]
	var a := ShotSpec.build(STATS, mods)
	var rev := mods.duplicate()
	rev.reverse()
	var b := ShotSpec.build(STATS, rev)
	assert_eq(a, b)


func test_stacking_rules() -> void:
	var s := ShotSpec.build(STATS, [_m("pierce", {"count": 1}, "a"), _m("pierce", {"count": 2}, "b"),
		_m("bounce", {"count": 2}, "c"), _m("bounce", {"count": 1}, "d"),
		_m("homing", {"strength": 3.0}, "e"), _m("homing", {"strength": 3.0}, "f")])
	assert_eq(s["pierce"], 3, "finite pierce adds")
	assert_eq(s["bounce"], 3, "bounce adds")
	assert_eq(s["homing"], ShotSpec.HOMING_CAP, "homing capped")
	var inf := ShotSpec.build(STATS, [_m("pierce", {"count": 2}, "a"), _m("pierce", {"count": -1}, "b")])
	assert_eq(inf["pierce"], -1, "infinite pierce dominates")


func test_split_children_inherit_all_but_split() -> void:
	var s := ShotSpec.build(STATS, [_m("split", {"count": 3, "damage_mult": 0.4}, "g"), _m("pierce", {"count": -1}, "o"), _m("bounce", {"count": 2}, "c")])
	var c := ShotSpec.child_of(s)
	assert_almost_eq(float(c["damage"]), 3.5 * 0.4, 0.001)
	assert_eq(c["pierce"], -1)
	assert_eq(c["bounce"], 2)
	assert_eq(c["split_count"], 0, "depth-1 split does not recurse")


func test_elements_union_and_size() -> void:
	var s := ShotSpec.build(STATS, [_m("element", {"element": "poison"}, "a"), _m("element", {"element": "poison"}, "b"),
		_m("element", {"element": "slow"}, "c"), _m("size", {"mult": 2.0, "damage_mult": 1.5}, "d")])
	assert_eq(s["elements"].size(), 2)
	assert_almost_eq(float(s["radius"]), ShotSpec.BASE_RADIUS * 2.0, 0.001)
	assert_almost_eq(float(s["damage"]), 3.5 * 1.5, 0.001)


func test_every_item_projectile_mod_combo_builds() -> void:
	# All pairwise combinations of the shipped items' projectile mods compose without errors.
	var mods: Array = []
	for item in Content.all("items"):
		for e in item["effects"]:
			if e["type"] == "projectile_mod":
				mods.append(_m(e["modifier"], e.get("params", {}), item["id"]))
	for i in mods.size():
		for j in mods.size():
			var s := ShotSpec.build(STATS, [mods[i], mods[j]])
			assert_true(float(s["damage"]) > 0.0)
	var all := ShotSpec.build(STATS, mods)
	assert_true(all["pierce"] == -1 and all["bounce"] > 0 and all["split_count"] > 0 and all["homing"] > 0.0)


func test_multishot_stacks_and_caps() -> void:
	var s := ShotSpec.build(STATS, [_m("multishot", {"count": 2, "spread": 0.1}, "a"), _m("multishot", {"count": 3, "spread": 0.5}, "b")])
	assert_eq(s["multishot"], 4, "2 + 3 - 1 extra shots")
	assert_almost_eq(float(s["spread"]), 0.5, 0.001, "widest spread wins")
	var many: Array = []
	for i in 6:
		many.append(_m("multishot", {"count": 3}, "x%d" % i))
	assert_eq(ShotSpec.build(STATS, many)["multishot"], ShotSpec.MAX_MULTISHOT)


func test_boomerang_wave_knockback() -> void:
	var s := ShotSpec.build(STATS, [_m("boomerang", {}, "a"), _m("wave", {"amp": 7, "freq": 2.5}, "b"), _m("knockback", {"mult": 2.0}, "c"), _m("knockback", {"mult": 1.5}, "d")])
	assert_true(s["boomerang"])
	assert_eq(s["wave_amp"], 7.0)
	assert_almost_eq(float(s["knockback"]), 3.0, 0.001, "knockback multiplies")
	var c := ShotSpec.child_of(ShotSpec.build(STATS, [_m("boomerang", {}, "a"), _m("split", {"count": 2}, "b"), _m("multishot", {"count": 2}, "c")]))
	assert_false(c["boomerang"], "split children don't boomerang")
	assert_eq(c["multishot"], 1)


func test_procs_sorted_and_carried() -> void:
	var procs := [{"kind": "stun", "chance": 0.1, "source": "z"}, {"kind": "crit", "chance": 0.1, "source": "a"}]
	var s := ShotSpec.build(STATS, [], [], procs)
	assert_eq(s["procs"].size(), 2)
	assert_eq(s["procs"][0]["kind"], "crit", "procs ordered deterministically")
	var rev := procs.duplicate()
	rev.reverse()
	assert_eq(ShotSpec.build(STATS, [], [], rev)["procs"], s["procs"])
