extends Node
## Data for the run in progress (DESIGN.md §16.2). Pure data plus rules that don't need nodes
## (health, stats, consumables, floor stash). Gameplay nodes read and mutate this.
##
## Health model (user decision): Hearts are refillable containers; Chitin is a temporary shield
## layer; Toxic Spined Chitin is a shield that bursts for room-wide damage when it breaks.
## All health values are in HALF-hearts.

const BASE_STATS: Dictionary = {
	# World units: 16 px tiles; a 1x1 room interior is 208 x 112 px (DESIGN.md §3.3).
	"damage": 3.5, "fire_rate": 2.7, "shot_speed": 1.0, "range": 150.0,
	"move_speed": 1.0, "luck": 0.0, "dash_cooldown": 0.9,
}
const STAT_LIMITS: Dictionary = {  # stat -> [floor, cap]
	"damage": [0.5, 1.0e9], "fire_rate": [0.5, 30.0], "shot_speed": [0.6, 2.5],
	"range": [40.0, 600.0], "move_speed": [0.4, 2.0], "luck": [-5.0, 10.0],
	"dash_cooldown": [0.25, 2.0],
}
const MAX_TOTAL_HEARTS := 12  # containers + shields, in whole hearts
const MAX_CONSUMABLE := 99

var active: bool = false
var seed_value: int = 0
var caste: String = "worker"
var floor_index: int = 0
var elapsed: float = 0.0

# Health (half-hearts)
var hearts_max: int = 6
var hearts: int = 6
var shields: Array[String] = []  # per half-heart, "chitin" | "toxic"; damage pops from the back

# Consumables
var mana: int = 0          # in-run currency (chips=1, fragments=5, chunks=10, crystals=25)
var dig_charges: int = 1   # bombs
var royal_jelly: int = 0   # keys

# Inventory
var items: Array[String] = []
var active_item: String = ""
var active_charge: int = 0
var active_max: int = 0
var flags: Dictionary = {}
var stat_mods: Array[Dictionary] = []  # [{stat, add, mult, source}]  rebuilt from items
var shot_mods: Array[Dictionary] = []  # [{modifier, params, source}] rebuilt from items
var tints: Array[Color] = []           # shot tints contributed by items (visual only)
var triggers: Array[Dictionary] = []   # [{event, chance, per_luck, action}] rebuilt from owned things
var procs: Array[Dictionary] = []      # [{kind, chance, per_luck, params}] on-hit, rebuilt
var auras: Array[Dictionary] = []      # [{radius, dps}] rebuilt
var perma_mods: Array[Dictionary] = [] # permanent stat changes from Strange Fluids (serialized)
var room_mods: Array[Dictionary] = []  # stat buffs that end when you leave the room (fossils)
var room_flags: Dictionary = {}        # flags that end when you leave the room

# Knick-knack (trinket), the fossil/fluid slot, and the Strange Fluid color mapping for the run
var trinket: String = ""
var consumable: Dictionary = {}        # {} | {"kind": "fossil"|"fluid", "id": fossil id | fluid color id}
var fluid_map: Dictionary = {}         # color id -> fluid id (seeded per run)
var fluids_identified: Dictionary = {} # fluid id -> true

# Radiation (Nuclear Throne model, DESIGN.md §8.2)
var radiation: float = 0.0
var radiation_threshold: int = 60
var mutations_offered: int = 0
var mutations: Array[String] = []
var bosses_met: Array = []            # boss ids already rolled this run (avoid repeats)
var floor_strata: Dictionary = {}      # "floor index" -> stratum id chosen for this run (main or alt)

# Floor stash: hauled materials waiting to be carried up the boss shaft. Lost on death.
var floor_stash: Dictionary = {}  # resource_type -> amount

# Run stats (for the summary screen and achievements later)
var stats: Dictionary = {}


func start_new(run_seed: int, caste_id: String = "worker") -> void:
	reset()
	active = true
	seed_value = run_seed & 0xFFFFFFFF
	caste = caste_id
	RNG.set_run_seed(seed_value)
	var c: Dictionary = Content.get_entry("characters", caste_id)
	var cs: Dictionary = c.get("stats", {})
	hearts_max = int(cs.get("hearts", 6))
	hearts = hearts_max
	dig_charges = int(c.get("start", {}).get("dig_charges", 1))
	MetaSave.data["runs"]["started"] = int(MetaSave.data["runs"].get("started", 0)) + 1
	Events.run_started.emit(seed_value)


