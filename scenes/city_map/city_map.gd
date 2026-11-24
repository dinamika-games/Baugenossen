extends Control
## Show the cooperative's projects on one screen (DESIGN.md, 6 and 7): a card
## for every request with its title, its state (locked, available, in
## progress, completed or needs repair), the residents who ask, their problem,
## and the button. The details of the needs and the wishes are on
## the checklist of the build site. Nothing starts on its own: the player
## picks a project, or saves and stops.

const STATUS_KEYS := {
    "locked": "STATUS_LOCKED",
    "available": "STATUS_AVAILABLE",
    "in_progress": "STATUS_IN_PROGRESS",
    "completed": "STATUS_COMPLETED",
    "needs_repair": "STATUS_NEEDS_REPAIR",
}
const ACTION_KEYS := {
    "available": "CITY_START",
    "in_progress": "CITY_CONTINUE",
    "completed": "CITY_REVISIT",
    "needs_repair": "CITY_REPAIR",
}
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    if _game.session.progress == null:
        _game.go("main_menu")
        return
    var content: ContentDb = _game.content
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    var header := Ui.hbox(24)
    var title := Ui.label(tr("The cooperative's projects"), Ui.TITLE_SIZE)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    header.add_child(Ui.button(tr("Save and exit"), _on_save_and_exit))
    column.add_child(header)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 16)
    grid.add_theme_constant_override("v_separation", 16)
    column.add_child(grid)
    var first_button: Button = null
    for id in content.mission_order:
        var card := _mission_card(content, id)
        grid.add_child(card[0])
        if first_button == null and card[1] != null:
            first_button = card[1]
    if first_button != null:
        first_button.grab_focus.call_deferred()


## A compact card of the project: [card, its button (or null)].
func _mission_card(content: ContentDb, id: String) -> Array:
    var mission := content.mission(id)
    var status: String = _game.session.mission_status(id)
    var box := Ui.vbox(4)
    box.custom_minimum_size = Vector2(560, 0)
    box.add_child(Ui.label(tr(mission["title"]), 24))
    var asked := Grammar.format(
        tr("Asked by {names}"), {"names": MissionText.requesters(mission, content)}
    )
    box.add_child(Ui.label("%s · %s" % [Texts.of(STATUS_KEYS[status]), asked], 16))
    var brief := Ui.label(tr(mission["brief"]), 16, true)
    brief.custom_minimum_size.x = 560
    box.add_child(brief)
    var action: Button = null
    if status == "locked":
        var titles: Array[String] = []
        for prerequisite in mission["prerequisite_ids"]:
            titles.append(tr(content.mission(prerequisite)["title"]))
        var after := {"missions": ", ".join(titles)}
        box.add_child(Ui.label(Grammar.format(tr("Opens after: {missions}"), after), 16, true))
    else:
        action = Ui.button(Texts.of(ACTION_KEYS[status]), _open.bind(id), 260)
        action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        box.add_child(action)
    var panel := Ui.panel(box)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if status == "locked":
        panel.modulate = Color(1, 1, 1, 0.7)
    return [panel, action]


func _open(id: String) -> void:
    _game.mission_id = id
    _game.go("build_site")


func _on_save_and_exit() -> void:
    _game.session.save()
    _game.go("main_menu")


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("cancel"):
        _on_save_and_exit()
