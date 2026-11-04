extends Node
## Platform wrapper (DESIGN.md §16.11). All Steam calls go through here so the game runs without
## Steam during development. GodotSteam is integrated in Milestone 8; until then every call is a
## logged no-op.

var steam_available: bool = false
var _steam: Object = null


func _ready() -> void:
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
		# M8: call steamInitEx(app_id) here and set steam_available from the result.
		steam_available = false


func unlock_achievement(api_name: String) -> void:
	if steam_available and _steam:
		_steam.call("setAchievement", api_name)
		_steam.call("storeStats")
	else:
		_log("achievement %s" % api_name)


func set_stat(api_name: String, value: int) -> void:
	if steam_available and _steam:
		_steam.call("setStatInt", api_name, value)
	else:
		_log("stat %s=%d" % [api_name, value])


func upload_leaderboard_score(board: String, score: int) -> void:
	_log("leaderboard %s <- %d" % [board, score])


func set_rich_presence(key: String, value: String) -> void:
	if steam_available and _steam:
		_steam.call("setRichPresence", key, value)


func cloud_enabled() -> bool:
	return steam_available


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print_verbose("[Platform:stub] ", msg)
