extends RefCounted
## Hopper (mud skippers, cap crabs): sits, telegraphs, then leaps toward the player in a burst;
## optionally sprays a ring when it lands.
var leap_speed := 140.0
var leap_time := 0.35
var rest := 1.1
var land_ring := 0
var windup := 0.35
var _t := 0.0
var _leap := 0.0
var _dir := Vector2.ZERO


func init(e: Enemy, p: Dictionary) -> void:
	leap_speed = float(p.get("leap_speed", 140))
	leap_time = float(p.get("leap_time", 0.35))
	rest = float(p.get("rest", 1.1))
	land_ring = int(p.get("land_ring", 0))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.35))
	_t = rest * e.rng.randf_range(0.5, 1.0)


func tick(e: Enemy, delta: float) -> void:
	if _leap > 0.0:
		_leap -= delta
		e.velocity = _dir * leap_speed
		if _leap <= 0.0:
			e.velocity = Vector2.ZERO
			for i in land_ring:
				e.fire(Vector2.from_angle(TAU * i / land_ring) * 70.0)
		return
	e.velocity = Vector2.ZERO
	_t -= delta
	if _t <= windup and not e.is_telegraphing() and _t > 0.0:
		e.telegraph(windup)
	if _t <= 0.0:
		_t = rest
		_leap = leap_time
		_dir = (e.to_player() + Vector2(e.rng.randf_range(-12, 12), e.rng.randf_range(-12, 12))).normalized()
