extends RefCounted
## {"type": "familiar", "behavior": "shooter"|"orbital"|"biter", "sprite": "toy_soldier", "count": 1, "params": {...}}
const PERSISTENT := true


static func apply(host: EffectHost, e: Dictionary, _source_id: String) -> void:
	for i in int(e.get("count", 1)):
		host.add_familiar(e.get("params", {}), str(e.get("sprite", "familiar")), str(e.get("behavior", "shooter")))
