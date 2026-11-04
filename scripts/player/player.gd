extends CharacterBody2D
## The wasp (DESIGN.md §3). Hover with momentum, dash with i-frames, Isaac-style shooting
## (4-dir keys / free-aim stick or mouse), health from RunState, items via EffectHost.

const ACCEL := 900.0
const FRICTION := 700.0
const SPEED_UNIT := 95.0       # px/s per 1.0 move speed
const DASH_TIME := 0.14
const DASH_MULT := 3.2
const DASH_COOLDOWN := 0.9
const HURT_IFRAMES := 1.0
const HOVER := 7.0
const DigChargeScript := preload("res://scripts/actors/dig_charge.gd")

var hurt_radius := 4.0
var aim_dir := Vector2.DOWN
var is_shooting := false
var facing := Vector2.DOWN
var spec: Dictionary = {}
var effects: EffectHost

var _fire_cd := 0.0
var _dash_t := 0.0
var _dash_cd := 0.0
var _iframes := 0.0
var _eye := 1.0
var _t := 0.0
var _trail: Array[Vector2] = []
var _body: Sprite2D
var _overlay: Sprite2D
var _flash := 0.0
var dead := false


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 4.5
	cs.shape = c
	add_child(cs)
	_body = Sprite2D.new()
	_body.texture = Art.texture("player", RunState.caste)
	add_child(_body)
	_overlay = Sprite2D.new()
	add_child(_overlay)
	effects = EffectHost.new(self)
	effects.rebuild()
	Events.stats_changed.connect(_on_stats_changed)
	_on_stats_changed()


func _on_stats_changed() -> void:
	spec = ShotSpec.build(RunState.all_stats(), RunState.shot_mods, RunState.tints)
	collision_mask = 1 if RunState.flags.get("flight", false) else (1 | 2 | 4)
	var ov := ""
	for id in RunState.items:
		var v: Dictionary = Content.get_entry("items", id).get("visual", {})
		if v.has("player_overlay"):
			ov = v["player_overlay"]
	_overlay.texture = Art.texture("player", "overlay_" + ov) if ov != "" else null


## Deferred from EffectHost: parents a new familiar to whatever room the player is in *now*.
func attach_familiar(f: Node2D) -> void:
	if is_instance_valid(f) and f.get_parent() == null and get_parent() != null:
		f.global_position = global_position
		get_parent().add_child(f)


func trail_point(back: int) -> Vector2:
	if _trail.is_empty():
		return global_position
	return _trail[maxi(0, _trail.size() - 1 - back)]


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_fire_cd -= delta
	_dash_cd -= delta
	_iframes -= delta
	_flash = maxf(0.0, _flash - delta)
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed := RunState.stat("move_speed") * SPEED_UNIT
	if _dash_t > 0.0:
		_dash_t -= delta
	else:
		var target := move * speed
		var rate := ACCEL if move != Vector2.ZERO else FRICTION
		velocity = velocity.move_toward(target, rate * delta)
		if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0:
			var d := move if move != Vector2.ZERO else facing
			velocity = d.normalized() * speed * DASH_MULT
			_dash_t = DASH_TIME
			_dash_cd = DASH_COOLDOWN
			_iframes = maxf(_iframes, DASH_TIME + 0.04)
			RunController.instance.fx.burst(global_position, Color(1, 0.9, 0.5, 0.6), 6, 30.0, 1.0)
			Audio.play_sfx("dash")
	if move != Vector2.ZERO:
		facing = move.normalized()
	move_and_slide()
	_trail.append(global_position)
	if _trail.size() > 60:
		_trail.pop_front()
	_handle_shooting()
	if Input.is_action_just_pressed("dig_charge") and RunState.dig_charges > 0:
		RunState.add_dig_charges(-1)
		var b: Node2D = DigChargeScript.new()
		b.room = RunController.instance.room
		b.position = global_position
		RunController.instance.room.entities.add_child(b)
	if Input.is_action_just_pressed("use_active"):
		effects.use_active()
	_animate()


