extends Node2D
## Trapdoor down to the next floor. Appears after the boss shaft haul completes.

var _open := 0.0
var _used := false


func _ready() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_open", 1.0, 0.5)
	Audio.play_sfx("trapdoor_open")


func _process(_d: float) -> void:
	queue_redraw()
	var p: Node2D = RunController.instance.player
	if not _used and _open >= 1.0 and p and p.global_position.distance_to(global_position) < 9.0:
		_used = true
		RunController.instance.on_trapdoor()


func _draw() -> void:
	var s := 9.0 * _open
	draw_rect(Rect2(-10, -8, 20, 16), Color(0.3, 0.22, 0.15))
	draw_rect(Rect2(-s, -s * 0.75, s * 2, s * 1.5), Color(0.02, 0.01, 0.01))
