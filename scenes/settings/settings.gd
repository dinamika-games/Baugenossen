extends Node
## Keep the settings of the game apart from the saves. There is no settings
## screen and no calibration screen (the body controls calibrate themselves):
## the camera starts with the game, the sound and the music switch with S and
## M, and the rest is chosen on the command line.
##
## The options after `--`:
## * `--settings=user://other.cfg`: keep the settings elsewhere (e.g., in the tests),
## * `--high-contrast`: stronger outlines and colours,
## * `--reduced-motion`: the residents move in without walking,
## * `--no-mirror`: show the camera picture as the camera sees it,
## * `--sensitivity=<0.25 to 2>` and `--dead-zone=<0.05 to 0.4>`: tune the hook.

signal changed

const DEFAULTS := {
    "camera_mirror": true,
    "sensitivity": 1.0,
    "dead_zone": 0.15,
    "sound": true,
    "music": true,
    "reduced_motion": false,
    "high_contrast": false,
}

## The settings saved in the file; the others come from the command line.
const SAVED := []

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
    if config.load(path) == OK:
        for key in SAVED:
            var value: Variant = config.get_value("settings", key, DEFAULTS[key])
            if typeof(value) == typeof(DEFAULTS[key]):
                values[key] = value
    for arg in OS.get_cmdline_user_args():
        match arg:
            "--high-contrast":
                values["high_contrast"] = true
            "--reduced-motion":
                values["reduced_motion"] = true
            "--no-mirror":
                values["camera_mirror"] = false
        if arg.begins_with("--sensitivity="):
            values["sensitivity"] = clampf(float(arg.trim_prefix("--sensitivity=")), 0.25, 2.0)
        elif arg.begins_with("--dead-zone="):
            values["dead_zone"] = clampf(float(arg.trim_prefix("--dead-zone=")), 0.05, 0.4)


func save_settings() -> void:
    var config := ConfigFile.new()
    for key in SAVED:
        config.set_value("settings", key, values[key])
    var error := config.save(path)
    if error != OK:
        push_warning("Could not save the settings to %s: %s" % [path, error_string(error)])


func get_value(key: String) -> Variant:
    return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
    values[key] = value
    if key in SAVED:
        save_settings()
    apply()
    changed.emit()


func apply() -> void:
    pass
