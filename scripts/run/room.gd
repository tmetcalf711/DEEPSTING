class_name Room
extends Node2D
## One room of the floor, built from a hand-authored template (DESIGN.md §10.4).
## Room-local coordinates: the interior spans (0,0)-(W,H); walls sit outside it.
## Persistent state (cleared, destroyed rocks, leftover pickups, opened secret walls...) is
## written back into the floor layout's room `info` dictionary on exit.

signal cleared_room()

const TILE := 16
const COLS := 13
const ROWS := 7
const W := COLS * TILE  # 208
const H := ROWS * TILE  # 112
const WALL := 16
const TOP_WALL := 22     # top wall is taller to fake depth (2.5D)
const DOOR_W := 24
const DIRS: Dictionary = {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}

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

var cell: Vector2i
var info: Dictionary
var template: Dictionary
var neighbor_types: Dictionary = {}   # dir -> neighbor room type
var palette: Dictionary = {}
var grid: Array = []                  # Array[Array[String]] of tile chars
var entities: Node2D
var rng_enemies: RandomNumberGenerator
var rng_drops: RandomNumberGenerator

var enemies_alive: int = 0
var had_enemies: bool = false
var is_cleared: bool = false
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
var shaft_x: float = W / 2.0             # boss shaft column; moved aside if a north door exists


func setup(p_cell: Vector2i, p_info: Dictionary, p_template: Dictionary, p_neighbors: Dictionary, p_palette: Dictionary) -> void:
	cell = p_cell
	info = p_info
	template = p_template
	neighbor_types = p_neighbors
	palette = p_palette
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
	if info["doors"].has("N"):
		shaft_x = W / 2.0 - 64.0
	_rebuild_walls()
	_restore_pickups()
	_spawn_pedestal()
	_spawn_brood_cells()
	if not is_cleared:
		_spawn_enemies()
	if enemies_alive == 0 and not is_cleared:
		_mark_cleared(false)
	if info["type"] == "boss" and is_cleared:
		_spawn_trapdoor()
		_shaft_open = 1.0
	if info["type"] in ["secret", "super_secret"] and not info.get("visited", false):
		RunState.bump("secrets_found")
		MetaSave.add_counter("secret_rooms_found")
		Events.toast.emit(tr("TOAST_SECRET_FOUND"))
	info["visited"] = true
	_enter_grace = 0.5
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
	if t.x < 0 or t.y < 0 or t.x >= COLS or t.y >= ROWS:
		return "#"
	return grid[t.y][t.x]


func is_walkable_tile(t: Vector2i) -> bool:
	return tile_at(t) in [".", "S", "D", "P"]


func is_bullet_blocked(p: Vector2, spectral: bool) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= W or p.y >= H:
		return true
	if spectral:
		return false
	return tile_at(world_to_tile(p)) in ["R", "T", "#"]


func free_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in ROWS:
		for x in COLS:
			if tile_at(Vector2i(x, y)) == ".":
				out.append(Vector2i(x, y))
	return out


## Nearest walkable tile center to a point (used to place drops so they never land in rocks).
func nearest_free_point(p: Vector2) -> Vector2:
	var best := Vector2(W / 2.0, H / 2.0)
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
	for y in ROWS:
		for x in COLS:
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
		_drop_from_table("tinted_rock", c)
	elif RunState.flags.get("rock_mana_bonus", false):
		_drop_from_table("rock_bonus", c)
	MetaSave.add_counter("rocks_broken")


# ---------------------------------------------------------------- walls and doors

func door_state(dir: String) -> String:
	## "none" | "closed" | "open" | "cracked" (unopened secret wall)
	if not info["doors"].has(dir):
		return "none"
	if info["doors"][dir] == "secret":
		return "open" if info.get("opened_secret", {}).has(dir) else "cracked"
	return "open" if is_cleared else "closed"


func door_pos(dir: String) -> Vector2:
	match dir:
		"N": return Vector2(W / 2.0, 0)
		"S": return Vector2(W / 2.0, H)
		"W": return Vector2(0, H / 2.0)
		_: return Vector2(W, H / 2.0)


## Just outside the door, where workers appear from.
func door_outside(dir: String) -> Vector2:
	return door_pos(dir) + Vector2(DIRS[dir]) * 20.0


func entry_point(dir: String) -> Vector2:
	return door_pos(dir) - Vector2(DIRS[dir]) * 16.0


