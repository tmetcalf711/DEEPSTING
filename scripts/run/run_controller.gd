class_name RunController
extends Node2D
## Owns a run in progress: floor generation, the current room, room transitions, camera juice,
## death/victory flow and run-scoped debug commands. One room is instantiated at a time; the
## floor layout dictionary holds every room's persistent state.

static var instance: RunController

const RoomScript := preload("res://scripts/run/room.gd")
const PlayerScript := preload("res://scripts/player/player.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const PauseScript := preload("res://scripts/ui/pause_menu.gd")
const EndScript := preload("res://scripts/ui/end_screen.gd")
const CAMERA_CENTER := Vector2(Room.W / 2.0, Room.H / 2.0 - 4.0)

var layout: Dictionary = {}
var stratum: Dictionary = {}
var item_pool: ItemPool
var room: Room
var player: CharacterBody2D
var projectiles: ProjectileSystem
var fx: FX
var camera: Camera2D
var hud: CanvasLayer
var took_damage_this_room := false

var _world: Node2D
var _fade: ColorRect
var _flash: ColorRect
var _trauma := 0.0
var _transitioning := false
var _ended := false
var _current: Vector2i


func _ready() -> void:
	instance = self
	GameState.mode = GameState.Mode.RUN
	if not RunState.active:
		RunState.start_new(RNG.random_seed())
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	projectiles = ProjectileSystem.new()
	fx = FX.new()
	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position = CAMERA_CENTER
	add_child(camera)
	hud = HudScript.new()
	add_child(hud)
	var pause: CanvasLayer = PauseScript.new()
	add_child(pause)
	var top := CanvasLayer.new()
	top.layer = 50
	add_child(top)
	_fade = _overlay_rect(Color(0, 0, 0, 0))
	_flash = _overlay_rect(Color(1, 1, 1, 0))
	top.add_child(_fade)
	top.add_child(_flash)
	Events.player_died.connect(_on_player_died)
	_register_commands()
	start_floor(RunState.floor_index)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	Engine.time_scale = 1.0


func _overlay_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ---------------------------------------------------------------- floor

func start_floor(floor_index: int) -> void:
	RunState.floor_index = floor_index
	RNG.set_floor(floor_index)
	var depth := floor_index + 1
	stratum = Content.get_entry("strata", "hive")  # M1: floor 1 is always The Abandoned Hive
	var cfg: Dictionary = Content.get_entry("config", "floorgen")
	var opts := {
		"required_specials": cfg.get("required_specials", ["treasure"]),
		"brood_cells": cfg.get("floor1_brood_cells", [2, 4]) if floor_index == 0 else [0, 0],
		"brood_cell_room_chance": float(cfg.get("brood_cell_room_chance", 0.5)) if floor_index == 0 else 0.0,
	}
	layout = FloorGen.generate(depth, RNG.stream("map"), cfg, opts)
	var templates := Content.all("rooms").filter(func(t: Dictionary) -> bool: return stratum["id"] in t.get("stratum", []))
	FloorGen.assign_templates(layout, templates, RNG.stream("rooms"))
	_roll_floor_contents()
	if player == null:
		player = PlayerScript.new()
	Events.floor_entered.emit(floor_index)
	Events.banner.emit(tr(stratum["name_key"]), tr("BANNER_FLOOR") % depth)
	Audio.play_music(str(stratum.get("music", "")))
	enter_room(layout["start"], "")


## Items/bosses are rolled at generation time in fixed room order so they don't depend on the
## order the player explores in (determinism, §16.3).
func _roll_floor_contents() -> void:
	if item_pool == null:
		item_pool = ItemPool.from_content()
	var r := RNG.stream("items")
	var bosses := Content.all("bosses").filter(func(b: Dictionary) -> bool: return stratum["id"] in b.get("strata", []))
	bosses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var drops: Dictionary = Content.get_entry("config", "drops")
	for c in layout["order"]:
		var info: Dictionary = layout["rooms"][c]
		match str(info["type"]):
			"treasure":
				info["pedestal"] = item_pool.roll("dig_site", r)
			"boss":
				info["boss_id"] = bosses[RNG.stream("rooms").randi_range(0, bosses.size() - 1)]["id"] if not bosses.is_empty() else ""
				info["pedestal_on_clear"] = item_pool.roll("boss", r)
			"secret":
				if r.randf() < float(drops.get("secret_room", {}).get("item_chance", 0.5)):
					info["pedestal"] = item_pool.roll("secret", r)
			"super_secret":
				info["pedestal"] = item_pool.roll("secret", r)


# ---------------------------------------------------------------- rooms

func enter_room(cell: Vector2i, from_dir: String) -> void:
	if room:
		room.on_exit()
		room.queue_free()
		room = null
	if projectiles.get_parent():
		projectiles.get_parent().remove_child(projectiles)
	if fx.get_parent():
		fx.get_parent().remove_child(fx)
	if player.get_parent():
		player.get_parent().remove_child(player)
	projectiles.clear()
	_current = cell
	var info: Dictionary = layout["rooms"][cell]
	var neighbors := {}
	for d in info["doors"]:
		var n: Vector2i = cell + FloorGen.DIRS[d]
		if layout["rooms"].has(n):
			neighbors[d] = layout["rooms"][n]["type"]
	room = RoomScript.new()
	room.setup(cell, info, Content.get_entry("rooms", info["template"]), neighbors, stratum.get("palette", {}))
	_world.add_child(room)
	room.add_child(fx)
	room.add_child(projectiles)
	projectiles.room = room
	projectiles.player = player
	projectiles.fx = fx
	player.position = room.entry_point(FloorGen.OPPOSITE[from_dir]) if from_dir != "" else Vector2(Room.W / 2.0, Room.H / 2.0 + 16)
	player.velocity = Vector2.ZERO
	room.entities.add_child(player)
	for f in player.effects.familiars:
		if is_instance_valid(f) and f.get_parent():
			f.get_parent().remove_child(f)
			f.position = player.position
			room.entities.add_child(f)
	took_damage_this_room = false
	if info["type"] == "boss" and not info.get("cleared", false):
		var b: Dictionary = Content.get_entry("bosses", str(info.get("boss_id", "")))
		Events.banner.emit(tr(b.get("name_key", "")), tr(b.get("title_key", "")))
	Events.room_entered.emit(int(info["index"]))
	Events.minimap_changed.emit()


func _physics_process(_delta: float) -> void:
	if room == null or player == null or _transitioning or _ended or player.dead:
		return
	var p := player.position
	var dir := ""
	if p.y < -6.0:
		dir = "N"
	elif p.y > Room.H + 6.0:
		dir = "S"
	elif p.x < -6.0:
		dir = "W"
	elif p.x > Room.W + 6.0:
		dir = "E"
	if dir != "" and room.door_state(dir) == "open":
		_transition(dir)


func _transition(dir: String) -> void:
	_transitioning = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.08)
	tw.tween_callback(func() -> void: enter_room(_current + FloorGen.DIRS[dir], dir))
	tw.tween_property(_fade, "color:a", 0.0, 0.12)
	tw.tween_callback(func() -> void: _transitioning = false)


