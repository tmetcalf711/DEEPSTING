extends RefCounted
## Sun Disk-style burst: a ring of big piercing shots that use the player's current shot spec.


static func activate(player: Node2D, params: Dictionary) -> void:
	var rc := RunController.instance
	var spec: Dictionary = player.spec.duplicate(true)
	spec["damage"] = float(spec["damage"]) * float(params.get("damage_mult", 2.0))
	spec["pierce"] = -1
	spec["radius"] = float(spec["radius"]) * 1.6
	spec["color"] = Color(1.0, 0.95, 0.55)
	var n: int = int(params.get("count", 16))
	for i in n:
		rc.projectiles.spawn_player_shot(player.global_position, Vector2.from_angle(TAU * i / n), spec)
	rc.fx.ring(player.global_position, 30.0, Color(1, 0.9, 0.5))
	rc.shake(0.3)
