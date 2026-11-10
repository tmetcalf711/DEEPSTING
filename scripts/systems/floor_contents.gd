class_name FloorContents
extends RefCounted
## Fills a generated layout with its contents (DESIGN.md §8.3): pedestal items, shop wares, the
## boss, minibosses, challenge waves, door locks. Everything is rolled here, in fixed room order,
## at generation time, so exploration order never changes what a seed gives (D19).
##
## ctx: {floor_index, stratum: Dictionary, pool: ItemPool, items_rng, rooms_rng, cfg (floorgen)}

const RNGScript := preload("res://scripts/autoload/rng.gd")
const PickupScript := preload("res://scripts/actors/pickup.gd")


static func fill(layout: Dictionary, ctx: Dictionary) -> void:
	var stratum: Dictionary = ctx["stratum"]
	var pool: ItemPool = ctx["pool"]
	var ri: RandomNumberGenerator = ctx["items_rng"]
	var rr: RandomNumberGenerator = ctx["rooms_rng"]
	var depth: int = int(ctx["floor_index"]) + 1
	var cfg: Dictionary = ctx.get("cfg", {})
	var shop_cfg: Dictionary = Content.get_entry("config", "shop")
	var drops: Dictionary = Content.get_entry("config", "drops")
	var bosses := _sorted(Content.all("bosses").filter(func(b: Dictionary) -> bool: return stratum["id"] in b.get("strata", [])))
	var minibosses := _sorted(Content.all("enemies").filter(func(e: Dictionary) -> bool:
		return "miniboss" in e.get("tags", []) and (stratum["id"] in e.get("strata", [stratum["id"]]))))
	for a in layout["order"]:
		var info: Dictionary = layout["rooms"][a]
		match str(info["type"]):
			"treasure":
				info["pedestal"] = _roll_with_strata(pool, "dig_site", stratum, ri)
			"boss":
				info["boss_id"] = bosses[rr.randi_range(0, bosses.size() - 1)]["id"] if not bosses.is_empty() else ""
				info["pedestal_on_clear"] = pool.roll("boss", ri)
			"secret":
				if ri.randf() < float(drops.get("secret_room", {}).get("item_chance", 0.5)):
					info["pedestal"] = pool.roll("secret", ri)
			"super_secret":
				info["pedestal"] = pool.roll("secret", ri)
			"shop":
				info["wares"] = roll_shop(pool, ri, shop_cfg)
			"curse":
				if ri.randf() < 0.5:
					info["pedestal"] = pool.roll("cursed", ri)
			"challenge":
				info["pedestal"] = pool.roll("dig_site", ri)
				info["waves"] = roll_waves(stratum, rr, depth)
			"miniboss":
				info["miniboss_id"] = minibosses[rr.randi_range(0, minibosses.size() - 1)]["id"] if not minibosses.is_empty() else ""
			"vault":
				info["pedestal"] = pool.roll("vault", ri)
			"library":
				info["pedestal"] = pool.roll("library", ri)
			"arcade":
				info["machines"] = Content.get_entry("config", "arcade").get("machines", {}).keys()
				info["machines"].sort()
	_apply_door_kinds(layout, depth, cfg)


## Royal Chamber / Mutation Den contents, rolled when the deal room appears after the boss.
static func fill_deal(info: Dictionary, pool: ItemPool, ri: RandomNumberGenerator) -> void:
	if info["type"] == "royal":
		info["choices"] = [pool.roll("royal", ri), pool.roll("royal", ri)]
	else:
		var wares: Array = []
		for i in 2:
			var id := pool.roll("mutation", ri)
			var q: int = int(Content.get_entry("items", id).get("quality", 2))
			wares.append({"kind": "item", "id": id, "heart_cost": 2 if q >= 3 else 1, "sold": false})
		info["wares"] = wares


static func roll_shop(pool: ItemPool, ri: RandomNumberGenerator, shop_cfg: Dictionary) -> Array:
	var wares: Array = []
	for i in int(shop_cfg.get("item_slots", 2)):
		var id := pool.roll("trader", ri)
		wares.append({"kind": "item", "id": id, "price": item_price(id, shop_cfg), "sold": false})
	var table: Array = shop_cfg.get("consumables", [])
	var weights: Array = table.map(func(e: Dictionary) -> float: return float(e.get("weight", 1.0)))
	for i in int(shop_cfg.get("consumable_slots", 3)):
		var e: Dictionary = table[RNGScript.weighted_index(ri, weights)]
		var w := {"kind": "pickup", "id": e["id"], "price": int(e["price"]), "sold": false}
		var pk: String = str(Content.get_entry("pickups", str(e["id"])).get("kind", ""))
		if pk in ["trinket", "fossil", "fluid"]:
			w["payload"] = PickupScript.roll_payload(pk, ri)
		wares.append(w)
	return wares


static func item_price(id: String, shop_cfg: Dictionary) -> int:
	var q: int = int(Content.get_entry("items", id).get("quality", 1))
	var prices: Array = shop_cfg.get("item_prices_by_quality", [10, 15, 15, 20, 25])
	return int(prices[clampi(q, 0, prices.size() - 1)])


## Challenge room: 3 waves of the stratum's enemies, growing with depth.
static func roll_waves(stratum: Dictionary, rr: RandomNumberGenerator, depth: int) -> Array:
	var pool_ids: Array = stratum.get("enemies", ["twin_grub"])
	var waves: Array = []
	for w in 3:
		var wave: Array = []
		for k in 2 + w + mini(depth, 3):
			wave.append(pool_ids[rr.randi_range(0, pool_ids.size() - 1)])
		waves.append(wave)
	return waves


## Locked doors (Royal Jelly), the Curse room's spiked door and the full-health Challenge door.
## The kind is written on BOTH sides of the connection.
static func _apply_door_kinds(layout: Dictionary, depth: int, cfg: Dictionary) -> void:
	var locks: Dictionary = cfg.get("locks", {})
	for a in layout["order"]:
		var info: Dictionary = layout["rooms"][a]
		var t: String = info["type"]
		var kind := ""
		var cost := 0
		if locks.has(t) and depth >= int(locks[t].get("min_depth", 1)):
			kind = "locked"
			cost = int(locks[t].get("cost", 1))
		elif t == "curse":
			kind = "spiked"
		elif t == "challenge":
			kind = "challenge"
		if kind == "":
			continue
		for s in info["links"]:
			if info["doors"][s] == "secret":
				continue
			var link: Array = info["links"][s]
			info["doors"][s] = kind
			layout["rooms"][link[0]]["doors"][link[1]] = kind
			if cost > 0:
				var lc: Dictionary = info.get("lock_cost", {})
				lc[s] = cost
				info["lock_cost"] = lc
				var olc: Dictionary = layout["rooms"][link[0]].get("lock_cost", {})
				olc[link[1]] = cost
				layout["rooms"][link[0]]["lock_cost"] = olc


static func _roll_with_strata(pool: ItemPool, pool_id: String, stratum: Dictionary, ri: RandomNumberGenerator) -> String:
	var sp := "strata_" + str(stratum.get("id", ""))
	if pool.pools.has(sp) and ri.randf() < 0.25 and not pool.candidates(sp).is_empty():
		return pool.roll(sp, ri)
	return pool.roll(pool_id, ri)


static func _sorted(arr: Array) -> Array:
	var out := arr.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out
