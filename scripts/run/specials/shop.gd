extends Node2D
## Trader shop run by Mott the pack rat: item and consumable wares for Mana.

const WareScript := preload("res://scripts/actors/ware.gd")

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	var npc := Sprite2D.new()
	npc.texture = Art.texture("npcs", "mott")
	npc.position = Vector2(room.room_w / 2.0, 22)
	room.entities.add_child(npc)
	var wares: Array = room.info.get("wares", [])
	for i in wares.size():
		var w: Node2D = WareScript.new()
		w.setup(room, wares[i])
		w.position = Vector2(room.room_w / 2.0 + (i - (wares.size() - 1) / 2.0) * 30.0, 62)
		room.entities.add_child(w)
	if not room.info.get("greeted", false):
		room.info["greeted"] = true
		Events.toast.emit(tr("SHOP_GREET_%d" % (int(room.info["index"]) % 3 + 1)))
