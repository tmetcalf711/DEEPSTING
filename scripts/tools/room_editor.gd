extends Control
## In-engine room template editor (DESIGN.md §10.4). Paints the same JSON format the game loads.
##   Left click: paint the selected tile / place the selected enemy.  Right click: erase.
##   Door lanes (tiles that must stay walkable) are outlined; the validator enforces them on save.
## Save writes res://data/rooms/<stratum>/<id>.json ("shared" for stratum "*"). Test saves, then
## starts a run containing only this room.

const TILES := [".", "R", "T", "#", "X", "S", "B", "D", "P"]
const TILE_NAMES := {".": "floor", "R": "rock", "T": "tinted", "#": "block", "X": "pit", "S": "spikes", "B": "brood", "D": "deposit", "P": "pedestal"}
const TILE_COLORS := {".": Color(0.24, 0.18, 0.12), "R": Color(0.47, 0.4, 0.33), "T": Color(0.42, 0.45, 0.62), "#": Color(0.15, 0.12, 0.1),
	"X": Color(0.02, 0.02, 0.02), "S": Color(0.6, 0.58, 0.55), "B": Color(0.93, 0.84, 0.58), "D": Color(0.78, 0.64, 0.42), "P": Color(0.95, 0.8, 0.3)}
const SHAPES := ["1x1", "2x1", "1x2", "2x2"]

var shape := "1x1"
var grid: Array = []          # Array[Array[String]]
var spawns: Array = []        # [{enemy, at:[x,y]}]
var brush := "R"              # a tile char, or "enemy"
var enemy_choice := "twin_grub"

var _id: LineEdit
var _stratum: LineEdit
var _types: LineEdit
var _tags: LineEdit
var _weight: SpinBox
var _shape_opt: OptionButton
var _load_opt: OptionButton
var _enemy_opt: OptionButton
var _status: Label
var _canvas: Control
var _painting := 0  # 0 none, 1 paint, 2 erase


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	add_child(root)
	var bar1 := HBoxContainer.new()
	root.add_child(bar1)
	_id = _line(bar1, "id", 110)
	_stratum = _line(bar1, "stratum (hive, topsoil, *)", 70)
	_shape_opt = OptionButton.new()
	for s in SHAPES:
		_shape_opt.add_item(s)
	_shape_opt.item_selected.connect(func(i: int) -> void: _resize(SHAPES[i]))
	_small(_shape_opt)
	bar1.add_child(_shape_opt)
	_types = _line(bar1, "room types (normal, boss...)", 100)
	_tags = _line(bar1, "tags (brood_cell...)", 80)
	_weight = SpinBox.new()
	_weight.min_value = 0.1
	_weight.max_value = 5.0
	_weight.step = 0.1
	_weight.value = 1.0
	_weight.tooltip_text = "weight"
	_small(_weight)
	bar1.add_child(_weight)
	var bar2 := HBoxContainer.new()
	root.add_child(bar2)
	_load_opt = OptionButton.new()
	_small(_load_opt)
	bar2.add_child(_load_opt)
	_button(bar2, tr("EDITOR_LOAD"), func() -> void: _load(_load_opt.get_item_text(_load_opt.selected)))
	_button(bar2, tr("EDITOR_NEW"), _new)
	_button(bar2, tr("EDITOR_SAVE"), func() -> void: _save())
	_button(bar2, tr("EDITOR_TEST"), _test)
	_button(bar2, "Back", func() -> void: GameState.goto_scene("main_menu"))
	_status = Label.new()
	_small(_status)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar2.add_child(_status)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var palette := VBoxContainer.new()
	palette.custom_minimum_size = Vector2(70, 0)
	body.add_child(palette)
	for t in TILES:
		_button(palette, "%s %s" % [t, TILE_NAMES[t]], func() -> void: _set_brush(t))
	_enemy_opt = OptionButton.new()
	_small(_enemy_opt)
	_enemy_opt.add_item("@boss")
	for id in Content.ids("enemies"):
		_enemy_opt.add_item(id)
	_enemy_opt.item_selected.connect(func(i: int) -> void:
		enemy_choice = _enemy_opt.get_item_text(i)
		_set_brush("enemy"))
	palette.add_child(_enemy_opt)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_canvas_input)
	body.add_child(_canvas)
	_refresh_load_list()
	_new()


func _small(c: Control) -> void:
	c.add_theme_font_size_override("font_size", 8)


func _line(parent: Node, hint: String, w: float) -> LineEdit:
	var l := LineEdit.new()
	l.placeholder_text = hint
	l.tooltip_text = hint
	l.custom_minimum_size = Vector2(w, 0)
	_small(l)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_small(b)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _set_brush(b: String) -> void:
	brush = b
	_status.text = "brush: " + (("enemy " + enemy_choice) if b == "enemy" else TILE_NAMES[b])


func _refresh_load_list() -> void:
	_load_opt.clear()
	for id in Content.ids("rooms"):
		_load_opt.add_item(id)


func _dims() -> Vector2i:
	var sc: Vector2i = Content.SHAPE_CELLS[shape]
	return Vector2i(13 * sc.x, 7 * sc.y)


func _resize(new_shape: String) -> void:
	shape = new_shape
	var d := _dims()
	var g: Array = []
	for y in d.y:
		var row: Array = []
		for x in d.x:
			row.append(grid[y][x] if y < grid.size() and x < grid[y].size() else ".")
		g.append(row)
	grid = g
	spawns = spawns.filter(func(s: Dictionary) -> bool: return int(s["at"][0]) < d.x and int(s["at"][1]) < d.y)
	_canvas.queue_redraw()


func _new() -> void:
	_id.text = "new_room"
	_stratum.text = "hive"
	_types.text = "normal"
	_tags.text = ""
	_weight.value = 1.0
	grid = []
	spawns = []
	_shape_opt.select(0)
	_resize("1x1")
	_status.text = "new 1x1 room"


