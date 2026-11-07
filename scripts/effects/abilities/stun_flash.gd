extends RefCounted
## Dead Phone-style flash: stuns every enemy in the room.


static func activate(player: Node2D, params: Dictionary) -> void:
	var rc := RunController.instance
	rc.screen_flash(Color(1, 1, 1, 0.8))
	for e in rc.room.room_enemies():
		e.stun(float(params.get("duration", 2.5)))
