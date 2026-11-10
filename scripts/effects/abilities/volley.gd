extends RefCounted
## A ring or spiral of stingers using the wasp's current shot spec.
## params: {count: 12, damage_mult: 1.0, pierce: false, homing: 0.0, spiral: false, color: "#rrggbb"}


static func activate(player: Node2D, params: Dictionary) -> void:
	var rc := RunController.instance
	var spec: Dictionary = player.spec.duplicate(true)
	spec["damage"] = float(spec["damage"]) * float(params.get("damage_mult", 1.0))
	if params.get("pierce", false):
		spec["pierce"] = -1
	spec["homing"] = maxf(float(spec["homing"]), float(params.get("homing", 0.0)))
	if params.has("color"):
		spec["color"] = Color.from_string(str(params["color"]), spec["color"])
	var n: int = int(params.get("count", 12))
	for i in n:
		var a := TAU * i / n
		var d := Vector2.from_angle(a)
		var at: Vector2 = player.global_position + (d * (4.0 + i * 1.5) if params.get("spiral", false) else Vector2.ZERO)
		rc.projectiles.spawn_player_shot(at, d.rotated(0.6) if params.get("spiral", false) else d, spec)
	rc.fx.ring(player.global_position, 24.0, spec["color"])