func reset() -> void:
	active = false
	seed_value = 0
	caste = "worker"
	floor_index = 0
	elapsed = 0.0
	hearts_max = 6
	hearts = 6
	shields = []
	mana = 0
	dig_charges = 1
	royal_jelly = 0
	items = []
	active_item = ""
	active_charge = 0
	active_max = 0
	flags = {}
	stat_mods = []
	shot_mods = []
	tints = []
	triggers = []
	procs = []
	auras = []
	perma_mods = []
	room_mods = []
	room_flags = {}
	trinket = ""
	consumable = {}
	fluid_map = {}
	fluids_identified = {}
	radiation = 0.0
	radiation_threshold = int(Content.get_entry("config", "radiation").get("first_threshold", 60))
	mutations_offered = 0
	mutations = []
	floor_strata = {}
	bosses_met = []
	floor_stash = {}
	stats = {"kills": 0, "rooms_cleared": 0, "brood_rescued": 0, "damage_taken": 0,
		"secrets_found": 0, "pulp_banked": 0, "stash_lost": 0, "items": 0}


# ---------------------------------------------------------------- stats

## final = clamp((base + sum(add)) * prod(mult), floor, cap)  (DESIGN.md §3.3)
func stat(stat_name: String) -> float:
	if perma_mods.is_empty() and room_mods.is_empty():
		return compute_stat(stat_name, stat_mods)
	var all_mods: Array = []
	all_mods.append_array(stat_mods)
	all_mods.append_array(perma_mods)
	all_mods.append_array(room_mods)
	return compute_stat(stat_name, all_mods)


func flag(name: String) -> bool:
	return bool(flags.get(name, false)) or bool(room_flags.get(name, false))


## Leaving a room ends room-only buffs (fossils like Shark Tooth / Feather Imprint).
func clear_room_effects() -> void:
	if room_mods.is_empty() and room_flags.is_empty():
		return
	room_mods.clear()
	room_flags.clear()
	Events.stats_changed.emit()


# ---------------------------------------------------------------- radiation

func add_radiation(amount: float) -> void:
	radiation = maxf(0.0, radiation + amount)
	Events.radiation_changed.emit(radiation, radiation_threshold)


func mutation_ready() -> bool:
	return radiation >= radiation_threshold


## Spends a full meter and raises the next threshold (60, 90, 120...).
func consume_mutation() -> void:
	radiation -= radiation_threshold
	radiation_threshold += int(Content.get_entry("config", "radiation").get("threshold_step", 30))
	mutations_offered += 1
	Events.radiation_changed.emit(radiation, radiation_threshold)


static func compute_stat(stat_name: String, mods: Array) -> float:
	var base: float = BASE_STATS.get(stat_name, 0.0)
	var add := 0.0
	var mult := 1.0
	for m in mods:
		if m.get("stat", "") == stat_name:
			add += float(m.get("add", 0.0))
			mult *= float(m.get("mult", 1.0))
	var lim: Array = STAT_LIMITS.get(stat_name, [-1.0e9, 1.0e9])
	return clampf((base + add) * mult, lim[0], lim[1])


func all_stats() -> Dictionary:
	var out := {}
	for k in BASE_STATS:
		out[k] = stat(k)
	return out


# ---------------------------------------------------------------- health

func total_hearts_half() -> int:
	return hearts_max + shields.size()


func is_dead() -> bool:
	return hearts <= 0 and shields.is_empty()


## Applies damage in half-hearts. Shields go first (last-gained first), then hearts.
## Returns the number of Toxic Chitin halves that broke (each triggers a damage burst).
func take_damage(halves: int) -> int:
	var toxic_broken := 0
	for i in halves:
		if not shields.is_empty():
			if shields.pop_back() == "toxic":
				toxic_broken += 1
		elif hearts > 0:
			hearts -= 1
	stats["damage_taken"] = int(stats.get("damage_taken", 0)) + halves
	return toxic_broken


## Returns how many half-hearts were actually healed.
func heal(halves: int) -> int:
	var before := hearts
	hearts = mini(hearts + halves, hearts_max)
	return hearts - before


func can_heal() -> bool:
	return hearts < hearts_max


func add_containers(count: int) -> void:
	for i in count:
		if total_hearts_half() + 2 > MAX_TOTAL_HEARTS * 2:
			# Isaac rule: at the cap, a container replaces a shield heart if one exists.
			if shields.size() >= 2:
				shields.pop_back()
				shields.pop_back()
			else:
				return
		hearts_max += 2


## kind: "chitin" | "toxic". Returns halves actually added.
func add_shield(kind: String, halves: int) -> int:
	var added := 0
	for i in halves:
		if total_hearts_half() >= MAX_TOTAL_HEARTS * 2:
			break
		shields.append(kind)
		added += 1
	return added


func can_add_shield() -> bool:
	return total_hearts_half() < MAX_TOTAL_HEARTS * 2


# ---------------------------------------------------------------- consumables

func add_mana(n: int) -> void:
	mana = clampi(mana + n, 0, MAX_CONSUMABLE)
	Events.consumables_changed.emit()


