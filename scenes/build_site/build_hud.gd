class_name BuildHud
extends Control
## Show the build interface (DESIGN.md, 7): the top bar with the mission, the
## tool, the input status and the large buttons (undo, redo, remove, review,
## pause), the checklist of the objectives, the row of five blocks to choose
## from at the bottom (see [BlockQueue]), and the message about the preview. The overlays (pause,
## review, completion) are built by [BuildOverlays].
##
## The HUD only shows and forwards; the build site decides.

signal action_requested(action: String)
signal slot_clicked(index: int)

var content: ContentDb

var _title: Label
var _tool: Label
var _status: Label
var _message: Label
var _checklist: VBoxContainer
var _row: HBoxContainer
var _tutorial: Label
var _undo: Button
var _redo: Button
var _remove: Button
var _slots: Array[PartIcon] = []


func build(db: ContentDb, high_contrast: bool) -> void:
    content = db
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    theme = Ui.make_theme(high_contrast)
    _build_top_bar()
    _build_checklist()
    _build_camera()
    _build_row()


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
    _undo = Ui.button(tr("Undo"), action_requested.emit.bind("undo"), 100)
    _redo = Ui.button(tr("Redo"), action_requested.emit.bind("redo"), 100)
    _remove = Ui.button(Texts.of("HUD_REMOVE"), action_requested.emit.bind("toggle_remove"), 120)
    _remove.toggle_mode = true
    bar.add_child(_undo)
    bar.add_child(_redo)
    bar.add_child(_remove)
    bar.add_child(Ui.button(tr("Review"), action_requested.emit.bind("submit_mission"), 120))
    # NOTE (mristin):
    # The pause button is always visible (DESIGN.md, 7).
    bar.add_child(Ui.button(tr("Pause"), action_requested.emit.bind("pause"), 110))
    for child in bar.get_children():
        if child is Button:
            child.focus_mode = Control.FOCUS_NONE


## The player in the camera, with the key points, so that they see whether the
## crane follows them while they build.
func _build_camera() -> void:
    var frame := Panel.new()
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.position = Vector2(8, 72)
    frame.size = Vector2(248, 188)
    add_child(frame)
    var camera := CameraView.new()
    camera.position = Vector2(4, 4)
    camera.size = Vector2(240, 180)
    camera.cover = true
    camera.frame = frame
    frame.add_child(camera)


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
    box.add_child(Ui.label(tr("Checklist"), 20))
    _checklist = Ui.vbox(4)
    box.add_child(_checklist)
    _tutorial = Ui.label("", 16, true)
    _tutorial.custom_minimum_size.x = 300
    box.add_child(_tutorial)


func _build_row() -> void:
    var box := Ui.vbox(4)
    var panel := Ui.panel(box)
    panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    panel.offset_top = -176
    add_child(panel)
    _message = Ui.label("", 18)
    _message.clip_text = true
    box.add_child(_message)
    _row = Ui.hbox(12)
    _row.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_child(_row)
    for index in range(BlockQueue.SIZE):
        var button := Button.new()
        button.custom_minimum_size = Vector2(150, 124)
        button.focus_mode = Control.FOCUS_NONE
        var icon := PartIcon.new()
        icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        button.add_child(icon)
        button.pressed.connect(slot_clicked.emit.bind(index))
        _row.add_child(button)
        _slots.append(icon)


## Show the row of blocks, the chosen one, and how soon the oldest leaves.
func set_queue(parts: Array[String], selected: int, progress: float) -> void:
    for index in range(_slots.size()):
        var icon := _slots[index]
        var definition := content.part(parts[index]) if index < parts.size() else null
        icon.definition = definition
        icon.label = tr(definition.name) if definition != null else ""
        icon.selected = index == selected
        icon.leaving = progress if index == 0 else -1.0
        icon.queue_redraw()


func release_focus_all() -> void:
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()


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


## Show the objectives: a symbol and the text for each, mandatory first.
func set_checklist(report: MissionEvaluator.Report) -> void:
    for child in _checklist.get_children():
        child.queue_free()
    for result in report.mandatory:
        _checklist.add_child(_objective_label(result, false))
    if not report.optional.is_empty():
        _checklist.add_child(Ui.label(tr("Wishes"), 18))
        for result in report.optional:
            _checklist.add_child(_objective_label(result, true))


static func _objective_label(result: Dictionary, optional: bool) -> Label:
    var mark := "✓" if result["satisfied"] else ("○" if optional else "✗")
    var line := Ui.label("%s %s" % [mark, MissionText.result_line(result)], 17, true)
    line.custom_minimum_size.x = 300
    var colour := Ui.OK_COLOUR if result["satisfied"] else (Ui.INK if optional else Ui.BAD_COLOUR)
    line.add_theme_color_override("font_color", colour)
    return line
