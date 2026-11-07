extends Node2D
## Royal Chamber (angel-deal equivalent): choose one of two Royal items; the other vanishes.

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	if not room.info.has("extra_pedestals"):
		var choices: Array = room.info.get("choices", [])
		for i in choices.size():
			room.add_extra_pedestal(str(choices[i]), Vector2(room.room_w / 2.0 + (i - (choices.size() - 1) / 2.0) * 48.0, room.room_h / 2.0), "royal")


func _draw() -> void:
	draw_circle(Vector2(room.room_w / 2.0, room.room_h / 2.0), 50.0, Color(1.0, 0.95, 0.7, 0.12))
