class_name ShotSpec
extends RefCounted
## Builds the player's projectile spec from stats + projectile modifiers (DESIGN.md §6.5).
## Modifiers are applied in fixed PRIORITY order (never pickup order) so every combination is
## deterministic and composes generically. No item pairs are special-cased.

const PRIORITY: Dictionary = {
	"size": 0, "element": 10, "spectral": 20, "pierce": 30, "homing": 40, "bounce": 50, "split": 60,
}
const SPEED_UNIT := 190.0   # px/s per 1.0 shot speed
const BASE_RADIUS := 3.0
const HOMING_CAP := 4.0
const MAX_SPLIT_DEPTH := 2


static func build(stats: Dictionary, mods: Array, tints: Array = []) -> Dictionary:
	var spec := {
		"damage": float(stats.get("damage", 3.5)),
		"speed": float(stats.get("shot_speed", 1.0)) * SPEED_UNIT,
		"range": float(stats.get("range", 150.0)),
		"radius": BASE_RADIUS,
		"pierce": 0,          # -1 = infinite
		"bounce": 0,
		"homing": 0.0,        # rad/s turn rate
		"split_count": 0,
		"split_mult": 0.0,
		"split_depth": 0,
		"spectral": false,
		"elements": [],
		"color": Color(1.0, 0.72, 0.12),
		"stretch": 1.0,
	}
	var sorted := mods.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = PRIORITY.get(a.get("modifier", ""), 99)
		var pb: int = PRIORITY.get(b.get("modifier", ""), 99)
		if pa != pb:
			return pa < pb
		return str(a.get("source", "")) < str(b.get("source", "")))
	for m in sorted:
		var p: Dictionary = m.get("params", {})
		match str(m.get("modifier", "")):
			"size":
				spec["radius"] *= float(p.get("mult", 1.5))
				spec["damage"] *= float(p.get("damage_mult", 1.0))
			"element":
				var el: String = p.get("element", "")
				if el != "" and not spec["elements"].has(el):
					spec["elements"].append(el)
			"spectral":
				spec["spectral"] = true
			"pierce":
				var c: int = int(p.get("count", -1))
				if c < 0 or spec["pierce"] < 0:
					spec["pierce"] = -1
				else:
					spec["pierce"] += c
				spec["stretch"] = maxf(spec["stretch"], 1.5)
			"homing":
				spec["homing"] = minf(spec["homing"] + float(p.get("strength", 1.0)), HOMING_CAP)
			"bounce":
				spec["bounce"] += int(p.get("count", 1))
			"split":
				spec["split_count"] = maxi(spec["split_count"], int(p.get("count", 2)))
				spec["split_mult"] = maxf(spec["split_mult"], float(p.get("damage_mult", 0.4)))
				spec["split_depth"] = mini(maxi(spec["split_depth"], int(p.get("depth", 1))), MAX_SPLIT_DEPTH)
			_:
				push_warning("ShotSpec: unknown modifier '%s'" % m.get("modifier", ""))
	# Visual composition: item tints nudge the base amber but never replace it (player shots stay
	# amber-family for readability, DESIGN.md §7.1); the strongest tints show in the trail/outline.
	if not tints.is_empty():
		var avg := Color(0, 0, 0, 0)
		for t in tints:
			avg += t
		avg /= float(tints.size())
		spec["color"] = (spec["color"] as Color).lerp(avg, minf(0.45, 0.15 * tints.size()))
	spec["tint_count"] = tints.size()
	return spec


## A child shot created by `split`: inherits everything except one level of split.
static func child_of(spec: Dictionary) -> Dictionary:
	var c := spec.duplicate(true)
	c["damage"] = float(spec["damage"]) * float(spec["split_mult"])
	c["split_depth"] = int(spec["split_depth"]) - 1
	if c["split_depth"] <= 0:
		c["split_count"] = 0
	c["radius"] = maxf(1.5, float(spec["radius"]) * 0.7)
	c["range"] = float(spec["range"]) * 0.5
	return c
