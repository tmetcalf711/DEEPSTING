extends RefCounted
## Fast, weak, approaches from a flanking offset, then commits.
var speed := 62.0
var flank := 22.0
var _ang := 0.0


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 62))
	flank = float(p.get("flank", 22))
	_ang = e.rng.randf_range(-1.2, 1.2)


func tick(e: Enemy, _delta: float) -> void:
	var tp := e.to_player()
	var goal := tp
	if tp.length() > 34.0:
		goal = tp + tp.normalized().rotated(PI / 2.0 * signf(_ang)) * flank * absf(_ang)
	e.velocity = goal.normalized() * speed