func _rebuild_walls() -> void:
	if _wall_body:
		_wall_body.queue_free()
	_wall_body = StaticBody2D.new()
	_wall_body.collision_layer = LAYER_WALLS
	_wall_body.collision_mask = 0
	add_child(_wall_body)
	var half := DOOR_W / 2.0
	var cx := W / 2.0
	var cy := H / 2.0
	var t := 40.0  # collision thickness (deeper than the visual wall so nothing tunnels)
	# Each side is split into two segments around the door gap; the gap is filled when the door
	# is not open.
	_side(Rect2(-t, -t, cx - half + t, t), Rect2(cx + half, -t, W - cx - half + t, t), Rect2(cx - half, -t, DOOR_W, t), "N")
	_side(Rect2(-t, H, cx - half + t, t), Rect2(cx + half, H, W - cx - half + t, t), Rect2(cx - half, H, DOOR_W, t), "S")
	_side(Rect2(-t, -t, t, cy - half + t), Rect2(-t, cy + half, t, H - cy - half + t), Rect2(-t, cy - half, t, DOOR_W), "W")
	_side(Rect2(W, -t, t, cy - half + t), Rect2(W, cy + half, t, H - cy - half + t), Rect2(W, cy - half, t, DOOR_W), "E")
	# Alcove depth limiter: doors lead into a short tunnel; going past it triggers the transition.
	queue_redraw()


func _side(a: Rect2, b: Rect2, gap: Rect2, dir: String) -> void:
	_add_rect(a)
	_add_rect(b)
	if door_state(dir) != "open":
		_add_rect(gap)


func _add_rect(r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = r.size
	cs.shape = rs
	cs.position = r.position + r.size / 2.0
	_wall_body.add_child(cs)


func open_secret(dir: String) -> void:
	var o: Dictionary = info.get("opened_secret", {})
	if o.has(dir):
		return
	o[dir] = true
	info["opened_secret"] = o
	RunController.instance.on_secret_opened(cell, dir)
	Audio.play_sfx("wall_crumble")
	RunController.instance.fx.burst(door_pos(dir), Color(0.6, 0.5, 0.4), 18, 80.0, 2.0)
	call_deferred("_rebuild_walls")


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
	return e


func on_enemy_died(e: Node) -> void:
	enemies_alive -= 1
	if e.get("is_boss"):
		# Minions die with their mother (Isaac convention).
		for other in get_tree().get_nodes_in_group("enemies"):
			if other != e and is_instance_valid(other) and other.get_parent() == entities:
				other.die(false)
	else:
		if rng_drops.randf() < float(_drops("enemy_kill").get("chance", 0.0)):
			_drop_from_table("enemy_kill", e.global_position)
	if enemies_alive <= 0 and not is_cleared:
		_mark_cleared(true)


func _spawn_pedestal() -> void:
	if not info.has("pedestal"):
		return
	var p: Node2D = PedestalScript.new()
	p.setup(self, str(info["pedestal"]))
	var at := Vector2(W / 2.0, H / 2.0)
	for y in ROWS:
		for x in COLS:
			if tile_at(Vector2i(x, y)) == "P":
				at = tile_center(Vector2i(x, y))
	if info["type"] == "boss":
		at = Vector2(W / 2.0, H / 2.0 + 4)
	p.position = at
	entities.add_child(p)


func _spawn_brood_cells() -> void:
	for y in ROWS:
		for x in COLS:
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
	var home := _home_door()
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


func _drop_from_table(table: String, pos: Vector2, force: bool = false) -> void:
	var t := _drops(table)
	if t.is_empty():
		return
	if not force and rng_drops.randf() >= float(t.get("chance", 1.0)):
		return
	var entries: Array = t["table"]
	var idx := RNG.weighted_index(rng_drops, entries.map(func(e: Dictionary) -> float: return float(e["weight"])))
	var v := Vector2.from_angle(rng_drops.randf() * TAU) * rng_drops.randf_range(20, 50)
	spawn_pickup(entries[idx]["id"], pos, v)


# ---------------------------------------------------------------- clearing / hauling

func _mark_cleared(from_combat: bool) -> void:
	is_cleared = true
	info["cleared"] = true
	call_deferred("_rebuild_walls")
	for n in get_tree().get_nodes_in_group("brood_cells"):
		if n.get_parent() == entities:
			n.unlock()
	if not from_combat:
		if info["type"] == "secret" or info["type"] == "super_secret":
			if not info.get("loot_spawned", false):
				info["loot_spawned"] = true
				var sr := _drops("secret_room")
				var cnt: Array = sr.get("count", [3, 5])
				for i in rng_drops.randi_range(int(cnt[0]), int(cnt[1])):
					_drop_from_table("secret_room", Vector2(W / 2.0, H / 2.0 + 18), true)
		return
	Audio.play_sfx("doors_open")
	RunState.bump("rooms_cleared")
	MetaSave.add_counter("rooms_cleared")
	RunController.instance.on_room_cleared(self)
	if info["type"] == "boss":
		_start_boss_shaft()
	else:
		_spawn_deposits_and_haul()
		_drop_from_table("room_clear", nearest_free_point(Vector2(W / 2.0, H / 2.0)))
	cleared_room.emit()


func _home_door() -> String:
	var hd: String = info.get("home_dir", "")
	if hd == "" or not info["doors"].has(hd):
		for d in ["S", "N", "W", "E"]:
			if info["doors"].has(d) and info["doors"][d] != "secret":
				return d
		return "S"
	return hd


func _spawn_deposits_and_haul() -> void:
	var dep := _drops("deposits")
	var cnt: Array = dep.get("count", [1, 3])
	var val: Array = dep.get("value", [2, 5])
	var n: int = rng_drops.randi_range(int(cnt[0]), int(cnt[1]))
	var slots: Array[Vector2i] = []
	for y in ROWS:
		for x in COLS:
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
	var from := door_outside(_home_door())
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
	t.position = Vector2(W / 2.0, H - 26)
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
		if is_instance_valid(t) and t.global_position.distance_to(pos) <= radius + float(t.get("hit_radius")):
			t.take_hit(damage, (t.global_position - pos).normalized(), ["blast"])
	if rc.player and rc.player.global_position.distance_to(pos) <= radius:
		rc.player.hurt(2, "dig_charge")
	for y in ROWS:
		for x in COLS:
			var t := Vector2i(x, y)
			if tile_center(t).distance_to(pos) <= radius + 4.0:
				destroy_tile(t)
	for dir in DIRS:
		if door_state(dir) == "cracked" and door_pos(dir).distance_to(pos) <= radius + 12.0:
			open_secret(dir)


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_enter_grace = maxf(0.0, _enter_grace - delta)
	# Secret walls leak a faint dust trickle every few seconds (the readable tell, §4).
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = rng_drops.randf_range(2.5, 4.5)
		for dir in DIRS:
			if door_state(dir) == "cracked":
				RunController.instance.fx.dust(door_pos(dir) - Vector2(DIRS[dir]) * 2.0)
	if _shaft_active and _shaft_open > 0.0:
		queue_redraw()


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
	draw_rect(Rect2(-WALL, -TOP_WALL, W + WALL * 2, H + TOP_WALL + WALL), wall_c.darkened(0.35))
	draw_rect(Rect2(-WALL, -TOP_WALL, W + WALL * 2, TOP_WALL - 8), wall_top)
	draw_rect(Rect2(0, -8, W, 8), wall_c)  # front face of the top wall
	draw_rect(Rect2(-WALL, 0, WALL, H), wall_c.darkened(0.15))
	draw_rect(Rect2(W, 0, WALL, H), wall_c.darkened(0.15))
	draw_rect(Rect2(-WALL, H, W + WALL * 2, WALL), wall_c.darkened(0.05))
	# Floor: checker + paper-comb hex hints (deterministic per room cell).
	for y in ROWS:
		for x in COLS:
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			draw_rect(r, floor_c if (x + y) % 2 == 0 else floor_alt)
			var hsh := absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ (x * 83492791) ^ (y * 2654435761)) % 9
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
	# Doors
	for dir in DIRS:
		_draw_door(dir)
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


