extends GutTest
## Health, consumables and the floor stash.

var rs: Node


func before_each() -> void:
	rs = load("res://scripts/autoload/run_state.gd").new()
	rs.reset()


func after_each() -> void:
	rs.free()


func test_shields_absorb_first_last_in_first_out() -> void:
	rs.hearts_max = 6
	rs.hearts = 6
	rs.add_shield("chitin", 2)
	rs.add_shield("toxic", 2)
	assert_eq(rs.take_damage(1), 1, "toxic half breaks first")
	assert_eq(rs.take_damage(1), 1)
	assert_eq(rs.take_damage(2), 0, "then chitin")
	assert_eq(rs.hearts, 6, "hearts untouched while shields last")
	rs.take_damage(1)
	assert_eq(rs.hearts, 5)


func test_death() -> void:
	rs.hearts_max = 2
	rs.hearts = 2
	rs.add_shield("chitin", 1)
	rs.take_damage(2)
	assert_false(rs.is_dead())
	rs.take_damage(1)
	assert_true(rs.is_dead())


func test_heal_capped() -> void:
	rs.hearts_max = 6
	rs.hearts = 3
	assert_eq(rs.heal(5), 3)
	assert_false(rs.can_heal())


func test_total_heart_cap() -> void:
	rs.hearts_max = 20
	rs.hearts = 20
	assert_eq(rs.add_shield("chitin", 10), 4, "12-heart cap = 24 halves")
	assert_false(rs.can_add_shield())
	rs.add_containers(1)
	assert_eq(rs.hearts_max, 22, "container replaces a shield heart at the cap")
	assert_eq(rs.shields.size(), 2)


func test_stats_formula() -> void:
	rs.stat_mods.assign([{"stat": "damage", "add": 1.0}, {"stat": "damage", "mult": 2.0}, {"stat": "fire_rate", "add": -10.0}])
	assert_almost_eq(rs.stat("damage"), (3.5 + 1.0) * 2.0, 0.001)
	assert_eq(rs.stat("fire_rate"), 0.5, "clamped to floor")


func test_consumable_caps() -> void:
	rs.mana = 0
	for i in 150:
		rs.mana = clampi(rs.mana + 1, 0, rs.MAX_CONSUMABLE)
	assert_eq(rs.mana, 99)


func test_stash_lose() -> void:
	rs.floor_stash = {"wood_pulp": 5, "amber": 3}
	assert_eq(rs.stash_total(), 8)
	assert_eq(rs.stash_pulp_value(), 5 * 1 + 3 * 2, "pulper values from data")
	assert_eq(rs.lose_stash(), 11)
	assert_eq(rs.stash_total(), 0)


func test_serialization_round_trip() -> void:
	rs.hearts_max = 8
	rs.hearts = 5
	rs.shields.assign(["chitin", "toxic"])
	rs.mana = 13
	rs.royal_jelly = 2
	rs.items.assign(["raw_geode"])
	rs.floor_stash = {"nectar": 4}
	var d: Dictionary = rs.to_dict()
	var other: Node = load("res://scripts/autoload/run_state.gd").new()
	other.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(other.hearts, 5)
	assert_eq(other.shields, rs.shields)
	assert_eq(other.items, rs.items)
	assert_eq(int(other.floor_stash["nectar"]), 4)
	other.free()
