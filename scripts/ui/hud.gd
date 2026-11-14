extends CanvasLayer
## In-run HUD: hearts/shields, consumables, active item charge, floor stash, minimap, boss bar,
## pickup banner, toasts. Drawn at the 640x360 logical resolution.

const MinimapScript := preload("res://scripts/ui/minimap.gd")
const PickupScript := preload("res://scripts/actors/pickup.gd")

var _root: Control
var _labels: Dictionary = {}
var _banner: Label
var _banner_sub: Label
var _banner_t := 0.0
var _toasts: VBoxContainer
var _boss_frac := -1.0
const INSPECT_RADIUS := 30.0   # world px: about two tiles
var _inspect: PanelContainer
var _inspect_icon: TextureRect
var _inspect_title: Label
var _inspect_kind: Label
var _inspect_body: Label
var _inspect_extra: Label
var _inspect_alpha := 0.0
var inspected: Node = null      # what the side panel is describing (read by tests)
var _boss_name := ""


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	add_child(_root)
	for k in ["mana", "dig_charge", "royal_jelly", "stash", "curse", "consumable"]:
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
	_build_inspect_panel()
	Events.banner.connect(_on_banner)
	Events.toast.connect(_on_toast)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_health_changed.connect(_on_boss_health)


func _on_boss_spawned(id: String) -> void:
	_boss_name = tr(Content.get_entry("bosses", id).get("name_key", ""))
	_boss_frac = 1.0


func _on_boss_health(f: float) -> void:
	_boss_frac = f if f > 0.0 else -1.0


## Side panel that names whatever item / ware / pickup the wasp is standing near.
func _build_inspect_panel() -> void:
	_inspect = PanelContainer.new()
	_inspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inspect.position = Vector2(-158, 94)
	_inspect.custom_minimum_size = Vector2(152, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.88)
	sb.border_color = Color(0.85, 0.65, 0.25, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_inspect.add_theme_stylebox_override("panel", sb)
	_root.add_child(_inspect)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	_inspect.add_child(hb)
	_inspect_icon = TextureRect.new()
	_inspect_icon.custom_minimum_size = Vector2(24, 24)
	_inspect_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inspect_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_inspect_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(_inspect_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.custom_minimum_size = Vector2(118, 0)
	hb.add_child(vb)
	_inspect_title = _label(9)
	_inspect_kind = _label(7)
	_inspect_kind.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	_inspect_body = _label(8)
	_inspect_extra = _label(8)
	_inspect_extra.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	for l in [_inspect_title, _inspect_kind, _inspect_body, _inspect_extra]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(118, 0)
		vb.add_child(l)
	_inspect.modulate.a = 0.0


## The nearest inspectable thing in the current room within reach of the wasp, or null.
static func nearest_inspectable(rc: Node) -> Node:
	if rc == null or rc.room == null or rc.player == null:
		return null
	var best: Node = null
	var best_d := INSPECT_RADIUS
	for n in rc.get_tree().get_nodes_in_group("inspectable"):
		if not is_instance_valid(n) or not rc.room.is_ancestor_of(n) or n.is_queued_for_deletion():
			continue
		var d: float = n.global_position.distance_to(rc.player.global_position)
		if d < best_d and not n.inspect_info().is_empty():
			best_d = d
			best = n
	return best


func _update_inspect(delta: float) -> void:
	var target := nearest_inspectable(RunController.instance)
	if target:
		var info: Dictionary = target.inspect_info()
		inspected = target
		_inspect_icon.texture = info.get("icon")
		_inspect_title.text = str(info.get("title", ""))
		_inspect_title.add_theme_color_override("font_color", info.get("color", Color.WHITE))
		_inspect_kind.text = str(info.get("kind", ""))
		_inspect_body.text = str(info.get("body", ""))
		_inspect_extra.text = str(info.get("extra", ""))
		_inspect_extra.visible = _inspect_extra.text != ""
		_inspect_body.visible = _inspect_body.text != ""
		_inspect_alpha = minf(1.0, _inspect_alpha + delta * 8.0)
	else:
		inspected = null
		_inspect_alpha = maxf(0.0, _inspect_alpha - delta * 6.0)
	_inspect.modulate.a = _inspect_alpha
	_inspect.size = Vector2(_inspect.custom_minimum_size.x, 0)  # shrink to fit the text


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
	_update_inspect(delta)
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
	var c: Dictionary = RunState.consumable
	var cname := ""
	if not c.is_empty():
		cname = EffectHost.fluid_display_name(str(c["id"])) if c["kind"] == "fluid" else tr(Content.get_entry("fossils", str(c["id"])).get("name_key", ""))
	_labels["consumable"].text = cname
	_labels["consumable"].position = Vector2(vp.x - 100, vp.y - 30)
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
	# Radiation meter (fills toward a mutation)
	var vp0 := _root.get_viewport_rect().size
	var rfrac := clampf(RunState.radiation / float(maxi(1, RunState.radiation_threshold)), 0.0, 1.0)
	var rr := Rect2(8, vp0.y - 14, 70, 4)
	_icon("radiation", Vector2(8, vp0.y - 26))
	_root.draw_rect(rr.grow(1), Color(0, 0, 0, 0.8))
	_root.draw_rect(Rect2(rr.position, Vector2(rr.size.x * rfrac, rr.size.y)), Color(0.5, 1.0, 0.3) if rfrac < 1.0 else Color(0.9, 1.0, 0.5))
	# Knick-knack and the fossil / fluid slot (bottom right)
	if RunState.trinket != "":
		_root.draw_texture(Art.texture("trinkets", RunState.trinket), Vector2(vp0.x - 120, vp0.y - 34))
	var cs: Dictionary = RunState.consumable
	if not cs.is_empty():
		if cs["kind"] == "fluid":
			var col := PickupScript.fluid_color(str(cs["id"]))
			_root.draw_rect(Rect2(vp0.x - 112, vp0.y - 20, 6, 9), col)
		else:
			_root.draw_texture(Art.texture("fossils", str(cs["id"])), Vector2(vp0.x - 116, vp0.y - 22))
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
