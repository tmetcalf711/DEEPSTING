extends Node
## Versioned meta save + settings + mid-run save (DESIGN.md §16.7).
## Files live in one directory (Steam Cloud friendly). Writes are atomic (tmp -> rename) and the
## previous good copy is kept as .bak, which is used if the main file fails to parse.

const META_VERSION := 1
const SETTINGS_VERSION := 1
const RUN_VERSION := 1

## Tests point this at a scratch directory.
var save_dir: String = "user://save"

var data: Dictionary = {}       # meta progression
var settings: Dictionary = {}   # player settings


func _ready() -> void:
	load_all()


func load_all() -> void:
	data = load_meta()
	settings = load_settings()


# ---------------------------------------------------------------- meta

static func default_meta() -> Dictionary:
	return {
		"version": META_VERSION,
		"comb": 0,                    # banked meta-currency
		"resources": {},              # resource_type -> lifetime banked (drives hive decor)
		"unlocks": {},                # "kind:id" -> true
		"achievements": {},           # id -> unix time unlocked
		"counters": {},               # lifetime stat counters, e.g. "kills.twin_grub"
		"brood": {"lost_rescued": 0, "mutated": {}},  # mutated: id -> true
		"completion_marks": {},       # caste_id -> {mark_id: true}
		"trove_seen": {},             # "kind:id" -> true
		"comb_upgrades": {},          # upgrade_id -> level
		"runs": {"started": 0, "won": 0, "best_depth": 0},
	}


func load_meta() -> Dictionary:
	var loaded: Variant = _read_json_with_backup(_path("meta.json"))
	if loaded is Dictionary:
		return migrate_meta(loaded)
	return default_meta()


func save_meta() -> bool:
	data["version"] = META_VERSION
	return _write_json_atomic(_path("meta.json"), data)


## Applies migrations in order. Every step must be pure (dict in -> dict out).
static func migrate_meta(d: Dictionary) -> Dictionary:
	var v: int = int(d.get("version", 0))
	if v < 1:
		d = _migrate_meta_v0_to_v1(d)
	# Future: if v < 2: d = _migrate_meta_v1_to_v2(d)
	# Fill any keys added since (forward-compatible defaults).
	var defaults := default_meta()
	for k in defaults:
		if not d.has(k):
			d[k] = defaults[k]
	d["version"] = META_VERSION
	return d


## v0 was the pre-release prototype format: {"currency": n, "brood": n}.
static func _migrate_meta_v0_to_v1(d: Dictionary) -> Dictionary:
	var out := default_meta()
	out["comb"] = int(d.get("currency", d.get("comb", 0)))
	var b: Variant = d.get("brood", 0)
	if b is int or b is float:
		out["brood"]["lost_rescued"] = int(b)
	elif b is Dictionary:
		out["brood"] = b
	for k in d:
		if k not in ["currency", "brood", "version"] and out.has(k):
			out[k] = d[k]
	return out


# Convenience mutators. Callers that must persist immediately (brood rescue, hauls) pass flush=true.

func bank_comb(amount: int, resource_type: String = "", flush: bool = true) -> void:
	data["comb"] = int(data.get("comb", 0)) + amount
	if resource_type != "":
		var res: Dictionary = data["resources"]
		res[resource_type] = int(res.get(resource_type, 0)) + amount
	Events.comb_banked.emit(amount)
	if flush:
		save_meta()


func add_counter(key: String, amount: int = 1) -> void:
	var c: Dictionary = data["counters"]
	c[key] = int(c.get(key, 0)) + amount


func is_unlocked(kind: String, id: String) -> bool:
	return data["unlocks"].has("%s:%s" % [kind, id])


func unlock(kind: String, id: String, flush: bool = true) -> void:
	var key := "%s:%s" % [kind, id]
	if data["unlocks"].has(key):
		return
	data["unlocks"][key] = true
	Events.content_unlocked.emit(kind, id)
	if flush:
		save_meta()


func wipe() -> void:
	data = default_meta()
	save_meta()
	delete_run()


# ---------------------------------------------------------------- settings

static func default_settings() -> Dictionary:
	return {
		"version": SETTINGS_VERSION,
		"video": {"fullscreen": false, "vsync": true},
		"audio": {"master": 1.0, "music": 0.7, "sfx": 0.9},
		"controls": {"aim_mode": "free", "bindings": {}},  # aim_mode: 4dir | 8dir | free
		"accessibility": {
			"screen_shake": 1.0, "hit_stop": true, "flash_reduction": false,
			"bullet_palette": "default", "high_contrast_projectiles": false, "text_scale": 1.0,
		},
		"gameplay": {"show_seed": true},
		"locale": "en",
	}


func load_settings() -> Dictionary:
	var loaded: Variant = _read_json_with_backup(_path("settings.json"))
	var defaults := default_settings()
	if loaded is Dictionary:
		return _deep_merge(defaults, loaded)
	return defaults


func save_settings() -> bool:
	settings["version"] = SETTINGS_VERSION
	return _write_json_atomic(_path("settings.json"), settings)


# ---------------------------------------------------------------- mid-run save

func save_run(run_dict: Dictionary) -> bool:
	var d := run_dict.duplicate(true)
	d["version"] = RUN_VERSION
	return _write_json_atomic(_path("run.json"), d)


func load_run() -> Dictionary:
	var loaded: Variant = _read_json_with_backup(_path("run.json"))
	if loaded is Dictionary and int(loaded.get("version", 0)) == RUN_VERSION:
		return loaded
	return {}


func has_run() -> bool:
	return FileAccess.file_exists(_path("run.json"))


func delete_run() -> void:
	for p in [_path("run.json"), _path("run.json.bak")]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# ---------------------------------------------------------------- io helpers

func _path(file_name: String) -> String:
	return save_dir.path_join(file_name)


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)


func _write_json_atomic(path: String, d: Dictionary) -> bool:
	_ensure_dir()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("MetaSave: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(d, "\t", true))
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("MetaSave: rename failed for %s (%s)" % [path, error_string(err)])
		return false
	return true


func _read_json_with_backup(path: String) -> Variant:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(p)) == OK and json.data is Dictionary:
			return _normalize_numbers(json.data)
		push_warning("MetaSave: %s is corrupt, trying backup" % p)
	return null


## JSON has no ints; parse_string returns floats. Convert integral floats back to int so save
## round-trips compare equal and int() casts aren't needed everywhere.
static func _normalize_numbers(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _normalize_numbers(v[k])
		return out
	if v is Array:
		var arr := []
		for e in v:
			arr.append(_normalize_numbers(e))
		return arr
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	return v


static func _deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = _deep_merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out
