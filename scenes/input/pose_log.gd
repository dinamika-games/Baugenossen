class_name PoseLog
extends RefCounted
## Log the body pose and what the controls make of it, as lines of text, so
## that bugs of the body controls can be found afterwards without recording any
## picture (DESIGN.md, 3.2: no camera frames are stored).
##
## Start the game with `-- --log-pose` (10 lines a second) or
## `-- --log-pose=<lines a second>`. Every line starts with "POSE " followed by
## one JSON object; the events (gestures, tracking changes, steps of the
## calibration) are always logged at once, whatever the rate. The lines go to
## the standard output and to Godot's log file (user://logs/godot.log).
## dev/pose/analyze_pose_log.py turns them into a CSV file and a summary.
##
## Only numbers are logged: the key points (normalized, as the camera sees
## them), their confidence, the measures, the smoothed signal, the velocity,
## the gesture phases and the input state.

const DEFAULT_RATE := 10.0
const PREFIX := "POSE "

## The key points worth logging (the COCO indices and short names).
const KEYPOINTS := {
    0: "nose",
    5: "l_shoulder",
    6: "r_shoulder",
    7: "l_elbow",
    8: "r_elbow",
    9: "l_wrist",
    10: "r_wrist",
    11: "l_hip",
    12: "r_hip",
}

var rate := 0.0
## The lines written so far, if kept (for the tests).
var lines: Array[String] = []
var keep_lines := false
var _last := -INF
var _last_tracking := ""


## The pose log the command line asks for, or null without --log-pose.
static func from_args(args: PackedStringArray) -> PoseLog:
    for arg in args:
        if arg == "--log-pose":
            return PoseLog.new(DEFAULT_RATE)
        if arg.begins_with("--log-pose="):
            return PoseLog.new(maxf(0.1, float(arg.trim_prefix("--log-pose="))))
    return null


func _init(lines_a_second := DEFAULT_RATE) -> void:
    rate = lines_a_second


## Log the start of a screen with its settings and calibration.
func start(screen: String, settings: Dictionary) -> void:
    _emit(
        {
            "kind": "start",
            "screen": screen,
            "settings": settings,
            "wall": Time.get_datetime_string_from_system()
        }
    )


## Log a sample if it is time (or there are events, or the tracking changed).
func sample(now: float, frame: Dictionary, fields: Dictionary, events: Array = []) -> void:
    var tracking := str(fields.get("tracking", ""))
    var due := now - _last >= 1.0 / rate
    if not due and events.is_empty() and tracking == _last_tracking:
        return
    _last = now
    _last_tracking = tracking
    var record := {"kind": "sample", "t": snappedf(now, 0.001)}
    record.merge(fields)
    record.merge(frame_fields(frame, now))
    if not events.is_empty():
        record["events"] = events
    _emit(record)


## The key points of the frame with their confidence: [x, y, score], rounded.
static func frame_fields(frame: Dictionary, now: float) -> Dictionary:
    if frame.is_empty():
        return {"frame": null}
    var points := {}
    var keypoints: Array = frame["keypoints"]
    var scores: Array = frame["scores"]
    for index in KEYPOINTS:
        var point: Vector2 = keypoints[index]
        points[KEYPOINTS[index]] = [
            snappedf(point.x, 0.001), snappedf(point.y, 0.001), snappedf(float(scores[index]), 0.01)
        ]
    return {
        "age": snappedf(now - float(frame["timestamp"]), 0.001),
        "size": [int(frame["width"]), int(frame["height"])],
        "mirrored": bool(frame.get("mirrored", false)),
        "kp": points,
    }


## The fields of the controller: its measures, signal, velocity and gestures.
static func controller_fields(controller: PoseController, velocity: Vector2) -> Dictionary:
    var measures := {}
    for key in ["unit", "h", "v", "lift_left", "lift_right"]:
        if controller.last_measures.has(key):
            measures[key] = snappedf(float(controller.last_measures[key]), 0.001)
    return {
        "tracking": controller.tracking,
        "m": measures,
        "s": [snappedf(controller.smoothed.x, 0.001), snappedf(controller.smoothed.y, 0.001)],
        "vel": [snappedf(velocity.x, 0.01), snappedf(velocity.y, 0.01)],
        "hands": controller.hand_phases(),
        "needs_neutral": controller.needs_neutral,
        "cursor": [snappedf(controller.cursor.x, 0.001), snappedf(controller.cursor.y, 0.001)],
    }


func _emit(record: Dictionary) -> void:
    var line := PREFIX + JSON.stringify(record)
    if keep_lines:
        lines.append(line)
    print(line)