func _handle_shooting() -> void:
	var raw := Input.get_vector("shoot_left", "shoot_right", "shoot_up", "shoot_down")
	var from_keys := raw != Vector2.ZERO and absf(raw.x) in [0.0, 1.0] and absf(raw.y) in [0.0, 1.0]
	if raw == Vector2.ZERO and Input.is_action_pressed("shoot_mouse"):
		raw = (get_global_mouse_position() - global_position).normalized()
		from_keys = false
	is_shooting = raw != Vector2.ZERO
	if not is_shooting:
		return
	aim_dir = _apply_aim_mode(raw, from_keys)
	if _fire_cd > 0.0:
		return
	_fire_cd = 1.0 / RunState.stat("fire_rate")
	_eye = -_eye
	var perp := aim_dir.orthogonal() * 2.0 * _eye
	RunController.instance.projectiles.spawn_player_shot(global_position + perp, aim_dir, spec, velocity * 0.15)
	_body.scale = Vector2(1.12, 0.9)
	Audio.play_sfx("sting")


func _apply_aim_mode(v: Vector2, from_keys: bool) -> Vector2:
	var mode := GameState.aim_mode()
	if mode == "auto":
		mode = "4dir" if from_keys else "free"
	match mode:
		"4dir":
			if absf(v.x) >= absf(v.y):
				return Vector2(signf(v.x), 0)
			return Vector2(0, signf(v.y))
		"8dir":
			return Vector2.from_angle(snappedf(v.angle(), PI / 4.0))
	return v.normalized()


func _animate() -> void:
	_body.position = Vector2(0, -HOVER + sin(_t * 6.0) * 1.0)
	_overlay.position = _body.position + Vector2(0, -7)
	_body.scale = _body.scale.lerp(Vector2.ONE, 0.25)
	if _dash_t > 0.0:
		_body.scale = Vector2(1.25, 0.8)
	_body.flip_h = facing.x < 0
	var blink := _iframes > 0.0 and _dash_t <= 0.0 and fmod(_t, 0.12) < 0.06
	_body.modulate = Color(3, 3, 3) if _flash > 0.0 else (Color(1, 1, 1, 0.35) if blink else Color.WHITE)
	queue_redraw()


func _draw() -> void:
	# Drop shadow under the hovering wasp (2.5D).
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)


## Returns true if damage was applied.
func hurt(halves: int, source: String) -> bool:
	if dead or _iframes > 0.0 or GameState.god_mode:
		return false
	var toxic := RunState.take_damage(halves)
	_iframes = HURT_IFRAMES
	_flash = 0.08
	var rc := RunController.instance
	rc.shake(0.4)
	rc.on_player_hurt()
	GameState.hitstop(0.07)
	Audio.play_sfx("player_hurt")
	Events.player_damaged.emit(halves, source)
	for i in toxic:
		rc.toxic_burst(global_position)
	if RunState.is_dead():
		if RunState.flags.get("revive_once", false):
			RunState.flags.erase("revive_once")
			RunState.hearts = mini(2, RunState.hearts_max)
			_iframes = 2.0
			rc.fx.burst(global_position, Color(1, 0.85, 0.3), 30, 90.0, 2.0)
			Events.banner.emit(tr("BANNER_REVIVED"), "")
		else:
			dead = true
			Events.player_died.emit()
	return true


## Picks up an item from a pedestal. Returns the id left on the pedestal ("" normally;
## the previous active item when swapping actives).
func pickup_item(id: String) -> String:
	var item: Dictionary = Content.get_entry("items", id)
	if item.is_empty():
		return ""
	var left := ""
	if item.get("kind", "") == "active" and RunState.active_item != "":
		left = RunState.active_item
	effects.add_item(id)
	Events.banner.emit(tr(item["name_key"]), tr(item.get("desc_key", "")))
	RunController.instance.fx.burst(global_position + Vector2(0, -10), Color(1, 0.85, 0.3), 14, 50.0, 1.5)
	Audio.play_sfx("item_get")
	return left
