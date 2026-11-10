class_name RunController
extends Node2D
## Owns a run in progress: floor generation and progression (chapter floors), the current room,
## room transitions through door slots, curses, the post-boss Royal Chamber / Mutation Den,
## camera juice, death/victory flow and run-scoped debug commands. One room is instantiated at
## a time; the floor layout dictionary holds every room's persistent state.

static var instance: RunController

const RoomScript := preload("res://scripts/run/room.gd")
const PlayerScript := preload("res://scripts/player/player.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const PauseScript := preload("res://scripts/ui/pause_menu.gd")
const EndScript := preload("res://scripts/ui/end_screen.gd")
const DarknessScript := preload("res://scripts/ui/darkness.gd")
const MutationPickerScript := preload("res://scripts/ui/mutation_picker.gd")

var layout: Dictionary = {}
var stratum: Dictionary = {}
var curse_id := ""
var item_pool: ItemPool
var trinket_pool: ItemPool
var room: Room
var player: CharacterBody2D
var projectiles: ProjectileSystem
var fx: FX
var camera: Camera2D
var hud: CanvasLayer
var took_damage_this_room := false
var took_damage_this_floor := false
var current_anchor := Vector2i.ZERO

var _world: Node2D
var _fade: ColorRect
var _flash: ColorRect
var _darkness: CanvasLayer
var _trauma := 0.0
var _transitioning := false
var _ended := false
var _forced_curse := ""


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
	add_child(camera)
	_darkness = DarknessScript.new()
	add_child(_darkness)
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
	Events.player_damaged.connect(func(_a: int, _s: String) -> void: took_damage_this_floor = true)
	_register_commands()
	if GameState.room_test_template != "":
		_start_room_test(GameState.room_test_template)
		if GameState.lab_mode:
			add_child(load("res://scripts/tools/synergy_lab.gd").new())
			GameState.god_mode = true
	else:
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


# ---------------------------------------------------------------- floors

## The ordered list of stratum ids for the run, across chapters (from config/floorgen chapters).
static func floor_plan() -> Array:
	var out: Array = []
	for ch in Content.get_entry("config", "floorgen").get("chapters", []):
		out.append_array(ch.get("floors", []))
	return out


func start_floor(floor_index: int) -> void:
	RunState.floor_index = floor_index
	RNG.set_floor(floor_index)
	var depth := floor_index + 1
	var plan := floor_plan()
	stratum = Content.get_entry("strata", str(plan[mini(floor_index, plan.size() - 1)]))
	var cfg: Dictionary = Content.get_entry("config", "floorgen")
	curse_id = _forced_curse if _forced_curse != "" else _roll_curse(floor_index, cfg)
	_forced_curse = ""
	if curse_id == "none":
		curse_id = ""
	var opts := {
		"required_specials": cfg.get("required_specials", ["treasure", "shop"]),
		"random_specials": eligible_specials(depth, cfg),
		"random_special_count": int(cfg.get("random_special_count", 1)),
		"brood_cells": cfg.get("floor1_brood_cells", [2, 4]) if floor_index == 0 else [0, 0],
		"brood_cell_room_chance": float(cfg.get("brood_cell_room_chance", 0.5)) if floor_index == 0 else 0.0,
		"labyrinth": curse_effect() == "labyrinth",
	}
	layout = FloorGen.generate(depth, RNG.stream("map"), cfg, opts)
	FloorGen.assign_templates(layout, _templates(), RNG.stream("rooms"))
	_ensure_pools()
	FloorContents.fill(layout, {"floor_index": floor_index, "stratum": stratum, "pool": item_pool,
		"items_rng": RNG.stream("items"), "rooms_rng": RNG.stream("rooms"), "cfg": cfg})
	if player == null:
		player = PlayerScript.new()
	took_damage_this_floor = false
	_darkness.set_enabled(curse_effect() == "darkness", float(Content.get_entry("curses", curse_id).get("light_radius", 56)))
	Events.floor_entered.emit(floor_index)
	var sub := tr("BANNER_FLOOR") % depth
	if curse_id != "":
		sub += "  ·  " + tr(Content.get_entry("curses", curse_id).get("name_key", ""))
	Events.banner.emit(tr(stratum["name_key"]), sub)
	Audio.play_music(str(stratum.get("music", "")))
	enter_room(layout["start"], "")
	player.effects.fire_event("floor_start", player.global_position)


func _ensure_pools() -> void:
	if item_pool == null:
		item_pool = ItemPool.from_content()
	if trinket_pool == null:
		trinket_pool = ItemPool.trinkets_from_content()
	EffectHost.ensure_fluid_map()


func _templates() -> Array:
	return Content.all("rooms").filter(func(t: Dictionary) -> bool:
		var s: Array = t.get("stratum", [])
		return stratum["id"] in s or "*" in s)


## Random special room weights for this depth, with depth/unlock rules applied.
static func eligible_specials(depth: int, cfg: Dictionary) -> Dictionary:
	var out := {}
	var rules: Dictionary = cfg.get("special_rules", {})
	var weights: Dictionary = cfg.get("special_weights", {})
	for t in weights:
		var rule: Dictionary = rules.get(t, {})
		if depth < int(rule.get("min_depth", 1)):
			continue
		if rule.has("unlock"):
			var u := str(rule["unlock"]).split(":")
			if not MetaSave.is_unlocked(u[0], u[1]):
				continue
		out[t] = weights[t]
	return out


func _roll_curse(floor_index: int, cfg: Dictionary) -> String:
	if floor_index == 0 and int(MetaSave.data["runs"].get("started", 0)) <= int(cfg.get("curse_free_runs", 3)):
		return ""
	var r := RNG.stream("misc")
	if r.randf() >= float(cfg.get("curse_chance", 0.15)):
		return ""
	var curses := Content.all("curses").filter(func(c: Dictionary) -> bool:
		if not c.has("unlock"):
			return true
		var u := str(c["unlock"]).split(":")
		return MetaSave.is_unlocked(u[0], u[1]))
	curses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	if curses.is_empty():
		return ""
	return curses[RNG.weighted_index(r, curses.map(func(c: Dictionary) -> float: return float(c.get("weight", 1.0))))]["id"]


func curse_effect() -> String:
	return str(Content.get_entry("curses", curse_id).get("effect", "")) if curse_id != "" else ""


# ---------------------------------------------------------------- rooms

func enter_room(anchor: Vector2i, entry_slot: String) -> void:
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
	RunState.clear_room_effects()
	current_anchor = anchor
	var info: Dictionary = layout["rooms"][anchor]
	var neighbors := {}
	for s in info["links"]:
		neighbors[s] = layout["rooms"][info["links"][s][0]]["type"]
	room = RoomScript.new()
	room.setup(anchor, info, Content.get_entry("rooms", info["template"]), neighbors, stratum.get("palette", {}))
	_world.add_child(room)
	room.add_child(fx)
	room.add_child(projectiles)
	projectiles.room = room
	projectiles.player = player
	projectiles.fx = fx
	player.position = room.entry_point(entry_slot) if entry_slot != "" and info["doors"].has(entry_slot) else room.center() + Vector2(0, 16)
	player.velocity = Vector2.ZERO
	room.entities.add_child(player)
	for f in player.effects.familiars:
		if is_instance_valid(f) and f.get_parent():
			f.get_parent().remove_child(f)
			f.position = player.position
			room.entities.add_child(f)
	took_damage_this_room = false
	_update_camera(true)
	if info["type"] == "boss" and not info.get("cleared", false):
		var b: Dictionary = Content.get_entry("bosses", str(info.get("boss_id", "")))
		Events.banner.emit(tr(b.get("name_key", "")), tr(b.get("title_key", "")))
	Events.room_entered.emit(int(info["index"]))
	Events.minimap_changed.emit()


func _physics_process(_delta: float) -> void:
	if room == null or player == null or _transitioning or _ended or player.dead:
		return
	var slot := room.slot_at(player.position)
	if slot != "" and room.door_state(slot) == "open" and room.info["links"].has(slot):
		_transition(slot)


func _transition(slot: String) -> void:
	_transitioning = true
	var link: Array = room.info["links"][slot]
	var spiked := room.door_kind(slot) == "spiked"
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.08)
	tw.tween_callback(func() -> void:
		enter_room(link[0], link[1])
		if spiked and not RunState.flags.get("flight", false):
			player.hurt(1, "spiked_door"))
	tw.tween_property(_fade, "color:a", 0.0, 0.12)
	tw.tween_callback(func() -> void: _transitioning = false)


