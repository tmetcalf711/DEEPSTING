extends RefCounted
## {"type": "stat_mod", "stat": "damage", "add": 1.0, "mult": 1.0}
const PERSISTENT := true


static func apply(_host: EffectHost, e: Dictionary, item_id: String) -> void:
	RunState.stat_mods.append({"stat": e["stat"], "add": float(e.get("add", 0.0)), "mult": float(e.get("mult", 1.0)), "source": item_id})
