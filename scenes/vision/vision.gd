extends Node

## Keep the camera and the vision for the whole game, across all the scenes, so
## that the camera starts only once (which takes a few seconds).
##
## The camera never starts on its own: the game calls [method start_camera] only
## after the player chose the body controls and agreed to use the camera (see
## scenes/settings/). Start with `-- --no-camera` to forbid the camera, e.g.,
## in the tests.
##
## The pose is read through [VisionPoseProvider] (scenes/input/).

@onready var service: Node = $Service


func _enter_tree() -> void:
    if "--no-camera" in OS.get_cmdline_user_args():
        $Service.CameraAllowed = false


## Start the camera and the pose; return whether the search for the camera began.
func start_camera() -> bool:
    return bool(service.StartCamera())


func stop_camera() -> void:
    service.StopCamera()


func status() -> String:
    return str(service.GetStatus())


func status_message() -> String:
    return str(service.GetStatusMessage())
