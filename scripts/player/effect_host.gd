class_name EffectHost
extends RefCounted
## Applies item effects (DESIGN.md §6.4). Each effect `type` is implemented by
## res://scripts/effects/<type>.gd exposing:
##   const PERSISTENT: bool   (true = re-derived from the item list on rebuild; false = one-shot)
##   static func apply(host: EffectHost, effect: Dictionary, item_id: String) -> void
## Adding a new effect type = adding one script. Gameplay code never checks item ids.

const EFFECT_DIR := "res://scripts/effects/"
const ABILITY_DIR := "res://scripts/effects/abilities/"
const FamiliarScript := preload("res://scripts/actors/familiar.gd")

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


## Picking up an item: record it, run one-shot effects, then rebuild persistent ones.
func add_item(id: String) -> void:
	var item: Dictionary = Content.get_entry("items", id)
	if item.get("kind", "") != "active":
		RunState.items.append(id)
	RunState.bump("items")
	Events.item_picked_up.emit(id)
	MetaSave.data["trove_seen"]["items:" + id] = true
	for e in item.get("effects", []):
		var s := effect_script(str(e["type"]))
		if s and not s.PERSISTENT:
			s.apply(self, e, id)
	rebuild()


## Re-derives all persistent effects from RunState.items (used on pickup and on resume).
func rebuild() -> void:
	RunState.stat_mods.clear()
	RunState.shot_mods.clear()
	RunState.tints.clear()
	for f in familiars:
		if is_instance_valid(f):
			f.queue_free()
	familiars.clear()
	var owned: Array = RunState.items.duplicate()
	if RunState.active_item != "":
		owned.append(RunState.active_item)
	for id in owned:
		var item: Dictionary = Content.get_entry("items", id)
		var tint: String = item.get("visual", {}).get("tint", "")
		if tint != "":
			RunState.tints.append(Color.from_string(tint, Color.WHITE))
		for e in item.get("effects", []):
			var s := effect_script(str(e["type"]))
			if s and s.PERSISTENT:
				s.apply(self, e, id)
	Events.stats_changed.emit()


func add_familiar(params: Dictionary, sprite: String) -> void:
	var f: Node2D = FamiliarScript.new()
	f.setup(player, params, sprite, familiars.size())
	f.global_position = player.global_position
	player.attach_familiar.call_deferred(f)
	familiars.append(f)


func use_active() -> void:
	var id := RunState.active_item
	if id == "" or RunState.active_charge < RunState.active_max:
		return
	for e in Content.get_entry("items", id).get("effects", []):
		if e["type"] == "active":
			var path := ABILITY_DIR + str(e["ability"]) + ".gd"
			if not ResourceLoader.exists(path):
				push_error("EffectHost: no ability '%s'" % e["ability"])
				return
			load(path).activate(player, e.get("params", {}))
			RunState.active_charge = 0
			Events.consumables_changed.emit()
			Audio.play_sfx("active_" + str(e["ability"]))


func on_room_cleared() -> void:
	if RunState.active_item != "" and RunState.active_charge < RunState.active_max:
		RunState.active_charge += 1
		Events.consumables_changed.emit()
