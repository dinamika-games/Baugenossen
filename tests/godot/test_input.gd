extends "res://tests/godot/godot_test.gd"
## Check the input with synthetic pose sequences, without a camera (DESIGN.md,
## 3 and 11, M4): the calibration, holding neutral, the axes, one gesture is one
## placement, the loss of the tracking freezes, the reacquisition never places,
## the catalogue never places, and the keyboard and a gesture confirming at
## once place only once.

const STEP := 1.0 / 30.0

var pose: SyntheticPoseProvider
var controller: PoseController
var dispatcher: InputDispatcher
var commands: Array[String] = []


func _run() -> void:
    _test_calibration()
    _test_neutral_and_axes()
    _test_gesture_places_once()
    _test_brief_lift_is_ignored()
    _test_both_hands_do_nothing()
    _test_tracking_loss()
    _test_catalogue_cannot_place()
    _test_concurrent_confirms()
    _test_dispatcher_states()
    _test_dwell()


func _setup() -> void:
    pose = SyntheticPoseProvider.new()
    controller = PoseController.new()
    dispatcher = InputDispatcher.new()
    commands.clear()
    dispatcher.command.connect(func(action: String, _arg: Variant) -> void: commands.append(action))
    controller.calibration = _calibrate(pose)


## Calibrate with the synthetic body; leaning is a shift, rising is a rise.
func _calibrate(body: SyntheticPoseProvider) -> Dictionary:
    var calibration := PoseCalibration.new()
    var postures := {
        "neutral": [0.0, 0.0],
        "left": [-0.06, 0.0],
        "right": [0.06, 0.0],
        "up": [0.0, 0.12],
        "down": [0.0, -0.12]
    }
    for attempt in range(20):
        if calibration.done():
            break
        var posture: Array = postures[calibration.current_step()]
        body.shift = posture[0]
        body.rise = posture[1]
        for i in range(60):
            body.advance(STEP)
            if calibration.feed(PoseMeasure.measure(body.latest_frame()), body.time):
                break
    body.shift = 0.0
    body.rise = 0.0
    return calibration.values


## Run the controller for the seconds; return the hook's total movement.
func _play(seconds: float) -> Vector2:
    var moved := Vector2.ZERO
    var frames := int(round(seconds / STEP))
    for i in range(frames):
        pose.advance(STEP)
        dispatcher.tick()
        var output := controller.update(pose.latest_frame(), pose.time, dispatcher.state)
        for event in output["events"]:
            _handle(event)
        if dispatcher.state == InputDispatcher.BUILD:
            dispatcher.dispatch("move_hook", output["velocity"])
            moved += output["velocity"] * STEP
    return moved


## What the build screen does with the controller's events.
func _handle(event: String) -> void:
    match event:
        "gesture_started":
            dispatcher.begin_gesture()
        "gesture_cancelled":
            dispatcher.end_gesture()
        "confirm", "open_catalogue":
            if dispatcher.state == InputDispatcher.GESTURE_PENDING:
                dispatcher.end_gesture(event)
            else:
                dispatcher.dispatch(event)
        "resume":
            dispatcher.dispatch("resume")


func _count(action: String) -> int:
    return commands.count(action)


func _test_calibration() -> void:
    var body := SyntheticPoseProvider.new()
    var values := _calibrate(body)
    check(values.has("h") and values.has("left") and values.has("up"), "every step calibrated")
    check(
        (
            (
                (float(values["left"]) - float(values["h"]))
                * (float(values["right"]) - float(values["h"]))
            )
            < 0.0
        ),
        "the left and the right lean lie on both sides of neutral"
    )
    var skipping := PoseCalibration.new()
    for i in range(40):
        body.advance(STEP)
        if skipping.feed(PoseMeasure.measure(body.latest_frame()), body.time):
            break
    skipping.skip()
    body.shift = 0.06
    for i in range(60):
        body.advance(STEP)
        if skipping.feed(PoseMeasure.measure(body.latest_frame()), body.time):
            break
    skipping.skip()
    skipping.skip()
    check(skipping.done() and skipping.usable(), "the steps can be skipped")
    check(skipping.values.has("left"), "a skipped side mirrors the other")
    check(not skipping.values.has("up"), "the skipped axis stays off")
    var none := PoseCalibration.new()
    none.skip()
    check(none.done() and not none.usable(), "without the neutral posture, no body controls")
    var still := PoseCalibration.new()
    body.shift = 0.0
    for i in range(40):
        body.advance(STEP)
        body.rise = 0.05 * sin(body.time * 40.0)
        still.feed(PoseMeasure.measure(body.latest_frame()), body.time)
    check_equal(still.feedback, "hold_still", "a wobbling player is asked to hold still")
    body.rise = 0.0