## Doors are stored on both sides of a connection; mirror a per-door flag to the other side.
func mirror_door_flag(info: Dictionary, slot: String, key: String) -> void:
	var link: Array = info["links"].get(slot, [])
	if link.is_empty():
		return
	var other: Dictionary = layout["rooms"][link[0]]
	var d: Dictionary = other.get(key, {})
	d[link[1]] = true
	other[key] = d
	Events.minimap_changed.emit()


func on_room_cleared(r: Room) -> void:
	player.effects.on_room_cleared()
	if RunState.mutation_ready():
		call_deferred("_offer_mutation")
	Events.room_cleared.emit(int(r.info["index"]))
	if r.info.has("pedestal_on_clear") and not r.info.has("pedestal"):
		r.info["pedestal"] = r.info["pedestal_on_clear"]
		r.call_deferred("_spawn_pedestals")
	if r.info["type"] == "boss":
		_maybe_open_deal(r)
	Events.minimap_changed.emit()


## Royal Chamber / Mutation Den after the boss (DESIGN.md §8.4).
func _maybe_open_deal(r: Room, force_type: String = "") -> void:
	var cfg: Dictionary = Content.get_entry("config", "floorgen").get("deal", {})
	var type := force_type
	if type == "":
		if RunState.floor_index + 1 < int(cfg.get("min_depth", 2)):
			return
		var chance: float = float(cfg.get("base", 0.3))
		if not took_damage_this_room:
			chance += float(cfg.get("no_boss_damage_bonus", 0.35))
		if not took_damage_this_floor:
			chance += float(cfg.get("no_floor_damage_bonus", 0.1))
		var rm := RNG.stream("misc")
		if rm.randf() >= chance:
			return
		type = "den" if RunState.flags.get("took_den", false) or rm.randf() < 0.5 else "royal"
	var a := FloorGen.add_deal_room(layout, type)
	if a == FloorGen.NONE:
		return
	var info: Dictionary = layout["rooms"][a]
	if info["template"] == "":
		var sorted_t := _templates()
		sorted_t.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["id"]) < str(y["id"]))
		FloorGen.assign_template(info, sorted_t, RNG.stream("rooms"))
		FloorContents.fill_deal(info, item_pool, RNG.stream("items"))
	r.neighbor_types[layout["deal_slot"]] = type
	r.refresh_doors()
	Events.toast.emit(tr("TOAST_DEAL_" + type.to_upper()))


