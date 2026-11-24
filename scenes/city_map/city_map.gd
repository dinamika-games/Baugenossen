extends Control
## Show the cooperative's projects (DESIGN.md, 6 and 7): every request with its
## residents, problem, requirements, wishes and rewards, and whether it is
## locked, available, in progress, completed or needs repair. Nothing starts on
## its own: the player picks a project, or saves and stops.

const STATUS_KEYS := {
    "locked": "STATUS_LOCKED",
    "available": "STATUS_AVAILABLE",
    "in_progress": "STATUS_IN_PROGRESS",
    "completed": "STATUS_COMPLETED",
    "needs_repair": "STATUS_NEEDS_REPAIR",
}
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    if _game.session.character == null:
        _game.go("main_menu")
        return
    var content: ContentDb = _game.content
    var character: Character = _game.session.character
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    var header := Ui.hbox(24)
    header.add_child(Ui.label(tr("CITY_TITLE"), Ui.TITLE_SIZE))
    column.add_child(header)
    var level := character.level()
    (
        column
        . add_child(
            (
                Ui
                . label(
                    (
                        tr("CITY_BUILDER_SUMMARY")
                        . format(
                            {
                                "name": character.name,
                                "level": level,
                                "rank": tr(Progression.rank_key(level)),
                                "xp": character.xp,
                                "next": Progression.xp_for_level(level + 1),
                                "karma": character.karma,
                                "reputation": tr(Progression.reputation_key(character.karma)),
                            }
                        )
                    ),
                    Ui.FONT_SIZE,
                    true
                )
            )
        )
    )
    var buttons := Ui.hbox()
    buttons.add_child(
        Ui.button(tr("CITY_CHARACTER_SHEET"), func() -> void: _game.go("character_sheet"))
    )
    buttons.add_child(Ui.button(tr("MENU_SETTINGS"), _on_settings))
    buttons.add_child(Ui.button(tr("BUTTON_SAVE_AND_EXIT"), _on_save_and_exit))
    column.add_child(buttons)
    var first_button: Button = null
    for id in content.mission_order:
        var card := _mission_card(content, id)
        column.add_child(card[0])
        if first_button == null and card[1] != null:
            first_button = card[1]
    if first_button != null:
        first_button.grab_focus.call_deferred()


func _mission_card(content: ContentDb, id: String) -> Array:
    var mission := content.mission(id)
    var status: String = _game.session.mission_status(id)
    var box := Ui.vbox(6)
    var title := Ui.hbox()
    title.add_child(Ui.label(tr(mission["title_key"]), 28))
    title.add_child(Ui.label("— " + tr(STATUS_KEYS[status]), 22))
    box.add_child(title)
    box.add_child(
        Ui.label(
            tr("CITY_REQUESTED_BY").format({"names": MissionText.requesters(mission, content)}), 18
        )
    )
    box.add_child(Ui.label(tr(mission["brief_key"]), Ui.FONT_SIZE, true))
    # NOTE (mristin):
    # An open project shows how far its site is; a locked one only its needs.
    var report: MissionEvaluator.Report = null
    if status != "locked":
        report = MissionEvaluator.evaluate(mission, _game.session.open_site(id))
    var needs: Array[String] = []
    for i in range(mission["mandatory_objectives"].size()):
        needs.append(_need_line(mission["mandatory_objectives"][i], report, true, i))
    box.add_child(Ui.label(tr("CITY_NEEDS") + "\n" + "\n".join(needs), 18, true))
    var wishes: Array[String] = []
    for i in range(mission["optional_objectives"].size()):
        var objective: Dictionary = mission["optional_objectives"][i]
        var reward := MissionText.reward_text(
            int(objective.get("xp", 0)), int(objective.get("karma", 0))
        )
        wishes.append("%s (%s)" % [_need_line(objective, report, false, i), reward])
    if not wishes.is_empty():
        box.add_child(Ui.label(tr("CITY_WISHES") + "\n" + "\n".join(wishes), 18, true))
    var base := MissionText.reward_text(int(mission["base_xp"]), int(mission["base_karma"]))
    var size := {"reward": base, "placements": int(mission.get("estimated_placements", 10))}
    box.add_child(Ui.label(tr("CITY_REWARD_AND_SIZE").format(size), 18))
    var action: Button = null
    if status == "locked":
        var names: Array[String] = []
        for prerequisite in mission["prerequisite_ids"]:
            names.append(tr(content.mission(prerequisite)["title_key"]))
        box.add_child(Ui.label(tr("CITY_LOCKED_UNTIL").format({"missions": ", ".join(names)}), 18))
    else:
        var keys := {
            "available": "CITY_START",
            "in_progress": "CITY_CONTINUE",
            "completed": "CITY_REVISIT",
            "needs_repair": "CITY_REPAIR",
        }
        action = Ui.button(tr(keys[status]), _open.bind(id), 320)
        action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        box.add_child(action)
    return [Ui.panel(box), action]


func _need_line(
    objective: Dictionary, report: MissionEvaluator.Report, mandatory: bool, index: int
) -> String:
    if report == null:
        return "• " + MissionText.line(objective["text_key"], 0, MissionText.required_of(objective))
    var result: Dictionary = (report.mandatory if mandatory else report.optional)[index]
    var mark := "✓" if result["satisfied"] else ("✗" if mandatory else "○")
    return "%s %s" % [mark, MissionText.result_line(result)]


func _open(id: String) -> void:
    _game.mission_id = id
    _game.go("build_site")


func _on_settings() -> void:
    _game.return_screen = "city_map"
    _game.go("settings")


func _on_save_and_exit() -> void:
    _game.session.save()
    _game.go("main_menu")


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("cancel"):
        _on_save_and_exit()
