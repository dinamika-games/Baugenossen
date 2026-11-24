extends Control
## Show the results of a completed mission (DESIGN.md, 6 and 7): the
## residents' response, the XP and karma earned, the wishes fulfilled, the
## practice, the levels gained and the unspent points. Then the player chooses:
## save and exit, revisit the site, or choose another project. Nothing starts
## on its own.

@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    var content: ContentDb = _game.content
    var character: Character = _game.session.character
    if character == null or not content.missions.has(_game.mission_id):
        _game.go("main_menu")
        return
    var mission := content.mission(_game.mission_id)
    var summary: Dictionary = _game.last_summary
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    column.add_child(Ui.label(tr("RESULTS_TITLE"), Ui.TITLE_SIZE))
    column.add_child(Ui.label(tr(mission["title_key"]), 28))
    column.add_child(
        Ui.label(
            tr("COMPLETE_THANKS").format(
                {
                    "names": MissionText.requesters(mission, content),
                    "thanks": tr(mission["completion_dialogue_key"])
                }
            ),
            Ui.FONT_SIZE,
            true
        )
    )
    if summary.get("first", false) or int(summary.get("xp", 0)) > 0:
        column.add_child(
            Ui.label(
                MissionText.reward_text(int(summary.get("xp", 0)), int(summary.get("karma", 0))), 26
            )
        )
    else:
        column.add_child(Ui.label(tr("RESULTS_ALREADY_REWARDED"), Ui.FONT_SIZE, true))
    for wish in summary.get("wishes", []):
        for objective in mission["optional_objectives"]:
            if objective["id"] == wish:
                column.add_child(
                    Ui.label(
                        (
                            "★ "
                            + MissionText.line(
                                objective["text_key"], 0, MissionText.required_of(objective)
                            )
                        ),
                        18
                    )
                )
    var practised: Array = summary.get("practice", [])
    if not practised.is_empty():
        var names: Array[String] = []
        for skill_id in practised:
            names.append(tr(content.skills[skill_id]["name_key"]))
        column.add_child(
            Ui.label(tr("RESULTS_PRACTICE").format({"skills": ", ".join(names)}), 18, true)
        )
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.play("level_up" if int(summary.get("levels", 0)) > 0 else "reward")
    if int(summary.get("levels", 0)) > 0:
        column.add_child(
            Ui.label(
                tr("RESULTS_LEVEL_UP").format(
                    {
                        "level": character.level(),
                        "rank": tr(Progression.rank_key(character.level()))
                    }
                ),
                24
            )
        )
    (
        column
        . add_child(
            (
                Ui
                . label(
                    (
                        tr("RESULTS_UNSPENT")
                        . format(
                            {
                                "skill_points": character.skill_points,
                                "perk_tokens": character.perk_tokens,
                                "attribute_points": character.attribute_points,
                            }
                        )
                    ),
                    18,
                    true
                )
            )
        )
    )
    if not summary.get("saved", true):
        var warning := Ui.label(tr("SAVE_ERROR_WRITE"), 18, true)
        warning.add_theme_color_override("font_color", Ui.BAD_COLOUR)
        column.add_child(warning)
    var buttons := Ui.hbox()
    var next := Ui.button(tr("RESULTS_ANOTHER_PROJECT"), func() -> void: _game.go("city_map"), 280)
    buttons.add_child(next)
    buttons.add_child(Ui.button(tr("RESULTS_REVISIT"), func() -> void: _game.go("build_site"), 240))
    buttons.add_child(
        Ui.button(tr("CITY_CHARACTER_SHEET"), func() -> void: _game.go("character_sheet"), 240)
    )
    buttons.add_child(Ui.button(tr("BUTTON_SAVE_AND_EXIT"), _save_and_exit, 240))
    column.add_child(buttons)
    next.grab_focus.call_deferred()


func _save_and_exit() -> void:
    _game.session.save()
    _game.go("main_menu")