## Radiation meter full: choose 1 of 3 mutations (offered at room clear, never mid-fight).
func _offer_mutation() -> void:
	if not RunState.mutation_ready() or _ended or get_node_or_null("MutationPicker"):
		return
	var options := roll_mutations(3, RNG.stream("items"))
	if options.is_empty():
		return
	RunState.consume_mutation()
	var picker: CanvasLayer = MutationPickerScript.new()
	picker.name = "MutationPicker"
	picker.setup(options)
	picker.chosen.connect(func(id: String) -> void:
		player.effects.add_mutation(id)
		Events.banner.emit(tr(Content.get_entry("mutations", id).get("name_key", "")), tr("BANNER_MUTATED"))
		call_deferred("_offer_mutation"))
	add_child(picker)


## Up to n distinct mutations, weighted, unlock-gated (DESIGN.md §8.2).
static func roll_mutations(n: int, r: RandomNumberGenerator) -> Array:
	var pool := Content.all("mutations").filter(func(m: Dictionary) -> bool:
		if not m.has("unlock"):
			return true
		var u := str(m["unlock"]).split(":")
		return MetaSave.is_unlocked(u[0], u[1]))
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var i := RNG.weighted_index(r, pool.map(func(m: Dictionary) -> float: return float(m.get("weight", 1.0))))
		out.append(pool[i]["id"])
		pool.remove_at(i)
	return out


func on_player_hurt() -> void:
	took_damage_this_room = true
	took_damage_this_floor = true


