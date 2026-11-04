extends GutTest

const MetaSaveScript := preload("res://scripts/autoload/meta_save.gd")
const DIR := "user://test_save_tmp"

var save: Node


func before_each() -> void:
	_wipe_dir()
	save = MetaSaveScript.new()
	save.save_dir = DIR
	save.data = MetaSaveScript.default_meta()
	save.settings = MetaSaveScript.default_settings()


func after_each() -> void:
	save.free()
	_wipe_dir()


func _wipe_dir() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		DirAccess.remove_absolute(DIR)


func test_meta_round_trip() -> void:
	save.data["comb"] = 321
	save.data["unlocks"]["items:raw_geode"] = true
	save.data["brood"]["lost_rescued"] = 7
	save.data["brood"]["mutated"]["pip"] = true
	save.data["counters"]["kills.twin_grub"] = 40
	assert_true(save.save_meta())
	var loaded: Dictionary = save.load_meta()
	assert_eq(loaded, save.data)


func test_missing_file_gives_defaults() -> void:
	assert_eq(save.load_meta(), MetaSaveScript.default_meta())


func test_corrupt_main_falls_back_to_backup() -> void:
	save.data["comb"] = 10
	save.save_meta()
	save.data["comb"] = 20
	save.save_meta()  # 10 is now in .bak
	var f := FileAccess.open(DIR.path_join("meta.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_eq(int(save.load_meta()["comb"]), 10)


func test_migrate_v0() -> void:
	var v0 := {"currency": 55, "brood": 3}
	var m: Dictionary = MetaSaveScript.migrate_meta(v0)
	assert_eq(m["version"], MetaSaveScript.META_VERSION)
	assert_eq(m["comb"], 55)
	assert_eq(m["brood"]["lost_rescued"], 3)
	assert_true(m.has("unlocks"))


func test_migrate_fills_new_keys() -> void:
	var partial := {"version": 1, "comb": 4}
	var m: Dictionary = MetaSaveScript.migrate_meta(partial)
	assert_eq(m["comb"], 4)
	assert_true(m.has("completion_marks"))


func test_settings_merge_keeps_new_defaults() -> void:
	var f_dir := DirAccess.make_dir_recursive_absolute(DIR)
	assert_eq(f_dir, OK)
	var f := FileAccess.open(DIR.path_join("settings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "audio": {"music": 0.2}}))
	f.close()
	var s: Dictionary = save.load_settings()
	assert_almost_eq(float(s["audio"]["music"]), 0.2, 0.0001)
	assert_true(s["audio"].has("sfx"), "default sibling keys survive")
	assert_true(s.has("accessibility"))


func test_run_save_round_trip_and_delete() -> void:
	var run := {"seed": 123, "floor_index": 2, "items": ["raw_geode"], "health": {"honeycomb": 3}}
	assert_true(save.save_run(run))
	assert_true(save.has_run())
	var loaded: Dictionary = save.load_run()
	assert_eq(loaded["seed"], 123)
	assert_eq(loaded["items"], ["raw_geode"])
	save.delete_run()
	assert_false(save.has_run())
