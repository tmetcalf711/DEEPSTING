class_name Room
extends Node2D
## One room of the floor, built from a hand-authored template (DESIGN.md §10.4).
## Rooms are 1x1, 2x1, 1x2 or 2x2 cells; one cell is 13x7 tiles of 16 px. Room-local coordinates:
## the interior spans (0,0)-(room_w, room_h) and walls sit outside it.
##
## Doors are addressed by wall slot keys "ox,oy,D" (see FloorGen). Door kinds come from the
## layout: normal, secret (cracked wall), locked (Royal Jelly), spiked (curse room), challenge
## (full health only), deal (Royal Chamber / Mutation Den).
##
## Persistent state (cleared, destroyed rocks, leftover pickups, opened walls/locks, special-room
## state) lives in the layout's room `info` dictionary, so it survives leaving the room.
## Special rooms add behavior through res://scripts/run/specials/<type>.gd (a "feature" node).

signal cleared_room()

const TILE := 16
const CELL_COLS := 13
const CELL_ROWS := 7
const CELL_W := CELL_COLS * TILE  # 208
const CELL_H := CELL_ROWS * TILE  # 112
## 1x1 room size; kept for code that only deals with single-cell rooms (camera defaults, tools).
const W := CELL_W
const H := CELL_H
const WALL := 16
const TOP_WALL := 22     # top wall is taller to fake depth (2.5D)
const DOOR_W := 24
const DIRS: Dictionary = {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const SPECIALS_DIR := "res://scripts/run/specials/"

const LAYER_WALLS := 1
const LAYER_OBSTACLES := 2
const LAYER_PITS := 4

const RockScript := preload("res://scripts/actors/rock.gd")
const EnemyScript := preload("res://scripts/enemies/enemy.gd")
const PickupScript := preload("res://scripts/actors/pickup.gd")
const PedestalScript := preload("res://scripts/actors/pedestal.gd")
const DepositScript := preload("res://scripts/actors/deposit.gd")
const WorkerScript := preload("res://scripts/actors/worker.gd")
const BroodCellScript := preload("res://scripts/actors/brood_cell.gd")
const TrapdoorScript := preload("res://scripts/actors/trapdoor.gd")
const LootPileScript := preload("res://scripts/actors/loot_pile.gd")

var anchor: Vector2i
var info: Dictionary
var template: Dictionary
var neighbor_types: Dictionary = {}   # slot -> neighbor room type
var palette: Dictionary = {}
var shape_cells := Vector2i.ONE       # room size in cells
var cols := CELL_COLS
var rows := CELL_ROWS
var room_w := float(CELL_W)
var room_h := float(CELL_H)
var grid: Array = []                  # Array[Array[String]] of tile chars
var entities: Node2D
var feature: Node = null              # special-room behavior, if any
var rng_enemies: RandomNumberGenerator
var rng_drops: RandomNumberGenerator

var enemies_alive: int = 0
var had_enemies: bool = false
var is_cleared: bool = false
var shaft_x: float = CELL_W / 2.0 - 64.0  # boss shaft column (left of the top door / deal door)
var creeps: Array = []                # [{pos, r, life, kind}] floor hazards (sludge...)

var _wall_body: StaticBody2D
var _obstacles: Dictionary = {}       # Vector2i -> Node2D
var _haul_workers: int = 0
var _haul_deposits: Array = []
var _haul_done: bool = true
var _dust_t: float = 0.0
var _shaft_open: float = 0.0          # 0..1 light shaft animation (boss rooms)
var _shaft_active: bool = false
var _boss_shaft_done: bool = false
var _enter_grace: float = 0.0
var _door_sig := ""
var _door_check_t := 0.0


func setup(p_anchor: Vector2i, p_info: Dictionary, p_template: Dictionary, p_neighbors: Dictionary, p_palette: Dictionary) -> void:
	anchor = p_anchor
	info = p_info
	template = p_template
	neighbor_types = p_neighbors
	palette = p_palette
	shape_cells = FloorGen.shape_size(str(info.get("shape", "1x1")))
	cols = CELL_COLS * shape_cells.x
	rows = CELL_ROWS * shape_cells.y
	room_w = cols * TILE
	room_h = rows * TILE
	rng_enemies = RNG.room_stream("enemies", int(info["index"]))
	rng_drops = RNG.room_stream("drops", int(info["index"]))


func _ready() -> void:
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	_build_grid()
	_build_obstacles()
	is_cleared = bool(info.get("cleared", false))
	_boss_shaft_done = bool(info.get("shaft_done", false))
	_rebuild_walls()
	_restore_pickups()
	_spawn_pedestals()
	_spawn_brood_cells()
	var fpath := SPECIALS_DIR + str(info["type"]) + ".gd"
	if ResourceLoader.exists(fpath):
		feature = load(fpath).new()
		feature.name = "Feature"
		add_child(feature)
		feature.setup(self)
	if not is_cleared:
		_spawn_enemies()
	if enemies_alive == 0 and not is_cleared:
		_mark_cleared(false)
	if info["type"] == "boss" and is_cleared:
		_spawn_trapdoor()
		_shaft_open = 1.0
	if info["type"] in FloorGen.SECRET_TYPES and not info.get("visited", false):
		RunState.bump("secrets_found")
		MetaSave.add_counter("secret_rooms_found")
		Events.toast.emit(tr("TOAST_SECRET_FOUND"))
	info["visited"] = true
	_enter_grace = 0.5
	_door_sig = _door_signature()
	queue_redraw()


# ---------------------------------------------------------------- grid

func _build_grid() -> void:
	grid.clear()
	var brood_active: bool = info.get("brood_cell", false) or info["type"] == "brood_cell"
	for row in template["grid"]:
		var r: Array = []
		for ch in str(row):
			if ch == "B" and not brood_active:
				ch = "."
			r.append(ch)
		grid.append(r)
	for t in info.get("destroyed", []):
		grid[int(t[1])][int(t[0])] = "."
	for t in info.get("brood_broken", []):
		grid[int(t[1])][int(t[0])] = "."


func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE + TILE / 2.0, t.y * TILE + TILE / 2.0)


