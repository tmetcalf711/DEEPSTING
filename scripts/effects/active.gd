extends RefCounted
## {"type": "active", "ability": "stun_flash", "charge": 2, "params": {...}}
## Ability behavior lives in res://scripts/effects/abilities/<ability>.gd (static activate()).
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, item_id: String) -> void:
	RunState.active_item = item_id
	RunState.active_max = int(e.get("charge", 1))
	RunState.active_charge = RunState.active_max  # new actives arrive fully charged
	Events.consumables_changed.emit()
