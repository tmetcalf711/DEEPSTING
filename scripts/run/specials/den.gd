extends Node2D
## Mutation Den (devil-deal equivalent): mutation items that cost heart containers.

const WareScript := preload("res://scripts/actors/ware.gd")

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	var wares: Array = room.info.get("wares", [])
	for i in wares.size():
		var w: Node2D = WareScript.new()
		w.setup(room, wares[i])
		w.position = Vector2(room.room_w / 2.0 + (i - (wares.size() - 1) / 2.0) * 44.0, room.room_h / 2.0)
		room.entities.add_child(w)


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(room.room_w / 2.0, room.room_h / 2.0), 46.0, Color(0.5, 0.05, 0.1, 0.18))