## Toxic Spined Chitin breaking: damage burst on every enemy in the room.
func toxic_burst(at: Vector2) -> void:
	fx.ring(at, 90.0, Color(0.4, 0.9, 0.3), 0.4)
	for e in room.room_enemies():
		e.take_hit(20.0, (e.global_position - at).normalized(), ["toxic"])


func on_trapdoor() -> void:
	if GameState.room_test_template != "":
		_end_run(true)
		return
	if RunState.floor_index + 1 < floor_plan().size():
		_descend(RunState.floor_index + 1)
	else:
		# End of the content built so far (chapter 1 in M2); later chapters arrive in M4.
		_end_run(true)


func _descend(next_floor: int) -> void:
	_transitioning = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void: start_floor(next_floor))
	tw.tween_property(_fade, "color:a", 0.0, 0.35)
	tw.tween_callback(func() -> void: _transitioning = false)


# ---------------------------------------------------------------- room test (room editor)

func _start_room_test(template_id: String) -> void:
	var t: Dictionary = Content.get_entry("rooms", template_id)
	var st: Array = t.get("stratum", ["hive"])
	stratum = Content.get_entry("strata", "hive" if st[0] == "*" else str(st[0]))
	if stratum.is_empty():
		stratum = Content.get_entry("strata", "hive")
	var shape: String = t.get("shape", "1x1")
	var a := Vector2i(1, 1)
	var cells: Array = []
	for off in FloorGen.SHAPES[shape]:
		cells.append(a + off)
	var types: Array = t.get("room_types", ["normal"])
	var info := {"index": 0, "type": str(types[0]), "shape": shape, "cells": cells, "dist": 1, "doors": {}, "links": {},
		"brood_cell": "brood_cell" in t.get("tags", []), "template": template_id, "home_slot": "", "offmap": false}
	var owner := {}
	for c in cells:
		owner[c] = a
	layout = {"depth": 1, "start": a, "boss": a if info["type"] == "boss" else FloorGen.NONE, "secret": FloorGen.NONE,
		"super_secret": FloorGen.NONE, "deal": FloorGen.NONE, "deal_slot": "", "order": [a], "owner": owner, "rooms": {a: info}}
	_ensure_pools()
	FloorContents.fill(layout, {"floor_index": 0, "stratum": stratum, "pool": item_pool,
		"items_rng": RNG.stream("items"), "rooms_rng": RNG.stream("rooms"), "cfg": Content.get_entry("config", "floorgen")})
	if info["type"] in ["royal", "den"]:
		FloorContents.fill_deal(info, item_pool, RNG.stream("items"))
	if player == null:
		player = PlayerScript.new()
	Events.banner.emit(tr("BANNER_ROOM_TEST"), template_id)
	enter_room(a, "")


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


# ---------------------------------------------------------------- camera & juice

func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func screen_flash(c: Color) -> void:
	if bool(MetaSave.settings.get("accessibility", {}).get("flash_reduction", false)):
		c.a *= 0.3
	_flash.color = c
	create_tween().tween_property(_flash, "color:a", 0.0, 0.35)


## Small rooms are framed statically; big rooms follow the player, clamped to the walls.
func _update_camera(snap: bool) -> void:
	if room == null:
		return
	var view := get_viewport_rect().size / camera.zoom
	var target := Vector2(room.room_w / 2.0, room.room_h / 2.0 - 4.0)
	var p: Vector2 = player.position if player else target
	if room.room_w + Room.WALL * 2 > view.x:
		target.x = clampf(p.x, -Room.WALL + view.x / 2.0, room.room_w + Room.WALL - view.x / 2.0)
	if room.room_h + Room.TOP_WALL + Room.WALL > view.y - 36.0:
		target.y = clampf(p.y, -Room.TOP_WALL - 18.0 + view.y / 2.0, room.room_h + Room.WALL + 18.0 - view.y / 2.0)
	camera.position = target if snap else camera.position.lerp(target, 0.18)


func _process(delta: float) -> void:
	if room and RunState.active and not _ended:
		RunState.elapsed += delta
	_update_camera(false)
	_trauma = maxf(0.0, _trauma - delta * 2.2)
	var s := _trauma * _trauma * GameState.screen_shake_scale() * 6.0
	var r := RNG.stream("fx")
	camera.offset = Vector2(r.randf_range(-s, s), r.randf_range(-s, s))
	if player and _darkness.enabled_now:
		_darkness.track(get_viewport().get_canvas_transform() * player.global_position, get_viewport_rect().size)


