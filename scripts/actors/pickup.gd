extends Node2D
## Pickups: mana (chip/fragment/chunk/crystal), hearts, chitin, toxic chitin, dig charges,
## royal jelly. Data in /data/pickups. Touch to collect; hearts/shields only when they'd help.

var room: Node
var data: Dictionary
var velocity := Vector2.ZERO
var collected := false
var _t := 0.0
var _spr: Sprite2D


func setup(p_room: Node, p_data: Dictionary) -> void:
	room = p_room
	data = p_data


func _ready() -> void:
	add_to_group("pickups")
	_spr = Sprite2D.new()
	_spr.texture = Art.texture("pickups", data["id"])
	add_child(_spr)
	_t = float(get_instance_id() % 100) / 10.0


func _physics_process(delta: float) -> void:
	_t += delta
	if velocity.length_squared() > 1.0:
		var np := position + velocity * delta
		if room.is_bullet_blocked(np, false):
			velocity = -velocity * 0.4
		else:
			position = np
		velocity *= 0.9
	_spr.position.y = -3.0 - absf(sin(_t * 3.0)) * 1.5
	var player: Node2D = RunController.instance.player
	if player == null:
		return
	var d := player.global_position.distance_to(global_position)
	if data["kind"] == "mana" and d < 26.0:
		position = position.move_toward(player.global_position, 90.0 * delta)
	if d < 10.0 and apply_pickup(data):
		collected = true
		RunController.instance.fx.burst(global_position, Color(1, 1, 0.8), 6, 40.0, 1.0)
		Audio.play_sfx("pickup_" + str(data["kind"]))
		queue_free()


## Applies a pickup's effect to the run. Returns false (and changes nothing) if it wouldn't help,
## e.g. a heart at full health. Shared with shop wares.
static func apply_pickup(d: Dictionary) -> bool:
	var v: int = int(d["value"])
	match str(d["kind"]):
		"mana":
			if RunState.mana >= RunState.MAX_CONSUMABLE:
				return false
			RunState.add_mana(v)
		"heart":
			if not RunState.can_heal():
				return false
			RunState.heal(v)
			Events.player_healed.emit(v)
		"chitin", "toxic_chitin":
			if not RunState.can_add_shield():
				return false
			RunState.add_shield("chitin" if d["kind"] == "chitin" else "toxic", v)
			Events.player_healed.emit(v)
		"dig_charge":
			RunState.add_dig_charges(v)
		"royal_jelly":
			RunState.add_royal_jelly(v)
	Events.consumables_changed.emit()
	return true
