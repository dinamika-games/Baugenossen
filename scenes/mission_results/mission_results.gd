extends Control
## Show the results of a completed mission (DESIGN.md, 6 and 7): the
## residents' response and the wishes fulfilled. Then the player chooses:
## save and exit, revisit the site, or choose another project. Nothing starts
## on its own.

@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    var content: ContentDb = _game.content
    if _game.session.progress == null or not content.missions.has(_game.mission_id):
        _game.go("main_menu")
        return
    var mission := content.mission(_game.mission_id)
    var summary: Dictionary = _game.last_summary
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    column.add_child(Ui.label(tr("Well built!"), Ui.TITLE_SIZE))
    column.add_child(Ui.label(tr(mission["title"]), 28))
    column.add_child(
        Ui.label(
            Grammar.format(
                tr("{names}: “{thanks}”"),
                {"names": MissionText.requesters(mission, content), "thanks": tr(mission["thanks"])}
            ),
            Ui.FONT_SIZE,
            true
        )
    )
    for wish in summary.get("wishes", []):
        for objective in mission["optional_objectives"]:
            if objective["id"] == wish:
                column.add_child(
                    Ui.label(
                        (
                            "★ "
                            + MissionText.line(
                                objective["text"], 0, MissionText.required_of(objective)
                            )
                        ),
                        18
                    )
                )
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.play("reward")
    if not summary.get("saved", true):
        var warning := Ui.label(Texts.of("SAVE_ERROR_WRITE"), 18, true)
        warning.add_theme_color_override("font_color", Ui.BAD_COLOUR)
        column.add_child(warning)
    var buttons := Ui.hbox(Ui.BUTTON_GAP)
    var next := Ui.button(tr("Choose another project"), func() -> void: _game.go("city_map"), 280)
    buttons.add_child(next)
    buttons.add_child(
        Ui.button(tr("Back to this site"), func() -> void: _game.go("build_site"), 240)
    )
    buttons.add_child(Ui.button(tr("Save and exit"), _save_and_exit, 240))
    column.add_child(buttons)
    next.grab_focus.call_deferred()


func _save_and_exit() -> void:
    _game.session.save()
    _game.go("main_menu")
