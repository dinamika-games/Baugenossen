class_name BuildHud
extends Control
## Show the build interface (DESIGN.md, 7): the top bar with the mission, the
## tool, the input status and the pause button, the checklist of the
## objectives, and the message about what the hook would do at the bottom.
## The blocks wait in the yard of the site itself (see [SiteView]). The overlays (pause,
## review, completion) are built by [BuildOverlays].
##
## The HUD only shows and forwards; the build site decides.

signal action_requested(action: String)

var content: ContentDb
## The camera inset, and its frame, which moves out of the hook's way.
var camera_view: CameraView
var camera_frame: Panel

var _title: Label
var _tool: Label
var _status: Label
var _message: Label
var _checklist: VBoxContainer
var _tutorial: Label


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
    camera_frame = frame
    var camera := CameraView.new()
    camera_view = camera
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
    panel.offset_top = -56
    add_child(panel)
    _message = Ui.label("", 20)
    _message.clip_text = true
    box.add_child(_message)


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


## Move the camera inset out of the way of a point of the screen (the hook):
## from the top left to the top, left of the checklist, and back.
func avoid(point: Vector2) -> void:
    if camera_frame == null:
        return
    if not camera_frame.get_rect().grow(48.0).has_point(point):
        return
    var left := Vector2(8, 72)
    var right := Vector2(get_viewport_rect().size.x - 340 - camera_frame.size.x - 8, 72)
    camera_frame.position = right if camera_frame.position.is_equal_approx(left) else left