func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func tile_at(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= cols or t.y >= rows:
		return "#"
	return grid[t.y][t.x]


func is_walkable_tile(t: Vector2i) -> bool:
	return tile_at(t) in [".", "S", "D", "P"]


func is_bullet_blocked(p: Vector2, spectral: bool) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= room_w or p.y >= room_h:
		return true
	if spectral:
		return false
	return tile_at(world_to_tile(p)) in ["R", "T", "#"]


func center() -> Vector2:
	return Vector2(room_w / 2.0, room_h / 2.0)


func free_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			if tile_at(Vector2i(x, y)) == ".":
				out.append(Vector2i(x, y))
	return out


## Nearest walkable tile center to a point (used to place drops so they never land in rocks).
func nearest_free_point(p: Vector2) -> Vector2:
	var best := center()
	var best_d := INF
	for t in free_tiles():
		var c := tile_center(t)
		var d := c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


func _build_obstacles() -> void:
	var pit_body := StaticBody2D.new()
	pit_body.collision_layer = LAYER_PITS
	pit_body.collision_mask = 0
	add_child(pit_body)
	for y in rows:
		for x in cols:
			var t := Vector2i(x, y)
			match tile_at(t):
				"R", "T", "#":
					var rock: Node2D = RockScript.new()
					rock.setup(self, t, tile_at(t))
					entities.add_child(rock)
					_obstacles[t] = rock
				"X":
					var cs := CollisionShape2D.new()
					var rs := RectangleShape2D.new()
					rs.size = Vector2(TILE, TILE)
					cs.shape = rs
					cs.position = tile_center(t)
					pit_body.add_child(cs)


func destroy_tile(t: Vector2i) -> void:
	var ch := tile_at(t)
	if not ch in ["R", "T"]:
		return
	grid[t.y][t.x] = "."
	var d: Array = info.get("destroyed", [])
	d.append([t.x, t.y])
	info["destroyed"] = d
	if _obstacles.has(t):
		_obstacles[t].shatter()
		_obstacles.erase(t)
	var c := tile_center(t)
	if ch == "T":
		drop_from_table("tinted_rock", c)
	elif RunState.flags.get("rock_mana_bonus", false):
		drop_from_table("rock_bonus", c)
	MetaSave.add_counter("rocks_broken")


# ---------------------------------------------------------------- doors

func door_kind(slot: String) -> String:
	return str(info["doors"].get(slot, ""))


## "none" | "closed" | "open" | "cracked" (unopened secret wall) | "locked" (needs Royal Jelly)
## | "barred" (challenge door while not at full health)
func door_state(slot: String) -> String:
	if not info["doors"].has(slot):
		return "none"
	match door_kind(slot):
		"secret":
			return "open" if info.get("opened_secret", {}).has(slot) else "cracked"
		"locked":
			if not info.get("unlocked", {}).has(slot):
				return "locked"
		"challenge":
			if info["type"] != "challenge" and not _challenge_door_allowed(slot):
				return "barred"
	return "open" if is_cleared else "closed"


func _challenge_door_allowed(slot: String) -> bool:
	var link: Array = info["links"].get(slot, [])
	if link.is_empty():
		return true
	var other: Dictionary = RunController.instance.layout["rooms"].get(link[0], {})
	return other.get("cleared", false) or RunState.hearts >= RunState.hearts_max


func door_pos(slot: String) -> Vector2:
	var ps := FloorGen.parse_slot(slot)
	var off: Vector2i = ps[0]
	match str(ps[1]):
		"N": return Vector2(off.x * CELL_W + CELL_W / 2.0, 0)
		"S": return Vector2(off.x * CELL_W + CELL_W / 2.0, room_h)
		"W": return Vector2(0, off.y * CELL_H + CELL_H / 2.0)
		_: return Vector2(room_w, off.y * CELL_H + CELL_H / 2.0)


func slot_dir(slot: String) -> String:
	return str(FloorGen.parse_slot(slot)[1])


## Just outside the door, where workers appear from.
func door_outside(slot: String) -> Vector2:
	return door_pos(slot) + Vector2(DIRS[slot_dir(slot)]) * 20.0


func entry_point(slot: String) -> Vector2:
	return door_pos(slot) - Vector2(DIRS[slot_dir(slot)]) * 16.0


## The wall slot a point outside the interior is passing through ("" if none).
func slot_at(p: Vector2) -> String:
	var dir := ""
	if p.y < -6.0:
		dir = "N"
	elif p.y > room_h + 6.0:
		dir = "S"
	elif p.x < -6.0:
		dir = "W"
	elif p.x > room_w + 6.0:
		dir = "E"
	if dir == "":
		return ""
	var ox := clampi(floori(p.x / CELL_W), 0, shape_cells.x - 1)
	var oy := clampi(floori(p.y / CELL_H), 0, shape_cells.y - 1)
	match dir:
		"N": oy = 0
		"S": oy = shape_cells.y - 1
		"W": ox = 0
		"E": ox = shape_cells.x - 1
	return FloorGen.slot_key(Vector2i(ox, oy), dir)


func all_slots() -> Array:
	return FloorGen.shape_slots(str(info.get("shape", "1x1")))


func _door_signature() -> String:
	var parts: PackedStringArray = []
	for s in all_slots():
		parts.append(door_state(s))
	return ",".join(parts)


func _rebuild_walls() -> void:
	if _wall_body:
		_wall_body.queue_free()
	_wall_body = StaticBody2D.new()
	_wall_body.collision_layer = LAYER_WALLS
	_wall_body.collision_mask = 0
	add_child(_wall_body)
	var t := 40.0  # collision thickness (deeper than the visual wall so nothing tunnels)
	var gaps := {"N": [], "S": [], "W": [], "E": []}
	for s in all_slots():
		if door_state(s) == "open":
			var p := door_pos(s)
			var d := slot_dir(s)
			gaps[d].append(p.x if d in ["N", "S"] else p.y)
	_side_rects(gaps["N"], -t, room_w + t, func(a: float, b: float) -> Rect2: return Rect2(a, -t, b - a, t))
	_side_rects(gaps["S"], -t, room_w + t, func(a: float, b: float) -> Rect2: return Rect2(a, room_h, b - a, t))
	_side_rects(gaps["W"], -t, room_h + t, func(a: float, b: float) -> Rect2: return Rect2(-t, a, t, b - a))
	_side_rects(gaps["E"], -t, room_h + t, func(a: float, b: float) -> Rect2: return Rect2(room_w, a, t, b - a))
	_door_sig = _door_signature()
	queue_redraw()


## Splits one wall side into solid segments around the open door gaps.
func _side_rects(gap_centers: Array, from: float, to: float, mk: Callable) -> void:
	gap_centers.sort()
	var cur := from
	for g in gap_centers:
		var a: float = float(g) - DOOR_W / 2.0
		if a > cur:
			_add_rect(mk.call(cur, a))
		cur = float(g) + DOOR_W / 2.0
	if to > cur:
		_add_rect(mk.call(cur, to))


func _add_rect(r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = r.size
	cs.shape = rs
	cs.position = r.position + r.size / 2.0
	_wall_body.add_child(cs)


func refresh_doors() -> void:
	call_deferred("_rebuild_walls")


func open_secret(slot: String) -> void:
	var o: Dictionary = info.get("opened_secret", {})
	if o.has(slot):
		return
	o[slot] = true
	info["opened_secret"] = o
	RunController.instance.mirror_door_flag(info, slot, "opened_secret")
	Audio.play_sfx("wall_crumble")
	RunController.instance.fx.burst(door_pos(slot), Color(0.6, 0.5, 0.4), 18, 80.0, 2.0)
	refresh_doors()


func _try_unlock_doors() -> void:
	var p: Node2D = RunController.instance.player
	if p == null:
		return
	for s in info["doors"]:
		if door_state(s) != "locked":
			continue
		if p.global_position.distance_to(door_pos(s)) > 18.0:
			continue
		var cost: int = int(info.get("lock_cost", {}).get(s, 1))
		if RunState.royal_jelly < cost:
			continue
		RunState.add_royal_jelly(-cost)
		var u: Dictionary = info.get("unlocked", {})
		u[s] = true
		info["unlocked"] = u
		RunController.instance.mirror_door_flag(info, s, "unlocked")
		Audio.play_sfx("door_unlock")
		RunController.instance.fx.burst(door_pos(s), Color(1.0, 0.95, 0.6), 14, 60.0, 1.5)
		refresh_doors()


# ---------------------------------------------------------------- spawning

func _spawn_enemies() -> void:
	for sp in template.get("spawns", []):
		var id: String = sp["enemy"]
		var is_boss := false
		if id == "@boss":
			id = str(info.get("boss_id", ""))
			is_boss = true
		var data: Dictionary = Content.get_entry("bosses" if is_boss else "enemies", id)
		if data.is_empty():
			push_warning("Room: unknown enemy '%s'" % id)
			continue
		var at: Array = sp["at"]
		spawn_enemy(data, tile_center(Vector2i(int(at[0]), int(at[1]))), is_boss)


func spawn_enemy(data: Dictionary, pos: Vector2, is_boss: bool = false) -> Node2D:
	var e: CharacterBody2D = EnemyScript.new()
	e.setup(data, self, is_boss)
	e.position = pos
	entities.add_child(e)
	enemies_alive += 1
	had_enemies = true
	if is_cleared:
		# Something spawned in a cleared room (arcade, console): close up again until it's dead.
		is_cleared = false
		info["cleared"] = false
		refresh_doors()
	return e


## Undo a reservation made by a splitting enemy once its children have been spawned.
func _release_reserved(n: int) -> void:
	enemies_alive -= n
	if enemies_alive <= 0 and not is_cleared:
		_mark_cleared(true)


func on_enemy_died(e: Node) -> void:
	enemies_alive -= 1
	if e.get("is_boss") and bool(e.data.get("behavior", {}).get("kill_minions_on_death", true)):
		# Minions die with their mother (Isaac convention).
		for other in get_tree().get_nodes_in_group("enemies"):
			if other != e and is_instance_valid(other) and other.get_parent() == entities:
				other.die(false)
	elif not e.get("is_boss"):
		if rng_drops.randf() < float(_drops("enemy_kill").get("chance", 0.0)):
			drop_from_table("enemy_kill", e.global_position)
	if enemies_alive <= 0 and not is_cleared:
		if feature and feature.has_method("on_enemies_cleared") and feature.on_enemies_cleared():
			return  # the feature spawned more (challenge waves)
		_mark_cleared(true)


## Pedestals: the template's "P" tile holds info.pedestal; specials may add extra pedestals
## (info.extra_pedestals: [{id, x, y, group}]). Taking one from a group empties the rest.
func _spawn_pedestals() -> void:
	if info.has("pedestal"):
		var at := center()
		for y in rows:
			for x in cols:
				if tile_at(Vector2i(x, y)) == "P":
					at = tile_center(Vector2i(x, y))
		if info["type"] == "boss":
			at = center() + Vector2(0, 4)
		_add_pedestal(str(info["pedestal"]), at, -1)
	var extra: Array = info.get("extra_pedestals", [])
	for i in extra.size():
		var e: Dictionary = extra[i]
		_add_pedestal(str(e["id"]), Vector2(float(e["x"]), float(e["y"])), i)


func _add_pedestal(id: String, at: Vector2, extra_index: int) -> Node2D:
	var p: Node2D = PedestalScript.new()
	p.setup(self, id, extra_index)
	p.position = at
	entities.add_child(p)
	return p


func add_extra_pedestal(id: String, at: Vector2, group: String = "") -> Node2D:
	var extra: Array = info.get("extra_pedestals", [])
	extra.append({"id": id, "x": at.x, "y": at.y, "group": group})
	info["extra_pedestals"] = extra
	return _add_pedestal(id, at, extra.size() - 1)


## Called by a pedestal when its item changes (taken or swapped).
func on_pedestal_changed(extra_index: int, new_id: String) -> void:
	if extra_index < 0:
		info["pedestal"] = new_id
		return
	var extra: Array = info["extra_pedestals"]
	extra[extra_index]["id"] = new_id
	var group: String = extra[extra_index].get("group", "")
	if group == "":
		return
	# Choice group (Royal Chamber): taking one makes the others vanish.
	for i in extra.size():
		if i != extra_index and extra[i].get("group", "") == group:
			extra[i]["id"] = ""
	for n in entities.get_children():
		if n.has_method("set_item") and n.get("extra_index") != extra_index and n.get("extra_index") >= 0:
			if extra[int(n.get("extra_index"))].get("group", "") == group:
				n.set_item("")


func _spawn_brood_cells() -> void:
	for y in rows:
		for x in cols:
			var t := Vector2i(x, y)
			if tile_at(t) == "B":
				var b: StaticBody2D = BroodCellScript.new()
				b.setup(self, t)
				b.position = tile_center(t)
				entities.add_child(b)
				_obstacles[t] = b


func on_brood_cell_broken(t: Vector2i, larvae: int) -> void:
	grid[t.y][t.x] = "."
	_obstacles.erase(t)
	var bb: Array = info.get("brood_broken", [])
	bb.append([t.x, t.y])
	info["brood_broken"] = bb
	# Banked immediately: not lost on death (DESIGN.md §11, D14).
	MetaSave.rescue_lost_brood(larvae)
	RunState.bump("brood_rescued", larvae)
	Events.brood_rescued.emit("lost_brood", false)
	Events.toast.emit(tr("TOAST_BROOD_RESCUED") % larvae)
	var home := home_slot()
	for i in larvae:
		var w: Node2D = WorkerScript.new()
		var lpos := tile_center(t) + Vector2(rng_drops.randf_range(-6, 6), rng_drops.randf_range(-4, 4))
		w.setup_escort(self, door_outside(home), lpos, i * 0.25)
		entities.add_child(w)


func _restore_pickups() -> void:
	for p in info.get("pickups", []):
		spawn_pickup(str(p["id"]), Vector2(float(p["x"]), float(p["y"])), Vector2.ZERO)
	info["pickups"] = []


func spawn_pickup(id: String, pos: Vector2, vel: Vector2 = Vector2.ZERO) -> void:
	var data: Dictionary = Content.get_entry("pickups", id)
	if data.is_empty():
		return
	var p: Node2D = PickupScript.new()
	p.setup(self, data)
	p.position = pos
	p.velocity = vel
	entities.add_child(p)


func _drops(table: String) -> Dictionary:
	return Content.get_entry("config", "drops").get(table, {})


func drop_from_table(table: String, pos: Vector2, force: bool = false, r: RandomNumberGenerator = null) -> void:
	var rng := r if r else rng_drops
	var t := _drops(table)
	if t.is_empty():
		return
	if not force and rng.randf() >= float(t.get("chance", 1.0)):
		return
	var entries: Array = t["table"]
	var idx := RNG.weighted_index(rng, entries.map(func(e: Dictionary) -> float: return float(e["weight"])))
	var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 50)
	spawn_pickup(entries[idx]["id"], pos, v)


# ---------------------------------------------------------------- hazards

func add_creep(pos: Vector2, kind: String, life: float, radius: float = 7.0) -> void:
	if creeps.size() > 80:
		creeps.pop_front()
	creeps.append({"pos": pos, "r": radius, "life": life, "max": life, "kind": kind})


## The creep kind under a point ("" if none). Player hover ignores ground creep except sludge.
func hazard_at(p: Vector2) -> String:
	for c in creeps:
		if p.distance_squared_to(c["pos"]) <= float(c["r"]) * float(c["r"]):
			return str(c["kind"])
	return ""


# ---------------------------------------------------------------- clearing / hauling

func _mark_cleared(from_combat: bool) -> void:
	is_cleared = true
	info["cleared"] = true
	refresh_doors()
	for n in get_tree().get_nodes_in_group("brood_cells"):
		if n.get_parent() == entities:
			n.unlock()
	if not from_combat:
		if info["type"] in FloorGen.SECRET_TYPES and not info.get("loot_spawned", false):
			info["loot_spawned"] = true
			var sr := _drops("secret_room")
			var cnt: Array = sr.get("count", [3, 5])
			for i in rng_drops.randi_range(int(cnt[0]), int(cnt[1])):
				drop_from_table("secret_room", center() + Vector2(0, 18), true)
		return
	Audio.play_sfx("doors_open")
	RunState.bump("rooms_cleared")
	MetaSave.add_counter("rooms_cleared")
	RunController.instance.on_room_cleared(self)
	if feature and feature.has_method("on_cleared"):
		feature.on_cleared()
	if info["type"] == "boss":
		_start_boss_shaft()
	elif info["type"] in ["normal", "brood_cell"]:
		_spawn_deposits_and_haul()
		drop_from_table("room_clear", nearest_free_point(center()))
	cleared_room.emit()


func home_slot() -> String:
	var hs: String = info.get("home_slot", "")
	if hs == "" or not info["doors"].has(hs):
		var keys: Array = info["doors"].keys()
		keys.sort()
		for s in keys:
			if info["doors"][s] != "secret":
				return s
		return "0,0,S"
	return hs


func _spawn_deposits_and_haul() -> void:
	var dep := _drops("deposits")
	var cnt: Array = dep.get("count", [1, 3])
	var val: Array = dep.get("value", [2, 5])
	var n: int = rng_drops.randi_range(int(cnt[0]), int(cnt[1])) * (shape_cells.x * shape_cells.y + 1) / 2
	var slots: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			if tile_at(Vector2i(x, y)) == "D":
				slots.append(Vector2i(x, y))
	var free := free_tiles()
	RNG.shuffle(rng_drops, free)
	slots.append_array(free)
	var res_table: Array = RunController.instance.stratum.get("resources", [{"id": "wood_pulp", "weight": 1}])
	var weights: Array = res_table.map(func(e: Dictionary) -> float: return float(e["weight"]))
	_haul_deposits.clear()
	for i in mini(n, slots.size()):
		var d: Node2D = DepositScript.new()
		var res_id: String = res_table[RNG.weighted_index(rng_drops, weights)]["id"]
		d.setup(res_id, rng_drops.randi_range(int(val[0]), int(val[1])))
		d.position = tile_center(slots[i]) + Vector2(rng_drops.randf_range(-3, 3), rng_drops.randf_range(-3, 3))
		entities.add_child(d)
		_haul_deposits.append(d)
	if _haul_deposits.is_empty():
		return
	_haul_done = false
	var total := 0
	for d in _haul_deposits:
		total += int(d.value)
	Events.haul_started.emit(int(info["index"]), total)
	var from := door_outside(home_slot())
	var delay := 0.4
	for d in _haul_deposits:
		var workers: int = clampi(ceili(float(d.value) / 2.0), 1, 3)
		d.workers_needed = workers
		for k in workers:
			var w: Node2D = WorkerScript.new()
			w.setup_haul(self, from, d, delay)
			w.finished.connect(_on_haul_worker_done)
			entities.add_child(w)
			_haul_workers += 1
			delay += 0.12


func _on_haul_worker_done() -> void:
	_haul_workers -= 1
	if _haul_workers <= 0:
		_finalize_haul()


## Credits every hauled deposit to the floor stash. Called when the last worker leaves, or early
## if the player leaves the room mid-haul (the swarm finishes off-screen).
func _finalize_haul() -> void:
	if _haul_done:
		return
	_haul_done = true
	var total := 0
	for d in _haul_deposits:
		if is_instance_valid(d):
			RunState.add_to_stash(d.resource_id, int(d.value))
			total += int(d.value)
			d.queue_free()
	_haul_deposits.clear()
	if total > 0:
		Events.haul_completed.emit(int(info["index"]), total)
		Events.toast.emit(tr("TOAST_HAULED") % total)


func _start_boss_shaft() -> void:
	# Boss down: a shaft opens to the surface and the swarm carries the floor stash up.
	_shaft_active = true
	RunState.add_to_stash("protein", 6)  # the boss carcass is hauled too
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(self, "_shaft_open", 1.0, 0.7)
	tw.tween_callback(_begin_shaft_haul)
	Events.toast.emit(tr("TOAST_SHAFT_OPEN"))


func _begin_shaft_haul() -> void:
	var total := RunState.stash_total()
	var pile: Node2D = LootPileScript.new()
	pile.setup(RunState.floor_stash.duplicate())
	pile.position = Vector2(shaft_x, 30)
	entities.add_child(pile)
	var n: int = clampi(3 + total / 4, 3, 18)
	pile.workers_needed = n
	_haul_workers = 0
	var top := Vector2(shaft_x, -TOP_WALL - 30)
	for i in n:
		var w: Node2D = WorkerScript.new()
		w.setup_haul(self, top + Vector2((i % 5 - 2) * 4, 0), pile, 0.15 * i)
		w.finished.connect(_on_shaft_worker_done.bind(pile))
		entities.add_child(w)
		_haul_workers += 1


func _on_shaft_worker_done(pile: Node2D) -> void:
	_haul_workers -= 1
	if _haul_workers > 0:
		return
	if is_instance_valid(pile):
		pile.queue_free()
	_complete_boss_shaft()


func _complete_boss_shaft() -> void:
	if _boss_shaft_done:
		return
	_boss_shaft_done = true
	info["shaft_done"] = true
	var pulp := RunState.bank_stash()
	Events.banner.emit(tr("BANNER_BANKED") % pulp, tr("BANNER_BANKED_SUB"))
	_spawn_trapdoor()


func _spawn_trapdoor() -> void:
	var t: Node2D = TrapdoorScript.new()
	t.position = Vector2(room_w / 2.0, room_h - 26)
	entities.add_child(t)


## Called by the controller before the room is freed.
func on_exit() -> void:
	_finalize_haul()
	if _shaft_active and not _boss_shaft_done:
		_complete_boss_shaft()
	var left: Array = []
	for n in get_tree().get_nodes_in_group("pickups"):
		if n.get_parent() == entities and not n.collected:
			left.append({"id": n.data["id"], "x": n.position.x, "y": n.position.y})
	info["pickups"] = left


# ---------------------------------------------------------------- explosions (Dig Charges)

func explode(pos: Vector2, radius: float, damage: float) -> void:
	var rc := RunController.instance
	rc.fx.explosion(pos, radius)
	rc.shake(0.55)
	Audio.play_sfx("dig_charge_boom")
	for t in get_tree().get_nodes_in_group("shootable"):
		if is_instance_valid(t) and is_ancestor_of(t) and t.global_position.distance_to(pos) <= radius + float(t.get("hit_radius")):
			t.take_hit(damage, (t.global_position - pos).normalized(), ["blast"])
	if rc.player and rc.player.global_position.distance_to(pos) <= radius:
		rc.player.hurt(2, "dig_charge")
	for y in rows:
		for x in cols:
			var t := Vector2i(x, y)
			if tile_center(t).distance_to(pos) <= radius + 4.0:
				destroy_tile(t)
	for s in all_slots():
		if door_state(s) == "cracked" and door_pos(s).distance_to(pos) <= radius + 12.0:
			open_secret(s)


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_enter_grace = maxf(0.0, _enter_grace - delta)
	# Secret walls leak a faint dust trickle every few seconds (the readable tell, §4).
	_dust_t -= delta
	if _dust_t <= 0.0:
		var see: bool = RunState.flags.get("see_secrets", false)
		_dust_t = rng_drops.randf_range(2.5, 4.5) * (0.4 if see else 1.0)
		for s in all_slots():
			if door_state(s) == "cracked":
				RunController.instance.fx.dust(door_pos(s) - Vector2(DIRS[slot_dir(s)]) * 2.0)
	if _shaft_active and _shaft_open > 0.0:
		queue_redraw()
	if not creeps.is_empty():
		var i := 0
		while i < creeps.size():
			creeps[i]["life"] = float(creeps[i]["life"]) - delta
			if float(creeps[i]["life"]) <= 0.0:
				creeps.remove_at(i)
			else:
				i += 1
		queue_redraw()
	# Door states can change without a clear (challenge door at full health, locks): re-check.
	_door_check_t -= delta
	if _door_check_t <= 0.0:
		_door_check_t = 0.2
		_try_unlock_doors()
		if _door_signature() != _door_sig:
			refresh_doors()


## Live enemies belonging to this room (a room being freed this frame may still be in the tree).
func room_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return is_ancestor_of(e) and not e.dead)


