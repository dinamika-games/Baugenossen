extends Node
## Keep the player's settings in user://settings.cfg, apart from the game data
## (DESIGN.md, 7 and 8): the input source, the camera, the calibration, the
## sound, the scale, the language and the accessibility options.
##
## Start with `-- --settings=user://other.cfg` to keep them elsewhere (e.g., in
## the tests).

signal changed

const DEFAULTS := {
    "input_source": "keyboard",
    "camera_consent": false,
    "camera_mirror": true,
    "gesture_mode": "knees",
    "sensitivity": 1.0,
    "dead_zone": 0.15,
    "calibration": {},
    "sound": true,
    "music": true,
    "ui_scale": 1.0,
    "locale": "en",
    "reduced_motion": false,
    "high_contrast": false,
}

const GESTURE_MODES := ["plank", "knees", "seated", "standing"]
const LOCALES := ["en"]

var path := "user://settings.cfg"
var values: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--settings="):
            path = arg.trim_prefix("--settings=")
    load_settings()
    apply()


func load_settings() -> void:
    values = DEFAULTS.duplicate(true)
    var config := ConfigFile.new()
    if config.load(path) != OK:
        return
    for key in DEFAULTS:
        var value: Variant = config.get_value("settings", key, DEFAULTS[key])
        if typeof(value) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and value is int):
            values[key] = value
    values["sensitivity"] = clampf(float(values["sensitivity"]), 0.25, 2.0)
    values["dead_zone"] = clampf(float(values["dead_zone"]), 0.05, 0.4)
    values["ui_scale"] = clampf(float(values["ui_scale"]), 0.75, 1.5)
    if values["gesture_mode"] not in GESTURE_MODES:
        values["gesture_mode"] = DEFAULTS["gesture_mode"]
    if values["locale"] not in LOCALES:
        values["locale"] = "en"


func save_settings() -> void:
    var config := ConfigFile.new()
    for key in values:
        config.set_value("settings", key, values[key])
    var error := config.save(path)
    if error != OK:
        push_warning("Could not save the settings to %s: %s" % [path, error_string(error)])


func get_value(key: String) -> Variant:
    return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
    values[key] = value
    save_settings()
    apply()
    changed.emit()


## Apply the language and the scale of the interface.
func apply() -> void:
    TranslationServer.set_locale(str(values["locale"]))
    if is_inside_tree():
        get_tree().root.content_scale_factor = float(values["ui_scale"])


func body_controls() -> bool:
    return values["input_source"] == "body" and bool(values["camera_consent"])
