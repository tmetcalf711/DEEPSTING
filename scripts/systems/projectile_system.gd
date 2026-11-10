class_name ProjectileSystem
extends Node2D
## All projectiles for the current room, simulated in one node with pooled objects (DESIGN.md
## §16.6, D9). No per-bullet nodes. Walls/rocks use the room's tile grid; targets use distance
## checks against the "shootable" group (player shots) or the player (enemy shots).

const MAX_BULLETS := 1500
const SHOT_HEIGHT := 6.0
const FALL_DIST := 24.0
const ENEMY_RED := Color(0.95, 0.22, 0.25)
const ENEMY_GREEN := Color(0.45, 0.95, 0.25)
const OUTLINE := Color(0.08, 0.04, 0.03)
const ELEMENT_COLORS: Dictionary = {"poison": Color(0.45, 1.0, 0.3), "slow": Color(0.6, 0.85, 1.0),
	"burn": Color(1.0, 0.5, 0.15), "shock": Color(1.0, 1.0, 0.4)}


class Bullet:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var friendly := true
	var damage := 0.0
	var radius := 3.0
	var travel_left := 0.0
	var z := 6.0
	var pierce := 0
	var bounce := 0
	var homing := 0.0
	var spectral := false
	var elements: Array = []
	var color := Color.WHITE
	var stretch := 1.0
	var hit: Dictionary = {}
	var spec: Dictionary = {}   # player shots keep their spec for split children
	var alive := true
	var wave_amp := 0.0
	var wave_freq := 0.0
	var wave_off := 0.0
	var age := 0.0
	var boomerang := false
	var returned := false
	var max_range := 0.0
	var knockback := 1.0
	var procs: Array = []


var bullets: Array[Bullet] = []
var _pool: Array[Bullet] = []
var room: Node = null          # Room (duck-typed: is_bullet_blocked(pos, spectral))
var player: Node2D = null
var fx: Node = null
var high_contrast := false


func _ready() -> void:
	z_index = 5
	high_contrast = bool(MetaSave.settings.get("accessibility", {}).get("high_contrast_projectiles", false))


func _new_bullet() -> Bullet:
	var b: Bullet = _pool.pop_back() if not _pool.is_empty() else Bullet.new()
	b.alive = true
	b.hit = {}
	b.elements = []
	b.z = SHOT_HEIGHT
	b.pierce = 0
	b.bounce = 0
	b.homing = 0.0
	b.spectral = false
	b.stretch = 1.0
	b.spec = {}
	b.wave_amp = 0.0
	b.wave_freq = 0.0
	b.wave_off = 0.0
	b.age = 0.0
	b.boomerang = false
	b.returned = false
	b.knockback = 1.0
	b.procs = []
	return b


func spawn_player_shot(pos: Vector2, dir: Vector2, spec: Dictionary, inherit: Vector2 = Vector2.ZERO) -> void:
	if bullets.size() >= MAX_BULLETS:
		return
	var b := _new_bullet()
	b.friendly = true
	b.pos = pos
	b.vel = dir.normalized() * float(spec["speed"]) + inherit
	b.damage = float(spec["damage"])
	b.radius = float(spec["radius"])
	b.travel_left = float(spec["range"])
	b.pierce = int(spec["pierce"])
	b.bounce = int(spec["bounce"])
	b.homing = float(spec["homing"])
	b.spectral = bool(spec["spectral"])
	b.elements = spec["elements"].duplicate()
	b.color = spec["color"]
	b.stretch = float(spec["stretch"])
	b.spec = spec
	b.max_range = b.travel_left
	b.wave_amp = float(spec.get("wave_amp", 0.0))
	b.wave_freq = float(spec.get("wave_freq", 0.0))
	b.boomerang = bool(spec.get("boomerang", false))
	b.knockback = float(spec.get("knockback", 1.0))
	b.procs = spec.get("procs", [])
	bullets.append(b)


## A full trigger pull: `multishot` shots fanned across `spread` (DESIGN.md §6.5).
func spawn_player_volley(pos: Vector2, dir: Vector2, spec: Dictionary, inherit: Vector2 = Vector2.ZERO) -> void:
	var n: int = int(spec.get("multishot", 1))
	if n <= 1:
		spawn_player_shot(pos, dir, spec, inherit)
		return
	var spread: float = float(spec.get("spread", 0.35))
	for i in n:
		var a := (float(i) / float(n - 1) - 0.5) * spread
		spawn_player_shot(pos, dir.rotated(a), spec, inherit)


func spawn_enemy_shot(pos: Vector2, vel: Vector2, color: Color = ENEMY_RED, radius: float = 3.0, travel: float = 400.0) -> void:
	if bullets.size() >= MAX_BULLETS:
		return
	var b := _new_bullet()
	b.friendly = false
	b.pos = pos
	b.vel = vel * (0.8 if RunState.flag("slow_enemy_shots") else 1.0)
	b.damage = 1.0  # half-hearts
	b.radius = radius
	b.travel_left = travel
	b.color = color
	bullets.append(b)


