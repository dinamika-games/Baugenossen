class_name PoseController
extends RefCounted
## Turn the calibrated body signals into the crane's commands (DESIGN.md, 3.3).
##
## * The hook moves with the lean (left/right) and the rise (up/down): smoothed
##   with an exponential moving average (alpha 0.2 at 30 Hz, adjusted to the
##   frame time), with a dead zone of 0.15 and the velocity
##   sign(s) * max(0, (|s| - 0.15) / 0.85)^1.5 * max_speed.
## * A deliberate lift and return of the right hand confirms (places), of the
##   left hand opens the catalogue. A lift must hold [member qualify_seconds],
##   the return [member return_seconds]; then a cooldown follows. One lift is
##   one event; a held hand repeats nothing; both hands at once do nothing.
##   While a lift is recognized, the hook stands still.
## * In the catalogue, the raised left hand points (see [member cursor]); the
##   return of the hand completes the dwell selection.
## * If a required joint is less confident than [member min_confidence] or the
##   frame is older than [member stale_seconds], everything freezes at once;
##   after [member lost_seconds] the tracking counts as lost. After that, and
##   after a catalogue selection, the hook moves only once the player held the
##   neutral posture for [member neutral_seconds]; a pending gesture is dropped,
##   never queued.
##
## These are debounce values, not exercise targets.

var calibration: Dictionary = {}
var alpha := 0.2
var dead_zone := 0.15
var max_speed := 10.0
var sensitivity := 1.0
var min_confidence := 0.6
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

## The smoothed signal in [-1, 1]^2.
var smoothed := Vector2.ZERO
var tracking := "lost"
## Where the raised left hand points in the catalogue, in [0, 1]^2, or (-1, -1).
var cursor := Vector2(-1, -1)
var needs_neutral := true
## The raw measures of the latest usable frame (see [PoseMeasure]), or {}.
var last_measures: Dictionary = {}

var _last_time := -1.0
var _bad_since := -1.0
var _neutral_since := -1.0
var _hands := {"left": _new_hand(), "right": _new_hand()}
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
## The events: "gesture_started", "gesture_cancelled", "confirm",
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
        PoseCalibration.normalize(
            float(measures["v"]),
            float(calibration["v"]),
            calibration.get("down"),
            calibration.get("up")
        )
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
    _update_hands(lifts, both_up, now, input_state, events)

    var resting: bool = (
        _hands["left"]["phase"] in ["rest", "blocked"]
        and _hands["right"]["phase"] in ["rest", "blocked"]
        and float(lifts["left"]) < release_threshold
        and float(lifts["right"]) < release_threshold
    )
    var neutral: bool = resting and absf(smoothed.x) < dead_zone and absf(smoothed.y) < dead_zone
    if neutral:
        if _neutral_since < 0.0:
            _neutral_since = now
        if needs_neutral and now - _neutral_since >= neutral_seconds:
            needs_neutral = false
    else:
        _neutral_since = -1.0

    if input_state == InputDispatcher.BUILD and resting and not needs_neutral:
        output["velocity"] = (
            Vector2(_curve(smoothed.x), _curve(smoothed.y)) * max_speed * sensitivity
        )
    return output


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
    if input_state != InputDispatcher.CATALOGUE or float(lifts["left"]) < lift_threshold:
        cursor = Vector2(-1, -1)
        return
    # NOTE (mristin):
    # The wrist's offset from the left shoulder, in shoulder widths, spans the
    # catalogue: two widths to each side, one and a half up and down.
    var offset: Vector2 = measures["left_hand"]
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
                return _event_for(side, input_state)
    return ""


func _event_for(side: String, input_state: String) -> String:
    match input_state:
        InputDispatcher.CATALOGUE:
            return "catalogue_release" if side == "left" else "gesture_cancelled"
        InputDispatcher.PAUSED:
            return "resume" if side == "right" and not needs_neutral else "gesture_cancelled"
        _:
            return "confirm" if side == "right" else "open_catalogue"
