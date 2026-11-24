extends Node
## Hold the game for all the screens: the session (the character and the
## sites), the mission being built, the pose provider, and the change of
## screens.
##
## Start with `-- --saves=user://other_saves` to keep the saves elsewhere (e.g.,
## in the tests), `-- --no-camera` to forbid the camera, and
## `-- --synthetic-pose` to try the body controls with a made-up body.

const SCREENS := {
    "main_menu": "res://scenes/main_menu/main_menu.tscn",
    "character_creation": "res://scenes/character_creation/character_creation.tscn",
    "city_map": "res://scenes/city_map/city_map.tscn",
    "build_site": "res://scenes/build_site/build_site.tscn",
    "character_sheet": "res://scenes/character_sheet/character_sheet.tscn",
    "mission_results": "res://scenes/mission_results/mission_results.tscn",
    "settings": "res://scenes/settings/settings_screen.tscn",
    "calibration": "res://scenes/calibration/calibration.tscn",
    "credits": "res://scenes/main_menu/credits.tscn",
}

var content: ContentDb
var session: GameSession
var mission_id := ""
## The result of the last submission, for the results screen.
var last_summary: Dictionary = {}
## Where the settings screen returns to.
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


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and session != null:
        if session.character != null and session.dirty:
            session.save()


func go(screen: String) -> void:
    get_tree().change_scene_to_file.call_deferred(SCREENS[screen])


## Start the camera if the player chose the body controls and agreed.
func ensure_pose() -> void:
    var settings: Node = get_node("/root/Settings")
    pose_provider.mirrored = bool(settings.get_value("camera_mirror"))
    if settings.body_controls() and pose_provider.status() == "off":
        pose_provider.start()


func quit() -> void:
    if session.character != null and session.dirty:
        session.save()
    var vision := get_node_or_null("/root/Vision")
    if vision != null:
        vision.service.Shutdown()
    get_tree().quit()
