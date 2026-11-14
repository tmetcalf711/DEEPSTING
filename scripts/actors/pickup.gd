extends Node2D
## Pickups (data in /data/pickups). Touch to collect; hearts/shields only when they'd help.
##   mana (chip/fragment/chunk/crystal), heart, chitin, toxic_chitin, dig_charge, royal_jelly
##   trinket / fossil / fluid: carry a `payload` (trinket id, fossil id, fluid color id) that is
##   rolled from the room's seeded stream when the pickup appears, and swap with what you hold.

var room: Node
var data: Dictionary
var payload := ""
var velocity := Vector2.ZERO
var collected := false
var pickup_delay := 0.0     # dropped pickups wait, and need the wasp to step away first
var _armed := true
var _t := 0.0
var _spr: Sprite2D


func setup(p_room: Node, p_data: Dictionary, p_payload: String = "") -> void:
	room = p_room
	data = p_data
	payload = p_payload


func _ready() -> void:
	add_to_group("pickups")
	add_to_group("inspectable")
	if payload == "":
		payload = roll_payload(str(data["kind"]), room.rng_drops)
	_spr = Sprite2D.new()
	match str(data["kind"]):
		"trinket":
			_spr.texture = Art.texture("trinkets", payload)
		"fossil":
			_spr.texture = Art.texture("fossils", payload)
		"fluid":
			_spr.texture = null  # drawn as a colored vial
		_:
			_spr.texture = Art.texture("pickups", data["id"])
	add_child(_spr)
	_t = float(get_instance_id() % 100) / 10.0
	if pickup_delay > 0.0:
		_armed = false


## What a trinket / fossil / fluid pickup contains. Uses the given (seeded) stream.
func inspect_info() -> Dictionary:
	if collected:
		return {}
	return load("res://scripts/ui/inspect.gd").for_pickup(data, payload)


static func roll_payload(kind: String, r: RandomNumberGenerator) -> String:
	match kind:
		"trinket":
			var rc := RunController.instance
			return rc.trinket_pool.roll("trinkets", r) if rc and rc.trinket_pool else ""
		"fossil":
			var ids: Array = Content.ids("fossils")
			return str(ids[r.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""
		"fluid":
			var colors: Array = Content.get_entry("config", "fluids").get("colors", [])
			return str(colors[r.randi_range(0, colors.size() - 1)]["id"]) if not colors.is_empty() else ""
	return ""


func _physics_process(delta: float) -> void:
	_t += delta
	if pickup_delay > 0.0:
		_armed = false  # set after spawning: stay inert until the delay passes and the wasp steps away
	pickup_delay = maxf(0.0, pickup_delay - delta)
	if velocity.length_squared() > 1.0:
		var np := position + velocity * delta
		if room.is_bullet_blocked(np, false):
			velocity = -velocity * 0.4
		else:
			position = np
		velocity *= 0.9
	_spr.position.y = -3.0 - absf(sin(_t * 3.0)) * 1.5
	queue_redraw()
	var player: Node2D = RunController.instance.player
	if player == null:
		return
	var d := player.global_position.distance_to(global_position)
	if not _armed:
		_armed = pickup_delay <= 0.0 and d > 14.0
		return
	if data["kind"] == "mana" and d < 26.0:
		position = position.move_toward(player.global_position, 90.0 * delta)
	if d < 10.0 and apply_pickup(data, payload, global_position):
		collected = true
		RunController.instance.fx.burst(global_position, Color(1, 1, 0.8), 6, 40.0, 1.0)
		Audio.play_sfx("pickup_" + str(data["kind"]))
		queue_free()


func _draw() -> void:
	if data.get("kind", "") != "fluid":
		return
	var c := fluid_color(payload)
	var y := -3.0 - absf(sin(_t * 3.0)) * 1.5
	draw_rect(Rect2(-3, y - 3, 6, 8), c.darkened(0.5))
	draw_rect(Rect2(-2, y - 2, 4, 6), c)
	draw_rect(Rect2(-1, y - 5, 2, 2), Color(0.7, 0.6, 0.5))


static func fluid_color(color_id: String) -> Color:
	for c in Content.get_entry("config", "fluids").get("colors", []):
		if c["id"] == color_id:
			return Color.from_string(str(c["color"]), Color.WHITE)
	return Color.WHITE


## Applies a pickup to the run. Returns false (and changes nothing) if it wouldn't help, e.g. a
## heart at full health. Shared with shop wares. `at` is where swapped-out things are dropped.
static func apply_pickup(d: Dictionary, p_payload: String = "", at: Vector2 = Vector2.ZERO) -> bool:
	var v: int = int(d.get("value", 1))
	var rc := RunController.instance
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
		"trinket":
			if p_payload == "" or rc == null:
				return false
			var old: String = rc.player.effects.set_trinket(p_payload)
			var t: Dictionary = Content.get_entry("trinkets", p_payload)
			Events.banner.emit(tr_static(t.get("name_key", "")), tr_static(t.get("desc_key", "")))
			if old != "":
				rc.room.drop_swapped("trinket", old, at)
		"fossil", "fluid":
			if p_payload == "" or rc == null:
				return false
			var old_c: Dictionary = RunState.consumable
			RunState.consumable = {"kind": d["kind"], "id": p_payload}
			if d["kind"] == "fossil":
				var f: Dictionary = Content.get_entry("fossils", p_payload)
				Events.banner.emit(tr_static(f.get("name_key", "")), tr_static(f.get("desc_key", "")))
			else:
				Events.banner.emit(EffectHost.fluid_display_name(p_payload), "")
			if not old_c.is_empty():
				rc.room.drop_swapped(str(old_c["kind"]), str(old_c["id"]), at)
	Events.consumables_changed.emit()
	return true


static func tr_static(key: String) -> String:
	return TranslationServer.translate(key)
