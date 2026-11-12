extends RefCounted
## Phase-driven boss. Each phase lists pattern names; patterns are generic (ring, fan, spiral,
## charge, spawn) and parameterized by data, so new bosses are mostly JSON.
var speed := 18.0
var phases: Array = []
var gap := 1.1
var minion := "feral_ant"
var max_minions := 4
var windup := 0.6

var _phase := 0
var _step := 0
var _wait := 1.2
var _active := ""
var _t := 0.0
var _charge_dir := Vector2.ZERO
var _spiral_ang := 0.0
var _fired := false
var _spots: Array = []


func init(e: Enemy, p: Dictionary) -> void:
	speed = float(p.get("speed", 18))
	phases = p.get("phases", [])
	gap = float(p.get("pattern_gap", 1.1))
	minion = str(p.get("minion", "feral_ant"))
	max_minions = int(p.get("max_minions", 4))
	windup = float(e.data.get("telegraph", {}).get("windup", 0.6))


func tick(e: Enemy, delta: float) -> void:
	_update_phase(e)
	if _active == "":
		e.velocity = e.to_player().normalized() * speed
		_wait -= delta
		if _wait <= 0.0:
			var list: Array = phases[_phase]["patterns"]
			_active = str(list[_step % list.size()])
			_step += 1
			_t = 0.0
			_fired = false
			e.telegraph(windup)
		return
	_t += delta
	match _active:
		"ring_burst": _ring(e)
		"aimed_fan": _fan(e)
		"spiral_burst": _spiral(e, delta)
		"spawn_minions": _spawn(e)
		"charge": _charge(e)
		"burrow_strike": _burrow_strike(e, delta)
		"rubble_rain": _rubble_rain(e)
		"cross_sweep": _cross_sweep(e)
		"homing_orbs": _homing_orbs(e)
		"bullet_wall": _bullet_wall(e)
		_: _end()


func _update_phase(e: Enemy) -> void:
	var frac: float = e.hp / e.max_hp
	while _phase < phases.size() - 1 and frac <= float(phases[_phase]["until_hp"]):
		_phase += 1
		_step = 0
		e.telegraph(0.8)
		RunController.instance.shake(0.4)


func _end() -> void:
	_active = ""
	_wait = gap * (0.75 if _phase > 0 else 1.0)


