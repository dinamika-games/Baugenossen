extends Control
## Show the main menu: continue, new game, credits and quit, and the language.

var _message: Label
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_theme_constant_override("separation", Ui.BUTTON_GAP / 2)
    for title in [Ui.label("Baugenossen", 60), Ui.label(tr("A City Built Together"), 26)]:
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        column.add_child(title)
    var has_save: bool = _game.session.has_save()
    var continue_button := BoardButton.create(tr("Continue"), _on_continue, has_save)
    continue_button.disabled = not has_save
    column.add_child(continue_button)
    var new_game := BoardButton.create(tr("New game"), _on_new_game, not has_save)
    column.add_child(new_game)
    column.add_child(BoardButton.create(tr("Credits"), _on_credits))
    column.add_child(BoardButton.create(tr("Quit"), _on_quit))
    var languages := get_node_or_null("/root/Languages")
    if languages != null and languages.codes().size() > 1:
        var chooser := Chooser.create(
            languages.names(), languages.codes().find(languages.current()), 300
        )
        chooser.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        chooser.changed.connect(_on_language)
        column.add_child(chooser)
    _message = Ui.label("", Ui.FONT_SIZE, true)
    column.add_child(_message)
    (continue_button if has_save else new_game).grab_focus.call_deferred()


func _on_continue() -> void:
    if _game.session.continue_game():
        if _game.session.load_message != "":
            _message.text = Texts.of(_game.session.load_message)
        _game.go("city_map")
    else:
        _message.text = Texts.of(
            _game.session.load_message if _game.session.load_message != "" else "SAVE_ERROR_CORRUPT"
        )


## Switch the language and show the menu again in it.
func _on_language(index: int) -> void:
    var languages: Node = get_node("/root/Languages")
    languages.choose(languages.codes()[index])
    _game.go("main_menu")


func _on_credits() -> void:
    _game.go("credits")


func _on_quit() -> void:
    _game.quit()


func _on_new_game() -> void:
    _game.session.new_game()
    _game.session.save()
    _game.go("city_map")