func _load(id: String) -> void:
	var t: Dictionary = Content.get_entry("rooms", id)
	if t.is_empty():
		return
	_id.text = id
	_stratum.text = ", ".join(t.get("stratum", []))
	_types.text = ", ".join(t.get("room_types", ["normal"]))
	_tags.text = ", ".join(t.get("tags", []))
	_weight.value = float(t.get("weight", 1.0))
	shape = str(t.get("shape", "1x1"))
	_shape_opt.select(SHAPES.find(shape))
	grid = []
	for row in t["grid"]:
		var r: Array = []
		for ch in str(row):
			r.append(ch)
		grid.append(r)
	spawns = t.get("spawns", []).duplicate(true)
	_canvas.queue_redraw()
	_status.text = "loaded " + id


func _list(text: String) -> Array:
	var out: Array = []
	for p in text.split(","):
		if p.strip_edges() != "":
			out.append(p.strip_edges())
	return out


func to_template() -> Dictionary:
	var rows: Array = []
	for r in grid:
		rows.append("".join(r))
	var d := {"id": _id.text.strip_edges(), "stratum": _list(_stratum.text), "shape": shape,
		"room_types": _list(_types.text), "difficulty": 1, "weight": _weight.value, "tags": _list(_tags.text),
		"grid": rows, "spawns": spawns}
	if shape == "1x1":
		d["doors"] = ["N", "E", "S", "W"]
	return d


## Returns the saved path, or "" when validation failed.
func _save() -> String:
	var d := to_template()
	var problems: PackedStringArray = Content.validate("rooms", d)
	if d["id"] == "" or not str(d["id"]).is_valid_identifier():
		problems.append("id must be a simple identifier")
	if (d["stratum"] as Array).is_empty():
		problems.append("needs a stratum")
	if not problems.is_empty():
		_status.text = tr("EDITOR_ERRORS") % "; ".join(problems)
		return ""
	var folder: String = "shared" if d["stratum"][0] == "*" else str(d["stratum"][0])
	var existing: Dictionary = Content.get_entry("rooms", d["id"])
	var path: String = existing.get("_path", "res://data/rooms/%s/%s.json" % [folder, d["id"]])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "cannot write %s" % path
		return ""
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	f.close()
	Content.reload()
	_refresh_load_list()
	_status.text = tr("EDITOR_SAVED") % path
	return path


func _test() -> void:
	if _save() == "":
		return
	GameState.room_test_template = _id.text.strip_edges()
	RunState.start_new(RNG.random_seed())
	GameState.goto_scene("run")


# ---------------------------------------------------------------- canvas

func _cell_px() -> float:
	var d := _dims()
	return floorf(minf(_canvas.size.x / d.x, _canvas.size.y / d.y))


func _tile_from(pos: Vector2) -> Vector2i:
	var px := _cell_px()
	return Vector2i(floori(pos.x / px), floori(pos.y / px))


func _on_canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed:
			_painting = 1 if e.button_index == MOUSE_BUTTON_LEFT else 2
			_apply(_tile_from(e.position))
		else:
			_painting = 0
	elif e is InputEventMouseMotion and _painting > 0 and brush != "enemy":
		_apply(_tile_from(e.position))


func _apply(t: Vector2i) -> void:
	var d := _dims()
	if t.x < 0 or t.y < 0 or t.x >= d.x or t.y >= d.y:
		return
	spawns = spawns.filter(func(s: Dictionary) -> bool: return not (int(s["at"][0]) == t.x and int(s["at"][1]) == t.y))
	if _painting == 2:
		grid[t.y][t.x] = "."
	elif brush == "enemy":
		grid[t.y][t.x] = "."
		spawns.append({"enemy": enemy_choice, "at": [t.x, t.y]})
	else:
		grid[t.y][t.x] = brush
	_canvas.queue_redraw()


func _draw_canvas() -> void:
	var px := _cell_px()
	var d := _dims()
	var lanes := Content.door_lanes(shape)
	var font := ThemeDB.fallback_font
	for y in d.y:
		for x in d.x:
			var r := Rect2(x * px, y * px, px - 1, px - 1)
			var ch: String = grid[y][x]
			_canvas.draw_rect(r, TILE_COLORS.get(ch, Color.MAGENTA))
			if ch != ".":
				_canvas.draw_string(font, r.position + Vector2(2, px - 4), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px * 0.6), Color(0, 0, 0, 0.6))
			if lanes.has(Vector2i(x, y)):
				_canvas.draw_rect(r, Color(0.4, 0.9, 1.0, 0.7), false, 1.0)
	# Cell seams for big rooms.
	var sc: Vector2i = Content.SHAPE_CELLS[shape]
	for cx in range(1, sc.x):
		_canvas.draw_line(Vector2(cx * 13 * px, 0), Vector2(cx * 13 * px, d.y * px), Color(1, 1, 1, 0.25), 1.0)
	for cy in range(1, sc.y):
		_canvas.draw_line(Vector2(0, cy * 7 * px), Vector2(d.x * px, cy * 7 * px), Color(1, 1, 1, 0.25), 1.0)
	for s in spawns:
		var c := Vector2((int(s["at"][0]) + 0.5) * px, (int(s["at"][1]) + 0.5) * px)
		var boss: bool = s["enemy"] == "@boss"
		_canvas.draw_circle(c, px * (0.45 if boss else 0.32), Color(0.8, 0.15, 0.2) if boss else Color(0.55, 0.85, 0.3))
		_canvas.draw_string(font, c + Vector2(-px * 0.4, px * 0.15), str(s["enemy"]).substr(0, 3), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px * 0.4), Color(0, 0, 0))
