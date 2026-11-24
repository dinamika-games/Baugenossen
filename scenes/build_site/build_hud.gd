class_name BuildHud
extends Control
## Show the build interface (DESIGN.md, 7): the top bar with the mission, the
## tool, the input status and the large buttons (undo, redo, remove, review,
## pause), the checklist of the objectives, the catalogue with its category
## tabs at the bottom, and the message about the preview. The overlays (pause,
## review, completion) are built by [BuildOverlays].
##
## The HUD only shows and forwards; the build site decides.

signal action_requested(action: String)
signal part_clicked(part_id: String)

const CATEGORY_ORDER := [
    "structure", "access", "furniture", "utilities", "nature", "recreation", "tools"
]

var content: ContentDb
var character: Character
var unlocked: Dictionary = {}
var offered: Array = []
var category := "structure"

var _title: Label
var _tool: Label
var _status: Label
var _message: Label
var _checklist: VBoxContainer
var _tabs: HBoxContainer
var _items: HBoxContainer
var _tutorial: Label
var _undo: Button
var _redo: Button
var _remove: Button
## part ID -> Button
var _item_buttons: Dictionary = {}
var _dwell_target := ""
var _dwell_progress := 0.0


func build(db: ContentDb, builder: Character, high_contrast: bool) -> void:
    content = db
    character = builder
    unlocked = Progression.unlocked_parts(builder, db)
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    theme = Ui.make_theme(high_contrast)
    _build_top_bar()
    _build_checklist()
    _build_catalogue()
    show_category(category)


func _build_top_bar() -> void:
    var bar := Ui.hbox(10)
    var panel := Ui.panel(bar)
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    panel.offset_bottom = 64
    add_child(panel)
    _title = Ui.label("", 22)
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _title.clip_text = true
    bar.add_child(_title)
    _tool = Ui.label("", 18)
    bar.add_child(_tool)
    _status = Ui.label("", 18)
    bar.add_child(_status)
    _undo = Ui.button(tr("HUD_UNDO"), action_requested.emit.bind("undo"), 100)
    _redo = Ui.button(tr("HUD_REDO"), action_requested.emit.bind("redo"), 100)
    _remove = Ui.button(tr("HUD_REMOVE"), action_requested.emit.bind("toggle_remove"), 120)
    _remove.toggle_mode = true
    bar.add_child(_undo)
    bar.add_child(_redo)
    bar.add_child(_remove)
    bar.add_child(Ui.button(tr("HUD_REVIEW"), action_requested.emit.bind("submit_mission"), 120))
    # NOTE (mristin):
    # The pause button is always visible (DESIGN.md, 7).
    bar.add_child(Ui.button(tr("HUD_PAUSE"), action_requested.emit.bind("pause"), 110))
    for child in bar.get_children():
        if child is Button:
            child.focus_mode = Control.FOCUS_NONE


func _build_checklist() -> void:
    var box := Ui.vbox(6)
    var panel := Ui.panel(box)
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    panel.offset_left = -330
    panel.offset_top = 72
    panel.offset_right = -8
    panel.custom_minimum_size.x = 322
    panel.modulate = Color(1, 1, 1, 0.94)
    add_child(panel)
    box.add_child(Ui.label(tr("HUD_CHECKLIST"), 20))
    _checklist = Ui.vbox(4)
    box.add_child(_checklist)
    _tutorial = Ui.label("", 16, true)
    _tutorial.custom_minimum_size.x = 300
    box.add_child(_tutorial)


func _build_catalogue() -> void:
    var box := Ui.vbox(4)
    var panel := Ui.panel(box)
    panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    panel.offset_top = -176
    add_child(panel)
    _message = Ui.label("", 18)
    _message.clip_text = true
    box.add_child(_message)
    _tabs = Ui.hbox(6)
    box.add_child(_tabs)
    for id in CATEGORY_ORDER:
        var record := _category_record(id)
        if record.is_empty():
            continue
        var tab := Ui.button(tr(record["name_key"]), show_category.bind(id), 120)
        tab.custom_minimum_size.y = 40
        tab.focus_mode = Control.FOCUS_NONE
        _tabs.add_child(tab)
    var scroll := ScrollContainer.new()
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.custom_minimum_size.y = 92
    box.add_child(scroll)
    _items = Ui.hbox(8)
    scroll.add_child(_items)


func _category_record(id: String) -> Dictionary:
    for record in content.categories:
        if record["id"] == id:
            return record
    return {}


