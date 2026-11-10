extends Node2D
## Familiars (DESIGN.md §6.4). Behaviors:
##   shooter: follows in a trail, fires in the player's aim direction while the player shoots
##            (doesn't inherit item modifiers, like Isaac)
##   orbital: circles the wasp, blocks enemy bullets, hurts enemies it touches
##   biter:   flies at the nearest enemy and chews on it

var player: Node2D
var params: Dictionary = {}
var sprite_id := "toy_soldier"
var behavior := "shooter"
var slot := 0
var block_radius := 5.0
var _cd := 0.0
var _spr: Sprite2D
var _t := 0.0


func setup(p_player: Node2D, p: Dictionary, sprite: String, p_slot: int, p_behavior: String = "shooter") -> void:
	player = p_player
	params = p
	sprite_id = sprite
	slot = p_slot
	behavior = p_behavior


func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("items", sprite_id)
	_spr.scale = Vector2.ONE * 0.75
	add_child(_spr)
	z_index = 1
	if behavior == "orbital":
		add_to_group("bullet_blockers")
		block_radius = float(params.get("block_radius", 5.0))


func _physics_process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(player):
		return
	_cd -= delta
	_spr.position.y = -6 + sin(_t * 4.0) * 1.0
	match behavior:
		"orbital":
			var a := _t * float(params.get("speed", 2.5)) + slot * TAU / 3.0
			global_position = player.global_position + Vector2.from_angle(a) * float(params.get("radius", 18.0))
			_touch(float(params.get("damage", 6.0)), 0.25)
		"biter":
			var target := _nearest_enemy()
			var goal: Vector2 = target.global_position if target else player.trail_point(10 + slot * 8)
			global_position = global_position.move_toward(goal, float(params.get("speed", 70.0)) * delta)
			_touch(float(params.get("damage", 4.0)), 0.3)
		_:
			var follow: Vector2 = player.trail_point(10 + slot * 8)
			global_position = global_position.lerp(follow, minf(1.0, delta * 10.0))
			if player.is_shooting and _cd <= 0.0:
				_cd = float(params.get("fire_interval", 0.75))
				var spec := ShotSpec.build({"damage": float(params.get("damage", 3.5)), "shot_speed": 0.9, "range": 130.0}, [])
				spec["color"] = Color(0.95, 0.85, 0.5)
				spec["radius"] = 2.5
				RunController.instance.projectiles.spawn_player_shot(global_position, player.aim_dir, spec)


func _nearest_enemy() -> Node2D:
	var rc := RunController.instance
	if rc == null or rc.room == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for e in rc.room.room_enemies():
		if e.untargetable:
			continue
		var d: float = e.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Contact damage, at most once per `interval` seconds.
func _touch(dmg: float, interval: float) -> void:
	if _cd > 0.0:
		return
	var rc := RunController.instance
	if rc == null or rc.room == null:
		return
	for e in rc.room.room_enemies():
		if not e.untargetable and e.global_position.distance_to(global_position) < float(e.hit_radius) + 5.0:
			e.take_hit(dmg, (e.global_position - global_position).normalized(), [])
			_cd = interval
			return
