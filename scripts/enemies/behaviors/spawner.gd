extends RefCounted
## Spawner (urn spiders, clogs...): mostly stationary; every so often telegraphs and births a
## minion, up to a cap. Minions never roll champion.
var interval := 3.5
var minion := "feral_ant"
var cap := 3
var windup := 0.6
var _t := 0.0
var _children: Array = []


func init(e: Enemy, p: Dictionary) -> void:
	interval = float(p.get("interval", 3.5))
	minion = str(p.get("minion", "feral_ant"))
	cap = int(p.get("cap", 3))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.6))
	_t = interval * e.rng.randf_range(0.4, 0.9)


func tick(e: Enemy, delta: float) -> void:
	e.velocity = Vector2.ZERO
	_children = _children.filter(func(c: Variant) -> bool: return is_instance_valid(c) and not c.dead)
	_t -= delta
	if _t <= windup and not e.is_telegraphing() and _t > 0.0:
		e.telegraph(windup)
	if _t <= 0.0:
		_t = interval
		if _children.size() < cap:
			var data: Dictionary = Content.get_entry("enemies", minion)
			var at: Vector2 = e.room.nearest_free_point(e.global_position + Vector2.from_angle(e.rng.randf() * TAU) * 14.0)
			_children.append(e.room.spawn_enemy(data, at, false, false))
