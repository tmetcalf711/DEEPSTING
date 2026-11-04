extends RefCounted
## Erratic flight over rocks and pits; periodically telegraphs and dives at the player.
var speed := 38.0
var dive_speed := 120.0
var dive_interval := 3.0
var windup := 0.4
var _wander := Vector2.ZERO
var _retarget := 0.0
var _dive_t := 0.0
var _diving := 0.0
var _dive_dir := Vector2.ZERO


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 38))
	dive_speed = float(p.get("dive_speed", 120))
	dive_interval = float(p.get("dive_interval", 3.0))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.4))
	_dive_t = dive_interval * e.rng.randf_range(0.5, 1.2)


func tick(e: Enemy, delta: float) -> void:
	if _diving > 0.0:
		_diving -= delta
		e.velocity = _dive_dir * dive_speed
		return
	_dive_t -= delta
	if _dive_t <= windup and not e.is_telegraphing() and _dive_t > 0.0:
		e.telegraph(windup)
	if _dive_t <= 0.0:
		_dive_t = dive_interval
		_diving = 0.45
		_dive_dir = e.to_player().normalized()
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = e.rng.randf_range(0.5, 1.1)
		_wander = Vector2.from_angle(e.rng.randf() * TAU)
	var toward := e.to_player().normalized() * 0.5
	e.velocity = (_wander + toward).normalized() * speed * (0.3 if e.is_telegraphing() else 1.0)
