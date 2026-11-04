extends Node2D
## Item pedestal. Touch to take the item. Active items swap: your old active is left behind.

const QUALITY_COLORS: Array[Color] = [Color(0.6, 0.6, 0.6), Color(0.95, 0.95, 0.95), Color(0.4, 0.9, 0.4), Color(0.35, 0.6, 1.0), Color(1.0, 0.75, 0.2)]

var room: Node
var item_id: String = ""
var _t := 0.0
var _spr: Sprite2D
var _cooldown := 0.0


func setup(p_room: Node, id: String) -> void:
	room = p_room
	item_id = id


func _ready() -> void:
	_spr = Sprite2D.new()
	add_child(_spr)
	_refresh()


func _refresh() -> void:
	_spr.texture = Art.texture("items", item_id) if item_id != "" else null
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_spr.position = Vector2(0, -14 + sin(_t * 2.5) * 1.5)
	queue_redraw()
	var player: Node2D = RunController.instance.player
	if item_id == "" or player == null or _cooldown > 0.0:
		return
	if player.global_position.distance_to(global_position + Vector2(0, -2)) < 11.0:
		var left_behind: String = player.pickup_item(item_id)
		item_id = left_behind
		room.info["pedestal"] = item_id
		_cooldown = 1.0
		_refresh()


func _draw() -> void:
	draw_rect(Rect2(-7, -6, 14, 8), Color(0.38, 0.3, 0.24))
	draw_rect(Rect2(-7, -6, 14, 2), Color(0.55, 0.45, 0.35))
	if item_id != "":
		var q: int = int(Content.get_entry("items", item_id).get("quality", 1))
		var c := QUALITY_COLORS[clampi(q, 0, 4)]
		c.a = 0.25 + 0.1 * sin(_t * 3.0)
		draw_circle(Vector2(0, -14), 9.0, c)
		draw_circle(Vector2(0, -2), 3.0, Color(0, 0, 0, 0.3))
