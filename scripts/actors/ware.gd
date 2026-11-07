extends Node2D
## Something for sale: shop wares (Mana price) or Mutation Den items (heart-container price).
## `entry` is the dictionary stored in room.info.wares, so "sold" persists on the floor.

const PickupScript := preload("res://scripts/actors/pickup.gd")

var room: Node
var entry: Dictionary
var _spr: Sprite2D
var _label: Label
var _t := 0.0
var _cooldown := 0.0


func setup(p_room: Node, p_entry: Dictionary) -> void:
	room = p_room
	entry = p_entry


func _ready() -> void:
	_spr = Sprite2D.new()
	add_child(_spr)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-16, 2)
	_label.size = Vector2(32, 10)
	_label.scale = Vector2(0.5, 0.5)
	_label.position = Vector2(-8, 2)
	add_child(_label)
	_refresh()


func _refresh() -> void:
	if entry.get("sold", false):
		_spr.texture = null
		_label.text = ""
		queue_redraw()
		return
	if entry["kind"] == "item":
		var blind: bool = RunController.instance.curse_effect() == "blind_items"
		_spr.texture = Art.texture("items", "unknown" if blind else str(entry["id"]))
	else:
		_spr.texture = Art.texture("pickups", str(entry["id"]))
	if entry.has("heart_cost"):
		_label.text = "♥".repeat(int(entry["heart_cost"]))
		_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.3))
	else:
		_label.text = str(entry.get("price", 0))
		_label.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_spr.position = Vector2(0, -10 + sin(_t * 2.0) * 1.0)
	if entry.get("sold", false) or _cooldown > 0.0:
		return
	var p: Node2D = RunController.instance.player
	if p and p.global_position.distance_to(global_position) < 11.0:
		_cooldown = 0.8
		_try_buy(p)


func _try_buy(p: Node2D) -> void:
	if entry.has("heart_cost"):
		var halves: int = int(entry["heart_cost"]) * 2
		# Can't pay with containers you don't have, and can't buy yourself to death.
		if RunState.hearts_max < halves or (RunState.hearts_max - halves <= 0 and RunState.shields.is_empty()):
			Audio.play_sfx("cant_afford")
			return
		RunState.hearts_max -= halves
		RunState.hearts = mini(RunState.hearts, RunState.hearts_max)
		RunState.flags["took_den"] = true
	else:
		var price: int = int(entry.get("price", 0))
		if RunState.mana < price:
			Audio.play_sfx("cant_afford")
			return
		if entry["kind"] == "pickup":
			if not PickupScript.apply_pickup(Content.get_entry("pickups", str(entry["id"]))):
				return
		RunState.add_mana(-price)
		MetaSave.add_counter("shop_purchases")
	if entry["kind"] == "item":
		var left: String = p.pickup_item(str(entry["id"]))
		if left != "":
			room.add_extra_pedestal(left, global_position + Vector2(0, 22))
	entry["sold"] = true
	Audio.play_sfx("buy")
	RunController.instance.fx.burst(global_position, Color(0.6, 0.95, 1.0), 10, 40.0, 1.2)
	_refresh()


func _draw() -> void:
	if entry.get("sold", false):
		return
	draw_rect(Rect2(-7, -3, 14, 5), Color(0.3, 0.24, 0.2))
