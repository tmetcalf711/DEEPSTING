extends RefCounted
## Rust beetle: ambles about; when the player lines up on a row or column it telegraphs and
## charges in a straight line until it hits something, then is stunned briefly.
var speed := 20.0
var charge_speed := 165.0
var align := 9.0
var sight := 170.0
var windup := 0.4
var _dir := Vector2.ZERO
var _charging := false
var _winding := 0.0
var _wander := Vector2.RIGHT
var _retarget := 0.0
var _cool := 0.6


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 20))
	charge_speed = float(p.get("charge_speed", 165))
	align = float(p.get("align", 9))
	sight = float(p.get("sight", 170))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.4))


func tick(e: Enemy, delta: float) -> void:
	if _charging:
		e.velocity = _dir * charge_speed
		if e.get_slide_collision_count() > 0:
			_charging = false
			_cool = 0.8
			e.stun(0.6)
			RunController.instance.shake(0.15)
		return
	if _winding > 0.0:
		_winding -= delta
		e.velocity = Vector2.ZERO
		if _winding <= 0.0:
			_charging = true
		return
	_cool -= delta
	var tp := e.to_player()
	if _cool <= 0.0 and tp.length() < sight and (absf(tp.x) < align or absf(tp.y) < align):
		_dir = Vector2(signf(tp.x), 0) if absf(tp.y) < align else Vector2(0, signf(tp.y))
		_winding = windup
		e.telegraph(windup)
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = e.rng.randf_range(0.8, 1.6)
		_wander = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][e.rng.randi_range(0, 3)]
	e.velocity = _wander * speed
