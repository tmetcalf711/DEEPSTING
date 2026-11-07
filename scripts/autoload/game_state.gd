extends Node
## App-level state machine and settings application (DESIGN.md §16.2).

enum Mode { BOOT, MENU, HIVE, RUN, PAUSED }

const SCENES: Dictionary = {
	"main_menu": "res://scenes/ui/main_menu.tscn",
	"run": "res://scenes/run/run.tscn",
	# M5: "hive": "res://scenes/hive/hive.tscn",
}

var mode: Mode = Mode.BOOT
## Dev flag toggled by the console's `god` command; gameplay systems read it from M1 on.
var god_mode: bool = false
## Set by the room editor's Test button: the next run builds just this template (empty = normal run).
var room_test_template: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_settings()
	Events.settings_changed.connect(apply_settings)


func apply_settings() -> void:
	var s: Dictionary = MetaSave.settings
	InputBindings.apply(s.get("controls", {}).get("bindings", {}))
	var video: Dictionary = s.get("video", {})
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if video.get("fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if video.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	TranslationServer.set_locale(str(s.get("locale", "en")))


func goto_scene(key: String) -> void:
	var path: String = SCENES.get(key, key)
	Events.scene_change_requested.emit(path)
	get_tree().call_deferred("change_scene_to_file", path)


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	mode = Mode.PAUSED if paused else Mode.RUN
	Events.game_paused.emit(paused)


func aim_mode() -> String:
	return str(MetaSave.settings.get("controls", {}).get("aim_mode", "free"))


func screen_shake_scale() -> float:
	return float(MetaSave.settings.get("accessibility", {}).get("screen_shake", 1.0))


## Brief freeze-frame for impact (toggleable in accessibility settings).
func hitstop(duration: float = 0.045) -> void:
	if not bool(MetaSave.settings.get("accessibility", {}).get("hit_stop", true)):
		return
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func quit() -> void:
	get_tree().quit()
