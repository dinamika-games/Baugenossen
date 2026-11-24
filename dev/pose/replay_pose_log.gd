extends SceneTree
## Replay a pose log (--log-pose) through the body controls of the game, as if
## the logged player played again: the auto-calibration, the measures, the
## smoothed signal, the hook velocity and the gestures, one line per logged
## frame. Use it to tune the controls on real movements without a camera.
##
## $GODOT --headless --path . --script dev/pose/replay_pose_log.gd -- <log> [--every=5]

const NAMES := {
    "nose": 0,
    "l_shoulder": 5,
    "r_shoulder": 6,
    "l_elbow": 7,
    "r_elbow": 8,
    "l_wrist": 9,
    "r_wrist": 10,
    "l_hip": 11,
    "r_hip": 12
}


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.is_empty():
        print("Usage: -- <log> [--every=N]")
        quit(1)
        return
    var every := 5
    for arg in args:
        if arg.begins_with("--every="):
            every = int(arg.trim_prefix("--every="))
    var auto := AutoCalibration.new()
    var controller := PoseController.new()
    var line_number := 0
    var printed := 0
    var hook := Vector2.ZERO
    var last_t := -1.0
    for line in FileAccess.get_file_as_string(args[0]).split("\n"):
        var at := line.find(PoseLog.PREFIX)
        if at < 0:
            continue
        var record: Variant = Json.parse(line.substr(at + PoseLog.PREFIX.length()))
        if not record is Dictionary or record.get("kind") != "sample" or not record.has("kp"):
            continue
        line_number += 1
        var frame := _frame(record)
        var now := float(record["t"])
        var events: Array = []
        var velocity := Vector2.ZERO
        if not controller.calibration.has("h"):
            var measures := {}
            if PoseMeasure.confident(frame, controller.min_confidence):
                measures = PoseMeasure.measure(frame)
            var calibration := auto.feed(measures, now)
            if not calibration.is_empty():
                controller.calibration = calibration
                controller.rearm()
                events.append("auto_calibrated %s" % [_rounded(calibration)])
        else:
            var output := controller.update(frame, now, InputDispatcher.BUILD)
            velocity = output["velocity"]
            events.append_array(output["events"])
        if last_t >= 0.0:
            hook += velocity * (now - last_t)
        last_t = now
        if line_number % every == 0 or not events.is_empty():
            printed += 1
            var m := PoseMeasure.measure(frame) if PoseMeasure.confident(frame, 0.3) else {}
            print(
                (
                    "t=%7.2f h=%+.2f v=%+.2f s=(%+.2f, dip %.2f) vel=(%+5.1f, %+5.1f) hook=(%+6.1f, %+6.1f) %s %s"
                    % [
                        now,
                        float(m.get("h", NAN)),
                        float(m.get("v", NAN)),
                        controller.smoothed.x,
                        controller.dip,
                        velocity.x,
                        velocity.y,
                        hook.x,
                        hook.y,
                        controller.tracking,
                        " ".join(events)
                    ]
                )
            )
    print("%d frames replayed." % line_number)
    quit(0)


func _rounded(values: Dictionary) -> Dictionary:
    var result := {}
    for key in values:
        result[key] = snappedf(float(values[key]), 0.01) if values[key] is float else values[key]
    return result


## Rebuild the frame of a logged sample (the key points which are not logged
## get no confidence).
func _frame(record: Dictionary) -> Dictionary:
    var points: Array = []
    points.resize(PoseProvider.KEYPOINT_COUNT)
    points.fill(Vector2.ZERO)
    var scores: Array = []
    scores.resize(PoseProvider.KEYPOINT_COUNT)
    scores.fill(0.0)
    for name in record["kp"]:
        var value: Array = record["kp"][name]
        points[NAMES[name]] = Vector2(float(value[0]), float(value[1]))
        scores[NAMES[name]] = float(value[2])
    return {
        "timestamp": float(record["t"]),
        "width": int(record["size"][0]),
        "height": int(record["size"][1]),
        "keypoints": points,
        "scores": scores,
        "mirrored": bool(record.get("mirrored", true)),
    }
