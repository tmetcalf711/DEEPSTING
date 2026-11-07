extends Node
## Vault (double Royal Jelly lock): a Vault pool item plus a pile of Mana.

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	if not room.info.get("loot_spawned", false):
		room.info["loot_spawned"] = true
		for i in 3:
			room.drop_from_table("vault", room.center() + Vector2(0, 22), true)
