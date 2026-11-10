extends RefCounted
## On-hit proc rolled per hit: {"type": "proc", "kind": "crit"|"chain"|"stun"|"element"|"knockback",
##  "chance": 0.1, "per_luck": 0.01, "params": {...}}  Resolved in ProjectileSystem._apply_procs.
const PERSISTENT := true


static func apply(_host: EffectHost, e: Dictionary, source_id: String) -> void:
	RunState.procs.append({"kind": e["kind"], "chance": float(e.get("chance", 0.1)),
		"per_luck": float(e.get("per_luck", 0.0)), "params": e.get("params", {}), "source": source_id})
