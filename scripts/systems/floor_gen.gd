class_name FloorGen
extends RefCounted
## Isaac-style floor layout generator (DESIGN.md §10). Pure: same (depth, rng seed, cfg, opts)
## gives the same layout. Big multi-cell rooms arrive in Milestone 2; this places 1x1 cells.
##
## Output layout:
## {
##   depth, target, attempts, start: Vector2i, boss: Vector2i,
##   secret: Vector2i (or NONE), super_secret: Vector2i (or NONE),
##   order: Array[Vector2i]            # deterministic room order (room_index = position)
##   rooms: {Vector2i: {index, type, dist, doors: {dir: "normal"|"secret"}, brood_cell: bool, template: ""}}
## }

const NONE := Vector2i(-1, -1)
const DIRS: Dictionary = {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const DIR_ORDER: PackedStringArray = ["N", "E", "S", "W"]
const OPPOSITE: Dictionary = {"N": "S", "S": "N", "E": "W", "W": "E"}
const RNGScript := preload("res://scripts/autoload/rng.gd")


static func target_room_count(depth: int, r: RandomNumberGenerator, cfg: Dictionary) -> int:
	var n: int = r.randi_range(0, 1) + int(cfg.get("base_rooms", 5)) + int(floor(depth * float(cfg.get("rooms_per_depth", 2.6))))
	return mini(int(cfg.get("room_cap", 20)), n)


## opts:
##   required_specials: Array[String]   dead-end room types that must exist (besides boss)
##   brood_cells: [min, max]            floor-1 sealed brood cells in normal rooms ([0,0] = none)
##   brood_cell_room_chance: float      chance an extra dead end becomes a Brood Cell room
static func generate(depth: int, r: RandomNumberGenerator, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var w: int = int(cfg.get("grid_w", 13))
	var h: int = int(cfg.get("grid_h", 9))
	var sa: Array = cfg.get("start", [6, 4])
	var start := Vector2i(int(sa[0]), int(sa[1]))
	var required: Array = opts.get("required_specials", cfg.get("required_specials", ["treasure"]))
	var skip: float = float(cfg.get("branch_skip_chance", 0.5))
	var target := target_room_count(depth, r, cfg)
	var max_attempts: int = int(cfg.get("max_attempts", 200))
	for attempt in range(1, max_attempts + 1):
		var filled := _grow(start, target, w, h, r, skip)
		if filled.size() != target:
			continue
		var order: Array = filled.keys()
		var dist := _bfs(start, filled)
		var dead_ends: Array = []
		for c in order:
			if c != start and _neighbor_count(c, filled) == 1:
				dead_ends.append(c)
		if dead_ends.size() < 1 + required.size():
			continue
		var layout := _build(depth, target, attempt, start, order, dist, dead_ends, required, w, h, r, opts)
		return layout
	push_error("FloorGen: failed after %d attempts (target %d)" % [max_attempts, target])
	return {}


static func _grow(start: Vector2i, target: int, w: int, h: int, r: RandomNumberGenerator, skip: float) -> Dictionary:
	var filled := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty() and filled.size() < target:
		var cell: Vector2i = queue.pop_front()
		# Fresh array every time: never shuffle (mutate) anything derived from a const.
		var dirs: Array = []
		dirs.append_array(DIR_ORDER)
		RNGScript.shuffle(r, dirs)
		for d in dirs:
			if filled.size() >= target:
				break
			var n: Vector2i = cell + DIRS[d]
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or filled.has(n):
				continue
			if _neighbor_count(n, filled) > 1:
				continue
			if r.randf() < skip:
				continue
			filled[n] = true
			queue.push_back(n)
		# Isaac's trick: if the queue drains early, keep growing from the start room.
		if queue.is_empty() and filled.size() < target and r.randf() < 0.5:
			queue.push_back(start)
	return filled


static func _build(depth: int, target: int, attempt: int, start: Vector2i, order: Array, dist: Dictionary,
		dead_ends: Array, required: Array, w: int, h: int, r: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var rooms := {}
	for i in order.size():
		var c: Vector2i = order[i]
		rooms[c] = {"index": i, "type": "normal", "dist": int(dist[c]), "doors": {}, "brood_cell": false, "template": ""}
	rooms[start]["type"] = "start"

	# Boss = farthest dead end (ties keep generation order).
	var boss: Vector2i = dead_ends[0]
	for c in dead_ends:
		if dist[c] > dist[boss]:
			boss = c
	rooms[boss]["type"] = "boss"
	var rest: Array = dead_ends.filter(func(c: Vector2i) -> bool: return c != boss)
	RNGScript.shuffle(r, rest)
	for t in required:
		rooms[rest.pop_front()]["type"] = t
	var bcr: float = float(opts.get("brood_cell_room_chance", 0.0))
	if not rest.is_empty() and bcr > 0.0 and r.randf() < bcr:
		rooms[rest.pop_front()]["type"] = "brood_cell"

	# Doors between all adjacent filled cells (the growth rule keeps it a tree).
	for c in order:
		for d in DIR_ORDER:
			if rooms.has(c + DIRS[d]):
				rooms[c]["doors"][d] = "normal"

	# Secret room: empty cell bordering >= 3 rooms, never the boss. Relax to >= 2.
	var secret := NONE
	for need in [3, 2]:
		var cands := _empty_cells(rooms, w, h, func(cell: Vector2i, nbrs: Array) -> bool:
			return nbrs.size() >= need and not nbrs.has(boss))
		if not cands.is_empty():
			secret = cands[r.randi_range(0, cands.size() - 1)]
			break
	if secret != NONE:
		_add_secret_room(rooms, secret, "secret", order.size())
		order.append(secret)

	# Super-secret: borders exactly 1 room (not boss, not secret), not adjacent to the secret room.
	var super_secret := NONE
	var ss_cands := _empty_cells(rooms, w, h, func(cell: Vector2i, nbrs: Array) -> bool:
		if nbrs.size() != 1 or nbrs[0] == boss or rooms[nbrs[0]]["type"] in ["secret"]:
			return false
		return secret == NONE or (absi(cell.x - secret.x) + absi(cell.y - secret.y)) > 1)
	if not ss_cands.is_empty():
		# Prefer far from start; deterministic tie-break by scan order.
		var best: Vector2i = ss_cands[0]
		for c in ss_cands:
			if _nbr_dist(rooms, c) > _nbr_dist(rooms, best):
				best = c
		super_secret = best
		_add_secret_room(rooms, super_secret, "super_secret", order.size())
		order.append(super_secret)

	# Floor-1 sealed brood cells in normal rooms (not start, not boss-adjacent).
	var bc: Array = opts.get("brood_cells", [0, 0])
	var hosts: Array = []
	for c in order:
		if rooms[c]["type"] == "normal" and not _adjacent(c, boss):
			hosts.append(c)
	RNGScript.shuffle(r, hosts)
	var n_cells: int = mini(hosts.size(), r.randi_range(int(bc[0]), int(bc[1])))
	for i in n_cells:
		rooms[hosts[i]]["brood_cell"] = true

	# Parent direction (toward start) for every room: where workers come from.
	for c in rooms:
		rooms[c]["home_dir"] = _home_dir(rooms, c)

	return {"depth": depth, "target": target, "attempts": attempt, "start": start, "boss": boss,
		"secret": secret, "super_secret": super_secret, "order": order, "rooms": rooms}


static func _add_secret_room(rooms: Dictionary, cell: Vector2i, type: String, index: int) -> void:
	var doors := {}
	var dmin := 999
	for d in DIR_ORDER:
		var n: Vector2i = cell + DIRS[d]
		if rooms.has(n) and rooms[n]["type"] not in ["secret", "super_secret"]:
			doors[d] = "secret"
			rooms[n]["doors"][OPPOSITE[d]] = "secret"
			dmin = mini(dmin, int(rooms[n]["dist"]))
	rooms[cell] = {"index": index, "type": type, "dist": dmin + 1, "doors": doors, "brood_cell": false, "template": ""}


## Assigns a template id to each room. Templates: Array of room dicts from Content.
static func assign_templates(layout: Dictionary, templates: Array, r: RandomNumberGenerator) -> void:
	var sorted_t := templates.duplicate()
	sorted_t.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for c in layout["order"]:
		var room: Dictionary = layout["rooms"][c]
		var cands: Array = []
		var weights: Array = []
		for t in sorted_t:
			if t.get("shape", "1x1") != "1x1":
				continue
			if not room["type"] in t.get("room_types", ["normal"]):
				continue
			if room["brood_cell"] and not "brood_cell" in t.get("tags", []):
				continue
			var ok := true
			for d in room["doors"]:
				if not d in t.get("doors", []):
					ok = false
			if ok:
				cands.append(t["id"])
				weights.append(float(t.get("weight", 1.0)))
		if cands.is_empty():
			push_error("FloorGen: no template for room type '%s' (brood=%s)" % [room["type"], room["brood_cell"]])
			continue
		room["template"] = cands[RNGScript.weighted_index(r, weights)]


## Stable string describing the structure (for determinism tests and debugging).
static func structure_hash(layout: Dictionary) -> String:
	var parts: PackedStringArray = []
	for c in layout["order"]:
		var room: Dictionary = layout["rooms"][c]
		var doors: Array = room["doors"].keys()
		doors.sort()
		parts.append("%d,%d:%s:%s:%s:%s" % [c.x, c.y, room["type"], "".join(doors), room["brood_cell"], room["template"]])
	return "|".join(parts)


static func _empty_cells(rooms: Dictionary, w: int, h: int, pred: Callable) -> Array:
	var out: Array = []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if rooms.has(c):
				continue
			var nbrs: Array = []
			for d in DIR_ORDER:
				var n: Vector2i = c + DIRS[d]
				if rooms.has(n) and rooms[n]["type"] not in ["secret", "super_secret"]:
					nbrs.append(n)
			if pred.call(c, nbrs):
				out.append(c)
	return out


static func _nbr_dist(rooms: Dictionary, c: Vector2i) -> int:
	for d in DIR_ORDER:
		if rooms.has(c + DIRS[d]):
			return int(rooms[c + DIRS[d]]["dist"])
	return 0


static func _home_dir(rooms: Dictionary, c: Vector2i) -> String:
	var best := ""
	var best_d: int = int(rooms[c]["dist"])
	for d in rooms[c]["doors"]:
		var n: Vector2i = c + DIRS[d]
		if rooms.has(n) and int(rooms[n]["dist"]) < best_d and rooms[n]["type"] not in ["secret", "super_secret"]:
			best_d = int(rooms[n]["dist"])
			best = d
	return best


static func _neighbor_count(c: Vector2i, filled: Dictionary) -> int:
	var n := 0
	for d in DIR_ORDER:
		if filled.has(c + DIRS[d]):
			n += 1
	return n


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


static func _bfs(start: Vector2i, filled: Dictionary) -> Dictionary:
	var dist := {start: 0}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in DIR_ORDER:
			var n: Vector2i = c + DIRS[d]
			if filled.has(n) and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				q.push_back(n)
	return dist
