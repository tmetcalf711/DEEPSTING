extends Node
## Art resolver (DESIGN.md §16.5). Every sprite lives at
##     res://assets/sprites/<category>/<id>.png
## If the PNG is missing, a procedural placeholder is generated: a silhouette chosen by category
## with a hue derived from the id. Replacing art = dropping in a PNG with the same name.

const SPRITE_ROOT := "res://assets/sprites"
const RNGScript := preload("res://scripts/autoload/rng.gd")

## category -> [shape, size_px, base_color]
const PLACEHOLDER_STYLE: Dictionary = {
	"player": ["wasp", 16, Color(0.98, 0.78, 0.15)],
	"enemies": ["blob", 16, Color(0.55, 0.85, 0.3)],
	"bosses": ["blob", 48, Color(0.75, 0.3, 0.6)],
	"items": ["gem", 16, Color(0.4, 0.8, 1.0)],
	"pickups": ["circle", 8, Color(1.0, 0.9, 0.5)],
	"projectiles": ["circle", 6, Color(1.0, 0.7, 0.1)],
	"tiles": ["square", 16, Color(0.35, 0.27, 0.2)],
	"props": ["square", 16, Color(0.5, 0.4, 0.3)],
	"ui": ["square", 16, Color(0.9, 0.9, 0.9)],
	"brood": ["circle", 10, Color(1.0, 0.95, 0.8)],
	"workers": ["wasp", 8, Color(0.95, 0.75, 0.2)],
	"fx": ["circle", 8, Color(1, 1, 1)],
}

## Per-id overrides ("category/id" -> [shape, size_px, color]) so placeholder silhouettes read
## clearly before real art exists. Real PNGs always win.
const ID_STYLE: Dictionary = {
	"ui/heart_full": ["heart", 9, Color(0.86, 0.12, 0.18)],
	"ui/heart_half": ["heart_half", 9, Color(0.86, 0.12, 0.18)],
	"ui/heart_empty": ["heart_empty", 9, Color(0.86, 0.12, 0.18)],
	"ui/chitin": ["heart", 9, Color(0.55, 0.62, 0.78)],
	"ui/chitin_half": ["heart_half", 9, Color(0.55, 0.62, 0.78)],
	"ui/toxic_chitin": ["heart", 9, Color(0.2, 0.42, 0.15)],
	"ui/toxic_chitin_half": ["heart_half", 9, Color(0.2, 0.42, 0.15)],
	"ui/mana": ["gem", 9, Color(0.35, 0.9, 1.0)],
	"ui/dig_charge": ["circle", 9, Color(0.35, 0.3, 0.28)],
	"ui/royal_jelly": ["circle", 9, Color(0.98, 0.93, 0.6)],
	"ui/stash": ["square", 9, Color(0.78, 0.64, 0.42)],
	"pickups/mana_chip": ["gem", 6, Color(0.35, 0.9, 1.0)],
	"pickups/mana_fragment": ["gem", 8, Color(0.45, 0.7, 1.0)],
	"pickups/mana_chunk": ["gem", 10, Color(0.6, 0.5, 1.0)],
	"pickups/mana_crystal": ["gem", 12, Color(0.85, 0.45, 1.0)],
	"pickups/heart_half": ["heart_half", 9, Color(0.86, 0.12, 0.18)],
	"pickups/heart_full": ["heart", 9, Color(0.86, 0.12, 0.18)],
	"pickups/chitin": ["heart", 9, Color(0.55, 0.62, 0.78)],
	"pickups/toxic_chitin": ["heart", 9, Color(0.2, 0.42, 0.15)],
	"pickups/dig_charge": ["circle", 9, Color(0.3, 0.26, 0.24)],
	"pickups/royal_jelly": ["circle", 8, Color(0.98, 0.93, 0.6)],
	"props/rock": ["rock", 16, Color(0.47, 0.4, 0.33)],
	"props/tinted_rock": ["rock", 16, Color(0.42, 0.45, 0.62)],
	"props/block": ["square", 16, Color(0.3, 0.25, 0.2)],
	"props/brood_cell": ["hex", 14, Color(0.93, 0.84, 0.58)],
	"props/deposit": ["rock", 10, Color(0.78, 0.64, 0.42)],
	"props/pedestal": ["square", 12, Color(0.55, 0.47, 0.38)],
	"props/trapdoor": ["square", 16, Color(0.12, 0.09, 0.07)],
	"props/dig_charge": ["circle", 10, Color(0.3, 0.26, 0.24)],
	"brood/larva": ["circle", 7, Color(1.0, 0.96, 0.85)],
	"player/overlay_gnome_hat": ["triangle", 8, Color(0.85, 0.12, 0.12)],
}

