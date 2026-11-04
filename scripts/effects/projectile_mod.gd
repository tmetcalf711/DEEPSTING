extends RefCounted
## {"type": "projectile_mod", "modifier": "pierce"|"bounce"|"split"|"homing"|"size"|"element"|"spectral", "params": {...}}
## Composition rules live in ShotSpec.build().
const PERSISTENT := true


static func apply(_host: EffectHost, e: Dictionary, item_id: String) -> void:
	RunState.shot_mods.append({"modifier": e["modifier"], "params": e.get("params", {}), "source": item_id})
