extends RefCounted
## {"type": "consumables", "mana": 3, "dig_charges": 5, "royal_jelly": 2}  One-shot grant on pickup.
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, _item_id: String) -> void:
	if e.has("mana"):
		RunState.add_mana(int(e["mana"]))
	if e.has("dig_charges"):
		RunState.add_dig_charges(int(e["dig_charges"]))
	if e.has("royal_jelly"):
		RunState.add_royal_jelly(int(e["royal_jelly"]))