var _cache: Dictionary = {}


func texture(category: String, id: String) -> Texture2D:
	var key := category + "/" + id
	if _cache.has(key):
		return _cache[key]
	var path := "%s/%s/%s.png" % [SPRITE_ROOT, category, id]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		tex = placeholder(category, id)
	_cache[key] = tex
	return tex


func has_real_art(category: String, id: String) -> bool:
	return ResourceLoader.exists("%s/%s/%s.png" % [SPRITE_ROOT, category, id])


func clear_cache() -> void:
	_cache.clear()


## Builds a placeholder texture. Deterministic per (category, id).
static func placeholder(category: String, id: String) -> ImageTexture:
	var style: Array = ID_STYLE.get(category + "/" + id, PLACEHOLDER_STYLE.get(category, ["square", 16, Color.MAGENTA]))
	var shape: String = style[0]
	var size: int = style[1]
	var base: Color = style[2]
	var h := absi(RNGScript.fnv1a64(id.to_utf8_buffer())) % 1000
	var tint := base
	if not ID_STYLE.has(category + "/" + id):
		tint.h = fposmod(base.h + (float(h) / 1000.0 - 0.5) * 0.25, 1.0)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := tint.darkened(0.6)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var dx := (x - c) / maxf(c, 0.5)
			var dy := (y - c) / maxf(c, 0.5)
			var inside := _inside(shape, dx, dy, h)
			match shape:
				"circle", "blob":
					inside = dx * dx + dy * dy <= 1.0
				"gem":
					inside = absf(dx) + absf(dy) <= 1.0
				"wasp":
					# body ellipse + stripes, wings as lighter lobes
					inside = (dx * dx) / 0.35 + dy * dy <= 1.0
				"square":
					inside = true
			if not inside:
				continue
			var col := tint
			if shape == "wasp" and int((dy + 1.0) * 3.0) % 2 == 1:
				col = Color(0.1, 0.08, 0.05)
			var edge := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					edge = true
			if shape == "heart_empty":
				col = Color(0.15, 0.1, 0.1)
			if edge or (shape != "square" and _near_edge(shape, dx, dy, c)) or (shape in ["heart", "heart_half", "heart_empty", "rock", "hex", "triangle"] and _is_border(shape, x, y, size, c, h)):
				col = outline
			if shape == "heart_half" and dx > 0.05:
				col = Color(0.15, 0.1, 0.1) if not _is_border(shape, x, y, size, c, h) else outline
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _inside(shape: String, dx: float, dy: float, h: int) -> bool:
	match shape:
		"heart", "heart_half", "heart_empty":
			# Two lobes + a point.
			var l1 := Vector2(dx + 0.45, dy + 0.3).length() <= 0.55
			var l2 := Vector2(dx - 0.45, dy + 0.3).length() <= 0.55
			var tri := dy >= -0.3 and absf(dx) <= (1.0 - dy) * 0.62 and dy <= 0.95
			return l1 or l2 or tri
		"rock":
			var wob := 0.82 + 0.12 * sin(atan2(dy, dx) * 3.0 + float(h % 7))
			return dx * dx + dy * dy * 1.25 <= wob * wob
		"hex":
			return absf(dy) <= 0.9 and absf(dx) * 0.87 + absf(dy) * 0.5 <= 0.9
		"triangle":
			return dy >= -0.9 and dy <= 0.8 and absf(dx) <= (dy + 0.9) * 0.55
	return false


static func _is_border(shape: String, x: int, y: int, size: int, c: float, h: int) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + o.x
		var ny: int = y + o.y
		if nx < 0 or ny < 0 or nx >= size or ny >= size:
			return true
		if not _inside(shape, (nx - c) / maxf(c, 0.5), (ny - c) / maxf(c, 0.5), h):
			return true
	return false


static func _near_edge(shape: String, dx: float, dy: float, c: float) -> bool:
	var px := 1.0 / maxf(c, 0.5)
	match shape:
		"circle", "blob":
			return dx * dx + dy * dy > (1.0 - px) * (1.0 - px)
		"gem":
			return absf(dx) + absf(dy) > 1.0 - px
		"wasp":
			return (dx * dx) / 0.35 + dy * dy > (1.0 - px * 1.5) * (1.0 - px * 1.5)
	return false
