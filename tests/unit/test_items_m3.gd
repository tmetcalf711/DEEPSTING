extends GutTest
## Milestone 3: content volume, translations, effect hooks, consumables, radiation, mutations.

var host: EffectHost
var dummy: Node2D


func before_each() -> void:
	RunState.reset()
	RunState.seed_value = 12345
	RNG.set_run_seed(12345)
	dummy = Node2D.new()
	add_child_autofree(dummy)
	host = EffectHost.new(dummy)


func test_content_volume() -> void:
	assert_gte(Content.count("items"), 60, "60+ items")
	assert_gte(Content.count("trinkets"), 15)
	assert_gte(Content.count("fossils"), 10)
	assert_gte(Content.count("fluids"), 12)
	assert_gte(Content.count("mutations"), 12)


func test_every_name_and_description_is_translated() -> void:
	for cat in ["items", "trinkets", "fossils", "fluids", "mutations", "enemies", "bosses", "curses"]:
		for e in Content.all(cat):
			for k in ["name_key", "desc_key"]:
				if e.has(k):
					assert_ne(tr(e[k]), e[k], "%s %s %s has text" % [cat, e["id"], k])


func test_every_quality_tier_exists() -> void:
	var tiers := {}
	for e in Content.all("items"):
		tiers[int(e["quality"])] = true
	for q in 5:
		assert_true(tiers.has(q), "quality %d used" % q)


func test_triggers_fire_generically() -> void:
	RunState.triggers.append({"event": "room_clear", "chance": 1.0, "action": {"kind": "mana", "amount": 3}})
	RunState.triggers.append({"event": "kill", "chance": 1.0, "action": {"kind": "mana", "amount": 100}})
	RunState.triggers.append({"event": "room_clear", "chance": 0.0, "action": {"kind": "mana", "amount": 50}})
	host.fire_event("room_clear", Vector2.ZERO)
	assert_eq(RunState.mana, 3, "only matching, successful triggers ran")


func test_rebuild_collects_from_items_trinket_and_mutations() -> void:
	RunState.items.assign(["coin_purse", "static_wire"])
	RunState.trinket = "toothpick"
	RunState.mutations.assign(["glow_glands"])
	host.rebuild()
	assert_eq(RunState.triggers.size(), 1, "coin purse trigger")
	assert_eq(RunState.procs.size(), 1, "static wire proc")
	assert_eq(RunState.auras.size(), 1, "glow glands aura")
	assert_almost_eq(RunState.stat("fire_rate"), 2.7 + 0.25, 0.001, "knick-knack stat applies")


func test_trinket_swap_returns_previous() -> void:
	assert_eq(host.set_trinket("paperclip"), "")
	assert_eq(host.set_trinket("toothpick"), "paperclip")
	assert_eq(RunState.trinket, "toothpick")
	assert_almost_eq(RunState.stat("luck"), 0.0, 0.001, "old knick-knack's effect is gone")


func test_fluid_map_deterministic_and_complete() -> void:
	EffectHost.ensure_fluid_map()
	var a: Dictionary = RunState.fluid_map.duplicate()
	var colors: Array = Content.get_entry("config", "fluids")["colors"]
	assert_eq(a.size(), colors.size())
	for c in colors:
		assert_true(Content.has_entry("fluids", a[c["id"]]))
	RunState.fluid_map = {}
	EffectHost.ensure_fluid_map()
	assert_eq(RunState.fluid_map, a, "same seed, same colors")
	RunState.fluid_map = {}
	RNG.set_run_seed(999)
	EffectHost.ensure_fluid_map()
	assert_ne(RunState.fluid_map, a, "different seed, different mapping")


func test_drinking_identifies_and_applies_permanently() -> void:
	EffectHost.ensure_fluid_map()
	var color := ""
	for c in RunState.fluid_map:
		if RunState.fluid_map[c] == "damage_up":
			color = c
	if color == "":
		pass_test("damage_up not mapped on this seed")
		return
	assert_ne(EffectHost.fluid_display_name(color), tr("FLUID_DAMAGE_UP_NAME"), "unknown before drinking")
	RunState.consumable = {"kind": "fluid", "id": color}
	host.use_consumable()
	assert_true(RunState.consumable.is_empty())
	assert_eq(EffectHost.fluid_display_name(color), tr("FLUID_DAMAGE_UP_NAME"), "identified after drinking")
	assert_almost_eq(RunState.stat("damage"), 3.9, 0.001)
	host.rebuild()
	assert_almost_eq(RunState.stat("damage"), 3.9, 0.001, "perma stat survives rebuilds")


func test_room_buff_ends_on_room_change() -> void:
	RunState.consumable = {"kind": "fossil", "id": "shark_tooth"}
	host.use_consumable()
	assert_almost_eq(RunState.stat("damage"), 6.0, 0.001)
	RunState.clear_room_effects()
	assert_almost_eq(RunState.stat("damage"), 3.5, 0.001)


func test_radiation_thresholds_grow() -> void:
	assert_false(RunState.mutation_ready())
	RunState.add_radiation(65)
	assert_true(RunState.mutation_ready())
	RunState.consume_mutation()
	assert_almost_eq(RunState.radiation, 5.0, 0.001)
	assert_eq(RunState.radiation_threshold, 90)
	RunState.add_radiation(85)
	RunState.consume_mutation()
	assert_eq(RunState.radiation_threshold, 120)


func test_mutation_offers_are_distinct_and_seeded() -> void:
	var r1 := RandomNumberGenerator.new()
	r1.seed = 4
	var r2 := RandomNumberGenerator.new()
	r2.seed = 4
	var a: Array = RunController.roll_mutations(3, r1)
	assert_eq(a.size(), 3)
	assert_eq(a, RunController.roll_mutations(3, r2))
	var uniq := {}
	for m in a:
		uniq[m] = true
	assert_eq(uniq.size(), 3)


func test_synergy_detection_is_generic() -> void:
	assert_false(EffectHost.is_synergy("raw_geode"), "nothing owned yet")
	RunState.items.assign(["obsidian_shard"])  # pierce
	assert_true(EffectHost.is_synergy("raw_geode"), "split + pierce")
	assert_false(EffectHost.is_synergy("bent_fork"), "a stat item never synergizes")
	RunState.items.assign(["darning_needle"])  # multishot
	assert_true(EffectHost.is_synergy("static_wire"), "chain + multishot")


func test_pickup_kinds_have_payload_rolls() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	assert_true(Content.has_entry("fossils", load("res://scripts/actors/pickup.gd").roll_payload("fossil", r)))
	var color: String = load("res://scripts/actors/pickup.gd").roll_payload("fluid", r)
	assert_true(Content.get_entry("config", "fluids")["colors"].any(func(c: Dictionary) -> bool: return c["id"] == color))


func test_trinket_pool_never_repeats() -> void:
	var p := ItemPool.trinkets_from_content()
	var r := RandomNumberGenerator.new()
	var seen := {}
	for i in Content.count("trinkets"):
		var id := p.roll("trinkets", r)
		assert_false(seen.has(id))
		seen[id] = true
	assert_eq(p.roll("trinkets", r), "", "exhausted pool gives nothing")
