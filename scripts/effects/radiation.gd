extends RefCounted
## {"type": "radiation", "amount": 30}  Adds to the radiation meter (one-shot).
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, _source_id: String) -> void:
	RunState.add_radiation(float(e.get("amount", 10)))
