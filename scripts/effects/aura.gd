extends RefCounted
## {"type": "aura", "radius": 28, "dps": 3}  Damages enemies near the wasp (ticks every 0.5 s).
const PERSISTENT := true


static func apply(_host: EffectHost, e: Dictionary, _source_id: String) -> void:
	RunState.auras.append({"radius": float(e.get("radius", 28)), "dps": float(e.get("dps", 3))})
