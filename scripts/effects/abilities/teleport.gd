extends RefCounted
## Teleports the wasp to the first room of a type on this floor. params: {room_type: "boss"}


static func activate(_player: Node2D, params: Dictionary) -> void:
	var rc := RunController.instance
	var want := str(params.get("room_type", "boss"))
	for a in rc.layout["order"]:
		if rc.layout["rooms"][a]["type"] == want:
			rc.call_deferred("enter_room", a, "")
			return
