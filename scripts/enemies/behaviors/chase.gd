extends RefCounted
## Walks at the player. Two-headed grubs "argue": random short stutters.
var speed := 40.0
var stutter_chance := 0.2
var _stutter := 0.0
var _check := 0.8


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 40))
	stutter_chance = float(p.get("stutter_chance", 0.2))


func tick(e: Enemy, delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = e.rng.randf_range(0.6, 1.2)
		if e.rng.randf() < stutter_chance:
			_stutter = 0.35
	if _stutter > 0.0:
		_stutter -= delta
		e.velocity = Vector2.ZERO
		return
	e.velocity = e.to_player().normalized() * speed