func enemies_awake() -> bool:
	return _enter_grace <= 0.0


# ---------------------------------------------------------------- drawing (placeholder art)

func _col(key: String, fallback: Color) -> Color:
	return Color.from_string(str(palette.get(key, "")), fallback)


func _draw() -> void:
	var floor_c := _col("floor", Color(0.23, 0.17, 0.12))
	var floor_alt := _col("floor_alt", floor_c.darkened(0.08))
	var wall_c := _col("wall", Color(0.42, 0.32, 0.21))
	var wall_top := _col("wall_top", wall_c.lightened(0.2))
	# Walls: top wall has a lit top face and a darker front face for depth.
	draw_rect(Rect2(-WALL, -TOP_WALL, room_w + WALL * 2, room_h + TOP_WALL + WALL), wall_c.darkened(0.35))
	draw_rect(Rect2(-WALL, -TOP_WALL, room_w + WALL * 2, TOP_WALL - 8), wall_top)
	draw_rect(Rect2(0, -8, room_w, 8), wall_c)  # front face of the top wall
	draw_rect(Rect2(-WALL, 0, WALL, room_h), wall_c.darkened(0.15))
	draw_rect(Rect2(room_w, 0, WALL, room_h), wall_c.darkened(0.15))
	draw_rect(Rect2(-WALL, room_h, room_w + WALL * 2, WALL), wall_c.darkened(0.05))
	# Floor: checker + paper-comb hex hints (deterministic per room).
	for y in rows:
		for x in cols:
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			draw_rect(r, floor_c if (x + y) % 2 == 0 else floor_alt)
			var hsh := absi((anchor.x * 73856093) ^ (anchor.y * 19349663) ^ (x * 83492791) ^ (y * 2654435761)) % 9
			if hsh == 0:
				_hex(tile_center(Vector2i(x, y)), 5.0, floor_c.lightened(0.08))
			match tile_at(Vector2i(x, y)):
				"X":
					draw_rect(r.grow(-1), Color(0.03, 0.02, 0.02))
					draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(TILE - 2, 3)), Color(0.12, 0.08, 0.06))
				"S":
					for k in 3:
						var sx := r.position.x + 3 + k * 5
						draw_colored_polygon(PackedVector2Array([Vector2(sx, r.end.y - 3), Vector2(sx + 2, r.position.y + 5), Vector2(sx + 4, r.end.y - 3)]), Color(0.65, 0.6, 0.55))
	# Creep (sludge) puddles
	for c in creeps:
		var a: float = clampf(float(c["life"]) / 1.0, 0.0, 1.0)
		draw_circle(c["pos"], float(c["r"]), Color(0.32, 0.36, 0.12, 0.55 * a))
		draw_circle(c["pos"] + Vector2(-1.5, -1.5), float(c["r"]) * 0.4, Color(0.55, 0.6, 0.25, 0.4 * a))
	for s in all_slots():
		_draw_door(s)
	# Boss shaft: light column from the surface.
	if _shaft_open > 0.0:
		var sw := 26.0 * _shaft_open
		var c := Color(1.0, 0.95, 0.7, 0.25 * _shaft_open)
		draw_rect(Rect2(shaft_x - sw / 2.0, -TOP_WALL, sw, 48 + TOP_WALL), c)
		draw_rect(Rect2(shaft_x - sw / 4.0, -TOP_WALL, sw / 2.0, 52 + TOP_WALL), Color(1, 1, 0.85, 0.25 * _shaft_open))
		draw_rect(Rect2(shaft_x - 12, -TOP_WALL, 24, 6), Color(0.05, 0.04, 0.03))