func clear() -> void:
	for b in bullets:
		_pool.append(b)
	bullets.clear()
	queue_redraw()


func clear_enemy_shots() -> void:
	for b in bullets:
		if not b.friendly:
			b.alive = false


func _physics_process(delta: float) -> void:
	if bullets.is_empty():
		queue_redraw()
		return
	# Only targets in the current room (a room being freed this frame may still be in the tree).
	var targets: Array = get_tree().get_nodes_in_group("shootable").filter(func(t: Node) -> bool:
		return room != null and room.is_ancestor_of(t))
	var blockers: Array = get_tree().get_nodes_in_group("bullet_blockers").filter(func(t: Node) -> bool:
		return room != null and room.is_ancestor_of(t))
	var spawned: Array[Bullet] = []
	for b in bullets:
		if not b.alive:
			continue
		b.age += delta
		if b.friendly and b.homing > 0.0 and not b.returned:
			_steer(b, targets, delta)
		if b.boomerang and not b.returned and b.travel_left < b.max_range * 0.5:
			# Boomerang: turn around and fly home, able to hit everything again.
			b.returned = true
			b.hit = {}
			b.travel_left = b.max_range * 0.75
		if b.returned and player and is_instance_valid(player):
			var home := player.global_position - b.pos
			if home.length() < 8.0:
				_kill(b, false)
				continue
			b.vel = home.normalized() * b.vel.length()
		if b.wave_amp > 0.0:
			var off := sin(b.age * b.wave_freq * TAU) * b.wave_amp
			b.pos += b.vel.normalized().orthogonal() * (off - b.wave_off)
			b.wave_off = off
		var step := b.vel * delta
		var np := b.pos + step
		if room and room.is_bullet_blocked(np, b.spectral) and not b.returned:
			if b.bounce > 0:
				if room.is_bullet_blocked(Vector2(np.x, b.pos.y), b.spectral):
					b.vel.x = -b.vel.x
				if room.is_bullet_blocked(Vector2(b.pos.x, np.y), b.spectral):
					b.vel.y = -b.vel.y
				b.bounce -= 1
				if fx:
					fx.spark(b.pos, b.color)
				continue
			_kill(b, true)
			continue
		b.pos = np
		b.travel_left -= step.length()
		b.z = SHOT_HEIGHT * clampf(b.travel_left / FALL_DIST, 0.0, 1.0)
		if b.travel_left <= 0.0:
			_kill(b, true)
			continue
		if b.friendly:
			for t in targets:
				if not is_instance_valid(t) or b.hit.has(t.get_instance_id()) or t.get("untargetable"):
					continue
				var tp: Vector2 = t.global_position
				var rr: float = b.radius + float(t.get("hit_radius"))
				if tp.distance_squared_to(b.pos) <= rr * rr:
					b.hit[t.get_instance_id()] = true
					_hit_target(b, t, targets)
					if int(b.spec.get("split_count", 0)) > 0 and int(b.spec.get("split_depth", 0)) > 0:
						_split(b, spawned)
					if b.pierce == 0:
						_kill(b, true)
						break
					elif b.pierce > 0:
						b.pierce -= 1
		elif _blocked_by_orbital(b, blockers):
			_kill(b, true)
		elif player and is_instance_valid(player):
			var pr: float = b.radius + float(player.get("hurt_radius"))
			if player.global_position.distance_squared_to(b.pos) <= pr * pr:
				if player.hurt(int(b.damage), "bullet"):
					_kill(b, true)
	bullets.append_array(spawned)
	# Compact dead bullets back into the pool.
	var i := 0
	while i < bullets.size():
		if not bullets[i].alive:
			_pool.append(bullets[i])
			bullets[i] = bullets[bullets.size() - 1]
			bullets.pop_back()
		else:
			i += 1
	queue_redraw()


## Applies one player shot to a target, rolling on-hit procs (crit, chain, stun, elements).
func _hit_target(b: Bullet, t: Node, targets: Array) -> void:
	var dmg := b.damage
	var elements: Array = b.elements
	var chains: Array = []
	var stun := 0.0
	if not b.procs.is_empty() and t.get("team") == "enemy":
		var luck := RunState.stat("luck")
		var r := RNG.stream("misc")
		for p in b.procs:
			if r.randf() >= float(p["chance"]) + float(p.get("per_luck", 0.0)) * luck:
				continue
			var params: Dictionary = p.get("params", {})
			match str(p["kind"]):
				"crit":
					dmg *= float(params.get("mult", 2.0))
					if fx:
						fx.ring(b.pos, 7.0, Color(1, 1, 0.6), 0.2)
				"element":
					var els: Array = params.get("elements", [params.get("element", "poison")])
					elements = elements.duplicate()
					elements.append(els[r.randi_range(0, els.size() - 1)])
				"chain":
					chains.append(params)
				"stun":
					stun = maxf(stun, float(params.get("duration", 1.0)))
	t.take_hit(dmg, b.vel.normalized() * b.knockback, elements)
	if stun > 0.0 and t.has_method("stun"):
		t.stun(stun)
	for c in chains:
		_chain(t, targets, dmg * float(c.get("mult", 0.5)), float(c.get("range", 70.0)), int(c.get("jumps", 1)))


