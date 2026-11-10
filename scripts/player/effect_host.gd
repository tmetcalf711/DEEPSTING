class_name EffectHost
extends RefCounted
## Applies effects from everything the wasp owns (DESIGN.md §6.4): passive/active items, the
## knick-knack (trinket), mutations, and one-shot consumables (fossils, Strange Fluids).
##
## Each effect `type` is implemented by res://scripts/effects/<type>.gd exposing:
##   const PERSISTENT: bool   (true = re-derived from what you own on rebuild; false = one-shot)
##   static func apply(host: EffectHost, effect: Dictionary, source_id: String) -> void
## Event hooks ("trigger" effects) and on-hit procs ("proc" effects) are collected on rebuild and
## dispatched generically here and in ProjectileSystem. Gameplay code never checks item ids.

const EFFECT_DIR := "res://scripts/effects/"
const ABILITY_DIR := "res://scripts/effects/abilities/"
const FamiliarScript := preload("res://scripts/actors/familiar.gd")
const TRIGGER_EVENTS: PackedStringArray = ["kill", "room_clear", "floor_start", "damage_taken"]

var player: Node2D
var familiars: Array[Node2D] = []
static var _scripts: Dictionary = {}


func _init(p_player: Node2D) -> void:
	player = p_player


static func effect_script(type: String) -> Script:
	if not _scripts.has(type):
		var path := EFFECT_DIR + type + ".gd"
		_scripts[type] = load(path) if ResourceLoader.exists(path) else null
		if _scripts[type] == null:
			push_error("EffectHost: no effect script for type '%s'" % type)
	return _scripts[type]


static func ability_script(ability: String) -> Script:
	var path := ABILITY_DIR + ability + ".gd"
	if not ResourceLoader.exists(path):
		push_error("EffectHost: no ability '%s'" % ability)
		return null
	return load(path)


## Runs one-shot effects of a source (item pickup, mutation chosen, fluid drunk...).
func run_one_shot(effects: Array, source_id: String) -> void:
	for e in effects:
		var s := effect_script(str(e["type"]))
		if s and not s.PERSISTENT:
			s.apply(self, e, source_id)


## The build "tags" an owned thing contributes: projectile modifiers and on-hit proc kinds.
static func build_tags(entry: Dictionary) -> Array:
	var out: Array = []
	for e in entry.get("effects", []):
		match str(e.get("type", "")):
			"projectile_mod":
				out.append(str(e["modifier"]))
			"proc":
				out.append("element" if e["kind"] == "element" else str(e["kind"]))
	return out


## True when a new item's tags interact with something already owned (config/synergies.json).
## Detected generically from tag pairs; no item pairs are listed anywhere.
static func is_synergy(new_item_id: String) -> bool:
	var new_tags := build_tags(Content.get_entry("items", new_item_id))
	if new_tags.is_empty():
		return false
	var have := {}
	for src in owned_sources():
		if src[1] == new_item_id:
			continue
		for t in build_tags(Content.get_entry(src[0], src[1])):
			have[t] = true
	for pair in Content.get_entry("config", "synergies").get("pairs", []):
		var a: String = pair[0]
		var b: String = pair[1]
		if (new_tags.has(a) and have.has(b)) or (new_tags.has(b) and have.has(a)):
			return true
	return false


## Picking up an item: record it, run one-shot effects, then rebuild persistent ones.
func add_item(id: String) -> void:
	var item: Dictionary = Content.get_entry("items", id)
	if item.get("kind", "") != "active":
		RunState.items.append(id)
	RunState.bump("items")
	Events.item_picked_up.emit(id)
	MetaSave.data["trove_seen"]["items:" + id] = true
	run_one_shot(item.get("effects", []), id)
	rebuild()


## Swaps in a knick-knack; returns the one that was held ("" if none).
func set_trinket(id: String) -> String:
	var old := RunState.trinket
	RunState.trinket = id
	if id != "":
		MetaSave.data["trove_seen"]["trinkets:" + id] = true
		run_one_shot(Content.get_entry("trinkets", id).get("effects", []), id)
	rebuild()
	return old


func add_mutation(id: String) -> void:
	RunState.mutations.append(id)
	MetaSave.data["trove_seen"]["mutations:" + id] = true
	run_one_shot(Content.get_entry("mutations", id).get("effects", []), id)
	rebuild()


## Everything owned, as [category, id] pairs, in a stable order.
static func owned_sources() -> Array:
	var out: Array = []
	for id in RunState.items:
		out.append(["items", id])
	if RunState.active_item != "":
		out.append(["items", RunState.active_item])
	if RunState.trinket != "":
		out.append(["trinkets", RunState.trinket])
	for id in RunState.mutations:
		out.append(["mutations", id])
	return out


## Re-derives all persistent effects from what's owned (on pickup and on resume).
func rebuild() -> void:
	RunState.stat_mods.clear()
	RunState.shot_mods.clear()
	RunState.tints.clear()
	RunState.triggers.clear()
	RunState.procs.clear()
	RunState.auras.clear()
	for f in familiars:
		if is_instance_valid(f):
			f.queue_free()
	familiars.clear()
	for src in owned_sources():
		var entry: Dictionary = Content.get_entry(src[0], src[1])
		var tint: String = entry.get("visual", {}).get("tint", "")
		if tint != "":
			RunState.tints.append(Color.from_string(tint, Color.WHITE))
		for e in entry.get("effects", []):
			var s := effect_script(str(e["type"]))
			if s and s.PERSISTENT:
				s.apply(self, e, src[1])
	Events.stats_changed.emit()