func _test_neutral_and_axes() -> void:
    _setup()
    var moved := _play(2.0)
    check(moved.length() < 0.001, "holding neutral moves nothing: %s" % moved)
    pose.shift = 0.06
    moved = _play(1.0)
    check(moved.x > 2.0 and absf(moved.y) < 0.5, "leaning right moves right: %s" % moved)
    pose.shift = -0.06
    moved = _play(1.5)
    check(moved.x < -2.0, "leaning left moves left: %s" % moved)
    pose.shift = 0.0
    _play(1.0)
    pose.rise = 0.12
    moved = _play(1.0)
    check(moved.y > 2.0 and absf(moved.x) < 0.5, "rising moves up: %s" % moved)
    pose.rise = -0.12
    moved = _play(1.5)
    check(moved.y < -2.0, "lowering moves down: %s" % moved)
    pose.rise = 0.0
    _play(1.0)
    pose.shift = 0.06 * 0.1
    moved = _play(1.0)
    check(moved.length() < 0.001, "a small lean stays in the dead zone")
    pose.shift = 0.0
    var fast := PoseController.new()
    fast.calibration = controller.calibration
    check(fast._curve(1.0) == 1.0 and fast._curve(0.15) == 0.0, "the velocity curve")


func _lift(side: String, height: float) -> void:
    if side == "right":
        pose.lift_right = height
    else:
        pose.lift_left = height


func _test_gesture_places_once() -> void:
    _setup()
    _play(1.0)
    _lift("right", 0.25)
    var moved := _play(0.5)
    check_equal(dispatcher.state, InputDispatcher.GESTURE_PENDING, "a lifted hand pends")
    check(moved.length() < 0.001, "the hook stands still meanwhile")
    _play(2.0)
    check_equal(_count("confirm"), 0, "a held hand places nothing yet")
    _lift("right", 0.0)
    _play(0.5)
    check_equal(_count("confirm"), 1, "lift and return places exactly once")
    check_equal(dispatcher.state, InputDispatcher.BUILD, "back to building")
    _play(1.0)
    check_equal(_count("confirm"), 1, "and nothing repeats")


func _test_brief_lift_is_ignored() -> void:
    _setup()
    _play(1.0)
    _lift("right", 0.25)
    _play(0.1)
    _lift("right", 0.0)
    _play(0.5)
    check_equal(_count("confirm"), 0, "a twitch of 100 ms places nothing")
    check_equal(dispatcher.state, InputDispatcher.BUILD, "and the build goes on")


func _test_both_hands_do_nothing() -> void:
    _setup()
    _play(1.0)
    _lift("right", 0.25)
    _lift("left", 0.25)
    _play(1.0)
    _lift("right", 0.0)
    _lift("left", 0.0)
    _play(1.0)
    check_equal(_count("confirm") + _count("open_catalogue"), 0, "both hands at once do nothing")


