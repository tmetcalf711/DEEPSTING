extends GutTest

const RNGScript := preload("res://scripts/autoload/rng.gd")


func test_same_seed_same_sequence() -> void:
	var a: Node = RNGScript.new()
	var b: Node = RNGScript.new()
	a.set_run_seed(12345)
	b.set_run_seed(12345)
	for i in 50:
		assert_eq(a.stream("map").randi(), b.stream("map").randi())
	a.free()
	b.free()


func test_streams_are_independent() -> void:
	var a: Node = RNGScript.new()
	var b: Node = RNGScript.new()
	a.set_run_seed(777)
	b.set_run_seed(777)
	# Consuming lots of "items" numbers on A must not change A's "map" stream.
	for i in 1000:
		a.stream("items").randf()
	for i in 20:
		assert_eq(a.stream("map").randi(), b.stream("map").randi())
	a.free()
	b.free()


func test_floors_differ_and_are_stable() -> void:
	var a: Node = RNGScript.new()
	a.set_run_seed(42)
	var f0: int = a.stream("map", 0).randi()
	var f1: int = a.stream("map", 1).randi()
	assert_ne(f0, f1)
	assert_eq(RNGScript.derive_seed(42, "map", 1), RNGScript.derive_seed(42, "map", 1))
	a.free()


func test_room_stream_order_independent() -> void:
	var a: Node = RNGScript.new()
	a.set_run_seed(99)
	var r3_first: int = a.room_stream("enemies", 3).randi()
	a.room_stream("enemies", 1).randi()
	var r3_again: int = a.room_stream("enemies", 3).randi()
	assert_eq(r3_first, r3_again)
	a.free()


func test_fnv_known_vector() -> void:
	# FNV-1a 64 of "a" is 0xaf63dc4c8601ec8c
	assert_eq(RNGScript.fnv1a64("a".to_utf8_buffer()), -5808556873153909620)


func test_seed_string_round_trip() -> void:
	for v in [0, 1, 0xFFFFFFFF, 0x12345678, 3141592653]:
		var s: String = RNGScript.seed_to_string(v)
		assert_eq(s.length(), 9, "format XXXX XXXX")
		assert_eq(RNGScript.string_to_seed(s), v)
		assert_eq(RNGScript.string_to_seed(s.to_lower().replace(" ", "")), v, "case/space-insensitive")


func test_seed_string_rejects_typos() -> void:
	var s: String = RNGScript.seed_to_string(0xCAFEBABE)
	var swapped := s.substr(1, 1) + s.substr(0, 1) + s.substr(2) if s[0] != s[1] else "ZZZZ ZZZZ"
	assert_eq(RNGScript.string_to_seed("ABC"), -1)
	assert_eq(RNGScript.string_to_seed("0OOO 1III"), -1, "ambiguous chars not in alphabet")
	assert_eq(RNGScript.string_to_seed(swapped), -1)


func test_weighted_index_distribution() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var counts := [0, 0, 0]
	for i in 6000:
		counts[RNGScript.weighted_index(r, [1.0, 2.0, 0.0])] += 1
	assert_eq(counts[2], 0, "zero weight never picked")
	assert_almost_eq(float(counts[1]) / float(counts[0]), 2.0, 0.25)
	assert_eq(RNGScript.weighted_index(r, [0.0, 0.0]), -1)


func test_shuffle_deterministic() -> void:
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 8
	r2.seed = 8
	var a := range(20)
	var b := range(20)
	RNGScript.shuffle(r1, a)
	RNGScript.shuffle(r2, b)
	assert_eq(a, b)
	assert_ne(a, range(20))