func add_familiar(params: Dictionary, sprite: String, behavior: String = "shooter") -> void:
	var f: Node2D = FamiliarScript.new()
	f.setup(player, params, sprite, familiars.size(), behavior)
	f.global_position = player.global_position
	player.attach_familiar.call_deferred(f)
	familiars.append(f)


func use_active() -> void:
	var id := RunState.active_item
	if id == "" or RunState.active_charge < RunState.active_max:
		return
	for e in Content.get_entry("items", id).get("effects", []):
		if e["type"] == "active":
			var s := ability_script(str(e["ability"]))
			if s == null:
				return
			s.activate(player, e.get("params", {}))
			RunState.active_charge = 0
			Events.consumables_changed.emit()
			Audio.play_sfx("active_" + str(e["ability"]))


func charge_active(n: int = 1) -> void:
	if RunState.active_item != "" and RunState.active_charge < RunState.active_max:
		RunState.active_charge = mini(RunState.active_max, RunState.active_charge + n)
		Events.consumables_changed.emit()


func on_room_cleared() -> void:
	charge_active(1)
	fire_event("room_clear", player.global_position)


# ---------------------------------------------------------------- consumables

## Uses the held fossil or Strange Fluid (DESIGN.md §4).
func use_consumable() -> void:
	var c: Dictionary = RunState.consumable
	if c.is_empty():
		return
	RunState.consumable = {}
	match str(c.get("kind", "")):
		"fossil":
			var f: Dictionary = Content.get_entry("fossils", str(c["id"]))
			Events.banner.emit(tr(f.get("name_key", "")), tr(f.get("desc_key", "")))
			run_one_shot(f.get("effects", []), str(c["id"]))
			MetaSave.add_counter("fossils_used")
		"fluid":
			var fid := fluid_for_color(str(c["id"]))
			var fl: Dictionary = Content.get_entry("fluids", fid)
			var was_known: bool = RunState.fluids_identified.has(fid)
			RunState.fluids_identified[fid] = true
			Events.banner.emit(tr(fl.get("name_key", "")), "" if was_known else tr("BANNER_FLUID_IDENTIFIED"))
			run_one_shot(fl.get("effects", []), fid)
			MetaSave.add_counter("fluids_drunk")
	Audio.play_sfx("consumable_use")
	Events.consumables_changed.emit()
	rebuild()


## The run's random color -> fluid effect mapping, made once per run from the seed.
static func ensure_fluid_map() -> void:
	if not RunState.fluid_map.is_empty():
		return
	var colors: Array = Content.get_entry("config", "fluids").get("colors", []).map(func(c: Dictionary) -> String: return str(c["id"]))
	var effects: Array = Content.ids("fluids")
	var r := RNG.room_stream("items", -1, 0)  # run-level stream: independent of floors and rooms
	RNG.shuffle(r, effects)
	for i in colors.size():
		if effects.is_empty():
			break
		RunState.fluid_map[colors[i]] = effects[i % effects.size()]


static func fluid_for_color(color_id: String) -> String:
	ensure_fluid_map()
	return str(RunState.fluid_map.get(color_id, ""))


## Display name for a held/seen fluid: its effect once identified, else its color.
static func fluid_display_name(color_id: String) -> String:
	var fid := fluid_for_color(color_id)
	if RunState.fluids_identified.has(fid) or RunState.flags.get("identify_fluids", false):
		return TranslationServer.translate(Content.get_entry("fluids", fid).get("name_key", ""))
	for c in Content.get_entry("config", "fluids").get("colors", []):
		if c["id"] == color_id:
			return TranslationServer.translate(str(c["name_key"]))
	return "?"


# ---------------------------------------------------------------- event triggers

## Fires every collected trigger for an event ("kill", "room_clear", "floor_start", "damage_taken").
func fire_event(event: String, at: Vector2) -> void:
	if RunState.triggers.is_empty():
		return
	var luck := RunState.stat("luck")
	var r := RNG.stream("misc")
	for t in RunState.triggers:
		if t.get("event", "") != event:
			continue
		var chance: float = float(t.get("chance", 1.0)) + float(t.get("per_luck", 0.0)) * luck
		if r.randf() < chance:
			do_action(t.get("action", {}), at)


## Generic action library shared by triggers (and usable by abilities).
func do_action(a: Dictionary, at: Vector2) -> void:
	var rc := RunController.instance
	match str(a.get("kind", "")):
		"pickup":
			if rc and rc.room:
				for i in int(a.get("count", 1)):
					rc.room.spawn_pickup(str(a["id"]), at, Vector2.from_angle(RNG.stream("fx").randf() * TAU) * 35.0)
		"heal":
			RunState.heal(int(a.get("amount", 1)))
		"shield":
			RunState.add_shield(str(a.get("shield", "chitin")), int(a.get("amount", 1)))
		"mana":
			RunState.add_mana(int(a.get("amount", 1)))
		"dig_charge":
			RunState.add_dig_charges(int(a.get("amount", 1)))
		"royal_jelly":
			RunState.add_royal_jelly(int(a.get("amount", 1)))
		"radiation":
			RunState.add_radiation(int(a.get("amount", 5)))
		"charge_active":
			charge_active(int(a.get("amount", 1)))
		"stun_room":
			if rc and rc.room:
				for e in rc.room.room_enemies():
					e.stun(float(a.get("duration", 1.0)))
		"burst":
			if rc:
				var spec: Dictionary = player.spec.duplicate(true)
				spec["damage"] = float(spec["damage"]) * float(a.get("damage_mult", 1.0))
				var n: int = int(a.get("count", 8))
				for i in n:
					rc.projectiles.spawn_player_shot(at, Vector2.from_angle(TAU * i / n), spec)
	Events.consumables_changed.emit()
