extends Node2D
## A resource deposit left by a cleared room. Workers harvest it; its value goes to the
## floor stash when the haul completes.

var resource_id: String = "wood_pulp"
var value: int = 1
var workers_needed: int = 1
var _harvested: int = 0
var _color := Color(0.78, 0.64, 0.42)
var _scale := 0.0
var _t := 0.0


func setup(res_id: String, v: int) -> void:
	resource_id = res_id
	value = v
	_color = Color.from_string(str(Content.get_entry("resources", res_id).get("color", "#c8a46a")), _color)


func _ready() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_scale", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func take_chunk() -> void:
	_harvested += 1
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var remaining := 1.0 - float(_harvested) / float(maxi(1, workers_needed))
	var s := _scale * (0.35 + 0.65 * remaining) * (0.8 + 0.08 * value)
	if s <= 0.01:
		return
	draw_circle(Vector2(0, 1), 6.0 * s, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(-2, -1) * s, 4.0 * s, _color.darkened(0.2))
	draw_circle(Vector2(2, -2) * s, 3.5 * s, _color)
	draw_circle(Vector2(0, -3.5) * s, 3.0 * s, _color.lightened(0.15))
	if fmod(_t, 1.6) < 0.15:
		draw_circle(Vector2(1, -5) * s, 1.0, Color(1, 1, 1, 0.9))
