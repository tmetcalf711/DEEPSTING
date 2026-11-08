extends GutTest

var ed: Control


func before_each() -> void:
	ed = load("res://tools/room_editor.tscn").instantiate()
	add_child_autofree(ed)


func test_load_round_trip() -> void:
	for id in ["hive_n01", "hive_x02", "topsoil_w02", "special_shop"]:
		ed._load(id)
		var t: Dictionary = ed.to_template()
		var src: Dictionary = Content.get_entry("rooms", id)
		assert_eq(t["grid"], src["grid"], id + " grid")
		assert_eq(t["shape"], src["shape"])
		assert_eq(t["spawns"], src["spawns"])
		assert_eq(Content.validate("rooms", t), PackedStringArray(), id + " exports valid JSON")


func test_resize_keeps_content() -> void:
	ed._new()
	ed.grid[2][3] = "R"
	ed._resize("2x2")
	assert_eq(ed.grid.size(), 14)
	assert_eq(ed.grid[0].size(), 26)
	assert_eq(ed.grid[2][3], "R")


func test_painting_and_lane_validation() -> void:
	ed._new()
	ed._painting = 1
	ed.brush = "R"
	ed._apply(Vector2i(6, 1))  # north door lane
	var problems: PackedStringArray = Content.validate("rooms", ed.to_template())
	assert_eq(problems.size(), 1, "blocked lane is reported: %s" % [problems])
	ed._painting = 2
	ed._apply(Vector2i(6, 1))
	ed._painting = 1
	ed.brush = "enemy"
	ed.enemy_choice = "twin_grub"
	ed._apply(Vector2i(3, 3))
	assert_eq(ed.spawns, [{"enemy": "twin_grub", "at": [3, 3]}])
	assert_eq(Content.validate("rooms", ed.to_template()), PackedStringArray())
