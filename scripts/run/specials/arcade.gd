extends Node
## Arcade: gamble Mana on machines (config/arcade.json).

const MachineScript := preload("res://scripts/actors/arcade_machine.gd")

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	var cfg: Dictionary = Content.get_entry("config", "arcade").get("machines", {})
	var ids: Array = room.info.get("machines", [])
	for i in ids.size():
		var m: Node2D = MachineScript.new()
		m.setup(room, str(ids[i]), cfg.get(ids[i], {}))
		m.position = Vector2(room.room_w / 2.0 + (i - (ids.size() - 1) / 2.0) * 44.0, 36)
		room.entities.add_child(m)
