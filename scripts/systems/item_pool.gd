class_name ItemPool
extends RefCounted
## Item pool rolls (DESIGN.md §6.3). An item seen in any pool is removed from all pools for the
## run. Exhausted pool -> its fallback pool -> FALLBACK_ITEM.

const FALLBACK_ITEM := "pocket_lint"
const RNGScript := preload("res://scripts/autoload/rng.gd")

var pools: Dictionary   # pool_id -> pool entry {entries: [{id, weight}], fallback}
var items: Dictionary   # item_id -> item entry
var is_unlocked: Callable  # func(item_id: String) -> bool
var seen: Dictionary = {}


func _init(pool_entries: Dictionary, item_entries: Dictionary, unlocked: Callable) -> void:
	pools = pool_entries
	items = item_entries
	is_unlocked = unlocked


static func from_content() -> ItemPool:
	var p := {}
	for e in Content.all("pools"):
		p[e["id"]] = e
	var it := {}
	for e in Content.all("items"):
		it[e["id"]] = e
	return ItemPool.new(p, it, func(id: String) -> bool:
		var item: Dictionary = it.get(id, {})
		return not item.get("locked_by_default", false) or MetaSave.is_unlocked("items", id))


func candidates(pool_id: String) -> Array:
	var out: Array = []
	for e in pools.get(pool_id, {}).get("entries", []):
		var id: String = e["id"]
		if items.has(id) and not seen.has(id) and is_unlocked.call(id):
			out.append(e)
	return out


func roll(pool_id: String, r: RandomNumberGenerator) -> String:
	var visited := {}
	var pid := pool_id
	while pid != "" and not visited.has(pid):
		visited[pid] = true
		var cands := candidates(pid)
		if not cands.is_empty():
			var weights: Array = cands.map(func(e: Dictionary) -> float: return float(e.get("weight", 1.0)))
			var id: String = cands[RNGScript.weighted_index(r, weights)]["id"]
			seen[id] = true
			return id
		pid = str(pools.get(pid, {}).get("fallback", "dig_site" if pid != "dig_site" else ""))
	return FALLBACK_ITEM


func mark_seen(id: String) -> void:
	seen[id] = true
