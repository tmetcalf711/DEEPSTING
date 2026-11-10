extends RefCounted
## {"type": "ability", "ability": "volley", "params": {...}}  Runs an ability script once
## (fossils, fluids). Active items use the "active" effect instead (charge-based).
const PERSISTENT := false


static func apply(host: EffectHost, e: Dictionary, _source_id: String) -> void:
	var s := EffectHost.ability_script(str(e["ability"]))
	if s:
		s.activate(host.player, e.get("params", {}))
