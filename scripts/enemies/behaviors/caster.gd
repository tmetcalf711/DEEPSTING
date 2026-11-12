extends RefCounted
## Bullet-pattern caster (lantern centipedes, skull moths...): drifts slowly, telegraphs, then
## casts a pattern: "ring" (n around), "fan" (n aimed), "spiral" (two arms over time).
var speed := 18.0
var interval := 2.6
var pattern := "fan"
var count := 5
var bullet_speed := 80.0
var homing := 0.0
var windup := 0.6
var _t := 0.0
var _casting := 0.0
var _arm := 0.0
var _drift := Vector2.RIGHT


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 18))
	interval = float(p.get("interval", 2.6))
	pattern = str(p.get("pattern", "fan"))
	count = int(p.get("count", 5))
	bullet_speed = float(p.get("bullet_speed", 80))
	homing = float(p.get("homing", 0.0))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.6))
	_t = interval * e.rng.randf_range(0.5, 1.0)
	_drift = Vector2.from_angle(e.rng.randf() * TAU)


func tick(e: Enemy, delta: float) -> void:
	if _casting > 0.0:
		_casting -= delta
		e.velocity = Vector2.ZERO
		if pattern == "spiral":
			_arm += delta * 7.0
			if int(_arm * 10.0) % 2 == 0:
				for k in 2:
					e.fire(Vector2.from_angle(_arm + k * PI) * bullet_speed, ProjectileSystem.ENEMY_GREEN)
		return
	_t -= delta
	if _t <= windup and not e.is_telegraphing() and _t > 0.0:
		e.telegraph(windup)
	if _t <= 0.0:
		_t = interval
		var color := ProjectileSystem.ENEMY_VIOLET if homing > 0.0 else ProjectileSystem.ENEMY_RED
		match pattern:
			"ring":
				var off: float = e.rng.randf() * TAU
				for i in count:
					e.fire(Vector2.from_angle(off + TAU * i / count) * bullet_speed, color, 3.0, homing)
			"spiral":
				_casting = 0.9
			_:
				var base := e.to_player().angle()
				for i in count:
					e.fire(Vector2.from_angle(base + (i - (count - 1) / 2.0) * 0.22) * bullet_speed, color, 3.0, homing)
		return
	if e.get_slide_collision_count() > 0:
		_drift = -_drift.rotated(e.rng.randf_range(-0.8, 0.8))
	e.velocity = (_drift + e.to_player().normalized() * 0.3).normalized() * speed
