extends RefCounted
## Drip slug: slow chaser that leaves sludge puddles. Sludge "sticks to wings": even hovering
## wasps are slowed by it (DESIGN.md §3.2).
var speed := 22.0
var drop_interval := 0.55
var creep_kind := "sludge"
var creep_life := 5.0
var _t := 0.0


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 22))
	drop_interval = float(p.get("drop_interval", 0.55))
	creep_kind = str(p.get("creep", "sludge"))
	creep_life = float(p.get("creep_life", 5.0))


func tick(e: Enemy, delta: float) -> void:
	e.velocity = e.to_player().normalized() * speed
	_t -= delta
	if _t <= 0.0:
		_t = drop_interval
		e.room.add_creep(e.global_position, creep_kind, creep_life)
