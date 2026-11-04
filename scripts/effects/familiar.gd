extends RefCounted
## {"type": "familiar", "behavior": "shooter", "sprite": "toy_soldier", "params": {...}}
const PERSISTENT := true


static func apply(host: EffectHost, e: Dictionary, _item_id: String) -> void:
	host.add_familiar(e.get("params", {}), str(e.get("sprite", "familiar")))
