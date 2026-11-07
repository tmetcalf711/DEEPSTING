extends RefCounted
## Stationary. Telegraphs, then fires a 4-way burst alternating + and x.
var interval := 2.4
var bullet_speed := 85.0
var windup := 0.55
var _t := 0.0
var _diag := false
var _armed := false
var count := 4


func init(e: Enemy, p: Dictionary) -> void:
	interval = float(p.get("interval", 2.4))
	bullet_speed = float(p.get("bullet_speed", 85))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.55))
	count = int(p.get("count", 4))
	_t = interval * e.rng.randf_range(0.4, 1.0)


func tick(e: Enemy, delta: float) -> void:
	e.velocity = Vector2.ZERO
	_t -= delta
	if not _armed and _t <= windup:
		_armed = true
		e.telegraph(windup)
	if _t <= 0.0:
		_armed = false
		_t = interval
		var step := TAU / count
		var off := step / 2.0 if _diag else 0.0
		for i in count:
			e.fire(Vector2.from_angle(off + i * step) * bullet_speed)
		_diag = not _diag
