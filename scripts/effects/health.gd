extends RefCounted
## {"type": "health", "heart_containers": 1, "heal": 2, "chitin": 2, "toxic_chitin": 2}  (half-hearts except containers)
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, _item_id: String) -> void:
	if e.has("heart_containers"):
		RunState.add_containers(int(e["heart_containers"]))
	if e.has("heal"):
		# heal: -1 means a full heal
		RunState.heal(RunState.hearts_max if int(e["heal"]) < 0 else int(e["heal"]))
	if e.has("chitin"):
		RunState.add_shield("chitin", int(e["chitin"]))
	if e.has("toxic_chitin"):
		RunState.add_shield("toxic", int(e["toxic_chitin"]))
