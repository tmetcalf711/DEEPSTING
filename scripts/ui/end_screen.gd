extends CanvasLayer
## Death / victory screen with the run summary.

var victory := false
var stash_lost := 0


func setup(won: bool, lost: int) -> void:
	victory = won
	stash_lost = lost


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	create_tween().tween_property(bg, "color:a", 0.85, 0.4)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	center.add_child(vb)
	var title := Label.new()
	title.text = tr("END_VICTORY" if victory else "END_DEATH")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.98, 0.78, 0.15) if victory else Color(0.9, 0.25, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var s := RunState.stats
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 9)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lines: PackedStringArray = [
		tr("END_SEED") % RunState.seed_string(),
		tr("END_TIME") % [int(RunState.elapsed) / 60, int(RunState.elapsed) % 60],
		tr("END_ROOMS") % int(s.get("rooms_cleared", 0)),
		tr("END_KILLS") % int(s.get("kills", 0)),
		tr("END_ITEMS") % int(s.get("items", 0)),
		tr("END_BROOD") % int(s.get("brood_rescued", 0)),
		tr("END_PULP") % int(s.get("pulp_banked", 0)),
	]
	if stash_lost > 0:
		lines.append(tr("END_STASH_LOST") % stash_lost)
	lines.append(tr("END_TOTALS") % [int(MetaSave.data.get("pulp", 0)), int(MetaSave.data["brood"].get("lost_rescued", 0))])
	info.text = "\n".join(lines)
	vb.add_child(info)
	var again := _button(vb, "END_NEW_RUN", func() -> void: _restart(RNG.random_seed()))
	_button(vb, "END_RETRY_SEED", func() -> void: _restart(RunState.seed_value))
	_button(vb, "PAUSE_MAIN_MENU", func() -> void:
		get_tree().paused = false
		RunState.reset()
		GameState.goto_scene("main_menu"))
	again.grab_focus()


func _button(parent: Node, key: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(150, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _restart(seed_value: int) -> void:
	get_tree().paused = false
	RunState.start_new(seed_value, RunState.caste)
	GameState.goto_scene("run")