func on_room_cleared(_r: Room) -> void:
	player.effects.on_room_cleared()
	Events.room_cleared.emit(int(_r.info["index"]))
	if _r.info.has("pedestal_on_clear") and not _r.info.has("pedestal"):
		_r.info["pedestal"] = _r.info["pedestal_on_clear"]
		_r.call_deferred("_spawn_pedestal")
	Events.minimap_changed.emit()


func on_secret_opened(cell: Vector2i, dir: String) -> void:
	var n: Vector2i = cell + FloorGen.DIRS[dir]
	if layout["rooms"].has(n):
		var o: Dictionary = layout["rooms"][n].get("opened_secret", {})
		o[FloorGen.OPPOSITE[dir]] = true
		layout["rooms"][n]["opened_secret"] = o
	Events.minimap_changed.emit()


func on_player_hurt() -> void:
	took_damage_this_room = true


## Toxic Spined Chitin breaking: damage burst on every enemy in the room.
func toxic_burst(at: Vector2) -> void:
	fx.ring(at, 90.0, Color(0.4, 0.9, 0.3), 0.4)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.take_hit(20.0, (e.global_position - at).normalized(), ["toxic"])


func on_trapdoor() -> void:
	# Milestone 1 is a single floor: the trapdoor ends the slice. M2 descends to floor 2.
	_end_run(true)


# ---------------------------------------------------------------- death / victory

