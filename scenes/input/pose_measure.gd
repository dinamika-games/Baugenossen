class_name PoseMeasure
extends RefCounted
## Measure the raw body signals of one pose frame (DESIGN.md, 3.3), in the
## builder's own unit, the width of the shoulders, so that they do not depend
## on the distance to the camera. In the push-up position the camera does not
## see the hands (they are at the bottom edge of the picture or below it, as
## the pose logs showed), so everything rests on the shoulders and the elbows:
## * "h": the shoulder midpoint relative to the elbow midpoint, horizontally
##   (leaning the torso sideways over the arms),
## * "v": how far the lower elbow is below the shoulders (about 0.8 shoulder
##   widths with straight arms, down to 0.2 when the player lowers the body;
##   the lower elbow, so that lifting one arm does not look like a dip),
## * "lift_left", "lift_right": how high each elbow is above its shoulder (a
##   lifted arm lifts its elbow),
## * "left_hand", "right_hand": where the hand points, from its shoulder: the wrist
##   if the camera sees it (a raised hand comes into the picture), else the
##   elbow.
##
## The picture's vertical never stands for the body's height directly: the
## calibration maps each signal around the player's neutral posture.

## The key points every measure needs: the shoulders and the elbows.
const REQUIRED := [
    PoseProvider.LEFT_SHOULDER,
    PoseProvider.RIGHT_SHOULDER,
    PoseProvider.LEFT_ELBOW,
    PoseProvider.RIGHT_ELBOW,
]

## A wrist counts for pointing when the model is this sure of it.
const WRIST_THRESHOLD := 0.5
## An elbow counts when the model is this sure of it; else it is mirrored.
const ELBOW_THRESHOLD := 0.4


## Whether the shoulders and at least one elbow are at least as confident as
## the threshold (a missing elbow is mirrored from the other, see [method
## measure]: lowered deep, an elbow may leave the bottom of the picture).
static func confident(frame: Dictionary, threshold: float) -> bool:
    if frame.is_empty():
        return false
    var scores: Array = frame["scores"]
    if float(scores[PoseProvider.LEFT_SHOULDER]) < threshold:
        return false
    if float(scores[PoseProvider.RIGHT_SHOULDER]) < threshold:
        return false
    return (
        float(scores[PoseProvider.LEFT_ELBOW]) >= threshold
        or float(scores[PoseProvider.RIGHT_ELBOW]) >= threshold
    )


## Whether every key point of [constant REQUIRED] is confident (both elbows).
static func all_confident(frame: Dictionary, threshold: float) -> bool:
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


## The raw signals of the frame, or {} if the shoulders can not be measured.
static func measure(frame: Dictionary) -> Dictionary:
    var left_shoulder := point(frame, PoseProvider.LEFT_SHOULDER)
    var right_shoulder := point(frame, PoseProvider.RIGHT_SHOULDER)
    var unit := left_shoulder.distance_to(right_shoulder)
    if unit < 1.0:
        return {}
    var left_elbow := point(frame, PoseProvider.LEFT_ELBOW)
    var right_elbow := point(frame, PoseProvider.RIGHT_ELBOW)
    var scores: Array = frame["scores"]
    # NOTE (mristin):
    # An unsure elbow (e.g., at the bottom edge of the picture) is mirrored from
    # the other one, across the middle of the shoulders.
    var left_sure := float(scores[PoseProvider.LEFT_ELBOW]) >= ELBOW_THRESHOLD
    var right_sure := float(scores[PoseProvider.RIGHT_ELBOW]) >= ELBOW_THRESHOLD
    if left_sure and not right_sure:
        right_elbow = right_shoulder + _mirror(left_elbow - left_shoulder)
    elif right_sure and not left_sure:
        left_elbow = left_shoulder + _mirror(right_elbow - right_shoulder)
    var shoulders := (left_shoulder + right_shoulder) / 2.0
    var elbows := (left_elbow + right_elbow) / 2.0
    var left_pointer := left_elbow
    if float(scores[PoseProvider.LEFT_WRIST]) >= WRIST_THRESHOLD:
        left_pointer = point(frame, PoseProvider.LEFT_WRIST)
    var right_pointer := right_elbow
    if float(scores[PoseProvider.RIGHT_WRIST]) >= WRIST_THRESHOLD:
        right_pointer = point(frame, PoseProvider.RIGHT_WRIST)
    return {
        "unit": unit,
        "h": (shoulders.x - elbows.x) / unit,
        "v": (maxf(left_elbow.y, right_elbow.y) - shoulders.y) / unit,
        "lift_left": (left_shoulder.y - left_elbow.y) / unit,
        "lift_right": (right_shoulder.y - right_elbow.y) / unit,
        "left_hand": (left_pointer - left_shoulder) / unit,
        "right_hand": (right_pointer - right_shoulder) / unit,
    }


## The offset from a shoulder to its elbow, as on the other side of the body.
static func _mirror(offset: Vector2) -> Vector2:
    return Vector2(-offset.x, offset.y)
