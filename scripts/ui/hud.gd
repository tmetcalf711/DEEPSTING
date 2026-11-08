extends CanvasLayer
## In-run HUD: hearts/shields, consumables, active item charge, floor stash, minimap, boss bar,
## pickup banner, toasts. Drawn at the 640x360 logical resolution.

const MinimapScript := preload("res://scripts/ui/minimap.gd")

var _root: Control
var _labels: Dictionary = {}
var _banner: Label
var _banner_sub: Label
var _banner_t := 0.0
var _toasts: VBoxContainer
var _boss_frac := -1.0
var _boss_name := ""


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	add_child(_root)
	for k in ["mana", "dig_charge", "royal_jelly", "stash", "curse"]:
		var l := _label(8)
		_root.add_child(l)
		_labels[k] = l
	_banner = _label(16)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(-200, 46)
	_banner.size = Vector2(400, 20)
	_root.add_child(_banner)
	_banner_sub = _label(8)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_sub.position = Vector2(-200, 68)
	_banner_sub.size = Vector2(400, 12)
	_root.add_child(_banner_sub)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toasts.position = Vector2(8, 300)
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.size = Vector2(260, 50)
	_root.add_child(_toasts)
	var mm: Control = MinimapScript.new()
	mm.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mm.position = Vector2(-100, 6)
	mm.size = Vector2(94, 64)
	_root.add_child(mm)
	Events.banner.connect(_on_banner)
	Events.toast.connect(_on_toast)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_health_changed.connect(_on_boss_health)


func _on_boss_spawned(id: String) -> void:
	_boss_name = tr(Content.get_entry("bosses", id).get("name_key", ""))
	_boss_frac = 1.0


func _on_boss_health(f: float) -> void:
	_boss_frac = f if f > 0.0 else -1.0


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_banner(title: String, sub: String) -> void:
	_banner.text = title
	_banner_sub.text = sub
	_banner_t = 2.6


func _on_toast(text: String) -> void:
	var l := _label(8)
	l.text = text
	_toasts.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))


func _process(delta: float) -> void:
	# The boss bar only shows while a live boss is in the current room.
	if _boss_frac > 0.0:
		var rc0 := RunController.instance
		if rc0 == null or rc0.room == null or rc0.room.room_enemies().filter(func(e: Node) -> bool: return e.is_boss).is_empty():
			_boss_frac = -1.0
	_banner_t = maxf(0.0, _banner_t - delta)
	var a := clampf(_banner_t / 0.5, 0.0, 1.0)
	_banner.modulate.a = a
	_banner_sub.modulate.a = a
	_labels["mana"].text = "%02d" % RunState.mana
	_labels["dig_charge"].text = "%02d" % RunState.dig_charges
	_labels["royal_jelly"].text = "%02d" % RunState.royal_jelly
	var st := RunState.stash_total()
	_labels["stash"].text = tr("HUD_STASH") % st if st > 0 else ""
	var vp := _root.get_viewport_rect().size
	_labels["mana"].position = Vector2(20, 30)
	_labels["dig_charge"].position = Vector2(20, 41)
	_labels["royal_jelly"].position = Vector2(20, 52)
	_labels["stash"].position = Vector2(vp.x - 100, 72)
	var rc := RunController.instance
	_labels["curse"].text = tr(Content.get_entry("curses", rc.curse_id).get("name_key", "")) if rc and rc.curse_id != "" else ""
	_labels["curse"].position = Vector2(8, 64)
	_labels["curse"].add_theme_color_override("font_color", Color(0.75, 0.55, 0.95))
	_root.queue_redraw()


func _draw_hud() -> void:
	# Hearts row, then shields (chitin / toxic chitin).
	var x := 8.0
	var y := 8.0
	var i := 0
	for h in range(0, RunState.hearts_max, 2):
		var filled := RunState.hearts - h
		var id := "heart_full" if filled >= 2 else ("heart_half" if filled == 1 else "heart_empty")
		_icon(id, Vector2(x + (i % 6) * 10, y + (i / 6) * 10))
		i += 1
	var s := 0
	while s < RunState.shields.size():
		var kind: String = RunState.shields[s]
		var full := s + 1 < RunState.shields.size() and RunState.shields[s + 1] == kind
		var base := "chitin" if kind == "chitin" else "toxic_chitin"
		_icon(base if full else base + "_half", Vector2(x + (i % 6) * 10, y + (i / 6) * 10))
		s += 2 if full else 1
		i += 1
	# Consumable icons
	_icon("mana", Vector2(8, 31))
	_icon("dig_charge", Vector2(8, 42))
	_icon("royal_jelly", Vector2(8, 53))
	# Active item + charge bar
	if RunState.active_item != "":
		var ax := 72.0
		var tex := Art.texture("items", RunState.active_item)
		_root.draw_texture(tex, Vector2(ax, 8))
		var frac := float(RunState.active_charge) / float(maxi(1, RunState.active_max))
		_root.draw_rect(Rect2(ax + 18, 8, 4, 16), Color(0.1, 0.1, 0.1))
		_root.draw_rect(Rect2(ax + 18, 8 + 16 * (1.0 - frac), 4, 16 * frac), Color(1.0, 0.85, 0.2) if frac >= 1.0 else Color(0.6, 0.6, 0.65))
		for k in range(1, RunState.active_max):
			_root.draw_line(Vector2(ax + 18, 8 + 16.0 * k / RunState.active_max), Vector2(ax + 22, 8 + 16.0 * k / RunState.active_max), Color(0, 0, 0))
	# Boss bar
	if _boss_frac > 0.0:
		var vp := _root.get_viewport_rect().size
		var w := 200.0
		var r := Rect2(vp.x / 2.0 - w / 2.0, vp.y - 22, w, 7)
		_root.draw_rect(r.grow(1), Color(0, 0, 0))
		_root.draw_rect(Rect2(r.position, Vector2(w * _boss_frac, r.size.y)), Color(0.8, 0.12, 0.15))
		_root.draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y - 3), _boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)


func _icon(id: String, at: Vector2) -> void:
	_root.draw_texture(Art.texture("ui", id), at)