func _on_player_died() -> void:
	if _ended:
		return
	fx.burst(player.global_position, Color(1, 0.8, 0.2), 40, 120.0, 2.0)
	shake(1.0)
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.6, true, false, true).timeout
	Engine.time_scale = 1.0
	_end_run(false)


func _end_run(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	var lost := 0
	if not victory:
		lost = RunState.lose_stash()
	else:
		MetaSave.data["runs"]["won"] = int(MetaSave.data["runs"].get("won", 0)) + 1
	MetaSave.data["runs"]["best_depth"] = maxi(int(MetaSave.data["runs"].get("best_depth", 0)), RunState.floor_index + 1)
	MetaSave.save_meta()
	MetaSave.delete_run()
	Events.run_ended.emit(victory)
	var end: CanvasLayer = EndScript.new()
	end.setup(victory, lost)
	add_child(end)
	get_tree().paused = true


# ---------------------------------------------------------------- juice

func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func screen_flash(c: Color) -> void:
	if bool(MetaSave.settings.get("accessibility", {}).get("flash_reduction", false)):
		c.a *= 0.3
	_flash.color = c
	create_tween().tween_property(_flash, "color:a", 0.0, 0.35)


func _process(delta: float) -> void:
	if room and RunState.active and not _ended:
		RunState.elapsed += delta
	_trauma = maxf(0.0, _trauma - delta * 2.2)
	var s := _trauma * _trauma * GameState.screen_shake_scale() * 6.0
	var r := RNG.stream("fx")
	camera.offset = Vector2(r.randf_range(-s, s), r.randf_range(-s, s))


# ---------------------------------------------------------------- debug commands

func _register_commands() -> void:
	DebugConsole.register("give", _cmd_give, "give <item_id>")
	DebugConsole.register("spawn", _cmd_spawn, "spawn <enemy_id> [n]")
	DebugConsole.register("reveal", _cmd_reveal, "reveal  reveal the whole map")
	DebugConsole.register("goto", _cmd_goto, "goto <room|boss|treasure|secret|start>  teleport (floors arrive in M2)")
	DebugConsole.register("room", _cmd_room, "room <template_id>  rebuild the current room from a template")
	DebugConsole.register("heal", _cmd_heal, "heal  refill hearts")


func _cmd_heal(_a: PackedStringArray) -> String:
	RunState.hearts = RunState.hearts_max
	return "healed"


func _cmd_give(args: PackedStringArray) -> String:
	if args.is_empty() or not Content.has_entry("items", args[0]):
		return "usage: give <item_id>  (%s)" % ", ".join(Content.ids("items"))
	var left: String = player.pickup_item(args[0])
	return "gave %s%s" % [args[0], (" (dropped " + left + ")") if left != "" else ""]


func _cmd_spawn(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: spawn <enemy_id> [n]"
	var boss := Content.has_entry("bosses", args[0])
	var data: Dictionary = Content.get_entry("bosses" if boss else "enemies", args[0])
	if data.is_empty():
		return "unknown enemy (%s)" % ", ".join(Content.ids("enemies") + Content.ids("bosses"))
	var n: int = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 1
	for i in n:
		room.spawn_enemy(data, room.nearest_free_point(Vector2(Room.W / 2.0, 24 + i * 6)), boss)
	room.is_cleared = false
	room.info["cleared"] = false
	room.call_deferred("_rebuild_walls")
	return "spawned %d %s" % [n, args[0]]


func _cmd_reveal(_a: PackedStringArray) -> String:
	for c in layout["rooms"]:
		layout["rooms"][c]["revealed"] = true
	Events.minimap_changed.emit()
	return "map revealed"


func _cmd_goto(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: goto <boss|treasure|secret|super_secret|start|brood_cell>"
	for c in layout["order"]:
		if layout["rooms"][c]["type"] == args[0]:
			enter_room(c, "")
			return "teleported to %s" % args[0]
	return "no %s room on this floor" % args[0]


func _cmd_room(args: PackedStringArray) -> String:
	if args.is_empty() or not Content.has_entry("rooms", args[0]):
		return "usage: room <template_id>  (%s)" % ", ".join(Content.ids("rooms"))
	var info: Dictionary = layout["rooms"][_current]
	info["template"] = args[0]
	info["cleared"] = false
	info["destroyed"] = []
	info["brood_broken"] = []
	enter_room(_current, "")
	return "room test: %s" % args[0]
