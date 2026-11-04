extends Node2D
## A placed Dig Charge (bomb): fuse, then blast rocks, enemies, the player and cracked walls.

const FUSE := 0.9
const RADIUS := 38.0
const DAMAGE := 60.0

var room: Node
var _t := 0.0


func _ready() -> void:
	Audio.play_sfx("dig_charge_place")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= FUSE:
		room.explode(global_position, RADIUS, DAMAGE)
		queue_free()


func _draw() -> void:
	var blink := fmod(_t * (6.0 + _t * 14.0), 1.0) < 0.5
	draw_circle(Vector2(0, 1), 4.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(0, -3), 4.5, Color(0.9, 0.3, 0.2) if blink else Color(0.3, 0.26, 0.24))
	draw_line(Vector2(1, -7), Vector2(3, -10), Color(0.8, 0.7, 0.5), 1.0)
	if blink:
		draw_circle(Vector2(3, -10), 1.2, Color(1, 0.9, 0.4))
