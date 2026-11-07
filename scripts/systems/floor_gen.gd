class_name FloorGen
extends RefCounted
## Isaac-style floor layout generator (DESIGN.md §10). Pure: the same (depth, rng seed, cfg, opts)
## always gives the same layout.
##
## Rooms are shaped (1x1, 2x1, 1x2, 2x2) and grown at room level: a new room may only touch the
## existing map at exactly one cell edge, so the room graph is a tree and every adjacency is a door.
##
## Output layout:
## {
##   depth, target, attempts, labyrinth,
##   start, boss, secret, super_secret, deal: Vector2i anchors (NONE when absent)
##   deal_slot: String                 # boss-room wall slot reserved for the Royal/Den door
##   order: Array[Vector2i]            # deterministic room order (room_index = position)
##   owner: {cell: anchor}             # which room covers each grid cell
##   rooms: {anchor: {index, type, shape, cells, dist, doors: {slot: kind}, links: {slot: [anchor, slot]},
##                    home_slot, brood_cell, template, offmap}}
## }
## A slot key is "ox,oy,D": the cell offset inside the room plus the wall direction.

const NONE := Vector2i(-1, -1)
const DEAL_ANCHOR := Vector2i(100, 100)  # off-map: Royal Chamber / Mutation Den
const DIRS: Dictionary = {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const DIR_ORDER: PackedStringArray = ["N", "E", "S", "W"]
const OPPOSITE: Dictionary = {"N": "S", "S": "N", "E": "W", "W": "E"}
const SHAPES: Dictionary = {
	"1x1": [Vector2i(0, 0)],
	"2x1": [Vector2i(0, 0), Vector2i(1, 0)],
	"1x2": [Vector2i(0, 0), Vector2i(0, 1)],
	"2x2": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
}
const SECRET_TYPES: PackedStringArray = ["secret", "super_secret"]
const RNGScript := preload("res://scripts/autoload/rng.gd")


static func target_room_count(depth: int, r: RandomNumberGenerator, cfg: Dictionary) -> int:
	var n: int = r.randi_range(0, 1) + int(cfg.get("base_rooms", 5)) + int(floor(depth * float(cfg.get("rooms_per_depth", 2.6))))
	return mini(int(cfg.get("room_cap", 20)), n)


static func slot_key(off: Vector2i, dir: String) -> String:
	return "%d,%d,%s" % [off.x, off.y, dir]


## Splits "ox,oy,D" into [Vector2i offset, dir].
static func parse_slot(key: String) -> Array:
	var p := key.split(",")
	return [Vector2i(int(p[0]), int(p[1])), p[2]]


static func shape_size(shape: String) -> Vector2i:
	var mx := Vector2i.ZERO
	for c in SHAPES.get(shape, SHAPES["1x1"]):
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	return mx + Vector2i.ONE


## Every wall slot of a shape (cell edges that face outside the shape), in a stable order.
static func shape_slots(shape: String) -> Array:
	var cells: Array = SHAPES.get(shape, SHAPES["1x1"])
	var out: Array = []
	for c in cells:
		for d in DIR_ORDER:
			if not cells.has(c + DIRS[d]):
				out.append(slot_key(c, d))
	return out


## opts:
##   required_specials: Array[String]   dead-end room types that must exist (besides boss)
##   random_specials: {type: weight}    one of these fills a spare dead end (if any)
##   random_special_count: int          how many random specials to try for (default 1)
##   brood_cells: [min, max]            sealed brood cells in normal rooms ([0,0] = none)
##   brood_cell_room_chance: float      chance a spare dead end becomes a Brood Cell room
##   labyrinth: bool                    XL floor (more rooms, +1 treasure)
static func generate(depth: int, r: RandomNumberGenerator, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var w: int = int(cfg.get("grid_w", 13))
	var h: int = int(cfg.get("grid_h", 9))
	var sa: Array = cfg.get("start", [6, 4])
	var start := Vector2i(int(sa[0]), int(sa[1]))
	var required: Array = []
	required.append_array(opts.get("required_specials", cfg.get("required_specials", ["treasure"])))
	var labyrinth: bool = opts.get("labyrinth", false)
	var target := target_room_count(depth, r, cfg)
	if labyrinth:
		target = mini(int(cfg.get("labyrinth_cap", 30)), int(target * float(cfg.get("labyrinth_mult", 1.8))))
		required.append("treasure")
	var skip: float = float(cfg.get("branch_skip_chance", 0.5))
	var big_rate: float = float(cfg.get("big_room_rate", 0.0))
	var big_weights: Dictionary = cfg.get("big_room_weights", {"2x1": 1.0, "1x2": 1.0, "2x2": 0.5})
	var max_attempts: int = int(cfg.get("max_attempts", 200))
	for attempt in range(1, max_attempts + 1):
		var grown := _grow(start, target, w, h, r, skip, big_rate, big_weights)
		var rooms: Dictionary = grown["rooms"]
		if rooms.size() != target:
			continue
		var layout := _link(rooms, grown["owner"], grown["order"], start)
		var linked: Dictionary = layout["rooms"]
		var dead_ends: Array = []
		for a in layout["order"]:
			if a != start and linked[a]["shape"] == "1x1" and linked[a]["links"].size() == 1:
				dead_ends.append(a)
		if dead_ends.size() < 1 + required.size():
			continue
		layout["depth"] = depth
		layout["target"] = target
		layout["attempts"] = attempt
		layout["labyrinth"] = labyrinth
		_place_specials(layout, dead_ends, required, r, opts)
		_place_secrets(layout, w, h, r)
		_place_brood_cells(layout, r, opts.get("brood_cells", [0, 0]))
		_finish(layout)
		return layout
	push_error("FloorGen: failed after %d attempts (target %d)" % [max_attempts, target])
	return {}


static func _grow(start: Vector2i, target: int, w: int, h: int, r: RandomNumberGenerator, skip: float,
		big_rate: float, big_weights: Dictionary) -> Dictionary:
	var owner := {start: start}
	var rooms := {start: {"shape": "1x1", "cells": [start]}}
	var order: Array = [start]
	var queue: Array[Vector2i] = [start]
	var shape_names: Array = big_weights.keys()
	shape_names.sort()
	var shape_w: Array = shape_names.map(func(s: String) -> float: return float(big_weights[s]))
	while not queue.is_empty() and rooms.size() < target:
		var a: Vector2i = queue.pop_front()
		# Fresh array every time: never shuffle (mutate) anything derived from a const.
		var slots: Array = []
		slots.append_array(shape_slots(rooms[a]["shape"]))
		RNGScript.shuffle(r, slots)
		for s in slots:
			if rooms.size() >= target:
				break
			var ps := parse_slot(s)
			var parent_cell: Vector2i = a + ps[0]
			var n: Vector2i = parent_cell + DIRS[ps[1]]
			if not _in_bounds(n, w, h) or owner.has(n):
				continue
			if r.randf() < skip:
				continue
			var placed := false
			if big_rate > 0.0 and r.randf() < big_rate:
				var shape: String = shape_names[RNGScript.weighted_index(r, shape_w)]
				var cells: Array = SHAPES[shape]
				var off: Vector2i = cells[r.randi_range(0, cells.size() - 1)]
				var anchor: Vector2i = n - off
				if _can_place(anchor, shape, owner, w, h):
					_place(anchor, shape, rooms, owner, order)
					queue.push_back(anchor)
					placed = true
			if not placed and _can_place(n, "1x1", owner, w, h):
				_place(n, "1x1", rooms, owner, order)
				queue.push_back(n)
		# Isaac's trick: if the queue drains early, keep growing from the start room.
		if queue.is_empty() and rooms.size() < target and r.randf() < 0.5:
			queue.push_back(start)
	return {"rooms": rooms, "owner": owner, "order": order}


static func _can_place(anchor: Vector2i, shape: String, owner: Dictionary, w: int, h: int) -> bool:
	var cells: Array = []
	for off in SHAPES[shape]:
		var c: Vector2i = anchor + off
		if not _in_bounds(c, w, h) or owner.has(c):
			return false
		cells.append(c)
	# The new room may touch the existing map at exactly one cell edge (keeps the room graph a tree).
	var touches := 0
	for c in cells:
		for d in DIR_ORDER:
			var n: Vector2i = c + DIRS[d]
			if not cells.has(n) and owner.has(n):
				touches += 1
	return touches == 1


static func _place(anchor: Vector2i, shape: String, rooms: Dictionary, owner: Dictionary, order: Array) -> void:
	var cells: Array = []
	for off in SHAPES[shape]:
		cells.append(anchor + off)
		owner[anchor + off] = anchor
	rooms[anchor] = {"shape": shape, "cells": cells}
	order.append(anchor)


static func _link(grown_rooms: Dictionary, owner: Dictionary, order: Array, start: Vector2i) -> Dictionary:
	var rooms := {}
	for i in order.size():
		var a: Vector2i = order[i]
		rooms[a] = {"index": i, "type": "normal", "shape": grown_rooms[a]["shape"], "cells": grown_rooms[a]["cells"],
			"dist": 0, "doors": {}, "links": {}, "brood_cell": false, "template": "", "home_slot": "", "offmap": false}
	for a in order:
		for s in shape_slots(rooms[a]["shape"]):
			var ps := parse_slot(s)
			var n: Vector2i = a + ps[0] + DIRS[ps[1]]
			if owner.has(n):
				var b: Vector2i = owner[n]
				rooms[a]["doors"][s] = "normal"
				rooms[a]["links"][s] = [b, slot_key(n - b, OPPOSITE[ps[1]])]
	rooms[start]["type"] = "start"
	# BFS over the room graph.
	var seen := {start: true}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for s in rooms[c]["links"]:
			var b: Vector2i = rooms[c]["links"][s][0]
			if not seen.has(b):
				seen[b] = true
				rooms[b]["dist"] = int(rooms[c]["dist"]) + 1
				q.push_back(b)
	return {"start": start, "boss": NONE, "secret": NONE, "super_secret": NONE, "deal": NONE, "deal_slot": "",
		"order": order.duplicate(), "owner": owner, "rooms": rooms}


static func _place_specials(layout: Dictionary, dead_ends: Array, required: Array, r: RandomNumberGenerator, opts: Dictionary) -> void:
	var rooms: Dictionary = layout["rooms"]
	var boss: Vector2i = dead_ends[0]
	for c in dead_ends:
		if rooms[c]["dist"] > rooms[boss]["dist"]:
			boss = c
	rooms[boss]["type"] = "boss"
	layout["boss"] = boss
	var rest: Array = dead_ends.filter(func(c: Vector2i) -> bool: return c != boss)
	RNGScript.shuffle(r, rest)
	for t in required:
		rooms[rest.pop_front()]["type"] = t
	var bcr: float = float(opts.get("brood_cell_room_chance", 0.0))
	if not rest.is_empty() and bcr > 0.0 and r.randf() < bcr:
		rooms[rest.pop_front()]["type"] = "brood_cell"
	var weights: Dictionary = opts.get("random_specials", {})
	var names: Array = weights.keys()
	names.sort()
	for i in int(opts.get("random_special_count", 1)):
		if rest.is_empty() or names.is_empty():
			break
		var idx := RNGScript.weighted_index(r, names.map(func(n: String) -> float: return float(weights[n])))
		if idx < 0:
			break
		rooms[rest.pop_front()]["type"] = names[idx]
	# Reserve a free wall on the boss room for a possible Royal Chamber / Mutation Den door.
	for s in shape_slots(rooms[boss]["shape"]):
		if not rooms[boss]["links"].has(s):
			layout["deal_slot"] = s
			break


static func _place_secrets(layout: Dictionary, w: int, h: int, r: RandomNumberGenerator) -> void:
	var rooms: Dictionary = layout["rooms"]
	var boss: Vector2i = layout["boss"]
	for need in [3, 2]:
		var cands := _empty_cells(layout, w, h, func(_cell: Vector2i, nbrs: Array) -> bool:
			return nbrs.size() >= need and not nbrs.has(boss))
		if not cands.is_empty():
			var c: Vector2i = cands[r.randi_range(0, cands.size() - 1)]
			_add_secret_room(layout, c, "secret")
			layout["secret"] = c
			break
	var secret: Vector2i = layout["secret"]
	var ss_cands := _empty_cells(layout, w, h, func(cell: Vector2i, nbrs: Array) -> bool:
		if nbrs.size() != 1 or nbrs[0] == boss:
			return false
		return secret == NONE or (absi(cell.x - secret.x) + absi(cell.y - secret.y)) > 1)
	if not ss_cands.is_empty():
		var best: Vector2i = ss_cands[0]
		var best_d := -1
		for c in ss_cands:
			var d := _neighbor_room_dist(layout, c)
			if d > best_d:
				best_d = d
				best = c
		_add_secret_room(layout, best, "super_secret")
		layout["super_secret"] = best


## A secret room is 1x1 and joins every neighboring room with a cracked wall on both sides.
static func _add_secret_room(layout: Dictionary, cell: Vector2i, type: String) -> void:
	var rooms: Dictionary = layout["rooms"]
	var owner: Dictionary = layout["owner"]
	var info := {"index": layout["order"].size(), "type": type, "shape": "1x1", "cells": [cell], "dist": 999,
		"doors": {}, "links": {}, "brood_cell": false, "template": "", "home_slot": "", "offmap": false}
	for d in DIR_ORDER:
		var n: Vector2i = cell + DIRS[d]
		if owner.has(n) and not rooms[owner[n]]["type"] in SECRET_TYPES:
			var b: Vector2i = owner[n]
			var bs := slot_key(n - b, OPPOSITE[d])
			var s := slot_key(Vector2i.ZERO, d)
			info["doors"][s] = "secret"
			info["links"][s] = [b, bs]
			rooms[b]["doors"][bs] = "secret"
			rooms[b]["links"][bs] = [cell, s]
			info["dist"] = mini(int(info["dist"]), int(rooms[b]["dist"]) + 1)
	rooms[cell] = info
	owner[cell] = cell
	layout["order"].append(cell)


static func _place_brood_cells(layout: Dictionary, r: RandomNumberGenerator, bc: Array) -> void:
	var rooms: Dictionary = layout["rooms"]
	var hosts: Array = []
	for a in layout["order"]:
		if rooms[a]["type"] != "normal":
			continue
		var boss_adjacent := false
		for s in rooms[a]["links"]:
			if rooms[a]["links"][s][0] == layout["boss"]:
				boss_adjacent = true
		if not boss_adjacent:
			hosts.append(a)
	RNGScript.shuffle(r, hosts)
	var n_cells: int = mini(hosts.size(), r.randi_range(int(bc[0]), int(bc[1])))
	for i in n_cells:
		rooms[hosts[i]]["brood_cell"] = true


static func _finish(layout: Dictionary) -> void:
	var rooms: Dictionary = layout["rooms"]
	for a in rooms:
		rooms[a]["home_slot"] = _home_slot(rooms, a)
	# Door kinds that depend on the room behind them (locked / spiked / challenge) are decided by
	# FloorContents; FloorGen only knows "normal" and "secret".


## Slot that leads toward the start room (where workers fly in from).
static func _home_slot(rooms: Dictionary, a: Vector2i) -> String:
	var best := ""
	var best_d: int = int(rooms[a]["dist"])
	var keys: Array = rooms[a]["links"].keys()
	keys.sort()
	for s in keys:
		var b: Vector2i = rooms[a]["links"][s][0]
		if rooms[b]["type"] in SECRET_TYPES and not rooms[a]["type"] in SECRET_TYPES:
			continue
		if int(rooms[b]["dist"]) < best_d:
			best_d = int(rooms[b]["dist"])
			best = s
	return best


## Adds the off-map Royal Chamber / Mutation Den behind the boss room's reserved wall slot.
static func add_deal_room(layout: Dictionary, type: String) -> Vector2i:
	if layout["deal_slot"] == "" or layout["deal"] != NONE:
		return layout["deal"]
	var boss: Vector2i = layout["boss"]
	var bs: String = layout["deal_slot"]
	var dir: String = parse_slot(bs)[1]
	var s := slot_key(Vector2i.ZERO, OPPOSITE[dir])
	layout["rooms"][DEAL_ANCHOR] = {"index": layout["order"].size(), "type": type, "shape": "1x1", "cells": [],
		"dist": int(layout["rooms"][boss]["dist"]) + 1, "doors": {s: "normal"}, "links": {s: [boss, bs]},
		"brood_cell": false, "template": "", "home_slot": s, "offmap": true}
	layout["rooms"][boss]["doors"][bs] = "deal"
	layout["rooms"][boss]["links"][bs] = [DEAL_ANCHOR, s]
	layout["order"].append(DEAL_ANCHOR)
	layout["deal"] = DEAL_ANCHOR
	return DEAL_ANCHOR


## Assigns a template id to each room by type, shape, stratum tag and door slots.
static func assign_templates(layout: Dictionary, templates: Array, r: RandomNumberGenerator) -> void:
	var sorted_t := templates.duplicate()
	sorted_t.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for a in layout["order"]:
		assign_template(layout["rooms"][a], sorted_t, r)


static func assign_template(room: Dictionary, sorted_templates: Array, r: RandomNumberGenerator) -> void:
	var cands: Array = []
	var weights: Array = []
	for t in sorted_templates:
		if t.get("shape", "1x1") != room["shape"]:
			continue
		if not room["type"] in t.get("room_types", ["normal"]):
			continue
		if room["brood_cell"] and not "brood_cell" in t.get("tags", []):
			continue
		if room["shape"] == "1x1" and t.has("doors"):
			var ok := true
			for s in room["doors"]:
				if not parse_slot(s)[1] in t["doors"]:
					ok = false
			if not ok:
				continue
		cands.append(t["id"])
		weights.append(float(t.get("weight", 1.0)))
	if cands.is_empty():
		if room["brood_cell"]:
			# No brood template for this shape: keep the room, lose the sealed cell.
			push_warning("FloorGen: no brood_cell template for shape %s; dropping the cell" % room["shape"])
			room["brood_cell"] = false
			assign_template(room, sorted_templates, r)
			return
		push_error("FloorGen: no template for %s room (%s, brood=%s)" % [room["type"], room["shape"], room["brood_cell"]])
		return
	room["template"] = cands[RNGScript.weighted_index(r, weights)]


## Stable string describing the structure (for determinism tests and debugging).
static func structure_hash(layout: Dictionary) -> String:
	var parts: PackedStringArray = []
	for a in layout["order"]:
		var room: Dictionary = layout["rooms"][a]
		var doors: Array = room["doors"].keys()
		doors.sort()
		parts.append("%d,%d:%s:%s:%s:%s:%s" % [a.x, a.y, room["shape"], room["type"], "|".join(doors), room["brood_cell"], room["template"]])
	return ";".join(parts)


static func _in_bounds(c: Vector2i, w: int, h: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


## Empty grid cells; pred(cell, neighbor_anchors) where neighbors are the distinct non-secret rooms
## touching the cell (one entry per touching cell edge).
static func _empty_cells(layout: Dictionary, w: int, h: int, pred: Callable) -> Array:
	var owner: Dictionary = layout["owner"]
	var rooms: Dictionary = layout["rooms"]
	var out: Array = []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if owner.has(c):
				continue
			var nbrs: Array = []
			for d in DIR_ORDER:
				var n: Vector2i = c + DIRS[d]
				if owner.has(n) and not rooms[owner[n]]["type"] in SECRET_TYPES:
					nbrs.append(owner[n])
			if pred.call(c, nbrs):
				out.append(c)
	return out


static func _neighbor_room_dist(layout: Dictionary, c: Vector2i) -> int:
	for d in DIR_ORDER:
		var n: Vector2i = c + DIRS[d]
		if layout["owner"].has(n):
			return int(layout["rooms"][layout["owner"][n]]["dist"])
	return 0
