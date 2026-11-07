extends Control
## Isaac-style minimap: visited rooms are bright, adjacent known rooms are dim, the current room
## is outlined, big rooms span their cells. Special room icons appear once a room is known.
## Curses: Tremor shows only visited rooms; Silt hides room icons. Items: Mole Map reveals rooms,
## Reading Glasses reveal secret rooms.

const CW := 9.0
const CH := 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.minimap_changed.connect(queue_redraw)
	Events.room_entered.connect(func(_i: int) -> void: queue_redraw())
	Events.item_picked_up.connect(func(_i: String) -> void: queue_redraw())


static func is_known(rooms: Dictionary, a: Vector2i, effect: String) -> bool:
	var info: Dictionary = rooms[a]
	if info.get("offmap", false):
		return false
	var secret: bool = info["type"] in FloorGen.SECRET_TYPES
	if info.get("visited", false) or info.get("revealed", false):
		return true
	if effect == "lost_map":
		return false
	if secret and RunState.flags.get("see_secrets", false):
		return true
	if not secret and RunState.flags.get("map_reveal", false):
		return true
	for s in info["links"]:
		var b: Vector2i = info["links"][s][0]
		if rooms.has(b) and rooms[b].get("visited", false):
			if info["doors"][s] != "secret" or info.get("opened_secret", {}).has(s):
				return true
	return false


func _draw() -> void:
	var rc := RunController.instance
	if rc == null or rc.layout.is_empty():
		return
	var effect := rc.curse_effect()
	var rooms: Dictionary = rc.layout["rooms"]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var cur: Vector2i = rc.current_anchor
	if rooms.has(cur) and rooms[cur].get("offmap", false):
		cur = rc.layout["boss"]
	var origin := size / 2.0 - Vector2(CW, CH) / 2.0
	for a in rooms:
		if not is_known(rooms, a, effect):
			continue
		var info: Dictionary = rooms[a]
		var col := Color(0.85, 0.8, 0.7) if info.get("visited", false) else Color(0.4, 0.37, 0.33)
		var bounds := Rect2()
		var first := true
		for c in info["cells"]:
			var p := origin + Vector2((c.x - cur.x) * (CW + 1), (c.y - cur.y) * (CH + 1))
			var r := Rect2(p, Vector2(CW, CH))
			bounds = r if first else bounds.merge(r)
			first = false
		if bounds.position.x < 0 or bounds.position.y < 0 or bounds.end.x > size.x or bounds.end.y > size.y:
			continue
		draw_rect(bounds, col)  # merged cells (fills the 1 px seams inside big rooms)
		if a == rc.current_anchor or (a == cur and cur != rc.current_anchor):
			draw_rect(bounds.grow(1), Color(1, 1, 1), false, 1.0)
		if effect == "unknown_rooms":
			continue
		var icon := _icon(info)
		if icon.a > 0.0:
			draw_rect(Rect2(bounds.get_center() - Vector2(2, 2), Vector2(4, 4)), icon)


static func _icon(info: Dictionary) -> Color:
	if info.get("brood_cell", false) and not info.get("cleared", false):
		return Color(1.0, 0.95, 0.8)
	match str(info["type"]):
		"boss": return Color(0.85, 0.1, 0.1)
		"treasure": return Color(1.0, 0.8, 0.15)
		"shop": return Color(0.35, 0.8, 0.9)
		"secret", "super_secret": return Color(0.3, 0.25, 0.2)
		"brood_cell": return Color(1.0, 0.95, 0.8)
		"curse": return Color(0.55, 0.2, 0.5)
		"sacrifice": return Color(0.6, 0.55, 0.5)
		"challenge": return Color(0.95, 0.5, 0.15)
		"miniboss": return Color(0.6, 0.2, 0.2)
		"vault": return Color(1.0, 0.9, 0.4)
		"arcade": return Color(0.95, 0.35, 0.65)
		"library": return Color(0.55, 0.4, 0.7)
	return Color.TRANSPARENT
