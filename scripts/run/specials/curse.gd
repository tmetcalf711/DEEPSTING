extends Node
## Curse room (spiked door): a Cursed pool item, or shield pickups.

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	if not room.info.has("pedestal") and not room.info.get("loot_spawned", false):
		room.info["loot_spawned"] = true
		for i in 2:
			room.drop_from_table("curse_room", room.center(), true)
