class_name PoseCalibration
extends RefCounted
## Calibrate the body controls to the player (DESIGN.md, 3.3): a neutral
## supported posture, a comfortable lean to the left and to the right, and a
## comfortable raised and lowered posture. Each step waits until the player
## holds still for [constant HOLD_SECONDS] (no hold durations as a target: the
## player holds only as long as the measurement needs). The player may skip
## any step but the neutral one; a skipped side copies the range of the other.
## Skipping the neutral posture leaves the body controls off, and the keyboard
## and the mouse stay available anyway.

const STEPS := ["neutral", "left", "right", "up", "down"]
const HOLD_SECONDS := 1.0
## The most a signal may wobble (standard deviation, in shoulder widths) while
## the player holds still.
const STILLNESS := 0.06
## The least an extreme must differ from the neutral posture.
const MIN_RANGE := 0.15

var step_index := 0
## The results: "h", "v", "lift_left", "lift_right" (neutral), "left", "right"
## (h), "up", "down" (v).
var values: Dictionary = {}
var skipped: Dictionary = {}
## "", "hold_still" or "move_further", for the instructions.
var feedback := ""
var _samples: Array[Dictionary] = []


func current_step() -> String:
    return STEPS[step_index] if step_index < STEPS.size() else ""


func done() -> bool:
    return step_index >= STEPS.size()


## Whether the result can drive the hook (at least the neutral posture).
func usable() -> bool:
    return values.has("h") and values.has("v")


## Feed the measures of a frame (see [PoseMeasure]); return whether the step
## finished with it.
func feed(measures: Dictionary, now: float) -> bool:
    if done() or measures.is_empty():
        return false
    _samples.append({"t": now, "h": measures["h"], "v": measures["v"], "m": measures})
    while not _samples.is_empty() and now - float(_samples[0]["t"]) > HOLD_SECONDS:
        _samples.pop_front()
    if now - float(_samples[0]["t"]) < HOLD_SECONDS * 0.9:
        feedback = ""
        return false
    if _spread("h") > STILLNESS or _spread("v") > STILLNESS:
        feedback = "hold_still"
        return false
    var h := _mean("h")
    var v := _mean("v")
    match current_step():
        "neutral":
            values["h"] = h
            values["v"] = v
            values["lift_left"] = _mean_of_measure("lift_left")
            values["lift_right"] = _mean_of_measure("lift_right")
        "left", "right":
            if absf(h - float(values["h"])) < MIN_RANGE:
                feedback = "move_further"
                return false
            values[current_step()] = h
        "up", "down":
            if absf(v - float(values["v"])) < MIN_RANGE:
                feedback = "move_further"
                return false
            values[current_step()] = v
    _next()
    return true


## Skip the current step (the player prefers not to do it, or can not).
func skip() -> void:
    if done():
        return
    skipped[current_step()] = true
    if current_step() == "neutral":
        step_index = STEPS.size()
        return
    _next()


func _next() -> void:
    _samples.clear()
    feedback = ""
    step_index += 1
    if done():
        _complete_sides()


func _complete_sides() -> void:
    if not usable():
        return
    for pair in [["left", "right", "h"], ["up", "down", "v"]]:
        var neutral := float(values[pair[2]])
        if not values.has(pair[0]) and values.has(pair[1]):
            values[pair[0]] = neutral - (float(values[pair[1]]) - neutral)
        if not values.has(pair[1]) and values.has(pair[0]):
            values[pair[1]] = neutral - (float(values[pair[0]]) - neutral)


func _mean(key: String) -> float:
    var total := 0.0
    for sample in _samples:
        total += float(sample[key])
    return total / _samples.size()


func _mean_of_measure(key: String) -> float:
    var total := 0.0
    for sample in _samples:
        total += float(sample["m"][key])
    return total / _samples.size()


func _spread(key: String) -> float:
    var mean := _mean(key)
    var total := 0.0
    for sample in _samples:
        total += pow(float(sample[key]) - mean, 2.0)
    return sqrt(total / _samples.size())


## Map a raw signal to [-1, 1] between the calibrated extremes: 0 in neutral,
## -1 at "left" or "down", +1 at "right" or "up". An axis without extremes
## stays at 0.
static func normalize(raw: float, neutral: float, negative: Variant, positive: Variant) -> float:
    if negative == null or positive == null:
        return 0.0
    var delta := raw - neutral
    var towards_positive := float(positive) - neutral
    var towards_negative := float(negative) - neutral
    if absf(towards_positive) < 0.0001 or absf(towards_negative) < 0.0001:
        return 0.0
    var along_positive := delta / towards_positive
    if along_positive >= 0.0:
        return clampf(along_positive, 0.0, 1.0)
    return -clampf(delta / towards_negative, 0.0, 1.0)


## Re-centre the neutral posture on the current one (an explicit action, never
## continuously while the player leans), keeping the ranges.
static func recentre(calibration: Dictionary, measures: Dictionary) -> Dictionary:
    var result := calibration.duplicate()
    if measures.is_empty() or not result.has("h"):
        return result
    for axis in [["h", "left", "right"], ["v", "down", "up"]]:
        var shift := float(measures[axis[0]]) - float(result[axis[0]])
        result[axis[0]] = float(measures[axis[0]])
        for side in [axis[1], axis[2]]:
            if result.has(side):
                result[side] = float(result[side]) + shift
    return result
