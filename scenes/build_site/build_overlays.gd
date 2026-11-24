class_name BuildOverlays
extends Control
## Show the overlays of the build site: the pause (also when the tracking was
## lost), the review before the submission, and the completion with the
## residents. Each forwards the player's choice as an action.

signal action_requested(action: String)

var _panel: PanelContainer
var _box: VBoxContainer


func build(high_contrast: bool) -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    theme = Ui.make_theme(high_contrast)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box = Ui.vbox(12)
    _panel = Ui.panel(_box)
    _panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    _panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _panel.grow_vertical = Control.GROW_DIRECTION_BOTH
    _panel.custom_minimum_size = Vector2(560, 0)
    add_child(_panel)
    hide_all()


func hide_all() -> void:
    _panel.visible = false
    for child in _box.get_children():
        child.queue_free()


func is_showing() -> bool:
    return _panel.visible


func _open(title: String) -> void:
    for child in _box.get_children():
        _box.remove_child(child)
        child.queue_free()
    _box.add_child(Ui.label(title, 30))
    _panel.visible = true
    _panel.reset_size()


func _add_button(key: String, action: String) -> Button:
    var button := Ui.button(Texts.of(key), action_requested.emit.bind(action), 420)
    _box.add_child(button)
    return button


## The pause; [param reason_key] explains why (e.g., the tracking was lost).
func show_pause(reason_key: String, body_controls: bool) -> void:
    _open(tr("Paused"))
    if reason_key != "":
        _box.add_child(Ui.label(Texts.of(reason_key), Ui.FONT_SIZE, true))
    if body_controls:
        _box.add_child(Ui.label(Texts.of("PAUSE_BODY_RESUME_HINT"), 18, true))
    var resume := _add_button("PAUSE_RESUME", "resume")
    if body_controls:
        _add_button("PAUSE_RECENTRE", "recentre")
    _add_button("PAUSE_SAVE_AND_LEAVE", "leave")
    _add_button("PAUSE_SAVE_AND_QUIT", "quit")
    resume.grab_focus.call_deferred()


## Say that the body controls need a camera.
func show_needs_body(waiting: String, message: String) -> void:
    _open(Texts.of("NEEDS_BODY_TITLE"))
    _box.add_child(Ui.label(Texts.of("NEEDS_" + waiting.to_upper()), Ui.FONT_SIZE, true))
    if message != "":
        _box.add_child(Ui.label(message, 16, true))
    _add_button("PAUSE_SAVE_AND_LEAVE", "leave").grab_focus.call_deferred()


## The review: every objective with its state and hint; complete only if valid.
func show_review(report: MissionEvaluator.Report, revisit: bool) -> void:
    _open(tr("Review"))
    var lines: Array[String] = []
    for result in report.mandatory:
        lines.append(_line(result, false))
    _box.add_child(Ui.label("\n".join(lines), 18, true))
    if not report.optional.is_empty():
        lines.clear()
        for result in report.optional:
            lines.append(_line(result, true))
        _box.add_child(Ui.label(tr("Wishes") + "\n" + "\n".join(lines), 18, true))
    var complete := _add_button("REVIEW_RESUBMIT" if revisit else "REVIEW_COMPLETE", "complete")
    complete.disabled = not report.can_submit()
    if not report.can_submit():
        _box.add_child(
            Ui.label(
                tr("Some needs are still open; you can keep building as long as you like."),
                18,
                true
            )
        )
    var back := _add_button("REVIEW_BACK", "cancel")
    (complete if report.can_submit() else back).grab_focus.call_deferred()


func _line(result: Dictionary, optional: bool) -> String:
    var mark := "✓" if result["satisfied"] else ("○" if optional else "✗")
    var text := "%s %s" % [mark, MissionText.result_line(result)]
    if not result["satisfied"] and str(result["hint_key"]) != "":
        text += " — " + Texts.of(str(result["hint_key"]))
    return text


## The thanks of the residents, with the button to the results.
func show_completion(thanks: String) -> void:
    _open(tr("Moving in!"))
    _box.add_child(Ui.label(thanks, Ui.FONT_SIZE, true))
    _add_button("COMPLETE_CONTINUE", "results").grab_focus.call_deferred()
    _panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    _panel.offset_top = 80


func move_to_centre() -> void:
    _panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
