extends Control
## Main menu (Milestone 0). Controller-navigable: first button gets focus, B/Esc backs out.
## All strings are translation keys (translations/strings.csv).

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _seed_edit: LineEdit = %SeedEdit
@onready var _seed_status: Label = %SeedStatus
@onready var _descend: Button = %Descend
@onready var _quit: Button = %Quit
@onready var _version: Label = %Version
@onready var _icon: TextureRect = %WaspIcon


func _ready() -> void:
	GameState.mode = GameState.Mode.MENU
	_title.text = tr("GAME_TITLE")
	_subtitle.text = tr("GAME_TAGLINE")
	_descend.text = tr("MENU_DESCEND")
	_quit.text = tr("MENU_QUIT")
	_seed_edit.placeholder_text = tr("MENU_SEED_PLACEHOLDER")
	_version.text = "v%s  ·  Pulp %d  ·  Brood %d" % [ProjectSettings.get_setting("application/config/version"), MetaSave.data.get("pulp", 0), MetaSave.data["brood"].get("lost_rescued", 0)]
	_icon.texture = Art.texture("player", "worker")
	_descend.pressed.connect(_on_descend)
	_quit.pressed.connect(GameState.quit)
	_seed_edit.text_changed.connect(_on_seed_changed)
	_on_seed_changed("")
	# Dev builds: the room editor (DESIGN.md §10.4).
	if OS.is_debug_build():
		var ed := Button.new()
		ed.text = tr("MENU_EDITOR")
		ed.add_theme_font_size_override("font_size", 8)
		ed.custom_minimum_size = Vector2(160, 0)
		ed.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ed.pressed.connect(func() -> void: GameState.goto_scene("room_editor"))
		_quit.get_parent().add_child(ed)
		_quit.get_parent().move_child(ed, _quit.get_index())
	GameState.room_test_template = ""
	_descend.grab_focus()


func _on_seed_changed(text: String) -> void:
	if text.strip_edges() == "":
		_seed_status.text = tr("MENU_SEED_RANDOM")
		return
	var s := RNG.string_to_seed(text)
	_seed_status.text = tr("MENU_SEED_OK") % RNG.seed_to_string(s) if s >= 0 else tr("MENU_SEED_BAD")


func _on_descend() -> void:
	var s := RNG.string_to_seed(_seed_edit.text)
	if s < 0:
		s = RNG.random_seed()
	RunState.start_new(s)
	GameState.goto_scene("run")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _seed_edit.has_focus():
		_descend.grab_focus()
		get_viewport().set_input_as_handled()
