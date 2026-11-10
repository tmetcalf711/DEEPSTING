extends CanvasLayer
## Radiation meter full: pick 1 of 3 mutations (DESIGN.md §8.2). Pauses the game; controller-navigable.

signal chosen(mutation_id: String)

var options: Array = []


func setup(p_options: Array) -> void:
	options = p_options


func _ready() -> void:
	layer = 42
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.12, 0.04, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	center.add_child(vb)
	var title := Label.new()
	title.text = tr("MUTATION_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var first: Button = null
	for id in options:
		var m: Dictionary = Content.get_entry("mutations", id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 70)
		b.text = "%s\n\n%s" % [tr(m.get("name_key", id)), tr(m.get("desc_key", ""))]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(_pick.bind(str(id)))
		row.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus()


func _pick(id: String) -> void:
	get_tree().paused = false
	chosen.emit(id)
	queue_free()
