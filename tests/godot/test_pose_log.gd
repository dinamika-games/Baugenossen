extends "res://tests/godot/godot_test.gd"
## Check the pose log (`-- --log-pose`): the arguments, the rate, that events
## are logged at once, and that every line is one JSON object with the key
## points, the measures and the gestures, but no picture.

const STEP := 1.0 / 30.0


func _run() -> void:
    check(PoseLog.from_args(PackedStringArray([])) == null, "no log without --log-pose")
    check_equal(PoseLog.from_args(PackedStringArray(["--log-pose"])).rate, 10.0, "10 a second")
    check_equal(PoseLog.from_args(PackedStringArray(["--log-pose=3"])).rate, 3.0, "or as given")

    var body := SyntheticPoseProvider.new()
    var controller := PoseController.new()
    var calibration := PoseCalibration.new()
    for i in range(60):
        body.advance(STEP)
        if calibration.feed(PoseMeasure.measure(body.latest_frame()), body.time):
            break
    calibration.skip()
    calibration.skip()
    calibration.skip()
    calibration.skip()
    controller.calibration = calibration.values
    var log := PoseLog.new(2.0)
    log.keep_lines = true
    log.start("test", {"calibration": controller.calibration})
    var events_seen := 0
    for i in range(90):
        body.advance(STEP)
        body.lift_right = 0.25 if i >= 40 and i < 55 else 0.0
        var frame := body.latest_frame()
        var output := controller.update(frame, body.time, InputDispatcher.BUILD)
        events_seen += output["events"].size()
        var fields := PoseLog.controller_fields(controller, output["velocity"])
        fields["state"] = InputDispatcher.BUILD
        log.sample(body.time, frame, fields, output["events"])
    check(events_seen >= 2, "the gesture made events")
    var samples := 0
    var with_events := 0
    for line in log.lines:
        check(line.begins_with(PoseLog.PREFIX), "every line starts with POSE")
        var record: Variant = Json.parse(line.trim_prefix(PoseLog.PREFIX))
        check(record is Dictionary, "every line is a JSON object")
        if record is Dictionary and record["kind"] == "sample":
            samples += 1
            check(record["kp"].has("r_wrist") and record["kp"]["r_wrist"].size() == 3, "key points")
            check(record.has("m") and record.has("hands") and record.has("vel"), "the controls")
            if record.has("events"):
                with_events += 1
    check(samples >= 6 and samples <= 12, "about 2 samples a second plus the events: %d" % samples)
    check(with_events >= 2, "the events are logged at once")
    check(not str(log.lines).contains("Rgb"), "no picture")
