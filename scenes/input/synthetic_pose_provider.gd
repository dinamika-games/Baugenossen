class_name SyntheticPoseProvider
extends PoseProvider
## Provide made-up poses for the tests and for trying the controls without a
## camera: a body in a supported plank, seen from the front, which leans, rises
## and lifts a hand as told. The tests advance the clock themselves.
##
## The body is described in the picture's units (0 to 1), not mirrored.

var time := 0.0
## How far the shoulders are shifted to the right of the hands (picture units).
var shift := 0.0
## How far the shoulders are raised above neutral (picture units, up is +).
var rise := 0.0
## How far each wrist is lifted above its resting place (picture units).
## How far the hands (and with them the elbows) moved sideways, normalized.
var hands_shift := 0.0
var lift_left := 0.0
var lift_right := 0.0
## The confidence of every key point; set low to lose the tracking.
var confidence := 0.9
## Whether there is anybody at all.
var present := true
## The time of the last frame; a stale frame keeps its old timestamp.
var frozen_at := -1.0


func start() -> bool:
    return true


func now() -> float:
    return time


func status() -> String:
    return "running"


func advance(seconds: float) -> void:
    time += seconds


func latest_frame() -> Dictionary:
    if not present:
        return {}
    var points: Array = []
    points.resize(KEYPOINT_COUNT)
    points.fill(Vector2(0.5, 0.5))
    var scores: Array = []
    scores.resize(KEYPOINT_COUNT)
    scores.fill(confidence)
    # NOTE (mristin):
    # The person faces the camera: their left side is on the right of the
    # picture. The hands rest on the floor, the shoulders above them.
    var shoulder_y := 0.45 - rise
    var cx := 0.5 + shift
    points[NOSE] = Vector2(cx, shoulder_y - 0.1)
    points[LEFT_SHOULDER] = Vector2(cx + 0.1, shoulder_y)
    points[RIGHT_SHOULDER] = Vector2(cx - 0.1, shoulder_y)
    # NOTE (mristin):
    # As in the pose logs: the elbows stay above the hands while the shoulders
    # lean, sink less than the shoulders, and a lifted arm lifts its elbow.
    points[LEFT_ELBOW] = Vector2(0.6 + hands_shift, (shoulder_y + 0.7) / 2.0 - lift_left)
    points[RIGHT_ELBOW] = Vector2(0.4 + hands_shift, (shoulder_y + 0.7) / 2.0 - lift_right)
    points[LEFT_WRIST] = Vector2(0.6, 0.7 - lift_left)
    points[RIGHT_WRIST] = Vector2(0.4, 0.7 - lift_right)
    points[LEFT_HIP] = Vector2(cx + 0.08, shoulder_y + 0.05)
    points[RIGHT_HIP] = Vector2(cx - 0.08, shoulder_y + 0.05)
    return {
        "timestamp": frozen_at if frozen_at >= 0.0 else time,
        "width": 640,
        "height": 480,
        "keypoints": points,
        "scores": scores,
        "mirrored": mirrored,
    }
