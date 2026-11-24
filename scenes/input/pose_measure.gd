class_name PoseMeasure
extends RefCounted
## Measure the raw body signals of one pose frame (DESIGN.md, 3.3), in the
## builder's own unit, the width of the shoulders, so that they do not depend
## on the distance to the camera:
## * "h": the shoulder midpoint relative to the wrist midpoint, horizontally
##   (leaning the torso sideways over the hands),
## * "v": a combination of the vertical shoulder-to-wrist distance and the
##   elbow angle (raising and lowering the torso),
## * "lift_left", "lift_right": how high each wrist is above its shoulder.
##
## The picture's vertical never stands for the body's height directly: the
## calibration maps each signal between the player's own comfortable extremes.

## How much the elbow angle weighs in "v" (the rest is the projected distance).
const ELBOW_WEIGHT := 0.5

## The key points every measure needs.
const REQUIRED := [
    PoseProvider.LEFT_SHOULDER,
    PoseProvider.RIGHT_SHOULDER,
    PoseProvider.LEFT_ELBOW,
    PoseProvider.RIGHT_ELBOW,
    PoseProvider.LEFT_WRIST,
    PoseProvider.RIGHT_WRIST,
]


## Whether every required key point is at least as confident as the threshold.
static func confident(frame: Dictionary, threshold: float) -> bool:
    if frame.is_empty():
        return false
    var scores: Array = frame["scores"]
    for index in REQUIRED:
        if float(scores[index]) < threshold:
            return false
    return true


## The key point in pixels, mirrored if the player sees the picture mirrored.
static func point(frame: Dictionary, index: int) -> Vector2:
    var normalized: Vector2 = frame["keypoints"][index]
    if bool(frame.get("mirrored", false)):
        normalized.x = 1.0 - normalized.x
    return Vector2(normalized.x * float(frame["width"]), normalized.y * float(frame["height"]))


static func _angle(a: Vector2, joint: Vector2, b: Vector2) -> float:
    var one := a - joint
    var two := b - joint
    if one.length() < 0.001 or two.length() < 0.001:
        return 180.0
    return rad_to_deg(absf(one.angle_to(two)))


## The raw signals of the frame, or {} if the shoulders can not be measured.
static func measure(frame: Dictionary) -> Dictionary:
    var left_shoulder := point(frame, PoseProvider.LEFT_SHOULDER)
    var right_shoulder := point(frame, PoseProvider.RIGHT_SHOULDER)
    var unit := left_shoulder.distance_to(right_shoulder)
    if unit < 1.0:
        return {}
    var left_wrist := point(frame, PoseProvider.LEFT_WRIST)
    var right_wrist := point(frame, PoseProvider.RIGHT_WRIST)
    var shoulders := (left_shoulder + right_shoulder) / 2.0
    var wrists := (left_wrist + right_wrist) / 2.0
    var elbows := (
        (
            _angle(left_shoulder, point(frame, PoseProvider.LEFT_ELBOW), left_wrist)
            + _angle(right_shoulder, point(frame, PoseProvider.RIGHT_ELBOW), right_wrist)
        )
        / 2.0
    )
    var distance := (wrists.y - shoulders.y) / unit
    return {
        "unit": unit,
        "h": (shoulders.x - wrists.x) / unit,
        "v": (1.0 - ELBOW_WEIGHT) * distance + ELBOW_WEIGHT * elbows / 90.0,
        "lift_left": (left_shoulder.y - left_wrist.y) / unit,
        "lift_right": (right_shoulder.y - right_wrist.y) / unit,
        "left_hand": (left_wrist - left_shoulder) / unit,
    }
