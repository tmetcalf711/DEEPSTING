extends RefCounted
## {"type": "room_stat", "stat": "damage", "add": 2.0}  Lasts until you leave the room.
## {"type": "room_stat", "flag": "flight"}           a room-only flag.
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, source_id: String) -> void:
	if e.has("flag"):
		RunState.room_flags[str(e["flag"])] = true
	else:
		RunState.room_mods.append({"stat": e["stat"], "add": float(e.get("add", 0.0)), "mult": float(e.get("mult", 1.0)), "source": source_id})
	Events.stats_changed.emit()
