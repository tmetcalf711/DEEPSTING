class_name Difficulty
extends RefCounted
## The difficulty curve (DESIGN.md §17 M4), all from data/config/difficulty.json. Depth is the
## 1-based floor number. Pure static helpers so tests can check the curve directly.


static func cfg() -> Dictionary:
	return Content.get_entry("config", "difficulty")


## Enemy HP multiplier: +hp_per_depth per floor below the first (bosses scale at boss_hp_factor of that).
static func hp_mult(depth: int, boss: bool) -> float:
	var per: float = float(cfg().get("hp_per_depth", 0.1)) * (float(cfg().get("boss_hp_factor", 0.5)) if boss else 1.0)
	return 1.0 + per * maxi(0, depth - 1)


static func bullet_speed_mult(depth: int) -> float:
	return 1.0 + float(cfg().get("bullet_speed_per_depth", 0.03)) * maxi(0, depth - 1)


## Half-hearts per enemy hit: half a heart early, a full heart from `full_heart_from_depth` on.
static func hit_damage(depth: int) -> int:
	return 2 if depth >= int(cfg().get("full_heart_from_depth", 7)) else 1


static func champion_chance(depth: int, curse_effect: String = "") -> float:
	var c: float = float(cfg().get("champion_base", 0.05)) + float(cfg().get("champion_per_depth", 0.01)) * maxi(0, depth - 1)
	if curse_effect == "champions":
		c += float(cfg().get("spore_bloom_bonus", 0.15))
	return minf(c, float(cfg().get("champion_cap", 0.4)))


## Hardest room-template difficulty allowed at a depth (1..3).
static func max_template_difficulty(depth: int) -> int:
	var bands: Array = cfg().get("template_difficulty_by_depth", [1, 1, 2, 2, 2, 3, 3, 3])
	return int(bands[clampi(depth - 1, 0, bands.size() - 1)])


static func depth() -> int:
	return RunState.floor_index + 1
