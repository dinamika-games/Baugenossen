class_name PoseController
extends RefCounted
## Turn the calibrated body signals into the crane's commands (DESIGN.md, 3.3).
## The player is in the push-up position (or on the knees):
##
## * The hook moves sideways with the lean: smoothed with an exponential moving
##   average (alpha 0.2 at 30 Hz, adjusted to the frame time), with a dead zone
##   of 0.15 and the velocity sign(s) * max(0, (|s| - 0.15) / 0.85)^1.5 *
##   max_speed. The hook does not move vertically: the part drops onto the
##   first support below it.
## * A dip (lowering the body, as in a push-up) is measured against the
##   baseline of the straight arms, which follows the player's posture slowly
##   (it drifts while they play). A short dip ([constant DIP_SHORT] of the
##   range, and back up) lowers the landing of the part by one level
##   ("level"); a full dip ([constant DIP_FULL]) places the part ("confirm"),
##   or resumes after a pause. The hook stands still while the player dips.
## * A deliberate lift and return of a hand opens the catalogue. A lift must
##   hold [member qualify_seconds],
##   the return [member return_seconds]; then a cooldown follows. One lift is
##   one event; a held hand repeats nothing; both hands at once do nothing.
##   While a lift is recognized, the hook stands still.
## * In the catalogue, the raised hand points (see [member cursor]); the
##   return of the hand completes the dwell selection.
## * If a required joint is less confident than [member min_confidence] or the
##   frame is older than [member stale_seconds], everything freezes at once;
##   after [member lost_seconds] the tracking counts as lost. After that, and
##   after a catalogue selection, the hook moves only once the player held the
##   neutral posture for [member neutral_seconds]; a pending gesture is dropped,
##   never queued.
##
## These are debounce values, not exercise targets.

## The dips, as shares of the range from the baseline down (the calibration's
## "down"): a short dip, a full dip, and back up. From the pose logs: a lean
## lowers the shoulders a little, too (a dip of 0.2 to 0.3), while a push-up
## reaches 0.8 to 1.0.
const DIP_SHORT := 0.45
const DIP_FULL := 0.75
const DIP_RELEASE := 0.15
## How fast the baseline of the straight arms follows the posture, in seconds:
## up at once, down slowly (and not at all during a dip).
const BASELINE_UP_SECONDS := 0.5
const BASELINE_DOWN_SECONDS := 4.0

var calibration: Dictionary = {}
var alpha := 0.2
var dead_zone := 0.15
var max_speed := 10.0
var sensitivity := 1.0
## The key points count from this confidence on; the pose logs showed the
## shoulders well placed at 0.5, so 0.6 dropped the tracking needlessly.
var min_confidence := 0.4
var stale_seconds := 0.25
var lost_seconds := 0.5
var qualify_seconds := 0.2
var return_seconds := 0.15
var cooldown_seconds := 0.35
var neutral_seconds := 0.5
## How far a wrist must rise above its neutral height, in shoulder widths, to
## count as lifted, and how far back down it must come to count as returned.
var lift_threshold := 0.6
var release_threshold := 0.3
## Whether a lifted hand gives events (the catalogue); the build site plays
## with push-ups only and switches them off.
var hand_gestures := true

## The smoothed signal in [-1, 1]^2.
var smoothed := Vector2.ZERO
var tracking := "lost"
## Where the raised hand points in the catalogue, in [0, 1]^2, or (-1, -1).
var cursor := Vector2(-1, -1)
var needs_neutral := true
## The raw measures of the latest usable frame (see [PoseMeasure]), or {}.
var last_measures: Dictionary = {}
## How deep the player dips now, in [0, 1] of the range.
var dip := 0.0

var _last_time := -1.0
var _bad_since := -1.0
var _neutral_since := -1.0
var _hands := {"left": _new_hand(), "right": _new_hand()}
var _baseline := NAN
## "", "short" (deeper than a short dip) or "full" (placed) during a dip.
var _dip_phase := ""
var _both_lifted := false


static func _new_hand() -> Dictionary:
    return {"phase": "rest", "since": 0.0, "cooldown_until": -1.0}


## Require the neutral posture before the hook moves again (after selecting in
## the catalogue, or after the tracking was lost).
func rearm() -> void:
    needs_neutral = true
    _neutral_since = -1.0
    # NOTE (mristin):
    # A hand still raised (e.g., pointing in the catalogue) must come down
    # before it can start a new gesture.
    for hand in _hands.values():
        hand["phase"] = "blocked"


