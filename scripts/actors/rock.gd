extends StaticBody2D
## Rock ("R"), tinted rock ("T") or indestructible block ("#"). Visual + collision only; the
## room grid is the source of truth for bullets.

var room: Node
var tile: Vector2i
var kind: String


func setup(p_room: Node, t: Vector2i, ch: String) -> void:
	room = p_room
	tile = t
	kind = ch
	collision_layer = 2
	collision_mask = 0
	position = p_room.tile_center(t)


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(15, 14)
	cs.shape = rs
	add_child(cs)
	var spr := Sprite2D.new()
	var id: String = {"R": "rock", "T": "tinted_rock", "#": "block"}[kind]
	spr.texture = Art.texture("props", id)
	spr.offset = Vector2(0, -2)
	add_child(spr)


func shatter() -> void:
	RunController.instance.fx.burst(global_position, Color(0.5, 0.42, 0.34), 10, 60.0, 2.0)
	Audio.play_sfx("rock_break")
	queue_free()
