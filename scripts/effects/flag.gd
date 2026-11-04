extends RefCounted
## {"type": "flag", "name": "flight"}  Boolean run flags read by systems (flight, revive_once...).
## Not persistent: one-shot flags like revive_once are consumed, so they must not be re-added
## on rebuild. They're serialized with RunState.flags.
const PERSISTENT := false


static func apply(_host: EffectHost, e: Dictionary, _item_id: String) -> void:
	RunState.flags[str(e["name"])] = true
