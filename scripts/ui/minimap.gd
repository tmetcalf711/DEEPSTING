extends Control
## Isaac-style minimap: visited rooms are bright, adjacent known rooms are dim, the current room
## is outlined. Special room icons appear once a room is known.

const CW := 9.0
const CH := 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.minimap_changed.connect(queue_redraw)
	Events.room_entered.connect(func(_i: int) -> void: queue_redraw())


func _known(rooms: Dictionary, c: Vector2i) -> bool:
	var info: Dictionary = rooms[c]
	if info.get("visited", false) or info.get("revealed", false):
		return true
	for d in info["doors"]:
		var n: Vector2i = c + FloorGen.DIRS[d]
		if rooms.has(n) and rooms[n].get("visited", false):
			if info["doors"][d] != "secret" or info.get("opened_secret", {}).has(d):
				return true
	return false


func _draw() -> void:
	var rc := RunController.instance
	if rc == null or rc.layout.is_empty():
		return
	var rooms: Dictionary = rc.layout["rooms"]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var cur: Vector2i = rc._current
	var origin := size / 2.0 - Vector2(CW, CH) / 2.0
	for c in rooms:
		if not _known(rooms, c):
			continue
		var info: Dictionary = rooms[c]
		var p := origin + Vector2((c.x - cur.x) * (CW + 1), (c.y - cur.y) * (CH + 1))
		if p.x < 0 or p.y < 0 or p.x + CW > size.x or p.y + CH > size.y:
			continue
		var col := Color(0.85, 0.8, 0.7) if info.get("visited", false) else Color(0.4, 0.37, 0.33)
		draw_rect(Rect2(p, Vector2(CW, CH)), col)
		if c == cur:
			draw_rect(Rect2(p, Vector2(CW, CH)).grow(1), Color(1, 1, 1), false, 1.0)
		var icon := Color.TRANSPARENT
		match str(info["type"]):
			"boss": icon = Color(0.85, 0.1, 0.1)
			"treasure": icon = Color(1.0, 0.8, 0.15)
			"secret", "super_secret": icon = Color(0.3, 0.25, 0.2)
			"brood_cell": icon = Color(1.0, 0.95, 0.8)
		if info.get("brood_cell", false) and not info.get("cleared", false):
			icon = Color(1.0, 0.95, 0.8)
		if icon.a > 0.0:
			draw_rect(Rect2(p + Vector2(2.5, 1.5), Vector2(4, 4)), icon)
