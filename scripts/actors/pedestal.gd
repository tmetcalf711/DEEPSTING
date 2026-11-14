extends Node2D
## Item pedestal. Touch to take the item. Active items swap: your old active is left behind.
## extra_index >= 0 means this pedestal belongs to room.info.extra_pedestals (specials);
## -1 means the room's main pedestal (info.pedestal).

const QUALITY_COLORS: Array[Color] = [Color(0.6, 0.6, 0.6), Color(0.95, 0.95, 0.95), Color(0.4, 0.9, 0.4), Color(0.35, 0.6, 1.0), Color(1.0, 0.75, 0.2)]

var room: Node
var item_id: String = ""
var extra_index := -1
var locked := false    # challenge rooms lock the pedestal until the waves are done
var _t := 0.0
var _spr: Sprite2D
var _cooldown := 0.0


func setup(p_room: Node, id: String, p_extra_index: int = -1) -> void:
	room = p_room
	item_id = id
	extra_index = p_extra_index


const Inspect := preload("res://scripts/ui/inspect.gd")


func _ready() -> void:
	add_to_group("pedestals")
	add_to_group("inspectable")
	_spr = Sprite2D.new()
	add_child(_spr)
	_refresh()


## HUD side-panel label (see scripts/ui/inspect.gd).
func inspect_info() -> Dictionary:
	var d := Inspect.for_item(item_id)
	if not d.is_empty() and locked:
		d["extra"] = tr("INSPECT_LOCKED_CHALLENGE")
	return d


func set_item(id: String) -> void:
	item_id = id
	_refresh()


static func blind() -> bool:
	return RunController.instance != null and RunController.instance.curse_effect() == "blind_items"


func _refresh() -> void:
	if item_id == "":
		_spr.texture = null
	else:
		_spr.texture = Art.texture("items", "unknown" if blind() else item_id)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_spr.position = Vector2(0, -14 + sin(_t * 2.5) * 1.5)
	_spr.modulate.a = 0.4 if locked else 1.0
	queue_redraw()
	var player: Node2D = RunController.instance.player
	if item_id == "" or player == null or _cooldown > 0.0 or locked:
		return
	if player.global_position.distance_to(global_position + Vector2(0, -2)) < 11.0:
		var left_behind: String = player.pickup_item(item_id)
		item_id = left_behind
		room.on_pedestal_changed(extra_index, item_id)
		_cooldown = 1.0
		_refresh()


func _draw() -> void:
	draw_rect(Rect2(-7, -6, 14, 8), Color(0.38, 0.3, 0.24))
	draw_rect(Rect2(-7, -6, 14, 2), Color(0.55, 0.45, 0.35))
	if item_id != "" and not blind():
		var q: int = int(Content.get_entry("items", item_id).get("quality", 1))
		var c := QUALITY_COLORS[clampi(q, 0, 4)]
		c.a = 0.25 + 0.1 * sin(_t * 3.0)
		draw_circle(Vector2(0, -14), 9.0, c)
		draw_circle(Vector2(0, -2), 3.0, Color(0, 0, 0, 0.3))