func reset_gestures() -> void:
    _hands = {"left": _new_hand(), "right": _new_hand()}
    _both_lifted = false


## Process the latest frame in the given input state; return
## {"velocity": Vector2 (cells per second, y up), "events": Array[String]}.
## The events: "gesture_started", "gesture_cancelled", "confirm", "level",
## "open_catalogue", "catalogue_release" and "resume".
func update(frame: Dictionary, now: float, input_state: String) -> Dictionary:
    var events: Array[String] = []
    var output := {"velocity": Vector2.ZERO, "events": events}
    var dt := 1.0 / 30.0 if _last_time < 0.0 else clampf(now - _last_time, 0.0, 0.5)
    _last_time = now

    var fresh := not frame.is_empty() and now - float(frame["timestamp"]) <= stale_seconds
    var measures := {}
    if fresh and PoseMeasure.confident(frame, min_confidence) and calibration.has("h"):
        measures = PoseMeasure.measure(frame)
    last_measures = measures
    if measures.is_empty():
        _lose(now, events)
        return output

    _bad_since = -1.0
    tracking = "ok"
    var target := Vector2(
        PoseCalibration.normalize(
            float(measures["h"]),
            float(calibration["h"]),
            calibration.get("left"),
            calibration.get("right")
        ),
        0.0
    )
    var weight := 1.0 - pow(1.0 - alpha, dt * 30.0)
    smoothed += (target - smoothed) * weight

    # NOTE (mristin):
    # Raising or lowering the torso moves both wrists relative to the shoulders
    # alike, so a lift counts relative to the other hand. Both hands raised
    # together count as both lifted, which does nothing.
    var raw_left := float(measures["lift_left"]) - float(calibration.get("lift_left", 0.0))
    var raw_right := float(measures["lift_right"]) - float(calibration.get("lift_right", 0.0))
    var lifts := {"left": raw_left - raw_right, "right": raw_right - raw_left}
    var both_up := minf(raw_left, raw_right) >= lift_threshold
    _update_cursor(measures, lifts, input_state)
    var hand_events: Array[String] = events
    if not hand_gestures:
        hand_events = []
    _update_hands(lifts, both_up, now, input_state, hand_events)
    # NOTE (mristin):
    # While a hand is lifted, the body moves, too: no dip counts then.
    var lifting: bool = both_up or _hands["left"]["phase"] in ["rising", "qualified", "returning"]
    lifting = lifting or _hands["right"]["phase"] in ["rising", "qualified", "returning"]
    _update_dip(float(measures["v"]), dt, input_state, [] as Array[String] if lifting else events)

    var resting: bool = (
        _hands["left"]["phase"] in ["rest", "blocked"]
        and _hands["right"]["phase"] in ["rest", "blocked"]
        and float(lifts["left"]) < release_threshold
        and float(lifts["right"]) < release_threshold
    )
    var neutral: bool = resting and absf(smoothed.x) < dead_zone and _dip_phase == ""
    if neutral:
        if _neutral_since < 0.0:
            _neutral_since = now
        if needs_neutral and now - _neutral_since >= neutral_seconds:
            needs_neutral = false
    else:
        _neutral_since = -1.0

    var still := _dip_phase != ""
    if input_state == InputDispatcher.BUILD and resting and not needs_neutral and not still:
        output["velocity"] = Vector2(_curve(smoothed.x), 0.0) * max_speed * sensitivity
    return output


## Follow the baseline of the straight arms and recognize the dips.
func _update_dip(v: float, dt: float, input_state: String, events: Array[String]) -> void:
    var depth_range := maxf(
        0.05, float(calibration.get("v", v)) - float(calibration.get("down", v - 0.4))
    )
    if is_nan(_baseline):
        _baseline = float(calibration.get("v", v))
    if v > _baseline:
        _baseline += (v - _baseline) * minf(1.0, dt / BASELINE_UP_SECONDS)
    elif _dip_phase == "" and _baseline - v < DIP_RELEASE * depth_range:
        _baseline += (v - _baseline) * minf(1.0, dt / BASELINE_DOWN_SECONDS)
    dip = clampf((_baseline - v) / depth_range, 0.0, 1.0)
    match _dip_phase:
        "":
            if dip >= DIP_SHORT:
                _dip_phase = "short"
        "short":
            if dip >= DIP_FULL:
                _dip_phase = "full"
                if input_state == InputDispatcher.BUILD:
                    events.append("confirm")
                elif input_state == InputDispatcher.PAUSED and not needs_neutral:
                    events.append("resume")
            elif dip < DIP_RELEASE:
                _dip_phase = ""
                if input_state == InputDispatcher.BUILD:
                    events.append("level")
        "full":
            if dip < DIP_RELEASE:
                _dip_phase = ""


