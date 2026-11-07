class_name FX
extends Node2D
## Lightweight pooled particle/juice effects drawn in one node. Purely cosmetic: uses the
## "fx" RNG stream, which is allowed to desync.

class P:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var max_life := 1.0
	var size := 1.0
	var color := Color.WHITE
	var kind := 0  # 0 dot, 1 ring, 2 warning circle
	var grav := 0.0

var parts: Array[P] = []
var _pool: Array[P] = []


func _ready() -> void:
	z_index = 6


func _rng() -> RandomNumberGenerator:
	return RNG.stream("fx")


func _add(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, color: Color, grav: float = 0.0) -> void:
	if parts.size() > 1200:
		return
	var p: P = _pool.pop_back() if not _pool.is_empty() else P.new()
	p.kind = kind
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.size = size
	p.color = color
	p.grav = grav
	parts.append(p)


func burst(pos: Vector2, color: Color, count: int = 10, speed: float = 60.0, size: float = 1.5) -> void:
	var r := _rng()
	for i in count:
		var v := Vector2.from_angle(r.randf() * TAU) * speed * r.randf_range(0.3, 1.0)
		_add(0, pos, v, r.randf_range(0.25, 0.55), size * r.randf_range(0.7, 1.3), color, 60.0)


func splat(pos: Vector2, color: Color) -> void:
	burst(pos, color, 4, 30.0, 1.0)


func spark(pos: Vector2, color: Color) -> void:
	burst(pos, color.lightened(0.4), 3, 50.0, 0.8)


func ring(pos: Vector2, radius: float, color: Color, life: float = 0.3) -> void:
	_add(1, pos, Vector2.ZERO, life, radius, color)


## Telegraph circle on the ground (falling rubble etc.) that fills up until it lands.
func warn(pos: Vector2, radius: float, duration: float) -> void:
	_add(2, pos, Vector2.ZERO, duration, radius, Color(0.9, 0.2, 0.2, 0.8))


func dust(pos: Vector2) -> void:
	var r := _rng()
	for i in 3:
		_add(0, pos + Vector2(r.randf_range(-5, 5), 0), Vector2(r.randf_range(-6, 6), r.randf_range(4, 14)), 0.9, 1.0, Color(0.75, 0.68, 0.55, 0.8), 10.0)


func explosion(pos: Vector2, radius: float) -> void:
	ring(pos, radius, Color(1.0, 0.85, 0.5), 0.35)
	burst(pos, Color(1.0, 0.6, 0.2), 24, 140.0, 2.5)
	burst(pos, Color(0.35, 0.3, 0.28), 16, 70.0, 3.0)


func _process(delta: float) -> void:
	var i := 0
	while i < parts.size():
		var p := parts[i]
		p.life -= delta
		if p.life <= 0.0:
			_pool.append(p)
			parts[i] = parts[parts.size() - 1]
			parts.pop_back()
			continue
		p.vel.y += p.grav * delta
		p.vel *= 0.92
		p.pos += p.vel * delta
		i += 1
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var t := p.life / p.max_life
		var c := p.color
		if p.kind != 2:
			c.a *= t
		match p.kind:
			0:
				draw_rect(Rect2(p.pos - Vector2.ONE * p.size * 0.5, Vector2.ONE * p.size), c)
			1:
				draw_arc(p.pos, p.size * (1.0 - t * 0.6), 0, TAU, 24, c, 2.0)
			2:
				var k := 1.0 - t
				draw_circle(p.pos, p.size, Color(0, 0, 0, 0.25 + 0.25 * k))
				draw_circle(p.pos, p.size * k, Color(p.color.r, p.color.g, p.color.b, 0.35))
				draw_arc(p.pos, p.size, 0, TAU, 20, Color(p.color.r, p.color.g, p.color.b, 0.9), 1.0)