## Chain lightning: jumps from the hit target to the nearest other enemies.
func _chain(from: Node, targets: Array, dmg: float, reach: float, jumps: int) -> void:
	var cur: Node2D = from
	var done := {from.get_instance_id(): true}
	for j in jumps:
		var best: Node2D = null
		var best_d := reach * reach
		for t in targets:
			if not is_instance_valid(t) or done.has(t.get_instance_id()) or t.get("team") != "enemy" or t.get("untargetable"):
				continue
			var d: float = t.global_position.distance_squared_to(cur.global_position)
			if d < best_d:
				best_d = d
				best = t
		if best == null:
			return
		done[best.get_instance_id()] = true
		if fx:
			fx.zap(cur.global_position, best.global_position)
		best.take_hit(dmg, (best.global_position - cur.global_position).normalized(), ["shock"])
		cur = best


func _blocked_by_orbital(b: Bullet, blockers: Array) -> bool:
	for o in blockers:
		var rr: float = b.radius + float(o.get("block_radius"))
		if o.global_position.distance_squared_to(b.pos) <= rr * rr:
			return true
	return false


func _steer(b: Bullet, targets: Array, delta: float) -> void:
	var best: Node2D = null
	var best_d := 110.0 * 110.0
	for t in targets:
		if not is_instance_valid(t) or t.get("team") != "enemy" or t.get("untargetable"):
			continue
		var d: float = t.global_position.distance_squared_to(b.pos)
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		return
	var desired := (best.global_position - b.pos).angle()
	var cur := b.vel.angle()
	var diff := wrapf(desired - cur, -PI, PI)
	var turn := clampf(diff, -b.homing * delta, b.homing * delta)
	b.vel = b.vel.rotated(turn)


func _split(b: Bullet, out: Array[Bullet]) -> void:
	var child := ShotSpec.child_of(b.spec)
	var n: int = int(b.spec["split_count"])
	var base_ang := b.vel.angle()
	for k in n:
		var ang := base_ang + (float(k) - float(n - 1) / 2.0) * (PI / 4.0)
		var c := _new_bullet()
		c.friendly = true
		c.pos = b.pos
		c.vel = Vector2.from_angle(ang) * float(child["speed"]) * 0.9
		c.damage = float(child["damage"])
		c.radius = float(child["radius"])
		c.travel_left = float(child["range"])
		c.pierce = int(child["pierce"])
		c.bounce = int(child["bounce"])
		c.homing = float(child["homing"])
		c.spectral = bool(child["spectral"])
		c.elements = child["elements"].duplicate()
		c.color = child["color"].lightened(0.2)
		c.stretch = float(child["stretch"])
		c.spec = child
		c.hit = b.hit.duplicate()  # don't instantly re-hit the same target
		out.append(c)


func _kill(b: Bullet, splat: bool) -> void:
	b.alive = false
	if splat and fx:
		fx.splat(b.pos - Vector2(0, b.z), b.color)


func _draw() -> void:
	for b in bullets:
		if not b.alive:
			continue
		# Drop shadow on the ground, body raised by fake height z.
		draw_circle(b.pos + Vector2(0, 1), b.radius * 0.8, Color(0, 0, 0, 0.35))
		var p := b.pos - Vector2(0, b.z)
		var outline := Color.WHITE if (high_contrast and not b.friendly) else OUTLINE
		if b.stretch > 1.01:
			var d := b.vel.normalized() * b.radius * (b.stretch - 1.0)
			draw_circle(p - d, b.radius + 1.0, outline)
			draw_circle(p + d, b.radius + 1.0, outline)
			draw_line(p - d, p + d, outline, b.radius * 2.0 + 2.0)
			draw_circle(p - d, b.radius, b.color.darkened(0.15))
			draw_line(p - d, p + d, b.color, b.radius * 2.0)
			draw_circle(p + d, b.radius, b.color.lightened(0.2))
		else:
			draw_circle(p, b.radius + 1.0, outline)
			draw_circle(p, b.radius, b.color)
			draw_circle(p - Vector2(b.radius * 0.35, b.radius * 0.35), b.radius * 0.35, b.color.lightened(0.5))
		# Readable build: each element adds a colored ring; boomerangs spin a notch.
		if b.friendly:
			var k := 0
			for el in b.elements:
				draw_arc(p, b.radius + 1.5 + k * 1.2, 0, TAU, 10, ELEMENT_COLORS.get(el, Color.WHITE), 1.0)
				k += 1
			if b.boomerang:
				var a := b.age * 14.0
				draw_line(p + Vector2.from_angle(a) * b.radius, p - Vector2.from_angle(a) * b.radius, outline, 1.0)
