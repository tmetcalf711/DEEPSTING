extends Node2D
## A rescued lost-brood larva wiggling toward the exit until a worker scoops it up.

var goal := Vector2.ZERO
var _t := 0.0
var _spr: Sprite2D


func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("brood", "larva")
	add_child(_spr)


func _process(delta: float) -> void:
	_t += delta
	_spr.scale = Vector2(1.0 + sin(_t * 9.0) * 0.15, 1.0 - sin(_t * 9.0) * 0.15)
	_spr.position.y = -3
	var room: Node = get_parent().get_parent()
	var np := position.move_toward(goal, 14.0 * delta)
	if room and not room.is_bullet_blocked(np, false):
		position = np
