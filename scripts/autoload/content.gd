extends Node
## Content registry (DESIGN.md §16.4). Loads every /data/<category>/**/*.json file, validates it
## against SCHEMA, and indexes entries by id. This is the only place gameplay looks up content.
##
##     Content.get_entry("items", "raw_geode")
##     Content.all("enemies")
##
## Export note: JSON is not an imported resource. Export presets must include "data/*" in their
## non-resource include filter (see CLAUDE.md).

const DATA_ROOT := "res://data"
const MOD_ROOT := "user://mods"  # D16: user://mods/<mod>/data/<category>/**.json
const MetaSaveScript := preload("res://scripts/autoload/meta_save.gd")

## Required fields per category: field -> expected Variant.Type (TYPE_NIL = any).
const SCHEMA: Dictionary = {
	"items": {"id": TYPE_STRING, "name_key": TYPE_STRING, "quality": TYPE_INT, "kind": TYPE_STRING, "effects": TYPE_ARRAY},
	"trinkets": {"id": TYPE_STRING, "name_key": TYPE_STRING, "effects": TYPE_ARRAY},
	"fossils": {"id": TYPE_STRING, "name_key": TYPE_STRING, "effects": TYPE_ARRAY},
	"fluids": {"id": TYPE_STRING, "name_key": TYPE_STRING, "effects": TYPE_ARRAY},
	"enemies": {"id": TYPE_STRING, "name_key": TYPE_STRING, "archetype": TYPE_STRING, "hp": TYPE_NIL},
	"bosses": {"id": TYPE_STRING, "name_key": TYPE_STRING, "chapter": TYPE_INT, "hp": TYPE_NIL},
	"pools": {"id": TYPE_STRING, "entries": TYPE_ARRAY},
	"rooms": {"id": TYPE_STRING, "stratum": TYPE_ARRAY, "shape": TYPE_STRING, "grid": TYPE_ARRAY, "doors": TYPE_ARRAY},
	"characters": {"id": TYPE_STRING, "name_key": TYPE_STRING, "stats": TYPE_DICTIONARY},
	"achievements": {"id": TYPE_STRING, "name_key": TYPE_STRING, "condition": TYPE_DICTIONARY, "unlocks": TYPE_ARRAY},
	"mutations": {"id": TYPE_STRING, "name_key": TYPE_STRING, "effects": TYPE_ARRAY},
	"brood": {"id": TYPE_STRING, "name_key": TYPE_STRING, "role": TYPE_STRING, "unlocks": TYPE_ARRAY},
	"curses": {"id": TYPE_STRING, "name_key": TYPE_STRING},
	"strata": {"id": TYPE_STRING, "name_key": TYPE_STRING, "chapter": TYPE_INT},
	"config": {"id": TYPE_STRING},
	"pickups": {"id": TYPE_STRING, "kind": TYPE_STRING, "value": TYPE_INT},
	"resources": {"id": TYPE_STRING, "name_key": TYPE_STRING, "pulp_value": TYPE_INT},
}

const ITEM_KINDS: PackedStringArray = ["passive", "active"]
const PICKUP_KINDS: PackedStringArray = ["mana", "heart", "chitin", "toxic_chitin", "dig_charge", "royal_jelly"]
const ROOM_TYPES: PackedStringArray = ["normal", "start", "boss", "treasure", "secret", "super_secret", "brood_cell", "shop", "miniboss"]
const ROOM_SHAPES: PackedStringArray = ["1x1", "2x1", "1x2", "2x2", "L_ne", "L_nw", "L_se", "L_sw"]

var _db: Dictionary = {}     # category -> {id -> entry}
var errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	_db.clear()
	errors.clear()
	for category in SCHEMA:
		_db[category] = {}
		for path in list_json_files(DATA_ROOT.path_join(category)):
			_load_file(category, path)
	if mods_enabled():
		for mod in DirAccess.get_directories_at(MOD_ROOT):
			for category in SCHEMA:
				for path in list_json_files(MOD_ROOT.path_join(mod).path_join("data").path_join(category)):
					_load_file(category, path, true)
	errors.append_array(cross_check())
	if not errors.is_empty():
		for e in errors:
			push_error("Content: " + e)


## Reference checks across categories (pool entries, unlock targets, room spawns).
func cross_check() -> PackedStringArray:
	var out: PackedStringArray = []
	for pool in all("pools"):
		for e in pool["entries"]:
			if not (has_entry("items", e["id"]) or has_entry("trinkets", e["id"])):
				out.append("pool '%s' references unknown item '%s'" % [pool["id"], e["id"]])
	for table_name in get_entry("config", "drops"):
		var t: Variant = get_entry("config", "drops")[table_name]
		if t is Dictionary and t.has("table"):
			for e in t["table"]:
				if not has_entry("pickups", e["id"]):
					out.append("drop table '%s' references unknown pickup '%s'" % [table_name, e["id"]])
	for ach in all("achievements"):
		for u in ach["unlocks"]:
			if _db.has(u.get("kind", "")) and not has_entry(u["kind"], u.get("id", "")):
				out.append("achievement '%s' unlocks unknown %s '%s'" % [ach["id"], u["kind"], u.get("id", "")])
	for room in all("rooms"):
		for sp in room.get("spawns", []):
			var eid: String = sp.get("enemy", "")
			if eid != "@boss" and not (has_entry("enemies", eid) or has_entry("bosses", eid)):
				out.append("room '%s' spawns unknown enemy '%s'" % [room["id"], eid])
	return out