func show_category(id: String) -> void:
    category = id
    for child in _items.get_children():
        child.queue_free()
    _item_buttons.clear()
    if id == "tools":
        _items.add_child(_tool_button("HUD_REMOVE", "toggle_remove"))
        _items.add_child(_tool_button("HUD_MOVE", "move_part"))
        _items.add_child(_tool_button("HUD_MIRROR", "mirror_part"))
        _items.add_child(_tool_button("HUD_COLOUR", "colour_variant"))
        return
    for part_id in content.part_order:
        var definition := content.part(part_id)
        if definition.category_id != id:
            continue
        if not offered.is_empty() and part_id not in offered:
            continue
        var button := Button.new()
        button.custom_minimum_size = Vector2(112, 88)
        button.tooltip_text = tr(definition.description_key)
        var icon := PartIcon.new()
        icon.definition = definition
        icon.locked = not unlocked.has(part_id)
        icon.label = tr(definition.name_key)
        icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        button.add_child(icon)
        button.pressed.connect(part_clicked.emit.bind(part_id))
        _items.add_child(button)
        _item_buttons[part_id] = button


## Show the previous (-1) or the next (+1) category.
func next_category(direction: int) -> void:
    var available: Array[String] = []
    for id in CATEGORY_ORDER:
        if not _category_record(id).is_empty():
            available.append(id)
    var index := available.find(category)
    show_category(available[posmod(index + direction, available.size())])


func _tool_button(key: String, action: String) -> Button:
    var button := Ui.button(tr(key), action_requested.emit.bind(action), 150)
    button.custom_minimum_size.y = 88
    return button


## Give the keyboard focus to the catalogue (in the CATALOGUE state).
func focus_catalogue(selected: String) -> void:
    var target: Button = _item_buttons.get(selected)
    if target == null:
        for child in _items.get_children():
            if not child.is_queued_for_deletion() and child is Button:
                target = child
                break
    if target != null:
        target.grab_focus()


func release_focus_all() -> void:
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()


## The catalogue entry under a point of the screen (for the pointing hand).
func entry_at(screen_point: Vector2) -> String:
    for part_id in _item_buttons:
        var button: Button = _item_buttons[part_id]
        if button.get_global_rect().has_point(screen_point):
            return part_id
    return ""


func catalogue_rect() -> Rect2:
    return _items.get_global_rect()


func show_dwell(target: String, progress: float) -> void:
    if target == _dwell_target and is_equal_approx(progress, _dwell_progress):
        return
    for part_id in _item_buttons:
        var icon: PartIcon = _item_buttons[part_id].get_child(0)
        icon.dwell = progress if part_id == target else 0.0
        icon.queue_redraw()
    _dwell_target = target
    _dwell_progress = progress


func set_title(text: String) -> void:
    _title.text = text


func set_tool(text: String) -> void:
    _tool.text = text


func set_status(text: String) -> void:
    _status.text = text


func set_message(text: String, colour: Color) -> void:
    _message.text = text
    _message.add_theme_color_override("font_color", colour)


func set_tutorial(text: String) -> void:
    _tutorial.text = text
    _tutorial.visible = text != ""


func set_history(can_undo: bool, can_redo: bool, removing: bool) -> void:
    _undo.disabled = not can_undo
    _redo.disabled = not can_redo
    _remove.set_pressed_no_signal(removing)


func set_selected(part_id: String) -> void:
    for id in _item_buttons:
        var icon: PartIcon = _item_buttons[id].get_child(0)
        icon.selected = id == part_id
        icon.queue_redraw()


## Show the objectives: a symbol and the text for each, mandatory first.
func set_checklist(report: MissionEvaluator.Report) -> void:
    for child in _checklist.get_children():
        child.queue_free()
    for result in report.mandatory:
        _checklist.add_child(_objective_label(result, false))
    if not report.optional.is_empty():
        _checklist.add_child(Ui.label(tr("HUD_WISHES"), 18))
        for result in report.optional:
            _checklist.add_child(_objective_label(result, true))


static func _objective_label(result: Dictionary, optional: bool) -> Label:
    var mark := "✓" if result["satisfied"] else ("○" if optional else "✗")
    var line := Ui.label("%s %s" % [mark, MissionText.result_line(result)], 17, true)
    line.custom_minimum_size.x = 300
    var colour := Ui.OK_COLOUR if result["satisfied"] else (Ui.INK if optional else Ui.BAD_COLOUR)
    line.add_theme_color_override("font_color", colour)
    return line
