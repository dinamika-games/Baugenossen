extends Control
## Show the main menu: new game, continue, settings, credits and quit.

var _message: Label
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_child(Ui.label("Baugenossen", 64))
    column.add_child(Ui.label(tr("GAME_SUBTITLE"), 28))
    column.add_child(Control.new())
    var has_save: bool = _game.session.has_save()
    var continue_button := Ui.button(tr("MENU_CONTINUE"), _on_continue, 320)
    continue_button.disabled = not has_save
    column.add_child(continue_button)
    column.add_child(Ui.button(tr("MENU_NEW_GAME"), _on_new_game, 320))
    column.add_child(Ui.button(tr("MENU_SETTINGS"), _on_settings, 320))
    column.add_child(Ui.button(tr("MENU_CREDITS"), func() -> void: _game.go("credits"), 320))
    column.add_child(Ui.button(tr("MENU_QUIT"), func() -> void: _game.quit(), 320))
    _message = Ui.label("", Ui.FONT_SIZE, true)
    column.add_child(_message)
    (continue_button if has_save else column.get_child(4)).grab_focus.call_deferred()


func _on_continue() -> void:
    if _game.session.continue_game():
        if _game.session.load_message != "":
            _message.text = tr(_game.session.load_message)
        _game.go("city_map")
    else:
        _message.text = tr(
            _game.session.load_message if _game.session.load_message != "" else "SAVE_ERROR_CORRUPT"
        )


func _on_new_game() -> void:
    _game.go("character_creation")


func _on_settings() -> void:
    _game.return_screen = "main_menu"
    _game.go("settings")
