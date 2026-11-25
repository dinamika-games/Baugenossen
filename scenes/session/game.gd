extends Node
## Hold the game for all the screens: the session (the progress and the
## sites), the mission being built, the pose provider, and the change of
## screens.
##
## The camera starts with the game (it takes a few seconds), except headless
## (the tests). Start with `-- --saves=user://other_saves` to keep the saves
## elsewhere (e.g., in the tests), `-- --no-camera` to forbid the camera, and
## `-- --synthetic-pose` to try the plumbing with a made-up body that stands
## still.

## The second press of Esc within this many seconds quits the game.
const QUIT_WINDOW := 2.0

const SCREENS := {
    "main_menu": "res://scenes/main_menu/main_menu.tscn",
    "city_map": "res://scenes/city_map/city_map.tscn",
    "build_site": "res://scenes/build_site/build_site.tscn",
    "credits": "res://scenes/main_menu/credits.tscn",
}

var content: ContentDb
var session: GameSession
var mission_id := ""
var pose_provider: PoseProvider = null
## The calibration of the body controls, kept from level to level (see the
## build site); {} until the crane learned the posture.
var pose_calibration: Dictionary = {}

var _quit_left := 0.0
var _quit_hint: Label


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
    var layer := CanvasLayer.new()
    layer.layer = 99
    add_child(layer)
    _quit_hint = Label.new()
    _quit_hint.text = tr("Press Esc again to quit.")
    _quit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _quit_hint.add_theme_font_size_override("font_size", 28)
    _quit_hint.add_theme_color_override("font_color", Color.WHITE)
    _quit_hint.add_theme_color_override("font_outline_color", Color.BLACK)
    _quit_hint.add_theme_constant_override("outline_size", 8)
    _quit_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _quit_hint.offset_top = -220
    _quit_hint.visible = false
    layer.add_child(_quit_hint)


func _process(delta: float) -> void:
    if _quit_left > 0.0:
        _quit_left -= delta
        _quit_hint.visible = _quit_left > 0.0


## Quit on the second press of Esc, so that a stray key does not end the game:
## the first press shows the hint (and does what Esc does on the screen).
func _input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    if event.physical_keycode != KEY_ESCAPE:
        return
    if _quit_left > 0.0:
        get_viewport().set_input_as_handled()
        quit()
        return
    _quit_hint.text = tr("Press Esc again to quit.")
    _quit_left = QUIT_WINDOW
    _quit_hint.visible = true


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and session != null:
        if session.progress != null and session.dirty:
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


## Whether the body can move the hook: the pose comes.
func body_ready() -> bool:
    return pose_provider.status() == "running"


func quit() -> void:
    if session.progress != null and session.dirty:
        session.save()
    var vision := get_node_or_null("/root/Vision")
    if vision != null:
        vision.service.Shutdown()
    get_tree().quit()
