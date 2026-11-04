extends GutTest

const ContentScript := preload("res://scripts/autoload/content.gd")


func test_all_shipped_data_is_valid() -> void:
	Content.reload()
	assert_eq(Content.errors, PackedStringArray(), "data errors: %s" % [Content.errors])
	assert_gt(Content.count("items"), 0)


func test_validate_rejects_bad_item() -> void:
	var bad := {"id": "x", "name_key": "X", "quality": 9, "kind": "weird", "effects": [{}]}
	var problems: PackedStringArray = ContentScript.validate("items", bad)
	assert_eq(problems.size(), 3)


func test_validate_reports_missing_fields() -> void:
	var problems: PackedStringArray = ContentScript.validate("items", {"id": "x"})
	assert_true(problems.size() >= 4)


func test_room_grid_width_checked() -> void:
	var room := {"id": "r", "stratum": ["hive"], "shape": "1x1", "doors": ["N"], "grid": ["...", ".."]}
	assert_eq(ContentScript.validate("rooms", room).size(), 1)


func test_item_lookup() -> void:
	var geode: Dictionary = Content.get_entry("items", "raw_geode")
	assert_eq(geode.get("quality"), 3)
	assert_typeof(geode["quality"], TYPE_INT, "JSON numbers normalized to int")
