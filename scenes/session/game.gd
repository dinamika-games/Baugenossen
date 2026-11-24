extends Node
## Hold the game for all the screens: the session (the character and the
## sites), the mission being built, the pose provider, and the change of
## screens.
##
## The camera starts with the game (it takes a few seconds), except headless
## (the tests). Start with `-- --saves=user://other_saves` to keep the saves
## elsewhere (e.g., in the tests), `-- --no-camera` to forbid the camera, and
## `-- --synthetic-pose` to try the plumbing with a made-up body that stands
## still.

const SCREENS := {
    "main_menu": "res://scenes/main_menu/main_menu.tscn",
    "character_creation": "res://scenes/character_creation/character_creation.tscn",
    "city_map": "res://scenes/city_map/city_map.tscn",
    "build_site": "res://scenes/build_site/build_site.tscn",
    "character_sheet": "res://scenes/character_sheet/character_sheet.tscn",
    "mission_results": "res://scenes/mission_results/mission_results.tscn",
    "calibration": "res://scenes/calibration/calibration.tscn",
    "credits": "res://scenes/main_menu/credits.tscn",
}

var content: ContentDb
var session: GameSession
var mission_id := ""
## The result of the last submission, for the results screen.
var last_summary: Dictionary = {}
## Where the calibration returns to.
var return_screen := "main_menu"
var pose_provider: PoseProvider = null


func _ready() -> void:
    InputActions.ensure_registered()
    content = ContentDb.get_default()
    var saves := "user://saves"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--saves="):
            saves = arg.trim_prefix("--saves=")
    session = GameSession.new(content, SaveRepository.new(saves))
    if "--synthetic-pose" in OS.get_cmdline_user_args():
        pose_provider = SyntheticPoseProvider.new()
    else:
        pose_provider = VisionPoseProvider.new(get_node_or_null("/root/Vision"))
    ensure_pose.call_deferred()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and session != null:
        if session.character != null and session.dirty:
            session.save()


func go(screen: String) -> void:
    get_tree().change_scene_to_file.call_deferred(SCREENS[screen])


## Start the camera, unless it is forbidden or nobody can see the game.
func ensure_pose() -> void:
    var settings: Node = get_node("/root/Settings")
    pose_provider.mirrored = bool(settings.get_value("camera_mirror"))
    if DisplayServer.get_name() == "headless" and pose_provider is VisionPoseProvider:
        return
    if pose_provider.status() == "off":
        pose_provider.start()


## Whether the body can move the hook: the pose comes and it is calibrated.
func body_ready() -> bool:
    var settings: Node = get_node("/root/Settings")
    return pose_provider.status() == "running" and settings.get_value("calibration").has("h")


func quit() -> void:
    if session.character != null and session.dirty:
        session.save()
    var vision := get_node_or_null("/root/Vision")
    if vision != null:
        vision.service.Shutdown()
    get_tree().quit()
