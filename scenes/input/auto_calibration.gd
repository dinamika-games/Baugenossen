class_name AutoCalibration
extends RefCounted
## Calibrate the body controls by themselves, without a calibration screen: as
## soon as the camera sees the player holding still for [constant HOLD_SECONDS],
## that posture becomes the neutral one, and the ranges of the lean and the
## rise are the defaults below (DESIGN.md, 3.3).
##
## This is the first try: the default ranges are guesses, to be tuned with the
## pose logs of real players (--log-pose), or learned while they play.

const HOLD_SECONDS := 2.0
## The most a signal may wobble (standard deviation, in shoulder widths) while
## the player holds still.
const STILLNESS := 0.06
## How far, in shoulder widths, the lean (h) and the rise (v) go from neutral
## to the full speed of the hook. From the first pose log of a player in the
## push-up position: the shoulders lean about ±0.25 over the elbows; lowering
## the body brings the elbows from about 0.8 to 0.2–0.5 below the shoulders,
## but with straight arms the body rises only about 0.1 more.
const LEAN_RANGE := 0.25
const DOWN_RANGE := 0.3
const UP_RANGE := 0.15

## "", "hold_still" while the player moves.
var feedback := ""
var _samples: Array[Dictionary] = []


## Feed the measures of a frame (see [PoseMeasure]); return the calibration
## once the player held still, else {}.
func feed(measures: Dictionary, now: float) -> Dictionary:
    if measures.is_empty():
        _samples.clear()
        return {}
    _samples.append({"t": now, "m": measures})
    while not _samples.is_empty() and now - float(_samples[0]["t"]) > HOLD_SECONDS:
        _samples.pop_front()
    if now - float(_samples[0]["t"]) < HOLD_SECONDS * 0.9:
        feedback = ""
        return {}
    if _spread("h") > STILLNESS or _spread("v") > STILLNESS:
        feedback = "hold_still"
        return {}
    # NOTE (mristin):
    # The median, so that the last moment of settling in does not count.
    var h := _median("h")
    var v := _median("v")
    # NOTE (mristin):
    # In the mirrored picture, leaning to the player's left moves the shoulders
    # to the left of the elbows (h goes down); rising lifts the shoulders
    # away from the elbows (v goes up).
    return {
        "h": h,
        "v": v,
        "lift_left": _mean("lift_left"),
        "lift_right": _mean("lift_right"),
        "left": h - LEAN_RANGE,
        "right": h + LEAN_RANGE,
        "down": v - DOWN_RANGE,
        "up": v + UP_RANGE,
        "auto": true,
    }


func reset() -> void:
    _samples.clear()
    feedback = ""


func _mean(key: String) -> float:
    var total := 0.0
    for sample in _samples:
        total += float(sample["m"][key])
    return total / _samples.size()


func _median(key: String) -> float:
    var values: Array[float] = []
    for sample in _samples:
        values.append(float(sample["m"][key]))
    values.sort()
    return values[values.size() / 2]


func _spread(key: String) -> float:
    var mean := _mean(key)
    var total := 0.0
    for sample in _samples:
        total += pow(float(sample["m"][key]) - mean, 2.0)
    return sqrt(total / _samples.size())
