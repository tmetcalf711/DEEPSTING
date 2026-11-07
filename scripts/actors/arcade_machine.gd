extends Node2D
## Arcade machine (slot beetle, fortune worm, crane). Touch to pay Mana and roll an outcome from
## config/arcade.json. Rolls use a per-room, per-play RNG stream so results are seed-stable.

var room: Node
var machine_id := ""
var cfg: Dictionary = {}
var _cooldown := 0.0
var _t := 0.0
var _spr: Sprite2D


func setup(p_room: Node, id: String, p_cfg: Dictionary) -> void:
	room = p_room
	machine_id = id
	cfg = p_cfg


func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("props", machine_id)
	_spr.offset = Vector2(0, -6)
	add_child(_spr)
	var l := Label.new()
	l.text = str(cfg.get("cost", 1))
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	l.scale = Vector2(0.5, 0.5)
	l.position = Vector2(-3, 3)
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_spr.scale = Vector2.ONE * (1.0 + (0.08 * sin(_t * 30.0) if _cooldown > 0.6 else 0.0))
	var p: Node2D = RunController.instance.player
	if _cooldown > 0.0 or p == null or p.global_position.distance_to(global_position) > 13.0:
		return
	var cost: int = int(cfg.get("cost", 1))
	if RunState.mana < cost:
		return
	_cooldown = 1.2
	RunState.add_mana(-cost)
	_play()


func _play() -> void:
	var plays: Dictionary = room.info.get("arcade_plays", {})
	var n: int = int(plays.get(machine_id, 0))
	plays[machine_id] = n + 1
	room.info["arcade_plays"] = plays
	var r := RNG.room_stream("drops", int(room.info["index"]) * 1000 + machine_id.length() * 37 + n)
	var outcomes: Array = cfg.get("outcomes", [])
	var o: Dictionary = outcomes[RNG.weighted_index(r, outcomes.map(func(e: Dictionary) -> float: return float(e["weight"])))]
	Audio.play_sfx("arcade_" + machine_id)
	var below := global_position + Vector2(0, 20)
	match str(o["result"]):
		"pickup":
			for i in int(o.get("count", 1)):
				room.spawn_pickup(str(o["id"]), below, Vector2.from_angle(r.randf() * TAU) * 40.0)
		"enemy":
			room.spawn_enemy(Content.get_entry("enemies", str(o["id"])), below)
		"fortune":
			Events.toast.emit(tr("FORTUNE_%d" % (r.randi_range(1, 8))))
		"item":
			room.add_extra_pedestal(RunController.instance.item_pool.roll(str(o.get("pool", "dig_site")), r), below + Vector2(0, 6))
		_:
			RunController.instance.fx.burst(global_position, Color(0.6, 0.6, 0.6), 6, 25.0, 1.0)
