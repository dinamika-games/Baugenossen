extends Control
## Create the builder (DESIGN.md, 4 and 7): the name and the look, the seven
## attributes with the remaining points, the background, up to two traits and
## the preview of the skills and the unlocked parts. Continue is possible only
## with exactly 40 attribute points.

var _content: ContentDb
var _character: Character
var _attribute_labels: Dictionary = {}
var _remaining: Label
var _skills: GridContainer
var _unlocks: Label
var _problems: Label
var _continue: Button
var _background_description: Label
var _trait_boxes: Dictionary = {}
var _specialist: OptionButton
var _preview: Control
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    _content = _game.content
    _character = Character.create_default(_content)
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    column.add_child(Ui.label(tr("CREATE_TITLE"), Ui.TITLE_SIZE))
    var columns := Ui.hbox(32)
    column.add_child(columns)
    var left := Ui.vbox()
    left.custom_minimum_size.x = 460
    var right := Ui.vbox()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.add_child(left)
    columns.add_child(right)
    _build_identity(left)
    _build_background_and_traits(left)
    _build_attributes(right)
    _build_skills(right)

    var buttons := Ui.hbox()
    buttons.add_child(Ui.button(tr("BUTTON_BACK"), func() -> void: _game.go("main_menu")))
    buttons.add_child(Ui.button(tr("CREATE_RESET"), _on_reset))
    _continue = Ui.button(tr("BUTTON_CONTINUE"), _on_continue)
    buttons.add_child(_continue)
    column.add_child(buttons)
    _problems = Ui.label("", Ui.FONT_SIZE, true)
    _problems.add_theme_color_override("font_color", Ui.BAD_COLOUR)
    column.add_child(_problems)
    _refresh()


func _build_identity(parent: VBoxContainer) -> void:
    var name_edit := LineEdit.new()
    name_edit.placeholder_text = tr("CREATE_NAME_PLACEHOLDER")
    name_edit.max_length = 40
    name_edit.custom_minimum_size = Vector2(400, 48)
    name_edit.text_changed.connect(
        func(text: String) -> void:
            _character.name = text
            _refresh()
    )
    parent.add_child(Ui.label(tr("CREATE_NAME")))
    parent.add_child(name_edit)
    name_edit.grab_focus.call_deferred()
    var pronouns := LineEdit.new()
    pronouns.placeholder_text = tr("CREATE_PRONOUNS_PLACEHOLDER")
    pronouns.max_length = 30
    pronouns.text_changed.connect(func(text: String) -> void: _character.pronouns = text)
    parent.add_child(Ui.label(tr("CREATE_PRONOUNS")))
    parent.add_child(pronouns)

    var look := Ui.hbox()
    _preview = Control.new()
    _preview.custom_minimum_size = Vector2(120, 150)
    _preview.draw.connect(
        func() -> void: PartArt.draw_person(_preview, Vector2(60, 140), 48.0, _character.appearance)
    )
    look.add_child(_preview)
    var choices := Ui.vbox(6)
    for key in ["skin", "hair", "clothing"]:
        var row := Ui.hbox(6)
        row.add_child(Ui.label(tr("CREATE_LOOK_" + key.to_upper())))
        row.add_child(Ui.button("◀", _cycle.bind(key, -1), 52))
        row.add_child(Ui.button("▶", _cycle.bind(key, 1), 52))
        choices.add_child(row)
    look.add_child(choices)
    parent.add_child(look)


func _cycle(key: String, delta: int) -> void:
    var sizes := {
        "skin": PartArt.SKINS.size(),
        "hair": PartArt.HAIRS.size(),
        "clothing": PartArt.CLOTHES.size()
    }
    _character.appearance[key] = posmod(int(_character.appearance[key]) + delta, sizes[key])
    _preview.queue_redraw()


