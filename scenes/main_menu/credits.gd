extends Control
## Show who made the game and with what (see THIRD_PARTY_NOTICES.md).

@onready var _game: Node = get_node("/root/Game")


func _ready() -> void:
    var column := Ui.screen(self, get_node("/root/Settings").get_value("high_contrast"))
    column.add_child(Ui.label(tr("Credits"), Ui.TITLE_SIZE))
    column.add_child(Ui.label(Texts.of("CREDITS_TEXT"), Ui.FONT_SIZE, true))
    var back := Ui.button(tr("Back"), func() -> void: _game.go("main_menu"))
    column.add_child(back)
    back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("cancel"):
        _game.go("main_menu")
