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
	var style: Array = PLACEHOLDER_STYLE.get(category, ["square", 16, Color.MAGENTA])
	var shape: String = style[0]
	var size: int = style[1]
	var base: Color = style[2]
	var h := absi(RNGScript.fnv1a64(id.to_utf8_buffer())) % 1000
	var tint := base
	tint.h = fposmod(base.h + (float(h) / 1000.0 - 0.5) * 0.25, 1.0)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := tint.darkened(0.6)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var dx := (x - c) / maxf(c, 0.5)
			var dy := (y - c) / maxf(c, 0.5)
			var inside := false
			match shape:
				"circle", "blob":
					inside = dx * dx + dy * dy <= 1.0
				"gem":
					inside = absf(dx) + absf(dy) <= 1.0
				"wasp":
					# body ellipse + stripes, wings as lighter lobes
					inside = (dx * dx) / 0.35 + dy * dy <= 1.0
				_:
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
			if edge or (shape != "square" and _near_edge(shape, dx, dy, c)):
				col = outline
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


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