func _build_background_and_traits(parent: VBoxContainer) -> void:
    parent.add_child(Ui.label(tr("CREATE_BACKGROUND")))
    var backgrounds := OptionButton.new()
    backgrounds.custom_minimum_size.y = Ui.BUTTON_HEIGHT
    for id in _content.background_order:
        backgrounds.add_item(tr(_content.backgrounds[id]["name_key"]))
    backgrounds.item_selected.connect(
        func(index: int) -> void:
            _character.background_id = _content.background_order[index]
            _refresh()
    )
    parent.add_child(backgrounds)
    _background_description = Ui.label("", 18, true)
    parent.add_child(_background_description)

    parent.add_child(Ui.label(tr("CREATE_TRAITS").format({"count": _content.max_traits})))
    for id in _content.trait_order:
        var record: Dictionary = _content.traits[id]
        if not record.get("implemented", false):
            continue
        var box := CheckBox.new()
        box.text = "%s: %s" % [tr(record["name_key"]), tr(record["description_key"])]
        box.toggled.connect(_on_trait.bind(id))
        _trait_boxes[id] = box
        parent.add_child(box)
    _specialist = OptionButton.new()
    for id in _content.skill_order:
        _specialist.add_item(tr(_content.skills[id]["name_key"]))
    _specialist.item_selected.connect(
        func(index: int) -> void:
            _character.specialist_skill = _content.skill_order[index]
            _refresh()
    )
    _specialist.visible = false
    parent.add_child(_specialist)


func _on_trait(on: bool, id: String) -> void:
    if on and id not in _character.traits:
        _character.traits.append(id)
    elif not on:
        _character.traits.erase(id)
    if id == "specialist":
        _specialist.visible = on
        if on and _character.specialist_skill == "":
            _character.specialist_skill = _content.skill_order[0]
            _specialist.select(0)
    _refresh()


func _build_attributes(parent: VBoxContainer) -> void:
    parent.add_child(Ui.label(tr("CREATE_ATTRIBUTES")))
    var grid := GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation", 10)
    for attribute in _content.attributes:
        var id := str(attribute["id"])
        grid.add_child(Ui.label(tr(attribute["name_key"])))
        grid.add_child(Ui.button("−", _change.bind(id, -1), 52))
        var value := Ui.label("", 24)
        value.custom_minimum_size.x = 40
        value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _attribute_labels[id] = value
        grid.add_child(value)
        grid.add_child(Ui.button("+", _change.bind(id, 1), 52))
        var description := Ui.label(tr(attribute["description_key"]), 16, true)
        description.custom_minimum_size.x = 180
        grid.add_child(description)
    parent.add_child(grid)
    _remaining = Ui.label("", 22)
    parent.add_child(_remaining)


func _change(id: String, delta: int) -> void:
    var value := _character.attribute(id) + delta
    if value < _content.attribute_min or value > _content.attribute_max:
        return
    if delta > 0 and Progression.attribute_points_left(_character, _content) <= 0:
        return
    _character.attributes[id] = value
    _refresh()


func _build_skills(parent: VBoxContainer) -> void:
    parent.add_child(Ui.label(tr("CREATE_SKILLS")))
    _skills = GridContainer.new()
    _skills.columns = 4
    _skills.add_theme_constant_override("h_separation", 18)
    parent.add_child(_skills)
    _unlocks = Ui.label("", 18, true)
    parent.add_child(_unlocks)


func _refresh() -> void:
    for id in _attribute_labels:
        _attribute_labels[id].text = str(_character.attribute(id))
    var left := Progression.attribute_points_left(_character, _content)
    _remaining.text = tr("CREATE_POINTS_LEFT").format({"count": left})
    _background_description.text = tr(
        _content.backgrounds[_character.background_id]["description_key"]
    )
    for child in _skills.get_children():
        child.queue_free()
    for id in _content.skill_order:
        var value := Progression.skill(_character, id, _content)
        _skills.add_child(Ui.label(tr(_content.skills[id]["name_key"]), 16))
        _skills.add_child(Ui.label(str(value), 16))
    var unlocked := Progression.unlocked_parts(_character, _content)
    var advanced: Array[String] = []
    for id in _content.part_order:
        if not _content.part(id).requirements.is_empty() and unlocked.has(id):
            advanced.append(tr(_content.part(id).name_key))
    _unlocks.text = tr("CREATE_UNLOCKED").format(
        {"parts": ", ".join(advanced) if not advanced.is_empty() else tr("CREATE_UNLOCKED_NONE")}
    )
    var full := _character.traits.size() >= _content.max_traits
    for id in _trait_boxes:
        _trait_boxes[id].disabled = full and id not in _character.traits
    var problems := Progression.creation_problems(_character, _content)
    _continue.disabled = not problems.is_empty()
    var texts: Array[String] = []
    for problem in problems:
        texts.append(tr(problem))
    _problems.text = "\n".join(texts)


func _on_reset() -> void:
    _game.go("character_creation")


func _on_continue() -> void:
    if not Progression.creation_problems(_character, _content).is_empty():
        return
    _character.name = _character.name.strip_edges()
    _game.session.new_game(_character)
    _game.session.save()
    _game.go("city_map")
