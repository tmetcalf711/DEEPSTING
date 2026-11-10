extends RefCounted
## {"type": "trigger", "event": "kill"|"room_clear"|"floor_start"|"damage_taken",
##  "chance": 0.05, "per_luck": 0.01, "action": {"kind": "pickup", "id": "chitin"}}
## Actions are the generic library in EffectHost.do_action (pickup, heal, shield, mana, dig_charge,
## royal_jelly, radiation, charge_active, stun_room, burst).
const PERSISTENT := true


static func apply(_host: EffectHost, e: Dictionary, source_id: String) -> void:
	var t := e.duplicate(true)
	t["source"] = source_id
	RunState.triggers.append(t)
