extends Node
## Mini-boss room: one tough enemy, guaranteed pickups on the kill.

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	if room.is_cleared:
		return
	var data: Dictionary = Content.get_entry("enemies", str(room.info.get("miniboss_id", "")))
	if data.is_empty():
		return
	room.spawn_enemy(data, room.center() + Vector2(0, -12))
	Events.banner.emit(tr(data.get("name_key", "")), tr("BANNER_MINIBOSS"))


func on_cleared() -> void:
	for i in 2:
		room.drop_from_table("miniboss", room.center(), true)
