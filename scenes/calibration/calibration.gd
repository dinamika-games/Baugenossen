extends Control
## Calibrate the body controls (DESIGN.md, 3.3): the player sees the mirrored
## camera picture with the key points, and follows the steps (neutral, lean
## left and right, raise and lower). Any step but the neutral one may be
## skipped. The hook moves only with the body, so the game needs this once.
## Without a camera, it says so.

var _calibration := PoseCalibration.new()
var _instruction: Label
var _feedback: Label
var _status: Label
var _picture: TextureRect
var _skeleton: Control
var _frame: Dictionary = {}
var _pose_log: PoseLog = PoseLog.from_args(OS.get_cmdline_user_args())
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    var column := Ui.screen(self, _settings.get_value("high_contrast"))
    column.add_child(Ui.label(tr("CALIBRATION_TITLE"), Ui.TITLE_SIZE))
    column.add_child(Ui.label(tr("CALIBRATION_HOW"), 18, true))
    var row := Ui.hbox(24)
    column.add_child(row)
    var stage := Control.new()
    stage.custom_minimum_size = Vector2(480, 360)
    row.add_child(stage)
    _picture = TextureRect.new()
    _picture.set_anchors_preset(Control.PRESET_FULL_RECT)
    _picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _picture.flip_h = bool(_settings.get_value("camera_mirror"))
    stage.add_child(_picture)
    _skeleton = Control.new()
    _skeleton.set_anchors_preset(Control.PRESET_FULL_RECT)
    _skeleton.draw.connect(_draw_skeleton)
    stage.add_child(_skeleton)
    var side := Ui.vbox()
    side.custom_minimum_size.x = 520
    row.add_child(side)
    _status = Ui.label("", 18, true)
    _instruction = Ui.label("", 26, true)
    _feedback = Ui.label("", 20, true)
    side.add_child(_status)
    side.add_child(_instruction)
    side.add_child(_feedback)
    side.add_child(Ui.button(tr("CALIBRATION_SKIP"), _on_skip, 320))
    side.add_child(
        Ui.button(tr("CALIBRATION_RESTART"), func() -> void: _game.go("calibration"), 320)
    )
    var back := Ui.button(tr("BUTTON_BACK"), _back, 320)
    side.add_child(back)
    back.grab_focus.call_deferred()
    _game.ensure_pose()
    if _pose_log != null:
        var settings := {}
        for key in ["camera_mirror", "sensitivity", "dead_zone"]:
            settings[key] = _settings.get_value(key)
        _pose_log.start("calibration", settings)
    if _game.pose_provider.status() == "off":
        _game.pose_provider.start()
    _refresh()


func _process(_delta: float) -> void:
    var provider: PoseProvider = _game.pose_provider
    var vision := get_node_or_null("/root/Vision")
    if vision != null and _picture.texture == null:
        _picture.texture = vision.service.GetCameraTexture()
    _status.text = tr("CALIBRATION_STATUS_" + provider.status().to_upper())
    if provider.status() == "failed" and provider.status_message() != "":
        _status.text += "\n" + provider.status_message()
    _frame = provider.latest_frame()
    _skeleton.queue_redraw()
    _log(provider, [])
    if (
        _calibration.done()
        or _frame.is_empty()
        or provider.now() - float(_frame["timestamp"]) > 0.25
    ):
        return
    if not PoseMeasure.confident(_frame, 0.6):
        _feedback.text = tr("CALIBRATION_NOT_VISIBLE")
        return
    var step := _calibration.current_step()
    if _calibration.feed(PoseMeasure.measure(_frame), provider.now()):
        _log(provider, ["step_done:" + step])
        _refresh()
    else:
        var keys := {
            "hold_still": "CALIBRATION_HOLD_STILL",
            "move_further": "CALIBRATION_MOVE_FURTHER",
            "": ""
        }
        _feedback.text = tr(keys[_calibration.feedback]) if _calibration.feedback != "" else ""


func _refresh() -> void:
    if _calibration.done():
        if _calibration.usable():
            _settings.set_value("calibration", _calibration.values)
            _instruction.text = tr("CALIBRATION_DONE")
        else:
            _instruction.text = tr("CALIBRATION_SKIPPED")
        _feedback.text = ""
        return
    _instruction.text = tr("CALIBRATION_STEP_" + _calibration.current_step().to_upper())


## Log the frame, the step and the measures (with --log-pose).
func _log(provider: PoseProvider, events: Array) -> void:
    if _pose_log == null:
        return
    var measures := {}
    if not _frame.is_empty() and PoseMeasure.confident(_frame, 0.3):
        var all := PoseMeasure.measure(_frame)
        for key in ["unit", "h", "v", "lift_left", "lift_right"]:
            if all.has(key):
                measures[key] = snappedf(float(all[key]), 0.001)
    var fields := {
        "screen": "calibration",
        "step": _calibration.current_step(),
        "feedback": _calibration.feedback,
        "status": provider.status(),
        "m": measures,
    }
    if _calibration.done():
        fields["result"] = _calibration.values
    _pose_log.sample(provider.now(), _frame, fields, events)


func _on_skip() -> void:
    if _pose_log != null:
        _log(_game.pose_provider, ["step_skipped:" + _calibration.current_step()])
    _calibration.skip()
    _refresh()


func _draw_skeleton() -> void:
    if _frame.is_empty():
        return
    var size := _skeleton.size
    var bones := [[5, 6], [5, 7], [7, 9], [6, 8], [8, 10], [5, 11], [6, 12], [11, 12]]
    var points: Array = _frame["keypoints"]
    var scores: Array = _frame["scores"]
    var mirror := bool(_settings.get_value("camera_mirror"))
    var place := func(index: int) -> Vector2:
        var point: Vector2 = points[index]
        return Vector2((1.0 - point.x) if mirror else point.x, point.y) * size
    for bone in bones:
        if float(scores[bone[0]]) >= 0.3 and float(scores[bone[1]]) >= 0.3:
            _skeleton.draw_line(place.call(bone[0]), place.call(bone[1]), Color("2f9a3a"), 4.0)
    for index in range(points.size()):
        var colour := Color("2f9a3a") if float(scores[index]) >= 0.6 else Color("d0342c")
        _skeleton.draw_circle(place.call(index), 5.0, colour)


func _back() -> void:
    _game.go(_game.return_screen if _game.return_screen != "" else "main_menu")


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("cancel"):
        _back()
