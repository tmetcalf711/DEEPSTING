extends RefCounted
## Synergy-lab training dummy: stands still, never dies (see Enemy.take_hit show_damage).


func init(_e: Enemy, _p: Dictionary) -> void:
	pass


func tick(e: Enemy, _delta: float) -> void:
	e.velocity = Vector2.ZERO