func _draw_door(dir: String) -> void:
	var st := door_state(dir)
	if st == "none":
		return
	var p := door_pos(dir)
	var horiz := dir == "N" or dir == "S"
	var size := Vector2(DOOR_W, WALL) if horiz else Vector2(WALL, DOOR_W)
	var r := Rect2(p - size / 2.0, size)
	if dir == "N":
		r = Rect2(Vector2(p.x - DOOR_W / 2.0, -TOP_WALL + 4), Vector2(DOOR_W, TOP_WALL - 4))
	elif dir == "S":
		r.position.y = H
	elif dir == "W":
		r.position.x = -WALL
	else:
		r.position.x = W
	if st == "cracked":
		# Hairline fractures: subtle but readable.
		var c := Color(0.12, 0.09, 0.07, 0.8)
		var m := r.get_center()
		draw_line(m + Vector2(-5, -3), m + Vector2(-1, 1), c, 1.0)
		draw_line(m + Vector2(-1, 1), m + Vector2(3, -2), c, 1.0)
		draw_line(m + Vector2(-1, 1), m + Vector2(0, 5), c, 1.0)
		draw_line(m + Vector2(3, -2), m + Vector2(6, 2), c, 1.0)
		return
	var ntype: String = neighbor_types.get(dir, "normal")
	var frame := Color(0.55, 0.42, 0.25)
	match ntype:
		"boss": frame = Color(0.7, 0.12, 0.12)
		"treasure": frame = Color(0.95, 0.78, 0.2)
		"secret", "super_secret": frame = Color(0.2, 0.15, 0.1)
		"brood_cell": frame = Color(0.95, 0.9, 0.7)
	if info["doors"][dir] == "secret" or info["type"] in ["secret", "super_secret"]:
		frame = Color(0.2, 0.15, 0.1)
	draw_rect(r.grow(2), frame)
	draw_rect(r, Color(0.04, 0.03, 0.02))
	if st == "closed":
		var bar := frame.darkened(0.2)
		for k in 3:
			if horiz:
				draw_rect(Rect2(r.position.x + 3 + k * 8, r.position.y, 3, r.size.y), bar)
			else:
				draw_rect(Rect2(r.position.x, r.position.y + 3 + k * 8, r.size.x, 3), bar)
