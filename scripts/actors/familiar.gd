extends Node2D
## Familiar that follows the player in a trail. behavior "shooter": fires in the player's aim
## direction while the player is shooting (does not inherit item modifiers, like Isaac).

var player: Node2D
var params: Dictionary = {}
var sprite_id := "toy_soldier"
var slot := 0
var _cd := 0.0
var _spr: Sprite2D
var _t := 0.0


func setup(p_player: Node2D, p: Dictionary, sprite: String, p_slot: int) -> void:
	player = p_player
	params = p
	sprite_id = sprite
	slot = p_slot


func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("items", sprite_id)
	_spr.scale = Vector2.ONE * 0.75
	add_child(_spr)
	z_index = 1


func _physics_process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(player):
		return
	var follow: Vector2 = player.trail_point(10 + slot * 8)
	global_position = global_position.lerp(follow, minf(1.0, delta * 10.0))
	_spr.position.y = -6 + sin(_t * 4.0) * 1.0
	_cd -= delta
	if player.is_shooting and _cd <= 0.0:
		_cd = float(params.get("fire_interval", 0.75))
		var spec := ShotSpec.build({"damage": float(params.get("damage", 3.5)), "shot_speed": 0.9, "range": 130.0}, [])
		spec["color"] = Color(0.95, 0.85, 0.5)
		spec["radius"] = 2.5
		RunController.instance.projectiles.spawn_player_shot(global_position, player.aim_dir, spec)
