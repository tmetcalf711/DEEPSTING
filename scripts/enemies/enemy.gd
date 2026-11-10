class_name Enemy
extends CharacterBody2D
## Data-driven enemy (DESIGN.md §7). Behavior comes from data: behavior.type ->
## res://scripts/enemies/behaviors/<type>.gd. Every attack telegraphs via telegraph().

const BEHAVIOR_DIR := "res://scripts/enemies/behaviors/"

var data: Dictionary
var room: Node
var is_boss := false
var team := "enemy"
var hit_radius := 6.0
var hp := 10.0
var max_hp := 10.0
var behavior: RefCounted
var rng: RandomNumberGenerator
var flying := false
var stunned := 0.0
var knock := Vector2.ZERO
var dead := false
## Underground (burrowers): invisible, can't be hit, no contact damage.
var untargetable := false
var poison_t := 0.0
var burn_t := 0.0
var slow_t := 0.0
var _poison_tick := 0.0

var _spr: Sprite2D
var _flash := 0.0
var _tele := 0.0
var _tele_max := 0.0
var _t := 0.0
var _spawn_t := 0.45


func setup(d: Dictionary, p_room: Node, boss: bool) -> void:
	data = d
	room = p_room
	is_boss = boss
	rng = p_room.rng_enemies
	hp = float(d.get("hp", 10))
	max_hp = hp
	hit_radius = float(d.get("radius", 6))
	flying = bool(d.get("flying", false))


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("shootable")
	collision_layer = 16
	collision_mask = 1 if flying else (1 | 2 | 4)
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = maxf(3.0, hit_radius - 1.5)
	cs.shape = c
	add_child(cs)
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("bosses" if is_boss else "enemies", data["id"])
	add_child(_spr)
	var btype: String = data.get("behavior", {}).get("type", "chase")
	var path := BEHAVIOR_DIR + btype + ".gd"
	if ResourceLoader.exists(path):
		behavior = load(path).new()
		behavior.init(self, data.get("behavior", {}))
	else:
		push_error("Enemy: no behavior '%s'" % btype)
	if is_boss:
		Events.boss_spawned.emit(data["id"])
		Events.boss_health_changed.emit(1.0)


func player() -> Node2D:
	return RunController.instance.player


func to_player() -> Vector2:
	var p := player()
	return (p.global_position - global_position) if p else Vector2.ZERO


func fire(vel: Vector2, color: Color = ProjectileSystem.ENEMY_RED, radius: float = 3.0) -> void:
	RunController.instance.projectiles.spawn_enemy_shot(global_position + Vector2(0, -2), vel, color, radius)


## Starts a wind-up flash + squash for `duration` seconds (the readable tell, §7.1).
func telegraph(duration: float) -> void:
	_tele = duration
	_tele_max = duration
	var sfx: String = data.get("telegraph", {}).get("sfx", "")
	if sfx != "":
		Audio.play_sfx(sfx)


func is_telegraphing() -> bool:
	return _tele > 0.0


func stun(t: float) -> void:
	stunned = maxf(stunned, t)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_tele = maxf(0.0, _tele - delta)
	if _spawn_t > 0.0 or not room.enemies_awake():
		_spawn_t -= delta
		_animate()
		return
	_tick_status(delta)
	if dead:
		return
	if stunned > 0.0:
		stunned -= delta
		velocity = knock
	elif behavior:
		behavior.tick(self, delta)
		if slow_t > 0.0:
			velocity *= 0.5
		velocity += knock
	knock = knock.move_toward(Vector2.ZERO, 400.0 * delta)
	move_and_slide()
	_contact()
	_animate()


## Elemental statuses from shots (DESIGN.md §6.5): poison ticks damage, slow halves movement.
func apply_elements(elements: Array) -> void:
	for el in elements:
		match str(el):
			"poison":
				poison_t = 3.0 if not is_boss else 2.0
			"slow":
				slow_t = 2.0 if not is_boss else 1.0
			"burn":
				burn_t = 1.5 if not is_boss else 1.0


func _tick_status(delta: float) -> void:
	slow_t = maxf(0.0, slow_t - delta)
	burn_t = maxf(0.0, burn_t - delta)
	if poison_t > 0.0 or burn_t > 0.0:
		poison_t = maxf(0.0, poison_t - delta)
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = 0.5
			var tick := (1.25 if poison_t > 0.0 else 0.0) + (3.0 if burn_t > 0.0 else 0.0)
			hp -= tick
			if data.get("show_damage", false):
				RunController.instance.fx.number(global_position, tick)
			_flash = 0.04
			if is_boss:
				Events.boss_health_changed.emit(maxf(0.0, hp / max_hp))
			if hp <= 0.0:
				die(true)