func get_entry(category: String, id: String) -> Dictionary:
	return _db.get(category, {}).get(id, {})


func has_entry(category: String, id: String) -> bool:
	return _db.get(category, {}).has(id)


func all(category: String) -> Array:
	return _db.get(category, {}).values()


func ids(category: String) -> Array:
	var out: Array = _db.get(category, {}).keys()
	out.sort()
	return out


func count(category: String) -> int:
	return _db.get(category, {}).size()


func mods_enabled() -> bool:
	if not is_inside_tree():
		return false
	var ms: Node = get_node_or_null("/root/MetaSave")
	return ms != null and bool(ms.settings.get("gameplay", {}).get("mods_enabled", false)) and DirAccess.dir_exists_absolute(MOD_ROOT)


func _load_file(category: String, path: String, allow_override: bool = false) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		errors.append("%s: not a JSON object" % path)
		return
	var entry: Dictionary = MetaSaveScript._normalize_numbers(parsed)
	var problems := validate(category, entry)
	if not problems.is_empty():
		for p in problems:
			errors.append("%s: %s" % [path, p])
		return
	if path.get_file().get_basename() != entry["id"]:
		errors.append("%s: id '%s' must match file name" % [path, entry["id"]])
		return
	if _db[category].has(entry["id"]) and not allow_override:
		errors.append("%s: duplicate id '%s'" % [path, entry["id"]])
		return
	entry["_path"] = path
	_db[category][entry["id"]] = entry


## Returns a list of human-readable problems (empty = valid). Pure: used by tests and tools.
static func validate(category: String, entry: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if not SCHEMA.has(category):
		out.append("unknown category '%s'" % category)
		return out
	var req: Dictionary = SCHEMA[category]
	for field in req:
		if not entry.has(field):
			out.append("missing field '%s'" % field)
			continue
		var t: int = req[field]
		if t != TYPE_NIL and typeof(entry[field]) != t:
			out.append("field '%s' should be %s" % [field, type_string(t)])
	if not out.is_empty():
		return out
	match category:
		"items":
			if entry["quality"] < 0 or entry["quality"] > 4:
				out.append("quality must be 0..4")
			if not ITEM_KINDS.has(entry["kind"]):
				out.append("kind must be one of %s" % [ITEM_KINDS])
			for e in entry["effects"]:
				if not (e is Dictionary and e.has("type")):
					out.append("every effect needs a 'type'")
		"rooms":
			if not ROOM_SHAPES.has(entry["shape"]):
				out.append("unknown shape '%s'" % entry["shape"])
			var grid: Array = entry["grid"]
			if grid.is_empty():
				out.append("grid is empty")
			else:
				var w: int = str(grid[0]).length()
				for row in grid:
					if str(row).length() != w:
						out.append("grid rows must all be the same width")
						break
			if grid.size() == 7 and str(grid[0]).length() == 13:
				# Door entry lanes must stay walkable (the player spawns there on entry).
				var lanes := {"N": [Vector2i(6, 0), Vector2i(6, 1)], "S": [Vector2i(6, 5), Vector2i(6, 6)],
					"W": [Vector2i(0, 3), Vector2i(1, 3)], "E": [Vector2i(11, 3), Vector2i(12, 3)]}
				for d in entry["doors"]:
					for t in lanes.get(str(d), []):
						var ch := str(grid[t.y])[t.x]
						if not ch in [".", "S", "D"]:
							out.append("door %s entry tile %s must be walkable (found '%s')" % [d, t, ch])
				for sp in entry.get("spawns", []):
					var at: Array = sp.get("at", [0, 0])
					var ch2 := str(grid[int(at[1])])[int(at[0])]
					if not ch2 in [".", "D"]:
						out.append("spawn %s at %s is on '%s'" % [sp.get("enemy", "?"), at, ch2])
			for t in entry.get("room_types", ["normal"]):
				if not ROOM_TYPES.has(str(t)):
					out.append("unknown room type '%s'" % t)
			for d in entry["doors"]:
				if not str(d) in ["N", "E", "S", "W", "N2", "E2", "S2", "W2"]:
					out.append("bad door '%s'" % d)
		"pickups":
			if not PICKUP_KINDS.has(entry["kind"]):
				out.append("pickup kind must be one of %s" % [PICKUP_KINDS])
		"pools":
			for e in entry["entries"]:
				if not (e is Dictionary and e.has("id")):
					out.append("pool entries need an 'id'")
	return out


static func list_json_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not entry_name.begins_with("."):
			var full := dir_path.path_join(entry_name)
			if dir.current_is_dir():
				out.append_array(list_json_files(full))
			elif entry_name.ends_with(".json"):
				out.append(full)
		entry_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