func add_dig_charges(n: int) -> void:
	dig_charges = clampi(dig_charges + n, 0, MAX_CONSUMABLE)
	Events.consumables_changed.emit()


func add_royal_jelly(n: int) -> void:
	royal_jelly = clampi(royal_jelly + n, 0, MAX_CONSUMABLE)
	Events.consumables_changed.emit()


# ---------------------------------------------------------------- floor stash

func add_to_stash(resource_type: String, amount: int) -> void:
	floor_stash[resource_type] = int(floor_stash.get(resource_type, 0)) + amount
	Events.stash_changed.emit(stash_total())


func stash_total() -> int:
	var t := 0
	for k in floor_stash:
		t += int(floor_stash[k])
	return t


## Pulp value of the stash: each material goes through the Pulper at its pulp_value.
func stash_pulp_value() -> int:
	var p := 0
	for k in floor_stash:
		var res: Dictionary = Content.get_entry("resources", k)
		p += int(floor_stash[k]) * int(res.get("pulp_value", 1))
	return p


## Banks the stash into the hive (called when the boss-shaft haul completes).
func bank_stash() -> int:
	var pulp := stash_pulp_value()
	if pulp > 0:
		MetaSave.bank_pulp(pulp, floor_stash.duplicate())
	stats["pulp_banked"] = int(stats.get("pulp_banked", 0)) + pulp
	floor_stash = {}
	Events.stash_changed.emit(0)
	return pulp


## Called on death: the unbanked stash is lost.
func lose_stash() -> int:
	var lost := stash_pulp_value()
	stats["stash_lost"] = int(stats.get("stash_lost", 0)) + lost
	floor_stash = {}
	return lost


# ---------------------------------------------------------------- misc

func seed_string() -> String:
	return RNG.seed_to_string(seed_value)


func bump(stat_key: String, n: int = 1) -> void:
	stats[stat_key] = int(stats.get(stat_key, 0)) + n


func to_dict() -> Dictionary:
	return {
		"seed": seed_value, "caste": caste, "floor_index": floor_index, "elapsed": elapsed,
		"health": {"hearts_max": hearts_max, "hearts": hearts, "shields": shields.duplicate()},
		"consumables": {"mana": mana, "dig_charges": dig_charges, "royal_jelly": royal_jelly},
		"items": items.duplicate(), "active_item": active_item, "active_charge": active_charge,
		"flags": flags.duplicate(true), "floor_stash": floor_stash.duplicate(), "stats": stats.duplicate(),
		"trinket": trinket, "consumable": consumable.duplicate(), "fluid_map": fluid_map.duplicate(),
		"fluids_identified": fluids_identified.duplicate(), "perma_mods": perma_mods.duplicate(true),
		"radiation": radiation, "radiation_threshold": radiation_threshold, "mutations": mutations.duplicate(),
		"floor_strata": floor_strata.duplicate(), "bosses_met": bosses_met.duplicate(),
	}


## Restores run data. Persistent item effects (stat/shot mods, familiars) are re-derived by
## EffectHost.rebuild() from `items`, so they are not serialized.
func from_dict(d: Dictionary) -> void:
	reset()
	active = true
	seed_value = int(d.get("seed", 0))
	caste = str(d.get("caste", "worker"))
	floor_index = int(d.get("floor_index", 0))
	elapsed = float(d.get("elapsed", 0.0))
	var h: Dictionary = d.get("health", {})
	hearts_max = int(h.get("hearts_max", 6))
	hearts = int(h.get("hearts", hearts_max))
	shields.assign(h.get("shields", []))
	var c: Dictionary = d.get("consumables", {})
	mana = int(c.get("mana", 0))
	dig_charges = int(c.get("dig_charges", 1))
	royal_jelly = int(c.get("royal_jelly", 0))
	items.assign(d.get("items", []))
	active_item = str(d.get("active_item", ""))
	active_charge = int(d.get("active_charge", 0))
	flags = d.get("flags", {}).duplicate(true)
	floor_stash = d.get("floor_stash", {}).duplicate()
	stats.merge(d.get("stats", {}), true)
	trinket = str(d.get("trinket", ""))
	consumable = d.get("consumable", {}).duplicate()
	fluid_map = d.get("fluid_map", {}).duplicate()
	fluids_identified = d.get("fluids_identified", {}).duplicate()
	perma_mods.assign(d.get("perma_mods", []))
	radiation = float(d.get("radiation", 0.0))
	radiation_threshold = int(d.get("radiation_threshold", radiation_threshold))
	mutations.assign(d.get("mutations", []))
	floor_strata = d.get("floor_strata", {}).duplicate()
	bosses_met = d.get("bosses_met", []).duplicate()
	# Run snapshots are taken at floor start; streams derive from (seed, floor), so re-seeding
	# reproduces the floor exactly.
	RNG.set_run_seed(seed_value)
	RNG.set_floor(floor_index)
