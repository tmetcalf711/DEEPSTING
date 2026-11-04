extends Node2D
## Worker wasp: flies in from the nest-side door (or down the boss shaft), harvests a deposit or
## picks up a rescued larva, and flies back out. Untargetable, invulnerable, ignored by enemies
## (DESIGN.md §5.2). Purely visual + timing.

signal finished()

enum S { WAIT, GO, WORK, RETURN }

const SPEED := 115.0
const HEIGHT := 9.0

var room: Node
var home := Vector2.ZERO
var target: Node2D = null       # deposit / loot pile
var larva: Node2D = null        # escort mode
var state: S = S.WAIT
var _delay := 0.0
var _work := 0.0
var _carry_color := Color.TRANSPARENT
var _t := 0.0
var _spr: Sprite2D


func setup_haul(p_room: Node, from: Vector2, deposit: Node2D, delay: float) -> void:
	room = p_room
	home = from
	target = deposit
	_delay = delay
	position = from


func setup_escort(p_room: Node, from: Vector2, larva_pos: Vector2, delay: float) -> void:
	room = p_room
	home = from
	_delay = delay + 0.3
	position = from
	larva = Node2D.new()
	larva.set_script(preload("res://scripts/actors/larva.gd"))
	larva.position = larva_pos
	larva.set("goal", from)
	p_room.entities.add_child.call_deferred(larva)


func _ready() -> void:
	z_index = 2
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("workers", "worker")
	add_child(_spr)
	visible = false


func _process(delta: float) -> void:
	_t += delta
	_spr.position.y = -HEIGHT + sin(_t * 18.0) * 0.8
	_spr.scale.y = 1.0 + sin(_t * 40.0) * 0.12
	queue_redraw()
	match state:
		S.WAIT:
			_delay -= delta
			if _delay <= 0.0:
				visible = true
				state = S.GO
		S.GO:
			var goal := _goal()
			if goal == null:
				state = S.RETURN
				return
			_fly(goal.global_position + Vector2(sin(_t * 3.0 + get_instance_id()) * 3.0, -2), delta)
			if position.distance_to(goal.global_position) < 5.0:
				state = S.WORK
				_work = 0.25 if larva else 1.1
		S.WORK:
			_work -= delta
			position += Vector2(sin(_t * 14.0), cos(_t * 11.0)) * 0.3
			if _work <= 0.0:
				if larva:
					larva.queue_free()
					larva = null
					_carry_color = Color(1, 0.96, 0.85)
				elif is_instance_valid(target):
					target.take_chunk()
					_carry_color = Color.from_string(str(Content.get_entry("resources", str(target.get("resource_id"))).get("color", "#c8a46a")), Color.TAN)
				state = S.RETURN
		S.RETURN:
			_fly(home, delta)
			if position.distance_to(home) < 4.0:
				finished.emit()
				queue_free()


func _goal() -> Node2D:
	if larva:
		return larva if is_instance_valid(larva) and larva.is_inside_tree() else null
	return target if is_instance_valid(target) else null


func _fly(to: Vector2, delta: float) -> void:
	var d := to - position
	var step := SPEED * delta
	position = to if d.length() <= step else position + d.normalized() * step
	_spr.flip_h = d.x < 0


func _draw() -> void:
	if not visible:
		return
	draw_circle(Vector2(0, 1), 2.5, Color(0, 0, 0, 0.3))
	if _carry_color.a > 0.0:
		draw_circle(Vector2(0, -HEIGHT + 4), 2.0, _carry_color)
