extends Control
## Show the builder (DESIGN.md, 4 and 7): the attributes, the skills with their
## ranks, the background, the traits, the perks, the XP to the next level and
## the karma; spend the earned points and tokens; and explain every locked part
## and perk.

var _content: ContentDb
var _character: Character
var _column: VBoxContainer
var _message: Label
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    _content = _game.content
    _character = _game.session.character
    if _character == null:
        _game.go("main_menu")
        return
    _column = Ui.screen(self, _settings.get_value("high_contrast"))
    _rebuild()


func _rebuild() -> void:
    for child in _column.get_children():
        child.queue_free()
    var level := _character.level()
    _column.add_child(Ui.label(_character.name, Ui.TITLE_SIZE))
    var traits: Array[String] = []
    for id in _character.traits:
        traits.append(tr(_content.traits[id]["name_key"]))
    (
        _column
        . add_child(
            (
                Ui
                . label(
                    (
                        tr("SHEET_SUMMARY")
                        . format(
                            {
                                "pronouns": _character.pronouns,
                                "background":
                                tr(_content.backgrounds[_character.background_id]["name_key"]),
                                "traits": ", ".join(traits) if not traits.is_empty() else "—",
                                "level": level,
                                "rank": tr(Progression.rank_key(level)),
                                "xp": _character.xp,
                                "next": Progression.xp_for_level(level + 1),
                                "karma": _character.karma,
                                "reputation": tr(Progression.reputation_key(_character.karma)),
                                "capacity": Progression.crane_capacity(_character),
                            }
                        )
                    ),
                    Ui.FONT_SIZE,
                    true
                )
            )
        )
    )
    (
        _column
        . add_child(
            (
                Ui
                . label(
                    (
                        tr("RESULTS_UNSPENT")
                        . format(
                            {
                                "skill_points": _character.skill_points,
                                "perk_tokens": _character.perk_tokens,
                                "attribute_points": _character.attribute_points,
                            }
                        )
                    ),
                    20,
                    true
                )
            )
        )
    )
    _message = Ui.label("", 18, true)
    _column.add_child(_message)
    var columns := Ui.hbox(40)
    _column.add_child(columns)
    columns.add_child(_attributes_box())
    columns.add_child(_skills_box())
    _column.add_child(_perks_box())
    _column.add_child(_locked_box())
    var back := Ui.button(tr("BUTTON_BACK"), _back)
    _column.add_child(back)
    back.grab_focus.call_deferred()


func _attributes_box() -> VBoxContainer:
    var box := Ui.vbox(6)
    box.add_child(Ui.label(tr("CREATE_ATTRIBUTES"), 24))
    for attribute in _content.attributes:
        var row := Ui.hbox()
        var id := str(attribute["id"])
        row.add_child(Ui.label("%s %d" % [tr(attribute["name_key"]), _character.attribute(id)]))
        if _character.attribute_points > 0 and _character.attribute(id) < _content.attribute_max:
            row.add_child(Ui.button("+", _raise.bind(id), 52))
        box.add_child(row)
    return box


func _skills_box() -> VBoxContainer:
    var box := Ui.vbox(4)
    box.add_child(Ui.label(tr("CREATE_SKILLS"), 24))
    for id in _content.skill_order:
        var value := Progression.skill(_character, id, _content)
        var row := Ui.hbox(8)
        (
            row
            . add_child(
                (
                    Ui
                    . label(
                        (
                            tr("SHEET_SKILL_LINE")
                            . format(
                                {
                                    "name": tr(_content.skills[id]["name_key"]),
                                    "value": value,
                                    "rank": tr(Progression.skill_rank_key(value, _content)),
                                }
                            )
                        ),
                        18
                    )
                )
            )
        )
        if _character.skill_points > 0 and value < Progression.SKILL_CAP:
            row.add_child(Ui.button("+1", _invest.bind(id, 1), 60))
            if _character.skill_points >= 5 and value + 5 <= Progression.SKILL_CAP:
                row.add_child(Ui.button("+5", _invest.bind(id, 5), 60))
        box.add_child(row)
    return box


func _perks_box() -> VBoxContainer:
    var box := Ui.vbox(4)
    box.add_child(Ui.label(tr("SHEET_PERKS"), 24))
    for id in _content.perk_order:
        var perk: Dictionary = _content.perks[id]
        var row := Ui.hbox(8)
        var owned := id in _character.perks
        var problem := Progression.perk_problem(_character, id, _content)
        var state := (
            tr("PERK_OWNED") if owned else tr(problem) if problem != "" else tr("PERK_AVAILABLE")
        )
        row.add_child(
            Ui.label(
                "%s — %s (%s)" % [tr(perk["name_key"]), tr(perk["description_key"]), state],
                17,
                true
            )
        )
        if problem == "":
            row.add_child(Ui.button(tr("PERK_BUY"), _buy.bind(id), 120))
        box.add_child(row)
    return box


func _locked_box() -> VBoxContainer:
    var box := Ui.vbox(4)
    box.add_child(Ui.label(tr("SHEET_UNLOCKS"), 24))
    for id in _content.part_order:
        var definition := _content.part(id)
        if definition.requirements.is_empty():
            continue
        var missing := Progression.missing_requirements(
            definition.requirements, _character, _content
        )
        var text := tr(definition.name_key) + ": "
        if missing.is_empty():
            text += tr("SHEET_UNLOCKED")
        else:
            var needs: Array[String] = []
            for requirement in missing:
                (
                    needs
                    . append(
                        (
                            tr("REQUIREMENT_LINE")
                            . format(
                                {
                                    "name":
                                    (
                                        tr(_content.skills[requirement["id"]]["name_key"])
                                        if requirement["type"] == "skill"
                                        else str(requirement["id"])
                                    ),
                                    "minimum": requirement["minimum"],
                                    "current": requirement["current"],
                                }
                            )
                        )
                    )
                )
            text += ", ".join(needs)
        box.add_child(Ui.label(text, 17, true))
    return box


func _raise(id: String) -> void:
    if Progression.raise_attribute(_character, id, _content):
        _changed()


func _invest(id: String, points: int) -> void:
    if Progression.invest(_character, id, points, _content):
        _changed()


func _buy(id: String) -> void:
    if Progression.buy_perk(_character, id, _content):
        _changed()


func _changed() -> void:
    _game.session.dirty = true
    _game.session.save()
    _rebuild()


func _back() -> void:
    _game.go("city_map")


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("cancel"):
        _back()
