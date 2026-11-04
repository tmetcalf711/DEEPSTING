extends Node
## Seeded RNG with independent named streams (DESIGN.md §16.3).
##
## Gameplay code must NEVER call global randf()/randi(). Use:
##     RNG.stream("map").randi_range(0, 3)
## Streams are derived from (run_seed, stream_name, floor_index), so consuming numbers in one
## stream never shifts another. Use RNG.room_stream(...) for per-room enemy rolls so visiting
## rooms in a different order does not change what spawns.

const STREAMS: PackedStringArray = ["map", "rooms", "items", "enemies", "drops", "fx", "misc"]
## 32 symbols, no ambiguous 0/O or 1/I.
const SEED_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var run_seed: int = 0
var floor_index: int = 0
var _streams: Dictionary = {}  # key "name@floor" -> RandomNumberGenerator


func _ready() -> void:
	set_run_seed(random_seed())


## A fresh, non-deterministic seed (only used to pick a seed for a new random run).
func random_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi() & 0xFFFFFFFF


func set_run_seed(value: int) -> void:
	run_seed = value & 0xFFFFFFFF
	floor_index = 0
	_streams.clear()


func set_floor(index: int) -> void:
	floor_index = index


## Returns the stream for the current floor (or an explicit floor). Created lazily.
func stream(stream_name: String, for_floor: int = -1) -> RandomNumberGenerator:
	assert(STREAMS.has(stream_name), "Unknown RNG stream: %s" % stream_name)
	var f: int = floor_index if for_floor < 0 else for_floor
	var key := "%s@%d" % [stream_name, f]
	if not _streams.has(key):
		var r := RandomNumberGenerator.new()
		r.seed = derive_seed(run_seed, stream_name, f)
		_streams[key] = r
	return _streams[key]


## A one-off generator for a specific room. Not cached: callers keep it for the room's lifetime.
func room_stream(stream_name: String, room_index: int, for_floor: int = -1) -> RandomNumberGenerator:
	var f: int = floor_index if for_floor < 0 else for_floor
	var r := RandomNumberGenerator.new()
	r.seed = derive_seed(run_seed, "%s#room%d" % [stream_name, room_index], f)
	return r


## Deterministic, engine-version-independent seed derivation (FNV-1a 64-bit).
static func derive_seed(base_seed: int, salt: String, salt_index: int) -> int:
	var text := "%d|%s|%d" % [base_seed, salt, salt_index]
	return fnv1a64(text.to_utf8_buffer())


static func fnv1a64(bytes: PackedByteArray) -> int:
	# 64-bit FNV-1a. GDScript ints are signed 64-bit and multiplication wraps, which is what we want.
	var h: int = -3750763034362895579  # 0xcbf29ce484222325 as signed
	const PRIME: int = 1099511628211  # 0x100000001b3
	for b in bytes:
		h = h ^ b
		h = h * PRIME
	return h


# --- Seed <-> display string ("XXXX XXXX") ---

static func seed_to_string(value: int) -> String:
	var v: int = value & 0xFFFFFFFF
	var chars := ""
	# 8 symbols * 5 bits = 40 bits; the top 8 bits carry a checksum so typos are detectable.
	var check: int = _checksum(v)
	var packed: int = (check << 32) | v
	for i in 8:
		var shift: int = (7 - i) * 5
		chars += SEED_ALPHABET[(packed >> shift) & 31]
	return chars.substr(0, 4) + " " + chars.substr(4, 4)


## Returns the seed, or -1 if the string is malformed or fails its checksum.
static func string_to_seed(text: String) -> int:
	var clean := text.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if clean.length() != 8:
		return -1
	var packed: int = 0
	for ch in clean:
		var idx: int = SEED_ALPHABET.find(ch)
		if idx < 0:
			return -1
		packed = (packed << 5) | idx
	var v: int = packed & 0xFFFFFFFF
	var check: int = (packed >> 32) & 0xFF
	if check != _checksum(v):
		return -1
	return v


static func _checksum(v: int) -> int:
	var c: int = 0x5A
	for i in 4:
		c = ((c * 31) + ((v >> (i * 8)) & 0xFF)) & 0xFF
	return c


## Daily Run seed for a UTC date string "YYYYMMDD".
static func daily_seed(yyyymmdd: String) -> int:
	return fnv1a64(("DEEPSTING-" + yyyymmdd).to_utf8_buffer()) & 0xFFFFFFFF


## Weighted pick from parallel arrays. Returns index or -1 when total weight is 0.
static func weighted_index(r: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var roll := r.randf() * total
	for i in weights.size():
		roll -= maxf(0.0, float(weights[i]))
		if roll < 0.0:
			return i
	return weights.size() - 1


## Deterministic in-place Fisher-Yates shuffle (Array.shuffle() uses the global RNG).
static func shuffle(r: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
