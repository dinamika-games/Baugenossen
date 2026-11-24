extends Control
## Change the settings (DESIGN.md, 7): the input source (with the consent to
## the camera), the calibration, the gesture mode, the camera mirror, the
## sensitivity and dead zone, the scale, the language and the accessibility.
## The keyboard and the mouse stay usable whatever is chosen.

const SCALES := [0.75, 1.0, 1.25, 1.5]

var _column: VBoxContainer
var _consent: VBoxContainer
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    _column = Ui.screen(self, _settings.get_value("high_contrast"))
    _build()


func _build() -> void:
    _column.add_child(Ui.label(tr("MENU_SETTINGS"), Ui.TITLE_SIZE))
    _column.add_child(Ui.label(tr("SETTINGS_INPUT"), 24))
    var input := _option(
        ["SETTINGS_INPUT_KEYBOARD", "SETTINGS_INPUT_BODY"],
        0 if not _settings.body_controls() else 1,
        _on_input
    )
    _column.add_child(input)
    _consent = Ui.vbox()
    _consent.visible = false
    _consent.add_child(Ui.label(tr("SETTINGS_CAMERA_CONSENT"), 18, true))
    var consent_buttons := Ui.hbox()
    consent_buttons.add_child(Ui.button(tr("SETTINGS_CAMERA_ALLOW"), _on_allow_camera))
    consent_buttons.add_child(Ui.button(tr("SETTINGS_CAMERA_DECLINE"), _on_decline_camera))
    _consent.add_child(consent_buttons)
    _column.add_child(_consent)
    _column.add_child(Ui.button(tr("MENU_CALIBRATION"), _on_calibrate, 320))
    _column.add_child(Ui.label(tr("SETTINGS_GESTURE_MODE"), 20))
    var modes: Array[String] = []
    for mode in _settings.GESTURE_MODES:
        modes.append("GESTURE_MODE_" + mode.to_upper())
    _column.add_child(
        _option(
            modes,
            _settings.GESTURE_MODES.find(_settings.get_value("gesture_mode")),
            _on_gesture_mode
        )
    )
    _column.add_child(_check("SETTINGS_MIRROR", "camera_mirror"))
    _column.add_child(_slider("SETTINGS_SENSITIVITY", "sensitivity", 0.25, 2.0, 0.05))
    _column.add_child(_slider("SETTINGS_DEAD_ZONE", "dead_zone", 0.05, 0.4, 0.01))
    _column.add_child(Ui.label(tr("SETTINGS_AUDIO"), 24))
    _column.add_child(_check("SETTINGS_SOUND", "sound"))
    _column.add_child(_check("SETTINGS_MUSIC", "music"))
    _column.add_child(Ui.label(tr("SETTINGS_DISPLAY"), 24))
    _column.add_child(
        _option(
            ["SCALE_75", "SCALE_100", "SCALE_125", "SCALE_150"],
            maxi(0, SCALES.find(float(_settings.get_value("ui_scale")))),
            _on_scale
        )
    )
    var locales: Array[String] = []
    for locale in _settings.LOCALES:
        locales.append("LANGUAGE_" + locale.to_upper())
    _column.add_child(
        _option(locales, _settings.LOCALES.find(_settings.get_value("locale")), _on_locale)
    )
    _column.add_child(_check("SETTINGS_REDUCED_MOTION", "reduced_motion"))
    _column.add_child(_check("SETTINGS_HIGH_CONTRAST", "high_contrast"))
    _column.add_child(Ui.label(tr("SETTINGS_KEYS"), 16, true))
    var back := Ui.button(tr("BUTTON_BACK"), _back)
    _column.add_child(back)
    back.grab_focus.call_deferred()


func _on_gesture_mode(index: int) -> void:
    _settings.set_value("gesture_mode", _settings.GESTURE_MODES[index])


func _on_scale(index: int) -> void:
    _settings.set_value("ui_scale", SCALES[index])


func _on_locale(index: int) -> void:
    _settings.set_value("locale", _settings.LOCALES[index])


func _option(keys: Array[String], selected: int, on_select: Callable) -> OptionButton:
    var option := OptionButton.new()
    option.custom_minimum_size = Vector2(360, Ui.BUTTON_HEIGHT)
    for key in keys:
        option.add_item(tr(key))
    option.select(maxi(selected, 0))
    option.item_selected.connect(on_select)
    return option


func _check(key: String, setting: String) -> CheckBox:
    var box := CheckBox.new()
    box.text = tr(key)
    box.button_pressed = bool(_settings.get_value(setting))
    box.toggled.connect(func(on: bool) -> void: _settings.set_value(setting, on))
    return box


func _slider(key: String, setting: String, low: float, high: float, step: float) -> HBoxContainer:
    var row := Ui.hbox()
    row.add_child(Ui.label(tr(key)))
    var slider := HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = step
    slider.value = float(_settings.get_value(setting))
    slider.custom_minimum_size = Vector2(300, 40)
    var value := Ui.label("%.2f" % slider.value)
    slider.value_changed.connect(
        func(number: float) -> void:
            value.text = "%.2f" % number
            _settings.set_value(setting, number)
    )
    row.add_child(slider)
    row.add_child(value)
    return row


func _on_input(index: int) -> void:
    if index == 0:
        _settings.set_value("input_source", "keyboard")
        _game.pose_provider.stop()
        _consent.visible = false
    elif bool(_settings.get_value("camera_consent")):
        _settings.set_value("input_source", "body")
    else:
        _consent.visible = true


func _on_allow_camera() -> void:
    _settings.set_value("camera_consent", true)
    _settings.set_value("input_source", "body")
    _consent.visible = false
    if not _settings.get_value("calibration").has("h"):
        _on_calibrate()


func _on_decline_camera() -> void:
    _settings.set_value("camera_consent", false)
    _settings.set_value("input_source", "keyboard")
    _game.go("settings")


func _on_calibrate() -> void:
    if not bool(_settings.get_value("camera_consent")):
        _consent.visible = true
        return
    _game.go("calibration")


func _back() -> void:
    _game.go(_game.return_screen)


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("cancel"):
        _back()
