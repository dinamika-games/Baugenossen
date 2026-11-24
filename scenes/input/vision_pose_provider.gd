class_name VisionPoseProvider
extends PoseProvider
## Provide the pose of the builder from the webcam, through the Vision autoload
## (RTMO and RTMPose-t in C#, see scenes/vision/). The camera frames stay in
## memory; only the key points come here.

var _vision: Node


func _init(vision: Node) -> void:
    _vision = vision


func start() -> bool:
    return _vision != null and _vision.start_camera()


func stop() -> void:
    if _vision != null:
        _vision.stop_camera()


func latest_frame() -> Dictionary:
    if _vision == null:
        return {}
    var service: Node = _vision.service
    var timestamp: float = service.GetPoseTimestamp()
    if timestamp < 0.0:
        return {}
    var points: PackedVector2Array = service.GetKeypoints()
    var scores: PackedFloat32Array = service.GetKeypointScores()
    if points.size() != KEYPOINT_COUNT or scores.size() != KEYPOINT_COUNT:
        return {}
    var size: Vector2 = service.GetPictureSize()
    return {
        "timestamp": timestamp,
        "width": int(size.x),
        "height": int(size.y),
        "keypoints": Array(points),
        "scores": Array(scores),
        "mirrored": mirrored,
    }


func now() -> float:
    if _vision == null:
        return super.now()
    return float(_vision.service.GetNow())


func status() -> String:
    if _vision == null:
        return "failed"
    match _vision.status():
        "Running":
            return "running"
        "SearchingCamera", "LoadingModels":
            return "starting"
        "Disabled":
            return "off"
        _:
            return "failed"


func status_message() -> String:
    return _vision.status_message() if _vision != null else ""
