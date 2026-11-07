extends Node2D
## Sacrifice Altar: stepping on the spikes costs half a heart; each sacrifice on the floor rolls
## a better outcome table (config/sacrifice.json).

var room: Room
var _armed := true


func setup(p_room: Room) -> void:
	room = p_room
	# Live in the y-sorted entity layer so the wasp draws over the altar correctly.
	room.remove_child(self)
	room.entities.add_child(self)
	position = room.center()


func _process(_d: float) -> void:
	var p: Node2D = RunController.instance.player
	if p == null:
		return
	var on := p.global_position.distance_to(global_position) < 9.0
	if not on:
		_armed = true
		return
	if not _armed:
		return
	_armed = false
	var cfg: Dictionary = Content.get_entry("config", "sacrifice")
	if not p.hurt(int(cfg.get("damage", 1)), "sacrifice"):
		return
	var uses: int = int(room.info.get("sac_uses", 0))
	room.info["sac_uses"] = uses + 1
	MetaSave.add_counter("sacrifices")
	var table: Array = cfg.get("uses", [])
	var outcomes: Array = table[mini(uses, table.size() - 1)]
	var r := RNG.room_stream("drops", int(room.info["index"]) * 100 + uses)
	var o: Dictionary = outcomes[RNG.weighted_index(r, outcomes.map(func(e: Dictionary) -> float: return float(e["weight"])))]
	var spot := global_position + Vector2(0, 22)
	match str(o["result"]):
		"pickup":
			room.spawn_pickup(str(o["id"]), spot, Vector2(r.randf_range(-30, 30), 30))
		"pickups":
			for i in int(o.get("count", 3)):
				room.spawn_pickup(str(o["id"]), spot, Vector2.from_angle(r.randf() * TAU) * 40.0)
		"item":
			room.add_extra_pedestal(RunController.instance.item_pool.roll(str(o["pool"]), r), spot + Vector2(0, 8))
		_:
			RunController.instance.fx.burst(global_position, Color(0.5, 0.1, 0.1), 8, 30.0, 1.2)


func _draw() -> void:
	draw_rect(Rect2(-10, -8, 20, 14), Color(0.32, 0.3, 0.29))
	draw_rect(Rect2(-10, -8, 20, 3), Color(0.45, 0.42, 0.4))
	for k in 4:
		var x := -7.0 + k * 4.5
		draw_colored_polygon(PackedVector2Array([Vector2(x, 3), Vector2(x + 1.5, -4), Vector2(x + 3, 3)]), Color(0.75, 0.7, 0.7))
