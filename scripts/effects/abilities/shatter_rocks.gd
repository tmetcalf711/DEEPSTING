extends RefCounted
## Every breakable rock in the room shatters (tinted rocks drop their loot).


static func activate(_player: Node2D, _params: Dictionary) -> void:
	var room: Room = RunController.instance.room
	for y in room.rows:
		for x in room.cols:
			room.destroy_tile(Vector2i(x, y))
	RunController.instance.shake(0.5)
