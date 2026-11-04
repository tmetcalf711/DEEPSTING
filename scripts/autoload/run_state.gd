extends Node
## Data for the run in progress (DESIGN.md §16.2). Pure data plus serialization. Gameplay nodes
## read and mutate this; MetaSave.save_run(RunState.to_dict()) writes the mid-run snapshot.

const BASE_STATS: Dictionary = {
	"damage": 3.5, "fire_rate": 2.7, "shot_speed": 1.0, "range": 260.0,
	"move_speed": 1.0, "luck": 0.0,
}
const STAT_LIMITS: Dictionary = {  # stat -> [floor, cap]
	"damage": [0.5, 1.0e9], "fire_rate": [0.5, 30.0], "shot_speed": [0.6, 2.5],
	"range": [60.0, 900.0], "move_speed": [0.4, 2.0], "luck": [-5.0, 10.0],
}
const MAX_TOTAL_CELLS := 12

var active: bool = false
var seed_value: int = 0
var caste: String = "worker"
var floor_index: int = 0
var room_index: int = 0
var elapsed: float = 0.0

# Health, in half-cells.
var honeycomb_max: int = 6
var honeycomb: int = 6
var royal: int = 0
var toxic: int = 0

# Consumables
var forage: int = 0
var dig_charges: int = 1
var markers: int = 0

var items: Array[String] = []
var trinket: String = ""
var active_item: String = ""
var active_charge: int = 0
var consumable_slot: String = ""
var radiation: int = 0
var mutations: Array[String] = []
var flags: Dictionary = {}
var stat_mods: Array[Dictionary] = []  # [{stat, add, mult}], rebuilt from items/mutations


func start_new(run_seed: int, caste_id: String = "worker") -> void:
	reset()
	active = true
	seed_value = run_seed & 0xFFFFFFFF
	caste = caste_id
	RNG.set_run_seed(seed_value)
	MetaSave.data["runs"]["started"] = int(MetaSave.data["runs"].get("started", 0)) + 1
	Events.run_started.emit(seed_value)


func reset() -> void:
	active = false
	seed_value = 0
	caste = "worker"
	floor_index = 0
	room_index = 0
	elapsed = 0.0
	honeycomb_max = 6
	honeycomb = 6
	royal = 0
	toxic = 0
	forage = 0
	dig_charges = 1
	markers = 0
	items = []
	trinket = ""
	active_item = ""
	active_charge = 0
	consumable_slot = ""
	radiation = 0
	mutations = []
	flags = {}
	stat_mods = []


## final = clamp((base + sum(add)) * prod(mult), floor, cap)  (DESIGN.md §3.3)
func stat(stat_name: String) -> float:
	var base: float = BASE_STATS.get(stat_name, 0.0)
	var add := 0.0
	var mult := 1.0
	for m in stat_mods:
		if m.get("stat", "") == stat_name:
			add += float(m.get("add", 0.0))
			mult *= float(m.get("mult", 1.0))
	var lim: Array = STAT_LIMITS.get(stat_name, [-1.0e9, 1.0e9])
	return clampf((base + add) * mult, lim[0], lim[1])


func total_cells_half() -> int:
	return honeycomb_max + royal + toxic


func seed_string() -> String:
	return RNG.seed_to_string(seed_value)


func to_dict() -> Dictionary:
	return {
		"seed": seed_value, "caste": caste, "floor_index": floor_index, "room_index": room_index,
		"elapsed": elapsed,
		"health": {"honeycomb_max": honeycomb_max, "honeycomb": honeycomb, "royal": royal, "toxic": toxic},
		"consumables": {"forage": forage, "dig_charges": dig_charges, "markers": markers},
		"items": items.duplicate(), "trinket": trinket, "active_item": active_item,
		"active_charge": active_charge, "consumable_slot": consumable_slot,
		"radiation": radiation, "mutations": mutations.duplicate(), "flags": flags.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	reset()
	active = true
	seed_value = int(d.get("seed", 0))
	caste = str(d.get("caste", "worker"))
	floor_index = int(d.get("floor_index", 0))
	room_index = int(d.get("room_index", 0))
	elapsed = float(d.get("elapsed", 0.0))
	var h: Dictionary = d.get("health", {})
	honeycomb_max = int(h.get("honeycomb_max", 6))
	honeycomb = int(h.get("honeycomb", honeycomb_max))
	royal = int(h.get("royal", 0))
	toxic = int(h.get("toxic", 0))
	var c: Dictionary = d.get("consumables", {})
	forage = int(c.get("forage", 0))
	dig_charges = int(c.get("dig_charges", 1))
	markers = int(c.get("markers", 0))
	items.assign(d.get("items", []))
	trinket = str(d.get("trinket", ""))
	active_item = str(d.get("active_item", ""))
	active_charge = int(d.get("active_charge", 0))
	consumable_slot = str(d.get("consumable_slot", ""))
	radiation = int(d.get("radiation", 0))
	mutations.assign(d.get("mutations", []))
	flags = d.get("flags", {}).duplicate(true)
	# Run snapshots are taken at floor start; streams derive from (seed, floor), so re-seeding
	# reproduces the floor exactly.
	RNG.set_run_seed(seed_value)
	RNG.set_floor(floor_index)