func _hex(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		pts.append(c + Vector2.from_angle(PI / 6.0 + i * PI / 3.0) * r)
	draw_polyline(pts, col, 1.0)


func _door_rect(slot: String) -> Rect2:
	var p := door_pos(slot)
	var d := slot_dir(slot)
	match d:
		"N": return Rect2(Vector2(p.x - DOOR_W / 2.0, -TOP_WALL + 4), Vector2(DOOR_W, TOP_WALL - 4))
		"S": return Rect2(Vector2(p.x - DOOR_W / 2.0, room_h), Vector2(DOOR_W, WALL))
		"W": return Rect2(Vector2(-WALL, p.y - DOOR_W / 2.0), Vector2(WALL, DOOR_W))
		_: return Rect2(Vector2(room_w, p.y - DOOR_W / 2.0), Vector2(WALL, DOOR_W))


func _draw_door(slot: String) -> void:
	var st := door_state(slot)
	if st == "none":
		return
	var r := _door_rect(slot)
	var horiz := slot_dir(slot) in ["N", "S"]
	if st == "cracked":
		# Hairline fractures: subtle but readable (stronger with Reading Glasses).
		var see: bool = RunState.flags.get("see_secrets", false)
		var c := Color(0.12, 0.09, 0.07, 1.0 if see else 0.8)
		var m := r.get_center()
		draw_line(m + Vector2(-5, -3), m + Vector2(-1, 1), c, 1.5 if see else 1.0)
		draw_line(m + Vector2(-1, 1), m + Vector2(3, -2), c, 1.0)
		draw_line(m + Vector2(-1, 1), m + Vector2(0, 5), c, 1.0)
		draw_line(m + Vector2(3, -2), m + Vector2(6, 2), c, 1.0)
		return
	var ntype: String = neighbor_types.get(slot, "normal")
	var kind := door_kind(slot)
	var frame := Color(0.55, 0.42, 0.25)
	match ntype:
		"boss": frame = Color(0.7, 0.12, 0.12)
		"treasure": frame = Color(0.95, 0.78, 0.2)
		"shop": frame = Color(0.35, 0.75, 0.85)
		"secret", "super_secret": frame = Color(0.2, 0.15, 0.1)
		"brood_cell": frame = Color(0.95, 0.9, 0.7)
		"royal": frame = Color(1.0, 0.97, 0.85)
		"den": frame = Color(0.35, 0.05, 0.08)
		"curse": frame = Color(0.3, 0.1, 0.25)
		"challenge": frame = Color(0.9, 0.45, 0.15)
		"vault": frame = Color(1.0, 0.85, 0.3)
		"library": frame = Color(0.5, 0.35, 0.6)
		"arcade": frame = Color(0.9, 0.3, 0.6)
		"miniboss": frame = Color(0.6, 0.2, 0.2)
		"sacrifice": frame = Color(0.5, 0.45, 0.4)
	if kind == "secret" or info["type"] in FloorGen.SECRET_TYPES:
		frame = Color(0.2, 0.15, 0.1)
	if info["type"] in ["royal", "den"]:
		frame = Color(1.0, 0.97, 0.85) if info["type"] == "royal" else Color(0.35, 0.05, 0.08)
	draw_rect(r.grow(2), frame)
	draw_rect(r, Color(0.04, 0.03, 0.02))
	if kind == "spiked":
		for k in 4:
			var t := (k + 0.5) / 4.0
			var base := r.position + (Vector2(r.size.x * t, r.size.y) if horiz else Vector2(r.size.x, r.size.y * t))
			draw_circle(r.position + (Vector2(r.size.x * t, 1) if horiz else Vector2(1, r.size.y * t)), 1.5, Color(0.75, 0.7, 0.7))
			draw_circle(base - (Vector2(0, 1) if horiz else Vector2(1, 0)), 1.5, Color(0.75, 0.7, 0.7))
	if st in ["closed", "locked", "barred"]:
		var bar := frame.darkened(0.2)
		for k in 3:
			if horiz:
				draw_rect(Rect2(r.position.x + 3 + k * 8, r.position.y, 3, r.size.y), bar)
			else:
				draw_rect(Rect2(r.position.x, r.position.y + 3 + k * 8, r.size.x, 3), bar)
	if st == "locked":
		var cost: int = int(info.get("lock_cost", {}).get(slot, 1))
		var m := r.get_center()
		for k in cost:
			var off := Vector2((k - (cost - 1) / 2.0) * 6.0, 0)
			draw_circle(m + off, 3.0, Color(0.98, 0.93, 0.6))
			draw_circle(m + off, 1.2, Color(0.4, 0.3, 0.1))
	elif st == "barred":
		var m2 := r.get_center()
		draw_circle(m2, 3.0, Color(0.86, 0.12, 0.18))
