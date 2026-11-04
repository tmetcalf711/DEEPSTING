extends Node2D
## The whole floor stash, piled under the boss shaft, carried up by the swarm.

var materials: Dictionary = {}
var workers_needed: int = 1
var _harvested: int = 0
var resource_id := "stash"
var value := 0


func setup(stash: Dictionary) -> void:
	materials = stash
	for k in stash:
		value += int(stash[k])


func take_chunk() -> void:
	_harvested += 1
	queue_redraw()


func _draw() -> void:
	var remaining := 1.0 - float(_harvested) / float(maxi(1, workers_needed))
	if remaining <= 0.0:
		return
	var s := (0.6 + minf(1.2, value / 25.0)) * remaining
	draw_circle(Vector2(0, 2), 10.0 * s, Color(0, 0, 0, 0.3))
	var i := 0
	for k in materials:
		var c := Color.from_string(str(Content.get_entry("resources", k).get("color", "#c8a46a")), Color.TAN)
		var off := Vector2.from_angle(i * 2.1) * 4.0 * s
		draw_circle(off + Vector2(0, -2), 5.0 * s, c)
		i += 1
	if materials.is_empty():
		draw_circle(Vector2(0, -2), 4.0 * s, Color.TAN)
