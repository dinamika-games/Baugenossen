class_name PoseProvider
extends RefCounted
## Provide the body pose of the builder (DESIGN.md, 3.2).
##
## A frame is a dictionary:
## * "timestamp": seconds on a monotonic clock (the same clock as [method now]),
## * "width", "height": the size of the camera picture in pixels,
## * "keypoints": 17 COCO key points (Vector2), normalized to [0, 1] in the
##   picture as the camera sees it (not mirrored),
## * "scores": the confidence of each key point in [0, 1],
## * "mirrored": whether the player sees the picture mirrored.
##
## Subclasses never fabricate a pose: without one, [method latest_frame] returns
## an empty dictionary.

## The indices of the COCO key points.
const NOSE := 0
const LEFT_SHOULDER := 5
const RIGHT_SHOULDER := 6
const LEFT_ELBOW := 7
const RIGHT_ELBOW := 8
const LEFT_WRIST := 9
const RIGHT_WRIST := 10
const LEFT_HIP := 11
const RIGHT_HIP := 12
const KEYPOINT_COUNT := 17

var mirrored := true


func start() -> bool:
    return false


func stop() -> void:
    pass


## The latest frame, or {} if there is none.
func latest_frame() -> Dictionary:
    return {}


## The current time on the clock of the frames' timestamps.
func now() -> float:
    return Time.get_ticks_msec() / 1000.0


## "off", "starting", "running" or "failed" (with [method status_message]).
func status() -> String:
    return "off"


func status_message() -> String:
    return ""
