extends RefCounted
## {"type": "perma_stat", "stat": "damage", "add": 0.4}  A permanent change for the rest of the run
## (Strange Fluids). Unlike stat_mod it isn't tied to owning something.
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, source_id: String) -> void:
	RunState.perma_mods.append({"stat": e["stat"], "add": float(e.get("add", 0.0)), "mult": float(e.get("mult", 1.0)), "source": source_id})
	Events.stats_changed.emit()
