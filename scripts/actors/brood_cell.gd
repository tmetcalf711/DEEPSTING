extends StaticBody2D
## Sealed brood cell (DESIGN.md §11.1). Invulnerable until the room is clear; then 3 hits (or a
## blast) break it and 1-3 lost brood are freed and banked immediately.

var room: Node
var tile: Vector2i
var team := "neutral"
var hit_radius := 7.0
var locked := true
var hp := 3
var _t := 0.0
var _shake := 0.0
var _spr: Sprite2D


func setup(p_room: Node, t: Vector2i) -> void:
	room = p_room
	tile = t
	collision_layer = 2
	collision_mask = 0


func _ready() -> void:
	add_to_group("shootable")
	add_to_group("brood_cells")
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(14, 12)
	cs.shape = rs
	add_child(cs)
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("props", "brood_cell")
	_spr.offset = Vector2(0, -2)
	add_child(_spr)
	locked = not room.is_cleared


func unlock() -> void:
	locked = false


func take_hit(damage: float, _dir: Vector2, elements: Array) -> void:
	if locked:
		RunController.instance.fx.spark(global_position, Color(0.9, 0.85, 0.6))
		return
	hp -= 3 if elements.has("blast") else 1
	_shake = 0.15
	Audio.play_sfx("brood_cell_crack")
	if hp <= 0:
		var n: int = room.rng_drops.randi_range(1, 3)
		RunController.instance.fx.burst(global_position, Color(1.0, 0.95, 0.75), 16, 70.0, 2.0)
		RunController.instance.shake(0.2)
		room.on_brood_cell_broken(tile, n)
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta)
	_spr.position.x = sin(_t * 70.0) * 1.5 if _shake > 0.0 else 0.0
	# Unlocked cells pulse so the player knows to break them.
	var pulse := 1.0 + (0.25 * (0.5 + 0.5 * sin(_t * 5.0)) if not locked else 0.0)
	_spr.modulate = Color(pulse, pulse, pulse * 0.9)
	_spr.scale = Vector2.ONE * (1.0 - (3 - hp) * 0.06)