## Whether the player has held the neutral posture for a while.
## The phase of each hand's gesture ("rest", "rising", "qualified",
## "returning" or "blocked"), for the pose log.
func hand_phases() -> Dictionary:
    return {"left": _hands["left"]["phase"], "right": _hands["right"]["phase"]}


func neutral_held(now: float, seconds: float) -> bool:
    return _neutral_since >= 0.0 and now - _neutral_since >= seconds


func _curve(value: float) -> float:
    var magnitude := maxf(0.0, (absf(value) - dead_zone) / (1.0 - dead_zone))
    return signf(value) * pow(magnitude, 1.5)


func _lose(now: float, events: Array[String]) -> void:
    if _bad_since < 0.0:
        _bad_since = now
    tracking = "lost" if now - _bad_since >= lost_seconds else "frozen"
    smoothed = Vector2.ZERO
    cursor = Vector2(-1, -1)
    var pending := false
    for hand in _hands.values():
        pending = pending or hand["phase"] in ["rising", "qualified", "returning"]
    if pending:
        events.append("gesture_cancelled")
    reset_gestures()
    rearm()


func _update_cursor(measures: Dictionary, lifts: Dictionary, input_state: String) -> void:
    var side := ""
    if input_state == InputDispatcher.CATALOGUE:
        if float(lifts["left"]) >= lift_threshold:
            side = "left"
        elif float(lifts["right"]) >= lift_threshold:
            side = "right"
    if side == "":
        cursor = Vector2(-1, -1)
        return
    # NOTE (mristin):
    # The hand's offset from its shoulder, in shoulder widths, spans the
    # catalogue: two widths to each side, one and a half up and down.
    var offset: Vector2 = measures[side + "_hand"]
    cursor = Vector2(clampf(0.5 + offset.x / 4.0, 0.0, 1.0), clampf(0.5 + offset.y / 3.0, 0.0, 1.0))


func _update_hands(
    lifts: Dictionary, both_up: bool, now: float, input_state: String, events: Array[String]
) -> void:
    if both_up:
        if not _both_lifted:
            events.append("gesture_cancelled")
        _both_lifted = true
        reset_gestures()
        _both_lifted = true
        return
    if _both_lifted:
        if absf(float(lifts["left"])) < release_threshold:
            _both_lifted = false
        return
    for side in ["left", "right"]:
        var event := _update_hand(side, float(lifts[side]), now, input_state, events)
        if event != "":
            events.append(event)


func _update_hand(
    side: String, lift: float, now: float, input_state: String, events: Array[String]
) -> String:
    var hand: Dictionary = _hands[side]
    var other: Dictionary = _hands["right" if side == "left" else "left"]
    match hand["phase"]:
        "blocked":
            if lift < release_threshold:
                hand["phase"] = "rest"
        "rest":
            if lift >= lift_threshold and now >= float(hand["cooldown_until"]):
                if other["phase"] != "rest":
                    return ""
                hand["phase"] = "rising"
                hand["since"] = now
                events.append("gesture_started")
        "rising":
            if lift < release_threshold:
                hand["phase"] = "rest"
                return "gesture_cancelled"
            if now - float(hand["since"]) >= qualify_seconds:
                hand["phase"] = "qualified"
        "qualified":
            if lift < release_threshold:
                hand["phase"] = "returning"
                hand["since"] = now
        "returning":
            if lift >= lift_threshold:
                hand["phase"] = "qualified"
            elif now - float(hand["since"]) >= return_seconds:
                hand["phase"] = "rest"
                hand["cooldown_until"] = now + cooldown_seconds
                return _event_for(input_state)
    return ""


func _event_for(input_state: String) -> String:
    match input_state:
        InputDispatcher.CATALOGUE:
            return "catalogue_release"
        InputDispatcher.PAUSED:
            return "gesture_cancelled"
        _:
            return "open_catalogue"