func _ring(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _t >= windup and not _fired:
		_fired = true
		var n := 12 if _phase == 0 else 16
		var off: float = e.rng.randf() * TAU
		for i in n:
			e.fire(Vector2.from_angle(off + TAU * i / n) * 70.0)
		_end()


func _fan(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _t >= windup and not _fired:
		_fired = true
		var base: float = e.to_player().angle()
		for i in 5:
			e.fire(Vector2.from_angle(base + (i - 2) * 0.26) * 95.0, ProjectileSystem.ENEMY_RED, 3.5)
		_end()


func _spiral(e: Enemy, _delta: float) -> void:
	e.velocity = Vector2.ZERO
	if _t < windup:
		return
	var k := int((_t - windup) / 0.07)
	while _spiral_ang < k:
		_spiral_ang += 1.0
		for arm in 2:
			e.fire(Vector2.from_angle(_spiral_ang * 0.42 + arm * PI) * 65.0, ProjectileSystem.ENEMY_GREEN)
	if _t >= windup + 1.4:
		_spiral_ang = 0.0
		_end()


func _spawn(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _t >= windup and not _fired:
		_fired = true
		var alive: int = e.room.room_enemies().size() - 1
		var data: Dictionary = Content.get_entry("enemies", minion)
		for i in mini(2, max_minions - alive):
			e.room.spawn_enemy(data, e.room.nearest_free_point(e.global_position + Vector2.from_angle(e.rng.randf() * TAU) * 14.0), false, false)
		_end()


func _charge(e: Enemy) -> void:
	if _t < windup:
		e.velocity = Vector2.ZERO
		_charge_dir = e.to_player().normalized()
		return
	e.velocity = _charge_dir * 150.0
	if _t > windup + 0.9 or (e.get_slide_collision_count() > 0 and _t > windup + 0.1):
		RunController.instance.shake(0.3)
		e.stun(0.5)
		_end()


## Dig under, tunnel to the player, burst out with a ring.
func _burrow_strike(e: Enemy, _delta: float) -> void:
	if _t < windup:
		e.velocity = Vector2.ZERO
		return
	if _t < windup + 1.2:
		if not e.untargetable:
			e.untargetable = true
			RunController.instance.fx.burst(e.global_position, Color(0.4, 0.3, 0.2), 16, 60.0, 2.0)
		e.velocity = e.to_player().normalized() * 85.0
		return
	if e.untargetable:
		e.untargetable = false
		e.velocity = Vector2.ZERO
		e.telegraph(0.45)
		return
	if _t >= windup + 1.65 and not _fired:
		_fired = true
		RunController.instance.shake(0.35)
		for i in 10:
			e.fire(Vector2.from_angle(TAU * i / 10.0) * 72.0)
		_end()


## Rocks fall from the ceiling: shadows telegraph the spots, then each bursts into shards.
func _rubble_rain(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _spots.is_empty():
		var p: Node2D = e.player()
		for i in 6:
			var base: Vector2 = p.global_position if i < 2 and p else e.room.center()
			var spot: Vector2 = base + Vector2(e.rng.randf_range(-70, 70), e.rng.randf_range(-40, 40))
			spot.x = clampf(spot.x, 10.0, e.room.room_w - 10.0)
			spot.y = clampf(spot.y, 10.0, e.room.room_h - 10.0)
			_spots.append(spot)
			RunController.instance.fx.warn(spot, 10.0, windup + 0.5)
		return
	if _t >= windup + 0.5 and not _fired:
		_fired = true
		var rc := RunController.instance
		rc.shake(0.3)
		for spot in _spots:
			rc.fx.burst(spot, Color(0.45, 0.38, 0.3), 8, 60.0, 2.0)
			for k in 4:
				rc.projectiles.spawn_enemy_shot(spot, Vector2.from_angle(PI / 4.0 + k * PI / 2.0) * 60.0)
			if rc.player and rc.player.global_position.distance_to(spot) < 10.0:
				rc.player.hurt(1, "rubble")
		_spots.clear()
		_end()


## Four arms of bullets sweeping around the boss.
func _cross_sweep(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _t < windup:
		return
	var k := int((_t - windup) / 0.09)
	while _spiral_ang < k:
		_spiral_ang += 1.0
		for arm in 4:
			e.fire(Vector2.from_angle(_spiral_ang * 0.16 + arm * PI / 2.0) * 72.0)
	if _t >= windup + 1.6:
		_spiral_ang = 0.0
		_end()


## Slow violet orbs that curve toward the wasp.
func _homing_orbs(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _t >= windup and not _fired:
		_fired = true
		var n := 3 if _phase == 0 else 5
		var base := e.to_player().angle()
		for i in n:
			e.fire(Vector2.from_angle(base + (i - (n - 1) / 2.0) * 0.6) * 45.0, ProjectileSystem.ENEMY_VIOLET, 4.0, 1.6)
		_end()


## A wall of bullets falls from the top wall with one gap to slip through.
func _bullet_wall(e: Enemy) -> void:
	e.velocity = Vector2.ZERO
	if _t >= windup and not _fired:
		_fired = true
		var rc := RunController.instance
		var w: float = e.room.room_w
		var gap: float = e.rng.randf_range(30.0, w - 30.0)
		var x := 6.0
		while x < w - 4.0:
			if absf(x - gap) > 16.0:
				rc.projectiles.spawn_enemy_shot(Vector2(x, 4.0), Vector2(0, 55.0 * Difficulty.bullet_speed_mult(Difficulty.depth())),
					ProjectileSystem.ENEMY_RED, 3.0, 400.0, 0.0, Difficulty.hit_damage(Difficulty.depth()))
			x += 12.0
		_end()