func _contact() -> void:
	if untargetable:
		return
	var p := player()
	if p and p.global_position.distance_to(global_position) < hit_radius + 4.0:
		p.hurt(int(data.get("contact_damage", 1)), data["id"])


func take_hit(damage: float, dir: Vector2, elements: Array) -> void:
	if dead or untargetable:
		return
	apply_elements(elements)
	hp -= damage
	if data.get("show_damage", false):
		RunController.instance.fx.number(global_position, damage)
		if hp < max_hp * 0.5:
			hp = max_hp  # lab dummies never die
	_flash = 0.06
	if not is_boss:
		knock += dir * 70.0
	if is_boss:
		Events.boss_health_changed.emit(maxf(0.0, hp / max_hp))
	Audio.play_sfx("enemy_hit")
	if hp <= 0.0:
		die(true)


func die(counted: bool = true) -> void:
	if dead:
		return
	dead = true
	var rc := RunController.instance
	rc.fx.burst(global_position, _spr.modulate * Color(0.6, 0.9, 0.3), 14 if not is_boss else 60, 70.0 if not is_boss else 140.0, 2.0)
	if counted:
		RunState.add_radiation(float(data.get("radiation", 1)))
		if rc.player and rc.player.effects:
			rc.player.effects.fire_event("kill", global_position)
		RunState.bump("kills")
		MetaSave.add_counter("kills." + str(data["id"]))
		Events.enemy_killed.emit(data["id"], false)
		GameState.hitstop(0.12 if is_boss else 0.03)
		rc.shake(0.9 if is_boss else 0.12)
	if is_boss:
		Events.boss_health_changed.emit(0.0)
		Events.boss_killed.emit(data["id"], not rc.took_damage_this_room)
		rc.projectiles.clear_enemy_shots()
	# Splitters (and bosses like the Grubking) break into smaller enemies. Spawned before the death
	# is reported so the room doesn't count as cleared in between.
	var split: Dictionary = data.get("split_into", {})
	if counted and not split.is_empty():
		var child: Dictionary = Content.get_entry("enemies", str(split.get("enemy", "")))
		for i in int(split.get("count", 2)):
			var off := Vector2.from_angle(TAU * i / float(split.get("count", 2)) + 0.5) * (hit_radius + 4.0)
			room.call_deferred("spawn_enemy", child, room.nearest_free_point(global_position + off))
		room.enemies_alive += int(split.get("count", 2))  # reserve; spawn_enemy adds again, so undo below
		room.call_deferred("_release_reserved", int(split.get("count", 2)))
	room.on_enemy_died(self)
	queue_free()


func _animate() -> void:
	var lift := 8.0 + sin(_t * 5.0) * 1.5 if flying else 0.0
	var sq := 1.0
	if _tele > 0.0:
		# Wind-up: swell + pulse.
		var k := 1.0 - _tele / maxf(_tele_max, 0.01)
		sq = 1.0 + 0.25 * k
	elif not flying:
		sq = 1.0 + sin(_t * 8.0) * 0.05
	_spr.scale = Vector2(sq, 2.0 - sq) if _tele <= 0.0 else Vector2(sq, sq)
	if _spawn_t > 0.0:
		_spr.scale *= 1.0 - clampf(_spawn_t / 0.45, 0.0, 1.0) * 0.6
	_spr.position = Vector2(0, -hit_radius * 0.6 - lift)
	_spr.visible = not untargetable
	var tele_flash := _tele > 0.0 and fmod(_tele, 0.16) < 0.08
	if _flash > 0.0:
		_spr.modulate = Color(3, 3, 3)
	elif tele_flash:
		_spr.modulate = Color(1.8, 1.4, 1.4)
	elif stunned > 0.0:
		_spr.modulate = Color(0.6, 0.6, 1.0)
	elif burn_t > 0.0:
		_spr.modulate = Color(1.0, 0.65, 0.4)
	elif poison_t > 0.0:
		_spr.modulate = Color(0.6, 1.0, 0.5)
	elif slow_t > 0.0:
		_spr.modulate = Color(0.75, 0.85, 1.0)
	else:
		_spr.modulate = Color.WHITE
	_spr.flip_h = to_player().x < 0
	queue_redraw()


func _draw() -> void:
	if untargetable:
		# Dirt mound moving underground.
		draw_circle(Vector2(0, 0), hit_radius * 0.9, Color(0.3, 0.22, 0.14, 0.9))
		draw_circle(Vector2(-1, -1), hit_radius * 0.5, Color(0.42, 0.32, 0.2, 0.9))
		return
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, hit_radius * (0.8 if flying else 1.0), Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