func _test_tracking_loss() -> void:
    _setup()
    _play(1.0)
    pose.shift = 0.06
    _play(0.5)
    _lift("right", 0.25)
    _play(0.3)
    pose.confidence = 0.3
    var moved := _play(0.1)
    check(moved.length() < 0.001, "a low confidence freezes the hook at once")
    check_equal(controller.tracking, "frozen", "the tracking freezes")
    _play(0.5)
    check_equal(controller.tracking, "lost", "and is lost after 500 ms")
    dispatcher.dispatch("pause")
    pose.confidence = 0.9
    _lift("right", 0.0)
    _play(1.0)
    check_equal(_count("confirm"), 0, "the reacquisition never places the pending part")
    check_equal(dispatcher.state, InputDispatcher.PAUSED, "and the game stays paused")
    pose.shift = 0.0
    _play(1.0)
    _lift("right", 0.25)
    _play(0.4)
    _lift("right", 0.0)
    _play(0.4)
    check_equal(dispatcher.state, InputDispatcher.BUILD, "an explicit lift resumes")
    check_equal(_count("confirm"), 0, "without placing")
    _setup()
    _play(1.0)
    pose.frozen_at = pose.time
    _play(0.4)
    check(controller.tracking != "ok", "a stale frame freezes, too")


func _test_catalogue_cannot_place() -> void:
    _setup()
    _play(1.0)
    _lift("left", 0.25)
    _play(0.4)
    _lift("left", 0.0)
    _play(0.4)
    check_equal(dispatcher.state, InputDispatcher.CATALOGUE, "the left hand opens the catalogue")
    _lift("right", 0.25)
    _play(0.4)
    _lift("right", 0.0)
    _play(0.4)
    check_equal(_count("confirm"), 0, "the right hand places nothing in the catalogue")
    _lift("left", 0.25)
    _play(0.3)
    check(controller.cursor.x >= 0.0, "the raised left hand points")
    dispatcher.dispatch("select_part", "bench_basic")
    controller.rearm()
    check_equal(dispatcher.state, InputDispatcher.BUILD, "selecting returns to building")
    pose.shift = 0.06
    var moved := _play(0.3)
    check(moved.length() < 0.001, "the hook waits for the neutral posture")
    _lift("left", 0.0)
    pose.shift = 0.0
    _play(1.0)
    pose.shift = 0.06
    moved = _play(0.5)
    check(moved.x > 0.5, "and then moves again")


func _test_concurrent_confirms() -> void:
    _setup()
    dispatcher.tick()
    check(dispatcher.dispatch("confirm"), "the keyboard confirms")
    check(not dispatcher.dispatch("confirm"), "a gesture in the same tick is dropped")
    check_equal(_count("confirm"), 1, "one placement")
    dispatcher.tick()
    check(dispatcher.dispatch("confirm"), "the next tick confirms again")


func _test_dispatcher_states() -> void:
    _setup()
    dispatcher.dispatch("pause")
    check(not dispatcher.dispatch("confirm"), "no placing while paused")
    check(not dispatcher.dispatch("move_hook", Vector2.ONE), "no moving while paused")
    dispatcher.dispatch("resume")
    check_equal(dispatcher.state, InputDispatcher.BUILD, "resumed")
    dispatcher.dispatch("submit_mission")
    check_equal(dispatcher.state, InputDispatcher.REVIEW, "the review")
    check(not dispatcher.dispatch("undo"), "is read-only")
    dispatcher.dispatch("cancel")
    check_equal(dispatcher.state, InputDispatcher.BUILD, "and returns to editing")
    dispatcher.dispatch("open_catalogue")
    check(not dispatcher.dispatch("confirm"), "the catalogue never places")
    check(not dispatcher.dispatch("move_hook", Vector2.ONE), "nor moves the hook")


func _test_dwell() -> void:
    var dwell := DwellSelector.new()
    dwell.point("bed_single", 0.0)
    check_equal(dwell.point("bed_single", 0.3), 0.3 / 0.65, "the dwell fills")
    check_equal(dwell.selected(), "", "not selected yet")
    dwell.point("table_basic", 0.5)
    check_equal(dwell.point("table_basic", 0.9), 0.4 / 0.65, "another entry starts over")
    dwell.point("table_basic", 1.2)
    check_equal(dwell.selected(), "table_basic", "selected after 650 ms")