# ---------------------------------------------------------------- debug commands

func _register_commands() -> void:
	DebugConsole.register("give", _cmd_give, "give <item_id>")
	DebugConsole.register("spawn", _cmd_spawn, "spawn <enemy_id> [n]")
	DebugConsole.register("reveal", _cmd_reveal, "reveal  reveal the whole map (incl. secrets)")
	DebugConsole.register("goto", _cmd_goto, "goto <floor number | room type>  e.g. goto 2, goto shop")
	DebugConsole.register("room", _cmd_room, "room <template_id>  rebuild the current room from a template (same shape)")
	DebugConsole.register("heal", _cmd_heal, "heal  refill hearts")
	DebugConsole.register("curse", _cmd_curse, "curse <id|none>  regenerate this floor with a curse")
	DebugConsole.register("deal", _cmd_deal, "deal <royal|den>  open a deal door in the boss room")
	DebugConsole.register("mana", func(a: PackedStringArray) -> String: return _cmd_consumable(a, "mana"), "mana <n>")
	DebugConsole.register("jelly", func(a: PackedStringArray) -> String: return _cmd_consumable(a, "royal_jelly"), "jelly <n>")


func _cmd_consumable(args: PackedStringArray, what: String) -> String:
	var n: int = int(args[0]) if not args.is_empty() and args[0].is_valid_int() else 10
	match what:
		"mana": RunState.add_mana(n)
		"royal_jelly": RunState.add_royal_jelly(n)
	return "+%d %s" % [n, what]


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
		room.spawn_enemy(data, room.nearest_free_point(Vector2(room.room_w / 2.0, 24 + i * 6)), boss)
	return "spawned %d %s" % [n, args[0]]


func _cmd_reveal(_a: PackedStringArray) -> String:
	for c in layout["rooms"]:
		layout["rooms"][c]["revealed"] = true
	Events.minimap_changed.emit()
	return "map revealed"


func _cmd_goto(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: goto <floor 1..%d | room type>" % floor_plan().size()
	if args[0].is_valid_int():
		var f: int = int(args[0]) - 1
		if f < 0 or f >= floor_plan().size():
			return "floors 1..%d exist so far" % floor_plan().size()
		start_floor(f)
		return "floor %d" % (f + 1)
	for a in layout["order"]:
		if layout["rooms"][a]["type"] == args[0]:
			enter_room(a, "")
			return "teleported to %s" % args[0]
	return "no %s room on this floor" % args[0]


func _cmd_room(args: PackedStringArray) -> String:
	if args.is_empty() or not Content.has_entry("rooms", args[0]):
		return "usage: room <template_id>  (%s)" % ", ".join(Content.ids("rooms"))
	var info: Dictionary = layout["rooms"][current_anchor]
	var t: Dictionary = Content.get_entry("rooms", args[0])
	if t.get("shape", "1x1") != info["shape"]:
		return "shape mismatch: this room is %s, %s is %s (use the room editor's Test button)" % [info["shape"], args[0], t.get("shape", "1x1")]
	info["template"] = args[0]
	info["cleared"] = false
	info["destroyed"] = []
	info["brood_broken"] = []
	enter_room(current_anchor, "")
	return "room test: %s" % args[0]


func _cmd_curse(args: PackedStringArray) -> String:
	if args.is_empty() or (args[0] != "none" and not Content.has_entry("curses", args[0])):
		return "usage: curse <none|%s>" % "|".join(Content.ids("curses"))
	_forced_curse = args[0]
	start_floor(RunState.floor_index)
	return "floor regenerated with curse: %s" % args[0]


func _cmd_deal(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0] in ["royal", "den"]:
		return "usage: deal <royal|den>"
	var boss: Vector2i = layout["boss"]
	if boss == FloorGen.NONE:
		return "no boss room on this floor"
	if current_anchor != boss:
		enter_room(boss, "")
	_maybe_open_deal(room, args[0])
	return "deal door opened (%s)" % args[0]
