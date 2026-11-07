extends RefCounted
## Mole cricket: surfaces, telegraphs, sprays a ring, burrows, tunnels toward the player, repeats.
enum S { SURFACED, UNDER, EMERGING }
var dig_speed := 70.0
var under_time := 1.3
var surface_time := 1.6
var ring := 6
var bullet_speed := 75.0
var windup := 0.5
var _s: S = S.SURFACED
var _t := 0.0
var _fired := false


func init(e: Enemy, p: Dictionary) -> void:
	dig_speed = float(p.get("dig_speed", 70))
	under_time = float(p.get("under_time", 1.3))
	surface_time = float(p.get("surface_time", 1.6))
	ring = int(p.get("ring", 6))
	bullet_speed = float(p.get("bullet_speed", 75))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.5))
	_t = surface_time * e.rng.randf_range(0.3, 1.0)


func tick(e: Enemy, delta: float) -> void:
	_t -= delta
	match _s:
		S.SURFACED:
			e.velocity = Vector2.ZERO
			if not _fired and _t <= surface_time * 0.5:
				_fired = true
				var off: float = e.rng.randf() * TAU
				for i in ring:
					e.fire(Vector2.from_angle(off + TAU * i / ring) * bullet_speed)
			if _t <= 0.0:
				_s = S.UNDER
				_t = under_time
				e.untargetable = true
				RunController.instance.fx.burst(e.global_position, Color(0.4, 0.3, 0.2), 8, 40.0, 1.5)
		S.UNDER:
			e.velocity = e.to_player().normalized() * dig_speed
			if _t <= 0.0:
				_s = S.EMERGING
				_t = windup
				e.velocity = Vector2.ZERO
				e.untargetable = false
				e.telegraph(windup)
		S.EMERGING:
			e.velocity = Vector2.ZERO
			if _t <= 0.0:
				_s = S.SURFACED
				_t = surface_time
				_fired = false
				RunController.instance.fx.burst(e.global_position, Color(0.4, 0.3, 0.2), 10, 50.0, 1.5)
