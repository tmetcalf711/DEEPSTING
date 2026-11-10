extends CanvasLayer
## Synergy Lab (dev tool, DESIGN.md §17 M3). Runs inside a room test of `lab_range`: training
## dummies show damage numbers. Click any item / knick-knack / mutation to add or remove it and
## watch the stinger change; the panel shows the composed shot spec.

var _list: ItemList
var _readout: Label
var _entries: Array = []   # [category, id]


func _ready() -> void:
	layer = 30
	var panel := PanelContainer.new()
	panel.position = Vector2(4, 74)
	panel.custom_minimum_size = Vector2(150, 230)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.85)
	sb.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = tr("LAB_TITLE")
	title.add_theme_font_size_override("font_size", 9)
	vb.add_child(title)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(145, 150)
	_list.focus_mode = Control.FOCUS_NONE  # arrow keys keep shooting
	_list.add_theme_font_size_override("font_size", 7)
	_list.item_clicked.connect(func(i: int, _p: Vector2, _b: int) -> void: _toggle(i))
	vb.add_child(_list)
	var row := HBoxContainer.new()
	vb.add_child(row)
	for spec in [["LAB_CLEAR", _clear], ["LAB_BACK", _back]]:
		var b := Button.new()
		b.text = tr(spec[0])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 8)
		b.pressed.connect(spec[1])
		row.add_child(b)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 7)
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_readout.add_theme_constant_override("outline_size", 2)
	_readout.position = Vector2(500, 74)
	add_child(_readout)
	for cat in ["items", "trinkets", "mutations"]:
		for id in Content.ids(cat):
			_entries.append([cat, id])
	_refresh()
	Events.stats_changed.connect(_refresh)


static func owns(cat: String, id: String) -> bool:
	match cat:
		"items": return RunState.items.has(id) or RunState.active_item == id
		"trinkets": return RunState.trinket == id
		"mutations": return RunState.mutations.has(id)
	return false


## Adds or removes one thing from the build (exposed for tests).
static func toggle(cat: String, id: String) -> void:
	var p: Node2D = RunController.instance.player
	if owns(cat, id):
		match cat:
			"items":
				RunState.items.erase(id)
				if RunState.active_item == id:
					RunState.active_item = ""
			"trinkets":
				RunState.trinket = ""
			"mutations":
				RunState.mutations.erase(id)
		p.effects.rebuild()
		return
	match cat:
		"items": p.pickup_item(id)
		"trinkets": p.effects.set_trinket(id)
		"mutations": p.effects.add_mutation(id)
	if RunState.active_item != "":
		RunState.active_charge = RunState.active_max


func _toggle(i: int) -> void:
	toggle(_entries[i][0], _entries[i][1])
	_refresh()


func _clear() -> void:
	RunState.items.clear()
	RunState.active_item = ""
	RunState.trinket = ""
	RunState.mutations.clear()
	RunController.instance.player.effects.rebuild()
	_refresh()


func _back() -> void:
	GameState.room_test_template = ""
	GameState.lab_mode = false
	RunState.reset()
	GameState.goto_scene("main_menu")


func _refresh() -> void:
	if _list == null:
		return
	var scroll := _list.get_v_scroll_bar().value
	_list.clear()
	for e in _entries:
		var entry: Dictionary = Content.get_entry(e[0], e[1])
		var mark := "■ " if owns(e[0], e[1]) else "□ "
		var prefix: String = {"items": "", "trinkets": "◆ ", "mutations": "☢ "}[e[0]]
		_list.add_item(mark + prefix + tr(entry.get("name_key", e[1])))
	_list.get_v_scroll_bar().value = scroll
	var p: Node2D = RunController.instance.player if RunController.instance else null
	if p == null or p.spec.is_empty():
		return
	var s: Dictionary = p.spec
	var procs: PackedStringArray = []
	for pr in s["procs"]:
		procs.append("%s %d%%" % [pr["kind"], int(round(float(pr["chance"]) * 100))])
	_readout.text = "damage %.2f  x%d shots\nfire rate %.2f/s  speed %.0f\nrange %.0f  size %.1f\npierce %s  bounce %d\nhoming %.1f  wave %.0f\nsplit %d (x%.2f)\nboomerang %s  spectral %s\nelements %s\nprocs %s" % [
		s["damage"], int(s["multishot"]), RunState.stat("fire_rate"), s["speed"], s["range"], s["radius"],
		"inf" if int(s["pierce"]) < 0 else str(s["pierce"]), int(s["bounce"]), s["homing"], s["wave_amp"],
		int(s["split_count"]), s["split_mult"], s["boomerang"], s["spectral"], ", ".join(s["elements"]) if not s["elements"].is_empty() else "-",
		", ".join(procs) if not procs.is_empty() else "-"]
